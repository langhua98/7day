#!/usr/bin/env python3
"""官方 POI prefab XML → assets/poi/sleepers.json（睡眠区位置、大小、刷怪组）。

坐标和 containers.json 一样：x 是游戏的左手坐标，游戏里会翻成 -x。
Sleepers 里的 Group 是 "组名,最少,最多" 重复；区域顺序和 Start/Size 一一对应。
"""
import json
import xml.etree.ElementTree as ET
from pathlib import Path


def parse_sleepers_xml(text: str) -> list:
    root = ET.fromstring(text)
    fields = {}
    for prop in root.iter("property"):
        name = prop.get("name")
        if name in ("SleeperVolumeStart", "SleeperVolumeSize", "SleeperVolumeGroup"):
            fields[name] = prop.get("value", "")
    starts = [s.strip() for s in fields.get("SleeperVolumeStart", "").split("#") if s.strip()]
    sizes = [s.strip() for s in fields.get("SleeperVolumeSize", "").split("#") if s.strip()]
    groups = [g.strip() for g in fields.get("SleeperVolumeGroup", "").split(",") if g.strip()]
    out = []
    for i, (st, sz) in enumerate(zip(starts, sizes)):
        try:
            sp = [float(v) for v in st.split(",")]
            sd = [float(v) for v in sz.split(",")]
        except ValueError:
            continue
        if len(sp) < 3 or len(sd) < 3:
            continue
        gi = i * 3
        if gi + 2 >= len(groups):
            break
        group = groups[gi]
        try:
            lo = int(float(groups[gi + 1]))
            hi = int(float(groups[gi + 2]))
        except ValueError:
            continue
        if not group or hi <= 0:
            continue
        out.append({
            "x": round(sp[0] + sd[0] / 2, 2), "y": round(sp[1] + sd[1] / 2, 2),
            "z": round(sp[2] + sd[2] / 2, 2),
            "sx": round(sd[0], 2), "sy": round(sd[1], 2), "sz": round(sd[2], 2),
            "group": group, "min": max(0, lo), "max": max(1, hi),
        })
    return out


def parse_poi(path: Path) -> list:
    return parse_sleepers_xml(path.read_text(encoding="utf-8", errors="replace"))


def run(assets) -> dict:
    poi_dir = Path(assets) / "poi"
    out = {}
    for xml in sorted(poi_dir.glob("*.xml")):
        vols = parse_poi(xml)
        if vols:
            out[xml.stem] = vols
    path = poi_dir / "sleepers.json"
    path.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    total = sum(len(v) for v in out.values())
    print(f"睡眠区: {len(out)} 栋楼，{total} 个区域 → {path}")
    return out


if __name__ == "__main__":
    import sys
    run(sys.argv[1] if len(sys.argv) > 1 else str(Path(__file__).resolve().parents[1] / "assets"))
