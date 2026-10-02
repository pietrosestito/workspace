#!/usr/bin/env python3
"""Replace one NROM-128 game inside a SUP / VT02 multicart flash dump with Box Hero.

The menu of these multicarts starts each game by pointing the VT02 banking registers
at that game's PRG and CHR inside the flash. If we overwrite an NROM-128 game
(16 KB PRG + 8 KB CHR) in place with a ROM of the same layout, the menu keeps working
and the old entry now launches our game (the name in the menu does not change).

Locate the victim game either by giving its .nes file (searched in the dump) or by
passing the offsets found by hand with a hex editor.

  patch_multicart.py dump.bin build/boxhero.nes out.bin --victim original_game.nes
  patch_multicart.py dump.bin build/boxhero.nes out.bin --prg 0x1A0000 --chr 0x1B0000

Some boards store the flash with swapped address/data lines or byte-swapped words;
if the victim game is not found, try --swap16 (16-bit word byte swap).
"""
import argparse
import sys


def read_nes(path):
    data = open(path, 'rb').read()
    if data[:4] != b'NES\x1a':
        sys.exit(f"{path}: not an iNES file")
    prg_size, chr_size = data[4] * 16384, data[5] * 8192
    trainer = 512 if data[6] & 4 else 0
    prg = data[16 + trainer:16 + trainer + prg_size]
    chr_ = data[16 + trainer + prg_size:16 + trainer + prg_size + chr_size]
    mapper = (data[6] >> 4) | (data[7] & 0xF0)
    return prg, chr_, mapper, data[6] & 1


def swap16(b):
    out = bytearray(b)
    out[0::2], out[1::2] = b[1::2], b[0::2]
    return out


def find_unique(dump, needle, what):
    pos = dump.find(needle)
    if pos < 0:
        sys.exit(f"{what} of the victim game not found in the dump")
    if dump.find(needle, pos + 1) >= 0:
        sys.exit(f"{what} found more than once: pass the offset by hand")
    return pos


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('dump')
    ap.add_argument('rom')
    ap.add_argument('out')
    ap.add_argument('--victim', help='.nes file of the game to replace')
    ap.add_argument('--prg', type=lambda s: int(s, 0), help='PRG offset in the dump')
    ap.add_argument('--chr', type=lambda s: int(s, 0), help='CHR offset in the dump')
    ap.add_argument('--swap16', action='store_true', help='dump has byte-swapped 16-bit words')
    a = ap.parse_args()

    dump = bytearray(open(a.dump, 'rb').read())
    if a.swap16:
        dump = swap16(dump)
    prg, chr_, mapper, _ = read_nes(a.rom)
    if mapper != 0 or len(prg) != 16384 or len(chr_) != 8192:
        sys.exit("the new ROM must be NROM-128 (16 KB PRG + 8 KB CHR)")

    if a.victim:
        vprg, vchr, vmapper, vmirror = read_nes(a.victim)
        if vmapper != 0 or len(vprg) != 16384 or len(vchr) != 8192:
            sys.exit("the victim must also be an NROM-128 game (16 KB PRG + 8 KB CHR)")
        if vmirror != 1:
            print("warning: the victim uses horizontal mirroring; Box Hero needs vertical "
                  "mirroring, the background may scroll wrongly. Pick a horizontally "
                  "scrolling game as the victim.")
        prg_off = find_unique(dump, vprg, "PRG")
        chr_off = find_unique(dump, vchr, "CHR")
    elif a.prg is not None and a.chr is not None:
        prg_off, chr_off = a.prg, a.chr
    else:
        sys.exit("give --victim, or both --prg and --chr")

    for off, size in ((prg_off, 16384), (chr_off, 8192)):
        if off < 0 or off + size > len(dump):
            sys.exit(f"offset 0x{off:X} is outside the dump")
    dump[prg_off:prg_off + 16384] = prg
    dump[chr_off:chr_off + 8192] = chr_
    if a.swap16:
        dump = swap16(dump)
    open(a.out, 'wb').write(dump)
    print(f"PRG written at 0x{prg_off:X}, CHR at 0x{chr_off:X} -> {a.out}")


if __name__ == '__main__':
    main()
