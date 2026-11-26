# Abismo Vertical (mapa subterráneo)

Instalación de **8 pisos** (Piso −7 abajo … Piso 0 en la superficie), 120 m de ancho. Datos en `systems/map/abismo.gd`
(los arma `TowerBuilder`, igual que la Torre Alfa). Se empieza en el fondo; arriba hay mejores armas y más enemigos.

| Piso | Nombre | Enemigos | Lo escrito a mano |
|---|---|---|---|
| −7 | Cimientos | 2 | pistola y mina al inicio · bóveda derecha (tarjeta amarilla) con 2 maletines de lab y una Deagle |
| −6 | Depósitos | 3 | caja con la tarjeta amarilla |
| −5 | Servicios | 3 | palanca → persiana (x = 80) · entrepiso con caja que guarda la tarjeta azul |
| −4 | Túneles | 4 | **extracción fija** (x = 114) · trampa de gas con palanca |
| −3 | Laboratorios | 4 | bóveda (tarjeta azul) con armas de alto nivel · respiradero de vapor |
| −2 | Oficinas | 5 | caja con la tarjeta roja |
| −1 | Seguridad | 5 | bóveda final (tarjeta roja) · vapor |
| 0 | Vestíbulo | 6 | acceso a la superficie |
| Sup. | Azotea | – | **helicóptero** (llega a los 4 min, hélice girando) |

Conexiones: 2 escaleras de mano por piso, 3 escaleras inclinadas, ascensor central (x = 60) con las 8 paradas.
**Paredes que se rompen, puertas para patear y vidrios: APAGADOS en el mapa (decisión del autor; se retomarán).** El código sigue (`office`, `glass`, `thin`). Paredes disponibles hoy: `door` (vano abierto), `duct`, `locked:<tarjeta>`, `shutter:<id>`. Antes: `office` (puerta que se patea / se baleá), `glass` (vidrio), `thin` (tabique fino: aguanta unos tiros),
`locked:<tarjeta>`, `shutter:<id>` (persiana que abre una `lever`). Romperlas hace ruido (`NoiseBus`).
`tests/map_shots.tscn -- <carpeta> [piso:x …]` saca capturas del mapa.

## Mecánicas nuevas (todas con prueba `mecanicas` / `abismo`)

* **Patada a la puerta:** botón USAR junto a una puerta de oficina → `Actor.kick_at`. Ruido 18–28 m.
* **Mina de proximidad** (botón «MINA» / tecla M): se arma en 1,5 s y explota con enemigos (`systems/weapons/mine.gd`).
* **Indicador de ruido** (`systems/ui/noise_overlay.gd`): ondas en la dirección del sonido (arriba/abajo/izq./der.), más fuertes cuanto más cerca; ▲/▼ si viene de otro piso.
* **Especialidades** (`systems/actor/specialty.gd`, botón «ESP» / tecla Q, se elige en el menú): Radar (10 s, enemigos + distancia), Paramédico, Velocista (+50 %), Escudo (domo 160 de daño / 7 s), Cohete (teledirigido), Demoledor (+2 minas, +1 granada). Recarga 35–60 s.
* **Persianas con palanca y trampas de gas.**

## Pendiente (acordado, aún no hecho)

Progresión (experiencia, chaleco, cargadores), modos (conquista de pisos, bomba, deathmatch), 20 jugadores / online, IA por perfiles,
caída de la puerta con animación propia, armas ocultas con lore, ajuste fino del mapa tras la prueba en el teléfono.
