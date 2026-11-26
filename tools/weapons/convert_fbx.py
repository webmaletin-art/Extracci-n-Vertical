"""Convierte armas FBX (subidas por el usuario) a GLB para el juego, con Blender (bpy).
Une las piezas, reduce las mallas muy pesadas, escala al largo REAL, orienta la boca del cañón hacia -Z (Godot) con
el arriba en +Y, y calcula los marcadores Grip (empuñadura), Support (guardamanos), Muzzle (boca) y Sight.
Uso: python3 tools/weapons/convert_fbx.py -- <carpeta FBX> <carpeta salida assets/weapons> <salida markers.json> [id ...]"""
import json
import math
import os
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, MK = argv[0], argv[1], argv[2]
# id → (archivo, largo real en m, tipo)
WEAPONS = {
    "m1911": ("M1911.fbx", 0.216, "pistol"), "deagle": ("DesertEagle.fbx", 0.27, "pistol"),
    "mp7": ("MP7.fbx", 0.64, "smg"), "vector": ("VectorSMG.fbx", 0.62, "smg"), "p90": ("P90.fbx", 0.50, "smg"),
    "cqbm4": ("CQBM4.fbx", 0.76, "rifle"), "m4supp": ("SuppressedM4.fbx", 0.95, "rifle"), "m16": ("M16.fbx", 1.0, "rifle"),
    "g36c": ("G36C.fbx", 0.72, "rifle"), "ak47": ("AK47.fbx", 0.88, "rifle"), "scarh": ("SCAR-H.fbx", 0.97, "rifle"),
    "aug": ("SteyrAUG_M1.fbx", 0.79, "rifle"), "m4dmr": ("M4Sniper.fbx", 1.05, "rifle"),
    # variantes (las 21 armas subidas)
    "m1911_1": ("M1911_1.fbx", 0.216, "pistol"), "m1911t": ("M1911Tactical.fbx", 0.22, "pistol"), "m16_1": ("M16_1.fbx", 1.0, "rifle"),
    "mp5_1": ("MP5_1.fbx", 0.68, "smg"), "mp5_2": ("MP5_2.fbx", 0.68, "smg"), "scar": ("SCAR.fbx", 0.9, "rifle"),
    "m4a1": ("M4A1.fbx", 0.84, "rifle"), "m4a1_1": ("M4A1_1.fbx", 0.84, "rifle"),
}
ONLY = argv[3:]          # (opcional) convertir sólo estos id
if os.environ.get("ROSTER"):       # lista extra (tools/weapons/gen_roster.py --convert-list)
    for _k, _v in json.load(open(os.environ["ROSTER"])).items():
        WEAPONS[_k] = (_v[0], _v[1], _v[2])
MAX_TRIS = 16000


def find(name):
    for f in os.listdir(SRC):
        if f.endswith(name):
            return os.path.join(SRC, f)
    return None


markers = json.load(open(MK)) if (ONLY and os.path.exists(MK)) else {}      # con ids concretos se conserva lo ya convertido
for wid, (fname, length, kind) in WEAPONS.items():
    if ONLY and wid not in ONLY:
        continue
    if ONLY and wid not in ONLY:
        continue
    path = find(fname)
    if not path:
        print("falta", fname)
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in bpy.data.objects:
        o.select_set(o.type == "MESH")
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris > MAX_TRIS:
        dm = ob.modifiers.new("dec", "DECIMATE")
        dm.ratio = MAX_TRIS / tris
        bpy.ops.object.modifier_apply(modifier="dec")
    V = np.array([v.co[:] for v in ob.data.vertices])
    lo, hi = V.min(0), V.max(0)
    ext = hi - lo
    ax = int(np.argmax(ext))                       # eje del cañón = el más largo
    rest = [i for i in range(3) if i != ax]
    vert = rest[int(np.argmax([ext[i] for i in rest]))]   # alto (empuñadura + cargador) > ancho
    side = [i for i in rest if i != vert][0]
    t = (V[:, ax] - lo[ax]) / ext[ax]
    # la boca es la punta más FINA (cañón); la culata / empuñadura es más gruesa
    def thick(mask):
        s = V[mask]
        return (s[:, vert].max() - s[:, vert].min()) if len(s) else 1e9
    front_sign = 1.0 if thick(t > 0.92) < thick(t < 0.08) else -1.0
    # arriba: la empuñadura sobresale hacia ABAJO del cañón; el cañón está cerca de la parte de arriba
    muz_mask = (t > 0.9) if front_sign > 0 else (t < 0.1)
    bc = V[muz_mask][:, vert].mean()
    up_sign = 1.0 if (hi[vert] - bc) < (bc - lo[vert]) else -1.0
    # base nueva: x = lado, y = arriba, -z = adelante (boca)
    R = np.zeros((3, 3))
    R[0, side] = 1.0
    R[1, vert] = up_sign
    R[2, ax] = -front_sign
    if np.linalg.det(R) < 0:
        R[0, side] = -1.0
    s = length / ext[ax]
    P = (V - (lo + hi) / 2) @ R.T * s
    # marcadores
    zf, zb = P[:, 2].min(), P[:, 2].max()          # zf = boca (más negativo)
    Lz = zb - zf
    yt, yb = P[:, 1].max(), P[:, 1].min()
    muzzle = [0.0, float(np.median(P[P[:, 2] < zf + Lz * 0.03][:, 1])), float(zf)]
    # empuñadura: entre 55 % y 85 % desde la boca, el punto más bajo de esa zona es la mano; Grip queda arriba de ella
    if kind == "pistol":
        band = P[(P[:, 2] > zf + Lz * 0.55)]
        if len(band) == 0:
            band = P[np.argsort(P[:, 2])[-20:]]
        g_low = band[np.argmin(band[:, 1])]
        grip = [0.0, float(g_low[1] * 0.35 + yt * 0.15), float(g_low[2] - Lz * 0.08)]
        support = [0.0, grip[1] - 0.02, grip[2] + 0.01]
    else:
        band = P[(P[:, 2] > zf + Lz * 0.45) & (P[:, 2] < zf + Lz * 0.85)]
        if len(band) == 0:                              # modelos de pocos vértices: se ensancha la zona
            band = P[(P[:, 2] > zf + Lz * 0.3)]
        g_low = band[np.argmin(band[:, 1])]
        grip = [0.0, float(g_low[1] + (yt - g_low[1]) * 0.45), float(g_low[2] - 0.01)]
        fore = P[(P[:, 2] > zf + Lz * 0.18) & (P[:, 2] < zf + Lz * 0.42)]
        if len(fore) == 0:
            fore = P[(P[:, 2] > zf + Lz * 0.1) & (P[:, 2] < zf + Lz * 0.6)]
        if len(fore) == 0:
            support = [0.0, float(muzzle[1] - 0.03), float(zf + Lz * 0.3)]
        else:
            support = [0.0, float(fore[:, 1].min() + 0.012), float(fore[:, 2].mean())]
    sight = [0.0, float(yt), float(zf + Lz * 0.65)]
    # escribir los vértices transformados y exportar
    for i, v in enumerate(ob.data.vertices):
        v.co = Vector(P[i].tolist())
    # Blender es Z-arriba y el exportador glTF convierte (x, y, z)_godot ← (x, z, -y)_blender: pasar a Blender
    for v in ob.data.vertices:
        x, y, z = v.co
        v.co = Vector((x, -z, y))
    ob.data.update()
    for p in ob.data.polygons:
        p.use_smooth = True
    mats = {}
    for m in ob.data.materials:
        if m and m.use_nodes and "Principled BSDF" in m.node_tree.nodes:
            b = m.node_tree.nodes["Principled BSDF"]
            c = b.inputs["Base Color"].default_value
            mats[m.name] = {"color": [round(c[0], 3), round(c[1], 3), round(c[2], 3)], "metallic": round(float(b.inputs["Metallic"].default_value), 2),
                            "roughness": round(float(b.inputs["Roughness"].default_value), 2)}
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, wid + ".glb"), use_selection=True, export_format="GLB")
    markers[wid] = {"kind": kind, "length": round(length, 3), "has_mag": True, "source": fname,
                    "markers": {"Grip": [round(x, 4) for x in grip], "Support": [round(x, 4) for x in support],
                                "Muzzle": [round(x, 4) for x in muzzle], "Sight": [round(x, 4) for x in sight]},
                    "materials": mats, "tris": int(sum(len(p.vertices) - 2 for p in ob.data.polygons))}
    print(wid, "ok", markers[wid]["tris"], "tris")
    json.dump(markers, open(MK, "w"), indent=1)         # se guarda en cada arma (si una falla no se pierde lo hecho)
json.dump(markers, open(MK, "w"), indent=1)
