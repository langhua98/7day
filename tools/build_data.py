#!/usr/bin/env python3
"""官方 Data/Config → 游戏用 JSON。

生成 assets/data/ 下的表：
  items.json    {id: {id, stack, value, durability, tags, zh}}
  blocks.json   {id: {hp, mass, glue, overhang, category, texture, repair, upgrade}}
  recipes.json  {key: {id, count, area, time, tool, tags, cat, zh, learnable, ingredients:[{id,count,zh}]}}
  progression.json  等级曲线、5 项属性、技能每级 passive_effect（7a）
  books.json    杂志类别/解锁配方、技能书效果（7b）
  traders.json  商人营业时间、货币、重置天数、可售物品价值（7c）
  quests.json   tier1/tier2 三类商人任务的经验和公爵币奖励（7d）
只保留 assets/index/icon_to_model.json 里的物品，再加上 scripts/blocks.gd 的方块。
方块血量、升级、修理、悬挑来自官方 blocks.xml + materials.xml。
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
    "zombieFemaleFat": "bigmama", "zombieFemaleFatFeral": "bigmama",
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


def zombie_model(name: str):
    """官方僵尸名 → 云盘模型名；Radiated/Charged/Infernal 这些变体用基础名查。"""
    if name in ZOMBIE_MODEL_MAP:
        return ZOMBIE_MODEL_MAP[name]
    for suffix in ("Radiated", "Charged", "Infernal"):
        if name.endswith(suffix):
            base = name[:-len(suffix)]
            if base in ZOMBIE_MODEL_MAP:
                return ZOMBIE_MODEL_MAP[base]
            feral = base + "Feral"
            if feral in ZOMBIE_MODEL_MAP:
                return ZOMBIE_MODEL_MAP[feral]
    return None


def map_entitygroups(groups: dict, available: set) -> dict:
    out = {}
    for name, entries in groups.items():
        mapped = []
        for e in entries:
            model = zombie_model(e["name"])
            if not model or model not in available:
                continue
            mapped.append({"id": model, "class": e["name"],
                "feral": "feral" in e["name"].lower() or e["name"].endswith("Feral"),
                "radiated": e["name"].endswith("Radiated"), "p": e["p"]})
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


def parse_materials_xml(text: str) -> dict:
    """materials.xml → {id: {hp, mass, glue, category, extends}}，处理 Extends。"""
    if not text:
        return {}
    root = ET.fromstring(text)
    raw = {}
    for el in root.findall("material"):
        mid = el.get("id")
        if not mid:
            continue
        props = {p.get("name"): p.get("value", "") for p in el.findall("property") if p.get("name")}
        raw[mid] = props
    out, visiting = {}, set()

    def resolve(mid):
        if mid in out:
            return out[mid]
        if mid in visiting or mid not in raw:
            return {}
        visiting.add(mid)
        row = {}
        parent = raw[mid].get("Extends")
        if parent:
            row.update(resolve(parent))
        row.update(raw[mid])
        visiting.discard(mid)
        out[mid] = row
        return row

    result = {}
    for mid in raw:
        p = resolve(mid)
        result[mid] = {
            "hp": _float(p.get("MaxDamage"), 0.0),
            "mass": max(1, _int(p.get("Mass"), 1)),
            "glue": max(0, _int(p.get("stability_glue"), 0)),
            "category": p.get("damage_category", ""),
        }
    return result


def parse_blocks_xml(text: str) -> dict:
    """blocks.xml → {name: {props, classes, extends}}，处理方块 Extends。"""
    if not text:
        return {}
    root = ET.fromstring(text)
    raw = {}
    for el in root.findall("block"):
        name = el.get("name")
        if not name:
            continue
        props, classes = {}, {}
        for pr in el.findall("property"):
            cls = pr.get("class")
            if cls:
                classes[cls] = {p.get("name"): p.get("value", "") for p in pr.findall("property") if p.get("name")}
            elif pr.get("name"):
                props[pr.get("name")] = pr.get("value", "")
        raw[name] = {"props": props, "classes": classes, "extends": props.get("Extends", "")}
    out, visiting = {}, set()

    def resolve(name):
        if name in out:
            return out[name]
        if name in visiting or name not in raw:
            return {"props": {}, "classes": {}, "extends": ""}
        visiting.add(name)
        row = {"props": {}, "classes": {}, "extends": ""}
        parent = raw[name].get("extends")
        if parent:
            row = resolve(parent)
            row = {"props": dict(row["props"]), "classes": {k: dict(v) for k, v in row["classes"].items()}, "extends": ""}
        row["props"].update(raw[name]["props"])
        for k, v in raw[name]["classes"].items():
            row["classes"].setdefault(k, {}).update(v)
        visiting.discard(name)
        out[name] = row
        return row

    return {name: resolve(name) for name in raw}


def build_blocks(blocks: dict, materials: dict, wanted) -> dict:
    """官方 blocks.xml + materials.xml → 建造方块表（血量、升级、修理、稳定、贴图编号）。"""
    out = {}
    for name in wanted:
        if name == "bedroll":  # 睡袋是实体，不是建造方块；官方血量 1 不适合当墙
            continue
        row = blocks.get(name)
        if not row:
            continue
        props, classes = row["props"], row["classes"]
        mat = materials.get(props.get("Material", ""), {})
        hp = _float(mat.get("hp"), 0.0) or _float(props.get("MaxDamage"), 0.0)
        if hp <= 0:
            continue
        repair = []
        for item, count in classes.get("RepairItems", {}).items():
            repair.append({"item": item, "count": max(1, _int(count, 1))})
        up = classes.get("UpgradeBlock", {})
        upgrade = {}
        to = base_name(up.get("ToBlock", ""))
        if to and to in wanted:
            upgrade = {
                "to": to,
                "item": up.get("Item", ""),
                "count": max(1, _int(up.get("ItemCount"), 1)),
                "hits": max(1, _int(up.get("UpgradeHitCount"), 4)),
                "sound": props.get("UpgradeSound", ""),
            }
        mass = max(1, _int(mat.get("mass"), 1))
        glue = max(0, _int(mat.get("glue"), 0))
        tex = re.findall(r"\d+", props.get("Texture", ""))
        out[name] = {
            "id": name,
            "hp": hp,
            "mass": mass,
            "glue": glue,
            "overhang": max(1, min(16, glue // mass)) if glue else 0,
            "category": mat.get("category", ""),
            "texture": int(tex[0]) if tex else 0,
            "repair": repair,
            "upgrade": upgrade,
        }
    return out


def block_names_from_gd(text: str) -> list:
    return [b["id"] for b in block_types_from_gd(text)]


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


# —— 掉落表（loot.xml）——

def _loot_count(value, default):
    """count="1" / "1,3" / "all" → (min, max) 或 "all"。"""
    if value is None or str(value).strip() == "":
        return default
    v = str(value).strip().lower()
    if v == "all":
        return "all"
    nums = [int(float(x)) for x in re.findall(r"-?\d+(?:\.\d+)?", v)]
    if not nums:
        return default
    if len(nums) == 1:
        return (nums[0], nums[0])
    return (min(nums[0], nums[1]), max(nums[0], nums[1]))


def _level_range(value):
    nums = [int(float(x)) for x in re.findall(r"-?\d+(?:\.\d+)?", str(value or ""))]
    if not nums:
        return (0, 999999)
    if len(nums) == 1:
        return (nums[0], nums[0])
    return (min(nums[0], nums[1]), max(nums[0], nums[1]))


def _loot_entry(el) -> dict:
    out = {}
    if el.get("group"):
        out["group"] = el.get("group")
    else:
        out["item"] = el.get("name", "")
    out["count"] = _loot_count(el.get("count"), (1, 1))
    if el.get("prob") not in (None, ""):
        out["prob"] = _float(el.get("prob"), 1.0)
    if el.get("loot_prob_template"):
        out["prob_template"] = el.get("loot_prob_template")
    return out


def parse_loot_xml(text: str) -> dict:
    """loot.xml → {prob, quality, groups, containers}，保留引用，build_loot 再裁剪。

    带 <requirement> 的条目（需要技能/书）先丢掉，手机版不做技能门槛。
    """
    root = ET.fromstring(text)
    prob = {}
    for tpl in root.iter("lootprobtemplate"):
        name = tpl.get("name")
        if not name:
            continue
        rows = []
        for el in tpl.findall("loot"):
            lo, hi = _level_range(el.get("level"))
            rows.append((lo, hi, _float(el.get("prob"), 0.0)))
        prob[name] = rows
    quality = {}
    for tpl in root.iter("lootqualitytemplate"):
        name = tpl.get("name")
        if not name:
            continue
        rows = []
        for el in tpl.findall("qualitytemplate"):
            lo, hi = _level_range(el.get("level"))
            rolls = [(_int(q.get("quality"), 1), _float(q.get("prob"), 1.0))
                     for q in el.findall("loot")]
            rows.append({"level": [lo, hi], "default": _int(el.get("default_quality"), 1),
                         "loot": [list(r) for r in rolls]})
        quality[name] = rows
    groups = {}
    for el in root.findall("lootgroup"):
        name = el.get("name")
        if not name:
            continue
        items, dropped = [], 0
        for it in el.findall("item"):
            if it.find("requirement") is not None:
                dropped += 1
                continue
            items.append(_loot_entry(it))
        # 官方默认：组没写 count 时只抽 1 个；写 count="all" 才全部过一遍
        groups[name] = {"count": _loot_count(el.get("count"), (1, 1)), "items": items,
                        "dropped": dropped}
    containers = {}
    for el in root.findall("lootcontainer"):
        name = el.get("name")
        if not name:
            continue
        items, dropped = [], 0
        for it in el.findall("item"):
            if it.find("requirement") is not None:
                dropped += 1
                continue
            items.append(_loot_entry(it))
        containers[name] = {
            "count": _loot_count(el.get("count"), (1, 1)),
            "quality": el.get("loot_quality_template", ""),
            "items": items,
            "dropped": dropped,
        }
    return {"prob": prob, "quality": quality, "groups": groups, "containers": containers}


def _prune_loot(loot: dict, items: dict) -> tuple:
    """只保留物品表里有的物品；空组、空容器去掉。返回 (裁剪后的表, 统计)。"""
    stats = {"items": 0, "groups": 0, "containers": 0, "requirements": 0}
    groups = loot["groups"]
    kept = {}

    def prune_group(name, visiting):
        if name in kept:
            return True
        if name in visiting:
            return False
        visiting.add(name)
        g = groups.get(name)
        if g is None:
            visiting.discard(name)
            return False
        out = []
        for e in g["items"]:
            if "group" in e:
                if prune_group(e["group"], visiting):
                    out.append(e)
                else:
                    stats["items"] += 1
            elif e.get("item", "") in items:
                out.append(e)
            else:
                stats["items"] += 1
        visiting.discard(name)
        stats["requirements"] += g.get("dropped", 0)
        if not out:
            stats["groups"] += 1
            return False
        kept[name] = {"count": g["count"], "items": out}
        return True

    for name in list(groups):
        prune_group(name, set())

    containers = {}
    for name, c in loot["containers"].items():
        out = []
        for e in c["items"]:
            if "group" in e:
                if e["group"] in kept:
                    out.append(e)
                else:
                    stats["items"] += 1
            elif e.get("item", "") in items:
                out.append(e)
            else:
                stats["items"] += 1
        stats["requirements"] += c.get("dropped", 0)
        if not out:
            stats["containers"] += 1
            continue
        containers[name] = {"count": c["count"], "quality": c["quality"], "items": out}
    return {"prob": loot["prob"], "quality": loot["quality"], "groups": kept,
            "containers": containers}, stats


def build_loot(loot_xml: str, items: dict) -> tuple:
    """loot.xml + items.json → (loot.json 表, 统计)。"""
    return _prune_loot(parse_loot_xml(loot_xml), items)


# —— 采集（blocks.xml 的 Harvest / Destroy 掉落）——

## 街边物件对不上具体方块，按材质取这些官方方块做代表
HARVEST_MATERIAL_BLOCKS = {
    "metal": ("cntTiltTruckEmpty", "electricalBox01", "cntWallSafeOpen"),
    "wood": ("woodShapes",),
    "stone": ("concreteShapes", "palletBagConcreteBaseFull"),
    "trash": ("cntTrashPile01", "garbage_decor1", "garbage_decor2"),
}


def _count_pair(value):
    nums = [int(float(x)) for x in re.findall(r"-?\d+(?:\.\d+)?", str(value or ""))]
    if not nums:
        return (1, 1)
    return (min(nums[0], nums[1]), max(nums[0], nums[1])) if len(nums) > 1 else (nums[0], nums[0])


def parse_block_drops(blocks_xml: str, wanted) -> dict:
    """blocks.xml → {方块名: {harvest: [...], destroy: [...]}}，只要 wanted 里的方块。"""
    root = ET.fromstring(blocks_xml)
    out = {}
    for el in root.iter("block"):
        name = el.get("name")
        if name not in wanted:
            continue
        harvest, destroy = [], []
        for d in el.findall("drop"):
            event = d.get("event")
            item = d.get("name", "")
            if event not in ("Harvest", "Destroy") or not item:
                continue
            lo, hi = _count_pair(d.get("count"))
            if hi <= 0:
                continue
            row = {"id": item, "count": [lo, hi], "prob": _float(d.get("prob"), 1.0)}
            (harvest if event == "Harvest" else destroy).append(row)
        out[name] = {"harvest": harvest, "destroy": destroy}
    return out


def build_harvest(blocks_xml: str, items: dict) -> dict:
    """官方方块掉落 → {materials: {metal/wood/stone/trash: {harvest, destroy}}}。"""
    wanted = {b for blocks in HARVEST_MATERIAL_BLOCKS.values() for b in blocks}
    parsed = parse_block_drops(blocks_xml, wanted)
    out = {"materials": {}}
    for mat, blocks in HARVEST_MATERIAL_BLOCKS.items():
        harvest, destroy = [], []
        for b in blocks:
            e = parsed.get(b)
            if e:
                harvest += e["harvest"]
                destroy += e["destroy"]
        kept_h = [r for r in harvest if r["id"] in items]
        kept_d = [r for r in destroy if r["id"] in items]
        out["materials"][mat] = {"harvest": kept_h, "destroy": kept_d}
        print(f"  采集 {mat}: 方块 {len(blocks)} 个，Harvest {len(kept_h)} 条，Destroy {len(kept_d)} 条"
              f"（丢掉 {len(harvest) - len(kept_h) + len(destroy) - len(kept_d)} 条不在物品表）")
    return out


# —— 僵尸种类（entityclasses.xml）——

def _parse_entityclasses(text: str) -> tuple:
    root = ET.fromstring(text)
    vars_ = {}
    for wrapper in ("replace_properties", "replace_passive_effect"):
        for rp in root.iter(wrapper):
            for pr in rp.iter("property"):
                n = pr.get("name")
                if n:
                    vars_[n] = pr.get("value", "")
    raw = {}
    for el in root.iter("entity_class"):
        name = el.get("name")
        if not name:
            continue
        props = {}
        for pr in el.findall("property"):
            k = pr.get("name")
            if k:
                props[k] = pr.get("value", "")
        effects = [{"name": pe.get("name"), "operation": pe.get("operation"),
                    "value": pe.get("value", "")} for pe in el.iter("passive_effect")]
        raw[name] = {"extends": el.get("extends", ""), "props": props, "effects": effects}
    return raw, vars_


def _expand_var(value, vars_: dict, depth=0):
    if not isinstance(value, str) or not value.startswith("^") or depth > 6:
        return value
    return _expand_var(vars_.get(value[1:], ""), vars_, depth + 1)


def _resolve_class(name: str, raw: dict, memo: dict) -> tuple:
    if name in memo:
        return memo[name]
    r = raw.get(name, {})
    props, effects, order = {}, {}, []
    parent = r.get("extends", "")
    if parent and parent in raw and parent != name:
        p_props, p_effects, p_order = _resolve_class(parent, raw, memo)
        props.update(p_props)
        effects.update(p_effects)
        order = list(p_order)
    props.update(r.get("props", {}))
    for e in r.get("effects", []):
        key = (e.get("name"), e.get("operation"))
        effects[key] = e.get("value", "")
        if key not in order:
            order.append(key)
    memo[name] = (props, effects, order)
    return memo[name]


def build_entityclasses(text: str, items: dict, loc: dict) -> dict:
    """entityclasses.xml → {官方类名: {model, name, hp, speed, damage, xp, feral, radiated, special}}"""
    raw, vars_ = _parse_entityclasses(text)
    memo = {}
    out = {}
    for name in raw:
        model = zombie_model(name)
        if not model:
            continue
        props, effects, _ = _resolve_class(name, raw, memo)
        tags = _expand_var(props.get("Tags", ""), vars_)
        tags_low = tags.lower()
        if "zombie" not in tags_low.split(","):
            continue
        hp_raw = effects.get(("HealthMax", "base_set"))
        if hp_raw is None:
            continue
        hp = _int(_expand_var(hp_raw, vars_), 0)
        if hp <= 0:
            continue
        agg = _expand_var(props.get("MoveSpeedAggro", ""), vars_)
        nums = [float(x) for x in re.findall(r"-?(?:\d+(?:\.\d+)?|\.\d+)", agg)]
        if nums:
            speed = max(nums)
        else:
            speed = _float(_expand_var(props.get("MoveSpeed", "1"), vars_), 1.0)
        hand = _expand_var(props.get("HandItem", ""), vars_)
        hand_dmg = float(items.get(hand, {}).get("damage", 0.0)) if hand else 0.0
        entity_dmg = _float(_expand_var(props.get("EntityDamage", "0"), vars_), 0.0)
        xp = _int(_expand_var(props.get("ExperienceGain", "0"), vars_), 0)
        low = name.lower()
        if low.endswith("charged") or low.endswith("infernal"):
            continue
        special = ""
        if "zombiecop" in tags_low or "fatcop" in low:
            special = "cop"
        if "demolition" in low:
            special = "demolition"
        elif "spider" in tags_low:
            special = "spider"
        elif "crawler" in tags_low:
            special = "crawler"
        elif "screamer" in tags_low or "screamer" in low:
            special = "screamer"
        elif model == "bigmama":
            special = "bigmama"
        elif "dog" in tags_low:
            special = "dog"
        out[name] = {
            "class": name,
            "model": model,
            "name": loc.get(name) or loc.get(name + "Name") or name,
            "hp": hp,
            "speed": round(speed, 3),
            "damage": round(hand_dmg, 2),
            "entity_damage": round(entity_dmg, 2),
            "xp": xp,
            "feral": "feral" in tags_low or name.endswith("Feral"),
            "radiated": name.endswith("Radiated") or "radiated" in tags_low,
            "special": special,
            "spawn": "dog" not in tags_low,
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
    if cache.exists() and zipfile.is_zipfile(cache):
        print(f"配置文件: 用缓存 {cache}")
        return cache
    if cache.exists():
        print(f"配置文件: 缓存损坏，重新下载 {cache}")
        cache.unlink()
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
    tmp = cache.with_name(cache.name + ".part")
    try:
        with urllib.request.urlopen(req, timeout=300) as r, open(tmp, "wb") as f:
            while True:
                chunk = r.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
        if not zipfile.is_zipfile(tmp):
            raise RuntimeError(f"{ZIP_NAME} 下载不完整")
        os.replace(tmp, cache)
    finally:
        if tmp.exists():
            tmp.unlink()
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


PROGRESSION_PERKS = [
    "perkDeadEye", "perkLuckyLooter", "perkSalvageOperations", "perkBoomstick",
    "perkPummelPete", "perkMotherLode", "perkPackMule", "perkBrawler",
    "perkMachineGunner", "perkHealingFactor", "perkRuleOneCardio", "perkArchery",
    "perkGunslinger", "perkDeepCuts", "perkParkour", "perkFromTheShadows",
    "perkBetterBarter", "perkPhysician", "perkAdvancedEngineering",
]
PROGRESSION_ATTRS = ["attPerception", "attStrength", "attFortitude", "attAgility", "attIntellect"]


def _expand_effect_levels(level_text: str, value_text: str) -> list:
    """passive_effect 的 level/value：两个数是等级区间 + 线性插值，多个数是逐级数值。"""
    levels = [float(x) for x in level_text.split(",") if x.strip()]
    values = [float(x) for x in value_text.split(",") if x.strip()]
    if not levels or not values:
        return []
    if len(levels) == 2 and len(values) == 2:
        lo, hi = int(levels[0]), int(levels[1])
        if lo == hi:
            return [[lo, values[0]]]
        n = abs(hi - lo)
        step = 1 if hi > lo else -1
        return [[lo + step * i, round(values[0] + (values[1] - values[0]) * i / n, 4)]
                for i in range(n + 1)]
    if len(values) == 1:
        return [[int(l), values[0]] for l in levels]
    return [[int(levels[i]), values[i]] for i in range(min(len(levels), len(values)))]


def parse_progression(prog_xml: str, loc: dict) -> dict:
    """progression.xml → 等级、属性、技能（只保留任务 7a 要的 19 个技能）。"""
    root = ET.fromstring(prog_xml)
    out = {"level": {}, "attributes": {}, "skills": {}}
    lv = root.find("level")
    for key in ("max_level", "exp_to_level", "experience_multiplier",
                "skill_points_per_level", "clamp_exp_cost_at_level"):
        raw = lv.get(key, "0") if lv is not None else "0"
        out["level"][key] = float(raw) if "." in raw else int(raw)
    skills = {s.get("name"): s for s in root.iter("skill")}
    perks = {p.get("name"): p for p in root.iter("perk")}
    attrs = root.find("attributes")
    if attrs is not None:
        for a in attrs.findall("attribute"):
            name = a.get("name")
            if name not in PROGRESSION_ATTRS:
                continue
            out["attributes"][name] = {
                "name": loc.get(a.get("name_key", ""), a.get("name_key", name)),
                "desc": loc.get(a.get("desc_key", ""), ""),
                "min": int(a.get("min_level", 1)),
                "max": int(a.get("max_level", 10)),
                "cost": int(a.get("base_skill_point_cost", 1) or 1),
                "cost_mult": float(a.get("cost_multiplier_per_level", 1.14)),
                "skills": [],
            }
    for perk_name in PROGRESSION_PERKS:
        p = perks.get(perk_name)
        if p is None:
            print(f"  进度表里没有 {perk_name}，跳过")
            continue
        sk = skills.get(p.get("parent", ""))
        attr = sk.get("parent") if sk is not None else p.get("parent", "")
        # 通用技能（幸运搜刮）放进感知列，面板保持 5 列
        if attr not in out["attributes"]:
            attr = "attPerception"
        costs = [int(x) for x in (p.get("override_cost") or "1,1,1,1,1").split(",")]
        effects = []
        for pe in p.iter("passive_effect"):
            pname = pe.get("name")
            if not pname:
                continue
            vals = _expand_effect_levels(pe.get("level", ""), pe.get("value", ""))
            if not vals:
                continue
            effects.append({"name": pname, "op": pe.get("operation", ""),
                            "tags": pe.get("tags", ""), "vals": vals,
                            "req": pe.find("requirement") is not None})
        ranks = {}
        for ed in p.iter("effect_description"):
            level = int(ed.get("level", 0))
            key = ed.get("long_desc_key") or ed.get("desc_key") or ""
            text = loc.get(key, "") or loc.get(ed.get("desc_key", ""), "")
            if level > 0 and text:
                ranks[str(level)] = text
        out["skills"][perk_name] = {
            "name": loc.get(p.get("name_key", ""), p.get("name_key", perk_name)),
            "desc": loc.get(p.get("desc_key", ""), ""),
            "attr": attr,
            "max": len(costs),
            "costs": costs,
            "effects": effects,
            "ranks": ranks,
        }
        out["attributes"][attr]["skills"].append(perk_name)
    return out


def build_progression(prog_xml: str, loc: dict, dest: Path) -> dict:
    out = parse_progression(prog_xml, loc)
    out_dir = dest / "data"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "progression.json"
    path.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    n_eff = sum(len(s["effects"]) for s in out["skills"].values())
    print(f"等级/技能: {len(out['skills'])} 个技能、{n_eff} 条 passive_effect → {path}")
    return out


MAGAZINE_SKIP = re.compile(r"master|admin|questReward|modGun", re.I)
TAG_TO_CRAFT = {
    "perkGunslinger": "craftingHandguns", "handgunSkill": "craftingHandguns",
    "perkDeadEye": "craftingRifles", "rifleSkill": "craftingRifles",
    "perkBoomstick": "craftingShotguns", "shotgunSkill": "craftingShotguns",
    "perkMachineGunner": "craftingMachineGuns", "machinegunSkill": "craftingMachineGuns",
    "perkArchery": "craftingBows", "bowSkill": "craftingBows",
    "perkJavelinMaster": "craftingSpears", "spearSkill": "craftingSpears",
    "perkPummelPete": "craftingClubs", "clubSkill": "craftingClubs",
    "perkDeepCuts": "craftingBlades", "bladeSkill": "craftingBlades",
    "perkSkullCrusher": "craftingSledgehammers", "sledgeSkill": "craftingSledgehammers",
    "perkBrawler": "craftingKnuckles", "knuckleSkill": "craftingKnuckles",
    "perkMiner69r": "craftingHarvestingTools", "harvestingSkill": "craftingHarvestingTools",
    "perkSalvageOperations": "craftingSalvageTools", "salvagingSkill": "craftingSalvageTools",
    "repairingSkill": "craftingRepairTools",
    "perkMasterChef": "craftingFood", "cookingPotFood": "craftingFood", "grill": "craftingFood",
    "medicalSkill": "craftingMedical",
    "perkMediumArmor": "craftingArmor", "perkHeavyArmor": "craftingArmor",
    "armorLightSkill": "craftingArmor", "armorMediumSkill": "craftingArmor",
    "armorHeavySkill": "craftingArmor",
    "electricianSkill": "craftingElectrician", "trapsSkill": "craftingTraps",
    "workstationSkill": "craftingWorkstations", "vehiclesSkill": "craftingVehicles",
    "perkAdvancedEngineering": "craftingWorkstations",
}
CRAFT_FALLBACK = {"weapon": "craftingRifles", "tool": "craftingHarvestingTools",
                  "medical": "craftingMedical", "food": "craftingFood",
                  "build": "craftingWorkstations", "ammo": "craftingRifles",
                  "other": "craftingWorkstations"}
BOOK_EFFECTS = {
    "bookShotgunMessiahDamage": ("damage", "perkBoomstick", 0.02),
    "bookSniperDamage": ("damage", "perkDeadEye", 0.02),
    "bookAutoWeaponsDamage": ("damage", "perkMachineGunner", 0.02),
    "bookEnforcerDamage": ("damage", "perkGunslinger", 0.02),
    "bookPistolPeteTakeAim": ("damage", "perkGunslinger", 0.02),
    "bookBarBrawling1BasicMoves": ("damage", "perkBrawler", 0.02),
    "bookBatterUpBigHits": ("damage", "perkPummelPete", 0.02),
    "bookSledgeSagaKnockdown": ("damage", "perkSkullCrusher", 0.02),
    "bookSpearHunter1Damage": ("damage", "perkJavelinMaster", 0.02),
    "bookRangersArrowRecovery": ("damage", "perkArchery", 0.02),
    "bookNightStalkerStealthDamage": ("stealth", "", 0.02),
    "bookArtOfMiningLuckyStrike": ("harvest", "", 0.02),
    "bookTechJunkie1Damage": ("harvest", "", 0.01),
    "bookUrbanCombatLanding": ("stamina", "", 2.0),
    "bookLuckyLooterDukes": ("loot", "", 0.02),
    "bookHuntingJournalBears": ("loot", "", 0.01),
    "bookWasteTreasuresHoney": ("loot", "", 0.02),
    "bookFiremansAlmanacHeat": ("stamina", "", 2.0),
}


def build_magazine_items(items_xml: str, loc: dict) -> dict:
    """官方 crafting 杂志（handgunsSkillMagazine 等）补进物品表，README 的图标没导也能读。"""
    out = {}
    root = ET.fromstring(items_xml)
    for it in root.iter("item"):
        name = it.get("name", "")
        if not name.endswith("SkillMagazine") or MAGAZINE_SKIP.search(name):
            continue
        props = {p.get("name"): p.get("value", "") for p in it.findall("property")}
        if "Unlocks" not in props:
            continue
        out[name] = {
            "id": name, "stack": 20, "value": int(props.get("EconomicValue", 100) or 100),
            "durability": 0.0, "tags": (props.get("Tags", "") + ",books,magazine").strip(","),
            "zh": loc.get(name) or loc.get(props.get("DescriptionKey", "")) or name,
            "magazine": 0, "rpm": 0.0, "ammo": "", "reload": 0.0, "damage": 0.0,
        }
    return out


def _recipe_category(r: dict) -> str:
    for tag in r.get("tags", []):
        if tag in TAG_TO_CRAFT:
            return TAG_TO_CRAFT[tag]
    return CRAFT_FALLBACK.get(str(r.get("cat", "other")), "craftingWorkstations")


def _recipe_level(r: dict, items_table: dict) -> int:
    tags = set(r.get("tags", []))
    item = items_table.get(str(r.get("id", "")), {})
    tags.update(str(item.get("tags", "")).split(","))
    for n in range(5):
        if "T%d" % n in tags:
            return n + 1
    return 1


def build_books(zip_path: Path, dest: Path) -> dict:
    items_path = dest / "data" / "items.json"
    recipes_path = dest / "data" / "recipes.json"
    if not items_path.exists() or not recipes_path.exists():
        sys.exit("找不到 items.json / recipes.json，先生成物品和配方")
    items_table = json.loads(items_path.read_text(encoding="utf-8"))
    recipes = json.loads(recipes_path.read_text(encoding="utf-8"))
    items_xml = read_config_file(zip_path, "items.xml")
    prog_xml = read_config_file(zip_path, "progression.xml")
    loc = load_localization(read_config_file(zip_path, "Localization.csv"))
    if not items_xml or not prog_xml:
        sys.exit(f"{zip_path} 里没有 items.xml 或 progression.xml")
    prog = ET.fromstring(prog_xml)
    categories = {}
    for cs in prog.iter("crafting_skill"):
        name = cs.get("name", "")
        categories[name] = {
            "name": loc.get(cs.get("name_key", ""), cs.get("name_key", name)),
            "desc": loc.get(cs.get("desc_key", ""), ""),
            "max_level": 5,
            "magazines": [],
            "unlocks": {},
        }
    magazines = {}
    root = ET.fromstring(items_xml)
    for it in root.iter("item"):
        name = it.get("name", "")
        if not name.endswith("SkillMagazine") or MAGAZINE_SKIP.search(name):
            continue
        props = {p.get("name"): p.get("value", "") for p in it.findall("property")}
        cat = props.get("Unlocks", "")
        if cat in categories:
            magazines[name] = {"zh": loc.get(name, name), "category": cat,
                               "icon": props.get("CustomIcon", "")}
            categories[cat]["magazines"].append(name)
    for key, r in recipes.items():
        if not r.get("learnable"):
            continue
        cat = _recipe_category(r)
        if cat not in categories:
            continue
        level = _recipe_level(r, items_table)
        categories[cat]["unlocks"][key] = level
    books = {}
    for name, row in items_table.items():
        if name in magazines or not str(row.get("tags", "")).find("books") >= 0:
            continue
        kind, key, value = BOOK_EFFECTS.get(name, ("loot", "", 0.01))
        books[name] = {"zh": row.get("zh", name), "effect": {"type": kind, "key": key, "value": value}}
    out = {"categories": categories, "magazines": magazines, "books": books}
    out_dir = dest / "data"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "books.json"
    path.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    n_unlocks = sum(len(c["unlocks"]) for c in categories.values())
    print(f"书/杂志: {len(magazines)} 本杂志、{len(books)} 本书、{n_unlocks} 条配方解锁 → {path}")
    return out


def parse_traders_xml(traders_xml: str, items_table: dict) -> dict:
    root = ET.fromstring(traders_xml)
    info = root.find("trader_info")
    open_t = str(info.get("open_time", "4:05")) if info is not None else "4:05"
    close_t = str(info.get("close_time", "21:50")) if info is not None else "21:50"

    def to_hours(text: str) -> float:
        p = text.split(":")
        return int(p[0]) + (int(p[1]) if len(p) > 1 else 0) / 60.0

    pool = {}
    for name, row in items_table.items():
        low = name.lower()
        if any(w in low for w in ("admin", "test", "master", "dev", "poi", "schematic", "quest")):
            continue
        value = int(row.get("value", 0))
        if value > 0:
            pool[name] = value
    reset = int(info.get("reset_interval", 3)) if info is not None else 3
    return {
        "open": round(to_hours(open_t), 4), "close": round(to_hours(close_t), 4),
        "reset_days": max(1, reset),
        "currency": root.get("currency_item", "casinoCoin"),
        "sell_markdown": float(root.get("sell_markdown", "0.2") or 0.2),
        "items": pool,
    }


def build_traders(zip_path: Path, dest: Path) -> dict:
    items_path = dest / "data" / "items.json"
    if not items_path.exists():
        sys.exit("找不到 items.json，先生成物品")
    items_table = json.loads(items_path.read_text(encoding="utf-8"))
    traders_xml = read_config_file(zip_path, "traders.xml")
    if not traders_xml:
        sys.exit(f"{zip_path} 里没有 Config/traders.xml")
    out = parse_traders_xml(traders_xml, items_table)
    path = dest / "data" / "traders.json"
    path.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"商人: {out['open']:.2f}-{out['close']:.2f} 点，{out['reset_days']} 天重置，"
          f"{len(out['items'])} 种可售物品，货币 {out['currency']} → {path}")
    return out


QUEST_IDS = {
    (1, "fetch"): "tier1_fetch", (1, "clear"): "tier1_clear",
    (1, "buried"): "tier1_buried_supplies",
    (2, "fetch"): "tier2_fetch", (2, "clear"): "tier2_clear",
    (2, "buried"): "tier2_buried_supplies",
}


def build_quests(zip_path: Path, dest: Path) -> dict:
    quests_xml = read_config_file(zip_path, "quests.xml")
    if not quests_xml:
        sys.exit(f"{zip_path} 里没有 Config/quests.xml")
    loc = load_localization(read_config_file(zip_path, "Localization.csv"))
    root = ET.fromstring(quests_xml)
    out = {"tier1": {}, "tier2": {}, "choices": 3}
    for (tier, kind), qid in QUEST_IDS.items():
        el = root.find(f".//quest[@id='{qid}']")
        if el is None:
            continue
        xp, coins = 0, 0
        for r in el.findall("reward"):
            if r.get("type") == "Exp":
                xp = int(float(r.get("value", 0) or 0))
            elif r.get("type") == "Item" and r.get("id") == "casinoCoin":
                coins = int(float(r.get("value", 0) or 0))
        name_key = f"quest_tier{tier}_{kind}" if tier == 2 else f"quest_tier1_{kind}"
        desc_key = {"fetch": "quest_fetch_description", "clear": "quest_clear_description",
                    "buried": "quest_buried_supplies_description"}[kind]
        fallback = {"fetch": "取货", "clear": "清剿", "buried": "埋藏补给"}[kind]
        name = loc.get(name_key) or loc.get(f"quest_tier1_{kind}") or fallback
        if tier == 2:
            name = "T2 " + name
        out[f"tier{tier}"][kind] = {
            "name": name,
            "desc": loc.get(desc_key, ""),
            "xp": xp, "coins": coins,
        }
    path = dest / "data" / "quests.json"
    path.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"商人任务: tier1 {len(out['tier1'])} 种、tier2 {len(out['tier2'])} 种 → {path}")
    return out


def build_all(dest: Path, zip_path: Path, index_path: Path, only: str = "all") -> dict:
    items_xml, loc_csv, gs_xml, eg_xml = read_config_zip(zip_path)
    gd_text = (ROOT / "scripts" / "blocks.gd").read_text(encoding="utf-8")
    official = {}
    if only in ("blocks", "items", "all"):
        official = build_blocks(
            parse_blocks_xml(read_config_file(zip_path, "blocks.xml")),
            parse_materials_xml(read_config_file(zip_path, "materials.xml")),
            block_names_from_gd(gd_text),
        )
    if only in ("blocks", "all"):
        out_dir = dest / "data"
        out_dir.mkdir(parents=True, exist_ok=True)
        path = out_dir / "blocks.json"
        path.write_text(json.dumps(official, ensure_ascii=False, indent=1), encoding="utf-8")
        missing = [i for i in block_names_from_gd(gd_text) if i not in official]
        print(f"方块配置: 官方 {len(official)} 个 → {path}")
        if missing:
            print(f"  blocks.xml 里没有、用脚本默认值的: {', '.join(missing)}")
    if only in ("items", "all"):
        items = parse_items_xml(items_xml)
        loc = load_localization(loc_csv)
        if not index_path.exists():
            sys.exit(f"找不到物品索引 {index_path}，先运行 tools/fetch_assets.py 的 fetch_index")
        index_rows = json.loads(index_path.read_text(encoding="utf-8"))
        blocks = block_types_from_gd(gd_text)
        for b in blocks:
            if b["id"] in official:
                b["hp"] = official[b["id"]]["hp"]
        out = build_items(items, loc, index_rows, blocks)
        out.update(build_magazine_items(items_xml, loc))
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
    if only in ("loot", "all"):
        items_path = dest / "data" / "items.json"
        if not items_path.exists():
            sys.exit(f"找不到 {items_path}，先运行 --only items")
        items_table = json.loads(items_path.read_text(encoding="utf-8"))
        loot_xml = read_config_file(zip_path, "loot.xml")
        if not loot_xml:
            sys.exit(f"{zip_path} 里没有 Config/loot.xml")
        loot, stats = build_loot(loot_xml, items_table)
        path = dest / "data" / "loot.json"
        path.write_text(json.dumps(loot, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"掉落表: 容器 {len(loot['containers'])} 个，组 {len(loot['groups'])} 个；"
              f"丢掉物品条目 {stats['items']}、空组 {stats['groups']}、空容器 {stats['containers']}、"
              f"需要技能的条目 {stats['requirements']} → {path}")
    if only in ("entities", "all"):
        items_table = parse_items_xml(items_xml)
        ec_xml = read_config_file(zip_path, "entityclasses.xml")
        if not ec_xml:
            sys.exit(f"{zip_path} 里没有 Config/entityclasses.xml")
        loc = load_localization(loc_csv)
        table = build_entityclasses(ec_xml, items_table, loc)
        path = dest / "data" / "zombies.json"
        path.write_text(json.dumps(table, ensure_ascii=False, indent=1), encoding="utf-8")
        feral = sum(1 for v in table.values() if v["feral"])
        rad = sum(1 for v in table.values() if v["radiated"])
        print(f"僵尸种类: {len(table)} 个（野性 {feral}，辐射 {rad}）→ {path}")
    if only in ("progression", "all"):
        prog_xml = read_config_file(zip_path, "progression.xml")
        if not prog_xml:
            sys.exit(f"{zip_path} 里没有 Config/progression.xml")
        build_progression(prog_xml, load_localization(loc_csv), dest)
    if only in ("harvest", "all"):
        items_path = dest / "data" / "items.json"
        if not items_path.exists():
            sys.exit(f"找不到 {items_path}，先运行 --only items")
        items_table = json.loads(items_path.read_text(encoding="utf-8"))
        blocks_xml = read_config_file(zip_path, "blocks.xml")
        if not blocks_xml:
            sys.exit(f"{zip_path} 里没有 Config/blocks.xml")
        harvest = build_harvest(blocks_xml, items_table)
        path = dest / "data" / "harvest.json"
        path.write_text(json.dumps(harvest, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"采集表: {len(harvest['materials'])} 种材质 → {path}")
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
    if only in ("books", "all"):
        build_books(zip_path, dest)
    if only in ("traders", "all"):
        build_traders(zip_path, dest)
    if only in ("quests", "all"):
        build_quests(zip_path, dest)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dest", default=str(DEFAULT_DEST), help="assets 目录")
    ap.add_argument("--zip", default="", help="本地 Data_Config.zip（不传就从云盘下载）")
    ap.add_argument("--index", default="", help="icon_to_model.json（默认 assets/index/）")
    ap.add_argument("--only", default="all", choices=["all", "items", "buffs", "gamestages", "entitygroups", "entities", "recipes", "loot", "harvest", "blocks", "progression", "books", "traders", "quests"], help="只生成某张表")
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
