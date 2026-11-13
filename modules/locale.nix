{
  flake.modules.nixos.base =
    { config, ... }:
    let
      settings = config.ephemeral.settings;
    in
    {
      time.timeZone = settings.timeZone;
      i18n.defaultLocale = settings.locale;

      # the console uses it too, so the LUKS passphrase is typed with the same layout
      services.xserver.xkb = {
        layout = settings.keyboardLayout;
        variant = settings.keyboardVariant;
      };
      console.useXkbConfig = true;
    };
}
