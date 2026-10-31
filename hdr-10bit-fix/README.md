# HDR flicker fix for the Steam Machine (HDMI 2.1, 4K 120Hz)

With HDR on at **4K 120Hz** over HDMI 2.1, some TVs flicker every 20 seconds or so, or lose the signal entirely. This fix stops it by capping the Steam Machine's HDMI output at **10-bit color**.

You lose nothing visible. HDR games are made in 10-bit, and everything else is 8-bit.

## At a glance

| | |
|---|---|
| **Fixes** | Flicker or "No signal" with HDR at 4K 120Hz over HDMI 2.1 |
| **Time needed** | About 10 minutes, including one restart |
| **Try before installing** | Yes. The test mode lasts only until the next restart. |
| **Undo** | One command, then a restart |
| **If something goes wrong** | The Steam Machine falls back to your TV's own settings. The flicker may return, but the picture won't go black. |

## Commands

Run each command from the fix's folder (see [Install](#install)).

| Command | What it does |
|---|---|
| `sudo bash edid-10bpc.sh status` | Shows whether the fix is needed or active |
| `sudo bash edid-10bpc.sh test` | Turns the fix on until the next restart |
| `sudo bash edid-10bpc.sh test-revert` | Turns the test off without restarting |
| `sudo bash edid-10bpc.sh install` | Turns the fix on permanently |
| `sudo bash edid-10bpc.sh uninstall` | Removes the fix completely |

## Does this apply to you?

This fix is for you if all of the following are true:

- Your Steam Machine runs SteamOS with HDMI 2.1 enabled by the community [steam-machine-hdmi21](https://github.com/beaglemoo/steam-machine-hdmi21) patch.
- The screen flickers or drops to "No signal" at **4K 120Hz with HDR on**, even with VRR off.
- The problem goes away at **4K 60Hz**.

The `status` command (step 3 below) confirms it: before the fix, it shows the HDMI link running at **12-bit**.

Tested on a TCL 65Q750G with SteamOS 3.9.5 and kernel 7.2.7-valve2. The HDMI 2.1 patch's author has tested the patch itself only on an LG C4.

## Why it happens

Your TV tells the Steam Machine which color depths it supports, using a small built-in data file called the **EDID**. When the EDID lists 12-bit color, the patched driver uses 12-bit at 4K 120Hz without checking that it fits through the HDMI link.

On TVs whose HDMI 2.1 link tops out at 48 Gbps (12 Gbps on each of 4 lanes), about **42.67 Gbps** is left for the picture after encoding:

| Mode (RGB 4:4:4) | Pixel clock | 10-bit | 12-bit |
|---|---|---|---|
| 4K 120Hz (standard timing, 4400 × 2250) | 1188 MHz | ~35.6 Gbps | **~42.8 Gbps** |
| 4K 144Hz (TCL 65Q750G timing) | 1343.5 MHz | ~40.3 Gbps | ~48.4 Gbps |

12-bit at 4K 120Hz needs slightly more than the link can carry. The link keeps failing and reconnecting, and each reconnect is a flicker. At 10-bit, it fits with room to spare.

These figures are pixel clock × bits per pixel. They leave out error-correction and packet overhead, so the real headroom is smaller than shown. 4K 144Hz HDR at 10-bit is close to the limit and has not been tested.

## What the fix changes

The fix gives the driver an edited copy of your TV's EDID that no longer lists 12-bit or 16-bit color. Nothing else in the EDID changes.

`edid-10bpc.py` clears only these flags, then recalculates the checksums:

| EDID section | Flags cleared | Left as is |
|---|---|---|
| HDMI 1.4 VSDB (OUI 00-0C-03), byte 6 | DC_36bit, DC_48bit (12- and 16-bit 4:4:4) | DC_30bit, DC_Y444 |
| HDMI Forum VSDB or HF-SCDB, byte 7 | DC_36bit_420, DC_48bit_420 | DC_30bit_420, FRL rate |
| EDID 1.4 base block, byte 20 | A declared depth above 10 bits is lowered to 10 | Everything else |

The permanent install (`edid-10bpc.sh install`) then:

1. Saves your TV's own EDID to `/etc/firmware-edid/original-HDMI-A-1.bin`.
2. Writes the edited copy to `/etc/firmware-edid/edid/HDMI-A-1-10bpc.bin`.
3. Adds the edited copy to the boot image (`/etc/mkinitcpio.conf.d/90-edid-10bpc.conf`), so it is available before the graphics driver starts.
4. Adds `firmware_class.path=/etc/firmware-edid drm.edid_firmware=HDMI-A-1:edid/HDMI-A-1-10bpc.bin` to the boot options (`/etc/default/grub.d/edid-10bpc.cfg`), the same way the HDMI 2.1 patch adds its own.
5. Lists these files in `/etc/atomic-update.conf.d/edid-10bpc.conf`, so SteamOS updates keep them.
6. Rebuilds the boot image and the boot menu.

**Fail-safe:** if the edited EDID ever fails to load, the Steam Machine falls back to the TV's own EDID. The worst case is the flicker coming back, not a black screen.

## Install

### 1. Open a terminal

Switch to **Desktop Mode** (Steam button → Power → Switch to Desktop) and open **Konsole** from the application menu. You can also connect over SSH from another computer.

The fix needs `sudo`, which asks for your password. If you have never set one, run `passwd` and choose one first.

### 2. Download the fix

```bash
cd ~
curl -L https://github.com/Involuntary-commit/Steam-Machine-Tweaks/archive/refs/heads/main.tar.gz | tar xz
cd Steam-Machine-Tweaks-main/hdr-10bit-fix
```

Run all of the following commands from this folder.

### 3. Check your setup

Set the display to 4K 120Hz with HDR on, keep the TV on, and run:

```bash
sudo bash edid-10bpc.sh status
```

If the **HDMI 2.1 link** line shows `12-bit`, this fix applies to you. The output looks like this:

```
Connector:      HDMI-A-1
Boot override:  not installed
EDID in use:
  12/16-bit color, 4:4:4 (HDMI VSDB): listed (byte 0x08a = 0xb8)
  12/16-bit color, 4:2:0 (HF-VSDB): listed (byte 0x09a = 0x67)
HDMI 2.1 link:  4:4:4, 12-bit
Result: the TV lists 12-bit color, so the driver can pick it. The fix is not active.
```

### 4. Try it until the next restart

This step changes nothing permanently. It only saves a backup of your TV's EDID.

```bash
sudo bash edid-10bpc.sh test
```

Unplug the HDMI cable for 5 seconds, then plug it back in. Watch for flicker for a few minutes, then run `status` again. The link should now show `10-bit` instead of `12-bit`.

To undo the test, restart the Steam Machine. To undo it without restarting, run `sudo bash edid-10bpc.sh test-revert` and replug the HDMI cable.

### 5. Make it permanent

```bash
sudo bash edid-10bpc.sh install
```

This takes a minute or two. At the end, you should see:

```
OK: EDID is in /boot/initramfs-linux-neptune-72.img
OK: boot option is set
```

(The image name depends on your SteamOS version.)

Along the way, SteamOS prints `ERROR: module not found: 'blake2b_generic'` and a few "Possibly missing" warnings. These are normal on SteamOS and harmless. The script checks the boot image itself.

Restart the Steam Machine, then run `status` once more. It should say `Boot override:  installed and active` and show the link at `10-bit`.

### TV on a different port

The commands assume the TV is on `HDMI-A-1`. To check, run `ls /sys/class/drm/`. Port names appear after the card number, as in `card0-HDMI-A-2`. If your TV is on another port, add `CONNECTOR=` and the port name after `sudo` in every command, for example:

```bash
sudo CONNECTOR=HDMI-A-2 bash edid-10bpc.sh status
```

## Uninstall

```bash
sudo bash edid-10bpc.sh uninstall
```

Then restart. The backup of your TV's EDID stays in `/etc/firmware-edid/` in case you need it later.

## Limitations

- **SteamOS updates:** the fix's files are on SteamOS's keep list, but the fix has not yet been tested across a SteamOS update. If the flicker comes back after an update, run `status`. If it says `Boot override:  not installed`, run `install` again.
- **A workaround, not a cure:** the real fix belongs in the HDMI 2.1 patch, which should fall back to 10-bit whenever 12-bit doesn't fit the link.
- **No 12-bit output:** nothing can use 12-bit color over HDMI while the fix is installed. HDR games use 10-bit, so they are unaffected.
- **One TV per port:** the fix stores the EDID of the TV that was connected when you installed it. If you connect a different TV or monitor to the same port, run `uninstall`, restart, then run `install` again.

## Tests

For developers:

```bash
python3 -m unittest discover -s tests -v
```

The tests rebuild the TCL 65Q750G's color-depth data and check that the patch:

- produces exactly the byte changes verified on real hardware (`0xb8 → 0x98` and `0x67 → 0x61`),
- changes nothing else,
- keeps every checksum valid,
- gives the same result when run twice.

## License

GPL-3.0. See [LICENSE](../LICENSE).

This is an unofficial community fix, not affiliated with Valve, and provided without warranty. It changes boot settings, so please read the script before running it.
