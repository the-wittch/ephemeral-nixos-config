# Stub. Copy the installer's hardware-configuration.nix and don't commit that copy.
# Disk layout is disko.nix. This file is modules and microcode.
{ lib, ... }:
{
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  # boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
}
