shader_type canvas_item;
// ─────────────────────────────────────────────────────────────────────────────
// 单色图案层（P1 用）—— 桌布的网点 / 棋盘 / 条纹
//
// 目标：把桌布做成**印刷网点**，而不是「渐变 + 噪点」。参考图里那片灰不是平涂的灰，
// 是 25% 覆盖的黑点。这么做有三个好处：
//   1. 它是「单色」的 —— 只有墨和纸两支颜色，没有中间灰，符合 1-bit 骨架；
//   2. 卡片（纸白）压在上面会自然浮起来，不需要靠投影也能分层；
//   3. 放大不会变糊：点阵永远整像素。
//
// 像素对齐：cell 以 `floor(FRAGCOORD / cell)` 取整分格。FRAGCOORD 是**物理像素**，
// 所以窗口缩放、相机平移都不会让网点变形、也不会起摩尔纹（用 UV 就会有这个毛病）。
//
// 四种图案：
//   DOT     有序抖动（Bayer 4×4）—— 覆盖率连续可调；cell=2 时是 2px 栅格上的 1px 墨点
//   CHECKER 棋盘格（50%，最硬的分层）
//   HLINE   横纹
//   VLINE   竖纹
//
// P1 已接到 `Desktop.gd` 的 `stage_bg`：DOT / 25% / cell 2。
// ─────────────────────────────────────────────────────────────────────────────

uniform vec4 paper_col : source_color = vec4(0.984314, 0.980392, 0.960784, 1.0); // #FBFAF5
uniform vec4 ink_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);         // INK #000000
// 覆盖率是阈值：Bayer 值低于 coverage 的像素落墨。25% + cell 2 时,
// 每个 2×2 格落一个 1px 实心墨点（面积正好 1/4）。
uniform float coverage : hint_range(0.0, 1.0) = 0.25;
uniform float cell = 2.0;     // 每格多少物理像素；2 = 最细的 25% 网点
uniform int pattern = 0;      // 0 DOT / 1 CHECKER / 2 HLINE / 3 VLINE

// Bayer 4×4（值 0..15，越小越先上墨）。有序抖动：阈值按矩阵顺序铺开，
// 覆盖率 4/16 时点会挤在四个角上形成斜向网点，而不是「左上角一块黑」。
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

	float ink = 0.0;
	if (pattern == 1) {
		ink = mod(g.x + g.y, 2.0) < 0.5 ? 1.0 : 0.0;
	} else if (pattern == 2) {
		ink = mod(g.y, 2.0) < 0.5 ? 1.0 : 0.0;
	} else if (pattern == 3) {
		ink = mod(g.x, 2.0) < 0.5 ? 1.0 : 0.0;
	} else {
		ink = coverage > bayer_at(f) ? 1.0 : 0.0;
	}

	vec3 col = mix(paper_col.rgb, ink_col.rgb, ink);
	COLOR = vec4(col, 1.0);
}
