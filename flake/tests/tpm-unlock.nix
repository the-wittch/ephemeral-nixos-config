# nix build path:.#checks.x86_64-linux.tpm-unlock -L
# The disk unlocked by the TPM and a PIN, and by the passphrase once wrong PINs have locked the
# TPM out. A software TPM and a real LUKS root; the disk test can't have a TPM, since disko starts
# its machine itself.
{ config, ... }:
let
  nixos = config.ephemeral.aspects.nixos;
  passphrase = "supersecret";
  pin = "4711";
  luks = "/dev/disk/by-id/virtio-crypt";
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.tpm-unlock = pkgs.testers.runNixOSTest {
        name = "tpm-unlock";
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
            ];
            ephemeral.settings = {
              hostname = "tpmunlock";
              username = "alice";
              diskDevice = "/dev/vda";
              swapSize = "1G";
            };
            boot.consoleLogLevel = lib.mkForce 7;
            boot.loader.limine.enable = lib.mkOverride 10 true;
            environment.systemPackages = [ pkgs.cryptsetup ];
            virtualisation = {
              useBootLoader = true;
              useEFIBoot = true;
              diskImage = lib.mkOverride 10 "./${config.system.name}.qcow2";
              # the root on the encrypted disk needs the store from the host
              mountHostNixStore = true;
              # the plain OVMF doesn't measure the boot into the TPM
              efi.OVMF = pkgs.OVMFFull;
              tpm.enable = true;
              emptyDiskImages = [
                {
                  size = 1024;
                  driveConfig.deviceExtraOpts.serial = "crypt";
                }
              ];
            };

            specialisation.on-luks.configuration = {
              # what tpm-unlock.nix adds; the VM's own definition replaces the machine's cryptroot
              boot.initrd.luks.devices = lib.mkVMOverride {
                cryptroot = {
                  device = luks;
                  crypttabExtraOpts = [ "tpm2-device=auto" ];
                };
              };
              virtualisation.rootDevice = "/dev/mapper/cryptroot";
              # with the splash on, the prompt is drawn on the screen and never reaches the
              # serial console the test reads and types into
              boot.plymouth.enable = lib.mkForce false;
            };
          };

        testScript =
          { nodes, ... }:
          let
            onLuks = nodes.machine.specialisation.on-luks.configuration.system.build.toplevel;
          in
          ''
            from datetime import timedelta

            # The prompts end without a newline, and the driver only sees whole lines, so these
            # wait for the lines systemd logs around them.
            def query():
                machine.wait_for_console_text(r"Starting password query on /dev/ttyS0", timeout=timedelta(minutes=3))
                # it logs that just before it writes the prompt and reads the answer
                machine.sleep(timedelta(seconds=2))

            # each start begins a new console log
            def boot():
                machine.shutdown()
                machine.start()

            # logged when systemd gives up on the TPM and asks for the passphrase
            fallback = "falling back to traditional unlocking"
            lockout = "dictionary attack lock-out mode"

            machine.start()
            machine.wait_for_unit("multi-user.target")

            with subtest("a LUKS root enrolled with the TPM, PCR 7 and a PIN, as ephemeral-setup does"):
                machine.succeed("printf %s ${passphrase} | cryptsetup luksFormat -q --iter-time=1 ${luks} -")
                machine.succeed("printf %s ${passphrase} | cryptsetup open ${luks} cryptroot -")
                machine.succeed("mkfs.ext4 -q /dev/mapper/cryptroot")
                machine.succeed(
                    "systemd-run --wait --pipe"
                    " -p SetCredential=cryptenroll.passphrase:${passphrase}"
                    " -p SetCredential=cryptenroll.new-tpm2-pin:${pin}"
                    " systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes --wipe-slot=tpm2 ${luks}"
                )
                dump = machine.succeed("cryptsetup luksDump ${luks}")
                assert "systemd-tpm2" in dump, "no TPM token in the LUKS header"
                machine.succeed("cryptsetup close cryptroot")
                # Limine always starts the newest generation's main system, never a specialisation
                machine.succeed(
                    "nix-env -p /nix/var/nix/profiles/system --set ${onLuks}"
                    " && ${onLuks}/bin/switch-to-configuration boot >&2"
                )

            with subtest("the PIN unlocks the disk, without the passphrase"):
                boot()
                query()
                machine.send_console("${pin}\n")
                machine.wait_for_unit("multi-user.target")
                assert machine.succeed("findmnt -no SOURCE /").strip() == "/dev/mapper/cryptroot"
                log = machine.get_console_log()
                assert "TPM2 PIN" in log or "token PIN" in log, "the first question wasn't the PIN"
                assert fallback not in log, "the TPM didn't unlock it"
                assert log.count("Starting password query on /dev/ttyS0") == 1, "it asked more than once"

            # The PIN is asked again until the TPM locks out, after 3 wrong ones in swtpm; only then
            # does systemd ask for the passphrase.
            with subtest("after wrong PINs lock the TPM out, the passphrase still unlocks it"):
                boot()
                for _ in range(6):
                    query()
                    # systemd asks for the passphrase right after the TPM refuses to try
                    if lockout in machine.get_console_log():
                        break
                    machine.send_console("0000\n")
                    machine.wait_for_console_text(r"Bad password|Bad PIN|lock-out mode", timeout=timedelta(minutes=1))
                else:
                    raise AssertionError("the TPM never locked out")
                machine.send_console("${passphrase}\n")
                machine.wait_for_unit("multi-user.target")
                assert machine.succeed("findmnt -no SOURCE /").strip() == "/dev/mapper/cryptroot"
          '';
      };
    };
}
