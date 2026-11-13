{
  flake.modules.nixos.base =
    { lib, ... }:
    {
      services.openssh = {
        enable = lib.mkDefault false;
        openFirewall = false;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
          X11Forwarding = false;
          AllowAgentForwarding = false;
        };
        hostKeys = [
          {
            path = "/persist/etc/ssh/ssh_host_ed25519_key";
            type = "ed25519";
          }
        ];
      };

      # sshd makes the key here when it first starts, which is after tmpfiles has run
      systemd.tmpfiles.rules = [
        "d /persist/etc/ssh 0755 root root -"
        "z /persist/etc/ssh/ssh_host_*_key 0600 - - -"
        "z /persist/etc/ssh/ssh_host_*_key.pub 0644 - - -"
      ];
    };
}
