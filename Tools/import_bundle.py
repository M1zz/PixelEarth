#!/usr/bin/env python3
"""Imports the second art bundle (Tools/source_art/bundle) into the game's sheets.

The big sheets again have the checkerboard painted in, and the keeper's pale mantle shares the checker's greys,
so enclosed background is cleared only where it really is the two-tone checker pattern.
Two files arrived with swapped names: keeper.png holds the passage decor, passage_tiles.png holds the keeper.
The keeper's last frame (a back view with the generator's mark) and the app icon's corner mark are not used as drawn.

Usage: import_bundle.py [OUT_DIR]     Requires Pillow. Runs after import_assets.py and gen_original_art.py.
"""
import os, sys
from collections import deque
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import import_assets as ia

SRC = os.path.join(HERE, 'source_art/bundle')
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '../Sources/PixelEarth/Resources')
CLEAR = (0, 0, 0, 0)

def load(n): return Image.open(os.path.join(SRC, n + '.png')).convert('RGBA')

def unchecker(im, tol=14, min_hole=150):
    """Clears the checkerboard reachable from the border, then any enclosed region made of both checker tones."""
    pal = ia.palette(im); W, H = im.size; px = im.load()
    lums = sorted(ia.lum(c + (255,)) for c in pal); mid = sum(lums) / 2
    def tone(p):
        # The checker is grey: anything tinted (the cream mantle, blue skin) is drawing, whatever its brightness.
        if max(p[:3]) - min(p[:3]) > 10: return -1
        l = ia.lum(p)
        if lums[0] - tol <= l <= lums[-1] + tol: return 0 if l < mid else 1
        return -1
    t = [[tone(px[x, y]) for x in range(W)] for y in range(H)]
    seen = [[False] * W for _ in range(H)]
    def flood(sx, sy):
        q = deque([(sx, sy)]); seen[sy][sx] = True; out = []
        while q:
            x, y = q.popleft(); out.append((x, y))
            for a, b in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= a < W and 0 <= b < H and not seen[b][a] and t[b][a] >= 0:
                    seen[b][a] = True; q.append((a, b))
        return out
    im = im.copy(); px = im.load()
    for y in range(H):
        for x in range(W):
            if t[y][x] < 0 or seen[y][x]: continue
            region = flood(x, y)
            border = any(a in (0, W - 1) or b in (0, H - 1) for a, b in region)
            if not border:
                if len(region) < min_hole: continue
                counts = [0, 0]
                for a, b in region: counts[t[b][a]] += 1
                if min(counts) < len(region) * 0.2: continue      # one flat grey: part of the drawing
            for p in region: px[p] = CLEAR
    return ia.despeckle(im, 80)

def cut_columns(im, n):
    """Splits a row of figures at the emptiest column near each even boundary."""
    a = im.getchannel('A').load(); W, H = im.size
    col = [sum(1 for y in range(0, H, 2) if a[x, y]) for x in range(W)]
    cuts = [0] + [min(range(b - W // (n * 4), b + W // (n * 4)), key=lambda x: col[x]) for b in (W * i // n for i in range(1, n))] + [W]
    return [im.crop((cuts[i], 0, cuts[i + 1], H)) for i in range(n)]

def shrink(f, scale):
    w, h = max(1, round(f.width * scale)), max(1, round(f.height * scale))
    return ia.crisp(f.convert('RGBa').resize((w, h), Image.BOX).convert('RGBA'))

def frames_to_strip(frames, w, h, scale, name):
    out = Image.new('RGBA', (w * len(frames), h), CLEAR)
    for i, f in enumerate(frames):
        g = shrink(f.crop(f.getbbox()), scale)
        g = g.crop((max(0, (g.width - w) // 2), max(0, g.height - h), max(0, (g.width - w) // 2) + min(w, g.width), g.height))
        out.alpha_composite(g, (i * w + (w - g.width) // 2, h - g.height))
    out.save(os.path.join(OUT, name + '.png'))

def build_keeper():
    S = unchecker(load('passage_tiles')); H = S.height
    rows = [S.crop((0, 0, S.width, 456)), S.crop((0, 456, S.width, H))]
    cells = cut_columns(rows[0], 4) + cut_columns(rows[1], 4)
    # Idle frames with the staff; row 0 col 3 has none and the last one is a back view.
    use = [cells[i] for i in (0, 1, 2, 4, 5)]
    tallest = max(c.getbbox()[3] - c.getbbox()[1] for c in use)
    widest = max(c.getbbox()[2] - c.getbbox()[0] for c in use)
    frames_to_strip(use, 72, 66, min(66 / tallest, 72 / widest), 'king')

def build_starved():
    S = unchecker(load('starved'))
    cells = cut_columns(S, 6)
    tallest = max(c.getbbox()[3] - c.getbbox()[1] for c in cells[:4])
    frames_to_strip(cells, 26, 28, 28 / tallest, 'zombie')

def build_decor():
    """Passage decals, from the sheet named keeper.png: 5 columns x 2 rows of painted tiles."""
    S = load('keeper'); W, H = S.size; cw, ch = W / 5, H / 2
    def cell(c, r, inset=10): return S.crop((round(c * cw) + inset, round(r * ch) + inset, round((c + 1) * cw) - inset, round((r + 1) * ch) - inset))
    names_a, names_b = cell(0, 0), cell(1, 0)
    scratch = cell(2, 0)
    sky = cell(4, 0, 30)
    hc = cell(1, 1); herb = unchecker(hc.crop((0, 0, int(hc.width * 0.8), int(hc.height * 0.85)))); herb = herb.crop(herb.getbbox())
    out = Image.new('RGBA', (48 * 3 + 64 + 16, 48), CLEAR)
    out.paste(names_a.resize((48, 48), Image.BOX), (0, 0)); out.paste(names_b.resize((48, 48), Image.BOX), (48, 0))
    out.paste(scratch.resize((48, 48), Image.BOX), (96, 0)); out.paste(sky.resize((64, 48), Image.BOX), (144, 0))
    h = shrink(herb, 30 / herb.height); out.alpha_composite(h, (208 + (16 - h.width) // 2, 0))
    out.save(os.path.join(OUT, 'decor.png'))
    load('bed').save(os.path.join(OUT, 'bed.png'))

def build_turret():
    load('turret').save(os.path.join(OUT, 'turret.png'))

def build_junction():
    """16x32 x2 frames -> tile atlas row 46: columns 0-1 the lower halves, 2-3 the upper halves."""
    J = load('junction'); tiles = Image.open(os.path.join(OUT, 'tiles.png')).convert('RGBA')
    for f in range(2):
        tiles.paste(J.crop((f * 16, 16, f * 16 + 16, 32)), (f * 16, 46 * 16))
        tiles.paste(J.crop((f * 16, 0, f * 16 + 16, 16)), ((2 + f) * 16, 46 * 16))
    tiles.save(os.path.join(OUT, 'tiles.png'))

def build_icon():
    """The app icon with the generator's corner mark painted over from the rock beside it."""
    im = load('app_icon'); px = im.load()
    for y in range(860, 950):
        for x in range(855, 950):
            px[x, y] = px[x - 100, y]
    im.save(os.path.join(HERE, 'source_art/app_icon_clean.png'))
    return im

def main():
    build_keeper(); build_starved(); build_decor(); build_turret(); build_junction(); build_icon()
    print('bundle imported to', OUT)

if __name__ == '__main__':
    main()
