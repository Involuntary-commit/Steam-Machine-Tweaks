#!/usr/bin/env python3
"""Caps an HDMI display's EDID at 10-bit color, so the GPU never picks 12- or 16-bit.

Clears these deep-color flags, then recalculates each block's checksum:
  - HDMI 1.4 VSDB (OUI 00-0C-03), byte 6: DC_48bit (bit 6) and DC_36bit (bit 5)
  - HDMI Forum VSDB (OUI C4-5D-D8) or HF-SCDB (extended tag 0x79), byte 7:
    DC_48bit_420 (bit 2) and DC_36bit_420 (bit 1)
  - EDID 1.4 base block, byte 20: a declared color depth above 10 bits is lowered to 10

10-bit (DC_30bit) and everything else stay as they are.

Usage:
  edid-10bpc.py IN.bin OUT.bin   write a patched copy
  edid-10bpc.py --report IN.bin  show the deep-color flags without changing anything
"""
import sys

HEADER = b"\x00\xff\xff\xff\xff\xff\xff\x00"
OUI_HDMI = b"\x03\x0c\x00"  # 00-0C-03, stored little-endian
OUI_HF = b"\xd8\x5d\xc4"  # C4-5D-D8
DEPTHS = {1: 6, 2: 8, 3: 10, 4: 12, 5: 14, 6: 16}


def fix_checksum(data, start):
    data[start + 127] = (256 - sum(data[start:start + 127]) % 256) % 256


def data_blocks(data, start):
    """Yield (absolute offset, tag, length) for each data block of a CTA-861 extension."""
    end = data[start + 2]
    i = 4
    while 4 <= i < end and i < 127:
        tag, length = data[start + i] >> 5, data[start + i] & 0x1F
        yield start + i, tag, length
        i += 1 + length


def deep_color_flags(data):
    """Return (offset, mask, kind) for every deep-color field present in the EDID."""
    fields = []
    for b in range(1, len(data) // 128):
        start = b * 128
        if data[start] != 0x02:  # CTA-861 extensions only
            continue
        for p, tag, length in data_blocks(data, start):
            if tag == 3 and length >= 6 and bytes(data[p + 1:p + 4]) == OUI_HDMI:
                fields.append((p + 6, 0x60, "4:4:4 (HDMI VSDB)"))
            elif tag == 3 and length >= 7 and bytes(data[p + 1:p + 4]) == OUI_HF:
                fields.append((p + 7, 0x06, "4:2:0 (HF-VSDB)"))
            elif tag == 7 and length >= 7 and data[p + 1] == 0x79:
                fields.append((p + 7, 0x06, "4:2:0 (HF-SCDB)"))
    return fields


def load(path):
    data = bytearray(open(path, "rb").read())
    if len(data) < 128 or len(data) % 128 or data[:8] != HEADER:
        sys.exit(f"{path}: not a valid EDID (wrong size or header)")
    return data


def base_depth(data):
    """Declared bits per color for an EDID 1.4 digital display, or None."""
    if data[18] == 1 and data[19] >= 4 and data[20] & 0x80:
        return DEPTHS.get((data[20] >> 4) & 0x07)
    return None


def report(data):
    depth = base_depth(data)
    if depth:
        print(f"Declared color depth (base block): {depth}-bit")
    fields = deep_color_flags(data)
    if not fields:
        print("No HDMI deep-color data found")
    for off, mask, kind in fields:
        state = "listed" if data[off] & mask else "removed"
        print(f"12/16-bit color, {kind}: {state} (byte {off:#05x} = {data[off]:#04x})")
    return any(data[off] & mask for off, mask, _ in fields) or (depth or 0) > 10


def patch(data):
    changes = []
    touched = set()
    if (base_depth(data) or 0) > 10:
        old = data[20]
        data[20] = (old & 0x8F) | (3 << 4)
        touched.add(0)
        changes.append(f"Declared color depth (base block): {old:#04x} -> {data[20]:#04x}")
    for off, mask, kind in deep_color_flags(data):
        old = data[off]
        if old & mask:
            data[off] = old & ~mask
            touched.add(off // 128)
            changes.append(f"12/16-bit color, {kind}: {old:#04x} -> {data[off]:#04x}")
    for b in touched:
        fix_checksum(data, b * 128)
    return changes


def main(argv):
    if len(argv) == 3 and argv[1] == "--report":
        return 1 if report(load(argv[2])) else 0
    if len(argv) != 3:
        sys.exit(__doc__.strip())
    data = load(argv[1])
    changes = patch(data)
    open(argv[2], "wb").write(data)
    print("\n".join(changes) or "No changes needed: this EDID already tops out at 10-bit.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
