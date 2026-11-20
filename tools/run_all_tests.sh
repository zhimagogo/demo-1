#!/usr/bin/env bash
# ============================================================================
# v12 全量验收跑批：按顺序跑完所有回归场景（同一时刻只允许一个 godot 进程）。
#
#   bash tools/run_all_tests.sh            # 只跑本轮新增 / 关键回归
#   bash tools/run_all_tests.sh --full     # 追加全部既有回归（含浸泡 / 截图统计）
#
# 判定：每个场景退出码 0 且日志无 "FAIL" / "SCRIPT ERROR" / "SHADER ERROR" 记 PASS；
#       单场景超过 SCENE_TIMEOUT 秒判 TIMEOUT（防「Parse Error → 场景无脚本 → 永不 quit」挂死整批）。
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

LOG_DIR="${TMPDIR:-/tmp}/demo1-tests"
SCENE_TIMEOUT="${SCENE_TIMEOUT:-600}"   # 单场景上限（秒）；SoakTest 2 游戏日约需 3~5 分钟
mkdir -p "$LOG_DIR"

CORE=(
  "tests/LawnInteractionTest.tscn|v46.2 grass parting direction / recovery / pause / jump / teleport / rolling field"
  "tests/LawnTest.tscn|v46 lawn coverage / building and road mask lifecycle / opaque grass budget"
  "tests/RenderQualityTest.tscn|v47 quality presets / shadow & postfx application / early-Z grass contract"
  "tests/RoadTownLifeTest.tscn|dirt road painting / topology / friendly road routing / soldier daily life and chat"
  "tests/MonsterBehaviorStabilityTest.tscn|monster roam / city / leash / retaliation / flee stability"
  "tools/monster_roam_probe.tscn|real world monster city / leash transitions"
  "tests/NavigationStabilityTest.tscn|navigation progress / occupancy / combat slots / cache"
  "tools/gather_probe.tscn|back view + rally speed"
  "tests/RallyFollowTest.tscn|rally accelerate / settle"
  "tests/SquadCommandTest.tscn|squad orders / green marks / lifelike follow"
  "tests/SettlerSkillTest.tscn|settler class skills (blizzard/rage/rapid/backstab)"
  "tests/PawnStatsTest.tscn|minion attribute system (level/xp/defense/crit)"
  "tests/SquadXpTownRegenTest.tscn|v34 squad xp sharing / hero+dragon town regen (day-only)"
  "tests/TavernHealTest.tscn|v22 tavern healing / gold economy / harvest off"
  "tests/HouseOccupancyTest.tscn|v43 occupied house warm tint / door light / resident lifecycle reset"
  "tests/BuildLimitTest.tscn|v37 tavern+dragon-garden unique build limit (card grey / no charge / rebuild)"
  "tests/CitizenManageTest.tscn|v25 citizen manage / settle class choice / promote / skill tree"
  "tests/AdvancedSkillTest.tscn|v33 advanced class skills (leap/meteor/pierce/stealth)"
  "tests/DragonPetTest.tscn|v26 dragon taming / garden E-interact / pet follow+fight / breath cone / respawn"
  "tests/CameraBackViewTest.tscn|camera raised + wide + back"
  "tools/water_check.tscn|water shaders + geometry"
  "tests/WaterFeatureTest.tscn|waterfall / river / lake wiring"
  "tests/LakeStuckTest.tscn|v36 lake collision/nav consistency + knockup clamp + stuck rescue"
  "tests/HeroOcclusionTest.tscn|hero occlusion silhouette"
  "tests/DissolveZoneTest.tscn|decoration hemisphere dissolve"
  "tests/CombatVfxTest.tscn|combat vfx chain"
  "tests/AnimVfxSyncTest.tscn|anim/vfx sync (class anims / replay / loop defer / hit react)"
  "tests/SpeechBubbleTest.tscn|minion persona speech bubbles"
  "tests/DeathDissolveTest.tscn|enemy death anim + texture dissolve"
  "tests/LootBurstTest.tscn|loot burst / bounce / magnet pickup"
  "tests/HealthBarTest.tscn|overhead HP visibility / camera / damage"
  "tests/ThirdPersonTest.tscn|third-person core regression"
  "tests/NightAssaultTest.tscn|dusk pause / night road-end waves / base assault / retaliation"
  "tests/NightAssaultNoFleeTest.tscn|v44 assaulting/night-wave raiders never flee at low hp"
  "tests/NightVigilTest.tscn|v43 night vigil posts / tavern healing / 2-3 soldier chat / dawn reset"
  "tests/NightDefenseFormationTest.tscn|v44 threat-direction gate deployment / melee front / ranged back / in-place chat"
  "tests/SceneValidation.tscn|main scene validation"
  "tests/WorldExpansionTest.tscn|v40 256x256 world / themed regions / nav connectivity / ground bounds / load budget"
  "tests/CityScaleTest.tscn|v43 52x52 city / enlarged buildings / relocated lake / spawn ring / torch gates"
  "tests/ScenePolishTest.tscn|v40.1 scene polish (prop grounding / overlap / vegetation / trail end distance)"
  "tests/MenuFlowTest.tscn|Demo entry / first-run tutorial spawning / menu flow"
  "tests/LevelSelectTest.tscn|v38 level catalog / menu entry / level map / prologue clear"
)
FULL=(
  "tests/WeatherRainTest.tscn|rain runtime"
  "tests/MinimapOrientation.tscn|minimap orientation"
  "tests/BossNightTest.tscn|boss night lifecycle"
  "tests/PixelCheck.tscn|pixel statistics"
  "tests/UiIconTest.tscn|ui icons"
  "tests/SoakTest.tscn|soak 2 game days"
)

run_one() {
  local scene="$1" label="$2" name
  name="$(basename "$scene" .tscn)"
  if [[ ! -f "$scene" ]]; then
    printf '%-34s SKIP  (missing %s)\n' "$name" "$scene"
    return 1
  fi
  local log="$LOG_DIR/$name.log"
  # 超时护栏：测试脚本一旦 Parse Error，场景就没有脚本、永远不 quit，
  # 批处理会被一个 100% CPU 的 godot 进程挂死（v12 实际踩到，白等 16 分钟）。
  # macOS 没有 coreutils timeout，故用「后台 pid + 轮询 + 到点 TERM/KILL」自建。
  godot --headless --path . "$scene" --log-file "$log" --fixed-fps 60 >/dev/null 2>&1 &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [[ "$waited" -ge "$SCENE_TIMEOUT" ]]; then
      kill -TERM "$pid" 2>/dev/null
      sleep 2
      kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      printf '%-34s TIMEOUT  (%ss > %ss) log=%s\n' "$name" "$waited" "$SCENE_TIMEOUT" "$log"
      grep -E 'SCRIPT ERROR|Parse Error|SHADER ERROR|FAIL' "$log" 2>/dev/null | head -5 | sed 's/^/      /'
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null
  local code=$?
  local fails
  fails="$(grep -c -E 'FAIL|SCRIPT ERROR|SHADER ERROR|Parse Error' "$log" 2>/dev/null || true)"
  if [[ "$code" -eq 0 && "${fails:-0}" -eq 0 ]]; then
    printf '%-34s PASS  (%s)\n' "$name" "$label"
    return 0
  fi
  printf '%-34s FAIL  exit=%s bad_lines=%s log=%s\n' "$name" "$code" "${fails:-?}" "$log"
  grep -E 'FAIL|SCRIPT ERROR|SHADER ERROR|Parse Error' "$log" 2>/dev/null | head -8 | sed 's/^/      /'
  return 1
}

total=0; failed=0
for entry in "${CORE[@]}"; do
  scene="${entry%%|*}"; label="${entry##*|}"
  total=$((total + 1))
  run_one "$scene" "$label" || failed=$((failed + 1))
done

if [[ "${1:-}" == "--full" ]]; then
  for entry in "${FULL[@]}"; do
    scene="${entry%%|*}"; label="${entry##*|}"
    total=$((total + 1))
    run_one "$scene" "$label" || failed=$((failed + 1))
  done
fi

echo "----------------------------------------------------------------"
echo "suites: $total   failed: $failed"
exit $((failed > 0 ? 1 : 0))
