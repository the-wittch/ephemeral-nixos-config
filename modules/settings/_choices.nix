# The settings picked from a menu, in the order the menus show them: the value settings.json
# gets, the name and line the menu shows, and a tag for one that's still settling. _rules.nix
# takes the allowed values from here; the installer's screens and plain prompts and
# ephemeral-setup build their menus from it.
{
  desktop = [
    {
      value = "plasma";
      label = "Plasma";
      description = "KDE Plasma 6, tiling with Krohnkite, colours from the wallpaper";
    }
    {
      value = "gnome";
      label = "GNOME";
      description = "GNOME much as it comes, with tray icons and Caffeine";
    }
    {
      value = "niri";
      label = "niri";
      description = "scrolling tiles, with the Noctalia shell";
    }
    {
      value = "umbriel";
      label = "Umbriel";
      description = "a new compositor, with the Noctalia shell";
      tag = "may change";
    }
    {
      value = "none";
      label = "None";
      description = "no screen, for a server reached over SSH";
    }
    {
      value = "handheld";
      label = "Handheld";
      description = "Steam's Game Mode and Plasma, for a Steam Deck or ROG Ally";
      tag = "beta";
    }
  ];
  nvidia = [
    {
      value = "open";
      label = "open";
      description = "RTX 20 / GTX 16 series and newer";
    }
    {
      value = "legacy";
      label = "legacy";
      description = "GTX 900 / GTX 10 series";
    }
    {
      value = "none";
      label = "none";
      description = "keep the open-source nouveau driver";
    }
  ];
  profile = [
    {
      value = "full";
      label = "Full";
      description = "dotfiles, theme, snapshots, OpenSnitch, Syncthing and more";
    }
    {
      value = "minimal";
      label = "Small";
      description = "a plain desktop now; run ephemeral-setup for the rest later";
    }
  ];
  # Control D is in the same menu, but it's useControlD with encryptedDns left at none
  encryptedDns = [
    {
      value = "none";
      label = "The network's DNS";
      description = "not encrypted; whatever the network hands out";
    }
    {
      value = "cloudflare";
      label = "Cloudflare";
      description = "DNS over TLS, no filtering";
    }
    {
      value = "quad9";
      label = "Quad9";
      description = "DNS over TLS, blocks known malware domains";
    }
    {
      value = "adguard";
      label = "AdGuard";
      description = "DNS over TLS, blocks ads and trackers";
    }
    {
      value = "controld";
      label = "Control D";
      description = "DNS over TLS to your own Control D resolver";
      useControlD = true;
    }
    {
      value = "custom";
      label = "Other";
      description = "DNS over TLS to servers you give, such as Mullvad or one at home";
    }
  ];
}
