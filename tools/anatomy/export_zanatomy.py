"""Exporta la anatomía completa de Z-Anatomy (Startup.blend) a un archivo intermedio para build_anatomy.py.

Uso (Blender como módulo de Python, `pip install bpy==5.3.0` en un entorno aparte):
    python export_zanatomy.py <Startup.blend> <salida.npz>

Toma (objetos visibles, sin las superficies de anotación «.j» / «.i»):
  1 Skeletal system → hueso · 4 Muscular system → musculo · 5 Cardiovascular system → vaso (corazón → organo)
  7 Nervous system → nervio (encéfalo, médula, nervios largos) · 8 Visceral systems → organo (pulmones, hígado, …)
Las curvas (arterias, venas, nervios, bronquios) se evalúan con su grosor. Coordenadas convertidas a las de Godot:
metros, Y arriba, mirando a +Z (Blender: Z arriba, mirando a −Y).
"""
import sys

import bpy
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
BLEND, OUT = argv[0], argv[1]
bpy.ops.wm.open_mainfile(filepath=BLEND)

SYSTEMS = {"1": "hueso", "4": "musculo", "5": "vaso", "7": "nervio", "8": "organo"}
SKIP = ("bursa", "tendon sheath", "synovial", "fascia", "retinaculum", "aponeurosis of", "septum", "surface of tooth",
        "region", "sulcus", "fissure", "gyrus*", "line", "plane", "notch")


def objs(c):
    out = list(c.objects)
    for ch in c.children:
        out += objs(ch)
    return out


dg = bpy.context.evaluated_depsgraph_get()
names, systems, offsets, verts, faces = [], [], [0], [], []
fo = [0]
for c in bpy.context.scene.collection.children:
    sysname = SYSTEMS.get(c.name[0])
    if sysname is None:
        continue
    for o in objs(c):
        if o.type not in ("MESH", "CURVE"):
            continue
        n = o.name
        if n.endswith((".j", ".i", ".t")) or o.hide_get() or o.hide_viewport:
            continue
        low = n.lower()
        if any(s in low for s in SKIP):
            continue
        dims = max(o.dimensions)
        if sysname in ("vaso", "nervio") and o.type == "CURVE" and dims < 0.12:
            continue                 # ramas chicas: no se ven y suman miles de triángulos
        if sysname == "nervio" and o.type == "MESH" and dims < 0.015:
            continue
        ev = o.evaluated_get(dg)
        try:
            me = ev.to_mesh()
        except RuntimeError:
            continue
        if me is None or len(me.polygons) == 0:
            ev.to_mesh_clear()
            continue
        me.calc_loop_triangles()
        mw = o.matrix_world
        v = np.array([tuple(mw @ vv.co) for vv in me.vertices], dtype=np.float32)
        f = np.array([tuple(t.vertices) for t in me.loop_triangles], dtype=np.int32)
        ev.to_mesh_clear()
        v = np.stack([v[:, 0], v[:, 2], -v[:, 1]], axis=1)     # Blender → Godot
        s = sysname
        if sysname == "vaso" and o.type == "MESH":
            s = "organo"                                     # cavidades y paredes del corazón
        names.append(n)
        systems.append(s)
        verts.append(v)
        faces.append(f)
        offsets.append(offsets[-1] + len(v))
        fo.append(fo[-1] + len(f))

np.savez_compressed(OUT, names=np.array(names), systems=np.array(systems), verts=np.concatenate(verts),
                    faces=np.concatenate(faces), voff=np.array(offsets), foff=np.array(fo))
tot = {}
for s, f in zip(systems, faces):
    tot[s] = tot.get(s, 0) + len(f)
print("objetos:", len(names), "triángulos por sistema:", tot)
