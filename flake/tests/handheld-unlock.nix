# The disk unlocked with a controller: presses typed into the splash's passphrase prompt through a
# virtual keyboard. QEMU has no gamepad, so the test makes one inside the initrd with evemu, with
# the ROG Xbox Ally X's IDs and buttons, and drives it through the initrd backdoor. The layout is
# French, where a and q, and z and w, are swapped, so a key sent by its US position would type the
# wrong character.
{ config, ... }:
let
  nixos = config.ephemeral.aspects.nixos;
  # A, LT, up, LB, down, left, RT, B
  passphrase = "azuqdlcb";
  luks = "/dev/disk/by-id/virtio-crypt";

  # what the Ally X's controller reports: 14 buttons from BTN_SOUTH, both sticks, both triggers
  # and the d-pad as a hat
  fakePad = ''
    # EVEMU 1.3
    N: Fake ROG Xbox Ally X
    I: 0003 0b05 1b4c 0110
    P: 00 00 00 00 00 00 00 00
    B: 00 1b 00 00 00 00 00 00 00
    B: 01 00 00 00 00 00 00 00 00
    B: 01 00 00 00 00 00 00 00 00
    B: 01 00 00 00 00 00 00 00 00
    B: 01 00 00 00 00 00 00 00 00
    B: 01 00 00 00 00 00 00 ff 3f
    B: 03 3f 00 03 00 00 00 00 00
    B: 04 10 00 00 00 00 00 00 00
    A: 00 0 65535 255 4095 0
    A: 01 0 65535 255 4095 0
    A: 02 0 1023 3 63 0
    A: 03 0 65535 255 4095 0
    A: 04 0 65535 255 4095 0
    A: 05 0 1023 3 63 0
    A: 10 -1 1 0 0 0
    A: 11 -1 1 0 0 0
  '';
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.handheld-unlock = pkgs.testers.runNixOSTest {
        name = "handheld-unlock";
        globalTimeout = 900;
        node.pkgsReadOnly = false;

        nodes.machine =
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
              nixos.handheld-unlock
            ];
            ephemeral.settings = {
              hostname = "handheld";
              username = "alice";
              diskDevice = "/dev/vda";
              swapSize = "1G";
              keyboardLayout = "fr";
            };
            boot.consoleLogLevel = lib.mkForce 7;
            boot.loader.limine.enable = lib.mkOverride 10 true;
            environment.systemPackages = [ pkgs.cryptsetup ];
            virtualisation = {
              useBootLoader = true;
              useEFIBoot = true;
              diskImage = lib.mkOverride 10 "./${config.system.name}.qcow2";
              mountHostNixStore = true;
              emptyDiskImages = [
                {
                  size = 1024;
                  driveConfig.deviceExtraOpts.serial = "crypt";
                }
              ];
            };

            specialisation.on-luks.configuration = {
              boot.initrd.luks.devices = lib.mkVMOverride { cryptroot.device = luks; };
              virtualisation.rootDevice = "/dev/mapper/cryptroot";
              testing.initrdBackdoor = true;
              boot.initrd.systemd = {
                initrdBin = [
                  pkgs.evemu
                  pkgs.gnugrep
                ];
                contents."/etc/fake-pad".text = fakePad;
              };
            };
          };

        testScript =
          { nodes, ... }:
          let
            onLuks = nodes.machine.specialisation.on-luks.configuration.system.build.toplevel;
          in
          ''
            import time

            def boot():
                machine.shutdown()
                machine.start()

            # the initrd's backdoor answers once the boot reaches it, before the disk is open
            def wait_for_prompt():
                machine.wait_until_succeeds("compgen -G '/run/systemd/ask-password/ask.*'", timeout=180)

            def key(pad, code):
                machine.succeed(
                    f"evemu-event {pad} --type EV_KEY --code {code} --value 1 --sync"
                    f" && evemu-event {pad} --type EV_KEY --code {code} --value 0 --sync"
                )

            def axis(pad, code, value):
                machine.succeed(
                    f"evemu-event {pad} --type EV_ABS --code {code} --value {value} --sync"
                    f" && evemu-event {pad} --type EV_ABS --code {code} --value 0 --sync"
                )

            # the Ally X's codes, read off the device
            def press(pad, name):
                buttons = {"A": 304, "B": 305, "X": 306, "Y": 307, "LB": 308, "RB": 309,
                           "View": 310, "Menu": 311}
                axes = {"LT": ("ABS_Z", 1023), "RT": ("ABS_RZ", 1023),
                        "up": ("ABS_HAT0Y", -1), "down": ("ABS_HAT0Y", 1),
                        "left": ("ABS_HAT0X", -1), "right": ("ABS_HAT0X", 1)}
                if name in buttons:
                    key(pad, buttons[name])
                else:
                    axis(pad, *axes[name])

            def press_all(pad, names):
                for name in names:
                    press(pad, name)

            machine.start()
            machine.wait_for_unit("multi-user.target")

            with subtest("a LUKS root, with a passphrase made of the controller's characters"):
                machine.succeed("printf %s ${passphrase} | cryptsetup luksFormat -q --iter-time=1 ${luks} -")
                machine.succeed("printf %s ${passphrase} | cryptsetup open ${luks} cryptroot -")
                machine.succeed("mkfs.ext4 -q /dev/mapper/cryptroot")
                machine.succeed("cryptsetup close cryptroot")
                # Limine always starts the newest generation's main system, never a specialisation
                machine.succeed(
                    "nix-env -p /nix/var/nix/profiles/system --set ${onLuks}"
                    " && ${onLuks}/bin/switch-to-configuration boot >&2"
                )

            with subtest("the controller unlocks the disk, after a wrong try and a press taken back"):
                boot()
                wait_for_prompt()
                machine.wait_for_unit("handheld-input.service")
                machine.succeed("(evemu-device /etc/fake-pad >/tmp/fake-pad 2>&1 &)")
                pad = machine.wait_until_succeeds(
                    "grep -o '/dev/input/event[0-9]*' /tmp/fake-pad", timeout=30
                ).strip()
                # it looks for new controllers four times a second
                time.sleep(2)

                press_all(pad, ["B"] * 8 + ["Menu"])
                machine.wait_until_succeeds(
                    "journalctl -b -o cat -u systemd-cryptsetup@cryptroot.service >/tmp/log"
                    " && grep -q 'Passphrase incorrect' /tmp/log",
                    timeout=60,
                )
                time.sleep(2)
                wait_for_prompt()

                # X typed, then deleted with View
                press_all(pad, ["X", "View", "A", "LT", "up", "LB", "down", "left", "RT", "B", "Menu"])
                machine.switch_root()
                assert machine.succeed("findmnt -no SOURCE /").strip() == "/dev/mapper/cryptroot"

            with subtest("the virtual keyboard is gone, and nothing it saw was logged"):
                machine.fail("grep -q 'Ephemeral controller keys' /proc/bus/input/devices")
                own = machine.succeed("journalctl -b -o cat _SYSTEMD_UNIT=handheld-input.service")
                assert own.strip() == "", f"handheld-input logged: {own!r}"
                assert "${passphrase}" not in machine.succeed("journalctl -b -o cat"), "the passphrase is in the journal"

            with subtest("a keyboard still works alongside"):
                boot()
                wait_for_prompt()
                # QEMU sends US key positions, which the French layout turns into the passphrase
                machine.send_chars("qwuadlcb\n")
                machine.switch_root()
                assert machine.succeed("findmnt -no SOURCE /").strip() == "/dev/mapper/cryptroot"
          '';
      };
    };
}
