# T.E.C-OS → Godot 4 移植计划

> 状态：计划 v2（P0–P2 完成，P3 视觉追平已对拍 2.30%；**交互层 P0 八项 + 批 1 + 批 2 + 批 3 + 批 4 已落地**） ｜ 目标引擎：Godot 4.x（GDScript，2D） ｜ 目标平台：桌面（Windows 优先）
> 前置阅读：`README.md`、`docs/INTERACTION_GAP_REPORT.md`（交互层差距与 P0 执行状态见其 §0.1–§0.5） ｜ 迁移基准：`data/case-a001.json`
> **最近更新（2026-10-21 夜）**：交互层 P0 八项（世界层/连线/单击双击分离/位置写回/力导向/右键钉住/落点表/反应表/详情窗）+ **批 1**（人物名册 / 因果追踪 / 图标栏 8 项 + 自由拖动 + 四角标）+ **批 2**（拖动幽灵线 / 桌布 chip 带坐标取回，**反向落点 8/8**）+ **批 3**（warn 药丸 / pop 入场 / hover 光标 / dim .32 / 场景命令 / 拖动镜像）+ **批 4**（反应表产出三通道 / 折叠重排 0.34s 过渡 / 系统窗 z 序十二档）全部落地，README「没做」清空，全套无头断言 **1119 项 0 失败**；连线层上线前后 P3 起始页**逐像素 `max diff = 0`**，2.30% 基线不变。剩余缺口见差距报告 §7。
> **v2 变更**：内容创作确定迁入 Godot 编辑器，Web 编辑器（editor.html）弃用；数据层从「JSON 不动」改为「JSON → Resource（.tres）一次性迁移」，详见 §一.1 与 §二.5。
> **迁移根目录（2026-10-20 定）**：`nodes-mvp/ydgodot/` —— **后续迁移的一切内容都放在这里**：Godot 工程（`project.godot` 直接位于 `ydgodot/` 根）、资源、测试、烘焙产物、转换脚本、文档。仓库其余部分（`src/`、`data/`、`index.html` 等 Web 版）在迁移验证通过前保持只读参考、不迁移、不改动。

---

## 〇、还原度定义（先把"100%"拆开）

| 维度 | 目标 | 说明 |
|---|---|---|
| 功能逻辑 | **100%** | 全部交互、状态机、判定规则逐条对齐，用回归测试钉死 |
| 视觉 — 纹理/布局/配色/动效曲线 | **100%** | CSS 计算类效果走烘焙，缓动走数学复刻 |
| 视觉 — 文字光栅化/断行 | **95% → 校对追平** | 唯一不能烘焙的部分；见 §5.4 |
| 工程管线 | **等价重建** | build.js / verify.js 没有对应物，需重建同等保障（§6） |

**原则：数据层迁移（JSON → Resource）、逻辑层翻译、视觉层重建、工程层等价。**

---

## 一、现状盘点（移植清单的输入）

### 1.1 数据资产

- `data/case-a001.json`：`config / scenes / items / chars / clues / memories / dialogues / endings` 八区。**它是迁移的输入，不是运行时的数据源**——P1 期间经一次性转换脚本转成 .tres 资源树（§二.5），之后 JSON 只作为导出/兼容格式存在。
- 文本协议：`[item:X] / [loc:X] / [char:X] / [clue:X]` 内嵌标签——Godot 侧照抄一个正则解析即可。**注意：文本内嵌标签是 Resource 引用管不到的角落**，悬空校验仍需保留为 `@tool` 脚本（§二.5 末）。
- `src/assets/`：`font.ttf`（像素字体）、`tec-avatar.png`、`executor-avatar.png`、`cert-avatar.png`、`emote-heartbroken.png`、`flower/`（序列帧）、`Air_Bach.ogg`（**OGG 是 Godot 原生格式**）。

### 1.2 功能模块（src/js 17 片 → Godot 脚本映射）

| 现有模块 | 职责 | Godot 对应 |
|---|---|---|
| 01-data / 02-state | 数据装载、图状态、快照/撤销 | `CaseLoader.gd`（读 `CaseDef.tres` 索引）+ `GraphState.gd`（RefCounted，纯逻辑） |
| 03-utils / 04-graph | 标签解析、场景展开、引用表 | `GraphLogic.gd`（静态函数库） |
| 05-combine / 09-commands | 拖放组合、物品命令 | `ComboSystem.gd` + `CommandSystem.gd` |
| 07-render / 08-interact | 节点渲染、画布交互 | `Canvas.tscn`（Node2D + Control 混合） |
| 10-windows / 11-dialog | 系统窗、对话/气泡 | `SysWindow.tscn` 基类 + `DialogWindow.tscn` |
| 12-panels / 13-matrix | 人物名册、推演桌布、结局演出 | `Panels/*.tscn`、`MatrixBoard.tscn`、`EndingPlayer.gd` |
| 14-detail / 15-desktop | 详情窗、桌面图标/ dock | `DetailPanel.tscn`、`Desktop.tscn` |
| 16-cases | 案件切换、音乐播放器、花园彩蛋 | `CaseManager.gd`、`MusicPlayer.gd`、`Garden.gd` |
| 17-boot | 启动/测试钩子 | `Boot.gd` + `TestHooks.gd`（debug build 限定） |

### 1.3 视觉资产拆解（决定烘焙清单）

- **纸张纹理**：`--paper-grain` / `--paper-fleck` 是 SVG `feTurbulence` 内联噪波 → 浏览器里渲染一次导出 PNG，Godot 里当静态纹理，**逐像素一致**。
- **浮雕体系**：`--raise / --raise-sm` / `--press` / `--win-shadow`（多层 box-shadow）→ 烘焙九切片贴图或单 shader（偏移模糊 × 2 + 内描边）。
- **发光**：节点点亮光晕（radial-gradient）→ 烘焙径向渐变贴图或 shader。
- **动画**：收缩/展开位移缩放（`cubic-bezier(.4,0,.2,1)`）、打字机 45ms/字、蓄力 2.5s 转环、虚线流动、结局分幕延时——全部是定时器 + 贝塞尔，数学复刻。
- **字体排版**：`font.ttf` + CJK 回退链（SimSun）→ Godot Font 资源 + fallback 链；断行规则差异是唯一的"细活区"。

---

## 二、Godot 工程结构（建议）

**根 = `ydgodot/`**（Godot 工程根；`project.godot` 在本目录，打开工程即打开 `ydgodot/`）。迁移相关的脚本、文档、对拍产物、转换报告也都在这一棵树里，仓库根不再新增迁移文件。

```
ydgodot/                           # ← 迁移根目录（Godot project.godot 在此）
├── project.godot
├── README.md                      # 迁移进度与运行方式（与仓库根 README 分开）
├── GODOT_PORT_PLAN.md             # 本计划
├── cases/                          # 内容数据：Resource 体系（§二.5）
│   └── a001/
│       ├── case.tres               # CaseDef：案件索引 + ConfigDef 内嵌
│       ├── scenes/SCENES_garden.tres …
│       ├── items/ITEMS_changji.tres …
│       ├── chars/CHARS_zs.tres …
│       ├── clues/CLUES_nm.tres …
│       ├── memories/MEM_0602_lhs.tres …
│       ├── dialogues/DLG_garden_review.tres …
│       └── endings/TRUE_E.tres …
├── assets/                         # 从 src/assets 拷贝而来 + 烘焙产物
│   ├── baked/                      # §5.1 的烘焙贴图（paper-grain.png、bevel-*.png…）
│   └── raw/                        # 原始 png/ogg/ttf
├── core/                           # 纯逻辑（不依赖场景树，可单测）
│   ├── defs/                       # SceneDef.gd ItemDef.gd …（class_name 自定义 Resource）
│   ├── CaseLoader.gd  GraphState.gd  GraphLogic.gd
│   ├── ComboSystem.gd  CommandSystem.gd
│   └── SaveSystem.gd               # user:// 存档 + 撤销栈
├── scenes/
│   ├── Desktop.tscn                # 桌面外壳（图标栏 / 系统窗层级）
│   ├── Canvas.tscn                 # 节点画布（Node2D 世界 + 缩放平移）
│   ├── SysWindow.tscn              # 系统窗基类（标题栏 / 拖动 / 最小化）
│   ├── windows/                    # TEC / 证物袋 / 线索册 / 推演桌布 / 对话窗…
│   └── cards/                      # 叙事卡 / 记忆放映卡 / 气泡
├── editor/                         # @tool 创作插件（§三 P4）：校验、文本标签扫描、案件打包
├── ui/
│   ├── theme/                      # Theme 资源：字体、StyleBox、配色常量
│   └── widgets/
├── tools/                          # 一次性转换脚本、字体重生成、导出脚本、对拍工具
│   └── json_to_tres.gd             # P1 数据迁移脚本（§三 P1.1）+ 对照报告
├── docs/                           # 迁移过程文档：转换报告、对拍基线、待办
└── tests/                          # §6 的回归体系
    ├── headless/                   # 无头逻辑测试（GUT 或自研 runner）
    └── pixeldiff/                  # 视觉对拍
```

**输入侧只读**：迁移输入仍是仓库根的 `data/case-a001.json` 与 `src/assets/`（拷贝到 `ydgodot/assets/raw/`，不原地改）。字体若要重新子集化，用仓库根的 `tools/subset-font.py`，产物落 `ydgodot/assets/raw/font.ttf`。

**关键架构决策**：`core/` 全部是纯 GDScript 类（不挂场景树），保证逻辑可以无头跑测试——这是对齐 `verify.js` 价值的唯一方式。

### 2.5 Resource 类型体系（v2 新增，内容数据的唯一形态）

创作迁入 Godot 后，**"作者写的"内容一律用自定义 Resource 管理；"玩家玩出来的"运行时态一律不用**（运行时图节点、存档快照、会话播放态保持 RefCounted/普通对象）。

| Resource 类 | 承载 | 关键设计 |
|---|---|---|
| `CaseDef` | 案件索引 + ConfigDef | 一个案件一个 `case.tres`，按目录索引全部实体 |
| `SceneDef` | title/content/desc/hiddenClue/canBePicked/image | `hiddenClue.ids` → `Array[ClueDef]` 类型化引用 |
| `ItemDef` | label/desc/canBePicked/commands/presentReactions…（按当前合并后的 schema） | image → Texture2D 引用 |
| `CommandDef` 基类 + 六子类 | text / choice / conditional / useItem / password / reveal | **多态 `@export`**：Inspector 按子类自动出表单，异形结构不再裸 Dictionary |
| `CharDef` | name/desc/avatar/talkQueue/sceneTalks/reactions/debut | `debut` → SceneDef 引用 |
| `ClueDef` | label/type/desc | type 用枚举，Inspector 下拉，杜绝打错字 |
| `MemoryDef` | when/where/who + script | 三字段类型化引用 |
| `DialogueDef` | `participants: Array[CharDef]` + `context: MemoryDef` + script | script.who 必须 ∈ participants、**脚本绑在记忆上下文（when × where）上** —— 两条都可在编辑器期拦截（`_validate_property` / `@tool` 校验） |
| `DialogueLineDef` | narr/say 枚举 + who + text | 记忆与对话共用 |
| `EndingDef` | `recipe: Array[ClueDef]`/isTrueCapture/truename/lines/message | 五感配方校验写进 `@tool`，**保存即校验** |
| `MotionProfile` | 动效时序常量（§5.3） | 视觉参数集中、可调 |

**粒度**：一个实体一个 .tres——diff 友好、并行创作不冲突、Godot 文件依赖追踪按文件生效，粗粒度会失去引用自动更新的精度。

**收益**：字符串 id 引用（recipe、requiredItem、sceneTalks 键……）全部变成类型化引用，**重命名/移动时引擎自动维护引用**——Web 侧需要校验器兜底的那类"悬空引用" bug 在这一层直接消失。

**唯一的例外**：正文散文里内嵌的 `[item:X]` 标签。Resource 引用管不到字符串内部，`editor/` 插件里保留一个"文本标签扫描"校验（正则提取 + 存在性检查），范围从"所有引用"缩到"只有文本标签"。

---

## 三、分阶段计划

### P0 · 垂直切片（1 周）——先证明路线成立

只做一条链，其余全不碰：

1. 建工程（**根 = `ydgodot/`**，见 §二），导入 `font.ttf`、头像、`Air_Bach.ogg`；烘焙纸纹与浮雕贴图（§5.1）。
2. 实现：桌面壳（空）+ 画布（单场景「植物学家的花园」展开）+ 拖放组合（手电筒→黑影→尸体）+ TEC 窗（分析计时）+ 一个结局演出。
3. **P0 允许直读 `data/case-a001.json` 快速起步**（不做数据改造），切片过了再做正式迁移。

**验收**：这条链在 Godot 里跑通，视觉上与浏览器并排对比"一眼看不出区别"。**这一步不过，后面不谈。**

> **P0 状态（2026-10-20）：链路已跑通** ✅
> - 工程：`ydgodot/`（Godot 4.7，GL Compatibility），素材已导入（字体 / 头像 / OGG / 花园序列帧）。
> - 链路：花园展开 → 手电筒（未点亮先被发光门拦下）→ 拖到黑影 → 尸体场景 → TEC 分析（5–8s 进度条）→ 结局分幕演出。
> - 回归：`tests/headless/test_p0.gd`（逻辑 20 项）+ `test_ui.gd`（真鼠标事件拖拽/双击 10 项）全绿；`--shot` 出 6 张阶段截图（`docs/`）。
> - **偏差（P3 追平）**：纸纹/浮雕用 shader 程序生成（未烘焙 PNG）；节点用 4 列网格（无径向布局/连线/镜头）；叙事卡从「锚在节点上方」改为右下浮窗；手电筒开局直接给（抽屉链路属 P1）；结局由「分析过尸体」触发（配方推演属 P1）。
> - **尚未做的验收项**：与浏览器并排的像素对拍（§5.5 的流程 P3 才建，这里只到「结构+观感一致」）。

### P1 · 核心循环（1–2 周）——游戏能从头玩到尾 + 数据正式迁移

1. **JSON → Resource 迁移**（v2 新增，P1 第一件事）：
   - 定义 §二.5 的全部 Resource 类；
   - 写一次性转换脚本（Godot 命令行脚本或 Node 脚本均可）：逐字段映射 `data/case-a001.json` → `cases/a001/**/*.tres`；
   - 转换后跑校验对照（实体数、引用数、文本逐字一致），产出对拍报告；
   - 迁移完成并验证后，`data/case-a001.json` 冻结为只读档案，Web 编辑器同步弃用（§三 P4）。
2. 图状态全量：节点/边/展开/收纳（证物袋、线索册、场景折叠）/隐藏与聚焦。
3. 命令系统六型（text / choice / conditional / useItem / password / reveal）+ 发光门 + 零件门。
4. 捕获/线索节点、五感槽位、推演桌布（执行者居中 + 连线 + 长按蓄力）、结局判定与演出（分幕 + 真名遮罩）。
5. 快照/撤销/存档（`user://tec_case_<id>.save`），与现有 JSON 快照结构同构。
6. 开场适性测试（问答 → 调查员证）。

**验收**：用**同一套操作脚本**（从 verify.js 的链路翻译）在 Godot 里无头跑通真结局；数据全部来自 .tres，不再读 JSON。

> **P1 进度（2026-10-20）**
> - ✅ **P1.1 JSON → Resource 迁移完成**：25 个 Resource 类（`core/defs/`，含 `CommandDef` 六子类、`PayloadDef` / `HiddenClueDef` / `ExcerptDef` / `ReactionDef` / `SceneTalkDef`）；`tools/json_to_tres.gd` 两趟转换（先定 `resource_path` 再填字段，环状引用落成 `ExtResource` 而不是内联副本）；写出 87 个 `.tres`（含 `case.tres` 索引）。
> - ✅ **对照报告**：`docs/migration_report.md`（实体数 / 写盘 / 引用解析 / 文本指纹）；`tests/headless/test_migration.gd` **14 项逐字段比对全绿**（不是抽查）。
> - ✅ **悬空引用归零**（180 条解析成功）；顺带把 2 条**数据自身错字**（`ITEMS_0602` / `ITEMS_sxbj`）暴露成报告里的 ⚠，行为与 Web 版一致（永不触发）。
> - ✅ **运行时已切资源**：`CaseLoader` 只认 `.tres`（JSON 冻结为档案），`GraphState` / `ComboSystem` 改用 `SceneDef` / `ItemDef` / `CommandDef`；P0 的逻辑 20 项 + 界面 10 项回归仍全绿。
> - ✅ **P1.2 图状态全量**（`core/GraphState.gd`）：节点 / 边 / 展开（`reveal_scene` + `reveal_container`）/ 折叠 / **收纳三态**（`BAG` 证物袋 · `LEDGER` 线索册 · `MATRIX` 推演桌布，含 `bag_store` / `ledger_store` / `matrix_assign` / `take_back` / `restash` 跨窗搬运）/ **折叠后的隐藏重算**（`recompute_hidden`：钉住的、跟场外有连线的都不藏）/ `delete_node`（连边一起走）/ 可复用工具查询。收纳窗已接进桌面（`scenes/windows/StorageWin.gd`，证物袋 + 线索册两扇）。
> - ✅ **P1.3 命令系统六型**（`core/CommandSystem.gd`）：text / choice / conditional / useItem / password / reveal 全部落地，含**光照门**（列出的灯至少亮一盏）、**零件门**（`requires` 必须已装在目标上）、`installs` 记账、工具消耗（非可复用工具用完消失，可复用工具留着，开关 `consume_tools`）。判定顺序对齐 Web：**先查零件，再查工具发不发光**。
> - ✅ **P1.4 五感与推演桌布**：`GraphState.matrix` 五感槽位（归位 / 取回 / 袋册桌布三向搬运）；`scenes/windows/MatrixWin.gd` 推演桌布（执行者居中、五感锚点、外圆 + 五芒星虚线阵、线索芯片拖出取回）；长按执行者 2.5 秒蓄力描星；配方**恰好相等**才命中（多一条也失败）；命中后分幕演出 + 真名遮罩（`真名已识破 ——花魄——`），末帧「确认捕获」；TEC 解读捕获 `hiddenClue`（尸体 → 植物学家陆珩松）。
> - ✅ **P1.5 快照 / 撤销 / 存档**（`core/SaveSystem.gd`）：快照对齐 Web（nodes / edges / explored / captured / tried / talkProg / tecProg / lastScene / collapsed / time / cardSeen / debuted / matrix / endings / garden；节点含位置 / 点亮 / 钉住 / 零件 / 收纳去向），恢复为原地写回；撤销栈上限 60；磁盘存档 `user://tec_case_<id>.save`，有效操作自动写盘、正常启动续档、`重来` 清档；`--shot` 与无头测试不写盘。桌面新增「撤销」按钮，恢复后重建卡片 / 收纳窗 / 桌布。
> - ✅ **P1.6 开场适性测试 / 调查员证**（`core/Investigator.gd` + `scenes/windows/IntroWin.gd`）：姓名 → 3 道五感题（多数决、平局取先达到）→ 头像 → 调查员证 → 确认领证；证件含 `TEC-XX-0000` 编号 / 签发日期 / 五感主导型与判词 / 像素头像 / 红色核准印章；`user://tec_investigator.json` 独立持久化，正常启动有证跳过开场，页眉证章可回看证件；`--shot` / 无头 / `--no-intro` 不弹。
> - ✅ **回归 354 项全绿**：`test_p0` 20 · `test_ui` 32 · `test_migration` 14 · `test_commands` 49 · `test_p12` 37 · `test_p14` 56 · `test_p15` 85 · **`test_p16` 61**（本轮新增：五感判定 / 编号 / 证件读写 / 三步 UI / 页眉证章 / 回看 / 重来不清证）。
> - ✅ **P2.1 案件系统**：`core/CaseCatalog.gd` 案件索引（A001 可玩 / A002 占位，UI id 与数据 id 解耦）+ 独立进度 `user://tec_progress.json`（`unlocked` / `completed` / `last`，损坏容错、未知 id 清洗）；`scenes/windows/CaseMapWin.gd` 案件地图（当前 / 进入 / 锁定 / 待接入 / 可进入）；案件窗 `×` 收进地图图标并打「已关闭」角标、`–` 收进右下角 170×56 案件卡片，两处先存盘、点落点原位展开；TRUE_E 标记完成并解锁 A002（A002 无数据时只提示待接入），旧存档里的 TRUE_E 在续档时补记。
> - ✅ **P2.2 TEC 生态**：`scenes/windows/TecWindow.gd` 重写（对话历史 / 点窗闲聊 / 5–8 秒分析进度条 / 档案逐条解读）；新增 `scenes/windows/TecChip.gd`（右下角 196×56 助手卡片，分析中显示进度、完成后打未读圆点、点卡片还原）；场景按 `sceneTalks` 读出并捕获台词 / `hiddenClue` 线索，物品 / 人物走 reaction 表，线索节点拒绝、忙碌拒绝；拖放支持 TEC 图标 / 窗口头像 / 助手卡片；`graph.tec_prog` 同时保存档案游标与闲聊游标，随快照持久化；`--shot-p2` 扩到九张（四张案件 + 五张 TEC）。
> - ✅ **回归 509 项全绿**：`test_p0` 20 · `test_ui` 32 · `test_migration` 14 · `test_commands` 49 · `test_p12` 37 · `test_p14` 56 · `test_p15` 85 · `test_p16` 61 · `test_p21` 71 · **`test_p22` 84**（本轮新增：对话游标 / 收起还原 / 分析进度 / 档案 / 反应表 / 拖放命中 / 撤销 / 重置清理）。
> - ✅ **P2.3 回忆系统**：`config.memoryScenes` → 三档时间轴；`GraphState` 新增 `time` / `card_seen` / `debuted` / `visible_node` / `spawn_mem_cast` / `timeline_known`，`loc:SCENES_0602` 自动收敛到 `time:` 且时间节点不上画布；新增 `scenes/windows/ArchiveWin.gd`（已知时刻倒序 / 简介 / 当前 / 已回顾 / 新角标）与 `MemCard.gd`（放映卡 + 回忆小剧场：暗纸、打字机、点击推进、整卡拖动、旁白 + 带头像台词、锚定避让）；时刻 × 人物 × 地点命中 `memories` 时由拖放触发小剧场，不捕获线索；`--shot-p2` 扩到十二张（新增档案窗 / 放映卡 / 小剧场）。
> - ✅ **回归 674 项全绿**：`test_p0` 20 · `test_ui` 32 · `test_migration` 15 · `test_commands` 49 · `test_p12` 37 · `test_p14` 56 · `test_p15` 85 · `test_p16` 61 · `test_p21` 71 · `test_p22` 84 · **`test_p23` 164**（本轮新增：数据契约 / 时间图层 / debut 门控 / 快照 / 档案窗 / 放映卡 / 回忆小剧场）。
> - ✅ **P2.4 多人对话系统**：`core/DialogueSystem.gd`（语境优先 fit → free，miss 不播；精确集合优先，三人剧本可由两人 loose 命中；blocked fallback、独白查询）+ `core/DialogueSession.gd`（joined / step / waitingFor / join / done）；`scenes/windows/ChatWindow.gd`（右上 390 宽、内容自适应高度、45ms/字打字机、点击补全/推进、旁白 + 带头像台词、贴底不裁末行、等待提示与拖人加入）；桌面接线人物 × 人物、拖人物到对话窗、双击人物开独白（无详情窗，暂用此入口，P3 追平）、切时刻 / 重置 / 切案 / 撤销恢复关窗；`--shot-p2` 扩到十五张（新增多人对话 / 等待加入 / 独白）。
> - ✅ **回归 776 项全绿**：`test_p0` 20 · `test_ui` 32 · `test_migration` 15 · `test_commands` 49 · `test_p12` 37 · `test_p14` 56 · `test_p15` 85 · `test_p16` 61 · `test_p21` 71 · `test_p22` 84 · `test_p23` 164 · **`test_p24` 102**（本轮新增：语境匹配 / loose / fallback / 状态机 / 打字机 / 拖人 / 独白 / 生命周期）。
> - ✅ **P2.5 音乐播放器 / 花园彩蛋**：`core/GardenSystem.gd`（五阶段真实时间 0 / 45 / 90 / 135 / 180 秒；位置百分数 8..92 / 30..85；老档归一化并回填 `narr`；`grant_seed` 只发一枚且不覆盖已有旁白；旁白按句 / 逗号切段到约 150 字）+ `scenes/windows/MusicWin.gd`（唱针 `ITEMS_cz` 装到唱机 `ITEMS_changji` 后出现播放器；播放 / 暂停 / 停止 / 进度跳转；关窗音乐继续）+ `MusicDock.gd`（右下角 238×60 卡片）+ `GardenWin.gd`（548 宽自由花圃、种子落点夹紧、种后拖动、开花后逐段旁白、窗口随内容伸缩）；`MatrixWin` 执行者头顶种子气泡拖到花园窗 / 图标下种；`Desktop` 动态图标 / 角标、TRUE_E 确认捕获发种子、快照 / 撤销 / 读档 / 重开清理；`SaveSystem` 为缺 `garden` 的 TRUE_E 旧档补种子；`SysWindow.enable_controls(..., show_min)` 支持花园窗不显示最小化。`--shot-p2` 扩到二十张（新增音乐 / dock / 种子 / 花园 / 旁白）。
> - ✅ **回归 922 项全绿**：`test_p0` 20 · `test_ui` 32 · `test_migration` 15 · `test_commands` 49 · `test_p12` 37 · `test_p14` 56 · `test_p15` 85 · `test_p16` 61 · `test_p21` 71 · `test_p22` 84 · `test_p23` 164 · `test_p24` 102 · **`test_p25` 146**（本轮新增：花园核心 / 老档迁移 / 播放器状态 / 进度跳转 / 图标收放 / dock / 种子投放 / 拖动 / 旁白 / 存档）。

### P2 · 系统全量（1–2 周）——补齐桌面生态

1. ✅ 案件系统：案件地图、收起/关闭两落点、切换与续档、角标体系（P2.1）。
2. ✅ TEC 生态：对话窗、分析进度条、右下角助手卡片、档案解读（P2.2）。
3. ✅ 回忆系统：时间轴切档、放映卡、人物登场门控（debut）、回忆小剧场（P2.3）。
4. ✅ 多人对话系统：对话窗、打字机、中途加人等待/续播、独白（P2.4）。
5. ✅ 音乐播放器（唱针装上后解锁）、花园彩蛋（种子/花坛真实时间生长）（P2.5）。

**验收**：与浏览器版逐项对表（附清单核对表），全部 ✅。

### P3 · 视觉追平（1 周）——像素对拍

1. 建对拍流程（§5.5）：同数据同操作 → 浏览器截图 vs Godot 截图 → diff 热力图。
2. 按差异从大到小逐项消灭：布局坐标 → 纹理 → 浮雕 → 动效时机 → 字体度量 → 断行。
3. 断行规则对齐（§5.4），CJK 标点避让自实现。

**验收**：关键场景对拍 diff 率低于约定阈值（建议 < 0.5% 像素差异，且文字区外为零）。

> **P3 进度（2026-10-21，本地进行中）**
> - ✅ **对拍流水线建成**（§5.5）：`tools/pixeldiff/capture_web.cjs`（CDP 无头 Edge，走完开场适性测试后抓 `start/garden/paper` 三态 + 关键 rects）→ `Desktop.gd --shot-p3`（`_shot_p3_flow()`）→ `tools/pixeldiff/compare.py`（阈值 8/16，分区统计 + `_diff/_mask/_pair` 三联图 + `start.json`）。
> - ✅ **量尺先校准**：Web 侧必须关 LCD 次像素（`--disable-lcd-text --disable-font-subpixel-positioning --force-color-profile=srgb`），否则 Chromium 的彩边会被当成实现差异；`--font-render-hinting` 对这个构建无效。**文字 AA 无法逐像素一致**（Godot 是 `antialiasing=NONE` 的硬边，Web 是 Skia 灰度覆盖率），实测打开灰度 AA 反而更差 ⇒ 按本文 §七「接受 AA 微小差异」处理，验收看「文字区外为零」。
> - ✅ **全屏 diff：7.00% → 2.30%**（1280×800 / 阈值 8）。分区：页眉 7146 px · 图标栏 9419 · 命令条 2069 · 画布 4960 · **窗框外沿 0**（烘焙九切片）。
> - ✅ 已消灭：窗框（烘焙 `win_frame.png` 九切片，`patch_margin=46`）、页眉几何（品牌/副题/证章/面包屑/七件套逐坐标对齐，七件套 x = 670/763/856/985/1066/1123/1180）、**页眉控件高 31 → 25/27**（Button 的最小尺寸会反顶 `set_size`，见 `_sync_header_sizes`）、枢纽场景双线框（`GraphState.is_hub` + `DashBorder.double_line`）、图标块（渐变 150deg、描边 alpha、字形垂直位移 10px、标签 4px、**阴影衰减跨边缘对称** —— CSS 高斯在边界恰好 50%，原式 `-1→soft` 等于沿块边描深影）。
> - ⏳ 剩余：各处文字 AA（页眉 0.70 + 命令条 0.20 + 画布 0.48 + 图标标签 ~0.25 = 约 1.6 pt，不可消）；图标栏「人物」「日志」空槽与四角标已随批 1 补齐（原 ≈ 0.54 pt），**`--shot-p3` 总分复测待做**。
> - 详细账目见 `.workbuddy/memory/2026-10-21.md`。

### P4 · 工程体系重建 + 创作管线迁移（与 P1–P3 并行）

1. **无头逻辑测试**：`core/` 纯逻辑用 GUT 或自研 runner 重建 verify.js 的核心断言（不需要 2300 行全翻，先翻"链路级"断言：配方链、案件切换、存档往返、对话状态机）。
2. **创作管线（v2 口径）**：
   - Web 编辑器（editor.html）**弃用**：迁移验证通过之日起冻结，不再接受功能改动；仓库里保留只读存档即可。
   - Godot 侧创作 = 引擎原生编辑器 + `editor/` 下的 `@tool` 插件：实体校验（必填/前缀/五感配方）、文本标签扫描（§2.5 末）、案件打包导出。
   - Web 编辑器的校验规则（EDITOR_PLAN.md 第四节）逐条翻译成 `@tool` 校验——大部分因类型化引用而天然消失，只剩文本标签与内容规则两类。
3. **数据出口**：保留一个"tres → JSON"导出脚本，用于与旧版/外部工具互通（可选，优先级低）。

### P5 · 发布

1. Windows 桌面导出（exe + 资源内嵌）；存档路径 `user://`（Windows: `%APPDATA%/Godot/...`）。
2. 打包前跑全量回归 + 对拍阈值门禁。

---

## 四、逻辑移植细则（防漂移清单）

这些是"看起来对、跑起来偏"的高发区，逐条翻译时必须对照：

1. **拖放命中优先级**：`bag-win > clue-win > chat-win > bag-dock > clue-icon > tec-dock > infer-icon > goto-icon > tec-avatar > tec-chip`——顺序即语义，不能乱。
2. **拖拽与点击的区分**：`moved` 阈值 5px、`_dragged` 复位时机（pointerdown 开头、排除表之前）。Godot 里用 `_gui_input` 的 button/motion 事件重建同一状态机。
3. **无头兼容**：浏览器版靠 `setTimeout` 返回 0 兜底同步执行；Godot 无头跑测试时 Timer 需要 `--fixed-fps` 或直接同步调用——**所有"延时后完成"的逻辑（分析、蓄力、打字机、结局分幕）都要提供"立即完成"的测试旁路**。
4. **快照字段清单**：哪些进存档（nodes/edges/explored/captured/tried/talkProg/tecProg/collapsed/time/cardSeen/debuted/matrix/endings/garden），哪些是"玩家知识不回滚"（seenTexts/unread）——照着 `02-state.js` 的注释逐条对。
5. **消耗规则**：`合成消耗` 开关 × `reusableTools` 清单 × `installs` 零件账——三条规则在 attemptCombo 和 runCommand 里各有一份实现，移植时合并成一处再翻译。
6. **文本协议**：`[kind:id]` 标签的正则、去重（同一标签多次出现只算一次）、`labelOf` 的中文名解析。**Resource 化后注意：标签里仍是字符串 id，需要一个"标签 id → Resource"的解析注册表**（按类前缀分派），这层映射是新旧两个世界的接缝。

## 五、视觉还原专项

### 5.1 烘焙清单（浏览器渲染一次 → PNG）

| 资产 | 来源 | 产出 |
|---|---|---|
| 纸纹颗粒 / 纸屑 | `--paper-grain` / `--paper-fleck` SVG | `paper-grain.png` / `paper-fleck.png`（平铺） |
| 浮雕阴影 | `--raise` / `--press` 系列 box-shadow | 九切片 `bevel-raise.png` / `bevel-press.png` / `bevel-win.png` |
| 光晕 | 点亮相机的 radial-gradient | `glow.png` |
| 蓄力环 | `.mx-exec::before` 虚线环 | shader 实时画（dash 弧）或 64 帧序列图 |
| 结局遮罩 | `#ending-overlay` rgba 纯色 | `ColorRect` 即可，无需烘焙 |

烘焙方法：在浏览器里做一个只含该元素的空白页，`--force-device-scale-factor=1` 截屏裁切。所有烘焙产物进 `assets/baked/` 并**记录生成参数**（字号/圆角/模糊半径），方便重烘。

### 5.2 字体

- `font.ttf` 导入，**关闭抗锯齿**，整数倍缩放，所有 UI 坐标取整（`snappedi`）。
- **现状（2026-10-20 更新）**：Web 版字体已扩为**全字形覆盖**（`src/assets/font.ttf` 779KB，含对话框 13px 正文所需字形），不再依赖 CJK 回退链——Godot 侧直接整字体导入即可，**不再配 fallbacks**（少一条度量/断行差异来源）。若日后要瘦身，用仓库根 `tools/subset-font.py` 重新子集化，产物放 `ydgodot/assets/raw/font.ttf`。
- 字体的 `line spacing / baseline` 要逐窗校对（详情窗、对话窗、叙事卡三处最易露馅）。

### 5.3 动效

- 缓动函数：在 GDScript 里实现标准 cubic-bezier 求值（给定 P1/P2 控制点），Tween 用 `set_custom_interpolator` 或直接手动补间——**不近似，直接同一条曲线**。
- 时序常量集中成 `MotionProfile` Resource（§2.5）：`WIN_PARK_MS=280`、`TYPE_CPS_MS=45`、`RITE_HOLD_MS=2500`、`TEC_ANALYZE_MS=[5000,8000]` 等，与 `src/js` 里的常量逐一对表。
- 打字机：按字符定时器，中文逐字、英文逐字母——注意浏览器版是逐 `char`（UTF-16 code unit），Godot 逐 Unicode 码点，遇到 emoji/生僻字要显式对齐（建议按码点，差异只在极端字符）。

### 5.4 文字排版（唯一不能烘焙的）

- Godot `Label.autowrap_mode` 的断行规则与浏览器 CSS 不同（尤其 CJK 标点避让）。
- 处理：写一个 `CjkWrap.gd`，实现中文排版规则（禁止行首标点、禁止行尾开括号、英文单词不断裂），对长文本控件统一接管。
- 验收不靠眼睛：把浏览器版若干长文段的实际断行位置导出为基准文件，Godot 侧逐段比对。

### 5.5 像素对拍流程

1. 浏览器侧：`--headless=new --force-device-scale-factor=1` 截屏（现有 CDP 脚本的成熟做法）。
2. Godot 侧：`--headless` + `Viewport.get_texture().get_image().save_png()`，同分辨率同缩放。
3. `pixeldiff/` 脚本输出差异率 + 热力图；进 CI 或手动门禁。
4. 对拍用例清单：开局桌面、花园展开态、TEC 对话窗、推演桌布满槽、对话窗中途等待、结局遮罩、案件切换动画首/末帧。

## 六、测试与回归体系（重建 verify.js 的价值）

| 现有 | Godot 侧 |
|---|---|
| verify.js 无头 DOM stub + 行为断言 | `core/` 纯逻辑单测（GUT 或自研 runner）+ 场景级冒烟（无头启动 → 脚本化操作 → 断言状态） |
| 模板逐字节比对 | 迁移脚本的转换对照报告（P1 一次性）+ `@tool` 校验（编辑器期） |
| CDP 截图人工目检 | §5.5 像素对拍门禁 |
| 测试钩子 `window.__*` | `TestHooks.gd`：仅 debug build 注册，提供与 verify.js 同名操作（`__combo / __reveal / __chatNext…`），让操作脚本可以逐行翻译复用 |

**底线**：P1 结束时，真结局链路必须有等价无头回归；没有测试覆盖的系统不进 P2。

## 七、风险清单

| 风险 | 等级 | 对策 |
|---|---|---|
| 文字光栅化/断行无法逐像素一致 | 中 | §5.4 自实现断行；接受 AA 微小差异；阈值门禁 |
| 交互细节漂移（拖放阈值、命中优先级） | 高 | §4 防漂移清单 + 测试钩子同名翻译 |
| CSS 效果烘焙后调参链路断裂 | 低 | 烘焙参数存档（§5.1），来源 SVG 一并入库 |
| 多人对话/回忆等新系统刚上 Web，Godot 侧二次实现引入新 bug | 中 | P2 先翻测试再翻实现 |
| JSON → Resource 迁移出错（字段漏映射、文本标签断链） | 中 | 转换脚本自带对照报告（实体数/引用数/文本逐字）；迁移后跑全量回归再冻结 JSON |
| 文本内嵌标签仍是字符串，Resource 引用管不到 | 低 | `@tool` 文本标签扫描保留（§2.5 末） |
| **迁移目标漂移**：Web 版仍在推进（多人对话、反应重构持续落地），对照报告与行为基线一直在动 | **高** | 开工前**冻结一个迁移基线 commit**（记为 `MIGRATE_BASE`），P1–P3 的对照、对拍、断言翻译全部以它为准；Web 版后续提交只作为「移植完成后回补」的待办清单，不追着改 |
| Godot Web 导出诱惑 | 低 | 明确不做：导 Web 等于回浏览器还加引擎税 |

## 八、工作量估算（单人全栈）

| 阶段 | 估时 |
|---|---|
| P0 垂直切片 | 1 周 |
| P1 核心循环（含数据迁移） | 1.5–2.5 周 |
| P2 系统全量 | 1–2 周 |
| P3 视觉追平 | 1 周 |
| P4 工程体系 + 创作插件（并行） | 0.5–1 周 |
| **合计** | **约 5–7.5 周** |

> 估算前提：开发者熟悉 Godot 2D UI；`core/` 逻辑大多可从 JS 逐行翻译，视觉上烘焙资产一次到位，迁移脚本一次写对（有对照报告兜底）。

## 九、明确不做

- 不做 3D 化。
- 不做 Godot Web 导出。
- **不在 `ydgodot/` 之外新建迁移文件**（脚本、报告、对拍基线、烘焙产物、文档一律进这个目录；仓库根只留 Web 版的既有文件）。
- **不再维护 Web 编辑器与 build.js 管线**——迁移验证通过后冻结弃用（v2 变更；原为"继续作为内容生产工具"）。
- 移植期不改数据 schema 的设计语义（字段改名/结构调整会污染迁移对照报告）；schema 演进等迁移完成后再做。
- 不在移植期新增玩法内容（防止移植 bug 与内容 bug 混淆）。

## 十、一句话结论

**先花一周做 P0 垂直切片**：它能同时回答"功能能不能 100%"（能）和"视觉差距你介不介意"（对拍后自有答案）。切片过了，后面全是工程量；切片不过，损失只有一周。数据在 P1 一次性迁入 Resource 体系，此后创作、校验、游玩都在 Godot 内闭环，Web 侧工具链整体退役。
