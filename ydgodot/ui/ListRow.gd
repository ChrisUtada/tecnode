class_name ListRow
extends RefCounted
## 清单行的统一外壳。
##
## 档案 / 案件 / 名册 / 物品 / 证据这些窗口的行体各不相同（按钮、编号牌、头像、
## 富文本），但外壳语法一致：PanelContainer + 底部 1px 发丝线 + 左右 8px 内边距。
## 这里只收敛外壳，行内内容仍由各窗口自己拼。

## 发丝线：左右各缩 8px（负 expand margin 只影响绘制，不动内容排版）。
static func style(hover: bool = false, hairline: bool = true) -> StyleBoxFlat:
	var sb := TecTheme.flat(TecTheme.BG if hover else TecTheme.NONE, 0, TecTheme.NONE, 0)
	sb.border_color = TecTheme.edge(0.18)
	if hairline:
		sb.border_width_bottom = 1
		sb.expand_margin_left = -8.0
		sb.expand_margin_right = -8.0
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


static func panel(row_name: String, min_height: float, hairline := true, hover := false) -> PanelContainer:
	var row := PanelContainer.new()
	row.name = row_name
	row.custom_minimum_size = Vector2(0, min_height)
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_theme_stylebox_override("panel", style(hover, hairline))
	return row
