{
  flake.modules.nixos.handheld-unlock =
    { pkgs, ... }:
    let
      input = pkgs.callPackage ./_handheld-input.nix { };
    in
    {
      boot.initrd = {
        # evdev gives each controller the /dev/input node the program reads; the initrd doesn't load
        # it on its own
        kernelModules = [
          "evdev"
          "uinput"
        ];
        # the Deck's and the Ally X's own controllers, which work without Handheld Daemon, and wired
        # Xbox and PlayStation pads
        availableKernelModules = [
          "hid_steam"
          "hid_asus"
          "hid_generic"
          "usbhid"
          "xpad"
          "hid_playstation"
        ];

        systemd.storePaths = [ input ];
        # Presses become keys on a virtual keyboard, so the splash's own passphrase prompt takes
        # them, and a real keyboard works alongside.
        systemd.services.handheld-input = {
          description = "Controller buttons as keys for the disk passphrase";
          wantedBy = [ "initrd.target" ];
          after = [ "systemd-modules-load.service" ];
          conflicts = [
            "initrd-switch-root.target"
            "shutdown.target"
          ];
          before = [
            "initrd-switch-root.target"
            "shutdown.target"
          ];
          unitConfig.DefaultDependencies = false;
          # nothing that needs a mount namespace, which the initrd's root can't always give
          serviceConfig = {
            ExecStart = "${input}/bin/handheld-input passphrase";
            DevicePolicy = "closed";
            DeviceAllow = [
              "/dev/uinput w"
              "/dev/tty0 r"
              "char-input r"
            ];
            CapabilityBoundingSet = [ "" ];
            NoNewPrivileges = true;
            RestrictAddressFamilies = [ "none" ];
            IPAddressDeny = "any";
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = [ "@system-service" ];
            SystemCallErrorNumber = "EPERM";
          };
        };
      };
    };
}
