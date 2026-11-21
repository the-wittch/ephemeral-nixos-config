{ lib, ... }:
let
  inherit (lib) mkOption types;
  text = types.strMatching "[^,]+";
in
{
  options.ephemeral.apps = mkOption {
    default = { };
    description = "Apps ephemeral-apps offers. Picks are kept in apps.json next to settings.json.";
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            label = mkOption {
              type = text;
              default = name;
            };
            category = mkOption { type = types.enum (import ./_categories.nix); };
            description = mkOption { type = text; };
            package = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Attribute path in pkgs, e.g. kdePackages.kdenlive.";
            };
            flatpak = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Flathub id, installed for the user.";
            };
            unfree = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Names for ephemeral.unfreePackages.";
            };
            default = mkOption {
              type = types.bool;
              default = false;
              description = "Picked unless apps.json has -<name>, so an older apps.json keeps it.";
            };
            desktops = mkOption {
              type = types.listOf (
                types.enum [
                  "gnome"
                  "plasma"
                  "niri"
                  "umbriel"
                ]
              );
              default = [ ];
              description = "Only offered and installed on these desktops; empty for all of them.";
            };
            warn = mkOption {
              type = types.nullOr text;
              default = null;
              description = "Shown before the app is added.";
            };
            nixos = mkOption {
              type = types.deferredModule;
              default = { };
            };
            homeManager = mkOption {
              type = types.deferredModule;
              default = { };
            };
          };
        }
      )
    );
  };
}
