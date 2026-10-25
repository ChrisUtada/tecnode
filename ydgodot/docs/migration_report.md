# 迁移对照报告（JSON → Resource）

> 由 `tools/json_to_tres.gd` 生成，勿手改。

## 实体数量

| 类型 | 数量 |
|---|---|
| CharDef | 5 |
| DialogueDef | 3 |
| EndingDef | 5 |
| EvidenceDef | 28 |
| EvidenceFieldDef | 1 |
| EvidenceRecipeDef | 6 |
| ItemDef | 35 |
| MemoryDef | 6 |
| SceneDef | 11 |

## 写盘

- 成功写出 `.tres`：**101** 个（含 `cases/a001/case.tres` 索引）
- 写盘失败：**0** 个

## 引用解析

- 成功解析：**220** 条
- 悬空 / 类型不符：**0** 条

## 数据自身的问题（非迁移错误）

无。

## 文本指纹（逐类拼接后 sha256，迁移前后应一致）

- `CharDef`：`b117709c33300ddfdbce51cdb0c61cc506ea149d036b5dfc64362796963adef8`
- `DialogueDef`：`016570c3be9d3f44901fa8fef787cf98dd19eb3fc3dbbf3bffa8282a9809e014`
- `EndingDef`：`22dc161061c7b0ba584bedb3b93a2360561092bdadcf4974dd0d1e58e86b4b6d`
- `EvidenceDef`：`933b5d53ee67d304e5916ee4b772d48ad9aba804f6928d2962372e6af8f2e449`
- `EvidenceFieldDef`：`8a0c5a216f3552f9408f0bcbde78ac32a38f3265c9e0b238a581bebed797f987`
- `EvidenceRecipeDef`：`16d52b155e02f289cdf2c2d6c3ebbbbb36505841026541024e2dbc616478b6b2`
- `ItemDef`：`3f24e03223204567af9497ee38468e0c022f5c6684edc876f733ffa6af85e98e`
- `MemoryDef`：`dbdb606869d9d1e176336e8c92c18ead12e67539fedb3ac6c610588065105a41`
- `SceneDef`：`53cd6278d7327ea6ab2cd0bbcdb5859afc5bfbea67aa2b448c5e547d01d91e41`
