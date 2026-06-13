#!/usr/bin/env python3
"""v4: hybrid sprite build for desk_pin motion loop.

Body  = half-grid (3.65px) logical reconstruction, desk_pin palette.
Ball  = canonical fine sprite (quarter-grid 1.825px) extracted from a clean frame,
        tracked per frame via white-pixel centroid, stamped over the body.
Output= /tmp/clawd_motion/v4/<char>_NN.png  (fine scale: 72x48-ish, RGBA)
        replica timeline (vanish span removed) resampled at 10fps.
"""
import os, json, hashlib
from PIL import Image

SRC = "/tmp/clawd_motion/frames"
OUT = "/tmp/clawd_motion/v4"
os.makedirs(OUT, exist_ok=True)

BG = (0x1e, 0x1e, 0x1d)
CORAL = (0xd9, 0x77, 0x57)          # desk_pin Palette.clawdBody
INDIGO = (0x64, 0x70, 0xf3)         # desk_pin Palette.codexBody
BLACK = (0x00, 0x00, 0x00)
WHITE = (0xff, 0xff, 0xff)
QPAL = [BG, (0xd8, 0x76, 0x56), BLACK, WHITE]   # quantization palette (measured colors)

S = 3.65            # half-grid dot (calibrated in pipeline.py)
FS = S / 2          # fine grid (ball)
CROP = (225, 270, 358, 362)
IDLE_END, REAPPEAR, CONTENT_END, TICK = 1.78, 3.83, 9.98, 0.1

files = sorted(f for f in os.listdir(SRC) if f.endswith(".png"))
def pts(name): return float(name.rsplit("_", 1)[1][:-4])
def load(f): return Image.open(os.path.join(SRC, f)).convert("RGB").crop(CROP)

# ---------- shared helpers (from pipeline.py) ----------
def cell_avg(px, w, h, x0, y0, s):
    xa, xb = x0 + s * 0.25, x0 + s * 0.75
    ya, yb = y0 + s * 0.25, y0 + s * 0.75
    rs = gs = bs = n = 0
    y = ya
    while y < yb:
        x = xa
        while x < xb:
            xi, yi = int(x), int(y)
            if 0 <= xi < w and 0 <= yi < h:
                r, g, b = px[xi, yi]
                rs += r; gs += g; bs += b; n += 1
            x += 1
        y += 1
    return (rs / n, gs / n, bs / n) if n else BG

def snap(img, s, ox, oy):
    px = img.load(); w, h = img.size
    cols = int((w - ox) / s); rows = int((h - oy) / s)
    err = 0.0; cells = []
    for r in range(rows):
        row = []
        for c in range(cols):
            v = cell_avg(px, w, h, ox + c * s, oy + r * s, s)
            best = min(QPAL, key=lambda p: sum((a - b) ** 2 for a, b in zip(p, v)))
            err += sum((a - b) ** 2 for a, b in zip(best, v))
            row.append(best)
        cells.append(row)
    return err / (rows * cols), cells, ox, oy

def best_phase(img, s, step=0.25):
    best = None
    ox = 0.0
    while ox < s:
        oy = 0.0
        while oy < s:
            cand = snap(img, s, ox, oy)
            if best is None or cand[0] < best[0]:
                best = cand
            oy += step
        ox += step
    return best  # (err, cells, ox, oy)

# ---------- ball detection (recording space) ----------
def ball_centroid(img):
    """centroid of near-white pixels; None if too few."""
    px = img.load(); w, h = img.size
    xs = ys = n = 0
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if r > 185 and g > 185 and b > 185:
                xs += x; ys += y; n += 1
    if n < 12:
        return None
    return (xs / n, ys / n, n)

def orange_cells_near(img, cx, cy, rad):
    px = img.load(); w, h = img.size
    best = 1e9
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if r > 150 and r - b > 60 and r - g > 30:
                d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                best = min(best, d)
    return best

# ---------- 1. canonical ball: frame where ball is far from body ----------
BALL_R = 8.0
best_ball = None
ball_info = {}     # file -> (cx, cy)
for f in files:
    t = pts(f)
    if t >= 10.0:  # tail contamination
        continue
    img = load(f)
    c = ball_centroid(img)
    if not c:
        continue
    cx, cy, n = c
    ball_info[f] = (cx, cy)
    d = orange_cells_near(img, cx, cy, BALL_R)
    if best_ball is None or d > best_ball[0]:
        best_ball = (d, f, cx, cy)

d, bf, bcx, bcy = best_ball
print(f"canonical ball frame: {bf} (clearance {d:.1f}px) center ({bcx:.1f},{bcy:.1f})")

bimg = load(bf); bpx = bimg.load()
FB = 11  # fine cells across ball patch (11 * 1.825 ≈ 20px)
half = FB * FS / 2
ball_sprite = []   # FB x FB of None / BLACK / WHITE
for r in range(FB):
    row = []
    for c in range(FB):
        x0, y0 = bcx - half + c * FS, bcy - half + r * FS
        v = cell_avg(bpx, bimg.size[0], bimg.size[1], x0, y0, FS)
        dist = (((x0 + FS / 2) - bcx) ** 2 + ((y0 + FS / 2) - bcy) ** 2) ** 0.5
        if dist > BALL_R:
            row.append(None)
        else:
            # ball is a solid disc: binary white/black inside radius (dark checks
            # blur toward bg in the recording, so bg must not be an option here)
            lum = (v[0] + v[1] + v[2]) / 3
            row.append(WHITE if lum > 90 else BLACK)
    ball_sprite.append(row)
nz = sum(1 for r in ball_sprite for v in r if v)
print(f"canonical ball: {FB}x{FB} fine cells, {nz} solid")

# ---------- 2. replica timeline (vanish removed) -> 10fps pose schedule ----------
events = [(pts(f), f) for f in files if pts(f) < CONTENT_END]
def active_file(t_replica):
    """map replica time (vanish span removed) back to source time, pick last frame <= it"""
    t = t_replica if t_replica < IDLE_END else t_replica + (REAPPEAR - IDLE_END)
    cur = events[0][1]
    for et, ef in events:
        if et <= t + 1e-9:
            cur = ef
        else:
            break
    return cur

REPLICA_LEN = IDLE_END + (CONTENT_END - REAPPEAR)   # 1.78 + 6.60 = 8.38s
n_ticks = int(REPLICA_LEN / TICK)
schedule = [active_file(i * TICK) for i in range(n_ticks)]
print(f"replica {REPLICA_LEN:.2f}s -> {n_ticks} ticks @10fps, {len(set(schedule))} distinct source frames")

# ---------- 3. render each scheduled frame: body grid + ball stamp ----------
def render_frame(f, body_color):
    img = load(f)
    err, cells, ox, oy = best_phase(img, S)
    rows, cols = len(cells), len(cells[0])
    W, H = cols * 2, rows * 2
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    p = out.load()
    ball = ball_info.get(f)
    # pass 1: body at half-grid (2x2 px per cell)
    for r in range(rows):
        for c in range(cols):
            v = cells[r][c]
            ccx, ccy = ox + c * S + S / 2, oy + r * S + S / 2
            if v == WHITE:
                v = None  # white belongs to the ball only; handled in pass 2
            if ball and v == BLACK:
                dist = ((ccx - ball[0]) ** 2 + (ccy - ball[1]) ** 2) ** 0.5
                if dist <= BALL_R + S / 2:
                    v = None  # ball-region black re-rendered finely in pass 2
            if v == QPAL[1]:
                v = body_color
            if v in (None, BG):
                continue
            for dy in (0, 1):
                for dx in (0, 1):
                    p[c * 2 + dx, r * 2 + dy] = v + (255,)
    # pass 2: ball as solid disc at fine grid, binary white/black per cell
    # (preserves the ball's frame-to-frame rotation; disc prior kills blur holes)
    if ball:
        ipx = img.load()
        for fy in range(H):
            for fx in range(W):
                x0, y0 = ox + fx * FS, oy + fy * FS
                dist = (((x0 + FS / 2) - ball[0]) ** 2 + ((y0 + FS / 2) - ball[1]) ** 2) ** 0.5
                if dist > BALL_R:
                    continue
                v = cell_avg(ipx, img.size[0], img.size[1], x0, y0, FS)
                dw = sum((a - b) ** 2 for a, b in zip(v, WHITE))
                db = sum((a - b) ** 2 for a, b in zip(v, BLACK))
                p[fx, fy] = (WHITE if dw < db else BLACK) + (255,)
    fill_enclosed_holes(out)
    return out, err

def fill_enclosed_holes(im):
    """Transparent pixels NOT reachable from the border are body-interior holes
    (eyes, mouth, blink slits) — in the source app they show the dark chat bg,
    so on a transparent desktop widget they must be painted black instead."""
    W, H = im.size
    p = im.load()
    seen = [[False] * W for _ in range(H)]
    stack = [(x, y) for x in range(W) for y in (0, H - 1) if p[x, y][3] == 0]
    stack += [(x, y) for y in range(H) for x in (0, W - 1) if p[x, y][3] == 0]
    for x, y in stack:
        seen[y][x] = True
    while stack:
        x, y = stack.pop()
        for nx, ny in ((x+1,y), (x-1,y), (x,y+1), (x,y-1)):
            if 0 <= nx < W and 0 <= ny < H and not seen[ny][nx] and p[nx, ny][3] == 0:
                seen[ny][nx] = True
                stack.append((nx, ny))
    for y in range(H):
        for x in range(W):
            if p[x, y][3] == 0 and not seen[y][x]:
                p[x, y] = (0, 0, 0, 255)

# render distinct source frames once, reuse
cache = {}
errs = []
for f in sorted(set(schedule)):
    im, err = render_frame(f, CORAL)
    cache[f] = im
    errs.append(err)
print(f"rendered {len(cache)} distinct frames, quant err avg {sum(errs)/len(errs):.0f} max {max(errs):.0f}")

def recolor(im, frm, to):
    out = im.copy(); p = out.load()
    for y in range(out.size[1]):
        for x in range(out.size[0]):
            r, g, b, a = p[x, y]
            if a and (r, g, b) == frm:
                p[x, y] = to + (a,)
    return out

for i, f in enumerate(schedule):
    cache[f].save(f"{OUT}/clawd_soccer_{i:02d}.png")
    recolor(cache[f], CORAL, INDIGO).save(f"{OUT}/cody_soccer_{i:02d}.png")

# ---------- 4. preview gif ----------
Z = 6
prev = []
for f in schedule:
    im = cache[f]
    bgim = Image.new("RGBA", im.size, BG + (255,))
    bgim.alpha_composite(im)
    prev.append(bgim.convert("RGB").resize((im.size[0] * Z, im.size[1] * Z), Image.NEAREST))
prev[0].save(f"{OUT}/preview_v4.gif", save_all=True, append_images=prev[1:],
             duration=100, loop=0)

meta = {"frames": n_ticks, "fps": 10, "size": list(cache[schedule[0]].size),
        "replica_len_s": round(REPLICA_LEN, 2), "ball_frames": len(ball_info)}
json.dump(meta, open(f"{OUT}/meta.json", "w"), indent=1)
print("META", meta)
