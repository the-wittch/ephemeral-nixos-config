{
  flake.modules.nixos.server =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      settings = config.ephemeral.settings;
      initrdKey = import ./_initrd-ssh-key.nix;
    in
    {
      assertions = [
        {
          assertion = settings.sshKeys != [ ];
          message = ''"server": true needs at least one key in "sshKeys"; without one, nobody can log in over SSH.'';
        }
      ];

      # ssh.nix already refuses passwords and root for every machine
      services.openssh.enable = true;
      # every interface, LAN included: keys only, so a broken Tailscale doesn't lock you out
      services.openssh.openFirewall = true;
      users.users.${settings.username}.openssh.authorizedKeys.keys = settings.sshKeys;

      # so an idle timer, the lid or the desktop can't put it to sleep
      systemd.targets =
        lib.genAttrs
          [
            "sleep"
            "suspend"
            "hibernate"
            "hybrid-sleep"
          ]
          (_: {
            enable = false;
          });

      # Unlocking over SSH after a reboot. The boot loader adds the key's boot copy to the initrd
      # when it's installed, so it never enters the Nix store; without that support, as in the VM,
      # it's off.
      boot.initrd = lib.mkIf config.boot.loader.supportsInitrdSecrets {
        secrets."/etc/ssh/boot-key" = initrdKey.boot;
        network = {
          enable = true;
          flushBeforeStage2 = true;
          ssh = {
            enable = true;
            # its own key, which clients would take for a changed one on port 22
            port = 2222;
            ignoreEmptyHostKeys = true;
            extraConfig = "HostKey /etc/ssh/ssh_host_ed25519_key";
            authorizedKeys = settings.sshKeys;
          };
        };
        # the plain key only ever exists in the initrd's memory, which is gone after the boot
        systemd.services.sshd = {
          after = [ "tpm2.target" ];
          preStart = ''
            IFS= read -r -n 10 start </etc/ssh/boot-key || true
            if [[ $start == -----BEGIN ]]; then
              /bin/cp /etc/ssh/boot-key /etc/ssh/ssh_host_ed25519_key
            else
              /bin/systemd-creds decrypt --name=${initrdKey.name} /etc/ssh/boot-key /etc/ssh/ssh_host_ed25519_key
            fi
            /bin/chmod 600 /etc/ssh/ssh_host_ed25519_key
          '';
        };
        systemd.users.root.shell = "/bin/systemd-tty-ask-password-agent";
        systemd.network.networks."90-ethernet" = {
          matchConfig.Type = "ether";
          networkConfig.DHCP = "yes";
        };
        # hardware-configuration.nix doesn't list network drivers, since nothing else needs them early
        availableKernelModules = [
          "e1000e"
          "igb"
          "igc"
          "ixgbe"
          "r8169"
          "tg3"
          "bnx2"
          "atlantic"
          "alx"
          "atl1c"
          "virtio_net"
          "r8152"
          "cdc_ether"
          "ax88179_178a"
        ];
      };

      # ephemeral-doctor checks the key when this is here
      environment.etc."ephemeral/server".text = "";

      # ephemeral-update and the installer make the key before building, and seal its boot copy,
      # since the boot loader reads that before anything here runs. This covers a rebuild without
      # them, for the one after, with an unsealed copy.
      systemd.tmpfiles.rules = [ "d /persist/etc/ssh/initrd 0700 root root -" ];
      systemd.services.initrd-ssh-host-key = {
        description = "Make the host key for unlocking over SSH";
        wantedBy = [ "multi-user.target" ];
        unitConfig.ConditionPathExists = "!${initrdKey.boot}";
        path = [
          pkgs.openssh
          pkgs.coreutils
        ];
        serviceConfig = config.ephemeral.sandbox // {
          Type = "oneshot";
          ReadWritePaths = [ "/persist/etc/ssh/initrd" ];
        };
        script = ''
          [[ -e ${initrdKey.key} ]] || ssh-keygen -q -t ed25519 -N "" -C initrd -f ${initrdKey.key}
          install -m 600 ${initrdKey.key} ${initrdKey.boot}
        '';
      };
    };
}
