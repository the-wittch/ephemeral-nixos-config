{ config, ... }:
let
  nixos = config.ephemeral.aspects.nixos;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.boot-minimal = pkgs.testers.runNixOSTest {
        name = "boot-minimal";
        # it usually takes under 2 minutes
        globalTimeout = 600;
        enableOCR = true;

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
            # with a serial console Plymouth only ever draws text, so the theme would never load;
            # its own log goes to the test output rather than over the splash
            boot.kernelParams = [
              "plymouth.ignore-serial-consoles"
              "plymouth.debug=stream:/dev/ttyS0"
            ];
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

          with subtest("ephemeral-setup is there to switch to the full profile"):
              machine.succeed("ephemeral-setup --help")

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

          with subtest("the boot splash runs its script and draws the passphrase prompt"):
              # Plymouth only finds a broken script when it runs it, and falls back to text,
              # so the wordmark on screen shows the script loaded and ran
              machine.succeed("systemctl stop display-manager.service")
              machine.succeed("chvt 1")
              # it daemonizes but keeps stdout open, which the driver would wait on forever;
              # no --debug, which prints over the splash
              machine.succeed("plymouthd --mode=boot --tty=/dev/tty1 </dev/null >/dev/null 2>&1")
              machine.succeed("plymouth show-splash")
              machine.succeed("(plymouth ask-for-password --prompt=test >/dev/null 2>&1 &)")
              machine.wait_for_text(r"E\s*P\s*H\s*E\s*M\s*E\s*R\s*A\s*L", timeout=timedelta(seconds=120))
              machine.screenshot("splash")
              machine.succeed("plymouth quit")
        '';
      };
    };
}
