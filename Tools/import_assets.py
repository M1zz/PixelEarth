#!/usr/bin/env python3
"""Converts the painted sheets in game_pixel_assets into the game's native sprite layouts.

The source PNGs are fully opaque with a checkerboard painted in, and are 4-10x larger than the game's
sheets, so they cannot be dropped in. This removes the checkerboard, downsamples and re-lays everything out.
Sprites the source art does not cover (cactus, coin, glow, pixel) stay from Tools/placeholder_assets.

Usage: import_assets.py [SOURCE_DIR] [OUT_DIR]     Requires Pillow.
"""
import os, sys
from collections import deque
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/Downloads/game_pixel_assets')
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, '../Sources/PixelEarth/Resources')
OLD = os.path.join(HERE, 'placeholder_assets')
T = 16
CLEAR = (0, 0, 0, 0)

def load(n): return Image.open(os.path.join(SRC, n + '.png')).convert('RGBA')
def old(n): return Image.open(os.path.join(OLD, n + '.png')).convert('RGBA')
def save(im, n): im.save(os.path.join(OUT, n + '.png'))
def lum(p): return (p[0] * 299 + p[1] * 587 + p[2] * 114) // 1000
def neutral(p, tol=16): return max(p[:3]) - min(p[:3]) <= tol

# ---------------------------------------------------------------- background removal
def palette(im):
    """The two checkerboard colours: the commonest non-black colours on the image border."""
    W, H = im.size; px = im.load(); bins = {}
    pts = [(x, y) for x in range(W) for y in (0, 1, H - 2, H - 1)] + [(x, y) for y in range(H) for x in (0, 1, W - 2, W - 1)]
    for x, y in pts:
        p = px[x, y]
        if lum(p) < 18: continue
        bins.setdefault((p[0] // 12, p[1] // 12, p[2] // 12), []).append(p)
    top = sorted(bins.values(), key=len, reverse=True)
    out = []
    for g in top:
        c = tuple(sum(v[i] for v in g) // len(g) for i in range(3))
        if all(sum(abs(c[i] - o[i]) for i in range(3)) > 30 for o in out): out.append(c)
        if len(out) == 2: break
    return out

def band(im):
    """Luminance range of a grey checkerboard, sampled from the image border; None if the checker is tinted."""
    W, H = im.size; px = im.load()
    pts = [px[x, y] for x in range(W) for y in (0, H - 1)] + [px[x, y] for y in range(H) for x in (0, W - 1)]
    pts = [p for p in pts if lum(p) >= 18]
    if not pts: return (112, 215)
    chroma = sorted(max(p[:3]) - min(p[:3]) for p in pts)
    if chroma[len(chroma) // 2] > 14: return None
    ls = sorted(lum(p) for p in pts if neutral(p))
    return (ls[len(ls) // 20] - 12, ls[-1 - len(ls) // 20] + 12)

def key(im, b=None, holes=0, tol=26, pal=None):
    """Clears checkerboard reachable from the border. holes>0 also clears enclosed bg regions of at least that many pixels."""
    im = im.copy(); W, H = im.size; px = im.load()
    b = b or (None if pal else band(im)); pal = pal or (None if b else palette(im))
    if b:
        def bg(p): return neutral(p) and b[0] <= lum(p) <= b[1]
    else:
        def bg(p): return any(abs(p[0] - c[0]) + abs(p[1] - c[1]) + abs(p[2] - c[2]) <= tol for c in pal)
    isbg = [[bg(px[x, y]) for x in range(W)] for y in range(H)]
    seen = [[False] * W for _ in range(H)]
    def flood(start):
        q = deque(start); out = []
        for x, y in start: seen[y][x] = True
        while q:
            x, y = q.popleft(); out.append((x, y))
            for a, c in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= a < W and 0 <= c < H and isbg[c][a] and not seen[c][a]:
                    seen[c][a] = True; q.append((a, c))
        return out
    edge = [(x, y) for x in range(W) for y in (0, H - 1) if isbg[y][x]] + [(x, y) for y in range(H) for x in (0, W - 1) if isbg[y][x]]
    for x, y in flood(list(dict.fromkeys(edge))): px[x, y] = CLEAR
    if holes:
        for y in range(H):
            for x in range(W):
                if isbg[y][x] and not seen[y][x]:
                    r = flood([(x, y)])
                    if len(r) >= holes:
                        for a, c in r: px[a, c] = CLEAR
    return im

def crisp(im, cut=110):
    """Hard alpha edge so downsampled sprites stay pixel art."""
    a = im.getchannel('A').point(lambda v: 255 if v >= cut else 0)
    im = im.copy(); im.putalpha(a); return im

def shrink(im, w, h): return im.resize((w, h), Image.BOX)

def components(im, min_px=150):
    """Bounding boxes of opaque blobs, grouped into rows, left to right."""
    W, H = im.size; a = im.getchannel('A').load(); seen = bytearray(W * H); out = []
    for y in range(H):
        for x in range(W):
            if a[x, y] and not seen[y * W + x]:
                q = deque([(x, y)]); seen[y * W + x] = 1; n = 0; x0 = x1 = x; y0 = y1 = y
                while q:
                    u, v = q.popleft(); n += 1
                    x0 = min(x0, u); x1 = max(x1, u); y0 = min(y0, v); y1 = max(y1, v)
                    for s in (u - 1, u, u + 1):
                        for t in (v - 1, v, v + 1):
                            if 0 <= s < W and 0 <= t < H and a[s, t] and not seen[t * W + s]:
                                seen[t * W + s] = 1; q.append((s, t))
                if n >= min_px: out.append((x0, y0, x1 + 1, y1 + 1))
    out.sort(key=lambda b: b[1]); rows = []
    for b in out:
        for r in rows:
            if b[1] < r[0][3] and b[3] > r[0][1]: r.append(b); break
        else: rows.append([b])
    for r in rows: r.sort()
    return rows

def despeckle(im, min_px=40):
    """Drops small islands left over from the painted background."""
    im = im.copy(); W, H = im.size; a = im.getchannel('A').load(); px = im.load(); seen = bytearray(W * H)
    for y in range(H):
        for x in range(W):
            if a[x, y] and not seen[y * W + x]:
                q = deque([(x, y)]); seen[y * W + x] = 1; pts = []
                while q:
                    u, v = q.popleft(); pts.append((u, v))
                    for s in (u - 1, u, u + 1):
                        for t in (v - 1, v, v + 1):
                            if 0 <= s < W and 0 <= t < H and a[s, t] and not seen[t * W + s]:
                                seen[t * W + s] = 1; q.append((s, t))
                if len(pts) < min_px:
                    for p in pts: px[p] = CLEAR
    return im

def largest(im):
    """Keeps only the biggest blob, for bounding boxes that clip a diagonal neighbour."""
    W, H = im.size; a = im.getchannel('A').load(); seen = bytearray(W * H); best = []
    for y in range(H):
        for x in range(W):
            if a[x, y] and not seen[y * W + x]:
                q = deque([(x, y)]); seen[y * W + x] = 1; pts = []
                while q:
                    u, v = q.popleft(); pts.append((u, v))
                    for s in (u - 1, u, u + 1):
                        for t in (v - 1, v, v + 1):
                            if 0 <= s < W and 0 <= t < H and a[s, t] and not seen[t * W + s]:
                                seen[t * W + s] = 1; q.append((s, t))
                if len(pts) > len(best): best = pts
    o = Image.new('RGBA', im.size, CLEAR); ip = im.load(); op = o.load()
    for p in best: op[p] = ip[p]
    return o

def body(im):
    """Largest blob after cutting thin bridges, so background crumbs touching a figure do not inflate its bounds."""
    a = im.getchannel('A')
    m = Image.new('RGBA', im.size, CLEAR); m.putalpha(a.filter(ImageFilter.MinFilter(5)))
    grown = largest(m).getchannel('A').filter(ImageFilter.MaxFilter(9))
    o = im.copy(); o.putalpha(Image.composite(a, Image.new('L', im.size, 0), grown)); return o

def fit(sprite, w, h, scale=None, cut=110):
    """Scales a keyed sprite into a w*h canvas, bottom centre, preserving aspect."""
    box = sprite.getbbox()
    if not box: return Image.new('RGBA', (w, h), CLEAR)
    s = sprite.crop(box); f = min(w / s.width, h / s.height)
    if scale: f = min(f, scale)
    nw, nh = max(1, round(s.width * f)), max(1, round(s.height * f))
    c = Image.new('RGBA', (w, h), CLEAR); c.alpha_composite(crisp(shrink(s, nw, nh), cut), ((w - nw) // 2, h - nh)); return c

# ---------------------------------------------------------------- tiles
CW, CH = 1376 / 20, 64
def cell(sheet, c, r, cs=1, rs=1, inset=0.0):
    x0, y0 = c * CW, r * CH; w, h = cs * CW, rs * CH
    return sheet.crop((round(x0 + w * inset), round(y0 + h * inset), round(x0 + w * (1 - inset)), round(y0 + h * (1 - inset))))
BGB = (112, 215)  # tiles.png checker, set explicitly because many crops touch neighbouring tiles
def inner(sheet, c, r, inset=0.14): return shrink(cell(sheet, c, r, inset=inset), T, T)
def sprite(sheet, c, r, cs=1, rs=1, w=T, h=T, inset=0.07, holes=0):
    return fit(despeckle(key(cell(sheet, c, r, cs, rs, inset), BGB, holes), 30), w, h)

def shade(p, f): return (min(255, int(p[0] * f)), min(255, int(p[1] * f)), min(255, int(p[2] * f)), p[3])
def edged(base, mask, soft=False):
    """Mask bits: 1 up, 2 right, 4 down, 8 left are exposed. Draws the dark rim and top light the source art bakes on every tile."""
    im = base.copy(); px = im.load(); U, R, D, L = mask & 1, mask & 2, mask & 4, mask & 8
    for i in range(T):
        for on, (x, y), (x2, y2), (x3, y3) in ((U, (i, 0), (i, 1), (i, 2)), (D, (i, T - 1), (i, T - 2), (i, T - 3)),
                                                (L, (0, i), (1, i), (2, i)), (R, (T - 1, i), (T - 2, i), (T - 3, i))):
            if not on: continue
            if soft:
                px[x, y] = shade(px[x, y], 0.5)
            else:
                px[x, y] = shade(px[x, y], 0.33); px[x2, y2] = shade(px[x2, y2], 1.18 if on == U else 0.78)
    cut = [(U and L, (0, 0)), (U and R, (T - 1, 0)), (D and L, (0, T - 1)), (D and R, (T - 1, T - 1))]
    for on, xy in cut:
        if on: px[xy] = CLEAR
    return im

def autotile(atlas, tid, v0, v1, soft=False, top=None, alpha=None):
    for mask in range(16):
        for v, b in enumerate((v0, v1)):
            src = (top[v] if top and mask & 1 else b)
            im = edged(src, mask, soft)
            if alpha:
                im.putalpha(im.getchannel('A').point(lambda a: min(a, alpha)))
            atlas.paste(im, ((mask * 2 + v) * T, tid * T))

def tint(im, rgb, amt):
    t = Image.new('RGBA', im.size, rgb + (255,)); o = Image.blend(im, t, amt); o.putalpha(im.getchannel('A')); return o

def liquid_body(sheet, c, r, alpha):
    """Lakes repeat one tile, so only the wave-free lower part of the source cell is used."""
    x0, y0 = c * CW, r * CH
    im = shrink(sheet.crop((round(x0 + 5), round(y0 + 30), round(x0 + CW - 5), round(y0 + CH - 6))), T, T)
    im.putalpha(alpha); return im

def build_tiles():
    S = load('tiles'); prev = old('tiles'); A = Image.new('RGBA', (prev.width, 46 * T), CLEAR)
    def two(c0, c1, r): return inner(S, c0, r), inner(S, c1, r)
    def put(tid, frames):
        for i, f in enumerate(frames): A.paste(f, (i * T, tid * T))
    autotile(A, 1, *two(1, 4, 0))
    def turf(c, base):
        # Only the green lip comes from the grass tile, so its darker soil cannot show as a band against plain dirt.
        o = base.copy(); o.paste(shrink(cell(S, c, 1, inset=0.05), T, T).crop((0, 0, T, 6)), (0, 0)); return o
    d0, d1 = two(1, 4, 0)
    autotile(A, 2, d0, d1, top=[turf(1, d0), turf(4, d1)])
    autotile(A, 3, *two(1, 4, 2))
    autotile(A, 4, inner(S, 1, 3, 0.24), inner(S, 4, 3, 0.24))  # past the log's end-cap, which would band every tile
    autotile(A, 5, *two(0, 2, 4), soft=True)
    autotile(A, 6, *two(7, 10, 4))
    autotile(A, 7, *two(11, 11, 4))
    autotile(A, 8, *two(9, 12, 4))
    autotile(A, 9, *two(0, 2, 5))
    autotile(A, 11, *two(0, 2, 6))
    autotile(A, 12, *two(3, 5, 6))
    autotile(A, 13, *two(13, 15, 6))
    autotile(A, 15, *two(1, 3, 8), alpha=165)
    autotile(A, 18, *two(3, 7, 5))
    autotile(A, 19, *two(5, 6, 5))
    autotile(A, 24, *two(14, 15, 4))
    autotile(A, 27, inner(S, 10, 3, 0.24), inner(S, 12, 3, 0.24))
    autotile(A, 28, *two(4, 6, 4), soft=True)
    autotile(A, 30, *two(16, 17, 6))
    def solid(c, r):
        o = Image.new('RGBA', (T, T), (34, 28, 40, 255)); o.alpha_composite(shrink(key(cell(S, c, r, inset=0.05), BGB), T, T)); return o
    autotile(A, 31, solid(0, 9), solid(3, 9))
    autotile(A, 32, *two(16, 18, 8))
    autotile(A, 36, *two(13, 13, 4))
    ghost = [tint(inner(S, c, 2), (150, 95, 215), 0.45) for c in (1, 4)]
    autotile(A, 37, *ghost)
    A.paste(prev.crop((0, 20 * T, 32 * T, 21 * T)), (0, 20 * T))      # cactus: not in the source art
    wa = prev.crop((0, 17 * T, T, 18 * T)).getchannel('A')
    water = [liquid_body(S, c, 6, wa) for c in (7, 8, 9, 8)]
    put(17, water)
    put(38, [tint(w, (120, 210, 255), 0.3) for w in water])
    put(22, [liquid_body(S, c, 6, Image.new('L', (T, T), 255)) for c in (10, 11, 12, 11)])
    tb = lambda c, r: sprite(S, c, r, inset=0.04)
    put(10, [tb(16, 4), tb(17, 4), tb(16, 5), tb(17, 5)])
    put(29, [tb(18, 4), tb(19, 4)])
    put(14, [sprite(S, 0, 7)])
    put(16, [sprite(S, 3, 7), sprite(S, 5, 7)])
    put(23, [sprite(S, 9, 7), sprite(S, 10, 7)])
    put(25, [sprite(S, c, 7) for c in (13, 14, 15, 13)])
    plat = [crisp(shrink(despeckle(key(cell(S, c, 7, inset=0.07), BGB), 30), T, T)) for c in (17, 16, 18, 19)]
    put(26, plat)
    # The mushrooms are painted on black rather than on the checkerboard.
    put(21, [fit(key(cell(S, c, 8, inset=0.07), (0, 42)), T, T) for c in (6, 7)])
    for tid, cols in ((33, (6, 10)), (34, (7, 11)), (35, (8, 12))): put(tid, [sprite(S, c, 9) for c in cols])
    for tid, rgb in ((41, (255, 70, 95)), (42, (90, 240, 130)), (43, (90, 160, 255))):
        put(tid, [tint(sprite(S, 13, 10), rgb, 0.42), tint(sprite(S, 13, 11), rgb, 0.5)])
    put(39, [sprite(S, c, 10, rs=2) for c in (0, 2, 3, 4)])
    put(40, [sprite(S, 10, 10), sprite(S, 12, 10)])
    put(44, [sprite(S, 17, 10), sprite(S, 19, 10)])
    # The throne is the empty altar with a crown: none when empty, red for a lord, gold for the player.
    seat = sprite(S, 0, 10, rs=2)
    crown = Image.open(os.path.join(OUT, 'items.png')).convert('RGBA').crop((16, 32, 32, 48)).resize((10, 10), Image.BOX)
    def throne(icon):
        o = seat.copy()
        if icon is not None: o.alpha_composite(icon, (3, 0))
        return o
    put(45, [throne(None), throne(tint(crown, (225, 50, 60), 0.6)), throne(crown)])
    save(A, 'tiles')
    W = Image.new('RGBA', old('walls').size, CLEAR)
    for i, (c, r) in enumerate(((1, 0), (1, 2), (0, 5), (16, 6))):
        for v in range(4):
            b = inner(S, c + (v % 2) * (2 if r != 6 else 1), r)
            W.paste(Image.eval(b.convert('RGB'), lambda p: int(p * 0.42)).convert('RGBA'), ((i * 4 + v) * T, 0))
    save(W, 'walls')

# ---------------------------------------------------------------- characters
# Character sheet: Tools/source_art/player_sprite_sheet.png. 4 rows (plain, iron, gold, diamond), each with
# 8 body poses and a loose arm. The source has 5 walk frames and the game plays 6, so one repeats.
HERO_POSES = (0, 1, 2, 3, 4, 5, 2, 6, 7)     # game pose -> source column: idle, walk x6, jump, fall
HERO_SCALE = 31 / 180                        # the standing figures are about 180 source pixels tall

def hero_cells():
    """Per row, the figures in source order, found by the blank columns between them. Only checker reachable
    from outside (or a large enclosed gap) is cleared, because the iron armour shares the checker's greys."""
    S = key(Image.open(os.path.join(HERE, 'source_art/player_sprite_sheet.png')).convert('RGBA'), b=(195, 255), holes=120)
    S = despeckle(S, 60); a = S.getchannel('A').load(); W, H = S.size
    def spans(hit, n, gap):
        out = []; start = None; last = None
        for i in range(n):
            if hit(i):
                if start is None: start = i
                elif i - last > gap: out.append((start, last + 1)); start = i
                last = i
        if start is not None: out.append((start, last + 1))
        return out
    rows = spans(lambda y: any(a[x, y] for x in range(W)), H, 12)
    cells = []
    for y0, y1 in rows:
        cols = spans(lambda x: any(a[x, y] for y in range(y0, y1)), W, 3)
        boxes = [S.crop((x0, y0, x1, y1)) for x0, x1 in cols]
        cells.append([b.crop(b.getbbox()) for b in boxes])
    assert [len(r) for r in cells] == [9] * 4, [len(r) for r in cells]
    return cells

def shrink_crisp(im, w, h):
    # Premultiplied, so the cleared background's colour cannot bleed into the sprite's edge.
    p = im.convert('RGBa').resize((w, h), Image.BOX).convert('RGBA')
    return crisp(p)

def build_player():
    cells = hero_cells(); out = Image.new('RGBA', (180, 128), CLEAR)
    for r in range(4):
        for pose, c in enumerate(HERO_POSES):
            f = cells[r][c]; w, h = max(1, round(f.width * HERO_SCALE)), min(32, round(f.height * HERO_SCALE))
            head = f.crop((0, 0, f.width, f.height * 2 // 5)).getbbox()
            cx = (head[0] + head[2]) / 2 * HERO_SCALE     # centred on the head, so walking does not jitter sideways
            x = max(0, min(20 - w, round(10 - cx)))
            out.alpha_composite(shrink_crisp(f, w, h), (c_x(pose, x), r * 32 + 32 - h))
    save(out, 'player')

def c_x(pose, x): return pose * 20 + x

def blobs(im, n, min_px=150, holes=0, b=None):
    k = despeckle(key(im, b, holes), 60); rows = components(k, min_px); flat = [x for r in rows for x in r]
    return [k.crop(x) for x in flat[:n]]

def strip(name, n, w, h, holes=0, save_as=None):
    fr = blobs(load(name), n, holes=holes)
    out = Image.new('RGBA', (w * n, h), CLEAR)
    scale = min(min(w / f.width, h / f.height) for f in fr)
    for i, f in enumerate(fr): out.paste(fit(f, w, h, scale), (i * w, 0))
    save(out, save_as or name)

def build_core():
    S = load('core'); H = S.height
    out = Image.new('RGBA', (96, 48), CLEAR)
    for i, xs in enumerate(((4, 340), (349, 684))): out.paste(fit(despeckle(key(S.crop((xs[0], 22, xs[1], H - 1)), pal=palette(S.crop((xs[0], 22, xs[1], H - 1)))), 400), 48, 48, cut=170), (i * 48, 0))
    save(out, 'core')

def glassify(im):
    """The painted glass shows the checkerboard through it; replace those mid-grey pixels with a real translucent tint."""
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            p = px[x, y]
            if p[3] and max(p[:3]) - min(p[:3]) < 38 and 55 <= lum(p) <= 175: px[x, y] = (170, 215, 222, 80)
    return im

def build_jar():
    S = load('jar'); H = S.height; xs = [(4, 296), (303, 594), (601, 982), (990, 1372)]
    out = Image.new('RGBA', (108, 40), CLEAR)
    # Stage 0 jar, 1 lantern, 2 greenhouse pack: the strapped frame is the one that reads as worn on the back.
    fr = [despeckle(key(S.crop((xs[j][0], 4, xs[j][1], H - 4))), 200) for j in (0, 1, 3)]
    scale = min(min(36 / f.crop(f.getbbox()).width, 40 / f.crop(f.getbbox()).height) for f in fr)
    for i, f in enumerate(fr):
        g = fit(f, 36, 40, scale)
        out.paste(glassify(g) if i < 2 else g, (i * 36, 0))
    save(out, 'jar')

def build_bug():
    """The bugs are pale specks on a dark checker, so they are picked out by brightness."""
    S = load('bug'); out = Image.new('RGBA', (8, 4), CLEAR)
    for i, xs in enumerate(((30, 110), (130, 240))):
        c = S.crop((xs[0], 32, xs[1], 80)); px = c.load()
        for y in range(c.height):
            for x in range(c.width):
                if lum(px[x, y]) < 125: px[x, y] = CLEAR
        out.paste(fit(c, 4, 4, cut=60), (i * 4, 0))
    save(out, 'bug')

def build_arm():
    cells = hero_cells(); out = Image.new('RGBA', (24, 12), CLEAR)
    for r in range(4):
        f = cells[r][8]; w, h = min(6, round(f.width * HERO_SCALE)), min(12, round(f.height * HERO_SCALE))
        out.alpha_composite(shrink_crisp(f, w, h), (r * 6 + (6 - w) // 2, 0))
    save(out, 'arm')

# ---------------------------------------------------------------- items
def build_items():
    Raw = load('items'); S = despeckle(key(Raw), 60)
    flat = [b for r in components(S, 300) for b in r]
    rows = [sorted(b for b in flat if lo <= (b[1] + b[3]) / 2 < hi) for lo, hi in ((0, 200), (200, 420), (420, 620), (620, 768))]
    rows[3] = [b for b in rows[3] if b[0] < 400]    # the generator's watermark sits bottom right
    print('item rows', [len(r) for r in rows])
    ids = [[100, 101, 102, 103, 104, 110, 111, 112, 113], [120, 121, 122, 123, 130, 131, 132, 133], [140, 141, 142], [150]]
    out = old('items')
    for r, line in zip(rows, ids):
        for b, iid in zip(r, line):
            i = iid - 100; x, y = (i % 16) * 16, (i // 16) * 16
            out.paste(Image.new('RGBA', (16, 16), CLEAR), (x, y)); sp = largest(S.crop(b))
            if iid in (131, 132): sp = largest(key(Raw.crop(b), band(Raw), holes=12))
            out.paste(fit(sp, 16, 16), (x, y))
    save(out, 'items')

# ---------------------------------------------------------------- backgrounds
def build_mountain(name, target_mean):
    S = key(load(name)); box = S.getbbox(); S = S.crop((0, box[1], S.width, box[3]))
    im = crisp(S.resize((512, 130), Image.BOX))
    px = im.load()
    def top(x):
        for y in range(130):
            if px[x, y][3]: return y
        return 129
    # Warp the last columns so the strip wraps without a step where sheets meet.
    delta = top(0) - top(511); N = 48; o = Image.new('RGBA', (512, 160), CLEAR); q = o.load()
    for x in range(512):
        d = round(delta * (x - (512 - N)) / N) if x >= 512 - N else 0
        for y in range(160):
            sy = min(129, max(0, y - 30 - d))
            q[x, y] = px[x, sy] if (y - 30 - d) >= 0 else CLEAR
    # The scene multiplies this sheet by the sky colour, so match the old sheet's brightness.
    vals = [lum(q[x, y]) for x in range(512) for y in range(160) if q[x, y][3]]
    f = target_mean / (sum(vals) / len(vals))
    for x in range(512):
        for y in range(160):
            if q[x, y][3]:
                p = shade(q[x, y], f); l = lum(p)
                # Snow is capped: multiplied by the sky tint, white would read as holes in the peaks.
                q[x, y] = shade(p, 165 / l) if l > 165 else p
    # The painted outline breaks up when squeezed, leaving flecks above the peaks, so the dark rim is peeled off.
    for _ in range(2):
        rim = [(x, y) for x in range(512) for y in range(160) if q[x, y][3] and lum(q[x, y]) < 40 and
               any(not (0 <= a < 512 and 0 <= b < 160) or not q[a, b][3] for a, b in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)) if b < 160)]
        for p in rim: q[p] = CLEAR
    save(o, name)

def mean_lum(im):
    p = im.load(); v = [lum(p[x, y]) for x in range(im.width) for y in range(im.height) if p[x, y][3]]
    return sum(v) / len(v)

def build_clouds():
    k = despeckle(key(load('clouds')), 60); fr = [x for r in components(k, 500) for x in r][:3]
    out = Image.new('RGBA', (192, 32), CLEAR)
    for i, b in enumerate(fr): out.paste(fit(k.crop(b), 64, 32, cut=90), (i * 64, 0))
    save(out, 'clouds')

def build_stars():
    # Star dots only come from the star band, which also leaves out the generator's watermark below it.
    S = load('stars'); px = S.load(); out = Image.new('RGBA', (256, 128), CLEAR); q = out.load(); band_h = 150
    for y in range(band_h):
        for x in range(S.width):
            p = px[x, y]; l = lum(p)
            if l > 125:
                u = x * 256 // S.width; v = y * 64 // band_h
                for vv, uu in ((v, u), (v + 64, (u + 97) % 256)):
                    if l > (q[uu, vv][3] or 0): q[uu, vv] = (min(255, p[0] + 30), min(255, p[1] + 30), min(255, p[2] + 30), min(255, l))
    save(out, 'stars')

# ---------------------------------------------------------------- UI
def ui(name, w, h, holes=0):
    k = despeckle(key(load(name), holes=holes)); b = k.getbbox(); return shrink(k.crop(b), w, h)
def build_ui():
    for n, w, h in (('slot', 40, 40), ('slot_sel', 40, 40), ('panel', 24, 24)):
        save(crisp(ui(n, w, h)), n)
    for n in ('heart', 'heart_empty'): save(fit(despeckle(key(load(n))), 16, 16), n)
    save(fit(key(load('cursor'), holes=40), 18, 18), 'cursor')

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    m0, m1 = mean_lum(old('mountains0')), mean_lum(old('mountains1'))
    build_items(); build_tiles(); build_player(); build_arm()
    strip('slimes', 6, 24, 16)
    strip('zombie', 4, 20, 28, holes=30)
    strip('bat', 2, 24, 14)
    strip('king', 2, 72, 66)
    build_core(); build_jar(); build_bug()
    build_mountain('mountains0', m0); build_mountain('mountains1', m1)
    build_clouds(); build_stars(); build_ui()
    # The lords, the light-starved, the light shard and the light gauge are the game's own drawings, not the source sheets.
    sys.path.insert(0, HERE); import gen_original_art; gen_original_art.OUT = OUT; gen_original_art.main()
    # The second bundle (Tools/source_art/bundle) replaces the keeper, the light-starved and the junction drawn above.
    import import_bundle; import_bundle.OUT = OUT; import_bundle.main()
    # Nael (Tools/source_art/nael) replaces the Earth-like sky, horizon and small creatures.
    import import_nael; import_nael.OUT = OUT; import_nael.main()
    print('wrote', OUT)
