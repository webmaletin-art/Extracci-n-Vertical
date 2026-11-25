# Plan maestro — auditoría y estado (fase 1)

Fuente: «PROMPT MAESTRO DE DESARROLLO» (Abismo Vertical, online, IA, progresión). Se trabaja por fases verificables.
Estado: ✅ hecho y probado · 🟡 parcial · ⬜ pendiente.

## Lo que ya existe y se conserva
| Sistema | Dónde | Estado |
|---|---|---|
| Actor único para jugador / bots / red (ActorInput) | `systems/actor` | ✅ base para online |
| Balística física, penetración, rebotes | `systems/weapons/ballistics.gd` | ✅ + alcance efectivo por arma |
| Anatomía, lesiones por órgano, hemorragias, rayos X | `systems/anatomy`, `systems/actor/injuries.gd` | ✅ |
| Parkour, escaleras, ascensor, puertas/cajas, botín con cuchillo | `systems/actor`, `systems/interaction` | ✅ (Torre Alfa) |
| Configuración única guardada (`Settings`, user://settings.cfg) | `systems/core/settings.gd` | ✅ práctica y partida usan la MISMA |
| Modo práctica (maniquí, armas, municiones, grabación) | `systems/core/practice_game.gd` | ✅ |
| Cliente liviano + paquetes descargables | `boot/`, CI | ✅ |
| Arquitectura de red (documentada) | `docs/MULTIJUGADOR.md` | 🟡 sin servidor todavía |

## Fase 2 — correcciones prioritarias (este cambio)
| Punto del plan | Estado |
|---|---|
| §18 Eliminar la cámara lenta extrema; cámara de muerte breve (1,6 s, cámara lenta suave 35 %, encuadre moderado, rayos X de todos los impactos) | ✅ (la repetición larga queda sólo como herramienta de desarrollo, apagada) |
| §18 Proyectil visible sobre la anatomía | ✅ (se dibuja encima de huesos/órganos) |
| §16 Apuntado: sensibilidad H/V, zona muerta, curva, velocidad máx., suavizado, freno de precisión; sin deriva al soltar (antes el joystick soltado seguía mandando su última dirección: era la deriva) | ✅ prueba automática `apuntado_fino` (direcciones, correr al revés, soltar sin deriva, cambiar de arma, toque fino) |
| §17 Cámara configurable (distancia, altura, desplazamientos, seguimiento, zoom/FOV, adelanto) igual en práctica y partida, guardada | ✅ Configuración › Cámara y panel de práctica (CÁMARA Y CONTROLES / GUARDAR / RESTABLECER / VOLVER A LA LOBBY) |
| §5 Armas en la espalda al trepar / escalera / colgado; pistola en la funda | ✅ (antes quedaban flotando) |
| Sangre visible (gotas más grandes, manchas sin sombreado, 3–6 por impacto, charco más rápido con salpicaduras) | ✅ |
| §5/§20 Armas nuevas clasificadas, con precio, alcance, nivel y mejoras | ✅ 18 armas (`docs/ARMAS.md`) |

## Pendiente por fases
* **Fase 3 — práctica**: blancos variados, prueba de parkour/escaleras/ascensor dentro del campo, inventario. 🟡
* **Fase 4 — sistema de juego**: lobby, preparación de equipo (EQUIPAR / DESEQUIPAR / COMPRAR), créditos (una sola moneda),
  municiones por tipo y escasas, pérdida al morir, extracción que conserva, DATOS, atributos 0–100, mejoras de armas. ⬜
* **Fase 5 — Abismo Vertical** (Piso −7 a 0, ver `docs/ATLAS_MAPAS.md`): greybox, mecanismos (ascensor averiado,
  caja fuerte, sistema eléctrico, puertas), rutas alternativas, botín aleatorio. ⬜
* **Fase 6 — IA**: perfiles novato/intermedio/avanzado/experto con la misma percepción y límites que un jugador. ⬜
* **Fase 7 — online**: servidor autoritativo, matchmaking hasta 20, relleno con IA, repetición de muerte LOCAL (nunca
  congela a otros: hoy la cámara lenta es `Engine.time_scale` local y en red se reemplaza por una repetición del cliente). ⬜
* **Fase 8 — optimización y pulido**. ⬜
* **Supabase**: capa de datos desacoplada (`ProfileStore` local ↔ Supabase) sin credenciales inventadas. ⬜ (fase 4)
