#!/usr/bin/env python3
"""从小桔云盘把自己导出的《七日杀》素材整理到本地 assets/ 目录（只放本地，不进仓库）。

用法（在 Mac 上，仓库根目录）：
    export XIAOJU_TOKEN=你的令牌
    python3 tools/fetch_assets.py              # 默认：8 种僵尸、每类 6 段音乐
    python3 tools/fetch_assets.py --zombies all --music 12

生成的结构：
    assets/index/icon_to_model.json
    assets/icons/<物品名>.png
    assets/models/zombie_<名字>.glb   （带骨骼和贴图）
    assets/models/<模型名>.glb         （物品模型、第一人称手臂，带贴图）
    assets/models/fp_arms.glb          （带骨骼和手指的第一人称手臂）
    assets/items/<模型名>.obj/.png      （物品网格和真贴图，从 items.zip 里按需取）
    assets/index/item_models.json      （物品模型名 → 网格、贴图）
    assets/world/*.obj/.png            （市中心场景：车辆、可翻找的容器、杂物、地面和楼的贴图）
    assets/index/world_models.json     （场景模型的类别、中文名、战利品类型）
    assets/poi/*.poimesh/.xml          （市中心建筑，再用 tools/build_poi.gd 转成 .res）
    assets/textures/*.png              （地面贴图）
    assets/music/*.wav                 （文件名里 Exp=探索 Cbt=战斗 Sus=紧张 Bld=血月）

只用 Python 自带库（装了 Pillow 会把场景贴图缩到 1024，省手机内存）。已存在且大小一致的文件会跳过，可以反复运行。
"""
import argparse
import io
import json
import os
import re
import shutil
import sys
import tempfile
import urllib.parse
import urllib.request
import zipfile

API = os.environ.get("XIAOJU_API", "https://langhua1998-xiaoju-cloud.hf.space/api/agent/v1")
DRIVE_ROOT = "/7day"
DEFAULT_ZOMBIES = ["soldier", "nurse", "cop", "biker", "lumberjack", "joe", "arlene", "screamer"]
# 游戏会用到的物品前缀（图标太多，只取这些，--all-icons 可以全取）
GAME_PREFIXES = ("melee", "gun", "food", "drink", "medical", "resource", "ammo", "armor", "apparel", "thrown", "tool")


def token():
    t = os.environ.get("XIAOJU_TOKEN", "").strip()
    if not t:
        sys.exit("请先设置环境变量 XIAOJU_TOKEN（小桔云盘令牌）")
    return t


def request(endpoint, **query):
    url = API + endpoint
    if query:
        url += "?" + urllib.parse.urlencode(query)
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token()})
    return urllib.request.urlopen(req, timeout=120)


def list_dir(path):
    items, cursor = [], None
    while True:
        q = {"path": path}
        if cursor:
            q["cursor"] = cursor
        with request("/items", **q) as r:
            data = json.load(r)
        items += data.get("children", [])
        cursor = data.get("next_cursor")
        if not cursor:
            return items


def download(item, dest):
    if os.path.exists(dest) and os.path.getsize(dest) == item.get("size"):
        return False
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".part"
    for attempt in range(4):
        try:
            with request(f"/items/{item['id']}/content") as r, open(tmp, "wb") as f:
                shutil.copyfileobj(r, f, 1 << 20)
        except OSError as e:
            print(f"  下载中断（{e}），重试 …")
            continue
        got = os.path.getsize(tmp)
        if item.get("size") in (None, got):
            os.replace(tmp, dest)
            return True
        print(f"  {item['name']} 只下载到 {mb(got)} / {mb(item['size'])}，重试 …")
    sys.exit(f"下载 {item['name']} 失败，请稍后再试")


def find(items, name):
    for it in items:
        if it["name"] == name:
            return it
    return None


def mb(n):
    return f"{n / 1e6:.1f}MB"


def fetch_index(dest):
    files = list_dir(f"{DRIVE_ROOT}/索引")
    it = find(files, "icon_to_model.json")
    if not it:
        sys.exit("云盘 /7day/索引/ 里没有 icon_to_model.json")
    download(it, os.path.join(dest, "index", "icon_to_model.json"))
    with open(os.path.join(dest, "index", "icon_to_model.json"), encoding="utf-8") as f:
        rows = json.load(f)
    print(f"物品表: {len(rows)} 行")
    return rows


def fetch_icons(dest, rows, all_icons):
    wanted = {r[0] for r in rows if r and r[0]}
    if not all_icons:
        wanted = {w for w in wanted if w.lower().startswith(GAME_PREFIXES)}
    out_dir = os.path.join(dest, "icons")
    os.makedirs(out_dir, exist_ok=True)
    have = {os.path.splitext(f)[0] for f in os.listdir(out_dir)}
    if wanted <= have:
        print(f"图标: 已有 {len(wanted)} 个，跳过")
        return
    zips = [z for z in list_dir(f"{DRIVE_ROOT}/物品图标") if z["name"].endswith(".zip")]
    for z in zips:
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, z["name"])
            print(f"下载图标包 {z['name']} ({mb(z['size'])}) …")
            download(z, path)
            n = 0
            with zipfile.ZipFile(path) as zf:
                for info in zf.infolist():
                    base = os.path.basename(info.filename)
                    stem, ext = os.path.splitext(base)
                    if ext.lower() == ".png" and stem in wanted:
                        with zf.open(info) as src, open(os.path.join(out_dir, base), "wb") as dst:
                            shutil.copyfileobj(src, dst)
                        n += 1
            print(f"图标: 解出 {n} 个")


def fetch_zombies(dest, choice):
    folder = f"{DRIVE_ROOT}/小橘素材库/zombies_assets_entities/zombies"
    zips = {os.path.splitext(z["name"])[0]: z for z in list_dir(folder) if z["name"].endswith(".zip")}
    names = sorted(zips) if choice == ["all"] else [n for n in choice if n in zips]
    missing = [n for n in choice if n != "all" and n not in zips]
    if missing:
        print("云盘里没有这些僵尸:", ", ".join(missing), "；可选:", ", ".join(sorted(zips)))
    out_dir = os.path.join(dest, "models")
    os.makedirs(out_dir, exist_ok=True)
    for name in names:
        out = os.path.join(out_dir, f"zombie_{name}.glb")
        tex_out = os.path.join(out_dir, f"zombie_{name}.png")
        if os.path.exists(out) and os.path.exists(tex_out):
            print(f"僵尸 {name}: 已有，跳过")
            continue
        z = zips[name]
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, z["name"])
            print(f"下载僵尸 {name} ({mb(z['size'])}) …")
            download(z, path)
            with zipfile.ZipFile(path) as zf:
                glbs = [i for i in zf.infolist() if i.filename.startswith("rigged/") and i.filename.endswith(".glb")]
                glbs = [i for i in glbs if i.file_size > 10_000]  # 有的导出是空壳
                if not glbs:
                    print(f"  {name} 没有可用的带骨骼 glb，跳过")
                    continue
                best = max(glbs, key=lambda i: i.file_size)
                with zf.open(best) as src, open(out, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                # 有的 glb 没把贴图打包进去，另外取一张主贴图（排除法线、RMOE、遮罩），文件名最短的通常是基础款
                skip = re.compile(r"(_n|_rmoe|normal|mask|gibs|_s|_ao|_e)\.png$", re.I)
                texs = [i for i in zf.infolist() if i.filename.startswith("textures/") and i.filename.lower().endswith(".png")
                        and not skip.search(i.filename) and i.file_size > 50_000]
                if texs:
                    main_tex = min(texs, key=lambda i: (len(os.path.basename(i.filename)), -i.file_size))
                    with zf.open(main_tex) as src, open(tex_out, "wb") as dst:
                        shutil.copyfileobj(src, dst)
            print(f"  → {os.path.relpath(out)} ({mb(os.path.getsize(out))})")


class RemoteFile(io.RawIOBase):
    """用 HTTP Range 按需读取云盘上的大文件，打开大 zip 时只下载用得到的部分。"""

    def __init__(self, item):
        self.id, self.size, self.pos = item["id"], item["size"], 0

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else self.size + off)
        return self.pos

    def readinto(self, buf):
        n = min(len(buf), self.size - self.pos)
        if n <= 0:
            return 0
        url = API + f"/items/{self.id}/content"
        for attempt in range(5):
            try:
                req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token(),
                                                           "Range": f"bytes={self.pos}-{self.pos + n - 1}"})
                with urllib.request.urlopen(req, timeout=300) as r:
                    data = r.read()
                break
            except OSError as e:
                print(f"  读取中断（{e}），重试 …")
        else:
            sys.exit("读取云盘文件失败，请稍后再试")
        buf[:len(data)] = data
        self.pos += len(data)
        return len(data)


def open_remote_zip(path):
    folder, name = path.rsplit("/", 1)
    it = find(list_dir(folder), name)
    if not it:
        return None
    return zipfile.ZipFile(io.BufferedReader(RemoteFile(it), buffer_size=1 << 20))


def fetch_fp_arms(dest):
    """带骨骼（肩、臂、手、每根手指）的第一人称手臂，游戏里摆成握持姿势。"""
    out = os.path.join(dest, "models", "fp_arms.glb")
    skin = os.path.join(dest, "textures", "fp_arms_skin.png")
    if os.path.exists(out) and os.path.exists(skin):
        print("第一人称手臂: 已有，跳过")
        return
    zf = open_remote_zip(f"{DRIVE_ROOT}/小橘素材库/player_assets_entities/player/common.zip")
    if zf is None:
        print("云盘里没有 player/common.zip，跳过带骨骼手臂")
        return
    glbs = [i for i in zf.infolist() if i.filename.startswith("rigged/") and i.filename.endswith(".glb")]
    if not glbs:
        print("player/common.zip 里没有带骨骼的手臂")
        return
    os.makedirs(os.path.dirname(out), exist_ok=True)
    os.makedirs(os.path.dirname(skin), exist_ok=True)
    with zf.open(glbs[0]) as src, open(out, "wb") as dst:
        shutil.copyfileobj(src, dst)
    # 手臂的原贴图（4K），样例里那张是缩小过的、带黑块
    for i in zf.infolist():
        if os.path.basename(i.filename) == "HD_Hands_Male.png":
            with zf.open(i) as src, open(skin, "wb") as dst:
                shutil.copyfileobj(src, dst)
    print(f"第一人称手臂 → {os.path.relpath(out)}")


def _norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def _base(s):
    s = re.sub(r"(?i)prefab", "", s)
    s = re.sub(r"(?i)_?lod\d+(_\d+)?$", "", s)
    return re.sub(r"(?i)(mesh|held|_)+$", "", s)


def _tokens(s):
    return re.findall(r"[A-Z]?[a-z0-9]+|[A-Z]+(?![a-z])", _base(s).replace("_", " "))


def _candidates(name):
    toks = _tokens(name)
    out = [_norm(_base(name))]
    out += [_norm("".join(toks[:i])) for i in range(len(toks) - 1, 0, -1)]  # 去掉后缀词：cannedFood_Peas → cannedFood
    out += [_norm("".join(toks[i:])) for i in range(1, len(toks))]          # 去掉前缀词
    return [c for c in out if c]


def _lod(n):
    m = re.search(r"(?i)lod(\d)", n)
    return int(m.group(1)) if m else 0


TEX_SKIP = re.compile(r"(?i)(_n|_rmom|_rmoe|_r|_m|_o|_e|_s|_h|_ao|_i|_gme|_gmer|_rme|_normal|_n_\d)$")


def match_item_models(model_names, mesh_sizes, tex_sizes):
    """物品表里的模型名（如 cannedFood_PeasPrefab）→ items.zip 里的网格和贴图。"""
    mesh_by = {}
    for m in mesh_sizes:
        if re.search(r"(?i)collision", m) or re.match(r"(?i)^(lod\d|object\d+|main_mesh|mesh)", m):
            continue
        mesh_by.setdefault(_norm(_base(m)), []).append(m)
    tex_by = {}
    for t in tex_sizes:
        if not TEX_SKIP.search(t):
            tex_by.setdefault(_norm(re.sub(r"(?i)_(d|df|diff)$", "", t)), []).append(t)

    def pick_mesh(name):
        for c in _candidates(name):
            if c in mesh_by:
                return min(mesh_by[c], key=lambda m: (_lod(m), -mesh_sizes[m]))
        k = _norm(_base(name))
        for mk, lst in mesh_by.items():
            if len(k) >= 5 and k in mk and "bullet" not in mk:
                return min(lst, key=lambda m: (_lod(m), -mesh_sizes[m]))
        return None

    def pick_tex(*names):
        for name in names:
            if not name:
                continue
            for c in _candidates(name):
                for key in (c, "new" + c):
                    if key in tex_by:
                        return max(tex_by[key], key=lambda t: tex_sizes[t])
            k = _norm(_base(name))
            for tk, lst in tex_by.items():
                if len(k) >= 5 and (k in tk or (len(tk) >= 5 and tk in k)):
                    return max(lst, key=lambda t: tex_sizes[t])
        return None

    out = {}
    for name in model_names:
        mesh = pick_mesh(name)
        if not mesh:
            continue
        # 有的模型拆成几块（pickaxeIron_1/_2/_3），一起取
        parts = [mesh]
        m = re.match(r"^(.*)_(\d+)$", mesh)
        if m:
            parts = sorted(x for x in mesh_sizes if re.fullmatch(re.escape(m.group(1)) + r"_\d+", x))
        out[name] = {"meshes": parts, "texture": pick_tex(name, mesh)}
    return out


def _merge_obj(texts):
    """把几个 obj 拼成一个（顶点编号顺延）。"""
    out, nv, nt, nn = [], 0, 0, 0
    for text in texts:
        cv = ct = cn = 0
        for line in text.splitlines():
            if line.startswith("v "):
                cv += 1
                out.append(line)
            elif line.startswith("vt "):
                ct += 1
                out.append(line)
            elif line.startswith("vn "):
                cn += 1
                out.append(line)
            elif line.startswith("f "):
                fixed = []
                for corner in line.split()[1:]:
                    p = corner.split("/")
                    p[0] = str(int(p[0]) + nv)
                    if len(p) > 1 and p[1]:
                        p[1] = str(int(p[1]) + nt)
                    if len(p) > 2 and p[2]:
                        p[2] = str(int(p[2]) + nn)
                    fixed.append("/".join(p))
                out.append("f " + " ".join(fixed))
        nv, nt, nn = nv + cv, nt + ct, nn + cn
    return "\n".join(out) + "\n"


def fetch_items(dest, rows):
    """从 items.zip（近 1GB）里只取物品表用得到的网格和贴图。"""
    index_out = os.path.join(dest, "index", "item_models.json")
    if os.path.exists(index_out):
        print("物品模型: 已有，跳过（删掉 assets/index/item_models.json 可重新取）")
        return
    zf = open_remote_zip(f"{DRIVE_ROOT}/小橘素材库/automatic_assets_other/items.zip")
    if zf is None:
        print("云盘里没有 automatic_assets_other/items.zip，物品用样例模型")
        return
    infos = {i.filename: i for i in zf.infolist()}
    meshes = {os.path.basename(n)[:-4]: n for n in infos if n.startswith("meshes/") and n.endswith(".obj")}
    texs = {os.path.basename(n)[:-4]: n for n in infos if n.startswith("textures/") and n.endswith(".png")}
    names = sorted({r[3] for r in rows if len(r) > 3 and r[3] and not r[3].startswith("gear_")})
    matched = match_item_models(names, {k: infos[v].file_size for k, v in meshes.items()},
                                {k: infos[v].file_size for k, v in texs.items()})
    out_dir = os.path.join(dest, "items")
    os.makedirs(out_dir, exist_ok=True)
    index, done_tex = {}, {}
    for name, m in matched.items():
        stem = re.sub(r"[^A-Za-z0-9_]", "_", name)
        obj_path = os.path.join(out_dir, stem + ".obj")
        merged = _merge_obj([zf.read(meshes[p]).decode("utf-8", "replace") for p in m["meshes"]])
        with open(obj_path, "w", encoding="utf-8") as f:
            f.write(merged)
        entry = {"mesh": f"items/{stem}.obj"}
        if m["texture"]:
            t = m["texture"]
            if t not in done_tex:
                with zf.open(infos[texs[t]]) as src, open(os.path.join(out_dir, t + ".png"), "wb") as dst:
                    shutil.copyfileobj(src, dst)
                done_tex[t] = f"items/{t}.png"
            entry["texture"] = done_tex[t]
        index[name] = entry
    with open(index_out, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=1)
    print(f"物品模型: {len(index)} 个（带贴图 {sum(1 for e in index.values() if 'texture' in e)} 个）")


# —— 场景：市中心街道上的车辆、容器、杂物，地面贴图 ——
# (资源包, 网格名, 贴图名, 类别, 中文名, 战利品类型)
# 类别：loot=能翻找的容器  car=车（能翻找、挡路）  prop=摆设（挡路）  small=小摆设（不挡路）
# 战利品类型：trash 垃圾 food 食物 drink 饮料 medical 药品 weapon 武器 tool 工具 any 随便
WORLD_ENT = "小橘素材库/automatic_assets_entities"
WORLD_MODELS = [
    ("lootcontainers", "bruteStyleTrashCanFull_1", "bruteStyleTrashCan_d", "loot", "垃圾桶", "trash"),
    ("lootcontainers", "domedTrashCanFull_1", "domedTrashCan_d", "loot", "垃圾桶", "trash"),
    ("lootcontainers", "fancyGarbageCan_1", "fancyGarbageCan_d", "loot", "垃圾桶", "trash"),
    ("lootcontainers", "Dumpster_LOD0", "dumpster_d", "loot", "大垃圾箱", "trash"),
    ("lootcontainers", "trashPileA_1", "trashPile", "loot", "垃圾堆", "trash"),
    ("lootcontainers", "trashPileC_1", "trashPile", "loot", "垃圾堆", "trash"),
    ("lootcontainers", "trashPileE_LOD0", "trashPile", "loot", "垃圾堆", "trash"),
    ("lootcontainers", "backPack_LOD0", "backpack_dropped_green", "loot", "背包", "any"),
    ("lootcontainers", "duffle_LOD0", "duffleBag_d", "loot", "旅行袋", "any"),
    ("lootcontainers", "sportsBag_LOD0", "sportsBag_d", "loot", "运动包", "any"),
    ("lootcontainers", "purse_LOD0", "purse_d", "loot", "手提包", "medical"),
    ("lootcontainers", "weaponBag_sm_1", "weaponBags_d", "loot", "武器包", "weapon"),
    ("lootcontainers", "tier1LootChest_LOD0", "tier1LootChest_d", "loot", "木箱", "any"),
    ("lootcontainers", "superChest_1", "superChest_d", "loot", "大箱子", "weapon"),
    ("lootcontainers", "shippingCrate_LOD0", "shippingCrate", "loot", "货箱", "tool"),
    ("lootcontainers", "gasGrillFull_1", "GasGrill_d", "loot", "烤架", "food"),
    ("lootcontainers", "groceryCartFull_LOD0", "groceryCart_d", "loot", "购物车", "food"),
    ("lootcontainers", "foodClutterPileMedium_01_LOD0", "foodClutterPile_d", "loot", "食物堆", "food"),
    ("lootcontainers", "tiltTruckFull_1", "tiltTruck_d", "loot", "手推车", "tool"),
    ("lootcontainers", "utilityCartFull_1", "utilityCart_d", "loot", "工具车", "tool"),
    ("lootcontainers", "waterCoolerFull_1", "waterCooler_d", "loot", "饮水机", "drink"),
    ("lootcontainers", "mailBox_01_LOD0", "mailBox_01", "loot", "邮箱", "any"),
    ("lootcontainers", "mailBox_03_LOD0", "mailBox_03", "loot", "邮箱", "any"),
    ("lootcontainers", "cashRegisterClosed_LOD0", "cashRegister_d", "loot", "收银机", "any"),
    ("commercial", "vendingMachinePlayer_LOD0", "vendingMachinePlayer", "loot", "自动售货机", "drink"),
    ("commercial", "janitorCart_1", "janitorCart", "loot", "清洁车", "tool"),
    ("commercial", "trashBinCommercial_LOD0", "trashBinCommercial_d", "loot", "垃圾桶", "trash"),
    ("industrial", "gasPumpFull_LOD0", "GasPump_d", "loot", "加油机", "tool"),
    ("vehicles", "sedan_LOD1", "sedan", "car", "轿车", "any"),
    ("vehicles", "suv_LOD1", "suv", "car", "越野车", "any"),
    ("vehicles", "policeCar_LOD1", "policeCar", "car", "警车", "weapon"),
    ("vehicles", "burntSedan_LOD0", "burntSedan", "car", "烧毁的车", "trash"),
    ("vehicles", "miniVan_LOD0", "miniVan", "car", "面包车", "any"),
    ("vehicles", "pickUpTruck._LOD0", "pickupTruck", "car", "皮卡", "tool"),
    ("vehicles", "frontCrumpledSedan_LOD0", "frontCrumpledSedan", "car", "撞毁的车", "any"),
    ("vehicles", "abandonedSUV_LOD0", "suv", "car", "废弃越野车", "any"),
    ("vehicles", "bus_city_LOD0", "bus_city", "car", "公交车", "any"),
    ("industrial", "barrierConcrete_LOD0", "barrierConcrete", "prop", "水泥路障", ""),
    ("industrial", "barrierPlastic_LOD0", "barrierPlastic", "prop", "路障", ""),
    ("industrial", "palletsWoodStack", "palletsWood", "prop", "木托盘", ""),
    ("industrial", "boxesCardboardPallet_LOD0", "boxesCardboard", "prop", "纸箱", ""),
    ("industrial", "palletBagSandBaseFull_LOD0", "palletBag_d", "prop", "沙袋", ""),
    ("industrial", "plasticBin_LOD0", "plasticBin_01_d", "small", "塑料箱", ""),
    ("outdoordecor", "brickStack_LOD0", "brickStack_d", "prop", "砖堆", ""),
    ("outdoordecor", "cinderBlock02_LOD0", "cinderBlock_d", "small", "空心砖", ""),
    ("outdoordecor", "plywoodStack_LOD0", "plyWoodStack_d", "prop", "胶合板", ""),
    ("outdoordecor", "cardboardRecycledPallet_LOD0", "cardboardRecycled_d", "prop", "废纸板", ""),
    ("outdoordecor", "campingTentAngularDamaged_LOD0", "campingTentAngular_d", "prop", "破帐篷", ""),
    ("outdoordecor", "guardRailLong_LOD0", "guardRail", "prop", "护栏", ""),
    ("commercial", "umbrellaTableDown_LOD0", "umbrellaTableDown", "prop", "遮阳伞桌", ""),
    ("commercial", "handTruck_1", "handTruck", "small", "手推车", ""),
    ("furniture", "couchUglySmall_LOD0", "couchUglySmall_d", "prop", "沙发", ""),
    ("furniture", "picnicTable_1", "picnicTable", "prop", "野餐桌", ""),
    ("furniture", "wheelChair_LOD0", "wheelChair", "small", "轮椅", ""),
    ("furniture", "chairFoldingMetalFoldedFallen_LOD0", "chairFoldingMetal", "small", "折叠椅", ""),
    ("debris", "trashGround02_LOD0", "groundTrash_d", "small", "垃圾", ""),
    ("debris", "trashGround03_LOD0", "groundTrash_d", "small", "垃圾", ""),
    ("gore", "corpseHangingLog1_LOD0", "corpseHangingLog1", "prop", "吊着的尸体", ""),
    ("buildings", "awningStraight_LOD0", "awning", "deco", "遮阳棚", ""),
]
# 地上的贴花（血迹、垃圾、报纸）
WORLD_DECALS = ("debris", ["decal_blood", "decal_blood02", "decal_blood05", "decal_blood06", "decal_rubbish01",
                           "decal_rubbish03", "decal_rubbish05", "decal_rubbish08", "decal_rubbish12",
                           "decal_newspaper", "decal_newspaper02", "BurntPaperDebris_d", "tornPaperDebris_d"])
# 地面和楼的贴图
TERRAIN_TEXTURES = ["asphalt", "concrete", "sidewalk_terrain", "gravel", "dirt", "rubble", "forest_ground",
                    "burnt_forest_ground", "desert_debris"]
BUILDING_TEXTURES = [("prefabs_assets_all.zip", "Concrete_Diffuse"), ("debris", "concreteRubbleTile_d"),
                     ("commercial", "windowGrunge_d"), ("buildings", "window_store"),
                     ("buildings", "windowStoreFrame_d"), ("debris", "rubbleConcreteSlab_d")]
WORLD_TEX_MAX = 1024


def _save_png(data, out, max_size=WORLD_TEX_MAX):
    """贴图缩到 max_size 以内（手机内存有限）；没装 Pillow 就原样保存。"""
    try:
        from PIL import Image
        im = Image.open(io.BytesIO(data))
        if max(im.size) > max_size:
            im.thumbnail((max_size, max_size), Image.LANCZOS)
        im.save(out, optimize=False)
    except ImportError:
        with open(out, "wb") as f:
            f.write(data)


def _zip_members(zf):
    meshes, texs = {}, {}
    for i in zf.infolist():
        base = os.path.basename(i.filename)
        if i.filename.startswith("meshes/") and base.endswith(".obj"):
            meshes[base[:-4]] = i
        elif i.filename.startswith("textures/") and base.endswith(".png"):
            texs[base[:-4]] = i
    return meshes, texs


def fetch_world(dest):
    index_out = os.path.join(dest, "index", "world_models.json")
    if os.path.exists(index_out):
        print("市中心场景: 已有，跳过（删掉 assets/index/world_models.json 可重新取）")
        return
    out_dir = os.path.join(dest, "world")
    os.makedirs(os.path.join(out_dir, "decals"), exist_ok=True)
    os.makedirs(os.path.join(dest, "index"), exist_ok=True)
    zips, members = {}, {}

    def open_zip(name):
        if name not in zips:
            path = f"{DRIVE_ROOT}/小橘素材库/{name}" if name.endswith(".zip") else f"{DRIVE_ROOT}/{WORLD_ENT}/{name}.zip"
            zips[name] = open_remote_zip(path)
            members[name] = _zip_members(zips[name]) if zips[name] else ({}, {})
        return zips[name], members[name]

    index, done_tex = {"models": {}, "decals": [], "textures": {}}, {}
    for pack, mesh, tex, kind, cn, loot in WORLD_MODELS:
        zf, (meshes, texs) = open_zip(pack)
        if zf is None or mesh not in meshes:
            print(f"  没找到 {pack}/{mesh}，跳过")
            continue
        stem = re.sub(r"[^A-Za-z0-9_]", "_", mesh)
        with open(os.path.join(out_dir, stem + ".obj"), "wb") as f:
            f.write(zf.read(meshes[mesh]))
        entry = {"mesh": f"world/{stem}.obj", "kind": kind, "name": cn, "loot": loot}
        if tex in texs:
            if tex not in done_tex:
                _save_png(zf.read(texs[tex]), os.path.join(out_dir, tex + ".png"))
                done_tex[tex] = f"world/{tex}.png"
            entry["texture"] = done_tex[tex]
        index["models"][stem] = entry
    pack, names = WORLD_DECALS
    zf, (_, texs) = open_zip(pack)
    for n in names:
        if zf and n in texs:
            _save_png(zf.read(texs[n]), os.path.join(out_dir, "decals", n + ".png"), 512)
            index["decals"].append(f"world/decals/{n}.png")
    zf = open_remote_zip(f"{DRIVE_ROOT}/小橘素材库/terraintextures_assets_all.zip")
    if zf:
        _, texs = _zip_members(zf)
        for n in TERRAIN_TEXTURES:
            if n in texs:
                _save_png(zf.read(texs[n]), os.path.join(out_dir, n + ".png"))
                index["textures"][n] = f"world/{n}.png"
    for pack, n in BUILDING_TEXTURES:
        zf, (_, texs) = open_zip(pack)
        if zf and n in texs:
            _save_png(zf.read(texs[n]), os.path.join(out_dir, n + ".png"))
            index["textures"][n] = f"world/{n}.png"
    with open(index_out, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=1)
    print(f"市中心场景: 模型 {len(index['models'])} 个，贴花 {len(index['decals'])} 张，贴图 {len(index['textures'])} 张")


def fetch_poi(dest):
    """市中心建筑（七日杀的 POI 预制体）：取远景网格 .mesh 和属性 .xml。
    .mesh（存成 .poimesh）之后由 tools/build_poi.gd 在 Godot 里转成 assets/poi/*.res。"""
    out_dir = os.path.join(dest, "poi")
    if os.path.isdir(out_dir) and any(f.endswith(".poimesh") for f in os.listdir(out_dir)):
        print("市中心建筑: 已有，跳过")
        return
    zf = open_remote_zip(f"{DRIVE_ROOT}/建筑POI/POIs_downtown_67.zip")
    if zf is None:
        print("云盘里没有 建筑POI/POIs_downtown_67.zip，市中心只有街道")
        return
    os.makedirs(out_dir, exist_ok=True)
    n = 0
    for i in zf.infolist():
        base = os.path.basename(i.filename)
        if re.fullmatch(r"[A-Za-z0-9_]+\.(mesh|xml)", base):
            # .mesh 和 Godot 自己的网格格式重名，改个扩展名免得 Godot 误读
            out = os.path.join(out_dir, base[:-5] + ".poimesh" if base.endswith(".mesh") else base)
            with zf.open(i) as src, open(out, "wb") as dst:
                shutil.copyfileobj(src, dst)
            n += base.endswith(".mesh")
    print(f"市中心建筑: {n} 栋")


# 样例文件夹里的现成素材：(云盘目录, 本地子目录, 文件筛选)
SAMPLE_SOURCES = [
    ("样例/models/items", "models", lambda n: n.lower().endswith(".glb")),          # 物品模型
    ("样例/models/common", "models", lambda n: n.startswith("FP_ARM") and n.endswith(".glb")),  # 第一人称手臂
    ("样例/textures/common", "textures", lambda n: n in ("HD_Hands_Male.png", "playerMale_Hand.png")),  # 手臂贴图
]


def fetch_samples(dest):
    for folder, sub, keep in SAMPLE_SOURCES:
        try:
            files = list_dir(f"{DRIVE_ROOT}/{folder}")
        except Exception as e:  # noqa: BLE001
            print(f"读取 {folder} 失败: {e}")
            continue
        n = 0
        for it in files:
            if it["type"] == "file" and keep(it["name"]) and it.get("size", 0) > 10_000:
                if download(it, os.path.join(dest, sub, it["name"])):
                    n += 1
        print(f"{folder} → assets/{sub}/: 新下载 {n} 个")


MUSIC_RE = re.compile(r"^(\d+)([a-z]?)(Exp|Cbt|Sus|Bld)(Pri|Sec|Psp|Lfx|Pp1|Sfx)(Hi|Lo)?\.wav$", re.I)


def fetch_music(dest, per_kind):
    files = [f for f in list_dir(f"{DRIVE_ROOT}/音乐") if f["name"].lower().endswith(".wav")]
    by_kind = {}
    for f in files:
        m = MUSIC_RE.match(f["name"])
        if not m:
            continue
        num, var, kind, layer, hilo = m.groups()
        # 七日杀的动态音乐是分层的，Pri 是主旋律层，单独播放效果最好
        if layer.lower() != "pri" or (hilo and hilo.lower() != "hi"):
            continue
        by_kind.setdefault(kind.capitalize(), []).append(f)
    total = 0
    for kind, lst in sorted(by_kind.items()):
        lst.sort(key=lambda f: f["name"])
        step = max(1, len(lst) // per_kind)
        chosen = lst[::step][:per_kind]
        for f in chosen:
            if download(f, os.path.join(dest, "music", f["name"])):
                total += f["size"]
        print(f"音乐 {kind}: {len(chosen)} 段")
    print(f"音乐新下载 {mb(total)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dest", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets"))
    ap.add_argument("--zombies", default=",".join(DEFAULT_ZOMBIES), help="逗号分隔的僵尸名，或 all")
    ap.add_argument("--music", type=int, default=6, help="每类音乐取几段")
    ap.add_argument("--all-icons", action="store_true", help="取全部图标（默认只取游戏会用到的）")
    ap.add_argument("--skip", default="", help="跳过某些步骤，逗号分隔: icons,zombies,samples,items,arms,world,poi,music")
    args = ap.parse_args()
    skip = set(filter(None, args.skip.split(",")))
    dest = os.path.abspath(args.dest)
    print("素材目录:", dest)
    rows = fetch_index(dest)
    if "icons" not in skip:
        fetch_icons(dest, rows, args.all_icons)
    if "zombies" not in skip:
        fetch_zombies(dest, [z.strip() for z in args.zombies.split(",") if z.strip()])
    if "samples" not in skip:
        fetch_samples(dest)
    if "items" not in skip:
        fetch_items(dest, rows)
    if "arms" not in skip:
        fetch_fp_arms(dest)
    if "world" not in skip:
        fetch_world(dest)
    if "poi" not in skip:
        fetch_poi(dest)
    if "music" not in skip:
        fetch_music(dest, args.music)
    print("完成。用 Godot 打开项目即可（第一次打开会导入素材，需要几分钟）。")


if __name__ == "__main__":
    main()
