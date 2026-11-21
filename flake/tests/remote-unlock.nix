# A server's disk unlocked over SSH from a second machine, through the boot loader's copy of the
# host key, then a login with a key and a password refused. features-eval only sees the options;
# this shows the key reaches the initrd and the passphrase gets through. remote-unlock-sealed does
# the same with the copy sealed to the TPM, as ephemeral-update makes it with Secure Boot on.
{ config, lib, ... }:
let
  nixos = config.ephemeral.aspects.nixos;
  passphrase = "supersecret";
  luks = "/dev/disk/by-id/virtio-crypt";
  key = import ../../modules/_initrd-ssh-key.nix;
  prelude = import ../../modules/packages/_prelude.nix { inherit lib; };
in
{
  perSystem =
    { pkgs, ... }:
    let
      keys = "${pkgs.path}/nixos/tests/initrd-network-ssh";
      ssh = "ssh -i /etc/client-key -o BatchMode=yes -o ConnectTimeout=5";
      # the function ephemeral-update runs, with the prelude every command has
      makeKey = pkgs.writeShellScript "make-initrd-ssh-key" (prelude + "\nmake_initrd_ssh_key\n");

      test =
        sealed:
        pkgs.testers.runNixOSTest {
          name = if sealed then "remote-unlock-sealed" else "remote-unlock";
          # it usually takes a few minutes
          globalTimeout = 900;
          node.pkgsReadOnly = false;

          nodes.server =
            { config, lib, ... }:
            {
              imports = [
                nixos.vm
                nixos.base
                nixos.server
              ];
              ephemeral.settings = {
                hostname = "server";
                username = "alice";
                diskDevice = "/dev/vda";
                swapSize = "1G";
                server = true;
                sshKeys = [ (lib.trim (builtins.readFile "${keys}/id_ed25519.pub")) ];
              };
              boot.consoleLogLevel = lib.mkForce 7;
              boot.loader.limine.enable = lib.mkOverride 10 true;
              environment.systemPackages = [
                pkgs.cryptsetup
                pkgs.jq
                pkgs.libarchive
              ];
              virtualisation = {
                useBootLoader = true;
                useEFIBoot = true;
                diskImage = lib.mkOverride 10 "./${config.system.name}.qcow2";
                # the root on the encrypted disk needs the store from the host
                mountHostNixStore = true;
                # the plain OVMF doesn't measure the boot into the TPM
                efi.OVMF = pkgs.OVMFFull;
                tpm.enable = sealed;
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
                boot.plymouth.enable = lib.mkForce false;
                # the test network has no DHCP; the address the running system has
                boot.initrd.systemd.network.networks."05-test" = {
                  matchConfig.Name = "eth1";
                  address = [ "${config.networking.primaryIPAddress}/24" ];
                };
              };
            };

          nodes.client = {
            environment.systemPackages = [ pkgs.netcat ];
            environment.etc.client-key = {
              source = "${keys}/id_ed25519";
              mode = "0600";
            };
          };

          testScript =
            { nodes, ... }:
            let
              onLuks = nodes.server.specialisation.on-luks.configuration.system.build.toplevel;
              # tpm.sh reads Secure Boot and the TPM under EPHEMERAL_ROOT; the sealing uses the real TPM
              firmware = lib.optionalString sealed "EPHEMERAL_ROOT=/tmp/fw ";
            in
            ''
              start_all()
              server.wait_for_unit("multi-user.target")

              with subtest("the server makes its key, and the boot loader puts its copy in the initrd"):
                  server.wait_until_succeeds("test -s ${key.boot}")
                  server.succeed(
                      "mkdir -p /tmp/flake /tmp/fw/dev /tmp/fw/sys/firmware/efi/efivars"
                      " && echo '{\"server\": true}' > /tmp/flake/settings.json"
                      " && touch /tmp/fw/dev/tpmrm0"
                      " && printf '\\x06\\x00\\x00\\x00\\x01'"
                      " > /tmp/fw/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
                  )
                  server.succeed("FLAKE_DIR=/tmp/flake ${firmware}${makeKey}")
                  server.succeed("printf %s ${passphrase} | cryptsetup luksFormat -q --iter-time=1 ${luks} -")
                  server.succeed("printf %s ${passphrase} | cryptsetup open ${luks} cryptroot -")
                  server.succeed("mkfs.ext4 -q /dev/mapper/cryptroot")
                  server.succeed("cryptsetup close cryptroot")
                  # Limine always starts the newest generation's main system, never a specialisation
                  server.succeed(
                      "nix-env -p /nix/var/nix/profiles/system --set ${onLuks}"
                      " && ${onLuks}/bin/switch-to-configuration boot >&2"
                  )
                  on_esp = "bsdtar -xOf /boot/limine/kernels/*-secrets"
                  server.succeed(f"bsdtar -tf /boot/limine/kernels/*-secrets | grep -q etc/ssh/boot-key")
                  ${
                    if sealed then
                      ''server.fail(f"{on_esp} | grep -q 'PRIVATE KEY'")''
                    else
                      ''server.succeed(f"{on_esp} | grep -q 'PRIVATE KEY'")''
                  }
                  host_key = server.succeed("cat ${key.key}.pub").split()[:2]
                  client.succeed(f"echo '[server]:2222 {' '.join(host_key)}' > /etc/initrd-known-hosts")

              with subtest("the passphrase typed over SSH unlocks the disk"):
                  server.shutdown()
                  server.start()
                  # the prompt can come up after sshd does, and then the first try finds nothing to answer
                  def unlock(_):
                      client.execute(
                          "printf '%s\\n' ${passphrase} | timeout 30 ${ssh} -tt -p 2222"
                          " -o UserKnownHostsFile=/etc/initrd-known-hosts -o StrictHostKeyChecking=yes root@server >&2"
                      )
                      return client.execute("timeout 20 sh -c 'until nc -z server 22; do sleep 1; done'")[0] == 0
                  retry(unlock, timeout=300)
                  server.wait_for_unit("multi-user.target")
                  assert server.succeed("findmnt -no SOURCE /").strip() == "/dev/mapper/cryptroot"

              with subtest("the running server takes the key and refuses a password"):
                  client.succeed("${ssh} -o StrictHostKeyChecking=no alice@server true")
                  refused = client.fail(
                      "${ssh} -o StrictHostKeyChecking=no -o PubkeyAuthentication=no"
                      " -o PreferredAuthentications=password,keyboard-interactive alice@server true 2>&1"
                  )
                  assert "Permission denied (publickey)" in refused, refused
                  client.fail("nc -z -w 5 server 2222")
            '';
        };
    in
    {
      checks.remote-unlock = test false;
      checks.remote-unlock-sealed = test true;
    };
}
