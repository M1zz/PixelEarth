#!/usr/bin/env python3
"""Dreamy ambient loop for the background. Run: python3 gen_music.py <outdir>

Seamless by construction: every note is written at (time mod length), and the reverb is a circular
convolution, so the tail of the last bar rings into the first. Deterministic (fixed seed).
Writes music.wav; make_music.sh-style conversion to CAF (IMA4) keeps it small and gapless.
"""
import sys, os, wave
import numpy as np

OUT = sys.argv[1] if len(sys.argv) > 1 else 'out'
os.makedirs(OUT, exist_ok=True)
SR = 44100
BAR = 8.0                       # seconds per chord
CHORDS = [                      # Dmaj9, Bm9, Gmaj7#11, A6add9 — open voicings, no resolution
    [50, 57, 66, 73, 76],
    [47, 54, 62, 69, 73],
    [43, 50, 59, 66, 73],
    [45, 52, 59, 64, 71],
]
PASSES = 2
L = BAR * len(CHORDS) * PASSES  # 64 s
N = int(SR * L)
rng = np.random.default_rng(7)
buf = np.zeros((2, N))

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)

def place(sig, start, pan):
    """Adds a mono note at `start` seconds, wrapping around the loop."""
    idx = (int(start * SR) + np.arange(len(sig))) % N
    np.add.at(buf[0], idx, sig * np.sqrt(1 - pan))
    np.add.at(buf[1], idx, sig * np.sqrt(pan))

def pad(m, dur, vol):
    t = np.arange(int(dur * SR)) / SR
    f = hz(m)
    s = sum(np.sin(2 * np.pi * f * (1 + d) * t + rng.uniform(0, 6.28)) for d in (-0.003, 0, 0.0035)) / 3
    s += 0.18 * np.sin(2 * np.pi * 2 * f * t)                  # a breath of overtone
    s *= 1 + 0.15 * np.sin(2 * np.pi * 0.11 * t + rng.uniform(0, 6.28))   # slow swell
    env = np.minimum(1, t / 3.5) * np.minimum(1, (dur - t) / 5.0)
    return s * np.clip(env, 0, 1) ** 1.5 * vol

def bell(m, vol):
    dur = 5.0
    t = np.arange(int(dur * SR)) / SR
    f = hz(m)
    s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 2.5)
    return s * np.exp(-t * 0.9) * np.minimum(1, t / 0.004) * vol

# pads: each chord swells in and overlaps the next
for p in range(PASSES):
    for c, chord in enumerate(CHORDS):
        start = (p * len(CHORDS) + c) * BAR
        for k, m in enumerate(chord):
            place(pad(m, BAR + 5, 0.11 if k else 0.15), start - 1.5, 0.3 + 0.4 * (k % 2))

# a low drone that completes whole cycles in the loop
t = np.arange(N) / SR
drone = np.sin(2 * np.pi * (round(hz(38) * L) / L) * t) * 0.06
buf += drone

# bells: sparse notes from the chord's own tones, high up, never on a grid
for p in range(PASSES):
    for c, chord in enumerate(CHORDS):
        start = (p * len(CHORDS) + c) * BAR
        tones = sorted(set(m % 12 for m in chord))
        for _ in range(rng.integers(2, 5)):
            m = 72 + int(rng.choice(tones)) + 12 * int(rng.integers(0, 2))
            place(bell(m, rng.uniform(0.05, 0.09)), start + rng.uniform(0, BAR), rng.uniform(0.15, 0.85))

# circular reverb: long, dark, slightly different per ear
def ir(seed):
    r = np.random.default_rng(seed)
    n = int(SR * 7)
    tt = np.arange(n) / SR
    x = r.standard_normal(n) * np.exp(-tt * 0.75)
    k = 40                                                      # darken with a moving average
    return np.convolve(x, np.ones(k) / k, 'same')

wet = np.zeros_like(buf)
for ch, seed in ((0, 1), (1, 2)):
    h = np.zeros(N); r = ir(seed); h[:len(r)] = r
    wet[ch] = np.real(np.fft.ifft(np.fft.fft(buf[ch]) * np.fft.fft(h)))
wet /= np.max(np.abs(wet)) + 1e-9
dry = buf / (np.max(np.abs(buf)) + 1e-9)
mix = 0.35 * dry + 0.65 * wet
mix *= 0.7 / np.max(np.abs(mix))

pcm = (np.clip(mix.T, -1, 1) * 32767).astype('<i2')
with wave.open(f'{OUT}/music.wav', 'w') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print(f'{OUT}/music.wav  {L:.0f}s')
