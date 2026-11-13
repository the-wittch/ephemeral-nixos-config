# nix build path:.#checks.x86_64-linux.profile-switch -L
# A live switch from the small install to the full system and back, as ephemeral-setup
# does it. Booting each one can't show units failing on the switch, or new kept folders
# not mounting until a reboot.
{ config, ... }:
let
  nixos = config.ephemeral.aspects.nixos;

  settings = {
    hostname = "profileswitch";
    username = "alice";
    diskDevice = "/dev/vda";
    swapSize = "1G";
    desktop = "gnome";
  };

  # the same aspects host-builder picks for each profile
  machine =
    profile:
    { lib, ... }:
    {
      imports = [
        nixos.vm
        nixos.pc
      ]
      ++ (
        if profile == "full" then
          [
            nixos.full
            nixos.gnome
            nixos.opensnitch
          ]
        else
          [
            nixos.minimal
            nixos.minimal-gnome
          ]
      );
      ephemeral.settings = settings // {
        inherit profile;
      };
      boot.consoleLogLevel = lib.mkForce 7;
      system.switch.enable = true;
    };
in
{
  perSystem =
    { pkgs, ... }:
    let
      # only its system is used
      full =
        (pkgs.testers.runNixOSTest {
          name = "profile-switch-full";
          node.pkgsReadOnly = false;
          nodes.machine = machine "full";
          testScript = "";
        }).nodes.machine.system.build.toplevel;
    in
    {
      checks.profile-switch = pkgs.testers.runNixOSTest {
        name = "profile-switch";
        node.pkgsReadOnly = false;

        nodes.machine = {
          imports = [ (machine "minimal") ];
          virtualisation.additionalPaths = [ full ];
        };

        testScript = ''
          from datetime import timedelta

          def is_clean(stage):
              machine.wait_until_succeeds("systemctl is-system-running --wait | grep -qxE 'running|degraded'", timeout=timedelta(seconds=180))
              failed = machine.succeed("systemctl --failed --no-legend --plain").strip()
              assert failed == "", f"{stage}: failed units\n{failed}"
              machine.wait_until_succeeds("systemctl is-active --quiet display-manager.service", timeout=timedelta(seconds=60))
              print(f"ok: {stage} is clean")

          def kept(stage):
              machine.succeed("grep -qx kept /persist/switch-marker")
              machine.succeed("grep -qx kept /home/alice/switch-marker")
              print(f"ok: {stage}, files on /persist and in the home folder are still there")

          machine.wait_for_unit("multi-user.target")
          is_clean("the small install")
          machine.fail("systemctl cat home-manager-alice.service")
          machine.succeed("echo kept > /persist/switch-marker && runuser -u alice -- sh -c 'echo kept > ~/switch-marker'")

          with subtest("switch to the full profile, as ephemeral-setup's rebuild does"):
              # "test" skips the bootloader; the VM has no boot disk to install one on
              machine.succeed("${full}/bin/switch-to-configuration test >&2")
              assert machine.succeed("readlink -f /run/current-system").strip() == "${full}"
              is_clean("after switching to the full profile")
              machine.succeed("systemctl is-active --quiet home-manager-alice.service")
              # kept on the full profile only
              machine.succeed("findmnt /var/lib/opensnitch")
              machine.succeed("systemctl is-active --quiet opensnitchd.service")
              kept("after switching to the full profile")

          with subtest("switch back to the small install"):
              machine.succeed("/run/booted-system/bin/switch-to-configuration test >&2")
              is_clean("after switching back")
              machine.fail("systemctl is-active --quiet home-manager-alice.service")
              kept("after switching back")
        '';
      };
    };
}
