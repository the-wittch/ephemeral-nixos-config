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
            defaultOn = mkOption {
              type = types.listOf (
                types.enum [
                  "gnome"
                  "plasma"
                  "niri"
                  "umbriel"
                  "handheld"
                ]
              );
              default = [ ];
              description = "Picked unless apps.json has -<name>, as with default, but only on these desktops.";
            };
            desktops = mkOption {
              type = types.listOf (
                types.enum [
                  "gnome"
                  "plasma"
                  "niri"
                  "umbriel"
                  "handheld"
                ]
              );
              default = [ ];
              description = "Only offered and installed on these desktops; empty for all of them.";
            };
            steamShortcuts = mkOption {
              type = types.listOf (
                types.submodule {
                  options = {
                    name = mkOption { type = text; };
                    args = mkOption {
                      type = types.str;
                      default = "";
                      description = "Added after `flatpak run <id>`.";
                    };
                  };
                }
              );
              default = [ ];
              description = "On a handheld, non-Steam games in Steam for this Flatpak, so it can be started from Game Mode.";
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
