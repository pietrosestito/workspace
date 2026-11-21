#!/usr/bin/env python3
"""Builds every PNG in nonno/assets/ from code, so the art stays reproducible.

Retro rules enforced here: every sprite/tile sheet uses at most 16 colours (plus
transparency), pixels are hard-edged, no alpha blending.

usage: mkassets.py [OUTDIR]
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'tools'))
import portrait  # noqa: E402
from mkchr import FONT  # noqa: E402  (shared 5x7 font of the NES games)

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'assets')
MAXCOL = 16
CLEAR = (0, 0, 0, 0)


def colours(im):
    a = np.array(im.convert('RGBA')).reshape(-1, 4)
    return {tuple(p[:3]) for p in a if p[3]}


def save(im, name, maxcol=MAXCOL):
    n = len(colours(im))
    assert n <= maxcol, f'{name}: {n} colours > {maxcol}'
    im.save(os.path.join(OUT, name))
    print(f'{name:18} {im.width}x{im.height}  {n} colours')


def outline(im, col):
    """1-px outline around the opaque area (outside only)."""
    a = np.array(im)
    m = np.pad(a[..., 3] > 0, 1)
    ring = np.zeros_like(m)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ring |= np.roll(np.roll(m, dy, 0), dx, 1)
    ring = (ring & ~m)[1:-1, 1:-1]
    a[ring] = col + (255,)
    return Image.fromarray(a)


def quantize_to(im, pal):
    """Snap every opaque pixel to the nearest colour of pal; alpha becomes 0/255."""
    a = np.array(im).astype(int)
    p = np.array(pal)
    d = ((a[..., None, :3] - p[None, None]) ** 2).sum(-1)
    out = np.zeros(a.shape, np.uint8)
    out[..., :3] = p[d.argmin(-1)]
    out[..., 3] = np.where(a[..., 3] > 110, 255, 0)
    return Image.fromarray(out)


# ------------------------------------------------------------------ Nonno
SK, GR, OL = portrait.skin, portrait.grey, portrait.OL
SHIRT, SHORT = portrait.SHIRT, portrait.SHORT
SHOE = (120, 70, 40)
FW, FH = 40, 52          # in-game frame (feet on row 50, outline on 51)


def nonno_head(big):
    """Head of the 64x94 portrait reduced to 28x30, snapped back to its own palette."""
    head = big.crop((2, 0, 62, 67))
    a = np.array(head).astype(float)
    a[..., :3] *= a[..., 3:4] / 255          # premultiply so the edge doesn't go dark
    small = Image.fromarray(a.astype(np.uint8)).resize((28, 30), Image.BOX)
    s = np.array(small).astype(float)
    s[..., :3] /= np.maximum(s[..., 3:4], 1) / 255
    pal = sorted(c for c in colours(big) if c != OL)
    head = quantize_to(Image.fromarray(np.clip(s, 0, 255).astype(np.uint8)), pal)
    d = ImageDraw.Draw(head)                 # re-ink the features lost in the reduction
    for x in (9, 18):
        d.rectangle((x, 14, x + 1, 15), fill=OL + (255,))
    d.line((8, 12, 11, 12), fill=GR[2] + (255,))
    d.line((17, 12, 20, 12), fill=GR[2] + (255,))
    d.line((10, 21, 18, 21), fill=OL + (255,))
    d.line((11, 22, 17, 22), fill=(252, 250, 242, 255))
    return head


# Frame order is the order of this dict (scenes/level.lua relies on it).
# legs: (dx, lift) for the back leg and the front leg
# arms: hand offset (dx, dy) from the shoulder for the back arm and the front arm (facing right)
# bob: body shift down, tilt: head shift right
POSES = {
    'idle':   dict(legs=((0, 0), (0, 0)), arms=((-1, 8), (1, 8)), bob=0, tilt=0),
    'idle2':  dict(legs=((0, 0), (0, 0)), arms=((-1, 7), (1, 7)), bob=1, tilt=0),
    'run1':   dict(legs=((-4, 1), (4, 0)), arms=((3, 7), (-3, 7)), bob=0, tilt=1),
    'run2':   dict(legs=((0, 4), (0, 0)), arms=((0, 8), (0, 8)), bob=1, tilt=1),
    'run3':   dict(legs=((4, 0), (-4, 1)), arms=((-3, 7), (3, 7)), bob=0, tilt=1),
    'run4':   dict(legs=((0, 0), (0, 4)), arms=((0, 8), (0, 8)), bob=1, tilt=1),
    'jump':   dict(legs=((-2, 4), (3, 2)), arms=((-9, -6), (9, -6)), bob=0, tilt=0),
    'fall':   dict(legs=((-3, 1), (3, 1)), arms=((-8, 0), (8, 0)), bob=0, tilt=0),
    'hurt':   dict(legs=((-3, 2), (2, 1)), arms=((-8, -4), (8, -4)), bob=1, tilt=-2),
    'throw1': dict(legs=((-3, 0), (3, 0)), arms=((-1, 8), (9, -7)), bob=0, tilt=-1),
    'throw2': dict(legs=((-3, 0), (4, 0)), arms=((-1, 8), (10, 3)), bob=1, tilt=2),
}
OX = 4                    # body offset inside the 40-px frame


def nonno_frame(head, pose):
    P = POSES[pose]
    im = Image.new('RGBA', (FW, FH), CLEAR)
    d = ImageDraw.Draw(im)
    A = lambda c: c + (255,)
    y0 = 30 + P['bob']                       # top of the torso
    # legs (skin) + shoes, feet on row 50
    for (dx, lift), x in zip(P['legs'], (OX + 12, OX + 18)):
        xx = x + dx
        d.rectangle((xx, y0 + 10, xx + 2, 48 - lift), fill=A(SK[1]))
        d.line((xx + 2, y0 + 10, xx + 2, 48 - lift), fill=A(SK[2]))
        d.rectangle((xx - 1, 49 - lift, xx + 3, 50 - lift), fill=A(SHOE))
    # shorts, torso
    d.rectangle((OX + 10, y0 + 8, OX + 22, y0 + 11), fill=A(SHORT))
    d.rectangle((OX + 10, y0, OX + 22, y0 + 8), fill=A(SHIRT[1]))
    d.rectangle((OX + 10, y0, OX + 12, y0 + 8), fill=A(SHIRT[0]))
    d.rectangle((OX + 20, y0, OX + 22, y0 + 8), fill=A(SHIRT[2]))
    d.polygon([(OX + 14, y0), (OX + 18, y0), (OX + 16, y0 + 3)], fill=A(SK[2]))      # collar
    im.alpha_composite(head, (OX + 2 + P['tilt'], P['bob']))
    # arms: 3-px sleeve from the shoulder towards the hand, 3x3 skin hand (over the head edge)
    for (hx, hy), sx in zip(P['arms'], (OX + 9, OX + 23)):
        x0, yy0, x1, y1 = sx, y0 + 1, sx + hx, y0 + 1 + hy
        n = max(abs(x1 - x0), abs(y1 - yy0), 1)
        for k in range(n + 1):
            x = round(x0 + (x1 - x0) * k / n)
            y = round(yy0 + (y1 - yy0) * k / n)
            d.rectangle((x - 1, y - 1, x + 1, y + 1), fill=A(SHIRT[1] if k < n - 1 else SK[1]))
    return outline(im, OL)


BALL_PAL = {'o': (40, 30, 60), 'w': (255, 255, 255), 'b': (60, 110, 220), 'y': (250, 210, 40)}
BALL = """
..oooo..
.owwbbo.
owwwbbbo
obwwwyyo
obbwwyyo
oyybwwwo
.oyybwo.
..oooo..
"""


def build_ball():
    f = np.array(ascii_sprite(BALL, BALL_PAL))
    sheet = Image.new('RGBA', (16, 8), CLEAR)
    sheet.paste(Image.fromarray(f), (0, 0))
    sheet.paste(Image.fromarray(np.rot90(f).copy()), (8, 0))
    save(sheet, 'ball.png')


def build_nonno():
    big = portrait.build()
    save(big, 'nonno_portrait.png')
    head = nonno_head(big)
    names = list(POSES)
    sheet = Image.new('RGBA', (FW * len(names), FH), CLEAR)
    for i, n in enumerate(names):
        sheet.alpha_composite(nonno_frame(head, n), (i * FW, 0))
    save(sheet, 'nonno.png')
    with open(os.path.join(OUT, 'nonno.txt'), 'w') as f:
        f.write(' '.join(names) + '\n')
    return names


# ------------------------------------------------------------------ hand-drawn small sprites
def ascii_sprite(rows, pal):
    rows = [r for r in rows.strip('\n').split('\n')]
    w = max(len(r) for r in rows)
    im = Image.new('RGBA', (w, len(rows)), CLEAR)
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch != '.':
                im.putpixel((x, y), pal[ch] + (255,))
    return im


CRAB_PAL = {'o': (40, 16, 16), 'r': (220, 60, 40), 'R': (250, 120, 80), 'd': (150, 30, 30),
            'w': (255, 255, 255), 'k': (0, 0, 0)}
CRAB = ["""
...ww..........ww.......
...wk..........kw.......
....o..........o........
.oo.o..........o.oo.....
oRRoo.oooooooo.ooRRo....
oRrro.oRRRRrrro.orrRo...
.orroorRrrrrrrrdoorro...
..ooorRrrrrrrrrrdooo....
....orrrrrrrrrrrdo......
....odrrrrrrrrrddo......
.....oddddddddddo.......
.....oo.o.oo.o.oo.......
....o..o..o..o..o.......
""", """
..ww..............ww....
..wk..............kw....
...o..............o.....
oo.o..............o.oo..
RRoo..oooooooo....ooRRo.
rrro..oRRRRrrro..orrrRo.
orroo.RrrrrrrrrdooorrRo.
.ooo.oRrrrrrrrrrdoooo...
....orrrrrrrrrrrdo......
....odrrrrrrrrrddo......
.....oddddddddddo.......
.....o.oo.o.oo.oo.......
......o..o..o..o........
"""]


def build_crab():
    frames = [ascii_sprite(f, CRAB_PAL) for f in CRAB]
    sheet = Image.new('RGBA', (24 * 2, 16), CLEAR)
    for i, f in enumerate(frames):
        sheet.alpha_composite(f, (i * 24, 16 - f.height))
    save(sheet, 'crab.png')


# ------------------------------------------------------------------ tiles 16x16
TP = {
    'sand': [(250, 222, 150), (232, 196, 120), (196, 156, 90), (150, 110, 60)],
    'grass': [(120, 200, 80), (60, 150, 60)],
    'wood': [(196, 130, 70), (150, 92, 48), (100, 60, 32), (60, 34, 20)],
    'cup': [(255, 230, 90), (230, 170, 30), (160, 100, 20)],
}


def build_tiles():
    """Sheet: 0 sand top, 1 sand fill, 2 crate, 3 plank (one-way look), 4 cup (goal)."""
    rng = np.random.default_rng(7)
    sheet = Image.new('RGBA', (16 * 5, 16), CLEAR)
    d = ImageDraw.Draw(sheet)
    s, w, c = TP['sand'], TP['wood'], TP['cup']
    A = lambda col: col + (255,)
    for t in (0, 1):
        x0 = t * 16
        d.rectangle((x0, 0, x0 + 15, 15), fill=A(s[1]))
        for _ in range(26):
            x, y = rng.integers(0, 16, 2)
            d.point((x0 + x, y), fill=A(s[2] if rng.random() < .6 else s[0]))
        if t == 0:
            d.rectangle((x0, 0, x0 + 15, 2), fill=A(s[0]))
            for x in range(0, 16, 3):
                d.point((x0 + x, 3), fill=A(s[2]))
    # crate
    x0 = 32
    d.rectangle((x0, 0, x0 + 15, 15), fill=A(w[1]))
    d.rectangle((x0, 0, x0 + 15, 15), outline=A(w[3]))
    d.rectangle((x0 + 1, 1, x0 + 14, 2), fill=A(w[0]))
    d.line((x0 + 2, 13, x0 + 13, 2), fill=A(w[2]), width=2)
    d.line((x0 + 1, 14, x0 + 14, 14), fill=A(w[2]))
    # plank
    x0 = 48
    d.rectangle((x0, 0, x0 + 15, 5), fill=A(w[0]))
    d.line((x0, 5, x0 + 15, 5), fill=A(w[2]))
    d.line((x0, 6, x0 + 15, 6), fill=A(w[3]))
    for x in (3, 12):
        d.rectangle((x0 + x, 6, x0 + x + 1, 15), fill=A(w[2]))
    # cup (goal)
    x0 = 64
    d.pieslice((x0 + 2, -6, x0 + 13, 9), 0, 180, fill=A(c[1]))
    d.rectangle((x0 + 3, 0, x0 + 12, 1), fill=A(c[0]))
    d.rectangle((x0 + 4, 2, x0 + 6, 5), fill=A(c[0]))
    d.arc((x0 - 1, 0, x0 + 5, 6), 90, 270, fill=A(c[2]))
    d.arc((x0 + 10, 0, x0 + 16, 6), 270, 90, fill=A(c[2]))
    d.rectangle((x0 + 7, 9, x0 + 8, 12), fill=A(c[2]))
    d.rectangle((x0 + 4, 13, x0 + 11, 15), fill=A(c[1]))
    d.line((x0 + 4, 13, x0 + 11, 13), fill=A(c[0]))
    save(sheet, 'tiles.png')


# ------------------------------------------------------------------ parallax backgrounds (320 wide, tileable)
SKY = [(40, 40, 110), (70, 60, 150), (130, 80, 170), (200, 100, 150), (245, 140, 110), (255, 190, 120)]


def dither_band(d, y0, y1, c0, c1, w=320):
    """Two-colour ordered-dither transition (no blending)."""
    bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    for y in range(y0, y1):
        t = (y - y0) / max(1, y1 - y0) * 16
        for x in range(w):
            d.point((x, y), fill=(c1 if bayer[y % 4][x % 4] < t else c0) + (255,))


def build_backgrounds():
    # sky + sun (static)
    sky = Image.new('RGBA', (320, 240), SKY[0] + (255,))
    d = ImageDraw.Draw(sky)
    band = 26
    for i in range(len(SKY) - 1):
        d.rectangle((0, i * band, 319, i * band + band - 9), fill=SKY[i] + (255,))
        dither_band(d, i * band + band - 8, (i + 1) * band, SKY[i], SKY[i + 1])
    d.rectangle((0, (len(SKY) - 1) * band, 319, 239), fill=SKY[-1] + (255,))
    sun = [(255, 240, 180), (255, 210, 120)]
    d.ellipse((210, 92, 270, 152), fill=sun[1] + (255,))
    d.ellipse((216, 98, 264, 146), fill=sun[0] + (255,))
    save(sky, 'bg_sky.png')
    # far: sea with islands and sparkles (tileable 320)
    sea = [(40, 70, 140), (60, 100, 170), (110, 150, 200), (255, 220, 160)]
    isle = [(70, 50, 100), (100, 70, 120)]
    far = Image.new('RGBA', (320, 90), CLEAR)
    d = ImageDraw.Draw(far)
    for (cx, wd, ht) in ((40, 80, 22), (150, 50, 12), (260, 110, 30)):
        d.pieslice((cx - wd // 2, 30 - ht, cx + wd // 2, 30 + ht), 180, 360, fill=isle[0] + (255,))
        d.pieslice((cx - wd // 2 + 6, 30 - ht + 6, cx + wd // 2 - 14, 30 + ht), 180, 270, fill=isle[1] + (255,))
    d.rectangle((0, 30, 319, 89), fill=sea[1] + (255,))
    dither_band(d, 30, 38, sea[2], sea[1])
    dither_band(d, 70, 89, sea[1], sea[0])
    rng = np.random.default_rng(3)
    for _ in range(60):
        x, y = int(rng.integers(0, 316)), int(rng.integers(36, 80))
        d.line((x, y, x + int(rng.integers(2, 6)), y), fill=(sea[3] if y < 50 else sea[2]) + (255,))
    save(far, 'bg_sea.png')
    # mid: palms silhouettes (tileable)
    pc = [(30, 50, 50), (50, 80, 60)]
    mid = Image.new('RGBA', (320, 120), CLEAR)
    d = ImageDraw.Draw(mid)
    for (x, h, lean) in ((50, 90, 10), (200, 70, -8), (270, 100, 6)):
        for k in range(h):
            xx = x + int(lean * (k / h) ** 2)
            d.rectangle((xx - 2, 119 - k, xx + 2, 119 - k), fill=pc[k % 6 < 1] + (255,))
        top = (x + lean, 119 - h)
        for ang in (-150, -110, -60, -20, 20, 160):
            a = np.radians(ang)
            for r in range(26):
                px = top[0] + int(r * np.cos(a))
                py = top[1] + int(r * np.sin(a) * .5 + (r / 26) ** 2 * 14)
                d.rectangle((px - 1, py - 1, px + 1, py + 1 - (r > 18)), fill=pc[0] + (255,))
    save(mid, 'bg_palms.png')


# ------------------------------------------------------------------ font (Love2D ImageFont: glyphs split by a marker column)
def build_font():
    glyphs = ' ' + ''.join(sorted(FONT))
    marker = (255, 0, 255, 255)
    w = 1 + sum(6 for _ in glyphs)
    im = Image.new('RGBA', (w, 8), CLEAR)
    x = 0
    for ch in glyphs:
        for y in range(8):
            im.putpixel((x, y), marker)
        x += 1
        if ch != ' ':
            for gy, row in enumerate(FONT[ch].split()):
                for gx, v in enumerate(row):
                    if v == '#':
                        im.putpixel((x + gx, gy), (255, 255, 255, 255))
        x += 5
    for y in range(8):
        im.putpixel((x, y), marker)
    im = im.crop((0, 0, x + 1, 8))
    im.save(os.path.join(OUT, 'font.png'))
    with open(os.path.join(OUT, 'font.txt'), 'w') as f:
        f.write(glyphs)
    print(f'font.png           {len(glyphs)} glyphs')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    build_nonno()
    build_crab()
    build_ball()
    build_tiles()
    build_backgrounds()
    build_font()
