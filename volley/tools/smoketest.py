#!/usr/bin/env python3
"""Headless test for SUP VOLLEY: plays whole matches in the cynes emulator.

Player 1 (Nonno) is driven by a small Python bot that follows the ball, player 2 is the
game's own CPU. Checks the state machine, scoring, both sides winning points and the
end of the match.

usage: smoketest.py build/volley.nes [--shots DIR] [--matches N]
"""
import argparse
import os
import random
import sys

from cynes import NES, NES_INPUT_A, NES_INPUT_DOWN, NES_INPUT_LEFT, NES_INPUT_RIGHT, NES_INPUT_START

ST_TITLE, ST_PLAY, ST_POINT, ST_OVER = range(4)


def labels(rom):
    out = {}
    with open(os.path.splitext(rom)[0] + '.lbl') as f:
        for line in f:
            _, addr, name = line.split()
            out[name.lstrip('.')] = int(addr, 16)
    return out


class Game:
    def __init__(self, rom, shots):
        self.nes, self.L, self.shots, self.frame = NES(rom), labels(rom), shots, None

    def __getitem__(self, name):
        if isinstance(name, tuple):
            return self.nes[self.L[name[0]] + name[1]]
        return self.nes[self.L[name]]

    def run(self, n=1, buttons=0):
        self.nes.controller = buttons
        for _ in range(n):
            self.frame = self.nes.step()
            if self.nes.has_crashed:
                sys.exit("FAIL: CPU crashed")

    def tap(self, b):
        self.run(1, b)
        self.run(1, 0)

    def shot(self, name):
        if self.shots:
            from PIL import Image
            Image.fromarray(self.frame.copy()).save(os.path.join(self.shots, name + '.png'))

    err = 0
    side = 1

    def bot(self):
        """Nonno: stands under the ball on his side, with a human-like aiming error."""
        bx, by, px = self['b_x'] + 8, self['b_y'], self[('pl_x', 0)] + 12
        side = 0 if bx < 128 else 1
        if side != self.side:
            self.side, self.err = side, random.randint(-14, 10)
        target = bx - 5 + self.err if bx < 128 else 60
        b = 0
        if px < target - 2:
            b |= NES_INPUT_RIGHT
        elif px > target + 2:
            b |= NES_INPUT_LEFT
        return b


def check(cond, msg):
    if not cond:
        sys.exit("FAIL: " + msg)
    print("ok  ", msg)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('rom')
    ap.add_argument('--shots')
    ap.add_argument('--matches', type=int, default=2)
    a = ap.parse_args()
    if a.shots:
        os.makedirs(a.shots, exist_ok=True)
    random.seed(1)
    g = Game(a.rom, a.shots)

    g.run(60)
    check(g['state'] == ST_TITLE, "boots to the title screen")
    g.tap(NES_INPUT_DOWN)
    g.run(5)
    check(g['menu'] == 1, "DOWN moves the menu cursor")
    g.shot('1_title')
    g.tap(NES_INPUT_DOWN)
    g.tap(NES_INPUT_START)
    g.run(5)
    check(g['state'] == ST_PLAY and g['mode'] == 1, "START begins a match against the CPU")
    g.run(20)
    g.shot('2_serve')

    g.tap(NES_INPUT_A)
    g.run(10)
    check(g[('pl_y', 0)] < 150, "A makes the Nonno jump")

    wins = [0, 0]
    shots_taken = set()
    for match in range(a.matches):
        touches = points = 0
        last_cd = [0, 0]
        for f in range(60 * 60 * 15):
            st = g['state']
            if st == ST_OVER:
                break
            g.run(1, g.bot() if st == ST_PLAY else 0)
            for p in (0, 1):
                cd = g[('pl_cd', p)]
                if cd == 12 and last_cd[p] != 12:
                    touches += 1
                last_cd[p] = cd
            if g['state'] == ST_POINT and st == ST_PLAY:
                points += 1
                if 'point' not in shots_taken:
                    shots_taken.add('point')
                    g.shot('4_point')
            if 'rally' not in shots_taken and g['b_y'] < 90 and g[('pl_ground', 1)] == 0:
                shots_taken.add('rally')
                g.shot('3_rally')
        s0, s1 = g[('score', 0)], g[('score', 1)]
        check(g['state'] == ST_OVER, f"match {match + 1} ends ({s0}-{s1}, {points} points, {touches} touches)")
        check(max(s0, s1) == 15, "the winner has 15 points")
        check(touches > points, "rallies happen (more touches than points)")
        wins[0 if s0 == 15 else 1] += 1
        g.run(60)
        g.shot('5_over')
        g.tap(NES_INPUT_START)
        g.run(10)
        check(g['state'] == ST_TITLE, "START after the match returns to the title")
        g.tap(NES_INPUT_START)
        g.run(5)
    print(f"matches won: Nonno bot {wins[0]}, CPU {wins[1]}")
    print("all checks passed")


if __name__ == '__main__':
    main()
