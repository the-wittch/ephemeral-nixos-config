{
  ephemeral.apps = {
    profile-sync-daemon = {
      label = "Profile-sync-daemon";
      category = "System";
      description = "keeps browser profiles in RAM and copies them back to disk";
      warn = "a crash or power cut loses up to 10 minutes of browser history and open tabs";
      nixos.services.psd = {
        enable = true;
        resyncTimer = "10min";
      };
    };
    ananicy-cpp = {
      label = "ananicy-cpp";
      category = "System";
      description = "sets CPU and IO priority per app using CachyOS rules";
      nixos =
        { pkgs, ... }:
        {
          services.ananicy = {
            enable = true;
            package = pkgs.ananicy-cpp;
            rulesProvider = pkgs.ananicy-rules-cachyos;
          };
        };
    };
    bpftune = {
      label = "bpftune";
      category = "System";
      description = "tunes network and memory settings as the load changes";
      nixos.services.bpftune.enable = true;
    };
  };
}
