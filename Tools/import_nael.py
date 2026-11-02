#!/usr/bin/env python3
"""Nael bundle (Tools/source_art/nael): the planet's own people, sky, horizon and ground.

Usage: import_nael.py [OUT_DIR]     Runs last from import_assets.py. Needs Pillow.
- Sprites already match the game sizes, so they are copied as is.
- The ground keeps the autotile shapes in tiles.png and takes the colours of surface_tiles.png:
  violet soil, teal moss, bone-white trunks, teal leaves. A PNG text mark keeps it from being applied twice.
"""
import os, shutil, sys
from PIL import Image, PngImagePlugin

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'source_art', 'nael')
OUT = os.path.join(HERE, '..', 'Sources', 'PixelEarth', 'Resources')
T = 16

# source name -> game name
FILES = {'stars.png': 'stars.png', 'slimes.png': 'slimes.png', 'bat.png': 'bat.png',
         'horizon_distant.png': 'mountains0.png', 'horizon_near.png': 'mountains1.png',
         'player.png': 'player.png', 'arm.png': 'arm.png', 'zombie.png': 'zombie.png', 'grandma.png': 'grandma.png',
         **{f'lord{f}.png': f'lord{f}.png' for f in range(5, 10)}}

def hexc(h): return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))
# dark -> light, taken from surface_tiles.png
SOIL = [hexc(c) for c in ('#160d1c', '#26182e', '#372440', '#4a3352')]
MOSS = [hexc(c) for c in ('#145a50', '#28b4a0', '#50f0d7', '#b4fff0')]
TRUNK = [hexc(c) for c in ('#6e6a64', '#b4afa5', '#e1ded7', '#f5f3ee')]
LEAF = [hexc(c) for c in ('#10404a', '#1e6e7d', '#2da5b4', '#64ebd7')]
DIRT, GRASS, WOOD, LEAVES, PINE, SNOWLEAF = 1, 2, 4, 5, 27, 28

def lum(p): return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]
def greenish(p): return p[1] > p[0] + 12 and p[1] > p[2]

def recolor_row(img, row, ramp_for):
    """Map each pixel of one tile row onto a 4-step ramp by its brightness rank within the row."""
    box = (0, row * T, img.width, row * T + T)
    band = img.crop(box); px = band.load()
    ls = sorted(lum(px[x, y]) for y in range(T) for x in range(band.width) if px[x, y][3] > 0)
    if not ls: return
    q = [ls[int(len(ls) * k / 4)] for k in (1, 2, 3)]          # quartile cuts, so every step is used
    for y in range(T):
        for x in range(band.width):
            p = px[x, y]
            if p[3] == 0: continue
            ramp = ramp_for(p)
            step = sum(lum(p) > c for c in q)
            px[x, y] = ramp[step] + (p[3],)
    img.paste(band, box)

def ground(path):
    img = Image.open(path)
    if img.info.get('nael') == '1': print('nael: ground already recoloured'); return
    img = img.convert('RGBA')
    recolor_row(img, DIRT, lambda p: SOIL)
    recolor_row(img, GRASS, lambda p: MOSS if greenish(p) else SOIL)
    for r in (WOOD, PINE): recolor_row(img, r, lambda p: TRUNK)
    for r in (LEAVES, SNOWLEAF): recolor_row(img, r, lambda p: LEAF)
    meta = PngImagePlugin.PngInfo(); meta.add_text('nael', '1')
    img.save(path, pnginfo=meta)
    print('nael: ground recoloured')

def main():
    for src, dst in FILES.items():
        shutil.copyfile(os.path.join(SRC, src), os.path.join(OUT, dst))
        print('nael:', src, '->', dst)
    ground(os.path.join(OUT, 'tiles.png'))
    # the app icon is made from icon_art.png by make_icon.py
    shutil.copyfile(os.path.join(SRC, 'app_icon.png'), os.path.join(HERE, 'icon_art.png'))

if __name__ == '__main__':
    if len(sys.argv) > 1: OUT = sys.argv[1]
    main()
