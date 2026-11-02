#!/usr/bin/env python3
"""Synthesized 8-bit style SFX as WAV files. Run: python3 gen_sounds.py <outdir>"""
import sys, os, math, random, struct, wave
OUT = sys.argv[1] if len(sys.argv) > 1 else 'out'
os.makedirs(OUT, exist_ok=True)
SR = 22050

def write(name, samples):
    with wave.open(f'{OUT}/{name}.wav', 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, s)) * 32000)) for s in samples))

def env(i, n, a=0.005, d=1.0):
    t = i / SR; total = n / SR
    at = min(1, t / a) if a > 0 else 1
    return at * max(0, 1 - (t / total)) ** d

def tone(f0, dur, kind='square', vol=0.5, slide=0, decay=1.0, vib=0):
    n = int(SR * dur); out = []; ph = 0
    for i in range(n):
        t = i / n
        f = f0 + slide * t + math.sin(i / SR * 40) * vib
        ph += f / SR
        x = ph % 1
        if kind == 'square': s = 1 if x < 0.5 else -1
        elif kind == 'tri': s = 4 * abs(x - 0.5) - 1
        elif kind == 'saw': s = 2 * x - 1
        else: s = math.sin(2 * math.pi * x)
        out.append(s * vol * env(i, n, d=decay))
    return out

def noise(dur, vol=0.5, lp=0.3, decay=1.5):
    n = int(SR * dur); out = []; last = 0; rnd = random.Random(1)
    for i in range(n):
        v = rnd.uniform(-1, 1); last += (v - last) * lp
        out.append(last * vol * env(i, n, d=decay))
    return out

def mix(*parts):
    n = max(len(p) for p in parts); out = [0.0] * n
    for p in parts:
        for i, s in enumerate(p): out[i] += s
    return out

def seq(parts, gap):
    out = []
    for p in parts: out += p + [0.0] * int(SR * gap)
    return out

write('dig', noise(0.07, 0.5, 0.25, 2))
write('brk', mix(noise(0.14, 0.7, 0.5, 1.5), tone(170, 0.12, 'tri', 0.4, -90)))
write('place', tone(520, 0.07, 'square', 0.25, -220))
write('jump', tone(280, 0.14, 'square', 0.22, 320))
write('hurt', mix(tone(170, 0.22, 'saw', 0.35, -110), noise(0.15, 0.25, 0.4)))
write('pick', seq([tone(880, 0.06, 'square', 0.22), tone(1320, 0.1, 'square', 0.22)], 0))
write('craft', seq([tone(f, 0.11, 'tri', 0.3) for f in (523, 659, 784, 1047)], 0))
write('swing', noise(0.1, 0.25, 0.9, 1.2))
write('bow', tone(900, 0.16, 'tri', 0.25, -620))
write('hit', mix(tone(240, 0.09, 'square', 0.3, -90), noise(0.06, 0.3, 0.6)))
write('die', seq([tone(f, 0.26, 'saw', 0.3) for f in (400, 300, 200, 120)], 0.02))
write('roar', mix(tone(80, 0.8, 'saw', 0.5, -40, 1.2, 6), noise(0.6, 0.4, 0.1)))
write('heal', seq([tone(f, 0.14, 'sine', 0.3) for f in (660, 880, 1100)], 0))
write('open', tone(440, 0.12, 'tri', 0.3, 220))
print('sounds written')
