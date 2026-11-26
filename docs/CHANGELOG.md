# Registro de cambios

## 0.4.0 — escenario liviano (según el informe del Mali-G57)

* Pisos y paredes con shader sin luces reales y luz pintada; tuberías y cables pintados; pool de 0 / 2 / 4 luces reales;
  resolución 3D relativa a 720p; sombras simples; sin niebla ni brillo; pisos más cortos; 507 → 196 dibujos en ALTA.

## 0.3.1 — huesos más lindos

* Sombreado suave (los colores por cara facetaban todo), huesos con 72 000 triángulos (cráneo ≈ 29 000), cráneo en 9
  placas con cortes menos serruchados, poros y tono marfil en el shader; el hueso entero es la unión de sus fragmentos
  (mismo peso por personaje). Trayectorias probadas fragmento por fragmento.

## 0.3.0 — huesos rotos de verdad y rayos X como Sniper Elite

* Huesos partidos en Blender (301 fragmentos de 41 huesos) y ajustados a cada personaje; los cercanos al impacto se
  desprenden y vuelan (trozos con física simple, reutilizables).
* Bala que se desvía en huesos densos, que queda aplastada en hongo adentro, rebotes en metal y piso que hieren más.
* Rayos X localizados: la ropa queda, la zona de la herida se abre y muestra huesos, órganos, vasos, ojos, orejas y
  músculos; cámara de muerte que sigue la herida.
* Anatomía: orejas, dedos de la mano y ojos izquierdo / derecho como grupos propios.

## 0.2.1 — sangre líquida

* Sangre líquida (gotas con gravedad, manchas en piso y paredes, charco); chorro arterial pulsátil que sigue al cuerpo;
  sangre oscura de vísceras; se corta con venda / botiquín.

## 0.2.0 — anatomía completa y daño interno

* Anatomía completa de Z-Anatomy (huesos, músculos, órganos, arterias y venas, encéfalo, médula, nervios) ajustada DENTRO
  de cada personaje con sus mismos pesos de piel (se deforma con cualquier animación).
* Daño interno real: trayectorias por dentro del cuerpo, fracturas, perforaciones, astillas de hueso hacia órganos,
  esquirlas alojadas, onda expansiva (pulmones, tímpanos), lanzado contra paredes, caídas por altura, efecto y
  hemorragia por órgano (`data/anatomy_damage.json`); puñetazos sólo quitan vida.
* Cámara lenta con acercamiento sólo en las muertes; destello rápido de las heridas graves en el juego.
* Escalera: el personaje queda de espaldas a la cámara.
* Zonas de impacto de manos y pies; balas que atraviesan cabeza y miembros.

## 0.1.0 — primer entregable (vertical slice)

* Proyecto nuevo en Godot 4.7.2 (GL Compatibility, Jolt).
* Torre Alfa (P0–P4 + azotea) con escaleras de mano, escalera inclinada, ascensor, cráter escalable, conducto,
  plataforma móvil, puerta con tarjeta, ruta secreta, zona de vapor y dos extracciones; esquema comprobado sin
  sectores inaccesibles.
* Personaje (Nexus) con 65 animaciones de Mixamo, movimiento progresivo, apuntado persistente, láser, parkour.
* Armas de Nexus con balística física; cuchillo, puños y patadas; 5 tipos de granada; destrucción; saqueo con cuchillo.
* Rayos X con anatomía BodyParts3D, fracturas y perforaciones, bullet time; lesiones con efecto en el juego.
* IA con oído y vista; sonidos de Nexus + 29 efectos de ElevenLabs.
* Configuración gráfica BAJA/MEDIA/ALTA y captador de rendimiento.
* 12 pruebas automáticas, workflow de APK.

## 0.5.0 — Práctica, menús y controles
- **Modo práctica** (ver `MODO_PRACTICA.md`): maniquí, armas y municiones, tiro dirigido a ojo / estómago / testículos, tomas de cerca, grabación de cuadros.
- Anatomía: nuevo grupo **testículos** (antes dentro de «vejiga»), daño específico y textos detallados para ojo, estómago, intestinos y testículos (`data/anatomy_damage.json`, campos `text` y `stun`); el disparo de frente puede darle al globo ocular.
- Rayos X: músculos con haces de fibras, fascia y tendones; vísceras húmedas; ojo con iris y venas.
- **HUD táctil**: joystick de apuntar bien a la derecha, botones de acción entre los joysticks; **editor de controles** (mover, tamaño por botón, transparencia, modo zurdo), distancia de cámara y vibración en Configuración.
- **Menú principal** con la Torre Alfa en corte girando (`MenuTower`) y **Configuración** rediseñada con navegación lateral (`UiTheme`).
- Prueba de anatomía: hasta 8 intentos (la bala puede desviarse en el hueso por azar; falló una vez en CI).

## 0.6.0 — Anatomía de calidad máxima, la bala por dentro, menú de la torre
- **Rayos X sólo en la muerte**: las heridas que no matan ya no muestran destello ni textos en pantalla (quedan en
  `Game.injury_stats`). En el modo práctica se puede ver la toma de cada herida.
- **Anatomía de calidad máxima** en todos los personajes (huesos sin reducir: ~430 000 triángulos; órganos ~250 000;
  vasos ~200 000; nervios/ojos/cerebro ~105 000) y **sin músculos** en los rayos X (como Sniper Elite).
- **Huesos enteros hasta el impacto**: se guarda el hueso entero y sus fragmentos de Blender; recién al romperse se ven los
  fragmentos, abiertos sólo cerca del impacto (hueso esponjoso con sangre). Fractura por pieza suelta (cada costilla,
  vértebra, hueso del cráneo), con superficie irregular y sin costuras; agujeros de la malla cerrados antes del corte.
- **Esqueleto continuo**: sin recorte esférico; la ropa desaparece en la zona y el resto del esqueleto sigue debajo.
  El cerebro sólo se ve si se rompe el cráneo; partes blandas y nervios sólo si están dañados.
- **La bala por dentro** (repetición de 4 s en cámara lenta): recorrido real calculado por `Injuries`, bala de Blender
  (`tools/ammo/make_bullets.py`: 7,62 mm con camisa de cobre y base de plomo, y versión en hongo), gira sobre su eje, se
  aplasta en hueso duro, da vueltas si se desvía; cada daño aparece cuando la bala llega; gotas finas; salpicadura en la
  entrada, chorro en la salida y goteo al piso.
- Lo que tapa la herida principal se vuelve transparente durante la toma; sin láser en la toma; viñeta de foco.
- Arreglo: el modelo de la bala en vuelo tenía el origen corrido ~0,9 m.
- **Menú**: Torre Alfa de noche bajo la lluvia (pisos B0-B4 iluminados, escaleras, portón, antena con baliza, piso mojado
  con reflejo, valla con alambre de púas, cartel TORRE ALFA A, farol, torres con luces rojas).
- Rendimiento: la anatomía se prepara en segundo plano al cargar la partida (`AnatomyBody.warm`).

## 0.7.0 — Fase 2 del plan maestro, armas nuevas y sangre
- 13 armas nuevas (Blender, tamaño real, marcadores de manos) → 18 en total, clasificadas con precio, alcance, nivel y
  mejoras (`docs/ARMAS.md`); daño que baja pasado el alcance; supresor más silencioso.
- Cámara de muerte breve (sin cámara lenta extrema); práctica usa la misma cámara que la partida.
- Apuntado rehecho (sensibilidad H/V, zona muerta, curva, freno de precisión, suavizado) y arreglo de la deriva.
- Cámara configurable y compartida entre práctica y partida; panel de práctica con GUARDAR / RESTABLECER / VOLVER.
- Fusil a la espalda / pistola en la funda en escaleras, colgado y trepando.
- Sangre visible: gotas y manchas más grandes y sin depender de la luz, más manchas por impacto, charco más rápido.
- Auditoría y plan por fases: `docs/PLAN_MAESTRO.md`; atlas de mapas: `docs/ATLAS_MAPAS.md`.

## 0.8.0 — Experimento: visualización técnica 3D
- Autoload `TechView` (reversible, no guarda nada): A filtro de pantalla, B materiales técnicos + contorno, C híbrido;
  rayos X realista / técnico gris / técnico con colores; parámetros en vivo. Se activa en Modo práctica y sigue
  activo al ir a la Torre en la misma sesión. Informe y mediciones: `docs/VISUAL_TECNICO.md`.

## 0.9.0 — Modo D «Plano dibujado» y daño por potencia

* Estilo D: sin texturas, luces ni sombras; tonos planos y líneas de tinta en bordes (agrupadas por tramos del mapa);
  grosor ajustable; láser negro; explosión como onda de líneas. Reversible desde Modo práctica.
* Test de rendimiento de estilos en Modo práctica (≈1 min, con disparos y granada, informe copiable).
* Daño por potencia: sangre y orificio de herida según el daño; escopeta rompe más huesos de cerca.
* Impactos visibles durante la cámara de muerte; rebotes corregidos (umbrales por material).

## 0.9.1 — estilo D por defecto y calidad sólo de anatomía

* El estilo «D · Plano dibujado» arranca activado (Modo práctica permite volver al original).
* La calidad gráfica (BAJA / MEDIA / ALTA) sólo cambia anatomía y daño: rayos X y sangre / fragmentos. Resolución 720p,
  sombras, luces, MSAA, decorado, humo y explosiones quedan fijos (`Settings.LOCKED`); se quitaron sus opciones del menú.
* Medición en el Z2356 (1600×720): original 41,4 FPS · A 24,2 · B 51,1 · C 37,1 · D 50,9.

## 0.9.2 — el cuerpo muerto sigue recibiendo impactos

* Al morir, las zonas de impacto del cuerpo siguen activas: los disparos que siguen (rayos X incluido) hieren, rompen
  huesos, salpican sangre y sacuden el cuerpo. Prueba nueva `cuerpo_muerto`.
* Cámara de muerte: si muere otro enemigo en plena toma, la toma pasa a ese cuerpo (antes no se encendía el rayos X);
  el radio de la ventana se conserva con los impactos siguientes.
* Estilo plano: las mallas nuevas (enemigos que aparecen) se convierten en el acto, sin cuadros con los colores originales.

## 0.10.0 — desmembramiento

* Sólo en cuerpos que ya murieron o que mueren con el tiro (un cuerpo vivo no pierde miembros). El daño se acumula por
  miembro: pistola ≈ 3 tiros, fusil ≈ 2, calibre grueso 1; la escopeta de cerca suma todos los perdigones y arranca
  varios miembros. Cuello (cabeza) sólo con arma potente.
* Cortes en articulaciones: hombro, codo, muñeca, cadera, rodilla, tobillo y nuca. El hueso se achica a casi cero
  (`LimbCutter`, modificador del esqueleto), así desaparece el miembro con traje, huesos y vasos; queda un muñón con corte
  de carne y hueso y un chorro arterial a latidos (~9 s).
* El miembro suelto (`Limb`, cuerpo rígido en el plano) sale despedido, gira, cae y sangra; mientras se ve la ventana
  de rayos X de ese cuerpo se muestra su versión de huesos y vasos; después, la normal.
* Pendiente: cortes a mitad de hueso (hoy sólo en articulaciones).

## 0.10.1 — orificios pegados al cuerpo y controles visibles

* Los orificios de bala se meten hacia el hueso (el punto de impacto está en el borde de la zona de impacto, más grande
  que el cuerpo), con la profundidad de la piel según la zona; siempre visibles sobre la ropa y ocultos en la toma de rayos X.
* Botones y joysticks táctiles: fondo oscuro, aro negro + aro de color y letra con borde (se leen sobre fondo blanco);
  botones de acción más cerca del joystick derecho.

## 0.11.1 — se recuperan las armas de Nexus

* Se deshace el cambio de 0.11.0: `am4`, `mp5` y `browning` vuelven a sus modelos de Operación Nexus (con texturas). Los modelos livianos (M4A1, MP5_1 y M1911 Táctica) se pueden volver a generar con `tools/weapons/convert_fbx.py -- <FBX> <salida> <markers.json> am4 mp5 browning`.

## 0.12.0 — las 21 armas subidas

* El juego tiene exactamente las 21 armas subidas (13 ya convertidas + 8 variantes: M1911 B, M1911 Táctica, M16 B, MP5 A / B, SCAR, M4A1, M4A1 B), todas livianas. Se quitan los modelos pesados de Operación Nexus (`browning`, `am4`, `mp5`, `remington`, `awm`) y se actualizan el mapa, el botín, los enemigos, el arma inicial (M1911 + M4A1), los objetos y las escenas de trailer. Sin escopeta ni .50 por ahora.

## 0.13.0 — 61 armas clasificadas por tipo y poder

* Se suman las 40 armas del pack *Ultimate Gun Pack* (Quaternius): 6 pistolas, 5 revólveres, 5 subfusiles, 9 fusiles / carabinas, 3 bullpup, 6 escopetas, 2 tiradores y 4 francotiradores / .50. Modelos de ≈ 700-1 900 triángulos.
* Cada una con calibre, daño por calibre, cadencia, cargador, recarga, alcance, dispersión y retroceso simulados a partir de armas reales (`tools/weapons/gen_roster.py`); precio y nivel salen de su poder (DPS y alcance). `docs/ARMAS.md` las lista por tipo con DPS y tiros para matar.
* Escopetas y rifle .50 BMG vuelven al juego. El modo práctica muestra las capacidades del arma elegida (calibre, daño, cadencia, DPS, alcance, cargador, recarga).
* Todas las armas se pueden encontrar en cajas y maletines y vender (`w_<id>`); munición por calibre.

## 0.14.0 — munición por tipo, Armería y menú blanco lineal

* **Munición:** 6 tipos por arma (estándar, trazante, punta hueca, perforante, incendiaria, punta de flor) en 19 calibres; las
  pistolas del mismo calibre comparten munición. Datos en `data/ammo.json` (generado por `tools/ammo/gen_ammo.py`), 114 cartuchos
  modelados en Blender (`tools/ammo/make_cartridges.py`). Precio por caja según energía × tipo: más potencia, más caro.
* **Efecto real por tipo:** daño, penetración, rebote, dispersión y ruido; además hueso (`bone`), tamaño de herida (`wound`),
  sangre (`blood`) y órganos (`organ`). La incendiaria revienta órganos al entrar; la punta de flor es la de mayor daño.
  Las heridas no letales dejan una mancha de sangre que se expande sobre la ropa/cuerpo bajo el orificio.
* **Cambio en partida:** botón «MUN» del HUD (`Actor.cycle_ammo`); `Firearm.reserves` guarda las balas por tipo.
* **Perfil** (autoload `Profile`): créditos, armas propias y equipadas, stock de munición; se guarda en `user://perfil.json`;
  se lleva al combate y se devuelve al extraer (morir pierde lo cargado). La munición sólo se compra con el arma en propiedad.
* **Armería** (`systems/ui/armory.gd`, botón en el menú): operador con el arma bien empuñada y cámara libre (arrastrar, rueda o
  pellizco, «VER EL ARMA»), cartel con datos (daño, cadencia, DPS, alcance, cargador, recarga, control, precisión) y, abajo, los
  cartuchos en 3D (parados y tumbados) con «USAR» y «COMPRAR».
* **Menú blanco con líneas:** `UiTheme` claro (tinta sobre blanco) y la torre de la portada pasa por el modo «Plano dibujado».
* Prueba nueva `municion` (tipos, precios, compra sólo con el arma). 17 pruebas, 0 fallas.

## 0.15.0 — Abismo Vertical y mecánicas nuevas

* **Mapa Abismo Vertical** (8 pisos, 120 m, 2 extracciones: túnel fijo y helicóptero a los 4 min). Ver `docs/ABISMO_VERTICAL.md`. Menú: «JUGAR · Abismo Vertical».
* Puertas de oficina (patada o disparos), vidrios y tabiques finos que se rompen con ruido; puertas con tarjeta de varios colores; persianas con palanca; trampa de gas.
* Minas de proximidad, indicador de ruido direccional, especialidades (radar, paramédico, velocista, escudo, cohete, demoledor).
* Helicóptero con hélice girando; menú con la Torre real en línea y el operador de espaldas; Armería con datos flotantes y cartuchos en línea; agarre de pistola corregido (hombros).
* Pruebas nuevas `abismo` y `mecanicas`: 19 pruebas, 0 fallas.

## 0.15.1 — pack «Flat Guns East»

* 10 armas planas nuevas (`flat_*`): 2 pistolas, 2 subfusiles (uno compacto tipo MAC), 2 fusiles, 2 escopetas y 2 francotiradores (uno .50 antimaterial). Conversión con `tools/weapons/convert_fbx.py` (ahora conserva `models.json` al convertir ids sueltos). 71 armas en total.

## 0.15.2 — correcciones tras la prueba

* Práctica: ya no queda la Torre dibujada de fondo (TechView borra las líneas agrupadas al cambiar de escena); placas de rebote opcionales (apagadas por defecto, no estorban); la munición de escopeta usa sus propios cartuchos.
* Heridas más chicas, pegadas a la piel y centradas en el cuerpo (no en el borde de la silueta).
* Puntería: la mira asentada y quieta corrige hacia el centro del torso; corriendo o disparando de inmediato la dispersión crece hasta ×3 y el tiro puede ir a cualquier parte.
* Munición: la incendiaria es una llama diminuta pero revienta órganos; la punta hueca desgarra; la perforante deja orificio de salida que sangra; la escopeta de cerca destroza huesos y órganos.
* Desmembramiento: la pierna entera sale por la ingle con un tiro potente o al morir.
* Armería: cada tipo de munición muestra un cartucho parado y otro tumbado con la punta de frente.
* Agarre: los hombros se abren un poco hacia afuera al apuntar.

## 0.15.3

* Abismo Vertical: sin paredes que romper, puertas para patear ni vidrios (el código queda apagado); más obstáculos (coberturas) en todos los pisos.
* Agarre: la clavícula acompaña al brazo y la torsión del antebrazo se reparte (menos «caramelo» en la muñeca y hombro hundido). `tests/grip_shots.tscn` con `NATURAL=1` saca la captura en colores reales.
* TechView convierte las mallas nuevas antes de dibujar el cuadro: no se ve más el color real por un instante.
* Práctica: usa la configuración del juego (sin forzar la toma de cerca) y tiene el botón «CONFIGURACIÓN DEL JUEGO»; sombras según la calidad elegida.
* Fx: no falla si el grupo de efectos quedó de un mapa anterior.

## 0.15.4

* Los personajes (jugador y enemigos) se ven de perfil exacto (90°), sin giro hacia la cámara; la culata del fusil apoya en el frente del hombro.
* Apuntado con joystick: al pasar de un lado al otro la mira se espeja de golpe (conserva la altura) en vez de recorrer el arco por arriba o por abajo.
* Pistola: brazos más estirados (semiflexionados) y más bajos, lejos de la cara; probado con alfa, vigia y doc.
* Pistola: el brazo sale del hombro por fuera del chaleco (antes salía del pecho): mira por fuera del hombro de tiro, codo hacia afuera, sin adelantar la clavícula; a la altura del pecho y más estirado. Probado en colores reales con alfa y vigia.

## 0.15.5 — empuñaduras reales en las 71 armas

* Nuevos marcadores de manos para TODAS las armas (`tools/weapons/fix_grips.py`): la derecha en la empuñadura de pistola (antes varias agarraban el cargador o el guardamonte), la izquierda en el guardamanos, en la corredera de la escopeta o en la empuñadura vertical delantera. Pistolas y revólveres se calculan solos de la silueta; fusiles, subfusiles, escopetas y francotiradores están marcados a mano (`tools/weapons/grips_manual.py`) mirando el perfil de cada modelo. Hoja de control: `docs/img_empunaduras.png` (rojo = mano derecha, azul = izquierda).
* Empuñadura vertical delantera: la mano izquierda la rodea (marco propio `VGRIP_LEFT`), no se apoya con la palma arriba.
* Subfusiles y armas sin culata (smg_1, smg_4, ar_1, ar_3, ar2_3, escopetas recortada y de culata corta): se sostienen adelante con los dos brazos estirados en vez de apoyarse en el hombro (`stockless` en models.json). Los subfusiles compactos con culata (MP5 y otros) se apoyan un poco más adelante para no tocar la cara.

## 0.16.0 — modelos «en línea» horneados (etapa 1: armas y props)

* `tools/bake_lined.gd` (`godot --headless --script tools/bake_lined.gd -- weapons|props|all`) genera `assets/lined/`: cada modelo sin texturas ni colores originales, con tono plano por pieza (armas: `tech_surface` + contorno) o relleno plano + aristas ya calculadas (props: `tech_flat` + malla `Lineas`). Se marca `no_tech`: TechView no lo convierte. `LinedBake` (`systems/render/lined_bake.gd`) comparte la extracción de aristas con TechView.
* Cargan la versión en línea si existe: `Firearm.create` (71 armas), `TowerBuilder._prop` y `Destructible.setup` (cajas y objetos). Si falta el archivo se usa el modelo original con el filtro.
* Anatomía: no se toca (queda tal cual). Pendiente de las próximas etapas: personajes (esqueleto), arquitectura del mapa y munición.
