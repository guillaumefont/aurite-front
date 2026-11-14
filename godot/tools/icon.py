#!/usr/bin/env python3
"""War-themed app icon, matching the menu and splash art.

Usage (from godot/): python3 tools/icon.py .
Writes icon.png (192, rounded, also the project icon), icon_bg.png and icon_fg.png
(432x432 Android adaptive layers; keep the emblem inside the central 66% safe zone).
Needs Pillow.
"""
import math, sys
from PIL import Image, ImageDraw, ImageFilter

SS = 4            # supersampling
N = 432 * SS

def hexc(h, a=255):
    h = h.lstrip('#'); return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))

def ridge(x, base, amp, sd):
    q = x / SS
    return base - amp * (math.sin(q * 0.012 + sd) * 0.55 + math.sin(q * 0.031 + sd * 2.3) * 0.3 + math.sin(q * 0.07 + sd * 4.1) * 0.15)

def background():
    im = Image.new('RGBA', (N, N))
    d = ImageDraw.Draw(im)
    hz = N * 0.66
    top, mid, low = hexc('0b0a08'), hexc('1a100c'), hexc('5a1f10')
    for y in range(N):
        t = y / hz
        c = lerp(top, mid, t / 0.5) if t < 0.5 else lerp(mid, low, min(1, (t - 0.5) / 0.5))
        d.line([(0, y), (N, y)], fill=c)
    # horizon fire glow
    glow = Image.new('RGBA', (N, N), (0, 0, 0, 0)); g = ImageDraw.Draw(glow)
    for cx in (0.22, 0.8):
        g.ellipse([N * cx - N * 0.32, hz - N * 0.12, N * cx + N * 0.32, hz + N * 0.12], fill=(255, 110, 35, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(N * 0.06))
    im.alpha_composite(glow)
    # crossed searchlights meeting behind the emblem
    beams = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    for ox, ang in ((0.18, 0.5), (0.82, -0.5)):
        b = Image.new('RGBA', (N, N), (0, 0, 0, 0)); bd = ImageDraw.Draw(b)
        o = (N * ox, hz + N * 0.02); a = -math.pi / 2 + ang; w = 0.085; L = N * 1.3
        bd.polygon([o, (o[0] + math.cos(a - w) * L, o[1] + math.sin(a - w) * L), (o[0] + math.cos(a + w) * L, o[1] + math.sin(a + w) * L)], fill=(255, 236, 190, 46))
        beams.alpha_composite(b.filter(ImageFilter.GaussianBlur(SS * 3)))
    im.alpha_composite(beams)
    # ridges
    for base, amp, sd, col in ((hz + N * 0.01, N * 0.035, 1.3, '2c1610'), (hz + N * 0.12, N * 0.04, 4.2, '130b08'), (N * 0.93, N * 0.03, 7.7, '060403')):
        pts = [(x, ridge(x, base, amp, sd)) for x in range(0, N + 8, 8)] + [(N, N), (0, N)]
        d.polygon(pts, fill=hexc(col))
    # embers
    import random
    rnd = random.Random(7)
    for _ in range(26):
        x, y = rnd.uniform(0, N), rnd.uniform(N * 0.45, N); r = rnd.uniform(1.2, 2.6) * SS
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, rnd.randint(140, 220), 60, rnd.randint(120, 220)))
    return im

def foreground():
    im = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    cx, cy = N / 2, N / 2 + N * 0.01
    W, H = N * 0.40, N * 0.46           # inside the 66% safe circle
    x0, y0 = cx - W / 2, cy - H / 2
    P = lambda fx, fy: (x0 + W * fx, y0 + H * fy)
    shield = [P(0.5, 0), P(1, 0.14), P(0.92, 0.66), P(0.5, 1), P(0.08, 0.66), P(0, 0.14)]
    # drop shadow
    sh = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon([(x, y + N * 0.02) for x, y in shield], fill=(0, 0, 0, 170))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(N * 0.02)))
    d = ImageDraw.Draw(im)
    d.polygon(shield, fill=hexc('21271a'))
    bw = int(N * 0.022)
    d.line(shield + [shield[0], shield[1]], fill=hexc('d9a441'), width=bw, joint='curve')
    # inner rule
    inner = [(cx + (x - cx) * 0.86, cy + (y - cy) * 0.86 + N * 0.004) for x, y in shield]
    d.line(inner + [inner[0], inner[1]], fill=hexc('d9a441', 110), width=int(N * 0.006), joint='curve')
    # chevrons taper to points and narrow toward the tip, clear of the border
    for i in range(3):
        y = 0.47 + 0.13 * i; hw = (0.27, 0.24, 0.19)[i]; t = 0.075
        d.polygon([P(0.5 - hw, y), P(0.5, y + 0.11 - t / 2), P(0.5 + hw, y), P(0.5, y + 0.11 + t / 2)], fill=hexc('d8cba3'))
    c = P(0.5, 0.25); st = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5; r = W * (0.17 if i % 2 == 0 else 0.07)
        st.append((c[0] + math.cos(a) * r, c[1] + math.sin(a) * r))
    d.polygon(st, fill=hexc('e5483f'))
    return im

def main(out):
    bg, fg = background(), foreground()
    bg.resize((432, 432), Image.LANCZOS).save(f'{out}/icon_bg.png')
    fg.resize((432, 432), Image.LANCZOS).save(f'{out}/icon_fg.png')
    # legacy / project icon: adaptive layers cropped like a launcher would (central 72/108), rounded
    full = bg.copy(); full.alpha_composite(fg)
    m = int(N * 18 / 108); full = full.crop((m, m, N - m, N - m))
    mask = Image.new('L', full.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, full.size[0] - 1, full.size[1] - 1], radius=int(full.size[0] * 0.22), fill=255)
    full.putalpha(mask)
    full.resize((192, 192), Image.LANCZOS).save(f'{out}/icon.png')

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
