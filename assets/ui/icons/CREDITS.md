# UI 图标资源来源与署名

本目录下的 PNG 图标由 `tools/fetch_icons.py` + `tools/rasterize_icons.gd` 从
[game-icons.net](https://game-icons.net) 的官方 SVG 仓库
[game-icons/icons](https://github.com/game-icons/icons) 自动生成。

- 授权：**CC BY 3.0**（https://creativecommons.org/licenses/by/3.0/）
- 处理：删除整幅黑底矩形、填充统一为纯白 `#ffffff`、透明背景、光栅化为 128×128 PNG
  （原 SVG 留档在 `src/`，该目录带 `.gdignore`，不参与 Godot 导入）
- 运行时由 `scripts/ui/IconDB.gd` 以 `res://assets/ui/icons/<id>.png` 约定加载，
  白色前景通过 `self_modulate` 调成主题色，故同一张图可在不同面板呈现不同配色。

## 署名（按作者分组）

- **delapouite** — building_house、building_wall、fast_forward、home、res_gold、res_stone、res_wood、stat_hero、stat_pop、target、time_day、tool_hammer、unit_ranged
- **guard13007** — pause、play
- **lorc** — attack、boss、building_tavern、carry、compass、crown、event_log、map、quest、res_food、skill_slash、stat_enemy、stat_soldier、time_night、tutorial、unit_melee、warning、weather_clear、weather_cloud、weather_rain、weather_storm、xp
- **sbed** — close、help、shield、skill_flame
- **skoll** — hp

> game-icons.net 图标由各作者以 CC BY 3.0 发布，使用时须保留本条署名。
