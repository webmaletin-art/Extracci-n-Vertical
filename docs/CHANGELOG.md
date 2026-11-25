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
