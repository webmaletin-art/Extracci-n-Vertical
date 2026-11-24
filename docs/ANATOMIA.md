# Rayos X, bullet time y lesiones

## Qué se ve

* **Disparo:** si la bala va a pegar en un enemigo (se predice la trayectoria antes del impacto) y el tiro es decisivo
  (o la opción está en «Siempre»), el tiempo baja al 3 %, la cámara sigue a la bala 3D (munición de Nexus) y en el
  impacto pasa a primer plano: piel transparente con borde azul, esqueleto, órganos y vasos.
* **Golpes y caídas:** patadas, puñetazos y cuchilladas fuertes y las caídas con daño muestran un instante de rayos X.
* **Daño visible:**
  * **hueso fracturado:** un corte dentado lo atraviesa en el punto del impacto y las dos mitades se separan (shader
    `XRayAnatomy._wound_shader`, modo 0), borde en rojo vivo y polvo de hueso;
  * **órgano o vaso perforado:** túnel a lo largo de la trayectoria de la bala (modo 1) con borde en carne viva;
  * **sangre siempre**: chorro de entrada y salida, goteo desde lo perforado (no se puede apagar).
* El HUD lista lo dañado: «Fractura expuesta: fémur der», «Perforación: hígado», «Hemorragia: vasos izq»…

## Cómo se arma

1. `tools/anatomy/build_anatomy.py` reduce BodyParts3D y asigna cada grupo a un hueso Mixamo.
2. `XRayAnatomy._compute()` ajusta la anatomía al esqueleto de cada personaje: torso, cabeza y piernas con dos
   referencias (caderas y hombros); los brazos (colgando en BodyParts3D, en T en Mixamo) segmento por segmento.
3. Las mallas se cargan recién la primera vez que se muestran y se pegan a los huesos con `BoneAttachment3D`
   (se mueven con la animación).
4. `injuries_at(info)` busca los grupos más cercanos al impacto en el espacio del hueso golpeado.

## Efecto en el juego (`Injuries`)

| Lesión | Efecto | Se cura con |
|---|---|---|
| Fractura de pierna (fémur, tibia, rótula, pie) | renguea con la animación de herido (máx. 1,1 m/s, no corre), salta 55 %, no sube a cajas de más de 0,8 m, trepa al 60 % y sube escaleras a la mitad | venda (entablillar) o botiquín |
| Brazo herido (húmero, radio/cúbito, mano, clavícula, escápula) | dispersión ×(1+1,6·nivel), el arma tiembla, recarga más lenta | botiquín (la venda reduce) |
| Cabeza (cráneo, mandíbula, cerebro) | la puntería oscila | botiquín |
| Órgano o vaso perforado | hemorragia: pierde vida por segundo y gotea sangre | venda o botiquín |

Los bots tienen las mismas lesiones (un enemigo con la pierna rota renguea).

## Próximo paso con Blender

Reemplazar cada grupo por versiones con daño real modelado (hueso astillado, órgano reventado) exportadas en GLB con el
mismo nombre de nodo (`g000`…): `show_xray` las puede intercambiar sin cambiar el resto. Z-Anatomy (`.blend`,
CC BY-SA 4.0) tiene músculos y pulmones para completar lo que le falta a BodyParts3D.
