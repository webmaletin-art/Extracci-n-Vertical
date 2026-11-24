"""Rompe de verdad los huesos en Blender: fragmentos de Voronoi (como Cell Fracture) con caras de corte cerradas.

Uso (Blender como módulo: pip install bpy==5.3.0):
    python fracture_bones.py -- <tools/anatomy/anatomy_src.glb> <tools/anatomy/anatomy_groups.json> <salida.npz>

Cada hueso se parte en N fragmentos (cráneo en placas, costillas, huesos largos en trozos, dedos, vértebras…).
Las caras del corte quedan marcadas (en el juego se ven como hueso esponjoso / médula, rojo) y los bordes se dentan con
ruido para que no parezcan cortes de cuchillo. Después tools/anatomy/build_fragments.py arma anatomy_frag.glb y
fit_anatomy.gd los ajusta dentro de cada personaje igual que la anatomía.
"""
import json
import math
import random
import sys

import bpy  # noqa: I001  (bpy tiene que ir antes que bmesh y mathutils)
import bmesh
import numpy as np
from mathutils import Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, GROUPS, OUT = argv[0], argv[1], argv[2]

# cuántos fragmentos por hueso (por el comienzo del nombre del grupo)
CELLS = [("cráneo", 16), ("mandíbula", 5), ("costillas", 12), ("vértebras", 8), ("pelvis", 10), ("esternón", 4),
         ("clavícula", 5), ("escápula", 7), ("húmero", 8), ("radio", 6), ("cúbito", 6), ("fémur", 9), ("tibia", 8),
         ("peroné", 6), ("rótula", 4), ("huesos de la mano", 8), ("dedos de la mano", 10), ("huesos del pie", 7),
         ("huesos de", 5)]

random.seed(7)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meta = json.load(open(GROUPS))
bones = {g["node"]: g for g in meta["groups"] if g["system"] == "hueso" and not g["label"].startswith("dientes")}


def cells_for(label):
    for k, n in CELLS:
        if label.startswith(k):
            return n
    return 0


def seeds_for(bm, n):
    """Semillas dentro del hueso: vértices al azar empujados hacia el centro (fragmentos parejos)."""
    vs = [v.co.copy() for v in bm.verts]
    c = sum(vs, Vector()) / len(vs)
    pts = []
    for i in range(n):
        v = random.choice(vs)
        pts.append(v.lerp(c, random.uniform(0.25, 0.6)))
    return pts


def fracture(obj, n):
    me = obj.data
    base = bmesh.new()
    base.from_mesh(me)
    base.transform(obj.matrix_world)
    bmesh.ops.triangulate(base, faces=base.faces)
    seeds = seeds_for(base, n)
    size = max((Vector(obj.dimensions)).length, 0.01)
    out = []
    for i, si in enumerate(seeds):
        bm = base.copy()
        for f in bm.faces:
            f.material_index = 0
        for j, sj in enumerate(seeds):
            if i == j or len(bm.verts) == 0:
                continue
            nrm = (sj - si).normalized()
            co = (si + sj) * 0.5
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=nrm, clear_outer=True)
            cut_edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
            if cut_edges:
                try:
                    filled = bmesh.ops.holes_fill(bm, edges=cut_edges, sides=0)
                    for f in filled.get("faces", []):
                        f.material_index = 1
                except Exception:
                    pass
        if len(bm.faces) < 4:
            bm.free()
            continue
        # bordes dentados: los vértices de las caras de corte se mueven con ruido (fractura, no corte limpio)
        amp = size * 0.012
        for f in bm.faces:
            if f.material_index == 1:
                for v in f.verts:
                    p = v.co * (40.0 / size)
                    v.co += Vector((noise.noise(p), noise.noise(p + Vector((5.2, 1.3, 7.1))), noise.noise(p + Vector((2.7, 9.4, 3.3))))) * amp
        bmesh.ops.triangulate(bm, faces=bm.faces)
        verts = np.array([tuple(v.co) for v in bm.verts], dtype=np.float32)
        bm.verts.index_update()
        faces = np.array([[v.index for v in f.verts] for f in bm.faces], dtype=np.int32)
        cut = np.array([1 if f.material_index == 1 else 0 for f in bm.faces], dtype=np.uint8)
        out.append((verts, faces, cut))
        bm.free()
    base.free()
    return out


names, parents, V, F, C, voff, foff = [], [], [], [], [], [0], [0]
done = 0
for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    node = obj.name.split(".")[0]
    if node not in bones:
        continue
    n = cells_for(bones[node]["label"])
    if n < 2:
        continue
    frags = fracture(obj, n)
    for k, (v, f, c) in enumerate(frags):
        v = np.stack([v[:, 0], v[:, 2], -v[:, 1]], axis=1)       # Blender → Godot
        names.append(f"{node}_f{k:02d}")
        parents.append(node)
        V.append(v)
        F.append(f)
        C.append(c)
        voff.append(voff[-1] + len(v))
        foff.append(foff[-1] + len(f))
    done += 1
    print(f"  {bones[node]['label']}: {len(frags)} fragmentos")

np.savez_compressed(OUT, names=np.array(names), parents=np.array(parents), verts=np.concatenate(V), faces=np.concatenate(F),
                    cut=np.concatenate(C), voff=np.array(voff), foff=np.array(foff))
print("huesos rotos:", done, "fragmentos:", len(names), "triángulos:", sum(len(f) for f in F))
