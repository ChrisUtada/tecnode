shader_type canvas_item;

// 分辨率无关的纸面：噪声按物理像素生成，窗口变大只增加采样面积，不拉伸纹理。
// 原来的 stage_paper.png 是 800p 的整图，720p 下会被纵向压 80px；这里改成
// 原生像素噪声 + 固定纸色，避免任何非整数倍重采样。

uniform vec4 paper_col : source_color = vec4(0.922, 0.910, 0.859, 1.0);
uniform vec4 grain_col : source_color = vec4(0.36, 0.34, 0.28, 1.0);
uniform float grain_amount : hint_range(0.0, 0.5) = 0.04;
uniform float fleck_amount : hint_range(0.0, 0.5) = 0.03;
uniform float vignette_amount : hint_range(0.0, 0.5) = 0.035;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec2 px = FRAGCOORD.xy;
	// 主纹理走逐像素 hash：只留细颗粒，不生成 4~6px 的软团块（旧版 coarse 层
	// 在 1280/1920 下会看成水彩斑）。低频只留 1% 的纸面不匀，负责大尺度明暗。
	float fine = hash21(px + 0.5);
	float fleck = smoothstep(0.985, 0.999, hash21(px * 1.37 + 83.0));
	float uneven = vnoise(px * 0.035 + 37.0);

	vec3 col = paper_col.rgb;
	col = mix(col, grain_col.rgb, (fine - 0.5) * grain_amount);
	col = mix(col, grain_col.rgb * 0.8, fleck * fleck_amount);
	col *= 1.0 + (uneven - 0.5) * 0.012;

	vec2 d = UV - vec2(0.5);
	float vig = smoothstep(0.38, 0.78, length(d));
	col *= 1.0 - vig * vignette_amount;

	COLOR = vec4(col, 1.0);
}
