# Torre Alfa — esquema de rutas

Generado desde `MapGraph` (`systems/map/map_graph.gd`) con los mismos datos que arma el mapa (`systems/map/torre_alfa.gd`).
La prueba automática **mapa** recorre este grafo desde la entrada y falla si queda algún sector inaccesible, si alguna
extracción no se alcanza o si la tarjeta del laboratorio no se puede conseguir. Resultado actual: **26 sectores, 0
inaccesibles, las dos extracciones alcanzables, tarjeta alcanzable.**

```
 y(m)   0         10        20        30        40        50        60   x(m)
 22,5  ═══════════════════════ AZOTEA ═════════════════ [HELI] ═══╦═══   ← extracción superior
                                                                   ║L
 18,0  │ lab bancos │ quirófano  │  ▓ASC  L│🔒 laboratorio  │ armario  L║   P4 Laboratorio (vapor 24-27,5)
       │            │            │  ▓      │  (tarjeta)     │          │
 13,5  │ ═PLAT═MÓVIL═ │  taller  L│  ▓ASC   │ hueco cráter   │          │   P3 Almacén / Taller
       │  (hueco 6-12)│         ║│  ▓       ╲▲▲ pilares       │          │
  9,0  │L entrepiso   │ tarima   ║│  ▓ASC    │╲ CRÁTER ╱      │         L║   P2 Servicios / Cráter
       │║(+2,2)       │           │  ▓        │ ▲▲▲▲▲▲        │          ║
  4,5  │ L  │  ╱escalera  │ ═conducto═ │ ▓ASC  L│ fondo cráter │ plat ⇢ plat│   P1 Depósitos (salto 52,6→54,6)
       │ ║  │ ╱      │         │ ▓      ║│               │          │
  0,0  │ ▶  ║╱ montac.│ contenedor │ ▓ASC  ║│ tarima  │  EXTRACCIÓN P0 │   P0 Acceso / Extracción
       inicio                         (cajas: ruta secreta x=34,5)
 L = escalera de mano · ASC = ascensor (paradas P0..P4) · ║ = trampilla · 🔒 = puerta con tarjeta
```

## Rutas para subir sin recorrer todo el piso

| Desde → hasta | Cómo |
|---|---|
| P0 → P1 | escalera de mano (x = 8), escalera inclinada (12 → 18,6), ascensor, escalera secreta detrás de la pila de cajas (x = 34,5) |
| P1 → P2 | escalera de mano (x = 59), ascensor, **cráter**: pilares de escombro (saltar / trepar) hasta el borde izquierdo del P2 |
| P1 → P3 | por los pilares altos del cráter hasta el borde del P3 (x = 46) |
| P2 → P3 | escalera de mano (x = 21), ascensor |
| P3 → P4 | escalera de mano (x = 30,5), ascensor |
| P4 → azotea | escalera de mano (x = 58), del otro lado de la puerta del laboratorio: **requiere la tarjeta** (está en la caja del entrepiso del P2) |
| bajar | cualquier hueco (trampillas, cráter, hueco del ascensor): caída por gravedad con daño desde 3,6 m |

## Conexiones (todas)

```

B0 · sector 1 ↔ B0 · sector 2  [door]
B0 · sector 2 ↔ B0 · sector 3  [door]
B0 · sector 3 ↔ B0 · sector 4  [door]
B0 · sector 4 ↔ B0 · sector 5  [door]
B1 · sector 1 ↔ B1 · sector 2  [door]
B1 · sector 2 ↔ B1 · sector 3  [duct]
B1 · sector 3 ↔ B1 · sector 4  [door]
B1 · sector 4 ↔ B1 · sector 5  [door]
B1 · sector 1 → B0 · sector 1  [caída]
B1 · sector 2 → B0 · sector 2  [caída]
B1 · sector 3 → B0 · sector 3  [caída]
B1 · sector 3 → B0 · sector 3  [caída]
B2 · sector 1 ↔ B2 · sector 2  [door]
B2 · sector 2 ↔ B2 · sector 3  [door]
B2 · sector 3 ↔ B2 · sector 4  [door]
B2 · sector 4 ↔ B2 · sector 5  [door]
B2 · sector 3 → B1 · sector 3  [caída]
B2 · sector 4 → B1 · sector 4  [caída]
B2 · sector 5 → B1 · sector 5  [caída]
B3 · sector 1 ↔ B3 · sector 2  [door]
B3 · sector 2 ↔ B3 · sector 3  [door]
B3 · sector 3 ↔ B3 · sector 4  [door]
B3 · sector 4 ↔ B3 · sector 5  [door]
B3 · sector 1 → B2 · sector 1  [caída]
B3 · sector 2 → B2 · sector 2  [caída]
B3 · sector 3 → B2 · sector 3  [caída]
B3 · sector 4 → B2 · sector 4  [caída]
B4 · sector 1 ↔ B4 · sector 2  [door]
B4 · sector 2 ↔ B4 · sector 3  [door]
B4 · sector 3 ↔ B4 · sector 4  [locked] (requiere keycard_lab)
B4 · sector 4 ↔ B4 · sector 5  [door]
B4 · sector 3 → B3 · sector 3  [caída]
B4 · sector 3 → B3 · sector 3  [caída]
B0 · sector 1 ↔ B1 · sector 1  [escalera de mano]
B1 · sector 5 ↔ B2 · sector 5  [escalera de mano]
B2 · sector 2 ↔ B3 · sector 2  [escalera de mano]
B3 · sector 3 ↔ B4 · sector 3  [escalera de mano]
B4 · sector 5 ↔ Azotea  [escalera de mano]
B0 · sector 3 ↔ B1 · sector 3  [escalera de mano]
B0 · sector 2 ↔ B1 · sector 2  [escalera]
B0 · sector 3 ↔ B1 · sector 3  [ascensor]
B1 · sector 3 ↔ B2 · sector 3  [ascensor]
B2 · sector 3 ↔ B3 · sector 3  [ascensor]
B3 · sector 3 ↔ B4 · sector 3  [ascensor]
B1 · sector 4 ↔ B2 · sector 4  [cráter (trepar)]
B1 · sector 4 ↔ B3 · sector 4  [cráter (pilares)]
```
