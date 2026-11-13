{
  flake.modules.nixos.base =
    { lib, ... }:
    {
      options.ephemeral.sandbox = lib.mkOption {
        type = lib.types.attrs;
        readOnly = true;
        description = "serviceConfig for the config's own root oneshots: read-only system, no network, no capabilities.";
        default = {
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          PrivateNetwork = true;
          NoNewPrivileges = true;
          CapabilityBoundingSet = [ "" ];
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          ProtectHostname = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
          RestrictNamespaces = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          SystemCallArchitectures = "native";
        };
      };
    };
}
