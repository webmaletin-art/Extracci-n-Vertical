#!/usr/bin/env python3
"""Arma la anatomía de rayos X del juego a partir de BodyParts3D (anatomia_por_sistemas/*.glb).

Uso: python3 tools/anatomy/build_anatomy.py <carpeta anatomia_por_sistemas> <salida assets/anatomy>

Qué hace:
  * Toma huesos, órganos, sistema nervioso (cerebro) y los vasos principales (aorta, cavas, carótidas, femorales…).
  * Reduce cada pieza con fast-simplification (de 3,1 millones a ~45 mil triángulos en total) para que se pueda mostrar
    en un teléfono durante la cámara lenta.
  * Agrupa las piezas por región anatómica («fémur izquierdo», «costillas derechas», «corazón», «hígado»…) y asigna cada
    grupo al hueso Mixamo que lo mueve (mixamorig_LeftUpLeg, mixamorig_Spine2…).
  * Guarda anatomy.glb (una malla por grupo, coordenadas de BodyParts3D: metros, Y arriba, mirando a +Z, pies en y=0)
    y anatomy.json (grupo → hueso, sistema, nombre en español, centro, segmento del brazo para re-posarlo).

Los brazos de BodyParts3D cuelgan al costado (posición anatómica) y los del esqueleto Mixamo están en T: por eso para los
grupos del brazo se guarda el segmento (hombro→codo, codo→muñeca, muñeca→punta) y el juego los alinea con el hueso.
Fuente: BodyParts3D, © The Database Center for Life Science, CC Atribución 4.0 (ver assets/anatomy/CREDITOS.md).
"""
import json
import os
import re
import sys

import fast_simplification
import numpy as np
import trimesh

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)

# sistema → (archivo, presupuesto de triángulos del sistema, mínimo por pieza). El presupuesto se reparte entre las piezas
# en proporción a la raíz cuadrada de sus triángulos: las piezas chicas no desaparecen y las grandes no se comen todo.
SYSTEMS = {
    "hueso": ("anatomia_huesos.glb", 30000, 24),
    "organo": ("anatomia_organos.glb", 10000, 16),
    "nervio": ("anatomia_nervios.glb", 5000, 16),
    "vaso": ("anatomia_vasos.glb", 6000, 12),
}
MAJOR_VESSELS = re.compile(r"aorta|vena cava|common carotid|internal jugular|subclavian|brachial artery|radial artery|"
                           r"ulnar artery|femoral (artery|vein)|popliteal|tibial artery|common iliac|external iliac|"
                           r"pulmonary trunk|pulmonary artery|coronary|renal (artery|vein)|cephalic vein|basilic vein|"
                           r"great saphenous|portal vein", re.I)
SKIP_ORGANS = re.compile(r"chamber|lens|vitreous|cornea|iris|choroid|lacrimal|ventricle$|aqueduct|central canal|"
                         r"taenia|mesentery|mesocolon|mesoappendix|ligament|gingiva|duct|tributary|habenula|"
                         r"pineal|tuber cinereum|sin nombre", re.I)

# (regex sobre el nombre, etiqueta del grupo en español). Se evalúa en orden; el lado (izq./der.) se agrega solo.
LABELS = [
    (r"mandible", "mandíbula"),
    (r"frontal bone|parietal|temporal bone|occipital bone|sphenoid|ethmoid|zygomatic|maxilla|nasal|lacrimal bone|"
     r"palatine|vomer|concha|alar cartilage|septal", "cráneo"),
    (r"hyoid|atlas|axis|cervical", "vértebras cervicales"),
    (r"thoracic vertebra", "vértebras torácicas"),
    (r"lumbar vertebra|intervertebral disk", "vértebras lumbares"),
    (r"sternum|manubrium|xiphoid", "esternón"),
    (r"\brib\b|costal cartilage", "costillas"),
    (r"clavicle", "clavícula"),
    (r"scapula", "escápula"),
    (r"humerus", "húmero"),
    (r"radius|ulna", "radio y cúbito"),
    (r"carpal|metacarpal|scaphoid|lunate|triquetral|pisiform|trapezi|trapezoid|capitate|hamate|finger|thumb", "mano"),
    (r"hip bone|sacrum|coccyx", "pelvis"),
    (r"femur", "fémur"),
    (r"patella", "rótula"),
    (r"tibia|fibula", "tibia y peroné"),
    (r"toe|metatarsal|calcaneus|talus|cuboid|cuneiform|navicular", "pie"),
    # órganos
    (r"atrium|ventricle|mitral|tricuspid|aortic valve|pulmonary valve|papillary", "corazón"),
    (r"liver|hepat", "hígado"),
    (r"gallbladder", "vesícula"),
    (r"stomach|esophagus", "estómago"),
    (r"duodenum|jejunum|ileum|ileocecal|colon|rectum|appendix", "intestinos"),
    (r"kidney|ureter|adrenal", "riñón"),
    (r"pancrea", "páncreas"),
    (r"bladder|urethra|prostate", "vejiga"),
    (r"trachea|bronch", "tráquea y bronquios"),
    (r"thymus", "timo"),
    (r"tongue|submandibular|pituitary", "boca y glándulas"),
    (r"sclera|eyeball", "ojos"),
    # sistema nervioso
    (r"cerebellum|pons|medulla|midbrain|colliculus", "cerebelo y tronco"),
    (r"gyrus|lobe|lobule|hemisphere|insula|hippocampus|capsule|hypothalamus", "cerebro"),
]


def label_for(name: str, system: str) -> str:
    base = re.sub(r"\s*\[.*\]$", "", name)
    if system == "vaso":
        return "vasos"
    for rx, lab in LABELS:
        if re.search(rx, base, re.I):
            return lab
    return {"vaso": "vasos", "organo": "órganos", "nervio": "cerebro", "hueso": "huesos"}[system]


def side_of(name: str, center: np.ndarray) -> str:
    n = name.lower()
    if n.startswith("left") or " of left" in n or "left " in n[:20]:
        return "izq"
    if n.startswith("right") or " of right" in n or "right " in n[:20]:
        return "der"
    if abs(center[0]) > 0.05:
        return "izq" if center[0] > 0 else "der"     # BodyParts3D mira a +Z: su izquierda es +X
    return ""


def load_pieces(fname):
    scene = trimesh.load(os.path.join(SRC, fname))
    out = []
    for node in scene.graph.nodes_geometry:
        tf, gname = scene.graph[node]
        g = scene.geometry[gname]
        if not isinstance(g, trimesh.Trimesh) or len(g.faces) == 0:
            continue
        v = trimesh.transformations.transform_points(g.vertices, tf)
        out.append((node, np.asarray(v, dtype=np.float32), np.asarray(g.faces, dtype=np.int64)))
    return out


def decimate(v, f, target, minimum):
    target = max(minimum, int(target))
    if len(f) <= target or len(f) < 60:
        return v, f
    red = 1.0 - target / len(f)
    try:
        v2, f2 = fast_simplification.simplify(v, f, target_reduction=red)
        if len(f2) >= 4:
            return v2.astype(np.float32), f2.astype(np.int64)
    except Exception as e:  # pieza degenerada: queda como estaba
        print("  aviso: no se pudo reducir", e)
    return v, f


# ---------- 1. piezas ----------
pieces = []   # dict(name, system, label, side, v, f)
for system, (fname, budget, minimum) in SYSTEMS.items():
    raw = []
    for name, v, f in load_pieces(fname):
        base = re.sub(r"\s*\[.*\]$", "", name)
        if system == "vaso" and not MAJOR_VESSELS.search(base):
            continue
        if system == "organo" and (SKIP_ORGANS.search(base) or re.search(r"ventricle$", base)):
            continue
        if system == "nervio" and re.search(r"ventricle|aqueduct|central canal", base, re.I):
            continue
        raw.append((name, v, f))
    # importancia: los huesos largos y el cráneo se ven grandes en la cámara lenta; falanges y costillas, menos
    def weight(name, f):
        w = np.sqrt(len(f))
        if re.search(r"femur|humerus|tibia|fibula|radius|ulna|hip bone|sacrum|mandible|frontal|parietal|occipital|"
                     r"temporal bone|clavicle|scapula|patella", name, re.I):
            w *= 5.0
        elif re.search(r"phalanx|rib|costal|carpal|tarsal|cuneiform", name, re.I):
            w *= 0.55
        return w
    wsum = sum(weight(n, f) for n, _, f in raw)
    kept = 0
    for name, v, f in raw:
        v2, f2 = decimate(v, f, budget * weight(name, f) / wsum, minimum)
        c = v2.mean(axis=0)
        pieces.append({"name": name, "system": system, "label": label_for(name, system), "side": side_of(name, c),
                       "v": v2, "f": f2, "c": c})
        kept += 1
    print(f"{system}: {kept} piezas")

# ---------- 2. marcas del esqueleto (posición anatómica) ----------
def piece_pts(rx, side):
    pts = [p["v"] for p in pieces if p["system"] == "hueso" and re.search(rx, p["name"], re.I) and p["side"] == side]
    return np.concatenate(pts) if pts else None

marks = {}
for side, sx in (("izq", "Left"), ("der", "Right")):
    hum = piece_pts(r"humerus", side)
    rad = piece_pts(r"radius|ulna", side)
    hand = piece_pts(r"carpal|metacarpal|phalanx of .*(finger|thumb)|scaphoid|lunate|capitate|hamate", side)
    fem = piece_pts(r"femur", side)
    tib = piece_pts(r"tibia", side)
    shoulder = hum[np.argmax(hum[:, 1])]
    elbow = hum[np.argmin(hum[:, 1])]
    wrist = rad[np.argmin(rad[:, 1])]
    tip = hand[np.argmin(hand[:, 1])]
    marks[sx] = {"shoulder": shoulder, "elbow": elbow, "wrist": wrist, "tip": tip,
                 "hip": fem[np.argmax(fem[:, 1])], "knee": fem[np.argmin(fem[:, 1])], "ankle": tib[np.argmin(tib[:, 1])]}
    print(side, {k: np.round(v, 3).tolist() for k, v in marks[sx].items()})

knee_y = (marks["Left"]["knee"][1] + marks["Right"]["knee"][1]) / 2
hip_y = (marks["Left"]["hip"][1] + marks["Right"]["hip"][1]) / 2
ankle_y = (marks["Left"]["ankle"][1] + marks["Right"]["ankle"][1]) / 2
sh_y = (marks["Left"]["shoulder"][1] + marks["Right"]["shoulder"][1]) / 2
sh_x = min(abs(marks["Left"]["shoulder"][0]), abs(marks["Right"]["shoulder"][0]))


# ---------- 3. hueso Mixamo de cada pieza ----------
def bone_for(p):
    c, lab = p["c"], p["label"]
    sx = "Left" if c[0] > 0 else "Right"
    m = marks[sx]
    x, y = c[0], c[1]
    in_arm = abs(x) > sh_x - 0.02 and y < m["shoulder"][1] + 0.02 and y > m["tip"][1] - 0.02 and lab not in (
        "clavícula", "escápula", "costillas", "pelvis", "fémur")
    if lab in ("húmero", "radio y cúbito", "mano") or (p["system"] == "vaso" and in_arm and abs(x) > sh_x + 0.02):
        if y > m["elbow"][1]:
            return f"mixamorig_{sx}Arm", "upper"
        if y > m["wrist"][1]:
            return f"mixamorig_{sx}ForeArm", "fore"
        return f"mixamorig_{sx}Hand", "hand"
    if lab in ("fémur", "rótula", "tibia y peroné", "pie") or (y < hip_y - 0.05 and abs(x) > 0.03):
        if y > knee_y + (0.0 if lab != "rótula" else 0.1):
            return f"mixamorig_{sx}UpLeg", ""
        if y > ankle_y + 0.03 or lab == "tibia y peroné":
            return f"mixamorig_{sx}Leg", ""
        return f"mixamorig_{sx}Foot", ""
    if lab == "pelvis":
        return "mixamorig_Hips", ""
    if lab == "vértebras lumbares":
        return "mixamorig_Spine", ""
    if lab in ("clavícula", "escápula"):
        return f"mixamorig_{sx}Shoulder", ""
    if lab in ("cráneo", "mandíbula", "cerebro", "cerebelo y tronco", "ojos", "boca y glándulas") or y > sh_y + 0.12:
        return "mixamorig_Head", ""
    if y > sh_y + 0.02 or lab == "vértebras cervicales":
        return "mixamorig_Neck", ""
    if y > sh_y - 0.22:
        return "mixamorig_Spine2", ""
    if y > hip_y + 0.12:
        return "mixamorig_Spine1", ""
    if y > hip_y:
        return "mixamorig_Spine", ""
    return "mixamorig_Hips", ""


groups = {}
for p in pieces:
    bone, seg = bone_for(p)
    key = (p["label"] + (" " + p["side"] if p["side"] and p["label"] not in ("cráneo", "cerebro", "corazón", "hígado",
           "estómago", "intestinos", "páncreas", "vejiga", "esternón", "tráquea y bronquios", "timo", "pelvis",
           "mandíbula", "vértebras cervicales", "vértebras torácicas", "vértebras lumbares", "cerebelo y tronco",
           "boca y glándulas", "ojos") else ""), bone)
    g = groups.setdefault(key, {"label": key[0], "bone": bone, "seg": seg, "system": p["system"], "v": [], "f": [], "n": 0,
                                "parts": []})
    g["f"].append(p["f"] + g["n"])
    g["v"].append(p["v"])
    g["n"] += len(p["v"])
    g["parts"].append(re.sub(r"\s*\[.*\]$", "", p["name"]))

# ---------- 4. GLB + JSON ----------
COLORS = {"hueso": [0.93, 0.89, 0.78, 1], "organo": [0.78, 0.22, 0.24, 1], "nervio": [0.92, 0.62, 0.66, 1],
          "vaso": [0.75, 0.08, 0.1, 1]}
scene = trimesh.Scene()
meta = {"source": "BodyParts3D (DBCLS), CC BY 4.0", "height": 1.72, "marks": {}, "groups": []}
for sx in marks:
    meta["marks"][sx] = {k: [round(float(a), 4) for a in v] for k, v in marks[sx].items()}
total = 0
for i, ((label, bone), g) in enumerate(sorted(groups.items(), key=lambda kv: kv[0][1] + kv[0][0])):
    v = np.concatenate(g["v"])
    f = np.concatenate(g["f"])
    if g["system"] == "vaso" and len(f) < 30:
        continue
    mesh = trimesh.Trimesh(vertices=v, faces=f, process=True)
    mesh.visual = trimesh.visual.ColorVisuals(mesh, face_colors=np.tile(np.array(COLORS[g["system"]]) * 255, (len(mesh.faces), 1)).astype(np.uint8))
    node = f"g{i:03d}"
    scene.add_geometry(mesh, node_name=node, geom_name=node)
    total += len(mesh.faces)
    c = mesh.bounds.mean(axis=0)
    meta["groups"].append({"node": node, "label": label, "bone": bone, "system": g["system"], "seg": g["seg"],
                           "center": [round(float(a), 4) for a in c], "radius": round(float(np.linalg.norm(mesh.extents) / 2), 4),
                           "tris": int(len(mesh.faces)), "parts": g["parts"][:40]})
scene.export(os.path.join(OUT, "anatomy.glb"))
json.dump(meta, open(os.path.join(OUT, "anatomy.json"), "w"), ensure_ascii=False, indent=1)
print("grupos:", len(meta["groups"]), "triángulos:", total)
