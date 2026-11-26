## Origen: Operación Nexus (player/arm_ik.gd), mismo autor; se reutiliza tal cual para que las manos agarren bien las armas.
class_name ArmIK
extends SkeletonModifier3D
## IK de dos huesos para los brazos + inclinación de columna/cabeza para apuntar.
## Corre después de la animación: la animación mueve piernas, torso y dedos,
## y este modificador lleva las manos a la empuñadura y al guardamanos del arma.

const P := "mixamorig_"

var right_target := Transform3D()      ## transform del hueso mano derecha (mundo)
var left_target := Transform3D()
var right_weight := 1.0
var left_weight := 1.0
var right_pole := Vector3.DOWN         ## hacia dónde apunta el codo (mundo)
var left_pole := Vector3.DOWN
var spine_pitch := 0.0                 ## radianes, repartido en 3 huesos
var spine_yaw := 0.0
var head_pitch := 0.0
var head_yaw := 0.0                    ## radianes: giro de la cabeza (contrarresta el torso en diagonal)
var head_roll := 0.0                   ## radianes: inclinación de la cabeza hacia el hombro derecho (+) al apuntar
var spine_roll := 0.0                  ## radianes: torso inclinado hacia el costado derecho (+)
var shoulder_open := 0.0               ## radianes: hombros hacia afuera/adelante al apuntar (los brazos no quedan metidos en el torso)
var spine_lean := 0.0                  ## radianes: inclinación hacia adelante (+) por velocidad / aceleración
var body_fwd := Vector3.FORWARD        ## eje de avance del personaje (mundo)
var body_right := Vector3.RIGHT        ## eje derecho del personaje (mundo)
var body_up := Vector3.UP

var _b := {}
var palm_local_r := Vector3.ZERO       ## ejes locales de la mano (calculados de la pose de reposo)
var palm_local_l := Vector3.ZERO
var finger_local_r := Vector3.UP
var finger_local_l := Vector3.UP
var enabled_arms := true
var reach_err_r := 0.0                 ## metros que le faltó al brazo para llegar al objetivo (diagnóstico)
var reach_err_l := 0.0
## --- modo cuerpo (tercera persona): el arma va pegada a la mano derecha de la animación ---
var use_attached_weapon := false
var weapon_attach := Transform3D()     ## arma en el espacio del hueso de la mano derecha
var weapon_support := Vector3.ZERO     ## marcador Support (espacio del arma)
var weapon_is_pistol := false
var left_grip_weight := 1.0            ## 0 = la mano izquierda queda como la animación, 1 = va al guardamanos
var left_override_active := false      ## recarga / curar / granada: la mano izquierda va a un marco propio
var left_override_frame := {}          ## marco en espacio mundo
var left_override_weight := 0.0
var right_override_active := false
var right_override_frame := {}
var right_override_weight := 0.0
var weapon_target := Transform3D()     ## 3ª persona: dónde debe quedar el arma (mundo) cuando se apunta; la mano derecha la sigue
var weapon_aim_dir := Vector3.ZERO     ## si no es cero: el arma se coloca AQUÍ dentro de la IK con el hombro ya inclinado (no el del cuadro anterior)
var weapon_butt := Vector3.ZERO        ## culata del arma (espacio del arma)
var weapon_aim_facing := 1.0
var weapon_target_w := 0.0             ## 0 = el arma sale de las manos de la animación, 1 = va exactamente a weapon_target
var reach_l := 0.6                     ## largo de cada brazo (hombro -> mano), de la pose de reposo
var reach_r := 0.6
var last_weapon_skel := Transform3D()  ## transform del arma en espacio del esqueleto (último cálculo)
var weapon_node: Node3D                ## nodo (hijo del esqueleto) que se coloca sobre el arma cada cuadro
var weapon_grip_local := Vector3.ZERO
var _hand_grip_local := Vector3.ZERO   ## empuñadura en el espacio de la mano derecha
var _hand_up_local := Vector3.UP       ## "arriba" del arma en el espacio de la mano derecha
var _weapon_axis_basis := Basis.IDENTITY   ## orientación del eje empuñadura -> guardamanos en espacio del arma
## Curvatura de dedos (radianes). Negativo = dejar lo que traiga la animación.
var curl_r := -1.0
var curl_l := -1.0
var trigger_curl := 0.45                ## el índice derecho queda más abierto (dedo en el gatillo)
var _fingers := []                      ## [{bone, rest, axis, right, index, thumb}]
## Agarres (grados por falange 1-2-3). Dedo índice de la derecha: apoyado en el gatillo.
const GRIP_FIST := {"Thumb": [28, 30, 20], "Index": [75, 90, 65], "Middle": [78, 92, 68], "Ring": [80, 95, 70], "Pinky": [80, 95, 70]}
const GRIP_PISTOL_R := {"Thumb": [12, 16, 8], "Index": [22, 30, 18], "Middle": [60, 80, 55], "Ring": [65, 85, 60], "Pinky": [68, 88, 62]}
const GRIP_RIFLE_R := {"Thumb": [14, 18, 8], "Index": [24, 34, 20], "Middle": [58, 78, 52], "Ring": [62, 84, 58], "Pinky": [64, 86, 60]}
const GRIP_HANDGUARD_L := {"Thumb": [10, 14, 6], "Index": [40, 62, 40], "Middle": [48, 70, 46], "Ring": [52, 74, 50], "Pinky": [54, 76, 52]}
var grip_r := GRIP_RIFLE_R
var grip_l := GRIP_HANDGUARD_L
var item_r := false                     ## la mano lleva un objeto (granada, venda, cargador): puño procedural
var item_l := false

func setup() -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null:
		sk = get_parent() as Skeleton3D
	for n in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "RightShoulder", "RightArm", "RightForeArm", "RightHand",
			"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightHandMiddle1", "LeftHandMiddle1"]:
		_b[n] = sk.find_bone(P + n)
	for side in ["Left", "Right"]:
		var ua := sk.get_bone_global_rest(_b[side + "Arm"]).origin
		var fa := sk.get_bone_global_rest(_b[side + "ForeArm"]).origin
		var ha := sk.get_bone_global_rest(_b[side + "Hand"]).origin
		if side == "Left":
			reach_l = ua.distance_to(fa) + fa.distance_to(ha)
		else:
			reach_r = ua.distance_to(fa) + fa.distance_to(ha)
	# En T-pose de Mixamo la palma mira hacia abajo (-Y del esqueleto).
	var rr := sk.get_bone_global_rest(_b.RightHand)
	var rl := sk.get_bone_global_rest(_b.LeftHand)
	palm_local_r = (rr.basis.inverse() * Vector3.DOWN).normalized()
	palm_local_l = (rl.basis.inverse() * Vector3.DOWN).normalized()
	finger_local_r = (rr.basis.inverse() * (sk.get_bone_global_rest(_b.RightHandMiddle1).origin - rr.origin)).normalized()
	finger_local_l = (rl.basis.inverse() * (sk.get_bone_global_rest(_b.LeftHandMiddle1).origin - rl.origin)).normalized()
	# Eje de flexión de cada falange: perpendicular al dedo y a la palma.
	for side in ["Left", "Right"]:
		for f in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			for k in [1, 2, 3]:
				var b := sk.find_bone(P + side + "Hand" + f + str(k))
				var child := sk.find_bone(P + side + "Hand" + f + str(k + 1))
				if b < 0 or child < 0:
					continue
				var rest_g := sk.get_bone_global_rest(b)
				var fl := (rest_g.basis.inverse() * (sk.get_bone_global_rest(child).origin - rest_g.origin)).normalized()
				var pl := (rest_g.basis.inverse() * Vector3.DOWN).normalized()
				if f == "Thumb":
					# el pulgar se cierra hacia la base del dedo mayor (cruza la palma)
					var mid := sk.get_bone_global_rest(sk.find_bone(P + side + "HandMiddle1")).origin + Vector3.DOWN * 0.03
					pl = (rest_g.basis.inverse() * (mid - rest_g.origin)).normalized()
				var axis := fl.cross(pl).normalized()
				_fingers.append({"bone": b, "rest": sk.get_bone_rest(b).basis.get_rotation_quaternion(), "axis": axis,
					"right": side == "Right", "index": f == "Index", "thumb": f == "Thumb", "k": k, "f": f})

## Posición mundo del hombro (con la pose del cuadro anterior).
func shoulder_world(right: bool) -> Vector3:
	var sk := get_skeleton()
	return sk.global_transform * chain_pose(sk, _b.RightArm if right else _b.LeftArm).origin

func bone(n: String) -> int:
	return _b.get(n, -1)

## Objetivo de mano a partir de un marco {wrist, finger, palm} (ver WeaponGrip).
func set_hand(right: bool, frame: Dictionary, weight := 1.0) -> void:
	var fl := finger_local_r if right else finger_local_l
	var pl := palm_local_r if right else palm_local_l
	var t := Transform3D(WeaponGrip.frame_basis(fl, pl, frame.finger, frame.palm), frame.wrist)
	if right:
		right_target = t; right_weight = weight
	else:
		left_target = t; left_weight = weight

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _b.is_empty():
		return
	var inv := sk.global_transform.affine_inverse()
	var right_axis := (inv.basis * body_right).normalized()
	var up_axis := (inv.basis * body_up).normalized()
	var fwd_axis := (inv.basis * body_fwd).normalized()
	if absf(spine_pitch) > 0.0001 or absf(spine_yaw) > 0.0001 or absf(spine_roll) > 0.0001 or absf(spine_lean) > 0.0001:
		for n in ["Spine", "Spine1", "Spine2"]:
			var g := sk.get_bone_global_pose(_b[n])
			var rot := Basis(up_axis, spine_yaw / 3.0) * Basis(right_axis, (spine_pitch + spine_lean) / 3.0) * Basis(fwd_axis, spine_roll / 3.0)
			g.basis = rot * g.basis
			sk.set_bone_global_pose(_b[n], g)
	if absf(head_pitch) > 0.0001 or absf(head_yaw) > 0.0001 or absf(head_roll) > 0.0001:
		for n in ["Neck", "Head"]:
			var g := sk.get_bone_global_pose(_b[n])
			g.basis = Basis(up_axis, head_yaw * 0.5) * Basis(right_axis, head_pitch * 0.5) * Basis(fwd_axis, head_roll * 0.5) * g.basis
			sk.set_bone_global_pose(_b[n], g)
	if curl_r >= 0.0 or curl_l >= 0.0 or item_r or item_l or not grip_r.is_empty() or not grip_l.is_empty():
		_apply_curl(sk)
	if not enabled_arms:
		return
	if use_attached_weapon:
		_process_attached(sk, inv)
		return
	if right_weight > 0.001:
		_solve(sk, _b.RightArm, _b.RightForeArm, _b.RightHand, inv * right_target, inv.basis * right_pole, right_weight)
	if left_weight > 0.001:
		_solve(sk, _b.LeftArm, _b.LeftForeArm, _b.LeftHand, inv * left_target, inv.basis * left_pole, left_weight)

## Calibra dónde va el arma respecto de la mano derecha usando una pose de referencia.
## Fusiles: el eje empuñadura -> guardamanos apunta de la mano derecha a la izquierda (arriba = arriba).
## Pistolas: la mano derecha agarra la empuñadura con la orientación de WeaponGrip.
## Así el arma queda bien en TODAS las animaciones del paquete, sin constantes a ojo.
func calibrate_attach(anim: Animation, t: float, grip_local: Vector3, support_local: Vector3, pistol: bool) -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null:
		sk = get_parent() as Skeleton3D
	sk.reset_bone_poses()
	apply_animation_pose(sk, anim, t)
	var hr := chain_pose(sk, _b.RightHand)
	var hl := chain_pose(sk, _b.LeftHand)
	var rot: Basis
	var grip_ref: Vector3
	if pistol:
		var d: Array = WeaponGrip.PISTOL_RIGHT
		var fw := (hr.basis * finger_local_r).normalized()
		var pw := (hr.basis * palm_local_r).normalized()
		rot = WeaponGrip.frame_basis((d[0] as Vector3), (d[1] as Vector3), fw, pw)
		grip_ref = hr.origin + rot * ((d[0] as Vector3).normalized() * float(d[2]) + (d[1] as Vector3).normalized() * float(d[3]))
	else:
		var a := (hl.origin - hr.origin).normalized()
		var aw := (support_local - grip_local).normalized()
		if aw.length() < 0.1:
			aw = Vector3(0, 0, -1)
		rot = Basis.looking_at(a, Vector3.UP) * Basis.looking_at(aw, Vector3.UP).inverse()
		grip_ref = hr.origin + hr.basis * finger_local_r * 0.075 + hr.basis * palm_local_r * 0.035
	var weapon_ref := Transform3D(rot, grip_ref - rot * grip_local)
	weapon_attach = hr.affine_inverse() * weapon_ref
	var hrb := hr.basis.orthonormalized()
	_hand_grip_local = hrb.inverse() * (grip_ref - hr.origin)
	_hand_up_local = hrb.inverse() * (rot * Vector3.UP)
	var aw2 := (support_local - grip_local).normalized()
	_weapon_axis_basis = Basis.looking_at(aw2 if aw2.length() > 0.1 else Vector3(0, 0, -1), Vector3.UP)
	weapon_grip_local = grip_local
	weapon_support = support_local
	weapon_is_pistol = pistol
	sk.reset_bone_poses()

## Pose global de un hueso sumando las poses locales desde la raíz (sirve fuera del ciclo de actualización).
static func chain_pose(sk: Skeleton3D, bone_idx: int) -> Transform3D:
	var t := Transform3D.IDENTITY
	var b := bone_idx
	while b >= 0:
		t = sk.get_bone_pose(b) * t
		b = sk.get_bone_parent(b)
	return t

static func apply_animation_pose(sk: Skeleton3D, anim: Animation, t: float) -> void:
	for i in anim.get_track_count():
		var bn := str(anim.track_get_path(i).get_subname(0))
		var b := sk.find_bone(bn)
		if b < 0:
			continue
		match anim.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(b, anim.rotation_track_interpolate(i, t))
			Animation.TYPE_POSITION_3D:
				sk.set_bone_pose_position(b, anim.position_track_interpolate(i, t))

func _open_shoulders(sk: Skeleton3D, inv: Transform3D) -> void:
	var up_axis := (inv.basis * body_up).normalized()
	var fwd_axis := (inv.basis * body_fwd).normalized()
	for side in ["Right", "Left"]:
		var b: int = _b[side + "Shoulder"]
		if b < 0:
			continue
		var sgn := -1.0 if side == "Right" else 1.0
		var g := sk.get_bone_global_pose(b)
		# elevar un poco la clavícula y llevarla hacia adelante: el hombro sale del pecho
		g.basis = Basis(up_axis, sgn * shoulder_open) * Basis(fwd_axis, sgn * shoulder_open * 0.8) * g.basis
		sk.set_bone_global_pose(b, g)

func _process_attached(sk: Skeleton3D, inv: Transform3D) -> void:
	if shoulder_open > 0.001 and weapon_target_w > 0.001:
		_open_shoulders(sk, inv)
	# mano derecha: la de la animación (con la corrección del override, si hay)
	if right_override_active and right_override_weight > 0.001:
		var rf := right_override_frame
		var t := Transform3D(WeaponGrip.frame_basis(finger_local_r, palm_local_r, inv.basis * rf.finger, inv.basis * rf.palm), inv * rf.wrist)
		_solve_pole(sk, true, t, right_override_weight)
	var hand_r := sk.get_bone_global_pose(_b.RightHand)
	if weapon_is_pistol:
		last_weapon_skel = hand_r * weapon_attach
	else:
		# fusiles: el arma queda entre las dos manos de la animación (la izquierda marca hacia dónde apunta)
		var hand_l := sk.get_bone_global_pose(_b.LeftHand)
		var hrb := hand_r.basis.orthonormalized()
		var a := hand_l.origin - hand_r.origin
		if a.length() < 0.05:
			last_weapon_skel = hand_r * weapon_attach
		else:
			a = a.normalized()
			var u := hrb * _hand_up_local
			u = u - a * u.dot(a)
			if u.length() < 0.05:
				u = Vector3.UP
			var wb := Basis.looking_at(a, u.normalized()) * _weapon_axis_basis.inverse()
			last_weapon_skel = Transform3D(wb, hand_r.origin + hrb * _hand_grip_local - wb * weapon_grip_local)
	if weapon_target_w > 0.001 and weapon_aim_dir.length_squared() > 0.1:
		# el hombro de ESTE cuadro (con la columna ya inclinada): así la culata queda en el hombro aunque se apunte hacia arriba
		var sr := sk.global_transform * sk.get_bone_global_pose(_b.RightArm).origin
		var sl := sk.global_transform * sk.get_bone_global_pose(_b.LeftArm).origin
		var d := weapon_aim_dir.normalized()
		var bb := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.97 else Vector3(weapon_aim_facing, 0, 0))
		if weapon_is_pistol:
			var center := sr.lerp(sl, 0.3) + Vector3(0, -0.06, 0)    # más cerca del hombro de tiro: la izquierda no cruza el pecho
			weapon_target = Transform3D(bb, center + d * 0.43 - bb * weapon_grip_local)
		else:
			var pocket := sr + d * 0.13 + Vector3(0, -0.02, 0)           # la culata apoya en el FRENTE del hombro, no dentro del torso
			weapon_target = Transform3D(bb, pocket - bb * weapon_butt)
	if weapon_target_w > 0.001 and not right_override_active:
		# apuntando: el arma va exactamente donde pide el jugador y las dos manos la siguen
		last_weapon_skel = last_weapon_skel.interpolate_with(inv * weapon_target, weapon_target_w)
		var rfw := WeaponGrip.hand_frame(sk.global_transform * last_weapon_skel, weapon_grip_local, true, weapon_is_pistol)
		var rt := Transform3D(WeaponGrip.frame_basis(finger_local_r, palm_local_r, inv.basis * rfw.finger, inv.basis * rfw.palm), inv * rfw.wrist)
		_solve_pole(sk, true, rt, weapon_target_w)
	if weapon_node:
		weapon_node.transform = last_weapon_skel
	# mano izquierda: al guardamanos, salvo que haya un movimiento propio (recarga, etc.)
	var frame := WeaponGrip.hand_frame(sk.global_transform * last_weapon_skel, weapon_support, false, weapon_is_pistol)
	var w := left_grip_weight
	if left_override_active and left_override_weight > 0.001:
		frame = _blend_frames(frame, left_override_frame, left_override_weight)
		w = maxf(w, left_override_weight)
	if w > 0.001:
		var lt := Transform3D(WeaponGrip.frame_basis(finger_local_l, palm_local_l, inv.basis * frame.finger, inv.basis * frame.palm), inv * frame.wrist)
		_solve_pole(sk, false, lt, w)

func _blend_frames(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	return {"wrist": (a.wrist as Vector3).lerp(b.wrist, k), "finger": (a.finger as Vector3).slerp((b.finger as Vector3).normalized(), k), "palm": (a.palm as Vector3).slerp((b.palm as Vector3).normalized(), k)}

## Resuelve un brazo eligiendo el codo hacia abajo y hacia afuera (hombros sin deformarse).
func _solve_pole(sk: Skeleton3D, right: bool, target: Transform3D, w: float) -> void:
	var up: int = _b.RightArm if right else _b.LeftArm
	var lo: int = _b.RightForeArm if right else _b.LeftForeArm
	var ha: int = _b.RightHand if right else _b.LeftHand
	var side := -1.0 if right else 1.0
	var pole_skel := (Vector3(side * 0.6, -1.0, 0.25)).normalized()
	_solve(sk, up, lo, ha, target, pole_skel, w)

func _apply_curl(sk: Skeleton3D) -> void:
	for f in _fingers:
		var item: bool = item_r if f.right else item_l
		var prof: Dictionary = GRIP_FIST if item else (grip_r if f.right else grip_l)
		var c: float = curl_r if f.right else curl_l
		if prof.is_empty() and c < 0.0:
			continue
		var ang: float
		if prof.is_empty():
			ang = c
			if f.right and f.index:
				ang *= trigger_curl
			if f.thumb:
				ang *= 0.7 if f.k == 1 else 0.6
			elif f.k == 1:
				ang *= 0.85
		else:
			ang = deg_to_rad(float(prof[f.f][f.k - 1]))
		sk.set_bone_pose_rotation(f.bone, f.rest * Quaternion(f.axis, ang))

func _solve(sk: Skeleton3D, upper: int, lower: int, hand: int, target: Transform3D, pole: Vector3, w: float) -> void:
	# La clavícula acompaña al brazo (como en una animación real): sin eso el hombro se estira y se «hunde» en el torso.
	var shoulder := sk.get_bone_parent(upper)
	if shoulder >= 0 and w > 0.3:
		var a0 := sk.get_bone_global_pose(upper).origin
		var b0 := sk.get_bone_global_pose(lower).origin
		var d_now := (b0 - a0).normalized()
		var d_want := (target.origin - a0).normalized()
		var qs := Quaternion(d_now, d_want) if d_now.dot(d_want) < 0.9999 else Quaternion.IDENTITY
		var part := Quaternion.IDENTITY.slerp(qs, 0.3 * w)
		var sg := sk.get_bone_global_pose(shoulder)
		sg.basis = Basis(part) * sg.basis
		sk.set_bone_global_pose(shoulder, sg)
	var hand_now := sk.get_bone_global_pose(hand)
	if w < 0.999:
		target = hand_now.interpolate_with(target, w)
	var a := sk.get_bone_global_pose(upper).origin
	var b := sk.get_bone_global_pose(lower).origin
	var c := hand_now.origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var to_t := target.origin - a
	var d := clampf(to_t.length(), 0.02, (l1 + l2) * 0.999)
	if hand == _b.RightHand:
		reach_err_r = maxf(to_t.length() - d, 0.0)
	else:
		reach_err_l = maxf(to_t.length() - d, 0.0)
	var dir := to_t.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var pp := pole - dir * pole.dot(dir)
	if pp.length_squared() < 1e-6:
		pp = Vector3.DOWN - dir * dir.y
	pp = pp.normalized()
	var elbow := a + dir * (l1 * cos_a) + pp * (l1 * sqrt(1.0 - cos_a * cos_a))
	var tpos := a + dir * d
	var ug := sk.get_bone_global_pose(upper)
	ug.basis = Basis(Quaternion((b - a).normalized(), (elbow - a).normalized())) * ug.basis
	sk.set_bone_global_pose(upper, ug)
	var lg := sk.get_bone_global_pose(lower)
	var c2 := sk.get_bone_global_pose(hand).origin
	lg.basis = Basis(Quaternion((c2 - lg.origin).normalized(), (tpos - lg.origin).normalized())) * lg.basis
	sk.set_bone_global_pose(lower, lg)
	# El antebrazo no tiene huesos de torsión: si la mano se gira de golpe respecto del antebrazo se «retuerce» como caramelo.
	# Se reparte la torsión: ~70 % la toma el antebrazo y sólo el resto se nota en la muñeca.
	var hg := sk.get_bone_global_pose(hand)
	var f_axis := (tpos - sk.get_bone_global_pose(lower).origin).normalized()
	var qd := (target.basis.orthonormalized() * hg.basis.orthonormalized().inverse()).get_rotation_quaternion()
	var tw := 2.0 * atan2(Vector3(qd.x, qd.y, qd.z).dot(f_axis), qd.w)
	tw = wrapf(tw, -PI, PI)
	var lg3 := sk.get_bone_global_pose(lower)
	lg3.basis = Basis(f_axis, tw * 0.7) * lg3.basis
	sk.set_bone_global_pose(lower, lg3)
	hg = sk.get_bone_global_pose(hand)
	var scl := hg.basis.get_scale()
	hg.basis = target.basis.orthonormalized().scaled(scl)
	sk.set_bone_global_pose(hand, hg)
