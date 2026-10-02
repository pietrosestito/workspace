#!/usr/bin/env python3
"""Headless smoke test: plays the ROM in the cynes emulator and checks game state.

usage: smoketest.py build/boxhero.nes [--shots DIR]
Needs: pip install cynes  (Pillow too, for --shots)
"""
import argparse
import os
import sys

from cynes import NES, NES_INPUT_A, NES_INPUT_B, NES_INPUT_RIGHT, NES_INPUT_START

ST_TITLE, ST_INTRO, ST_PLAY, ST_DYING, ST_CLEAR = 0, 1, 2, 3, 4
T_BOSS = 4


def load_labels(rom):
    labels = {}
    with open(os.path.splitext(rom)[0] + '.lbl') as f:
        for line in f:
            _, addr, name = line.split()
            labels[name.lstrip('.')] = int(addr, 16)
    return labels


class Game:
    def __init__(self, rom, shots):
        self.nes = NES(rom)
        self.L = load_labels(rom)
        self.shots = shots
        self.frame = None

    def __getitem__(self, name):
        return self.nes[self.L[name]]

    def __setitem__(self, name, value):
        self.nes[self.L[name]] = value

    def obj(self, name, i):
        return self.nes[self.L[name] + i]

    def run(self, frames, buttons=0):
        self.nes.controller = buttons
        for _ in range(frames):
            self.frame = self.nes.step()
            if self.nes.has_crashed:
                sys.exit("FAIL: CPU crashed")

    def tap(self, buttons):
        self.run(1, buttons)
        self.run(1, 0)

    def shot(self, name):
        if self.shots:
            from PIL import Image
            Image.fromarray(self.frame.copy()).save(os.path.join(self.shots, name + '.png'))

    def px(self):
        return self['px'] | (self['px_h'] << 8)

    def cam(self):
        return self['cam_x'] | (self.nes[self.L['cam_x'] + 1] << 8)


def check(cond, msg):
    if not cond:
        sys.exit("FAIL: " + msg)
    print("ok  ", msg)


def fly_to_boss(g):
    """Carry the player through the level above the ground until the boss appears."""
    for _ in range(3000):
        g['py'] = 40
        g['vy_l'] = g['vy_h'] = 0
        g.run(1, NES_INPUT_RIGHT | NES_INPUT_B)
        if g['boss_on'] and g.cam() >= g['lvl_maxcam'] | (g.nes[g.L['lvl_maxcam'] + 1] << 8):
            x = g.cam() + 16        # land on the left edge of the arena
            g['px'], g['px_h'], g['py'] = x & 0xFF, x >> 8, 192
            return
    sys.exit("FAIL: never reached the boss arena")


def defeat_boss(g):
    """Drop the player onto the boss repeatedly until it dies."""
    for _ in range(12):
        slot = next(i for i in range(8) if g.obj('obj_t', i) == T_BOSS)
        bx = g.obj('obj_xl', slot) | (g.obj('obj_xh', slot) << 8)
        by = g.obj('obj_y', slot)
        g['px'] = (bx + 8) & 0xFF
        g['px_h'] = (bx + 8) >> 8
        g['py'] = max(by - 24, 0)
        g['vy_l'], g['vy_h'] = 0, 2
        g.nes[g.L['obj_inv'] + slot] = 0
        g.run(12)
        if g['state'] == ST_CLEAR:
            return
    sys.exit("FAIL: boss did not die")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('rom')
    ap.add_argument('--shots')
    a = ap.parse_args()
    if a.shots:
        os.makedirs(a.shots, exist_ok=True)

    g = Game(a.rom, a.shots)
    g.run(60)
    check(g['state'] == ST_TITLE, "boots to the title screen")
    g.shot('1_title')

    g.tap(NES_INPUT_START)
    g.run(10)
    check(g['state'] == ST_INTRO, "START opens the level intro")
    g.shot('2_intro')
    g.run(130)
    check(g['state'] == ST_PLAY, "level 1 starts")
    g.run(30)
    check(g['on_ground'] == 1 and g['py'] == 192, "player lands on the ground")
    g.shot('3_start')

    g.tap(NES_INPUT_A)
    g.run(14, NES_INPUT_A)
    check(g['py'] < 150, "player jumps (holding A jumps higher)")
    g.shot('4_jump')
    g.run(60)
    x0 = g.px()
    g.run(60, NES_INPUT_RIGHT)
    check(g.px() > x0 + 40, "player walks right")

    # run right until something kills us (enemy or pit): checks death and respawn
    lives = g['lives']
    for _ in range(600):
        g.run(1, NES_INPUT_RIGHT | NES_INPUT_B)
        if g['state'] == ST_DYING:
            break
    check(g['state'] == ST_DYING, "player can die")
    g.shot('5_dying')
    g.run(260)
    check(g['state'] == ST_PLAY and g['lives'] == lives - 1, "life lost and level restarted")

    for level in range(3):
        fly_to_boss(g)
        g.run(40)
        g.shot(f'6_boss{level + 1}')
        check(g['boss_hp'] > 0, f"boss of level {level + 1} spawned")
        defeat_boss(g)
        check(g['state'] == ST_CLEAR, f"boss of level {level + 1} defeated")
        g.run(200)
        g.shot(f'7_after{level + 1}')
        if level < 2:
            g.run(130)
            check(g['state'] == ST_PLAY and g['level'] == level + 1, f"level {level + 2} starts")
            g.run(20)
            g.shot(f'8_level{level + 2}')

    check(g['state'] == 6, "win screen after the last boss")
    print("all checks passed")


if __name__ == '__main__':
    main()
