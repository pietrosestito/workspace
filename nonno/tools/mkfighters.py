#!/usr/bin/env python3
"""Fighters for the 1-vs-1 mode, drawn from a skeleton.

Every pose is a set of joint angles; the generator draws outlined limbs in depth
order, pastes the head and writes, for each frame, the hurt box (opaque bbox) and the
hit point (fist/foot/horns) into a Lua table that scenes/fight.lua loads.

Frames are 96x96, facing right, origin = feet centre at (48, 94).
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
FS = 96
OX, OY = 48, 94
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
    'ko2': P(hip=(14, 26), lean=-88, head=(0, 0), barm=(-150, 0), farm=(-120, 0), bleg=(70, 10), fleg=(82, 0)),
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
class Char:
    def __init__(self, name, thigh, shin, uarm, farm, torso, tw, limb, leg, cols, head):
        self.name, self.thigh, self.shin, self.uarm, self.farm = name, thigh, shin, uarm, farm
        self.torso, self.tw, self.limb, self.leg, self.c, self.head = torso, tw, limb, leg, cols, head


def nonno():
    big = portrait.build()
    head = M.nonno_head(big)
    c = dict(ol=M.OL, skin=M.SK[1], skin2=M.SK[2], shirt=M.SHIRT[1], shirt_l=M.SHIRT[0], shirt_d=M.SHIRT[2],
             short=M.SHORT, shoe=M.SHOE, hand=M.SK[1])
    return Char('nonno', 13, 13, 11, 10, 22, 15, 5, 6, c, head)


TORO_FUR = [(150, 92, 56), (116, 68, 40), (80, 46, 28)]
TORO_HORN = [(250, 240, 210), (200, 180, 140)]


def toro_head():
    """Bull head, 34x30, looking right: horns, snout with a gold ring, angry eye."""
    W, H = 34, 30
    im = Image.new('RGBA', (W, H), M.CLEAR)
    d = ImageDraw.Draw(im)
    A = lambda c: c + (255,)
    # horns
    d.polygon([(6, 10), (1, 4), (2, 0), (5, 3), (10, 7)], fill=A(TORO_HORN[0]))
    d.polygon([(22, 8), (28, 2), (31, 0), (30, 5), (25, 11)], fill=A(TORO_HORN[0]))
    d.line((2, 1, 6, 8), fill=A(TORO_HORN[1]))
    d.line((30, 1, 25, 9), fill=A(TORO_HORN[1]))
    # ears
    d.ellipse((1, 11, 8, 15), fill=A(TORO_FUR[1]))
    d.ellipse((24, 10, 31, 14), fill=A(TORO_FUR[1]))
    # skull + face
    d.ellipse((5, 6, 27, 27), fill=A(TORO_FUR[1]))
    d.ellipse((7, 6, 22, 20), fill=A(TORO_FUR[0]))
    # tuft between the horns
    d.polygon([(12, 4), (16, 9), (19, 3), (21, 8), (14, 10)], fill=A(TORO_FUR[2]))
    # snout (facing right)
    d.ellipse((15, 17, 33, 29), fill=A((214, 160, 130)))
    d.ellipse((17, 18, 31, 26), fill=A((236, 186, 156)))
    d.rectangle((25, 21, 26, 22), fill=A(M.OL))
    d.rectangle((30, 21, 31, 22), fill=A(M.OL))
    d.arc((24, 22, 32, 30), 20, 160, fill=A((250, 200, 40)), width=2)        # nose ring
    # eye + angry brow
    d.rectangle((18, 12, 21, 14), fill=A((255, 255, 255)))
    d.rectangle((20, 12, 21, 14), fill=A((200, 20, 20)))
    d.line((16, 10, 23, 12), fill=A(M.OL), width=2)
    return im


def toro():
    c = dict(ol=M.OL, skin=TORO_FUR[0], skin2=TORO_FUR[2], shirt=TORO_FUR[1], shirt_l=TORO_FUR[0],
             shirt_d=TORO_FUR[2], short=(200, 40, 40), shoe=(50, 40, 44), hand=TORO_FUR[1], belt=(240, 190, 40))
    return Char('toro', 15, 14, 13, 12, 26, 22, 7, 8, c, toro_head())


# --------------------------------------------------------------------------- drawing
def vec(a, L):
    r = math.radians(a)
    return L * math.sin(r), L * math.cos(r)


def capsule(d, p0, p1, w, col, ol):
    for width, c in ((w + 2, ol), (w, col)):
        d.line((p0, p1), fill=c + (255,), width=width)
        r = width / 2
        for (x, y) in (p0, p1):
            d.ellipse((x - r + .5, y - r + .5, x + r - .5, y + r - .5), fill=c + (255,))


def frame(ch, pose):
    c = ch.c
    im = Image.new('RGBA', (FS, FS), M.CLEAR)
    d = ImageDraw.Draw(im)
    hx = OX + pose['hip'][0]
    hy = OY - ch.thigh - ch.shin - 2 + pose['hip'][1]
    lean = pose['lean']
    neck = (hx + math.sin(math.radians(lean)) * ch.torso,      # torso leans forward by `lean`
            hy - math.cos(math.radians(lean)) * ch.torso)
    side = (math.cos(math.radians(lean)), math.sin(math.radians(lean)))   # across the shoulders
    def sh(k):
        return (neck[0] + side[0] * k + math.sin(math.radians(lean)) * -3,
                neck[1] + side[1] * k + math.cos(math.radians(lean)) * 3)
    tips = {}

    def limb(root, ang, L1, L2, w, col, endcol, name, foot=False):
        a1, a2 = ang[0], ang[0] + ang[1]
        v1, v2 = vec(a1, L1), vec(a2, L2)
        knee = (root[0] + v1[0], root[1] + v1[1])
        end = (knee[0] + v2[0], knee[1] + v2[1])
        capsule(d, root, knee, w, col, c['ol'])
        capsule(d, knee, end, w - 1, col, c['ol'])
        if foot:
            fx, fy = vec(a2 + 90, 4)
            capsule(d, end, (end[0] + fx, end[1] + fy), 3, endcol, c['ol'])
        else:
            r = w / 2 + 1
            d.ellipse((end[0] - r - 1, end[1] - r - 1, end[0] + r + 1, end[1] + r + 1), fill=c['ol'] + (255,))
            d.ellipse((end[0] - r, end[1] - r, end[0] + r, end[1] + r), fill=endcol + (255,))
        tips[name] = end

    # back limbs
    limb(sh(-ch.tw / 2 + 3), pose['barm'], ch.uarm, ch.farm, ch.limb, c['shirt_d'], c['hand'], 'barm')
    limb((hx - 3, hy), pose['bleg'], ch.thigh, ch.shin, ch.leg, c['skin2'], c['shoe'], 'bleg', foot=True)
    # torso: shorts at the hip, shirt above
    capsule(d, (hx, hy), neck, ch.tw - 2, c['shirt'], c['ol'])
    lx, ly = -side[0] * (ch.tw / 2 - 4), -side[1] * (ch.tw / 2 - 4)
    d.line(((hx + lx, hy + ly - 2), (neck[0] + lx, neck[1] + ly + 2)), fill=c['shirt_l'] + (255,), width=3)
    bx, by = math.sin(math.radians(lean)) * 5, -math.cos(math.radians(lean)) * 5
    capsule(d, (hx - bx * 0.2, hy - by * 0.2), (hx + bx, hy + by), ch.tw - 1 - ch.tw // 5, c['short'], c['ol'])
    if 'belt' in c:
        d.line(((hx + bx - side[0] * ch.tw / 2, hy + by - side[1] * ch.tw / 2),
                (hx + bx + side[0] * ch.tw / 2, hy + by + side[1] * ch.tw / 2)), fill=c['belt'] + (255,), width=2)
    # front leg
    limb((hx + 3, hy), pose['fleg'], ch.thigh, ch.shin, ch.leg, c['skin'], c['shoe'], 'fleg', foot=True)
    # head, rotated with the torso when lying down
    head = ch.head
    if abs(lean) > 40:
        head = head.rotate(-lean, expand=True, resample=Image.NEAREST)
    hw, hh = head.size
    up = (math.sin(math.radians(lean)), -math.cos(math.radians(lean)))
    cx = neck[0] + up[0] * hh * 0.42 + pose['head'][0]
    cy = neck[1] + up[1] * hh * 0.42 + pose['head'][1]
    im.alpha_composite(head, (int(round(cx - hw / 2)), int(round(cy - hh / 2))))
    tips['head'] = (cx + hw / 2 - 2, cy - hh / 4)
    # front arm last (in front of everything)
    limb(sh(ch.tw / 2 - 3), pose['farm'], ch.uarm, ch.farm, ch.limb, c['shirt'], c['hand'], 'farm')
    im = M.outline(im, c['ol'])
    a = np.array(im)[..., 3] > 0
    ys, xs = np.nonzero(a)
    hurt = (int(xs.min()) - OX, int(ys.min()) - OY, int(xs.max()) - OX, int(ys.max()) - OY)
    hit = None
    if pose['hit']:
        tx_, ty_ = tips[pose['hit']]
        hit = (round(tx_) - OX, round(ty_) - OY, 7)
    return im, hurt, hit


def build(ch):
    poses = dict(POSES)
    if ch.name == 'toro':
        poses.update(TORO_EXTRA)
    names = list(poses)
    rows = (len(names) + COLS - 1) // COLS
    sheet = Image.new('RGBA', (FS * COLS, FS * rows), M.CLEAR)
    lua = ['-- generated by tools/mkfighters.py: frame index, hurt box and hit point (origin = feet, facing right)',
           'return {']
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
