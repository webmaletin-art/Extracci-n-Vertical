"""Escena de la portada (Blender, bpy): el letrero «EXTRACCIÓN EXTREME VERTICAL» y las municiones de la toma en cámara lenta.
Uso: python3 tools/menu_scene/make_scene.py -- <carpeta de salida>      (escribe letrero.glb y municion.glb; luego tools/bake_lined.gd -- menu)
Todo en metros y sobredimensionado a propósito (la bala mide ~0,55 m) para que se lea en pantalla. Sin materiales: el juego lo dibuja en línea."""
import math
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

OUT = sys.argv[sys.argv.index("--") + 1]
FONT = "/usr/share/fonts/truetype/freefont/FreeSansBoldOblique.ttf"


def clean():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def to_mesh(o):
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.convert(target="MESH")
    return o


def text(body, size, loc, extrude=0.14, bevel=0.012, name="txt"):
    c = bpy.data.curves.new(name, "FONT")
    c.body = body
    c.size = size
    c.extrude = extrude
    c.bevel_depth = bevel
    c.bevel_resolution = 1
    c.font = bpy.data.fonts.load(FONT)
    c.resolution_u = 4
    o = bpy.data.objects.new(name, c)
    bpy.context.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (math.radians(90), 0, 0)          # de pie, mirando a -Y (a la cámara)
    return to_mesh(o)


def box(size, loc, rot=(0, 0, 0), name="box"):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.scale = size
    o.location = loc
    o.rotation_euler = rot
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.transform_apply(scale=True)
    return o


def cyl(r, h, loc, rot=(0, 0, 0), seg=16, name="cyl"):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, vertices=seg, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    return o


def lathe(profile, seg=20, name="lathe"):
    """profile: [(radio, z)] de la base a la punta; se gira alrededor de Z."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    verts = [bm.verts.new((r, 0, z)) for r, z in profile]
    for a, b in zip(verts, verts[1:]):
        bm.edges.new((a, b))
    bmesh.ops.spin(bm, geom=bm.verts[:] + bm.edges[:], cent=(0, 0, 0), axis=(0, 0, 1), angle=math.tau, steps=seg)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    return o


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o


def export(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True)


def sign():
    parts = []
    # «E» + gran X de vigas cruzadas + «TREME», con «EXTRACCIÓN» arriba y la placa «VERTICAL» abajo
    parts.append(text("E", 3.0, (-4.15, 0.0, 0.2), name="E"))
    for k, ang in enumerate((38, -38)):
        beam = box((0.62, 0.34, 4.0), (0.0, 0.0, 1.55), (0, math.radians(ang), 0), name="viga%d" % k)
        parts.append(beam)
        for t in (-1.45, -0.55, 0.45, 1.35):                       # remaches
            rv = cyl(0.07, 0.12, (math.sin(math.radians(ang)) * t, -0.2, 1.55 + math.cos(math.radians(ang)) * t), (math.radians(90), 0, 0), 10, "remache")
            parts.append(rv)
    parts.append(text("TRACCIÓN", 1.25, (1.2, 0.0, 2.45), name="TRACCION"))
    parts.append(text("TREME", 1.55, (1.55, 0.0, 0.55), name="TREME"))
    parts.append(box((6.4, 0.22, 0.62), (0.2, 0.05, -0.5), (0, 0, 0), "placa"))
    parts.append(text("VERTICAL", 0.62, (-2.2, -0.12, -0.7), 0.12, 0.01, "VERTICAL"))
    for sx in (-1, 1):                                              # franjas de peligro a los costados de la placa
        for i in range(4):
            parts.append(box((0.22, 0.2, 0.5), (sx * (3.9 + i * 0.42) + 0.2, 0.05, -0.5), (0, math.radians(24 * sx), 0), "franja"))
    s = join(parts, "Letrero")
    s.location.z += 0.0
    return s


def ammo():
    objs = []
    # Bala entera: base plana, cuerpo, ojiva
    b = lathe([(0.0, 0.0), (0.105, 0.0), (0.11, 0.06), (0.11, 0.28), (0.095, 0.4), (0.06, 0.5), (0.0, 0.56)], 24, "Bala")
    objs.append(b)
    # Bala deformada en «hongo»: la punta se abre en pétalos
    h = lathe([(0.0, 0.0), (0.105, 0.0), (0.112, 0.06), (0.115, 0.2), (0.15, 0.3), (0.215, 0.36), (0.235, 0.39), (0.17, 0.4), (0.06, 0.37), (0.0, 0.34)], 24, "BalaHongo")
    objs.append(h)
    # Perforante: ojiva larga y fina
    a = lathe([(0.0, 0.0), (0.09, 0.0), (0.095, 0.05), (0.095, 0.3), (0.075, 0.5), (0.04, 0.66), (0.0, 0.74)], 24, "BalaPerforante")
    objs.append(a)
    # Casquillo (con reborde y cuello)
    c = lathe([(0.0, 0.0), (0.135, 0.0), (0.135, 0.03), (0.115, 0.04), (0.115, 0.34), (0.085, 0.44), (0.085, 0.48), (0.0, 0.48)], 24, "Casquillo")
    objs.append(c)
    # Fragmentos (esquirlas) de la bala al romperse
    frag = []
    for i, (x, y, z, s) in enumerate([(0, 0, 0, 0.1), (0.15, 0.05, 0.06, 0.07), (-0.12, -0.04, 0.1, 0.08), (0.05, -0.1, -0.08, 0.06)]):
        me = bpy.data.meshes.new("f")
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=4, radius1=s, radius2=0.0, depth=s * 2.2)
        bm.to_mesh(me)
        bm.free()
        f = bpy.data.objects.new("f%d" % i, me)
        bpy.context.collection.objects.link(f)
        f.location = (x, y, z)
        f.rotation_euler = (i * 1.1, i * 0.7, i * 0.4)
        frag.append(f)
    for f in frag:
        bpy.context.view_layer.objects.active = f
        f.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True)
    objs.append(join(frag, "Fragmentos"))
    # Estela de velocidad: varilla fina y tres anillos que se ensanchan hacia atrás
    t = cyl(0.014, 3.0, (0, 0, -1.5), (0, 0, 0), 6, "Estela")
    objs.append(t)
    rings = []
    for i, z in enumerate((-0.25, -0.55, -0.9)):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.18 + i * 0.07, minor_radius=0.012, major_segments=24, minor_segments=5, location=(0, 0, z))
        rings.append(bpy.context.active_object)
    objs.append(join(rings, "AnillosVelocidad"))
    # Fogonazo: estrella de puntas
    me = bpy.data.meshes.new("Fogonazo")
    bm = bmesh.new()
    n = 9
    pts = []
    for i in range(n * 2):
        r = 0.55 if i % 2 == 0 else 0.2
        a = math.tau * i / (n * 2)
        pts.append(bm.verts.new((math.cos(a) * r, 0.0, math.sin(a) * r)))
    bm.faces.new(pts)
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.05)
    bm.to_mesh(me)
    bm.free()
    fl = bpy.data.objects.new("Fogonazo", me)
    bpy.context.collection.objects.link(fl)
    objs.append(fl)
    # Anillo de impacto: grieta circular alrededor del orificio de entrada / salida
    bpy.ops.mesh.primitive_torus_add(major_radius=0.3, minor_radius=0.02, major_segments=28, minor_segments=5, location=(0, 0, 0), rotation=(math.radians(90), 0, 0))
    ring = bpy.context.active_object
    ring.name = "AnilloImpacto"
    objs.append(ring)
    return objs


clean()
s = sign()
export(OUT + "/letrero.glb", [s])
clean()
export(OUT + "/municion.glb", ammo())
print("ESCENA OK")
