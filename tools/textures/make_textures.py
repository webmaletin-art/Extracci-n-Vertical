#!/usr/bin/env python3
"""Genera las texturas procedurales del escenario (tileables, 512 px) en assets/textures/.

Uso: python3 tools/textures/make_textures.py assets/textures
Son la base mientras no haya texturas horneadas en Blender; se reemplazan dejando el mismo nombre de archivo.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
N = 512
rng = np.random.default_rng(7)


def tile_noise(size, scale, octaves=5, seed=0):
    """Ruido de valor tileable (suma de octavas) en [0, 1]."""
    r = np.random.default_rng(seed)
    acc = np.zeros((size, size))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        cells = max(2, int(scale * 2 ** o))
        g = r.random((cells, cells))
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)
        # tileable: la grilla se repite al envolver porque se re-muestrea con wrap
        a = np.asarray(img, dtype=np.float64) / 255.0
        a = (a + np.roll(a, size // 2, axis=0) + np.roll(a, size // 2, axis=1) + np.roll(np.roll(a, size // 2, 0), size // 2, 1)) / 4
        acc += a * amp
        tot += amp
        amp *= 0.5
    acc /= tot
    return (acc - acc.min()) / (acc.max() - acc.min() + 1e-9)


def save(name, arr, mode="RGB"):
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode).save(os.path.join(OUT, name), optimize=True)


# --- hormigón de pared (manchas, poros, juntas de encofrado) ---
n1 = tile_noise(N, 4, 6, 1)
n2 = tile_noise(N, 24, 3, 2)
base = 0.42 + 0.22 * n1 + 0.10 * (n2 - 0.5)
stain = np.clip((tile_noise(N, 3, 4, 3) - 0.6) * 2.5, 0, 1)
base -= stain * 0.18
rgb = np.stack([base * 1.0, base * 0.98, base * 0.95], -1) * 255
rgb[::128, :, :] *= 0.55          # juntas de encofrado
rgb[:, ::256, :] *= 0.65
save("concrete.png", rgb)

# --- chapa de piso antideslizante (diamantes) ---
y, x = np.mgrid[0:N, 0:N]
d = ((x + y) % 32 < 3) & ((x // 32 + y // 32) % 2 == 0)
d2 = ((x - y) % 32 < 3) & ((x // 32 + y // 32) % 2 == 1)
m = 0.38 + 0.12 * tile_noise(N, 8, 4, 4)
m = m + (d | d2) * 0.16
rust = np.clip((tile_noise(N, 5, 5, 5) - 0.62) * 3, 0, 1)
rgb = np.stack([m + rust * 0.25, m + rust * 0.08, m - rust * 0.05], -1) * 255
save("floor_plate.png", rgb)

# --- rejilla metálica (con transparencia) ---
img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
dr = ImageDraw.Draw(img)
for i in range(0, N, 32):
    dr.rectangle([i, 0, i + 5, N], fill=(70, 72, 74, 255))
    dr.rectangle([0, i, N, i + 3], fill=(58, 60, 62, 255))
img.save(os.path.join(OUT, "grating.png"))

# --- panel metálico oxidado (paredes de taller) ---
p = 0.30 + 0.12 * tile_noise(N, 6, 5, 6)
rust = np.clip((tile_noise(N, 4, 6, 7) - 0.55) * 2.2, 0, 1)
rgb = np.stack([p + rust * 0.30, p + rust * 0.12, p + 0.02 - rust * 0.04], -1) * 255
rgb[:, ::128, :] *= 0.5
rgb[::256, :, :] *= 0.5
for yy in range(8, N, 128):         # remaches
    for xx in range(8, N, 32):
        rgb[yy - 2:yy + 2, xx - 2:xx + 2] = 150
save("metal_panel.png", rgb)

# --- franjas de peligro ---
st = (((x + y) // 48) % 2 == 0)
rgb = np.where(st[..., None], np.array([214, 168, 32]), np.array([24, 24, 24])).astype(np.float64)
rgb *= (0.8 + 0.2 * tile_noise(N, 10, 3, 8))[..., None]
save("hazard.png", rgb)

# --- fachada lejana (fondo 2D: estructura con ventanas encendidas) ---
W, H = 1024, 512
bg = np.zeros((H, W, 3))
bg[:] = [12, 14, 18]
r2 = np.random.default_rng(11)
for bx in range(0, W, 64):
    for by in range(0, H, 48):
        if r2.random() < 0.35:
            c = np.array([255, 190, 110]) if r2.random() < 0.7 else np.array([120, 170, 255])
            k = 0.25 + 0.6 * r2.random()
            bg[by + 14:by + 30, bx + 10:bx + 50] = c * k
bg[::48, :, :] = [30, 32, 36]
bg[:, ::64, :] = [26, 28, 32]
im = Image.fromarray(bg.astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
im.save(os.path.join(OUT, "far_facade.png"))

# --- cielo nocturno con niebla (gradiente) ---
g = np.linspace(0, 1, 256)[:, None]
sky = np.concatenate([(8 + 20 * g) * np.ones((256, 4)), ], 1)
rgb = np.stack([8 + 22 * g, 10 + 26 * g, 16 + 34 * g], -1) * np.ones((256, 4, 1))
save("sky_grad.png", rgb)
print("texturas listas en", OUT)
