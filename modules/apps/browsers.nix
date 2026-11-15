{
  ephemeral.apps = {
    firefox = {
      label = "Firefox";
      category = "Browsers";
      description = "Mozilla's browser";
      package = "firefox";
      default = true;
    };
    brave = {
      label = "Brave";
      category = "Browsers";
      description = "Chromium with ad blocking built in (the Origin build)";
      package = "brave-origin";
    };
    chromium = {
      label = "Chromium";
      category = "Browsers";
      description = "the open-source base of Chrome";
      package = "chromium";
    };
    librewolf = {
      label = "LibreWolf";
      category = "Browsers";
      description = "Firefox with telemetry removed and stricter defaults";
      package = "librewolf";
    };
    tor-browser = {
      label = "Tor Browser";
      category = "Browsers";
      description = "browse through the Tor network";
      package = "tor-browser";
    };
    mullvad-browser = {
      label = "Mullvad Browser";
      category = "Browsers";
      description = "Tor Browser's privacy settings without Tor";
      package = "mullvad-browser";
    };
  };
}
