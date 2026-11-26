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
    "handheld-full"
    "handheld-minimal"
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
          ports = i.allowedTCPPorts ++ i.allowedUDPPorts;
          ranges = i.allowedTCPPortRanges ++ i.allowedUDPPortRanges;
        in
        # DNS over UDP and TCP, the second for answers too big for one packet
        !(lib.hasPrefix "podman" name && ranges == [ ] && lib.all (p: p == 53) ports)
        && (ports ++ ranges) != [ ]
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
      && !lib.elem c.ephemeral.settings.desktop [
        "none"
        "handheld"
      ]
      && !c.services.opensnitch.enable
    ) "OpenSnitch is off";
  exposed = lib.concatMap (name: map (p: "${name}: ${p}") (exposure name)) hosts;

  # Every system service a file in modules/ defines a program for, as root, has to use
  # ephemeral.sandbox or at least what it promises; the initrd's, which can't have a mount
  # namespace, everything else. Found from where each definition comes from, so a new service is
  # checked without being listed here. The handheld is a machine of its own, as its desktop and
  # apps are in no other.
  withAllApps =
    name:
    config.flake.nixosConfigurations.${name}.extendModules {
      modules = [
        { ephemeral.pickedApps = lib.attrNames config.ephemeral.apps; }
      ]
      ++ map (app: app.nixos) (lib.attrValues config.ephemeral.apps);
    };
  machines = map withAllApps [
    "feat-all"
    "handheld-full"
  ];
  unsandboxed = {
    credential-secret-setup = "it bind-mounts the credential key into the running system";
    opensnitch-boot-guard = "it adds nftables rules to the system's network, so it can't have a private one; the rest of the sandbox applies";
    systemd-machine-id-commit = "systemd's own unit; persist.nix only points it at /persist, as preservation's first-boot setup does";
    rollback = "it swaps the btrfs root for root-blank in the initrd, which takes the block device and CAP_SYS_ADMIN";
    decky-loader = "upstream only supports it as root: it installs plugins and runs the ones that ask for root, and drops to the user for the rest";
  };
  definedIn =
    machine: path:
    lib.unique (
      lib.concatMap
        (
          d:
          lib.attrNames (
            lib.filterAttrs (
              _: s: lib.isAttrs s && (s ? script || (s.serviceConfig or { }) ? ExecStart)
            ) d.value
          )
        )
        (
          lib.filter (
            d: lib.hasPrefix (toString ../modules) d.file
          ) (lib.getAttrFromPath path machine.options).definitionsWithLocations
        )
    );
  system = [
    "systemd"
    "services"
  ];
  initrd = [
    "boot"
    "initrd"
    "systemd"
    "services"
  ];
  sandboxed =
    s:
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
  initrdSandboxed =
    s:
    s.CapabilityBoundingSet or null == [ "" ]
    && s.NoNewPrivileges or false
    && s ? SystemCallFilter
    && s.DevicePolicy or null == "closed"
    && s.RestrictAddressFamilies or null == [ "none" ];
  looseIn =
    machine:
    lib.filter (
      name:
      !(unsandboxed ? ${name})
      && !sandboxed (lib.getAttrFromPath system machine.config).${name}.serviceConfig
    ) (definedIn machine system)
    ++ lib.filter (
      name:
      !(unsandboxed ? ${name})
      && !initrdSandboxed (lib.getAttrFromPath initrd machine.config).${name}.serviceConfig
    ) (definedIn machine initrd);
  defined = lib.unique (lib.concatMap (m: definedIn m system ++ definedIn m initrd) machines);
  loose = lib.unique (lib.concatMap looseIn machines);
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
          "rollback"
          "handheld-input"
          "decky-loader"
        ]) "sandbox-eval found only: ${toString defined}";
        assert lib.assertMsg (loose == [ ]) ''
          root services from modules/ without the sandbox: ${toString loose}
          Use config.ephemeral.sandbox, or add the service to unsandboxed in flake/checks-security.nix with the reason.'';
        assert lib.assertMsg (stale == [ ]) "unsandboxed lists services that are gone: ${toString stale}";
        pkgs.writeText "sandbox-eval" (lib.concatStringsSep "\n" defined);
    };
}
