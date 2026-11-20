# demo-1

基于 **Godot 4.7 / GDScript** 的 3D 俯视角沙盒游戏工程：**主控角色 + 模拟经营 + 即时战斗**。

在主城（`BaseCore`，HP 归 0 即游戏结束）周围经营：招募定居村民、建造房屋 / 酒馆 / 龙园、驯服巨龙、组队讨伐，入夜抵御成规模的夜潮攻城。

## 环境要求

| 项目 | 版本 |
| --- | --- |
| Godot | 4.7+（4.7.1 已验证） |
| 渲染器 | Forward+ |
| 物理 | Jolt |

打开工程后 Godot 会自行生成 `.godot/` 缓存（已 gitignore，**不要提交**）。

## 快速开始

```bash
godot --editor --path .   # 在编辑器中打开
godot --path .            # 直接运行（MainMenu → 开始游戏 → 关卡地图 → 主场景）
```

## 回归测试

工程没有测试框架、没有 lint、也没有 CI —— 回归 = 场景跑批：

```bash
bash tools/run_all_tests.sh          # CORE 42 套
bash tools/run_all_tests.sh --full   # 追加 6 套（天气 / 小地图 / 像素统计 / 浸泡等）
```

判定标准：**退出码 0 且日志无 `FAIL` / `SCRIPT ERROR` / `SHADER ERROR` / `Parse Error`**。

> ⚠️ 同一时刻只允许一个 Godot 进程（`.godot` 缓存会打架）。并行 / 多会话时一律用
> `bash tools/godot_locked.sh <godot 参数...>`，并给测试加 `--quit-after` 兜底。

## 目录结构

| 目录 | 职责 |
| --- | --- |
| `scripts/autoload/` | 全局单例（EventBus / GameManager / TimeManager / LevelRuntime / RenderQuality 等） |
| `scripts/defs/` | 玩法数据资源类型与内置配置（单位 / 职业 / 建筑 / 技能 / 关卡目录） |
| `scripts/entities/` | 建筑、资源点、投射物、金币掉落、Pawn 实体及其状态机 |
| `scripts/components/` | 可复用实体组件：血量、攻击、技能、血条 / 气泡等表现 |
| `scripts/systems/` | 世界级系统：网格、建造、寻路、刷怪、定居、驯龙、引导等 |
| `scripts/ui/` | HUD 与各面板 |
| `scenes/` | 主菜单、关卡地图、主场景、UI 桩场景 |
| `assets/` | 模型 / 贴图 / 着色器 / 特效 / 音频（占位资产见 `assets/_PLACEHOLDER/`） |
| `tests/`、`tools/` | 回归测试场景、探针与截图工具 |

## 参与协作

欢迎 Issue 与 Pull Request：

1. **Fork** 本仓库 → 新建分支开发 → 提 **Pull Request**（请不要直接往 `main` 推）。
2. 提交前请至少跑一次无头加载：`godot --headless --path . --quit`；涉及交互 / 镜头 / 美术的改动请在编辑器内实际运行验证。
3. **不要提交** `.godot/`、`build/`、`artifacts/`、`logs/`、`.DS_Store`。
4. `.uid` 文件是 Godot 生成的稳定资源 ID，**绝不手改**。
5. 提交信息用中文描述「改了什么 + 为什么」，一个 PR 聚焦一件事。

> 工程契约（架构、单位 / 模型 / 导航约定、修改检查清单、高频坑）详见 **[AGENTS.md](AGENTS.md)**，改动前请先读。

## 素材与许可

第三方素材（Kenney / KayKit / 霞鹜文楷 等）的来源与授权见：

- [assets/CREDITS.md](assets/CREDITS.md)
- [assets/ui/CREDITS.md](assets/ui/CREDITS.md)
- [dragon-assets/lowpoly-cc0.md](dragon-assets/lowpoly-cc0.md)

二次分发前请保留上述说明。
