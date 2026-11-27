# A scheduled backup over SSH to a second machine standing in for a storage box: backup-setup makes
# root's key and keeps the passphrase, borgmatic runs as the timer would start it, and the archive
# holds what the built-in patterns say and nothing they leave out.
{ config, ... }:
let
  nixos = config.ephemeral.aspects.nixos;
  backup = import ../../modules/_backup.nix;
in
{
  perSystem =
    { pkgs, config, ... }:
    {
      checks.backups = pkgs.testers.runNixOSTest {
        name = "backups";
        # the service waits a minute before it starts
        globalTimeout = 900;
        node.pkgsReadOnly = false;

        nodes.machine =
          { lib, ... }:
          {
            imports = [
              nixos.vm
              nixos.pc
            ];
            ephemeral.settings = {
              hostname = "machine";
              username = "alice";
              diskDevice = "/dev/vda";
              swapSize = "1G";
            };
            ephemeral.backupRepositories = [
              {
                label = "box";
                path = "ssh://borg@storage/./repo";
              }
            ];
            environment.systemPackages = [ config.legacyPackages.ephemeralTools.backup-setup ];
            boot.consoleLogLevel = lib.mkForce 7;
          };

        nodes.storage = {
          services.openssh.enable = true;
          users.users.borg = {
            isNormalUser = true;
            home = "/home/borg";
          };
        };

        testScript = ''
          start_all()
          machine.wait_for_unit("multi-user.target")
          storage.wait_for_unit("sshd.service")

          with subtest("backup-setup makes root's key and keeps the typed passphrase root-only"):
              # with a repository already there, it only asks for the passphrase
              machine.succeed(
                  "mkdir -p /tmp/flake && touch /tmp/flake/flake.nix",
                  "echo '[{\"label\": \"box\", \"path\": \"ssh://borg@storage/./repo\"}]' > /tmp/flake/backup.json",
              )
              # in a terminal, as it asks there; each answer waits for its question, since sudo takes
              # in what was typed before it while it runs
              machine.succeed(
                  "{ sleep 5; echo 'correct horse'; sleep 2; echo 'correct horse'; }"
                  " | script -qec 'FLAKE_DIR=/tmp/flake backup-setup' /dev/null >&2"
              )
              assert machine.succeed("stat -c '%a %U' ${backup.dir} ${backup.dir}/passphrase ${backup.dir}/ssh_key").split() == [
                  "700", "root", "600", "root", "600", "root"
              ]
              pub = machine.succeed("cat ${backup.dir}/ssh_key.pub").strip()
              # restricted to borg and its repository, as a storage box does it
              storage.succeed(
                  "install -d -m 700 -o borg -g users /home/borg/.ssh",
                  f"echo 'command=\"${pkgs.borgbackup}/bin/borg serve --restrict-to-path /home/borg/repo\",restrict {pub}'"
                  " > /home/borg/.ssh/authorized_keys",
                  "chown borg /home/borg/.ssh/authorized_keys && chmod 600 /home/borg/.ssh/authorized_keys",
              )

          with subtest("the timer runs every 6 hours"):
              assert "00/6:00:00" in machine.succeed("systemctl show -p TimersCalendar --value borgmatic.timer")

          with subtest("a backup over SSH has what the patterns keep, and none of what they leave out"):
              machine.succeed(
                  "install -d -o alice /home/alice/Documents /home/alice/Downloads /home/alice/.cache/x"
                  " /home/alice/code/node_modules/dep /home/alice/later",
                  "echo notes > /home/alice/Documents/notes.txt",
                  "echo file > /home/alice/Downloads/file.iso",
                  "echo cache > /home/alice/.cache/x/c",
                  "echo dep > /home/alice/code/node_modules/dep/index.js",
                  "echo main > /home/alice/code/main.rs",
                  "touch /home/alice/later/.nobackup && echo later > /home/alice/later/draft",
                  "mkdir -p /home/alice/.local/share/Steam/userdata/1/remote"
                  " /home/alice/.local/share/Steam/steamapps/common/Game"
                  " /home/alice/.local/share/Steam/steamapps/compatdata/10/pfx/drive_c/users/steamuser/Saved"
                  " /home/alice/.local/share/Steam/steamapps/compatdata/10/pfx/drive_c/windows"
                  " /home/alice/Games/Heroic/Prefixes/default/Other/drive_c/users/steamuser/Saved"
                  " /home/alice/Games/Heroic/Other",
                  "echo s > /home/alice/.local/share/Steam/userdata/1/remote/save",
                  "echo s > /home/alice/.local/share/Steam/steamapps/compatdata/10/pfx/drive_c/users/steamuser/Saved/slot1",
                  "echo s > /home/alice/Games/Heroic/Prefixes/default/Other/drive_c/users/steamuser/Saved/slot1",
                  "echo g > /home/alice/.local/share/Steam/steamapps/common/Game/data.pak",
                  "echo g > /home/alice/.local/share/Steam/steamapps/compatdata/10/pfx/drive_c/windows/win.ini",
                  "echo g > /home/alice/.local/share/Steam/steam.sh",
                  "echo g > /home/alice/Games/Heroic/Other/game.exe",
                  "chown -R alice /home/alice/.local /home/alice/Games",
                  "mkdir -p /persist/etc/nixos && echo '{}' > /persist/etc/nixos/settings.json",
              )
              machine.succeed("borgmatic repo-create --encryption repokey-blake2 >&2")
              machine.succeed("systemctl start borgmatic.service")
              assert machine.succeed("systemctl show -p Result --value borgmatic.service").strip() == "success"
              listed = machine.succeed("borgmatic list --archive latest --short").split()
              for kept in [
                  "home/alice/Documents/notes.txt",
                  "home/alice/Downloads/file.iso",
                  "home/alice/code/main.rs",
                  "persist/etc/nixos/settings.json",
                  "home/alice/.local/share/Steam/userdata/1/remote/save",
                  "home/alice/.local/share/Steam/steamapps/compatdata/10/pfx/drive_c/users/steamuser/Saved/slot1",
                  "home/alice/Games/Heroic/Prefixes/default/Other/drive_c/users/steamuser/Saved/slot1",
              ]:
                  assert kept in listed, f"{kept} isn't in the backup"
              for left in [
                  "home/alice/.cache/x/c",
                  "home/alice/code/node_modules/dep/index.js",
                  "home/alice/later/draft",
                  "persist/etc/borg/passphrase",
                  "persist/etc/borg/ssh_key",
                  "home/alice/.local/share/Steam/steamapps/common/Game/data.pak",
                  "home/alice/.local/share/Steam/steamapps/compatdata/10/pfx/drive_c/windows/win.ini",
                  "home/alice/.local/share/Steam/steam.sh",
                  "home/alice/Games/Heroic/Other/game.exe",
              ]:
                  assert left not in listed, f"{left} is in the backup"
              storage.succeed("test -d /home/borg/repo/data")

          with subtest("the repository's host key is kept, and its cache is on /persist"):
              machine.succeed("grep -q storage ${backup.dir}/known_hosts")
              machine.succeed("test -n \"$(ls -A /persist/var/lib/borg)\"")
        '';
      };
    };
}
