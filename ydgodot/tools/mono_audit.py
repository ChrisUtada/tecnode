#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mono_audit.py — 单色改版 P0.4：把散落的 `Color(...)` 字面量揪出来，按「色值 → 出处」列清单。

为什么需要它：单色改版的整条路子建立在「调色只改 `ui/TecTheme.gd` 十几行」上。
只要还有一处 `Color("8a5a3b")` 散在窗口类里，改色就会漏，而且漏得悄无声息
（那处不改也照样能跑，只是颜色不对）。所以把「有没有漏」做成一个可执行的检查。

用法：
    python tools/mono_audit.py           # 打印清单（按色值分组）
    python tools/mono_audit.py --md      # 打印 Markdown 表，可贴进文档
    python tools/mono_audit.py --check   # 门槛模式：任何非白名单字面量 → 退出码 1
    python tools/mono_audit.py --count   # 只报数量

白名单：
  * `ui/TecTheme.gd` 全文件 —— 调色板本体，色值**只准**出现在这里。
  * `tests/` —— 断言里写死期望色是刻意的（测的就是「这个色没被改」），
    默认排除；`--with-tests` 可一并扫。

扫描规则：
  * 只看 `.gd`（`.tscn` / `.tres` 里没有颜色；shader 的 uniform 默认值只是兜底，
    运行期一律由 GDScript 覆盖，不参与调色板）。
  * 跳过 `addons/`（第三方）。
  * 跳过注释里的 `Color(...)`（`#` 之后、且不在字符串里）。
  * 识别两种写法：`Color("rrggbb"[aa])` 与 `Color(r, g, b[, a])`。
  * `Color(OTHER_COLOR, 0.5)`（改 alpha）不算字面量，跳过 —— 它已经引用了常量。
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections import defaultdict

# Windows 控制台默认 GBK，打印 ✅ / 中文会直接抛 UnicodeEncodeError；CI 与本地统一成 UTF-8。
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

PALETTE_FILE = "ui/TecTheme.gd"
SKIP_DIRS = {"addons", ".git", ".godot"}

# C-D：三层体系的常量和材质色文件域。
REQUIRED_CONSTANTS = {"SPOT_ACCENT", "MAT_FLAME", "MAT_EMBER", "MAT_DUST", "MAT_ASH", "MAT_PLANT"}
MATERIAL_CONSTANTS = {"MAT_FLAME", "MAT_EMBER", "MAT_DUST", "MAT_ASH", "MAT_PLANT"}
# 材质色只允许出现在画布 / 特效 / 内容容器相关文件；铬件（窗、按钮、页眉）引用即报错。
MATERIAL_ALLOWED = (
    "scenes/cards/",
    "scenes/windows/GardenWin.gd",
    "scenes/windows/MemCard.gd",
    "ui/effects/",
)

# Color("rrggbb") / Color("rrggbbaa") / Color('#rrggbb')
RE_HEX = re.compile(r'Color\(\s*[\'"]#?([0-9a-fA-F]{3,8})[\'"]\s*\)')
# Color(0.1, 0.2, 0.3) / Color(0.1, 0.2, 0.3, 0.4)（允许换行、允许行尾注释）
RE_NUM = re.compile(
    r"Color\(\s*"
    r"(-?\d*\.?\d+)\s*,\s*"
    r"(-?\d*\.?\d+)\s*,\s*"
    r"(-?\d*\.?\d+)"
    r"(?:\s*,\s*(-?\d*\.?\d+))?\s*\)"
)


def strip_comment(line: str) -> str:
    """去掉行内注释：`#` 之前若在字符串里则不算注释。"""
    out = []
    quote = ""
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            out.append(ch)
            if ch == "\\":
                if i + 1 < len(line):
                    out.append(line[i + 1])
                    i += 2
                    continue
            elif ch == quote:
                quote = ""
        else:
            if ch in "\"'":
                quote = ch
                out.append(ch)
            elif ch == "#":
                break
            else:
                out.append(ch)
        i += 1
    return "".join(out)


def hex_from_nums(r: str, g: str, b: str, a: str | None) -> str:
    """把 0~1 浮点四元组还原成 `rrggbb`（+ `aa`），用于把两种写法归到同一个色值。"""
    def byte(v: float) -> int:
        return max(0, min(255, int(round(v * 255.0))))

    parts = [byte(float(r)), byte(float(g)), byte(float(b))]
    if a is not None and abs(float(a) - 1.0) > 1e-6:
        parts.append(byte(float(a)))
    return "".join(f"{p:02x}" for p in parts)


def normalize_hex(raw: str) -> str:
    """`#abc` → `aabbcc`；统一小写。"""
    h = raw.lower()
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    elif len(h) == 4:  # rgba 短写
        h = "".join(c * 2 for c in h)
    return h


def iter_gd(with_tests: bool, palette_too: bool):
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        rel_dir = os.path.relpath(dirpath, ROOT).replace("\\", "/")
        if rel_dir == ".":
            rel_dir = ""
        if not with_tests and rel_dir.split("/")[0] == "tests":
            continue
        for name in sorted(filenames):
            if not name.endswith(".gd"):
                continue
            rel = f"{rel_dir}/{name}" if rel_dir else name
            if not palette_too and rel == PALETTE_FILE:
                continue
            yield rel, os.path.join(dirpath, name)


def scan(with_tests: bool = False, palette_too: bool = False):
    """返回 [(file, line_no, 归一化色值, 原始片段)]。"""
    hits = []
    for rel, path in iter_gd(with_tests, palette_too):
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for no, raw_line in enumerate(fh, 1):
                # 注释先砍掉；`Color(` 本身不会跨行出现在字符串里，
                # 多行写法（`Color(\n ... )`）在 GDScript 里极其罕见，按行处理够用。
                line = strip_comment(raw_line)
                if "Color(" not in line:
                    continue
                for m in RE_HEX.finditer(line):
                    hits.append((rel, no, normalize_hex(m.group(1)), m.group(0)))
                for m in RE_NUM.finditer(line):
                    hits.append(
                        (rel, no, hex_from_nums(*m.groups()), m.group(0))
                    )
    return hits


def palette_values():
    """从 TecTheme.gd 抽出所有 const 的色值（含被引用的别名），作为「合法调色板」集合。"""
    path = os.path.join(ROOT, PALETTE_FILE)
    vals = set()
    if not os.path.exists(path):
        return vals
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw_line in fh:
            line = strip_comment(raw_line)
            for m in RE_HEX.finditer(line):
                vals.add(normalize_hex(m.group(1)))
            for m in RE_NUM.finditer(line):
                vals.add(hex_from_nums(*m.groups()))
    return vals


def report_text(hits):
    by_val = defaultdict(list)
    for rel, no, val, snippet in hits:
        by_val[val].append((rel, no, snippet))

    if not hits:
        print("✅ 没有散落的 Color(...) 字面量。")
        return

    files = {rel for rel, _, _, _ in hits}
    print(f"共 {len(hits)} 处字面量，{len(by_val)} 个不同色值，分布在 {len(files)} 个文件。\n")
    for val in sorted(by_val, key=lambda v: (-len(by_val[v]), v)):
        spots = by_val[val]
        print(f"#{val}  ×{len(spots)}")
        for rel, no, snippet in spots:
            print(f"    {rel}:{no}   {snippet}")
        print()


def report_md(hits):
    by_val = defaultdict(list)
    for rel, no, val, snippet in hits:
        by_val[val].append((rel, no))

    files = {rel for rel, _, _, _ in hits}
    print(f"共 {len(hits)} 处 / {len(by_val)} 色 / {len(files)} 文件\n")
    print("| 色值 | 次数 | 出处 |")
    print("|---|---|---|")
    for val in sorted(by_val, key=lambda v: (-len(by_val[v]), v)):
        spots = by_val[val]
        where = "、".join(f"`{rel.split('/')[-1]}:{no}`" for rel, no in spots)
        print(f"| `#{val}` | {len(spots)} | {where} |")


def palette_constants():
    """返回 TecTheme 里 `const NAME :=` 的常量名集合。"""
    path = os.path.join(ROOT, PALETTE_FILE)
    names = set()
    if not os.path.exists(path):
        return names
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw_line in fh:
            line = strip_comment(raw_line)
            m = re.match(r"\s*const\s+([A-Z0-9_]+)\s*:=", line)
            if m:
                names.add(m.group(1))
    return names


def material_violations():
    """C-D：MAT_* 只能出现在允许域；同时检查六个三层常量都已登记。"""
    bad = []
    missing = sorted(REQUIRED_CONSTANTS - palette_constants())
    if missing:
        bad.append(f"TecTheme 缺少三层常量：{', '.join(missing)}")
    for rel, path in iter_gd(with_tests=False, palette_too=False):
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for no, raw_line in enumerate(fh, 1):
                line = strip_comment(raw_line)
                for name in MATERIAL_CONSTANTS:
                    if f"TecTheme.{name}" not in line:
                        continue
                    if not any(rel.startswith(prefix) for prefix in MATERIAL_ALLOWED):
                        bad.append(f"{rel}:{no}  材质色 {name} 出现在非内容域")
    return bad


def report_check(hits, strict_palette: bool):
    """门槛模式：字面量必须全部收进 TecTheme，或者等于调色板里的某个值。"""
    ok = palette_values() if not strict_palette else set()
    bad = [h for h in hits if h[2] not in ok]
    mat_bad = material_violations()
    if not bad and not mat_bad:
        print(f"✅ 通过：{len(hits)} 处字面量全部命中 TecTheme 调色板；"
              f"三层常量齐全，材质色文件域合规。")
        return 0
    if bad:
        print(f"❌ 有 {len(bad)} 处字面量不在调色板里：")
        for rel, no, val, snippet in bad:
            print(f"    {rel}:{no}   #{val}   {snippet}")
    for msg in mat_bad:
        print(f"❌ {msg}")
    return 1


def main() -> int:
    ap = argparse.ArgumentParser(description="扫描散落的 Color(...) 字面量")
    ap.add_argument("--md", action="store_true", help="输出 Markdown 表")
    ap.add_argument("--check", action="store_true", help="门槛模式：有漏即退出码 1")
    ap.add_argument("--count", action="store_true", help="只报数量")
    ap.add_argument("--with-tests", action="store_true", help="连 tests/ 一起扫")
    ap.add_argument(
        "--strict-palette",
        action="store_true",
        help="配合 --check：连「等于调色板色值」也判失败，要求全部走常量名",
    )
    args = ap.parse_args()

    hits = scan(with_tests=args.with_tests)

    if args.count:
        print(f"{len(hits)} 处 / {len({h[2] for h in hits})} 色")
        return 0
    if args.check:
        return report_check(hits, args.strict_palette)
    if args.md:
        report_md(hits)
        return 0
    report_text(hits)
    return 0


if __name__ == "__main__":
    sys.exit(main())
