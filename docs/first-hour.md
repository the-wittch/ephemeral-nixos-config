# The first hour

1. **Log in.** If you picked the small install, run `ephemeral-setup` first and choose the full system. `ephemeral-setup` is also how you change the options you picked later.
2. **Run `ephemeral-apps`** and tick the apps you want, if you didn't pick them during the install.
3. **Allow what you use.** OpenSnitch, if you kept it on, asks the first time a program connects out. If something can't connect later, check its rules.
4. **Using the Proton Pass SSH agent?** Run `pass-cli login`, then log out and back in.
5. **Keep the config in git:**

   ```bash
   cd /persist/etc/nixos && git init && git add -A && git commit -m "my machine"
   ```

   Push it to a private repo. `settings.json` stays out of git on its own.

## Good to know

- `/` is wiped on every boot. Your home folder is kept; for anything else, see [Keeping things across reboots](persistence.md).
- Rebuild after any change with `ephemeral-update`.
- `passwd` doesn't stick. Change your password as shown under [Security notes](security.md).
- A broken rebuild? Pick the previous entry in the boot menu. See [When something breaks](troubleshooting.md).
- Try a change first with `nix run path:/persist/etc/nixos#vm`.
- `ephemeral-help` lists every command.
