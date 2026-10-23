#!/usr/bin/env python3
"""楼内碰撞数据（tools/build_poi_full.py 的 .col 和门列表）：用一栋假的小楼跑一遍，不需要真素材。
用法：python3 tests/test_poi_interior.py"""
import gzip
import json
import os
import struct
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import build_poi_full as B  # noqa: E402


def write_glb(path, groups):
    """groups: [(子网格名, [三角形 (p0,p1,p2)，游戏坐标 0..1])] → 最小的 glb（根 → LOD0 → 每组一个节点）"""
    buf = b""
    j = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}],
         "nodes": [{"name": "root", "children": [1]}, {"name": "LOD0", "children": []}],
         "meshes": [], "accessors": [], "bufferViews": [], "buffers": []}
    for name, tris in groups:
        pts = []
        for t in tris:
            for p in t:
                pts.append((1.0 - p[0], p[1], p[2] - 1.0))   # 游戏坐标 → glTF
        data = b"".join(struct.pack("<3f", *p) for p in pts)
        j["bufferViews"].append({"buffer": 0, "byteOffset": len(buf), "byteLength": len(data)})
        j["accessors"].append({"bufferView": len(j["bufferViews"]) - 1, "componentType": 5126,
                               "count": len(pts), "type": "VEC3"})
        buf += data
        j["meshes"].append({"primitives": [{"attributes": {"POSITION": len(j["accessors"]) - 1}}]})
        j["nodes"].append({"name": name, "mesh": len(j["meshes"]) - 1})
        j["nodes"][1]["children"].append(len(j["nodes"]) - 1)
    j["buffers"].append({"byteLength": len(buf)})
    js = json.dumps(j).encode()
    js += b" " * (-len(js) % 4)
    buf += b"\0" * (-len(buf) % 4)
    body = struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(buf), b"BIN\0") + buf
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)


def quad(a, b, c, d):
    return [(a, b, c), (a, c, d)]


CUBE = [("T_F", quad((0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0))), ("B_F", quad((0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1))),
        ("N_F", quad((0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1))), ("S_F", quad((0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0))),
        ("W_F", quad((0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0))), ("E_F", quad((1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)))]
# 往 +x 升高的斜坡
RAMP = [("B_F", quad((0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1))), ("M_x", quad((0, 0, 0), (0, 0, 1), (1, 1, 1), (1, 1, 0))),
        ("E_F", quad((1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1))),
        ("S_P", [((0, 0, 0), (1, 1, 0), (1, 0, 0))]), ("N_P", [((0, 0, 1), (1, 0, 1), (1, 1, 1))])]
HALF = [(n, [tuple((p[0], p[1] * 0.5, p[2]) for p in t) for t in tris]) for n, tris in CUBE]
PANE = [("N_P", quad((0, 0, 0.45), (1, 0, 0.45), (1, 1, 0.45), (0, 1, 0.45)))]

BLOCKS_XML = """<blocks>
<block name="concrete"><property name="Shape" value="New"/><property name="Texture" value="1"/></block>
<block name="concreteShapes"><property name="Shape" value="New"/><property name="Texture" value="1"/></block>
<block name="doorWood"><property name="Class" value="DoorSecure"/><property name="Shape" value="Ext3dModel"/>
  <property name="Model" value="Entities/Doors/door"/><property name="MultiBlockDim" value="1,2,1"/></block>
<block name="ladderWood"><property name="Class" value="Ladder"/><property name="Shape" value="New"/><property name="Texture" value="1"/></block>
<block name="cntFridge"><property name="Class" value="Loot"/><property name="LootList" value="fridge"/>
  <property name="Shape" value="Ext3dModel"/><property name="Model" value="x"/><property name="MultiBlockDim" value="1,2,1"/></block>
<block name="plantTall"><property name="Shape" value="New"/><property name="Texture" value="1"/><property name="Collide" value="melee,bullet"/></block>
<block name="cntDeskWoodRandomLootHelper"><property name="Class" value="CompositeTileEntity"/>
  <property name="Shape" value="ModelEntity"/><property name="Model" value="z"/><property class="Loot"><property name="LootContainer" value="x"/></property></block>
<block name="commercialDoorV2Blue"><property name="Class" value="CompositeTileEntity"/><property name="Shape" value="ModelEntity"/>
  <property name="Model" value="d"/><property name="MultiBlockDim" value="1,2,1"/></block>
<block name="cntCabinetBottomFiller"><property name="Shape" value="New"/><property name="Texture" value="1"/></block>
<block name="looseBoardsTrapPlate1x1"><property name="Class" value="TrapDoor"/><property name="Shape" value="ModelEntity"/><property name="Model" value="t"/></block>
<block name="sofa"><property name="Shape" value="Ext3dModel"/><property name="Model" value="y"/></block>
</blocks>"""
SHAPES_XML = """<shapes>
<shape name="rampTest"><property name="Model" value="@:Shapes/ramp_test.fbx"/></shape>
<shape name="halfTest"><property name="Model" value="@:Shapes/half_test.fbx"/></shape>
<shape name="paneTest"><property name="Model" value="@:Shapes/pane_test.fbx"/></shape>
</shapes>"""
NAMES = {1: "concrete", 2: "concreteShapes:rampTest", 3: "doorWood", 4: "ladderWood", 5: "cntFridge",
         6: "concreteShapes:halfTest", 7: "concreteShapes:paneTest", 8: "plantTall", 9: "sofa",
         10: "cntDeskWoodRandomLootHelper", 11: "commercialDoorV2Blue", 12: "cntCabinetBottomFiller",
         13: "looseBoardsTrapPlate1x1"}


def build_fixture(root):
    X, Y, Z = 7, 5, 7
    cells = {}
    for x in range(X):
        for z in range(Z):
            cells[(x, 0, z)] = 1            # 地板（街面下一格）
            cells[(x, 4, z)] = 1            # 屋顶
            if x in (0, X - 1) or z in (0, Z - 1):
                for y in (1, 2, 3):
                    cells[(x, y, z)] = 1    # 外墙
    cells[(3, 1, 0)] = 3                    # 门（只存根方块，上一格靠 MultiBlockDim 补）
    cells.pop((3, 2, 0))
    cells[(2, 1, 3)] = 2                    # 斜坡，往 +x 升
    cells[(1, 1, 5)] = 4                    # 梯子
    cells[(5, 1, 5)] = 5                    # 冰箱（没模型的容器）
    cells[(4, 1, 1)] = 6                    # 半块
    cells[(1, 1, 1)] = 7                    # 玻璃竖板
    cells[(2, 1, 1)] = 8                    # 不挡人的植物
    cells[(5, 1, 1)] = 9                    # 沙发（画不出来的家具）
    cells[(4, 1, 5)] = 10                   # 新版容器：功能块 Loot，没写 LootList
    cells[(0, 1, 3)] = 11                   # 新版门：CompositeTileEntity，名字带 Door
    cells.pop((0, 2, 3))
    cells[(3, 1, 4)] = 12                   # 柜子填充块，不能翻
    cells[(4, 1, 3)] = 13                   # 掉人的陷阱板，不是门
    vals = [0] * (X * Y * Z)
    for (x, y, z), t in cells.items():
        vals[x + y * X + z * X * Y] = t
    poi = os.path.join(root, "poi")
    os.makedirs(poi)
    n = X * Y * Z
    with open(os.path.join(poi, "test_poi.tts"), "wb") as f:
        f.write(b"tts\0" + struct.pack("<I", 19) + struct.pack("<HHH", X, Y, Z))
        f.write(struct.pack("<%dI" % n, *vals) + b"\0" * (3 * n))
    with open(os.path.join(poi, "test_poi.nim"), "wb") as f:
        f.write(struct.pack("<II", 1, len(NAMES)))
        for i, nm in NAMES.items():
            f.write(struct.pack("<IB", i, len(nm)) + nm.encode())
    with open(os.path.join(poi, "test_poi.xml"), "w") as f:
        f.write('<prefab><property name="YOffset" value="-1"/></prefab>')
    bd = os.path.join(root, "blocks")
    os.makedirs(bd)
    open(os.path.join(bd, "blocks.xml"), "w").write(BLOCKS_XML)
    open(os.path.join(bd, "shapes.xml"), "w").write(SHAPES_XML)
    open(os.path.join(bd, "painting.xml"), "w").write("<paints/>")
    open(os.path.join(bd, "ta_opaque.xml"), "w").write('<uvs><uv id="1" index="0"/></uvs>')
    sd = os.path.join(root, "shapes")
    os.makedirs(sd)
    write_glb(os.path.join(sd, "Cube.glb"), CUBE)
    write_glb(os.path.join(sd, "ramp_test.glb"), RAMP)
    write_glb(os.path.join(sd, "half_test.glb"), HALF)
    write_glb(os.path.join(sd, "pane_test.glb"), PANE)
    return X, Y, Z


def main():
    fails = []

    def check(cond, msg):
        if not cond:
            fails.append(msg)

    with tempfile.TemporaryDirectory() as root:
        X, Y, Z = build_fixture(root)
        B.run(root, ["test_poi"])
        poi = os.path.join(root, "poi")
        d = open(os.path.join(poi, "test_poi.col"), "rb").read()
        check(d[:4] == b"poic", "col 文件头")
        sx, sy, sz, ox, dy, oz = struct.unpack_from("<HHHhhh", d, 4)
        check((sx, sy, sz) == (X, Y, Z) and (ox, dy, oz) == (-3, 4, -3), "尺寸和偏移 %s" % ((sx, sy, sz, ox, dy, oz),))
        col = gzip.decompress(d[16:])
        check(len(col) == X * Y * Z, "格子数")
        at = lambda x, y, z: col[x + y * X + z * X * Y]
        check(at(3, 0, 3) == B.COL_FULL and at(3, 4, 3) == B.COL_FULL and at(0, 1, 0) == B.COL_FULL, "地板和墙是整格")
        check(at(3, 2, 3) == B.COL_EMPTY, "屋里是空的")
        check(at(3, 1, 0) == B.COL_DOOR and at(3, 2, 0) == B.COL_DOOR, "门两格 %d %d" % (at(3, 1, 0), at(3, 2, 0)))
        check(at(2, 1, 3) == B.COL_RAMP, "斜坡往 +x 升 %d" % at(2, 1, 3))
        check(at(1, 1, 5) == B.COL_LADDER, "梯子")
        check(at(5, 1, 5) == B.COL_FULL, "没模型的冰箱画成箱子、挡人")
        check(at(4, 1, 1) == 4, "半块 = 4/8 米 %d" % at(4, 1, 1))
        check(at(1, 1, 1) == B.COL_FULL, "玻璃竖板挡人")
        check(at(2, 1, 1) == B.COL_EMPTY, "Collide 没有 movement 的不挡人")
        check(at(5, 1, 1) == B.COL_EMPTY, "画不出来的家具不挡人")
        js = json.load(open(os.path.join(poi, "containers.json")))["test_poi"]
        check(js.get("col") is True, "containers.json 标了 col")
        doors = js["doors"]
        check(len(doors) == 2, "两扇门 %s" % [d["block"] for d in doors])
        check(any(d["block"] == "commercialDoorV2Blue" and d["axis"] == "z" for d in doors), "新版门，门板沿 z")
        if doors:
            dd = doors[0]
            check((dd["x0"], dd["y0"], dd["z0"], dd["y1"]) == (3, 1, 0, 2), "门的格子 %s" % dd)
            check(dd["axis"] == "x" and not dd["metal"], "门板沿 x（两边是墙）")
        fr = [c for c in js["list"] if c["block"] == "cntFridge"]
        check(len(fr) == 1 and fr[0]["drawn"] is False and fr[0]["sy"] == 2, "冰箱：没画、两格高 %s" % fr)
        check(all("_t" not in c for c in js["list"]), "内部字段不写进 json")
        desk = [c for c in js["list"] if c["block"] == "cntDeskWoodRandomLootHelper"]
        check(len(desk) == 1 and desk[0]["loot"] == "cntDeskWoodRandomLootHelper", "新版容器认出来 %s" % desk)
        check(not any(c["block"] == "cntCabinetBottomFiller" for c in js["list"]), "填充块不算容器")
    for f in fails:
        print("FAIL:", f)
    print("test_poi_interior", "OK" if not fails else "FAIL")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
