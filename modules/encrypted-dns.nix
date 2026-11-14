let
  # server address#name; resolved checks the TLS certificate against the name
  providers = {
    cloudflare = map (ip: "${ip}#cloudflare-dns.com") [
      "1.1.1.1"
      "1.0.0.1"
      "2606:4700:4700::1111"
      "2606:4700:4700::1001"
    ];
    quad9 = map (ip: "${ip}#dns.quad9.net") [
      "9.9.9.9"
      "149.112.112.112"
      "2620:fe::fe"
      "2620:fe::9"
    ];
    adguard = map (ip: "${ip}#dns.adguard-dns.com") [
      "94.140.14.14"
      "94.140.15.15"
      "2a10:50c0::ad1:ff"
      "2a10:50c0::ad2:ff"
    ];
  };
in
{
  flake.modules.nixos.encrypted-dns =
    { config, ... }:
    let
      settings = config.ephemeral.settings;
    in
    {
      assertions = [
        {
          assertion = settings.encryptedDns != "custom" || settings.customDns != [ ];
          message = ''
            settings.json sets "encryptedDns": "custom" but lists no servers in customDns.
            Add them as "address#name", e.g. "customDns": [ "194.242.2.2#dns.mullvad.net" ].
          '';
        }
        {
          assertion = !(settings.useControlD && settings.profile == "full");
          message = ''
            settings.json sets both useControlD and encryptedDns ("${settings.encryptedDns}"), and DNS can only go to one of them.
            Set "useControlD": false or "encryptedDns": "none".
          '';
        }
      ];

      services.resolved = {
        enable = true;
        settings.Resolve = {
          DNS = providers.${settings.encryptedDns} or settings.customDns;
          # no plain DNS to the network's own servers, ever
          FallbackDNS = "";
          Domains = "~.";
          DNSOverTLS = "yes";
        };
      };

      services.opensnitch.rules.resolved-dns-over-tls = {
        name = "resolved-dns-over-tls";
        enabled = true;
        action = "allow";
        duration = "always";
        operator = {
          type = "list";
          operand = "list";
          list = [
            {
              type = "simple";
              sensitive = false;
              operand = "process.path";
              data = "${config.systemd.package}/lib/systemd/systemd-resolved";
            }
            {
              type = "simple";
              sensitive = false;
              operand = "dest.port";
              data = "853";
            }
          ];
        };
      };
    };
}
