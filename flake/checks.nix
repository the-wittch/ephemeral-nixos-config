{
  config,
  inputs,
  lib,
  ...
}:
let
  nixos = config.flake.nixosConfigurations.nixos;
  withExtras = nixos.extendModules { modules = [ config.ephemeral.aspects.nixos.extras ]; };
  machine =
    (config.flake.lib.mkFlake {
      inputs.self = {
        outPath = ../tests/machine;
        inputs = { };
      };
      root = ../tests/machine;
    }).nixosConfigurations.nixos;
  withPassSshAgent = nixos.extendModules {
    modules = [ config.ephemeral.aspects.nixos.passSshAgent ];
  };
  # aspects import what they need, so these work without the full profile around them
  standalone = inputs.nixpkgs.lib.nixosSystem {
    modules = with config.ephemeral.aspects.nixos; [
      pc
      minimal
      minimal-plasma
      passSshAgent
      extras
      ../tests/plasma-minimal/hardware-configuration.nix
      {
        ephemeral.settings = {
          username = "alice";
          diskDevice = "/dev/vda";
        };
      }
    ];
  };
  withAllApps = nixos.extendModules {
    modules = [
      { ephemeral.pickedApps = lib.attrNames config.ephemeral.apps; }
    ]
    ++ map (app: app.nixos) (lib.attrValues config.ephemeral.apps);
  };
  options = lib.attrNames nixos.options.ephemeral.settings;
  # username has none: settings.json has to set it
  defaults = lib.mapAttrs (_: option: option.default) (
    lib.filterAttrs (_: option: option ? default) nixos.options.ephemeral.settings
  );
  example = lib.importJSON ../settings.example.json;
  differ = lib.filter (name: example.${name} or null != defaults.${name}) (lib.attrNames defaults);
  hostsUnderTest = [
    "gnome-full"
    "gnome-minimal"
    "niri-full"
    "niri-minimal"
    "plasma-full"
    "plasma-minimal"
    "umbriel-full"
    "umbriel-minimal"
  ];
  warningsOf = name: lib.concatStrings config.flake.nixosConfigurations.${name}.config.warnings;
  minimalWarns = warningsOf "plasma-minimal";
  hostDrvs = lib.concatMapStrings (
    name: config.flake.nixosConfigurations.${name}.config.system.build.toplevel.drvPath + "\n"
  ) hostsUnderTest;

  # A desktop's full and minimal variants have to agree on these, apart from the differences
  # listed below. "plasma:..." allows a difference for one desktop, a bare name for all of them.
  parityOptions = [
    "services.xserver.enable"
    "services.displayManager.gdm.enable"
    "services.displayManager.sddm.enable"
    "services.displayManager.plasma-login-manager.enable"
    "services.displayManager.noctalia-greeter.enable"
    "services.displayManager.defaultSession"
    "services.greetd.enable"
    "services.desktopManager.plasma6.enable"
    "services.desktopManager.gnome.enable"
    "programs.niri.enable"
    "programs.umbriel.enable"
    "services.gnome.gnome-keyring.enable"
    "services.gnome.gnome-initial-setup.enable"
    "security.pam.services.plasmalogin.kwallet.enable"
    "security.pam.services.greetd.enableGnomeKeyring"
    "security.pam.services.gdm-password.enableGnomeKeyring"
    "services.gvfs.enable"
    "xdg.portal.enable"
    "boot.plymouth.theme"
  ];
  allowedDrift = {
    "boot.plymouth.theme" = "Stylix, which only the full profile has, themes the boot splash";
    "persist:/var/lib/opensnitch" = "OpenSnitch is a full-profile option";
    "gnome:services.gnome.gnome-initial-setup.enable" =
      "no difference in practice: for an existing user it only marks itself done and exits (GNOME 40 and later)";
  };
  drift =
    desktop:
    let
      host = profile: config.flake.nixosConfigurations."${desktop}-${profile}".config;
      full = host "full";
      minimal = host "minimal";
      get = c: name: lib.attrByPath (lib.splitString "." name) null c;
      persisted = c: map (d: d.directory) c.environment.persistence."/persist".directories;
      differs = lib.filter (name: get full name != get minimal name) parityOptions;
      onlyOne =
        lib.subtractLists (persisted full) (persisted minimal)
        ++ lib.subtractLists (persisted minimal) (persisted full);
    in
    map (item: { inherit desktop item; }) (differs ++ map (d: "persist:${d}") onlyOne);
  allDrift = lib.concatMap drift [
    "gnome"
    "niri"
    "plasma"
    "umbriel"
  ];
  # for .github/drv-diff.sh: a refactor that only moves code leaves all of these unchanged
  systemDrvs =
    lib.mapAttrs (
      _: host:
      let
        drv = builtins.tryEval host.config.system.build.toplevel.drvPath;
      in
      # nixos needs a settings.json, which a fresh clone doesn't have
      if drv.success then drv.value else null
    ) config.flake.nixosConfigurations
    // {
      mkflake-machine = machine.config.system.build.toplevel.drvPath;
    };

  allowed = d: allowedDrift ? ${d.item} || allowedDrift ? "${d.desktop}:${d.item}";
  unexplained = map (d: "${d.desktop}: ${d.item}") (lib.filter (d: !allowed d) allDrift);
  stale = lib.filter (key: !lib.any (d: key == d.item || key == "${d.desktop}:${d.item}") allDrift) (
    lib.attrNames allowedDrift
  );
in
{
  ephemeral.hosts = lib.genAttrs hostsUnderTest (name: {
    root = ../tests/${name};
  });

  perSystem =
    { config, pkgs, ... }:
    {
      legacyPackages.systemDrvs = systemDrvs;

      checks = {
        config-eval = pkgs.runCommand "config-eval" { } ''
          echo ${lib.escapeShellArg nixos.config.networking.hostName} > "$out"
        '';
        scripts = pkgs.linkFarmFromDrvs "scripts" (
          lib.attrValues (removeAttrs config.packages [ "pass-cli" ])
        );
        extras-eval = pkgs.writeText "extras-eval" (
          builtins.unsafeDiscardStringContext withExtras.config.system.build.toplevel.drvPath
        );
        aspect-deps = pkgs.writeText "aspect-deps" (
          builtins.unsafeDiscardStringContext standalone.config.system.build.toplevel.drvPath
        );
        pass-ssh-agent-eval = pkgs.writeText "pass-ssh-agent-eval" (
          builtins.unsafeDiscardStringContext withPassSshAgent.config.system.build.toplevel.drvPath
        );
        mkflake-eval =
          assert lib.assertMsg (
            machine.config.environment.etc ? ephemeral-fixture
          ) "lib.mkFlake didn't load the machine's own modules/";
          pkgs.writeText "mkflake-eval" (
            builtins.unsafeDiscardStringContext (
              machine.config.system.build.toplevel.drvPath + "\n" + machine.config.system.build.vm.drvPath
            )
          );
        desktops-eval =
          assert lib.assertMsg (lib.hasInfix "extras, usePassSshAgent: only on the full profile" minimalWarns)
            "profile minimal didn't warn about full-only settings:\n${minimalWarns}";
          assert lib.assertMsg (
            !lib.hasInfix "only on the full profile" (warningsOf "niri-full")
          ) "profile full warned about full-only settings";
          pkgs.writeText "desktops-eval" (builtins.unsafeDiscardStringContext hostDrvs);
        desktop-parity =
          assert lib.assertMsg (unexplained == [ ]) ''
            full and minimal differ here. Fix it, or add it to allowedDrift in flake/checks.nix with the reason:
              ${lib.concatStringsSep "\n  " unexplained}
          '';
          assert lib.assertMsg (stale == [ ]) ''
            allowedDrift lists differences that are gone; remove them:
              ${lib.concatStringsSep "\n  " stale}
          '';
          pkgs.runCommand "desktop-parity" { } "touch $out";
        apps-eval = pkgs.writeText "apps-eval" (
          builtins.unsafeDiscardStringContext withAllApps.config.system.build.toplevel.drvPath
        );
        settings-example =
          assert lib.assertMsg (options == lib.attrNames example && differ == [ ]) ''
            settings.example.json has to list every setting with its default.
              missing: ${toString (lib.subtractLists (lib.attrNames example) options)}
              unknown: ${toString (lib.subtractLists options (lib.attrNames example))}
              different from the defaults in modules/settings/_schema.nix:${toString differ}
          '';
          pkgs.runCommand "settings-example" { } "touch $out";
      };
    };
}
