#!/usr/bin/env python3
"""把编译好的 ipa 传到小桔云盘，并建一个分享链接，方便签名软件直接下载。

用法：XIAOJU_TOKEN=... python3 tools/publish_ipa.py build/7day-unsigned.ipa
链接会打印到日志，并写进 GitHub Actions 的运行摘要页面。
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

API = os.environ.get("XIAOJU_API", "https://langhua1998-xiaoju-cloud.hf.space/api/agent/v1")
SITE = API.split("/api/")[0]
FOLDER = os.environ.get("XIAOJU_IPA_FOLDER", "/7day/安装包")


def call(method, endpoint, body=None, raw=None, query=None):
    url = API + endpoint
    if query:
        url += "?" + urllib.parse.urlencode(query)
    headers = {"Authorization": "Bearer " + os.environ["XIAOJU_TOKEN"]}
    data = raw
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    elif raw is not None:
        headers["Content-Type"] = "application/octet-stream"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            text = r.read().decode("utf-8", "replace")
            return r.status, text
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")


def parse(text):
    try:
        return json.loads(text)
    except ValueError:
        return None


def find_links(obj):
    """从返回的 JSON 里找出所有像链接的字段。"""
    found = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, str) and (v.startswith("http") or (v.startswith("/") and "share" in k.lower() + v.lower())):
                found.append(v if v.startswith("http") else SITE + v)
            else:
                found += find_links(v)
    elif isinstance(obj, list):
        for v in obj:
            found += find_links(v)
    return found


def direct_links(share):
    """分享返回的是网页地址（share.html#口令），签名软件要的是文件直链。
    用口令去公开接口 /api/s/口令 换出 /dl/ 直链（有效约 6 小时）。"""
    web = share.get("web_path", "")
    if "#" not in web:
        return []
    code = web.split("#", 1)[1]
    try:
        with urllib.request.urlopen(f"{SITE}/api/s/{code}", timeout=60) as r:
            data = json.load(r)
    except Exception as e:  # noqa: BLE001
        print("换直链失败：", e)
        return []
    return [SITE + it["url"] for it in data.get("items", []) if it.get("url")]


def summary(lines):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")


def main():
    ipa = sys.argv[1]
    run = os.environ.get("GITHUB_RUN_NUMBER", "local")
    name = f"7day-{run}.ipa"
    data = open(ipa, "rb").read()
    print(f"上传 {name}（{len(data) / 1e6:.1f}MB）到 {FOLDER} …")

    item = None
    for folder in (FOLDER, "/7day"):
        status, text = call("PUT", "/files", raw=data, query={"path": f"{folder}/{name}"})
        print("PUT", folder, status, text[:500])
        if status < 300:
            item = parse(text) or {}
            item = item.get("item", item)
            break
    if not item or not item.get("id"):
        print("::error::上传到云盘失败")
        return 1

    item_id = item["id"]
    drive_path = item.get("path", f"{FOLDER}/{name}")
    share = None
    for body in ({"id": item_id}, {"item_id": item_id}, {"path": drive_path}, {"item": item_id}):
        status, text = call("POST", "/shares", body=body)
        print("POST /shares", list(body)[0], status, text[:800])
        if status < 300:
            share = parse(text) or {}
            break

    lines = [f"### 安装包已上传到小桔云盘", f"- 云盘位置：`{drive_path}`"]
    if share is not None:
        links = direct_links(share) or find_links(share)
        for link in links:
            print(f"::notice title=ipa 下载链接::{link}")
            lines.append(f"- 下载链接：{link}")
        if not links:
            print("分享已创建，但返回里没找到链接：", json.dumps(share, ensure_ascii=False))
            lines.append("- 分享已创建，返回内容：`" + json.dumps(share, ensure_ascii=False)[:500] + "`")
    else:
        print("::warning::建分享链接失败，可以在云盘网页上手动分享这个文件")
        lines.append("- 建分享链接失败，可以在云盘网页上手动分享这个文件")
    summary(lines)
    return 0


if __name__ == "__main__":
    sys.exit(main())
