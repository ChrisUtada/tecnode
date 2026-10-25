class_name DialogueDef
extends Resource
## 多人对话：参与者 + 可以绑在记忆上下文（when × where）上。

@export var id: String = ""
@export var participants: Array[CharDef] = []
@export var context_when: SceneDef = null
@export var context_where: SceneDef = null
@export var script_lines: Array[DialogueLineDef] = []   # 不能叫 script：Resource 自己有个 script
## 首次完整播放后掉落的「词」级证据。补全跳过 / 中途关闭 / 重播都不掉。
@export var drops_evidence: Array[EvidenceDef] = []
