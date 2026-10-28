{
  ephemeral.apps = {
    discord = {
      label = "Discord";
      category = "Communication";
      description = "chat and voice";
      package = "discord";
      unfree = [
        "discord"
        "discord-unwrapped"
      ];
    };
    signal = {
      label = "Signal";
      category = "Communication";
      description = "end-to-end encrypted messenger";
      package = "signal-desktop";
    };
    telegram = {
      label = "Telegram";
      category = "Communication";
      description = "messenger";
      package = "telegram-desktop";
    };
    element = {
      label = "Element";
      category = "Communication";
      description = "Matrix chat";
      package = "element-desktop";
    };
    thunderbird = {
      label = "Thunderbird";
      category = "Communication";
      description = "email and calendar";
      flatpak = "org.mozilla.thunderbird";
    };
    slack = {
      label = "Slack";
      category = "Communication";
      description = "team chat";
      package = "slack";
      unfree = [ "slack" ];
    };
    zoom = {
      label = "Zoom";
      category = "Communication";
      description = "video calls";
      package = "zoom-us";
      unfree = [ "zoom" ];
    };
  };
}
