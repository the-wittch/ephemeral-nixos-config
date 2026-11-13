# Keeping things across reboots

Your files are in your home folder, which is kept. Everything else on `/` is built again from the config at every boot, so what a program writes outside `/home`, a database in `/var/lib` or a file you edited in `/etc`, is gone after a reboot. Apps from `ephemeral-apps` already keep what they need.

To see what's kept:

```bash
ephemeral-doctor kept
```

and what the next reboot will remove, written since this boot:

```bash
sudo ephemeral-doctor lost
```

| | reboot | rebuild or update | go back to an older system | reinstall |
|---|---|---|---|---|
| `/` outside what's kept | gone | kept until the next reboot | gone | gone |
| `/home` | kept | kept | kept | gone |
| the other kept paths | kept | kept | kept, but not mounted if that system doesn't keep them | gone |
| `/var/log`, snapshots of `/persist` | kept | kept | kept | gone |
| installed packages (`/nix`) | kept | kept | kept | reinstalled |

A reinstall erases the whole disk, `/persist` included. Make a [backup](backup.md) before one.

To keep more, save this as `/persist/etc/nixos/modules/keep.nix`, with your own paths, and run `ephemeral-update`:

```nix
{
  flake.modules.nixos.pc.environment.persistence."/persist" = {
    directories = [ "/var/lib/postgresql" ];
    files = [ "/etc/machine-info" ];
  };
}
```

They're kept from then on. Whatever was in them before isn't copied over, so copy it to `/persist` first if you need it; `/persist/var/lib/postgresql` for the example above.

Taking a path off the list doesn't delete anything. Its files stay in `/persist`, no longer mounted. The same goes for an app you unpick in `ephemeral-apps` that kept data, such as Docker. To find and remove what's left:

```bash
sudo du -sh /persist/var/lib/*
sudo rm -rf /persist/var/lib/docker
```

Snapshots still hold a copy for up to four weeks, so the space comes back as they expire.
