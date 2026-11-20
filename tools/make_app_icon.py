#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""demo-1 应用图标（窗口/任务栏/Dock）生成脚本。

素材全部来自 assets/ui/icons/（game-icons.net，CC BY 3.0，见 assets/ui/icons/CREDITS.md）：
用「金冠 + 盾徽 + 城墙」三件现成开源图标在深胡桃木底上合成，产出 512×512 的
icon.png 供 project.godot 的 config/icon 使用；不做任何手绘/程序化涂鸦填充。

用法： python3 tools/make_app_icon.py
"""
from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, "assets", "ui", "icons")
OUT = os.path.join(ROOT, "icon.png")

SIZE = 512
WALNUT_TOP = (46, 36, 26, 255)
WALNUT_BOTTOM = (26, 20, 15, 255)
GOLD = (243, 205, 97, 255)
GOLD_DIM = (150, 118, 54, 255)


def tinted(name: str, size: int, color: tuple[int, int, int, int]) -> Image.Image:
    """把白色前景图标按给定颜色着色（等价于运行时 self_modulate）。"""
    src = Image.open(os.path.join(ICON_DIR, name + ".png")).convert("RGBA")
    src = src.resize((size, size), Image.LANCZOS)
    solid = Image.new("RGBA", src.size, color)
    solid.putalpha(src.split()[3])
    return solid


def main() -> int:
    base = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # 深胡桃木圆角方底（竖向渐变模拟木纹光照）
    grad = Image.new("RGBA", (1, SIZE))
    for y in range(SIZE):
        t = y / (SIZE - 1)
        grad.putpixel((0, y), tuple(
            int(WALNUT_TOP[i] * (1 - t) + WALNUT_BOTTOM[i] * t) for i in range(4)))
    grad = grad.resize((SIZE, SIZE))

    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=96, fill=255)
    base.paste(grad, (0, 0), mask)

    draw = ImageDraw.Draw(base)
    # 外圈暗金描边 + 内圈细线（和 HUD 的 BORDER_GOLD 同一套观感）
    draw.rounded_rectangle([6, 6, SIZE - 7, SIZE - 7], radius=92, outline=GOLD, width=7)
    draw.rounded_rectangle([22, 22, SIZE - 23, SIZE - 23], radius=78, outline=GOLD_DIM, width=3)

    # 盾徽（暗金底，压暗一档）→ 金冠（主体）——两个形状在小尺寸下都能一眼认出
    shield = tinted("shield", 400, (56, 42, 28, 240))
    base.alpha_composite(shield, (56, 62))
    shield_rim = tinted("shield", 400, GOLD_DIM)
    shield_rim.putalpha(shield_rim.split()[3].point(lambda a: int(a * 0.55)))
    base.alpha_composite(shield_rim, (56, 62))
    crown = tinted("crown", 296, GOLD)
    base.alpha_composite(crown, (108, 150))

    # 轻量外发光，让图标在深色任务栏上也有轮廓
    glow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    glow.paste(GOLD, (0, 0), base.split()[3])
    glow = glow.filter(ImageFilter.GaussianBlur(18))
    out = Image.alpha_composite(glow, base)

    out.save(OUT)
    print(f"写出 {OUT} ({SIZE}×{SIZE}, {os.path.getsize(OUT)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
