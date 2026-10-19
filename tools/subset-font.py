# -*- coding: utf-8 -*-
"""按「项目实际用字」重新裁剪凤凰点阵体（Vonwaon Bitmap），生成 src/assets/font.ttf。

背景：仓库原本的 font.ttf 只有 1393 个字，剧情里没被覆盖到的字（如「逼」）会按 CSS
字体栈回落到宋体，同一行里笔画风格突变。这个脚本从官方全量字体重新裁一份：

  font.ttf   12px 字模，用字 = data ∪ src（不含 editor）∪ ASCII ∪ GB2312 一级常用字

**只做一档**。官方另有一根 16px 字模，曾试过给叙事正文用（16px 字号落在 1× 上最锐利），
但那档的笔画只有 1px、相对字号是 1/16，比 12px 档细一圈，和界面其余文字并排就是「两种字」。
现在的口径是：全站一根 12px 字模，正文用 13px 字号（与节点详情同档），靠 +8% 的渲染厚度
而不是换字模来解决"看着太小"。

用法：
    python tools/subset-font.py [官方字体目录]

官方字体目录默认取 .workbuddy/fonts/（不入库），文件名固定为 VonwaonBitmap-12px.ttf。
下载：https://timothyqiu.itch.io/vonwaon-bitmap （CC0 1.0，公有领域）
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".workbuddy", "fonts")
OUT_DIR = os.path.join(ROOT, "src", "assets")
ASCII = {chr(c) for c in range(0x20, 0x7F)}


def walk_strings(node, out):
    if isinstance(node, dict):
        for v in node.values():
            walk_strings(v, out)
    elif isinstance(node, list):
        for v in node:
            walk_strings(v, out)
    elif isinstance(node, str):
        out.update(node)


def data_chars():
    cs = set()
    d = json.load(open(os.path.join(ROOT, "data", "case-a001.json"), encoding="utf-8"))
    walk_strings(d, cs)
    return cs | ASCII


def src_chars():
    cs = set()
    for dp, _, fs in os.walk(os.path.join(ROOT, "src")):
        if os.sep + "editor" in dp:
            continue
        for fn in fs:
            if fn.endswith((".js", ".html", ".css")):
                cs.update(open(os.path.join(dp, fn), encoding="utf-8").read())
    return cs


def gb2312_level1():
    cs = set()
    for b1 in range(0xB0, 0xD8):
        for b2 in range(0xA1, 0xFF):
            try:
                cs.add(bytes([b1, b2]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return cs


def subset(src, chars, out):
    text = "".join(sorted(c for c in chars if ord(c) >= 0x20))
    tmp = out + ".txt"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    subprocess.check_call([
        sys.executable, "-m", "fontTools.subset", src,
        "--text-file=" + tmp,
        "--output-file=" + out,
        "--layout-features=*",
        "--no-hinting",
    ])
    os.remove(tmp)
    print("  %-14s %5d 字  %6.0f KB" % (os.path.basename(out), len(text), os.path.getsize(out) / 1024))


def main():
    f12 = os.path.join(SRC_DIR, "VonwaonBitmap-12px.ttf")
    if not os.path.exists(f12):
        sys.exit("缺少官方字体：" + f12 + "（下载见脚本头部注释）")

    body = data_chars()
    print("data 用字：%d" % len(body))
    print("生成：")
    subset(f12, body | src_chars() | gb2312_level1(), os.path.join(OUT_DIR, "font.ttf"))


if __name__ == "__main__":
    main()
