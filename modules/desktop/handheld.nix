# A Steam Deck or ROG Ally: Steam's Game Mode at boot, Plasma as desktop mode, the disk unlocked
# with the controller. In beta: designed on a Deck and an Ally X, not yet run on one.
# The same system on every handheld: what differs between them, Handheld Daemon finds at run time.
{ config, ... }:
let
  inherit (config.ephemeral.aspects) nixos;

  handheld =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      user = config.ephemeral.settings.username;

      session = pkgs.writeShellApplication {
        name = "ephemeral-handheld-session";
        text = ''
          plasma_run=${pkgs.kdePackages.plasma-workspace}/libexec/plasma-dbus-run-session-if-needed
        ''
        + builtins.readFile ../handheld/_session.sh;
      };

      # Steam calls these SteamOS commands. Updates come from ephemeral update, so the update
      # ones say there's nothing to do.
      steamos = [
        (pkgs.writeShellApplication {
          name = "steamos-session-select";
          runtimeInputs = [ pkgs.dbus ];
          text = builtins.readFile ../handheld/_session-select.sh;
        })
        # 7 is SteamOS's "no update available"
        (pkgs.writeShellScriptBin "steamos-update" "exit 7")
        (pkgs.writeShellScriptBin "steamos-select-branch" ''
          [[ ''${1:-} == -c ]] && echo rel
          exit 0
        '')
      ];

      returnToGameMode = pkgs.makeDesktopItem {
        name = "return-to-game-mode";
        desktopName = "Return to Game Mode";
        exec = "steamos-session-select gamescope";
        icon = "steam";
        categories = [ "System" ];
      };
    in
    {
      imports = [ nixos.handheld-unlock ];

      ephemeral.unfreePackages = [
        "steam"
        "steam-unwrapped"
      ];
      programs.steam = {
        enable = true;
        gamescopeSession = {
          enable = true;
          # what makes Steam show its SteamOS menus, Switch to Desktop among them
          steamArgs = [
            "-gamepadui"
            "-steamos3"
            "-steampal"
            "-steamdeck"
            "-pipewire-dmabuf"
          ];
        };
      };

      # Logged in at boot with no password: the disk passphrase is what guards the device, as
      # on any install here.
      services.displayManager.plasma-login-manager.enable = false;
      services.greetd = {
        enable = true;
        settings = {
          initial_session = {
            inherit user;
            command = lib.getExe session;
          };
          # only if the session loop itself ends
          default_session = {
            inherit user;
            command = lib.getExe session;
          };
        };
      };

      # the Ally's controller, back buttons, power limits and stick lights
      services.handheld-daemon = {
        enable = true;
        inherit user;
        # The Ally's power limits go through asus-wmi. acpi_call, which other handhelds need, is an
        # out-of-tree module that lets root run any ACPI method, so it stays out.
        adjustor = {
          enable = true;
          loadAcpiCallModule = false;
        };
      };
      # its settings, profiles and API token
      preservation.preserveAt."/persist".directories = [ "/etc/hhd" ];

      # Handheld Daemon leaves the Deck's power button alone, and logind's default is to power off
      services.logind.settings.Login = {
        HandlePowerKey = "suspend";
        HandlePowerKeyLongPress = "poweroff";
      };

      # The lock screen wants the login password, which the controller can't type there. The
      # disk passphrase is what guards a handheld that's off; one that's asleep isn't locked.
      environment.etc."xdg/kscreenlockerrc".text = ''
        [Daemon]
        Autolock=false
        LockOnResume=false
      '';
      # Steam in the background on the desktop is what makes the controller a mouse and gives it
      # an on-screen keyboard (Steam and X together)
      environment.etc."xdg/autostart/steam-silent.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Steam
        Exec=${lib.getExe config.programs.steam.package} -silent
        Icon=steam
        Terminal=false
        OnlyShowIn=KDE;
      '';

      environment.systemPackages = steamos ++ [ returnToGameMode ];
    };
in
{
  flake.modules.nixos.handheld.imports = [
    nixos.plasma
    handheld
  ];
  flake.modules.nixos."minimal-handheld".imports = [
    nixos."minimal-plasma"
    handheld
  ];
}
