shader_type canvas_item;
// ─────────────────────────────────────────────────────────────────────────────
// 单色表面（P2 / P3 用）—— 硬边填充 + 1px 硬描边 + 硬投影
//
// 与 `surface.gdshader` 的关系：**参数同名**，所以逐处替换时把 `load()` 指向本文件
// 就够，调用方一行不用改。区别在渲染口径：
//
//   surface（柔和浮雕）              mono（单色硬边）
//   ─────────────────────────────    ─────────────────────────────
//   body  = 1 - smoothstep(-.75,.75)  body  = step(0, d)   —— 0.75px 过渡都不要
//   ring  ≈ 1.4px 渐隐                 ring  = step(-edge_w, d) —— 真 1px 硬线
//   投影 4 层高斯叠                 投影  = step(0, d_shift) —— 纯平移，不模糊
//   三档渐变 hi/mid/lo              纯色填充（专色靠符号，不靠底色）
//
// 为什么去掉柔和：软边在 1x 屏上会摊成半透明灰线，缩到 0.62x 再采样一次就成了脏边。
// 硬边（step）在任意缩放下要么整像素、要么没有，这才是点阵该有的样子。
//
// 未接线：P0 只把文件摆好，材质切换在 P2（`SysWindow._uses_baked_frame()` 改 false 之后）。
// ─────────────────────────────────────────────────────────────────────────────

uniform vec2 rect_size = vec2(168.0, 70.0);
uniform float pad = 8.0;
// 5 而不是 13：3px 圆角以下才看得出「方」，13px 在 130px 的卡上已经接近胶囊。
uniform float radius = 5.0;

// 填充。老名字 `col_mid` 保留，方便把 surface 的赋值原样搬过来。
uniform vec4 col_mid : source_color = vec4(0.961, 0.949, 0.910, 1.0);
uniform vec4 col_hi : source_color = vec4(0.984, 0.973, 0.933, 1.0);
uniform vec4 col_lo : source_color = vec4(0.933, 0.914, 0.843, 1.0);
// >0 时按 hi→lo 走一道竖直渐变；0 = 纯色。单色骨架默认 0。
uniform float gradient_mix = 0.0;

// 1px 硬描边。宽度可以是 0（无框）、1（常规）、2（点亮/强调）。
uniform vec4 edge_col : source_color = vec4(0.169, 0.169, 0.149, 1.0);
uniform float edge_w = 1.0;

// 硬投影：把矩形 SDF 平移后直接 step 出来 —— 没有模糊，就是一块错位的实色。
// 单色方案里它承担「窗比桌高一层」的信息，所以宁可硬。
uniform vec4 shade_col : source_color = vec4(0.306, 0.282, 0.212, 0.30);
uniform vec2 shade_offset = vec2(3.0, 4.0);

// 内侧 1px 高光（左上）。柔版是靠一圈内发光做的，单色版只在左上角补一条。
uniform vec4 rim_col : source_color = vec4(1.0, 0.988, 0.945, 0.0);

// 填充网点。单色方案用来区分「面 = 纸」和「面 = 网点纸」（比如未探索的容器）。
uniform bool pattern_on = false;
uniform int pattern_kind = 0;          // 0 网点 / 1 棋盘 / 2 横纹 / 3 竖纹
uniform float pattern_cell = 2.0;      // 每格多少**物理像素**
uniform float pattern_density = 0.25;  // 只对网点有效：点的面积占比
uniform vec4 pattern_col : source_color = vec4(0.169, 0.169, 0.149, 0.25);

float sd_rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

// 像素级图案：以 FRAGCOORD（物理像素）取整分格，缩放/平移都不会让网点变形或起摩尔纹。
float pattern_mask() {
	float c = max(pattern_cell, 1.0);
	vec2 g = floor(FRAGCOORD.xy / c);
	vec2 f = FRAGCOORD.xy - g * c;   // 格内偏移，单位=物理像素
	if (pattern_kind == 1) {
		return mod(g.x + g.y, 2.0) < 0.5 ? 1.0 : 0.0;
	} else if (pattern_kind == 2) {
		return mod(g.y, 2.0) < 0.5 ? 1.0 : 0.0;
	} else if (pattern_kind == 3) {
		return mod(g.x, 2.0) < 0.5 ? 1.0 : 0.0;
	}
	// 网点：边长为 round(sqrt(density) * c) 的方块居中。density=.25、c=2 → 1 个像素，
	// 正好 25%；c=4 → 2×2 / 16。用方块不用圆，因为 2px 的圆画出来就是一个十字。
	float d = clamp(sqrt(pattern_density), 0.0, 1.0);
	float side = floor(d * c + 0.5);
	if (side <= 0.0) {
		return 0.0;
	}
	vec2 cen = vec2(c * 0.5);
	vec2 half_side = vec2(side * 0.5);
	vec2 q = abs(f - cen) - half_side;
	float m = 1.0 - step(0.0, max(q.x, q.y));
	return m;
}

void fragment() {
	vec2 px = (UV - 0.5) * rect_size;
	vec2 half_size = rect_size * 0.5 - vec2(pad);
	float r = min(radius, min(half_size.x, half_size.y));

	// 硬投影：先看「平移后的形状」里有没有这个像素
	float d_sh = sd_rbox(px - shade_offset, half_size, r);
	float sh = step(0.0, d_sh) * shade_col.a;

	// 主体
	float d = sd_rbox(px, half_size, r);
	float body = step(0.0, d);

	// 填充色（可选渐变，默认纯色）
	vec3 base = col_mid.rgb;
	if (gradient_mix > 0.001) {
		float t = clamp((px.y + half_size.y) / max(half_size.y * 2.0, 1.0), 0.0, 1.0);
		base = mix(col_hi.rgb, col_lo.rgb, t * gradient_mix);
	}
	if (pattern_on) {
		base = mix(base, pattern_col.rgb, pattern_mask() * pattern_col.a);
	}

	// 内侧左上 1px 高光：贴边且法线朝左上
	if (rim_col.a > 0.001) {
		float inner = step(-1.0, d) * body;
		vec2 n = normalize(vec2(px.x / max(half_size.x, 1.0), px.y / max(half_size.y, 1.0)) + vec2(0.0001));
		float lit = clamp(0.5 - 0.5 * (n.x + n.y), 0.0, 1.0);
		base = mix(base, rim_col.rgb, inner * rim_col.a * step(0.5, lit));
	}

	// 1px 硬描边：d 落在 [-edge_w, 0] 的那一圈
	if (edge_w > 0.001) {
		float ring = step(-edge_w, d) * body;
		base = mix(base, edge_col.rgb, ring * edge_col.a);
	}

	COLOR = vec4(mix(shade_col.rgb, base, body), max(sh, body));
}
