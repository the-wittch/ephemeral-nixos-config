# What settings-from-pass copies from the Proton Pass item, and so all the loader takes from
# settings.from-pass.json. useControlD comes from the item's controldResolver field.
{
  strings = [
    "hostname"
    "username"
    "diskDevice"
    "swapSize"
    "timeZone"
    "desktop"
  ];
  bools = [ "useFlakePassCli" ];
}
