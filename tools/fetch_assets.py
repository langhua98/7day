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
    assets/props/*.glb                 （场景里摆的车辆、家具）
    assets/textures/*.png              （地面贴图）
    assets/music/*.wav                 （文件名里 Exp=探索 Cbt=战斗 Sus=紧张 Bld=血月）

只用 Python 自带库。已存在且大小一致的文件会跳过，可以反复运行。
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


# 样例文件夹里的现成素材：(云盘目录, 本地子目录, 文件筛选)
SAMPLE_SOURCES = [
    ("样例/models/items", "models", lambda n: n.lower().endswith(".glb")),          # 物品模型
    ("样例/models/common", "models", lambda n: n.startswith("FP_ARM") and n.endswith(".glb")),  # 第一人称手臂
    ("样例/models/vehicles", "props", lambda n: n.lower().endswith(".glb")),        # 场景摆设
    ("样例/models/furniture", "props", lambda n: n.lower().endswith(".glb")),
    ("样例/textures/terraintextures", "textures", lambda n: n in ("desert_debris.png", "rubble.png")),  # 地面贴图
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
    ap.add_argument("--skip", default="", help="跳过某些步骤，逗号分隔: icons,zombies,samples,items,arms,music")
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
    if "music" not in skip:
        fetch_music(dest, args.music)
    print("完成。用 Godot 打开项目即可（第一次打开会导入素材，需要几分钟）。")


if __name__ == "__main__":
    main()
