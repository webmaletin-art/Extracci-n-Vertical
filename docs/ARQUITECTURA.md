# Arquitectura técnica

## Convenciones

* GDScript con tabuladores, `class_name` en cada sistema reutilizable, tipado explícito, comentarios `##` y textos en
  español; identificadores en inglés.
* **Ejes:** X = horizontal (0..60 m), Y = arriba, plano de juego **z = 0** (los personajes, balas y granadas se mueven
  sólo en X/Y; la profundidad es decorado). Cámara en +Z mirando a −Z. Altura de piso 4,5 m.
* **Capas de física:** 1 mundo · 2 cuerpos de personajes · 3 hitbox (zonas del cuerpo, `Area3D`) · 4 destructibles ·
  6 interacción (`Interactable`, `Ladder`) · 7 escombros / granadas.
* Los balances viven en datos (`data/*.json`) y en constantes al principio de cada clase (`Actor.SPEED_CURVE`,
  `Actor.ZONE_MULT`, `Actor.MELEE`, `Elevator.speed`…).

## Flujo

`scenes/main.tscn` (menú) → `Game` arma: `Ballistics` → `TowerBuilder.build(TorreAlfa.data())` → jugador (`Actor` +
`PlayerController`) → `SideCamera` → `Hud` → `BulletTime` → `PerfProbe`.

## Sistemas

| Sistema | Responsabilidad | Depende de |
|---|---|---|
| `Actor` | Personaje (jugador y bots). Lee un `ActorInput` por cuadro: movimiento progresivo, **apuntado persistente en el mundo** (`aim_dir`, sólo lo cambia el joystick derecho/mouse), estados (suelo, aire, escalera, colgado, trepando, acción, caído, muerto), parkour, combate, daño por zonas, reacciones, láser, curación | `ActorInput`, `CharacterModel`, `ArmIK`, `Firearm`, `Ballistics`, `Injuries`, `XRayAnatomy` |
| `ActorInput` | Intención de un cuadro (lo llena el jugador o la IA; en red, lo que manda cada cliente) | — |
| `CharacterModel` | Carga personajes de Nexus y adapta las animaciones a cada esqueleto (retarget por rotaciones de reposo) | `assets/anims/ref_skeleton.json` |
| `ArmIK` / `WeaponGrip` | (de Nexus) IK de dos huesos: el arma va hacia donde se apunta y las manos la siguen; flexión de columna y cabeza | — |
| `Injuries` | Trauma: qué se rompe con cada golpe (bala, esquirla, cuchillo, onda, lanzado, caída, puño) y sus efectos y hemorragias por órgano; venda y botiquín | `AnatomyBody`, `data/anatomy_damage.json` |
| `Firearm` | Arma en mano: modelo + marcadores, cargador, cadencia, recarga, ciclo de cerrojo | `data/weapons.json`, `WeaponMaterials` |
| `Ballistics` | Proyectiles físicos sin nodos sueltos: integración con gravedad y resistencia, rayo por tramo, daño por zona, penetración, rebote, predicción para la cámara de bala | `Fx`, `Sfx` |
| `Grenade` / `Explosion` | Granada con trayectoria real y espoleta; explosión con daño radial ocluido, onda, humo (`SmokeCloud` tapa la vista de la IA) y fuego (`FireZone`) | `data/explosives.json` |
| `Destructible` | Intacto → dañado → roto; fragmentos del grupo fijo; barriles explotan; suelta botín | `Fx`, `Explosion`, `LootContainer` |
| `LootContainer` | Abrir en silencio con cuchillo (arrodillado, sonidos), forzar (ruido) o destruir | `Inventory` |
| `Ladder` / `Elevator` | Escalera de mano al ritmo de la animación; ascensor `AnimatableBody3D` con paradas, panel y llamada | — |
| `TowerBuilder` | Construye el mapa desde datos; geometría juntada por material (`BoxBatcher`); velos de sectores; luces; ajustes gráficos del mapa | `TorreAlfa`, `MapGraph` |
| `MapGraph` | Esquema de sectores y conexiones; comprobación de accesibilidad | — |
| `SideCamera` | Sigue en X/Y con adelanto hacia el apuntado, límites, vibración; la toma prestada la cámara de bala | `TimeFx` |
| `BotBrain` | IA: patrulla, alerta por ruido, combate con tiempo de reacción y error, búsqueda | `NoiseBus` |
| `NoiseBus` | Ruido para la IA: radio por acción, atenuado por paredes | — |
| `AnatomyBody` | Anatomía ajustada del personaje (mallas con su piel), trayectorias por dentro del cuerpo, heridas en espacio de enlace, shader de heridas, destello y toma de muerte | `assets/anatomy/fit` |
| `BulletTime` | Cámara de muerte (lenta + acercamiento) y destellos de heridas graves | `AnatomyBody`, `Ballistics`, `TimeFx` |
| `Sfx` / `Fx` | Sonido 3D con reverberación por lugar; partículas y fragmentos reutilizables escalados por calidad | `Settings` |
| `Settings` / `SettingsMenu` / `PerfProbe` | Calidad gráfica y efectos; captador de rendimiento | — |

## Números fijos importantes

| Qué | Valor | Dónde |
|---|---|---|
| Gravedad del personaje / salto | 18 m/s² / 6,2 m/s (≈1,07 m) | `Actor.GRAVITY`, `JUMP_V` |
| Velocidad por inclinación | 0,15→0,55 · 0,40→1,15 · 0,70→2,0 · 0,92→3,6 · 1,0→5,2 m/s | `Actor.SPEED_CURVE` |
| Bordes que se agarran | 1,15–2,35 m sobre los pies · cajas 0,35–1,3 m | `Actor.HANG_*`, `VAULT_*` |
| Caída sin daño / mortal | 3,6 m / 11 m | `Actor.SAFE_FALL`, `DEADLY_FALL` |
| Multiplicador por zona (bala) | cabeza 3,5 · cuello 2,5 · torso 1 · pelvis 0,9 · brazo 0,55 · pierna 0,6 | `Actor.ZONE_MULT` |
| Daño de bots al jugador | ×0,6 (PvE) | `Actor.BOT_DAMAGE_TO_PLAYER` |
| Proyectiles simultáneos | 96 | `Ballistics.MAX` |
| Fragmentos físicos / marcas | 40 / 48 | `Fx.MAX_DEBRIS`, `MAX_MARKS` |

## Decisiones

* **2.5D real:** personajes y armas 3D; el escenario es 3D modular (losas, paredes, props) con fondo en planos lejanos.
  Los fondos prerenderizados en Blender se agregan como texturas de esos planos sin cambiar código.
* **Apuntado persistente:** `aim_dir` es un vector del mundo; el cuerpo mira hacia donde se apunta y retrocede si se
  camina al revés. Sin arma de fuego (puños, cuchillo) el cuerpo mira hacia donde camina (el apuntado queda guardado).
* **Sin destrucción estructural:** paredes, losas y vigas no se rompen; sí cajas, barriles, vidrios y paneles.
* **Velos por sector:** el jugador sólo ve bien el sector donde está; lo ya visto queda en penumbra y lo no visitado
  oscuro. Además se ocultan los pisos lejanos (menos dibujo).
* **IA con las mismas reglas que el jugador** (llena un `ActorInput`): sirve igual en red.
