{ config, lib, ... }:
let
  # each optional feature on its own, and all of them at once; the desktop hosts switch none on
  hosts = [
    "feat-all"
    "feat-laptop"
    "feat-network"
    "feat-nvidia-legacy"
    "feat-nvidia-open"
    "feat-pass"
    "feat-server"
  ];
  host = name: config.flake.nixosConfigurations.${name}.config;
  # evaluating them catches option renames; this checks each feature is really switched on
  expect = {
    feat-all =
      c:
      c.hardware.nvidia.open
      && c.services.tailscale.enable
      && c.fileSystems ? "/mnt/files"
      && c.boot.loader.limine.secureBoot.enable
      && lib.elem "tpm2-device=auto" c.boot.initrd.luks.devices.cryptroot.crypttabExtraOpts
      && c.services.borgmatic.enable
      && c.services.opensnitch.rules.borgmatic-ssh.operator.list != [ ];
    feat-laptop =
      c:
      c.services.fprintd.enable
      && c.services.upower.enable
      && lib.elem "/var/lib/upower" (
        map (d: d.directory) c.preservation.preserveAt."/persist".directories
      )
      && c.services.resolved.settings.Resolve.DNSOverTLS == "yes"
      && c.services.resolved.settings.Resolve.FallbackDNS == ""
      && lib.elem "9.9.9.9#dns.quad9.net" c.services.resolved.settings.Resolve.DNS;
    feat-network = c: c.services.tailscale.enable && !c.services.opensnitch.enable;
    feat-nvidia-legacy = c: !c.hardware.nvidia.open && c.services.xserver.videoDrivers == [ "nvidia" ];
    feat-nvidia-open = c: c.hardware.nvidia.open;
    feat-pass =
      c:
      c.environment.sessionVariables.PASS_SSH_VAULT == "Work keys"
      && c.services.resolved.settings.Resolve.DNS == [ "194.242.2.2#dns.mullvad.net" ];
    # a server with a desktop keeps it, and OpenSnitch, which has somewhere to ask
    feat-server =
      c:
      c.services.openssh.enable
      && lib.elem 22 c.networking.firewall.allowedTCPPorts
      && c.users.users.alice.openssh.authorizedKeys.keys != [ ]
      && !c.systemd.targets.suspend.enable
      && c.services.displayManager.gdm.enable
      && c.services.opensnitch.enable
      && c.boot.initrd.network.ssh.enable
      && c.boot.initrd.network.ssh.port == 2222
      # a path on /persist, which the boot loader appends; a store path would put the key in the store
      && c.boot.initrd.secrets == { "/etc/ssh/boot-key" = (import ../modules/_initrd-ssh-key.nix).boot; }
      && c.boot.loader.supportsInitrdSecrets
      && !(lib.any (lib.hasPrefix "/.initrd-secrets") (lib.attrNames c.boot.initrd.systemd.contents));
  };
  missing = lib.filter (name: !(expect.${name} (host name))) hosts;
  # the desktop hosts come from checks.nix
  handheld =
    c:
    c.services.handheld-daemon.enable
    && c.services.handheld-daemon.adjustor.enable
    && !lib.elem "acpi_call" c.boot.kernelModules
    && lib.elem "/etc/hhd" (map (d: d.directory) c.preservation.preserveAt."/persist".directories)
    && c.services.logind.settings.Login.HandlePowerKey == "suspend"
    && c.boot.initrd.systemd.services ? handheld-input
    && c.services.greetd.enable
    && !c.services.displayManager.plasma-login-manager.enable
    # nobody in Game Mode to answer it
    && !c.services.opensnitch.enable
    && lib.elem "hid_steam.lizard_mode=0" c.boot.kernelParams
    && lib.any (lib.hasPrefix "C /etc/hhd/state.yml ") c.systemd.tmpfiles.rules
    && c.environment.etc ? "ephemeral/handheld-buttons"
    # Remote Play's ports stay closed until steamRemotePlay opens them
    && !c.programs.steam.remotePlay.openFirewall
    && c.environment.etc ? "ephemeral/update-at-boot";
  notHandheld =
    c:
    !c.services.handheld-daemon.enable
    && !(c.boot.initrd.systemd.services ? handheld-input)
    && !lib.elem "uinput" c.boot.initrd.kernelModules
    && !lib.elem "hid_steam.lizard_mode=0" c.boot.kernelParams;
  # handheld-full as each device
  as =
    device:
    (config.flake.nixosConfigurations.handheld-full.extendModules {
      modules = [ { ephemeral.settings.handheld = lib.mkForce device; } ];
    }).config;
  kernel = c: c.boot.kernelPackages.kernel.version;
  devices =
    let
      deck = as "steamdeck";
      other = host "handheld-full";
    in
    # Handheld Daemon doesn't support the Deck, whose controller Steam reads itself
    !deck.services.handheld-daemon.enable
    && !lib.any (lib.hasPrefix "C /etc/hhd/state.yml ") deck.systemd.tmpfiles.rules
    # the Deck's back buttons type at the disk prompt only on a Deck
    && lib.hasInfix "L4\t1" deck.environment.etc."ephemeral/handheld-buttons".text
    && !lib.hasInfix "L4" other.environment.etc."ephemeral/handheld-buttons".text
    && kernel deck == kernel other
    # asus-armoury came in 6.19
    && lib.versionAtLeast (kernel (as "rog-ally")) "6.19"
    && lib.versionAtLeast (kernel (as "legion-go")) "6.19";
  refused =
    name: change:
    !(builtins.tryEval
      (config.flake.nixosConfigurations.${name}.extendModules {
        modules = [ { ephemeral.settings = lib.mapAttrs (_: lib.mkForce) change; } ];
      }).config.system.build.toplevel.drvPath
    ).success;
  # the TPM would give the key to anything booted with the PIN, so this has to stay refused
  tpmWithoutSecureBoot =
    (builtins.tryEval
      (config.flake.nixosConfigurations.feat-all.extendModules {
        modules = [ { ephemeral.settings.secureBoot = lib.mkForce false; } ];
      }).config.system.build.toplevel.drvPath
    ).success;
in
{
  ephemeral.hosts = lib.genAttrs hosts (name: {
    root = ../tests/${name};
  });

  perSystem =
    { pkgs, ... }:
    {
      checks.features-eval =
        assert lib.assertMsg (
          missing == [ ]
        ) "these hosts don't have the feature they switch on: ${toString missing}";
        assert lib.assertMsg (!tpmWithoutSecureBoot) "tpmUnlock without secureBoot was accepted";
        assert lib.assertMsg (refused "feat-server" {
          sshKeys = [ ];
        }) "a server without sshKeys was accepted";
        assert lib.assertMsg (refused "none-full" {
          server = false;
        }) "desktop none without server was accepted";
        assert lib.assertMsg
          (
            let
              picked = (host "none-full").ephemeral.pickedApps;
            in
            lib.elem "htop" picked && !lib.elem "firefox" picked
          )
          "without a desktop, the terminal apps ticked by default should be picked, and the desktop ones not";
        assert lib.assertMsg
          (lib.all (n: handheld (host n)) [
            "handheld-full"
            "handheld-minimal"
          ])
          "a handheld is missing Handheld Daemon, its kept settings and lights, the power button, the controller unlock or its button list, or has OpenSnitch";
        assert lib.assertMsg devices
          "a Steam Deck should have no Handheld Daemon and keep this config's kernel, and an Ally or a Legion Go get a kernel with their drivers, 6.19 or newer";
        assert lib.assertMsg (lib.all (n: notHandheld (host n)) [
          "plasma-full"
          "plasma-minimal"
          "feat-all"
        ]) "a machine that isn't a handheld has the handheld's services";
        pkgs.writeText "features-eval" (
          builtins.unsafeDiscardStringContext (
            lib.concatMapStrings (name: (host name).system.build.toplevel.drvPath + "\n") hosts
          )
        );
    };
}
