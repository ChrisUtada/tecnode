shader_type canvas_item;
// 柔和浮雕表面（对齐 CSS 的 --raise / --win-shadow / 卡片渐变）
// 节点尺寸由脚本写进 rect_size；pad 是留给外投影的透明边距。
// P3 若改用烘焙九切片，直接把这个材质换掉即可（接口不变）。

uniform vec2 rect_size = vec2(168.0, 70.0);
uniform float pad = 8.0;
uniform float radius = 11.0;

uniform vec4 col_hi : source_color = vec4(0.984, 0.973, 0.933, 1.0);
uniform vec4 col_mid : source_color = vec4(0.961, 0.949, 0.910, 1.0);
uniform vec4 col_lo : source_color = vec4(0.933, 0.914, 0.843, 1.0);
uniform vec4 edge_col : source_color = vec4(0.290, 0.271, 0.204, 0.30);
uniform vec4 rim_col : source_color = vec4(1.0, 0.988, 0.945, 0.95);
uniform vec4 shade_col : source_color = vec4(0.306, 0.282, 0.212, 0.30);
uniform vec2 shade_offset = vec2(3.0, 4.0);
uniform float shade_soft = 7.0;
uniform float gradient_mix = 1.0;
uniform bool flat_fill = false;

float sd_rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void fragment() {
	vec2 px = (UV - 0.5) * rect_size;
	vec2 half_size = rect_size * 0.5 - vec2(pad);

	// 外投影：SDF 的柔性衰减近似 box-shadow 的模糊
	float d_sh = sd_rbox(px - shade_offset, half_size, radius);
	float sh = 1.0 - smoothstep(-1.0, shade_soft, d_sh);
	float sh_a = shade_col.a * sh;

	// 卡面
	float d = sd_rbox(px, half_size, radius);
	float body = 1.0 - smoothstep(-0.75, 0.75, d);

	vec3 base = col_mid.rgb;
	if (!flat_fill) {
		float t = clamp((px.y + half_size.y) / max(half_size.y * 2.0, 1.0), 0.0, 1.0);
		base = mix(col_hi.rgb, col_mid.rgb, smoothstep(0.0, 0.5, t));
		base = mix(base, col_lo.rgb, smoothstep(0.5, 1.0, t) * gradient_mix);
	}

	// 内侧左上高光 / 右下阴影（对应 --raise 的两侧明暗）
	float inner = smoothstep(-3.2, -0.6, d) * body;           // 贴边 3px 内
	vec2 n = normalize(vec2(px.x / max(half_size.x, 1.0), px.y / max(half_size.y, 1.0)) + vec2(0.0001));
	float lit = clamp(0.5 - 0.5 * (n.x + n.y), 0.0, 1.0);
	base = mix(base, rim_col.rgb, inner * rim_col.a * lit * 0.75);

	float dark = clamp(0.5 + 0.5 * (n.x + n.y), 0.0, 1.0);
	base = mix(base, shade_col.rgb, inner * shade_col.a * dark * 0.9);

	// 1px 描边
	float ring = smoothstep(-1.6, -0.2, d) * body;
	base = mix(base, edge_col.rgb, ring * clamp(edge_col.a * 3.0, 0.0, 1.0));

	vec4 outc = vec4(base, body);
	outc = vec4(mix(shade_col.rgb, outc.rgb, body), max(sh_a, body));
	COLOR = outc;
}
