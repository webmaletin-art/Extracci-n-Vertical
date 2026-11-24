class_name Gibs
extends Node3D
## Trozos sueltos: fragmentos de hueso que se desprenden (los rompió Blender: fracture_bones.py) y balas aplastadas.
## Grupo fijo de nodos (no se crean ni destruyen en combate). Vuelan con su velocidad, giran, caen con gravedad, rebotan
## en el piso / paredes y quedan ahí. Usan el tiempo del juego: en cámara lenta flotan despacio.

const MAX := 36

static var instance: Gibs

var _mi: Array[MeshInstance3D] = []
var _vel: Array[Vector3] = []
var _spin: Array[Vector3] = []
var _life: Array[float] = []
var _rest: Array[bool] = []
var _i := 0
var bone_mat: StandardMaterial3D
var bullet_mesh: Mesh

func _ready() -> void:
	instance = self
	bone_mat = StandardMaterial3D.new()
	bone_mat.vertex_color_use_as_albedo = true
	bone_mat.roughness = 0.55
	bone_mat.emission_enabled = true
	bone_mat.emission = Color(0.12, 0.1, 0.08)
	bone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in MAX:
		var mi := MeshInstance3D.new()
		mi.visible = false
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mi.append(mi)
		_vel.append(Vector3.ZERO)
		_spin.append(Vector3.ZERO)
		_life.append(0.0)
		_rest.append(true)
	bullet_mesh = make_mushroom()

func _exit_tree() -> void:
	if instance == self:
		instance = null

## Bala deformada «en hongo» (punta aplastada con pétalos de la camisa de cobre).
static func make_mushroom() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var copper := Color(0.78, 0.45, 0.22)
	var lead := Color(0.45, 0.45, 0.48)
	var seg := 10
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	# base (culote) cilíndrica y cabeza ancha aplastada con bordes irregulares
	var rings := [[0.0, 0.0035, copper], [0.007, 0.0038, copper], [0.009, 0.0065, copper], [0.0105, 0.0085, lead], [0.012, 0.0, lead]]
	var prev: Array = []
	for r in rings:
		var cur: Array = []
		for k in seg:
			var a := TAU * k / seg
			var rr: float = float(r[1]) * (1.0 + rng.randf_range(-0.25, 0.25) * (1.0 if float(r[1]) > 0.006 else 0.0))
			cur.append(Vector3(cos(a) * rr, sin(a) * rr, -float(r[0])))
		if not prev.is_empty():
			for k in seg:
				var a0: Vector3 = prev[k]
				var a1: Vector3 = prev[(k + 1) % seg]
				var b0: Vector3 = cur[k]
				var b1: Vector3 = cur[(k + 1) % seg]
				for p in [a0, b0, b1, a0, b1, a1]:
					st.set_color(r[2])
					st.add_vertex(p)
		prev = cur
	st.generate_normals()
	return st.commit()

## Lanza un trozo. mesh en coordenadas locales alrededor de xform.origin.
func spawn(mesh: Mesh, xform: Transform3D, vel: Vector3, spin: Vector3, life := 14.0, mat: Material = null) -> void:
	var mi := _mi[_i]
	var k := _i
	_i = (_i + 1) % MAX
	mi.mesh = mesh
	mi.material_override = mat if mat else bone_mat
	mi.global_transform = xform
	mi.visible = true
	_vel[k] = vel
	_spin[k] = spin
	_life[k] = life
	_rest[k] = false

func _process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	for k in MAX:
		var mi := _mi[k]
		if not mi.visible:
			continue
		_life[k] -= delta
		if _life[k] <= 0.0:
			mi.visible = false
			continue
		if _rest[k]:
			continue
		var v := _vel[k]
		v.y -= 9.8 * delta
		var p := mi.global_position
		var nxt := p + v * delta
		var q := PhysicsRayQueryParameters3D.create(p, nxt, 1 | 8)
		var h := space.intersect_ray(q)
		if not h.is_empty():
			var n: Vector3 = h.normal
			v = v.bounce(n) * 0.35
			nxt = (h.position as Vector3) + n * 0.01
			_spin[k] *= 0.5
			if v.length() < 0.4 and n.y > 0.6:
				_rest[k] = true
		mi.global_position = nxt
		var sp := _spin[k]
		if sp.length() > 0.001:
			mi.global_basis = Basis(sp.normalized(), sp.length() * delta) * mi.global_basis
		_vel[k] = v
