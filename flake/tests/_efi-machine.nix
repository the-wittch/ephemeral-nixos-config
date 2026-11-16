# A machine on a real ESP, with firmware variables that survive a reboot, built from the
# aspects of any release: what an installed machine has when its bootloader changes.
{ hostname }:
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
    inherit hostname;
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
}
