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

and which services lose their data at every reboot:

```bash
sudo ephemeral-doctor audit
```

`audit` goes by the state folders services tell systemd about, so it misses a program that writes somewhere without saying so. `lost` shows those too, mixed in with everything else that's new since boot.

| | reboot | rebuild or update | go back to an older system | reinstall |
|---|---|---|---|---|
| `/` outside what's kept | gone | kept until the next reboot | kept until the next reboot | gone |
| `/home` | kept | kept | kept | gone |
| the other kept paths | kept | kept | kept, but not mounted if that system doesn't keep them | gone |
| `/var/log`, snapshots of `/persist` | kept | kept | kept | gone |
| installed packages (`/nix`) | kept | kept | kept | reinstalled |

A reinstall erases the whole disk, `/persist` included. Make a [backup](backup.md) before one.

To keep more, save this as `/persist/etc/nixos/modules/keep.nix`, with your own paths, and run `ephemeral-update`:

```nix
{
  flake.modules.nixos.pc.preservation.preserveAt."/persist" = {
    directories = [
      {
        directory = "/var/lib/postgresql";
        user = "postgres";
        group = "postgres";
        mode = "0750";
      }
    ];
    files = [ "/etc/machine-info" ];
  };
}
```

They're kept from the next reboot. Whatever was in them before isn't copied over, so copy it to `/persist` first if you need it; `/persist/var/lib/postgresql` for the example above.

A kept folder gets the owner and mode given here at every boot, root and `0755` unless you say otherwise, so give them for a folder a service owns, as above. `ls -ld` on the folder shows what they are now, and `sudo ephemeral-doctor audit` suggests the entry for a service's folder with them filled in. The options are [preservation's](https://nix-community.github.io/preservation/configuration-options.html).

A service with `DynamicUser` keeps its data in `/var/lib/private/<name>`, and systemd refuses to start it unless that folder and `/var/lib/private` are mode `0700`:

```nix
{
  flake.modules.nixos.pc.preservation.preserveAt."/persist".directories = [
    {
      directory = "/var/lib/private/i2pd";
      mode = "0700";
      configureParent = true;
      parent.mode = "0700";
    }
  ];
}
```

Taking a path off the list doesn't delete anything. Its files stay in `/persist`, no longer mounted. The same goes for an app you unpick in `ephemeral-apps` that kept data, such as Docker. `sudo ephemeral-doctor audit` lists those leftovers in `/persist/var/lib`, with their sizes, and how to remove each:

```bash
sudo rm -rf /persist/var/lib/docker
```

It only looks in `/persist/var/lib`. Other folders on `/persist`, like `/persist/etc/ssh` and `/persist/passwords`, are used where they are, never mounted, so they'd all look like leftovers.

Snapshots still hold a copy for up to four weeks, so the space comes back as they expire.
