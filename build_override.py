"""Build an EDID override that adds refresh rates to the Razer Blade 14 (2023) internal panel
(AUO B140QAN06.U, Windows ID AUO5DA7).

AMD Adrenalin 24.9.1+ drops the panel's 240 Hz mode, leaving only 60 Hz. It still accepts modes whose
uncompressed bandwidth fits the eDP link (pixel clock up to ~690 MHz), so this script adds such
modes to the panel's own EDID.

    python build_override.py                     # 120 and 144 Hz -> override_edid_60_120_144h2640.bin
    python build_override.py --rates 120,140     # -> override_edid_60_120_140.bin
    python build_override.py --rates 120 -o custom.bin

A rate R uses the panel's own 2720x1800 timing totals with the pixel clock scaled. R@H uses a
horizontal total of H instead (reduced blanking: front porch 8, sync 32), e.g. 144@2640 = 684.29 MHz.
One timing up to 655.35 MHz goes into the spare base-block descriptor slot; the rest go into the
panel's DisplayID 2.0 block next to its native 240 Hz timing (room for three). The original 60 and
240 Hz timings are kept. Rates must be 60-240 Hz: lower rates garbled this panel in testing.
"""
import argparse
import os
import sys

# The panel's original 256-byte EDID (base block + DisplayID 2.0 extension), as read from the panel.
ORIGINAL_EDID = bytes.fromhex(
    "00FFFFFFFFFFFF0006AFA75D0000000003200104A51E1378030F95AE5243B026"
    "0F505400000001010101010101010101010101010101C17200A0A040C8603020"
    "AA002DBC100000180000000F0000000000000000000000000020000000FD0C3C"
    "F0B2B276010A202020202020000000FE004231343051414E30362E55200A019C"
    "702079020022001406EE1184FF099F002F801F003F06C70009000900250109F7"
    "F011F7F0113CF080810010721A000003013CF0000060506050F0000000000000"
    "0000000000000000000000000000000000000000000000000000000000000000"
    "000000000000000000000000000000000000000000000000000000000000AB90"
)

PANEL_TOTALS = (2720, 1800)      # both native timings (60 and 240 Hz) use these totals
MAX_DTD_KHZ = 655350             # base-block DTD pixel clock field is 16 bits of 10 kHz
SPARE_SLOT = 0x48                # base descriptor holding only a near-empty tag 0x0F descriptor
DID_SECTION = 129                # DisplayID section header inside the extension block
DID_BLOCKS = 133                 # first DisplayID data block


def fail(msg):
    sys.exit("error: " + msg)


def fix_checksum(buf, lo, at):
    buf[at] = (256 - sum(buf[lo:at])) & 0xFF


def checksums_ok(buf):
    return (sum(buf[0:128]) & 0xFF == 0 and sum(buf[128:256]) & 0xFF == 0
            and sum(buf[DID_SECTION:255]) & 0xFF == 0)


def parse_rates(text):
    rates = []
    for item in text.split(","):
        rate, _, htotal = item.strip().partition("@")
        try:
            rate, htotal = int(rate), int(htotal) if htotal else PANEL_TOTALS[0]
        except ValueError:
            fail(f"bad rate {item!r}; use R or R@HTOTAL, e.g. 120 or 144@2640")
        if not 60 <= rate <= 240:
            fail(f"{rate} Hz: use 60-240 Hz (lower rates garble this panel)")
        if not 2600 < htotal <= PANEL_TOTALS[0]:
            fail(f"{rate}@{htotal}: horizontal total must be 2601-2720")
        rates.append((rate, htotal))
    return rates


def pixel_khz(rate, htotal):
    return round(htotal * PANEL_TOTALS[1] * rate / 1000)


def make_dtd(native_dtd, khz):
    """Base-block detailed timing: the panel's 60 Hz DTD with a new pixel clock (same totals)."""
    dtd = bytearray(native_dtd)
    dtd[0:2] = (khz // 10).to_bytes(2, "little")
    return dtd


def make_type7(native_t7, khz, htotal):
    """DisplayID 2.0 Type VII timing: the panel's 240 Hz descriptor with a new clock and blanking."""
    t7 = bytearray(native_t7)
    t7[0:3] = (khz - 1).to_bytes(3, "little")        # pixel clock in kHz, minus one
    t7[3] &= 0x7F                                     # not the preferred timing
    if htotal != PANEL_TOTALS[0]:
        hblank = htotal - (int.from_bytes(t7[4:6], "little") + 1)
        t7[6:8] = (hblank - 1).to_bytes(2, "little")
        t7[8:10] = ((8 - 1) | 0x8000).to_bytes(2, "little")   # front porch 8, keep H+ polarity
        t7[10:12] = (32 - 1).to_bytes(2, "little")             # sync width 32
    return t7


def build(rates):
    buf = bytearray(ORIGINAL_EDID)
    if not checksums_ok(buf) or buf[8:12] != bytes.fromhex("06AFA75D"):
        fail("embedded EDID is damaged")
    if buf[128] != 0x70 or buf[DID_SECTION] != 0x20 or buf[DID_BLOCKS] != 0x22:
        fail("unexpected DisplayID layout")

    added = []
    native_dtd = buf[0x36:0x36 + 18]
    t7_len = buf[DID_BLOCKS + 2]
    t7_end = DID_BLOCKS + 3 + t7_len
    native_t7 = buf[DID_BLOCKS + 3:DID_BLOCKS + 23]
    new_t7 = bytearray()
    slot_free = True
    for rate, htotal in rates:
        khz = pixel_khz(rate, htotal)
        if slot_free and htotal == PANEL_TOTALS[0] and khz <= MAX_DTD_KHZ:
            buf[SPARE_SLOT:SPARE_SLOT + 18] = make_dtd(native_dtd, khz)
            slot_free = False
            where = "base block"
        else:
            new_t7 += make_type7(native_t7, khz, htotal)
            where = "DisplayID"
        note = "" if khz <= 690000 else "  (over ~690 MHz: new drivers drop to 6-bit or reject it)"
        added.append(f"{rate} Hz: {htotal}x{PANEL_TOTALS[1]} total, {khz / 1000:.2f} MHz ({where}){note}")

    if new_t7:
        section_end = DID_BLOCKS + buf[DID_SECTION + 1]   # DisplayID checksum byte sits here (254)
        tail = buf[t7_end:section_end]
        if any(tail[len(tail) - len(new_t7):]):
            fail("not enough free space in the DisplayID block for that many timings")
        buf[t7_end:section_end] = new_t7 + tail[:len(tail) - len(new_t7)]
        buf[DID_BLOCKS + 2] = t7_len + len(new_t7)

    fix_checksum(buf, 0, 127)
    fix_checksum(buf, DID_SECTION, 254)
    fix_checksum(buf, 128, 255)
    if not checksums_ok(buf):
        fail("checksum recompute failed")
    return bytes(buf), added


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rates", default="120,144@2640", help="comma-separated, R or R@HTOTAL (default 120,144@2640)")
    ap.add_argument("-o", "--output", help="output file (default: named after the rates)")
    ap.add_argument("--force", action="store_true", help="overwrite an existing output file")
    args = ap.parse_args()

    rates = parse_rates(args.rates)
    data, added = build(rates)
    out = args.output or "override_edid_60_" + "_".join(
        f"{r}" if h == PANEL_TOTALS[0] else f"{r}h{h}" for r, h in rates) + ".bin"
    if os.path.exists(out) and not args.force:
        fail(f"{out} exists; use --force to overwrite or -o to pick another name")
    with open(out, "wb") as f:
        f.write(data)
    print("kept: 60 Hz (base block) and 240 Hz (DisplayID, needs AMD 24.8.1)")
    for line in added:
        print("added:", line)
    print("wrote", out)


if __name__ == "__main__":
    main()
