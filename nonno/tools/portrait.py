"""Nonno portrait, 64x94, 14 colours, drawn from the proportions of his photo (photo not in the repo)."""
import math, numpy as np
from PIL import Image, ImageDraw
W_, H_ = 64, 94
# photo-space (x5 view) -> sprite space. Head bbox in photo: x 100..346, y 48..366  ->  sprite x 4..60, y 1..67
X0, X1, Y0, Y1 = 100, 346, 48, 366
SX, SY = 56/(X1-X0), 66/(Y1-Y0)
mp = lambda x, y: (4 + (x-X0)*SX, 1 + (y-Y0)*SY)
poly = [(210,48),(262,52),(300,70),(322,105),(334,150),(346,200),(344,232),(332,262),(318,300),(296,332),(262,358),(222,362),(190,350),(160,326),(140,290),(124,255),(112,215),(104,170),(103,128),(112,92),(135,68),(170,52)]
skin = [(250,222,198), (234,190,160), (206,152,124), (164,110,90)]
grey = [(244,244,248), (206,206,214), (146,146,158)]
OL = (34, 22, 22); WH = (252, 250, 242); IRIS = (84, 72, 62)
SHIRT = [(86, 90, 104), (56, 60, 74), (36, 38, 50)]; SHORT = (40, 44, 78)

def build(variant=0):
    im = Image.new('RGBA', (W_, H_), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    A = lambda c: c + (255,)
    P = lambda pts: [mp(*p) for p in pts]
    # ---- body
    d.rectangle((14, 68, 49, 87), fill=A(SHIRT[1])); d.rectangle((14, 68, 23, 87), fill=A(SHIRT[0])); d.rectangle((14, 83, 49, 87), fill=A(SHIRT[2]))
    d.rectangle((26, 66, 37, 72), fill=A(skin[2])); d.polygon([(26, 68), (37, 68), (31, 74)], fill=A(skin[1]))
    for (a, b) in ((6, 13), (50, 57)):
        d.rectangle((a, 70, b, 78), fill=A(SHIRT[1])); d.ellipse((a-1, 77, b+1, 86), fill=A(skin[1]))
    d.rectangle((17, 88, 28, 92), fill=A(SHORT)); d.rectangle((35, 88, 46, 92), fill=A(SHORT))
    d.rectangle((15, 92, 28, 93), fill=A(OL)); d.rectangle((35, 92, 48, 93), fill=A(OL))
    # ---- head
    d.polygon(P(poly), fill=A(skin[1]))
    m = Image.new('L', (W_, H_), 0); ImageDraw.Draw(m).polygon(P(poly), fill=255); m = np.array(m) > 0
    YY, XX = np.mgrid[0:H_, 0:W_]
    cx, cy = mp(223, 205)
    t = (XX-cx)/28*0.7 + (YY-cy)/33*0.55
    for y, x in zip(*np.nonzero(m)):
        c = skin[0] if t[y, x] < -0.42 else skin[1] if t[y, x] < 0.3 else skin[2]
        im.putpixel((int(x), int(y)), A(c))
    # ears
    for (ex, ey, sg) in ((112, 226, -1), (340, 222, 1)):
        X, Y = mp(ex, ey); d.ellipse((X-3, Y-6, X+3, Y+6), fill=A(skin[2])); d.line((X+sg*-1, Y-3, X+sg*-1, Y+3), fill=A(skin[3]))
    # ---- hair: grey on the sides, thin fringe on top
    for pts in ([(100,84),(128,62),(150,52),(136,96),(126,150),(118,214),(104,182),(100,130)],
                [(346,88),(322,64),(298,52),(314,98),(324,150),(332,206),(346,190),(348,130)],
                [(150,56),(210,44),(282,52),(304,64),(280,68),(212,57),(160,70)]):
        d.polygon(P(pts), fill=A(grey[1]))
    for pts in ([(100,84),(114,74),(122,100),(112,170),(100,130)], [(346,88),(334,76),(324,100),(334,170),(346,130)]):
        d.polygon(P(pts), fill=A(grey[0]))
    for k in range(12):                                   # strands
        x, y = mp(112 + (k % 2)*6, 80 + k*10); d.line((x, y, x-1, y+3), fill=A(grey[2]))
        x, y = mp(336 - (k % 2)*6, 80 + k*10); d.line((x, y, x+1, y+3), fill=A(grey[2]))
    # ---- forehead lines, folds, eye bags
    for (a, b) in (((178, 108), (270, 108)), ((190, 124), (262, 124))):
        d.line([mp(*a), mp(*b)], fill=A(skin[2]))
    for pts in (((192,238),(184,262),(186,284)), ((284,232),(296,258),(296,284))):
        d.line([mp(*p) for p in pts], fill=A(skin[3]))
    for (cx_, cy_) in ((190, 204), (272, 200)):
        X, Y = mp(cx_, cy_); d.line((X-5, Y, X+5, Y), fill=A(skin[2]))
    # ---- brows
    d.line([mp(162, 160), mp(224, 168)], fill=A(grey[2]), width=2); d.line([mp(246, 164), mp(308, 154)], fill=A(grey[2]), width=2)
    # ---- eyes (narrowed by the smile)
    for (ex, ey, sg) in ((190, 188, 1), (272, 184, -1)):
        X, Y = mp(ex, ey)
        d.ellipse((X-5, Y-2, X+5, Y+2), fill=A(WH)); d.ellipse((X-2, Y-2, X+2, Y+2), fill=A(IRIS)); d.rectangle((X-1, Y-1, X, Y), fill=A(OL))
        d.line((X-6, Y-3, X+6, Y-3), fill=A(OL)); d.line((X-5, Y+3, X+5, Y+3), fill=A(skin[3]))
        for k in (0, 1, 2): d.line((X+sg*7, Y-2+k*2, X+sg*11, Y-3+k*3), fill=A(skin[3]))
    # ---- nose
    d.line([mp(234, 196), mp(228, 244)], fill=A(skin[2]), width=1); d.line([mp(214, 252), mp(246, 252)], fill=A(skin[3]), width=2)
    X, Y = mp(214, 250); d.point((X, Y), fill=A(OL)); X, Y = mp(246, 250); d.point((X, Y), fill=A(OL))
    d.line([mp(212, 256), mp(222, 262)], fill=A(skin[2])); d.line([mp(248, 256), mp(238, 262)], fill=A(skin[2]))
    # ---- mouth: smile showing the upper teeth
    Xa, Ya = mp(198, 272); Xb, Yb = mp(290, 272); Xm = (Xa+Xb)/2
    d.pieslice((Xa, Ya-6, Xb, Ya+7), 0, 180, fill=A(OL))
    d.rectangle((Xa+4, Ya+1, Xb-4, Ya+3), fill=A(WH)); d.point((Xm, Ya+2), fill=A(OL)); d.point((Xm+1, Ya+2), fill=A(OL))
    d.arc((Xa, Ya-6, Xb, Ya+7), 0, 180, fill=A(skin[3]))
    d.line((Xa-1, Ya, Xa+1, Ya-3), fill=A(skin[3])); d.line((Xb+1, Ya, Xb-1, Ya-3), fill=A(skin[3]))
    # ---- grey stubble on the chin and jaw
    sm = Image.new('L', (W_, H_), 0); ImageDraw.Draw(sm).polygon(P([(150,296),(196,320),(250,326),(300,306),(318,292),(302,342),(262,362),(222,366),(188,354),(160,326)]), fill=255)
    sm = np.array(sm) > 0
    for y, x in zip(*np.nonzero(sm & m)):
        if (x + y) % 2 == 0: im.putpixel((int(x), int(y)), A(grey[1] if (x*3 + y) % 5 else grey[2]))
    # ---- outline
    a = np.pad(np.array(im)[..., 3] > 0, 1); ol = np.zeros_like(a)
    for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)): ol |= np.roll(np.roll(a, dy, 0), dx, 1)
    ol = (ol & ~a)[1:-1, 1:-1]
    for y, x in zip(*np.nonzero(ol)): im.putpixel((int(x), int(y)), A(OL))
    return im

