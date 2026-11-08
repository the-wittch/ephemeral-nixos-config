{ config, ... }:
let
  nixos = config.flake.modules.nixos;

  umbriel =
    { config, ... }:
    let
      settings = config.ephemeral.settings;
    in
    {
      programs.umbriel.enable = true;

      # Umbriel's own defaults first; tables merge, so only these keys change.
      # ~/.config/umbriel/local.toml is for your own changes.
      environment.etc."xdg/umbriel/config.toml".text = ''
        [include]
        files = ["${config.programs.umbriel.package}/share/umbriel/config.toml"]

        [include.optional]
        files = ["~/.config/umbriel/local.toml"]

        [input.keyboard]
        layout = "${settings.keyboardLayout}"
        variant = "${settings.keyboardVariant}"

        [keybinds]
        "Mod+Return" = { action = "spawn:ghostty", repeat = false }
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
