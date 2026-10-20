shader_type canvas_item;
// 桌面纸张：细颗粒 + 零星纸屑 + 大面积色斑（对齐 #stage / body 的 --paper-grain / --paper-fleck）
// P3 可换成烘焙 PNG（见计划 §5.1），此处用程序噪波保证 P0 不依赖浏览器。

uniform vec4 base_col : source_color = vec4(0.914, 0.898, 0.839, 1.0);
uniform vec2 area = vec2(1280.0, 800.0);
uniform float grain = 0.030;
uniform float fleck = 0.055;
uniform float blotch = 0.045;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 px = UV * area;

	float g1 = hash12(floor(px));
	float g2 = hash12(floor(px * 0.5) + vec2(31.7, 11.3));
	vec3 c = base_col.rgb + vec3((g1 - 0.5) * grain + (g2 - 0.5) * grain * 0.55);

	// 纸屑：24px 格子里约 1.5% 的格子带一个暗点
	vec2 cell = floor(px / 24.0);
	if (hash12(cell + vec2(91.0, 7.0)) > 0.985) {
		vec2 inside = fract(px / 24.0);
		if (length(inside - vec2(0.5)) < 0.22) {
			c -= vec3(fleck);
		}
	}

	// 两团大色斑（左上偏亮、右上偏暗）
	float b1 = smoothstep(0.9, 0.0, length((UV - vec2(0.16, 0.16)) * vec2(1.5, 1.1)));
	float b2 = smoothstep(0.85, 0.0, length((UV - vec2(0.84, 0.22)) * vec2(1.4, 1.2)));
	c += vec3(0.020) * b1;
	c -= vec3(blotch * 0.55) * b2;

	COLOR = vec4(c, 1.0);
}
