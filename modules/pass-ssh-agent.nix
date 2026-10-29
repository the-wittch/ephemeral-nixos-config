{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos.passSshAgent =
    { config, ... }:
    let
      passCli = "${config.ephemeral.passCli}/bin/pass-cli";
    in
    {
      home-manager.sharedModules = [ hm.passSshAgent ];

      services.opensnitch.rules.pass-cli = {
        name = "pass-cli";
        enabled = true;
        action = "allow";
        duration = "always";
        operator = {
          type = "list";
          operand = "list";
          list = [
            {
              type = "simple";
              sensitive = false;
              operand = "process.path";
              data = passCli;
            }
            {
              type = "regexp";
              sensitive = false;
              operand = "dest.host";
              data = "^([a-z0-9-]+\\.)*proton\\.me$";
            }
          ];
        };
      };
    };

  flake.modules.homeManager.passSshAgent =
    {
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      passCli = "${osConfig.ephemeral.passCli}/bin/pass-cli";
      vault = lib.replaceStrings [ "%" ] [ "%%" ] (
        lib.escapeShellArg osConfig.ephemeral.settings.passSshVault
      );
      dir = "proton-pass-ssh-agent";
      socket = "${dir}/agent.sock";
    in
    {
      systemd.user.services.proton-pass-ssh-agent = {
        Unit = {
          Description = "Proton Pass SSH agent";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
          StartLimitIntervalSec = 300;
          StartLimitBurst = 3;
        };
        Service = {
          # logged out of pass-cli: skip instead of failing. info prints the account email
          ExecCondition = "${pkgs.runtimeShell} -c '${passCli} info >/dev/null 2>&1'";
          ExecStart = "${passCli} ssh-agent start --vault-name ${vault} --socket-path %t/${socket}";
          # the agent leaves its socket behind on exit; systemd removes this directory instead
          RuntimeDirectory = dir;
          RuntimeDirectoryMode = "0700";
          Restart = "on-failure";
          RestartSec = 30;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      # the desktop's own agent stays in use while this one isn't running
      programs.zsh.envExtra = ''
        if [ -S "$XDG_RUNTIME_DIR/${socket}" ]; then
          export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/${socket}"
        fi
      '';

      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        settings."Match exec \"test -S $XDG_RUNTIME_DIR/${socket}\"".IdentityAgent =
          "\${XDG_RUNTIME_DIR}/${socket}";
      };
    };
}
