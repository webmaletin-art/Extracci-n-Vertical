class_name Actor
extends CharacterBody3D
## Personaje (jugador o bot). Lee un ActorInput por cuadro y resuelve:
##  * Movimiento analógico progresivo: la velocidad sale de cuánto se inclina el joystick (sigilo → caminar → correr →
##    velocidad máxima), sin botón de correr. Frenado inmediato y controlado.
##  * Apuntado independiente y persistente: aim_dir vive en coordenadas del MUNDO y sólo lo cambia el joystick derecho
##    (o el mouse). El movimiento nunca lo pisa. El cuerpo mira hacia donde se apunta: si se camina al revés, retrocede.
##  * Parkour: salto, agarre automático de bordes, trepar, subir a cajas, escaleras de mano, caída por gravedad y daño.
##  * Combate: arma de fuego (Firearm + Ballistics), cuchillo, puños y patadas en combinación, granadas.
##  * Daño por zonas (hitboxes en los huesos), reacciones con animaciones de Mixamo, muerte.
## El juego es 2.5D: el personaje se mueve en el plano z = 0 (X = horizontal, Y = vertical).

signal damaged(info: Dictionary)
signal died(info: Dictionary)
signal shot_fired(projectile: int, weapon: Firearm)
signal weapon_changed
signal landed(fall_height: float)
signal noise_made(radius: float)

enum State { GROUND, AIR, LADDER, HANG, CLIMB, ACTION, DOWN, DEAD }

const P := "mixamorig_"
const GRAVITY := 18.0
const JUMP_V := 6.2                 ## ~1.07 m de salto con esta gravedad
const ACCEL := 16.0
const DECEL := 26.0
const AIR_CONTROL := 0.35
## Banda de velocidad según la inclinación del joystick (|x|): [inclinación, m/s]
const SPEED_CURVE := [[0.12, 0.0], [0.15, 0.55], [0.40, 1.15], [0.70, 2.0], [0.92, 3.6], [1.0, 5.2]]
const BACK_MAX := 3.0               ## retroceder apuntando: como mucho correr hacia atrás
const CROUCH_MAX := 1.2
const BOT_DAMAGE_TO_PLAYER := 0.6   ## balance PvE: los bots pegan menos que el jugador (en PvP es 1)
const LADDER_SPEED := 1.6
const HANG_REACH_MIN := 1.15        ## altura del borde sobre los pies para agarrarse en el aire
const HANG_REACH_MAX := 2.35
const VAULT_MIN := 0.35             ## cajas y tarimas que se suben con el botón de salto
const VAULT_MAX := 1.3
const JUMP_VAULT := 0.9             ## hasta esta altura se sube saltando; más alto, con la animación de apoyarse y trepar
const SAFE_FALL := 3.6              ## metros sin daño
const DEADLY_FALL := 11.0
## Multiplicador de daño por zona y por qué zona es «crítica» (activa la cámara de rayos X)
const ZONE_MULT := {"head": 3.5, "neck": 2.5, "torso": 1.0, "pelvis": 0.9, "arm": 0.55, "leg": 0.6, "hand": 0.4, "foot": 0.4}
## Velocidad propia de cada clip de locomoción (m/s): la reproducción se escala para que los pies no patinen.
const CLIP_SPEED := {"walk_f": 1.4, "walk_b": 1.3, "run_f": 3.3, "run_b": 2.6, "sprint_f": 5.4, "sprint_b": 4.0,
	"cwalk_f": 1.3, "cwalk_b": 1.2, "injured_walk_f": 1.0, "injured_walk_b": 0.9, "pistol_walk_f": 1.4, "pistol_walk_b": 1.3, "pistol_run_f": 3.4, "pistol_run_b": 2.7}

@export var character_id := "alfa"
@export var team := 0
@export var max_health := 100.0
@export var is_player := false

var inp := ActorInput.new()
var injuries := Injuries.new()
var laser: MeshInstance3D           ## láser desde la boca del cañón hasta donde pega
var laser_dot: MeshInstance3D
var _bleed_t := 0.0
var blob: MeshInstance3D            ## sombra simple (círculo oscuro en el piso): reemplaza a las sombras reales en teléfonos flojos
var _thrown := false                ## lanzado por una explosión (choque contra pared / piso = lesión terciaria)
var _bad_fall := false              ## la próxima caída no es de pie (lanzado, derribado, soltado de un borde)
var state := State.GROUND
var health := 100.0
var facing := 1.0                   ## +1 mira a +X, -1 a -X
var aim_dir := Vector2(1, 0)        ## PERSISTENTE, en el mundo
var recoil_angle := 0.0             ## patada del arma (se recupera sola; no cambia aim_dir)
var speed_target := 0.0
var crouching := false
var stunned := 0.0
var noise_level := 0.0              ## último ruido de pasos (radio en m), para el HUD
var floor_name := 0                 ## piso actual (lo calcula el mapa)
var model: Node3D
var skel: Skeleton3D
var ap: AnimationPlayer
var ik: ArmIK
var slot: Node3D                    ## arma de fuego entre las manos (lo coloca ArmIK)
var knife_node: Node3D
var hand_r: BoneAttachment3D
var hitboxes: Array[Area3D] = []
var reach: Area3D
## inventario de armas
var weapons := {}                   ## "primary"/"secondary" → Firearm
var current := "fists"              ## "primary" | "secondary" | "knife" | "fists"
var has_knife := true
var grenades := {"frag": 2, "smoke": 1, "stun": 0, "incendiary": 0, "c4": 0}
var grenade_kind := "frag"
var inventory: Inventory
var loot_value := 0
var last_hit_info := {}
var killer: Node = null
## estado interno
var _anim := ""
var _action_anim := ""
var _action_t := 0.0
var _action_cb := Callable()
var _action_events: Array = []      ## [[fracción, Callable, hecho]]
var _air_top := 0.0
var _step_t := 0.0
var _combo := 0
var _combo_t := 0.0
var _ladder: Ladder
var _ladder_cool := 0.0
var _hang_top := Vector3.ZERO
var _hang_wall_x := 0.0
var _climb_from := Vector3.ZERO
var _climb_to := Vector3.ZERO
var _climb_t := 0.0
var _climb_len := 1.0
var _grab_cool := 0.0
var _grenade_hold := false
var _yaw := 0.0
var _ik_w := 0.0
var _model_offset := Vector3.ZERO
var plane_shift := Vector3.ZERO     ## desplaza el modelo (no la física): el modo práctica pone la zona elegida en el plano de tiro z = 0
var _cap: CollisionShape3D
var _time := 0.0
var _down_t := 0.0
var interact_target: Node = null    ## lo que se puede USAR ahora (para el botón contextual)
var action_progress := -1.0         ## 0..1 mientras se fuerza una caja, etc. (barra del HUD)

func _ready() -> void:
	health = max_health
	collision_layer = 2
	collision_mask = 1 | 8
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.3
	safe_margin = 0.02
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY
	_cap = CollisionShape3D.new()
	var c := CapsuleShape3D.new()
	c.radius = 0.28
	c.height = 1.74
	_cap.shape = c
	_cap.position.y = 0.87
	add_child(_cap)
	_build_body()
	_build_reach()
	_build_blob()
	inventory = Inventory.new()
	if is_player:
		add_to_group("player")
	add_to_group("actors")
	_yaw = facing * deg_to_rad(70.0)

# ---------------------------------------------------------------- construcción

func _build_body() -> void:
	model = CharacterModel.instantiate(character_id)
	model.name = "Body"
	add_child(model)
	skel = model.get_node("Skeleton3D")
	ap = AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	model.add_child(ap)
	ap.add_animation_library("", CharacterModel.anim_library(character_id))
	ap.playback_default_blend_time = 0.18
	ik = ArmIK.new()
	ik.name = "ArmIK"
	skel.add_child(ik)
	ik.setup()
	ik.curl_r = -1.0
	ik.curl_l = -1.0
	ik.grip_r = {}
	ik.grip_l = {}
	ik.enabled_arms = false
	slot = Node3D.new()
	slot.name = "WeaponSlot"
	skel.add_child(slot)
	ik.weapon_node = slot
	hand_r = BoneAttachment3D.new()
	hand_r.bone_name = P + "RightHand"
	skel.add_child(hand_r)
	knife_node = _make_knife()
	hand_r.add_child(knife_node)
	knife_node.visible = false
	_build_hitboxes()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).set_meta("actor_mesh", true)
	_play("idle", 0.0)

## Cuchillo de combate (procedural: hoja + guarda + mango). Se reemplaza por un GLB cuando exista.
func _make_knife() -> Node3D:
	var root := Node3D.new()
	root.name = "Knife"
	var blade := MeshInstance3D.new()
	var bm := PrismMesh.new()
	bm.size = Vector3(0.028, 0.17, 0.006)
	blade.mesh = bm
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.72, 0.74, 0.76)
	steel.metallic = 0.9
	steel.roughness = 0.25
	blade.material_override = steel
	blade.position = Vector3(0, 0.165, 0)
	root.add_child(blade)
	var guard := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.05, 0.012, 0.018)
	guard.mesh = gm
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.08)
	dark.roughness = 0.6
	guard.material_override = dark
	guard.position = Vector3(0, 0.075, 0)
	root.add_child(guard)
	var handle := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.014
	hm.bottom_radius = 0.016
	hm.height = 0.11
	handle.mesh = hm
	handle.material_override = dark
	handle.position = Vector3(0, 0.02, 0)
	root.add_child(handle)
	# en el espacio del hueso de la mano Mixamo: Y va hacia los dedos; el cuchillo sale por el lado del pulgar
	root.position = Vector3(0.0, 0.08, 0.03)
	root.rotation = Vector3(deg_to_rad(90), 0, 0)
	return root

## Zonas de impacto: cápsulas en los huesos (capa 3). Los proyectiles y los golpes leen "zone" y "bone".
func _build_hitboxes() -> void:
	var defs := [["Head", "head", 0.13, 0.0], ["Neck", "neck", 0.07, 0.0], ["Spine2", "torso", 0.17, 0.0],
		["Spine", "torso", 0.16, 0.0], ["Hips", "pelvis", 0.16, 0.0],
		["LeftArm", "arm", 0.06, 1.0], ["LeftForeArm", "arm", 0.05, 1.0], ["RightArm", "arm", 0.06, 1.0],
		["RightForeArm", "arm", 0.05, 1.0], ["LeftUpLeg", "leg", 0.085, 1.0], ["LeftLeg", "leg", 0.065, 1.0],
		["RightUpLeg", "leg", 0.085, 1.0], ["RightLeg", "leg", 0.065, 1.0],
		["LeftHand", "hand", 0.05, 1.0], ["RightHand", "hand", 0.05, 1.0], ["LeftFoot", "foot", 0.055, 1.0], ["RightFoot", "foot", 0.055, 1.0]]
	for d in defs:
		var b := skel.find_bone(P + str(d[0]))
		if b < 0:
			continue
		var att := BoneAttachment3D.new()
		att.bone_name = P + str(d[0])
		skel.add_child(att)
		var area := Area3D.new()
		area.collision_layer = 4
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		area.set_meta("actor", self)
		area.set_meta("zone", d[1])
		area.set_meta("bone", P + str(d[0]))
		var cs := CollisionShape3D.new()
		var r: float = d[2]
		var length := 0.25
		var kids := skel.get_bone_children(b)
		if not kids.is_empty():
			length = skel.get_bone_global_rest(kids[0]).origin.distance_to(skel.get_bone_global_rest(b).origin)
		if d[1] == "head":
			var s := SphereShape3D.new()
			s.radius = r
			cs.shape = s
			cs.position = Vector3(0, 0.09, 0.02)
		else:
			var cap := CapsuleShape3D.new()
			cap.radius = r
			cap.height = maxf(length + (r * 2.0 if d[3] > 0.0 else r), r * 2.0 + 0.01)
			cs.shape = cap
			cs.position = Vector3(0, length * 0.5, 0)
		area.add_child(cs)
		att.add_child(area)
		hitboxes.append(area)

static var _blob_mat: StandardMaterial3D
func _build_blob() -> void:
	if _blob_mat == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0.62), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_blob_mat = StandardMaterial3D.new()
		_blob_mat.albedo_texture = t
		_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_mat.render_priority = 2
	blob = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 0.8)
	q.orientation = PlaneMesh.FACE_Y
	blob.mesh = q
	blob.material_override = _blob_mat
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.top_level = true
	blob.add_to_group("blob_shadow")
	add_child(blob)

func _update_blob() -> void:
	var on := Settings.shadows >= 1 and state != State.DEAD and visible
	blob.visible = on
	if not on:
		return
	var from := global_position + Vector3(0, 0.6, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0, 1 | 8)
	q.exclude = [get_rid()]
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	if h.is_empty():
		blob.visible = false
		return
	var k := clampf(1.0 - (from.y - (h.position as Vector3).y - 0.6) / 5.0, 0.2, 1.0)
	blob.global_position = (h.position as Vector3) + Vector3(0, 0.015, 0.05)
	blob.scale = Vector3.ONE * k

func _build_reach() -> void:
	reach = Area3D.new()
	reach.collision_layer = 0
	reach.collision_mask = 32
	reach.monitorable = false
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.9
	cs.shape = s
	cs.position = Vector3(0, 1.0, 0)
	reach.add_child(cs)
	add_child(reach)

func hitbox_rids() -> Array:
	var out := [get_rid()]
	for h in hitboxes:
		out.append(h.get_rid())
	return out

# ---------------------------------------------------------------- armas

func give_weapon(slot_name: String, weapon_id: String) -> Firearm:
	if weapons.has(slot_name):
		(weapons[slot_name] as Firearm).queue_free()
	var f := Firearm.create(weapon_id)
	f.visible = false
	slot.add_child(f)
	weapons[slot_name] = f
	if current == "fists" or current == slot_name:
		equip(slot_name)
	return f

func weapon() -> Firearm:
	return weapons.get(current) as Firearm

func equip(slot_name: String) -> void:
	if slot_name == "knife" and not has_knife:
		return
	if slot_name in ["primary", "secondary"] and not weapons.has(slot_name):
		return
	var w := weapon()
	if w:
		w.cancel_reload()
	current = slot_name
	for k in weapons:
		(weapons[k] as Firearm).visible = k == current
	knife_node.visible = current == "knife"
	var f := weapon()
	if f:
		ik.use_attached_weapon = true
		ik.enabled_arms = true
		# calibrar dónde va el arma respecto de la mano con una pose de apuntado (como en Nexus)
		var anim_name := "pistol_idle" if f.is_pistol else "idle_aim"
		var anim := ap.get_animation(anim_name)
		ik.calibrate_attach(anim, 0.0, f.grip, f.support, f.is_pistol)
		ik.grip_r = ArmIK.GRIP_PISTOL_R if f.is_pistol else ArmIK.GRIP_RIFLE_R
		ik.grip_l = ArmIK.GRIP_HANDGUARD_L
		Sfx.play("equip", global_position, -8.0)
	else:
		ik.use_attached_weapon = false
		ik.enabled_arms = false
		ik.grip_r = {}
		ik.grip_l = {}
		ik.weapon_target_w = 0.0
	_anim = ""
	weapon_changed.emit()

func cycle_weapon() -> void:
	var order := ["primary", "secondary", "knife", "fists"]
	var i := order.find(current)
	for n in range(1, 5):
		var cand: String = order[(i + n) % order.size()]
		if cand == "fists" or (cand == "knife" and has_knife) or weapons.has(cand):
			equip(cand)
			return

# ---------------------------------------------------------------- ciclo

func _physics_process(delta: float) -> void:
	_time += delta
	if injuries.deaf > 0.0:
		injuries.deaf = maxf(injuries.deaf - delta, 0.0)
		if is_player:
			Sfx.set_deaf(injuries.deaf)
	if injuries.bleeding > 0.0 and state != State.DEAD:
		health -= injuries.bleeding * delta
		_bleed_t -= delta
		if health <= 0.0:
			_die({"type": "bleed", "zone": "torso", "dir": Vector3.DOWN})
	_grab_cool = maxf(_grab_cool - delta, 0.0)
	_ladder_cool = maxf(_ladder_cool - delta, 0.0)
	stunned = maxf(stunned - delta, 0.0)
	_combo_t = maxf(_combo_t - delta, 0.0)
	recoil_angle = move_toward(recoil_angle, 0.0, delta * deg_to_rad(18.0))
	if state != State.DEAD:
		_update_aim(delta)
		_handle_weapon_input(delta)
	match state:
		State.GROUND, State.AIR:
			_move_free(delta)
		State.LADDER:
			_move_ladder(delta)
		State.HANG:
			_move_hang(delta)
		State.CLIMB:
			_move_climb(delta)
		State.ACTION, State.DOWN, State.DEAD:
			_move_locked(delta)
	position.z = 0.0
	velocity.z = 0.0
	_update_blob()
	_update_action(delta)
	_find_interactable()
	inp.clear_edges()

func _process(delta: float) -> void:
	_update_visual(delta)

# ---------------------------------------------------------------- apuntado

## Velocidad máxima de giro del apuntado con joystick (grados por segundo, con sensibilidad 1,0). El joystick sólo dice
## HACIA DÓNDE: el arma gira hacia ahí a esta velocidad (más lento cuanto menos se estira el joystick), así no salta.
const AIM_RATE := 170.0

func _update_aim(delta := 1.0 / 60.0) -> void:
	if inp.aim.length() > 0.2 and stunned <= 0.0:
		var tgt := inp.aim.normalized()
		if inp.aim_snap:
			aim_dir = tgt
		else:
			var a := aim_dir.angle()
			var diff := angle_difference(a, tgt.angle())
			var tilt := clampf((inp.aim.length() - 0.2) / 0.8, 0.0, 1.0)
			var rate := deg_to_rad(AIM_RATE) * (0.3 + 0.7 * tilt) * Settings.aim_sensitivity
			aim_dir = Vector2.from_angle(a + clampf(diff, -rate * delta, rate * delta))
	var armed := weapon() != null
	if not armed:
		# sin arma de fuego el cuerpo mira hacia donde camina (cuerpo a cuerpo); el apuntado queda guardado igual
		if absf(inp.move.x) > 0.3 and state == State.GROUND and _action_anim == "":
			facing = signf(inp.move.x)
		elif inp.aim.length() > 0.2 and absf(aim_dir.x) > 0.15:
			facing = signf(aim_dir.x)
	elif absf(aim_dir.x) > 0.08:
		facing = signf(aim_dir.x)

## Dirección de disparo (apuntado + retroceso), 3D en el plano del juego.
func fire_dir() -> Vector3:
	var sway := 0.0
	if injuries.arm > 0.0 or injuries.head > 0.0 or injuries.hand > 0.0:
		# brazo herido / conmoción: el arma tiembla y la puntería oscila
		sway = (sin(_time * 2.1) * 0.6 + sin(_time * 5.3) * 0.4) * deg_to_rad(2.5) * (injuries.aim_penalty() - 1.0)
	var a := Vector2(aim_dir.x, aim_dir.y).rotated(recoil_angle * facing + sway)
	return Vector3(a.x, a.y, 0.0).normalized()

## Ángulo vertical del apuntado respecto del frente del cuerpo (rad, + arriba).
func aim_pitch() -> float:
	return atan2(aim_dir.y, absf(aim_dir.x) if signf(aim_dir.x) == facing or absf(aim_dir.x) < 0.01 else -absf(aim_dir.x))

# ---------------------------------------------------------------- movimiento libre

static func speed_for(tilt: float) -> float:
	tilt = clampf(absf(tilt), 0.0, 1.0)
	if tilt < SPEED_CURVE[0][0]:
		return 0.0
	for i in range(1, SPEED_CURVE.size()):
		var a: Array = SPEED_CURVE[i - 1]
		var b: Array = SPEED_CURVE[i]
		if tilt <= b[0]:
			return lerpf(a[1], b[1], (tilt - a[0]) / (b[0] - a[0]))
	return SPEED_CURVE[-1][1]

func _move_free(delta: float) -> void:
	var on_floor := is_on_floor()
	var mx := inp.move.x if stunned <= 0.0 and _action_anim == "" else inp.move.x * 0.3
	if _action_anim in ["punch_jab", "punch_cross", "punch_hook", "kick_front", "kick_side", "stab", "stab_reverse", "throw_grenade"]:
		mx *= 0.25
	crouching = on_floor and (inp.crouch or (inp.move.y < -0.6 and absf(inp.move.x) < 0.5 and not _ladder_here())) and state == State.GROUND
	var target := speed_for(mx) * signf(mx)
	if crouching:
		target = clampf(target, -CROUCH_MAX, CROUCH_MAX)
	elif weapon() != null and signf(target) != facing and absf(target) > BACK_MAX:
		target = signf(target) * BACK_MAX
	if stunned > 0.0:
		target *= 0.4
	if injuries.paralysis:
		target = clampf(target, -0.35, 0.35)   # médula dañada: casi no puede moverse
	elif injuries.leg_broken:
		target = clampf(target, -1.1, 1.1)     # pierna fracturada: renguea (no corre) hasta usar venda o botiquín
	elif injuries.breath:
		target = clampf(target, -2.4, 2.4)     # pulmón perforado: no le da el aire para correr
	speed_target = target
	var vx := velocity.x
	if on_floor:
		var rate := ACCEL if absf(target) > absf(vx) and signf(target) == signf(vx) else DECEL
		vx = move_toward(vx, target, rate * delta)
	else:
		vx = move_toward(vx, target, ACCEL * AIR_CONTROL * delta)
	velocity.x = vx
	if not on_floor:
		velocity.y -= GRAVITY * delta
		_air_top = maxf(_air_top, global_position.y)
		if state != State.AIR:
			state = State.AIR
			_air_top = global_position.y
	# escaleras
	if _ladder_cool <= 0.0 and absf(inp.move.y) > 0.55 and absf(inp.move.y) > absf(inp.move.x) * 0.8:
		var l := _ladder_here()
		if l and l.can_enter(self, inp.move.y):
			_enter_ladder(l)
			return
	# salto / parkour contextual
	if inp.jump and on_floor and stunned <= 0.0 and _action_anim == "":
		if not _try_vault():
			velocity.y = JUMP_V * (0.55 if injuries.leg_broken else 1.0)
			state = State.AIR
			_air_top = global_position.y
			_play("jump_up", 0.08)
			Sfx.play("jump", global_position, -6.0, 1.0, 4.0, self)
	# agarrarse de un borde en el aire
	if state == State.AIR and _grab_cool <= 0.0 and stunned <= 0.0:
		if _try_grab():
			return
	var was_air := state == State.AIR
	var pre_speed := velocity.length()
	move_and_slide()
	if _thrown and (is_on_wall() or is_on_floor()) and pre_speed > 6.0:
		_thrown = false
		_bad_fall = true
		take_damage({"damage": (pre_speed - 5.0) * 4.0, "type": "impact", "speed": pre_speed, "zone": "torso",
			"bone": P + "Spine1", "point": global_position + Vector3.UP * 1.1, "dir": -velocity.normalized()})
	if was_air and is_on_floor():
		_on_land()
	elif state == State.GROUND and not is_on_floor():
		state = State.AIR
		_air_top = global_position.y
	_crouch_shape(crouching)
	_footsteps(delta)

func _crouch_shape(c: bool) -> void:
	var cap := _cap.shape as CapsuleShape3D
	var h := 1.2 if c else 1.74
	if not is_equal_approx(cap.height, h):
		cap.height = h
		_cap.position.y = h * 0.5

func _on_land() -> void:
	state = State.GROUND
	var h := _air_top - global_position.y
	var bad := _bad_fall or _thrown or absf(velocity.x) > 3.8
	_bad_fall = false
	_thrown = false
	landed.emit(h)
	if h > SAFE_FALL:
		var k := clampf((h - SAFE_FALL) / (DEADLY_FALL - SAFE_FALL), 0.0, 1.0)
		var dmg := lerpf(8.0, 110.0, k * k)
		Sfx.play("land", global_position, 2.0, 0.8, 18.0, self)
		Sfx.play("body_fall", global_position, 0.0, 1.0)
		TimeFx.shake(0.4 + k)
		var info := {"damage": dmg, "type": "fall", "zone": "leg", "bone": P + ("LeftLeg" if randf() < 0.5 else "RightLeg"),
			"point": global_position + Vector3.UP * 0.4, "dir": Vector3.DOWN, "fall_height": h, "bad_landing": bad}
		take_damage(info)
		if state != State.DEAD:
			_action("hard_landing", 1.4)
	elif h > 2.2 and absf(velocity.x) > 2.5:
		_action("land_roll", 1.3)
		Sfx.play("land", global_position, -4.0, 1.0, 8.0, self)
	elif h > 0.6:
		_play("jump_down", 0.05)
		Sfx.play("land", global_position, -8.0, 1.0, 6.0, self)

func _footsteps(delta: float) -> void:
	var sp := absf(velocity.x)
	if not is_on_floor() or sp < 0.3:
		noise_level = move_toward(noise_level, 0.0, delta * 10.0)
		return
	_step_t -= delta * sp
	# radio del ruido de pasos: sigilo casi nada, correr se oye desde lejos
	noise_level = lerpf(0.8, 16.0, clampf((sp - 0.5) / 4.7, 0.0, 1.0)) * (0.5 if crouching else 1.0)
	if _step_t <= 0.0:
		_step_t = 0.75
		var vol := lerpf(-22.0, -4.0, clampf(sp / 5.0, 0.0, 1.0))
		Sfx.play("step_concrete", global_position, vol, 1.0, noise_level, self)
		noise_made.emit(noise_level)

# ---------------------------------------------------------------- parkour

func _ray(from: Vector3, to: Vector3, mask := 1 | 8) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)

## Busca un borde delante (dir = ±1). Devuelve {wall_x, top} o {}.
func _probe_ledge(dir: float, min_h: float, max_h: float) -> Dictionary:
	var p := global_position
	var wall := {}
	for hh in [min_h - 0.15, (min_h + max_h) * 0.5 - 0.2, max_h - 0.25]:
		var w := _ray(p + Vector3(0, hh, 0), p + Vector3(dir * 0.75, hh, 0))
		if not w.is_empty() and absf((w.normal as Vector3).x) > 0.7:
			wall = w
			break
	if wall.is_empty():
		return {}
	var wx: float = (wall.position as Vector3).x
	var down := _ray(Vector3(wx + dir * 0.18, p.y + max_h + 0.5, 0), Vector3(wx + dir * 0.18, p.y + min_h - 0.3, 0))
	if down.is_empty() or (down.normal as Vector3).y < 0.7:
		return {}
	var top: float = (down.position as Vector3).y
	var h := top - p.y
	if h < min_h or h > max_h:
		return {}
	# espacio libre arriba del borde para pararse
	var clear := _ray(Vector3(wx + dir * 0.4, top + 0.1, 0), Vector3(wx + dir * 0.4, top + 1.6, 0))
	if not clear.is_empty():
		return {}
	return {"wall_x": wx, "top": top}

func _try_vault() -> bool:
	var dir := signf(inp.move.x) if absf(inp.move.x) > 0.25 else facing
	var l := _probe_ledge(dir, VAULT_MIN, 0.8 if injuries.leg_broken else VAULT_MAX)
	if l.is_empty() or absf(float(l.wall_x) - global_position.x) > 0.7:
		return false
	if float(l.top) - global_position.y <= JUMP_VAULT:
		# caja o tarima baja: alcanza con un salto (se da un empujón hacia adelante para caer encima), sin la animación de apoyarse
		velocity.x = dir * 3.2
		return false
	_start_climb(Vector3(float(l.wall_x) + dir * 0.4, float(l.top), 0), "climb_box", 1.6, dir)
	Sfx.play("gear_rattle", global_position, -8.0, 1.0, 5.0, self)
	return true

func _try_grab() -> bool:
	var dir := signf(inp.move.x) if absf(inp.move.x) > 0.2 else signf(velocity.x) if absf(velocity.x) > 0.3 else facing
	if inp.move.y < -0.5:
		return false
	var l := _probe_ledge(dir, HANG_REACH_MIN, HANG_REACH_MAX)
	if l.is_empty():
		return false
	state = State.HANG
	_hang_top = Vector3(float(l.wall_x), float(l.top), 0)
	_hang_wall_x = float(l.wall_x)
	facing = dir
	velocity = Vector3.ZERO
	global_position = Vector3(_hang_wall_x - dir * 0.34, float(l.top) - 1.92, 0)
	_play("hang_catch", 0.06)
	_action_anim = ""
	Sfx.play("gear_rattle", global_position, -6.0, 1.1, 5.0, self)
	return true

func _move_hang(_delta: float) -> void:
	velocity = Vector3.ZERO
	if _anim == "hang_catch" and not ap.is_playing():
		_play("hang_idle", 0.15)
	if inp.jump or inp.move.y > 0.5 or (signf(inp.move.x) == facing and absf(inp.move.x) > 0.6):
		_start_climb(Vector3(_hang_wall_x + facing * 0.42, _hang_top.y, 0), "hang_climb", 1.15, facing)
	elif inp.move.y < -0.5 or (signf(inp.move.x) == -facing and absf(inp.move.x) > 0.6):
		state = State.AIR
		_air_top = global_position.y
		_grab_cool = 0.5
		_play("falling", 0.15)

func _start_climb(to: Vector3, anim_name: String, speed: float, dir: float) -> void:
	state = State.CLIMB
	facing = dir
	_climb_from = global_position
	_climb_to = to
	_climb_t = 0.0
	var a := ap.get_animation(anim_name)
	if injuries.leg_broken:
		speed *= 0.6          # con la pierna rota trepa despacio
	_climb_len = (a.length if a else 1.0) / speed
	_play(anim_name, 0.08, speed)
	velocity = Vector3.ZERO
	_cap.disabled = true

func _move_climb(delta: float) -> void:
	_climb_t += delta
	var k := clampf(_climb_t / _climb_len, 0.0, 1.0)
	# primero sube (con el cuerpo pegado a la pared), después avanza sobre el borde
	var ky := smoothstep(0.0, 0.7, k)
	var kx := smoothstep(0.45, 1.0, k)
	global_position = Vector3(lerpf(_climb_from.x, _climb_to.x, kx), lerpf(_climb_from.y, _climb_to.y, ky), 0)
	if k >= 1.0:
		_cap.disabled = false
		state = State.GROUND
		_anim = ""
		velocity = Vector3.ZERO

# ---------------------------------------------------------------- escaleras

func _ladder_here() -> Ladder:
	for a in reach.get_overlapping_areas():
		if a is Ladder:
			return a
	return null

func _enter_ladder(l: Ladder) -> void:
	_ladder = l
	state = State.LADDER
	velocity = Vector3.ZERO
	_cap.disabled = true
	var y := clampf(global_position.y, l.bottom_y, l.top_y - 1.4)
	if inp.move.y < 0.0 and global_position.y > l.top_y - 0.5:
		# bajar desde arriba: se toma la escalera de espaldas al vacío
		y = l.top_y - 1.5
	global_position = Vector3(l.global_position.x, y, 0)
	_play("ladder_climb", 0.2, 0.0)
	Sfx.play("gear_rattle", global_position, -10.0, 1.0, 3.0, self)

func _move_ladder(delta: float) -> void:
	var l := _ladder
	if l == null:
		state = State.AIR
		_cap.disabled = false
		return
	var v := inp.move.y if absf(inp.move.y) > 0.2 else 0.0
	var spd := LADDER_SPEED * (0.5 if injuries.leg_broken else 1.0) * clampf(absf(v) * 1.2, 0.0, 1.0) * signf(v)
	global_position.y += spd * delta
	# la animación avanza al ritmo de la subida: un ciclo de Climbing_Ladder = dos peldaños
	var cyc := ap.get_animation("ladder_climb")
	var drift: Vector3 = cyc.get_meta("drift", Vector3(0, 0.6, 0)) if cyc else Vector3(0, 0.6, 0)
	var per_cycle := maxf(absf(drift.y), 0.3)
	ap.speed_scale = spd / per_cycle * (cyc.length if cyc else 0.77)
	_step_t -= absf(spd) * delta
	if _step_t <= 0.0 and absf(spd) > 0.1:
		_step_t = 0.3
		Sfx.play("ladder_step", global_position + Vector3.UP, -10.0, randf_range(0.9, 1.1), 4.0, self)
	if global_position.y >= l.top_y - 1.45 and v > 0.0:
		# arriba: trepar al piso con la animación de salida
		ap.speed_scale = 1.0
		_ladder = null
		_start_climb(Vector3(l.global_position.x + l.exit_dir * 0.6, l.top_y, 0), "ladder_top", 2.6, l.exit_dir if l.exit_dir != 0.0 else facing)
		return
	if global_position.y <= l.bottom_y + 0.02 and v < 0.0:
		_exit_ladder()
		return
	if inp.jump:
		_exit_ladder()
		velocity = Vector3(facing * 2.0, 2.0, 0)
		state = State.AIR
		_air_top = global_position.y

func _exit_ladder() -> void:
	_ladder = null
	_ladder_cool = 0.4
	_cap.disabled = false
	ap.speed_scale = 1.0
	state = State.AIR
	_air_top = global_position.y
	_anim = ""

# ---------------------------------------------------------------- acciones (animaciones de una vez)

func _move_locked(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if state == State.DOWN:
		_down_t -= delta
		if _down_t <= 0.0:
			state = State.ACTION
			_action("getting_up", 1.4, func(): state = State.GROUND)

## Reproduce una animación de una sola vez. events: [[fracción 0..1, Callable]] (golpe, soltar granada…).
func _action(anim_name: String, speed := 1.0, done := Callable(), events := []) -> void:
	if ap.get_animation(anim_name) == null:
		if done.is_valid():
			done.call()
		return
	_action_anim = anim_name
	_action_t = 0.0
	_action_cb = done
	_action_events = []
	for e in events:
		_action_events.append([e[0], e[1], false])
	_play(anim_name, 0.1, speed, true)

func _update_action(delta: float) -> void:
	if _action_anim == "":
		return
	var a := ap.get_animation(_action_anim)
	var len_s := a.length / maxf(absf(ap.speed_scale), 0.01) if a else 0.5
	_action_t += delta
	var k := _action_t / maxf(len_s, 0.01)
	for e in _action_events:
		if not e[2] and k >= e[0]:
			e[2] = true
			(e[1] as Callable).call()
	if k >= 0.97:
		var cb := _action_cb
		_action_anim = ""
		_anim = ""
		_action_cb = Callable()
		if cb.is_valid():
			cb.call()

func busy() -> bool:
	return _action_anim != "" or state in [State.LADDER, State.HANG, State.CLIMB, State.ACTION, State.DOWN, State.DEAD]

# ---------------------------------------------------------------- combate

func _handle_weapon_input(delta: float) -> void:
	var w := weapon()
	if w:
		w.tick(delta)
	if inp.switch_to != "" and _action_anim == "" and state in [State.GROUND, State.AIR]:
		if inp.switch_to == "next":
			cycle_weapon()
		else:
			equip(inp.switch_to)
	if state in [State.LADDER, State.HANG, State.CLIMB, State.ACTION, State.DOWN] or stunned > 0.0:
		return
	if inp.reload and w and w.start_reload():
		pass
	if inp.melee and (_action_anim == "" or _combo_t > 0.0):
		_melee()
	# granada: mantener = mostrar el arco, soltar = lanzar
	if inp.grenade and not _grenade_hold and grenades.get(grenade_kind, 0) > 0 and _action_anim == "":
		_grenade_hold = true
	elif not inp.grenade and _grenade_hold:
		_grenade_hold = false
		_throw_grenade()
	if w and _action_anim == "" and inp.fire and not w.reloading and state != State.CLIMB:
		if w.trigger(true, _time):
			_shoot(w)
	elif w:
		w.trigger(false, _time)
	if w and w.mag == 0 and w.reserve > 0 and not w.reloading and inp.fire:
		w.start_reload()

func _shoot(w: Firearm) -> void:
	var st := w.stats
	var from := w.muzzle_world()
	from.z = 0.0
	# si la boca del arma quedó metida en una pared, el disparo sale desde el hombro (no atraviesa paredes)
	var chest := global_position + Vector3(0, 1.35 if not crouching else 0.95, 0)
	var wall := _ray(chest, from, 1)
	if not wall.is_empty():
		from = (wall.position as Vector3) - fire_dir() * 0.05
	var exclude := hitbox_rids()
	var first := -1
	for n in int(st.pellets):
		var spread := deg_to_rad(float(st.spread)) * (0.6 if crouching else 1.0) * (1.4 if absf(velocity.x) > 2.5 else 1.0) * injuries.aim_penalty()
		var d := fire_dir().rotated(Vector3.BACK, randf_range(-spread, spread) * 0.5)
		if Ballistics.instance:
			var idx := Ballistics.instance.fire(from, d, float(st.speed), float(st.damage), self, exclude,
				{"penetration": st.penetration, "drag": st.drag, "ricochet": st.ricochet})
			if first < 0:
				first = idx
	recoil_angle = minf(recoil_angle + deg_to_rad(float(st.recoil)) * (0.6 if crouching else 1.0), deg_to_rad(14.0))
	Fx.muzzle(w.muzzle_world(), fire_dir())
	Sfx.play(str(st.sound), from, 0.0, 1.0, float(st.noise), self)
	if Fx.has_method("emit"):
		pass
	shot_fired.emit(first, w)
	if is_player:
		TimeFx.shake(0.04 + float(st.recoil) * 0.01)

const COMBO := ["punch_jab", "punch_cross", "kick_front"]
const MELEE := {
	"punch_jab": {"t": 0.32, "dmg": 9.0, "h": 1.45, "reach": 0.75, "speed": 1.5, "force": 1.5, "sound": "punch"},
	"punch_cross": {"t": 0.38, "dmg": 13.0, "h": 1.45, "reach": 0.8, "speed": 1.4, "force": 2.0, "sound": "punch"},
	"punch_hook": {"t": 0.42, "dmg": 15.0, "h": 1.5, "reach": 0.75, "speed": 1.3, "force": 2.5, "sound": "punch"},
	"kick_front": {"t": 0.42, "dmg": 20.0, "h": 0.95, "reach": 1.0, "speed": 1.35, "force": 4.0, "sound": "kick"},
	"kick_side": {"t": 0.45, "dmg": 24.0, "h": 1.05, "reach": 1.1, "speed": 1.2, "force": 5.0, "sound": "kick"},
	"stab": {"t": 0.42, "dmg": 45.0, "h": 1.3, "reach": 0.85, "speed": 1.6, "force": 1.0, "sound": "knife_stab"},
	"stab_reverse": {"t": 0.45, "dmg": 55.0, "h": 1.35, "reach": 0.85, "speed": 1.5, "force": 1.0, "sound": "knife_stab"},
}

func _melee() -> void:
	var anim_name: String
	if current == "knife":
		anim_name = "stab" if _combo % 2 == 0 else "stab_reverse"
	else:
		anim_name = COMBO[_combo % COMBO.size()]
	_combo += 1
	_combo_t = 0.75
	if _combo >= 3 and current != "knife":
		_combo = 0
	var m: Dictionary = MELEE[anim_name]
	var w := weapon()
	if w:
		w.visible = false       # el arma se guarda un instante para golpear
	var f := facing
	_action(anim_name, m.speed, func():
		if weapon():
			weapon().visible = true
		, [[m.t / ap.get_animation(anim_name).length * m.speed if ap.get_animation(anim_name) else 0.4, func(): _melee_hit(anim_name, f)]])
	Sfx.play("swing", global_position + Vector3.UP * 1.3, -10.0, randf_range(0.9, 1.15), 3.0, self)

func _melee_hit(anim_name: String, dir: float) -> void:
	var m: Dictionary = MELEE[anim_name]
	var center := global_position + Vector3(dir * float(m.reach) * 0.7, float(m.h), 0)
	var shape := SphereShape3D.new()
	shape.radius = 0.38
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, center)
	q.collision_mask = 4 | 8
	q.collide_with_areas = true
	q.exclude = hitbox_rids()
	var res := get_world_3d().direct_space_state.intersect_shape(q, 16)
	var best: Area3D = null
	var best_rank := 99
	var hit_destructible := false
	for r in res:
		var c: Object = r.collider
		if c is Area3D and (c as Area3D).has_meta("actor") and (c as Area3D).get_meta("actor") != self:
			var rank: int = ["head", "neck", "torso", "pelvis", "arm", "leg"].find(str((c as Area3D).get_meta("zone")))
			# el puño busca la cabeza, la patada el torso
			if anim_name.begins_with("kick") and rank <= 1:
				rank += 2
			if rank < best_rank:
				best_rank = rank
				best = c
		elif c is Node and (c as Node).has_method("apply_damage") and not hit_destructible:
			hit_destructible = true
			(c as Node).apply_damage(float(m.dmg) * (1.5 if current == "knife" else 1.0), center, Vector3(dir, 0, 0), "melee", self)
			Sfx.play("impact_wood", center, -4.0, 1.0, 10.0, self)
	if best:
		var target: Node = best.get_meta("actor")
		var info := {"damage": float(m.dmg), "type": "knife" if current == "knife" else ("kick" if anim_name.begins_with("kick") else "punch"),
			"zone": best.get_meta("zone"), "bone": best.get_meta("bone"), "point": center, "dir": Vector3(dir, 0.1, 0),
			"shooter": self, "force": m.force, "anim": anim_name}
		target.take_damage(info)
		Sfx.play(str(m.sound), center, 0.0, randf_range(0.9, 1.1), 14.0, self)
		TimeFx.hitstop(0.045 if current != "knife" else 0.06)
		if is_player:
			TimeFx.shake(0.15)

func _throw_grenade() -> void:
	if grenades.get(grenade_kind, 0) <= 0 or busy():
		return
	grenades[grenade_kind] -= 1
	var kind := grenade_kind
	var w := weapon()
	if w:
		w.visible = false
	Sfx.play("grenade_pin", global_position + Vector3.UP * 1.4, -6.0, 1.0, 4.0, self)
	_action("throw_grenade", 2.2, func():
		if weapon():
			weapon().visible = true
		, [[0.42, func(): _release_grenade(kind)]])

## Velocidad inicial de la granada (para el arco del HUD y para el lanzamiento real).
func grenade_velocity() -> Vector3:
	var d := Vector3(aim_dir.x, aim_dir.y, 0).normalized()
	if absf(d.x) < 0.05:
		d.x = facing * 0.05
	return d * 11.0 + Vector3(velocity.x * 0.5, 1.5, 0)

func grenade_origin() -> Vector3:
	return global_position + Vector3(facing * 0.3, 1.6, 0)

func _release_grenade(kind: String) -> void:
	var g := Grenade.spawn(get_parent(), kind, grenade_origin(), grenade_velocity(), self)
	if g == null:
		return

# ---------------------------------------------------------------- daño

func take_damage(info: Dictionary) -> void:
	if state == State.DEAD:
		return
	var zone := str(info.get("zone", "torso"))
	var t := str(info.get("type", ""))
	var amount := float(info.get("damage", 10.0))
	if t in ["bullet", "fragment"]:
		amount *= float(ZONE_MULT.get(zone, 1.0))
	elif t == "punch" and zone in ["torso", "pelvis"]:
		amount *= 0.6                  # al cuerpo duele, pero menos que a la cara
	# lo que se rompe por dentro (anatomía real) suma su propio daño
	var res: Dictionary = injuries.process(self, info) if skel else {}
	info["injuries"] = res.get("texts", [])
	info["anatomy_nodes"] = res.get("nodes", [])
	info["anatomy_main"] = res.get("main", "")
	info["bullet_path"] = res.get("path", [])
	info["seq0"] = res.get("seq0", 0)
	info["seq1"] = res.get("seq1", 0)
	if t in ["bullet", "fragment", "knife"]:
		amount = amount * 0.5 + float(res.get("hp", 0.0))
	else:
		amount += float(res.get("hp", 0.0))
	var src = info.get("shooter")
	if is_player and src is Actor and is_instance_valid(src) and (src as Actor).team != team:
		amount *= BOT_DAMAGE_TO_PLAYER
	if bool(res.get("death", false)):
		amount = maxf(amount, health + 1.0)
	if is_player and Settings.haptics and amount > 3.0:
		Input.vibrate_handheld(clampi(int(amount * 4.0), 30, 220))
	info["final_damage"] = amount
	info["victim"] = self
	health -= amount
	info["lethal"] = health <= 0.0
	last_hit_info = info
	damaged.emit(info)
	var dir: Vector3 = info.get("dir", Vector3(-facing, 0, 0))
	if t in ["bullet", "fragment", "knife", "blast", "impact"] or (t in ["punch", "kick"] and amount > 12.0):
		var bp: Vector3 = info.get("point", global_position + Vector3.UP * 1.2)
		var through: bool = t == "bullet" and zone in ["head", "neck", "arm", "leg", "hand", "foot"]
		if Blood.instance:
			Blood.instance.spray(bp, dir, through, amount > 30.0)      # entrada y, si atravesó, salida
		else:
			Fx.blood(bp, dir, 1.0)
	if health <= 0.0:
		_die(info)
		return
	_react(info, amount)

func _react(info: Dictionary, amount: float) -> void:
	if state in [State.LADDER, State.HANG]:
		if amount > 25.0:
			if state == State.LADDER:
				_exit_ladder()
			else:
				state = State.AIR
			_play("falling", 0.1)
		return
	if state in [State.CLIMB, State.DOWN]:
		return
	var zone := str(info.get("zone", "torso"))
	var t := str(info.get("type", "bullet"))
	var dir: Vector3 = info.get("dir", Vector3.ZERO)
	var force := float(info.get("force", 0.0))
	var anim_name := "hit_small"
	if t in ["punch", "kick"]:
		if zone in ["head", "neck"]:
			anim_name = "hit_uppercut" if str(info.get("anim", "")) == "punch_hook" else ("hit_head_big" if amount > 12 else "hit_head")
		else:
			anim_name = "hit_stomach_big" if amount > 15 else "hit_stomach"
		velocity.x += signf(dir.x) * force
		if force >= 4.0 and randf() < 0.35:
			_knock_down()
			return
	elif t == "blast":
		_knock_down()
		return
	elif t == "fall":
		return
	elif zone in ["head", "neck"]:
		anim_name = "hit_head_big"
	elif amount > 28:
		anim_name = "hit_gut_shot"
	# no cortar una acción importante con un golpecito
	if _action_anim in ["throw_grenade", "hard_landing", "getting_up"] and amount < 20:
		return
	if weapon():
		weapon().visible = true
	_action(anim_name, 1.3)
	if stunned <= 0.0 and amount > 20:
		stunned = 0.25

func _knock_down() -> void:
	state = State.DOWN
	_down_t = 1.6
	_action("knocked_down", 1.2)
	Sfx.play("body_fall", global_position, -2.0, 1.0, 10.0, self)

## Explosión: empuje que puede tirar al personaje contra paredes y piso.
func throw(v: Vector3) -> void:
	if state == State.LADDER:
		_exit_ladder()
	elif state == State.HANG:
		state = State.AIR
	velocity += v
	if v.length() > 4.0:
		_thrown = true
		if state == State.GROUND:
			state = State.AIR
			_air_top = global_position.y

func stun(seconds: float) -> void:
	stunned = maxf(stunned, seconds)

func heal(amount: float) -> void:
	if state != State.DEAD:
		health = minf(health + amount, max_health)

func _die(info: Dictionary) -> void:
	state = State.DEAD
	killer = info.get("shooter")
	_cap.disabled = false
	_action_anim = ""
	var dir: Vector3 = info.get("dir", Vector3(-facing, 0, 0))
	var from_front := signf(dir.x) == -facing
	var anim_name := "death_head" if str(info.get("zone", "")) == "head" else ("death_fall_back" if from_front else "death_fall_fwd")
	if str(info.get("type", "")) in ["blast", "fall"]:
		anim_name = "death_chest"
	ik.enabled_arms = false
	ik.use_attached_weapon = false
	var w := weapon()
	if w:
		w.visible = false
	_play(anim_name, 0.12, 1.0, true)
	injuries.on_death()
	if Blood.instance and (injuries.bleeding > 0.0 or str(info.get("type", "")) in ["bullet", "fragment", "knife", "blast"]):
		var pos := global_position
		get_tree().create_timer(1.2).timeout.connect(func(): if Blood.instance: Blood.instance.pool(pos))
	collision_layer = 0
	for h in hitboxes:
		h.collision_layer = 0
	Sfx.play("body_fall", global_position, 0.0, 1.0, 12.0, self)
	died.emit(info)

func is_dead() -> bool:
	return state == State.DEAD

# ---------------------------------------------------------------- interacción

func _find_interactable() -> void:
	interact_target = null
	if state != State.GROUND or busy():
		action_progress = -1.0 if state != State.ACTION else action_progress
		return
	var best: Node = null
	var bd := 999.0
	for a in reach.get_overlapping_areas():
		if a is Interactable and (a as Interactable).can_use(self):
			var d := (a as Node3D).global_position.distance_to(global_position + Vector3.UP)
			if d < bd:
				bd = d
				best = a
	interact_target = best
	if inp.interact and best:
		(best as Interactable).use(self)

## Acción larga con barra (forzar una caja con el cuchillo, apretar el botón del ascensor…).
func begin_task(anim_name: String, seconds: float, on_done: Callable, on_tick := Callable(), cancel_on_move := true) -> void:
	state = State.ACTION
	velocity.x = 0.0
	action_progress = 0.0
	var a := ap.get_animation(anim_name)
	_play(anim_name, 0.2, 1.0, true)
	var t0 := _time
	var tick_t := [0.0]
	var check := func(_d: float) -> bool:
		if state != State.ACTION:
			return true
		if cancel_on_move and (absf(inp.move.x) > 0.6 or inp.jump):
			state = State.GROUND
			action_progress = -1.0
			_anim = ""
			return true
		action_progress = clampf((_time - t0) / seconds, 0.0, 1.0)
		if on_tick.is_valid():
			tick_t[0] += _d
			on_tick.call(action_progress)
		if action_progress >= 1.0:
			state = State.GROUND
			action_progress = -1.0
			_anim = ""
			on_done.call()
			return true
		return false
	_task = check
	if a == null:
		pass

var _task := Callable()
func _notification(what: int) -> void:
	if what == NOTIFICATION_PHYSICS_PROCESS and _task.is_valid():
		if _task.call(get_physics_process_delta_time()):
			_task = Callable()

# ---------------------------------------------------------------- imagen (animación + pose del arma)

func _play(anim_name: String, blend := 0.18, speed := 1.0, force := false) -> void:
	if ap == null or ap.get_animation(anim_name) == null:
		return
	if anim_name == _anim and not force:
		ap.speed_scale = speed
		return
	_anim = anim_name
	ap.play(anim_name, blend)
	ap.speed_scale = speed
	if force:
		ap.seek(0.0, true)

func _loco_anim() -> Array:
	var sp := velocity.x
	var aspeed := absf(sp)
	var fwd := signf(sp) == facing or aspeed < 0.05
	var w := weapon()
	var pistol := w != null and w.is_pistol
	if state == State.AIR:
		return ["jump_loop" if velocity.y > -4.0 else "falling", 1.0]
	if crouching:
		if aspeed < 0.12:
			return ["crouch_aim" if w else "crouch_idle", 1.0]
		var c := "cwalk_f" if fwd else "cwalk_b"
		return [c, aspeed / CLIP_SPEED[c]]
	if injuries.leg_broken and not crouching:
		if aspeed < 0.12:
			return ["injured_idle" if w == null else ("pistol_idle" if pistol else "idle_aim"), 1.0]
		var iw := "injured_walk_f" if fwd else "injured_walk_b"
		return [iw, clampf(aspeed / float(CLIP_SPEED[iw]), 0.5, 1.4)]
	if aspeed < 0.12:
		if w:
			return ["pistol_idle" if pistol else "idle_aim", 1.0]
		return ["knife_idle" if current == "knife" else "idle", 1.0]
	var base := ""
	if aspeed < 2.3:
		base = "walk"
	elif aspeed < 4.4 or not fwd:
		base = "run"
	else:
		base = "sprint"
	var n := ("pistol_" if pistol and base != "sprint" else "") + base + ("_f" if fwd else "_b")
	if not CLIP_SPEED.has(n):
		n = base + ("_f" if fwd else "_b")
	return [n, clampf(aspeed / float(CLIP_SPEED.get(n, 1.4)), 0.45, 1.7)]

func _update_visual(delta: float) -> void:
	if model == null:
		return
	# --- animación de base
	if _action_anim == "" and state in [State.GROUND, State.AIR] and state != State.DEAD:
		var la := _loco_anim()
		if not (_anim == "jump_up" and ap.is_playing()) and not (_anim == "jump_down" and ap.is_playing() and absf(velocity.x) < 0.5):
			_play(la[0], 0.2, la[1])
	# --- orientación del cuerpo: 3/4 hacia la cámara mirando a donde apunta
	var target_yaw := facing * deg_to_rad(70.0)
	_model_offset = plane_shift
	if state == State.LADDER:
		# Climbing_Ladder de Mixamo viene girado 180° respecto de las demás: con 0 queda de espaldas a la cámara, mirando la pared
		target_yaw = 0.0
		_model_offset = Vector3(0, 0, (_ladder.global_position.z + 0.42) if _ladder else -0.5)
	elif state in [State.HANG, State.CLIMB]:
		target_yaw = facing * deg_to_rad(90.0)
	_yaw = lerp_angle(_yaw, target_yaw, clampf(delta * 12.0, 0.0, 1.0))
	model.rotation = Vector3(0, _yaw, 0)
	model.position = model.position.lerp(_model_offset, clampf(delta * 10.0, 0.0, 1.0))
	# --- pose del arma: ArmIK la lleva a la dirección de apuntado del mundo y las manos la siguen
	var w := weapon()
	var aiming := w != null and state in [State.GROUND, State.AIR] and _action_anim == "" and not w.reloading
	_ik_w = move_toward(_ik_w, 1.0 if aiming else 0.0, delta * 6.0)
	_update_laser(w, aiming and _ik_w > 0.6)
	if state == State.DEAD:
		_ik_w = 0.0
	var mb := model.global_basis.orthonormalized()
	ik.body_fwd = mb.z
	ik.body_right = -mb.x
	ik.body_up = Vector3.UP
	if w and _ik_w > 0.001:
		ik.weapon_target = _weapon_target(w)
		ik.weapon_aim_dir = fire_dir()
		ik.weapon_butt = w.butt
		ik.weapon_aim_facing = facing
		ik.weapon_target_w = _ik_w
		# al apuntar hacia arriba el torso se echa hacia atrás (más cuanto más arriba), la cabeza acompaña un poco menos
		var pitch := clampf(aim_pitch(), deg_to_rad(-70), deg_to_rad(80))
		ik.spine_pitch = pitch * (0.5 + 0.2 * absf(pitch) / deg_to_rad(80.0)) * _ik_w
		ik.head_pitch = pitch * 0.25 * _ik_w
		ik.left_grip_weight = 1.0
	else:
		ik.weapon_aim_dir = Vector3.ZERO
		ik.weapon_target_w = 0.0
		ik.spine_pitch = 0.0
		ik.head_pitch = 0.0
	ik.enabled_arms = w != null and state not in [State.LADDER, State.HANG, State.CLIMB, State.DEAD]

## Transform (mundo) del arma apuntando en aim_dir: culata en el hombro derecho (fusiles) o brazos estirados (pistola).
func _weapon_target(w: Firearm) -> Transform3D:
	var sr := ik.shoulder_world(true)
	var sl := ik.shoulder_world(false)
	var d := fire_dir()
	var b := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.97 else Vector3(facing, 0, 0))
	if w.is_pistol:
		var center := (sr + sl) * 0.5 + Vector3(0, -0.05, 0)
		var grip_pos := center + d * 0.48
		return Transform3D(b, grip_pos - b * w.grip)
	var pocket := sr + d * 0.06 + Vector3(0, -0.03, 0)
	return Transform3D(b, pocket - b * w.butt)

# ---------------------------------------------------------------- láser del arma

## Láser desde la boca del cañón en la dirección real del disparo (con temblor y retroceso) hasta lo primero que toca.
## Rojo para el jugador, ámbar para los enemigos (delata su puntería: lectura táctica). Se apaga en Configuración.
func _update_laser(w: Firearm, on: bool) -> void:
	if BulletTime.closeup_active:
		on = false
	if laser == null:
		laser = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.008, 0.008, 1.0)
		laser.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1.0, 0.05, 0.03, 0.75) if is_player else Color(1.0, 0.55, 0.05, 0.45)
		laser.material_override = m
		laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		laser.top_level = true
		add_child(laser)
		laser_dot = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.07
		sm.radial_segments = 8
		sm.rings = 4
		laser_dot.mesh = sm
		var dm := m.duplicate() as StandardMaterial3D
		dm.albedo_color.a = 1.0
		laser_dot.material_override = dm
		laser_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		laser_dot.top_level = true
		add_child(laser_dot)
	var show := on and w != null and Settings.laser and state != State.DEAD and (is_player or Settings.laser_enemies) and not TimeFx.active
	laser.visible = show
	laser_dot.visible = show
	if not show:
		return
	var from := w.muzzle_world()
	var d := fire_dir()
	var to := from + d * 40.0
	var q := PhysicsRayQueryParameters3D.create(from, Vector3(to.x, to.y, 0.0), 1 | 4 | 8)
	q.collide_with_areas = true
	q.exclude = hitbox_rids()
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		to = hit.position
	var seg := to - from
	var l := maxf(seg.length(), 0.01)
	var up := Vector3.UP if absf(seg.normalized().y) < 0.97 else Vector3.RIGHT
	laser.global_transform = Transform3D(Basis.looking_at(seg / l, up).scaled_local(Vector3(1, 1, l)), from + seg * 0.5)
	laser_dot.global_position = to
	laser_dot.visible = not hit.is_empty()

# ---------------------------------------------------------------- curación

## Usa una venda o un botiquín del inventario (tarda unos segundos arrodillado). Devuelve false si no hay.
func use_medical(item := "") -> bool:
	if item == "":
		item = "medkit" if inventory.count("medkit") > 0 and (injuries.head > 0.0 or health < max_health * 0.5) else "bandage"
		if inventory.count(item) <= 0:
			item = "medkit" if inventory.count("medkit") > 0 else "bandage"
	if inventory.count(item) <= 0 or busy() or state != State.GROUND:
		return false
	var secs := 2.2 if item == "bandage" else 3.5
	Sfx.play("bandage", global_position + Vector3.UP, -6.0)
	begin_task("kneel_work", secs, func():
		if inventory.remove(item):
			heal(injuries.treat(item))
			if is_player:
				get_tree().call_group("hud", "toast", "Venda aplicada: hemorragia cortada, pierna entablillada" if item == "bandage" else "Botiquín: lesiones curadas"))
	return true
