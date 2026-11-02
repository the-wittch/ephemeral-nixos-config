# Keeping things across reboots

`/` is wiped on every boot. Your home folder is kept, and so is a short list of system paths (`modules/persist.nix`), but anything else a program writes outside `/home` is gone after a reboot: a database in `/var/lib`, a file you edited in `/etc`. Apps from `ephemeral-apps` already keep what they need.

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
