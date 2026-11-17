{
  flake.modules.nixos.tpm-unlock =
    { config, ... }:
    {
      assertions = [
        {
          # with Secure Boot off, anything booted can ask the TPM, so the PIN alone would guard the disk
          assertion = config.ephemeral.settings.secureBoot;
          message = "tpmUnlock needs secureBoot on first: see docs/security.md.";
        }
      ];

      # the TPM first, then the passphrase when it can't unlock
      boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = [ "tpm2-device=auto" ];

      # ephemeral-doctor checks the firmware's state when this is here
      environment.etc."ephemeral/tpm-unlock".text = "";
    };
}
