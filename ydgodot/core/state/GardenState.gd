class_name GardenState
extends RefCounted
## 花园的领域状态：种子 + 花圃。
##
## 数据结构与存档字段 `garden` 保持一致（{seed: bool, plots: Array}），
## 增删花圃的规则仍归 `GardenSystem`。

var data: Dictionary = {"seed": false, "plots": []}


func reset() -> void:
	data = {"seed": false, "plots": []}


func has_seed() -> bool:
	return bool(data.get("seed", false))


func set_seed(on: bool) -> void:
	data["seed"] = on


func plots() -> Array:
	var p = data.get("plots", [])
	if not (p is Array):
		p = []
		data["plots"] = p
	return p


## 从存档恢复；缺失 / 类型不对的字段补默认值。
func from_dict(value) -> void:
	data = (value as Dictionary).duplicate(true) if value is Dictionary else {}
	plots()
	data["seed"] = bool(data.get("seed", false))


func to_dict() -> Dictionary:
	return data.duplicate(true)
