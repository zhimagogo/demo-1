#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验所有图标在 IconBadge 圆形底盘内不溢出。

IconBadge 的几何：徽章边长 B，圆盘半径 R = 0.5·B·plate_ratio(0.92) = 0.46·B，
字模内缩到 GLYPH_RATIO(0.64)·B（见 scripts/ui/IconBadge.gd）。
本脚本按「字模实际绘制尺寸」缩放每个 PNG 的 alpha，计算最远不透明像素到中心的
距离，断言 <= R（留 2% 余量），并打印最差的前 8 名。

用法： python3 tools/check_icon_fit.py
"""
from __future__ import annotations

import glob
import math
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, "assets", "ui", "icons")

BADGE = 64.0            # 任意边长即可，比例与尺寸无关
PLATE_RATIO = 0.92
GLYPH_RATIO = 0.64
ALPHA_MIN = 16          # 低于此透明度视为不可见（抗锯齿边缘不算溢出）


def max_radius_ratio(path: str) -> float:
    """返回「最远可见像素半径 / 圆盘半径」；<=1 表示完全落在圆盘内。"""
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    alpha = im.split()[3]
    glyph = BADGE * GLYPH_RATIO                    # 字模绘制边长（像素）
    scale = glyph / w
    plate_r = BADGE * 0.5 * PLATE_RATIO
    cx = cy = w / 2.0 - 0.5
    worst = 0.0
    px = alpha.load()
    for y in range(h):
        for x in range(w):
            if px[x, y] < ALPHA_MIN:
                continue
            d = math.hypot(x - cx, y - cy) * scale
            if d > worst:
                worst = d
    return worst / plate_r


def main() -> int:
    files = sorted(glob.glob(os.path.join(ICON_DIR, "*.png")))
    if not files:
        print("[fit] 没有找到图标 PNG")
        return 1
    rows = []
    for f in files:
        rows.append((max_radius_ratio(f), os.path.basename(f)[:-4]))
    rows.sort(reverse=True)
    bad = [(r, n) for r, n in rows if r > 1.0]
    print(f"[fit] 圆盘半径 = 0.46·B，字模 {GLYPH_RATIO}·B，共 {len(rows)} 个图标")
    print("[fit] 溢出最严重的前 8 个（比值 <= 1.00 为合格）：")
    for r, n in rows[:8]:
        print(f"       {r:5.3f}  {n}")
    if bad:
        print(f"[fit] 不合格 {len(bad)} 个：" + "、".join(n for _, n in bad))
        return 1
    print("[fit] 全部图标都在圆盘内 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
