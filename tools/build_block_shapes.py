#!/usr/bin/env python3
"""官方 shapes_by_name.zip → assets/data/block_shapes.json

运行时只读 JSON，不再让 Godot 导入几百个形状 glb。
坐标和绕序沿用 tools/build_poi_full.py 的 load_glb，和楼里的形状一致。
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_poi_full as B

MODELS = {
    "cube": "cube.glb",
    "half": "cubeHalf.glb",
    "ramp": "ramp.glb",
    "stairs": "stairs.glb",
    "pole": "pole.glb",
    "plate": "plate.glb",
}


def collect(path):
    out = []
    for _, tris in B.load_glb(path):
        for tri in tris:
            out.append([[round(float(c), 4) for c in p] for p in tri])
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--shapes", default="assets/shapes")
    ap.add_argument("--dest", default="assets")
    args = ap.parse_args()
    src = os.path.abspath(args.shapes)
    out_dir = os.path.join(os.path.abspath(args.dest), "data")
    os.makedirs(out_dir, exist_ok=True)
    result = {}
    for shape, name in MODELS.items():
        path = os.path.join(src, name)
        if not os.path.exists(path):
            print(f"  缺 {name}，{shape} 先用程序几何")
            continue
        tris = collect(path)
        if not tris:
            print(f"  {name} 没有三角形，{shape} 先用程序几何")
            continue
        result[shape] = tris
        print(f"  {shape}: {name}，{len(tris)} 个三角形")
    out = os.path.join(out_dir, "block_shapes.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, separators=(",", ":"))
    print(f"方块形状: {len(result)} 种 → {out}")


if __name__ == "__main__":
    main()
