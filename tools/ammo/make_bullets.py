"""Balas realistas en Blender (bpy) para la cámara lenta: 7,62 mm con camisa de cobre (ojiva, cuerpo, ranura de
engarce, cola de bote) y base de plomo; y la misma bala deformada en hongo (pétalos de camisa abiertos, plomo
expuesto) para cuando pega en hueso duro.
Uso: python3 tools/ammo/make_bullets.py -- <carpeta salida>   →  bullet_fmj.glb, bullet_mushroom.glb
La punta mira a -Z en Godot (+Y en Blender). Tamaño real (~27 mm)."""
import math
import sys

import bpy
import bmesh
from mathutils import Vector, noise

OUT = sys.argv[sys.argv.index("--") + 1]
MM = 0.001
# perfil (radio, altura) desde la base hasta la punta, en mm
PROFILE = [(0.0, -13.4), (2.9, -13.4), (3.2, -12.6), (3.9, -10.4), (3.95, -6.2), (3.72, -5.6), (3.72, -4.6), (3.95, -4.0),
           (3.95, 0.6)]
for i in range(1, 15):                      # ojiva tangente
    t = i / 14.0
    y = 0.6 + 12.8 * t
    r = 3.95 * math.sqrt(max(1.0 - t ** 1.7, 0.0)) * (1.0 - 0.06 * t)
    PROFILE.append((max(r, 0.25), y))
PROFILE.append((0.0, 13.55))


def material(name, color, metal, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    return m


def lathe(name, steps=64):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    for (r, y) in PROFILE:
        ring = []
        for k in range(steps):
            a = 2 * math.pi * k / steps
            ring.append(bm.verts.new((r * MM * math.cos(a), y * MM, r * MM * math.sin(a))))
        rings.append(ring)
    for j in range(len(rings) - 1):
        for k in range(steps):
            k2 = (k + 1) % steps
            vs = [rings[j][k], rings[j][k2], rings[j + 1][k2], rings[j + 1][k]]
            # sin caras degeneradas en los polos
            uniq = []
            for v in vs:
                if all((v.co - u.co).length > 1e-7 for u in uniq):
                    uniq.append(v)
            if len(uniq) >= 3:
                f = bm.faces.new(uniq)
                f.material_index = 1 if j == 0 else 0           # la base (plomo) usa el material 1
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)          # (el perfil gira al revés: normales hacia afuera)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    return ob


def mushroom(ob):
    """Hongo: la ojiva se aplasta contra el hueso, la camisa se abre en 6 pétalos y el plomo queda expuesto."""
    me = ob.data
    for v in me.vertices:
        x, y, z = v.co
        r = math.hypot(x, z)
        a = math.atan2(z, x)
        yy = y / MM
        if yy > -2.0:
            t = (yy + 2.0) / 15.5                        # 0 en el cuerpo, 1 en la punta
            petal = 0.55 + 0.45 * abs(math.cos(3.0 * a))
            grow = 1.0 + 1.6 * t * petal
            n = noise.noise(Vector((x * 900, y * 900, z * 900)))
            r2 = (r + 3.2 * MM * t) * grow * (1.0 + 0.12 * n)
            y2 = -2.0 * MM + (yy + 2.0) * MM * 0.32 - 1.4 * MM * t * (1.0 - petal)
            v.co = Vector((r2 * math.cos(a), y2, r2 * math.sin(a)))
        else:
            v.co = Vector((x, y * 0.85 - 0.6 * MM, z))     # el cuerpo se acorta un poco
    me.update()


def export(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB", export_apply=True)


bpy.ops.wm.read_factory_settings(use_empty=True)
copper = material("cobre", (0.85, 0.45, 0.22), 1.0, 0.22)
lead = material("plomo", (0.35, 0.36, 0.38), 0.8, 0.5)
b = lathe("bala_fmj")
b.data.materials.append(copper)
b.data.materials.append(lead)
export(b, OUT + "/bullet_fmj.glb")
m = lathe("bala_hongo")
m.data.materials.append(copper)
m.data.materials.append(lead)
mushroom(m)
export(m, OUT + "/bullet_mushroom.glb")
print("listo", OUT)
