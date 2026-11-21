# Rules 4, 5 and 6 of ARCHITECTURE.md's Security section, checked on the evaluated machines
{ config, lib, ... }:
let
  hosts = [
    "gnome-full"
    "gnome-minimal"
    "plasma-full"
    "plasma-minimal"
    "niri-full"
    "niri-minimal"
    "umbriel-full"
    "umbriel-minimal"
    "none-full"
    "none-minimal"
    "feat-all"
    "feat-laptop"
    "feat-network"
    "feat-pass"
    "feat-server"
  ];
  host = name: config.flake.nixosConfigurations.${name}.config;

  # Podman opens DNS on its own bridge so containers can resolve names; that bridge isn't
  # reachable from the network
  openOnInterfaces =
    interfaces:
    lib.attrNames (
      lib.filterAttrs (
        name: i:
        let
          ports = i.allowedTCPPorts ++ i.allowedTCPPortRanges ++ i.allowedUDPPortRanges;
        in
        !(lib.hasPrefix "podman" name && ports == [ ] && lib.all (p: p == 53) i.allowedUDPPorts)
        && (ports ++ i.allowedUDPPorts) != [ ]
      ) interfaces
    );

  exposure =
    name:
    let
      c = host name;
      fw = c.networking.firewall;
      ssh = c.services.openssh.settings;
      # a server opens SSH, keys only, and nothing else
      serverSsh =
        c.ephemeral.settings.server
        && !ssh.PasswordAuthentication
        && !ssh.KbdInteractiveAuthentication
        && ssh.PermitRootLogin == "no";
      tcp = if serverSsh then lib.remove 22 fw.allowedTCPPorts else fw.allowedTCPPorts;
    in
    lib.optional (!fw.enable) "the firewall is off"
    ++ lib.optional (
      tcp ++ fw.allowedUDPPorts ++ fw.allowedTCPPortRanges ++ fw.allowedUDPPortRanges != [ ]
    ) "ports are open: ${builtins.toJSON tcp} tcp, ${builtins.toJSON fw.allowedUDPPorts} udp"
    ++ lib.optional (
      openOnInterfaces fw.interfaces != [ ]
    ) "ports are open on ${toString (openOnInterfaces fw.interfaces)}"
    ++ lib.optional (c.services.openssh.enable && !serverSsh) "SSH is on"
    ++ lib.optional c.users.mutableUsers "users can be changed outside the config"
    ++ lib.optional (c.users.users.root.hashedPassword != "!") "root has a password"
    ++ lib.optional (
      c.ephemeral.settings.profile == "full"
      && c.ephemeral.settings.useOpenSnitch
      && c.ephemeral.settings.desktop != "none"
      && !c.services.opensnitch.enable
    ) "OpenSnitch is off";
  exposed = lib.concatMap (name: map (p: "${name}: ${p}") (exposure name)) hosts;

  # Every system service a file in modules/ defines a program for, as root, has to use
  # ephemeral.sandbox or at least what it promises. Found from where each definition comes from,
  # so a new service is checked without being listed here.
  everything = config.flake.nixosConfigurations.feat-all.extendModules {
    modules = [
      { ephemeral.pickedApps = lib.attrNames config.ephemeral.apps; }
    ]
    ++ map (app: app.nixos) (lib.attrValues config.ephemeral.apps);
  };
  unsandboxed = {
    credential-secret-setup = "it bind-mounts the credential key into the running system";
    opensnitch-boot-guard = "it adds nftables rules to the system's network, so it can't have a private one; the rest of the sandbox applies";
  };
  ours = lib.filter (
    d: lib.hasPrefix (toString ../modules) d.file
  ) everything.options.systemd.services.definitionsWithLocations;
  # impermanence makes a persist-<path> unit for each kept file, from persist.nix's list
  defined = lib.filter (name: !lib.hasPrefix "persist-persist-" name) (
    lib.unique (
      lib.concatMap (
        d:
        lib.attrNames (
          lib.filterAttrs (
            _: s: lib.isAttrs s && (s ? script || (s.serviceConfig or { }) ? ExecStart)
          ) d.value
        )
      ) ours
    )
  );
  sandboxed =
    name:
    let
      s = everything.config.systemd.services.${name}.serviceConfig;
    in
    (s.User or "root") != "root"
    || s.DynamicUser or false
    || (
      s.ProtectSystem or null == "strict"
      && s.ProtectHome or false
      && s.NoNewPrivileges or false
      && s.PrivateNetwork or false
      && s ? CapabilityBoundingSet
      && s ? SystemCallFilter
    );
  loose = lib.filter (name: !(unsandboxed ? ${name}) && !sandboxed name) defined;
  stale = lib.filter (name: !lib.elem name defined) (lib.attrNames unsandboxed);
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.exposure-eval =
        assert lib.assertMsg (
          exposed == [ ]
        ) "machines with something exposed:\n${lib.concatStringsSep "\n" exposed}";
        pkgs.writeText "exposure-eval" (lib.concatStringsSep "\n" hosts);

      checks.sandbox-eval =
        # the detection itself has to work, or this check passes on nothing
        assert lib.assertMsg (lib.all (n: lib.elem n defined) [
          "root-reset-check"
          "controld-resolver"
          "snapper-persist-setup"
        ]) "sandbox-eval found only: ${toString defined}";
        assert lib.assertMsg (loose == [ ]) ''
          root services from modules/ without the sandbox: ${toString loose}
          Use config.ephemeral.sandbox, or add the service to unsandboxed in flake/checks-security.nix with the reason.'';
        assert lib.assertMsg (stale == [ ]) "unsandboxed lists services that are gone: ${toString stale}";
        pkgs.writeText "sandbox-eval" (lib.concatStringsSep "\n" defined);
    };
}
