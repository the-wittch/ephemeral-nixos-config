# A server's host key for unlocking over SSH, and the copy the boot loader puts in the initrd:
# sealed to this machine's TPM when Secure Boot is on, the key itself otherwise.
# server.nix and the commands both read these.
{
  key = "/persist/etc/ssh/initrd/ssh_host_ed25519_key";
  boot = "/persist/etc/ssh/initrd/boot-key";
  name = "initrd-ssh-host-key";
}
