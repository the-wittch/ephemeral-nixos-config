# Handheld (beta)

`"desktop": "handheld"` turns a Steam Deck or a ROG Ally into something like SteamOS: it starts in Steam's Game Mode, and "Switch to Desktop" goes to Plasma. Underneath it's the same system as any other install: `/` wiped at every boot, `/persist`, the encrypted disk, backups and `ephemeral`. Steam's games and saves are in your home folder, which is kept.

It's a beta. It was built from what a ROG Xbox Ally X's controller sends and from the kernel's drivers, but it hasn't been run through on a handheld yet. Expect rough edges, and please report them.

## Installing

1. Plug in a USB keyboard. The installer can't be used with the controller yet.
2. On the Desktop screen, pick **Handheld**.
3. For the disk passphrase, use only the characters in the table below, so you can type it with the controller at boot. The installer won't take any other characters. Eight is the least it takes; ten or more is better.

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
- the ROG Xbox Ally X's own, without its back buttons, which only work once the system is up
- wired Xbox 360, One and Series pads, and Xbox 360 pads through Microsoft's wireless receiver
- wired DualShock 4 and DualSense pads

Bluetooth pads, and Xbox One and Series pads through the Xbox Wireless Adapter, work in Game Mode and on the desktop, but not at the prompt.

## Game Mode and the desktop

- **To the desktop**: Steam's power menu, "Switch to Desktop".
- **Back to Game Mode**: "Return to Game Mode" in Plasma's launcher. Logging out does the same, and every boot starts in Game Mode.
- **Updates**: Steam's own system update button does nothing here. Update from the desktop with `ephemeral update`, as on any other install.

On an Ally, [Handheld Daemon](https://github.com/hhd-dev/hhd) runs the back buttons, the power limits and the stick lights.

## Not done yet

- Using the installer with the controller, and an on-screen keyboard in it.
- Decky Loader and NonSteamLaunchers as apps to pick.
- Anything that has to be typed when the system can't start, such as the emergency shell, needs a keyboard.
