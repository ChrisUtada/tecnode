class_name CharDef
extends Resource
## 人物。`debut` = 最早能见到他/她的地方（门控用，见 03-utils.js 的双门）。

@export var id: String = ""
@export var name: String = ""
@export_multiline var desc: String = ""
@export var avatar: String = ""
@export var debut: SceneDef = null
@export var talk_queue: Array[String] = []
@export var scene_talks: Array[SceneTalkDef] = []
@export var clue_reactions: Array[ReactionDef] = []
@export var item_reactions: Array[ReactionDef] = []
@export var hidden_clue: HiddenClueDef = null
