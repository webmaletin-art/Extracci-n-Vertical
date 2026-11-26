"""Modela con Blender (bpy) los cartuchos reales de data/ammo.json: vaina de latón con su culote (con o sin pestaña), bala con su
forma (punta redonda / puntiaguda), punta hueca con la cavidad, trazante con la punta roja, perforante con la punta negra y,
en las escopetas, cartuchos de plástico con culote de latón. Un GLB por calibre y tipo, en metros, parado (eje Y de Godot, base en y = 0).
Uso: python3 tools/ammo/make_cartridges.py -- <carpeta de salida assets/ammo/cartridges>"""
import json, math, os, sys
import bpy, bmesh
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1]
os.makedirs(OUT, exist_ok=True)
D = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "ammo.json")))
MM = 0.001

def mat(name, color, metallic=0.0, rough=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    return m

def lathe(name, pts, material, seg=20):
    """Revoluciona el perfil [(radio, altura), ...] (en m) alrededor del eje Y."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    vs = [bm.verts.new((r, 0.0, y)) for r, y in pts]          # en Blender la altura es Z (el GLB la pasa a Y de Godot)
    es = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
    bmesh.ops.spin(bm, geom=vs + es, axis=(0, 0, 1), cent=(0, 0, 0), angle=math.tau, steps=seg)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(material)
    return ob

def ogive(r_b, rn, y0, vis, cyl, n=7, y_from=0.0, y_to=1.0):
    """Perfil de la bala (radio, altura) entre las fracciones y_from..y_to de su parte visible."""
    pts = []
    for i in range(n + 1):
        t = y_from + (y_to - y_from) * i / n
        if t <= cyl:
            r = r_b
        else:
            u = (t - cyl) / (1.0 - cyl)
            r = rn + (r_b - rn) * math.sqrt(max(0.0, 1.0 - u * u))
        pts.append((r, y0 + vis * t))
    return pts

def build(key, typ):
    c = D["calibers"][key]
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)
    brass = mat("laton", (0.78, 0.55, 0.18), 0.85, 0.32)
    copper = mat("cobre", (0.72, 0.34, 0.2), 0.7, 0.4)
    red = mat("punta_roja", (0.85, 0.05, 0.05), 0.2, 0.5)
    black = mat("punta_negra", (0.03, 0.03, 0.035), 0.4, 0.4)
    orange = mat("punta_naranja", (0.95, 0.45, 0.05), 0.3, 0.45)
    clen, db, dn, oal, dbul = c["case_len"] * MM, c["d_base"] * MM, c["d_neck"] * MM, c["oal"] * MM, c["d_bullet"] * MM
    rb, rn_case, rbul = db / 2, dn / 2, dbul / 2
    if c["shape"] == "shell":
        hull = {"std": (0.75, 0.08, 0.08), "hp": (0.18, 0.4, 0.15), "tr": (0.95, 0.4, 0.05), "ap": (0.04, 0.04, 0.05), "in": (0.9, 0.25, 0.05), "fl": (0.1, 0.3, 0.7)}[typ]
        plastic = mat("plastico", hull, 0.0, 0.55)
        head_h = 16 * MM
        lathe("culote", [(0, 0), (rb * 1.06, 0), (rb * 1.06, 2 * MM), (rb, 2.6 * MM), (rb, head_h), (0, head_h)], brass, 24)
        lathe("cuerpo", [(rb, head_h), (rb * 0.99, 62 * MM), (rb * 0.93, 67 * MM), (rb * 0.6, oal - 0.0), (0, oal)], plastic, 24)
    else:
        rim_r = rb + (0.8 * MM if c["rimmed"] else 0.0)
        pts = [(0, 0), (rim_r, 0), (rim_r, 1.3 * MM), (rb - 0.5 * MM, 1.3 * MM), (rb - 0.5 * MM, 2.2 * MM), (rb, 2.6 * MM)]
        if c["shape"] == "bottle":
            y_sh, y_n = clen * 0.58, clen * 0.76
            pts += [(rb * 0.99, y_sh), (rn_case, y_n), (rn_case, clen)]
        else:
            pts += [(rb * 0.99, clen * 0.6), (rn_case, clen)]
        pts += [(rbul * 1.0, clen)]
        lathe("vaina", pts, brass, 24)
        vis = oal - clen
        rn = rbul * (0.14 if c["shape"] == "bottle" else 0.32)
        cyl = 0.30 if c["shape"] == "bottle" else 0.22
        if typ in ("hp", "fl"):
            top = rbul * (0.62 if typ == "hp" else 0.78)
            body = ogive(rbul, top, clen, vis, cyl, 6, 0.0, 1.0)
            body[-1] = (top, clen + vis)
            depth = 3.6 if typ == "hp" else 6.5
            body += [(top * 0.55, clen + vis), (top * 0.5, clen + vis - depth * 0.7 * MM), (0.0, clen + vis - depth * MM)]       # cavidad
            ob = lathe("bala_hueca" if typ == "hp" else "bala_flor", [(0, clen)] + body, copper, 24)
            # borde en estrella: los vértices del borde de la boca se alternan hacia afuera / adentro (6 muescas la hueca, 8 pétalos la flor)
            petals = 6 if typ == "hp" else 8
            ytop = clen + vis
            for v in ob.data.vertices:
                if abs(v.co.z - ytop) < 1e-5 and (v.co.x ** 2 + v.co.y ** 2) ** 0.5 > top * 0.5:
                    ang = math.atan2(v.co.y, v.co.x)
                    k = 0.82 + 0.34 * (0.5 + 0.5 * math.cos(ang * petals))
                    v.co.x *= k
                    v.co.y *= k
                    if typ == "fl":
                        v.co.z -= 1.2 * MM * (0.5 - 0.5 * math.cos(ang * petals))     # pétalos a distinta altura
        elif typ in ("tr", "ap", "in"):
            split = {"tr": 0.62, "ap": 0.52, "in": 0.58}[typ]
            lathe("bala_cuerpo", [(0, clen)] + ogive(rbul, rn, clen, vis, cyl, 6, 0.0, split), copper, 24)
            lathe("punta", ogive(rbul, rn, clen, vis, cyl, 6, split, 1.0) + [(0, clen + vis)], {"tr": red, "ap": black, "in": orange}[typ], 24)
        else:
            lathe("bala", [(0, clen)] + ogive(rbul, rn, clen, vis, cyl, 7) + [(0, clen + vis)], copper, 24)
    bpy.ops.object.select_all(action="SELECT")
    path = os.path.join(OUT, "%s_%s.glb" % (key, typ))
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)
    tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == "MESH" for p in o.data.polygons)
    return tris

bpy.ops.wm.read_factory_settings(use_empty=True)
n = 0
for key in D["calibers"]:
    for typ in ("std", "tr", "hp", "ap", "in", "fl"):
        t = build(key, typ)
        n += 1
        print("cartucho", key, typ, t, "tris")
print("LISTO", n)
