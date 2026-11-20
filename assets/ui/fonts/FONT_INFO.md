# 中文字体信息（assets/ui/fonts/）

## 结论速览

| 项 | 值 |
| --- | --- |
| 本项目文件 | `assets/ui/fonts/ui_cjk.ttf` |
| 字体名（Family） | **LXGW WenKai Lite**（霞鹜文楷 Lite） |
| 字重 | Regular（常规，本项目**只放这一个字重**，体积优先） |
| 版本 | **v1.522**（name 表内 `Version 1.522; March 17, 2026`） |
| PostScript 名 | `LXGWWenKaiLite-Regular` |
| 字形数 | 25,985 |
| 文件大小 | **13,872,424 字节（约 13.23 MB）** — 低于 25 MB 预算 |
| 授权 | **SIL Open Font License 1.1（OFL 1.1）** —— 可商用、可嵌入、可再分发 |
| 授权全文 | 同目录 `OFL.txt`（随字体一并分发，OFL 要求保留） |
| 下载 URL | <https://github.com/lxgw/LxgwWenKai-Lite/releases/download/v1.522/LXGWWenKaiLite-Regular.ttf> |
| 发布页 | <https://github.com/lxgw/LxgwWenKai-Lite/releases/tag/v1.522> |
| 上游仓库 | <https://github.com/lxgw/LxgwWenKai-Lite> |
| 作者 | LXGW（落霞孤鹜）— <https://github.com/lxgw> |
| SHA-256 | `140c99ba4e28e817cec49bf82a0c5fcdc4fe633fb9dfda16d0ee8d59a8545f15` |

校验命令：

```sh
shasum -a 256 assets/ui/fonts/ui_cjk.ttf
# 140c99ba4e28e817cec49bf82a0c5fcdc4fe633fb9dfda16d0ee8d59a8545f15  assets/ui/fonts/ui_cjk.ttf
```

---

## 为什么选 Lite 而不是完整版

上游同时提供三个体量档，本项目按「体积优先」选了 Lite Regular：

| 版本 | 文件名 | 体积 | 取舍 |
| --- | --- | --- | --- |
| 完整版 | `LXGWWenKai-Regular.ttf` | 24.39 MB | 字形最全，接近预算上限 |
| **Lite（已采用）** | `LXGWWenKaiLite-Regular.ttf` | **13.23 MB** | 剔除生僻字，常用字全覆盖，UI 用足够 |
| Screen | `LXGWWenKaiScreen.ttf` | 24.48 MB | 为屏幕显示优化笔画，但体积无优势 |

Lite 版是为「字体子集化 / 网页嵌入」场景准备的，正好符合游戏 UI 只用到常用汉字的需求，**体积只有完整版的 54%**。

---

## 字符覆盖实测

按 TTF 的 `cmap`（format 12）逐码位实测：

| 区段 | 覆盖 | 说明 |
| --- | --- | --- |
| ASCII `U+0020–007E` | 95/95（100%） | 英文、数字、半角标点齐全 |
| 基本汉字 `U+4E00–9FFF` | 18,429/20,992（87%） | 缺的是生僻字，常用字全覆盖 |
| CJK 标点 `U+3000–303F` | 60/64（93%） | `、。「」《》` 等齐全 |
| 全角标点 `U+FF00–FFEF` | 173/240（72%） | |
| 扩展 A `U+3400–4DBF` | 747/6,592（11%） | 生僻，UI 无需 |

抽查本项目实际用到的汉字（`殖民地经营沙盒木石金币村民士兵房屋农田市集箭塔兵营主角经验等级任务生命值暂停速度网格建造招募完成取消`）——**全部命中，无缺失**。

---

## 在 Godot 中的用法

字体已放在约定路径 `res://assets/ui/fonts/ui_cjk.ttf`，`UIStyle.make_font()` 优先加载它（缺失时回退 `SystemFont`）。

注意事项：

1. **不要在 `.tscn` 里手工挂这个 FontFile**，统一由 `UIStyle` 单点提供，便于换肤。
2. 字体是**常规字重**。需要「加粗」标题时，Godot 4 可用 `FontVariation.variation_embolden`（合成加粗），
   不要再下载第二个字重文件——本项目约定只保留一个。
3. 首次导入 13 MB 字体需要几秒，属正常现象；`.godot/` 内的导入缓存已 gitignore。
4. 若将来要换成 Noto Sans SC / 思源黑体，只需替换 `ui_cjk.ttf` 并更新本文件的校验值，
   调用方（`UIStyle`）无需改动。

---

## 授权合规说明

- 本字体以 **SIL Open Font License 1.1** 分发，**允许商用**、允许嵌入游戏、允许再分发。
- OFL 要求：再分发时必须附带授权全文，且**不得单独售卖字体本身**。
  因此 `OFL.txt` 与字体放在同一目录、一并分发。
- 保留字体名（Reserved Font Name）为 `霞鹜`、`霞鶩`、`落霞孤鹜`、`落霞孤鶩`、`LXGW`。
  本项目**未修改字体文件**，仅原样复制并重命名为 `ui_cjk.ttf`，无需改名。
- 上游对有修改的重编译版本有额外许可条款（见 `OFL.txt` 的 `[ADDITIONAL PERMISSION]` 段）。
