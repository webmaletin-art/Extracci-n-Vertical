"""Empuñaduras marcadas a mano mirando la silueta de perfil de cada arma (tools/weapons/fix_grips.py --sheet las dibuja).
Coordenadas de 0 a 10 dentro del recuadro del arma: x desde la CULATA (0) hasta la BOCA (10); y desde ARRIBA (0) hasta ABAJO (10).
grip = palma de la mano derecha sobre la empuñadura de pistola (≈ un tercio de su alto, nunca el cargador);
support = mano izquierda: "rail" debajo del guardamanos / corredera, "vgrip" empuñadura vertical delantera, "mag" cargador.
Las pistolas y revólveres se calculan solos (la empuñadura es la culata del arma)."""
M = {
    "mp7": ((3.9, 5.2), (6.5, 3.6), "rail"), "p90": ((3.8, 6.6), (6.8, 6.4), "vgrip"), "vector": ((3.6, 4.5), (7.2, 2.8), "rail"),
    "cqbm4": ((3.9, 5.0), (7.5, 4.9), "vgrip"), "g36c": ((3.7, 5.6), (7.0, 3.3), "rail"), "m16": ((3.1, 5.0), (6.3, 3.5), "rail"),
    "m4supp": ((2.4, 4.9), (5.0, 3.3), "rail"), "ak47": ((3.5, 5.0), (6.4, 3.1), "rail"), "aug": ((4.7, 5.0), (7.3, 4.8), "vgrip"),
    "scarh": ((3.4, 5.6), (6.4, 4.0), "rail"), "m4dmr": ((3.3, 5.2), (6.0, 4.0), "rail"), "m16_1": ((3.1, 5.5), (5.5, 4.5), "rail"),
    "mp5_1": ((2.6, 5.0), (6.2, 3.6), "rail"), "mp5_2": ((2.7, 5.1), (6.3, 3.6), "rail"), "scar": ((3.1, 5.5), (5.8, 3.6), "rail"),
    "m4a1": ((3.1, 5.0), (7.0, 4.9), "vgrip"), "m4a1_1": ((3.3, 5.1), (6.2, 4.0), "rail"),
    "smg_4": ((1.7, 4.9), (6.8, 2.6), "rail"), "smg_1": ((2.2, 5.1), (6.6, 3.0), "rail"), "smg_3": ((4.6, 4.9), (8.3, 4.9), "vgrip"),
    "smg_2": ((4.2, 5.0), (7.4, 3.6), "rail"), "smg_5": ((3.5, 5.0), (7.0, 3.6), "rail"), "ar_1": ((1.2, 4.9), (6.0, 3.1), "rail"),
    "ar2_4": ((3.4, 5.1), (7.4, 3.2), "rail"), "ar_3": ((0.9, 4.6), (6.2, 3.0), "rail"), "ar2_3": ((0.8, 4.8), (5.0, 3.2), "rail"),
    "ar2_2": ((3.1, 5.1), (6.2, 3.3), "rail"), "ar_2": ((3.1, 4.6), (6.8, 2.6), "rail"), "ar_5": ((3.2, 4.7), (6.8, 2.6), "rail"),
    "ar2_1": ((2.9, 5.1), (6.0, 3.0), "rail"), "ar_4": ((3.3, 4.5), (6.8, 2.6), "rail"), "bullpup_2": ((2.9, 5.5), (8.1, 5.2), "vgrip"),
    "bullpup_3": ((3.7, 5.6), (7.0, 4.6), "rail"), "bullpup_1": ((4.7, 5.8), (8.5, 5.0), "vgrip"),
    "shotgun_sawed": ((1.9, 4.8), (5.0, 3.7), "rail"), "shotgun_short": ((2.0, 4.0), (7.4, 4.9), "rail"),
    "shotgun_1": ((3.0, 4.8), (6.8, 4.8), "rail"), "shotgun_2": ((2.8, 4.6), (7.0, 4.7), "rail"), "shotgun_3": ((2.8, 4.6), (6.8, 5.2), "rail"),
    "shotgun_4": ((2.8, 4.6), (5.8, 4.7), "rail"), "sniper_6": ((2.9, 5.3), (5.4, 4.9), "rail"), "sniper_3": ((2.7, 6.0), (5.6, 5.8), "rail"),
    "sniper_1": ((3.1, 5.3), (5.5, 4.6), "rail"), "sniper_2": ((2.8, 5.2), (3.9, 4.6), "rail"), "sniper_4": ((2.4, 5.6), (4.6, 4.6), "rail"),
    "sniper_5": ((2.3, 5.2), (4.8, 3.9), "rail"), "flat_smg_c": ((5.7, 4.6), (8.0, 2.8), "rail"), "flat_smg_f": ((3.8, 4.6), (7.4, 3.0), "rail"),
    "flat_rifle_a": ((3.6, 4.8), (7.0, 3.4), "rail"), "flat_rifle_b": ((3.0, 4.9), (6.8, 3.0), "rail"),
    "flat_shotgun_p": ((3.6, 4.6), (6.2, 3.9), "rail"), "flat_shotgun_a": ((3.4, 4.7), (7.2, 2.8), "rail"),
    "flat_sniper_r": ((3.2, 5.6), (6.6, 4.6), "rail"), "flat_sniper_m": ((3.9, 5.6), (6.2, 4.4), "rail"),
}
