class_name ReactionDef
extends Resource
## 人物对某个东西的反应（看到线索 / 摸到物品时的一句话）。

@export var trigger_id: String = ""        # 保留原始 id（DATA_* 这类伪线索也在里面）
@export var clue: ClueDef = null
@export var item: ItemDef = null
@export_multiline var text: String = ""
