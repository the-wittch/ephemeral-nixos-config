{ lib }:

lib.generators.toINI { } {
  General.ColorScheme = "BreezeDark";
  KDE = {
    LookAndFeelPackage = "org.kde.breezedark.desktop";
    widgetStyle = "Breeze";
  };
  Icons.Theme = "breeze-dark";
}
