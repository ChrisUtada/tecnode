# 迁移对照报告（JSON → Resource）

> 由 `tools/json_to_tres.gd` 生成，勿手改。

## 实体数量

| 类型 | 数量 |
|---|---|
| CharDef | 5 |
| ClueDef | 20 |
| DialogueDef | 3 |
| EndingDef | 5 |
| ItemDef | 36 |
| MemoryDef | 6 |
| SceneDef | 11 |

## 写盘

- 成功写出 `.tres`：**87** 个（含 `cases/a001/case.tres` 索引）
- 写盘失败：**0** 个

## 引用解析

- 成功解析：**180** 条
- 悬空 / 类型不符：**0** 条

## 数据自身的问题（非迁移错误）

- ⚠ item 反应表指向不存在的实体 `ITEMS_0602`（Web 版同样永不触发；已保留 trigger_id）
- ⚠ item 反应表指向不存在的实体 `ITEMS_sxbj`（Web 版同样永不触发；已保留 trigger_id）

## 文本指纹（逐类拼接后 sha256，迁移前后应一致）

- `CharDef`：`b117709c33300ddfdbce51cdb0c61cc506ea149d036b5dfc64362796963adef8`
- `ClueDef`：`c382b790ed38dc5a323b44202406f02a967366fa837ccc78d229bd8f7d7f79e4`
- `DialogueDef`：`016570c3be9d3f44901fa8fef787cf98dd19eb3fc3dbbf3bffa8282a9809e014`
- `EndingDef`：`22dc161061c7b0ba584bedb3b93a2360561092bdadcf4974dd0d1e58e86b4b6d`
- `ItemDef`：`aa34fae7182fcda67fd7afb6a4d9a0d265366088c584d488b2a2d175a34867ce`
- `MemoryDef`：`dbdb606869d9d1e176336e8c92c18ead12e67539fedb3ac6c610588065105a41`
- `SceneDef`：`97f84ec24d9ff94344f08369ad5034e6d86f40ce11791ef17007163e20d7a3be`
