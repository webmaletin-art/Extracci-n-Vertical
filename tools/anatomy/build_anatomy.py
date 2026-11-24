#!/usr/bin/env python3
"""Reduce y agrupa la anatomía completa de Z-Anatomy para el juego.

Uso: python3 tools/anatomy/build_anatomy.py <zanat.npz de export_zanatomy.py> <carpeta salida (tools/anatomy)>

Salida: anatomy_src.glb (un nodo por grupo, coordenadas de Z-Anatomy convertidas a Godot: metros, Y arriba, mirando a +Z)
y anatomy_groups.json (grupo → sistema, nombre en español, hueso Mixamo de referencia, piezas). Después
tools/anatomy/fit_anatomy.gd ajusta esos grupos DENTRO de cada personaje y les copia los pesos de piel.
En el juego sólo se muestran los grupos dañados (rayos X localizados), por eso puede haber bastante detalle.
Fuente: Z-Anatomy (https://www.z-anatomy.com), CC BY-SA 4.0.
"""
import json
import os
import re
import sys

import fast_simplification
import numpy as np
import trimesh

SRC, OUT = sys.argv[1], sys.argv[2]
d = np.load(SRC)
names, systems = [str(x) for x in d["names"]], [str(x) for x in d["systems"]]
V, F, voff, foff = d["verts"], d["faces"], d["voff"], d["foff"]

BUDGET = {"hueso": 72000, "musculo": 40000, "organo": 16000, "vaso": 12000, "nervio": 7000, "oreja": 1600}
MIN_TRIS = {"hueso": 24, "musculo": 24, "organo": 16, "vaso": 12, "nervio": 12, "oreja": 200}


def piece(i):
    return V[voff[i]:voff[i + 1]], F[foff[i]:foff[i + 1]]


def side_of(name, c):
    if name.endswith(".l"):
        return "izq"
    if name.endswith(".r"):
        return "der"
    if abs(c[0]) > 0.04:
        return "izq" if c[0] > 0 else "der"        # mirando a +Z, la izquierda del cuerpo es +X
    return ""


def pts(rx, side):
    out = [piece(i)[0] for i, n in enumerate(names) if systems[i] == "hueso" and re.search(rx, n, re.I) and n.endswith("." + side)]
    return np.concatenate(out) if out else None


marks = {}
for side, key in (("l", "Left"), ("r", "Right")):
    hum, rad, fem, tib = pts(r"^humerus", side), pts(r"^(radius|ulna)", side), pts(r"^femur", side), pts(r"^tibia", side)
    hand = pts(r"(carpal|metacarpal|finger|thumb|scaphoid|lunate|capitate|hamate|trapezi|pisiform|triquetr)", side)
    wrist = rad[np.argmin(rad[:, 1])]
    marks[key] = {"shoulder": hum[np.argmax(hum[:, 1])], "elbow": hum[np.argmin(hum[:, 1])], "wrist": wrist,
                  "tip": hand[np.argmin(hand[:, 1])] if hand is not None else wrist - np.array([0, 0.18, 0]),
                  "hip": fem[np.argmax(fem[:, 1])], "knee": fem[np.argmin(fem[:, 1])], "ankle": tib[np.argmin(tib[:, 1])]}
L, R = marks["Left"], marks["Right"]
hip_y = (L["hip"][1] + R["hip"][1]) / 2
knee_y = (L["knee"][1] + R["knee"][1]) / 2
ankle_y = (L["ankle"][1] + R["ankle"][1]) / 2
sh_y = (L["shoulder"][1] + R["shoulder"][1]) / 2
sh_x = min(abs(L["shoulder"][0]), abs(R["shoulder"][0]))
print("marcas izq:", {k: np.round(v, 3).tolist() for k, v in L.items()})


def region(c, name, system):
    """(nombre de la región en español, hueso Mixamo) según el centro de la pieza."""
    x, y = c[0], c[1]
    key = "Left" if x > 0 else "Right"
    lado = "izq" if x > 0 else "der"
    m = marks[key]
    low = name.lower()
    if system == "hueso" and re.search(r"clavicle|scapula", low):
        return "hombro " + lado, f"mixamorig_{key}Shoulder"
    in_arm = abs(x) > sh_x - 0.01 and m["tip"][1] - 0.03 < y < m["shoulder"][1] + 0.01 and not re.search(
        r"rib|costal|pector|serratus|latissimus|trapez|rhomboid|intercostal|lung|pleura|oblique|abdomin", low)
    if in_arm:
        if y > m["elbow"][1]:
            return "brazo " + lado, f"mixamorig_{key}Arm"
        if y > m["wrist"][1]:
            return "antebrazo " + lado, f"mixamorig_{key}ForeArm"
        return "mano " + lado, f"mixamorig_{key}Hand"
    if y < hip_y - 0.06 and abs(x) > 0.02:
        if y > knee_y + 0.04:
            return "muslo " + lado, f"mixamorig_{key}UpLeg"
        if y > knee_y - 0.05:
            return "rodilla " + lado, f"mixamorig_{key}Leg"
        if y > ankle_y + 0.03:
            return "pierna " + lado, f"mixamorig_{key}Leg"
        return "pie " + lado, f"mixamorig_{key}Foot"
    if y > sh_y + 0.14:
        return "cabeza", "mixamorig_Head"
    if y > sh_y + 0.02:
        return "cuello", "mixamorig_Neck"
    if y > sh_y - 0.2:
        return "tórax", "mixamorig_Spine2"
    if y > hip_y + 0.12:
        return "abdomen", "mixamorig_Spine1"
    if y > hip_y - 0.02:
        return "abdomen bajo", "mixamorig_Spine"
    return "pelvis", "mixamorig_Hips"


BONES = [(r"^femur", "fémur"), (r"^tibia", "tibia"), (r"^fibula", "peroné"), (r"^patella", "rótula"), (r"^humerus", "húmero"),
         (r"^radius", "radio"), (r"^ulna", "cúbito"),
         (r"phalanx of .*finger of hand|phalanx of thumb|phalanx of (index|middle|ring|little) finger|of thumb", "dedos de la mano"),
         (r"carpal|scaphoid|lunate|triquetr|pisiform|trapezi|capitate|hamate|metacarpal", "huesos de la mano"),
         (r"metatarsal|calcaneus|talus|cuboid|cuneiform|navicular|toe", "huesos del pie"), (r"^hip bone|^sacrum|^coccyx", "pelvis"),
         (r"^clavicle", "clavícula"), (r"^scapula", "escápula"), (r"^mandible", "mandíbula"), (r"tooth|teeth", "dientes"),
         (r"frontal bone|parietal|temporal bone|occipital bone|sphenoid|ethmoid|zygomatic|maxilla|nasal|lacrimal|palatine|vomer|concha|skull|ossicle|malleus|incus|stapes", "cráneo"),
         (r"vertebra c|atlas|axis|hyoid", "vértebras cervicales"), (r"vertebra t", "vértebras torácicas"),
         (r"vertebra l|intervertebral", "vértebras lumbares"), (r"sternum|manubrium|xiphoid", "esternón"), (r"rib|costal", "costillas")]
ORGANS = [(r"lung|pleura|bronch", "pulmón"), (r"atrium|ventricle|leaflet|valve|papillary|heart|myocard|pericard|auricle", "corazón"),
          (r"liver|hepat|porta", "hígado"), (r"gallbladder", "vesícula"), (r"stomach", "estómago"), (r"oesophagus|esophag", "esófago"),
          (r"jejunum|ileum|duoden|colon|caecum|cecum|rectum|appendix|taenia|omentum|mesocolon|mesentery", "intestinos"),
          (r"kidney|ureter|suprarenal", "riñón"), (r"spleen", "bazo"), (r"pancrea", "páncreas"),
          (r"bladder|urethra|prostate|ductus deferens|testis|seminal", "vejiga"),
          (r"trachea|laryn|epiglottis|pharynx|cartilage", "tráquea y laringe"), (r"thyroid", "tiroides")]
NERVES = [(r"telencephalon|lobe\b|gyrus|cortex|hippocamp|thalamus|caudate|putamen|lentiform|amygdala|callosum|falx|commissure|fornix|insula|cerebral", "cerebro"),
          (r"cerebell|lobule|vermis|pons|midbrain|oblongata|peduncle", "cerebelo y tronco cerebral"),
          (r"spinal|cauda|fasciculus|tract|horn|dura|intermedi|reticul", "médula espinal"), (r"eyeball|retina|lens|cornea|sclera|optic", "ojo")]


def label(i, c):
    n = names[i]
    s = systems[i]
    reg, bone = region(c, n, s)
    lado = side_of(n, c)
    sfx = (" " + lado) if lado else ""
    if s == "hueso":
        for rx, lab in BONES:
            if re.search(rx, n, re.I):
                if lab in ("costillas", "vértebras torácicas"):
                    return f"{lab}{sfx}" + (" superiores" if bone == "mixamorig_Spine2" else " inferiores"), bone
                if lab in ("cráneo", "mandíbula", "pelvis", "esternón", "dientes") or lab.startswith("vértebras"):
                    return lab, bone
                return lab + sfx, bone
        return "huesos de " + reg, bone
    if s == "organo":
        for rx, lab in ORGANS:
            if re.search(rx, n, re.I):
                if lab in ("pulmón", "riñón"):
                    low = n.lower()
                    side = "izq" if ("left" in low or n.endswith(".l")) else "der" if ("right" in low or n.endswith(".r")) else lado
                    return f"{lab} {side}".strip(), bone
                return lab, bone
        return "órganos de " + reg, bone
    if s == "nervio":
        for rx, lab in NERVES:
            if re.search(rx, n, re.I):
                return (lab + sfx) if lab == "ojo" else lab, bone
        return "nervios de " + reg, bone
    if s == "vaso":
        if re.search(r"aorta|vena cava|pulmonary trunk|brachiocephalic", n, re.I):
            return "aorta y grandes vasos", bone
        return "arterias y venas de " + reg, bone
    if s == "oreja":
        return "oreja" + sfx, "mixamorig_Head"
    return "músculos de " + reg, bone


def weight(i, ntris):
    w = np.sqrt(ntris)
    n = names[i].lower()
    if systems[i] == "hueso" and re.search(r"frontal|parietal|occipital|temporal bone|sphenoid|maxilla|zygomatic|mandible", n):
        w *= 7.0                       # el cráneo es lo que más se ve en la cámara de muerte
    elif systems[i] == "hueso" and re.search(r"femur|tibia|fibula|humerus|radius|ulna|hip bone|sacrum|clavicle|scapula|patella|vertebra", n):
        w *= 4.0
    elif re.search(r"phalanx|tooth|malleus|incus|stapes|cartilage of", n):
        w *= 0.4
    elif systems[i] == "organo" and re.search(r"lung|liver|heart|ventricle|atrium|stomach|kidney|colon|jejunum|ileum", n):
        w *= 2.0
    return w


groups = {}
per_sys = {}
for i in range(len(names)):
    per_sys.setdefault(systems[i], []).append(i)
for s, idxs in per_sys.items():
    ws = {i: weight(i, int(foff[i + 1] - foff[i])) for i in idxs}
    tot = sum(ws.values())
    for i in idxs:
        v, f = piece(i)
        if len(f) == 0:
            continue
        if s == "nervio" and re.search(r"tract|fasciculus|horn|intermedi|reticul|nucleus|substance|commissure|process", names[i], re.I):
            continue                     # haces internos de la médula: no se ven y no se dejan reducir
        target = max(MIN_TRIS[s], int(BUDGET[s] * ws[i] / tot))
        if len(f) > target and len(f) >= 60:
            try:
                v2, f2 = fast_simplification.simplify(v, f, target_reduction=1.0 - target / len(f))
                if len(f2) >= 4:
                    v, f = v2.astype(np.float32), f2.astype(np.int64)
            except Exception:
                pass
        if len(f) > max(4 * target, 400):
            print("  omitida (no se pudo reducir):", names[i], len(f))
            continue
        lab, bone = label(i, v.mean(axis=0))
        g = groups.setdefault((s, lab), {"label": lab, "bone": bone, "system": s, "v": [], "f": [], "n": 0, "parts": []})
        g["f"].append(f + g["n"])
        g["v"].append(v)
        g["n"] += len(v)
        g["parts"].append(names[i])

COL = {"oreja": [215, 160, 140, 255], "hueso": [235, 228, 205, 255], "musculo": [170, 45, 40, 255], "organo": [190, 70, 75, 255], "vaso": [170, 15, 25, 255], "nervio": [235, 200, 120, 255]}
scene = trimesh.Scene()
meta = {"source": "Z-Anatomy (CC BY-SA 4.0)", "marks": {k: {a: [round(float(x), 4) for x in b] for a, b in m.items()} for k, m in marks.items()}, "groups": []}
total = {}
for k, ((sy, lab), g) in enumerate(sorted(groups.items(), key=lambda kv: kv[0])):
    mesh = trimesh.Trimesh(vertices=np.concatenate(g["v"]), faces=np.concatenate(g["f"]), process=True)
    mesh.merge_vertices()
    # sin color por cara (separaría los vértices y todo se vería facetado): el color lo pone el shader del juego
    node = f"g{k:03d}"
    scene.add_geometry(mesh, node_name=node, geom_name=node)
    total[sy] = total.get(sy, 0) + len(mesh.faces)
    meta["groups"].append({"node": node, "label": lab, "system": sy, "bone": g["bone"], "tris": int(len(mesh.faces)),
                           "center": [round(float(x), 4) for x in mesh.bounds.mean(axis=0)], "parts": g["parts"][:60]})
os.makedirs(OUT, exist_ok=True)
scene.export(os.path.join(OUT, "anatomy_src.glb"))
json.dump(meta, open(os.path.join(OUT, "anatomy_groups.json"), "w"), ensure_ascii=False, indent=1)
print("grupos:", len(meta["groups"]), "triángulos:", total, "total", sum(total.values()))
