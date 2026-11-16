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
      efivar = name: "/sys/firmware/efi/efivars/${name}-8be4df61-93ca-11d2-aa0d-00e098032b8c";
      dir = "/persist/var/lib/sbctl";
      key = name: {
        privkey = "${dir}/keys/${name}/${name}.key";
        pubkey = "${dir}/keys/${name}/${name}.pem";
        type = "file";
      };
    in
    {
      boot.loader.limine.secureBoot = {
        enable = true;
        autoGenerateKeys = true;
      };

      # /var/lib/sbctl is only bind-mounted from /persist on a running system. From a chroot,
      # sbctl would make new keys there and sign with them.
      environment.etc."sbctl/sbctl.conf".text = builtins.toJSON {
        landlock = true;
        keydir = "${dir}/keys";
        guid = "${dir}/GUID";
        files_db = "${dir}/files.json";
        bundles_db = "${dir}/bundles.json";
        keys = {
          pk = key "PK";
          kek = key "KEK";
          db = key "db";
        };
      };

      # The nixpkgs install ignores sbctl's exit status, and only enrolls when it makes the keys.
      boot.loader.limine.extraInstallCommands = lib.mkAfter ''
        if ! ${pkgs.util-linux}/bin/mountpoint -q /persist; then
          echo "secureBoot: /persist isn't mounted, so this machine's keys aren't there" >&2
          exit 1
        fi
        cert=${dir}/keys/db/db.pem
        if [[ ! -s $cert ]]; then
          # turned on in the same rebuild as an update from before v4.8.0: sbctl still ran with
          # the old system's settings, and its keys are gone at the next boot
          cert=/var/lib/sbctl/keys/db/db.pem
        fi

        signed=0
        for efi in ${esp}/efi/limine/BOOTX64.EFI ${esp}/efi/boot/BOOTX64.EFI; do
          [[ -e $efi ]] || continue
          if ! ${pkgs.sbsigntool}/bin/sbverify --cert "$cert" "$efi" >/dev/null 2>&1; then
            echo "secureBoot: $efi isn't signed with this machine's key; sbctl's output is above" >&2
            exit 1
          fi
          signed=1
        done
        if ((!signed)); then
          echo "secureBoot: no Limine on ${esp} to check" >&2
          exit 1
        fi

        if [[ $cert != ${dir}/* ]]; then
          echo "secureBoot: the keys aren't on /persist yet, so they aren't enrolled this time." >&2
          echo "Once this rebuild has finished, run ephemeral-update once more to enroll them." >&2
        elif [[ $(${pkgs.coreutils}/bin/od -An -tu1 -j4 -N1 ${efivar "SetupMode"} 2>/dev/null | ${pkgs.coreutils}/bin/tr -d ' ') == 1 ]]; then
          # Microsoft's keys stay trusted for option ROMs, docks and firmware updates. sbctl 0.18
          # stops on a default list the firmware doesn't have, so only the ones it has are named.
          builtin=()
          for list in db KEK; do
            if [[ -e ${efivar "\${list}Default"} ]]; then
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
      # tells ephemeral-doctor to check the firmware's Secure Boot state
      environment.etc."ephemeral/secure-boot".text = "";
    };
}
