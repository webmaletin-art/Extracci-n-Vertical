#!/usr/bin/env python3
"""Munición por calibre y por tipo (estándar, punta hueca, trazante, perforante). Escribe data/ammo.json (dimensiones reales
del cartucho, multiplicadores por tipo, precio por caja) y actualiza los objetos de botín `ammo_<calibre>_<tipo>` en
data/items.json y data/loot_tables.json. Los modelos 3D se hacen con Blender: tools/ammo/make_cartridges.py.
Uso: python3 tools/ammo/gen_ammo.py   (después de tools/weapons/gen_roster.py)

Los precios suben con el poder: la perforante cuesta ×3, la punta hueca ×2,2 y la trazante ×1,5 que la estándar."""
import json, os
R = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# calibre (clave de gen_roster) → nombre, energía J, largo vaina, diámetro base, diámetro cuello, largo total, diámetro bala (mm), forma, rimmed, cartuchos por caja
CAL = {
 "380":    (".380 ACP",     300, 17.3, 9.5, 9.3, 24.4, 9.0, "straight", False, 24),
 "9x19":   ("9×19 mm",      500, 19.2, 9.9, 9.7, 29.7, 9.0, "straight", False, 30),
 "40sw":   (".40 S&W",      650, 21.6, 10.8, 10.6, 28.8, 10.2, "straight", False, 24),
 "45acp":  (".45 ACP",      520, 22.8, 12.1, 11.9, 32.4, 11.5, "straight", False, 24),
 "38sp":   (".38 Special",  350, 29.3, 9.6, 9.6, 38.9, 9.0, "straight", True, 12),
 "357":    (".357 Magnum",  800, 33.0, 9.6, 9.6, 40.6, 9.1, "straight", True, 12),
 "44mag":  (".44 Magnum",  1600, 32.6, 11.7, 11.7, 41.0, 10.9, "straight", True, 12),
 "454":    (".454 Casull", 2600, 35.6, 12.0, 12.0, 43.2, 11.5, "straight", True, 10),
 "50ae":   (".50 AE",      1900, 32.6, 14.0, 13.5, 40.6, 12.7, "straight", False, 10),
 "46x30":  ("4,6×30 mm",    450, 30.0, 7.9, 6.2, 38.0, 4.65, "bottle", False, 40),
 "57x28":  ("5,7×28 mm",    500, 28.9, 7.9, 6.4, 40.5, 5.7, "bottle", False, 50),
 "556":    ("5,56×45 mm",  1700, 44.5, 9.6, 6.4, 57.4, 5.7, "bottle", False, 30),
 "762x39": ("7,62×39 mm",  2000, 38.7, 11.3, 8.6, 56.0, 7.9, "bottle", False, 30),
 "762x51": ("7,62×51 mm",  3400, 51.2, 11.9, 8.6, 69.9, 7.8, "bottle", False, 20),
 "308":    (".308 Win",    3400, 51.2, 11.9, 8.6, 69.9, 7.8, "bottle", False, 20),
 "300wm":  (".300 Win Mag", 4000, 66.8, 13.0, 8.9, 84.8, 7.8, "bottle", False, 10),
 "338":    (".338 Lapua",  6000, 69.2, 14.9, 9.4, 93.5, 8.6, "bottle", False, 10),
 "50bmg":  (".50 BMG",    17000, 99.1, 20.4, 14.2, 138.8, 12.95, "bottle", False, 5),
 "12ga":   ("12 ga",       2000, 70.0, 21.3, 21.3, 76.0, 18.5, "shell", False, 10),
}
# tipo → nombre, daño, penetración, rebote, velocidad, dispersión, ruido (+m), precio ×, descripción
TYPES = {
 "std": ("Estándar (FMJ)",   1.00, 1.00, 1.00, 1.00, 1.00, 0, 1.0, "Camisa completa: equilibrada y barata."),
 "hp":  ("Punta hueca",      1.30, 0.45, 0.50, 0.97, 1.00, 0, 2.2, "Se abre al impactar: más daño y más sangre, atraviesa poco."),
 "tr":  ("Trazante",         1.00, 1.00, 1.20, 1.00, 0.95, 2, 1.5, "Deja una estela luminosa: se ve adónde van los tiros."),
 "ap":  ("Perforante",       1.12, 2.60, 0.60, 1.06, 0.90, 2, 3.0, "Núcleo de acero: atraviesa paredes y coberturas."),
}
# escopetas: los tipos cambian de sentido (postas / balón / balón perforante / incendiaria)
SHOTGUN = {
 "std": ("Postas",            1.00, 1.00, 1.00, 1.00, 1.00, 0, 1.0, "8-9 perdigones: devastadora de cerca."),
 "hp":  ("Balón (slug)",      5.00, 1.40, 0.60, 1.20, 0.25, 0, 2.2, "Un solo proyectil pesado: mucho daño y más alcance."),
 "tr":  ("Incendiaria",       0.85, 0.80, 0.80, 0.95, 1.10, 4, 1.8, "Perdigones incandescentes: se ven y encienden."),
 "ap":  ("Balón perforante",  4.50, 3.50, 0.50, 1.30, 0.22, 2, 3.0, "Dardo de acero: atraviesa casi todo."),
}
def base_price(energy):
    return max(1.0, energy ** 0.62 / 18.0)

def main():
    ammo = {"_doc": "Municiones. calibres: dimensiones reales en mm; tipos: multiplicadores contra la munición estándar; items: <calibre>_<tipo> con precio por caja. Generado por tools/ammo/gen_ammo.py",
            "types": {k: {"name": v[0], "dmg": v[1], "pen": v[2], "ric": v[3], "speed": v[4], "spread": v[5], "noise": v[6], "price": v[7], "text": v[8]} for k, v in TYPES.items()},
            "shotgun_types": {k: {"name": v[0], "dmg": v[1], "pen": v[2], "ric": v[3], "speed": v[4], "spread": v[5], "noise": v[6], "price": v[7], "text": v[8]} for k, v in SHOTGUN.items()},
            "calibers": {}, "items": {}}
    w = json.load(open(R + "/data/weapons.json"))
    by_name = {}
    for k, v in w.items():
        if not k.startswith("_"):
            by_name.setdefault(v.get("caliber", ""), []).append(k)
    for key, c in CAL.items():
        name, energy, clen, dbase, dneck, oal, dbul, shape, rim, box = c
        wl = by_name.get(name if name != "12 ga" else "12 ga postas", [])
        ammo["calibers"][key] = {"name": name, "energy": energy, "case_len": clen, "d_base": dbase, "d_neck": dneck, "oal": oal, "d_bullet": dbul,
                                 "shape": shape, "rimmed": rim, "box": box, "round_price": round(base_price(energy), 2), "weapons": wl}
        table = SHOTGUN if shape == "shell" else TYPES
        for t, v in table.items():
            ammo["items"]["%s_%s" % (key, t)] = {"caliber": key, "type": t, "name": "%s · %s" % (name, v[0]), "box": box,
                "price": int(round(base_price(energy) * box * v[7] / 5.0)) * 5, "weapons": wl}
    json.dump(ammo, open(R + "/data/ammo.json", "w"), indent=1, ensure_ascii=False)
    # --- objetos de botín: una caja por calibre y tipo
    it = json.load(open(R + "/data/items.json"))
    for k in [k for k in it if k.startswith("ammo_")]:
        it.pop(k)
    for iid, a in ammo["items"].items():
        c = ammo["calibers"][a["caliber"]]
        it["ammo_" + iid] = {"name": "Munición " + a["name"], "type": "municion", "value": max(3, a["price"] // 4), "amount": a["box"],
                             "ammo_for": a["weapons"], "caliber": a["caliber"], "ammo_type": a["type"], "icon": "ammo_9mm_common"}
    json.dump(it, open(R + "/data/items.json", "w"), indent=1, ensure_ascii=False)
    # --- botín: estándar frecuente; especiales raras (más raras cuanto más poderosas)
    lt = json.load(open(R + "/data/loot_tables.json"))
    common = ["9x19", "556", "12ga", "45acp"]
    for name, tbl in lt.items():
        if name.startswith("_") or not isinstance(tbl, dict):
            continue
        items = [x for x in tbl["items"] if not x[0].startswith("ammo_")]
        if name in ("crate_wood", "crate_metal"):
            for c in common:
                items.append(["ammo_%s_std" % c, 12, 1, 1])
            items += [["ammo_9x19_hp", 4, 1, 1], ["ammo_556_tr", 3, 1, 1]]
        if name == "crate_metal":
            items += [["ammo_556_ap", 2, 1, 1], ["ammo_762x51_std", 4, 1, 1]]
        if name == "lab_case":
            items += [["ammo_338_std", 8, 1, 1], ["ammo_338_ap", 3, 1, 1], ["ammo_762x51_ap", 3, 1, 1], ["ammo_50bmg_std", 3, 1, 1]]
        if name == "suitcase":
            items += [["ammo_45acp_hp", 5, 1, 1], ["ammo_9x19_ap", 3, 1, 1]]
        tbl["items"] = items
    json.dump(lt, open(R + "/data/loot_tables.json", "w"), indent=1, ensure_ascii=False)
    print("calibres", len(ammo["calibers"]), "· objetos de munición", len(ammo["items"]))

if __name__ == "__main__":
    main()
