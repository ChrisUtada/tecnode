#!/usr/bin/env bash
# 无头回归总入口：跑 tests/headless/test_*.gd，汇总项数与失败数。
#
# 用法：
#   GODOT=/path/to/godot_console ./tools/run_tests.sh
#   ./tools/run_tests.sh tests/headless/test_p0.gd tests/headless/test_ui.gd
#
# 默认 Godot 路径与 README 一致；不存在时用 GODOT 环境变量覆盖。
set -u

cd "$(dirname "$0")/.." || exit 2

GODOT="${GODOT:-/d/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe}"
if [ ! -x "$GODOT" ] && ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "找不到 Godot：$GODOT" >&2
	echo "用 GODOT=/path/to/godot_console 覆盖。" >&2
	exit 2
fi

TESTS=("$@")
if [ ${#TESTS[@]} -eq 0 ]; then
	# 注意：_test_base.gd 不匹配 test_*.gd，不会被当成用例。
	while IFS= read -r t; do
		TESTS+=("$t")
	done < <(ls tests/headless/test_*.gd 2>/dev/null | sort)
fi

if [ ${#TESTS[@]} -eq 0 ]; then
	echo "没有找到测试脚本（tests/headless/test_*.gd）。" >&2
	exit 2
fi

TOTAL_ITEMS=0
TOTAL_FAILS=0
BAD=0

for t in "${TESTS[@]}"; do
	rel="${t#./}"
	if [ ! -f "$rel" ]; then
		printf '%-30s 不存在\n' "$(basename "$rel")"
		BAD=1
		continue
	fi

	out="$(mktemp)"
	"$GODOT" --headless --path . --script "res://$rel" >"$out" 2>&1
	code=$?

	summary="$(grep -E '^=== [0-9]+ 项，失败 [0-9]+ ===$' "$out" | tail -1)"
	# 脚本级错误不会计入 fails，曾经导致「解析失败但汇总 0 失败」的假绿。
	script_err="$(grep -E 'SCRIPT ERROR|Parse Error|Failed to load script' "$out" | head -3)"
	if [ -n "$summary" ]; then
		n="$(printf '%s' "$summary" | sed -E 's/^=== ([0-9]+) 项，失败 ([0-9]+) ===$/\1/')"
		f="$(printf '%s' "$summary" | sed -E 's/^=== ([0-9]+) 项，失败 ([0-9]+) ===$/\2/')"
		TOTAL_ITEMS=$((TOTAL_ITEMS + n))
		TOTAL_FAILS=$((TOTAL_FAILS + f))
		if [ "$f" -eq 0 ] && [ "$code" -eq 0 ] && [ -z "$script_err" ]; then
			status="PASS"
		else
			status="FAIL"
			BAD=1
		fi
		printf '%-30s %s  %s\n' "$(basename "$rel")" "$summary" "$status"
	else
		printf '%-30s 无汇总（exit=%d）\n' "$(basename "$rel")" "$code"
		BAD=1
	fi

	grep '  FAIL  ' "$out" | sed 's/^/    /'
	rm -f "$out"
done

echo '----------------------------------------'
echo "合计：$TOTAL_ITEMS 项，失败 $TOTAL_FAILS"
if [ "$BAD" -ne 0 ] || [ "$TOTAL_FAILS" -ne 0 ]; then
	exit 1
fi
