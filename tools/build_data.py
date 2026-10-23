#!/usr/bin/env python3
"""官方 Data/Config → 游戏用 JSON。

生成 assets/data/ 下的表：
  items.json    {id: {id, stack, value, durability, tags, zh}}
  recipes.json  {key: {id, count, area, time, tool, tags, cat, zh, learnable, ingredients:[{id,count,zh}]}}
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

## 官方僵尸名 → 云盘模型名（没有模型的会在 map_entitygroups 里过滤）
ZOMBIE_MODEL_MAP = {
    "zombieJoe": "joe", "zombieJoeFeral": "joe",
    "zombieNurse": "nurse", "zombieNurseFeral": "nurse",
    "zombieUtilityWorker": "worker", "zombieJanitor": "worker",
    "zombieBoe": "boe", "zombieBoeFeral": "boe",
    "zombieMoe": "moe", "zombieMoeFeral": "moe",
    "zombieMarlene": "marlene", "zombieMarleneFeral": "marlene",
    "zombieYo": "yo", "zombieYoFeral": "yo",
    "zombieTomClark": "tomclark", "zombieTomClarkFeral": "tomclark",
    "zombieSteve": "steve", "zombieSteveFeral": "steve",
    "zombieDarlene": "darlene", "zombieDarleneFeral": "darlene",
    "zombiePartyGirl": "cocktailwaitress", "zombiePartyGirlFeral": "cocktailwaitress",
    "zombieArlene": "arlene", "zombieArleneFeral": "arlene",
    "zombieLab": "lab", "zombieLabFeral": "lab",
    "zombieBusinessMan": "suit", "zombieBusinessManFeral": "suit",
    "zombieLumberjack": "lumberjack", "zombieLumberjackFeral": "lumberjack",
    "zombieFatHawaiian": "hawaiian", "zombieFatHawaiianFeral": "hawaiian",
    "zombieSteveCrawler": "crawler", "zombieSteveCrawlerFeral": "crawler",
    "zombieFatCop": "cop", "zombieFatCopFeral": "cop",
    "zombieSpider": "spider", "zombieSpiderFeral": "spider",
    "zombieScreamer": "screamer",
    "zombieDemolition": "demolition",
    "zombieBiker": "biker", "zombieBikerFeral": "biker",
    "zombieSoldier": "soldier", "zombieSoldierFeral": "soldier",
    "zombieHazmat": "hazmat", "zombieHazmatFeral": "hazmat",
    "zombieWight": "wight", "zombieWightFeral": "wight",
    "zombieMutated": "mutated", "zombieMutatedFeral": "mutated",
    "zombiePlagueSpitter": "plaguespitter", "zombiePlagueSpitterFeral": "plaguespitter",
    "animalZombieDog": "dog",
    "zombieChuck": "chuck", "zombieChuckFeral": "chuck",
    "zombieRancher": "rancher", "zombieRancherFeral": "rancher",
    "zombieFrostclaw": "frostclaw", "zombieFrostclawFeral": "frostclaw",
    "zombieSnow": "snow", "zombieSnowFeral": "snow",
    "zombieSand": "sand", "zombieSandFeral": "sand",
    "zombieThug": "thug", "zombieThugFeral": "thug",
    "zombieMechanic": "mechanic", "zombieMechanicFeral": "mechanic",
    "zombieBigMama": "bigmama", "zombieBigMamaFeral": "bigmama",
    "zombieBurnt": "burnt", "zombieBurntFeral": "burnt",
}


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


def _ammo_prefix(first: str) -> str:
    for suffix in ("BreachingSlug", "BulletBall", "BulletHP", "BulletAP", "SteelAP", "Exploding",
                   "Flaming", "Regular", "Shell", "Slug", "Stone", "Iron", "HE", "Frag", "AP", "HP"):
        if first.endswith(suffix):
            return first[:-len(suffix)]
    return first


def _gun_stats(el) -> dict:
    out = {}
    for pr in el.iter("property"):
        name = pr.get("name")
        value = pr.get("value", "")
        if name == "Magazine_items" and value and "ammo" not in out:
            out["ammo"] = _ammo_prefix(value.split(",")[0].strip())
        elif name == "Reload_time" and value:
            out["reload"] = _float(value, 0.0)
    for node in el.iter():
        if node.tag not in ("passive_effect", "stat"):
            continue
        name = node.get("name")
        if name not in ("MagazineSize", "RoundsPerMinute", "EntityDamage"):
            continue
        nums = [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", node.get("value", ""))]
        if not nums:
            continue
        value = max(nums)
        if name == "MagazineSize" and value > 0:
            out["magazine"] = int(value)
        elif name == "RoundsPerMinute" and value > 0:
            out["rpm"] = value
        elif name == "EntityDamage" and value > 0:
            out["damage"] = value
    return out


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
        props.update(_gun_stats(el))
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
            "magazine": _int(props.get("magazine"), 0),
            "rpm": _float(props.get("rpm"), 0.0),
            "ammo": props.get("ammo", ""),
            "reload": _float(props.get("reload"), 0.0),
            "damage": _float(props.get("damage"), 0.0),
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
            "magazine": row.get("magazine", 0),
            "rpm": row.get("rpm", 0.0),
            "ammo": row.get("ammo", ""),
            "reload": row.get("reload", 0.0),
            "damage": row.get("damage", 0.0),
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


def status_buffs_from_gd(text: str) -> list:
    """scripts/config.gd 的 STATUS 表里用到的官方 buff 名。"""
    return sorted(set(re.findall(r'"buff"\s*:\s*"([^"]+)"', text)))


def parse_buffs(text: str, loc: dict, wanted) -> dict:
    """buffs.xml → {buff 名: {zh, desc, icon}}，只导 wanted 里的。"""
    wanted = set(wanted)
    out = {}
    if not text:
        return out
    root = ET.fromstring(text)
    for el in root.iter("buff"):
        name = el.get("name") or ""
        if name not in wanted:
            continue
        name_key = el.get("name_key") or name + "Name"
        desc_key = el.get("description_key") or name + "Desc"
        out[name] = {
            "zh": loc.get(name_key) or loc.get(name) or "",
            "desc": loc.get(desc_key) or "",
            "icon": el.get("icon") or "",
        }
    return out


def parse_gamestages(text: str) -> dict:
    root = ET.fromstring(text)
    out = {}
    for spawner in root.findall("spawner"):
        name = spawner.get("name")
        if not name:
            continue
        stages = []
        for gs in spawner.findall("gamestage"):
            spawns = []
            for sp in gs.findall("spawn"):
                spawns.append({
                    "group": sp.get("group", ""),
                    "num": _int(sp.get("num"), 1),
                    "max_alive": _int(sp.get("maxAlive"), 1),
                    "duration": _float(sp.get("duration"), 1.0),
                    "interval": _float(sp.get("interval"), 0.0),
                })
            stages.append({"stage": _int(gs.get("stage"), 1), "spawns": spawns})
        stages.sort(key=lambda s: s["stage"])
        out[name] = stages
    return out


def select_horde_stage(stages: list, gs: int) -> dict:
    chosen = stages[0] if stages else {"stage": 1, "spawns": []}
    for stage in stages:
        if stage["stage"] <= gs:
            chosen = stage
        else:
            break
    return chosen


def blood_moon_total(stage: dict, mult: float) -> int:
    total = sum(s["num"] for s in stage.get("spawns", []) if s["num"] < 999)
    return max(1, int(total * mult))


def parse_entitygroups(text: str) -> dict:
    root = ET.fromstring(text)
    out = {}
    for eg in root.findall("entitygroup"):
        name = eg.get("name")
        if not name:
            continue
        out[name] = [
            {"name": e.get("n", ""), "p": _float(e.get("p"), 1.0)}
            for e in eg.findall("e") if e.get("n")
        ]
    return out


def map_entitygroups(groups: dict, available: set) -> dict:
    out = {}
    for name, entries in groups.items():
        mapped = []
        for e in entries:
            model = ZOMBIE_MODEL_MAP.get(e["name"])
            if not model or model not in available:
                continue
            mapped.append({"id": model, "feral": e["name"].endswith("Feral"), "p": e["p"]})
        if mapped:
            out[name] = mapped
    return out


# —— 配方（recipes.xml）——

## 合成面板的分类：按成品名前缀和 tags 判断，不针对具体物品
RECIPE_CATS = ("tool", "weapon", "ammo", "medical", "food", "build", "other")


def base_name(name: str) -> str:
    """方块配方名可能带 ":VariantHelper" 之类的后缀，去掉后再和物品表比对。"""
    name = (name or "").strip()
    if ":" in name:
        name = name.split(":", 1)[0]
    return name


def parse_ingredient_times(items_text: str) -> dict:
    """items.xml 里每个物品的 CraftingIngredientTime（配方没写 craft_time 时用来估时间）。"""
    root = ET.fromstring(items_text)
    raw, parent = {}, {}
    for el in root.findall("item"):
        name = el.get("name")
        if not name:
            continue
        for pr in el.findall("property"):
            if pr.get("name") == "CraftingIngredientTime":
                raw[name] = _float(pr.get("value"), 1.0)
            elif pr.get("name") == "Extends":
                parent[name] = pr.get("value", "")
    out = {}
    for name in set(raw) | set(parent):
        cur, seen = name, set()
        while cur and cur not in raw and cur not in seen:
            seen.add(cur)
            cur = parent.get(cur, "")
        if cur in raw:
            out[name] = raw[cur]
    return out


def parse_block_names(text: str) -> set:
    if not text:
        return set()
    root = ET.fromstring(text)
    return {el.get("name") for el in root.iter("block") if el.get("name")}


def parse_recipes_xml(text: str) -> list:
    """recipes.xml → [{name, count, area, time, tool, tags, ingredients}]，time 为 None 表示官方没写。"""
    root = ET.fromstring(text)
    out = []
    for el in root.iter("recipe"):
        name = el.get("name")
        if not name:
            continue
        ings = []
        for ing in el.findall("ingredient"):
            iname = ing.get("name")
            if iname:
                ings.append({"id": iname, "count": max(1, _int(ing.get("count"), 1))})
        t = el.get("craft_time")
        out.append({
            "name": name,
            "count": max(1, _int(el.get("count"), 1)),
            "area": (el.get("craft_area") or "").strip(),
            "time": _float(t, 0.0) if t not in (None, "") else None,
            "tool": base_name(el.get("craft_tool") or ""),
            "tags": (el.get("tags") or "").strip(),
            "ingredients": ings,
            "forge": el.find("wildcard_forge_category") is not None,
        })
    return out


def recipe_category(item_id: str, recipe_tags: str, item_tags: str) -> str:
    low = item_id.lower()
    tags = {t.strip().lower() for t in (recipe_tags + "," + item_tags).split(",") if t.strip()}
    if low.startswith("ammo"):
        return "ammo"
    if low.startswith("meleetool") or low.startswith("tool") or "tool" in tags:
        return "tool"
    if low.startswith("melee") or low.startswith("gun") or "weapon" in tags:
        return "weapon"
    if low.startswith("medical") or "medical" in tags:
        return "medical"
    if low.startswith("food") or low.startswith("drink") or "food" in tags or "drink" in tags:
        return "food"
    if "block" in tags or "shapes" in low or low.endswith("block") or "building" in tags:
        return "build"
    return "other"


def build_recipes(recipes: list, items: dict, block_names: set, loc: dict, ing_times: dict):
    """只保留成品和全部材料都在物品表（items.json）或方块表（blocks.xml）里的配方。

    返回 (表, 丢弃原因计数)。同名配方（不同工作站）用 名字@工作站 区分。
    """
    def known(i):
        return i in items or i in block_names

    def zh(i):
        return items.get(i, {}).get("zh") or loc.get(i) or i

    out, dropped = {}, {}
    for r in recipes:
        rid = base_name(r["name"])
        reason = ""
        if r["forge"] or any(i["id"].startswith("unit_") for i in r["ingredients"]):
            reason = "锻造炉熔炼材料"
        elif not known(rid):
            reason = "成品不在物品表"
        elif not r["ingredients"]:
            reason = "没有材料"
        else:
            ings = []
            for ing in r["ingredients"]:
                iid = base_name(ing["id"])
                if not known(iid):
                    reason = "材料不在物品表"
                    break
                ings.append({"id": iid, "count": ing["count"], "zh": zh(iid)})
        if reason:
            dropped[reason] = dropped.get(reason, 0) + 1
            continue
        time = r["time"]
        if time is None:
            # 官方没写 craft_time：按材料的 CraftingIngredientTime（默认 1 秒）累加
            time = sum(ing_times.get(i["id"], 1.0) * i["count"] for i in ings)
        key = rid
        if key in out:
            key = f"{rid}@{r['area'] or 'backpack'}"
            n = 2
            while key in out:
                key = f"{rid}@{r['area'] or 'backpack'}#{n}"
                n += 1
        tags = [t.strip() for t in r["tags"].split(",") if t.strip()]
        out[key] = {
            "id": rid,
            "count": r["count"],
            "area": r["area"],
            "time": round(max(0.5, time), 2),
            "tool": r["tool"],
            "tags": tags,
            "learnable": "learnable" in tags,
            "cat": recipe_category(rid, r["tags"], items.get(rid, {}).get("tags", "")),
            "zh": zh(rid),
            "block": rid not in items,
            "ingredients": ings,
        }
    return out, dropped


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
        gs_name = next((n for n in names if n.endswith("Config/gamestages.xml")), None)
        eg_name = next((n for n in names if n.endswith("Config/entitygroups.xml")), None)
        gamestages = zf.read(gs_name).decode("utf-8-sig") if gs_name else ""
        entitygroups = zf.read(eg_name).decode("utf-8-sig") if eg_name else ""
    return items, loc, gamestages, entitygroups


def read_config_file(path: Path, filename: str) -> str:
    """从 Data_Config.zip 里读一个 Config/xxx.xml，没有就返回空串。"""
    with zipfile.ZipFile(path) as zf:
        name = next((n for n in zf.namelist() if n.endswith("Config/" + filename)), None)
        return zf.read(name).decode("utf-8-sig") if name else ""


def read_buffs_xml(path: Path) -> str:
    return read_config_file(path, "buffs.xml")


def build_all(dest: Path, zip_path: Path, index_path: Path, only: str = "all") -> dict:
    items_xml, loc_csv, gs_xml, eg_xml = read_config_zip(zip_path)
    if only in ("items", "all"):
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
    else:
        out = {}
    if only in ("buffs", "all"):
        wanted = status_buffs_from_gd((ROOT / "scripts" / "config.gd").read_text(encoding="utf-8"))
        buffs = parse_buffs(read_buffs_xml(zip_path), load_localization(loc_csv), wanted)
        out_dir = dest / "data"
        out_dir.mkdir(parents=True, exist_ok=True)
        path = out_dir / "buffs.json"
        path.write_text(json.dumps(buffs, ensure_ascii=False, indent=1), encoding="utf-8")
        missing = [w for w in wanted if w not in buffs]
        print(f"状态效果: 需要 {len(wanted)} 个，找到 {len(buffs)} 个 → {path}")
        if missing:
            print(f"  buffs.xml 里没有: {', '.join(missing)}（游戏里用 config.gd 的中文名）")
    if only in ("gamestages", "all"):
        stages = parse_gamestages(gs_xml)
        out_dir = dest / "data"
        out_dir.mkdir(parents=True, exist_ok=True)
        path = out_dir / "gamestages.json"
        path.write_text(json.dumps(stages, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"血月阶段表: {len(stages.get('BloodMoonHorde', []))} 个阶段 → {path}")
    if only in ("entitygroups", "all"):
        groups = parse_entitygroups(eg_xml)
        models_dir = dest / "models"
        available = {p.stem.removeprefix("zombie_") for p in models_dir.glob("zombie_*.glb")}
        if not available:
            available = set(ZOMBIE_MODEL_MAP.values())
        mapped = map_entitygroups(groups, available)
        out_dir = dest / "data"
        out_dir.mkdir(parents=True, exist_ok=True)
        path = out_dir / "entitygroups.json"
        path.write_text(json.dumps(mapped, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"僵尸组: {len(mapped)} 组，可用模型 {len(available)} 个 → {path}")
    if only in ("recipes", "all"):
        items_path = dest / "data" / "items.json"
        if not items_path.exists():
            sys.exit(f"找不到 {items_path}，先运行 --only items")
        items_table = json.loads(items_path.read_text(encoding="utf-8"))
        rec_xml = read_config_file(zip_path, "recipes.xml")
        if not rec_xml:
            sys.exit(f"{zip_path} 里没有 Config/recipes.xml")
        raw = parse_recipes_xml(rec_xml)
        blocks = parse_block_names(read_config_file(zip_path, "blocks.xml"))
        recipes, dropped = build_recipes(raw, items_table, blocks, load_localization(loc_csv),
                                         parse_ingredient_times(items_xml))
        path = dest / "data" / "recipes.json"
        path.write_text(json.dumps(recipes, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"配方: 官方 {len(raw)} 条，保留 {len(recipes)} 条，丢弃 {sum(dropped.values())} 条 → {path}")
        for reason, n in sorted(dropped.items(), key=lambda kv: -kv[1]):
            print(f"  丢弃 {n} 条：{reason}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dest", default=str(DEFAULT_DEST), help="assets 目录")
    ap.add_argument("--zip", default="", help="本地 Data_Config.zip（不传就从云盘下载）")
    ap.add_argument("--index", default="", help="icon_to_model.json（默认 assets/index/）")
    ap.add_argument("--only", default="all", choices=["all", "items", "buffs", "gamestages", "entitygroups", "recipes"], help="只生成某张表")
    args = ap.parse_args()
    dest = Path(args.dest)
    zip_path = Path(args.zip) if args.zip else dest / "cache" / ZIP_NAME
    if not args.zip and not zip_path.exists():
        zip_path = download_data_zip(zip_path)
    index_path = Path(args.index) if args.index else dest / "index" / "icon_to_model.json"
    build_all(dest, zip_path, index_path, args.only)
    return 0


if __name__ == "__main__":
    sys.exit(main())
