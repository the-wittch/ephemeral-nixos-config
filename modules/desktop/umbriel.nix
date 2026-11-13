{ config, ... }:
let
  nixos = config.ephemeral.aspects.nixos;

  umbriel =
    { config, pkgs, ... }:
    let
      settings = config.ephemeral.settings;
      package = config.programs.umbriel.package;

      # Umbriel's own show_cheatsheet opens it at every start; this opens it at the first login only
      cheatsheetOnce = pkgs.writeShellScript "umbriel-cheatsheet-once" ''
        marker=''${XDG_STATE_HOME:-$HOME/.local/state}/ephemeral/umbriel-cheatsheet-shown
        [ -e "$marker" ] && exit 0
        ${package}/bin/umbriel msg cheatsheet-open || exit 0
        mkdir -p "''${marker%/*}" && touch "$marker"
      '';

      umbrielConfig = pkgs.writeText "umbriel-config.toml" ''
        [include]
        files = ["${package}/share/umbriel/config.toml"]

        [include.optional]
        files = ["~/.config/umbriel/local.toml"]

        [general]
        show_cheatsheet = false
        autostart = ["${cheatsheetOnce}"]

        [input.keyboard]
        layout = "${settings.keyboardLayout}"
        variant = "${settings.keyboardVariant}"

        [keybinds]
        "Mod+Return" = { action = "spawn:ghostty", repeat = false }
        "Mod+slash" = { action = "cheatsheet-toggle", repeat = false }
      '';
    in
    {
      programs.umbriel.enable = true;

      # Umbriel's own defaults first; tables merge, so only these keys change.
      # ~/.config/umbriel/local.toml is for your own changes.
      environment.etc."xdg/umbriel/config.toml".source =
        pkgs.runCommand "umbriel-config.toml" { nativeBuildInputs = [ package ]; }
          ''
            HOME=$TMPDIR umbriel config validate -c ${umbrielConfig}
            cp ${umbrielConfig} $out
          '';
    };
in
{
  flake.modules.nixos.umbriel.imports = [
    umbriel
    nixos.noctalia
  ];

  flake.modules.nixos."minimal-umbriel".imports = [
    umbriel
    nixos.noctalia-base
  ];
}
