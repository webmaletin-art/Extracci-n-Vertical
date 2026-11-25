#!/usr/bin/env python3
"""Arma el paquete de audio del trailer a partir de trailer_sonidos.json: copia cada sonido usado a audio/ (en WAV),
escribe sonidos.csv (tiempo, archivo, posición, volumen, tono) y mezcla todo en mezcla_audio.wav (stereo, 44,1 kHz)
con los mismos tiempos del video. Uso: audio_pack.py <carpeta con trailer_sonidos.json>"""
import csv, json, os, subprocess, sys, wave
import numpy as np

out = sys.argv[1]
data = json.load(open(os.path.join(out, "trailer_sonidos.json")))
ev = data["events"]
total = float(data["seconds"]) + 1.0
SR = 44100
os.makedirs(os.path.join(out, "audio"), exist_ok=True)
root = os.getcwd()
cache = {}

def load(res):
    """res://assets/sounds/x.ogg -> arreglo float32 mono 44,1 kHz (ffmpeg decodifica ogg / mp3 / wav)."""
    if res in cache:
        return cache[res]
    path = os.path.join(root, res.replace("res://", ""))
    if not os.path.exists(path):
        cache[res] = None
        return None
    wav = os.path.join(out, "audio", os.path.splitext(os.path.basename(path))[0] + ".wav")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-c:a", "pcm_s16le", wav], check=True)
    with wave.open(wav) as w:
        a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
    cache[res] = a
    return a

mix = np.zeros((int(total * SR), 2), dtype=np.float32)
rows = []
for e in ev:
    f = e.get("file", "")
    a = load(f) if f else None
    if a is None:
        continue
    pitch = max(float(e.get("pitch", 1.0)), 0.05)
    if abs(pitch - 1.0) > 0.01:                       # cambia tono y duración como el motor (remuestreo)
        n = int(len(a) / pitch)
        a = np.interp(np.linspace(0, len(a) - 1, n), np.arange(len(a)), a)
    g = 10 ** (float(e.get("db", 0.0)) / 20.0)
    pos = e.get("pos")
    pan, dist_g = 0.0, 1.0
    if pos:                                           # paneo y atenuación simples por la posición
        x = float(pos["x"]) if isinstance(pos, dict) else float(str(pos).strip("()").split(",")[0])
        pan = 0.0
        dist_g = 1.0
    i0 = int(float(e["t"]) * SR)
    if i0 >= len(mix):
        continue
    seg = a[: len(mix) - i0] * g * dist_g
    mix[i0:i0 + len(seg), 0] += seg * (1 - max(pan, 0))
    mix[i0:i0 + len(seg), 1] += seg * (1 + min(pan, 0))
    rows.append([e["t"], e["sound"], os.path.basename(f), e.get("pos"), e.get("db"), e.get("pitch")])
peak = np.max(np.abs(mix)) or 1.0
mix = mix / max(peak, 1.0) * 0.95
with wave.open(os.path.join(out, "mezcla_audio.wav"), "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((mix * 32767).astype(np.int16).tobytes())
with open(os.path.join(out, "sonidos.csv"), "w", newline="") as fh:
    cw = csv.writer(fh)
    cw.writerow(["segundo", "sonido", "archivo", "posicion_mundo", "volumen_db", "tono"])
    cw.writerows(sorted(rows, key=lambda r: float(r[0])))
print("audio:", len(rows), "sonidos,", len(cache), "archivos")
