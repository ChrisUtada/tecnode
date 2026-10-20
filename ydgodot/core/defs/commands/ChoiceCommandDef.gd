class_name ChoiceCommandDef
extends CommandDef
## 选项命令：给几个分支，各自带结果。

@export_multiline var title: String = ""
@export_multiline var prompt: String = ""
@export var options: Array[ChoiceOptionDef] = []
