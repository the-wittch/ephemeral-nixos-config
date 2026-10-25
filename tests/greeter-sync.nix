# VM test for greeter.nix and scripts/greeter-sync.sh.
#   nix build path:.#checks.x86_64-linux.greeter-sync -L
{ pkgs }:

pkgs.testers.runNixOSTest {
  name = "greeter-sync";

  node.specialArgs.settings = {
    username = "alice";
    desktop = "gnome";
  };

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../greeter.nix ];

      services.displayManager.gdm.enable = true;
      programs.dconf.enable = true;
      users.users.alice.isNormalUser = true;
      users.users.bob.isNormalUser = true;
      environment.systemPackages = [ pkgs.dconf ];
      virtualisation.memorySize = 2048;
    };

  testScript = ''
    import shlex

    bg = "/var/lib/AccountsService/backgrounds/alice"
    pics = "/home/alice/Pictures"

    def png(path, owner="alice", mode="600", size=4096):
        path = shlex.quote(path)
        machine.succeed(
            f"printf '\\211PNG\\r\\n\\032\\n' > {path}"
            f" && head -c {size} /dev/urandom >> {path}"
            f" && chown {owner} {path} && chmod {mode} {path}"
        )

    started = "systemctl show -p InactiveEnterTimestampMonotonic --value greeter-sync.service"

    def set_wallpaper(uri):
        keys = "/home/alice/.dconf-keys"
        ini = f"[org/gnome/desktop/background]\npicture-uri='{uri}'\n"
        machine.succeed(
            f"mkdir -p {keys} /home/alice/.config/dconf"
            f" && printf %s {shlex.quote(ini)} > {keys}/bg"
            " && chown -R alice /home/alice/.config /home/alice/.dconf-keys"
        )
        machine.succeed("systemctl reset-failed greeter-sync.service || true")
        before = machine.succeed(started).strip()
        # the .path unit sees the new user db and starts the sync
        machine.succeed(f"runuser -u alice -- dconf compile /home/alice/.config/dconf/user {keys}")
        try:
            machine.wait_until_succeeds(
                f"[ \"$({started})\" != {shlex.quote(before)} ]"
                " && systemctl show -p ActiveState --value greeter-sync.service | grep -qxE 'inactive|failed'",
                timeout=30,
            )
        finally:
            print(machine.succeed("journalctl -b --no-pager -u greeter-sync.path -u greeter-sync.service | tail -n 8"))
        machine.fail("systemctl is-failed greeter-sync.service")

    def greeter_uri():
        return machine.succeed(
            "HOME=/var/empty DCONF_PROFILE=gdm dconf read /org/gnome/desktop/background/picture-uri"
        ).strip()

    def expect(uri, why):
        got = greeter_uri()
        assert got == uri, f"{why}: greeter shows {got!r}, wanted {uri!r}"
        print(f"ok: {why}")

    def expect_nothing(why):
        got = greeter_uri()
        assert got == "", f"{why}: greeter shows {got!r}"
        machine.fail(f"test -e {bg}")
        print(f"ok: {why}")

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("greeter-sync.path")
    # the boot run has nothing to publish but must not trip the sandbox
    machine.fail("systemctl is-failed greeter-sync.service")
    machine.succeed(f"install -d -o alice -m 700 /home/alice {pics}")

    with subtest("gdm profile reads greeter-db and keeps the nixpkgs defaults"):
        profile = machine.succeed("cat /etc/dconf/profile/gdm")
        lines = profile.splitlines()
        assert lines[0] == "user-db:user", profile
        assert lines[1] == "file-db:/var/lib/gdm/greeter-db", profile
        assert lines[-1].endswith("/share/gdm/greeter-dconf-defaults"), profile
        assert machine.succeed(
            "HOME=/var/empty DCONF_PROFILE=gdm dconf read /org/gnome/desktop/interface/color-scheme"
        ).strip() == "'prefer-dark'"

    with subtest("a private wallpaper is copied out world-readable"):
        png(f"{pics}/wall.png")
        set_wallpaper(f"file://{pics}/wall.png")
        expect(f"'file://{bg}'", "private wallpaper published")
        machine.succeed(f"cmp {pics}/wall.png {bg}")
        assert machine.succeed(f"stat -c '%a %U' {bg}").strip() == "644 root"

    with subtest("percent-encoded paths are decoded"):
        png(f"{pics}/my wall.png")
        set_wallpaper(f"file://{pics}/my%20wall.png")
        expect(f"'file://{bg}'", "encoded path published")
        machine.succeed(f"cmp '{pics}/my wall.png' {bg}")

    with subtest("a world-readable file outside home is used in place"):
        machine.succeed("install -d -m 755 /srv")
        png("/srv/pub.png", owner="root", mode="644")
        set_wallpaper("file:///srv/pub.png")
        expect("'file:///srv/pub.png'", "public file used in place")
        machine.fail(f"test -e {bg}")

    with subtest("root-only files are never published"):
        png("/var/lib/secret.png", owner="root", mode="600")
        set_wallpaper("file:///var/lib/secret.png")
        expect_nothing("root-only path refused")

    with subtest("a symlink to a root-only file is never published"):
        machine.succeed(f"ln -sfn /var/lib/secret.png {pics}/link.png && chown -h alice {pics}/link.png")
        set_wallpaper(f"file://{pics}/link.png")
        expect_nothing("symlink to root-only file refused")

    with subtest("another user's private file is never published"):
        machine.succeed("install -d -o bob -m 700 /home/bob")
        png("/home/bob/private.png", owner="bob", mode="644")
        set_wallpaper("file:///home/bob/private.png")
        expect_nothing("other user's file refused")

    with subtest("files under /etc are never published"):
        png("/etc/pub.png", owner="root", mode="644")
        set_wallpaper("file:///etc/pub.png")
        expect_nothing("/etc refused")

    with subtest("non-images are never published"):
        machine.succeed(f"printf 'not an image' > {pics}/notes.png && chown alice {pics}/notes.png")
        set_wallpaper(f"file://{pics}/notes.png")
        expect_nothing("non-image refused")

    with subtest("an oversized file replaces nothing and leaves nothing stale"):
        set_wallpaper(f"file://{pics}/wall.png")
        expect(f"'file://{bg}'", "valid wallpaper back")
        png(f"{pics}/huge.png", size=51 * 1024 * 1024)
        set_wallpaper(f"file://{pics}/huge.png")
        expect_nothing("oversized refused, old copy removed")

    with subtest("no secret bytes reached the published directory"):
        machine.succeed(
            "for f in /var/lib/AccountsService/backgrounds/*; do"
            " [ -e \"$f\" ] || continue; ! cmp -s \"$f\" /var/lib/secret.png; done"
        )
  '';
}
