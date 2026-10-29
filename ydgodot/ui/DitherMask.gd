extends ColorRect
## 全屏网点遮罩：ColorRect + dither_fade 材质。
##
## 调用方先 `configure(...)`，再按普通 ColorRect 设置 anchors / mouse_filter。
## 不设 class_name，走 preload；避免新增全局脚本类缓存依赖。

const SHADER := preload("res://ui/shaders/dither_fade.gdshader")


func configure(p_inner: float, p_outer: float,
		p_radius_inner: float = 0.15, p_radius_outer: float = 1.05,
		p_cell: float = 2.0) -> void:
	color = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("coverage_inner", p_inner)
	mat.set_shader_parameter("coverage_outer", p_outer)
	mat.set_shader_parameter("radius_inner", p_radius_inner)
	mat.set_shader_parameter("radius_outer", p_radius_outer)
	mat.set_shader_parameter("cell", p_cell)
	material = mat
