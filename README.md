# Steam Machine Tweaks

Fixes and add-ons for the Valve Steam Machine on SteamOS.

Each tweak lives in its own folder, with a guide that walks you through it step by step. You don't need any coding experience, only a few minutes in Desktop Mode.

## Tweaks

| Tweak | What it does | Can be undone |
|---|---|---|
| [HDR flicker fix](hdr-10bit-fix/) | Stops flicker and "No signal" with HDR at 4K 120Hz over HDMI 2.1. Caps the HDMI output at 10-bit color, with no visible loss. | Yes, with one command |

## Before you start

- **Desktop Mode:** every tweak is installed from Desktop Mode (Steam button → Power → Switch to Desktop), using the **Konsole** terminal app.
- **Password:** most tweaks need `sudo`, which asks for your password. If you have never set one, run `passwd` in Konsole first.
- **Read first:** each guide explains exactly what the tweak changes and how to undo it. Please read it before running anything.

## License

GPL-3.0. See [LICENSE](LICENSE).

This is an unofficial community project, not affiliated with Valve, and provided without warranty.
