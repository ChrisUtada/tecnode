# T.E.C-OS · Godot 移植工程（ydgodot/）

> 迁移根目录。**后续迁移的所有内容都在这里**：工程、资源、测试、烘焙产物、转换脚本、文档。
> 计划与阶段目标见 [`GODOT_PORT_PLAN.md`](./GODOT_PORT_PLAN.md)。

## 当前状态：P2.2 TEC 生态已完成，下一步 P2.3 回忆系统

- **P0 垂直切片**：可跑（下面这条链路）
- **P1.1 JSON → Resource 迁移**：✅ 数据全部落在 `cases/a001/**/*.tres`，运行时**不再读 JSON**
  - 逐字段对照回归 `test_migration.gd`：11 场景 / 36 物品 / 5 人物 / 20 线索 / 6 回忆 / 3 对话 / 5 结局，**全字段一致**
  - 180 条字符串引用 → **类型化引用**（重命名/移动时引擎自动维护），悬空 0 条
  - 迁移暴露了 2 条**数据自身的错字引用**（`ITEMS_0602`、`ITEMS_sxbj`），行为与 Web 版一致（永不触发），记在报告里待你决定是否修
- **P1.2–P1.3**（图状态全量 / 六型命令）：✅ 已落地
  - 图状态：展开 / 折叠 / **收纳三态**（证物袋 BAG · 线索册 LEDGER · 推演桌布 MATRIX）/ 折叠后的隐藏重算（钉住的、跟场外有连线的都留在画布）/ 删节点连边一起走
  - 命令：text / choice / conditional / useItem / password / reveal 六型齐全，含光照门、零件门、`installs` 记账、工具消耗
  - 收纳窗已接进桌面：左侧图标栏点「证物袋」「线索册」能开窗、逐条取回
  - 回归：`test_p12.gd` 37 项（收纳三态 / 隐藏重算 / 判定顺序 / 消耗）
- **P1.4 五感与推演桌布**：✅ 已落地
  - 槽位：`GraphState.matrix`（vision / hearing / touch / smell / taste），归位 / 取回 / 袋册桌布三向搬运
  - 桌布窗：`MatrixWin`（执行者居中、五感锚点、外圆 + 五芒星虚线阵、线索芯片）
  - 推演：长按执行者 2.5 秒蓄力描星；配方必须**恰好**相等（多一条也不算）
  - 结局：命中后分幕演出 + 真名遮罩（`真名已识破 ——花魄——`），末帧按钮「确认捕获」
  - 捕获：TEC 解读场景时捕获 `hiddenClue`（尸体 → 植物学家陆珩松）
  - 回归：`test_p14.gd` 56 项（含真鼠标事件把线索卡拖上桌布）
- **P1.5 快照 / 撤销 / 存档**：✅ 已落地
  - `SaveSystem`：快照字段对齐 Web（nodes / edges / explored / captured / tried / talkProg / tecProg / lastScene / collapsed / time / cardSeen / debuted / matrix / endings / garden），节点含位置、点亮、钉住、零件、收纳去向
  - 撤销：页眉「撤销」按钮，最多 60 步；只记录真正改变状态的步骤（发光门、错密码、纯文本不占步）
  - 存档：`user://tec_case_<id>.save`，每次有效操作自动写盘；正常启动自动续档，`重来` 清档，`--shot` / 无头测试不写盘
  - 恢复：原地写回 `GraphState`，重建卡片与收纳 / 桌布视图，隐藏状态重算
  - 回归：`test_p15.gd` 85 项（快照往返 / 原地恢复 / 撤销上限 / JSON + 磁盘 / 桌面接线）
- **P1.6 开场适性测试 / 调查员证**：✅ 已落地
  - 流程：姓名 → 3 道五感题（每题 5 个选项，多数决、平局取先达到）→ 选头像 → 调查员证 → 确认领证
  - 证件：`TEC-XX-0000` 编号、签发日期、五感主导型与判词、像素头像、红色「T.E.C 核准」印章
  - 持久化：`user://tec_investigator.json`（与案件存档独立，`重来` 不清）；有证时正常启动跳过开场
  - 页眉证章：领证后显示「▣ 姓名 · 编号」，点击回看调查员证；`--shot` / 无头测试 / `--no-intro` 不弹开场
  - 回归：`test_p16.gd` 61 项（五感判定 / 编号 / 读写档 / 完整三步 UI / 页眉 / 回看 / 重来不清证）
- **P2.1 案件系统**：✅ 已落地
  - 案件索引 `CaseCatalog`：A001 可玩、A002 占位；UI 编号 `A001` 与数据 id `a001` 解耦，旧存档路径不变
  - 进度独立持久化：`user://tec_progress.json`（`unlocked` / `completed` / `last`），`重来` 只清案件档
  - 案件地图 `CaseMapWin`：当前 / 进入 / 锁定 / 待接入 / 可进入，A002 在 TRUE_E 后解锁并提示「数据待接入」
  - 标题栏两落点：`–` 收进右下角案件卡片，`×` 收进左侧「案件地图」图标并显示「已关闭」角标；两处都会先存盘，点落点原位展开
  - 续档 / 迁移：启动读取进度，旧存档里的 TRUE_E 会补记完成并解锁下一案
  - 回归：`test_p21.gd` 71 项（进度读写 / 清洗 / 地图状态 / 停车展开 / 角标 / dock / 自动存档 / 真名解锁）
- **P2.2 TEC 生态**：✅ 已落地
  - `TecWindow` 重写：对话历史（1px 分隔线）、点窗内任意位置按 `talkQueue` 闲聊、分析进度条（5–8 秒，`--fast` 0.05 秒）
  - `TecChip`：`–` 收起为右下角 196×56 助手卡片；分析中显示进度条，完成后打未读圆点；点卡片还原窗口
  - 档案解读：场景按 `sceneTalks` 逐条读出，并捕获台词 / `hiddenClue` 里的线索；物品 / 人物走 reaction 表；线索节点拒绝分析；重复分析只补未读，读完提示「档案已经全部解读完毕」
  - 拖放：TEC 图标、窗口头像、助手卡片都能接节点；与案件停车卡片并存
  - 回归：`test_p22.gd` 84 项（对话游标 / 收起还原 / 分析进度 / 档案 / 反应表 / 拖放命中 / 撤销 / 重置清理）

一条完整链路已在 Godot 4.7 里跑通，其余系统尚未搬迁：

```
开场：适性测试（姓名 → 3 问 → 头像）→ 调查员证 → 页眉证章
桌面壳（暗色页眉 / 图标栏 / 案件窗）
  └ 画布：单场景「植物学家的花园」展开（卡片节点 + 柔和浮雕）
      └ 拖放组合：手电筒 ——拖到——> 黑影（先要点亮，否则被发光门拦下）
          └ 尸体场景展开（绷带 / 粗糙的绳索 / 下腹部右侧 / 血痕…）
              └ TEC 窗：拖场景 / 物品进来分析（真实 5–8 秒进度条）
                  ├ 对话 / 档案解读；`–` 收成右下角助手卡片
                  └ 结局演出：分幕台词 + 真名遮罩
```

## 怎么跑

```bash
GODOT="/d/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe"

# 1) 首次进工程（生成 .godot 缓存、注册 class_name）
"$GODOT" --headless --path ydgodot --import

# 2) 玩
"$GODOT" --path ydgodot --resolution 1280x800

# 3) 无头回归（逻辑 / 界面交互 / 数据迁移 三层）
"$GODOT" --headless --path ydgodot --script res://tests/headless/test_p0.gd
"$GODOT" --headless --path ydgodot --script res://tests/headless/test_ui.gd
"$GODOT" --headless --path ydgodot --script res://tests/headless/test_migration.gd
"$GODOT" --headless --path ydgodot --script res://tests/headless/test_commands.gd
"$GODOT" --headless --path ydgodot --script res://tests/headless/test_p12.gd
"$GODOT" --headless --path ydgodot --script res://tests/headless/test_p14.gd
"$GODOT" --headless --path ydgodot --script res://tests/headless/test_p15.gd
"$GODOT" --headless --path ydgodot --script res://tests/headless/test_p16.gd
"$GODOT" --headless --path ydgodot --script res://tests/headless/test_p21.gd
"$GODOT" --headless --path ydgodot --script res://tests/headless/test_p22.gd

# 3.5) 重跑数据迁移（JSON → .tres；只在确认数据基准后跑）
"$GODOT" --headless --path ydgodot --script res://tools/json_to_tres.gd

# 4) 视觉自查：跑一遍切片，把 15 张截图存进 docs/
"$GODOT" --path ydgodot --resolution 1280x800 -- --shot

# 4.5) 开场 / 调查员证截图（6 张，写到 docs/p1_1*.png）
"$GODOT" --path ydgodot --resolution 1280x800 -- --shot --shot-intro

# 4.6) 案件 / TEC 截图（9 张，写到 docs/p2_*.png）
"$GODOT" --path ydgodot --resolution 1280x800 -- --shot-p2
```

- `--fast`：把「分析计时」「结局分幕延迟」压到 0（无头/测试旁路，见计划 §四.3）。
- `--shot`：跑固定剧本并截图（`docs/p0_*.png`、`docs/p1_*.png`）。截图需要真实渲染，**不能加 `--headless`**。
- `--shot-p2`：跑案件地图 / 收起 / 关闭 / 解锁 + TEC 对话 / 分析 / 助手卡片 / 档案共 9 张截图；使用临时进度档，退出时清理。
- `--no-intro`：跳过开场适性测试（无证时也不弹）。

## 目录

| 路径 | 内容 |
|---|---|
| `core/` | 纯逻辑（不挂场景树，可无头测）：`CaseLoader` / `GraphState` / `ComboSystem` / `SaveSystem` / `Investigator` / `CaseCatalog` |
| `scenes/` | `Desktop.tscn` + `Desktop.gd`（壳与接线）、`cards/NodeCard.gd`、`windows/*` |
| `ui/` | `TecTheme.gd`（配色/字体/StyleBox）、`shaders/surface.gdshader`（浮雕）、`shaders/paper.gdshader`（纸纹） |
| `cases/a001/` | **内容数据（唯一形态）**：`case.tres` 索引 + `scenes/` `items/` `chars/` `clues/` `memories/` `dialogues/` `endings/`，一实体一文件 |
| `core/defs/` | 25 个自定义 Resource 类（`SceneDef` / `ItemDef` / `CommandDef` 六子类 / `CharDef` …） |
| `data/` | `case-a001.json` —— **已冻结为只读档案**（迁移输入 + 对照基准，运行时不再读它） |
| `assets/raw/` | `src/assets/` 的拷贝（字体 / 头像 / OGG / 花园序列帧） |
| `tests/headless/` | `test_p0.gd`（逻辑 20）、`test_ui.gd`（真鼠标事件 32）、`test_migration.gd`（JSON ↔ `.tres` 逐字段 14）、`test_commands.gd`（六型命令 49）、`test_p12.gd`（图状态全量 37）、`test_p14.gd`（桌布 / 结局 56）、`test_p15.gd`（快照 / 撤销 / 存档 85）、`test_p16.gd`（开场 / 调查员证 61）、`test_p21.gd`（案件系统 71）、`test_p22.gd`（TEC 生态 84）—— **共 509 项** |
| `docs/` | P0 切片 6 张 + P1 新特性 15 张 + P2 案件 / TEC 9 张截图（P3 对拍基线从这些图起步） |
| `tools/` | P1 的 `json_to_tres.gd` 与对拍工具（待建） |

## P0 已做 / 明确没做

**已做**

- 数据装载 + 文本协议（`[item:X]` 标签换中文名、`<br>` 转换行、单复数前缀都认）
- 图状态：展开场景长出实体节点、幂等、`entity` / `move` 边
- 组合与命令：发光工具门（未点亮拦下、不记 tried）、`useItem` 命中、`onSuccess.scene` 揭示
- 交互：拖拽（5px 阈值、落点判定、拖动位移）、双击（点亮 / 展开）
- 窗口基类：拖动标题栏、关闭、内容流 / 定位容器分离
- TEC 对话 / 分析：5–8 秒进度条 + `--fast` 旁路 + 闲聊 + 档案解读 + 右下角助手卡片
- 结局演出：分幕台词按 `delay` 落下、点击继续、遮罩收幕
- 无头回归两层（逻辑 + 界面），全绿

**没做（P2.3 起）**

- 真实布局算法（现在是 4 列网格，无连线、无层级、无镜头聚焦/缩放）
- 详情窗、人物名册、多人对话 / 打字机
- 回忆/时间轴、人物登场门控、音乐播放器、花园彩蛋
- 除案件窗 / TEC 外的系统窗最小化、系统窗层级与 z 序的完整规则

## 与 Web 版的已知偏差（P0 有意从简，P3 再追平）

| 项 | Web 版 | P0 现在的做法 |
|---|---|---|
| 纸纹 / 浮雕 | 内联 SVG 噪波 + 多层 box-shadow | **shader 程序生成**（`paper.gdshader` / `surface.gdshader`）——P3 若换烘焙 PNG，只替换材质 |
| 节点布局 | 径向分层 + 折叠/展开动画 + 镜头平移 | 4 列网格，无动画 |
| 叙事卡 | 锚在触发节点上方、可拖 | 固定在右下角的浮窗（可拖） |
| 手电筒来源 | 书桌 → 左侧抽屉 → 手电筒 | 开局直接放在画布上（抽屉链路属 P1.2） |
| 数据形态 | `data/case-a001.json` 直读 | `cases/a001/**/*.tres`（P1.1），JSON 冻结为档案 |
| 结局触发 | 推演桌布命中配方 | 已接推演桌布；`--shot` 仍直接播放 `TRUE_E` 以保留 P0 对拍基线 |
| 调查员头像库 | 常驻两人 + 已结识人物，领证后可再更换 | 常驻两人 + 画布上已出现的人物；回看证件已接，换头像 / 人名册属 P2 |
| 字体回退 | VonwaonBitmap → SimSun → … | 全字形字体直导，**不配 fallback** |

## 约定

- `core/` 里的类**不继承 Node**，方便无头跑。
- 所有「延时后完成」的逻辑必须带「立即完成」旁路（`--fast` / `finish_now()`）。
- 测试钩子（`dbg_*`）只做**同名翻译**，命名对齐 Web 版 `window.__*`，方便把操作脚本逐行搬过来。
- 迁移期不改数据 schema（见计划 §九）。
