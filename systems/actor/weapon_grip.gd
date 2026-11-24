class_name WeaponGrip
extends RefCounted
## Dónde y cómo van las manos sobre un arma (en espacio del arma: -Z adelante, +Y arriba).
## Origen: Operación Nexus (player/weapon_grip.gd).
## Devuelve el transform de la muñeca (hueso mano) en espacio mundo.

## [dirección de los dedos, dirección de la palma, retroceso de la muñeca, separación de la palma]
const RIFLE_RIGHT := [Vector3(-0.3, -0.55, -0.78), Vector3(-0.85, -0.35, 0.1), 0.075, 0.035]
const RIFLE_LEFT := [Vector3(0.6, 0.15, -0.78), Vector3(0.55, 0.85, 0.0), 0.07, 0.035]
const PISTOL_RIGHT := [Vector3(-0.2, -0.6, -0.77), Vector3(-0.85, -0.3, 0.1), 0.07, 0.03]
const PISTOL_LEFT := [Vector3(0.5, -0.5, -0.7), Vector3(0.9, 0.35, 0.15), 0.07, 0.03]

## Devuelve {wrist, finger, palm} en espacio mundo.
static func hand_frame(weapon_xf: Transform3D, marker: Vector3, right: bool, pistol: bool) -> Dictionary:
	var d: Array = (PISTOL_RIGHT if right else PISTOL_LEFT) if pistol else (RIFLE_RIGHT if right else RIFLE_LEFT)
	var b := weapon_xf.basis.orthonormalized()
	var fdir: Vector3 = (b * (d[0] as Vector3)).normalized()
	var pdir: Vector3 = (b * (d[1] as Vector3)).normalized()
	var p: Vector3 = weapon_xf * marker
	return {"wrist": p - fdir * float(d[2]) - pdir * float(d[3]), "finger": fdir, "palm": pdir}

## Marco libre de mano (para granada, venda, cargador): posición de la palma y direcciones.
static func free_frame(palm_pos: Vector3, finger: Vector3, palm: Vector3) -> Dictionary:
	finger = finger.normalized(); palm = palm.normalized()
	return {"wrist": palm_pos - finger * 0.07 - palm * 0.03, "finger": finger, "palm": palm}

static func frame_basis(finger_local: Vector3, palm_local: Vector3, finger_world: Vector3, palm_world: Vector3) -> Basis:
	return _frame(finger_world, palm_world) * _frame(finger_local, palm_local).inverse()

static func _frame(f: Vector3, p: Vector3) -> Basis:
	var x := f.normalized()
	var y := (p - x * p.dot(x)).normalized()
	return Basis(x, y, x.cross(y))

static func pole(weapon_xf: Transform3D, right: bool) -> Vector3:
	var b := weapon_xf.basis.orthonormalized()
	return (b * (Vector3(0.7, -1.0, 0.35) if right else Vector3(-0.5, -1.0, 0.1))).normalized()
