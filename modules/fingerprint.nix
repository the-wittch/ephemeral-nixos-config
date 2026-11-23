{
  flake.modules.nixos.fingerprint = {
    services.fprintd.enable = true;
    preservation.preserveAt."/persist".directories = [
      {
        directory = "/var/lib/fprint";
        mode = "0700";
      }
    ];
  };
}
