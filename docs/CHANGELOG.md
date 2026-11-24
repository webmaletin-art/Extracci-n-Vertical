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
