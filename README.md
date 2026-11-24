# EXTRACCIÓN VERTICAL

**Explora · Saquea · Sobrevive · Extrae.** Shooter táctico de extracción en 2.5D para Android: personajes 3D en un
edificio industrial visto de costado, apuntado libre e independiente, parkour, escaleras, ascensor, destrucción,
granadas, saqueo con cuchillo, cámara lenta con **rayos X** (huesos que se fracturan, órganos perforados) y lesiones
que cambian cómo se juega.

Motor **Godot 4.7.2** · renderer **GL Compatibility** (teléfonos de gama baja) · física **Jolt** a 60 Hz · 1280×720.

## Estado: primer entregable (vertical slice) jugable

| Pedido | Estado | Dónde |
|---|---|---|
| Personaje 3D con animaciones de Mixamo | ✅ 65 clips (locomoción con arma, pistola, escalera, borde, trepar, golpes, patadas, cuchillo, 9 reacciones, 6 muertes, caídas, herido, interacción) | `tools/anim_builder/anims.json` |
| Mapa industrial de 5 niveles irregular | ✅ Torre Alfa P0–P4 + azotea, 26 sectores, comprobado sin sectores inaccesibles | `docs/MAPA_TORRE_ALFA.md` |
| Joystick izquierdo progresivo | ✅ sigilo → caminar → correr → máximo según inclinación, frena en seco | `Actor.SPEED_CURVE` |
| Joystick derecho con apuntado persistente | ✅ dirección en coordenadas del mundo; el movimiento no la pisa; retrocede apuntando | `Actor.aim_dir` |
| Disparo independiente del movimiento + láser | ✅ láser desde la boca del cañón hasta el impacto | `Actor._update_laser` |
| Salto, parkour, agarre de bordes, trepar cajas | ✅ | `Actor._try_vault/_try_grab` |
| Escalera vertical con animación al ritmo | ✅ un ciclo de Mixamo = dos peldaños, salida arriba animada | `Ladder`, `Actor._move_ladder` |
| Ascensor funcional (plataforma real) | ✅ 5 paradas, panel y llamadas, barandas sólo al moverse | `Elevator` |
| Armas (de Operación Nexus) | ✅ AM4, Browning (inicio) · MP5, Remington, AWM sin mira (botín) | `data/weapons.json` |
| Balística física | ✅ velocidad, gravedad, resistencia, penetración, rebote en metal, pooling | `Ballistics` |
| Cuchillo, puños y patadas | ✅ combinación jab-cross-patada, apuñalar, reacciones por zona | `Actor._melee` |
| Granadas | ✅ fragmentación, aturdidora, humo, incendiaria, C4 (arco previsto al mantener) | `Grenade`, `Explosion` |
| Cajas rompibles, barriles, vidrio, chapas | ✅ intacto → dañado → roto, fragmentos, botín | `Destructible` |
| Contenedor que se abre con cuchillo | ✅ arrodillado, barra de progreso, sonidos de metal/madera/cerradura; forzar sin cuchillo hace ruido | `LootContainer` |
| Explosión con daño y fragmentos | ✅ destello, bola de fuego, onda, humo, escombros, daño radial con oclusión, vibración | `Explosion` |
| Rayos X / bullet time | ✅ la cámara sigue la bala y en el impacto muestra huesos, órganos y vasos; fracturas y perforaciones; sangre siempre | `BulletTime`, `XRayAnatomy` |
| Lesiones con efecto | ✅ pierna rota = renguea y trepa lento; brazo/cabeza = puntería tiembla; hemorragia; venda/botiquín | `Injuries` |
| Sonidos | ✅ disparos y recargas de Nexus (Black Veil) + 29 efectos nuevos de ElevenLabs | `docs/audio/` |
| IA con oído y vista | ✅ patrulla, alerta por ruido, combate, búsqueda | `BotBrain`, `NoiseBus` |
| Configuración gráfica baja/media/alta | ✅ escala de render, sombras, luces, partículas, humo, explosiones, decorado, fondo, FPS, rayos X | `Settings`, `SettingsMenu` |
| Captador de rendimiento | ✅ hace desaparecer cada categoría y los objetos más pesados, mide y arma un ranking | `PerfProbe`, `docs/RENDIMIENTO.md` |
| Multijugador | 🟡 arquitectura preparada (entradas → Actor, autoridad definida), sin red todavía | `docs/MULTIJUGADOR.md` |

## Jugar / probar

* **Pruebas:** `tools/run_tests.sh` (12 pruebas: mapa, velocidad, ajustes, inventario, apuntado, escalera, ascensor,
  balística, destrucción, granada, lesiones, captador).
* **APK:** GitHub → Actions → **Pruebas y APK** → Run workflow → el APK queda en *Artifacts* (firma de prueba descartable).
* **Capturas de revisión:** `xvfb-run -a godot --path . --rendering-driver opengl3 tests/shots.tscn -- <carpeta> [escenario]`.
* **Captador sin interfaz:** `godot --path . scenes/main.tscn -- --probe` (imprime el informe).

### Controles

| Táctil | Teclado / mouse | Acción |
|---|---|---|
| Joystick izquierdo | A / D (+Shift correr al máximo, Ctrl sigilo) | moverse (la inclinación da la velocidad) · arriba/abajo: escaleras, agacharse |
| Joystick derecho | mover el mouse | apuntar (queda fijo al soltar) |
| ◎ | clic izquierdo | disparar |
| ⤒ | Espacio | saltar / subir a cajas / agarrarse de bordes |
| ✊ / 🔪 | F | golpe (jab → cross → patada) o cuchillo |
| ● (mantener) | G (mantener) | granada: muestra el arco, al soltar se lanza |
| USAR (aparece sólo cuando sirve) | E | abrir cajas con cuchillo, ascensor, puertas, recoger |
| ✚ (aparece si estás herido) | H | venda / botiquín |
| R · ⇄ · ▼ | R · Q (1-4) · C | recargar · cambiar arma · agacharse |
| II | Esc / Tab | pausa, inventario, configuración, analizar rendimiento |

## Estructura

```
project.godot          Godot 4.7.2, GL Compatibility, Jolt
scenes/                main.tscn (menú → partida)
systems/
  core/                Settings, TimeFx (cámara lenta), NoiseBus (ruido para la IA), Game, PlayerController, PerfProbe
  actor/               Actor (jugador y bots), ActorInput, Injuries, CharacterModel, ArmIK y WeaponGrip (de Nexus)
  weapons/             Firearm, Ballistics, Grenade, WeaponMaterials
  destruction/         Destructible, Explosion (+ humo y fuego)
  interaction/         Interactable, LootContainer, Ladder, Elevator, objetos sueltos, puerta con tarjeta, extracción
  inventory/           Inventory (botín, tablas)
  map/                 TorreAlfa (datos), TowerBuilder, MapGraph, BoxBatcher
  camera/              SideCamera
  ai/                  BotBrain
  anatomy/             XRayAnatomy, BulletTime
  audio/               Sfx
  fx/                  Fx (partículas y fragmentos reutilizables)
  ui/                  Hud, TouchStick, SettingsMenu
data/                  armas, explosivos, objetos, tablas de botín, personajes (JSON: se editan sin tocar código)
assets/                personajes, armas, animaciones, anatomía, props, sonidos, texturas, íconos, munición
tools/                 anim_builder (Mixamo → .res), anatomy (BodyParts3D → GLB), sfx (ElevenLabs), textures, run_tests.sh
tests/                 pruebas automáticas y capturas
docs/                  ARQUITECTURA, RECURSOS, MAPA_TORRE_ALFA, ANATOMIA, RENDIMIENTO, MULTIJUGADOR, audio/
```

## Créditos y licencias

* Animaciones: **Mixamo** (Adobe), del respaldo `mixamo-respaldo`.
* Personajes, armas, munición, íconos y parte de los sonidos: **Operación Nexus / BLACK VEIL** (mismo autor).
* Anatomía: **BodyParts3D**, © The Database Center for Life Science, licencia **CC BY 4.0** (`assets/anatomy/CREDITOS.md`).
* Modelos de decorado: bibliotecas libres de **Sweet Home 3D** (Free Art License / CC0 / CC BY, `assets/props/CREDITOS_SH3D.txt`).
* Efectos de sonido nuevos: generados con **ElevenLabs** (`docs/audio/elevenlabs_ledger.jsonl`).
