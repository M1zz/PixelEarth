#!/usr/bin/env python3
"""Background music, one seamless loop per situation. Run: python3 gen_music.py <outdir>

  afternoon  the quiet afternoon before the sky goes out, and the sky regained   (dreamy pads and bells)
  lost       the surface after the disaster and floors 1-4                       (minor, sparse, wind)
  camp       floor 5, the camp in the Tomorrow Forest                            (warm kalimba over pads)
  deep       floors 6-9                                                          (the planet's heartbeat, glass shimmer)
  fight      a floor lord, or holding a throne                                   (drums and an ostinato)

Seamless by construction: every note is written at (time mod length), and the reverb is a circular
convolution, so the tail of the last bar rings into the first. Deterministic (fixed seeds).
Writes <name>.wav; convert each to CAF (IMA4) for the game, which keeps them small and gapless:
  afconvert -f caff -d ima4 <outdir>/<name>.wav Sources/PixelEarth/Resources/music_<name>.caf
"""
import sys, os, wave
import numpy as np

OUT = sys.argv[1] if len(sys.argv) > 1 else 'out'
SR = 44100

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)


class Track:
    def __init__(self, seconds, seed):
        self.L = seconds
        self.N = int(SR * seconds)
        self.buf = np.zeros((2, self.N))
        self.rng = np.random.default_rng(seed)

    def place(self, sig, start, pan=0.5):
        """Adds a mono sound at `start` seconds, wrapping around the loop."""
        idx = (int(start * SR) + np.arange(len(sig))) % self.N
        np.add.at(self.buf[0], idx, sig * np.sqrt(1 - pan))
        np.add.at(self.buf[1], idx, sig * np.sqrt(pan))

    # --- voices
    def pad(self, m, dur, vol, attack=3.5, release=5.0):
        t = np.arange(int(dur * SR)) / SR
        f = hz(m); r = self.rng
        s = sum(np.sin(2 * np.pi * f * (1 + d) * t + r.uniform(0, 6.28)) for d in (-0.003, 0, 0.0035)) / 3
        s += 0.18 * np.sin(2 * np.pi * 2 * f * t)                      # a breath of overtone
        s *= 1 + 0.15 * np.sin(2 * np.pi * 0.11 * t + r.uniform(0, 6.28))   # slow swell
        env = np.minimum(1, t / attack) * np.minimum(1, (dur - t) / release)
        return s * np.clip(env, 0, 1) ** 1.5 * vol

    def bell(self, m, vol, dur=5.0):
        t = np.arange(int(dur * SR)) / SR
        f = hz(m)
        s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 2.5)
        return s * np.exp(-t * 0.9) * np.minimum(1, t / 0.004) * vol

    def kalimba(self, m, vol):
        t = np.arange(int(1.6 * SR)) / SR
        f = hz(m)
        s = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * 18)
        return s * np.exp(-t * 3.2) * np.minimum(1, t / 0.002) * vol

    def thump(self, vol, f0=58):
        """One beat of a heart, or a soft kick: a sine that drops in pitch."""
        t = np.arange(int(0.45 * SR)) / SR
        f = f0 * (1 + 1.4 * np.exp(-t * 30))
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9) * vol

    def noise_hit(self, vol, decay, dark=8):
        n = int(0.35 * SR); t = np.arange(n) / SR
        x = self.rng.standard_normal(n)
        if dark > 1: x = np.convolve(x, np.ones(dark) / dark, 'same')
        return x * np.exp(-t * decay) * vol

    def bass(self, m, dur, vol):
        t = np.arange(int(dur * SR)) / SR
        f = hz(m)
        s = sum(np.sin(2 * np.pi * f * k * t) / k for k in range(1, 6))   # a soft saw
        env = np.minimum(1, t / 0.01) * np.exp(-t * 2.2)
        return s * env * vol

    def wind(self, vol):
        """Filtered noise that swells twice per loop; whole cycles so it loops."""
        x = self.rng.standard_normal(self.N)
        x = np.real(np.fft.ifft(np.fft.fft(x) * np.fft.fft(np.r_[np.ones(300) / 300, np.zeros(self.N - 300)])))
        t = np.arange(self.N) / SR
        swell = 0.5 + 0.5 * np.sin(2 * np.pi * 2 * t / self.L)
        w = x / (np.max(np.abs(x)) + 1e-9) * swell * vol
        self.buf[0] += w; self.buf[1] += np.roll(w, SR // 3)

    def drone(self, m, vol):
        t = np.arange(self.N) / SR
        self.buf += np.sin(2 * np.pi * (round(hz(m) * self.L) / self.L) * t) * vol   # whole cycles in the loop

    # --- finish
    def write(self, name, wet=0.65, room=7.0):
        def ir(seed):
            r = np.random.default_rng(seed)
            n = int(SR * room); tt = np.arange(n) / SR
            x = r.standard_normal(n) * np.exp(-tt * 0.75 * 7 / room)
            return np.convolve(x, np.ones(40) / 40, 'same')                       # darken
        rev = np.zeros_like(self.buf)
        for ch, seed in ((0, 1), (1, 2)):
            h = np.zeros(self.N); r = ir(seed)[:self.N]; h[:len(r)] = r
            rev[ch] = np.real(np.fft.ifft(np.fft.fft(self.buf[ch]) * np.fft.fft(h)))
        rev /= np.max(np.abs(rev)) + 1e-9
        dry = self.buf / (np.max(np.abs(self.buf)) + 1e-9)
        mix = (1 - wet) * dry + wet * rev
        mix *= 0.7 / np.max(np.abs(mix))
        pcm = (np.clip(mix.T, -1, 1) * 32767).astype('<i2')
        with wave.open(f'{OUT}/{name}.wav', 'w') as w:
            w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        print(f'{OUT}/{name}.wav  {self.L:.0f}s')


def afternoon():
    """The quiet afternoon: Dmaj9, Bm9, Gmaj7#11, A6add9, open voicings, no resolution."""
    BAR, PASSES = 8.0, 2
    CHORDS = [[50, 57, 66, 73, 76], [47, 54, 62, 69, 73], [43, 50, 59, 66, 73], [45, 52, 59, 64, 71]]
    tr = Track(BAR * len(CHORDS) * PASSES, 7); r = tr.rng
    for p in range(PASSES):
        for c, chord in enumerate(CHORDS):
            start = (p * len(CHORDS) + c) * BAR
            for k, m in enumerate(chord):
                tr.place(tr.pad(m, BAR + 5, 0.11 if k else 0.15), start - 1.5, 0.3 + 0.4 * (k % 2))
    tr.drone(38, 0.06)
    for p in range(PASSES):
        for c, chord in enumerate(CHORDS):
            start = (p * len(CHORDS) + c) * BAR
            tones = sorted(set(m % 12 for m in chord))
            for _ in range(r.integers(2, 5)):
                m = 72 + int(r.choice(tones)) + 12 * int(r.integers(0, 2))
                tr.place(tr.bell(m, r.uniform(0.05, 0.09)), start + r.uniform(0, BAR), r.uniform(0.15, 0.85))
    tr.write('afternoon')


def lost():
    """The sky has gone out: D minor, slower, the bells far apart and low, wind across the loop."""
    BAR = 10.0
    CHORDS = [[50, 57, 64, 65], [46, 53, 62, 69], [43, 50, 58, 65], [45, 52, 55, 62]]   # Dm(add9) Bbmaj7 Gm7 Asus
    tr = Track(BAR * len(CHORDS), 11); r = tr.rng
    for c, chord in enumerate(CHORDS):
        for k, m in enumerate(chord):
            tr.place(tr.pad(m, BAR + 6, 0.09 if k else 0.13, attack=5, release=7), c * BAR - 2, 0.3 + 0.4 * (k % 2))
    tr.drone(38, 0.09)
    tr.wind(0.05)
    for c, chord in enumerate(CHORDS):
        if c % 2: continue
        m = 62 + sorted(set(x % 12 for x in chord))[int(r.integers(0, 3))]
        tr.place(tr.bell(m, 0.06, dur=7), c * BAR + r.uniform(2, 7), r.uniform(0.2, 0.8))
    tr.write('lost', wet=0.75)


def camp():
    """Somewhere to stay: F major, a kalimba figure that comes round like a song you know."""
    BPM = 76; beat = 60 / BPM; BAR = 4 * beat
    CHORDS = [[53, 60, 64, 69], [50, 57, 60, 65], [46, 53, 57, 62], [48, 55, 60, 64]]   # Fmaj7 Dm7 Bbmaj7 C
    FIGURE = [0, 2, 1, 3, None, 2, 1, None]          # chord-tone indices per eighth; None rests
    PASSES = 2
    tr = Track(BAR * len(CHORDS) * PASSES, 23); r = tr.rng
    for p in range(PASSES):
        for c, chord in enumerate(CHORDS):
            start = (p * len(CHORDS) + c) * BAR
            for k, m in enumerate(chord):
                tr.place(tr.pad(m, BAR + 3, 0.07 if k else 0.1, attack=2, release=3), start - 0.8, 0.3 + 0.4 * (k % 2))
            tones = [m + 12 for m in chord[1:]] + [chord[1] + 24]
            for i, ti in enumerate(FIGURE):
                if ti is None or (p == 1 and i == 7): continue
                jitter = r.uniform(-0.012, 0.012)
                tr.place(tr.kalimba(tones[ti], 0.11 if i % 2 == 0 else 0.08), start + i * beat / 2 + jitter, 0.35 + 0.3 * (i % 3) / 2)
    tr.drone(41, 0.04)
    tr.write('camp', wet=0.45, room=4.0)


def deep():
    """Close to the heart: C# minor leaning phrygian, a slow heartbeat, glass ringing far above."""
    BEAT = 60 / 54
    BAR = 4 * BEAT
    CHORDS = [[49, 56, 63, 64], [50, 57, 62, 66], [49, 56, 61, 68], [47, 54, 61, 62]]   # C#m(add9) Dmaj7 C#m B(sus)
    PASSES = 2
    tr = Track(BAR * len(CHORDS) * PASSES, 31); r = tr.rng
    for p in range(PASSES):
        for c, chord in enumerate(CHORDS):
            start = (p * len(CHORDS) + c) * BAR
            for k, m in enumerate(chord):
                tr.place(tr.pad(m - 12 if k == 0 else m, BAR + 4, 0.08 if k else 0.12, attack=4, release=5), start - 1, 0.3 + 0.4 * (k % 2))
    n_beats = int(round(tr.L / BEAT))
    for b in range(n_beats):                       # lub-dub
        t0 = b * BEAT
        tr.place(tr.thump(0.5, 52), t0, 0.5); tr.place(tr.thump(0.32, 48), t0 + 0.22, 0.5)
    for _ in range(10):
        m = 85 + int(r.choice([0, 3, 7, 10, 14]))
        tr.place(tr.bell(m, r.uniform(0.025, 0.045), dur=6), r.uniform(0, tr.L), r.uniform(0.1, 0.9))
    tr.drone(37, 0.05)
    tr.write('deep', wet=0.6)


def fight():
    """A lord, or a throne to hold: A minor at 112, kick and snare, an ostinato that does not let go."""
    BPM = 112; beat = 60 / BPM; BAR = 4 * beat
    PROG = [(45, [57, 60, 64]), (41, [57, 60, 65]), (43, [55, 59, 62]), (40, [55, 59, 64])]   # Am F G Em
    OST = [0, 0, 12, 0, 10, 0, 7, 0]               # over the bar's root, in eighths
    PASSES = 4
    tr = Track(BAR * len(PROG) * PASSES, 41); r = tr.rng
    for p in range(PASSES):
        for c, (root, triad) in enumerate(PROG):
            start = (p * len(PROG) + c) * BAR
            for i, iv in enumerate(OST):
                tr.place(tr.bass(root - 12 + iv, beat / 2 * 0.95, 0.16), start + i * beat / 2, 0.5)
            for k, m in enumerate(triad):
                tr.place(tr.pad(m, BAR, 0.05, attack=0.05, release=0.6), start, 0.25 + 0.25 * k)
            for b in range(4):
                tb = start + b * beat
                if b % 2 == 0: tr.place(tr.thump(0.55, 55), tb, 0.5)
                else: tr.place(tr.noise_hit(0.22, 18, dark=3), tb, 0.5)
                tr.place(tr.noise_hit(0.05, 60, dark=1), tb + beat / 2, 0.7)
            if p % 2 == 1:                          # a high call answers every other pass
                tr.place(tr.bell(triad[2] + 12, 0.07, dur=2.5), start + 2 * beat, r.uniform(0.3, 0.7))
    tr.write('fight', wet=0.3, room=2.5)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for make in (afternoon, lost, camp, deep, fight):
        make()
