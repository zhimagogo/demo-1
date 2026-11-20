#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""demo-1 UI 图标资产管线（第 1 步：抓取 + 清洗）。

来源：game-icons.net 官方 SVG 仓库 https://github.com/game-icons/icons
授权：CC BY 3.0 —— 逐条作者与出处记录到 assets/ui/icons/icons.json / CREDITS.md。

做三件事：
  1) 按 ICONS 表（id → 作者/图标名）从 raw.githubusercontent.com 抓取 SVG；
  2) 清洗成「纯白前景 + 透明底」——删掉整幅黑底矩形、把所有填充强制为 #ffffff，
     这样 Godot 里可以直接用 modulate / self_modulate 任意调色；
  3) 写出 assets/ui/icons/src/<id>.svg（带 .gdignore，不进 Godot 导入）与
     assets/ui/icons/icons.json + CREDITS.md。

第 2 步光栅化由 tools/rasterize_icons.gd 完成（Godot 内建 ThorVG，无需额外依赖）。

用法： python3 tools/fetch_icons.py
"""
from __future__ import annotations

import concurrent.futures
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "ui", "icons")
SRC_DIR = os.path.join(OUT_DIR, "src")
CACHE = os.path.join(ROOT, "tools", "_icon_tree.json")

TREE_API = "https://api.github.com/repos/game-icons/icons/git/trees/master?recursive=1"
RAW = "https://raw.githubusercontent.com/game-icons/icons/master/"

# ---------------------------------------------------------------------------
# 冻结的图标 id 表：id → "作者/图标名"（game-icons.net）。
# id 即运行时文件名（IconDB 约定：res://assets/ui/icons/<id>.png）。
# 面板只能使用下表中的 id；需要新图标时先在这里登记，再重跑本脚本。
# ---------------------------------------------------------------------------
ICONS: dict[str, str] = {
    # —— 资源（GameDefs.resource_defs() 的 id 前缀 res_）——
    "res_wood": "delapouite/log",
    "res_stone": "delapouite/stone-pile",
    "res_food": "lorc/wheat",
    "res_gold": "delapouite/coins",
    # —— 建筑（GameDefs.building_defs() 的 id 前缀 building_）——
    # v22：农田/市集/箭塔随建筑删除一并移出图标库（兵营 v21 已删）；新增酒馆。
    "building_wall": "delapouite/stone-wall",
    "building_house": "delapouite/house",
    "building_tavern": "lorc/glass-shot",
    # —— 顶栏统计 / 时间 / 天气 ——
    "stat_pop": "delapouite/person",
    "stat_soldier": "lorc/visored-helm",
    "stat_hero": "delapouite/knight-banner",
    "stat_enemy": "lorc/wolf-head",
    "time_day": "delapouite/sunrise",
    "time_night": "lorc/moon",
    "weather_clear": "lorc/sunbeams",
    "weather_cloud": "lorc/fluffy-cloud",
    "weather_rain": "lorc/heavy-rain",
    "weather_storm": "lorc/lightning-storm",
    # —— 单位 / 技能 ——
    "unit_melee": "lorc/crossed-swords",
    "unit_ranged": "delapouite/bow-arrow",
    "skill_slash": "lorc/broadsword",
    "skill_flame": "sbed/fire",
    # —— 面板 / 系统语义 ——
    "quest": "lorc/scroll-unfurled",
    "event_log": "lorc/tied-scroll",
    "tutorial": "lorc/open-book",
    "boss": "lorc/daemon-skull",
    "hp": "skoll/hearts",
    "xp": "lorc/medal",
    "map": "lorc/treasure-map",
    "compass": "lorc/compass",
    "warning": "lorc/hazard-sign",
    "close": "sbed/cancel",
    "help": "sbed/help",
    "pause": "guard13007/pause-button",
    "play": "guard13007/play-button",
    "fast_forward": "delapouite/fast-forward-button",
    "home": "delapouite/family-house",
    "tool_hammer": "delapouite/warhammer",
    "target": "delapouite/crosshair",
    "attack": "lorc/crossed-slashes",
    "carry": "lorc/knapsack",
    "shield": "sbed/shield",
    "crown": "lorc/crown",
}


def log(msg: str) -> None:
    print(f"[icons] {msg}", flush=True)


def _meta(icon_id: str, path: str) -> dict:
    """单个图标的署名元数据（作者 = 仓库一级目录名）。"""
    return {
        "id": icon_id,
        "source": "game-icons.net",
        "path": path,
        "author": path.split("/")[0],
        "url": f"https://game-icons.net/1x1/{path[:-4]}.html",
        "raw": RAW + path,
        "license": "CC BY 3.0",
        "png": f"res://assets/ui/icons/{icon_id}.png",
    }


def curl_text(url: str, timeout: int = 60) -> str:
    """用系统 curl 抓取（本机验证：python urllib 会卡住，curl 稳定 <1s）。"""
    out = subprocess.run(
        ["curl", "-sSL", "--max-time", str(timeout), "-A", "demo-1-asset-pipeline", url],
        capture_output=True, check=False,
    )
    if out.returncode != 0 or not out.stdout:
        raise RuntimeError(f"curl 失败 rc={out.returncode} {url}")
    return out.stdout.decode("utf-8")


def fetch_tree() -> dict:
    """取 game-icons 仓库文件树（本地缓存，避免反复打 GitHub API）。"""
    if os.path.exists(CACHE) and os.path.getsize(CACHE) > 1000:
        with open(CACHE, "r", encoding="utf-8") as f:
            return json.load(f)
    log("拉取 game-icons 仓库文件树 …")
    data = json.loads(curl_text(TREE_API))
    with open(CACHE, "w", encoding="utf-8") as f:
        json.dump(data, f)
    return data


BG_RECT = re.compile(r'<path[^>]*d="M0 0h512v512H0z"[^>]*/>')
FILL_ATTR = re.compile(r'fill="(#[0-9a-fA-F]{3,6}|black|white|none)"')


def clean_svg(svg: str) -> str:
    """去掉整幅黑底矩形，并强制所有可见填充为纯白（便于运行时调色）。"""
    svg = BG_RECT.sub("", svg)
    svg = svg.replace('fill="#000000"', 'fill="#fff"').replace('fill="#000"', 'fill="#fff"')
    svg = svg.replace('fill="black"', 'fill="#fff"')

    def _keep_none(m: re.Match) -> str:
        return m.group(0) if m.group(1) == "none" else 'fill="#fff"'

    svg = FILL_ATTR.sub(_keep_none, svg)
    # 根节点补 fill，让没有显式 fill 的 path 也继承白色
    if "<svg" in svg and "fill=" not in svg.split(">", 1)[0]:
        svg = svg.replace("<svg", '<svg fill="#fff"', 1)
    return svg


def main() -> int:
    tree = fetch_tree()
    by_path = {t["path"] for t in tree.get("tree", []) if t["path"].endswith(".svg")}

    os.makedirs(SRC_DIR, exist_ok=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(SRC_DIR, ".gdignore"), "w", encoding="utf-8") as f:
        f.write("# 图标原始 SVG 只作来源留档，不参与 Godot 资源导入\n")

    manifest: dict[str, dict] = {}
    failures: list[str] = []
    pending: list[tuple[str, str]] = []
    for icon_id, src in ICONS.items():
        path = src + ".svg"
        if path not in by_path:
            failures.append(f"{icon_id}: 源图标不存在 {path}")
            continue
        dst_svg = os.path.join(SRC_DIR, icon_id + ".svg")
        raw = ""
        if os.path.exists(dst_svg) and os.path.getsize(dst_svg) > 0:
            raw = open(dst_svg, "r", encoding="utf-8").read()
        if "<svg" not in raw:
            pending.append((icon_id, path))
            continue
        manifest[icon_id] = _meta(icon_id, path)

    def _download(item: tuple[str, str]) -> tuple[str, str, str]:
        icon_id, path = item
        try:
            return icon_id, path, curl_text(RAW + path, timeout=45)
        except Exception as exc:  # noqa: BLE001 - 资产管线要报出具体失败项
            return icon_id, path, f"__ERROR__{exc}"

    if pending:
        log(f"并行下载 {len(pending)} 个 SVG …")
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            for icon_id, path, svg in pool.map(_download, pending):
                if svg.startswith("__ERROR__"):
                    failures.append(f"{icon_id}: 下载失败 {svg[9:]}")
                    continue
                cleaned = clean_svg(svg)
                with open(os.path.join(SRC_DIR, icon_id + ".svg"), "w", encoding="utf-8") as f:
                    f.write(cleaned)
                manifest[icon_id] = _meta(icon_id, path)

    with open(os.path.join(OUT_DIR, "icons.json"), "w", encoding="utf-8") as f:
        json.dump({
            "note": "由 tools/fetch_icons.py 生成；id 即文件名，运行时见 scripts/ui/IconDB.gd",
            "license": "CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/)",
            "source": "https://game-icons.net",
            "repository": "https://github.com/game-icons/icons",
            "icons": manifest,
        }, f, ensure_ascii=False, indent=2)

    authors: dict[str, list[str]] = {}
    for icon_id, meta in manifest.items():
        authors.setdefault(meta["author"], []).append(icon_id)
    lines = [
        "# UI 图标资源来源与署名",
        "",
        "本目录下的 PNG 图标由 `tools/fetch_icons.py` + `tools/rasterize_icons.gd` 从",
        "[game-icons.net](https://game-icons.net) 的官方 SVG 仓库",
        "[game-icons/icons](https://github.com/game-icons/icons) 自动生成。",
        "",
        "- 授权：**CC BY 3.0**（https://creativecommons.org/licenses/by/3.0/）",
        "- 处理：删除整幅黑底矩形、填充统一为纯白 `#ffffff`、透明背景、光栅化为 128×128 PNG",
        "  （原 SVG 留档在 `src/`，该目录带 `.gdignore`，不参与 Godot 导入）",
        "- 运行时由 `scripts/ui/IconDB.gd` 以 `res://assets/ui/icons/<id>.png` 约定加载，",
        "  白色前景通过 `self_modulate` 调成主题色，故同一张图可在不同面板呈现不同配色。",
        "",
        "## 署名（按作者分组）",
        "",
    ]
    for author in sorted(authors):
        lines.append(f"- **{author}** — " + "、".join(sorted(authors[author])))
    lines += [
        "",
        "> game-icons.net 图标由各作者以 CC BY 3.0 发布，使用时须保留本条署名。",
        "",
    ]
    with open(os.path.join(OUT_DIR, "CREDITS.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    log(f"完成：{len(manifest)}/{len(ICONS)} 个图标已写入 {SRC_DIR}")
    if failures:
        for item in failures:
            log("失败 " + item)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
