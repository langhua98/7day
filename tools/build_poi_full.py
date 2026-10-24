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
import gzip
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
            # 新版的功能块是 <property class="Loot"><property name="LootList" …/></property>，
            # 记成 "@Loot" 和 "Loot.LootList"
            for pr in bl.findall("property"):
                cls = pr.get("class")
                if cls:
                    props["@" + cls] = "1"
                    for sub in pr.findall("property"):
                        if sub.get("name"):
                            props[cls + "." + sub.get("name")] = sub.get("value")
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
                g = {"groups": groups, "full": self._is_cube(groups)}
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

    kind_cache = {}

    def col_kind(t):
        """方块编号 → 碰撞类别（不看旋转）；None = 按形状几何算"""
        if t not in kind_cache:
            kind_cache[t] = block_col_kind(db, names.get(t, "air"), info(t))
        return kind_cache[t]

    # 从楼外面的空气往里灌：只有挨着“外面”的方块才画（玩家进不了楼，封死的屋子里面看不到，省手机性能）。
    # 碎掉的窗户、敞开的门是空气，能灌进去，所以从破口还能看到屋里。
    n_all = X * Y * Z
    outside = bytearray(n_all)
    stack = []

    def passable(j):
        v = blocks[j] & 0xFFFF
        if v == 0:
            return True
        i = info(v)
        if i is None:
            return not names.get(v, "").startswith("terrainFiller")
        if i["kind"] == "terrain":
            return False
        # 只有整块的方块挡得住视线。桌子、柜台、半块、斜坡这些格子也要灌进去，
        # 不然它们底下的地板、背后的墙不画，进楼后能从桌子底下看穿到楼下
        return not i.get("full")

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
    diagnose(name, blocks, names, db, shapes, info)
    col, doors = build_collision(blocks, size, db, names, shapes, info, col_kind)
    conts = find_containers(blocks, names, size, db, (ox, dy, oz))
    for c in conts:
        c["drawn"] = info(c.pop("_t")) is not None
        if not c["drawn"]:
            # 有实体模型的容器（冰箱、垃圾桶…）：游戏里有模型就不画箱子
            c["model"] = prop_key(db.get(c["block"], "Model"))
    props = find_props(blocks, names, size, db, (ox, dy, oz), ground)
    return {"parts": parts, "missing": missing, "containers": conts, "col": col, "doors": doors,
            "offset": (ox, dy, oz), "ground": ground, "size": size, "props": props}


# 模型方块（家具、灯、柜子、杂物…）：游戏里是单独的预制体模型，不是形状方块。
# 这几类不是摆设（睡着的僵尸、动物的刷新点），不画
PROP_SKIP_FOLDERS = ("Zombies", "Animals")


def prop_key(model):
    """Model 属性 "@:Entities/Furniture/chair01Prefab.prefab" → "Furniture/chair01Prefab"；不是实体模型返回 None"""
    m = re.match(r"@?:?Entities/(.+?)\.prefab$", model or "")
    if not m:
        return None
    key = m.group(1)
    folder = key.split("/")[0]
    if folder in PROP_SKIP_FOLDERS:
        return None
    return folder + "/" + key.split("/")[-1]


def find_props(blocks, names, size, db, offset, ground):
    """楼里每个模型方块 → {"models": [预制体名], "items": [[模型下标, x, y, z, 转向], …]}。
    门另外处理（会开关），不在这里。坐标和容器一样：方块底面中心，楼的本地坐标（Unity 方向，x 未翻）。
    只存了多格方块的根格子：模型按 MultiBlockDim 摆在占的格子中间。"""
    X, Y, Z = size
    ox, dy, oz = offset
    keys = {}
    models, index, items = [], {}, []
    for j, v in enumerate(blocks):
        t = v & 0xFFFF
        if not t:
            continue
        if t not in keys:
            nm = names.get(t, "")
            b = base_name(nm)
            k = None
            if nm and db.get(b, "Shape") == "ModelEntity" and not is_door(db, nm):
                k = prop_key(db.get(b, "Model"))
            keys[t] = (k, nm)
        k, nm = keys[t]
        if k is None:
            continue
        x, y, z = j % X, (j // X) % Y, j // (X * Y)
        if y < ground - 1:
            continue
        r = (v >> 16) & 0x1F
        dim = multi_dim(db, nm, r)
        if k not in index:
            index[k] = len(models)
            models.append(k)
        cx = x + 0.5 + (0.5 if dim[0] % 2 == 0 else 0.0)
        cz = z + 0.5 + (0.5 if dim[2] % 2 == 0 else 0.0)
        items.append([index[k], round(cx + ox, 2), y + dy, round(cz + oz, 2), r])
    return {"models": models, "items": items}


def diagnose(name, blocks, names, db, shapes, info):
    """打印这栋楼的方块有多少能画出来、画不出来的原因（排查完整版为空用）"""
    count = collections.Counter(v & 0xFFFF for v in blocks if v & 0xFFFF)
    why = collections.Counter()
    miss_model = collections.Counter()
    miss_block = collections.Counter()
    for t, n in count.items():
        nm = names.get(t, "")
        if info(t) is not None:
            why["能画"] += n
            continue
        b = base_name(nm)
        sh = shape_of(nm)
        if not nm:
            why["名表里没有"] += n
        elif nm.startswith("terrainFiller"):
            why["terrainFiller"] += n
        elif b not in db.b:
            why["blocks.xml 里没有"] += n
            miss_block[b] += n
        elif sh is not None and sh not in shapes.defs:
            why["shapes.xml 里没有形状"] += n
            miss_model["形状 " + sh] += n
        else:
            model = shapes.defs.get(sh, {}).get("Model") if sh else db.get(b, "Model")
            shape = db.get(b, "Shape")
            if sh or (model or "").startswith("@:Shapes/") or shape == "New":
                why["缺形状模型 glb"] += n
                miss_model[os.path.basename(model or "Cube.fbx")] += n
            else:
                why["模型方块（%s）" % (shape or "?")] += n
    print(f"  {name}: 方块表 {len(db.b)} 种，形状表 {len(shapes.defs)} 种，形状模型 {len(shapes.files)} 个；"
          f"非空格 {sum(count.values())}，" + "，".join(f"{k} {v}" for k, v in why.most_common()), flush=True)
    # 容器、门的方块名（排查楼里认不出箱子和门）
    kinds = []
    for t, n in count.most_common():
        nm = names.get(t, "")
        b = base_name(nm)
        cls = db.get(b, "Class") or ""
        low = b.lower()
        if "cnt" in low or "loot" in low or "door" in low or "hatch" in low or "Loot" in cls or "Door" in cls:
            kinds.append(f"{nm}[{cls or '-'}|{db.get(b, 'Shape') or '-'}|{db.get(b, 'LootList') or '-'}|画{'是' if info(t) else '否'}]×{n}")
    if kinds:
        print("    容器/门方块：" + "，".join(kinds[:25]))
    if miss_block:
        print("    blocks.xml 里没有：" + "，".join(f"{k}×{v}" for k, v in miss_block.most_common(8)))
    if miss_model:
        print("    缺模型：" + "，".join(f"{k}×{v}" for k, v in miss_model.most_common(8)))
        print("    已有模型举例：" + "，".join(sorted(shapes.files)[:8]))


def container_name(db, nm):
    """方块是不是可翻的容器：名字 cnt 开头，或 Class / 功能块带 Loot。
    返回官方 LootList；新版很多容器（…RandomLootHelper）没写 LootList，就返回方块名。不是容器返回 None"""
    b = base_name(nm)
    cls = db.get(b, "Class") or ""
    if not (b.startswith("cnt") or "Loot" in cls or db.get(b, "@Loot")):
        return None
    low = b.lower()
    if "filler" in low or "empty" in low:
        return None   # 柜子的装饰填充块、空书架，不能翻
    return db.get(b, "LootList") or db.get(b, "Loot.LootList") or b


def is_door(db, nm):
    """门、活板门（不含掉人的陷阱板 TrapDoor、假柜门）"""
    b = base_name(nm)
    low = b.lower()
    cls = db.get(b, "Class") or ""
    if cls == "TrapDoor" or "trap" in low or "fake" in low:
        return False
    return "Door" in cls or bool(db.get(b, "@Door")) or "door" in low or "hatch" in low


def find_containers(blocks, names, size, db, offset):
    """楼里的容器方块 → [{block, loot, x, y, z, rot}]。坐标是楼的本地坐标（和 _full 网格一致，
    方块底面中心，y 未减 ground）。多格的容器（冰箱、货架）连在一起的同名方块只算一个。"""
    X, Y, Z = size
    ox, dy, oz = offset
    kinds = {}
    cells = {}
    for j, v in enumerate(blocks):
        t = v & 0xFFFF
        if not t:
            continue
        if t not in kinds:
            nm = names.get(t, "")
            kinds[t] = (nm, container_name(db, nm)) if nm else (nm, None)
        if kinds[t][1]:
            cells[j] = t
    out = []
    seen = set()
    for j in sorted(cells):
        if j in seen:
            continue
        t = cells[j]
        comp, stack = [], [j]
        seen.add(j)
        while stack:
            k = stack.pop()
            comp.append(k)
            x, y, z = k % X, (k // X) % Y, k // (X * Y)
            for ddx, ddy, ddz in FACES:
                nx, ny, nz = x + ddx, y + ddy, z + ddz
                if 0 <= nx < X and 0 <= ny < Y and 0 <= nz < Z:
                    n = nx + ny * X + nz * X * Y
                    if n not in seen and cells.get(n) == t:
                        seen.add(n)
                        stack.append(n)
        xs = [k % X for k in comp]
        ys = [(k // X) % Y for k in comp]
        zs = [k // (X * Y) for k in comp]
        r = (blocks[j] >> 16) & 0x1F
        dim = multi_dim(db, kinds[t][0], r)
        sx, sy, sz = max(max(xs) - min(xs) + 1, dim[0]), max(max(ys) - min(ys) + 1, dim[1]), max(max(zs) - min(zs) + 1, dim[2])
        out.append({"block": base_name(kinds[t][0]), "loot": kinds[t][1],
                    "x": round((min(xs) + max(xs) + 1) / 2 + ox, 2), "y": min(ys) + dy,
                    "z": round((min(zs) + max(zs) + 1) / 2 + oz, 2), "rot": r % 4,
                    "sx": sx, "sy": sy, "sz": sz, "_t": t})
    return out


# —— 楼内碰撞（让玩家能走进楼、上楼梯、开门）——
# 每格一个字节：
#   0 空（空气、家具模型、不挡人的装饰）
#   1..8 从格子底往上 n/8 米是实心（8 = 整格）
#   9 上半格实心（倒扣的半块、吊顶）
#   10..13 斜坡/楼梯，往 +x、-x、+z、-z 方向升高（游戏坐标，方块内 0→1 米）
#   14 梯子（能穿过，站在里面能爬）
#   15 门（关着是整格，开着是空；状态在游戏里）
COL_EMPTY, COL_FULL, COL_TOP_HALF, COL_RAMP, COL_LADDER, COL_DOOR = 0, 8, 9, 10, 14, 15
_SAMPLES = [(i + 0.5) / 4 for i in range(4)]


def multi_dim(db, block_name, rot):
    """多格方块（门、冰箱）的尺寸 MultiBlockDim "x,y,z"，转 90/270 度时 x、z 对调"""
    v = db.get(base_name(block_name), "MultiBlockDim") or ""
    try:
        d = [max(1, int(s)) for s in v.split(",")]
    except ValueError:
        d = []
    if len(d) != 3:
        return (1, 1, 1)
    return (d[2], d[1], d[0]) if rot % 2 == 1 else tuple(d)


def block_col_kind(db, nm, bi):
    """方块名 → 碰撞类别；返回 None 表示是画出来的形状方块，要按几何（含旋转）算"""
    if not nm or nm == "air":
        return COL_EMPTY
    if nm.startswith("terrainFiller"):
        return COL_FULL
    b = base_name(nm)
    cls = db.get(b, "Class") or ""
    if bi is None and is_door(db, nm):
        return COL_DOOR
    if cls == "Ladder" or (db.get(b, "Climbable") or "").lower() == "true" or b.lower().startswith("ladder"):
        return COL_LADDER
    collide = db.get(b, "Collide")
    if collide is not None and "movement" not in collide.lower():
        return COL_EMPTY
    if bi is None:
        # 没模型的容器在游戏里画成箱子，挡人；其他家具模型画不出来，就不挡（免得撞空气墙）
        return COL_FULL if container_name(db, nm) else COL_EMPTY
    if bi["kind"] == "terrain":
        return COL_FULL
    return None


def shape_col(geo):
    """转好的形状几何 → 碰撞类别：竖着往下打 4×4 根射线，看每根打到的最高、最低点"""
    tris = [q for _, _, _, rt, _ in (geo or []) for q, _ in rt]
    if not tris:
        return COL_EMPTY
    lo = min(p[1] for q in tris for p in q)
    hi = max(p[1] for q in tris for p in q)
    cols = {}
    for su in _SAMPLES:
        for sw in _SAMPLES:
            ys = []
            for a, b, c in tris:
                d = (b[0] - a[0]) * (c[2] - a[2]) - (c[0] - a[0]) * (b[2] - a[2])
                if abs(d) < 1e-7:
                    continue   # 竖着的三角形
                l1 = ((b[0] - su) * (c[2] - sw) - (c[0] - su) * (b[2] - sw)) / d
                l2 = ((c[0] - su) * (a[2] - sw) - (a[0] - su) * (c[2] - sw)) / d
                l3 = 1.0 - l1 - l2
                if min(l1, l2, l3) < -1e-4:
                    continue
                ys.append(l1 * a[1] + l2 * b[1] + l3 * c[1])
            if ys:
                cols[(su, sw)] = (min(ys), max(ys))
    if len(cols) < 4:
        # 薄的东西（玻璃、竖板、栏杆、柱子）：够高就当整格挡住，矮的小东西不挡
        return COL_FULL if hi - lo >= 0.5 else COL_EMPTY
    if min(v[0] for v in cols.values()) >= 0.4:
        return COL_TOP_HALF
    tops = {k: v[1] for k, v in cols.items()}
    top = lambda su, sw: tops.get((su, sw), 0.0)
    mx = max(tops.values())
    if mx - min(top(su, sw) for su in _SAMPLES for sw in _SAMPLES) > 0.3:
        dx = sum(top(su, sw) * (1 if su > 0.5 else -1) for su in _SAMPLES for sw in _SAMPLES) / 8
        dz = sum(top(su, sw) * (1 if sw > 0.5 else -1) for su in _SAMPLES for sw in _SAMPLES) / 8
        if max(abs(dx), abs(dz)) > 0.25:
            # 楼梯、斜坡（拐角楼梯取升得多的方向）
            if abs(dx) >= abs(dz):
                return COL_RAMP + (0 if dx > 0 else 1)
            return COL_RAMP + (2 if dz > 0 else 3)
    return max(1, min(COL_FULL, math.ceil(mx * 8 - 0.05)))


def build_collision(blocks, size, db, names, shapes, info, col_kind):
    """整栋楼每格的碰撞类别（bytearray，下标 x + y*X + z*X*Y）和门的列表"""
    X, Y, Z = size
    col = bytearray(X * Y * Z)
    geo_cache = {}
    door_cells = {}
    for j, v in enumerate(blocks):
        t = v & 0xFFFF
        if not t:
            continue
        k = col_kind(t)
        if k is None:
            r = (v >> 16) & 0x1F
            key = (info(t)["model"], r)
            if key not in geo_cache:
                geo_cache[key] = shape_col(shapes.rotated(key[0], r))
            k = geo_cache[key]
        if k == COL_DOOR:
            door_cells[j] = t
        col[j] = k
    doors = []
    seen = set()
    for j in sorted(door_cells):
        if j in seen:
            continue
        t = door_cells[j]
        comp, stack = [], [j]
        seen.add(j)
        while stack:
            k = stack.pop()
            comp.append(k)
            x, y, z = k % X, (k // X) % Y, k // (X * Y)
            for ddx, ddy, ddz in FACES:
                nx, ny, nz = x + ddx, y + ddy, z + ddz
                if 0 <= nx < X and 0 <= ny < Y and 0 <= nz < Z:
                    n = nx + ny * X + nz * X * Y
                    if n not in seen and door_cells.get(n) == t:
                        seen.add(n)
                        stack.append(n)
        xs = [k % X for k in comp]
        ys = [(k // X) % Y for k in comp]
        zs = [k // (X * Y) for k in comp]
        x0, y0, z0, x1, y1, z1 = min(xs), min(ys), min(zs), max(xs), max(ys), max(zs)
        nm = names.get(t, "")
        r = (blocks[j] >> 16) & 0x1F
        dim = multi_dim(db, nm, r)
        # 只存了门的根方块时，按 MultiBlockDim 往上补满（门一般 1×2）
        y1 = max(y1, min(Y - 1, y0 + dim[1] - 1))
        for y in range(y0, y1 + 1):
            for z in range(z0, z1 + 1):
                for x in range(x0, x1 + 1):
                    i = x + y * X + z * X * Y
                    if col[i] == COL_EMPTY:
                        col[i] = COL_DOOR

        def solid(x, y, z):
            if 0 <= x < X and 0 <= y < Y and 0 <= z < Z:
                return 4 <= col[x + y * X + z * X * Y] <= COL_TOP_HALF
            return False
        # 门板沿哪个方向：比一格宽就沿宽的方向；否则看两边哪边是墙
        if x1 > x0:
            axis = "x"
        elif z1 > z0:
            axis = "z"
        else:
            wx = solid(x0 - 1, y0, z0) + solid(x0 + 1, y0, z0)
            wz = solid(x0, y0, z0 - 1) + solid(x0, y0, z0 + 1)
            axis = "x" if wx > wz or (wx == wz and r % 2 == 0) else "z"
        low = base_name(nm).lower()
        doors.append({"block": base_name(nm), "model": prop_key(db.get(base_name(nm), "Model")), "x0": x0, "y0": y0, "z0": z0, "x1": x1, "y1": y1, "z1": z1,
                      "axis": axis, "metal": any(w in low for w in ("metal", "steel", "vault", "iron", "security", "jail")),
                      "hatch": "hatch" in low})
    return col, doors


def write_col(path, res):
    """碰撞格子：b"poic" u16 X Y Z、i16 偏移 x y z，然后 gzip 压缩的 X*Y*Z 字节（下标 x + y*X + z*X*Y）"""
    X, Y, Z = res["size"]
    ox, dy, oz = res["offset"]
    with open(path, "wb") as f:
        f.write(b"poic" + struct.pack("<HHHhhh", X, Y, Z, ox, dy, oz))
        f.write(gzip.compress(bytes(res["col"]), 6))


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
    if not os.path.isdir(poi_dir):
        print("完整的楼: 没有 assets/poi/，跳过")
        return set()
    names = sorted(f[:-4] for f in os.listdir(poi_dir) if f.endswith(".tts"))
    if only:
        names = [n for n in names if n in only]
    print("  方块文件：" + "，".join(f"{f} {os.path.getsize(os.path.join(bdir, f)) // 1024}KB" for f in need), flush=True)
    db = Blocks(os.path.join(bdir, "blocks.xml"))
    shapes = Shapes(os.path.join(bdir, "shapes.xml"), os.path.join(assets, "shapes"))
    paint_table = load_paint_table(os.path.join(bdir, "painting.xml"))
    uv_ids = load_uv_ids(os.path.join(bdir, "ta_opaque.xml"))
    used = set()
    props_needed = set()
    doors_needed = set()
    cpath = os.path.join(poi_dir, "containers.json")
    conts = json.load(open(cpath)) if os.path.exists(cpath) else {}
    for n in names:
        try:
            res = build_poi(n, poi_dir, db, shapes, paint_table, uv_ids)
        except (OSError, ValueError, struct.error) as e:
            print(f"  {n}: 读不了（{e}），跳过")
            continue
        write_full(os.path.join(poi_dir, n + ".full"), res)
        write_col(os.path.join(poi_dir, n + ".col"), res)
        tris = 0
        for (ch, kind, _), mo in res["parts"].items():
            if kind == 0:
                used.update(mo.tex)
            tris += len(mo.idx) // 3
        conts[n] = {"ground": res["ground"], "list": res["containers"], "doors": res["doors"], "col": True,
                    "props": res["props"]}
        props_needed.update(res["props"]["models"])
        doors_needed.update(d["model"] for d in res["doors"] if d.get("model"))
        print(f"  {n}: {tris} 个三角形，{len({k[0] for k in res['parts']})} 块，{len(res['containers'])} 个容器，"
              f"{len(res['doors'])} 扇门，{len(res['props']['items'])} 个模型（{len(res['props']['models'])} 种）", flush=True)
    used.discard(-1)
    up = os.path.join(poi_dir, "full_textures.json")
    old = set(json.load(open(up))) if os.path.exists(up) else set()
    json.dump(sorted(used | old), open(up, "w"))
    json.dump(conts, open(cpath, "w"), ensure_ascii=False)
    # 要找模型的预制体（tools/fetch_assets.py 的 fetch_poi_props 读）
    json.dump({"props": sorted(props_needed), "doors": sorted(doors_needed)},
              open(os.path.join(poi_dir, "props_needed.json"), "w"))
    return used


if __name__ == "__main__":
    main()

