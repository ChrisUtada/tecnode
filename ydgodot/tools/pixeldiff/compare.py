import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageStat


def parse_region(value):
    name, coords = value.split(":", 1)
    x, y, w, h = (int(v) for v in coords.split(","))
    return name, (x, y, x + w, y + h)


def ratio(mask, threshold, crop=None):
    m = mask.crop(crop) if crop else mask
    hist = m.histogram()
    total = m.width * m.height
    changed = sum(hist[threshold + 1:])
    return changed / total if total else 0.0


def channel_max_diff(a, b):
    diff = ImageChops.difference(a, b)
    r, g, bl = diff.split()
    return ImageChops.lighter(ImageChops.lighter(r, g), bl)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--a", required=True, help="reference image")
    parser.add_argument("--b", required=True, help="candidate image")
    parser.add_argument("--out", required=True, help="output prefix")
    parser.add_argument("--threshold", type=int, default=8)
    parser.add_argument(
        "--region",
        action="append",
        default=[],
        help="name:x,y,w,h (repeatable)",
    )
    ns = parser.parse_args()

    a_path = Path(ns.a)
    b_path = Path(ns.b)
    out = Path(ns.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    a = Image.open(a_path).convert("RGB")
    b = Image.open(b_path).convert("RGB")
    if a.size != b.size:
        raise SystemExit(f"size mismatch: {a.size} != {b.size}")

    mask = channel_max_diff(a, b)
    stat = ImageStat.Stat(mask)
    diff = ImageChops.difference(a, b)
    rgb_stat = ImageStat.Stat(diff)

    base = a.convert("L").point(lambda p: int(p * 0.35))
    red = Image.new("RGB", a.size, (255, 54, 54))
    heat = Image.composite(red, base, mask.point(lambda p: 255 if p > ns.threshold else 0))
    heat.save(out.with_name(out.name + "_diff.png"))

    black = Image.new("L", a.size, 0)
    white = Image.new("L", a.size, 255)
    Image.merge("RGB", (
        Image.composite(white, black, mask.point(lambda p: 255 if p > ns.threshold else 0)),
        black,
        black,
    )).save(out.with_name(out.name + "_mask.png"))

    pair = Image.new("RGB", (a.width * 2 + 8, a.height), (32, 32, 32))
    pair.paste(a, (0, 0))
    pair.paste(b, (a.width + 8, 0))
    pair.save(out.with_name(out.name + "_pair.png"))

    regions = {}
    for value in ns.region:
        name, crop = parse_region(value)
        if crop[0] < 0 or crop[1] < 0 or crop[2] > a.width or crop[3] > a.height:
            raise SystemExit(f"region out of bounds: {value}")
        regions[name] = {
            "rect": [crop[0], crop[1], crop[2] - crop[0], crop[3] - crop[1]],
            "ratio_gt0": ratio(mask, 0, crop),
            "ratio_gt8": ratio(mask, 8, crop),
            "ratio_gt16": ratio(mask, 16, crop),
        }

    result = {
        "a": str(a_path.resolve()),
        "b": str(b_path.resolve()),
        "size": list(a.size),
        "threshold": ns.threshold,
        "ratio_gt0": ratio(mask, 0),
        "ratio_gt8": ratio(mask, 8),
        "ratio_gt16": ratio(mask, 16),
        "mean_abs_rgb": [round(v, 4) for v in rgb_stat.mean],
        "max_channel_diff": int(mask.getextrema()[1]),
        "mismatch_bbox": list(mask.getbbox()) if mask.getbbox() else None,
        "regions": regions,
    }
    out.with_suffix(".json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")

    print(json.dumps(result, ensure_ascii=False, indent=2))
    print("summary:", ", ".join(f"{k}={v * 100:.3f}%" for k, v in result.items() if k.startswith("ratio_gt")))


if __name__ == "__main__":
    main()
