{
  hostname = "nixos";
  username = "nixuser";
  timeZone = "UTC";
  locale = "en_US.UTF-8";
  keyboardLayout = "us";
  keyboardVariant = "";
  diskDevice = "/dev/nvme0n1";
  swapSize = "16G";
  desktop = "plasma";
  profile = "full";
  nvidia = "none";
  extras = false;
  laptop = false;
  fingerprint = false;
  useControlD = false;
  useTailscale = false;
  useOpenSnitch = true;
  useFlakePassCli = false;
  usePassSettings = false;
  passSettingsVault = "Personal";
  passSettingsItem = "nixos-settings";
  usePassSshAgent = false;
  passSshVault = "Personal";
}
