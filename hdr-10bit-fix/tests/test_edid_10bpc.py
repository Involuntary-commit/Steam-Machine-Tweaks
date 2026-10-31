"""Tests for edid-10bpc.py. Run: python3 -m unittest discover -s tests"""
import importlib.util
import pathlib
import unittest

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("edid10bpc", HERE.parent / "edid-10bpc.py")
edid = importlib.util.module_from_spec(spec)
spec.loader.exec_module(edid)


def checksum_ok(data):
    return all(sum(data[b * 128:(b + 1) * 128]) % 256 == 0 for b in range(len(data) // 128))


def base_block(version=(1, 3), depth_bits=0):
    b = bytearray(128)
    b[0:8] = edid.HEADER
    b[8:10] = b"\x10\xac"  # manufacturer "DEL" (placeholder)
    b[18], b[19] = version
    b[20] = 0x80 | (depth_bits << 4)  # digital input
    b[21], b[22], b[23] = 121, 68, 120  # 121x68 cm, gamma 2.2
    # 1920x1080@60 detailed timing, 148.5 MHz
    b[54:72] = bytes.fromhex("023a801871382d40582c4500c48e2100001e")
    b[72:90] = bytes.fromhex("000000fc0054657374205456200a20202020")
    b[126] = 1
    edid.fix_checksum(b, 0)
    return b


def cta_block(*blocks):
    b = bytearray(128)
    b[0], b[1], b[3] = 0x02, 0x03, 0x70
    payload = b"".join(blocks)
    b[4:4 + len(payload)] = payload
    b[2] = 4 + len(payload)
    edid.fix_checksum(b, 0)
    return b


# Data blocks from a TCL 65Q750G. Flags, TMDS and HF-VSDB bytes are as read from
# the TV; the VSDB physical address is a placeholder.
HDMI_VSDB = bytes.fromhex("6e030c001000b83c21008001020304")
HF_VSDB = bytes.fromhex("6ad85dc4017880670230f0")
HF_SCDB = bytes.fromhex("ea79000001788067023000")


def tv_edid(*blocks, **base):
    return base_block(**base) + cta_block(*(blocks or (HDMI_VSDB, HF_VSDB)))


class PatchTests(unittest.TestCase):
    def test_tcl_tv_matches_known_good_fix(self):
        data = tv_edid()
        changes = edid.patch(data)
        vsdb = 128 + 4
        hf = vsdb + len(HDMI_VSDB)
        self.assertEqual(data[vsdb + 6], 0x98)  # was 0xb8: DC_36bit cleared, DC_30bit kept
        self.assertEqual(data[hf + 7], 0x61)  # was 0x67: 12/16-bit 4:2:0 cleared, FRL kept
        self.assertEqual(len(changes), 2)
        self.assertTrue(checksum_ok(data))

    def test_only_deep_color_bytes_change(self):
        before = tv_edid()
        after = bytearray(before)
        edid.patch(after)
        diff = [i for i in range(len(before)) if before[i] != after[i]]
        self.assertEqual(diff, [128 + 4 + 6, 128 + 4 + len(HDMI_VSDB) + 7, 255])

    def test_hf_scdb(self):
        data = tv_edid(HDMI_VSDB, HF_SCDB)
        edid.patch(data)
        self.assertEqual(data[128 + 4 + len(HDMI_VSDB) + 7], 0x61)
        self.assertTrue(checksum_ok(data))

    def test_edid_14_base_depth_lowered(self):
        data = tv_edid(version=(1, 4), depth_bits=4)  # 12 bits
        edid.patch(data)
        self.assertEqual(edid.base_depth(data), 10)
        self.assertTrue(checksum_ok(data))

    def test_edid_14_base_depth_10_untouched(self):
        data = tv_edid(version=(1, 4), depth_bits=3)
        self.assertEqual(edid.base_depth(data), 10)
        before = bytes(data)
        edid.patch(data)
        self.assertEqual(bytes(data[:128]), before[:128])

    def test_idempotent(self):
        data = tv_edid()
        edid.patch(data)
        once = bytes(data)
        self.assertEqual(edid.patch(data), [])
        self.assertEqual(bytes(data), once)

    def test_report_flags_before_and_after(self):
        data = tv_edid()
        self.assertTrue(edid.report(data))
        edid.patch(data)
        self.assertFalse(edid.report(data))

    def test_non_cta_extension_ignored(self):
        data = base_block() + bytearray(b"\x70" + bytes(127))  # DisplayID
        self.assertEqual(edid.deep_color_flags(data), [])


if __name__ == "__main__":
    unittest.main()
