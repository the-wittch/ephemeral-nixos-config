# settings.json

[`settings.example.json`](../settings.example.json) lists every key with its default. CI fails if a setting or a default changes without it.

| key | what |
|-----|------|
| `hostname`, `username`, `timeZone` | who and where the machine is |
| `locale` | language, e.g. `de_DE.UTF-8` |
| `keyboardLayout`, `keyboardVariant` | e.g. `de` and `nodeadkeys`; also used at the LUKS prompt |
| `diskDevice`, `swapSize` | the whole disk (not a partition) and the swap file size |
| `desktop` | `plasma`, `gnome`, `niri` or `umbriel` |
| `profile` | `full` (everything in these docs) or `minimal` (the installer's small install) |
| `nvidia` | `none`, `open` (RTX 20 / GTX 16 series and newer) or `legacy` (GTX 900 / 10 series) |
| `extras` | the extra apps and shell tools listed in the [README](../README.md) |
| `laptop` | thermald on Intel, battery reporting, screen rotation and light sensors |
| `fingerprint` | fingerprint login and sudo |
| `useControlD` | DNS over TLS through Control D |
| `useTailscale` | the Tailscale VPN |
| `useOpenSnitch` | OpenSnitch asks before programs connect out (on by default) |
| `usePassSettings`, `passSettingsVault`, `passSettingsItem` | merge settings from Proton Pass |
| `usePassSshAgent`, `passSshVault` | the Proton Pass SSH agent at login, serving the keys in that vault |
| `useFlakePassCli` | build pass-cli from the pinned release here instead of nixpkgs |

Every key but `username` has a default. Rebuild after changing it. Values are checked on the rebuild: a disk has to be a `/dev/` path, swap a size like `16G`, and vault names can't contain quotes, `$`, backticks or backslashes, since some of them end up in shell scripts. Since v4.0.0, the older `settings.nix`, `settings.from-pass.nix` and `smb-shares.nix` aren't read. If one is still there without its `.json`, the rebuild stops and prints the command that converts it, for example:

```bash
cd /persist/etc/nixos
nix eval --json --file settings.nix | nix run nixpkgs#jq -- . > settings.json
rm settings.nix
```

All the helper commands edit JSON with `jq`, so nothing they write is ever evaluated as Nix code.
