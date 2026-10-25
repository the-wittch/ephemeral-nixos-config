# tmpfs root wiped every boot, /persist on its own disk, three boots.
#   nix build path:.#checks.x86_64-linux.boot -L
{ pkgs, baseModules }:

let
  settings = {
    hostname = "boottest";
    username = "alice";
    diskDevice = "/dev/vda";
    swapSize = "1G";
    timeZone = "UTC";
    desktop = "gnome";
    useControlD = true;
    useFlakePassCli = false;
    usePassSettings = false;
    passSettingsVault = "Personal";
    passSettingsItem = "nixos-settings";
  };
  flakeRoot = ../.;
in
pkgs.testers.runNixOSTest {
  name = "boot";

  # the unfree allowlist sets nixpkgs.config
  node.pkgsReadOnly = false;
  node.specialArgs = { inherit settings flakeRoot; };

  nodes.machine =
    { lib, pkgs, ... }:
    {
      imports = baseModules { inherit settings flakeRoot; };

      # no luks disk. a tmpfs root is what the rollback gives
      disko.enableConfig = false;
      boot.initrd.systemd.services.rollback.enable = false;
      boot.loader.systemd-boot.enable = lib.mkForce false;
      # the test driver needs console output
      boot.consoleLogLevel = lib.mkForce 7;
      environment.systemPackages = [
        pkgs.cryptsetup
        pkgs.e2fsprogs
      ];

      virtualisation = {
        diskImage = null;
        emptyDiskImages = [
          {
            size = 4096;
            driveConfig.deviceExtraOpts.serial = "persist";
          }
          # usb stick for the header backup test
          {
            size = 64;
            driveConfig.deviceExtraOpts.serial = "usb";
          }
        ];
        fileSystems = {
          "/persist" = {
            device = "/dev/disk/by-id/virtio-persist";
            fsType = "btrfs";
            autoFormat = true;
            neededForBoot = true;
          };
          "/var/log" = {
            device = "tmpfs";
            fsType = "tmpfs";
            neededForBoot = true;
          };
        };
        memorySize = 4096;
        cores = 2;
      };
    };

  testScript = ''
    def boot_is_clean(boot):
        machine.wait_for_unit("multi-user.target")
        machine.wait_until_succeeds("systemctl is-system-running --wait | grep -qxE 'running|degraded'", timeout=180)

        cycles = machine.succeed("journalctl -b --no-pager -o cat | grep -i 'ordering cycle' || true").strip()
        assert cycles == "", f"boot {boot}: ordering cycle\n{cycles}"

        assert machine.succeed("stat -c %a /etc").strip() == "755", f"boot {boot}: /etc is not 755"

        failed = machine.succeed("systemctl --failed --no-legend --plain").strip()
        assert failed == "", f"boot {boot}: failed units\n{failed}"

        for unit in ["nix-daemon.socket", "systemd-resolved.service", "controld-resolver.service",
                     "flatpak-flathub.service", "home-manager-alice.service",
                     "display-manager.service",
                     "snapper-persist-setup.service", "snapper-timeline.timer"]:
            machine.succeed(f"systemctl is-active --quiet {unit}")
        print(f"ok: boot {boot} is clean")

    def reboot():
        machine.shutdown()
        machine.start()

    with subtest("first boot, nothing on /persist yet"):
        machine.wait_for_unit("multi-user.target")
        # key exists on first boot
        machine.succeed("test -s /persist/var/lib/systemd/credential.secret")
        machine.succeed("test ! -L /var/lib/systemd/credential.secret && findmnt -n /var/lib/systemd/credential.secret")
        # like libvirt: encrypt now, decrypt after reboots
        machine.succeed("echo boot-one-secret | systemd-creds encrypt --with-key=host --name=t - /persist/t.cred")
        # 0700 on purpose. /etc has to stay readable
        machine.succeed("install -d /persist/etc && chmod 700 /persist/etc && printf 'testid\\n' > /persist/etc/controld-resolver")
        reboot()

    with subtest("second boot"):
        boot_is_clean(2)

    with subtest("Control D config reaches resolved, readable only by resolved"):
        conf = "/run/systemd/resolved.conf.d/controld.conf"
        assert machine.succeed(f"stat -c '%a %U %G' {conf}").strip() == "640 root systemd-resolve"
        machine.succeed(f"grep -qF 'testid.dns.controld.com' {conf}")
        machine.succeed("resolvectl dns | grep -qF 'testid.dns.controld.com'")

    with subtest("credential key is bind-mounted from /persist"):
        machine.succeed("findmnt -n /var/lib/systemd/credential.secret")
        machine.succeed("test -s /persist/var/lib/systemd/credential.secret")
        machine.succeed("test ! -L /var/lib/systemd/credential.secret && findmnt -n /var/lib/systemd/credential.secret")

    with subtest("a new user's first shell has no zsh wizard"):
        machine.fail("test -e /home/alice/.zshrc")
        out = machine.succeed(
            "timeout 20 runuser -u alice -- script -qec 'zsh -i -c true' /dev/null </dev/null 2>&1 || true"
        )
        assert "zsh-newuser-install" not in out, f"zsh wizard ran:\n{out}"

    with subtest("hardening is on"):
        assert machine.succeed("sysctl -n kernel.kptr_restrict").strip() == "2"
        assert machine.succeed("sysctl -n kernel.unprivileged_bpf_disabled").strip() == "1"
        machine.succeed("grep -qx 'blacklist sctp' /etc/modprobe.d/nixos.conf")
        machine.fail("grep -qw '^sctp' /proc/modules")

    with subtest("nix daemon is for wheel only"):
        machine.succeed("runuser -u alice -- nix store info")
        machine.succeed("useradd -m mallory")
        machine.fail("runuser -u mallory -- nix store info")

    with subtest("Flathub was added offline"):
        machine.succeed("flatpak remotes --system --columns=name | grep -qx flathub")

    with subtest("the GDM login screen is dark"):
        scheme = machine.succeed(
            "HOME=/var/empty DCONF_PROFILE=gdm dconf read /org/gnome/desktop/interface/color-scheme"
        ).strip()
        assert scheme == "'prefer-dark'", f"gdm color-scheme is {scheme!r}"

    with subtest("the wallpaper is rendered and is the default for GNOME and GDM"):
        png = "/run/current-system/sw/share/backgrounds/ephemeral/wallpaper.png"
        uri = f"'file://{png}'"
        machine.succeed(f"file -L {png} | grep -q 'PNG image data, 3840 x 2160'")
        user = machine.succeed(
            "runuser -l alice -c 'GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.background picture-uri'"
        ).strip()
        assert user == uri, f"GNOME default wallpaper is {user!r}"
        gdm = machine.succeed(
            "HOME=/var/empty DCONF_PROFILE=gdm dconf read /org/gnome/desktop/background/picture-uri"
        ).strip()
        assert gdm == uri, f"GDM wallpaper is {gdm!r}"

    with subtest("snapshots of /persist undo a delete, and stay root-only"):
        machine.succeed("echo precious > /persist/home/alice/notes.txt && chown alice /persist/home/alice/notes.txt")
        machine.succeed("systemctl start snapper-timeline.service")
        # the timeline service returns before the snapshot exists
        machine.wait_until_succeeds("snapper -c persist --csvout list --columns number | tail -n 1 | grep -qvx 0", timeout=30)
        n = machine.succeed("snapper -c persist --csvout list --columns number | tail -n 1").strip()
        assert n.isdigit() and n != "0", f"no snapshot taken: {n!r}"
        machine.succeed("rm /home/alice/notes.txt")
        machine.succeed(f"cp -a /persist/.snapshots/{n}/snapshot/home/alice/notes.txt /home/alice/")
        assert machine.succeed("cat /home/alice/notes.txt").strip() == "precious"
        assert machine.succeed("stat -c %a /persist/.snapshots").strip() == "750"
        machine.fail("runuser -u alice -- ls /persist/.snapshots")
        machine.succeed(f"btrfs property get -ts /persist/.snapshots/{n}/snapshot ro | grep -qx 'ro=true'")

    with subtest("luks-header-backup refuses the same disk and memory, then writes a real header"):
        # throwaway luks image named like the real one
        machine.succeed(
            "truncate -s 64M /persist/fake-disk.img"
            " && printf secret > /root/key"
            " && cryptsetup luksFormat --batch-mode --pbkdf pbkdf2 --pbkdf-force-iterations 1000"
            "    --key-file /root/key /persist/fake-disk.img"
            " && cryptsetup open --key-file /root/key /persist/fake-disk.img cryptroot"
        )
        machine.fail("luks-header-backup /tmp/header.img")
        machine.succeed("mkfs.ext4 -q /dev/mapper/cryptroot && install -d /mnt/inside && mount /dev/mapper/cryptroot /mnt/inside")
        machine.fail("luks-header-backup /mnt/inside/header.img")
        machine.succeed("umount /mnt/inside")
        machine.succeed("install -d /mnt/usb && mkfs.ext4 -q /dev/disk/by-id/virtio-usb && mount /dev/disk/by-id/virtio-usb /mnt/usb")
        machine.succeed("luks-header-backup /mnt/usb/header.img")
        machine.succeed("cryptsetup isLuks /mnt/usb/header.img")
        assert machine.succeed("stat -c %a /mnt/usb/header.img").strip() == "600"
        machine.fail("luks-header-backup /mnt/usb/header.img")
        machine.succeed("umount /mnt/usb && cryptsetup close cryptroot && rm /persist/fake-disk.img")

    with subtest("root is wiped, /persist is kept"):
        machine.succeed("touch /root-was-here /persist/persist-was-here")
        reboot()
        boot_is_clean(3)
        machine.fail("test -e /root-was-here")
        machine.succeed("test -e /persist/persist-was-here")
        # encrypted on boot 1, through the first-boot link
        got = machine.succeed("systemd-creds decrypt --name=t /persist/t.cred -").strip()
        assert got == "boot-one-secret", f"credential from boot 1 no longer decrypts: {got!r}"
  '';
}
