# The first hour

1. **Log in.** If you picked the small install, run `ephemeral-setup` first and choose the full system. `ephemeral-setup` is also how you change the options you picked later.
2. **Run `ephemeral-doctor`** to see that everything is as it should be. It says how to fix anything that isn't.
3. **Run `ephemeral-apps`** and tick the apps you want, if you didn't pick them during the install.
4. **Allow what you use.** OpenSnitch, if you kept it on, asks the first time a program connects out. If something can't connect later, check its rules.
5. **Using the Proton Pass SSH agent?** Run `pass-cli login`, then log out and back in.
6. **Back up the LUKS header** to a USB stick, once: `luks-header-backup /run/media/$USER/<stick>/luks-header.img`. Without it, a damaged header loses the whole disk.
7. **Keep the config in git:**

   ```bash
   cd /persist/etc/nixos && git init && git add -A && git commit -m "my machine"
   ```

   Push it to a private repo. `settings.json` stays out of git on its own.

## Good to know

- `/` is wiped on every boot. Your home folder is kept; `ephemeral-doctor kept` lists the rest, and [Keeping things across reboots](persistence.md) says how to add to it.
- Rebuild after any change with `ephemeral-update`.
- `passwd` doesn't stick. Change your password with `ephemeral-passwd`.
- A rebuild broke something? `ephemeral-update --previous` goes back. See [When something breaks](troubleshooting.md).
- Check a change builds with `ephemeral-update --check` before switching to it, or try it in a VM first with `nix run path:/persist/etc/nixos#vm`.
- `ephemeral-help` lists every command.
