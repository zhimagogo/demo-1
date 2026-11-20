#!/usr/bin/env bash
# 一键导出 Windows 发行包（给朋友体验用）
#
# 用法：
#   bash tools/export_windows.sh              # 默认输出到 build/windows/demo1.exe
#   bash tools/export_windows.sh /tmp/out     # 指定输出目录
#
# 前置条件：本机已安装与编辑器版本一致的官方导出模板
#   ~/Library/Application Support/Godot/export_templates/<版本>.stable/windows_release_x86_64.exe
# 缺失时脚本会打印官方下载地址与安装位置（模板来自 Godot 官方 Release，勿用第三方来源）。
#
# 注意：同一时刻只允许一个 godot 进程（.godot 缓存会打架）。

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$PROJECT_ROOT/build/windows}"
GODOT_BIN="${GODOT:-godot}"
PRESET_NAME="Windows Desktop"
EXE_NAME="demo1.exe"

cd "$PROJECT_ROOT"

# ---- 1. 版本与模板检查 ----------------------------------------------------
FULL_VER="$("$GODOT_BIN" --version | head -1)"
SHORT_VER="$(echo "$FULL_VER" | cut -d. -f1-3)"          # 4.7.1
TEMPLATE_VER="${SHORT_VER}.stable"                        # 4.7.1.stable
TPL_DIR="$HOME/Library/Application Support/Godot/export_templates/${TEMPLATE_VER}"

echo "Godot      : $FULL_VER"
echo "模板目录   : $TPL_DIR"

if [[ ! -f "$TPL_DIR/version.txt" ]]; then
	echo ""
	echo "❌ 未找到导出模板（$TEMPLATE_VER）。"
	echo "   官方下载：https://github.com/godotengine/godot/releases/tag/${TEMPLATE_VER}"
	echo "   文件：Godot_v${TEMPLATE_VER}_export_templates.tpz"
	echo "   安装：解包后把 templates/ 下的内容放进 $TPL_DIR/"
	echo "   （或在编辑器里「编辑器 → 管理导出模板 → 下载并安装」）"
	exit 1
fi

if [[ "$(cat "$TPL_DIR/version.txt")" != "$TEMPLATE_VER" ]]; then
	echo "❌ 模板版本不匹配：目录内为 $(cat "$TPL_DIR/version.txt")，需要 $TEMPLATE_VER"
	exit 1
fi

if [[ ! -f "$TPL_DIR/windows_release_x86_64.exe" ]]; then
	echo "❌ 模板目录缺少 windows_release_x86_64.exe"
	exit 1
fi
echo "模板版本   : $(cat "$TPL_DIR/version.txt") ✅"

# ---- 2. 并发保护 ----------------------------------------------------------
if pgrep -f "Godot.*--path" >/dev/null 2>&1 || pgrep -f "godot" >/dev/null 2>&1; then
	echo "⚠️  检测到已有 godot 进程在跑，可能与导出争抢 .godot 缓存。"
	echo "   建议先关闭编辑器/测试进程再导出。"
fi

# ---- 3. 导出 --------------------------------------------------------------
mkdir -p "$OUT_DIR"
echo ""
echo "▶ 开始导出（preset: $PRESET_NAME）..."
"$GODOT_BIN" --headless --path . --export-release "$PRESET_NAME" "$OUT_DIR/$EXE_NAME"

# ---- 4. 校验 --------------------------------------------------------------
EXE_PATH="$OUT_DIR/$EXE_NAME"
if [[ ! -f "$EXE_PATH" ]]; then
	echo "❌ 导出失败：未生成 $EXE_PATH"
	exit 1
fi

SIZE="$(stat -f%z "$EXE_PATH" 2>/dev/null || stat -c%s "$EXE_PATH")"
echo ""
echo "✅ 导出成功"
echo "   路径：$EXE_PATH"
echo "   大小：$((SIZE / 1024 / 1024)) MB"

# 校验内嵌 pck：文件末尾 12 字节应为 <u64 pck大小><u32 魔数 GDPC>
python3 - "$EXE_PATH" <<'PY'
import struct, sys
p = sys.argv[1]
size = __import__("os").path.getsize(p)
with open(p, "rb") as f:
    f.seek(size - 12)
    pck_size = struct.unpack("<Q", f.read(8))[0]
    magic = f.read(4)
    pck_start = size - 12 - pck_size
    f.seek(pck_start)
    head = f.read(4)
if magic == b"GDPC" and head == b"GDPC":
    print(f"   内嵌 pck：{pck_size/1024/1024:.1f} MB ✅（头尾魔数均校验通过）")
else:
    print(f"   ⚠️ 内嵌 pck 校验异常：footer={magic} head={head}")
    sys.exit(1)
PY
