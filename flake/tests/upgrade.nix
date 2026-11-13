# nix build path:.#checks.x86_64-linux.upgrade -L
{ config, lib, ... }:
let
  pin = lib.importJSON ../../tests/upgrade/previous.json;
  previous = builtins.getFlake "git+https://github.com/the-wittch/ephemeral-nixos-config?rev=${pin.rev}";

  settings = {
    hostname = "upgrade";
    username = "alice";
    diskDevice = "/dev/vda";
    swapSize = "1G";
    desktop = "gnome";
  };

  machine =
    nixos:
    { lib, ... }:
    {
      imports = [
        nixos.vm
        nixos.pc
        nixos.full
        nixos.opensnitch
        nixos.gnome
        # releases before this change switch the dotfiles on with their own module
        (nixos.dotfiles or { })
      ];
      ephemeral.settings = settings;
      boot.consoleLogLevel = lib.mkForce 7;
      # test machines leave switch-to-configuration out unless asked
      system.switch.enable = true;
    };
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      # built only for its system; never run
      next =
        (pkgs.testers.runNixOSTest {
          name = "upgrade-next";
          node.pkgsReadOnly = false;
          nodes.machine = machine config.ephemeral.aspects.nixos;
          testScript = "";
        }).nodes.machine.system.build.toplevel;
    in
    {
      checks.upgrade = previous.inputs.nixpkgs.legacyPackages.${system}.testers.runNixOSTest {
        name = "upgrade";
        node.pkgsReadOnly = false;

        nodes.machine = {
          imports = [ (machine previous.modules.nixos) ];
          virtualisation.additionalPaths = [ next ];
        };

        testScript = ''
          from datetime import timedelta

          def is_clean(stage):
              machine.wait_until_succeeds("systemctl is-system-running --wait | grep -qxE 'running|degraded'", timeout=timedelta(seconds=180))
              failed = machine.succeed("systemctl --failed --no-legend --plain").strip()
              assert failed == "", f"{stage}: failed units\n{failed}"
              for unit in ["display-manager.service", "home-manager-alice.service"]:
                  machine.succeed(f"systemctl is-active --quiet {unit}")
              print(f"ok: {stage} is clean")

          machine.wait_for_unit("multi-user.target")
          is_clean("${pin.tag}")
          machine.succeed("echo kept > /persist/upgrade-marker && runuser -u alice -- sh -c 'echo kept > ~/upgrade-marker'")

          with subtest("switch from ${pin.tag} to this code"):
              # "test" skips the bootloader; the VM has no boot disk to install one on
              machine.succeed("${next}/bin/switch-to-configuration test >&2")
              assert machine.succeed("readlink -f /run/current-system").strip() == "${next}"
              is_clean("after the switch")
              machine.succeed("grep -qx kept /persist/upgrade-marker")
              machine.succeed("grep -qx kept /home/alice/upgrade-marker")
        '';
      };
    };
}
