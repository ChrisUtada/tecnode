class_name EvidenceRecipeDef
extends Resource
## 证据配方：无序对 `a × b → evidence`。产物只能是「证」级证据。
## 不限制输入 tier —— 物×物、物×词、证×物都由数据逐条定义；
## 「签名配方 = 物 × 词 → 证」是教学口径，不是硬编码限制。

@export var id: String = ""
## 原料可以是 ItemDef（物）或 EvidenceDef（词 / 证）；无序对。
@export var a: Resource = null
@export var b: Resource = null
@export var evidence: EvidenceDef = null
## 产出的证落到哪个五感槽位；纳入可达性检查。
@export_enum("vision", "hearing", "touch", "taste", "smell") var sense: String = "vision"
@export_multiline var text: String = ""
