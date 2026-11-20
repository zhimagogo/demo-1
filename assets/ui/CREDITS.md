# UI 第三方资源署名（assets/ui/）

> **本目录全部资源均为 CC0 1.0（公有领域）或 SIL OFL 1.1，均可商用。**
> CC0 不强制署名，本项目仍按规范逐条记录来源与授权。
> 全部贴图均为原包**真实素材**，未自行绘制、未程序化生成、未缩放重采样；
> 颜色一律由运行时 `modulate` 上色，源文件保持原包像素。

---

## 一、Kenney（全部 CC0 1.0）

作者：**Kenney Vleugels**（[kenney.nl](https://kenney.nl)）
授权：**Creative Commons Zero 1.0 Universal（CC0 1.0）** — <https://creativecommons.org/publicdomain/zero/1.0/>
可商用：**是**（可商用、可修改、可再分发，署名非强制）

### 1. Kenney UI Pack (v2.0)

- 来源：<https://kenney.nl/assets/ui-pack>
- 包内授权文件原文：`License.txt` — "UI Pack (2.0) … License: (Creative Commons Zero, CC0)"
- 用于本项目的文件（均在 `assets/ui/kenney/`）：

| 本项目文件名 | 包内原始文件 | 尺寸 |
| --- | --- | --- |
| `button_normal.png` | `PNG/Grey/Default/button_rectangle_depth_flat.png` | 192×64 |
| `button_hover.png` | `PNG/Grey/Default/button_rectangle_depth_border.png` | 192×64 |
| `button_pressed.png` | `PNG/Grey/Default/button_rectangle_border.png` | 192×64 |
| `button_disabled.png` | `PNG/Grey/Default/button_rectangle_flat.png` | 192×64 |
| `chip_bg.png` | `PNG/Grey/Default/button_rectangle_line.png` | 192×64 |

> 说明：选用 `Grey/`（中性灰）版本，便于运行时 `modulate` 上暗金色。
> 任务书曾建议改用本包的 `button_rectangle_depth_*.png`，实际**已采用该家族**。

### 2. Kenney UI Pack: RPG Expansion

- 来源：<https://kenney.nl/assets/ui-pack-rpg-expansion>
- 包内授权文件原文：`license.txt` — "UI pack: RPG extension by Kenney Vleugels … License (CC0)"
- 用于本项目的文件（均在 `assets/ui/kenney/`）：

| 本项目文件名 | 包内原始文件 | 尺寸 |
| --- | --- | --- |
| `bar_track.png` | `PNG/barBack_horizontalLeft.png` + `barBack_horizontalMid.png` + `barBack_horizontalRight.png` | 36×18 |
| `bar_fill.png` | `PNG/barYellow_horizontalLeft.png` + `barYellow_horizontalMid.png` + `barYellow_horizontalRight.png` | 36×18 |
| `bar_fill_cool.png` | `PNG/barBlue_horizontalLeft.png` + `barBlue_horizontalBlue.png` + `barBlue_horizontalRight.png` | 36×18 |

> 说明：原包把进度条拆成 Left/Mid/Right 三个文件，本项目按 **Left + Mid + Right 原像素横向无缝拼接**为单个 36×18 PNG，
> 以便 Godot `StyleBoxTexture` / `NinePatchRect` 用一张图做 3-slice（左右端固定、中段拉伸）。拼接过程未缩放、未重绘、未改色。
> `bar_track` 原图是 alpha 26/51 的浅黑凹槽（刻意做的凹陷感），`bar_fill` 为暖色系、`bar_fill_cool` 为冷色系（额外提供）。

### 3. Kenney Fantasy UI Borders (v1.0)

- 来源：<https://kenney.nl/assets/fantasy-ui-borders>
- 包内授权文件原文：`License.txt` — "Fantasy UI Borders (1.0) … License: (Creative Commons Zero, CC0)"
- 用于本项目的文件（均在 `assets/ui/kenney/`）：

| 本项目文件名 | 包内原始文件 | 尺寸 |
| --- | --- | --- |
| `panel_dark.png` | `PNG/Default/Panel/panel-015.png` | 48×48 |
| `panel_inset.png` | `PNG/Default/Panel/panel-004.png` | 48×48 |
| `frame_ornate.png` | `PNG/Default/Panel/panel-023.png` | 48×48 |
| `frame_ornate_hollow.png` | `PNG/Default/Border/panel-border-017.png` | 48×48 |
| `divider_h.png` | `PNG/Default/Divider/divider-002.png` | 96×10 |

> 说明：本包素材是**纯白遮罩**（RGB 240,240,240 装饰线 + 透明底），天然适合 `modulate` 上任意颜色，
> 是「中性版本」的最佳来源，因此面板类全部取自本包而非 RPG 包的棕色 panel。

---

## 二、九宫格参数总表（人话版）

程序读取的权威版本是 **`assets/ui/kenney/slices.json`**（数值按交付文件逐像素实测，未经估算）。
下表是它的可读摘要，两者必须一致。

| 规范名 | 尺寸(w×h) | 左/上/右/下 margin | 用法 | 来源包 |
| --- | --- | --- | --- | --- |
| `panel_dark.png` | 48×48 | 4 / 4 / 4 / 4 | 9-slice，主面板底（白色遮罩，运行时上深色） | Fantasy UI Borders |
| `panel_inset.png` | 48×48 | 8 / 8 / 8 / 8 | 9-slice，内凹区（进度槽 / 列表底） | Fantasy UI Borders |
| `frame_ornate.png` | 48×48 | 14 / 14 / 14 / 14 | 9-slice，模态卡片外框（实心+角饰，可直接当 StyleBoxTexture） | Fantasy UI Borders |
| `frame_ornate_hollow.png` | 48×48 | 16 / 16 / 16 / 16 | 9-slice，中空外框（需自行叠层，附加件） | Fantasy UI Borders |
| `button_normal.png` | 192×64 | 9 / 9 / 9 / 9 | 9-slice，按钮常态 | UI Pack |
| `button_hover.png` | 192×64 | 12 / 12 / 12 / 12 | 9-slice，按钮悬停（外圈亮框） | UI Pack |
| `button_pressed.png` | 192×64 | 8 / 8 / 8 / 8 | 9-slice，按钮按下（内凹框） | UI Pack |
| `button_disabled.png` | 192×64 | 6 / 6 / 6 / 6 | 9-slice，按钮禁用（纯平无立体） | UI Pack |
| `chip_bg.png` | 192×64 | 8 / 8 / 8 / 8 | 9-slice，顶栏资源小胶囊底 | UI Pack |
| `bar_track.png` | 36×18 | 9 / 0 / 9 / 0 | **3-slice_h**，进度条槽（上下 margin 必须为 0） | RPG Expansion |
| `bar_fill.png` | 36×18 | 9 / 0 / 9 / 0 | **3-slice_h**，进度条填充（暖色系：金/绿/红/橙） | RPG Expansion |
| `bar_fill_cool.png` | 36×18 | 9 / 0 / 9 / 0 | **3-slice_h**，进度条填充（冷色系：蓝/青/紫，附加件） | RPG Expansion |
| `divider_h.png` | 96×10 | 4 / 4 / 4 / 4 | 9-slice，横向装饰分隔条 | Fantasy UI Borders |

### 按规范省略的两项（理由见 `slices.json` 的 `_omitted`）

| 规范名 | 处理 | 原因 |
| --- | --- | --- |
| `divider_h_flip.png` | **省略** | Fantasy UI Borders 全部 `Divider/divider-*.png` 经逐像素比对，上下翻转与左右翻转均与原图**完全一致**（垂直翻转 diff bbox = `None`），翻转版与 `divider_h.png` 字节等同，做出来是废文件。 |
| `glow_soft.png` | **省略** | ui-pack / ui-pack-rpg-expansion / fantasy-ui-borders 三个包内**没有**柔光或径向渐变素材。按「不许自己画/程序生成凑数」的要求不伪造，故省略；需要光晕效果时请用 `StyleBoxFlat` 的 shadow 或渐变 `ColorRect` 在代码里实现。 |

---

## 三、配色约定（给接线的同学）

所有贴图源文件是**白色或中性灰遮罩**，本身不含主题色，颜色由运行时决定：

- 面板：`panel_dark` / `panel_inset` 建议 `modulate_color` 取深胡桃木色（如 `Color(0.13,0.105,0.085)`）。
- 边框：`frame_ornate` 建议暗金（如 `Color(0.62,0.50,0.28)`）。
- 按钮四态：`modulate_color` 取暗金；hover 更亮、pressed 更暗、disabled 去饱和。
- 进度条：`bar_fill` 适合暖色（金/绿/红/橙），`bar_fill_cool` 适合冷色（蓝/青/紫）。
  实测按 `modulate` 相乘后的色相误差：`bar_fill` × 金 ≈ 1.4°、× 红 ≈ 9°；`bar_fill_cool` × 蓝 ≈ 0.4°。

---

## 四、字体 —— LXGW WenKai Lite（霞鹜文楷 Lite），SIL OFL 1.1

- 资源名：**LXGW WenKai Lite**（霞鹜文楷 Lite）
- 作者：**LXGW（落霞孤鹜）** — <https://github.com/lxgw>
- 来源：<https://github.com/lxgw/LxgwWenKai-Lite/releases/tag/v1.522>
- 直链：<https://github.com/lxgw/LxgwWenKai-Lite/releases/download/v1.522/LXGWWenKaiLite-Regular.ttf>
- 版本：**v1.522**（Regular 常规字重）
- 授权：**SIL Open Font License 1.1（OFL 1.1）** — <https://openfontlicense.org>
  可商用：**是**（可商用、可嵌入游戏、可再分发；OFL 要求随附授权全文，且不得单独售卖字体本身）
- 用于本项目的文件：

| 本项目文件名 | 说明 | 大小 | SHA-256 |
| --- | --- | --- | --- |
| `assets/ui/fonts/ui_cjk.ttf` | 字体本体（原样复制、未修改、未子集化） | 13,872,424 B（约 13.23 MB） | `140c99ba4e28e817cec49bf82a0c5fcdc4fe633fb9dfda16d0ee8d59a8545f15` |
| `assets/ui/fonts/OFL.txt` | OFL 1.1 授权全文（OFL 要求随字体一并分发） | 5,176 B | — |

> 详细字体信息（字符覆盖实测、为什么选 Lite、Godot 用法）见 `assets/ui/fonts/FONT_INFO.md`。

---

## 五、合规小结

| 资源 | 授权 | 可商用 | 是否强制署名 | 本项目是否已署名 |
| --- | --- | --- | --- | --- |
| Kenney UI Pack (v2.0) | CC0 1.0 | ✅ | ❌ 非强制 | ✅ 已署名 |
| Kenney UI Pack: RPG Expansion | CC0 1.0 | ✅ | ❌ 非强制 | ✅ 已署名 |
| Kenney Fantasy UI Borders (v1.0) | CC0 1.0 | ✅ | ❌ 非强制 | ✅ 已署名 |
| LXGW WenKai Lite | SIL OFL 1.1 | ✅ | ✅ 需保留授权全文 | ✅ 已署名并附带 `OFL.txt` |

- 本目录**不含**任何 AI 生成、程序化生成或手工绘制的素材；不含任何来源不明、授权不清的素材。
- Kenney 素材未做任何像素级修改（仅重命名 + 进度条 Left/Mid/Right 原像素拼接）。
- 字体未做任何修改。

### 关于「游戏图标」的说明

`assets/ui/icons/`（游戏内图标，game-icons.net 等）**不在本文件的署名范围内**，
其署名与授权逐条记录在 `assets/ui/icons/CREDITS.md` 与 `assets/ui/icons/icons.json`。
