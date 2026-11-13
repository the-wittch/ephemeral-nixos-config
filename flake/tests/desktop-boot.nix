# nix build path:.#checks.x86_64-linux.desktop-boot-umbriel -L
# The boot test runs GNOME; these boot the other desktops far enough to show their login screen.
{ config, lib, ... }:
let
  nixos = config.ephemeral.aspects.nixos;
  test =
    pkgs: desktop:
    pkgs.testers.runNixOSTest {
      name = "desktop-boot-${desktop}";
      node.pkgsReadOnly = false;

      nodes.machine =
        { lib, ... }:
        {
          imports = [
            nixos.vm
            nixos.pc
            nixos.full
            nixos.opensnitch
            nixos.${desktop}
          ];
          ephemeral.settings = {
            hostname = "desktoptest";
            username = "alice";
            diskDevice = "/dev/vda";
            swapSize = "1G";
            inherit desktop;
          };
          boot.consoleLogLevel = lib.mkForce 7;
        };

      testScript = ''
        from datetime import timedelta

        def boot_is_clean(boot):
            machine.wait_for_unit("multi-user.target")
            machine.wait_until_succeeds("systemctl is-system-running --wait | grep -qxE 'running|degraded'", timeout=timedelta(seconds=180))
            cycles = machine.succeed("journalctl -b --no-pager -o cat | grep -i 'ordering cycle' || true").strip()
            assert cycles == "", f"boot {boot}: ordering cycle\n{cycles}"
            failed = machine.succeed("systemctl --failed --no-legend --plain").strip()
            assert failed == "", f"boot {boot}: failed units\n{failed}"
            for unit in ["display-manager.service", "home-manager-alice.service"]:
                machine.succeed(f"systemctl is-active --quiet {unit}")
            print(f"ok: boot {boot} is clean")

        boot_is_clean(1)

        with subtest("root is wiped, /persist is kept"):
            machine.succeed("touch /root-was-here /persist/persist-was-here")
            machine.shutdown()
            machine.start()
            boot_is_clean(2)
            machine.fail("test -e /root-was-here")
            machine.succeed("test -e /persist/persist-was-here")
      '';
    };
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks = lib.genAttrs' [ "plasma" "niri" "umbriel" ] (
        desktop: lib.nameValuePair "desktop-boot-${desktop}" (test pkgs desktop)
      );
    };
}
