#!/usr/bin/env python3
"""Build the 7DTD asset lookup tables from the raw index files.

Reads research/7dtd-index/raw/ and writes CSV tables to research/7dtd-index/.
Only metadata is handled here: names, ids, bundle paths and drive paths.
No game asset is read or written.

Usage: python3 tools/build_7dtd_index.py
"""
import csv
import json
import os
from collections import Counter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "research", "7dtd-index")
RAW = os.path.join(ROOT, "raw")
DRIVE_EXPORT = "/7day/小橘素材库/"  # default folder for bundles not uploaded yet
# The full upload finished 2026-10-22 09:43 UTC. Bundles with no zip after that
# had nothing to export, so they are marked "empty" instead of "pending".
UPLOAD_COMPLETE = True
DRIVE_ICONS = "/7day/物品图标/item_icons_5188.zip"


def load(name):
    with open(os.path.join(RAW, name), encoding="utf-8") as f:
        return json.load(f)


inventory = {}
with open(os.path.join(RAW, "bundle_inventory.jsonl"), encoding="utf-8") as f:
    for line in f:
        if line.strip():
            b = json.loads(line)
            inventory[b["bundle"]] = b

uploaded = {}
with open(os.path.join(RAW, "drive_paths.tsv"), encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) == 2 and parts[0]:
            uploaded[parts[0]] = int(parts[1])


def bundle_rel(bundle):
    name = bundle[: -len(".bundle")] if bundle.endswith(".bundle") else bundle
    return name + ".zip"


# Bundle zips may sit in any top-level folder of /7day (the folder has been renamed
# while uploads were running), so find each zip by its bundle-relative path.
found_zip = {}
for p in uploaded:
    parts = p.split("/", 3)  # ['', '7day', '<folder>', '<rel>']
    if len(parts) == 4 and p.endswith(".zip"):
        found_zip.setdefault(parts[3], p)


def drive_zip(bundle):
    """Drive path of the export zip for one bundle (empty if no bundle)."""
    if not bundle:
        return ""
    rel = bundle_rel(bundle)
    if rel in found_zip:
        return found_zip[rel]
    return "" if UPLOAD_COMPLETE else DRIVE_EXPORT + rel


def known(bundle):
    return bundle if bundle in inventory else ""


def mesh_to_bundle(mesh):
    """Map an items.xml Meshfile Addressables path to its bundle.

    @:Other/Items/...      -> automatic_assets_other/items.bundle
    @:Entities/<Group>/... -> automatic_assets_entities/<group>.bundle
    """
    if not mesh or not mesh.startswith("@:"):
        return ""
    parts = mesh[2:].split("/")
    if len(parts) < 2:
        return ""
    return known("automatic_assets_%s/%s.bundle" % (parts[0].lower(), parts[1].lower()))


# Armor sets whose bundle name differs from the set name (confirmed by the export thread).
SET_BUNDLE_ALIAS = {"athletic": "fitness", "primitive": "fiber", "rogue": "stealth",
                    "kegbreaker": "oktoberfest"}


def gear_model_to_bundle(model):
    """Map a preview gear model name (gear_<Set>_<source>) to its bundle."""
    parts = model.split("_")
    if len(parts) != 3 or parts[0] != "gear":
        return ""
    s, src = parts[1].lower(), parts[2]
    s = SET_BUNDLE_ALIAS.get(s, s)
    candidates = {
        "male": ["player_assets_entities/player/male/gear/%s.bundle" % s],
        "dlc": ["automatic_assets_dlc/%scosmetic.bundle" % s,
                "automatic_assets_dlc/%scosmetics.bundle" % s],
        "dlc2": ["automatic_assets_dlc/%scosmetic.bundle" % s,
                 "automatic_assets_dlc/%scosmetics.bundle" % s],
        "tw": ["automatic_assets_twitchdrops/%s.bundle" % s],
        "twout": ["automatic_assets_twitchdrops/%sstoregearoutfit.bundle" % s],
        "twhat": ["automatic_assets_twitchdrops/%sstoregearhat.bundle" % s,
                  "automatic_assets_twitchdrops/%shat.bundle" % s],
    }.get(src, [])
    for c in candidates:
        if c in inventory:
            return c
    return ""


def write_csv(name, header, rows):
    path = os.path.join(ROOT, name)
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print("%-16s %5d rows" % (name, len(rows)))


def status(bundle):
    if not bundle:
        return ""
    if drive_zip(bundle) in uploaded:
        return "uploaded"
    return "empty" if UPLOAD_COMPLETE else "pending"


# ---- items.csv: one row per item / block icon ----
icon_rows = load("icon_to_model.json")
item_mesh = load("item_to_mesh.json")
names = {r[0]: (r[1], r[2], r[3]) for r in icon_rows}

# Prefab name (e.g. bookPrefab) -> bundle, learned from items.xml mesh paths.
prefab_bundle = {}
for m in item_mesh.values():
    b = mesh_to_bundle(m["mesh"])
    if b:
        prefab_bundle.setdefault(m["mesh"].rsplit("/", 1)[-1].rsplit(".", 1)[0], b)


def preview_to_bundle(preview):
    if preview.startswith("gear_"):
        return gear_model_to_bundle(preview)
    return prefab_bundle.get(preview, "")


items = []
seen = set()
for item_id, m in sorted(item_mesh.items()):
    zh, en, preview = names.get(item_id) or names.get(m["icon"]) or ("", "", "")
    b = mesh_to_bundle(m["mesh"])
    if not b:
        b = preview_to_bundle(preview)
    items.append([item_id, zh, en, m["icon"], m["tint"] or "", m["mesh"], preview,
                  b, drive_zip(b), status(b), DRIVE_ICONS])
    seen.add(item_id)
for icon, zh, en, preview in icon_rows:
    if icon in seen:
        continue
    b = preview_to_bundle(preview)
    items.append([icon, zh, en, icon, "", "", preview, b, drive_zip(b), status(b), DRIVE_ICONS])
items.sort(key=lambda r: r[0].lower())
write_csv("items.csv",
          ["item_id", "name_zh", "name_en", "icon", "icon_tint", "mesh_path", "preview_model",
           "model_bundle", "drive_zip", "drive_status", "drive_icon_zip"], items)

# ---- characters.csv: player gear sets, zombies, heads, hair ----
char_models = load("character_model_to_bundle.json")
chars = []
for model, bundle in sorted(char_models.items()):
    kind = {"pf": "female_player_gear", "zb": "zombie"}.get(model.split("_")[0], "other")
    b = inventory.get(bundle, {})
    anim = "animations_assets_animations/zombie.bundle" if kind == "zombie" else ""
    chars.append([model, kind, bundle, len(b.get("meshes", [])), len(b.get("textures", [])),
                  drive_zip(bundle), status(bundle), anim, drive_zip(anim)])
# Bundles of characters that have no preview model yet.
listed = set(char_models.values())
for bundle in sorted(inventory):
    if bundle in listed:
        continue
    if bundle.startswith("zombies_assets_entities/"):
        kind = "zombie"
    elif bundle.startswith("player_assets_entities/"):
        kind = "player_" + "_".join(bundle.split("/")[2:4])  # e.g. player_male_hair
    else:
        continue
    b = inventory[bundle]
    anim = "animations_assets_animations/zombie.bundle" if kind == "zombie" else ""
    chars.append(["", kind, bundle, len(b["meshes"]), len(b["textures"]),
                  drive_zip(bundle), status(bundle), anim, drive_zip(anim)])
write_csv("characters.csv",
          ["preview_model", "kind", "bundle", "mesh_count", "texture_count",
           "drive_zip", "drive_status", "animation_bundle", "animation_drive_zip"], chars)

# ---- armor_sets.csv ----
armor = []
for s, srcs in sorted(load("armorset_to_gear_model.json").items()):
    for src, model in sorted(srcs.items()):
        b = gear_model_to_bundle(model)
        armor.append([s, src, model, b, drive_zip(b), status(b)])
write_csv("armor_sets.csv",
          ["armor_set", "source", "preview_model", "bundle", "drive_zip", "drive_status"], armor)

# ---- pois.csv: buildings (prefabs come from server Data/Prefabs, not client bundles) ----
# The raw prefab files for every POI are packed in one zip under /7day/建筑POI/.
POI_ZIP = "/7day/建筑POI/POIs_all_1575.zip"
poi_zip = POI_ZIP if POI_ZIP in uploaded else ""
pois = [[p[0], p[1], p[3], p[4], p[5], poi_zip] for p in load("poi_index.json")]
write_csv("pois.csv", ["poi_file", "name_en", "zoning", "difficulty_tier", "prefab_size_xyz",
                       "drive_zip"], pois)

# ---- bundles.csv: every client bundle and where its export lives ----
# Extra zips exported later for a bundle (e.g. Texture2DArray slices), keyed by bundle.
EXTRA_ZIPS = {
    "terraintextures_assets_all.bundle": "/7day/小橘素材库/terraintextures_arrays.zip",
}
bundles = []
for name, b in sorted(inventory.items()):
    t = b["types"]
    z = drive_zip(name)
    bundles.append([name, name.split("/")[0], b["size"], len(b["meshes"]), len(b["textures"]),
                    t.get("AudioClip", 0), t.get("AnimationClip", 0), t.get("GameObject", 0),
                    z, uploaded.get(z, ""), status(name), b["err"] or "",
                    EXTRA_ZIPS.get(name, "") if EXTRA_ZIPS.get(name) in uploaded else ""])
write_csv("bundles.csv",
          ["bundle", "group", "bundle_bytes", "mesh_count", "texture_count", "audio_count",
           "animation_count", "gameobject_count", "drive_zip", "drive_zip_bytes",
           "drive_status", "extract_error", "extra_drive_zip"], bundles)

# ---- other drive files (music, icons, samples, preview pages) ----
bundle_zips = ({drive_zip(n) for n in inventory} | set(EXTRA_ZIPS.values()) | {POI_ZIP}) - {""}
other = [[p, n] for p, n in sorted(uploaded.items()) if p not in bundle_zips]
write_csv("drive_other.csv", ["drive_path", "bytes"], other)

c = Counter(r[10] for r in bundles)
print("bundles on drive:", dict(c))
