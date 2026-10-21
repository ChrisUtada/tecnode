class_name ReactionDef
extends Resource
## 人物对某个东西的反应（看到线索 / 摸到物品时的一句话）。

@export var trigger_id: String = ""        # 保留原始 id（DATA_* 这类伪线索也在里面）
@export var clue: ClueDef = null
@export var item: ItemDef = null
@export_multiline var text: String = ""
## 命中后的产出（Web `05-combine.js:112-123`）：{"scene": sid, "items": [id…]}
## A-001 的 27 条反应全是纯文本；结构照 Web 的表格条目保留，等带 results 的剧本直接可用。
@export var results: Dictionary = {}
