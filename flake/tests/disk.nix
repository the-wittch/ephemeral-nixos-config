# nix build path:.#checks.x86_64-linux.disk -L
# The real layout on a real disk: LUKS, the btrfs subvolumes and the rollback, which the
# other tests turn off. Also breaks the rollback on purpose and fixes it the way
# ephemeral-doctor --fix-root-reset does.
{ config, inputs, ... }:
let
  nixos = config.ephemeral.aspects.nixos;
in
{
  perSystem =
    { lib, pkgs, ... }:
    let
      installed = inputs.nixpkgs.lib.nixosSystem {
        modules = [
          nixos.base
          {
            nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system;
            ephemeral.settings = {
              hostname = "disktest";
              username = "alice";
              diskDevice = "/dev/vda";
              swapSize = "256M";
            };
            boot.consoleLogLevel = lib.mkForce 7;
            # disko installs from a VM with no firmware variables to write, and boots the disk
            # with fresh ones. Limine still goes to its own folder, as on a real machine, so the
            # boot shows the fallback copy starts it.
            boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
            boot.loader.limine.efiInstallAsRemovable = false;
          }
        ];
      };
      passphrase = "secretsecret";
      layout = import ../../modules/_disko-layout.nix {
        device = "/dev/vda";
        swapSize = "256M";
      };
    in
    {
      checks.disk = inputs.disko.lib.testLib.makeDiskoTest {
        inherit pkgs;
        name = "ephemeral";
        # makeDiskoTest writes the passphrase there for formatting; booting asks for it
        disko-config.disko.devices = lib.recursiveUpdate layout {
          disk.main.content.partitions.luks.content.passwordFile = "/tmp/secret.key";
        };
        inherit (installed) extendModules;
        bootCommands = ''
          machine.wait_for_console_text("assphrase")
          machine.send_console("${passphrase}\n")
        '';
        # makeDiskoTest's own script already imports shlex
        extraTestScript = ''
          def reboot():
              machine.shutdown()
              machine.start()
              machine.wait_for_console_text("assphrase")
              machine.send_console("${passphrase}\n")
              machine.wait_for_unit("multi-user.target")

          def top_level(cmd):
              machine.succeed(
                  "mkdir -p /mnt/btrfs && mount -o subvolid=5 /dev/mapper/cryptroot /mnt/btrfs"
                  f" && {cmd}; status=$?; umount /mnt/btrfs; exit $status"
              )

          machine.wait_for_unit("multi-user.target")

          with subtest("firmware with no boot entries starts Limine from the fallback path"):
              machine.succeed("test -s /boot/limine/limine.conf")
              machine.succeed("cmp /boot/EFI/BOOT/BOOTX64.EFI /boot/EFI/limine/BOOTX64.EFI")
              machine.fail("test -e /boot/loader/loader.conf")

          with subtest("the first boot reset /"):
              machine.succeed("systemctl is-active --quiet root-reset-check.service")
              assert machine.succeed("findmnt -n -o FSROOT /").strip() == "/root"

          with subtest("LUKS2 with argon2id, discards passed through, and the btrfs layout as designed"):
              dump = "cryptsetup luksDump /dev/disk/by-partlabel/disk-main-luks"
              machine.succeed(f"{dump} | grep -Eq '^Version:[[:space:]]+2$'")
              machine.succeed(f"{dump} | grep -Eq 'PBKDF:[[:space:]]+argon2id'")
              machine.succeed("cryptsetup status cryptroot | grep -q discards")
              subvols = set(machine.succeed(
                  "mkdir -p /mnt/btrfs && mount -o subvolid=5 /dev/mapper/cryptroot /mnt/btrfs"
                  " && btrfs subvolume list -o /mnt/btrfs | awk '{ print $NF }'; umount /mnt/btrfs"
              ).split())
              want = {"root", "root-blank", "nix", "persist", "log", "swap"}
              assert want <= subvols, f"subvolumes missing: {want - subvols}"
              top_level("btrfs property get -ts /mnt/btrfs/root-blank ro | grep -qx ro=true")
              for mnt in ["/", "/nix", "/persist", "/var/log"]:
                  opts = machine.succeed(f"findmnt -no OPTIONS {mnt}").strip().split(",")
                  assert "noatime" in opts and any(o.startswith("compress=zstd") for o in opts), f"{mnt}: {opts}"
              boot = machine.succeed("findmnt -no OPTIONS /boot").strip()
              assert "fmask=0077" in boot and "dmask=0077" in boot, f"/boot is readable by users: {boot}"
              machine.succeed("swapon --show=NAME --noheadings | grep -qx /.swapvol/swapfile")

          with subtest("subvolumes made inside /, nested two deep, are removed too, as containers make them"):
              machine.succeed("btrfs subvolume create /nested && btrfs subvolume create /nested/inner")
              machine.succeed("touch /nested/inner/was-here")
              reboot()
              machine.fail("test -e /nested")
              machine.succeed("systemctl is-active --quiet root-reset-check.service")

          with subtest("subvolumes nested past any depth, or under a name with a newline, don't stop the reset"):
              # /var/tmp is on / and anyone can write it; btrfs lets users make subvolumes there
              deep = "d=/var/tmp/deep; mkdir -p $d; for i in $(seq 70); do btrfs subvolume create $d/s >/dev/null; d=$d/s; done; touch $d/was-here"
              odd = 'n=$(printf "odd\\nroot"); mkdir -p "/var/tmp/$n" && btrfs subvolume create "/var/tmp/$n/persist" && touch "/var/tmp/$n/persist/was-here"'
              for name, cmd in [("deep", deep), ("odd", odd)]:
                  status, _ = machine.execute(f"runuser -u alice -- bash -c {shlex.quote(cmd)}")
                  print(f"MEASURED {name} subvolumes as an unprivileged user: {'allowed' if status == 0 else 'refused, made as root instead'}")
                  if status != 0:
                      machine.succeed(f"bash -c {shlex.quote(cmd)}")
              machine.succeed("touch /persist/kept-past-the-attack")
              reboot()
              machine.succeed("systemctl is-active --quiet root-reset-check.service")
              machine.fail("test -e /var/tmp/deep")
              assert machine.succeed("find /var/tmp -maxdepth 1 -name 'odd*'").strip() == "", machine.succeed("ls -lA /var/tmp")
              machine.succeed("test -e /persist/kept-past-the-attack")

          with subtest("a reboot wipes /, and keeps /persist and /var/log"):
              machine.succeed("touch /root-was-here /persist/persist-was-here /var/log/log-was-here")
              reboot()
              machine.fail("test -e /root-was-here")
              machine.succeed("test -e /persist/persist-was-here")
              machine.succeed("test -e /var/log/log-was-here")
              machine.succeed("systemctl is-active --quiet root-reset-check.service")

          with subtest("without root-blank it still boots, keeps /, and root-reset-check fails, with no marker either"):
              top_level("btrfs subvolume delete /mnt/btrfs/root-blank")
              machine.succeed("touch /root-was-here && rm /.root-reset")
              reboot()
              machine.succeed("test -e /root-was-here")
              machine.succeed("systemctl is-failed --quiet root-reset-check.service")

          with subtest("the steps ephemeral-doctor --fix-root-reset runs bring the reset back"):
              top_level(
                  "btrfs subvolume create /mnt/btrfs/blank"
                  " && btrfs subvolume snapshot -r /mnt/btrfs/blank /mnt/btrfs/root-blank"
                  " && btrfs subvolume delete /mnt/btrfs/blank"
              )
              reboot()
              machine.fail("test -e /root-was-here")
              machine.succeed("systemctl is-active --quiet root-reset-check.service")
        '';
      };
    };
}
