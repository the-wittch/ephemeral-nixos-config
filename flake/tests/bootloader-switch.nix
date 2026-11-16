# nix build path:.#checks.x86_64-linux.bootloader-switch -L
# An update from a release that boots with systemd-boot, on a real ESP with firmware variables
# that survive a reboot, the way every machine installed before Limine gets it.
{ config, lib, ... }:
let
  pin = lib.importJSON ../../tests/upgrade/previous.json;
  previous = builtins.getFlake "git+https://github.com/the-wittch/ephemeral-nixos-config?rev=${pin.rev}";

  machine =
    nixos:
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        nixos.vm
        nixos.base
      ];
      ephemeral.settings = {
        hostname = "loaderswitch";
        username = "alice";
        diskDevice = "/dev/vda";
        swapSize = "1G";
      };
      boot.consoleLogLevel = lib.mkForce 7;
      system.switch.enable = true;
      environment.systemPackages = [ pkgs.efibootmgr ];
      # vm.nix boots the kernel directly with no disk; this one needs a disk with an ESP
      virtualisation = {
        useBootLoader = true;
        useEFIBoot = true;
        diskImage = lib.mkOverride 10 "./${config.system.name}.qcow2";
      };
    };

  bootloader =
    loader:
    { lib, ... }:
    {
      boot.loader.${loader}.enable = lib.mkOverride 10 true;
    };
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      next =
        (pkgs.testers.runNixOSTest {
          name = "bootloader-switch-next";
          node.pkgsReadOnly = false;
          nodes.machine.imports = [
            (machine config.ephemeral.aspects.nixos)
            (bootloader "limine")
          ];
          testScript = "";
        }).nodes.machine.system.build.toplevel;
    in
    {
      checks.bootloader-switch = previous.inputs.nixpkgs.legacyPackages.${system}.testers.runNixOSTest {
        name = "bootloader-switch";
        node.pkgsReadOnly = false;

        nodes.machine = {
          imports = [
            (machine previous.modules.nixos)
            (bootloader "systemd-boot")
          ];
          virtualisation.additionalPaths = [ next ];
        };

        testScript = ''
          import re

          def boot_entries():
              out = machine.succeed("efibootmgr")
              # efibootmgr marks an active entry with * and an inactive one with a space
              entries = dict(re.findall(r"^Boot([0-9A-F]{4})[* ] (.+?)(?:\t|$)", out, re.M))
              order = re.search(r"^BootOrder: (\S+)", out, re.M)
              current = re.search(r"^BootCurrent: (\S+)", out, re.M)
              return (
                  entries,
                  order.group(1).split(",") if order else [],
                  current.group(1) if current else None,
              )

          def booted():
              return machine.succeed("readlink -f /run/booted-system").strip()

          machine.start()
          machine.wait_for_unit("multi-user.target")

          with subtest("${pin.tag} boots from systemd-boot"):
              machine.succeed("test -e /boot/loader/loader.conf")
              old = booted()

          with subtest("the update installs Limine and puts it first in the boot order"):
              machine.succeed(
                  "nix-env -p /nix/var/nix/profiles/system --set ${next}"
                  " && ${next}/bin/switch-to-configuration boot >&2"
              )
              entries, order, _ = boot_entries()
              assert order, "the firmware has no boot order"
              assert entries.get(order[0]) == "Limine", f"first in the boot order: {entries.get(order[0])} ({order})"
              assert "Linux Boot Manager" in entries.values(), "systemd-boot's entry, kept to fall back on, is gone"
              conf = machine.succeed("cat /boot/limine/limine.conf")
              assert f"{old}/init" in conf, "the generation from before the update isn't in Limine's menu"

          with subtest("this code boots through Limine"):
              machine.shutdown()
              machine.start()
              machine.wait_for_unit("multi-user.target")
              assert booted() == "${next}", f"booted {booted()}"
              entries, _, current = boot_entries()
              assert entries.get(current) == "Limine", f"started from {entries.get(current)}"

          with subtest("with every firmware entry gone, the fallback path starts Limine"):
              entries, _, _ = boot_entries()
              for num in entries:
                  machine.succeed(f"efibootmgr -q -B -b {num}")
              machine.succeed("cmp /boot/EFI/BOOT/BOOTX64.EFI /boot/EFI/limine/BOOTX64.EFI")
              machine.shutdown()
              machine.start()
              machine.wait_for_unit("multi-user.target")
              # systemd-boot's menu would have started ${pin.tag}, its newest entry
              assert booted() == "${next}", f"booted {booted()}"
        '';
      };
    };
}
