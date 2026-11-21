#!/usr/bin/env python3
"""Fighters for the 1-vs-1 mode, drawn from a skeleton.

Every pose is a set of joint angles; the generator draws outlined limbs in depth
order, pastes the head and writes, for each frame, the hurt box (opaque bbox) and the
hit point (fist/foot/horns) into a Lua table that scenes/fight.lua loads.

Frames are 176x176, facing right, origin = feet centre at (88, 172).
usage: mkfighters.py [OUTDIR]
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mkassets as M  # noqa: E402
import portrait  # noqa: E402

OUT = M.OUT
FS = 176
OX, OY = 88, 172
COLS = 8

# --------------------------------------------------------------------------- poses
# angles in degrees: 0 = straight down, 90 = forward (horizontal), 180 = up, negative = backwards
# arm/leg = (upper angle, lower angle relative to upper); lean = torso angle from vertical
# hip = (dx, dy) offset of the hip; hit = which limb tip is the hit point (or None)
BASE = dict(hip=(0, 0), lean=5, head=(0, 0),
            barm=(30, 110), farm=(45, 95), bleg=(-14, 4), fleg=(18, -14), hit=None)


def P(**kw):
    d = dict(BASE)
    d.update(kw)
    return d


POSES = {
    'idle1': P(),
    'idle2': P(hip=(0, 1), barm=(28, 114), farm=(42, 100)),
    'walk1': P(bleg=(-24, 10), fleg=(26, -20)),
    'walk2': P(hip=(0, 1), bleg=(-6, 6), fleg=(8, -26)),
    'walk3': P(bleg=(10, -20), fleg=(-8, 4)),
    'walk4': P(hip=(0, 1), bleg=(-10, -24), fleg=(12, 0)),
    'crouch': P(hip=(0, 15), lean=20, bleg=(50, -110), fleg=(85, -120)),
    'jump': P(hip=(0, -2), bleg=(40, -110), fleg=(80, -120), barm=(60, 80), farm=(80, 60)),
    'jk': P(hip=(0, -2), lean=-10, bleg=(40, -110), fleg=(100, -5), hit='fleg'),
    'block': P(lean=-5, barm=(25, 140), farm=(35, 140), bleg=(-18, 6), fleg=(12, -10)),
    'cblock': P(hip=(0, 15), lean=15, bleg=(50, -110), fleg=(85, -120), barm=(30, 140), farm=(40, 140)),
    'hit': P(hip=(-3, 1), lean=-22, head=(-2, 0), barm=(-30, 40), farm=(20, 60), bleg=(-20, 8), fleg=(14, -4)),
    'ko1': P(hip=(8, 10), lean=-50, head=(-2, 0), barm=(-80, 10), farm=(-40, 20), bleg=(10, -40), fleg=(40, -30)),
    'ko2': P(hip=(3, 26), lean=-88, head=(0, 0), barm=(-150, 0), farm=(-120, 0), bleg=(70, 10), fleg=(82, 0)),
    'win': P(lean=0, barm=(170, 10), farm=(165, 5), bleg=(-12, 0), fleg=(12, 0)),
    'lp1': P(farm=(70, 60)),
    'lp2': P(lean=10, hip=(2, 0), farm=(90, 0), hit='farm'),
    'hp1': P(lean=-5, hip=(-2, 0), barm=(10, 120)),
    'hp2': P(lean=18, hip=(5, 0), barm=(92, 0), farm=(30, 120), fleg=(26, -10), hit='barm'),
    'lk1': P(fleg=(55, -60)),
    'lk2': P(lean=-8, fleg=(80, 0), hit='fleg'),
    'hk1': P(lean=-10, fleg=(80, -90)),
    'hk2': P(lean=-22, hip=(-2, -1), fleg=(118, 0), barm=(-20, 60), hit='fleg'),
    'ck1': P(hip=(0, 15), lean=20, bleg=(50, -110), fleg=(70, -80)),
    'ck2': P(hip=(-2, 15), lean=25, bleg=(50, -110), fleg=(88, 0), hit='fleg'),
    'sp1': P(lean=-12, barm=(175, 10), farm=(60, 70)),
    'sp2': P(lean=20, hip=(5, 0), barm=(105, 0), farm=(20, 100), fleg=(26, -10), hit=None),
}
TORO_EXTRA = {   # charge: head down, horns forward
    'sp1': P(lean=30, hip=(-2, 3), barm=(-40, 30), farm=(-30, 40), bleg=(-30, 20), fleg=(30, -40)),
    'sp2': P(lean=45, hip=(-6, 5), head=(2, 3), barm=(-60, 20), farm=(-50, 30), bleg=(-40, 10), fleg=(40, -50), hit='head'),
}


# --------------------------------------------------------------------------- characters
# Realistic proportions (about 6.5 heads), V-shaped torso, tapered limbs with muscle bulges,
# 3-tone shading lit from the upper left.
class Char:
    def __init__(self, name, **kw):
        self.name = name
        self.__dict__.update(kw)
        self.k = (self.thigh + self.shin) / 26          # pose hip offsets were authored for 26-px legs


NONNO_TOP = [(70, 120, 220), (40, 76, 160)]            # beach volley tank top


def nonno_head_small(big):
    """Portrait head reduced to 22x25, snapped to its palette, features re-inked."""
    head = big.crop((2, 0, 62, 67))
    a = np.array(head).astype(float)
    a[..., :3] *= a[..., 3:4] / 255
    small = Image.fromarray(a.astype(np.uint8)).resize((26, 29), Image.BOX)
    s = np.array(small).astype(float)
    s[..., :3] /= np.maximum(s[..., 3:4], 1) / 255
    pal = sorted(c for c in M.colours(big) if c not in (M.OL,) + tuple(M.SHIRT) + (M.SHORT,))
    head = M.quantize_to(Image.fromarray(np.clip(s, 0, 255).astype(np.uint8)), pal)
    d = ImageDraw.Draw(head)
    A = lambda c: c + (255,)
    for x in (8, 16):                                   # eyes, brows, smile
        d.rectangle((x, 13, x + 1, 14), fill=A(M.OL))
        d.line((x - 1, 11, x + 2, 11), fill=A(M.GR[2]))
    d.line((9, 20, 17, 20), fill=A(M.OL))
    d.line((10, 21, 16, 21), fill=A((252, 250, 242)))
    return head


def nonno():
    big = portrait.build()
    sk = M.SK
    return Char('nonno', head=nonno_head_small(big), thigh=28, shin=27, uarm=22, farm=20, torso=40, neck=4,
                shoulders=44, chest=38, waist=24, arm=(15, 10, 5), fore=(12, 8, 3), leg=(19, 12, 4), calf=(14, 8, 5),
                neckw=12, fist=5, skin=sk[:3], top=NONNO_TOP, shorts=[(62, 68, 116), M.SHORT], bare=False,
                ol=M.OL, foot=sk[1])


TORO_FUR = [(170, 108, 66), (130, 78, 44), (90, 52, 30), (60, 34, 20)]
TORO_HORN = [(250, 240, 210), (200, 180, 140)]
TORO_SNOUT = [(236, 186, 156), (200, 146, 118)]
GOLD = (245, 195, 50)


def toro_head():
    """Bull head 30x28, looking right: horns, snout with a gold ring, angry eye."""
    W, H = 30, 28
    im = Image.new('RGBA', (W, H), M.CLEAR)
    d = ImageDraw.Draw(im)
    A = lambda c: c + (255,)
    d.polygon([(6, 9), (1, 3), (2, 0), (5, 3), (10, 7)], fill=A(TORO_HORN[0]))
    d.polygon([(19, 7), (25, 2), (28, 0), (27, 5), (22, 10)], fill=A(TORO_HORN[0]))
    d.line((2, 1, 6, 7), fill=A(TORO_HORN[1]))
    d.line((27, 1, 22, 8), fill=A(TORO_HORN[1]))
    d.ellipse((0, 10, 7, 14), fill=A(TORO_FUR[2]))
    d.ellipse((4, 5, 24, 25), fill=A(TORO_FUR[1]))
    d.ellipse((6, 5, 19, 18), fill=A(TORO_FUR[0]))
    d.polygon([(10, 3), (14, 8), (17, 2), (19, 7), (12, 9)], fill=A(TORO_FUR[3]))
    d.ellipse((13, 15, 29, 27), fill=A(TORO_SNOUT[1]))
    d.ellipse((15, 16, 28, 24), fill=A(TORO_SNOUT[0]))
    d.rectangle((22, 19, 23, 20), fill=A(M.OL))
    d.rectangle((26, 19, 27, 20), fill=A(M.OL))
    d.arc((21, 20, 29, 28), 20, 160, fill=A(GOLD), width=2)
    d.rectangle((15, 11, 18, 13), fill=A((255, 255, 255)))
    d.rectangle((17, 11, 18, 13), fill=A((200, 20, 20)))
    d.line((13, 9, 20, 11), fill=A(M.OL), width=2)
    return im


def toro():
    return Char('toro', head=toro_head(), thigh=30, shin=28, uarm=24, farm=22, torso=46, neck=3,
                shoulders=58, chest=50, waist=30, arm=(19, 13, 7), fore=(15, 10, 4), leg=(22, 14, 5), calf=(16, 9, 6),
                neckw=20, fist=6, skin=TORO_FUR[:3], top=None, shorts=[(210, 40, 40), (150, 24, 30)], bare=True,
                ol=M.OL, foot=TORO_FUR[3], belt=GOLD)


# --------------------------------------------------------------------------- drawing
LIGHT = (-0.6, -0.8)                                    # light from the upper left


def vec(a, L):
    r = math.radians(a)
    return L * math.sin(r), L * math.cos(r)


def rnd(pts):
    return [(round(x), round(y)) for x, y in pts]


def taper(d, p0, p1, w0, w1, bulge, cols, ol, caps=True):
    """Limb segment with a muscle bulge, outlined, shaded on three tones."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    L = math.hypot(dx, dy) or 1
    ux, uy = dx / L, dy / L
    nx, ny = -uy, ux
    if nx * LIGHT[0] + ny * LIGHT[1] < 0:               # n points towards the light
        nx, ny = -nx, -ny
    def side(sgn, lo, hi, extra=0):
        pts_a, pts_b = [], []
        for i in range(9):
            t = i / 8
            w = (w0 + (w1 - w0) * t + bulge * math.sin(math.pi * t)) / 2 + extra
            cx, cy = p0[0] + dx * t, p0[1] + dy * t
            pts_a.append((cx + sgn * nx * w * lo, cy + sgn * ny * w * lo))
            pts_b.append((cx + sgn * nx * w * hi, cy + sgn * ny * w * hi))
        return pts_a + pts_b[::-1]
    def body(extra):
        return side(1, -1, 1, extra)
    def cap(p, w, col):
        d.ellipse((p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2), fill=col + (255,))
    if caps:
        cap(p0, w0 + 2, ol); cap(p1, w1 + 2, ol)
    d.polygon(rnd(body(1)), fill=ol + (255,))
    if caps:
        cap(p0, w0, cols[1]); cap(p1, w1, cols[1])
    d.polygon(rnd(body(0)), fill=cols[1] + (255,))
    d.polygon(rnd(side(1, 0.15, 0.75)), fill=cols[0] + (255,))      # lit side
    d.polygon(rnd(side(-1, 0.45, 1.0)), fill=cols[2] + (255,))      # shadow side


def torso_poly(hip, lean, T, wa, ch_, sh):
    """V-shaped torso in local coordinates (x across, y up the spine), rotated by lean."""
    pts = [(-wa / 2, 0), (-wa / 2 - 1, -T * 0.3), (-ch_ / 2, -T * 0.68), (-sh / 2, -T * 0.88), (-sh / 2 + 4, -T),
           (sh / 2 - 4, -T), (sh / 2, -T * 0.88), (ch_ / 2, -T * 0.68), (wa / 2 + 1, -T * 0.3), (wa / 2, 0)]
    return [tw(hip, lean, x, y) for x, y in pts]


def tw(hip, lean, x, y):
    c, s = math.cos(math.radians(lean)), math.sin(math.radians(lean))
    return (hip[0] + x * c - y * s, hip[1] + x * s + y * c)


def frame(ch, pose):
    im = Image.new('RGBA', (FS, FS), M.CLEAR)
    d = ImageDraw.Draw(im)
    A = lambda c: c + (255,)
    k = ch.k
    hx = OX + pose['hip'][0] * k
    hy = OY - ch.thigh - ch.shin - 3 + pose['hip'][1] * k
    hip = (hx, hy)
    lean = pose['lean']
    T = ch.torso
    neck = tw(hip, lean, 0, -T)
    shoulder_b = tw(hip, lean, -ch.shoulders / 2 + ch.arm[0] / 2, -T * 0.9)
    shoulder_f = tw(hip, lean, ch.shoulders / 2 - ch.arm[0] / 2, -T * 0.9)
    hip_b, hip_f = tw(hip, lean, -ch.waist / 4, 0), tw(hip, lean, ch.waist / 4, 0)
    tips = {}

    def arm(root, ang, back):
        cols = [c for c in ch.skin] if not back else [ch.skin[1], ch.skin[2], ch.skin[2]]
        e = vec(ang[0], ch.uarm); elbow = (root[0] + e[0], root[1] + e[1])
        w = vec(ang[0] + ang[1], ch.farm); wrist = (elbow[0] + w[0], elbow[1] + w[1])
        taper(d, elbow, wrist, ch.fore[0], ch.fore[1], ch.fore[2], cols, ch.ol)
        taper(d, root, elbow, ch.arm[0], ch.arm[1], ch.arm[2], cols, ch.ol)     # biceps over the forearm
        r = ch.fist
        d.ellipse((wrist[0] - r - 1, wrist[1] - r - 1, wrist[0] + r + 1, wrist[1] + r + 1), fill=A(ch.ol))
        d.ellipse((wrist[0] - r, wrist[1] - r, wrist[0] + r, wrist[1] + r), fill=A(cols[1]))
        d.ellipse((wrist[0] - r + 1, wrist[1] - r + 1, wrist[0] + 1, wrist[1] + 1), fill=A(cols[0]))
        tips['barm' if back else 'farm'] = wrist

    def leg(root, ang, back):
        cols = [c for c in ch.skin] if not back else [ch.skin[1], ch.skin[2], ch.skin[2]]
        kv = vec(ang[0], ch.thigh); knee = (root[0] + kv[0], root[1] + kv[1])
        av = vec(ang[0] + ang[1], ch.shin); ankle = (knee[0] + av[0], knee[1] + av[1])
        taper(d, knee, ankle, ch.calf[0], ch.calf[1], ch.calf[2], cols, ch.ol)
        taper(d, root, knee, ch.leg[0], ch.leg[1], ch.leg[2], cols, ch.ol)
        fv = vec(ang[0] + ang[1] + 90, 9)
        taper(d, ankle, (ankle[0] + fv[0], ankle[1] + fv[1]), 6, 5, 0, [ch.foot, ch.foot, ch.skin[2]], ch.ol)
        # shorts over the upper thigh
        sv = vec(ang[0], ch.thigh * 0.4)
        taper(d, (root[0] - sv[0] * 0.3, root[1] - sv[1] * 0.3), (root[0] + sv[0], root[1] + sv[1]), ch.leg[0] + 3, ch.leg[0] + 2, 0,
              [ch.shorts[0], ch.shorts[0] if not back else ch.shorts[1], ch.shorts[1]], ch.ol, caps=False)
        tips['bleg' if back else 'fleg'] = (ankle[0] + fv[0] * 0.6, ankle[1] + fv[1] * 0.6)

    arm(shoulder_b, pose['barm'], True)
    leg(hip_b, pose['bleg'], True)
    # torso
    poly = torso_poly(hip, lean, T, ch.waist, ch.chest, ch.shoulders)
    d.polygon(rnd(torso_poly(hip, lean, T, ch.waist + 2, ch.chest + 2, ch.shoulders + 2)), fill=A(ch.ol))
    d.polygon(rnd(poly), fill=A(ch.skin[1]))
    lit = [tw(hip, lean, x, y) for x, y in ((-ch.waist / 2 + 1, -2), (-ch.chest / 2 + 1, -T * 0.68), (-ch.shoulders / 2 + 3, -T * 0.9),
                                            (-ch.shoulders / 2 + 9, -T * 0.97), (-4, -T * 0.6), (-ch.waist / 2 + 6, -2))]
    d.polygon(rnd(lit), fill=A(ch.skin[0]))
    dark = [tw(hip, lean, x, y) for x, y in ((ch.waist / 2 - 1, -1), (ch.chest / 2 - 1, -T * 0.68), (ch.shoulders / 2 - 2, -T * 0.88),
                                             (ch.shoulders / 2 - 6, -T * 0.9), (ch.chest / 2 - 7, -T * 0.6), (ch.waist / 2 - 5, -1))]
    d.polygon(rnd(dark), fill=A(ch.skin[2]))
    if ch.bare:                                          # pecs and abs
        for sx in (-1, 1):
            a0 = tw(hip, lean, sx * ch.chest * 0.42, -T * 0.66)
            a1 = tw(hip, lean, sx * 2, -T * 0.6)
            d.line(rnd([a0, a1]), fill=A(ch.skin[2]), width=2)
        d.line(rnd([tw(hip, lean, 0, -T * 0.62), tw(hip, lean, 0, -T * 0.12)]), fill=A(ch.skin[2]))
        for yy in (0.48, 0.34, 0.2):
            d.line(rnd([tw(hip, lean, -ch.waist * 0.32, -T * yy), tw(hip, lean, ch.waist * 0.32, -T * yy)]), fill=A(ch.skin[2]))
    else:                                                # tank top: straps, open armholes
        top = [tw(hip, lean, x, y) for x, y in ((-ch.waist / 2, -2), (-ch.chest / 2 + 1, -T * 0.62), (-ch.shoulders / 2 + 9, -T * 0.86),
                                                (-ch.shoulders / 2 + 9, -T), (-5, -T), (-2, -T * 0.86), (2, -T * 0.86), (5, -T),
                                                (ch.shoulders / 2 - 9, -T), (ch.shoulders / 2 - 9, -T * 0.86), (ch.chest / 2 - 1, -T * 0.62),
                                                (ch.waist / 2, -2))]
        d.polygon(rnd(top), fill=A(ch.top[0]))
        sh = [tw(hip, lean, x, y) for x, y in ((ch.waist / 2 - 5, -2), (ch.chest / 2 - 6, -T * 0.6), (ch.shoulders / 2 - 9, -T * 0.86),
                                               (ch.shoulders / 2 - 9, -T), (ch.chest / 2 - 1, -T * 0.62), (ch.waist / 2, -2))]
        d.polygon(rnd(sh), fill=A(ch.top[1]))
        d.line(rnd([tw(hip, lean, -ch.waist / 2 + 2, -T * 0.25), tw(hip, lean, ch.waist / 2 - 2, -T * 0.25)]), fill=A(ch.top[1]))
    # waistband
    d.polygon(rnd([tw(hip, lean, x, y) for x, y in ((-ch.waist / 2 - 2, 4), (-ch.waist / 2 - 1, -3), (ch.waist / 2 + 1, -3), (ch.waist / 2 + 2, 4))]),
              fill=A(ch.shorts[1]))
    if getattr(ch, 'belt', None):
        d.line(rnd([tw(hip, lean, -ch.waist / 2 - 1, -2), tw(hip, lean, ch.waist / 2 + 1, -2)]), fill=A(ch.belt), width=2)
    leg(hip_f, pose['fleg'], False)
    # neck + head
    head = ch.head
    if abs(lean) > 40:
        head = head.rotate(-lean, expand=True, resample=Image.NEAREST)
    hw, hh = head.size
    up = (math.sin(math.radians(lean)), -math.cos(math.radians(lean)))
    hc = (neck[0] + up[0] * (ch.neck + hh * 0.45) + pose['head'][0], neck[1] + up[1] * (ch.neck + hh * 0.45) + pose['head'][1])
    taper(d, (neck[0] - up[0] * 3, neck[1] - up[1] * 3), (neck[0] + up[0] * (ch.neck + 4), neck[1] + up[1] * (ch.neck + 4)),
          ch.neckw, ch.neckw - 2, 0, ch.skin, ch.ol)
    im.alpha_composite(head, (int(round(hc[0] - hw / 2)), int(round(hc[1] - hh / 2))))
    tips['head'] = (hc[0] + hw / 2 - 2, hc[1] - hh / 4)
    arm(shoulder_f, pose['farm'], False)
    im = M.outline(im, ch.ol)
    a = np.array(im)[..., 3] > 0
    ys, xs = np.nonzero(a)
    hurt = (int(xs.min()) - OX, int(ys.min()) - OY, int(xs.max()) - OX, int(ys.max()) - OY)
    hit = None
    if pose['hit']:
        tx_, ty_ = tips[pose['hit']]
        hit = (round(tx_) - OX, round(ty_) - OY, 9)
    return im, hurt, hit


def build(ch):
    poses = dict(POSES)
    if ch.name == 'toro':
        poses.update(TORO_EXTRA)
    names = list(poses)
    rows = (len(names) + COLS - 1) // COLS
    sheet = Image.new('RGBA', (FS * COLS, FS * rows), M.CLEAR)
    lua = ['-- generated by tools/mkfighters.py: frame index, hurt box and hit point (origin = feet, facing right)',
           'return {', '    size = %d, ox = %d, oy = %d, cols = %d,' % (FS, OX, OY, COLS)]
    for i, n in enumerate(names):
        im, hurt, hit = frame(ch, poses[n])
        sheet.alpha_composite(im, ((i % COLS) * FS, (i // COLS) * FS))
        hs = 'nil' if hit is None else '{ %d, %d, %d }' % hit
        lua.append('    %s = { i = %d, hurt = { %d, %d, %d, %d }, hit = %s },' % ((n, i) + hurt + (hs,)))
    lua.append('}')
    M.save(sheet, f'f_{ch.name}.png')
    with open(os.path.join(OUT, f'f_{ch.name}.lua'), 'w') as f:
        f.write('\n'.join(lua) + '\n')


SPARK = ["""
.......w.......
.......w.......
...w...y...w...
....w..y..w....
.....wyyyw.....
......yWy......
wwyyyyWWWyyyyww
......yWy......
.....wyyyw.....
....w..y..w....
...w...y...w...
.......w.......
.......w.......
""", """
...............
......w.w......
.....w...w.....
...............
..w.........w..
.w...........w.
...............
.w...........w.
..w.........w..
...............
.....w...w.....
......w.w......
...............
"""]


def build_fx():
    pal = {'w': (255, 255, 255), 'y': (255, 220, 80), 'W': (255, 255, 200), 'b': (120, 200, 255)}
    sheet = Image.new('RGBA', (15 * 4, 13), M.CLEAR)
    for i, s in enumerate(SPARK):
        sheet.alpha_composite(M.ascii_sprite(s, pal), (i * 15, 0))
        blue = s.replace('y', 'b').replace('W', 'w')
        sheet.alpha_composite(M.ascii_sprite(blue, pal), ((i + 2) * 15, 0))
    M.save(sheet, 'spark.png')
    ball = M.ascii_sprite(M.BALL, M.BALL_PAL).resize((16, 16), Image.NEAREST)
    sheet = Image.new('RGBA', (32, 16), M.CLEAR)
    sheet.alpha_composite(ball, (0, 0))
    sheet.alpha_composite(ball.rotate(90), (16, 0))
    M.save(sheet, 'bigball.png')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    build(nonno())
    build(toro())
    build_fx()
