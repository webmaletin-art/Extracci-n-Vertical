# Anatomía, heridas y daño interno

## Fuente y ajuste al personaje

* **Z-Anatomy** (atlas completo, CC BY-SA 4.0): esqueleto, músculos, órganos (pulmones, corazón, hígado, intestinos…),
  arterias y venas, encéfalo, médula y nervios largos. 1361 piezas exportadas con Blender (`tools/anatomy/export_zanatomy.py`,
  `pip install bpy==5.3.0`) y reducidas a **126 grupos, ~117 000 triángulos** (`tools/anatomy/build_anatomy.py`):
  huesos 36 k, músculos 39 k, órganos 15 k, vasos 12 k, nervios 14 k.
* **Una misma cosa con el personaje** (`tools/anatomy/fit_anatomy.gd`, por personaje → `assets/anatomy/fit/<id>.scn`):
  1. el personaje se pone en la pose de la anatomía (brazos abajo);
  2. torso y cabeza se ajustan por caderas y hombros; brazos y piernas segmento por segmento (cada hueso con su largo);
  3. cada vértice se mete DENTRO de la piel (rayo desde el eje del hueso, margen 8 mm);
  4. cada vértice copia los **pesos de piel** del vértice del personaje más cercano de la misma región;
  5. se pasa a la pose de enlace con la piel inversa → la anatomía usa el MISMO esqueleto y los MISMOS pesos que el
     personaje y se deforma igual en cualquier animación;
  6. se verifica en 8 poses (reposo, apuntar, correr, agachado, escalera, colgado, muerte, patada) y se corrige.

Resultado de la verificación (vértices que quedan fuera de la piel en alguna de las 8 poses, de 64 275):

```
alfa: 64275 vértices · metidos en la pose anatómica 12100 · fuera de la piel (verificación en 8 poses): 750 (máx 13.7 mm)
vigia: 64275 vértices · metidos en la pose anatómica 9754 · fuera de la piel (verificación en 8 poses): 567 (máx 24.7 mm)
doc: 64275 vértices · metidos en la pose anatómica 9430 · fuera de la piel (verificación en 8 poses): 652 (máx 51.9 mm)
fantasma: 64275 vértices · metidos en la pose anatómica 7692 · fuera de la piel (verificación en 8 poses): 1037 (máx 31.9 mm)
mortero: 64275 vértices · metidos en la pose anatómica 9274 · fuera de la piel (verificación en 8 poses): 1251 (máx 50.0 mm)
zapador: 64275 vértices · metidos en la pose anatómica 9330 · fuera de la piel (verificación en 8 poses): 614 (máx 28.5 mm)
```

En las poses de juego normales (apuntar, correr, escalera, patada) son unas decenas de vértices de milímetros. Lo que
queda (≈1 %) está casi todo en la **parte de atrás de la rodilla agachado, en las manos colgado y en la pose de muerte**:
ahí la propia piel del personaje se pliega sobre sí misma con esa animación y no hay un «adentro» claro. Se puede
mejorar con corrección de forma en Blender o con pesos más suaves en el rig de esos personajes.

## Qué se rompe (`Injuries`, `AnatomyBody.trace`)

| Daño | Qué pasa adentro |
|---|---|
| Bala | Se recorre la trayectoria real por dentro del cuerpo: cada hueso que cruza se **fractura** (corte dentado con astillas), cada músculo, órgano, vaso y nervio queda **perforado** (túnel de entrada y salida). En cabeza, cuello, brazos, piernas, manos y pies la bala **sale** y sigue; en el torso se frena adentro (14–26 cm) salvo calibres potentes |
| Astilla de hueso | Un hueso quebrado puede clavar una astilla en una estructura vecina: cráneo → cerebro (60 %), costillas → pulmón / corazón / hígado, esternón → corazón, clavícula → aorta / arterias del cuello / pulmón, vértebras → médula, pelvis → vejiga / arterias, fémur → arteria femoral |
| Esquirla de granada | Proyectil físico (18–26 por granada) que entra y queda **alojado** a 4–12 cm |
| Onda expansiva (cerca) | Tímpanos rotos (sordera: todo suena apagado), **pulmones e intestinos reventados**; en lugar cerrado pega ×1,25–1,4 |
| Lanzado por la explosión | Al chocar con pared o piso a más de 6 m/s: costillas, cráneo, húmero, radio, fémur según la velocidad |
| Caída de pie | > 3,6 m: huesos del pie (talón) 45 %, tibia 15 % · > 5 m: pie 85 %, tibia 55 %, fémur 20 %, lumbares 15 %, pelvis 10 % · > 8 m: además hígado, riñón y costillas |
| Caída mala (lanzado, de costado, soltado) | Órganos ×2 y cráneo |
| Cuchillo | Herida profunda de ≈ 12 cm en la dirección del golpe |
| Puñetazo | Sólo vida (60 % al cuerpo); a la cabeza puede dar conmoción y derribar; con poca vida mata. No rompe huesos |
| Patada al torso | ≈ 20 % fisura de costillas |

## Efecto de cada estructura (`data/anatomy_damage.json`)

Cada estructura tiene vida que quita al instante, hemorragia por segundo y un efecto. Ejemplos:

| Estructura | Vida | Hemorragia | Efecto | Se detiene con |
|---|---|---|---|---|
| Cerebro, cerebelo y tronco | muerte | — | — | — |
| Médula espinal | 45 | 0,5/s | parálisis (casi no camina) | botiquín (la parálisis no se cura) |
| Corazón | 25 | **7/s** | — | botiquín (urgente) |
| Aorta y grandes vasos | 20 | **9/s** | — | botiquín (urgente) |
| Arterias del cuello / muslo | 10 / 8 | 5 / 4 /s | — | botiquín |
| Pulmón | 10 | 1,2/s | no corre | botiquín |
| Hígado | 12 | 2,5/s | — | botiquín |
| Intestinos, estómago | 6 | 0,8/s | — | venda |
| Músculos | 3–5 | 0,2–0,4/s | brazo / pierna según dónde | venda |
| Cráneo | 40 | 0,8/s | puntería oscila | botiquín |
| Fémur / tibia / pie | 15 / 8 / 5 | 1 / 0,4 / 0,2 | pierna rota: renguea, no corre, trepa lento | venda (entablillar) |
| Huesos de la mano | 4 | 0,3/s | el arma tiembla mucho | venda |

La venda corta las hemorragias chicas, frena a la mitad las grandes y entablilla la pierna; el botiquín corta todas y
recupera brazo, mano, cabeza y respiración. Con corazón o aorta perforados hay que llegar a un botiquín en segundos.

## Qué se ve

* **Muertes** (del enemigo por el jugador o del jugador): cámara lenta y cámara que se acerca a la herida que mató
  (cabeza, explosión, caída). Se ven **sólo las partes dañadas** (todas las heridas acumuladas), el cuerpo como silueta
  de rayos X. Si el disparo va a matar, antes la cámara sigue a la bala.
* **Heridas graves que no matan**: destello rápido de las partes dañadas a través del cuerpo, sin cámara lenta.
* **Puñetazos**: nada (sólo la vida).
* **Sangre líquida** (`systems/fx/blood.gd`, idea de BLACK VEIL rehecha con grupos fijos): gotas que se estiran con la
  velocidad, caen con gravedad y dejan manchas en piso y paredes; charco que crece bajo el cuerpo.
  * Entrada y salida del tiro (la salida, más fuerte, cuando la bala atraviesa).
  * **Arteria / corazón / aorta rotos: chorro pulsátil** al ritmo del corazón (75 → 140 latidos por minuto a medida que se
    desangra), con presión que baja con la vida. Sale de la herida y sigue al cuerpo cuando se mueve.
  * **Vísceras y músculos: sangre oscura que mana y gotea.**
  * Una fuente por hueso (se suman las heridas); la venda o el botiquín las cortan; al morir se apagan y queda el charco.

## ¿Daño modelado en Blender?

Todavía no. Blender (`bpy`) se usa para exportar Z-Anatomy; las heridas se dibujan en el juego con un shader sobre la
anatomía (corte dentado con astillas en el hueso, túnel de bala, estallido). Ventaja: aparecen exactamente donde pega
cada bala. Siguiente paso posible: pre-romper en Blender los huesos largos, el cráneo y las costillas en fragmentos
reales (Cell Fracture) y los órganos grandes en versiones reventadas, ajustarlos igual que la anatomía y, en el
impacto, mostrar los fragmentos más cercanos a la herida desplazándose.

## Referencias usadas para calibrar

* Fuerza de puñetazo de boxeadores olímpicos ≈ 3 427 N (Walilko et al., 2005): https://pubmed.ncbi.nlm.nih.gov/16183766/
* ≈ 3 300 N dan ≈ 25 % de fisurar una costilla; el nocaut depende del giro de la cabeza (C. Bir):
  https://livescience.com/6040-brute-force-humans-punch.html
* Caídas de pie > 3 m: el talón es la fractura más frecuente, luego pie, tobillo y tibia:
  https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12491098/ · altura ≥ 5 m aumenta la gravedad; caer de costado o de
  espalda es peor: https://link.springer.com/10.1038/s41598-021-95226-w
* Lesiones por explosión (primarias: tímpano desde ~5 psi, pulmón 15–50 psi; secundarias: esquirlas, principal causa
  de bajas; terciarias: ser lanzado; peor en lugar cerrado): https://en.wikipedia.org/wiki/Blast_injury ·
  https://msdmanuals.com/professional/multimedia/table/mechanisms-of-blast-injury

Los valores del juego son de balance, inspirados en esas referencias, no un modelo médico.
