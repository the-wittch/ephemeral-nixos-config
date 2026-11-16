{
  flake.modules.nixos.secure-boot =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      esp = config.boot.loader.efi.efiSysMountPoint;
      sbctl = lib.getExe config.boot.loader.limine.secureBoot.sbctl;
      setupMode = "/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c";
    in
    {
      boot.loader.limine.secureBoot = {
        enable = true;
        # made on the first rebuild, in /var/lib/sbctl, which boot.nix keeps on /persist
        autoGenerateKeys = true;
      };

      # Limine's install runs sbctl without checking that it worked, and enrolls keys only on the
      # rebuild that makes them. A Limine nobody signed doesn't boot once Secure Boot is on, so
      # that's checked here, and the keys go into the firmware whenever it's in Setup Mode.
      boot.loader.limine.extraInstallCommands = lib.mkAfter ''
        signed=0
        for efi in ${esp}/efi/limine/BOOTX64.EFI ${esp}/efi/boot/BOOTX64.EFI; do
          [[ -e $efi ]] || continue
          if ! ${pkgs.sbsigntool}/bin/sbverify --cert /var/lib/sbctl/keys/db/db.pem "$efi" >/dev/null 2>&1; then
            echo "secureBoot: $efi isn't signed with this machine's key; sbctl's output is above" >&2
            exit 1
          fi
          signed=1
        done
        if ((!signed)); then
          echo "secureBoot: no Limine on ${esp} to check" >&2
          exit 1
        fi

        # The folder is mounted from /persist when the new system starts, which is after this.
        # Keys enrolled from anywhere else would be gone at the next boot, leaving a firmware
        # that only trusts keys nobody has.
        if ! ${pkgs.util-linux}/bin/mountpoint -q /var/lib/sbctl; then
          echo "secureBoot: /var/lib/sbctl isn't on /persist yet, so the keys aren't enrolled this time." >&2
          echo "Once this rebuild has finished, run ephemeral-update once more to enroll them." >&2
        elif [[ $(${pkgs.coreutils}/bin/od -An -tu1 -j4 -N1 ${setupMode} 2>/dev/null | ${pkgs.coreutils}/bin/tr -d ' ') == 1 ]]; then
          # Microsoft's keys and the firmware's own stay trusted, for docks, graphics cards and
          # firmware updates that are signed with them. sbctl 0.18 means to skip a default list
          # the firmware doesn't have, but stops instead, so only the ones it has are named.
          builtin=()
          for list in db KEK; do
            if [[ -e /sys/firmware/efi/efivars/''${list}Default-8be4df61-93ca-11d2-aa0d-00e098032b8c ]]; then
              builtin+=("$list")
            fi
          done
          if ((''${#builtin[@]})); then
            ${sbctl} enroll-keys --microsoft "--firmware-builtin=$(IFS=,; echo "''${builtin[*]}")"
          else
            ${sbctl} enroll-keys --microsoft
          fi
        fi
      '';

      environment.systemPackages = [ config.boot.loader.limine.secureBoot.sbctl ];
      # ephemeral-doctor checks the firmware's state when this is here
      environment.etc."ephemeral/secure-boot".text = "";
    };
}
