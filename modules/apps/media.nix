{
  ephemeral.apps = {
    mpv = {
      label = "mpv";
      category = "Media";
      description = "minimal video player";
      package = "mpv";
    };
    spotify = {
      label = "Spotify";
      category = "Media";
      description = "music streaming";
      package = "spotify";
      unfree = [ "spotify" ];
    };
    obs-studio = {
      label = "OBS Studio";
      category = "Media";
      description = "screen recording and streaming";
      package = "obs-studio";
    };
    audacity = {
      label = "Audacity";
      category = "Media";
      description = "audio editor";
      package = "audacity";
    };
    kdenlive = {
      label = "Kdenlive";
      category = "Media";
      description = "video editor";
      package = "kdePackages.kdenlive";
    };
    handbrake = {
      label = "HandBrake";
      category = "Media";
      description = "video converter";
      package = "handbrake";
    };
  };
}
