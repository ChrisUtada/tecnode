class_name EvidenceRecipeDef
extends Resource
## 证据配方：无序对 `a × b → evidence`。产物只能是「证」级证据。
## 不限制输入 tier —— 物×物、物×词、证×物都由数据逐条定义；
## 「签名配方 = 物 × 词 → 证」是教学口径，不是硬编码限制。

@export var id: String = ""
@export var a: EvidenceDef = null
@export var b: EvidenceDef = null
@export var evidence: EvidenceDef = null
@export_multiline var text: String = ""
