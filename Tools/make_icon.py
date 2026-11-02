#!/usr/bin/env python3
"""macOS app icon from the full-bleed art in Tools/icon_art.png.

Follows the macOS icon grid: a 824x824 rounded square (continuous corners) centred on a 1024 canvas,
with a soft drop shadow. The art is cropped at native scale, not resized, so the pixels stay crisp.
Run: python3 Tools/make_icon.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'App', 'Assets.xcassets', 'AppIcon.appiconset')
C, BODY = 1024, 824
M = (C - BODY) // 2

def squircle_mask(size, scale=4, n=5.0):
    """Superellipse |x|^n + |y|^n = 1 — the soft, continuous corner macOS icons use."""
    s = size * scale
    img = Image.new('L', (s, s), 0)
    pts = []
    import math
    for i in range(720):
        t = 2 * math.pi * i / 720
        c, si = math.cos(t), math.sin(t)
        x = abs(c) ** (2 / n) * (1 if c >= 0 else -1)
        y = abs(si) ** (2 / n) * (1 if si >= 0 else -1)
        pts.append(((x + 1) / 2 * (s - 1), (y + 1) / 2 * (s - 1)))
    ImageDraw.Draw(img).polygon(pts, fill=255)
    return img.resize((size, size), Image.LANCZOS)

art = Image.open(os.path.join(HERE, 'icon_art.png')).convert('RGBA')
off = (art.width - BODY) // 2
body = art.crop((off, off - 20, off + BODY, off - 20 + BODY))   # nudge up a little: the jar sits high
mask = squircle_mask(BODY)

# a faint light rim on the upper edge, like light catching glass
rim = Image.new('RGBA', (BODY, BODY), (0, 0, 0, 0))
inner = mask.filter(ImageFilter.MinFilter(5))
edge = Image.eval(Image.composite(Image.new('L', (BODY, BODY), 0), mask, inner), lambda v: v)
grad = Image.linear_gradient('L').resize((BODY, BODY)).transpose(Image.FLIP_TOP_BOTTOM)
edge = Image.composite(edge, Image.new('L', (BODY, BODY), 0), grad)
rim.putalpha(Image.eval(edge, lambda v: v * 50 // 255))
rim = Image.merge('RGBA', (*Image.new('RGB', (BODY, BODY), (255, 236, 200)).split(), rim.getchannel('A')))
body = Image.alpha_composite(body, rim)
body.putalpha(mask)

canvas = Image.new('RGBA', (C, C), (0, 0, 0, 0))
shadow = Image.new('RGBA', (C, C), (0, 0, 0, 0))
sh = Image.new('L', (C, C), 0); sh.paste(mask, (M, M + 12))
shadow.putalpha(sh.filter(ImageFilter.GaussianBlur(14)).point(lambda v: v * 0.45))
canvas = Image.alpha_composite(canvas, shadow)
canvas.alpha_composite(body, (M, M))

for pt in (16, 32, 128, 256, 512):
    for sc in (1, 2):
        px = pt * sc
        name = f'icon_{pt}x{pt}' + ('@2x' if sc == 2 else '') + '.png'
        canvas.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
print('icons written to', os.path.normpath(OUT))
