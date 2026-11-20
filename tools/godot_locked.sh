#!/usr/bin/env bash
# ============================================================================
# godot 串行化包装（v33）：同一时刻只允许一个 godot 进程（.godot 缓存会打架）。
#
#   bash tools/godot_locked.sh --headless --path . tests/X.tscn --fixed-fps 60
#
# 锁：${TMPDIR:-/tmp}/demo1-godot.lock（mkdir 原子锁 + 陈旧锁回收）。
# 等待上限 GODOT_LOCK_TIMEOUT 秒（默认 1200）；超时退出码 124。
# 注意：不使用 exec（否则 trap 不执行、锁不会释放）；SIGKILL 由陈旧锁回收兜底。
# ============================================================================
set -uo pipefail

LOCK_DIR="${TMPDIR:-/tmp}/demo1-godot.lock"
WAIT_MAX="${GODOT_LOCK_TIMEOUT:-1200}"
STALE_SEC="${GODOT_LOCK_STALE:-2400}"      # 持有超过此时长视为死锁
GODOT_BIN="${GODOT_BIN:-godot}"

start="$(date +%s)"
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
	if [ -d "$LOCK_DIR" ]; then
		mtime="$(stat -f %m "$LOCK_DIR" 2>/dev/null || stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0)"
		age=$(( $(date +%s) - mtime ))
		if [ "$age" -gt "$STALE_SEC" ]; then
			echo "[godot_locked] 回收陈旧锁（${age}s）: $LOCK_DIR" >&2
			rm -rf "$LOCK_DIR"
			continue
		fi
	fi
	if [ $(( $(date +%s) - start )) -gt "$WAIT_MAX" ]; then
		echo "[godot_locked] 等待锁超时（${WAIT_MAX}s），放弃。占用者可能是另一个 godot 跑批。" >&2
		exit 124
	fi
	sleep 3
done

cleanup() { rm -rf "$LOCK_DIR"; }
trap cleanup EXIT INT TERM

echo "[godot_locked] 获得锁（等待 $(( $(date +%s) - start ))s）：$*" >&2
"$GODOT_BIN" "$@"
code=$?
cleanup
trap - EXIT INT TERM
exit $code
