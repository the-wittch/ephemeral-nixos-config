let
  # fonts have to go in fonts.packages, not the package list, for apps to find them
  nerd = label: font: description: {
    inherit label description;
    category = "Fonts";
    nixos =
      { pkgs, ... }:
      {
        fonts.packages = [ pkgs.nerd-fonts.${font} ];
      };
  };
in
{
  ephemeral.apps = {
    nerd-jetbrains-mono =
      nerd "JetBrains Mono Nerd Font" "jetbrains-mono"
        "the system's code font with icons added";
    nerd-fira-code = nerd "Fira Code Nerd Font" "fira-code" "code font with ligatures";
    nerd-hack = nerd "Hack Nerd Font" "hack" "plain and very readable";
    nerd-meslo =
      nerd "Meslo Nerd Font" "meslo-lg"
        "the font Powerlevel10k and other prompt themes recommend";
    nerd-caskaydia-cove =
      nerd "CaskaydiaCove Nerd Font" "caskaydia-cove"
        "Cascadia Code from Windows Terminal";
    nerd-sauce-code-pro = nerd "SauceCodePro Nerd Font" "sauce-code-pro" "Adobe's Source Code Pro";
    nerd-iosevka = nerd "Iosevka Nerd Font" "iosevka" "narrow so more fits on a line";
    nerd-ubuntu-mono = nerd "Ubuntu Mono Nerd Font" "ubuntu-mono" "Ubuntu's terminal font";
    nerd-victor-mono = nerd "Victor Mono Nerd Font" "victor-mono" "cursive italics";
    nerd-commit-mono = nerd "Commit Mono Nerd Font" "commit-mono" "neutral and quiet";
    nerd-geist-mono = nerd "Geist Mono Nerd Font" "geist-mono" "Vercel's code font";
    nerd-symbols =
      nerd "Nerd Font symbols only" "symbols-only"
        "just the icons to use alongside any font";
  };
}
