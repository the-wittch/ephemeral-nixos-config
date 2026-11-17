{ lib, flakeRoot }:

let
  readData = import ./_read-data.nix;

  # a missing file must not become username nixuser
  fromSettings = readData (flakeRoot + "/settings") (throw ''
    settings.json is not in this flake.
    Installed machine:
      sudo nixos-rebuild switch --flake path:/persist/etc/nixos#nixos
    Or copy /persist/etc/nixos/settings.json next to flake.nix.
  '');

  # the pass file can't turn itself on
  usePass = fromSettings.usePassSettings or false;

  # Only what settings-from-pass writes, so the file can't turn off OpenSnitch or the like. The
  # Proton Pass item is trusted for these, except that it can only turn Control D on: someone who
  # can edit the item shouldn't be able to send DNS back to the network unencrypted.
  passKeys =
    let
      pass = import ./_pass-keys.nix;
    in
    lib.genAttrs (pass.strings ++ pass.bools ++ [ "useControlD" ]) (_: null);
  fromPass =
    let
      read = builtins.intersectAttrs passKeys (readData (flakeRoot + "/settings.from-pass") { });
    in
    if !usePass then
      { }
    else if (read.useControlD or null) == false then
      removeAttrs read [ "useControlD" ]
    else
      read;

  merged =
    if !(fromSettings ? username) || fromSettings.username == "" then
      throw "settings must set username"
    else
      fromSettings // fromPass;
  # old keys still load, so an upgrade doesn't fail on a settings.json nobody has touched yet
  removed = {
    allowUnfree = "unfree packages are listed in ephemeral.unfreePackages";
    useChezmoi = "chezmoi was dropped in v3.0.0; Home Manager writes the dotfiles";
    chezmoiRepo = "chezmoi was dropped in v3.0.0";
    chezmoiRev = "chezmoi was dropped in v3.0.0";
  };
  stale = lib.filter (key: merged ? ${key}) (lib.attrNames removed);
  merged' =
    if (merged.controldResolver or "") != "" then
      throw ''
        Don't put controldResolver in settings.
        Write the Control D id to /persist/etc/controld-resolver and set useControlD = true.
      ''
    else
      lib.foldl' (
        acc: key:
        lib.warn "settings.${key} is no longer used (${removed.${key}}). Delete it from settings.json." acc
      ) merged stale;
  evaluated = lib.evalModules {
    modules = [
      ./_schema.nix
      {
        _file = toString (flakeRoot + "/settings.json");
        ephemeral.settings = removeAttrs merged' ([ "controldResolver" ] ++ lib.attrNames removed);
      }
    ];
  };
in
evaluated.config.ephemeral.settings
