# Armas de Extracción Vertical

**61 armas** clasificadas por tipo y ordenadas por poder (precio). Las 21 primeras son las subidas del usuario; las 40 `Quaternius` son del pack *Ultimate Gun Pack* (modelos de bajo poligonaje: 700-1 900 triángulos). Calibre, cadencia, cargador y alcance simulan los reales (ver `tools/weapons/gen_roster.py`). **DPS** = daño × perdigones × disparos/min ÷ 60; **TTK** = tiros para 100 de vida (sin zonas del cuerpo; la anatomía puede matar antes).

### Pistolas y revólveres (15)

| Arma | id | Calibre | Nivel | Precio | Daño | Disparos/min | DPS | TTK | Cargador | Recarga | Alcance | Dispersión | Retroceso |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Pistola M1911 | `m1911` | .45 ACP | 0 | 0 CR | 32 | 330 | 176 | 4 | 8 | 1.7 s | 30 m | 2.00° | 3.2° |
| Revólver .38 Special (2") | `revolver_4` | .38 Special | 0 | 250 CR | 22 | 150 | 55 | 5 | 5 | 3.0 s | 20 m | 3.40° | 2.8° |
| Pistola subcompacta .380 | `pistol_5` | .380 ACP | 1 | 350 CR | 19 | 320 | 101 | 6 | 10 | 1.6 s | 18 m | 3.20° | 2.2° |
| Revólver .357 Magnum (4") | `revolver_1` | .357 Magnum | 1 | 450 CR | 38 | 150 | 95 | 3 | 6 | 3.2 s | 35 m | 2.40° | 4.4° |
| Pistola M1911 B | `m1911_1` | .45 ACP | 1 | 500 CR | 31 | 340 | 175 | 4 | 8 | 1.7 s | 30 m | 2.00° | 3.2° |
| Pistola compacta 9 mm | `pistol_1` | 9×19 mm | 1 | 500 CR | 24 | 330 | 132 | 5 | 15 | 1.6 s | 25 m | 2.60° | 2.4° |
| Pistola de servicio 9 mm | `pistol_2` | 9×19 mm | 1 | 500 CR | 24 | 340 | 136 | 5 | 17 | 1.7 s | 28 m | 2.20° | 2.5° |
| Revólver .357 Magnum (6") | `revolver_2` | .357 Magnum | 1 | 500 CR | 38 | 140 | 88 | 3 | 6 | 3.2 s | 48 m | 1.80° | 4.2° |
| Pistola .40 S&W | `pistol_3` | .40 S&W | 1 | 550 CR | 27 | 320 | 144 | 4 | 14 | 1.7 s | 30 m | 2.30° | 2.9° |
| Revólver .44 Magnum | `revolver_3` | .44 Magnum | 1 | 550 CR | 50 | 110 | 91 | 2 | 6 | 3.4 s | 50 m | 2.00° | 6.2° |
| Pistola .45 ACP de doble pila | `pistol_4` | .45 ACP | 1 | 600 CR | 31 | 300 | 155 | 4 | 13 | 1.8 s | 30 m | 2.10° | 3.1° |
| Revólver .454 Casull | `revolver_5` | .454 Casull | 1 | 600 CR | 60 | 90 | 90 | 2 | 5 | 3.6 s | 55 m | 2.20° | 8.0° |
| Pistola de cañón largo .357 | `pistol_6` | .357 Magnum | 1 | 700 CR | 38 | 240 | 152 | 3 | 9 | 2.0 s | 50 m | 1.40° | 4.4° |
| Pistola M1911 Táctica | `m1911t` | .45 ACP | 1 | 750 CR | 32 | 330 | 176 | 4 | 8 | 1.7 s | 30 m | 1.60° | 2.8° |
| Pistola Desert Eagle | `deagle` | .50 AE | 2 | 1.200 CR | 52 | 200 | 173 | 2 | 7 | 2.0 s | 40 m | 2.40° | 5.5° |

### Subfusiles (10)

| Arma | id | Calibre | Nivel | Precio | Daño | Disparos/min | DPS | TTK | Cargador | Recarga | Alcance | Dispersión | Retroceso |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Subfusil MP5 A | `mp5_1` | 9×19 mm | 1 | 1.400 CR | 21 | 800 | 280 | 5 | 30 | 2.0 s | 40 m | 2.40° | 1.0° |
| Subfusil MP5 B | `mp5_2` | 9×19 mm | 1 | 1.550 CR | 21 | 780 | 273 | 5 | 30 | 2.0 s | 40 m | 2.40° | 1.0° |
| Subfusil 9 mm | `smg_3` | 9×19 mm | 2 | 1.600 CR | 24 | 650 | 260 | 5 | 30 | 2.1 s | 42 m | 2.00° | 1.0° |
| Subfusil compacto 9 mm | `smg_1` | 9×19 mm | 2 | 1.800 CR | 24 | 800 | 320 | 5 | 30 | 2.0 s | 32 m | 2.60° | 1.2° |
| Subfusil MP7 | `mp7` | 4,6×30 mm | 2 | 1.900 CR | 22 | 950 | 348 | 5 | 40 | 2.0 s | 45 m | 2.20° | 0.9° |
| Subfusil largo 5,7×28 (PDW) | `smg_5` | 5,7×28 mm | 2 | 1.900 CR | 20 | 900 | 300 | 5 | 50 | 2.4 s | 50 m | 1.80° | 0.8° |
| Subfusil P90 | `p90` | 5,7×28 mm | 2 | 2.100 CR | 20 | 900 | 300 | 5 | 50 | 2.6 s | 45 m | 2.30° | 0.8° |
| Pistola ametralladora 9 mm | `smg_4` | 9×19 mm | 2 | 2.100 CR | 24 | 1000 | 400 | 5 | 32 | 2.0 s | 25 m | 3.20° | 1.6° |
| Subfusil .45 ACP | `smg_2` | .45 ACP | 2 | 2.150 CR | 31 | 700 | 361 | 4 | 25 | 2.2 s | 38 m | 2.20° | 1.4° |
| Subfusil Vector | `vector` | .45 ACP | 3 | 2.500 CR | 23 | 1200 | 460 | 5 | 25 | 1.9 s | 35 m | 2.60° | 0.6° |

### Fusiles de asalto, carabinas y bullpup (23)

| Arma | id | Calibre | Nivel | Precio | Daño | Disparos/min | DPS | TTK | Cargador | Recarga | Alcance | Dispersión | Retroceso |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Subcarabina 5,56 | `ar2_4` | 5,56×45 mm | 2 | 2.150 CR | 30 | 800 | 400 | 4 | 30 | 2.1 s | 55 m | 2.40° | 1.7° |
| Carabina compacta 5,56 | `ar_1` | 5,56×45 mm | 3 | 2.200 CR | 30 | 850 | 425 | 4 | 30 | 2.1 s | 50 m | 2.60° | 1.8° |
| Carabina 5,56 | `ar_3` | 5,56×45 mm | 3 | 2.200 CR | 30 | 800 | 400 | 4 | 30 | 2.2 s | 60 m | 2.00° | 1.4° |
| Fusil de asalto 5,56 | `ar_2` | 5,56×45 mm | 3 | 2.350 CR | 30 | 700 | 350 | 4 | 30 | 2.3 s | 90 m | 1.20° | 1.3° |
| Fusil 5,56 ligero | `ar2_2` | 5,56×45 mm | 3 | 2.400 CR | 30 | 750 | 375 | 4 | 30 | 2.3 s | 85 m | 1.40° | 1.3° |
| Carabina 7,62×39 | `ar2_3` | 7,62×39 mm | 3 | 2.400 CR | 38 | 650 | 411 | 3 | 30 | 2.3 s | 65 m | 2.20° | 2.2° |
| Bullpup largo 5,56 | `bullpup_1` | 5,56×45 mm | 3 | 2.400 CR | 30 | 700 | 350 | 4 | 30 | 2.4 s | 95 m | 1.10° | 1.2° |
| Bullpup compacto 5,56 | `bullpup_2` | 5,56×45 mm | 3 | 2.450 CR | 30 | 900 | 450 | 4 | 30 | 2.2 s | 60 m | 2.20° | 1.5° |
| Fusil de asalto 7,62×39 | `ar_5` | 7,62×39 mm | 3 | 2.500 CR | 38 | 600 | 380 | 3 | 30 | 2.4 s | 85 m | 1.90° | 2.3° |
| Bullpup 5,56 | `bullpup_3` | 5,56×45 mm | 3 | 2.500 CR | 30 | 800 | 400 | 4 | 30 | 2.3 s | 80 m | 1.50° | 1.4° |
| Carabina CQB M4 | `cqbm4` | 5,56×45 mm | 2 | 2.600 CR | 28 | 800 | 373 | 4 | 30 | 2.1 s | 60 m | 2.00° | 1.3° |
| Fusil M4A1 | `m4a1` | 5,56×45 mm | 3 | 3.000 CR | 30 | 650 | 325 | 4 | 30 | 2.3 s | 80 m | 1.60° | 1.4° |
| Fusil M4A1 B | `m4a1_1` | 5,56×45 mm | 3 | 3.100 CR | 31 | 650 | 335 | 4 | 30 | 2.3 s | 80 m | 1.60° | 1.4° |
| Fusil G36C | `g36c` | 5,56×45 mm | 3 | 3.200 CR | 30 | 750 | 375 | 4 | 30 | 2.3 s | 75 m | 1.50° | 1.2° |
| Fusil de combate pesado 7,62×51 | `ar_4` | 7,62×51 mm | 3 | 3.300 CR | 48 | 520 | 416 | 3 | 20 | 2.7 s | 120 m | 1.20° | 3.2° |
| Fusil M16 B | `m16_1` | 5,56×45 mm | 3 | 3.300 CR | 33 | 620 | 341 | 4 | 30 | 2.4 s | 100 m | 1.00° | 1.5° |
| Fusil M16 | `m16` | 5,56×45 mm | 3 | 3.400 CR | 34 | 600 | 340 | 3 | 30 | 2.4 s | 100 m | 1.00° | 1.5° |
| Fusil de combate 7,62×51 | `ar2_1` | 7,62×51 mm | 4 | 3.600 CR | 48 | 600 | 480 | 3 | 20 | 2.6 s | 110 m | 1.40° | 2.8° |
| Fusil M4 con supresor | `m4supp` | 5,56×45 mm | 3 | 3.600 CR | 29 | 650 | 314 | 4 | 30 | 2.3 s | 80 m | 1.50° | 1.2° |
| Fusil AK-47 | `ak47` | 7,62×39 mm | 3 | 3.800 CR | 38 | 600 | 380 | 3 | 30 | 2.5 s | 85 m | 2.00° | 2.2° |
| Fusil Steyr AUG | `aug` | 5,56×45 mm | 4 | 4.200 CR | 33 | 680 | 374 | 4 | 30 | 2.6 s | 95 m | 1.10° | 1.2° |
| Fusil SCAR | `scar` | 5,56×45 mm | 3 | 4.400 CR | 40 | 650 | 433 | 3 | 30 | 2.6 s | 110 m | 1.30° | 2.6° |
| Fusil SCAR-H | `scarh` | 7,62×51 mm | 4 | 5.200 CR | 45 | 600 | 450 | 3 | 20 | 2.6 s | 110 m | 1.30° | 2.6° |

### Escopetas (6)

| Arma | id | Calibre | Nivel | Precio | Daño | Disparos/min | DPS | TTK | Cargador | Recarga | Alcance | Dispersión | Retroceso |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Escopeta de corredera culata corta | `shotgun_short` | 12 ga postas | 1 | 500 CR | 14×8 | 70 | 130 | 1 | 5 | 3.0 s | 12 m | 7.50° | 6.5° |
| Escopeta de corredera 12 | `shotgun_1` | 12 ga postas | 1 | 550 CR | 14×8 | 70 | 130 | 1 | 6 | 3.0 s | 15 m | 6.50° | 6.0° |
| Escopeta táctica de 8 cartuchos | `shotgun_2` | 12 ga postas | 1 | 550 CR | 14×8 | 75 | 140 | 1 | 8 | 3.4 s | 16 m | 6.00° | 5.6° |
| Escopeta de caza | `shotgun_4` | 12 ga postas | 1 | 600 CR | 14×9 | 65 | 136 | 1 | 5 | 3.0 s | 25 m | 4.20° | 6.2° |
| Escopeta recortada de 2 cañones | `shotgun_sawed` | 12 ga postas | 2 | 1.000 CR | 14×12 | 120 | 336 | 1 | 2 | 2.4 s | 8 m | 9.00° | 9.0° |
| Escopeta semiautomática | `shotgun_3` | 12 ga postas | 2 | 1.100 CR | 14×8 | 200 | 373 | 1 | 6 | 3.2 s | 15 m | 6.80° | 6.4° |

### Tiradores (3)

| Arma | id | Calibre | Nivel | Precio | Daño | Disparos/min | DPS | TTK | Cargador | Recarga | Alcance | Dispersión | Retroceso |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Tirador semiautomático 7,62×51 | `sniper_3` | 7,62×51 mm | 2 | 1.900 CR | 48 | 180 | 144 | 3 | 10 | 2.8 s | 170 m | 0.60° | 3.2° |
| Fusil de precisión semiautomático .308 | `sniper_6` | .308 Win | 3 | 2.400 CR | 62 | 140 | 144 | 2 | 10 | 2.8 s | 220 m | 0.50° | 3.4° |
| Tirador M4 (DMR) | `m4dmr` | 7,62×51 mm | 4 | 6.000 CR | 58 | 240 | 232 | 2 | 20 | 2.8 s | 150 m | 0.40° | 3.5° |

### Francotiradores (4)

| Arma | id | Calibre | Nivel | Precio | Daño | Disparos/min | DPS | TTK | Cargador | Recarga | Alcance | Dispersión | Retroceso |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Fusil de cerrojo .308 | `sniper_1` | .308 Win | 2 | 1.400 CR | 62 | 40 | 41 | 2 | 5 | 3.3 s | 230 m | 0.30° | 5.5° |
| Fusil de cerrojo .300 Win Mag | `sniper_2` | .300 Win Mag | 2 | 1.850 CR | 72 | 38 | 45 | 2 | 5 | 3.4 s | 280 m | 0.28° | 6.2° |
| Fusil de cerrojo .338 Lapua | `sniper_4` | .338 Lapua | 3 | 2.550 CR | 90 | 35 | 52 | 2 | 5 | 3.6 s | 330 m | 0.25° | 7.0° |
| Fusil antimaterial .50 BMG | `sniper_5` | .50 BMG | 4 | 4.900 CR | 130 | 50 | 108 | 1 | 5 | 4.2 s | 400 m | 0.30° | 9.5° |

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
