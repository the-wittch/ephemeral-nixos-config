{ config, ... }:
let
  nixos = config.flake.modules.nixos;
in
{
  # the machine as a throwaway VM: root on tmpfs, /persist on a scratch btrfs disk
  flake.modules.nixos.vm =
    { config, lib, ... }:
    let
      # documented throwaway password; the VM's disks are gone when it closes
      demo = "ephemeral";
    in
    {
      disko.enableConfig = false;
      boot.initrd.systemd.services.rollback.enable = false;
      boot.loader.systemd-boot.enable = lib.mkForce false;
      hardware.enableRedistributableFirmware = lib.mkForce false;
      services.speechd.enable = lib.mkForce false;
      users.users.root.hashedPasswordFile = lib.mkForce null;
      users.users.${config.ephemeral.settings.username} = {
        hashedPasswordFile = lib.mkForce null;
        password = demo;
      };

      virtualisation = {
        diskImage = null;
        emptyDiskImages = [
          {
            size = 4096;
            driveConfig.deviceExtraOpts.serial = "persist";
          }
        ];
        fileSystems = {
          "/persist" = {
            device = "/dev/disk/by-id/virtio-persist";
            fsType = "btrfs";
            autoFormat = true;
            neededForBoot = true;
          };
          "/var/log" = {
            device = "tmpfs";
            fsType = "tmpfs";
            neededForBoot = true;
          };
        };
        memorySize = 4096;
        cores = 2;
      };
    };

  flake.modules.nixos.pc.virtualisation.vmVariant.imports = [ nixos.vm ];

  perSystem =
    { lib, ... }:
    let
      machine = config.flake.nixosConfigurations.nixos.config;
    in
    {
      apps.vm = {
        type = "app";
        program = lib.getExe' machine.system.build.vm "run-${machine.networking.hostName}-vm";
        meta.description = "boot this machine's config in a throwaway VM (user password: ephemeral)";
      };
    };
}
