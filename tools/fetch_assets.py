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
    assets/props/*.glb                 （场景里摆的车辆、家具）
    assets/textures/*.png              （地面贴图）
    assets/music/*.wav                 （文件名里 Exp=探索 Cbt=战斗 Sus=紧张 Bld=血月）

只用 Python 自带库。已存在且大小一致的文件会跳过，可以反复运行。
"""
import argparse
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
    ap.add_argument("--skip", default="", help="跳过某些步骤，逗号分隔: icons,zombies,samples,music")
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
    if "music" not in skip:
        fetch_music(dest, args.music)
    print("完成。用 Godot 打开项目即可（第一次打开会导入素材，需要几分钟）。")


if __name__ == "__main__":
    main()
