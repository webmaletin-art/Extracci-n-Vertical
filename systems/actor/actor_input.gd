class_name ActorInput
extends RefCounted
## Lo que quiere hacer un personaje en este cuadro. Lo llenan el control del jugador (joysticks / teclado) o la IA.
## El Actor sólo lee esto: así el mismo código sirve para el jugador, los bots y, en red, para las entradas que el
## servidor recibe de cada cliente (ver docs/MULTIJUGADOR.md).

var move := Vector2.ZERO        ## x: -1..1 horizontal (cuánto se inclina el joystick); y: +1 arriba / -1 abajo (escaleras, agacharse)
var aim := Vector2.ZERO         ## dirección de apuntado en el MUNDO (x derecha, y arriba). Cero = conservar la anterior
var fire := false               ## gatillo apretado
var jump := false               ## se apretó saltar en este cuadro (salto / parkour contextual)
var jump_held := false
var crouch := false
var reload := false
var melee := false              ## golpe: puño / combinación / cuchillo según lo que se tenga en mano
var grenade := false            ## mantener = mostrar el arco; soltar = lanzar
var interact := false           ## se apretó USAR en este cuadro
var interact_held := false
var switch_to := ""             ## "primary" | "secondary" | "knife" | "fists" | "next"

func clear_edges() -> void:
	jump = false
	reload = false
	melee = false
	interact = false
	switch_to = ""

func copy_from(o: ActorInput) -> void:
	move = o.move; aim = o.aim; fire = o.fire; jump = o.jump; jump_held = o.jump_held; crouch = o.crouch
	reload = o.reload; melee = o.melee; grenade = o.grenade; interact = o.interact; interact_held = o.interact_held
	switch_to = o.switch_to
