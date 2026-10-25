class_name EvidenceDef
extends Resource
## 证据卡（物 / 词 / 证）。字牌即规则：物和词只是原料，只有「证」能填进档案卡字段。
## `tier` 用下拉枚举，避免数据里出现「物证 / 证词 / 结论」这类同义写法。

## 物现在由 ItemDef 本体承担；`wu` 仅保留给旧档迁移，不再产新卡。
@export_enum("wu", "ci", "zheng") var tier: String = "zheng"
@export_enum("vision", "hearing", "touch", "taste", "smell") var sense: String = "vision"
## 证怎么来的：tec 分析 / synth 合成 / deduce 档案演绎。
@export_enum("tec", "synth", "deduce") var origin: String = "tec"
@export var id: String = ""
@export var label: String = ""
@export_multiline var desc: String = ""
## 合成 / 掉落时的一句话来源说明，详情窗可读。
@export_multiline var source_text: String = ""
