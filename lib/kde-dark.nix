{ lib }:

let
  sections = [
    {
      name = "General";
      attrs.ColorScheme = "BreezeDark";
    }
    {
      name = "KDE";
      attrs = {
        LookAndFeelPackage = "org.kde.breezedark.desktop";
        widgetStyle = "Breeze";
      };
    }
    {
      name = "Icons";
      attrs.Theme = "breeze-dark";
    }
  ];

  ini =
    lib.concatMapStringsSep "\n" (section: ''
      [${section.name}]
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "${name}=${value}") section.attrs)}
    '') sections
    + "\n";

  kwriteScript =
    kwriteconfig:
    lib.concatMapStrings (
      section:
      lib.concatStrings (
        lib.mapAttrsToList (name: value: ''
          run ${lib.escapeShellArgs [
            kwriteconfig
            "--file"
            "kdeglobals"
            "--group"
            section.name
            "--key"
            name
            value
          ]}
        '') section.attrs
      )
    ) sections;
in
{
  inherit ini kwriteScript;
}
