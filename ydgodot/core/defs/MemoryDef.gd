class_name MemoryDef
extends Resource
## 一段回忆：when（哪一天）× where（在哪）× who（谁的视角）+ 剧本。

@export var id: String = ""
@export var when: SceneDef = null
@export var where: SceneDef = null
@export var who: CharDef = null
@export var title: String = ""
@export var script_lines: Array[DialogueLineDef] = []   # 不能叫 script：Resource 自己有个 script
## 首次完整播放后掉落的「词」级证据（与对话同口径）。
@export var drops_evidence: Array[EvidenceDef] = []
