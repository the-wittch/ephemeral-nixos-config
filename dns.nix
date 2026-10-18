{
  lib,
  settings,
  ...
}:

let
  id = settings.controldResolver or ""; # "" skips this
in
{
  # public Control D resolvers; the id is yours
  services.resolved = lib.mkIf (id != "") {
    enable = true;
    settings.Resolve = {
      DNS = [
        "76.76.2.22#${id}.dns.controld.com"
        "2606:1a40::22#${id}.dns.controld.com"
      ];
      FallbackDNS = [ ];
      Domains = [ "~." ];
      DNSOverTLS = true;
    };
  };
}
