"""Reduce un GLB pesado a una versión liviana (sin texturas): Blender (bpy) con decimación. Uso: python3 tools/decimate_glb.py -- entrada.glb salida.glb triángulos"""
import sys
import bpy
argv = sys.argv[sys.argv.index("--") + 1:]
src, dst, target = argv[0], argv[1], int(argv[2])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
tot = sum(len(o.data.polygons) for o in meshes)
print("triángulos de entrada:", tot)
ratio = min(1.0, target / max(tot, 1))
for o in meshes:
    bpy.context.view_layer.objects.active = o
    m = o.modifiers.new("dec", "DECIMATE")
    m.ratio = ratio
    bpy.ops.object.modifier_apply(modifier=m.name)
    o.data.materials.clear()
print("triángulos de salida:", sum(len(o.data.polygons) for o in meshes))
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", use_selection=False)
