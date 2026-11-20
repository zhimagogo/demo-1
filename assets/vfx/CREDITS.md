# 特效贴图资产来源与授权

## Kenney Particle Pack（CC0，公有领域）

来源：<https://kenney.nl/assets/particle-pack>（Godot 打包版：<https://github.com/Calinou/kenney-particle-pack>）
授权：**Creative Commons Zero (CC0)** —— 可商用、无署名义务（本文件仅作来源记录）。
完整许可证副本见同目录 `KENNEY_LICENSE.txt`。

本项目从中挑选以下贴图放入 `assets/vfx/textures/`（原文件名不变）：

| 贴图 | 用途 |
| --- | --- |
| `slash_01..04.png` | 挥砍刀光 / 弧形残影（主角与近战小兵） |
| `spark_01/04/05/06.png` | 命中火星、金属撞击 |
| `star_04/06/08.png` | 枪口十字星闪光、法术蓄力光点 |
| `muzzle_02/04.png` | 射手射击瞬间枪口焰 |
| `magic_03/05.png` | 法师法术弹 / 魔法爆散 |
| `smoke_04/06.png` | 冲击环底烟、瀑布水雾 |
| `flame_03/05.png` | 火焰（营地 / 爆炸点缀） |
| `trace_03/05.png` | 投射物拖尾、速度线 |
| `flare_01.png` / `light_01.png` | 柔光晕、法术点光、瀑布飞沫 |
| `circle_02.png` | 冲击环 / 涟漪环底图 |
| `twirl_02.png` | 旋风斩旋转气流 |
| `scorch_02.png` | 命中焦痕（可选） |

> 贴图以 2D 公告牌粒子形式使用；若需更高分辨率或 3D 网格化美术，替换本目录同名文件即可，调用方无需改动。

## 卡通火焰贴图（v30，本项目程序化生成）

来源：`tools/make_toon_fire_textures.gd`（Godot Image API 程序化绘制，非外部素材）
授权：随本项目分发，无外部授权约束。
文件：`toon_flame_01.png`（cel 分层火舌）/ `toon_puff_01.png`（卡通烟团）——
巨龙火球火衣 / 尾焰 / 爆炸火舌团与吐息主火舌 / 余烟使用。
