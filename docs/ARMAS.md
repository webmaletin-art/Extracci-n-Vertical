# Armas de Extracción Vertical

Datos en `data/weapons.json` (se cambian ahí, sin tocar código). Ordenadas por clase y precio.
**Actualización:** los modelos pesados de Operación Nexus de `am4`, `mp5` y `browning` se reemplazaron por los livianos subidos (M4A1, MP5_1 y M1911 Táctica, color liso, ≈ 0,9 MB en total contra 1,5 MB y sus texturas), con los mismos id y estadísticas; quedan `remington` y `awm` de Nexus hasta tener modelos livianos de una escopeta y un rifle .50.
**Repetidas (antes):** se usó la de mejor calidad — el fusil M4 y el MP5 de Operación Nexus (con texturas PBR) quedan en lugar de los
M4A1 / MP5 subidos (color liso); de los M1911, M16 y SCAR se usó la versión más detallada (M1911, M16, SCAR-H). Las armas
subidas se convierten con `tools/weapons/convert_fbx.py` (Blender): tamaño real, boca del cañón a −Z, marcadores de manos;
Vector (114 000 triángulos) y AUG (283 000) se redujeron a ~16 000.

| Arma | id | Clase | Nivel | Precio | Daño | Disparos/min | Cargador | Alcance | Dispersión | Retroceso |
|---|---|---|---|---|---|---|---|---|---|---|
| Pistola M1911 Táctica | `browning` | Pistola | 0 | 0 CR | 24 | 360 | 13 | 25 m | 2.2° | 2.6° |
| Pistola M1911 | `m1911` | Pistola | 1 | 450 CR | 32 | 330 | 8 | 30 m | 2.0° | 3.2° |
| Pistola Desert Eagle | `deagle` | Pistola | 2 | 1.200 CR | 52 | 200 | 7 | 40 m | 2.4° | 5.5° |
| Subfusil MP5 | `mp5` | Subfusil | 1 | 1.400 CR | 21 | 800 | 30 | 40 m | 2.4° | 1.0° |
| Subfusil MP7 | `mp7` | Subfusil | 2 | 1.900 CR | 22 | 950 | 40 | 45 m | 2.2° | 0.9° |
| Subfusil P90 | `p90` | Subfusil | 2 | 2.100 CR | 20 | 900 | 50 | 45 m | 2.3° | 0.8° |
| Subfusil Vector | `vector` | Subfusil | 3 | 2.500 CR | 23 | 1200 | 25 | 35 m | 2.6° | 0.6° |
| Escopeta Remington 31 | `remington` | Escopeta | 2 | 1.600 CR | 14×8 | 70 | 6 | 15 m | 6.5° | 6.0° |
| Carabina CQB M4 | `cqbm4` | Fusil | 2 | 2.600 CR | 28 | 800 | 30 | 60 m | 2.0° | 1.3° |
| Fusil de asalto AM4 (M4A1) | `am4` | Fusil | 3 | 3.000 CR | 30 | 650 | 30 | 80 m | 1.6° | 1.4° |
| Fusil G36C | `g36c` | Fusil | 3 | 3.200 CR | 30 | 750 | 30 | 75 m | 1.5° | 1.2° |
| Fusil M16 | `m16` | Fusil | 3 | 3.400 CR | 34 | 600 | 30 | 100 m | 1.0° | 1.5° |
| Fusil M4 con supresor | `m4supp` | Fusil | 3 | 3.600 CR | 29 | 650 | 30 | 80 m | 1.5° | 1.2° |
| Fusil AK-47 | `ak47` | Fusil | 3 | 3.800 CR | 38 | 600 | 30 | 85 m | 2.0° | 2.2° |
| Fusil Steyr AUG | `aug` | Fusil | 4 | 4.200 CR | 33 | 680 | 30 | 95 m | 1.1° | 1.2° |
| Fusil SCAR-H | `scarh` | Fusil | 4 | 5.200 CR | 45 | 600 | 20 | 110 m | 1.3° | 2.6° |
| Tirador M4 (DMR) | `m4dmr` | Tirador | 4 | 6.000 CR | 58 | 240 | 20 | 150 m | 0.4° | 3.5° |
| Fusil de precisión AWM (sin mira) | `awm` | Francotirador | 5 | 8.000 CR | 95 | 45 | 5 | 250 m | 0.25° | 7.0° |

* **Precio 0** = equipo inicial gratuito (pistola básica). El fusil no es gratuito.
* **Alcance**: más allá del alcance efectivo el daño baja de a poco hasta la mitad a 2× el alcance (`Ballistics`).
* **Nivel** (0 básica … 5 élite): orden de poder para botín y tienda.
* **Supresor** (M4 con supresor): disparo 14 dB más bajo y radio de ruido 14 m (la IA lo oye menos).

## Mejoras (armas guardadas)

5 niveles por atributo; costo por nivel = 12 %, 20 %, 32 %, 50 %, 75 % del precio del arma.

| Mejora | Qué cambia | Por nivel |
|---|---|---|
| Precisión | `spread` | ×0.92 |
| Estabilidad (retroceso) | `recoil` | ×0.9 |
| Capacidad del cargador | `mag` | ×1.1 |
| Velocidad de recarga | `reload` | ×0.93 |
| Alcance | `range` | ×1.08 |

Ejemplo: M4 nivel 5 de precisión = dispersión × 0,92⁵ ≈ 0,66 (un tercio más precisa); costo total ≈ 1,89 × el precio.
Pendiente (fase 4): pantalla de tienda / mejoras y su validación en el servidor.
