#!/usr/bin/env python3
"""Offline renderer for Aurite Front's sound: the web version's WebAudio synth recipes,
rendered to WAV (effects) and OGG (two-layer march). Run: python3 tools/synth.py <project dir>"""
import sys, os, wave, subprocess
import numpy as np

SR = 32000
rng = np.random.default_rng(7)
NOISE = rng.uniform(-1, 1, SR * 4).astype(np.float32)


def biquad_mag(kind, f, q, freqs):
    """Magnitude response of an RBJ biquad (lowpass/highpass/bandpass) at freqs."""
    w0 = 2 * np.pi * f / SR
    w = 2 * np.pi * freqs / SR
    alpha = np.sin(w0) / (2 * q)
    c = np.cos(w0)
    if kind == 'lowpass':
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
    elif kind == 'highpass':
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
    else:
        b = [alpha, 0, -alpha]
    a = [1 + alpha, -2 * c, 1 - alpha]
    z = np.exp(-1j * w)
    H = (b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z)
    return np.abs(H)


def filt(sig, kind, f0, f1=None, q=None, dur=None):
    """Filter with an (exponentially) swept cutoff via overlap-add FFT chunks."""
    q = q or 0.707
    n = len(sig)
    N = 512
    hop = N // 2
    win = np.hanning(N).astype(np.float32)
    out = np.zeros(n + N, np.float32)
    padded = np.concatenate([sig, np.zeros(N, np.float32)])
    freqs = np.fft.rfftfreq(N, 1 / SR)
    dur = dur or n / SR
    for s in range(0, n, hop):
        t = (s + hop) / SR
        if f1 and f1 != f0:
            k = min(1.0, t / dur)
            f = f0 * (f1 / f0) ** k
        else:
            f = f0
        f = min(max(f, 20), SR / 2 - 100)
        seg = padded[s:s + N] * win
        spec = np.fft.rfft(seg) * biquad_mag(kind, f, q, freqs)
        out[s:s + N] += np.fft.irfft(spec, N).astype(np.float32)
    return out[:n]


def env_exp(n, vol, att, dur):
    """WebAudio-style: .0001 -> vol over att (exponential), then -> .0001 at dur."""
    t = np.arange(n) / SR
    e = np.empty(n, np.float32)
    a = t < att
    e[a] = 0.0001 * (vol / 0.0001) ** (t[a] / att)
    b = ~a
    k = np.clip((t[b] - att) / max(1e-4, dur - att), 0, 1)
    e[b] = vol * (0.0001 / vol) ** k
    e[t > dur] = 0
    return e


def nz(buf, t, dur, kind, f, vol, f2=None, q=None):
    n = int((dur + 0.05) * SR)
    off = rng.integers(0, len(NOISE) - n - 1)
    s = filt(NOISE[off:off + n].copy(), kind, f, f2, q, dur)
    s *= env_exp(n, vol, 0.004, dur)
    mix(buf, t, s)


def osc(kind, f1, f2, n, dur):
    t = np.arange(n) / SR
    if f2 != f1:
        k = np.clip(t / dur, 0, 1)
        f = f1 * (f2 / f1) ** k
    else:
        f = np.full(n, f1)
    ph = np.cumsum(f) / SR
    if kind == 'sine':
        return np.sin(2 * np.pi * ph)
    if kind == 'square':
        return np.sign(np.sin(2 * np.pi * ph))
    if kind == 'sawtooth':
        return 2 * (ph % 1) - 1
    if kind == 'triangle':
        return 2 * np.abs(2 * (ph % 1) - 1) - 1


def tn(buf, t, f1, f2, dur, kind, vol, att=0.004):
    n = int((dur + 0.05) * SR)
    s = osc(kind, f1, f2, n, dur).astype(np.float32) * env_exp(n, vol, att, dur)
    mix(buf, t, s)


def mix(buf, t, s):
    i = int(t * SR)
    if i >= len(buf):
        return
    m = min(len(s), len(buf) - i)
    buf[i:i + m] += s[:m]


def impulse(dur, decay):
    n = int(SR * dur)
    return (rng.uniform(-1, 1, n) * (1 - np.arange(n) / n) ** decay).astype(np.float32)


IMP = impulse(2.6, 3)


def reverb(dry, wet):
    if wet <= 0:
        return dry
    L = len(dry) + len(IMP)
    F = 1 << int(np.ceil(np.log2(L)))
    r = np.fft.irfft(np.fft.rfft(dry, F) * np.fft.rfft(IMP, F), F)[:L].astype(np.float32)
    r *= 0.32 * wet * 1.6 / max(1e-6, np.sqrt(np.sum(IMP ** 2)))
    out = np.concatenate([dry, np.zeros(len(IMP), np.float32)]) + r
    return out


def trim(s):
    a = np.abs(s)
    thr = a.max() * 0.002 if a.max() > 0 else 0
    idx = np.where(a > thr)[0]
    end = idx[-1] + 200 if len(idx) else len(s)
    s = s[:end]
    fade = min(len(s), int(0.02 * SR))
    s[-fade:] *= np.linspace(1, 0, fade)
    return s


def write_wav(path, s, sr=SR, stereo=False):
    s = np.clip(s, -1, 1)
    data = (s * 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(2 if stereo else 1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())


def sfx(name):
    b = np.zeros(SR * 4, np.float32)
    t = 0.005
    wet = 0.2
    if name == 'gun':
        wet = .12; nz(b, t, .05, 'bandpass', 2600, .22, None, 1.2); tn(b, t, 190, 90, .035, 'square', .05)
    elif name == 'snipe':
        wet = .55; nz(b, t, .035, 'highpass', 2800, .45); nz(b, t + .01, .3, 'bandpass', 900, .12, 300); tn(b, t, 900, 120, .06, 'square', .06)
    elif name == 'shell':
        wet = .3; nz(b, t, .28, 'lowpass', 1400, .45, 250); tn(b, t, 120, 42, .26, 'sine', .4)
    elif name == 'heavy':
        wet = .4; nz(b, t, .4, 'lowpass', 1100, .6, 160); tn(b, t, 90, 32, .38, 'sine', .55); nz(b, t + .04, .25, 'bandpass', 500, .15, 200)
    elif name == 'mortar':
        wet = .35; tn(b, t, 170, 55, .22, 'sine', .45); nz(b, t, .18, 'lowpass', 700, .3, 200); nz(b, t + .05, .5, 'bandpass', 1200, .04, 3000)
    elif name == 'rocket':
        wet = .25; nz(b, t, .4, 'bandpass', 500, .25, 2800, .8); tn(b, t, 260, 900, .3, 'sawtooth', .03)
    elif name == 'flak':
        wet = .3; nz(b, t, .09, 'lowpass', 1800, .3); nz(b, t + .1, .09, 'lowpass', 1600, .26); tn(b, t, 300, 120, .06, 'square', .04)
    elif name == 'flame':
        wet = .15; nz(b, t, .38, 'bandpass', 800, .2, 1500, .6); nz(b, t, .3, 'lowpass', 300, .15)
    elif name == 'arc':
        wet = .35; tn(b, t, 1900, 180, .2, 'sawtooth', .08); tn(b, t, 700, 3200, .12, 'square', .035); nz(b, t, .14, 'highpass', 4200, .12)
    elif name == 'small':
        wet = .2; nz(b, t, .22, 'lowpass', 800, .25, 200)
    elif name == 'boom':
        wet = .45; nz(b, t, .9, 'lowpass', 700, .6, 70); tn(b, t, 95, 28, .6, 'sine', .55); nz(b, t + .08, .6, 'highpass', 1800, .06)
    elif name == 'bigboom':
        wet = .7; nz(b, t, 1.8, 'lowpass', 900, .9, 40); tn(b, t, 70, 20, 1.4, 'sine', .8); nz(b, t + .12, 1.2, 'bandpass', 600, .2, 150); nz(b, t + .2, .9, 'highpass', 2400, .07)
    elif name == 'click':
        wet = 0; tn(b, t, 1400, 1000, .03, 'square', .04)
    elif name in ('ack', 'ack_ashen'):
        wet = .08; nz(b, t, .05, 'bandpass', 2400, .06, None, 3); f = 820 if name == 'ack_ashen' else 1180
        tn(b, t + .03, f, f, .05, 'square', .035); tn(b, t + .09, f * 1.33, f * 1.33, .06, 'square', .03)
    elif name == 'ready':
        wet = .3
        for i, f in enumerate([660, 880, 1320]):
            tn(b, t + i * .08, f, f, .14, 'triangle', .13)
    elif name == 'alert':
        wet = .25
        for k in range(2):
            tn(b, t + k * .36, 560, 560, .14, 'square', .06); tn(b, t + k * .36 + .17, 420, 420, .16, 'square', .06)
    elif name == 'place':
        wet = .25; tn(b, t, 200, 80, .22, 'square', .07); nz(b, t, .3, 'lowpass', 500, .25); nz(b, t + .12, .15, 'bandpass', 1500, .05)
    elif name == 'siren':
        wet = .4
        n = int(2.7 * SR); tt = np.arange(n) / SR
        f = np.empty(n)
        for i, x in enumerate(tt):
            k = x % .85
            f[i] = 380 + 500 * (k / .45) if k < .45 else 880 - 500 * ((k - .45) / .4)
        ph = np.cumsum(f) / SR
        s = (2 * (ph % 1) - 1).astype(np.float32)
        g = np.clip(tt / .1, 0, 1) * 0.07
        g[tt > 2.3] *= np.clip(1 - (tt[tt > 2.3] - 2.3) / .3, 0, 1)
        s = filt(s * g.astype(np.float32), 'lowpass', 1800)
        mix(b, t, s)
    b = trim(b)
    return trim(reverb(b, wet)) * 1.6


# ---------------- music ----------------
MSR = 32000
SIXT = 60 / 104 / 4
PROG = [[38, 50, 53, 57], [38, 50, 53, 57], [34, 46, 50, 53], [36, 48, 52, 55], [38, 50, 53, 57], [43, 55, 58, 62], [45, 57, 61, 64], [45, 57, 61, 64]]
FANF = [
    [[0, 62, 3], [3, 62, 1], [4, 69, 4], [8, 67, 3], [11, 65, 1], [12, 64, 4], [16, 62, 6], [22, 57, 2], [24, 62, 8]],
    [[0, 57, 3], [3, 57, 1], [4, 62, 3], [7, 62, 1], [8, 65, 4], [12, 64, 2], [14, 62, 2], [16, 61, 4], [20, 64, 4], [24, 69, 8]],
    [[0, 69, 2], [2, 67, 2], [4, 65, 2], [6, 64, 2], [8, 62, 6], [14, 61, 2], [16, 62, 3], [19, 64, 1], [20, 65, 4], [24, 62, 8]],
]
OST = [2, 0, 1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2, 0, 1, 0]
SNR = [3, 0, 1, 0, 2, 0, 1, 1, 3, 0, 1, 0, 2, 1, 1, 1]
mtof = lambda m: 440 * 2 ** ((m - 69) / 12)


class Bus:
    def __init__(self, n):
        self.L = np.zeros(n, np.float32); self.R = np.zeros(n, np.float32)
        self.wL = np.zeros(n, np.float32); self.wR = np.zeros(n, np.float32)

    def add(self, t, s, vol, wet=0, pan=0):
        gl = vol * np.sqrt((1 - pan) / 2) * 1.414; gr = vol * np.sqrt((1 + pan) / 2) * 1.414
        for arr, g in ((self.L, gl), (self.R, gr)):
            mix(arr, t, s * g)
        if wet:
            mix(self.wL, t, s * gl * wet); mix(self.wR, t, s * gr * wet)


def v_nz(dur, kind, f, vol, f2=None, q=None):
    n = int((dur + 0.05) * SR); off = rng.integers(0, len(NOISE) - n - 1)
    return filt(NOISE[off:off + n].copy(), kind, f, f2, q, dur) * env_exp(n, vol, .004, dur)


def v_tn(f1, f2, dur, kind, vol, att=.004):
    n = int((dur + 0.05) * SR)
    return osc(kind, f1, f2, n, dur).astype(np.float32) * env_exp(n, vol, att, dur)


def padd(*arrs):
    n = max(len(a) for a in arrs); out = np.zeros(n, np.float32)
    for a in arrs: out[:len(a)] += a
    return out


def snare(B, t, v):
    B.add(t, padd(v_nz(.16, 'bandpass', 2100, .9, 1600, .9), v_nz(.09, 'highpass', 5000, .35), v_tn(230, 180, .05, 'triangle', .4)), v, .18, .12)


def kick(B, t, v):
    B.add(t, padd(v_tn(120, 45, .3, 'sine', .9), v_nz(.03, 'lowpass', 900, .3)), v, .1)


def timp(B, t, m, v, dur=1.1):
    f = mtof(m)
    B.add(t, padd(v_tn(f * 1.06, f, dur, 'sine', .9, .006), v_tn(f * 2.01, f * 2, dur * .5, 'sine', .2), v_nz(.06, 'lowpass', 400, .25)), v, .35)


def cymbal(B, t, v):
    B.add(t, padd(v_nz(1.6, 'highpass', 6500, .5), v_nz(.8, 'bandpass', 3500, .2, None, .5)), v, .4, -.2)


def adsr(n, dur, peak, hold, att=.035):
    tt = np.arange(n) / SR
    e = np.where(tt < att, peak * tt / att, hold)
    rel = tt > dur
    e[rel] = hold * np.clip(1 - (tt[rel] - dur) / .12, 0, 1)
    return e.astype(np.float32)


def brass(B, t, notes, dur, v, bright):
    n = int((dur + .2) * SR); acc = np.zeros(n, np.float32)
    for m in notes:
        f = mtof(m)
        for dt in (-5, 5):
            ff = f * 2 ** (dt / 1200)
            acc += osc('sawtooth', ff, ff, n, dur).astype(np.float32)
    s = filt(acc, 'lowpass', 900 + bright * 2600, 600 + bright * 900, 1.5, min(dur, .5)) * adsr(n, dur, .5, .4)
    B.add(t, s, v, .3)


def horn(B, t, m, dur, v):
    f = mtof(m); n = int((dur + .25) * SR); tt = np.arange(n) / SR
    vib = 1 + .006 * np.minimum(1, tt / max(.05, min(dur, .4))) * np.sin(2 * np.pi * 5.2 * tt)
    ph = np.cumsum(f * vib) / SR
    s = (2 * (ph % 1) - 1) + .25 * np.sign(np.sin(np.pi * ph))
    s = filt(s.astype(np.float32), 'lowpass', 1700, None, 2) * adsr(n, dur, .45, .38, .05)
    B.add(t, s, v, .45, -.15)


def strings(B, t, m, dur, v, acc):
    f = mtof(m); n = int((dur + .05) * SR); s = np.zeros(n, np.float32)
    for dt in (-8, 8):
        ff = f * 2 ** (dt / 1200); s += osc('sawtooth', ff, ff, n, dur).astype(np.float32)
    s = filt(s, 'lowpass', 1100 if acc else 700) * env_exp(n, .55 if acc else .38, .012, dur)
    B.add(t, s, v, .12, .2)


def render_march(I, bars=32, seed=3):
    global rng
    rng = np.random.default_rng(seed)
    total = bars * 16
    length = total * SIXT
    n = int((length + 3) * SR)
    B = Bus(n)
    motif = 0
    lvl = .55 + I * .45
    order = [0, 1, 2, 1]
    for st in range(total):
        t = st * SIXT
        s = st % 16; bar = st // 16; ph = bar % 8
        ch = PROG[(bar >> 1) % len(PROG)]; chn = PROG[((bar >> 1) + 1) % len(PROG)]
        o = OST[s]
        if o:
            strings(B, t, ch[0] + (0 if s % 4 == 0 else 12), SIXT * (1.6 if s % 4 == 0 else .9), .11 * lvl, o == 2)
        if s in (0, 8) or (I > .35 and s in (6, 14)):
            kick(B, t, (.55 if s == 0 else .42) * lvl)
        if bar % 4 == 3 and s >= 12:
            for k in range(2): snare(B, t + k * SIXT / 2, (.14 + (s - 12) * .05) * lvl)
        else:
            vv = SNR[s]
            if vv: snare(B, t, (.32 if vv == 3 else .24 if vv == 2 else .09) * (.6 + I * .6))
        if s == 0 and bar % 2 == 0: timp(B, t, ch[0], .5 * lvl)
        if ph == 7 and s >= 8: timp(B, t, chn[0], .12 + (s - 8) * .03, .3)
        if s == 0 and bar % 8 == 0 and bar > 0: cymbal(B, t, .18 * lvl)
        if s == 0 and bar % 2 == 0: brass(B, t, ch[1:], SIXT * (5 if I > .3 else 28), .06 * lvl, I)
        if I > .3 and bar % 2 == 1 and s in (0, 3, 4, 12):
            brass(B, t, ch[1:], SIXT * (.8 if s == 3 else 2.5 if s == 4 else 2), .07 * lvl, .6 + I * .4)
        if ph == 0 and s == 0: motif = order[(bar // 8) % len(order)]
        if ph < 2:
            off = ph * 16 + s
            for oo, m, l in FANF[motif]:
                if oo == off: horn(B, t, m, SIXT * l * .95, .09)
        if ph == 4 and I > .5:
            for oo, m, l in FANF[(motif + 1) % len(FANF)]:
                if oo == s and oo < 16: horn(B, t, m + (0 if rng.random() < .5 else -12), SIXT * l * .95, .07)
    L = B.L + reverb_tail(B.wL); R = B.R + reverb_tail(B.wR)
    # wrap the tail past the loop point back to the start so the loop is seamless
    ln = int(length * SR)
    L[:n - ln] += L[ln:n]; R[:n - ln] += R[ln:n]
    L = L[:ln]; R = R[:ln]
    st = np.stack([L, R], 1)
    st /= max(1e-6, np.abs(st).max()) / 0.8
    return st


def reverb_tail(w):
    L = len(w) + len(IMP); F = 1 << int(np.ceil(np.log2(L)))
    r = np.fft.irfft(np.fft.rfft(w, F) * np.fft.rfft(IMP, F), F)[:len(w)].astype(np.float32)
    return r * 0.32 * 1.6 / max(1e-6, np.sqrt(np.sum(IMP ** 2)))


def master(st, gain_db=9.0, knee=0.6):
    """Louder march for phone speakers: fixed gain (same for both layers, so the crossfade holds),
    then a soft knee above `knee` instead of hard clipping on drum hits."""
    x = st * 10 ** (gain_db / 20)
    a = np.abs(x)
    over = a > knee
    y = x.copy()
    y[over] = np.sign(x[over]) * (knee + (1 - knee) * np.tanh((a[over] - knee) / (1 - knee)))
    return y * 0.97


def main():
    root = sys.argv[1]
    os.makedirs(f'{root}/sfx', exist_ok=True); os.makedirs(f'{root}/music', exist_ok=True)
    names = ['gun', 'snipe', 'shell', 'heavy', 'mortar', 'rocket', 'flak', 'flame', 'arc', 'small', 'boom', 'bigboom', 'click', 'ack', 'ack_ashen', 'ready', 'alert', 'place', 'siren']
    peak = 0
    out = {}
    for n in names:
        out[n] = sfx(n); peak = max(peak, np.abs(out[n]).max())
    for n in names:
        # Each effect keeps its place in the mix, but the range is squeezed (power 0.35) so quiet
        # UI clicks and small arms stay audible on a phone speaker; nothing goes below 0.4 peak.
        p = np.abs(out[n]).max()
        s = out[n] / p * max(0.4, 0.95 * (p / peak) ** 0.35)
        write_wav(f'{root}/sfx/{n}.wav', s)
        print(n, round(len(s) / SR, 2), 's')
    if '--no-music' in sys.argv:
        return
    for nm, I in (('march_calm', .1), ('march_combat', .95)):
        st = master(render_march(I))
        tmp = f'/tmp/{nm}.wav'
        data = (np.clip(st, -1, 1) * 32767).astype('<i2')
        with wave.open(tmp, 'wb') as w:
            w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', tmp, '-c:a', 'libvorbis', '-q:a', '3', f'{root}/music/{nm}.ogg'], check=True)
        print(nm, round(len(st) / SR, 1), 's')


main()
