{
  flake.modules.homeManager.extras =
    { lib, pkgs, ... }:
    {
      home.packages = [ pkgs.fetch ];

      xdg.configFile."fetch/logo.txt".source = ./logo.txt;
      xdg.configFile."fetch/config".text = ''
        os
        kernel
        uptime
        packages
        shell
        wm
        terminal
        ---
        cpu
        gpu
        memory
        swap
        disk
        label_color=blue
        spin=y
      '';

      # spins in each new Ghostty window until a key is pressed; the key goes on to the prompt.
      # The variable keeps shells started from that one (nix develop, direnv) quiet.
      programs.zsh.initContent = lib.mkOrder 1500 ''
        if [[ $TERM_PROGRAM == ghostty && -z $EPHEMERAL_FETCHED ]] && (( $+commands[fetch] )); then
          export EPHEMERAL_FETCHED=1
          fetch
        fi
      '';
    };
}
