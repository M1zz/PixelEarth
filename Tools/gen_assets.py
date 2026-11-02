#!/usr/bin/env python3
"""Pixel-art asset generator for Pixel Earth (macOS/SpriteKit).
Produces real PNG spritesheets so they can later be swapped for hand-drawn packs.
Run: python3 gen_assets.py <outdir>
"""
import sys, os, math, random
from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else 'out'
os.makedirs(OUT, exist_ok=True)
T = 16  # tile size

# ---------------------------------------------------------------- palettes
# Each ramp: outline, shadow, dark, base, light, highlight  (hex)
def ramp(*hexes): return [tuple(int(h[i:i+2],16) for i in (1,3,5)) + (255,) for h in hexes]
PAL = {
 'dirt':   ramp('#2b1a10','#4a2e1b','#6b4425','#8a5a2f','#a3713d','#c08a4f'),
 'grass':  ramp('#143d16','#1f5e22','#2f8a32','#45ad3c','#6fcf4a','#a2e86b'),
 'stone':  ramp('#1d1f26','#3a3d48','#55596a','#737888','#8e93a3','#b1b6c4'),
 'wood':   ramp('#2a1a10','#4a2f1c','#6a4428','#875a34','#a37241','#c48f55'),
 'leaves': ramp('#10331a','#1c5126','#277033','#359043','#4db257','#86d66e'),
 'coal':   ramp('#0a0a0e','#15151b','#22222b','#2e2e3a','#3d3d4b','#55556a'),
 'iron':   ramp('#3a2416','#6b4a32','#9a6d4a','#c48a5e','#dba77c','#f0c9a3'),
 'gold':   ramp('#5a3a05','#a06a0c','#d49416','#f2bb2b','#ffd95a','#fff1a8'),
 'sand':   ramp('#5b4a22','#9e8a4a','#c9b36a','#e2cd82','#efdc9a','#faf0bf'),
 'plank':  ramp('#3a2412','#6b4423','#9a6a36','#c48d4b','#d9a65f','#ead08c'),
 'bedrock':ramp('#000000','#101014','#1a1a20','#26262e','#33333d','#44444f'),
 'brick':  ramp('#232530','#464a58','#656a7c','#858b9e','#9fa5b8','#c5cad8'),
 'snow':   ramp('#6e8fb5','#a9c3e2','#d2e2f5','#eef5ff','#f8fbff','#ffffff'),
 'ice':    ramp('#2a5f8a','#4a8fbf','#6fb5dd','#95d2ef','#bde6f8','#e6f7ff'),
 'cactus': ramp('#17381a','#235a28','#2f7a34','#3f9a44','#5fb85c','#93d684'),
 'diamond':ramp('#0f5a6a','#1f9db2','#3fd0e6','#7ff0ff','#bdf9ff','#ffffff'),
 'pine':   ramp('#1c110a','#33201a','#4a2f22','#5e3f2c','#73503a','#8a654a'),
 'snowleaf':ramp('#0e2c1a','#1b4a2a','#276638','#2f7d44','#eef5ff','#ffffff'),
 'stonewall':ramp('#15161c','#2c2e38','#3f424f','#52566a','#656a7f','#7d829a'),
 'glass':  ramp('#4a7a9a','#9fd2ee','#c5e8fa','#dff3ff','#ffffff','#ffffff'),
 'water':  ramp('#0e2f6e','#1b4aa8','#2a66d1','#3b82e8','#6aa8f5','#bfe0ff'),
 'lava':   ramp('#4a0e02','#8a2208','#c8420c','#f06a14','#ffa02a','#ffe070'),
 'skin':   ramp('#3a1f12','#8a5a3c','#c98b63','#eab38a','#f6cfae','#ffe6d2'),
 'rubble': ramp('#17141a','#2e2730','#453a44','#5a4c58','#73636f','#8f7f8a'),
 'crystal':ramp('#3d6f8f','#8fd4ee','#bfeaf8','#e2f7ff','#ffffff','#ffffff'),
 'redglow':ramp('#4a0f1f','#9a1f3a','#d8385a','#ff5f7a','#ff9fb0','#ffe0e6'),
 'grnglow':ramp('#0f4a2a','#1f8a4a','#3fc46f','#7fe89a','#b8ffc8','#eafff0'),
 'bluglow':ramp('#0f2f5a','#1f5fb0','#3f9ae8','#7fc8ff','#b8e4ff','#eaf6ff'),
}
OUTL = (20, 14, 24, 255)
CLEAR = (0, 0, 0, 0)

def mix(a, b, t):
    return tuple(int(a[i] + (b[i]-a[i])*t) for i in range(3)) + (255,)

class Canvas:
    def __init__(self, w, h):
        self.img = Image.new('RGBA', (w, h), CLEAR); self.w=w; self.h=h; self.px=self.img.load()
    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h: self.px[x, y] = c
    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h: return self.px[x, y]
        return CLEAR
    def rect(self, x, y, w, h, c):
        for yy in range(y, y+h):
            for xx in range(x, x+w): self.put(xx, yy, c)
    def line(self, x0, y0, x1, y1, c):
        dx, dy = abs(x1-x0), abs(y1-y0); sx = 1 if x0<x1 else -1; sy = 1 if y0<y1 else -1; err = dx-dy
        while True:
            self.put(x0, y0, c)
            if x0==x1 and y0==y1: break
            e2 = 2*err
            if e2 > -dy: err -= dy; x0 += sx
            if e2 < dx: err += dx; y0 += sy
    def outline(self, c=OUTL):
        """Draw 1px outline around all opaque pixels (inside transparent neighbors)."""
        src = [[self.px[x,y] for y in range(self.h)] for x in range(self.w)]
        for y in range(self.h):
            for x in range(self.w):
                if src[x][y][3] == 0:
                    for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                        nx,ny = x+dx,y+dy
                        if 0<=nx<self.w and 0<=ny<self.h and src[nx][ny][3] and src[nx][ny] != c:
                            self.put(x,y,c); break
    def paste(self, other, x, y):
        self.img.alpha_composite(other.img, (x, y))
    def shade(self, x, y, f):
        c = self.get(x, y)
        if c[3]: self.put(x, y, tuple(min(255, int(v*f)) for v in c[:3]) + (c[3],))

# ---------------------------------------------------------------- tile textures
def texture_fill(c, pal, rng, kind):
    o, sh, dk, base, lt, hi = pal
    c.rect(0, 0, T, T, base)
    if kind in ('dirt', 'plank_bg'):
        for _ in range(7):  # clumps
            x, y = rng.randrange(0, T-1), rng.randrange(0, T-1)
            col = dk if rng.random() < 0.6 else lt
            c.rect(x, y, rng.choice((1, 2)), rng.choice((1, 2)), col)
        for _ in range(3):  # pebbles
            x, y = rng.randrange(1, T-2), rng.randrange(1, T-2)
            c.put(x, y, lt); c.put(x+1, y, lt); c.put(x, y+1, dk); c.put(x+1, y+1, dk)
    elif kind in ('stone', 'brick', 'bedrock', 'stonewall'):
        for _ in range(4):  # pebbles / facets
            x, y = rng.randrange(1, T-3), rng.randrange(1, T-3)
            w, h = rng.choice((2, 3)), rng.choice((1, 2))
            c.rect(x, y, w, h, lt); c.rect(x, y+h, w, 1, dk)
        for _ in range(2):  # cracks
            x, y = rng.randrange(1, T-4), rng.randrange(1, T-4)
            l = rng.randrange(2, 5)
            for i in range(l):
                c.put(x+i, y + (i//2 if rng.random()<0.5 else 0), sh)
        for _ in range(5):
            c.put(rng.randrange(T), rng.randrange(T), dk)
    elif kind in ('sand', 'snow'):
        for _ in range(10):
            x, y = rng.randrange(T), rng.randrange(T)
            c.put(x, y, lt if rng.random() < 0.5 else dk)
        for _ in range(3):
            x, y = rng.randrange(T-1), rng.randrange(T-1); c.put(x, y, hi); c.put(x+1, y, lt)
    elif kind == 'ice':
        for _ in range(3):
            x, y = rng.randrange(2, T-6), rng.randrange(2, T-3); l = rng.randrange(3, 6)
            c.line(x, y, x+l, y-1, hi)
        for _ in range(4): c.put(rng.randrange(T), rng.randrange(T), lt)
    elif kind in ('wood', 'pine'):
        for x in range(T):
            col = base
            if x in (2, 3, 9, 10): col = dk
            if x in (6, 13): col = lt
            c.rect(x, 0, 1, T, col)
        kx, ky = rng.randrange(4, 12), rng.randrange(3, 12)
        c.rect(kx, ky, 3, 2, dk); c.put(kx+1, ky, sh); c.rect(kx-1, ky-1, 5, 1, lt)
    elif kind in ('leaves', 'snowleaf'):
        c.rect(0, 0, T, T, dk)
        for _ in range(9):
            x, y = rng.randrange(-1, T-1), rng.randrange(-1, T-1)
            c.rect(x, y, 3, 2, base if rng.random() < 0.7 else lt)
        for _ in range(4):
            x, y = rng.randrange(T-1), rng.randrange(T-1); c.put(x, y, hi if rng.random()<0.5 else lt)
    elif kind == 'plank':
        for y in range(T):
            col = base
            if y in (0, 8): col = sh
            if y in (1, 9): col = lt
            if y in (7, 15): col = dk
            c.rect(0, y, T, 1, col)
        c.rect(5, 1, 1, 6, dk); c.rect(11, 9, 1, 6, dk)
        for _ in range(4): c.put(rng.randrange(T), rng.randrange(T), lt)
    elif kind == 'ore':
        pass
    elif kind == 'cactus':
        c.rect(0, 0, T, T, base)
        for x in (2, 6, 10, 14): c.rect(x, 0, 1, T, dk)
        for x in (4, 8, 12): c.rect(x, 0, 1, T, lt)
        for _ in range(4):
            x, y = rng.randrange(1, T-1), rng.randrange(1, T-1); c.put(x, y, (255,255,255,255))
    elif kind == 'rubble':
        c.rect(0, 0, T, T, base)
        for _ in range(5):  # sharp shards
            x, y = rng.randrange(0, T-3), rng.randrange(0, T-3); w, h = rng.choice((3,4,5)), rng.choice((2,3))
            c.rect(x, y, w, h, lt if rng.random()<0.5 else dk); c.rect(x, y+h-1, w, 1, sh); c.put(x, y, hi)
        for _ in range(6): c.put(rng.randrange(T), rng.randrange(T), sh)
    elif kind == 'crystal':
        c.rect(0, 0, T, T, (190, 234, 248, 150))
        for _ in range(3):
            x, y = rng.randrange(0, T-4), rng.randrange(2, T-1); l = rng.randrange(4, 8)
            c.line(x, y, x+l, y-l, (255,255,255,200)); c.line(x+1, y, x+l, y-l+1, (230,247,255,120))
        for _ in range(3): c.put(rng.randrange(T), rng.randrange(T), (255,255,255,255))
    elif kind == 'glass':
        c.rect(0, 0, T, T, (200, 235, 255, 70))
        c.line(2, 10, 10, 2, (255,255,255,160)); c.line(4, 12, 12, 4, (255,255,255,110))

def apply_edges(c, pal, mask, rng, kind):
    """mask bits: 1=up exposed, 2=right, 4=down, 8=left."""
    o, sh, dk, base, lt, hi = pal
    U, R, D, L = mask & 1, mask & 2, mask & 4, mask & 8
    if kind in ('leaves', 'snowleaf'):
        # scalloped organic edges
        for i in range(T):
            if U and (i % 4 in (0, 3) or rng.random() < 0.2): c.put(i, 0, CLEAR)
            if D and (i % 4 in (1, 2) or rng.random() < 0.2): c.put(i, T-1, CLEAR)
            if L and (i % 4 in (0, 3) or rng.random() < 0.2): c.put(0, i, CLEAR)
            if R and (i % 4 in (1, 2) or rng.random() < 0.2): c.put(T-1, i, CLEAR)
        if U and L: c.put(0,0,CLEAR); c.put(1,0,CLEAR); c.put(0,1,CLEAR)
        if U and R: c.put(T-1,0,CLEAR); c.put(T-2,0,CLEAR); c.put(T-1,1,CLEAR)
        if D and L: c.put(0,T-1,CLEAR); c.put(1,T-1,CLEAR); c.put(0,T-2,CLEAR)
        if D and R: c.put(T-1,T-1,CLEAR); c.put(T-2,T-1,CLEAR); c.put(T-1,T-2,CLEAR)
        # highlight on exposed top
        if U:
            for x in range(T):
                if c.get(x, 0)[3] == 0 and c.get(x, 1)[3]: c.put(x, 1, hi if kind=='leaves' else (255,255,255,255))
        c.outline(o)
        return
    if kind == 'grass':
        g = PAL['grass']
        if U:
            depth = [4,4,5,4,3,4,5,5,4,3,4,4,5,4,4,3]
            for x in range(T):
                d = depth[(x + rng.randrange(0,2)) % T]
                for y in range(d): c.put(x, y, g[3] if y < d-1 else g[2])
                c.put(x, 0, g[4])
            # tufts: knock out some top pixels, add highlights
            for x in range(T):
                r = rng.random()
                if r < 0.25: c.put(x, 0, CLEAR)
                elif r < 0.5: c.put(x, 0, g[5])
                elif r < 0.6: c.put(x, 0, CLEAR); c.put(x, 1, g[5])
            # soil shadow under grass
            for x in range(T):
                y = 0
                while y < T and c.get(x,y)[:3] in (g[2][:3], g[3][:3], g[4][:3], g[5][:3]): y += 1
                if y < T: c.put(x, y, sh)
        if L:
            for y in range(0 if U else 0, 7 if U else 4):
                w = 2 if y < 4 else 1
                for x in range(w): c.put(x, y, g[3] if x else g[4])
        if R:
            for y in range(0, 7 if U else 4):
                w = 2 if y < 4 else 1
                for x in range(w): c.put(T-1-x, y, g[3] if x else g[2])
    # bevel / shadow
    if U and kind != 'grass':
        for x in range(T): c.put(x, 0, lt);
        for x in range(T):
            if rng.random() < 0.35: c.put(x, 1, lt if kind not in ('snow','ice') else hi)
        if kind == 'snow':
            for x in range(T): c.put(x, 0, hi); c.put(x, 1, hi)
    if L and kind != 'grass':
        for y in range(T): c.put(0, y, lt if kind != 'stone' else base)
    if D:
        for x in range(T): c.put(x, T-1, sh)
        for x in range(T):
            if rng.random() < 0.4: c.put(x, T-2, dk)
    if R:
        for y in range(T): c.put(T-1, y, dk)
    # outline on exposed sides
    for i in range(T):
        if U: c.put(i, 0, o) if kind != 'grass' or c.get(i,0)[3] else None
        if D: c.put(i, T-1, o)
        if L: c.put(0, i, o)
        if R: c.put(T-1, i, o)
    if kind == 'grass' and U:
        # outline just above the grass surface where tufts were knocked out -> keep transparent, but outline sides of tufts
        for x in range(T):
            if c.get(x,0)[3] == 0 and c.get(x,1)[3]: c.put(x,1,o)
    # rounded corners
    if U and L: c.put(0, 0, CLEAR); c.put(1, 1, o)
    if U and R: c.put(T-1, 0, CLEAR); c.put(T-2, 1, o)
    if D and L: c.put(0, T-1, CLEAR); c.put(1, T-2, o)
    if D and R: c.put(T-1, T-1, CLEAR); c.put(T-2, T-2, o)
    if kind == 'glass':
        # frame
        for i in range(T):
            if U: c.put(i,0,PAL['glass'][1])
            if D: c.put(i,T-1,PAL['glass'][1])
            if L: c.put(0,i,PAL['glass'][1])
            if R: c.put(T-1,i,PAL['glass'][1])

def ore_overlay(c, pal, rng):
    o, sh, dk, base, lt, hi = pal
    for _ in range(3):
        x, y = rng.randrange(2, T-4), rng.randrange(2, T-4)
        c.rect(x, y, 3, 3, base); c.put(x, y, hi); c.put(x+1, y, lt); c.put(x, y+1, lt); c.rect(x, y+2, 3, 1, dk); c.put(x+2, y+1, dk)
        for (ox, oy) in ((-1,0),(-1,1),(-1,2),(3,0),(3,1),(3,2),(0,-1),(1,-1),(2,-1),(0,3),(1,3),(2,3)): c.put(x+ox, y+oy, o)

AUTOTILE = {  # id: (kind, palette)
 1:('dirt','dirt'), 2:('grass','dirt'), 3:('stone','stone'), 4:('wood','wood'), 5:('leaves','leaves'),
 6:('ore','coal'), 7:('ore','iron'), 8:('ore','gold'), 9:('sand','sand'), 11:('plank','plank'), 12:('bedrock','bedrock'),
 13:('brick','brick'), 15:('glass','glass'), 18:('snow','snow'), 19:('ice','ice'), 20:('cactus','cactus'), 24:('ore','diamond'),
 27:('pine','pine'), 28:('snowleaf','snowleaf'), 30:('stonewall','stonewall'),
 31:('rubble','rubble'), 32:('crystal','crystal'),
}

def make_tile(tid, mask, variant):
    kind, pname = AUTOTILE[tid]
    rng = random.Random(tid * 1000 + mask * 7 + variant * 131)
    c = Canvas(T, T)
    pal = PAL[pname]
    if kind == 'ore':
        texture_fill(c, PAL['stone'], rng, 'stone'); ore_overlay(c, pal, rng)
        apply_edges(c, PAL['stone'], mask, rng, 'stone')
    elif kind == 'grass':
        texture_fill(c, pal, rng, 'dirt'); apply_edges(c, pal, mask, rng, 'grass')
    else:
        texture_fill(c, pal, rng, kind); apply_edges(c, pal, mask, rng, kind)
    return c

# ---------------------------------------------------------------- special tiles (frames)
def torch(frame):
    c = Canvas(T, T); rng = random.Random(frame)
    c.rect(7, 7, 2, 9, PAL['wood'][3]); c.put(7, 7, PAL['wood'][4]); c.rect(7, 15, 2, 1, PAL['wood'][1])
    c.rect(6, 6, 4, 2, (90, 70, 50, 255))
    fl = [(6,3,4,4),(6,2,4,5),(5,3,5,4),(6,3,4,4)][frame]
    x, y, w, h = fl
    c.rect(x, y, w, h, PAL['lava'][3]); c.rect(x+1, y-1, w-2, 1, PAL['lava'][3])
    c.rect(x+1, y+1, w-2, h-2, PAL['lava'][4]); c.put(x+1 + frame % 2, y+1, PAL['lava'][5]); c.put(x+ (frame%3), y-1 if frame%2 else y, PAL['lava'][5])
    return c

def flame_tile(pal, frame, rows=T):
    c = Canvas(T, T); rng = random.Random(frame)
    o, sh, dk, base, lt, hi = pal
    c.rect(0, 0, T, T, base)
    for x in range(T):
        y = (x*3 + frame*4) % 16
        c.put(x, (y // 4) * 4 + (frame % 2), lt)
        if (x + frame) % 7 == 0: c.rect(x, 6 + (x % 3), 2, 1, hi)
        if (x + frame) % 5 == 0: c.rect(x, 11 - (x % 4), 1, 2, dk)
    return c

def water_tile(frame):
    c = Canvas(T, T)
    o, sh, dk, base, lt, hi = PAL['water']
    c.rect(0, 0, T, T, (base[0], base[1], base[2], 190))
    for x in range(T):
        if (x + frame*2) % 8 < 3: c.put(x, 0, (hi[0],hi[1],hi[2],220))
        if (x + frame*2 + 4) % 11 < 2: c.put(x, 5 + (x % 2), (lt[0],lt[1],lt[2],160))
        if (x*3 + frame) % 13 < 2: c.put(x, 11, (dk[0],dk[1],dk[2],200))
    return c

def door_tile(open_):
    c = Canvas(T, T); p = PAL['plank']
    if not open_:
        c.rect(4, 0, 8, T, p[3]); c.rect(4, 0, 1, T, p[4]); c.rect(11, 0, 1, T, p[1])
        c.rect(6, 2, 4, 5, p[2]); c.rect(6, 9, 4, 5, p[2]); c.rect(6, 2, 4, 1, p[1]); c.rect(6, 9, 4, 1, p[1])
        c.put(10, 8, PAL['gold'][4])
    else:
        c.rect(0, 0, 3, T, p[3]); c.rect(0, 0, 1, T, p[4]); c.rect(2, 0, 1, T, p[1]); c.rect(1,3,1,4,p[2]); c.rect(1,9,1,4,p[2])
    c.outline(OUTL); return c

def chest_tile(open_):
    c = Canvas(T, T); p = PAL['wood']; g = PAL['gold']
    c.rect(1, 5 if not open_ else 7, 14, 10 if not open_ else 8, p[3])
    c.rect(1, 5 if not open_ else 7, 14, 1, p[4])
    c.rect(1, 9, 14, 1, p[1]); c.rect(2, 10, 12, 4, p[2])
    if open_:
        c.rect(1, 3, 14, 3, p[2]); c.rect(1, 3, 14, 1, p[4]); c.rect(3, 7, 10, 1, g[4])
    c.rect(7, 8, 2, 3, g[3]); c.put(7, 8, g[5]); c.rect(1,5,1,10,p[1]); c.rect(14,5,1,10,p[1])
    c.outline(OUTL); return c

def flower_tile(v):
    c = Canvas(T, T); g = PAL['grass']
    cols = [((255,107,157,255),(255,190,215,255)), ((255,210,63,255),(255,240,160,255)), ((255,140,42,255),(255,200,120,255)), ((197,139,255,255),(230,210,255,255))][v]
    c.rect(7, 8, 2, 8, g[3]); c.put(7, 15, g[2]); c.rect(4, 11, 3, 2, g[3]); c.rect(10, 12, 3, 2, g[3]); c.put(4,11,g[4]); c.put(12,12,g[4])
    c.rect(5, 4, 6, 5, cols[0]); c.put(5,4,CLEAR); c.put(10,4,CLEAR); c.put(5,8,CLEAR); c.put(10,8,CLEAR)
    c.rect(7, 5, 2, 2, cols[1]); c.put(7, 6, (255, 230, 120, 255))
    if v == 3: c.rect(2, 9, 2, 7, g[3]); c.rect(12, 10, 2, 6, g[3])
    c.outline(OUTL); return c

def shroom_tile(f):
    c = Canvas(T, T); d = PAL['diamond']
    c.rect(6, 8, 4, 8, (220, 245, 255, 255)); c.rect(6, 8, 1, 8, (180, 215, 235, 255))
    c.rect(3, 4, 10, 5, d[3]); c.rect(5, 2, 6, 2, d[3]); c.rect(4, 3, 8, 1, d[3])
    c.rect(4, 4, 8, 1, d[4]); c.put(5, 5, d[5]); c.put(6, 5, d[5]); c.put(10, 6, d[5])
    if f: c.put(7, 3, d[5]); c.put(11, 5, d[5])
    c.outline(OUTL); return c

def platform_tile(mask):
    c = Canvas(T, T); p = PAL['plank']
    L, R = mask & 8, mask & 2
    c.rect(0, 2, T, 4, p[3]); c.rect(0, 2, T, 1, p[4]); c.rect(0, 5, T, 1, p[1])
    for x in (2, 13): c.rect(x, 6, 2, 3, p[2])
    if L: c.rect(0, 2, 1, 4, p[1])
    if R: c.rect(T-1, 2, 1, 4, p[1])
    c.put(6, 3, p[2]); c.put(10, 4, p[2])
    c.outline(OUTL); return c

def lantern_tile(f):
    c = Canvas(T, T); g = PAL['gold']; st = PAL['stone']
    c.rect(7, 0, 2, 3, st[2]); c.rect(5, 3, 6, 1, st[2]); c.rect(5, 11, 6, 1, st[2]); c.rect(5, 4, 1, 7, st[2]); c.rect(10, 4, 1, 7, st[2])
    c.rect(6, 4, 4, 7, (255, 225, 140, 255)); c.rect(7, 5, 2, 4, (255, 245, 200, 255))
    if f: c.put(7, 6, (255,255,255,255))
    c.outline(OUTL); return c

def bench_tile():
    c = Canvas(T, T); p = PAL['plank']; st = PAL['stone']; ir = PAL['iron']
    c.rect(0, 4, T, 3, p[3]); c.rect(0, 4, T, 1, p[4]); c.rect(0, 6, T, 1, p[1])
    c.rect(1, 7, 3, 9, p[2]); c.rect(12, 7, 3, 9, p[2]); c.rect(1, 10, 14, 1, p[1])
    c.rect(4, 1, 4, 3, st[3]); c.rect(4, 1, 4, 1, st[4]); c.rect(10, 2, 3, 2, ir[3]); c.put(10,2,ir[4])
    c.outline(OUTL); return c

def spore_tile(pname, f):
    c = Canvas(T, T); p = PAL[pname]; g = PAL['grass']
    c.rect(7, 9, 2, 7, (90, 70, 60, 255)); c.put(7, 9, (120, 95, 80, 255))
    r = 4 if f == 0 else 5
    for y in range(2, 2 + 2*r):
        for x in range(8 - r, 8 + r):
            if (x - 7.5)**2 + (y - (1.5 + r))**2 <= r*r: c.put(x, y, p[3])
    c.rect(6, 3, 2, 2, p[5]); c.put(5, 5, p[4]); c.put(9, 7 if f == 0 else 8, p[2])
    if f: c.put(3, 2, p[5]); c.put(12, 4, p[5]); c.put(10, 1, p[4])
    c.outline(OUTL); return c

def pedestal_tile(v):
    c = Canvas(T, T); st = PAL['brick']
    c.rect(2, 12, 12, 4, st[3]); c.rect(2, 12, 12, 1, st[4]); c.rect(4, 8, 8, 4, st[2]); c.rect(4, 8, 8, 1, st[4]); c.rect(1, 15, 14, 1, st[1])
    c.rect(5, 6, 6, 2, st[3]); c.rect(5, 6, 6, 1, st[5])
    if v:
        p = [None, PAL['redglow'], PAL['grnglow'], PAL['bluglow']][v]
        c.rect(6, 1, 4, 5, p[3]); c.rect(7, 0, 2, 1, p[3]); c.rect(6, 2, 1, 2, p[5]); c.put(9, 4, p[2]); c.put(5, 3, p[4]); c.put(10, 2, p[4])
    c.outline(OUTL); return c

def core_tile(f):
    c = Canvas(T, T); g = PAL['gold']; w = PAL['crystal']
    c.rect(3, 13, 10, 3, PAL['bedrock'][3]); c.rect(3, 13, 10, 1, PAL['bedrock'][5])
    col = (120, 120, 140, 255) if f == 0 else (255, 240, 200, 255)
    for y in range(2, 13):
        for x in range(2, 14):
            if (x - 7.5)**2 + (y - 7)**2 <= 25: c.put(x, y, col)
    if f: c.rect(5, 4, 3, 2, (255,255,255,255)); c.put(10, 9, g[4]); c.put(4, 9, w[1])
    else: c.rect(5, 4, 3, 2, (170,170,190,255)); c.rect(6, 8, 4, 1, (90,90,110,255))
    c.outline(OUTL); return c

def plant_tile(pname, f):
    c = Canvas(T, T); p = PAL[pname]; st = PAL['grass']
    c.rect(7, 8, 2, 8, p[1]); c.rect(4, 11, 3, 1, p[1]); c.rect(10, 12, 3, 1, p[1])
    for (x, y) in ((7, 2), (3, 7), (11, 8), (7, 5)):
        c.rect(x-1, y, 4 if x == 7 and y == 2 else 3, 3, p[3]); c.put(x, y, p[5])
    if f: c.put(1, 4, p[4]); c.put(14, 3, p[4]); c.put(12, 1, p[5])
    c.outline(OUTL); return c

def vine_tile(f):
    c = Canvas(T, T); g = PAL['grass']
    for y in range(T):
        x = 7 + (1 if (y // 3 + f) % 2 else 0)
        c.put(x, y, g[2]); c.put(x+1, y, g[3])
    for (x, y) in ((4, 3), (10, 7), (3, 11), (11, 13)):
        c.rect(x, y, 3, 2, g[3]); c.put(x+1, y, g[4])
    c.outline(OUTL); return c

SPECIAL = {
 10: [torch(f) for f in range(4)],
 14: [bench_tile()],
 16: [door_tile(False), door_tile(True)],
 17: [water_tile(f) for f in range(4)],
 21: [shroom_tile(0), shroom_tile(1)],
 22: [flame_tile(PAL['lava'], f) for f in range(4)],
 23: [chest_tile(False), chest_tile(True)],
 25: [flower_tile(v) for v in range(4)],
 26: [platform_tile(m) for m in (0, 2, 8, 10)],
 29: [lantern_tile(0), lantern_tile(1)],
 33: [spore_tile('redglow', 0), spore_tile('redglow', 1)],
 34: [spore_tile('bluglow', 0), spore_tile('bluglow', 1)],
 35: [spore_tile('grnglow', 0), spore_tile('grnglow', 1)],
 39: [pedestal_tile(v) for v in range(4)],
 40: [core_tile(0), core_tile(1)],
 41: [plant_tile('redglow', 0), plant_tile('redglow', 1)],
 42: [plant_tile('grnglow', 0), plant_tile('grnglow', 1)],
 43: [plant_tile('bluglow', 0), plant_tile('bluglow', 1)],
 44: [vine_tile(0), vine_tile(1)],
}

def build_tiles():
    rows = 45; cols = 32
    atlas = Canvas(cols*T, rows*T)
    for tid in range(1, rows):
        if tid in AUTOTILE:
            for mask in range(16):
                for v in range(2):
                    atlas.paste(make_tile(tid, mask, v), (mask*2+v)*T, tid*T)
        elif tid in SPECIAL:
            for i, c in enumerate(SPECIAL[tid]): atlas.paste(c, i*T, tid*T)
    atlas.img.save(f'{OUT}/tiles.png')
    # walls: dirt, stone, sand, snow(dirt) darker flat
    walls = Canvas(4*T*4, T)
    for i, (kind, p) in enumerate((('dirt','dirt'), ('stone','stone'), ('sand','sand'), ('stone','stonewall'))):
        for v in range(4):
            rng = random.Random(900 + i*10 + v); c = Canvas(T, T); texture_fill(c, PAL[p], rng, kind)
            for y in range(T):
                for x in range(T): c.shade(x, y, 0.42)
            walls.paste(c, (i*4+v)*T, 0)
    walls.img.save(f'{OUT}/walls.png')

# ---------------------------------------------------------------- characters
def player_frame(pose, hair=(90,55,30,255), shirt=(205,70,70,255), pants=(55,62,140,255), armor=None):
    """20x28 frame. pose: 'idle','walk0..5','jump','fall'. Front arm omitted (drawn at runtime)."""
    c = Canvas(20, 32); sk = PAL['skin']
    legA = legB = 0; bob = 0; armBack = 0
    if pose.startswith('walk'):
        i = int(pose[4]); seq = [(-2, 2), (-1, 1), (0, 0), (2, -2), (1, -1), (0, 0)]
        legA, legB = seq[i]; bob = 1 if i in (0, 3) else 0; armBack = -legA
    elif pose == 'jump': legA, legB = -3, 1; bob = -1
    elif pose == 'fall': legA, legB = 1, -2
    y0 = 2 + bob
    # back arm
    bx = 5 + (armBack if armBack else 0)
    c.rect(bx, y0+11, 3, 7, shirt if not armor else armor); c.rect(bx, y0+18, 3, 2, sk[3])
    # legs
    c.rect(6, y0+18, 4, 7 + legA, pants); c.rect(10, y0+18, 4, 7 + legB, pants)
    c.rect(6, y0+18+7+legA-1, 4, 1, (40, 42, 90, 255)); c.rect(10, y0+18+7+legB-1, 4, 1, (40, 42, 90, 255))
    # shoes
    c.rect(5, y0+25+legA, 5, 2, (60, 40, 30, 255)); c.rect(10, y0+25+legB, 5, 2, (60, 40, 30, 255))
    # torso
    body = armor or shirt
    c.rect(6, y0+10, 8, 9, body); c.rect(6, y0+10, 8, 1, mix(body, (255,255,255,255), 0.25)); c.rect(6, y0+17, 8, 2, mix(body, (0,0,0,255), 0.3))
    if armor: c.rect(9, y0+12, 2, 5, mix(armor, (0,0,0,255), 0.35))
    # head
    c.rect(5, y0+1, 10, 9, sk[3]); c.rect(5, y0+1, 10, 1, sk[4]); c.rect(5, y0+9, 10, 1, sk[2])
    # hair / helmet
    if armor:
        c.rect(4, y0, 12, 4, armor); c.rect(4, y0, 12, 1, mix(armor,(255,255,255,255),0.3)); c.rect(4, y0+4, 2, 4, armor); c.rect(14, y0+4, 2, 4, armor)
    else:
        c.rect(4, y0, 12, 3, hair); c.rect(4, y0+3, 2, 3, hair); c.rect(14, y0+3, 2, 2, hair); c.put(5, y0, mix(hair,(255,255,255,255),0.3)); c.put(6,y0,mix(hair,(255,255,255,255),0.3))
    # face (facing right)
    c.rect(12, y0+4, 2, 2, (30, 30, 40, 255)); c.put(12, y0+4, (255,255,255,255)); c.put(13, y0+7, sk[2])
    c.outline(OUTL)
    return c

def build_player():
    poses = ['idle'] + [f'walk{i}' for i in range(6)] + ['jump', 'fall']
    sets = [('default', None), ('iron', PAL['iron'][3]), ('gold', PAL['gold'][3]), ('diamond', PAL['diamond'][3])]
    sheet = Canvas(20*len(poses), 32*len(sets))
    for r, (name, armor) in enumerate(sets):
        for i, p in enumerate(poses): sheet.paste(player_frame(p, armor=armor), i*20, r*32)
    sheet.img.save(f'{OUT}/player.png')
    arm = Canvas(6, 12); sk = PAL['skin']
    arm.rect(1, 1, 3, 9, (205,70,70,255)); arm.rect(1, 1, 3, 1, (230,110,110,255)); arm.rect(1, 8, 3, 3, sk[3]); arm.outline(OUTL)
    arm.img.save(f'{OUT}/arm.png')

def slime(pal, frame, w=24, h=16, crown=False):
    c = Canvas(w, h + (10 if crown else 0)); o, sh, dk, base, lt, hi = pal
    oy = 10 if crown else 0
    sq = [0, 2][frame]
    top = oy + sq; hh = h - sq
    # body blob
    cy = top + hh*0.62; ry = max(1.0, hh*0.66); bottom = oy + h - 1
    for y in range(top, oy + h):
        if y <= cy:
            f = 1 - ((cy - y)/ry)**2; hw = (w/2 - 1) * (math.sqrt(f) if f > 0 else 0)
        else:
            hw = (w/2 - 1) * (1 - 0.18*((y-cy)/max(1,(bottom-cy)))**2)
        hw = int(round(hw))
        if hw > 0: c.rect(w//2 - hw, y, 2*hw, 1, base)
    for y in range(top, oy+h):
        for x in range(w):
            if c.get(x, y)[3]:
                if y >= oy + h - 3: c.put(x, y, dk)
                if c.get(x-1,y)[3]==0 or c.get(x+1,y)[3]==0: c.put(x, y, dk)
    # highlight
    c.rect(w//4, top + 2, w//4, 2, lt); c.rect(w//4, top+2, 2, 1, hi); c.put(w//4+1, top+3, hi)
    # eyes
    ew = max(2, w//12); eh = ew + 1; gap = max(5, w//5)
    ex = w//2 - gap//2 - ew//2; ey = top + h//2 - eh//2
    c.rect(ex, ey, ew, eh, (20,20,30,255)); c.rect(ex+gap, ey, ew, eh, (20,20,30,255)); c.put(ex, ey, (255,255,255,255)); c.put(ex+gap, ey, (255,255,255,255))
    if crown:  # angry brows
        c.rect(ex-1, ey-2, ew+2, 1, (20,20,30,255)); c.rect(ex+gap-1, ey-2, ew+2, 1, (20,20,30,255))
    if crown:
        g = PAL['gold']; cw = max(16, w//2); cx = w//2 - cw//2
        c.rect(cx, 4, cw, 6, g[3]); c.rect(cx, 4, cw, 1, g[5]); c.rect(cx, 9, cw, 1, g[1])
        n = 5; step = cw//(n-1)
        for i in range(n):
            px = cx + i*step; tall = i % 2 == 1 or i == n//2
            c.rect(px, 0 if tall else 2, 3 if i < n-1 else 2, 4 if tall else 2, g[3]); c.put(px, 0 if tall else 2, g[5])
        c.rect(cx + cw//2 - 1, 6, 2, 2, (255,70,90,255)); c.put(cx+3, 7, PAL['diamond'][4]); c.put(cx+cw-4, 7, PAL['diamond'][4])
    c.outline(o); return c

def zombie(frame):
    c = Canvas(20, 28); sk = ramp('#1f3320','#3f6b3a','#5f8f55','#7aa06a','#93b882','#b5d4a3'); cloth = (60, 70, 85, 255)
    seq = [(-2, 2), (0, 0), (2, -2), (0, 0)]; la, lb = seq[frame]
    c.rect(6, 19, 4, 7 + la, cloth); c.rect(10, 19, 4, 7 + lb, cloth)
    c.rect(6, 11, 8, 9, (95, 70, 60, 255)); c.rect(6, 11, 8, 1, (120, 90, 75, 255)); c.rect(7, 14, 2, 3, (70,50,45,255))
    c.rect(5, 2, 10, 9, sk[3]); c.rect(5, 2, 10, 1, sk[4]); c.rect(5,10,10,1,sk[2])
    c.rect(12, 5, 2, 2, (200, 40, 40, 255)); c.put(12, 5, (255, 120, 120, 255)); c.rect(11, 8, 3, 1, sk[1])
    c.rect(4, 1, 12, 2, sk[2]); c.put(6, 1, sk[1])
    # arms stretched forward
    c.rect(13, 12, 6, 3, sk[3]); c.rect(13,12,6,1,sk[4]); c.rect(12, 15, 3, 3, (95,70,60,255))
    c.outline(OUTL); return c

def bat(frame):
    c = Canvas(24, 14); dk = (70, 55, 90, 255); base = (95, 75, 120, 255)
    c.rect(9, 5, 6, 6, base); c.rect(9, 5, 6, 1, (120,100,145,255)); c.rect(10, 11, 1, 2, dk); c.rect(13, 11, 1, 2, dk)
    c.rect(9, 3, 2, 2, base); c.rect(13, 3, 2, 2, base)
    if frame == 0:
        for i in range(8): c.rect(8 - i, 6 - i//2, 1, 3 + i//3, dk); c.rect(15 + i, 6 - i//2, 1, 3 + i//3, dk)
    else:
        for i in range(8): c.rect(8 - i, 7 + i//2, 1, 3, dk); c.rect(15 + i, 7 + i//2, 1, 3, dk)
    c.put(10, 7, (255, 80, 80, 255)); c.put(13, 7, (255, 80, 80, 255)); c.outline(OUTL); return c

def build_enemies():
    sheet = Canvas(24*2*3, 16)
    for r, p in enumerate(('leaves', 'diamond', 'ice')):
        pal = PAL[p] if p != 'diamond' else ramp('#2a0e3a','#5a2a80','#8a45b0','#b36bd8','#d19ae8','#f0d0ff')
        if p == 'leaves': pal = ramp('#0f3a12','#1f6a22','#3fa03a','#6ad66a','#9fe89a','#d8ffd0')
        if p == 'ice': pal = ramp('#1a3a5a','#3a6f9a','#5fa0cc','#aee6ff','#d6f3ff','#ffffff')
        for f in range(2): sheet.paste(slime(pal, f), (r*2+f)*24, 0)
    sheet.img.save(f'{OUT}/slimes.png')
    z = Canvas(80, 28)
    for f in range(4): z.paste(zombie(f), f*20, 0)
    z.img.save(f'{OUT}/zombie.png')
    b = Canvas(48, 14)
    for f in range(2): b.paste(bat(f), f*24, 0)
    b.img.save(f'{OUT}/bat.png')
    kp = ramp('#0c2f4a','#1f6a9a','#2f8fd0','#5fc0ff','#9fdcff','#e0f6ff')
    k = Canvas(72*2, 56+10)
    for f in range(2): k.paste(slime(kp, f, 72, 56, crown=True), f*72, 0)
    k.img.save(f'{OUT}/king.png')

# ---------------------------------------------------------------- items (16x16)
def pick(pal):
    c = Canvas(16, 16); w = PAL['wood']
    c.line(4, 12, 11, 5, w[3]); c.line(5, 12, 12, 5, w[2])
    # head
    o, sh, dk, base, lt, hi = pal
    c.line(7, 2, 13, 2, base); c.line(6, 3, 13, 3, base); c.rect(13, 3, 1, 6, base); c.rect(12, 4, 1, 5, base); c.rect(6, 2, 1, 1, lt)
    c.line(7, 2, 12, 2, lt); c.rect(13, 4, 1, 4, sh); c.put(12, 8, sh); c.put(8, 3, hi)
    c.outline(OUTL); return c

def sword(pal):
    c = Canvas(16, 16); w = PAL['wood']; o, sh, dk, base, lt, hi = pal
    c.line(4, 11, 12, 3, base); c.line(5, 12, 13, 4, dk); c.line(4, 10, 11, 3, lt); c.put(12, 3, hi)
    c.rect(3, 9, 4, 1, PAL['gold'][3]); c.rect(5, 7, 1, 4, PAL['gold'][3]); c.put(3, 9, PAL['gold'][5])
    c.line(2, 13, 4, 11, w[2]); c.put(2, 13, w[1])
    c.outline(OUTL); return c

def simple_icon(fn):
    c = Canvas(16, 16); fn(c); c.outline(OUTL); return c

def bow(c):
    w = PAL['wood']
    for i in range(12): c.put(4 + (abs(i-6)//2), 2+i, w[3])
    for i in range(12): c.put(5 + (abs(i-6)//2), 2+i, w[2])
    c.line(5, 2, 5, 13, (230, 230, 230, 255)); c.put(4,2,w[4]); c.put(4,13,w[4])
def arrow(c):
    c.line(3, 12, 11, 4, PAL['wood'][3]); c.rect(11, 3, 3, 1, (210,210,210,255)); c.rect(12, 2, 1, 3, (210,210,210,255)); c.put(13,3,(255,255,255,255))
    c.rect(2, 11, 2, 3, (220, 80, 80, 255)); c.rect(3, 13, 2, 1, (220,80,80,255))
def gel(c):
    p = ramp('#0e3a5a','#1f7ab0','#3fb0e8','#5fd3ff','#9fe8ff','#ffffff')
    c.rect(3, 7, 10, 6, p[3]); c.rect(4, 5, 8, 2, p[3]); c.rect(5, 4, 6, 1, p[3]); c.rect(3, 12, 10, 1, p[2]); c.rect(5, 6, 3, 1, p[5]); c.put(5,7,p[4])
def ingot(pal):
    def f(c):
        o, sh, dk, base, lt, hi = pal
        c.rect(3, 6, 10, 5, base); c.rect(2, 7, 1, 4, dk); c.rect(13, 7, 1, 4, dk); c.rect(3, 6, 10, 1, lt); c.rect(3, 10, 10, 1, sh); c.rect(4, 7, 3, 1, hi)
    return f
def diamond_item(c):
    p = PAL['diamond']
    for i in range(5): c.rect(8 - i - 1, 4 + i, 2*i + 2, 1, p[3])
    for i in range(5): c.rect(8 - (4-i) - 1, 9 + i, 2*(4-i) + 2, 1, p[2] if i>2 else p[3])
    c.rect(5, 5, 3, 1, p[5]); c.put(5, 6, p[4]); c.rect(6, 4, 4, 1, p[4])
def potion(c):
    c.rect(6, 1, 4, 3, (210, 210, 220, 255)); c.rect(5, 4, 6, 2, (200,200,210,255)); c.rect(4, 6, 8, 8, (255, 90, 120, 255)); c.rect(3, 8, 10, 5, (255,90,120,255)); c.rect(4, 13, 8, 1, (190, 50, 80, 255))
    c.rect(5, 7, 2, 4, (255, 180, 200, 255)); c.put(5, 7, (255,255,255,255))
def crown(c):
    g = PAL['gold']
    c.rect(2, 8, 12, 6, g[3]); c.rect(2, 8, 12, 1, g[5]); c.rect(2, 13, 12, 1, g[1])
    for i, x in enumerate((2, 6, 10)): c.rect(x+1, 4 if i==1 else 6, 2, 4 if i==1 else 2, g[3]); c.put(x+1, 4 if i==1 else 6, g[5])
    c.rect(13, 6, 1, 2, g[3]); c.put(7, 10, (255, 70, 90, 255)); c.put(8,10,(255,70,90,255)); c.put(4, 11, PAL['diamond'][4]); c.put(11, 11, PAL['diamond'][4])
def armor_icon(pal):
    def f(c):
        o, sh, dk, base, lt, hi = pal
        c.rect(4, 3, 8, 11, base); c.rect(2, 4, 2, 5, base); c.rect(12, 4, 2, 5, base); c.rect(4, 3, 8, 1, lt); c.rect(6, 3, 4, 2, sh); c.rect(4, 12, 8, 2, dk); c.rect(7, 6, 2, 5, dk); c.put(5,5,hi)
    return f
def life_crystal(c):
    r = ramp('#5a0a1a','#a01030','#d82050','#ff3d6b','#ff8aa0','#ffd0da')
    pts = [(8,14),(2,7),(4,3),(8,6),(12,3),(14,7)]
    for y in range(3, 15):
        for x in range(2, 15):
            # inside heart-ish polygon approx
            inside = (y >= 7 and abs(x-8) <= (14-y)*1.0) or (y < 7 and ((x-5)**2 + (y-6)**2 <= 9 or (x-11)**2 + (y-6)**2 <= 9))
            if inside: c.put(x, y, r[3])
    c.put(4, 5, r[5]); c.put(5, 5, r[5]); c.put(4, 6, r[4]); c.rect(6, 12, 4, 1, r[2]); c.rect(7,13,2,1,r[2])
def coin(c):
    g = PAL['gold']; c.rect(4,3,8,10,g[3]); c.rect(3,4,10,8,g[3]); c.rect(5,4,2,6,g[5]); c.rect(4,11,8,1,g[1]); c.rect(7,6,2,4,g[1])

def build_items():
    icons = {
      100: pick(PAL['wood']), 101: pick(PAL['stone']), 102: pick(PAL['iron']), 103: pick(PAL['gold']), 104: pick(PAL['diamond']),
      110: sword(PAL['wood']), 111: sword(PAL['iron']), 112: sword(PAL['gold']), 113: sword(PAL['diamond']),
      120: simple_icon(gel), 121: simple_icon(ingot(PAL['iron'])), 122: simple_icon(ingot(PAL['gold'])), 123: simple_icon(diamond_item),
      130: simple_icon(potion), 131: simple_icon(bow), 132: simple_icon(arrow), 133: simple_icon(crown),
      140: simple_icon(armor_icon(PAL['iron'])), 141: simple_icon(armor_icon(PAL['gold'])), 142: simple_icon(armor_icon(PAL['diamond'])),
      150: simple_icon(life_crystal), 160: simple_icon(coin),
    }
    # layout: 16 columns, id-100 index
    sheet = Canvas(16*16, 16*4)
    for iid, c in icons.items():
        i = iid - 100; sheet.paste(c, (i % 16) * 16, (i // 16) * 16)
    sheet.img.save(f'{OUT}/items.png')

# ---------------------------------------------------------------- background & UI
def build_background():
    rng = random.Random(7)
    for layer, (amp, base, col) in enumerate(((42, 70, (54, 70, 110, 255)), (34, 90, (38, 56, 80, 255)))):
        c = Canvas(512, 160)
        heights = []
        for x in range(512):
            t = x / 512 * math.pi * 2
            h = base - (math.sin(t*2)*0.5 + math.sin(t*5+1)*0.3 + math.sin(t*11)*0.12 + math.sin(t*23)*0.05) * amp
            heights.append(int(h))
        for x in range(512):
            h = heights[x]
            for y in range(h, 160):
                sh = 1.0 if y - h < 2 else (0.97 if (y - h) > 40 and (x*3 + y) % 11 == 0 else 1.0)
                c.put(x, y, tuple(int(v*sh) for v in col[:3]) + (255,))
            if layer == 0 and h < 40: # snow caps
                for y in range(h, min(160, h + (42 - h))): c.put(x, y, (200, 215, 235, 255))
            c.put(x, h, tuple(min(255, int(v*1.3)) for v in col[:3]) + (255,))
        # trees silhouettes on near layer
        if layer == 1:
            for i in range(60):
                x = rng.randrange(512); h = heights[x]; th = rng.randrange(6, 14)
                for yy in range(th):
                    w = max(1, (th - yy) // 3)
                    c.rect(x - w, h - th + yy, 2*w + 1, 1, (28, 42, 60, 255))
        c.img.save(f'{OUT}/mountains{layer}.png')
    clouds = Canvas(192, 32)
    for i, (w, h) in enumerate(((52, 14), (40, 12), (64, 16))):
        x0 = i * 64 + 2
        d = ImageDraw.Draw(clouds.img)
        for (ox, oy, rw, rh) in ((0, 6, w, h-6), (w*0.15, 0, w*0.4, h*0.8), (w*0.45, 2, w*0.45, h*0.7)):
            d.ellipse((x0+ox, 4+oy, x0+ox+rw, 4+oy+rh), fill=(255, 255, 255, 235))
        d.rectangle((x0, 4+h-2, x0+w, 4+h), fill=(220, 230, 245, 235))
    clouds.img.save(f'{OUT}/clouds.png')
    # stars
    st = Canvas(256, 128); rng = random.Random(3)
    for _ in range(90):
        x, y = rng.randrange(256), rng.randrange(128); b = rng.choice((160, 200, 255))
        st.put(x, y, (b, b, 255, 255))
        if rng.random() < 0.2: st.put(x+1, y, (b//2, b//2, 200, 255)); st.put(x, y+1, (b//2, b//2, 200, 255))
    st.img.save(f'{OUT}/stars.png')

def build_ui():
    # 9-slice panel 24x24 (8px borders)
    p = Canvas(24, 24); dark = (22, 26, 38, 235); edge = (60, 66, 90, 255); light = (120, 130, 160, 255)
    p.rect(0, 0, 24, 24, dark); p.rect(1, 1, 22, 22, dark)
    p.rect(0, 0, 24, 1, light); p.rect(0, 0, 1, 24, light); p.rect(0, 23, 24, 1, edge); p.rect(23, 0, 1, 24, edge)
    p.rect(1, 1, 22, 1, edge); p.rect(1, 1, 1, 22, edge)
    p.put(0, 0, CLEAR); p.put(23, 0, CLEAR); p.put(0, 23, CLEAR); p.put(23, 23, CLEAR)
    p.img.save(f'{OUT}/panel.png')
    s = Canvas(40, 40)
    s.rect(0, 0, 40, 40, (30, 34, 50, 230)); s.rect(1, 1, 38, 38, (40, 46, 66, 230)); s.rect(2, 2, 36, 36, (26, 30, 44, 230))
    s.rect(1, 1, 38, 1, (90, 98, 130, 255)); s.rect(1, 1, 1, 38, (90, 98, 130, 255)); s.rect(1, 38, 38, 1, (12, 14, 22, 255)); s.rect(38, 1, 1, 38, (12,14,22,255))
    s.img.save(f'{OUT}/slot.png')
    s2 = Canvas(40, 40); g = PAL['gold']
    s2.rect(0, 0, 40, 40, g[3]); s2.rect(2, 2, 36, 36, (70, 58, 30, 235)); s2.rect(0,0,40,1,g[5]); s2.rect(0,0,1,40,g[5]); s2.rect(0,39,40,1,g[1]); s2.rect(39,0,1,40,g[1])
    s2.img.save(f'{OUT}/slot_sel.png')
    h = Canvas(16, 16)
    hp = ramp('#5a0a1a','#a01030','#d82050','#ff3d6b','#ff8aa0','#ffd0da')
    for y in range(3, 14):
        for x in range(1, 15):
            inside = (y >= 7 and abs(x-8) <= (14-y)*1.15) or (y < 7 and ((x-5)**2 + (y-6)**2 <= 10 or (x-11)**2 + (y-6)**2 <= 10))
            if inside: h.put(x, y, hp[3])
    h.put(4, 5, hp[5]); h.put(5, 5, hp[5]); h.put(4, 6, hp[4]); h.rect(6,12,4,1,hp[2])
    h.outline(OUTL); h.img.save(f'{OUT}/heart.png')
    he = Canvas(16, 16)
    for y in range(3, 14):
        for x in range(1, 15):
            inside = (y >= 7 and abs(x-8) <= (14-y)*1.15) or (y < 7 and ((x-5)**2 + (y-6)**2 <= 10 or (x-11)**2 + (y-6)**2 <= 10))
            if inside: he.put(x, y, (40, 30, 40, 200))
    he.outline((20,14,24,255)); he.img.save(f'{OUT}/heart_empty.png')
    cur = Canvas(18, 18); cur.rect(0,0,18,1,(255,255,255,255)); cur.rect(0,17,18,1,(255,255,255,255)); cur.rect(0,0,1,18,(255,255,255,255)); cur.rect(17,0,1,18,(255,255,255,255))
    for (x,y) in ((0,0),(17,0),(0,17),(17,17)): cur.put(x,y,(255,255,255,255))
    cur.rect(4,0,10,1,CLEAR); cur.rect(4,17,10,1,CLEAR); cur.rect(0,4,1,10,CLEAR); cur.rect(17,4,1,10,CLEAR)
    cur.img.save(f'{OUT}/cursor.png')
    # particles / glow
    glow = Canvas(64, 64)
    for y in range(64):
        for x in range(64):
            d = math.hypot(x-31.5, y-31.5)/32
            a = max(0, 1-d)**2
            glow.put(x, y, (255, 255, 255, int(a*255)))
    glow.img.save(f'{OUT}/glow.png')
    px = Canvas(2,2); px.rect(0,0,2,2,(255,255,255,255)); px.img.save(f'{OUT}/pixel.png')

def build_jar():
    # 3 stages: jar(24x32), lantern(28x36), greenhouse pack(36x40) -> one sheet 36 wide, 3 cells of 40 tall
    sheet = Canvas(36*3, 40)
    glass = (200, 235, 255, 110); rim = (190, 220, 240, 230); cork = PAL['wood']
    for i, (w, h) in enumerate(((22, 28), (26, 32), (34, 38))):
        c = Canvas(36, 40); x0 = (36 - w)//2; y0 = 40 - h
        for y in range(y0, 40):
            for x in range(x0, x0 + w):
                edge = x == x0 or x == x0 + w - 1 or y == 39
                c.put(x, y, rim if edge else glass)
        c.rect(x0 + 2, y0 + 2, 2, h - 6, (255,255,255,170))
        c.rect(x0 + 4, y0 - 4, w - 8, 5, cork[3]); c.rect(x0 + 4, y0 - 4, w - 8, 1, cork[4]); c.rect(x0 + 3, y0, w - 6, 1, rim)
        if i >= 1:
            c.rect(x0 + w//2 - 1, y0 - 10, 2, 6, (120,120,130,255)); c.rect(x0 + w//2 - 4, y0 - 11, 8, 2, (150,150,160,255))
        if i == 2:
            c.rect(x0 - 2, y0 + 4, 2, h - 10, (110, 80, 50, 255)); c.rect(x0 + w, y0 + 4, 2, h - 10, (110, 80, 50, 255))
        c.outline(OUTL)
        sheet.paste(c, i*36, 0)
    sheet.img.save(f'{OUT}/jar.png')
    bug = Canvas(8, 4)
    for f in range(2):
        bug.rect(f*4 + 1, 1, 2, 2, (255,255,255,255)); bug.put(f*4, 1 if f else 2, (255,255,255,160)); bug.put(f*4 + 3, 2 if f else 1, (255,255,255,160))
    bug.img.save(f'{OUT}/bug.png')
    big = Canvas(96, 48)
    for f in range(2):
        c = Canvas(48, 48); col = (110, 112, 135, 255) if f == 0 else (255, 242, 210, 255)
        for y in range(48):
            for x in range(48):
                d = math.hypot(x - 23.5, y - 23.5)
                if d <= 18: c.put(x, y, col)
                elif d <= 21 and f: c.put(x, y, (255, 230, 150, 120))
        c.rect(14, 12, 8, 5, (255,255,255,255) if f else (170,170,190,255)); c.rect(12, 14, 3, 3, (255,255,255,200) if f else (150,150,170,255))
        if f == 0:
            for (x, y, l) in ((18, 26, 9), (26, 20, 7), (22, 31, 6)): c.line(x, y, x + l, y + 2, (70, 70, 90, 255))
        c.outline(OUTL); big.paste(c, f*48, 0)
    big.img.save(f'{OUT}/core.png')

build_tiles(); build_player(); build_jar(); build_enemies(); build_items(); build_background(); build_ui()
print('assets written to', OUT)
