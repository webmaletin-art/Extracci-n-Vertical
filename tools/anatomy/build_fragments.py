#!/usr/bin/env python3
"""Arma tools/anatomy/anatomy_frag.glb (un nodo por fragmento: gNNN_fKK) y anatomy_frags.json con los fragmentos de
fracture_bones.py. Las caras de corte van en color de hueso roto / médula (rojo oscuro), el resto en color hueso.
Uso: python3 tools/anatomy/build_fragments.py <frag.npz> <carpeta salida>"""
import json
import os
import sys

import numpy as np
import trimesh

d = np.load(sys.argv[1])
OUT = sys.argv[2]
names, parents = [str(x) for x in d["names"]], [str(x) for x in d["parents"]]
V, F, C, voff, foff = d["verts"], d["faces"], d["cut"], d["voff"], d["foff"]
BONE = np.array([235, 228, 205, 255], dtype=np.uint8)
MARROW = np.array([150, 20, 18, 255], dtype=np.uint8)
scene = trimesh.Scene()
meta = {"fragments": []}
for i, n in enumerate(names):
    v = V[voff[i]:voff[i + 1]]
    f = F[foff[i]:foff[i + 1]]
    c = C[foff[i]:foff[i + 1]]
    m = trimesh.Trimesh(vertices=v, faces=f, process=False)
    cols = np.where(c[:, None] == 1, MARROW, BONE)
    m.visual = trimesh.visual.ColorVisuals(m, face_colors=cols)
    scene.add_geometry(m, node_name=n, geom_name=n)
    meta["fragments"].append({"node": n, "parent": parents[i], "tris": int(len(f)), "center": [round(float(x), 4) for x in v.mean(axis=0)]})
scene.export(os.path.join(OUT, "anatomy_frag.glb"))
json.dump(meta, open(os.path.join(OUT, "anatomy_frags.json"), "w"), indent=1)
print("fragmentos:", len(names))
