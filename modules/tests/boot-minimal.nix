# nix build path:.#checks.x86_64-linux.boot-minimal -L
{ config, ... }:
let
  nixos = config.flake.modules.nixos;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.boot-minimal = pkgs.testers.runNixOSTest {
        name = "boot-minimal";

        node.pkgsReadOnly = false;

        nodes.machine =
          { lib, ... }:
          {
            imports = [
              nixos.vm
              nixos.pc
              nixos.minimal
              nixos.minimal-gnome
            ];

            ephemeral.settings = {
              hostname = "boottest";
              username = "alice";
              diskDevice = "/dev/vda";
              swapSize = "1G";
              desktop = "gnome";
              profile = "minimal";
            };

            boot.consoleLogLevel = lib.mkForce 7;
          };

        testScript = ''
          from datetime import timedelta

          def boot_is_clean(boot):
              machine.wait_for_unit("multi-user.target")
              machine.wait_until_succeeds("systemctl is-system-running --wait | grep -qxE 'running|degraded'", timeout=timedelta(seconds=180))
              failed = machine.succeed("systemctl --failed --no-legend --plain").strip()
              assert failed == "", f"boot {boot}: failed units\n{failed}"
              machine.succeed("systemctl is-active --quiet display-manager.service")
              print(f"ok: boot {boot} is clean")

          boot_is_clean(1)

          with subtest("no home manager on the minimal profile, and zsh completion comes from the system"):
              machine.fail("systemctl cat home-manager-alice.service")
              machine.succeed("grep -q compinit /etc/zshrc")

          with subtest("root is wiped, /persist is kept"):
              machine.succeed("touch /root-was-here /persist/persist-was-here")
              machine.shutdown()
              machine.start()
              boot_is_clean(2)
              machine.fail("test -e /root-was-here")
              machine.succeed("test -e /persist/persist-was-here")
        '';
      };
    };
}
