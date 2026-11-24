# Multijugador (preparación)

Primera etapa: un jugador local contra bots. La arquitectura ya separa **intención** (ActorInput) de **simulación**
(Actor), que es lo que permite pasar a red sin rehacer sistemas.

## Autoridad

**Servidor autoritativo** (Godot `MultiplayerAPI` / ENet; servidor dedicado sin gráficos con el mismo proyecto).

| Qué | Quién decide | Qué viaja |
|---|---|---|
| Movimiento | servidor simula `Actor` con el `ActorInput` de cada cliente; el cliente predice el suyo y corrige | cliente → servidor: `ActorInput` por tick (move, aim, botones, número de tick) · servidor → clientes: posición, velocidad, estado, facing |
| Dirección de apuntado | el cliente la manda (es entrada); el servidor la limita (velocidad angular máxima) | `aim` dentro del `ActorInput`; los demás la reciben en el estado (para la IK y el láser) |
| Disparos | servidor: valida cadencia y munición, crea el proyectil en `Ballistics` con la semilla de dispersión | evento «disparo» (arma, origen, dirección, semilla) para efectos en clientes |
| Proyectiles | servidor integra; los clientes simulan la misma trayectoria sólo para verla (determinista con la semilla) | sólo impactos confirmados |
| Daño y lesiones | servidor (`take_damage`, `Injuries`) | vida, lesiones, muerte |
| Inventario y botín | servidor (`Inventory`, `Inventory.roll` con RNG del servidor) | cambios de inventario del propio jugador |
| Destrucción | servidor (fase de cada `Destructible`); los fragmentos son sólo visuales y locales | id + fase nueva |
| Contenedores / puertas / ascensor | servidor (estado y progreso) | eventos y estado |
| Extracción | servidor | resultado de la partida |
| Cámara lenta / rayos X | **local** (no frena el tiempo de los demás): en red se reproduce como repetición del impacto | — |

## Lo que ya respeta esto

* `Actor` sólo actúa según `inp` (los bots usan el mismo camino) → la entrada se puede recibir por red.
* La IA (`BotBrain`) correría sólo en el servidor.
* Todo lo aleatorio que afecta al juego (botín, dispersión) pasa por un `RandomNumberGenerator` que se puede sembrar.

## Pendiente

Identificadores de red para destructibles y contenedores (hoy por orden de construcción, que es determinista),
`MultiplayerSynchronizer` del estado de `Actor`, y la regla PvP (`BOT_DAMAGE_TO_PLAYER` vale sólo contra bots).
