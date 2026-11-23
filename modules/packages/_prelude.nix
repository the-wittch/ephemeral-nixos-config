# What every command starts with: the values it shares with the settings schema, then all of
# scripts/lib. A function no command calls costs nothing. flake/tests/_scripts.sh runs the
# scripts with the same text.
{ lib }:
let
  rules = import ../settings/_rules.nix;
  pass = import ../settings/_pass-keys.nix;
  choices = import ../settings/_choices.nix;
  initrdKey = import ../_initrd-ssh-key.nix;
  backup = import ../_backup.nix;
  categories = import ../apps/_categories.nix;
  libDir = ../../scripts/lib;
  array = name: list: "${name}=(${lib.escapeShellArgs list})\n";
in
# in one group, so the one directive covers them: no command uses them all
"# shellcheck disable=SC2034\n{\n"
+ "controld_id_re=${lib.escapeShellArg rules.controldResolver}\n"
+ "vault_re=${lib.escapeShellArg rules.passSshVault}\n"
+ "custom_dns_re=${lib.escapeShellArg rules.customDns}\n"
+ "initrd_ssh_key=${lib.escapeShellArg initrdKey.key}\n"
+ "initrd_ssh_boot_key=${lib.escapeShellArg initrdKey.boot}\n"
+ "initrd_ssh_key_name=${lib.escapeShellArg initrdKey.name}\n"
+ "backup_dir=${lib.escapeShellArg backup.dir}\n"
+ "backup_label_re=${lib.escapeShellArg backup.label}\n"
+ "backup_repo_re=${lib.escapeShellArg backup.repository}\n"
+ array "app_categories" categories
+ array "pass_keys" pass
# menu_<setting> lists a menu's values in order; menu_label has "<setting>/<value>"
+ lib.concatStrings (
  lib.mapAttrsToList (key: entries: array "menu_${key}" (map (c: c.value) entries)) choices
)
+ "declare -A menu_label=(\n"
+ lib.concatStrings (
  lib.mapAttrsToList (
    key: entries:
    lib.concatMapStrings (
      c:
      "  [${lib.escapeShellArg "${key}/${c.value}"}]=${lib.escapeShellArg "${c.label} — ${c.description}"}\n"
    ) entries
  ) choices
)
+ ")\n}\n"
+ lib.concatMapStrings (name: builtins.readFile (libDir + "/${name}")) (
  lib.filter (lib.hasSuffix ".sh") (lib.attrNames (builtins.readDir libDir))
)
