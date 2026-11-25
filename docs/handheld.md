# Handheld (beta)

`"desktop": "handheld"` turns a Steam Deck or a ROG Ally into something like SteamOS: it starts in Steam's Game Mode, and "Switch to Desktop" goes to Plasma. Underneath it's the same system as any other install: `/` wiped at every boot, `/persist`, the encrypted disk, backups and `ephemeral`. Steam's games and saves are in your home folder, which is kept.

It's a beta. The controller tables come from what a ROG Xbox Ally X sends and from the kernel's drivers, and CI boots it and unlocks a disk with a virtual controller, but nothing on this page has been checked on a real handheld yet. Please report what you find.

## Which handhelds

| | status |
|---|---|
| ROG Xbox Ally X, ROG Xbox Ally | the controller table was read off an Xbox Ally X; the rest is untested |
| ROG Ally X (2024) | the same controller IDs as the Xbox Ally X, so it should behave the same; untested |
| Steam Deck LCD and OLED | the controller table is from the kernel's `hid-steam` driver; untested |
| ROG Ally (2023) | Game Mode should work; its controller isn't in the table, so the disk needs a keyboard at boot |

Other handhelds that [Handheld Daemon](https://github.com/hhd-dev/hhd) supports may work in Game Mode, but their controllers can't type the passphrase at boot.

## Installing

1. Plug in a USB keyboard. The installer can't be used with the controller yet.
2. On the Desktop screen, pick **Handheld**.
3. For the disk passphrase, use only the characters in the table below, so you can type it with the controller at boot. The installer won't take any other characters, or the Deck's back buttons on anything but a Deck.

The installer takes eight presses at the least, but make it longer. Fourteen buttons give each press less than four bits, so eight presses are about 30 bits, which a determined offline attack on a stolen disk can get through. Twelve presses are about 46 bits, sixteen about 61. On a Deck the back buttons add four more characters.

## Unlocking the disk

At boot, the passphrase prompt takes your controller's buttons as you'd type the passphrase. Press your buttons in order, then **Start**. **Select** deletes the last press. A keyboard works too.

| button | types | button | types |
|---|---|---|---|
| A | `a` | d-pad up | `u` |
| B | `b` | d-pad down | `d` |
| X | `x` | d-pad left | `l` |
| Y | `y` | d-pad right | `r` |
| LB | `q` | LT | `z` |
| RB | `e` | RT | `c` |
| left stick press | `s` | right stick press | `t` |
| L4, L5, R4, R5 (Steam Deck only) | `1`, `2`, `3`, `4` | | |

Buttons go by where they sit, as on an Xbox pad: on a PlayStation pad, cross is A, circle B, square X and triangle Y.

So A, Y, up, up, LB, down, RT, B is the passphrase `ayuuqdcb`.

These controllers work at the prompt:

- the Steam Deck's own
- the ROG Ally X's and Xbox Ally's own, without their back buttons, which only work once the system is up
- wired Xbox 360, One and Series pads, and Xbox 360 pads through Microsoft's wireless receiver
- wired DualShock 4 and DualSense pads

Bluetooth pads, and Xbox One and Series pads through the Xbox Wireless Adapter, work in Game Mode and on the desktop, but not at the prompt.

## Game Mode and the desktop

- **To the desktop**: Steam's power menu, "Switch to Desktop".
- **Back to Game Mode**: "Return to Game Mode" in Plasma's launcher. Logging out does the same, and every boot starts in Game Mode.
- **On the desktop**, Steam runs in the background, so the controller works as a mouse, and Steam and X together bring up its on-screen keyboard, for `sudo` and anything else you have to type.
- **Updates**: Steam's own system update button does nothing here. Update from the desktop with `ephemeral update`, as on any other install.
- **Power button**: a short press suspends, a long one powers off.

On an Ally, Handheld Daemon runs the back buttons, the gyro, the stick lights and the power limits (TDP), from its overlay: double-tap the Armoury Crate button. Its settings are kept across reboots. On a Deck, Steam reads the controller itself, and Handheld Daemon only adds its overlay and power profiles.

## What to expect

These come from the kernel and firmware every install has, not from anything made for handhelds, and none have been tried on these devices here:

- **Screen, brightness, Wi-Fi, Bluetooth, battery, sound**: the standard drivers. The Deck LCD's Wi-Fi is Realtek, the OLED's Qualcomm and the Ally's MediaTek. The Deck's speakers don't get the sound processing SteamOS gives them, so they can sound thinner.
- **Fans**: left to the firmware's own curve on both. Handheld Daemon can set a curve on an Ally.
- **Power limits on a Deck**: Steam's performance slider needs SteamOS's own helpers, which this hasn't got, so expect it to do nothing.
- **Firmware updates**: neither is on LVFS, so `fwupd` doesn't update them. Update an Ally's BIOS from its own setup screen or Windows, and a Deck's from SteamOS.
- **Docking**: external screens over USB-C work as on any AMD laptop.

## When something goes wrong

- **The boot menu needs a keyboard.** To start an older build after a bad update, plug one in, press a key while the boot menu shows, and pick it, as [When something breaks](troubleshooting.md) says.
- **The emergency shell**, and anything else typed while the system can't start, needs a keyboard too.
- **Game Mode keeps restarting**: plug in a keyboard and switch to another console with Ctrl, Alt and F2, log in, and run `journalctl -b --user` to see why Steam stopped.
- **The controller does nothing at the passphrase prompt**: use a keyboard to unlock, then run `journalctl -b -u handheld-input` and include its output in a report.

When you report a problem, include `ephemeral report` and these:

```sh
cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name
grep -E '^(N|I|H):' /proc/bus/input/devices
journalctl -b -u handheld-daemon
```

## Security

The disk passphrase is what protects a handheld when it's off. Once it's unlocked:

- you're logged in at boot without a password, and the desktop doesn't lock, on its own or on waking. Anyone holding it while it's on or asleep is in your account. Steam's own lock screen (Settings, Security) can ask for a PIN on waking in Game Mode.
- Handheld Daemon runs as root, as nixpkgs sets it up, outside the sandbox this config's own services get. Its settings API listens only on `127.0.0.1:5335`, with a token, and the firewall is closed to it either way.
- `acpi_call`, which lets root run any ACPI method and some handhelds need for power limits, isn't loaded.

## Not done yet

- Using the installer with the controller, and an on-screen keyboard in it.
- Decky Loader and NonSteamLaunchers as apps to pick.
