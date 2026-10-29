shader_type canvas_item;
// ─────────────────────────────────────────────────────────────────────────────
// 单色网点渐隐遮罩（MONO P6.4）
//
// 用途：结局 / 开场全屏遮罩。目标不是半透明灰，而是**黑点的密度渐变**：
//   中心覆盖率 coverage_inner → 边缘 coverage_outer，按 4×4 Bayer 抖动。
// 每个像素只有「落墨」或「透明」两种结果，不产生连续 alpha 灰。
//
// 像素对齐：FRAGCOORD 是物理像素；cell 必须取整，避免窗口缩放后网点变形。
// UV 只用来算到中心的距离；网点本身永远按屏幕像素切格。
// ─────────────────────────────────────────────────────────────────────────────

uniform vec4 ink_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float coverage_inner : hint_range(0.0, 1.0) = 0.35;
uniform float coverage_outer : hint_range(0.0, 1.0) = 0.6;
uniform float radius_inner : hint_range(0.0, 2.0) = 0.15;
uniform float radius_outer : hint_range(0.0, 2.0) = 1.05;
uniform float cell : hint_range(1.0, 8.0) = 2.0;

const float BAYER4[16] = float[16](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0
);

float bayer_at(vec2 f) {
	int ix = int(mod(f.x, 4.0));
	int iy = int(mod(f.y, 4.0));
	return (BAYER4[iy * 4 + ix] + 0.5) / 16.0;
}

void fragment() {
	float c = max(cell, 1.0);
	vec2 g = floor(FRAGCOORD.xy / c);
	vec2 f = FRAGCOORD.xy - g * c;

	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float t = smoothstep(radius_inner, max(radius_inner + 0.001, radius_outer), d);
	float coverage = mix(coverage_inner, coverage_outer, t);

	float ink = coverage > bayer_at(f) ? 1.0 : 0.0;
	COLOR = vec4(ink_col.rgb, ink_col.a * ink);
}
