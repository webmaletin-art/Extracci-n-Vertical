#!/usr/bin/env python3
"""Arma el catálogo de armas: las 40 del pack Quaternius (clasificadas por tipo, con calibre y características reales
simuladas) + los datos de calibre de las 21 anteriores. Escribe data/weapons.json, data/items.json (armas para vender y
munición por calibre), data/loot_tables.json y docs/ARMAS.md. Los modelos se convierten con convert_fbx.py (ROSTER=roster.json).

Uso:  python3 tools/weapons/gen_roster.py --write        (actualiza data/ y docs/)
      python3 tools/weapons/gen_roster.py --convert-list /tmp/roster_convert.json   (lista para convert_fbx.py)

DAÑO POR CALIBRE (valor de juego por bala, sobre 100 de vida) y ENERGÍA EN BOCA aproximada (J), de fuentes públicas:
  9×19 ≈ 500 J · .40 S&W ≈ 650 · .45 ACP ≈ 520 · .357 Mag ≈ 800 · .44 Mag ≈ 1 600 · .454 Casull ≈ 2 600 · .50 AE ≈ 1 900 ·
  4,6×30 ≈ 450 · 5,7×28 ≈ 500 · 5,56 NATO ≈ 1 700 · 7,62×39 ≈ 2 000 · 7,62×51 ≈ 3 400 · .300 WM ≈ 4 000 ·
  .338 Lapua ≈ 6 000 · .50 BMG ≈ 17 000 · 12 ga postas ≈ 2 000 repartidos en 8-9 perdigones.
CADENCIA = disparos por minuto reales del tipo de arma (revólver 90-150, pistola 300, subfusil 600-1 200, fusil 600-850,
corredera 70, cerrojo 35-45, semiautomático de precisión 140-240)."""
import json, os, sys, glob
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
R = os.path.abspath(R)

# calibre: nombre, energía (J), daño, penetración (cm de madera), rebote, velocidad de juego (m/s), ruido base (m)
CAL = {
    "9x19":   ("9×19 mm",        500, 24, 2.0, 0.30, 255, 28),
    "40sw":   (".40 S&W",        650, 27, 3.0, 0.28, 260, 30),
    "45acp":  (".45 ACP",        520, 31, 2.5, 0.30, 245, 30),
    "380":    (".380 ACP",       300, 19, 1.5, 0.32, 230, 24),
    "357":    (".357 Magnum",    800, 38, 4.0, 0.25, 290, 38),
    "38sp":   (".38 Special",    350, 22, 1.8, 0.30, 240, 30),
    "44mag":  (".44 Magnum",    1600, 50, 6.0, 0.22, 330, 42),
    "454":    (".454 Casull",   2600, 60, 7.0, 0.20, 360, 46),
    "50ae":   (".50 AE",        1900, 52, 6.0, 0.25, 300, 40),
    "46x30":  ("4,6×30 mm",      450, 22, 5.0, 0.30, 330, 28),
    "57x28":  ("5,7×28 mm",      500, 20, 5.0, 0.30, 340, 28),
    "556":    ("5,56×45 mm",    1700, 30, 6.0, 0.25, 340, 38),
    "762x39": ("7,62×39 mm",    2000, 38, 7.0, 0.22, 330, 40),
    "762x51": ("7,62×51 mm",    3400, 48, 9.0, 0.18, 420, 44),
    "308":    (".308 Win",      3400, 62, 10.0, 0.15, 450, 48),
    "300wm":  (".300 Win Mag",  4000, 72, 11.0, 0.14, 480, 52),
    "338":    (".338 Lapua",    6000, 90, 14.0, 0.10, 520, 60),
    "50bmg":  (".50 BMG",      17000, 130, 25.0, 0.08, 560, 72),
    "12ga":   ("12 ga postas",  2000, 14, 1.0, 0.15, 200, 44),
}

# id, fbx, nombre, clase, calibre, largo real (m), rpm, auto, cargador, recarga (s), alcance (m), dispersión (°), retroceso (°), perdigones, daño propio (opcional)
Q = [
 # --- Pistolas (semiautomáticas)
 ("pistol_5", "Pistol_5", "Pistola subcompacta .380",       "pistol", "380",   0.17, 320,  False, 10, 1.6, 18, 3.2, 2.2, 1),
 ("pistol_1", "Pistol_1", "Pistola compacta 9 mm",          "pistol", "9x19",  0.20, 330,  False, 15, 1.6, 25, 2.6, 2.4, 1),
 ("pistol_2", "Pistol_2", "Pistola de servicio 9 mm",       "pistol", "9x19",  0.20, 340,  False, 17, 1.7, 28, 2.2, 2.5, 1),
 ("pistol_3", "Pistol_3", "Pistola .40 S&W",                "pistol", "40sw",  0.21, 320,  False, 14, 1.7, 30, 2.3, 2.9, 1),
 ("pistol_4", "Pistol_4", "Pistola .45 ACP de doble pila",  "pistol", "45acp", 0.23, 300,  False, 13, 1.8, 30, 2.1, 3.1, 1),
 ("pistol_6", "Pistol_6", "Pistola de cañón largo .357",    "pistol", "357",   0.30, 240,  False,  9, 2.0, 50, 1.4, 4.4, 1),
 # --- Revólveres
 ("revolver_4", "Revolver_4", "Revólver .38 Special (2\")", "pistol", "38sp",  0.17, 150,  False, 5, 3.0, 20, 3.4, 2.8, 1),
 ("revolver_1", "Revolver_1", "Revólver .357 Magnum (4\")", "pistol", "357",   0.24, 150,  False, 6, 3.2, 35, 2.4, 4.4, 1),
 ("revolver_2", "Revolver_2", "Revólver .357 Magnum (6\")", "pistol", "357",   0.28, 140,  False, 6, 3.2, 48, 1.8, 4.2, 1),
 ("revolver_3", "Revolver_3", "Revólver .44 Magnum",        "pistol", "44mag", 0.30, 110,  False, 6, 3.4, 50, 2.0, 6.2, 1),
 ("revolver_5", "Revolver_5", "Revólver .454 Casull",       "pistol", "454",   0.33, 90,   False, 5, 3.6, 55, 2.2, 8.0, 1),
 # --- Subfusiles
 ("smg_4", "SubmachineGun_4", "Pistola ametralladora 9 mm", "smg", "9x19",  0.33, 1000, True, 32, 2.0, 25, 3.2, 1.6, 1),
 ("smg_1", "SubmachineGun_1", "Subfusil compacto 9 mm",     "smg", "9x19",  0.36, 800,  True, 30, 2.0, 32, 2.6, 1.2, 1),
 ("smg_3", "SubmachineGun_3", "Subfusil 9 mm",              "smg", "9x19",  0.52, 650,  True, 30, 2.1, 42, 2.0, 1.0, 1),
 ("smg_2", "SubmachineGun_2", "Subfusil .45 ACP",           "smg", "45acp", 0.55, 700,  True, 25, 2.2, 38, 2.2, 1.4, 1),
 ("smg_5", "SubmachineGun_5", "Subfusil largo 5,7×28 (PDW)", "smg", "57x28", 0.65, 900, True, 50, 2.4, 50, 1.8, 0.8, 1),
 # --- Fusiles de asalto y carabinas
 ("ar_1",   "AssaultRifle_1",  "Carabina compacta 5,56",    "rifle", "556",   0.55, 850, True, 30, 2.1, 50, 2.6, 1.8, 1),
 ("ar2_4",  "AssaultRifle2_4", "Subcarabina 5,56",          "rifle", "556",   0.56, 800, True, 30, 2.1, 55, 2.4, 1.7, 1),
 ("ar_3",   "AssaultRifle_3",  "Carabina 5,56",             "rifle", "556",   0.62, 800, True, 30, 2.2, 60, 2.0, 1.4, 1),
 ("ar2_3",  "AssaultRifle2_3", "Carabina 7,62×39",          "rifle", "762x39", 0.68, 650, True, 30, 2.3, 65, 2.2, 2.2, 1),
 ("ar2_2",  "AssaultRifle2_2", "Fusil 5,56 ligero",         "rifle", "556",   0.86, 750, True, 30, 2.3, 85, 1.4, 1.3, 1),
 ("ar_2",   "AssaultRifle_2",  "Fusil de asalto 5,56",      "rifle", "556",   0.97, 700, True, 30, 2.3, 90, 1.2, 1.3, 1),
 ("ar_5",   "AssaultRifle_5",  "Fusil de asalto 7,62×39",   "rifle", "762x39", 0.97, 600, True, 30, 2.4, 85, 1.9, 2.3, 1),
 ("ar2_1",  "AssaultRifle2_1", "Fusil de combate 7,62×51",  "rifle", "762x51", 0.99, 600, True, 20, 2.6, 110, 1.4, 2.8, 1),
 ("ar_4",   "AssaultRifle_4",  "Fusil de combate pesado 7,62×51", "rifle", "762x51", 1.0, 520, True, 20, 2.7, 120, 1.2, 3.2, 1),
 # --- Bullpup
 ("bullpup_2", "Bullpup_2", "Bullpup compacto 5,56",        "rifle", "556",   0.62, 900, True, 30, 2.2, 60, 2.2, 1.5, 1),
 ("bullpup_3", "Bullpup_3", "Bullpup 5,56",                 "rifle", "556",   0.70, 800, True, 30, 2.3, 80, 1.5, 1.4, 1),
 ("bullpup_1", "Bullpup_1", "Bullpup largo 5,56",           "rifle", "556",   0.76, 700, True, 30, 2.4, 95, 1.1, 1.2, 1),
 # --- Escopetas
 ("shotgun_sawed", "Shotgun_SawedOff", "Escopeta recortada de 2 cañones", "shotgun", "12ga", 0.55, 120, False, 2, 2.4, 8, 9.0, 9.0, 12),
 ("shotgun_short", "Shotgun_ShortStock", "Escopeta de corredera culata corta", "shotgun", "12ga", 0.85, 70, False, 5, 3.0, 12, 7.5, 6.5, 8),
 ("shotgun_1", "Shotgun_1", "Escopeta de corredera 12",     "shotgun", "12ga", 1.00, 70,  False, 6, 3.0, 15, 6.5, 6.0, 8),
 ("shotgun_2", "Shotgun_2", "Escopeta táctica de 8 cartuchos", "shotgun", "12ga", 1.10, 75, False, 8, 3.4, 16, 6.0, 5.6, 8),
 ("shotgun_3", "Shotgun_3", "Escopeta semiautomática",     "shotgun", "12ga", 1.10, 200, False, 6, 3.2, 15, 6.8, 6.4, 8),
 ("shotgun_4", "Shotgun_4", "Escopeta de caza",            "shotgun", "12ga", 1.05, 65,  False, 5, 3.0, 25, 4.2, 6.2, 9),
 # --- Francotiradores y tiradores
 ("sniper_6", "SniperRifle_6", "Fusil de precisión semiautomático .308", "dmr", "308", 1.20, 140, False, 10, 2.8, 220, 0.5, 3.4, 1),
 ("sniper_3", "SniperRifle_3", "Tirador semiautomático 7,62×51", "dmr", "762x51", 1.25, 180, False, 10, 2.8, 170, 0.6, 3.2, 1),
 ("sniper_1", "SniperRifle_1", "Fusil de cerrojo .308",    "sniper", "308",  1.25, 40, False, 5, 3.3, 230, 0.30, 5.5, 1),
 ("sniper_2", "SniperRifle_2", "Fusil de cerrojo .300 Win Mag", "sniper", "300wm", 1.30, 38, False, 5, 3.4, 280, 0.28, 6.2, 1),
 ("sniper_4", "SniperRifle_4", "Fusil de cerrojo .338 Lapua", "sniper", "338", 1.15, 35, False, 5, 3.6, 330, 0.25, 7.0, 1),
 ("sniper_5", "SniperRifle_5", "Fusil antimaterial .50 BMG", "sniper", "50bmg", 1.40, 50, False, 5, 4.2, 400, 0.30, 9.5, 1),
]
# calibres de las 21 armas anteriores (sólo metadato: no se tocan sus estadísticas)
OLD_CAL = {"m1911": "45acp", "m1911_1": "45acp", "m1911t": "45acp", "deagle": "50ae", "mp7": "46x30", "p90": "57x28", "vector": "45acp",
           "mp5_1": "9x19", "mp5_2": "9x19", "cqbm4": "556", "m4a1": "556", "m4a1_1": "556", "g36c": "556", "m16": "556", "m16_1": "556",
           "m4supp": "556", "aug": "556", "scar": "556", "ak47": "762x39", "scarh": "762x51", "m4dmr": "762x51"}
SOUND = {"pistol": ("bv_pistol_shot", "bv_pistol_reload", None), "smg": ("shot_smg", "bv_rifle_reload", None),
         "rifle": ("bv_rifle_shot", "bv_rifle_reload", None), "dmr": ("bv_dmr_shot", "bv_rifle_reload", None),
         "sniper": ("bv_sniper_shot", "bv_bolt_reload", "bv_bolt_cycle"), "shotgun": ("shot_shotgun", "shell_in", "pump")}
NOISE = {"pistol": 0, "smg": -2, "rifle": 0, "dmr": 4, "sniper": 8, "shotgun": 4}
CLASSMUL = {"pistol": 0.5, "smg": 0.8, "rifle": 0.65, "dmr": 0.7, "sniper": 0.75, "shotgun": 0.7}

def tier_of(price):
    for i, lim in enumerate([300, 1000, 2200, 3600, 6000]):
        if price < lim:
            return i
    return 5

def entry(q):
    wid, fbx, name, cls, cal, length, rpm, auto, mag, reload_, rng, spread, recoil, pellets = q
    cname, energy, dmg, pen, ric, speed, noise = CAL[cal]
    d = dmg
    if cls == "shotgun":
        d = 14 if wid != "shotgun_sawed" else 14
    snd, rsnd, cyc = SOUND[cls]
    dps = d * pellets * rpm / 60.0
    metric = dps * (0.6 if pellets > 1 else 1.0) + 1.2 * d * (pellets ** 0.6)
    price = int(round(metric * (8 + rng / 12.0) * 0.6 * CLASSMUL[cls] / 50.0)) * 50
    price = max(price, 150)
    e = {"model": wid, "name": name, "class": cls, "hold": "pistol" if wid.startswith(("pistol_", "revolver_")) else "rifle",
         "caliber": cname, "mag": mag, "reserve": mag * 3, "rpm": rpm, "auto": auto, "damage": d, "pellets": pellets, "speed": speed,
         "drag": 0.05 if cls != "shotgun" else 0.5, "spread": spread, "recoil": recoil, "reload": reload_, "sound": snd, "reload_sound": rsnd,
         "noise": noise + NOISE[cls], "penetration": pen, "ricochet": ric, "price": price, "range": rng, "tier": tier_of(price)}
    if cyc:
        e["cycle_sound"] = cyc
    if cls == "sniper":
        e["scope"] = False
    return e

def derived(e):
    dps = e["damage"] * e["pellets"] * e["rpm"] / 60.0
    ttk = -(-100 // (e["damage"] * (e["pellets"] if e["pellets"] > 1 else 1)))      # tiros para 100 de vida (sin zona)
    return dps, int(ttk)

def main():
    if "--convert-list" in sys.argv:
        out = sys.argv[sys.argv.index("--convert-list") + 1]
        json.dump({q[0]: [q[1] + ".fbx", q[5], "pistol" if q[3] == "pistol" else ("smg" if q[3] == "smg" else "rifle")] for q in Q}, open(out, "w"), indent=1)
        return
    w = json.load(open(R + "/data/weapons.json"))
    for q in Q:
        w[q[0]] = entry(q)
    for k, c in OLD_CAL.items():
        if k in w:
            w[k]["caliber"] = CAL[c][0]
    # nombre claro para las anteriores y orden por clase / precio
    json.dump(w, open(R + "/data/weapons.json", "w"), indent=1, ensure_ascii=False)
    ids = [k for k in w if not k.startswith("_")]
    # --- objetos: armas para vender y munición por calibre
    it = json.load(open(R + "/data/items.json"))
    for k in list(it):
        if k.startswith("w_") and k not in ("w_mp5_1",):
            it.pop(k)
    it.pop("w_mp5_1", None)
    for k in ids:
        e = w[k]
        icon = {"pistol": "pistol", "smg": "weapon_mp5", "rifle": "weapon_mp5", "dmr": "weapon_awm", "sniper": "weapon_awm", "shotgun": "weapon_remington"}[e["class"]]
        it["w_" + k] = {"name": e["name"], "type": "arma", "value": max(50, int(round(e["price"] * 0.22 / 10.0)) * 10), "weapon": k, "icon": icon}
    groups = {}
    for k in ids:
        groups.setdefault(w[k].get("caliber", "?"), []).append(k)
    icon_for = {"12 ga postas": "ammo_shotgun_buckshot", ".338 Lapua": "ammo_127_ap", ".50 BMG": "ammo_127_ap", ".300 Win Mag": "ammo_127_ap", ".308 Win": "ammo_127_ap",
                "7,62×51 mm": "ammo_127_ap", "7,62×39 mm": "ammo_556_common", "5,56×45 mm": "ammo_556_common"}
    for k in [k for k in it if k.startswith("ammo_")]:
        it.pop(k)
    amount = {"pistol": 26, "smg": 40, "rifle": 30, "dmr": 20, "sniper": 10, "shotgun": 8}
    for cname, wl in groups.items():
        key = "ammo_" + cname.replace(" ", "").replace(",", "").replace("×", "x").replace(".", "").lower()
        cls = w[wl[0]]["class"]
        it[key] = {"name": "Munición " + cname, "type": "municion", "value": max(4, int(CAL_ENERGY(cname) ** 0.5 / 4)), "amount": amount[cls],
                   "ammo_for": wl, "icon": icon_for.get(cname, "ammo_9mm_common")}
    json.dump(it, open(R + "/data/items.json", "w"), indent=1, ensure_ascii=False)
    # --- botín: armas por nivel en cajas y maletines (para vender); munición vigente
    lt = json.load(open(R + "/data/loot_tables.json"))
    def clean(items):
        out = []
        for x in items:
            if x[0].startswith("w_") or x[0].startswith("ammo_"):
                continue
            out.append(x)
        return out
    low = [k for k in ids if w[k]["tier"] <= 1]
    mid = [k for k in ids if 2 <= w[k]["tier"] <= 3]
    high = [k for k in ids if w[k]["tier"] >= 4]
    for name, wl, wt in (("crate_wood", low, 1), ("crate_metal", low + mid, 1), ("suitcase", mid, 1), ("lab_case", mid + high, 1)):
        base = clean(lt[name]["items"])
        base += [["ammo_556x45mm", 14, 1, 2], ["ammo_9x19mm", 14, 1, 2]] if name in ("crate_wood", "crate_metal") else []
        base += [["ammo_12gapostas", 8, 1, 1]] if name in ("crate_wood", "crate_metal") else []
        base += [["ammo_338lapua", 6, 1, 2]] if name == "lab_case" else []
        for k in wl:
            base.append(["w_" + k, max(1, 6 - w[k]["tier"]), 1, 1])
        lt[name]["items"] = base
    json.dump(lt, open(R + "/data/loot_tables.json", "w"), indent=1, ensure_ascii=False)
    write_docs(w, ids)

def CAL_ENERGY(cname):
    for v in CAL.values():
        if v[0] == cname:
            return v[1]
    return 500

def write_docs(w, ids):
    cls_name = {"pistol": "Pistolas y revólveres", "smg": "Subfusiles", "rifle": "Fusiles de asalto, carabinas y bullpup", "shotgun": "Escopetas",
                "dmr": "Tiradores", "sniper": "Francotiradores"}
    s = open(R + "/docs/ARMAS.md").read()
    head = s.split("| Arma | id |")[0]
    head = head.split("**21 armas**")[0] if "**21 armas**" in head else head
    tail_idx = s.index("* **Precio 0**")
    tail = s[tail_idx:]
    out = head.rstrip() + "\n\n**%d armas** clasificadas por tipo y ordenadas por poder (precio). Las 21 primeras son las subidas del usuario; las 40 `Quaternius` son del pack *Ultimate Gun Pack* (modelos de bajo poligonaje: 700-1 900 triángulos). Calibre, cadencia, cargador y alcance simulan los reales (ver `tools/weapons/gen_roster.py`). **DPS** = daño × perdigones × disparos/min ÷ 60; **TTK** = tiros para 100 de vida (sin zonas del cuerpo; la anatomía puede matar antes).\n\n" % len(ids)
    for cls in ("pistol", "smg", "rifle", "shotgun", "dmr", "sniper"):
        rows = sorted([k for k in ids if w[k]["class"] == cls], key=lambda k: (w[k]["price"], k))
        out += "### %s (%d)\n\n| Arma | id | Calibre | Nivel | Precio | Daño | Disparos/min | DPS | TTK | Cargador | Recarga | Alcance | Dispersión | Retroceso |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n" % (cls_name[cls], len(rows))
        for k in rows:
            e = w[k]
            dps, ttk = derived(e)
            dmg = ("%d×%d" % (e["damage"], e["pellets"])) if e["pellets"] > 1 else str(e["damage"])
            out += "| %s | `%s` | %s | %d | %s CR | %s | %d | %d | %d | %d | %.1f s | %d m | %.2f° | %.1f° |\n" % (
                e["name"], k, e.get("caliber", "—"), e["tier"], format(e["price"], ",").replace(",", "."), dmg, e["rpm"], dps, ttk, e["mag"], e["reload"], e["range"], e["spread"], e["recoil"])
        out += "\n"
    open(R + "/docs/ARMAS.md", "w").write(out + tail)

if __name__ == "__main__":
    main()
