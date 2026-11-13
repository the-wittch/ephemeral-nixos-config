{ config, lib, ... }:
let
  # each optional feature on its own, and all of them at once; the desktop hosts switch none on
  hosts = [
    "feat-all"
    "feat-laptop"
    "feat-network"
    "feat-nvidia-legacy"
    "feat-nvidia-open"
    "feat-pass"
  ];
  host = name: config.flake.nixosConfigurations.${name}.config;
  # evaluating them catches option renames; this checks each feature is really switched on
  expect = {
    feat-all = c: c.hardware.nvidia.open && c.services.tailscale.enable && c.fileSystems ? "/mnt/files";
    feat-laptop = c: c.services.fprintd.enable && c.services.upower.enable;
    feat-network = c: c.services.tailscale.enable && !c.services.opensnitch.enable;
    feat-nvidia-legacy = c: !c.hardware.nvidia.open && c.services.xserver.videoDrivers == [ "nvidia" ];
    feat-nvidia-open = c: c.hardware.nvidia.open;
    feat-pass =
      c:
      c.environment.sessionVariables.PASS_SSH_VAULT == "Work keys"
      && c.ephemeral.passCli.pname == "pass-cli";
  };
  missing = lib.filter (name: !(expect.${name} (host name))) hosts;
in
{
  ephemeral.hosts = lib.genAttrs hosts (name: {
    root = ../tests/${name};
  });

  perSystem =
    { pkgs, ... }:
    {
      checks.features-eval =
        assert lib.assertMsg (
          missing == [ ]
        ) "these hosts don't have the feature they switch on: ${toString missing}";
        pkgs.writeText "features-eval" (
          builtins.unsafeDiscardStringContext (
            lib.concatMapStrings (name: (host name).system.build.toplevel.drvPath + "\n") hosts
          )
        );
    };
}
