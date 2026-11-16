# nix build path:.#checks.x86_64-linux.secure-boot -L
# A machine on the previous release turns secureBoot on after updating, as docs/security.md
# describes, on firmware that starts in Setup Mode and keeps its variables across reboots.
{ config, lib, ... }:
let
  pin = lib.importJSON ../../tests/upgrade/previous.json;
  previous = builtins.getFlake "git+https://github.com/the-wittch/ephemeral-nixos-config?rev=${pin.rev}";

  machine = import ./_efi-machine.nix { hostname = "secureboot"; };

  limine =
    { lib, pkgs, ... }:
    {
      boot.loader.limine.enable = lib.mkOverride 10 true;
      environment.systemPackages = [ pkgs.sbsigntool ];
    };
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      nixos = config.ephemeral.aspects.nixos;
      build =
        name: modules:
        (pkgs.testers.runNixOSTest {
          inherit name;
          node.pkgsReadOnly = false;
          nodes.machine.imports = [
            (machine nixos)
            limine
          ]
          ++ modules;
          testScript = "";
        }).nodes.machine.system.build.toplevel;
      next = build "secure-boot-next" [ ];
      signed = build "secure-boot-signed" [ nixos.secure-boot ];
    in
    {
      checks.secure-boot = previous.inputs.nixpkgs.legacyPackages.${system}.testers.runNixOSTest {
        name = "secure-boot";
        node.pkgsReadOnly = false;

        nodes.machine = {
          imports = [
            (machine previous.modules.nixos)
            limine
          ];
          virtualisation.additionalPaths = [
            next
            signed
          ];
        };

        testScript = ''
          import datetime
          import re

          db = "/var/lib/sbctl/keys/db"
          limine = "/boot/EFI/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI"
          # the kernel or systemd writing to the serial console: Limine has started a kernel
          kernel_started = r"Linux version|systemd\[1\]"

          def efivar(name):
              path = f"/sys/firmware/efi/efivars/{name}-8be4df61-93ca-11d2-aa0d-00e098032b8c"
              return int(machine.succeed(f"od -An -tu1 -j4 -N1 {path}").strip())

          def booted():
              return machine.succeed("readlink -f /run/booted-system").strip()

          def install(system):
              machine.succeed(
                  f"nix-env -p /nix/var/nix/profiles/system --set {system}"
                  f" && {system}/bin/switch-to-configuration boot >&2"
              )

          def reboot():
              machine.shutdown()
              machine.start()
              machine.wait_for_unit("multi-user.target")

          def signed_with_this_key():
              machine.succeed(f"for efi in {limine}; do sbverify --cert {db}/db.pem $efi; done")

          machine.start()
          machine.wait_for_unit("multi-user.target")

          with subtest("${pin.tag} boots from Limine, with the firmware in Setup Mode"):
              assert efivar("SecureBoot") == 0, "Secure Boot is already on"
              assert efivar("SetupMode") == 1, "the firmware isn't in Setup Mode"

          with subtest("after the update, /var/lib/sbctl is kept on /persist"):
              install("${next}")
              reboot()
              assert booted() == "${next}", f"booted {booted()}"
              machine.succeed("mountpoint -q /var/lib/sbctl")

          with subtest("turning secureBoot on makes keys on /persist, signs Limine and enrolls the keys"):
              install("${signed}")
              machine.succeed(f"test -s /persist{db}/db.key")
              signed_with_this_key()
              assert efivar("SetupMode") == 0, "the keys weren't enrolled"
              key = machine.succeed(f"sha256sum {db}/db.key")

          with subtest("the machine boots with Secure Boot on"):
              reboot()
              assert booted() == "${signed}", f"booted {booted()}"
              assert efivar("SecureBoot") == 1, "Secure Boot is off"

          with subtest("a rebuild signs again with the same key"):
              machine.succeed("${signed}/bin/switch-to-configuration boot >&2")
              signed_with_this_key()
              assert machine.succeed(f"sha256sum {db}/db.key") == key, "the key changed"

          with subtest("with every firmware entry gone, the signed fallback copy starts the machine"):
              out = machine.succeed("efibootmgr")
              for num in re.findall(r"^Boot([0-9A-F]{4})[* ]", out, re.M):
                  machine.succeed(f"efibootmgr -q -B -b {num}")
              machine.shutdown()
              machine.start()
              # seen on a boot that works, so its absence below means something
              machine.wait_for_console_text(kernel_started, timeout=datetime.timedelta(minutes=2))
              machine.wait_for_unit("multi-user.target")
              assert booted() == "${signed}", f"booted {booted()}"
              assert efivar("SecureBoot") == 1, "Secure Boot is off"

          with subtest("Limine refuses to start a kernel that was changed"):
              machine.succeed('for f in /boot/limine/kernels/*; do printf x >> "$f"; done')
              machine.shutdown()
              machine.start()
              try:
                  machine.wait_for_console_text(kernel_started, timeout=datetime.timedelta(minutes=2))
                  started = True
              except Exception:
                  started = False
              assert not started, "a changed kernel was started"
              machine.crash()
        '';
      };
    };
}
