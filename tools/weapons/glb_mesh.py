"""Lectura mínima de GLB (posiciones e índices, con las transformaciones de los nodos) para analizar armas."""
import json, struct
import numpy as np

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def _acc(j, bin_, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    n = a["count"] * NC[a["type"]]
    dt = CT[a["componentType"]]
    stride = bv.get("byteStride")
    comp = NC[a["type"]]
    if stride and stride != comp * np.dtype(dt).itemsize:
        raw = np.frombuffer(bin_, dtype=np.uint8, count=stride * a["count"], offset=off).reshape(a["count"], stride)
        arr = raw[:, :comp * np.dtype(dt).itemsize].copy().view(dt).reshape(a["count"], comp)
        return arr
    arr = np.frombuffer(bin_, dtype=dt, count=n, offset=off)
    return arr.reshape(a["count"], comp) if comp > 1 else arr


def _mat(n):
    if "matrix" in n:
        return np.array(n["matrix"], dtype=float).reshape(4, 4).T
    t = np.array(n.get("translation", [0, 0, 0]), float)
    q = n.get("rotation", [0, 0, 0, 1])
    s = np.array(n.get("scale", [1, 1, 1]), float)
    x, y, z, w = q
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m = np.eye(4)
    m[:3, :3] = r * s
    m[:3, 3] = t
    return m


def load(path):
    b = open(path, "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    o = 20 + jl
    bl = struct.unpack("<I", b[o:o + 4])[0]
    bin_ = b[o + 8:o + 8 + bl]
    verts, tris = [], []
    base = 0
    names = []

    def walk(ni, parent):
        nonlocal base
        n = j["nodes"][ni]
        m = parent @ _mat(n)
        names.append((n.get("name", ""), m))
        if "mesh" in n:
            for p in j["meshes"][n["mesh"]]["primitives"]:
                pos = _acc(j, bin_, p["attributes"]["POSITION"]).astype(float)
                pw = (m[:3, :3] @ pos.T).T + m[:3, 3]
                idx = _acc(j, bin_, p["indices"]).astype(int).reshape(-1, 3) if "indices" in p else np.arange(len(pos)).reshape(-1, 3)
                verts.append(pw)
                tris.append(idx + base)
                base += len(pw)
        for c in n.get("children", []):
            walk(c, m)
    for r in j["scenes"][j.get("scene", 0)]["nodes"]:
        walk(r, np.eye(4))
    return np.vstack(verts), np.vstack(tris), names
