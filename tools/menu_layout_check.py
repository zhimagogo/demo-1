#!/usr/bin/env python3
"""测量主菜单截图的标题/副标题/按钮文本行位置，检测垂直重叠。"""
import sys
from PIL import Image

def bands(img, x0, x1, y0=80, y1=640, thr=300, min_px=6):
    rows = []
    for y in range(y0, min(y1, img.size[1])):
        cnt = sum(1 for x in range(max(0, x0), min(img.size[0], x1)) if sum(img.getpixel((x, y))) > thr)
        if cnt >= min_px:
            rows.append((y, cnt))
    out = []
    for y, n in rows:
        if out and y - out[-1][1] <= 4:
            out[-1][1] = y
        else:
            out.append([y, y])
    return out

def analyze(path):
    img = Image.open(path).convert('RGB')
    w, h = img.size
    print(f'== {path}  window={w}x{h}')
    bs = bands(img, w // 2 - 260, w // 2 + 260)
    for b in bs:
        # 行内最亮像素的水平范围
        xs = [x for y in range(b[0], b[1] + 1) for x in range(w // 2 - 300, w // 2 + 300)
              if sum(img.getpixel((x, y))) > 300]
        span = (min(xs), max(xs)) if xs else (0, 0)
        print(f'  band y={b[0]}-{b[1]}  x={span[0]}-{span[1]}  w={span[1]-span[0]}')
    return bs

if __name__ == '__main__':
    for p in sys.argv[1:]:
        analyze(p)
