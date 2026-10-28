#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""test_audit.py — 测试私有访问守卫。

为什么需要它：重构 `Desktop.gd` 时，私有字段 / 方法会不断移动。测试若直接访问
`scene._cards`、`scene._on_card_selected`，每一步拆分都会变成「改产品 + 改测试」的双倍
工作量，而且编译器不会提醒漏改。脚本把「现状」登记成基线：

  · 基线现已清空（`test_audit_baseline.txt` 只剩说明注释）——测试一律走
    `scene.debug.dbg_*` 接缝或真实输入事件；
  · 新增访问：`--check` 直接失败；
  · 访问消失：只提示「可清理」，不判失败。

用法：
    python tools/test_audit.py            # 打印当前清单
    python tools/test_audit.py --check    # 门槛：出现基线外的新访问 → 退出码 1
    python tools/test_audit.py --update   # 重建基线（只应在明确接受现状时跑）

扫描口径：`tests/**/*.gd` 中 `scene._xxx` / `desk._xxx`，以及
`scene.<controller>._xxx`（Desktop 仍持有状态，控制器只是宿主）。
窗口 / 卡片的视觉断言（如 `card._gui_input`）不在本守卫范围：它们是控件自身的
输入接线，不属于 Desktop 的私有实现；新增窗口级接缝时再单独收紧。
"""

from __future__ import annotations

import argparse
import os
import re
import sys

for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TESTS = os.path.join(ROOT, "tests")
BASELINE = os.path.join(HERE, "test_audit_baseline.txt")

# Desktop 实例在测试里通常叫 scene；保留 desk 以便后续重命名。
# 拆分后私有成员可能挂在 scene.<controller> 下，同样算「测试直连私有实现」。
CONTROLLERS = (
    "garden_music", "people", "tec", "matrix", "tutorial", "session", "canvas",
    "drag", "launcher", "narrative", "card_ui", "windows", "chrome",
)
TARGET_RE = re.compile(
    r"\b(?:scene|desk)\.(?:(?:" + "|".join(CONTROLLERS) + r")\.)?(_[A-Za-z0-9_]+)"
)


def collect() -> dict[str, list[tuple[str, int]]]:
    found: dict[str, list[tuple[str, int]]] = {}
    for dirpath, _dirnames, filenames in os.walk(TESTS):
        for fn in sorted(filenames):
            if not fn.endswith(".gd") or fn == "_test_base.gd":
                continue
            path = os.path.join(dirpath, fn)
            with open(path, encoding="utf-8") as f:
                for lineno, line in enumerate(f, 1):
                    code = line.split("#", 1)[0]
                    for match in TARGET_RE.finditer(code):
                        pair = match.group(0)
                        found.setdefault(pair, []).append(
                            (os.path.relpath(path, ROOT), lineno)
                        )
    return found


def load_baseline() -> set[str]:
    if not os.path.exists(BASELINE):
        return set()
    allowed: set[str] = set()
    with open(BASELINE, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                allowed.add(line)
    return allowed


def write_baseline(pairs: set[str]) -> None:
    with open(BASELINE, "w", encoding="utf-8", newline="\n") as f:
        f.write("# test_audit 基线：允许存在的 Desktop 私有访问。\n")
        f.write("# 只允许减少；新增访问请改走 DesktopDebug 或真实输入事件。\n")
        for pair in sorted(pairs):
            f.write(pair + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="测试私有访问守卫")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--check", action="store_true", help="基线外的新访问即失败")
    group.add_argument("--update", action="store_true", help="重建基线")
    parser.add_argument("--md", action="store_true", help="输出 Markdown 表")
    args = parser.parse_args()

    found = collect()
    pairs = set(found)

    if args.update:
        write_baseline(pairs)
        print(f"已写入基线：{len(pairs)} 条 → {os.path.relpath(BASELINE, ROOT)}")
        return 0

    if args.md:
        print("| 访问 | 次数 | 出处 |")
        print("|---|---:|---|")
        for pair in sorted(pairs, key=lambda p: (-len(found[p]), p)):
            where = ", ".join(f"{f}:{n}" for f, n in found[pair][:3])
            if len(found[pair]) > 3:
                where += " …"
            print(f"| `{pair}` | {len(found[pair])} | {where} |")
        return 0

    if args.check:
        allowed = load_baseline()
        new = sorted(pairs - allowed)
        stale = sorted(allowed - pairs)
        for pair in new:
            print(f"ERROR 新增私有访问：{pair}")
            for f, n in found[pair]:
                print(f"       {f}:{n}")
        if stale:
            print(f"NOTE  基线里已有 {len(stale)} 条不再出现，可择机清理：")
            print("       " + ", ".join(stale[:12]) + (" …" if len(stale) > 12 else ""))
        print(f"=== 当前 {len(pairs)} 条，新增 {len(new)} 条，基线 {len(allowed)} 条 ===")
        return 1 if new else 0

    for pair in sorted(pairs):
        print(f"{pair:36s} {len(found[pair])}")
    print(f"=== 共 {len(pairs)} 条 / {sum(len(v) for v in found.values())} 处 ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
