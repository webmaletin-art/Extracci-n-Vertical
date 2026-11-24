#!/usr/bin/env python3
"""Genera los efectos que faltan con la API de efectos de sonido de ElevenLabs.

Uso: python3 tools/sfx/elevenlabs_sfx.py [nombre ...]   (sin nombres: genera todos los que no existan)
La clave NO va en el repositorio: el entorno de la sesión la inyecta (o se usa la variable ELEVENLABS_API_KEY).
Cada generación queda anotada en docs/audio/elevenlabs_ledger.jsonl (nombre, duración, texto, créditos antes/después).
"""
import json, os, sys, time, urllib.error, urllib.request

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "sounds")
LEDGER = os.path.join(ROOT, "docs", "audio", "elevenlabs_ledger.jsonl")
KEY = os.environ.get("ELEVENLABS_API_KEY", "x")   # el proxy de la sesión reemplaza el valor
API = "https://api.elevenlabs.io/v1"

# nombre: (segundos, texto)
SOUNDS = {
    "punch_0": (0.8, "Hard bare-knuckle punch hitting a face, close-up realistic body impact, short meaty thud with slight slap, no music"),
    "punch_1": (0.7, "Heavy punch to the stomach, dull body blow thud with cloth rustle, realistic close foley, no music"),
    "kick_0": (0.8, "Powerful boot kick hitting a person's torso, deep heavy thump with gear rattle, realistic foley, no music"),
    "kick_1": (0.8, "Combat kick impact to the ribs, heavy thud and grunt-less body hit, tactical vest rattle, no music"),
    "swing": (0.5, "Fast arm swing whoosh through the air, short punch whoosh, close, no music"),
    "knife_stab": (0.8, "Combat knife stab into flesh through clothing, wet sharp puncture, realistic gritty foley, no music"),
    "knife_insert": (0.9, "Steel knife blade being wedged into the gap of a wooden crate lid, metal scraping on wood, quiet, close, no music"),
    "metal_scrape": (1.0, "Knife blade scraping and prying a metal case latch, short creepy metallic scratch, survival horror style, no music"),
    "wood_creak": (1.0, "Wooden crate lid creaking under pressure as it is pried open, slow tense creak, no music"),
    "lock_rattle": (0.7, "Small metal padlock and latch rattling while being forced, close quiet clicks, no music"),
    "lock_open": (0.7, "Metal latch snapping open with a satisfying clack, case lock released, no music"),
    "lid_open": (1.0, "Heavy lid of a supply crate being lifted open, wood and hinge creak with dust, no music"),
    "wood_crack": (0.6, "Wooden crate cracking from a bullet impact, splintering crack, no music"),
    "wood_break": (1.2, "Wooden crate smashing apart into splinters and planks falling on concrete, no music"),
    "glass_crack": (0.6, "Thick glass panel cracking from impact, sharp spiderweb crack, no music"),
    "glass_break": (1.5, "Large glass window shattering, shards falling on a metal floor, no music"),
    "metal_fall": (1.4, "Heavy metal sheet panel tearing off and clanging onto a concrete floor, no music"),
    "ladder_step": (0.5, "Hand and boot on a steel ladder rung, short metallic clank, close, no music"),
    "elevator_start": (2.0, "Industrial freight elevator motor starting with a heavy clunk and rising electric hum, no music"),
    "elevator_hum": (1.0, "Steady industrial elevator motor and cable hum while moving, mechanical rattle, no music"),
    "elevator_stop": (1.5, "Industrial elevator stopping with a heavy metal clank and brake hiss, no music"),
    "button": (0.5, "Industrial push button press, chunky plastic click with small beep, no music"),
    "denied": (0.6, "Security keycard reader access denied error buzz, two short low beeps, no music"),
    "flashbang": (1.5, "Stun grenade flashbang detonation, extremely loud sharp bang followed by high pitched tinnitus ringing, no music"),
    "smoke_hiss": (2.0, "Smoke grenade ignition and continuous gas hissing, no music"),
    "fire_loop": (3.0, "Burning fire on the floor, crackling flames, steady loopable, no music"),
    "steam_burst": (1.2, "Pressurized steam pipe burst, sudden loud hiss, industrial, no music"),
    "heartbeat": (1.5, "Slow heavy heartbeat in slow motion, deep cinematic thumps, no music"),
    "bullet_whoosh": (1.5, "Cinematic slow motion bullet flying past, deep stretched whoosh with air ripple, no music"),
}

def _open(req, timeout=120):
    """Reintenta ante 429 (límite de pedidos) con espera creciente."""
    for i in range(6):
        try:
            return urllib.request.urlopen(req, timeout=timeout)
        except urllib.error.HTTPError as e:
            if e.code != 429 or i == 5:
                raise
            time.sleep(4 * (i + 1))

def credits():
    r = urllib.request.Request(API + "/user/subscription", headers={"xi-api-key": KEY})
    return json.load(_open(r))["character_count"]

def gen(name, secs, text):
    body = json.dumps({"text": text, "duration_seconds": secs, "prompt_influence": 0.6}).encode()
    r = urllib.request.Request(API + "/sound-generation?output_format=mp3_44100_128", data=body, method="POST",
                               headers={"xi-api-key": KEY, "Content-Type": "application/json"})
    data = _open(r).read()
    with open(os.path.join(OUT, name + ".mp3"), "wb") as f:
        f.write(data)
    return len(data)

def main():
    names = sys.argv[1:] or [n for n in SOUNDS if not any(os.path.exists(os.path.join(OUT, n + e)) for e in (".mp3", ".ogg", ".wav"))]
    os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
    for n in names:
        secs, text = SOUNDS[n]
        c0 = credits()
        size = gen(n, secs, text)
        time.sleep(3.0)
        c1 = credits()
        entry = {"t": time.strftime("%Y-%m-%dT%H:%M:%S"), "name": n, "seconds": secs, "text": text, "bytes": size, "credits_before": c0, "credits_after": c1}
        open(LEDGER, "a").write(json.dumps(entry, ensure_ascii=False) + "\n")
        print(f"{n}: {size} bytes, créditos {c0} → {c1}")

if __name__ == "__main__":
    main()
