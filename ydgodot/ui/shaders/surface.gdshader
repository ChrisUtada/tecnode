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

// CSS 的 box-shadow 是「两盏」：左上暖白高光 + 右下暖墨软影。
// 默认关掉（alpha 0）：节点卡的 pad 只有 8px，7px 模糊的高光会被画布边界裁成硬边，
// 反而比不画更糟（实测 stage 区 +1991 px）。图标块的余量够，那边显式打开。
uniform vec4 glow_col : source_color = vec4(1.0, 0.988, 0.945, 0.0);
uniform vec2 glow_offset = vec2(-2.0, -3.0);
uniform float glow_soft = 7.0;

float sd_rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void fragment() {
	vec2 px = (UV - 0.5) * rect_size;
	vec2 half_size = rect_size * 0.5 - vec2(pad);

	// 外投影：近似 box-shadow 的模糊。
	// ⚠ 衰减必须**跨着边缘对称**（-soft → +soft）：CSS 的 box-shadow 是一圈高斯，
	// 在盒子边界上恰好衰减到一半（50% alpha）。原先写成 `-1 → soft` 是「边界上还近乎满值、
	// 出去以后陡降」，看着就像沿着块边描了一圈深影 —— 图标栏每格 800 多像素差异全在这。
	// 实测改成对称后全屏 2.70% → 2.30%。
	float d_sh = sd_rbox(px - shade_offset, half_size, radius);
	float sh_a = shade_col.a * (1.0 - smoothstep(-shade_soft, shade_soft, d_sh));

	float d_gl = sd_rbox(px - glow_offset, half_size, radius);
	float gl_a = glow_col.a * (1.0 - smoothstep(-1.0, glow_soft, d_gl));

	// 卡面
	float d = sd_rbox(px, half_size, radius);
	// 1-bit：**硬切**。原来 `smoothstep(-0.75, 0.75, d)` 是一圈 1.5px 的半透明过渡，
	// 在白纸上读作「毛边」，也把纯黑描边稀释成灰。像素级硬边是这套界面的底线。
	// 阈值放到 +0.5：卡片是**连续缩放**的（0.62~1.3x），边缘几乎不可能落在整数像素上，
	// 用 step(0, d) 会把整像素切掉、只剩亚像素覆盖 —— 肉眼看到的就是「一圈灰毛」。
	// 放宽半像素仍是硬边（没有渐变过渡），但能稳定占满一个像素。
	float body = 1.0 - smoothstep(-0.5, 0.5, d);

	vec3 base = col_mid.rgb;
	if (!flat_fill) {
		// Web 全线是 `linear-gradient(150deg, hi 0%, card ~52~55%, lo 100%)`。
		// 150deg 的方向向量 = (sin150, -cos150) = (0.5, 0.866)：右下走向，不是纯竖直。
		// 按竖直插值整块卡的下半部会偏亮（实测差 492 px / 屏，全在图标块与节点卡上）。
		vec2 gdir = vec2(0.5, 0.866);
		float glen = abs(half_size.x * 2.0 * gdir.x) + abs(half_size.y * 2.0 * gdir.y);
		float t = clamp((dot(px, gdir) + glen * 0.5) / max(glen, 1.0), 0.0, 1.0);
		base = mix(col_hi.rgb, col_mid.rgb, smoothstep(0.0, 0.52, t));
		base = mix(base, col_lo.rgb, smoothstep(0.52, 1.0, t) * gradient_mix);
	}

	// 内侧左上高光 / 右下阴影（对应 --raise 的两侧明暗）
	float inner = smoothstep(-3.2, -0.6, d) * body;           // 贴边 3px 内
	vec2 n = normalize(vec2(px.x / max(half_size.x, 1.0), px.y / max(half_size.y, 1.0)) + vec2(0.0001));
	float lit = clamp(0.5 - 0.5 * (n.x + n.y), 0.0, 1.0);
	base = mix(base, rim_col.rgb, inner * rim_col.a * lit * 0.75);

	float dark = clamp(0.5 + 0.5 * (n.x + n.y), 0.0, 1.0);
	base = mix(base, shade_col.rgb, inner * shade_col.a * dark * 0.9);

	// 1px 描边 = `border:1px solid var(--edge)`。ring 梯度铺开约 1.4px（比 CSS 那条真 1px
	// 边界软），按 edge 的 alpha 打七折会太淡、乘 3 倍又成了实墨黑边；1.4 是对拍扫出来的档位。
	// 环带 = 区间相减：d ∈ [-1.5, 0) 为 1，其余为 0。
	// ⚠ 别写成 `1.0 - smoothstep(...)` —— 那样卡片**内部**也会是 1，整块涂黑。
	float ring = step(-1.5, d) - step(0.0, d);
	// 硬边不再需要 ×1.4 的补偿（那是给软渐变补 alpha 的）
	base = mix(base, edge_col.rgb, ring * clamp(edge_col.a, 0.0, 1.0));

	// 影子合成：CSS 里先画高光再画暗影，所以暗影压在上面
	float sa = 1.0 - (1.0 - sh_a) * (1.0 - gl_a);
	vec3 srgb = shade_col.rgb;
	if (sa > 0.0001) {
		srgb = (shade_col.rgb * sh_a + glow_col.rgb * gl_a * (1.0 - sh_a)) / sa;
	}
	COLOR = vec4(mix(srgb, base, body), max(sa, body));
}
