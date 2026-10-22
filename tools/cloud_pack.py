#!/usr/bin/env python3
"""混合加载：大素材（楼、车和杂物、音乐、音效、部分僵尸）不打进安装包，
打成一个 Godot 素材包（.pck）放到小桔云盘，游戏开局时下载、存在手机里、加载。

用法（在 GitHub Actions 里，素材导入之后、导出安装包之前）：
    python3 tools/cloud_pack.py prepare            # 写导出配置：安装包排除这些素材，"Pack" 预设只含这些素材
    godot --headless --export-pack "Pack" build/assets.pck
    XIAOJU_TOKEN=... python3 tools/cloud_pack.py upload build/assets.pck
        # 上传到 /7day/素材包/，建分享，写 cloud.json 让游戏知道去哪下载；
        # 上传失败就把素材放回安装包，保证这一版照样能玩

同样的素材内容只上传一次（文件名带内容指纹），手机上已经下过的也不用再下。
"""
import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import publish_ipa as drive  # noqa: E402  复用上传、分享、换直链

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRESETS = os.path.join(ROOT, "export_presets.cfg")
CLOUD_JSON = os.path.join(ROOT, "cloud.json")
FOLDER = "/7day/素材包"

# 放云盘的素材（相对 assets/）。手臂、物品、图标和三种常见僵尸留在安装包里，不联网也能玩
CLOUD_DIRS = ["world", "poi", "music", "sounds"]
CLOUD_ZOMBIES = ["soldier", "cop", "biker", "lumberjack", "screamer"]
# 不是资源的文件。cloud_files.json 是素材包里的文件清单：加载素材包后游戏列目录看不到包里的文件，靠它来找
MANIFEST = "assets/index/cloud_files.json"
CLOUD_PLAIN = ["assets/index/world_models.json", "assets/poi/index.json", MANIFEST]
RESOURCE_EXT = (".png", ".obj", ".glb", ".wav", ".ogg", ".mp3", ".res")


def cloud_files():
    out = []
    for d in CLOUD_DIRS:
        base = os.path.join(ROOT, "assets", d)
        for dirpath, _, files in os.walk(base):
            for f in files:
                if f.lower().endswith(RESOURCE_EXT):
                    out.append(os.path.relpath(os.path.join(dirpath, f), ROOT).replace(os.sep, "/"))
    models = os.path.join(ROOT, "assets", "models")
    if os.path.isdir(models):
        for f in os.listdir(models):
            if any(f.lower().startswith(f"zombie_{z}.") for z in CLOUD_ZOMBIES) and f.lower().endswith(RESOURCE_EXT):
                out.append(f"assets/models/{f}")
    return sorted(out)


def exclude_patterns():
    pats = [f"assets/{d}/*" for d in CLOUD_DIRS] + CLOUD_PLAIN
    pats += [f"assets/models/zombie_{z}.*" for z in CLOUD_ZOMBIES]
    return ",".join(pats)


def version(files):
    """内容指纹：文件名 + 大小 + 修改不敏感的内容摘要（只读开头 64KB，够区分又快）。"""
    h = hashlib.sha256()
    for rel in files + [p for p in CLOUD_PLAIN if p != MANIFEST and os.path.exists(os.path.join(ROOT, p))]:
        path = os.path.join(ROOT, rel)
        h.update(rel.encode())
        h.update(str(os.path.getsize(path)).encode())
        with open(path, "rb") as f:
            h.update(f.read(65536))
    return h.hexdigest()[:12]


def read_presets():
    return open(PRESETS, encoding="utf-8").read()


def main_preset(text):
    """取出 preset.0 和 preset.0.options 两段（新加的 preset.1 之前的部分）。"""
    m = re.search(r"^\[preset\.1\]", text, re.M)
    return text[:m.start()].rstrip() + "\n" if m else text


def set_key(section, key, value):
    return re.sub(rf"^{re.escape(key)}=.*$", f"{key}={value}", section, count=1, flags=re.M)


def prepare():
    files = cloud_files()
    if not files:
        print("没有要放云盘的素材，全部打进安装包")
        return
    with open(os.path.join(ROOT, MANIFEST), "w", encoding="utf-8") as f:
        json.dump(files, f, ensure_ascii=False)
    base = main_preset(read_presets())
    main = set_key(base, "exclude_filter", json.dumps(exclude_patterns()))
    main = set_key(main, "include_filter", json.dumps("assets/index/*.json,cloud.json"))
    pack = base.replace("[preset.0]", "[preset.1]").replace("[preset.0.options]", "[preset.1.options]")
    pack = set_key(pack, "name", '"Pack"')
    pack = set_key(pack, "runnable", "false")
    pack = set_key(pack, "export_filter", '"resources"')
    pack = set_key(pack, "include_filter", json.dumps(",".join(CLOUD_PLAIN)))
    pack = set_key(pack, "exclude_filter", '""')
    pack = set_key(pack, "export_path", '"build/assets.pck"')
    files_line = "export_files=PackedStringArray(" + ", ".join(json.dumps("res://" + f) for f in files) + ")"
    pack = re.sub(r"^(export_filter=.*)$", lambda m: m.group(1) + "\n" + files_line, pack, count=1, flags=re.M)
    with open(PRESETS, "w", encoding="utf-8") as f:
        f.write(main + "\n" + pack)
    print(f"云盘素材 {len(files)} 个文件，指纹 {version(files)}；安装包排除：{exclude_patterns()}")


def put_back(reason):
    """上传失败：素材放回安装包，这一版不依赖云盘。"""
    print(f"::warning::{reason}，这一版把素材打进安装包")
    base = main_preset(read_presets())
    main = set_key(base, "exclude_filter", '""')
    main = set_key(main, "include_filter", json.dumps("assets/index/*.json,assets/poi/index.json"))
    with open(PRESETS, "w", encoding="utf-8") as f:
        f.write(main)
    if os.path.exists(CLOUD_JSON):
        os.remove(CLOUD_JSON)
    return 0


def upload(pck):
    if not os.path.exists(pck) or os.path.getsize(pck) < 1024:
        return put_back("素材包没导出来")
    files = cloud_files()
    ver = version(files)
    name = f"assets-{ver}.pck"
    size = os.path.getsize(pck)
    # 同样内容已经上传过就直接用
    item = None
    status, text = drive.call("GET", "/items", query={"path": FOLDER})
    listing = drive.parse(text) or {}
    for it in listing.get("children", []):
        if it.get("name") == name and it.get("size") == size:
            item = it
            print(f"云盘上已有 {name}，不再上传")
    if item is None:
        print(f"上传素材包 {name}（{size / 1e6:.1f}MB）…")
        with open(pck, "rb") as f:
            data = f.read()
        for folder in (FOLDER, "/7day"):
            status, text = drive.call("PUT", "/files", raw=data, query={"path": f"{folder}/{name}"})
            print("PUT", folder, status, text[:300])
            if status < 300:
                break
        if status >= 300:
            return put_back(f"上传素材包失败（{status}）")
        item = (drive.parse(text) or {}).get("item", {})
    share = None
    for body in ({"id": item["id"]}, {"item_id": item["id"]}, {"path": item.get("path", f"{FOLDER}/{name}")}):
        status, text = drive.call("POST", "/shares", body=body)
        print("POST /shares", status, text[:300])
        if status < 300:
            share = drive.parse(text) or {}
            break
    web = (share or {}).get("web_path", "")
    if "#" not in web:
        return put_back("建素材包的分享链接失败")
    code = web.split("#", 1)[1]
    info = {"site": drive.SITE, "share": code, "file": name, "size": size, "version": ver,
            "expires_at": share.get("expires_at", "")}
    with open(CLOUD_JSON, "w", encoding="utf-8") as f:
        json.dump(info, f, ensure_ascii=False)
    print("cloud.json:", json.dumps(info, ensure_ascii=False))
    drive.summary([f"- 云盘素材包：`{FOLDER}/{name}`（{size / 1e6:.0f}MB），游戏第一次打开时下载"])
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "prepare":
        prepare()
    elif cmd == "upload":
        sys.exit(upload(sys.argv[2]))
    else:
        sys.exit(__doc__)
