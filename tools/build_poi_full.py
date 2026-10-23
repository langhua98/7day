#!/usr/bin/env python3
"""用七日杀建筑的完整方块数据（.tts 方块布局 + .blocks.nim 方块名表）生成楼的网格，近看有窗户、楼梯、屋檐。

输入（tools/fetch_assets.py 放好的）：
    assets/poi/<楼>.tts / .nim / .xml
    assets/blocks/blocks.xml / shapes.xml / painting.xml （游戏的方块表、形状表、刷漆表）
    assets/shapes/*.glb                             （形状模型）
    assets/blocks/ta_opaque.xml                     （贴图编号对照表）
输出：
    assets/poi/<楼>.full                            （tools/build_poi.gd 再转成 Godot 网格）

.tts 格式（第 19 版）："tts\\0"、u32 版本、u16 长宽高，然后每格一个 u32 方块值（下标 = x + y*X + z*X*Y），
每格 1 字节密度、2 字节损坏，然后是刷漆：u32 位图字节数 + 位图（哪些格刷了漆）+ 每个刷漆格一个 u64
（6 个面各 8 位刷漆编号，面的顺序：上、下、北 +z、西 -x、南 -z、东 +x）。
方块值：低 16 位是方块编号（.nim 里查名字），16~20 位是旋转（0~23，24~27 是 45 度转）。

方块数据比远景网格整体低 4 格（远景地面在 4 - YOffset），所以 y 统一加 4。

用法：python3 tools/build_poi_full.py [--only 楼名,楼名]
"""
import argparse
import collections
import json
import math
import os
import re
import struct
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets")

# 方块 6 个面（方块自己的坐标）：上、下、北、西、南、东
FACES = [(0, 1, 0), (0, -1, 0), (0, 0, 1), (-1, 0, 0), (0, 0, -1), (1, 0, 0)]
FACE_OF = {d: i for i, d in enumerate(FACES)}
# 远景网格用这张贴图代替远处看不清的贴图，反推刷漆表时不算
FAR_FILLER_TEX = 553
# 网格按多少米分块
CHUNK = 16


# —— 旋转：rot = B[k] · Ry^j（r = 4k + j），从远景网格里各种形状的朝向反推出来 ——
def _mul(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


_RY1 = ((0, 0, 1), (0, 1, 0), (-1, 0, 0))
_RY = [((1, 0, 0), (0, 1, 0), (0, 0, 1))]
for _ in range(3):
    _RY.append(_mul(_RY[-1], _RY1))
_B = [((1, 0, 0), (0, 1, 0), (0, 0, 1)), ((-1, 0, 0), (0, -1, 0), (0, 0, 1)), ((-1, 0, 0), (0, 0, 1), (0, 1, 0)),
      ((0, -1, 0), (1, 0, 0), (0, 0, 1)), ((1, 0, 0), (0, 0, 1), (0, -1, 0)), ((0, 1, 0), (-1, 0, 0), (0, 0, 1))]
ROTATIONS = [_mul(_B[k], _RY[j]) for k in range(6) for j in range(4)] + _RY   # 24~27（45 度）先按 0~3 算


def rotate(m, p):
    """绕方块中心转（p 是 0..1 的方块内坐标）"""
    q = (p[0] - 0.5, p[1] - 0.5, p[2] - 0.5)
    return tuple(sum(m[i][j] * q[j] for j in range(3)) + 0.5 for i in range(3))


def rotate_dir(m, d):
    return tuple(sum(m[i][j] * d[j] for j in range(3)) for i in range(3))


# —— 读文件 ——

def read_nim(path):
    d = open(path, "rb").read()
    _, n = struct.unpack_from("<II", d, 0)
    o, out = 8, {}
    for _ in range(n):
        i = struct.unpack_from("<I", d, o)[0]
        ln = d[o + 4]
        out[i] = d[o + 5:o + 5 + ln].decode("utf-8", "replace")
        o += 5 + ln
    return out


def read_tts(path):
    d = open(path, "rb").read()
    if d[:3] != b"tts":
        raise ValueError("不是 tts")
    X, Y, Z = struct.unpack_from("<HHH", d, 8)
    n = X * Y * Z
    blocks = struct.unpack_from("<%dI" % n, d, 14)
    paints = {}
    o = 14 + 7 * n
    if o + 4 <= len(d):
        nb = struct.unpack_from("<I", d, o)[0]
        if nb == (n + 7) // 8:
            bm = d[o + 4:o + 4 + nb]
            q = o + 4 + nb
            k = 0
            for i in range(n):
                if bm[i >> 3] >> (i & 7) & 1:
                    paints[i] = struct.unpack_from("<Q", d, q + 8 * k)[0]
                    k += 1
    return (X, Y, Z), blocks, paints


# —— 方块表 ——

class Blocks:
    def __init__(self, path):
        self.b = {}
        for bl in ET.parse(path).getroot().iter("block"):
            props = {pr.get("name"): pr.get("value") for pr in bl.findall("property") if pr.get("name")}
            self.b[bl.get("name")] = props

    def get(self, name, key, depth=0):
        p = self.b.get(name)
        if p is None or depth > 12:
            return None
        if key in p:
            return p[key]
        ext = p.get("Extends")
        return self.get(ext.split(",")[0].strip(), key, depth + 1) if ext else None

    def textures(self, name):
        """方块默认贴图（6 个面）"""
        t = self.get(name, "Texture")
        if not t:
            return [-1] * 6
        try:
            ids = [int(s) for s in t.split(",")]
        except ValueError:
            return [-1] * 6
        return ids if len(ids) == 6 else [ids[0]] * 6


def base_name(block_name):
    return block_name.split(":")[0]


def shape_of(block_name):
    return block_name.split(":")[1] if ":" in block_name else None


# —— 形状模型（assets/shapes/*.glb，游戏 shapes_assets_all 按模型导出的，只有几何）——
# glb 里根节点下是 LOD0，再下面每个子网格是一组面，名字表示：
#   第一个字母 = 用方块哪个面的贴图/刷漆（T 上 B 下 N 北 W 西 S 南 E 东；M_x = 中间的面，用 ShapeAltTexture 第 7 项）
#   后缀 _F = 正好盖满方块的一个面，_P = 贴在方块边上的一部分：旁边是整块时看不见，可以不画
SLOT = {"T": 0, "B": 1, "N": 2, "W": 3, "S": 4, "E": 5, "M": 6}


def _qmat(q):
    x, y, z, w = q
    return [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]


def _trs(n):
    if "matrix" in n:
        m = n["matrix"]
        return [[m[j * 4 + i] for j in range(4)] for i in range(4)]
    t, r, sc = n.get("translation", [0, 0, 0]), n.get("rotation", [0, 0, 0, 1]), n.get("scale", [1, 1, 1])
    R = _qmat(r)
    return [[R[i][j] * sc[j] for j in range(3)] + [t[i]] for i in range(3)] + [[0, 0, 0, 1]]


def _mm(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def load_glb(path):
    """→ [(子网格名, [三角形 (p0, p1, p2)])]，坐标换回游戏的方块坐标（0..1，Unity 左手系）"""
    d = open(path, "rb").read()
    jl = struct.unpack_from("<I", d, 12)[0]
    j = json.loads(d[20:20 + jl])
    o = 20 + jl
    bl = struct.unpack_from("<I", d, o)[0]
    buf = d[o + 8:o + 8 + bl]

    def acc(i):
        a = j["accessors"][i]
        bv = j["bufferViews"][a["bufferView"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        fmt, size = {5126: ("f", 4), 5123: ("H", 2), 5125: ("I", 4), 5121: ("B", 1)}[a["componentType"]]
        nc = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        stride = bv.get("byteStride", size * nc)
        return [struct.unpack_from("<%d%s" % (nc, fmt), buf, off + k * stride) for k in range(a["count"])]

    out = []

    def walk(ni, M, in_lod):
        n = j["nodes"][ni]
        M = _mm(M, _trs(n))
        name = n.get("name", "")
        if name.startswith("LOD") and name != "LOD0":
            return
        if "mesh" in n and in_lod:
            tris = []
            for prim in j["meshes"][n["mesh"]]["primitives"]:
                P = []
                for v in acc(prim["attributes"]["POSITION"]):
                    g = [sum(M[i][k] * v[k] for k in range(3)) + M[i][3] for i in range(3)]
                    P.append((1.0 - g[0], g[1], g[2] + 1.0))   # glTF 右手系 → 游戏坐标
                idx = [t[0] for t in acc(prim["indices"])] if "indices" in prim else list(range(len(P)))
                for t in range(0, len(idx) - 2, 3):
                    tris.append((P[idx[t]], P[idx[t + 1]], P[idx[t + 2]]))
            out.append((name, tris))
        for c in n.get("children", []):
            walk(c, M, in_lod or name == "LOD0")

    I = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
    for r in j["scenes"][j.get("scene", 0)]["nodes"]:
        walk(r, I, False)
    return out


def parse_group(name):
    """子网格名 → (面槽位 0..6, 能不能被挡住不画)"""
    nm = name.split(".")[0].strip()
    parts = nm.split("_")
    if parts[0] == "M":
        return 6, False, True
    slot = SLOT.get(parts[0][:1])
    if slot is None:
        return None, False, False
    suffix = parts[1] if len(parts) > 1 else ""
    return slot, suffix in ("F", "P"), False


class Shapes:
    """形状名 / 模型路径 → 几何；按 (模型, 旋转) 缓存转好的三角形"""

    def __init__(self, shapes_xml, glb_dir):
        self.defs = {}
        for sh in ET.parse(shapes_xml).getroot().iter("shape"):
            self.defs[sh.get("name")] = {pr.get("name"): pr.get("value") for pr in sh.findall("property") if pr.get("name")}
        self.files = {f[:-4].lower(): os.path.join(glb_dir, f) for f in os.listdir(glb_dir) if f.endswith(".glb")}
        self.geo, self.rot_cache = {}, {}

    def model_geo(self, model):
        """model 是 "@:Shapes/cube_half.fbx" 这种路径"""
        key = os.path.splitext(os.path.basename(model or ""))[0].lower()
        if key not in self.geo:
            g = None
            if key in self.files:
                groups = []
                for name, tris in load_glb(self.files[key]):
                    slot, cullable, middle = parse_group(name)
                    if slot is not None and tris:
                        groups.append((slot, cullable, tris))
                full = {sl for sl, c, _ in groups if c and sl < 6}
                g = {"groups": groups, "full": len(full) == 6 and all(
                    nm.split(".")[0].endswith("_F") for nm, _ in []) or self._is_cube(groups)}
            self.geo[key] = g
        return self.geo[key]

    @staticmethod
    def _is_cube(groups):
        # 六个面都是 _F 而且没有别的面：整块，能挡住旁边方块的面
        return len(groups) == 6 and all(c for _, c, _ in groups) and len({s for s, _, _ in groups}) == 6

    def rotated(self, model, r):
        key = (model, r)
        if key in self.rot_cache:
            return self.rot_cache[key]
        g = self.model_geo(model)
        res = None
        if g:
            m = ROTATIONS[r] if r < len(ROTATIONS) else ROTATIONS[0]
            res = []
            for slot, cullable, tris in g["groups"]:
                wd = rotate_dir(m, FACES[slot]) if slot < 6 else None
                rt = []
                for t in tris:
                    q = [rotate(m, p) for p in t]
                    e1 = [q[1][i] - q[0][i] for i in range(3)]
                    e2 = [q[2][i] - q[0][i] for i in range(3)]
                    n = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]]
                    ln = math.sqrt(sum(c * c for c in n))
                    if ln < 1e-9:
                        continue
                    rt.append((q, (-n[0] / ln, -n[1] / ln, -n[2] / ln)))
                # 正好盖满方块一个面的方形：最后按面合并成大块，少画很多三角形
                full_face = False
                if wd and len(rt) == 2:
                    ax = [k for k in range(3) if wd[k]][0]
                    side = 1.0 if wd[ax] > 0 else 0.0
                    pts = [p for q, _ in rt for p in q]
                    others = [k for k in range(3) if k != ax]
                    full_face = (all(abs(p[ax] - side) < 1e-3 for p in pts) and
                                 all(abs(min(p[k] for p in pts)) < 1e-3 and abs(max(p[k] for p in pts) - 1) < 1e-3
                                     for k in others))
                res.append((slot, cullable, wd, rt, full_face))
        self.rot_cache[key] = res
        return res


# —— 生成网格 ——

class MeshOut:
    def __init__(self):
        self.verts, self.normals, self.tex, self.idx = [], [], [], []

        self._lookup = {}

    def tri(self, pts, n, tex):
        # 位置、法线、贴图都一样的顶点合成一个
        nk = (round(n[0], 3), round(n[1], 3), round(n[2], 3))
        for p in pts:
            key = (round(p[0], 4), round(p[1], 4), round(p[2], 4), nk, tex)
            k = self._lookup.get(key)
            if k is None:
                k = len(self.verts)
                self._lookup[key] = k
                self.verts.append(p)
                self.normals.append(n)
                self.tex.append(tex)
            self.idx.append(k)


def load_paint_table(path):
    table, cur = {}, None
    for line in open(path, encoding="utf-8"):
        m = re.search(r'<paint id="(\d+)"', line)
        if m:
            cur = int(m.group(1))
        m = re.search(r'name="TextureId" value="(\d+)"', line)
        if m and cur is not None:
            table[cur] = int(m.group(1))
    return table


def _tex_list(value):
    """"8" 或 "8,8,606,8,8,8" → 6 个贴图编号；ShapeAltTexture "T,B,55,W,S,E,285" → 7 项（字母 = 用方块自己的）"""
    if not value:
        return None
    out = []
    for s in value.split(","):
        s = s.strip()
        out.append(int(s) if s.lstrip("-").isdigit() else s)
    return out


def build_poi(name, poi_dir, db, shapes, paint_table, uv_ids):
    size, blocks, paints = read_tts(os.path.join(poi_dir, name + ".tts"))
    names = read_nim(os.path.join(poi_dir, name + ".nim"))
    X, Y, Z = size
    xml = open(os.path.join(poi_dir, name + ".xml"), encoding="utf-8", errors="replace").read()
    m = re.search(r'name="YOffset" value="(-?\d+)"', xml)
    ground = -int(m.group(1)) if m else 0
    # 远景网格的地面总在 4 - YOffset，也就是方块数据整体抬高 4 格（四栋楼都核对过）
    ox, dy, oz = -(X // 2), 4, -(Z // 2)

    info_cache = {}

    def info(t):
        """方块编号 → dict(kind, model, tex[6], alt[7])；kind: shape / terrain / None（不画）"""
        if t in info_cache:
            return info_cache[t]
        nm = names.get(t, "air")
        res = None
        if nm != "air" and not nm.startswith("terrainFiller"):
            sh = shape_of(nm)
            if sh is not None:
                d = shapes.defs.get(sh, {})
                tex = _tex_list(db.get(base_name(nm), "Texture")) or [-1]
                res = {"kind": "shape", "model": d.get("Model"), "tex": tex,
                       "alt": _tex_list(d.get("ShapeAltTexture"))}
            else:
                shape = db.get(nm, "Shape") or ""
                model = db.get(nm, "Model") or ""
                tex = _tex_list(db.get(nm, "Texture")) or [-1]
                if shape == "Terrain":
                    res = {"kind": "terrain", "terrain": nm}
                elif model.startswith("@:Shapes/"):
                    res = {"kind": "shape", "model": model, "tex": tex, "alt": _tex_list(db.get(nm, "ShapeAltTexture"))}
                elif shape == "New" and not model:
                    res = {"kind": "shape", "model": "@:Shapes/Cube.fbx", "tex": tex, "alt": None}
            if res and res["kind"] == "shape":
                if len(res["tex"]) != 6:
                    res["tex"] = [res["tex"][0]] * 6
                g = shapes.model_geo(res["model"])
                if g is None:
                    res = None
                else:
                    res["full"] = g["full"]
        info_cache[t] = res
        return res

    def at(x, y, z):
        if 0 <= x < X and 0 <= y < Y and 0 <= z < Z:
            return blocks[x + y * X + z * X * Y]
        return 0

    def blocks_face(v):
        i = info(v & 0xFFFF)
        return bool(i) and (i["kind"] == "terrain" or i.get("full"))

    # 从楼外面的空气往里灌：只有挨着“外面”的方块才画（玩家进不了楼，封死的屋子里面看不到，省手机性能）。
    # 碎掉的窗户、敞开的门是空气，能灌进去，所以从破口还能看到屋里。
    n_all = X * Y * Z
    outside = bytearray(n_all)
    stack = []

    def passable(j):
        v = blocks[j] & 0xFFFF
        return v == 0 or info(v) is None and not names.get(v, "").startswith("terrainFiller")

    for x in range(X):
        for y in range(Y):
            for z in range(Z):
                if x in (0, X - 1) or z in (0, Z - 1) or y == Y - 1:
                    j = x + y * X + z * X * Y
                    if passable(j) and not outside[j]:
                        outside[j] = 1
                        stack.append(j)
    while stack:
        j = stack.pop()
        x, y, z = j % X, (j // X) % Y, j // (X * Y)
        for ddx, ddy, ddz in FACES:
            nx, ny, nz = x + ddx, y + ddy, z + ddz
            if 0 <= nx < X and 0 <= ny < Y and 0 <= nz < Z:
                k = nx + ny * X + nz * X * Y
                if not outside[k] and passable(k):
                    outside[k] = 1
                    stack.append(k)

    def seen(x, y, z):
        if x in (0, X - 1) or z in (0, Z - 1) or y == Y - 1:
            return True
        for ddx, ddy, ddz in FACES:
            nx, ny, nz = x + ddx, y + ddy, z + ddz
            if 0 <= nx < X and 0 <= ny < Y and 0 <= nz < Z and outside[nx + ny * X + nz * X * Y]:
                return True
        return False

    # 按 16 米一块分开（手机上看不见的块整块跳过不画）
    parts = {}

    def part(kind, name, x, y, z):
        key = ((x // CHUNK, y // CHUNK, z // CHUNK), kind, name)
        if key not in parts:
            parts[key] = MeshOut()
        return parts[key]

    flat = collections.defaultdict(set)
    missing = collections.Counter()

    def slot_tex(i, slot, bi):
        if slot < 6:
            p = (paints.get(i, 0) >> (8 * slot)) & 0xFF
            if p:
                t = paint_table.get(p, -1)
                if t > 0:
                    return t
        alt = bi["alt"]
        if alt and slot < len(alt) and isinstance(alt[slot], int):
            return alt[slot]
        if slot == 6:
            # 中间的面：ShapeAltTexture 没写就用上面的贴图
            return bi["tex"][0]
        return bi["tex"][slot]

    for i, v in enumerate(blocks):
        t = v & 0xFFFF
        if not t:
            continue
        bi = info(t)
        if bi is None:
            continue
        x, y, z = i % X, (i // X) % Y, i // (X * Y)
        if y < ground - 1:
            continue   # 地下部分（我们的地面是平的）
        if not seen(x, y, z):
            continue
        if bi["kind"] == "terrain":
            if not blocks_face(at(x, y + 1, z)):
                q = [(x + ox, y + 1 + dy, z + oz), (x + 1 + ox, y + 1 + dy, z + oz),
                     (x + 1 + ox, y + 1 + dy, z + 1 + oz), (x + ox, y + 1 + dy, z + 1 + oz)]
                mo = part(2, TERRAIN_OF.get(bi["terrain"], "concrete"), x, y, z)
                mo.tri([q[0], q[1], q[2]], (0, 1, 0), -1)
                mo.tri([q[0], q[2], q[3]], (0, 1, 0), -1)
            continue
        r = (v >> 16) & 0x1F
        geo = shapes.rotated(bi["model"], r)
        if not geo:
            continue
        for slot, cullable, wd, tris, full_face in geo:
            if cullable and wd and blocks_face(at(x + wd[0], y + wd[1], z + wd[2])):
                continue
            tid = slot_tex(i, slot, bi)
            if tid in uv_ids:
                kind, tex = 0, tid
            elif tid > 0:
                kind, tex = 1, -1   # 不在不透明图集里的是玻璃一类透明贴图
            else:
                kind, tex = 0, -1
                missing[tid] += 1
            if full_face and kind == 0:
                ax = [k for k in range(3) if wd[k]][0]
                c = (x, y, z)
                plane = c[ax] + (1 if wd[ax] > 0 else 0)
                others = [k for k in range(3) if k != ax]
                flat[(wd, plane, tex, (x // CHUNK, y // CHUNK, z // CHUNK))].add((c[others[0]], c[others[1]]))
                continue
            mo = part(kind, "", x, y, z)
            for q, n in tris:
                mo.tri([(x + p[0] + ox, y + p[1] + dy, z + p[2] + oz) for p in q], n, tex)
    # 合并同一平面、同一贴图的整面（贴图按世界坐标每米铺一次，合并后看起来一样）
    for (wd, plane, tex, ch), cells_set in flat.items():
        mo = part(0, "", ch[0] * CHUNK, ch[1] * CHUNK, ch[2] * CHUNK)
        ax = [k for k in range(3) if wd[k]][0]
        u_ax, v_ax = [k for k in range(3) if k != ax]
        left = set(cells_set)
        for (u, v) in sorted(cells_set):
            if (u, v) not in left:
                continue
            w = 1
            while (u + w, v) in left:
                w += 1
            h = 1
            while all((u + k, v + h) in left for k in range(w)):
                h += 1
            for a in range(w):
                for b in range(h):
                    left.discard((u + a, v + b))

            def P(du, dv):
                p = [0, 0, 0]
                p[ax], p[u_ax], p[v_ax] = plane, u + du, v + dv
                return (p[0] + ox, p[1] + dy, p[2] + oz)

            q = [P(0, 0), P(w, 0), P(w, h), P(0, h)]
            e1 = [q[1][k] - q[0][k] for k in range(3)]
            e2 = [q[2][k] - q[0][k] for k in range(3)]
            cr = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]]
            if sum(cr[k] * wd[k] for k in range(3)) > 0:   # 约定：叉乘朝里
                q = q[::-1]
            mo.tri([q[0], q[1], q[2]], wd, tex)
            mo.tri([q[0], q[2], q[3]], wd, tex)
    return {"parts": parts, "missing": missing,
            "offset": (ox, dy, oz), "ground": ground}



# 地面方块 → 地面贴图（assets/terrain/）
TERRAIN_OF = {"terrAsphalt": "asphalt", "terrGravel": "gravel", "terrDirt": "dirt", "terrConcrete": "concrete",
              "terrDestroyedStone": "rubble", "terrDestroyedWoodDebris": "rubble", "terrForestGround": "forest_ground",
              "terrBurntForestGround": "burnt_forest_ground", "terrDesertGround": "desert_debris"}


def write_full(path, res):
    """二进制：b"poif" u32 面组数；每组 u16 块号 u8 类别(0 不透明 1 玻璃 2 地面) u8 名字长+名字 u32 顶点数
    f32 顶点*3 f32 法线*3 i32 贴图编号 u32 下标数 u32 下标"""
    keys = sorted(k for k, mo in res["parts"].items() if mo.verts)
    chunk_ids = {c: i for i, c in enumerate(sorted({k[0] for k in keys}))}
    with open(path, "wb") as f:
        f.write(b"poif")
        f.write(struct.pack("<I", len(keys)))
        for key in keys:
            ch, kind, nm = key
            mo = res["parts"][key]
            nb = nm.encode()
            f.write(struct.pack("<HBB", chunk_ids[ch], kind, len(nb)) + nb)
            f.write(struct.pack("<I", len(mo.verts)))
            f.write(struct.pack("<%df" % (len(mo.verts) * 3), *[c for p in mo.verts for c in p]))
            f.write(struct.pack("<%df" % (len(mo.verts) * 3), *[float(c) for p in mo.normals for c in p]))
            f.write(struct.pack("<%di" % len(mo.verts), *mo.tex))
            f.write(struct.pack("<I", len(mo.idx)))
            f.write(struct.pack("<%dI" % len(mo.idx), *mo.idx))


def load_uv_ids(path):
    ids = set()
    for line in open(path, encoding="utf-8-sig"):
        if "<uv " in line:
            m = re.search(r'\bid="(\d+)"', line)
            if m:
                ids.add(int(m.group(1)))
    return ids


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", default=ROOT)
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    run(args.assets, [n for n in args.only.split(",") if n])


def run(assets, only=()):
    poi_dir = os.path.join(assets, "poi")
    bdir = os.path.join(assets, "blocks")
    need = ["blocks.xml", "shapes.xml", "painting.xml", "ta_opaque.xml"]
    if not all(os.path.exists(os.path.join(bdir, f)) for f in need) or not os.path.isdir(os.path.join(assets, "shapes")):
        print("完整的楼: 缺 assets/blocks/" + "、".join(need) + " 或 assets/shapes/，跳过")
        return set()
    names = sorted(f[:-4] for f in os.listdir(poi_dir) if f.endswith(".tts"))
    if only:
        names = [n for n in names if n in only]
    db = Blocks(os.path.join(bdir, "blocks.xml"))
    shapes = Shapes(os.path.join(bdir, "shapes.xml"), os.path.join(assets, "shapes"))
    paint_table = load_paint_table(os.path.join(bdir, "painting.xml"))
    uv_ids = load_uv_ids(os.path.join(bdir, "ta_opaque.xml"))
    used = set()
    for n in names:
        try:
            res = build_poi(n, poi_dir, db, shapes, paint_table, uv_ids)
        except (OSError, ValueError, struct.error) as e:
            print(f"  {n}: 读不了（{e}），跳过")
            continue
        write_full(os.path.join(poi_dir, n + ".full"), res)
        tris = 0
        for (ch, kind, _), mo in res["parts"].items():
            if kind == 0:
                used.update(mo.tex)
            tris += len(mo.idx) // 3
        print(f"  {n}: {tris} 个三角形，{len({k[0] for k in res['parts']})} 块", flush=True)
    used.discard(-1)
    up = os.path.join(poi_dir, "full_textures.json")
    old = set(json.load(open(up))) if os.path.exists(up) else set()
    json.dump(sorted(used | old), open(up, "w"))
    return used


if __name__ == "__main__":
    main()

