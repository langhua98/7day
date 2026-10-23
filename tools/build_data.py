#!/usr/bin/env python3
"""官方 Data/Config → 游戏用 JSON。

默认只生成 assets/data/items.json：
  {id: {id, stack, value, durability, tags, zh}}
只保留 assets/index/icon_to_model.json 里的物品，再加上 scripts/blocks.gd 的方块。
Data_Config.zip 从云盘 /7day/小橘素材库/ 下载；令牌只读环境变量 XIAOJU_TOKEN。
"""
import argparse
import csv
import io
import json
import os
import re
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DEST = ROOT / "assets"
API_DEFAULT = "https://langhua1998-xiaoju-cloud.hf.space/api/agent/v1"
DRIVE_FOLDER = "/7day/小橘素材库"
ZIP_NAME = "Data_Config.zip"


def _int(value, default=0):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def _float(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _durability(el) -> float:
    """从 passive_effect / stat 里找 DegradationMax，取数值里的最大值。"""
    best = 0.0
    for node in el.iter():
        if node.tag not in ("passive_effect", "stat"):
            continue
        if node.get("name") != "DegradationMax":
            continue
        nums = [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", node.get("value", ""))]
        if nums:
            best = max(best, max(nums))
    return best


def parse_items_xml(text: str) -> dict:
    """解析 items.xml，处理 <property name="Extends" value="..."> 继承。"""
    root = ET.fromstring(text)
    raw, raw_dur = {}, {}
    for el in root.findall("item"):
        name = el.get("name")
        if not name:
            continue
        props = {}
        for pr in el.findall("property"):
            key = pr.get("name")
            if key:
                props[key] = pr.get("value", "")
        raw[name] = props
        raw_dur[name] = _durability(el)

    resolved_props, resolved_dur = {}, {}
    visiting = set()

    def resolve(name: str):
        if name in resolved_props:
            return resolved_props[name], resolved_dur[name]
        if name in visiting:
            return {}, 0.0
        visiting.add(name)
        props, parent_dur = {}, 0.0
        parent = raw.get(name, {}).get("Extends")
        if parent:
            parent_props, parent_dur = resolve(parent)
            props.update(parent_props)
        props.update(raw.get(name, {}))
        props.pop("Extends", None)
        dur = raw_dur.get(name, 0.0) or parent_dur
        resolved_props[name] = props
        resolved_dur[name] = dur
        visiting.discard(name)
        return props, dur

    out = {}
    for name in raw:
        props, dur = resolve(name)
        out[name] = {
            "stack": max(1, _int(props.get("Stacknumber"), 1)),
            "value": _int(props.get("EconomicValue"), 0),
            "tags": props.get("Tags", ""),
            "durability": dur,
        }
    return out


def load_localization(text: str) -> dict:
    """Localization.csv 的 Key → 简体中文。"""
    out = {}
    for row in csv.DictReader(io.StringIO(text)):
        key = (row.get("Key") or "").strip()
        zh = (row.get("schinese") or "").strip()
        if key and zh:
            out[key] = zh
    return out


def block_types_from_gd(text: str) -> list:
    """从 scripts/blocks.gd 的 TYPES 里读方块 id / 中文名 / 耐久。"""
    out = []
    pattern = r'\[\s*"([^"]+)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*([0-9.]+)'
    for m in re.finditer(pattern, text):
        out.append({"id": m.group(1), "zh": m.group(2), "en": m.group(3), "hp": float(m.group(4))})
    return out


def build_items(items: dict, loc: dict, index_rows: list, blocks: list) -> dict:
    """只保留物品索引里的 id，再补上可放置方块。"""
    allowed = []
    index_zh = {}
    for row in index_rows:
        if not isinstance(row, list) or not row:
            continue
        item_id = str(row[0])
        allowed.append(item_id)
        if len(row) > 1 and row[1]:
            index_zh[item_id] = str(row[1])
    out = {}
    for item_id in allowed:
        if item_id not in items:
            continue
        row = items[item_id]
        out[item_id] = {
            "id": item_id,
            "stack": row["stack"],
            "value": row["value"],
            "durability": row["durability"],
            "tags": row["tags"],
            "zh": loc.get(item_id) or index_zh.get(item_id) or item_id,
        }
    for block in blocks:
        if block["id"] in out:
            continue
        out[block["id"]] = {
            "id": block["id"],
            "stack": 999,
            "value": 0,
            "durability": block["hp"],
            "tags": "block",
            "zh": block["zh"],
        }
    return out


def _api_base() -> str:
    return os.environ.get("XIAOJU_API", API_DEFAULT)


def _request_json(path: str, query=None) -> dict:
    token = os.environ.get("XIAOJU_TOKEN", "")
    if not token:
        sys.exit("缺少环境变量 XIAOJU_TOKEN（云盘令牌只放环境变量，不要写进仓库）")
    url = _api_base() + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode("utf-8"))


def download_data_zip(cache: Path) -> Path:
    if cache.exists() and cache.stat().st_size > 0:
        print(f"配置文件: 用缓存 {cache}")
        return cache
    data = _request_json("/items", {"path": DRIVE_FOLDER})
    children = data.get("children", data.get("items", []))
    item = next((i for i in children if i.get("name") == ZIP_NAME), None)
    if not item:
        sys.exit(f"云盘 {DRIVE_FOLDER} 里没有 {ZIP_NAME}")
    cache.parent.mkdir(parents=True, exist_ok=True)
    token = os.environ.get("XIAOJU_TOKEN", "")
    req = urllib.request.Request(
        _api_base() + f"/items/{item['id']}/content",
        headers={"Authorization": "Bearer " + token},
    )
    print(f"配置文件: 下载 {ZIP_NAME}（{item.get('size', 0) / 1e6:.1f}MB）")
    with urllib.request.urlopen(req, timeout=300) as r, open(cache, "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    return cache


def read_config_zip(path: Path):
    with zipfile.ZipFile(path) as zf:
        names = {i.filename: i for i in zf.infolist()}
        items_name = next((n for n in names if n.endswith("Config/items.xml")), None)
        loc_name = next((n for n in names if n.endswith("Config/Localization.csv")), None)
        if not items_name or not loc_name:
            sys.exit(f"{path} 里没有 Config/items.xml 或 Config/Localization.csv")
        items = zf.read(items_name).decode("utf-8-sig")
        loc = zf.read(loc_name).decode("utf-8-sig")
    return items, loc


def build_all(dest: Path, zip_path: Path, index_path: Path) -> dict:
    items_xml, loc_csv = read_config_zip(zip_path)
    items = parse_items_xml(items_xml)
    loc = load_localization(loc_csv)
    if not index_path.exists():
        sys.exit(f"找不到物品索引 {index_path}，先运行 tools/fetch_assets.py 的 fetch_index")
    index_rows = json.loads(index_path.read_text(encoding="utf-8"))
    blocks = block_types_from_gd((ROOT / "scripts" / "blocks.gd").read_text(encoding="utf-8"))
    out = build_items(items, loc, index_rows, blocks)
    out_dir = dest / "data"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "items.json"
    out_path.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    index_ids = {r[0] for r in index_rows if isinstance(r, list) and r}
    missing = sorted(i for i in index_ids if i not in items)
    print(f"物品配置: XML {len(items)} 个，索引 {len(index_ids)} 个，输出 {len(out)} 个")
    if missing:
        print(f"  索引里有、items.xml 没有的 {len(missing)} 个，例如: {', '.join(missing[:12])}")
    print(f"  → {out_path}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dest", default=str(DEFAULT_DEST), help="assets 目录")
    ap.add_argument("--zip", default="", help="本地 Data_Config.zip（不传就从云盘下载）")
    ap.add_argument("--index", default="", help="icon_to_model.json（默认 assets/index/）")
    ap.add_argument("--only", default="items", choices=["items"], help="只生成某张表")
    args = ap.parse_args()
    dest = Path(args.dest)
    zip_path = Path(args.zip) if args.zip else dest / "cache" / ZIP_NAME
    if not args.zip and not zip_path.exists():
        zip_path = download_data_zip(zip_path)
    index_path = Path(args.index) if args.index else dest / "index" / "icon_to_model.json"
    if args.only == "items":
        build_all(dest, zip_path, index_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
