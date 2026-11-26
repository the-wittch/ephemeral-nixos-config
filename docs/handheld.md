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

You can install with the controller alone. On a Steam Deck or an Ally the installer starts on **Handheld**; on anything else, pick it on the Desktop screen.

| on the controller | in the installer |
|---|---|
| d-pad | move |
| A or Start | choose, or go on |
| B | back |
| X | tick or untick |
| Y | on-screen keyboard, in a text field |
| LB, RB | previous and next field |
| Select | delete |

1. Boot the installer from USB. On an Ally, hold volume down while it starts, pick **Boot Menu**, and pick the USB stick there, or its buttons won't work until the installer is up.
2. **Connect to Wi-Fi** on the first screen: pick your network, and type its password with the on-screen keyboard.
3. On the passphrase screen the controller types the passphrase the way it will at boot. Press your buttons, then **Start**; **Select** deletes. Use only the characters in the table below; the installer won't take any others, or the Deck's back buttons on anything but a Deck.
4. The login password and the rest are typed with the on-screen keyboard (Y).

A USB keyboard works throughout too.

The passphrase has to be at least twelve presses. Fourteen buttons give each press less than four bits, so twelve presses are about 46 bits and sixteen about 61; eight would be about 30, which an offline attack on a stolen disk can get through. On a Deck the back buttons add four more characters.
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

So A, Y, up, up, LB, down, RT, B, X, Y, right, left is the passphrase `ayuuqdcbxyrl`. If a keyboard is plugged in, make sure its Caps Lock is off: with it on, the controller's presses come out as capitals and the passphrase is refused.

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
- **On a Deck** the controller is a gamepad from the start rather than a mouse, which is what lets it unlock the disk. On the desktop, Steam in the background makes it a mouse again.

On an Ally, Handheld Daemon runs the back buttons, the gyro, the stick lights and the power limits (TDP), from its overlay: double-tap the Armoury Crate button. Its settings are kept across reboots. On a Deck, Steam reads the controller itself, and Handheld Daemon only adds its overlay and power profiles.

## Launchers and Decky

On the full profile, the Apps screen has these for Game Mode. Heroic, Lutris and Decky Loader are ticked already; untick any you don't want:

- **Heroic**: Epic, GOG and Amazon games.
- **Lutris**: in Game Mode it also brings **Battle.net**, the **EA app**, **Ubisoft Connect** and the **Rockstar Games Launcher**. The first time, each one runs Lutris's installer for it. After that, Lutris asks whether to play or install again, and A on Play starts it.
- **Prism Launcher**: Minecraft.
- **Decky Loader**: plugins for Game Mode's quick menu, from the Decky store. It runs as root, as upstream has it, and a plugin can ask to run as root too, so add only plugins you trust. It also turns on Steam's remote debugging, which is how it gets into Steam's menus, and any program on the handheld can reach that while Steam runs. The firewall keeps it from the network.

The launchers you pick show up in Steam's library as non-Steam games after the next switch into Game Mode or boot. Delete one in Steam and it stays deleted. Heroic and Lutris can each add single games to Steam too.

On an Ally the stick lights start as a rainbow; change them in Handheld Daemon's overlay and the change stays.

## What to expect

These come from the kernel and firmware every install has, not from anything made for handhelds, and none have been tried on these devices here:

- **Screen, brightness, Wi-Fi, Bluetooth, battery, sound**: the standard drivers. The Deck LCD's Wi-Fi is Realtek, the OLED's Qualcomm and the Ally's MediaTek. The Deck's speakers don't get the sound processing SteamOS gives them, so they can sound thinner.
- **Fans**: left to the firmware's own curve on both. Handheld Daemon can set a curve on an Ally.
- **Power limits on a Deck**: Steam's performance slider needs SteamOS's own helpers, which this hasn't got, so expect it to do nothing.
- **Firmware updates**: neither is on LVFS, so `fwupd` doesn't update them. Update an Ally's BIOS from its own setup screen or Windows, and a Deck's from SteamOS.
- **Docking**: external screens over USB-C work as on any AMD laptop.

## When something goes wrong

- **An older build, after a bad update**: on a Deck, the d-pad and A should work in the boot menu, as the Deck's firmware passes them on. On an Ally, hold volume down at power-on, pick **Boot Menu** and then Ephemeral Nix; started that way, its d-pad should work in the boot menu too. Neither has been tried yet; a keyboard always works. Press a key while the menu shows and pick the older build, as [When something breaks](troubleshooting.md) says.
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
- OpenSnitch is off, whatever `useOpenSnitch` says: Game Mode can't show its questions, so it would block Steam. [Decky Loader](#launchers-and-decky), if you pick it, runs as root.

