#!/usr/bin/env python3
"""v45 水系截图量化指标（只做对比参考，不是回归门槛）。

用法（用 DSH 自带 python，含 Pillow/numpy）：
  python3 tools/water_metrics.py artifacts/v45-base-water-lake-overview.png [...]
输出每张图的湖面高光/饱和度、南岸沙滩占比、瀑布前纯白硬块占比。
机位固定来自 tools/water_shot.tscn，所以多边形/矩形可按 1600x900 写死；
换机位要同步改下面的区域。指标只用于「改前/改后」相对比较，绝对值没有意义。
"""
import sys
from PIL import Image
import numpy as np

# 湖面轮廓（v45-base water_shot 的 lake-overview 机位；顺时针，全图像素坐标）
LAKE_POLY = [
    (630, 430), (700, 400), (790, 392), (900, 402), (985, 425), (1040, 500),
    (1052, 600), (1010, 690), (930, 760), (820, 800), (700, 780), (620, 700),
    (578, 600), (590, 500),
]
ISLAND_RECT = (785, 548, 905, 645)          # 湖心岛（不参与湖面统计）
SOUTH_SHORE_RECT = (690, 690, 1010, 800)    # 南岸沙滩带（含少量水/草，只看相对值）
POOL_RECT = (500, 600, 1000, 800)           # fall-front：潭面/落水区
MIST_RECT = (300, 600, 650, 870)            # fall-front：潭西侧（浮冰/雪斑/水雾）


def hsv(rgb: np.ndarray):
    mx = rgb.max(2)
    mn = rgb.min(2)
    v = mx
    s = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    d = mx - mn + 1e-6
    hue = np.zeros_like(v)
    mr = mx == r
    mg = (mx == g) & ~mr
    mb = (mx == b) & ~mr & ~mg
    hue[mr] = ((g - b)[mr] / d[mr]) % 6.0
    hue[mg] = (b - r)[mg] / d[mg] + 2.0
    hue[mb] = (r - g)[mb] / d[mb] + 4.0
    return hue * 60.0, s, v


def poly_mask(shape, poly):
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w]
    inside = np.zeros((h, w), bool)
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        cond = ((y1 > yy) != (y2 > yy))
        xint = (x2 - x1) * (yy - y1) / (y2 - y1 + 1e-9) + x1
        inside ^= cond & (xx < xint)
    return inside


def rect_mask(shape, rect):
    x0, y0, x1, y1 = rect
    m = np.zeros(shape, bool)
    m[max(0, y0):y1, max(0, x0):x1] = True
    return m


def metrics(path: str) -> None:
    rgb = np.asarray(Image.open(path).convert('RGB')).astype(np.float32) / 255.0
    hue, s, v = hsv(rgb)
    water = poly_mask(rgb.shape[:2], LAKE_POLY)
    ix0, iy0, ix1, iy1 = ISLAND_RECT
    water[iy0:iy1, ix0:ix1] = False
    wash = (v > 0.86) & (s < 0.22)
    azure = (hue > 155) & (hue < 205) & (s > 0.30) & (v > 0.12)
    print(f"\n== {path}")
    print("  湖面: 饱和度 %.3f  亮度 %.3f  高光白纱占比 %.1f%%  青绿水面占比 %.1f%%"
          % (s[water].mean(), v[water].mean(), 100.0 * wash[water].mean(), 100.0 * azure[water].mean()))
    west = water.copy()
    west[:, 840:] = False
    east = water.copy()
    east[:, :840] = False
    print("  西半湖白纱 %.1f%% / 东半湖白纱 %.1f%%"
          % (100.0 * wash[west].mean(), 100.0 * wash[east].mean()))
    shore = rect_mask(rgb.shape[:2], SOUTH_SHORE_RECT)
    sand = (hue > 20) & (hue < 62) & (s > 0.14) & (s < 0.55) & (v > 0.45)
    print("  南岸沙滩色占比 %.1f%%" % (100.0 * sand[shore].mean()))
    pool = rect_mask(rgb.shape[:2], POOL_RECT)
    mist = rect_mask(rgb.shape[:2], MIST_RECT)
    hard_white = (v > 0.93) & (s < 0.10)
    print("  落水区纯白占比 %.1f%%  潭西侧纯白占比 %.1f%%"
          % (100.0 * hard_white[pool].mean(), 100.0 * hard_white[mist].mean()))


if __name__ == '__main__':
    for p in sys.argv[1:]:
        metrics(p)
