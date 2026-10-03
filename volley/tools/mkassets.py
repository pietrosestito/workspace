#!/usr/bin/env python3
"""Build all SUP VOLLEY graphics: CHR-ROM, the two nametables and the metasprite tables.

The background screens are drawn here with NES rules enforced (one 3-colour palette per
16x16 block), then cut into 8x8 tiles and de-duplicated. Font glyphs keep their ASCII code
as tile index so the game can print text at run time.

usage: mkassets.py OUTDIR   -> chr.bin, title.nam, game.nam, assets.inc
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'tools'))
from mkchr import FONT  # noqa: E402  (shared 5x7 font)

# ------------------------------------------------------------------ palettes
BACKDROP = 0x21
BGPAL = [(0x0F, 0x10, 0x30),   # 0 sky: shadow, grey, white (text, clouds, net)
         (0x11, 0x2C, 0x30),   # 1 sea
         (0x37, 0x27, 0x17),   # 2 sand
         (0x28, 0x1A, 0x17)]   # 3 sun / palm
SPRPAL = [(0x27, 0x17, 0x0F),  # 0 faces, ball shadow, cursor
          (0x30, 0x10, 0x0F),  # 1 hair
          (0x2A, 0x1A, 0x27),  # 2 Nonno body
          (0x16, 0x30, 0x27)]  # 3 Toro body, ball

# ------------------------------------------------------------------ characters (24x40)
def mirror(rows):
    for r in rows:
        assert len(r) == 12, (len(r), r)
    return [r + r[::-1] for r in rows]

NONNO_HAIR = mirror([
    "........3333", ".....3331111", "....31112211", "...311211122",
    "..3112111211", "..3121112111", ".31211211122", ".31211211111"])
NONNO_FACE = mirror([
    ".21111111111", ".21112221122", ".21111111111", "211333331111",
    "211111111111", "211233321111", "211112221121", "211111111211",
    "211112111331", "211111333333", "211133333333", "213333333333",
    "233331112222", ".21111111111", "..2211111111", "....22222222"])
TORO_HAIR = mirror([
    "......3.3.33", "....3.333333", "...333323333", "..3333233332",
    "..3332333323", ".33323333233", ".33233332333", ".33333333333"])
TORO_FACE = mirror([
    ".33111111111", ".31111111111", ".21111111111", "211331111111",
    "211133311111", "211233211111", "211111111121", "211111111211",
    "211112111331", "211111111111", "211111122222", "211111111111",
    "211111113333", ".21111113333", "..2211113333", "....22223333"])
BODY_TOP = mirror([   # 1 shirt, 2 shirt shade / shorts, 3 skin
    ".......23333", ".....2233333", "....23311333", "...233311333",
    "..2332111133", "..2332111111", "..2332111111", "..2332211111",
    "...333222222", "....22222222", "....22222222"])
LEGS = {
    'stand': ["......3333....3333......", "......3333....3333......", "......3333....3333......",
              ".....22222....22222.....", ".....22222....22222....."],
    'walk':  [".....3333......3333.....", "....3333........3333....", "....3333........3333....",
              "...22222........22222...", "...22222........22222..."],
    'jump':  [".....33333....33333.....", ".....22222....22222.....", "........................",
              "........................", "........................"],
}

# ------------------------------------------------------------------ ball, shadow, cursor
def ball_art(phase):
    rows = []
    for y in range(16):
        r = ''
        for x in range(16):
            dx, dy = x - 7.5, y - 7.5
            if dx * dx + dy * dy > 7.6 ** 2:
                r += '.'
                continue
            seam = (abs(dy - 3.2 * math.sin((x + 1 + phase) / 2.6)) < 0.75 or
                    abs(dx + 2.5 * math.sin((y + 2 + phase) / 3.0) - 2) < 0.7)
            r += '1' if seam else '2'
        rows.append(r)
    return rows

SHADOW = ["................", "................", "....22222222....", "..222222222222..",
          "..222222222222..", "....22222222....", "................", "................"]
CURSOR = ["........", ".33.....", ".3333...", ".333333.", ".3333...", ".33.....", "........", "........"]

# ------------------------------------------------------------------ NES-rule canvas
class Screen:
    def __init__(self):
        self.idx = [[0] * 256 for _ in range(240)]
        self.bpal = [[None] * 16 for _ in range(15)]

    def px(self, x, y, pal, i):
        if not (0 <= x < 256 and 0 <= y < 240):
            return
        if i == 0:
            self.idx[y][x] = 0
            return
        b = self.bpal[y // 16][x // 16]
        if b is None:
            self.bpal[y // 16][x // 16] = b = pal
        if b != pal:
            raise SystemExit(f"palette clash in 16x16 block ({x // 16},{y // 16}): {b} vs {pal}")
        self.idx[y][x] = i

    def fill(self, x0, y0, x1, y1, pal, fn):
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.px(x, y, pal, fn(x, y))

    def text(self, s, tx, ty, pal=0, col=3, scale=1, shadow=False):
        for n, ch in enumerate(s):
            glyph = FONT.get(ch)
            if not glyph:
                continue
            for gy, row in enumerate(glyph.split()):
                for gx, c in enumerate(row):
                    if c != '#':
                        continue
                    for sy in range(scale):
                        for sx in range(scale):
                            x = tx * 8 + n * 8 * scale + (gx + 1) * scale + sx
                            y = ty * 8 + gy * scale + sy
                            if shadow and self.idx[y + 1][x + 1] == 0:
                                self.px(x + 1, y + 1, pal, 1)
                            self.px(x, y, pal, col)


def beach(s, net, clouds):
    # sea y 112..159 and sand y 160..239, aligned to 16-pixel attribute blocks
    s.fill(0, 112, 256, 120, 1, lambda x, y: 3 if (x % 8 + y) % 4 == 0 else 2)
    s.fill(0, 120, 256, 160, 1, lambda x, y: 2 if ((x % 16) - (y % 16) * 2) % 16 == 0 and y % 2 == 0 else 1)
    dots = [((2, 3), (11, 9)), ((6, 12), (13, 2)), ((9, 6), (1, 14))]

    def sand(x, y):
        if y < 162:
            return 2
        variant = dots[((x // 16) * 7 + (y // 16) * 3) % 3]
        if (x % 16, y % 16) in variant:
            return 3
        return 2 if y >= 216 else 1
    s.fill(0, 160, 256, 240, 2, sand)
    # sun and palm (palette 3)
    s.fill(208, 32, 240, 64, 3, lambda x, y: 1 if (x - 223.5) ** 2 + (y - 47.5) ** 2 < 13 ** 2 else 0)
    for y in range(48, 112):
        tx = int(18 - (y - 48) * 0.06 + 2 * math.sin(y / 14))
        for x in range(tx, tx + 6):
            s.px(x, y, 3, 3)
    for k in range(6):
        ang = -2.6 + k * 0.55
        for t in range(26):
            x = int(20 + math.cos(ang) * t)
            y = int(48 + math.sin(ang) * t * 0.6 + (t / 9) ** 2)
            for d in range(-2, 3):
                if 0 <= y + d < 112:
                    s.px(x, y + d, 3, 2)
    for cx, cy in clouds:
        s.fill(cx - 24, cy - 8, cx + 24, cy + 8, 0, lambda x, y, cx=cx, cy=cy:
               3 if ((x - cx) / 22) ** 2 + ((y - cy) / 6) ** 2 < 1 or
               ((x - cx + 6) / 10) ** 2 + ((y - cy + 5) / 6) ** 2 < 1 else 0)
    if net:
        for y in range(112, 200):           # pole: white on sea, brown on sand
            for x in range(126, 130):
                s.px(x, y, 1 if y < 160 else 2, 3)
        for y in range(120, 152):           # tape at y 120, mesh below
            for x in range(120, 136):
                if y in (120, 121) or y == 151 or (x + y) % 4 == 0 or (x - y) % 4 == 0:
                    s.px(x, y, 1, 3)


def title_screen():
    s = Screen()
    beach(s, net=False, clouds=((196, 92),))
    s.text("SUP", 10, 3, scale=2, shadow=True)
    s.text("VOLLEY", 7, 6, scale=2, shadow=True)
    s.text("PREMI START", 10, 10)
    s.text("1 GIOCATORE", 10, 22, pal=2, col=3)
    s.text("2 GIOCATORI", 10, 24, pal=2, col=3)
    s.text("(C) 2026", 12, 27, pal=2, col=3)
    return s


def game_screen():
    s = Screen()
    beach(s, net=True, clouds=((90, 36), (176, 30)))
    s.text("NONNO 00", 2, 1)
    s.text("TORO 00", 23, 1)
    return s

# ------------------------------------------------------------------ tile encoding
def encode(tile):
    lo = bytes(sum(((tile[y][x] & 1) << (7 - x)) for x in range(8)) for y in range(8))
    hi = bytes(sum(((tile[y][x] >> 1) << (7 - x)) for x in range(8)) for y in range(8))
    return lo + hi


def font_tile(ch):
    t = [[0] * 8 for _ in range(8)]
    for gy, row in enumerate(FONT[ch].split()):
        for gx, c in enumerate(row):
            if c == '#':
                t[gy][gx + 1] = 3
    return t


class BgTiles:
    """Background pattern table: font at ASCII codes, scene tiles in the free slots."""
    def __init__(self):
        self.slots = {}                    # tile tuple -> index
        self.data = bytearray(4096)
        self.free = [i for i in range(256) if not 0x20 <= i < 0x60]
        self.add(tuple([0] * 64), 0)       # tile 0 = blank sky
        self.free.remove(0)
        for ch in FONT:
            self.add(tuple(v for row in font_tile(ch) for v in row), ord(ch))
        self.add(tuple([0] * 64), 0x20)    # space

    def add(self, key, index):
        self.slots.setdefault(key, index)
        rows = [list(key[i * 8:i * 8 + 8]) for i in range(8)]
        self.data[index * 16:index * 16 + 16] = encode(rows)

    def get(self, key):
        if key in self.slots:
            return self.slots[key]
        if not self.free:
            raise SystemExit("background needs more than 256 tiles")
        i = self.free.pop(0)
        self.add(key, i)
        return i


def nametable(screen, tiles):
    nam = bytearray(1024)
    for ty in range(30):
        for tx in range(32):
            key = tuple(screen.idx[ty * 8 + y][tx * 8 + x] for y in range(8) for x in range(8))
            nam[ty * 32 + tx] = tiles.get(key)
    for ay in range(8):
        for ax in range(8):
            v = 0
            for q, (bx, by) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1))):
                bxx, byy = ax * 2 + bx, ay * 2 + by
                p = screen.bpal[byy][bxx] if byy < 15 else None
                v |= (p or 0) << (q * 2)
            nam[960 + ay * 8 + ax] = v
    return nam

# ------------------------------------------------------------------ sprites
class SprTiles:
    def __init__(self):
        self.data = bytearray(4096)
        self.n = 0

    def put(self, rows):
        assert self.n < 256
        t = [[0 if c == '.' else int(c) for c in r] for r in rows]
        self.data[self.n * 16:self.n * 16 + 16] = encode(t)
        self.n += 1
        return self.n - 1


def metasprite(spr, art, pal_for_row):
    """Cut art into 8x8 tiles, skipping empty ones. Returns [(dx, dy, tile, attr)]."""
    out = []
    for ty in range(0, len(art), 8):
        for tx in range(0, len(art[0]), 8):
            tile = [r[tx:tx + 8] for r in art[ty:ty + 8]]
            if all(set(r) <= {'.'} for r in tile):
                continue
            out.append((tx, ty, spr.put(tile), pal_for_row(ty)))
    return out


def main():
    out = sys.argv[1]
    tiles = BgTiles()
    title = nametable(title_screen(), tiles)
    game = nametable(game_screen(), tiles)

    spr = SprTiles()
    spr.put(["........"] * 8)                     # tile 0 unused / blank
    lines = ["; generated by tools/mkassets.py - do not edit"]
    names = []
    for cname, hair, face, body_pal in (("nonno", NONNO_HAIR, NONNO_FACE, 2), ("toro", TORO_HAIR, TORO_FACE, 3)):
        for pose in ("stand", "walk", "jump"):
            art = hair + face + BODY_TOP + LEGS[pose]
            assert len(art) == 40 and all(len(r) == 24 for r in art)
            ms = metasprite(spr, art, lambda ty: 1 if ty < 8 else 0 if ty < 24 else body_pal)
            label = f"ms_{cname}_{pose}"
            names.append(label)
            lines.append(f"{label}: .byte {len(ms)}")
            for dx, dy, t, a in ms:
                lines.append(f"  .byte {dx},{dy},${t:02X},{a}")
    for i in range(2):
        ms = metasprite(spr, ball_art(i * 3), lambda ty: 3)
        lines.append(f"ms_ball{i}: .byte {len(ms)}")
        for dx, dy, t, a in ms:
            lines.append(f"  .byte {dx},{dy},${t:02X},{a}")
    ms = metasprite(spr, SHADOW, lambda ty: 0)
    lines.append(f"ms_shadow: .byte {len(ms)}")
    for dx, dy, t, a in ms:
        lines.append(f"  .byte {dx},{dy},${t:02X},{a}")
    lines.append(f"TILE_CURSOR = ${spr.put(CURSOR):02X}")
    lines.append("char_ms_lo: .byte " + ",".join(f"<{n}" for n in names))
    lines.append("char_ms_hi: .byte " + ",".join(f">{n}" for n in names))
    pal = [c for p in BGPAL + SPRPAL for c in (BACKDROP,) + p]
    lines.append("palette: .byte " + ",".join(f"${c:02X}" for c in pal))

    with open(os.path.join(out, 'chr.bin'), 'wb') as f:
        f.write(tiles.data + spr.data)
    with open(os.path.join(out, 'title.nam'), 'wb') as f:
        f.write(title)
    with open(os.path.join(out, 'game.nam'), 'wb') as f:
        f.write(game)
    with open(os.path.join(out, 'assets.inc'), 'w') as f:
        f.write("\n".join(lines) + "\n")
    used_bg = 256 - len(tiles.free)
    print(f"background tiles: {used_bg}/256, sprite tiles: {spr.n}/256")


if __name__ == '__main__':
    main()
