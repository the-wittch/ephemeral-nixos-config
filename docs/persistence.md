# Keeping things across reboots

`/` is wiped on every boot. Your home folder is kept, and so is a short list of system paths (`modules/persist.nix`), but anything else a program writes outside `/home` is gone after a reboot: a database in `/var/lib`, a file you edited in `/etc`. Apps from `ephemeral-apps` already keep what they need.

| | reboot | rebuild or update | boot an older generation | reinstall |
|---|---|---|---|---|
| `/` outside the paths below | gone | kept until the next reboot | gone | gone |
| `/home` | kept | kept | kept | gone |
| system paths on the persistence list | kept | kept | kept, but not mounted if that generation doesn't list them | gone |
| `/var/log`, snapshots of `/persist` | kept | kept | kept | gone |
| installed packages (`/nix`) | kept | kept | kept | reinstalled |

A reinstall erases the whole disk, `/persist` included. Make a [backup](backup.md) before one.

To keep more, add the paths in a file in `modules/`:

```nix
{
  flake.modules.nixos.pc.environment.persistence."/persist" = {
    directories = [ "/var/lib/postgresql" ];
    files = [ "/etc/machine-info" ];
  };
}
```

Rebuild, and they're kept from then on. Whatever was in them before the rebuild isn't copied over, so copy it to `/persist` first if you need it. To see what's on `/` that would be lost:

```bash
sudo find / -xdev -type f -newermt "$(uptime -s)" -not -path '/tmp/*' 2>/dev/null
```

Taking a path off the list doesn't delete anything. Its files stay in `/persist`, no longer mounted. The same goes for an app you unpick in `ephemeral-apps` that kept data, such as Docker. To find and remove what's left:

```bash
sudo du -sh /persist/var/lib/*
sudo rm -rf /persist/var/lib/docker
```

Snapshots still hold a copy for up to four weeks, so the space comes back as they expire.
