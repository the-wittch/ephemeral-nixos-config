# nix build path:.#checks.x86_64-linux.disk -L
# The real layout on a real disk: LUKS, the btrfs subvolumes and the rollback, which the
# other tests turn off. Also breaks the rollback on purpose and fixes it the way
# docs/troubleshooting.md says.
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

          with subtest("the first boot reset /"):
              machine.succeed("systemctl is-active --quiet root-reset-check.service")
              assert machine.succeed("findmnt -n -o FSROOT /").strip() == "/root"

          with subtest("a reboot wipes /, and keeps /persist and /var/log"):
              machine.succeed("touch /root-was-here /persist/persist-was-here /var/log/log-was-here")
              reboot()
              machine.fail("test -e /root-was-here")
              machine.succeed("test -e /persist/persist-was-here")
              machine.succeed("test -e /var/log/log-was-here")
              machine.succeed("systemctl is-active --quiet root-reset-check.service")

          with subtest("without root-blank it still boots, keeps /, and root-reset-check fails"):
              top_level("btrfs subvolume delete /mnt/btrfs/root-blank")
              machine.succeed("touch /root-was-here")
              reboot()
              machine.succeed("test -e /root-was-here")
              machine.succeed("systemctl is-failed --quiet root-reset-check.service")

          with subtest("the steps in troubleshooting.md bring the reset back"):
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
