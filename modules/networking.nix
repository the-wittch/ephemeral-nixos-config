{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      networking.networkmanager = {
        enable = true;
        plugins = with pkgs; [
          networkmanager-openvpn
        ];
        # a different MAC address on each Wi-Fi network, the same one every time
        wifi.macAddress = "stable";
      };
      networking.firewall.enable = true;

      services.resolved.settings.Resolve.LLMNR = "false";
    };
}
