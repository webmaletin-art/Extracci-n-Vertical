# Inventario de recursos (FASE 1 — auditoría)

Regla: reutilizar lo que hay, comprobar que funciona, no tocar los repositorios originales y anotar de dónde sale cada cosa.

## Repositorios revisados

| Fuente | Qué hay | Formato | Cantidad | Esqueleto | Compatibilidad | Licencia |
|---|---|---|---|---|---|---|
| `mixamo-respaldo` | Todas las animaciones de Mixamo clasificadas (18 categorías, 38 packs) | FBX binario 7.7, 30 fps, **sin piel** (la malla está en `personajes/ybot_tpose.fbx`) | 3099 archivos / 2446 únicas + 2 packs GLB extra (personas y perro, no Mixamo) | Mixamo (`mixamorig:*`, 65 huesos con dedos) | ✅ directa: mismos nombres de hueso que los personajes de Nexus | Términos de Mixamo (uso en juegos permitido) |
| `Operaci-n-Nexus-1` (BLACK VEIL) | 15 personajes rigeados, 15 armas procesadas con marcadores, munición 3D, íconos, 723 modelos de decorado, sonidos de armas y ambiente, IK de brazos | GLB (personajes ~20 k triángulos), `.scn` + texturas webp (armas), OGG/WAV | ver abajo | Mixamo (rig de Tripo3D, el esqueleto viene girado a +X: lo corrige `CharacterModel`) | ✅ | Propio (mismo autor); decorado: bibliotecas de Sweet Home 3D (FAL / CC0 / CC BY) |
| Subida «Extracción Vertical» (anatomía) | BodyParts3D por sistemas (huesos 244, órganos 276, vasos 623, músculos 53, nervios 52, ligamentos 8, piel 2) + Z-Anatomy y Z-Biomechanics (`.blend`) | GLB 83 MB (3,1 M triángulos) · Blend 300 MB | 1258 piezas | ninguno (piezas sueltas, posición anatómica) | ✅ tras reducir y asignar a huesos (`tools/anatomy`) | BodyParts3D: **CC BY 4.0**; Z-Anatomy: CC BY-SA 4.0 (sólo para trabajar en Blender, no entra al juego) |

## Usado en el juego

### Personajes (de Nexus, `data/characters.json`)

| id | rol | triángulos | uso |
|---|---|---|---|
| alfa | Asalto | 19 946 | jugador |
| zapador, mortero, fantasma, vigia, doc | enemigos | 18 968 – 19 890 | bots |

Problemas encontrados: los GLB de Tripo3D miran a +X y tienen otra rotación de reposo por hueso → `CharacterModel`
calcula una corrección por personaje (una vez, en memoria). La referencia de reposo se guardó en
`assets/anims/ref_skeleton.json` para no cargar el FBX del operador (13 MB) en el teléfono.

### Armas (de Nexus, «de a poco»)

| id | nombre | tipo | cómo aparece |
|---|---|---|---|
| am4 | AR-15 AM4 | fusil | inicial |
| browning | Browning HP | pistola | inicial |
| mp5 | MP5 | subfusil | botín / enemigos (P2–P4) |
| remington | Remington 31 | escopeta (8 perdigones) | botín / enemigos |
| awm | AWM | francotirador **sin mira** (decisión de diseño) | P4 (botín) |

Pendientes para sumar con los mismos datos: browning ya está; `m24`, `mac10`, `stevens`, `subfusil`, `tambor`, `z15`,
`service`, `sr14`, `m79` (lanzagranadas). Sin modelo todavía: **bate, hacha, arco** (las animaciones existen:
`Pro_Melee_Axe_Pack`, `Longbow_*`, `Baseball_*`); el cuchillo es procedural hasta tener un GLB.

### Animaciones elegidas (65, `tools/anim_builder/anims.json`)

| Grupo | Fuente (mixamo-respaldo) |
|---|---|
| Locomoción con fusil (idle, apuntando, caminar/correr/sprint adelante y atrás, agachado) | `packs/Pro_Rifle_Pack` (*_inplace) |
| Pistola | `packs/Pistol_Handgun_Locomotion_Pack` |
| Salto (subida, aire, caída) | `Pro_Rifle_Pack/jump_*` |
| Escalera de mano: subir (ciclo de 0,77 s), empezar, salir arriba | `saltos_parkour/Climbing_Ladder`, `Start_Climbing_Ladder`, `Climbing_To_Top` |
| Bordes: agarrarse, colgado, trepar, soltarse; subir a cajas; pendiente | `Braced_Hang`, `Hanging_Idle`, `Braced_Hang_To_Crouch`, `Braced_Hang_Drop_2`, `Climbing_6`, `Climbing_4` |
| Golpes: jab, cross, gancho, patada frontal y lateral | `combate_pelea/Punching*`, `Kicking_2`, `Mma_Kick` |
| Cuchillo: guardia, puñalada, puñalada invertida | `Knife_Idle`, `Stabbing`, `Stabbing_3` |
| Reacciones: leve, cabeza (2), estómago (2), gancho, tiro en el vientre; derribo y levantarse | `Basic_Shooter_Pack/hit_reaction`, `Head_Hit_*`, `Stomach_Hit`, `Big_Stomach_Hit`, `Receive_Uppercut_To_The_Face`, `Pro_Melee_Axe_Pack/standing_react_large_gut`, `Knocked_Down`, `Getting_Up_3` |
| Muertes (6) | `Pro_Rifle_Pack/death_*`, `caidas_muertes/Falling_*_Death`, `Dying_Backwards` |
| Caídas: en el aire, aterrizaje duro, rodar, de cara | `Action_Adventure_Pack/falling_idle`, `hard_landing`, `falling_to_roll`, `Falling_Flat_Impact` |
| Herido (pierna rota): quieto, caminar adelante/atrás, correr | `packs/Male_Injured_Pack` |
| Interacción: arrodillado trabajando (forzar caja), revolver, botón, levantar, lanzar granada | `Kneeling_Inspecting`, `Rummaging`, `Button_Pushing`, `Picking_Up_Object`, `Basic_Shooter_Pack/toss_grenade` |

Buscadas y disponibles para la próxima etapa: apuntar arriba/abajo (no hace falta: lo hace la IK), bate
(`Baseball_*`), hacha (`Pro_Melee_Axe_Pack`, 30 clips), arco (`Longbow_Aiming_Pack`, `Pro_Longbow_Pack`),
cobertura (`Action_Adventure_Pack/*cover*`), cuerdas (`Climbing_A_Rope*`).

### Anatomía (rayos X)

`tools/anatomy/build_anatomy.py` toma huesos, órganos (sin cámaras ni conductos chicos), cerebro y 141 vasos
principales, los reduce a **~63 000 triángulos** repartidos por importancia (huesos largos y cráneo con más detalle) y
los agrupa en 71 regiones asignadas a huesos Mixamo → `assets/anatomy/anatomy.glb` (1,5 MB) + `anatomy.json`.
Limitaciones de BodyParts3D: no trae pulmones (sí tráquea y bronquios) y casi no tiene músculos de brazos y piernas.

### Sonidos

* De Nexus (`assets/sounds`): disparos y recargas grabados de BLACK VEIL (`bv_*`), pasos por material, impactos,
  granadas, explosión, recargas, ambiente (generador, viento, lluvia), interfaz.
* Nuevos con ElevenLabs (29): puñetazos, patadas, golpe al aire, cuchillo, abrir cajas (madera, metal, cerradura,
  tapa), madera y vidrio rompiéndose, chapa cayendo, escalón de escalera, ascensor (arranque, marcha, frenada), botón,
  acceso denegado, aturdidora, humo, fuego, vapor, latido y bala en cámara lenta. Registro con el texto de cada uno y los
  créditos: `docs/audio/elevenlabs_ledger.jsonl` (≈300 créditos en total).

### Decorado (galería de Nexus / Sweet Home 3D)

30 modelos industriales y de laboratorio (`assets/props/props.json`): cajas, barriles, palets, contenedor, montacargas,
estanterías, bancos de trabajo, armarios, consolas y equipos de laboratorio, luces, rejas. Licencias en
`assets/props/CREDITOS_SH3D.txt`.
