class_name ConditionalCommandDef
extends CommandDef
## 条件命令：列出的线索**全部**已捕获才放行（缺一条就只给 failMessage）。

@export var conditions: Array[ConditionDef] = []
@export_multiline var success_message: String = ""
@export var on_success: PayloadDef = null
