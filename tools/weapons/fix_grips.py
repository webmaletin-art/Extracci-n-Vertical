#!/usr/bin/env python3
"""Recalcula los marcadores de las manos de TODAS las armas mirando la silueta real del modelo (de perfil):
  * Grip (mano derecha): la empuñadura de pistola, no el cargador. Se reconoce porque es la saliente de abajo cuya punta
    se inclina hacia la culata (los cargadores van rectos o hacia adelante); en pistolas y revólveres es la culata del arma.
  * Support (mano izquierda): la empuñadura vertical delantera si el arma la tiene (saliente angosta delante del cargador)
    y si no el guardamanos / la corredera de la escopeta, por debajo, a una distancia natural del hombro.
  * SupportKind: "vgrip" (empuñadura vertical: la mano la rodea como a la de pistola) o "rail" (guardamanos, palma arriba).
Uso: python3 tools/weapons/fix_grips.py [--sheet salida.png]  (escribe assets/weapons/models.json)"""
import sys, json, os
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_mesh
import grips_manual
from PIL import Image, ImageDraw

R = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PX = 0.002          # 2 mm por píxel


def silhouette(v, t):
    zmin, zmax = v[:, 2].min(), v[:, 2].max()
    ymin, ymax = v[:, 1].min(), v[:, 1].max()
    W = int((zmax - zmin) / PX) + 3
    H = int((ymax - ymin) / PX) + 3
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    # columna 0 = culata (z máx), fila 0 = arriba (y máx)
    for tri in t:
        d.polygon([((zmax - v[k, 2]) / PX + 1, (ymax - v[k, 1]) / PX + 1) for k in tri], fill=255)
    a = np.array(im) > 0
    return a, zmax, ymax


def to_world(col, row, zmax, ymax):
    return float(zmax - (col - 1) * PX), float(ymax - (row - 1) * PX)


def segments(mask_cols):
    segs, start = [], None
    for i, m in enumerate(list(mask_cols) + [False]):
        if m and start is None:
            start = i
        elif not m and start is not None:
            segs.append((start, i - 1))
            start = None
    return segs


def runs_in_row(a, row, c0, c1):
    W = a.shape[1]
    c0, c1 = max(c0, 0), min(c1, W - 1)
    return segments([bool(a[row, c]) for c in range(c0, c1 + 1)]), c0


def widest_center(a, row, c0, c1):
    rs, base = runs_in_row(a, row, c0, c1)
    if not rs:
        return None, 0
    r = max(rs, key=lambda r: r[1] - r[0])
    return base + (r[0] + r[1]) / 2.0, (r[1] - r[0] + 1)


def find_guard(a, ref, L):
    """Hueco del guardamonte: fondo encerrado, chico, justo debajo del cajón."""
    H, W = a.shape
    im = Image.fromarray((a * 255).astype(np.uint8))
    pad = Image.new("L", (W + 2, H + 2), 0)
    pad.paste(im, (1, 1))
    ImageDraw.floodfill(pad, (0, 0), 128)
    holes = (np.array(pad)[1:-1, 1:-1] == 0)
    seen = np.zeros_like(holes)
    best = None
    found = []
    for y0 in range(H):
        for x0 in range(W):
            if holes[y0, x0] and not seen[y0, x0]:
                stack = [(y0, x0)]
                seen[y0, x0] = True
                ys, xs = [], []
                while stack:
                    y, x = stack.pop()
                    ys.append(y); xs.append(x)
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < H and 0 <= nx < W and holes[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            stack.append((ny, nx))
                w = (max(xs) - min(xs) + 1) * PX
                h = (max(ys) - min(ys) + 1) * PX
                top = min(ys)
                cx = (max(xs) + min(xs)) / 2.0
                if 0.005 < w < 0.075 and 0.005 < h < 0.05 and L * 0.2 < cx < L * 0.75:
                    found.append((min(xs), max(xs), min(ys), max(ys)))
    if not found:
        return None
    # el más bajo (el guardamonte está debajo del cajón; rieles y miras, arriba); el gatillo lo parte en dos: se unen
    g = max(found, key=lambda b: b[3])
    for b in found:
        if b is not g and abs(b[3] - g[3]) * PX < 0.02 and (min(abs(b[0] - g[1]), abs(g[0] - b[1])) * PX < 0.02):
            g = (min(g[0], b[0]), max(g[1], b[1]), min(g[2], b[2]), max(g[3], b[3]))
    return g


def analyze(wid, model, cls):
    v, t, _ = glb_mesh.load(os.path.join(R, "assets/weapons/%s.glb" % model))
    a, zmax, ymax = silhouette(v, t)
    H, W = a.shape
    filled = a.any(axis=0)
    bottom = np.array([np.max(np.nonzero(a[:, c])[0]) if filled[c] else -1 for c in range(W)])
    top = np.array([np.min(np.nonzero(a[:, c])[0]) if filled[c] else H for c in range(W)])
    L = W
    pistol = cls == "pistol"
    core = bottom[int(L * 0.15):int(L * 0.95)]
    core = core[core >= 0]
    ref = np.percentile(core, 30 if not pistol else 20)

    def segs_at(th):
        deep = bottom > ref + int(th / PX)
        out = []
        for s0, s1 in segments(deep):
            if s1 - s0 < int(0.01 / PX):
                continue
            yb = int(bottom[s0:s1 + 1].max())
            depth = (yb - ref) * PX
            pts = []
            for k in np.linspace(0.15, 0.85, 8):
                row = int(ref + (yb - ref) * k)
                c, wpx = widest_center(a, row, s0 - int(0.01 / PX), s1 + int(0.01 / PX))
                if c is not None:
                    pts.append((k * depth, c * PX, wpx * PX))
            if len(pts) < 3:
                continue
            ys = np.array([p[0] for p in pts])
            cs = np.array([p[1] for p in pts])
            rake = np.polyfit(ys, cs, 1)[0]            # columnas por metro de bajada: < 0 la punta va hacia la culata
            width = float(np.median([p[2] for p in pts]))
            out.append({"s0": s0, "s1": s1, "depth": depth, "rake": rake, "width": width, "c": (s0 + s1) / 2.0, "yb": yb,
                        "touch_butt": s0 <= int(L * 0.04)})
        return out

    deep = [i for i in segs_at(0.045) if not i["touch_butt"]]
    shallow = [i for i in segs_at(0.025) if not i["touch_butt"]]

    def point_in(seg, k):
        row = int(ref + (seg["yb"] - ref) * k)
        c, _ = widest_center(a, row, seg["s0"] - int(0.01 / PX), seg["s1"] + int(0.01 / PX))
        if c is None:
            c = seg["c"]
        return to_world(c, row, zmax, ymax)

    guard = find_guard(a, ref, L) if not pistol else None
    BULLPUP = ("aug", "p90", "bullpup_1", "bullpup_2", "bullpup_3")
    notch = int(0.012 / PX)
    stock_end = None
    for c in range(0, int(L * 0.6)):
        if bottom[c] >= 0 and bottom[c] <= ref + notch:
            stock_end = c
            break
    grip_rows = []          # (fila, centro) de la empuñadura de arriba hacia abajo
    if model in BULLPUP:
        raked = [i for i in deep if i["rake"] < -0.12 and i["width"] > 0.018]
        g = min(raked, key=lambda i: i["rake"]) if raked else (min(deep, key=lambda i: i["c"]) if deep else None)
        if g:
            for row in range(int(ref + notch), int(g["yb"])):
                c, wpx = widest_center(a, row, g["s0"] - 3, g["s1"] + 3)
                if c is not None:
                    grip_rows.append((row, c))
    elif guard is not None:
        # la empuñadura es lo que está justo DETRÁS del guardamonte (hacia la culata), y sigue hacia abajo
        g_left, g_right, g_top, g_bot = guard
        prev = None
        for row in range(int(g_top + (g_bot - g_top) * 0.3), H):
            rs, base = runs_in_row(a, row, max(g_left - int(0.12 / PX), 0), g_right if row <= g_bot else g_left + int(0.03 / PX))
            rs = [r for r in rs if 0.01 < (r[1] - r[0] + 1) * PX < 0.055]
            if row <= g_bot:
                rs = [r for r in rs if base + r[1] <= g_left + 2]
            if not rs:
                if grip_rows:
                    break
                continue
            if prev is None:
                r = max(rs, key=lambda r: r[1])              # el tramo pegado al guardamonte
            else:
                r = min(rs, key=lambda r: abs(base + (r[0] + r[1]) / 2.0 - prev))
            cen = base + (r[0] + r[1]) / 2.0
            if prev is not None and abs(cen - prev) > int(0.025 / PX):
                break
            grip_rows.append((row, cen))
            prev = cen
    elif stock_end is not None or pistol:
        c_lo = 0 if (pistol or stock_end is None) else max(stock_end - 3, 0)
        c_hi = min(W - 1, c_lo + int((0.22 if not pistol else 0.12) / PX) + (0 if not pistol else int(L * 0.25)))
        prev = None
        for row in range(int(ref + notch), H):
            rs, base = runs_in_row(a, row, c_lo, c_hi)
            rs = [r for r in rs if (r[1] - r[0] + 1) * PX > 0.01 and (pistol or ((r[1] - r[0] + 1) * PX < 0.065 and r[0] > 1))]
            if not rs:
                if grip_rows:
                    break
                continue
            r = min(rs, key=lambda r: r[0])          # la saliente MÁS DE ATRÁS (la empuñadura, no el guardamonte ni el cargador)
            cen = base + (r[0] + r[1]) / 2.0
            if prev is not None and abs(cen - prev) > int(0.03 / PX):
                if len(grip_rows) < int(0.03 / PX):
                    grip_rows = []          # lo de arriba era otra cosa (unión de la culata): se vuelve a empezar
                else:
                    break
            grip_rows.append((row, cen))
            prev = cen
    if len(grip_rows) >= int(0.04 / PX):
        k = grip_rows[int(len(grip_rows) * 0.30)]
        gz, gy = to_world(k[1], k[0], zmax, ymax)
        g_col = k[1]
        kp = grip_rows[int(len(grip_rows) * 0.62)]
    else:
        # culata con empuñadura integrada (escopetas de caza, francotiradores): la «muñeca» más delgada detrás del gatillo
        cs = [c for c in range(int(L * 0.18), int(L * 0.45)) if bottom[c] >= 0]
        col = min(cs, key=lambda c: bottom[c] - top[c])
        gz, gy = to_world(col, top[col] + (bottom[col] - top[col]) * 0.62, zmax, ymax)
        g_col = col
        kp = None
    kind = "rail"
    if pistol:
        if kp:
            sz, sy = to_world(kp[1], kp[0], zmax, ymax)
        else:
            sz, sy = gz, gy - 0.03
        kind = "pistol"
    else:
        muzzle_col = L - 1
        thick = [c for c in range(int(g_col), muzzle_col) if bottom[c] >= 0 and (bottom[c] - top[c]) * PX > 0.03]
        body_front = max(thick) if thick else muzzle_col
        mags = [i for i in deep if i["c"] > g_col + int(0.03 / PX)]
        mag_front = max([i["s1"] for i in mags if i["c"] < g_col + L * 0.35] + [int(g_col)])
        fg = [i for i in shallow if i["c"] > mag_front + int(0.015 / PX) and i["width"] < 0.05 and abs(i["rake"]) < 0.35 and i["depth"] < 0.14]
        if fg:
            sz, sy = point_in(fg[0], 0.30)
            kind = "vgrip"
        else:
            frac = 0.5 if cls == "shotgun" else 0.42
            col = int(g_col + (muzzle_col - g_col) * frac)
            col = max(col, mag_front + int(0.06 / PX))
            col = min(col, int(L * 0.74), body_front - int(0.03 / PX))
            if col <= mag_front and mags:
                sz, sy = point_in(mags[0], 0.25)       # subfusil sin guardamanos: la izquierda toma el cargador
                kind = "mag"
            else:
                col = int(min(max(col, 0), muzzle_col - 2))
                while bottom[col] < 0 and col > 0:
                    col -= 1
                sz, sy = to_world(col, bottom[col], zmax, ymax)
                sy += 0.004
    return {"Grip": [0.0, round(gy, 4), round(gz, 4)], "Support": [0.0, round(sy, 4), round(sz, 4)], "SupportKind": kind}


def manual(model):
    v, t, _ = glb_mesh.load(os.path.join(R, "assets/weapons/%s.glb" % model))
    zmin, zmax = v[:, 2].min(), v[:, 2].max()
    ymin, ymax = v[:, 1].min(), v[:, 1].max()
    (gx, gy), (sx, sy), kind = grips_manual.M[model]
    W = lambda x, y: [0.0, round(float(ymax - y / 10.0 * (ymax - ymin)), 4), round(float(zmax - x / 10.0 * (zmax - zmin)), 4)]
    return {"Grip": W(gx, gy), "Support": W(sx, sy), "SupportKind": kind}


def main():
    mk = json.load(open(R + "/assets/weapons/models.json"))
    w = json.load(open(R + "/data/weapons.json"))
    done, fail = 0, []
    for wid, st in w.items():
        if wid.startswith("_"):
            continue
        model = st["model"]
        if model not in mk:
            fail.append(wid)
            continue
        if model in grips_manual.M:
            r = manual(model)
        else:
            r = analyze(wid, model, st["class"])
        if r is None:
            fail.append(wid)
            continue
        mk[model]["markers"]["Grip"] = r["Grip"]
        mk[model]["markers"]["Support"] = r["Support"]
        mk[model]["support_kind"] = r["SupportKind"]
        done += 1
    json.dump(mk, open(R + "/assets/weapons/models.json", "w"), indent=1)
    print("marcadores recalculados:", done, "sin cambio:", fail)


if __name__ == "__main__":
    main()
