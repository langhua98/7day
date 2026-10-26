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
    assets/vehicles/*.glb/.obj/.png    （可驾驶载具：自行车、小摩托、4x4、旋翼机）
    assets/world/bedroll.obj/.png      （睡袋，从 respawnpoints.zip 取）
    assets/poi/*.poimesh/.xml          （市中心建筑，再用 tools/build_poi.gd 转成 .res）
    assets/poi/*.tts/.nim → *.full     （完整方块数据，tools/build_poi_full.py 生成路口几栋楼的完整网格）
    assets/blocks/*.xml、assets/shapes/*.glb（游戏的方块表、形状表、刷漆表和形状模型）
    assets/blocks/c_*.png n_*.png      （楼用到的方块贴图和法线，atlas.json 是贴图编号 → 层号；
                                        tools/build_poi.gd 再打包成 assets/poi/atlas_*.res）
    assets/terrain/*.png               （地面贴图：颜色、法线、粗糙度）
    assets/textures/*.png              （地面贴图）
    assets/effects/*.png               （枪口火光、血雾、火花）
    assets/music/*.wav                 （文件名里 Exp=探索 Cbt=战斗 Sus=紧张 Bld=血月）

只用 Python 自带库（装了 Pillow 会把场景贴图缩到 1024，省手机内存）。已存在且大小一致的文件会跳过，可以反复运行。
"""
import argparse
import http.client
import io
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import zipfile

API = os.environ.get("XIAOJU_API", "https://langhua1998-xiaoju-cloud.hf.space/api/agent/v1")
DRIVE_ROOT = "/7day"
# 工作站模型：crafting.zip 里是分件 OBJ（不是预制体 GLB），先取每个工作站的主网格和贴图
STATION_MODELS = {
    "campfire": ("campfireWoodLogs_LOD0.obj", "campfire.png"),
    "workbench": ("woodWorkBench_LOD0.obj", "woodWorkBench.png"),
    "forge": ("forgeWorkstation_LOD0.obj", "forgeWorkstation.png"),
    "chemistryStation": ("ChemSetB.obj", "chemistryStation.png"),
    "cementMixer": ("cementMixerBody_LOD0.obj", "cementMixer.png"),
}
## 刷怪表用到的全部僵尸模型（不含暂时不刷的 dog）
DEFAULT_ZOMBIES = ["arlene", "bigmama", "biker", "boe", "burnt", "chuck", "cocktailwaitress",
    "cop", "crawler", "darlene", "demolition", "frostclaw", "hawaiian", "joe", "lab", "lumberjack",
    "marlene", "moe", "mutated", "nurse", "plaguespitter", "rancher", "screamer", "soldier", "spider",
    "steve", "suit", "tomclark", "wight", "worker", "yo"]
## 玩家方块形状：按形状名/ 下的官方 glb，运行时由 build_block_shapes.py 转成 JSON
BLOCK_SHAPE_FILES = ("cube.glb", "cubeHalf.glb", "ramp.glb", "stairs.glb", "pole.glb", "plate.glb")
# 游戏会用到的物品前缀（图标太多，只取这些，--all-icons 可以全取）
GAME_PREFIXES = ("melee", "gun", "food", "drink", "medical", "resource", "ammo", "armor", "apparel", "thrown", "tool", "vehicle")
## blocks.xml 的 CustomIcon：尖刺方块用 Master 的图标；图标包里有，但不在物品索引里
BLOCK_ICON_ALIASES = {
    "trapSpikesWoodMaster": "trapSpikesWoodDmg0",
    "trapSpikesScrapIronMaster": "trapSpikesIronDmg0",
}
FLAGSTONE_TEXTURE_ID = 226


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
        except (OSError, http.client.HTTPException) as e:
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


def ensure_fallback_icons(out_dir):
    """云盘物品图标没有 flagstoneShapes；用官方方块贴图 c_226 生成图标；没有就画个石头。"""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("图标: 没有 Pillow，跳过领地石/尖刺/石板兜底图标")
        return

    def save(name, painter):
        path = os.path.join(out_dir, name + ".png")
        if os.path.exists(path):
            return
        img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        painter(ImageDraw.Draw(img), img)
        img.save(path)

    flagstone = os.path.join(os.path.dirname(out_dir), "blocks", "c_%03d.png" % FLAGSTONE_TEXTURE_ID)
    if os.path.exists(flagstone):
        try:
            img = Image.open(flagstone).convert("RGBA").resize((64, 64), Image.Resampling.LANCZOS)
            d = ImageDraw.Draw(img)
            d.rounded_rectangle((1, 1, 62, 62), 4, outline=(70, 66, 60, 255), width=3)
            img.save(os.path.join(out_dir, "flagstoneShapes.png"))
            return
        except Exception:
            pass
    def stone(d, _img):
        d.rounded_rectangle((2, 10, 62, 58), 3, fill=(125, 120, 112, 255), outline=(70, 66, 60, 255), width=2)
        for x in (16, 32, 48):
            d.line((x, 12, x, 56), fill=(88, 84, 78, 255), width=2)
        d.line((4, 33, 60, 33), fill=(88, 84, 78, 255), width=2)
    save("flagstoneShapes", stone)


def fetch_icons(dest, rows, all_icons):
    wanted = {r[0] for r in rows if r and r[0]}
    if not all_icons:
        wanted = {w for w in wanted if w.lower().startswith(GAME_PREFIXES)}
    out_dir = os.path.join(dest, "icons")
    os.makedirs(out_dir, exist_ok=True)
    have = {os.path.splitext(f)[0] for f in os.listdir(out_dir)}
    alias_target = {src: dst for src, dst in BLOCK_ICON_ALIASES.items()}
    alias_missing = {dst for dst in alias_target.values() if dst not in have}
    if wanted <= have and not alias_missing:
        print(f"图标: 已有 {len(wanted)} 个，跳过")
        ensure_fallback_icons(out_dir)
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
                    if ext.lower() != ".png":
                        continue
                    if stem in alias_target:
                        target = alias_target[stem] + ".png"
                        with zf.open(info) as src, open(os.path.join(out_dir, target), "wb") as dst:
                            shutil.copyfileobj(src, dst)
                        n += 1
                    elif stem in wanted:
                        with zf.open(info) as src, open(os.path.join(out_dir, base), "wb") as dst:
                            shutil.copyfileobj(src, dst)
                        n += 1
            print(f"图标: 解出 {n} 个")
    ensure_fallback_icons(out_dir)


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
            except (OSError, http.client.HTTPException) as e:
                print(f"  读取中断（{e}），重试 …")
                time.sleep(2 ** attempt)
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
# 战利品：官方 lootcontainer 名（loot.xml）；prop/small/deco 不能翻，最后一列留空
WORLD_ENT = "小橘素材库/automatic_assets_entities"
WORLD_MODELS = [
    ("lootcontainers", "bruteStyleTrashCanFull_1", "bruteStyleTrashCan_d", "loot", "垃圾桶", "garbage"),
    ("lootcontainers", "domedTrashCanFull_1", "domedTrashCan_d", "loot", "垃圾桶", "garbage"),
    ("lootcontainers", "fancyGarbageCan_1", "fancyGarbageCan_d", "loot", "垃圾桶", "garbage"),
    ("lootcontainers", "Dumpster_LOD0", "dumpster_d", "loot", "大垃圾箱", "dumpster"),
    ("lootcontainers", "trashPileA_1", "trashPile", "loot", "垃圾堆", "junk"),
    ("lootcontainers", "trashPileC_1", "trashPile", "loot", "垃圾堆", "junk"),
    ("lootcontainers", "trashPileE_LOD0", "trashPile", "loot", "垃圾堆", "junk"),
    ("lootcontainers", "backPack_LOD0", "backpack_dropped_green", "loot", "背包", "cntBackpack"),
    ("lootcontainers", "duffle_LOD0", "duffleBag_d", "loot", "旅行袋", "luggage"),
    ("lootcontainers", "sportsBag_LOD0", "sportsBag_d", "loot", "运动包", "luggage"),
    ("lootcontainers", "purse_LOD0", "purse_d", "loot", "手提包", "purse"),
    ("lootcontainers", "weaponBag_sm_1", "weaponBags_d", "loot", "武器包", "weaponsBagSmall"),
    ("lootcontainers", "tier1LootChest_LOD0", "tier1LootChest_d", "loot", "木箱", "woodenChest"),
    ("lootcontainers", "superChest_1", "superChest_d", "loot", "大箱子", "reinforcedChestT1"),
    ("lootcontainers", "shippingCrate_LOD0", "shippingCrate", "loot", "货箱", "garage"),
    ("lootcontainers", "gasGrillFull_1", "GasGrill_d", "loot", "烤架", "gasGrill"),
    ("lootcontainers", "groceryCartFull_LOD0", "groceryCart_d", "loot", "购物车", "shoppingCart"),
    ("lootcontainers", "foodClutterPileMedium_01_LOD0", "foodClutterPile_d", "loot", "食物堆", "foodPileMed"),
    ("lootcontainers", "tiltTruckFull_1", "tiltTruck_d", "loot", "手推车", "utilityCart"),
    ("lootcontainers", "utilityCartFull_1", "utilityCart_d", "loot", "工具车", "utilityCart"),
    ("lootcontainers", "waterCoolerFull_1", "waterCooler_d", "loot", "饮水机", "waterCooler"),
    ("lootcontainers", "mailBox_01_LOD0", "mailBox_01", "loot", "邮箱", "mailbox"),
    ("lootcontainers", "mailBox_03_LOD0", "mailBox_03", "loot", "邮箱", "mailbox"),
    ("lootcontainers", "cashRegisterClosed_LOD0", "cashRegister_d", "loot", "收银机", "cashRegister"),
    ("commercial", "vendingMachinePlayer_LOD0", "vendingMachinePlayer", "loot", "自动售货机", "cooler"),
    ("commercial", "janitorCart_1", "janitorCart", "loot", "清洁车", "utilityCart"),
    ("commercial", "trashBinCommercial_LOD0", "trashBinCommercial_d", "loot", "垃圾桶", "garbage"),
    ("industrial", "gasPumpFull_LOD0", "GasPump_d", "loot", "加油机", "gasPump"),
    ("vehicles", "sedan_LOD1", "sedan", "car", "轿车", "cars"),
    ("vehicles", "suv_LOD1", "suv", "car", "越野车", "cars"),
    ("vehicles", "policeCar_LOD1", "policeCar", "car", "警车", "policeCars"),
    ("vehicles", "burntSedan_LOD0", "burntSedan", "car", "烧毁的车", "cars"),
    ("vehicles", "miniVan_LOD0", "miniVan", "car", "面包车", "cars"),
    ("vehicles", "pickUpTruck._LOD0", "pickupTruck", "car", "皮卡", "cars"),
    ("vehicles", "frontCrumpledSedan_LOD0", "frontCrumpledSedan", "car", "撞毁的车", "cars"),
    ("vehicles", "abandonedSUV_LOD0", "suv", "car", "废弃越野车", "cars"),
    ("vehicles", "bus_city_LOD0", "bus_city", "car", "公交车", "cars"),
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


# —— 可驾驶载具 ——
# 自行车和旋翼机用云盘样例里的 glb（glb 里只有 2×2 占位贴图，游戏里用纯色）；小摩托和 4x4 从 vehicles.zip 取分件和贴图
VEHICLE_SAMPLES = [("bike_LOD0.glb", "bike.glb"), ("gyrocopter_LOD0.glb", "gyrocopter.glb")]
VEHICLE_ZIP_FILES = {
    "minibike_LOD0.obj": "minibike.obj",
    "minibike.png": "minibike.png",
    "4X4body_LOD0.obj": "4x4_body.obj",
    "4X4undercarriage_LOD0.obj": "4x4_under.obj",
    "4X4hood_LOD0.obj": "4x4_hood.obj",
    "4X4doorL_LOD0.obj": "4x4_door_l.obj",
    "4X4doorR_LOD0.obj": "4x4_door_r.obj",
    "4X4tailGate_LOD0.obj": "4x4_tailgate.obj",
    "4X4headLight_LOD0.obj": "4x4_headlight.obj",
    "4X4steeringWheel_LOD0.obj": "4x4_wheel_steer.obj",
    "4X4truckWheels_LOD0.obj": "4x4_wheel.obj",
    "4X4truck.png": "4x4.png",
}


def fetch_vehicles(dest):
    out_dir = os.path.join(dest, "vehicles")
    os.makedirs(out_dir, exist_ok=True)
    folder = f"{DRIVE_ROOT}/样例/models/vehicles"
    samples = {os.path.splitext(i["name"])[0]: i for i in list_dir(folder)}
    for src, dst_name in VEHICLE_SAMPLES:
        it = samples.get(os.path.splitext(src)[0])
        out = os.path.join(out_dir, dst_name)
        if it is None:
            print(f"  云盘样例里没有 {src}，跳过")
        elif os.path.exists(out) and os.path.getsize(out) == it.get("size"):
            print(f"载具 {dst_name}: 已有，跳过")
        else:
            print(f"载具 {dst_name}: 下载 …")
            download(it, out)
    zf = open_remote_zip(f"{DRIVE_ROOT}/{WORLD_ENT}/vehicles.zip")
    if zf is None:
        print("云盘里没有 vehicles.zip，跳过小摩托和 4x4")
        return
    members = {}
    for info in zf.infolist():
        members[os.path.basename(info.filename)] = info
    for src, dst_name in VEHICLE_ZIP_FILES.items():
        info = members.get(src)
        out = os.path.join(out_dir, dst_name)
        if info is None:
            print(f"  vehicles.zip 里没有 {src}，跳过")
            continue
        if dst_name.endswith(".png"):
            # 官方载具贴图是 4K，装了 Pillow 就缩到 1024，省手机内存
            if os.path.exists(out) and os.path.getsize(out) < 4_000_000:
                continue
            _save_png(zf.read(info), out, 1024)
            continue
        if os.path.exists(out) and os.path.getsize(out) == info.file_size:
            continue
        with zf.open(info) as fsrc, open(out, "wb") as fdst:
            shutil.copyfileobj(fsrc, fdst)
    zf.close()
    print(f"载具模型: → {os.path.relpath(out_dir)}")


# 睡袋（3c）：automatic_assets_entities/respawnpoints.zip 里按名字找网格和贴图
RESPAWN_MODELS = [("bedroll", r"bedroll|sleepingbag"), ("corpse_bag", r"backpack")]


def fetch_respawn(dest):
    out_dir = os.path.join(dest, "world")
    if os.path.exists(os.path.join(out_dir, "bedroll.obj")):
        print("睡袋: 已有，跳过")
        return
    zf = open_remote_zip(f"{DRIVE_ROOT}/{WORLD_ENT}/respawnpoints.zip")
    if zf is None:
        print("云盘里没有 respawnpoints.zip，睡袋用纯色方块")
        return
    os.makedirs(out_dir, exist_ok=True)
    meshes, texs = _zip_members(zf)

    def best(names, pat):
        hits = [n for n in names if re.search(pat, n, re.I)]
        # 优先 LOD0、名字短的
        hits.sort(key=lambda n: ("lod0" not in n.lower(), re.search(r"lod[1-9]", n, re.I) is not None, len(n)))
        return hits[0] if hits else None

    for out, pat in RESPAWN_MODELS:
        m = best(meshes, pat)
        if not m:
            print(f"  respawnpoints.zip 里没找到 {out}（{pat}），先用纯色顶上")
            continue
        with open(os.path.join(out_dir, out + ".obj"), "wb") as f:
            f.write(zf.read(meshes[m]))
        stem = re.sub(r"_?LOD\d+$", "", m, flags=re.I)
        t = best([n for n in texs if not re.search(r"_(n|normal|s|spec|mask)$", n, re.I)], re.escape(stem)) or best(texs, pat)
        if t:
            _save_png(zf.read(texs[t]), os.path.join(out_dir, out + ".png"))
        print(f"  {out}: {m}" + (f" + {t}" if t else "（没贴图）"))


def fetch_poi(dest):
    """市中心建筑（七日杀的 POI 预制体）：取远景网格 .mesh、属性 .xml，以及完整方块数据 .tts 和方块名表 .blocks.nim
    （存成 .nim）。.mesh（存成 .poimesh）之后由 tools/build_poi.gd 在 Godot 里转成 assets/poi/*.res。"""
    out_dir = os.path.join(dest, "poi")
    if os.path.isdir(out_dir) and any(f.endswith(".tts") for f in os.listdir(out_dir)):
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
        if re.fullmatch(r"[A-Za-z0-9_]+\.(mesh|xml|tts|blocks\.nim)", base):
            # .mesh 和 Godot 自己的网格格式重名，改个扩展名免得 Godot 误读
            if base.endswith(".mesh"):
                base = base[:-5] + ".poimesh"
            elif base.endswith(".blocks.nim"):
                base = base[:-11] + ".nim"
            out = os.path.join(out_dir, base)
            with zf.open(i) as src, open(out, "wb") as dst:
                shutil.copyfileobj(src, dst)
            n += base.endswith(".poimesh")
    print(f"市中心建筑: {n} 栋")


# —— 楼和地面的真实贴图 ——
# 方块贴图：图集 ta_opaque 有 407 层（每层是一个方块面），对照表 ta_opaquexml 里每条
# <uv id index blockw blockh>：id 是网格里记的贴图编号，index 是起始层；大贴图占 blockw×blockh 层（按行排）。
BLOCK_ZIP = "小橘素材库/blocktextureatlases_assets_all.zip"
BLOCK_MAP = "小橘素材库/meshdescriptions_textassets"
BLOCK_TEX = 256        # 每层缩到 256（一个方块 1 米，够清楚，也省手机内存）
# 地形贴图数组（MicroSplat）：24 层，颜色 / 法线（x 在 A、y 在 G）/ 光滑度+AO（G、A）。
# 层号是和 terraintextures_assets_all 里的单张贴图逐一比对出来的；tile = 几米重复一次（ta_terrainxml 的 blockw）。
TERRAIN_ZIP = "小橘素材库/terraintextures_arrays.zip"
TERRAIN_LAYERS = {"asphalt": (4, 8), "concrete": (6, 4), "gravel": (5, 8), "dirt": (9, 8), "rubble": (8, 8),
                  "forest_ground": (2, 8), "burnt_forest_ground": (10, 8), "desert_debris": (11, 8)}
TERRAIN_TEX = 1024
# 能自己摆的建造方块（scripts/blocks.gd 里的同名表）：从游戏的 blocks.xml 查它们用哪张贴图
BLOCKS_XML = "小橘素材库/config"
BUILD_BLOCKS = ["frameShapes", "woodShapes", "cobblestoneShapes", "concreteShapes", "steelShapes", "flagstoneShapes"]


def _build_block_textures():
    """建造方块名 → 贴图编号（blocks.xml 里的 Texture 属性，没有就顺着 Extends 往上找）"""
    it = find(list_dir(f"{DRIVE_ROOT}/{BLOCKS_XML}"), "blocks.xml")
    if not it:
        print("云盘里没有 config/blocks.xml，建造方块用纯色")
        return {}
    with request(f"/items/{it['id']}/content") as r:
        xml = r.read().decode("utf-8-sig", "replace")
    tex, ext = {}, {}
    for m in re.finditer(r'<block\s+name="([^"]+)"(.*?)</block>', xml, re.S):
        name, body = m.group(1), m.group(2)
        t = re.search(r'name="Texture"\s+value="([^"]*)"', body)
        if t:
            nums = re.findall(r"\d+", t.group(1))
            if nums:
                tex[name] = int(nums[0])
        e = re.search(r'name="Extends"\s+value="([^"]*)"', body)
        if e:
            ext[name] = e.group(1).split(",")[0].strip()
    out = {}
    for name in BUILD_BLOCKS:
        n, hops = name, 0
        while n and n not in tex and hops < 8:
            n, hops = ext.get(n), hops + 1
        if n in tex:
            out[name] = tex[n]
    print(f"建造方块贴图: {len(out)}/{len(BUILD_BLOCKS)} 种在 blocks.xml 里找到")
    return out


def _poi_tex_ids(poi_dir):
    """市中心建筑网格里用到的贴图编号（格式见 tools/build_poi.gd）"""
    import struct
    ids = set()
    for f in os.listdir(poi_dir):
        if not f.endswith(".poimesh"):
            continue
        data = open(os.path.join(poi_dir, f), "rb").read()
        if data[:4] != b"hsem":
            continue
        p, chunks = 7, struct.unpack_from("<H", data, 5)[0]
        for _ in range(chunks):
            p += 1 + data[p]
            nv = struct.unpack_from("<I", data, p)[0]
            p += 4 + nv * 12
            na = struct.unpack_from("<I", data, p)[0]
            p += 4
            ids.update(struct.unpack_from("<H", data, p + k * 8)[0] for k in range(na))
            p += na * 8
            ni = struct.unpack_from("<I", data, p)[0]
            p += 4 + ni * 2
    return ids


def _unpack_normal(im, size):
    """Unity 的打包法线（x 在 A 通道、y 在 G 通道）→ 普通 RGB 法线图"""
    from PIL import Image
    im = im.convert("RGBA")
    if max(im.size) > size:
        im = im.resize((size, size), Image.LANCZOS)
    _, g, _, a = im.split()
    xs, ys = a.tobytes(), g.tobytes()
    zs = bytearray(len(xs))
    for i in range(len(xs)):
        x, y = xs[i] / 127.5 - 1.0, ys[i] / 127.5 - 1.0
        zs[i] = int((max(0.0, 1.0 - x * x - y * y) ** 0.5 * 0.5 + 0.5) * 255)
    return Image.merge("RGB", (a, g, Image.frombytes("L", im.size, bytes(zs))))


# 市中心路口那几栋用完整方块数据生成（窗户、楼梯、屋檐都有），其余的楼用远景网格
CONFIG_ZIP = "小橘素材库/Data_Config.zip"
SHAPES_ZIP = "小橘素材库/shapes_by_name.zip"
UI_ZIP = "小橘素材库/textures_assets_textures/ui.zip"


def _zip_name(info):
    """压缩包里的文件名：没标 UTF-8 的按 UTF-8 / GBK 还原（Python 默认当 cp437 读）"""
    name = info.filename
    if info.flag_bits & 0x800:
        return name
    raw = name.encode("cp437", "replace")
    for enc in ("utf-8", "gbk"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            pass
    return name


def fetch_full_buildings(dest):
    """游戏的方块表、形状表、刷漆表和形状模型，然后用 tools/build_poi_full.py 生成完整的楼（assets/poi/*.full）"""
    bdir = os.path.join(dest, "blocks")
    sdir = os.path.join(dest, "shapes")
    os.makedirs(bdir, exist_ok=True)
    if not all(os.path.exists(os.path.join(bdir, f)) for f in ("blocks.xml", "shapes.xml", "painting.xml")):
        zf = open_remote_zip(f"{DRIVE_ROOT}/{CONFIG_ZIP}")
        if zf is None:
            print("云盘里没有 Data_Config.zip，楼只用远景网格")
            return
        for i in zf.infolist():
            base = os.path.basename(i.filename)
            if base in ("blocks.xml", "shapes.xml", "painting.xml"):
                with zf.open(i) as src, open(os.path.join(bdir, base), "wb") as dst:
                    shutil.copyfileobj(src, dst)
    if not os.path.exists(os.path.join(bdir, "ta_opaque.xml")):
        it = find(list_dir(f"{DRIVE_ROOT}/{BLOCK_MAP}"), "ta_opaquexml")
        if it:
            with request(f"/items/{it['id']}/content") as r, open(os.path.join(bdir, "ta_opaque.xml"), "wb") as f:
                f.write(r.read())
    if not (os.path.isdir(sdir) and any(f.endswith(".glb") for f in os.listdir(sdir))):
        zf = open_remote_zip(f"{DRIVE_ROOT}/{SHAPES_ZIP}")
        if zf is None:
            print("云盘里没有 shapes_by_name.zip，楼只用远景网格")
            return
        os.makedirs(sdir, exist_ok=True)
        # 只给 build_poi_full.py 读，不让 Godot 导入
        open(os.path.join(sdir, ".gdignore"), "w").close()
        glbs = [i for i in zf.infolist() if i.filename.lower().endswith(".glb")]
        # “按模型文件名/” 下每个模型一个 glb，文件名 = shapes.xml 里 Model 指向的 fbx 名。
        # 压缩包里的中文路径常常没标 UTF-8，Python 按 cp437 读成乱码，所以先还原再比
        by_model = [i for i in glbs if "按模型文件名/" in _zip_name(i)]
        picked = by_model or glbs
        for i in picked:
            with zf.open(i) as src, open(os.path.join(sdir, os.path.basename(_zip_name(i))), "wb") as dst:
                shutil.copyfileobj(src, dst)
        # 玩家方块形状只要六个，顺手从“按形状名”目录取，build_block_shapes.py 用
        for i in glbs:
            name = _zip_name(i)
            base = os.path.basename(name)
            if base in BLOCK_SHAPE_FILES and "按形状名/" in name:
                with zf.open(i) as src, open(os.path.join(sdir, base), "wb") as dst:
                    shutil.copyfileobj(src, dst)
        print(f"形状模型: 压缩包里 {len(glbs)} 个 glb，按模型文件名的 {len(by_model)} 个，取了 {len(picked)} 个")
        if not picked:
            print("  shapes_by_name.zip 里没有 glb，楼只用远景网格。前几个文件：" +
                  "，".join(_zip_name(i) for i in zf.infolist()[:5]))
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import build_poi_full
    print("完整的楼:")
    build_poi_full.run(dest)
    import build_sleepers
    build_sleepers.run(dest)


# —— 楼里的家具、灯、柜子、门（方块表里 Shape="ModelEntity" 的实体模型）——
# 云盘 entities_by_prefab.zip：每个预制体一个 glb（保留子节点层级，底色贴图嵌在里面），文件名就是预制体名。
# 这里只取楼里用到的，tools/build_props.gd 再在 Godot 里把每个 glb 合成一个网格（assets/poiprops/*.res）
PROPS_ZIP = "小橘素材库/entities_by_prefab.zip"


def fetch_block_shapes(dest):
    """六个官方方块形状 → assets/data/block_shapes.json。缺哪个就在 PR 里说明。"""
    sdir = os.path.join(dest, "shapes")
    os.makedirs(sdir, exist_ok=True)
    missing = [f for f in BLOCK_SHAPE_FILES if not os.path.exists(os.path.join(sdir, f))]
    if missing:
        zf = open_remote_zip(f"{DRIVE_ROOT}/{SHAPES_ZIP}")
        if zf is not None:
            for i in zf.infolist():
                name = _zip_name(i)
                base = os.path.basename(name)
                if base in missing and "按形状名/" in name:
                    with zf.open(i) as src, open(os.path.join(sdir, base), "wb") as dst:
                        shutil.copyfileobj(src, dst)
        else:
            print("云盘里没有 shapes_by_name.zip，形状先用程序几何")
    tool = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_block_shapes.py")
    subprocess.run([sys.executable, tool, "--shapes", sdir, "--dest", dest], check=True)


def fetch_ui(dest):
    """官方背景、logo 和指南针底图 → assets/ui/。没有也不影响游戏，只是用纯色顶。"""
    udir = os.path.join(dest, "ui")
    need = ("background.png", "7DTD_logo.png", "compass_background3.png")
    os.makedirs(udir, exist_ok=True)
    if all(os.path.exists(os.path.join(udir, f)) for f in need):
        return
    zf = open_remote_zip(f"{DRIVE_ROOT}/{UI_ZIP}")
    if zf is None:
        print("云盘里没有 ui.zip，载入页和标题用纯色")
        return
    got = 0
    for i in zf.infolist():
        base = os.path.basename(_zip_name(i))
        if base in need:
            with zf.open(i) as src, open(os.path.join(udir, base), "wb") as dst:
                shutil.copyfileobj(src, dst)
            got += 1
    print(f"UI 贴图: 取了 {got}/{len(need)} 张")


def _godot_rotations():
    """方块转向 0..27 → Godot 的 Basis（楼的本地坐标 x 是翻过来的：M·R·M，M = diag(-1, 1, 1)），按列存"""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import build_poi_full
    out = []
    for r in build_poi_full.ROTATIONS:
        g = [[r[i][j] * (-1 if i == 0 else 1) * (-1 if j == 0 else 1) for j in range(3)] for i in range(3)]
        out.append([g[i][j] for j in range(3) for i in range(3)])
    return out


# 底色 512；法线、ORM（遮蔽/粗糙度/金属度）手机上看不出 256 和 512 的差别，省一半多内存
POI_PROP_TEX = {"albedo": 512, "normal": 256, "orm": 256}
NORMAL_IMPORT = ('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
                 'compress/mode=2\ncompress/normal_map=1\nmipmaps/generate=true\n')


def _glb_image_roles(j):
    """glb 里每张图的用途：材质里当底色、法线还是 ORM 用"""
    roles = {}

    def mark(ref, role):
        if isinstance(ref, dict) and "index" in ref:
            src = j.get("textures", [])[ref["index"]].get("source")
            if src is not None:
                roles.setdefault(src, role)

    for m in j.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        mark(pbr.get("baseColorTexture"), "albedo")
        mark(m.get("normalTexture"), "normal")
        mark(pbr.get("metallicRoughnessTexture"), "orm")
        mark(m.get("occlusionTexture"), "orm")
    return roles


def _glb_external_textures(data, tex_dir, rel):
    """glb 里嵌的贴图挪出去：按内容去重（很多预制体共用一张贴图，嵌在每个 glb 里各一份）、按用途缩小，
    存成 tex_dir/<md5>_<用途>.jpg|png，glb 改成按相对路径 rel/… 引用。法线图顺便写好导入设置。返回新的 glb 字节"""
    import hashlib
    jl = struct.unpack_from("<I", data, 12)[0]
    j = json.loads(data[20:20 + jl])
    o = 20 + jl
    bl = struct.unpack_from("<I", data, o)[0]
    buf = data[o + 8:o + 8 + bl]
    roles = _glb_image_roles(j)
    for k, im in enumerate(j.get("images", [])):
        if "bufferView" not in im:
            continue
        role = roles.get(k, "albedo")
        bv = j["bufferViews"][im["bufferView"]]
        raw = buf[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        ext = "png" if im.get("mimeType") == "image/png" or raw[:4] == b"\x89PNG" else "jpg"
        name = f"{hashlib.md5(raw).hexdigest()}_{role}.{ext}"
        out = os.path.join(tex_dir, name)
        if not os.path.exists(out):
            try:
                from PIL import Image
                img = Image.open(io.BytesIO(raw))
                lim = POI_PROP_TEX[role]
                if max(img.size) > lim:
                    img.thumbnail((lim, lim), Image.LANCZOS)
                if ext == "jpg":
                    img.convert("RGB").save(out, quality=90)
                else:
                    img.save(out)
            except ImportError:
                with open(out, "wb") as f:
                    f.write(raw)
            if role == "normal" and not os.path.exists(out + ".import"):
                with open(out + ".import", "w") as f:
                    f.write(NORMAL_IMPORT)
        del im["bufferView"]
        im["uri"] = f"{rel}/{name}"
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    rest = data[o:]
    total = 12 + 8 + len(js) + len(rest)
    return struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(js), b"JSON") + js + rest


def fetch_poi_props(dest):
    """tools/build_poi_full.py 列出的实体模型（poi/props_needed.json）→ assets/poipropsrc/<文件夹>/<预制体>.glb，
    对照表 assets/poi/props.json：{"models": {预制体: {src, mesh, door}}, "missing": [...], "rot": [...]}"""
    poi_dir = os.path.join(dest, "poi")
    need_path = os.path.join(poi_dir, "props_needed.json")
    index_out = os.path.join(poi_dir, "props.json")
    if not os.path.exists(need_path):
        print("楼里的模型: 没有 poi/props_needed.json（完整版的楼没生成），跳过")
        return
    need = json.load(open(need_path))
    doors = set(need.get("doors", []))
    keys = sorted(set(need.get("props", [])) | doors)
    src_dir = os.path.join(dest, "poipropsrc")
    tex_dir = os.path.join(dest, "poiproptex")
    # 云盘的 glb 重导过（加了法线、ORM）：旧版取的全部重取
    mark = os.path.join(src_dir, ".v2")
    if not os.path.exists(mark):
        for d in (src_dir, tex_dir, os.path.join(dest, "poiprops")):
            shutil.rmtree(d, ignore_errors=True)
        os.makedirs(src_dir, exist_ok=True)
        open(mark, "w").close()
    todo = [k for k in keys if not os.path.exists(os.path.join(src_dir, k + ".glb"))]
    if todo:
        zf = open_remote_zip(f"{DRIVE_ROOT}/{PROPS_ZIP}")
        if zf is None:
            print("云盘里没有 entities_by_prefab.zip，楼里只有门板和箱子")
        else:
            infos = {_zip_name(i): i for i in zf.infolist()}
            got = 0
            for k in todo:
                i = infos.get(k + ".glb")
                if i is None:
                    continue
                out = os.path.join(src_dir, k + ".glb")
                os.makedirs(os.path.dirname(out), exist_ok=True)
                os.makedirs(tex_dir, exist_ok=True)
                # glb 在 poipropsrc/<文件夹>/ 下，贴图在 poiproptex/
                data = _glb_external_textures(zf.read(i), tex_dir, "../../poiproptex")
                with open(out, "wb") as d_:
                    d_.write(data)
                got += 1
            print(f"  取了 {got} 个 glb（缺的 {len(todo) - got} 个压缩包里没有）")
    models, missing = {}, []
    for k in keys:
        if os.path.exists(os.path.join(src_dir, k + ".glb")):
            stem = re.sub(r"[^A-Za-z0-9_]", "_", k)
            models[k] = {"src": f"poipropsrc/{k}.glb", "mesh": f"poiprops/{stem}.res", "door": k in doors}
        else:
            missing.append(k)
    with open(index_out, "w", encoding="utf-8") as f:
        json.dump({"models": models, "missing": missing, "rot": _godot_rotations()}, f, ensure_ascii=False)
    print(f"楼里的模型: 要 {len(keys)} 种（门 {len(doors)} 种），有模型 {len(models)} 种")


def fetch_blocks(dest):
    out_dir = os.path.join(dest, "blocks")
    index_out = os.path.join(out_dir, "atlas.json")
    poi_dir = os.path.join(dest, "poi")
    extra = os.path.join(poi_dir, "full_textures.json")
    if os.path.exists(index_out):
        with open(index_out, encoding="utf-8") as f:
            old = json.load(f)
        have = set(old.get("ids", {}))
        need = {str(i) for i in json.load(open(extra))} if os.path.exists(extra) else set()
        need -= set(map(str, old.get("missing", [])))
        need.add(str(FLAGSTONE_TEXTURE_ID))
        if "blocks" in old and need <= have and os.path.exists(os.path.join(out_dir, "c_%03d.png" % FLAGSTONE_TEXTURE_ID)):
            print("方块贴图: 已有，跳过（删掉 assets/blocks/atlas.json 可重新取）")
            return
        print("方块贴图: 有新的贴图要取，重新取")
    try:
        from PIL import Image
    except ImportError:
        print("方块贴图: 需要 Pillow（pip install Pillow），跳过，楼先用纯色")
        return
    it = find(list_dir(f"{DRIVE_ROOT}/{BLOCK_MAP}"), "ta_opaquexml")
    zf = open_remote_zip(f"{DRIVE_ROOT}/{BLOCK_ZIP}")
    if not it or zf is None:
        print("云盘里没有方块贴图或对照表，楼先用纯色")
        return
    with request(f"/items/{it['id']}/content") as r:
        xml = r.read().decode("utf-8-sig")
    uv = {}
    for line in xml.splitlines():
        if "<uv " in line:
            a = dict(re.findall(r'(\w+)="([^"]*)"', line))
            uv[int(a["id"])] = (int(a["index"]), int(a.get("blockw", 1)), int(a.get("blockh", 1)))
    used = _poi_tex_ids(poi_dir) if os.path.isdir(poi_dir) else set()
    if os.path.exists(extra):
        used |= set(json.load(open(extra)))   # 完整的楼用到的贴图
    try:
        build = _build_block_textures()
    except Exception as e:  # 查不到就用纯色，不影响楼
        print(f"建造方块贴图: 读 blocks.xml 失败（{e}），用纯色")
        build = {}
    wanted = sorted(i for i in (((used or set(uv.keys())) | set(build.values())) | {FLAGSTONE_TEXTURE_ID}) if i in uv)
    names = {os.path.basename(i.filename): i for i in zf.infolist()}
    os.makedirs(out_dir, exist_ok=True)
    # 这些图只给 tools/build_poi.gd 打包成图集用，不让 Godot 单独导入
    open(os.path.join(out_dir, ".gdignore"), "w").close()
    ids, layer = {}, 0
    for tid in wanted:
        start, bw, bh = uv[tid]
        ids[str(tid)] = [layer, bw, bh]
        for k in range(bw * bh):
            src = start + k
            c = Image.open(io.BytesIO(zf.read(names[f"ta_opaque_0_{src:03d}.png"]))).convert("RGB")
            c.resize((BLOCK_TEX, BLOCK_TEX), Image.LANCZOS).save(os.path.join(out_dir, f"c_{layer:03d}.png"))
            n = Image.open(io.BytesIO(zf.read(names[f"ta_opaque_n_0_{src:03d}.png"])))
            _unpack_normal(n, BLOCK_TEX).save(os.path.join(out_dir, f"n_{layer:03d}.png"))
            layer += 1
    missing = sorted(used - set(uv))
    with open(index_out, "w", encoding="utf-8") as f:
        json.dump({"layers": layer, "size": BLOCK_TEX, "ids": ids, "missing": missing,
                   "blocks": {k: v for k, v in build.items() if str(v) in ids}}, f, indent=1)
    print(f"方块贴图: {len(ids)} 种，{layer} 层" + (f"（对照表里没有的编号 {missing}）" if missing else ""))
    ensure_fallback_icons(os.path.join(dest, "icons"))


def fetch_terrain(dest):
    out_dir = os.path.join(dest, "terrain")
    index_out = os.path.join(out_dir, "terrain.json")
    if os.path.exists(index_out):
        print("地形贴图: 已有，跳过")
        return
    try:
        from PIL import Image
    except ImportError:
        print("地形贴图: 需要 Pillow，跳过")
        return
    zf = open_remote_zip(f"{DRIVE_ROOT}/{TERRAIN_ZIP}")
    if zf is None:
        print("云盘里没有 terraintextures_arrays.zip，地面用单张贴图")
        return
    names = {os.path.basename(i.filename): i for i in zf.infolist()}
    os.makedirs(out_dir, exist_ok=True)
    index = {}

    def layer(kind, k):
        return Image.open(io.BytesIO(zf.read(names[f"MicroSplatConfig_{kind}_tarray_{k:03d}.png"])))

    for name, (k, tile) in TERRAIN_LAYERS.items():
        size = (TERRAIN_TEX, TERRAIN_TEX)
        layer("diff", k).convert("RGB").resize(size, Image.LANCZOS).save(os.path.join(out_dir, name + ".png"))
        _unpack_normal(layer("normal", k), TERRAIN_TEX).save(os.path.join(out_dir, name + "_n.png"))
        # ORM：R=AO，G=粗糙度（1-光滑度），B=金属度 0
        _, g, _, a = layer("smoothAO", k).convert("RGBA").resize(size, Image.LANCZOS).split()
        rough = g.point(lambda v: 255 - v)
        Image.merge("RGB", (a, rough, Image.new("L", size, 0))).save(os.path.join(out_dir, name + "_orm.png"))
        index[name] = {"albedo": f"terrain/{name}.png", "normal": f"terrain/{name}_n.png",
                       "orm": f"terrain/{name}_orm.png", "tile": tile}
    with open(index_out, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=1)
    print(f"地形贴图: {len(index)} 种（颜色+法线+粗糙度）")


# 特效贴图：枪口火光、血雾、血迹、火花、烟
EFFECT_TEXTURES = ["muzzleflash_point", "muzzle_large", "blood_mist02", "blood_mist04", "blood_spray", "blood_splat_1",
                   "p_blood", "blood_slash", "sparksSheet_A_2x2", "smoke_A_sprite", "p_smoke2"]


def fetch_effects(dest):
    out_dir = os.path.join(dest, "effects")
    if os.path.isdir(out_dir) and len(os.listdir(out_dir)) >= len(EFFECT_TEXTURES):
        print("特效贴图: 已有，跳过")
        return
    zf = open_remote_zip(f"{DRIVE_ROOT}/小橘素材库/effects_assets_all.zip")
    if zf is None:
        print("云盘里没有 effects_assets_all.zip，跳过特效")
        return
    _, texs = _zip_members(zf)
    os.makedirs(out_dir, exist_ok=True)
    n = 0
    for name in EFFECT_TEXTURES:
        if name in texs:
            _save_png(zf.read(texs[name]), os.path.join(out_dir, name + ".png"), 512)
            n += 1
    print(f"特效贴图: {n} 张")


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

# 音效：组名 → (zip 名, 文件名正则, 最多几个)。存到 assets/sounds/<组名>/，游戏里随机挑一个播
SOUND_GROUPS = {
    "fire_pistol": ("weapons", r"pistol_fire\d*\.wav", 3),
    "fire_magnum": ("weapons", r"(44magnum|desertvulture)_fire\d*\.wav", 3),
    "fire_smg": ("weapons", r"smg_fire\d+\.wav", 3),
    "fire_rifle": ("weapons", r"(tacticalar|ak47)_fire\d+\.wav", 4),
    "fire_mg": ("weapons", r"m60_fire\d+\.wav", 3),
    "fire_sniper": ("weapons", r"(sniperrifle|lever_action_rifle)_fire\d*\.wav", 3),
    "fire_shotgun": ("weapons", r"(pump_shotgun|autoshotgun|shotgundb)_fire\d+\.wav", 3),
    "fire_bow": ("weapons", r"(bow|crossbow2)_fire\d+\.wav", 3),
    "fire_rocket": ("weapons", r"m136_fire\.wav", 1),
    "reload_rifle": ("weapons", r"(ak47|mp5|sniperrifle)_reload\.wav", 3),
    "reload_pistol": ("weapons", r"(pistol|44magnum)_reload\.wav", 2),
    "reload_shotgun": ("weapons", r"shotgun_reload\.wav", 1),
    "empty": ("weapons", r"(weapon_empty|dryfire)\d+\.wav", 2),
    "swing": ("weapons", r"(club|batwood|machete|axe)_swinglight\d*\.wav", 4),
    "swing_fist": ("weapons", r"fists_swinglight\d+\.wav", 3),
    "hit_flesh": ("impactsurface", r"(metalhitorganic|organichitorganic)\d*\.wav", 4),
    "bullet_flesh": ("impactsurface", r"bullethitorganic\d*\.wav", 3),
    "bullet_wall": ("impactsurface", r"bullethit(stone|metal)\d*\.wav", 4),
    "hit_wood": ("impactsurface", r"bullethitwood\d*\.wav", 3),
    "explosion": ("explosions", r"explosion\d\.wav", 3),
    "zm_roam": ("enemies", r"zombiemale2?roam\d+\.wav", 5),
    "zm_alert": ("enemies", r"zombiemale2?alert\d+\.wav", 4),
    "zm_attack": ("enemies", r"zombiemale2?attack\d+\.wav", 4),
    "zm_pain": ("enemies", r"zombiemale2?pain\d+\.wav", 4),
    "zm_death": ("enemies", r"zombiemale2?death\d+\.wav", 4),
    "zf_roam": ("enemies", r"zombiefemale2?roam\d+\.wav", 4),
    "zf_alert": ("enemies", r"zombiefemale2?alert\d+\.wav", 3),
    "zf_attack": ("enemies", r"zombiefemale2?attack\d+\.wav", 4),
    "zf_pain": ("enemies", r"zombiefemale2?pain\d+\.wav", 3),
    "zf_death": ("enemies", r"zombiefemale2?death\d+\.wav", 3),
    "scream": ("enemies", r"zombiefemalescoutalert\d+\.wav", 3),
    "step": ("step", r"stepstone\d+\.wav", 6),
    "pain": ("player_male", r"player1pain(sm|lg)\d*\.wav", 4),
    "death": ("player_male", r"player1death\d*\.wav", 1),
    "jump": ("player_male", r"player1jump\d*\.wav", 2),
    "land": ("player_male", r"player1landSoft\d*\.wav", 2),
    "eat": ("useactions", r"player_eating\.wav", 1),
    "drink": ("useactions", r"player_drinking\.wav", 1),
    "bandage": ("useactions", r"player_bandage\.wav", 1),
    "search": ("useactions", r"open_(cardboard|garbage|fridge|cupboard|trashcan|dumpster|backpack)\.wav", 7),
    "loot": ("ui", r"ui_loot_success\.wav", 1),
    "door": ("useactions", r"\w*door\w*open\w*\.wav", 2),
    # 工作站开关和完成音效
    "campfire_open": ("campfire", r"campfire_open\.wav", 1),
    "campfire_done": ("campfire", r"campfire_complete_item\.wav", 1),
    "forge_open": ("forge", r"forge_open\.wav", 1),
    "forge_done": ("forge", r"forge_item_complete\.wav", 1),
    "chem_open": ("chem_station", r"chem_station_open\.wav", 1),
    "chem_done": ("chem_station", r"chem_station_complete_item\.wav", 1),
    "cement_open": ("crafting", r"cement_mixer_open\.wav", 1),
    "cement_done": ("crafting", r"cement_mixer_complete\.wav", 1),
    "amb_day": ("ambient_loops", r"a_windlight_lp\.wav", 1),
    "amb_night": ("ambient_loops", r"a_crickets_lp\.wav", 1),
    "amb_flies": ("ambient_loops", r"flies_lp\.wav", 1),
}


def fetch_station_models(dest):
    """工作站主网格（crafting.zip 的 OBJ 分件）和贴图 → assets/stationmodels/。
    没有模型时游戏会退回方块。"""
    out_dir = os.path.join(dest, "stationmodels")
    if os.path.isdir(out_dir) and len(os.listdir(out_dir)) >= len(STATION_MODELS) * 2:
        print("工作站模型: 已有，跳过")
        return
    zf = open_remote_zip(f"{DRIVE_ROOT}/小橘素材库/automatic_assets_entities/crafting.zip")
    if zf is None:
        print("工作站模型: 云盘没有 crafting.zip，先用方块")
        return
    names = set(zf.namelist())
    os.makedirs(out_dir, exist_ok=True)
    got = 0
    for station, (obj, tex) in STATION_MODELS.items():
        op = f"meshes/automatic_assets_entities/crafting/{obj}"
        tp = f"textures/automatic_assets_entities/crafting/{tex}"
        if op not in names:
            print(f"  缺模型 {obj}")
            continue
        with open(os.path.join(out_dir, station + ".obj"), "wb") as f:
            f.write(zf.read(op))
        if tp in names:
            with open(os.path.join(out_dir, station + ".png"), "wb") as f:
                f.write(zf.read(tp))
        got += 1
    print(f"工作站模型: {got}/{len(STATION_MODELS)} 个（缺的先用方块）")


def fetch_sounds(dest):
    out_dir = os.path.join(dest, "sounds")
    index_out = os.path.join(out_dir, "index.json")
    # 不整包跳过：后面版本会加组（工作站等），已有组不重复下载
    zips, total = {}, 0
    index = {}
    if os.path.exists(index_out):
        try:
            index = json.load(open(index_out))
        except Exception:
            index = {}
    for group, (pack, pattern, limit) in SOUND_GROUPS.items():
        have = index.get(group, [])
        if have and all(os.path.exists(os.path.join(dest, p)) for p in have):
            continue
        if pack not in zips:
            zf = open_remote_zip(f"{DRIVE_ROOT}/小橘素材库/automatic_assets_sounds/{pack}.zip")
            zips[pack] = (zf, zf.infolist() if zf else [])
        zf, infos = zips[pack]
        rx = re.compile(pattern, re.I)
        hits = sorted((i for i in infos if rx.fullmatch(os.path.basename(i.filename))), key=lambda i: i.filename)
        step = max(1, len(hits) // limit)
        chosen = hits[::step][:limit]
        os.makedirs(os.path.join(out_dir, group), exist_ok=True)
        got = []
        for i in chosen:
            base = os.path.basename(i.filename)
            with zf.open(i) as src, open(os.path.join(out_dir, group, base), "wb") as dst:
                shutil.copyfileobj(src, dst)
            got.append(f"sounds/{group}/{base}")
            total += i.file_size
        if got:
            index[group] = got
        elif not have:
            print(f"  音效 {group}: 没找到")
    with open(index_out, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=1)
    print(f"音效: {sum(len(v) for v in index.values())} 个，新取 {mb(total)}")

SKY_CUBES = ["WhispyClouds", "FluffyClouds", "ThickOvercastClouds", "MilkyWay_V_Cross_1024"]
FONTS = ["NotoSansCJKjp-Medium.otf", "AGENCYB.ttf", "opinionproextracondensed-bold.otf"]


def _cube_to_pano(folder, w=2048):
    """六面立方体贴图（Unity 左手坐标）→ 全景图 pano.png，游戏里按经纬度查。"""
    try:
        import numpy as np
        from PIL import Image
    except ImportError:
        print("  没有 numpy/Pillow，跳过全景图", folder)
        return
    faces = {}
    for f in ["px", "nx", "py", "ny", "pz", "nz"]:
        path = os.path.join(folder, f + ".png")
        if not os.path.exists(path):
            return
        faces[f] = np.asarray(Image.open(path).convert("RGB"), dtype=np.uint8)
    n = faces["px"].shape[0]
    h = w // 2
    lon = (np.arange(w) + 0.5) / w * 2 * np.pi - np.pi
    lat = np.pi / 2 - (np.arange(h) + 0.5) / h * np.pi
    lon, lat = np.meshgrid(lon, lat)
    x, y, z = np.cos(lat) * np.sin(lon), np.sin(lat), np.cos(lat) * np.cos(lon)
    ax, ay, az = np.abs(x), np.abs(y), np.abs(z)
    out = np.zeros((h, w, 3), dtype=np.uint8)
    # 每个方向看哪个轴最大，落在哪一面；面内坐标按 OpenGL/Unity 立方体贴图的约定
    rules = [
        ("px", (ax >= ay) & (ax >= az) & (x > 0), -z, -y, ax),
        ("nx", (ax >= ay) & (ax >= az) & (x <= 0), z, -y, ax),
        ("py", (ay > ax) & (ay >= az) & (y > 0), x, z, ay),
        ("ny", (ay > ax) & (ay >= az) & (y <= 0), x, -z, ay),
        ("pz", (az > ax) & (az > ay) & (z > 0), x, -y, az),
        ("nz", (az > ax) & (az > ay) & (z <= 0), -x, -y, az),
    ]
    for f, m, sc, tc, ma in rules:
        u = ((sc[m] / ma[m] + 1) / 2 * (n - 1)).round().astype(int)
        v = ((tc[m] / ma[m] + 1) / 2 * (n - 1)).round().astype(int)
        out[m] = faces[f][v, u]
    Image.fromarray(out).save(os.path.join(folder, "pano.png"))


def fetch_sky_fonts(dest):
    """天空盒（云层、银河，六面立方体贴图）和游戏字体。"""
    sky_dir, font_dir = os.path.join(dest, "sky"), os.path.join(dest, "fonts")
    if os.path.isdir(sky_dir) and os.path.isdir(font_dir):
        print("天空和字体: 已有，跳过")
        return
    zf = open_remote_zip(f"{DRIVE_ROOT}/小橘素材库/其他/天空盒与反射贴图.zip")
    if zf:
        for i in zf.infolist():
            parts = i.filename.split("/")
            if len(parts) == 3 and parts[1] in SKY_CUBES and parts[2].endswith(".png"):
                os.makedirs(os.path.join(sky_dir, parts[1]), exist_ok=True)
                _save_png(zf.read(i), os.path.join(sky_dir, parts[1], parts[2]), 1024)
    for name in SKY_CUBES:
        _cube_to_pano(os.path.join(sky_dir, name))
    zf = open_remote_zip(f"{DRIVE_ROOT}/小橘素材库/其他/字体.zip")
    if zf:
        os.makedirs(font_dir, exist_ok=True)
        done = set()
        for i in zf.infolist():
            base = os.path.basename(i.filename)
            if base in FONTS and base not in done:
                done.add(base)
                with zf.open(i) as src, open(os.path.join(font_dir, base), "wb") as dst:
                    shutil.copyfileobj(src, dst)
    print("天空和字体: 完成")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dest", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets"))
    ap.add_argument("--zombies", default=",".join(DEFAULT_ZOMBIES), help="逗号分隔的僵尸名，或 all")
    ap.add_argument("--music", type=int, default=6, help="每类音乐取几段")
    ap.add_argument("--all-icons", action="store_true", help="取全部图标（默认只取游戏会用到的）")
    ap.add_argument("--skip", default="", help="跳过某些步骤，逗号分隔: icons,zombies,samples,items,arms,world,vehicles,respawn,poi,full,blockshapes,props,stations,blocks,terrain,effects,music,sounds,sky,ui,data")
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
    if "vehicles" not in skip:
        fetch_vehicles(dest)
    if "respawn" not in skip:
        fetch_respawn(dest)
    if "poi" not in skip:
        fetch_poi(dest)
    if "full" not in skip:
        fetch_full_buildings(dest)
    if "blockshapes" not in skip:
        fetch_block_shapes(dest)
    if "props" not in skip:
        fetch_poi_props(dest)
    if "blocks" not in skip:
        fetch_blocks(dest)
    if "terrain" not in skip:
        fetch_terrain(dest)
    if "effects" not in skip:
        fetch_effects(dest)
    if "music" not in skip:
        fetch_music(dest, args.music)
    if "stations" not in skip:
        fetch_station_models(dest)
    if "sounds" not in skip:
        fetch_sounds(dest)
    if "sky" not in skip:
        fetch_sky_fonts(dest)
    if "ui" not in skip:
        fetch_ui(dest)
    if "data" not in skip:
        print("官方配置表…")
        subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_data.py"), "--dest", dest], check=True)
    print("完成。用 Godot 打开项目即可（第一次打开会导入素材，需要几分钟）。")


if __name__ == "__main__":
    main()
