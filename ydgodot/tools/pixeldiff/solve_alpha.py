"""由「白底 / 黑底」两张底片反解系统窗九切片的直通 alpha。

    over_bg = src * a + bg * (1 - a)

两式相减消掉 src：a = 1 - (V_white - V_black) / 255；再回代求 src。
窗内（不透明卡面）两底片相同 ⇒ a = 1，直接取白底颜色。

用法：python ydgodot/tools/pixeldiff/solve_alpha.py
产出：ydgodot/assets/baked/win_frame.png
"""

from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
BAKED = HERE.parents[1] / "assets" / "baked"
WIN = (100, 66, 1164, 718)  # x, y, w, h —— 与 #case-win 的 CSS 计算值一致
MARGIN = 46                # 9-slice 四角尺寸：13px 圆角 + 22px 投影 + 余量


def main() -> None:
    w = Image.open(BAKED / "_win_white.png").convert("RGB")
    b = Image.open(BAKED / "_win_black.png").convert("RGB")
    box = (WIN[0] - MARGIN, WIN[1] - MARGIN,
           WIN[0] + WIN[2] + MARGIN, WIN[1] + WIN[3] + MARGIN)
    w = w.crop(box)
    b = b.crop(box)

    out = Image.new("RGBA", w.size)
    pw, pb, po = w.load(), b.load(), out.load()
    stats = {"opaque": 0, "clear": 0, "partial": 0}
    for y in range(w.height):
        for x in range(w.width):
            wr, wg, wb = pw[x, y]
            br, bg, bb = pb[x, y]
            # 三个通道的 alpha 估计取均值（抗锯齿处会有 1 的量化误差）
            a = 1.0 - ((wr - br) + (wg - bg) + (wb - bb)) / 3.0 / 255.0
            a = max(0.0, min(1.0, a))
            if a <= 0.002:
                po[x, y] = (0, 0, 0, 0)
                stats["clear"] += 1
                continue
            if a >= 0.998:
                po[x, y] = (wr, wg, wb, 255)
                stats["opaque"] += 1
                continue
            # 回代：src = (V_white - 255*(1-a)) / a
            def solve(v):
                return max(0, min(255, round((v - 255.0 * (1.0 - a)) / a)))
            po[x, y] = (solve(wr), solve(wg), solve(wb), round(a * 255))
            stats["partial"] += 1

    out.save(BAKED / "win_frame.png")
    print("写出", BAKED / "win_frame.png", out.size)
    print("不透明 %d / 全透明 %d / 半透明 %d" % (stats["opaque"], stats["clear"], stats["partial"]))
    # 抽查：边框上沿、阴影正下方、卡面中心
    for name, (px, py) in {
        "卡面中心": (MARGIN + WIN[2] // 2, MARGIN + WIN[3] // 2),
        "上边框 y=0": (MARGIN + WIN[2] // 2, MARGIN),
        "边框上方 2px": (MARGIN + WIN[2] // 2, MARGIN - 2),
        "下边框外 6px": (MARGIN + WIN[2] // 2, MARGIN + WIN[3] + 6),
        "下边框外 14px": (MARGIN + WIN[2] // 2, MARGIN + WIN[3] + 14),
    }.items():
        print("  %-12s %s" % (name, out.getpixel((px, py))))


if __name__ == "__main__":
    main()
