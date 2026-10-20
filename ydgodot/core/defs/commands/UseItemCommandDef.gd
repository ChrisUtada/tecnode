class_name UseItemCommandDef
extends CommandDef
## 用某个工具（拖过来）触发。
## `requires` = 前置零件必须已装在目标上；`installs` = 成功时把工具装上。

@export var required_item: ItemDef = null
@export var requires: Array[ItemDef] = []
@export var installs: bool = false
@export_multiline var success_message: String = ""
@export var on_success: PayloadDef = null
