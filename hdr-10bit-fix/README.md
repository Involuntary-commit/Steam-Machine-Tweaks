# HDR Flicker Fix

Stops your TV from flickering or showing "No signal" when HDR is on at **4K 120Hz**.

Tested on a **TCL 65Q750G**. Other TCL TVs, and TVs from other brands, can have the same problem. The menu tells you whether yours does.

This is a follow-up to beaglemoo's [HDMI 2.1 patch](https://github.com/beaglemoo/steam-machine-hdmi21), which makes 4K 120Hz possible on the Steam Machine. Install that patch first.

You won't notice any change in picture quality.

## Install

1. Press the **Steam** button → **Power** → **Switch to Desktop**.
2. Open the app menu (bottom left) and start **Konsole**.
3. Copy this line, paste it into Konsole (right-click → **Paste**), and press **Enter**:

   ```
   cd ~ && curl -fsSL https://github.com/Involuntary-commit/Steam-Machine-Tweaks/releases/latest/download/hdr-10bit-fix.tar.gz | tar xz && bash hdr-10bit-fix/edid-10bpc.sh
   ```

4. Type your password and press **Enter**. Nothing appears while you type. That's normal.
5. Type **1** and press **Enter** to try the fix.
6. Unplug the HDMI cable for 5 seconds, then plug it back in.
7. Flicker gone? Type **2** and press **Enter** to keep the fix, then **y** to restart.

**No password yet?** In Konsole, type `passwd`, press **Enter**, and choose one. Then go back to step 3.

**Good practice:** this fix changes boot settings with administrator rights. You can see exactly what it changes in the **What it changes on your Steam Machine** section below.

## Remove it

Follow steps 1 to 4 again, then type **3**.

## Good to know

- **Not sure it worked?** Run the same line again. The menu shows `Fix: installed` and `HDMI link: 4:4:4, 10-bit`.
- **After a SteamOS update:** if the flicker comes back, run the line again and choose **2**.
- **If anything goes wrong**, the Steam Machine simply uses your TV's normal settings again. The flicker may return, but the screen won't go black.

---

<details>
<summary><b>Is this fix for me?</b></summary>

It is if all of these are true:

- Your Steam Machine uses the community [HDMI 2.1 patch](https://github.com/beaglemoo/steam-machine-hdmi21) for 4K 120Hz.
- The screen flickers or says "No signal" at 4K 120Hz with HDR on, even with VRR off.
- The problem goes away at 4K 60Hz.

When you open the menu, it shows `HDMI link: 4:4:4, 12-bit` if the fix applies to you.

Tested on a TCL 65Q750G with SteamOS 3.9.5 and kernel 7.2.7-valve2.

</details>

<details>
<summary><b>Why it happens</b></summary>

Your TV tells the Steam Machine which color depths it supports, through a small built-in data file called the **EDID**. When the EDID lists 12-bit color, the patched graphics driver uses 12-bit at 4K 120Hz without checking that it fits through the HDMI cable's link.

On TVs whose HDMI 2.1 link tops out at 48 Gbps (12 Gbps on each of 4 lanes), about 42.67 Gbps is left for the picture:

| Mode (RGB 4:4:4) | Pixel clock | 10-bit | 12-bit |
|---|---|---|---|
| 4K 120Hz (standard timing) | 1188 MHz | ~35.6 Gbps | **~42.8 Gbps** |
| 4K 144Hz (TCL 65Q750G timing) | 1343.5 MHz | ~40.3 Gbps | ~48.4 Gbps |

12-bit at 4K 120Hz needs slightly more than the link can carry. The link keeps dropping and reconnecting, and each reconnect is a flicker. At 10-bit, it fits with room to spare.

These figures leave out error-correction overhead, so the real headroom is smaller. 4K 144Hz HDR at 10-bit has not been tested.

HDR games are made in 10-bit, so capping the output at 10-bit loses nothing visible.

</details>

<details>
<summary><b>What it changes on your Steam Machine</b></summary>

The fix gives the graphics driver an edited copy of your TV's EDID that no longer lists 12-bit or 16-bit color. Nothing else in the EDID changes.

| EDID section | Flags removed | Left as is |
|---|---|---|
| HDMI 1.4 VSDB, byte 6 | DC_36bit, DC_48bit | DC_30bit, DC_Y444 |
| HDMI Forum VSDB or HF-SCDB, byte 7 | DC_36bit_420, DC_48bit_420 | DC_30bit_420, FRL rate |
| EDID 1.4 base block, byte 20 | A declared depth above 10 bits is lowered to 10 | Everything else |

Installing adds these files:

| File | Purpose |
|---|---|
| `/etc/firmware-edid/original-HDMI-A-1.bin` | Backup of your TV's own EDID |
| `/etc/firmware-edid/edid/HDMI-A-1-10bpc.bin` | The edited EDID |
| `/etc/mkinitcpio.conf.d/90-edid-10bpc.conf` | Puts the edited EDID in the boot image |
| `/etc/default/grub.d/edid-10bpc.cfg` | Adds the boot option `drm.edid_firmware=HDMI-A-1:edid/HDMI-A-1-10bpc.bin` |
| `/etc/atomic-update.conf.d/edid-10bpc.conf` | Asks SteamOS updates to keep these files |

Removing the fix deletes all of them except the backup.

The boot-image rebuild prints `ERROR: module not found: 'blake2b_generic'`. This is normal on SteamOS and harmless. The menu hides this output and saves it to `/tmp/edid-10bpc.log`.

</details>

<details>
<summary><b>Limitations</b></summary>

- **SteamOS updates:** the fix's files are on SteamOS's keep list, but the fix hasn't been tested across an update yet.
- **A workaround, not a cure:** the real fix belongs in the HDMI 2.1 patch, which should fall back to 10-bit whenever 12-bit doesn't fit.
- **One TV per port:** the fix stores the EDID of the TV connected when you installed it. If you switch TVs, remove the fix, restart, and install it again.
- **TV on another port:** the fix assumes `HDMI-A-1`. To use another port, start the last part of the command with `CONNECTOR=HDMI-A-2`, as in `CONNECTOR=HDMI-A-2 bash hdr-10bit-fix/edid-10bpc.sh`. Run `ls /sys/class/drm/` to see port names.

</details>

<details>
<summary><b>Advanced: commands without the menu</b></summary>

From the `hdr-10bit-fix` folder:

| Command | What it does |
|---|---|
| `sudo bash edid-10bpc.sh status` | Detailed report: EDID flags, boot option, link depth |
| `sudo bash edid-10bpc.sh test` | Fix on until the next restart |
| `sudo bash edid-10bpc.sh test-revert` | Test off without restarting |
| `sudo bash edid-10bpc.sh install` | Install permanently |
| `sudo bash edid-10bpc.sh uninstall` | Remove completely |

In the repository (not the download), run the tests with `python3 -m unittest discover -s tests -v`. They check that the edit produces exactly the byte changes verified on real hardware (`0xb8 → 0x98` and `0x67 → 0x61`), changes nothing else, and keeps every checksum valid.

</details>

## License

GPL-3.0. See [LICENSE](../LICENSE). Unofficial, not affiliated with Valve, and provided without warranty.
