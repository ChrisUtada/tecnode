class_name CommandDef
extends Resource
## 物品命令基类。子类各自带 `@export` 字段，Inspector 里按子类出表单。
## 六型：text / choice / conditional / useItem / password / reveal（见 09-commands.js）。

@export var label: String = ""
@export var requires_lit: Array[ItemDef] = []      # 光照门：这些灯至少亮一盏
@export_multiline var fail_message: String = ""
