#!/usr/bin/env python3
"""Draws the game's own sprites, the ones that replace genre-familiar art:
the throne keeper (floor lords), the light-starved (night wanderers), the light shard icon and the light vessel gauge.

Runs after import_assets.py (which it is called from) and overwrites only these files / cells.
Usage: gen_original_art.py [OUT_DIR]     Requires Pillow.
"""
import os, sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '../Sources/PixelEarth/Resources')
CLEAR = (0, 0, 0, 0)
INK = (18, 16, 24, 255)

def outline(im, color=INK):
    """1px dark outline around every opaque pixel, drawn into transparent neighbours."""
    W, H = im.size; src = im.load(); out = im.copy(); px = out.load()
    for y in range(H):
        for x in range(W):
            if src[x, y][3]: continue
            if any(0 <= x + dx < W and 0 <= y + dy < H and src[x + dx, y + dy][3] and src[x + dx, y + dy] != color
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = color
    return out

# ------------------------------------------------------------------ throne keeper (72x66, 2 frames)
CLOAK, CLOAK_HI, CLOAK_LO = (58, 56, 68, 255), (84, 82, 96, 255), (40, 38, 48, 255)
TRIM, TRIM_HI = (176, 172, 184, 255), (222, 218, 228, 255)   # pale: takes the floor's tint
MASK, MASK_LO = (226, 220, 204, 255), (176, 168, 150, 255)
GLOW, GLOW_HALO = (255, 255, 255, 255), (236, 236, 240, 255)
STAFF = (96, 78, 60, 255)

def keeper(air):
    im = Image.new('RGBA', (72, 66), CLEAR); d = ImageDraw.Draw(im)
    top, foot = (6, 65) if not air else (2, 60)
    flare = 6 if air else 0
    # cloak: a wide bell, folds as vertical lighter lines
    d.polygon([(22, top + 22), (50, top + 22), (62 + flare, foot), (10 - flare, foot)], fill=CLOAK)
    for x0, x1 in ((24, 18), (31, 28), (41, 44), (48, 54)):
        d.line([(x0, top + 26), (x1 - (flare if x1 < 36 else -flare) // 2, foot - 1)], fill=CLOAK_HI)
    d.line([(10 - flare, foot), (62 + flare, foot)], fill=CLOAK_LO, width=2)
    # mantle with pale trim
    d.polygon([(16, top + 26), (36, top + 18), (56, top + 26), (52, top + 32), (36, top + 27), (20, top + 32)], fill=TRIM)
    d.line([(18, top + 28), (36, top + 21), (54, top + 28)], fill=TRIM_HI)
    # hood and mask
    d.ellipse([24, top, 48, top + 24], fill=CLOAK_LO)
    d.ellipse([27, top + 4, 45, top + 22], fill=CLOAK)
    d.ellipse([29, top + 7, 43, top + 21], fill=MASK)
    d.rectangle([31, top + 12, 34, top + 13], fill=INK); d.rectangle([38, top + 12, 41, top + 13], fill=INK)
    d.line([(36, top + 7), (36, top + 11)], fill=MASK_LO); d.line([(36, top + 15), (35, top + 20)], fill=MASK_LO)
    # the light it guards, held at the chest
    cx, cy = 36, top + 36
    d.polygon([(cx, cy - 6), (cx + 5, cy), (cx, cy + 6), (cx - 5, cy)], fill=GLOW_HALO)
    d.polygon([(cx, cy - 4), (cx + 3, cy), (cx, cy + 4), (cx - 3, cy)], fill=GLOW)
    # arms around it
    d.polygon([(22, top + 30), (30, cy - 2), (31, cy + 4), (21, top + 40)], fill=CLOAK_HI)
    d.polygon([(50, top + 30), (42, cy - 2), (41, cy + 4), (51, top + 40)], fill=CLOAK_HI)
    # staff with an unlit cage lantern, raised when leaping
    sy = top - 2 if air else top + 6
    d.line([(60, sy + 6), (60, foot - (8 if air else 0))], fill=STAFF, width=2)
    d.rectangle([57, sy, 63, sy + 7], outline=TRIM); d.point([(60, sy + 3)], fill=GLOW)
    return outline(im)

# ------------------------------------------------------------------ light-starved (20x28, 4 frames)
SKIN, SKIN_LO = (150, 160, 172, 255), (112, 120, 134, 255)
RAG, RAG_LO = (62, 58, 66, 255), (44, 40, 48, 255)
EYE = (250, 236, 170, 255)
CAGE = (120, 110, 96, 255)

def starved(f):
    im = Image.new('RGBA', (20, 28), CLEAR); d = ImageDraw.Draw(im)
    step = [0, 1, 0, -1][f]
    # legs, thin and alternating
    d.line([(8, 21), (8 - step, 27)], fill=SKIN_LO, width=2)
    d.line([(12, 21), (12 + step, 27)], fill=SKIN_LO, width=2)
    # hunched body in rags
    d.polygon([(6, 10), (14, 9), (15, 22), (5, 22)], fill=RAG)
    d.line([(6, 16), (14, 15)], fill=RAG_LO); d.point([(7, 21), (10, 22), (13, 21)], fill=RAG_LO)
    # head pushed forward, hollow glowing eyes
    d.ellipse([8, 2, 17, 11], fill=SKIN)
    d.point([(13, 6), (15, 6)], fill=EYE); d.point([(14, 9)], fill=SKIN_LO)
    # long arm reaching ahead, an empty lantern cage swinging from the other
    d.line([(13, 12), (18, 14 + step)], fill=SKIN, width=1)
    d.line([(6, 12), (4, 17)], fill=SKIN, width=1)
    d.rectangle([2, 17 + abs(step), 5, 21 + abs(step)], outline=CAGE)
    return outline(im)

# ------------------------------------------------------------------ light shard icon (16x16)
def shard():
    im = Image.new('RGBA', (16, 16), CLEAR); d = ImageDraw.Draw(im)
    d.polygon([(9, 1), (13, 6), (8, 15), (4, 9)], fill=(255, 222, 140, 255))
    d.polygon([(9, 3), (11, 6), (8, 12), (6, 9)], fill=(255, 248, 220, 255))
    d.line([(9, 4), (8, 11)], fill=(255, 255, 255, 255))
    im = outline(im, (96, 70, 30, 255))
    px = im.load()
    for p in ((2, 3), (14, 11), (3, 13)): px[p] = (255, 250, 210, 255)
    return im

# ------------------------------------------------------------------ junction tile (row 46 of tiles.png, 2 frames)
def junction(f):
    """A tall slit in the stone with a cold draught moving through it: the place where the passage turns."""
    im = Image.new('RGBA', (16, 16), (52, 50, 60, 255)); d = ImageDraw.Draw(im)
    for y in range(0, 16, 4): d.line([(0, y), (15, y)], fill=(40, 38, 48, 255))
    d.rectangle([4, 0, 11, 15], fill=(8, 10, 16, 255))
    d.line([(3, 0), (3, 15)], fill=(120, 120, 134, 255)); d.line([(12, 0), (12, 15)], fill=(84, 84, 98, 255))
    for i, y in enumerate(range(2 + f * 2, 16, 5)):
        d.line([(5 + (i + f) % 3, y), (8 + (i + f) % 3, y)], fill=(120, 170, 220, 200))
    return im

# ------------------------------------------------------------------ light vessel gauge (stretchable 24x12 frame)
def vessel():
    im = Image.new('RGBA', (24, 12), CLEAR); d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, 23, 11], radius=5, outline=(20, 18, 26, 255))
    d.rounded_rectangle([1, 1, 22, 10], radius=4, outline=(150, 170, 186, 255))
    d.line([(5, 2), (18, 2)], fill=(236, 244, 250, 200))      # glass highlight
    return im

def main():
    k = Image.new('RGBA', (144, 66), CLEAR); k.paste(keeper(False), (0, 0)); k.paste(keeper(True), (72, 0))
    k.save(os.path.join(OUT, 'king.png'))
    z = Image.new('RGBA', (80, 28), CLEAR)
    for f in range(4): z.paste(starved(f), (f * 20, 0))
    z.save(os.path.join(OUT, 'zombie.png'))
    items = Image.open(os.path.join(OUT, 'items.png')).convert('RGBA')
    i = 150 - 100   # Item.lightShard
    items.paste(Image.new('RGBA', (16, 16), CLEAR), ((i % 16) * 16, (i // 16) * 16)); items.alpha_composite(shard(), ((i % 16) * 16, (i // 16) * 16))
    items.save(os.path.join(OUT, 'items.png'))
    vessel().save(os.path.join(OUT, 'vessel.png'))
    tiles = Image.open(os.path.join(OUT, 'tiles.png')).convert('RGBA')
    if tiles.height < 47 * 16:
        grown = Image.new('RGBA', (tiles.width, 47 * 16), CLEAR); grown.paste(tiles, (0, 0)); tiles = grown
    for f in range(2): tiles.paste(junction(f), (f * 16, 46 * 16))
    tiles.save(os.path.join(OUT, 'tiles.png'))
    print('wrote original art to', OUT)

if __name__ == '__main__':
    main()
