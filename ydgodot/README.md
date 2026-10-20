# T.E.C-OS · Godot 移植工程（ydgodot/）

> 迁移根目录。**后续迁移的所有内容都在这里**：工程、资源、测试、烘焙产物、转换脚本、文档。
> 计划与阶段目标见 [`GODOT_PORT_PLAN.md`](./GODOT_PORT_PLAN.md)。

## 当前状态：P1 进行中（P1.1 数据迁移已完成）

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
- **P1.4–P1.6**（五感与推演桌布 / 快照撤销存档 / 开场适性测试）：未开工

一条完整链路已在 Godot 4.7 里跑通，其余系统尚未搬迁：

```
桌面壳（暗色页眉 / 图标栏 / 案件窗）
  └ 画布：单场景「植物学家的花园」展开（卡片节点 + 柔和浮雕）
      └ 拖放组合：手电筒 ——拖到——> 黑影（先要点亮，否则被发光门拦下）
          └ 尸体场景展开（绷带 / 粗糙的绳索 / 下腹部右侧 / 血痕…）
              └ TEC 窗：拖场景进来分析（真实 5–8 秒进度条）
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

# 3.5) 重跑数据迁移（JSON → .tres；只在确认数据基准后跑）
"$GODOT" --headless --path ydgodot --script res://tools/json_to_tres.gd

# 4) 视觉自查：跑一遍切片，把 13 张截图存进 docs/
"$GODOT" --path ydgodot --resolution 1280x800 -- --shot
```

- `--fast`：把「分析计时」「结局分幕延迟」压到 0（无头/测试旁路，见计划 §四.3）。
- `--shot`：跑固定剧本并截图（`docs/p0_*.png`）。截图需要真实渲染，**不能加 `--headless`**。

## 目录

| 路径 | 内容 |
|---|---|
| `core/` | 纯逻辑（不挂场景树，可无头测）：`CaseLoader` / `GraphState` / `ComboSystem` |
| `scenes/` | `Desktop.tscn` + `Desktop.gd`（壳与接线）、`cards/NodeCard.gd`、`windows/*` |
| `ui/` | `TecTheme.gd`（配色/字体/StyleBox）、`shaders/surface.gdshader`（浮雕）、`shaders/paper.gdshader`（纸纹） |
| `cases/a001/` | **内容数据（唯一形态）**：`case.tres` 索引 + `scenes/` `items/` `chars/` `clues/` `memories/` `dialogues/` `endings/`，一实体一文件 |
| `core/defs/` | 25 个自定义 Resource 类（`SceneDef` / `ItemDef` / `CommandDef` 六子类 / `CharDef` …） |
| `data/` | `case-a001.json` —— **已冻结为只读档案**（迁移输入 + 对照基准，运行时不再读它） |
| `assets/raw/` | `src/assets/` 的拷贝（字体 / 头像 / OGG / 花园序列帧） |
| `tests/headless/` | `test_p0.gd`（逻辑 20）、`test_ui.gd`（真鼠标事件 32）、`test_migration.gd`（JSON ↔ `.tres` 逐字段 14）、`test_commands.gd`（六型命令 49）、`test_p12.gd`（图状态全量 37）—— **共 152 项** |
| `docs/` | P0 切片 6 张 + P1 新特性 7 张截图（P3 对拍基线从这些图起步） |
| `tools/` | P1 的 `json_to_tres.gd` 与对拍工具（待建） |

## P0 已做 / 明确没做

**已做**

- 数据装载 + 文本协议（`[item:X]` 标签换中文名、`<br>` 转换行、单复数前缀都认）
- 图状态：展开场景长出实体节点、幂等、`entity` / `move` 边
- 组合与命令：发光工具门（未点亮拦下、不记 tried）、`useItem` 命中、`onSuccess.scene` 揭示
- 交互：拖拽（5px 阈值、落点判定、拖动位移）、双击（点亮 / 展开）
- 窗口基类：拖动标题栏、关闭、内容流 / 定位容器分离
- TEC 分析：5–8 秒进度条 + `--fast` 旁路 + 解读文案
- 结局演出：分幕台词按 `delay` 落下、点击继续、遮罩收幕
- 无头回归两层（逻辑 + 界面），全绿

**没做（P1 起）**

- JSON → `.tres` Resource 迁移（含类型化引用与 `@tool` 校验）
- 真实布局算法（现在是 4 列网格，无连线、无层级、无镜头聚焦/缩放）
- 撤销栈 / 快照 / 存档、收纳（证物袋 / 线索册）、详情窗、人物名册、对话系统
- 回忆/时间轴、案件切换、音乐播放器、花园彩蛋
- 打字机、窗口最小化、系统窗层级与 z 序的完整规则

## 与 Web 版的已知偏差（P0 有意从简，P3 再追平）

| 项 | Web 版 | P0 现在的做法 |
|---|---|---|
| 纸纹 / 浮雕 | 内联 SVG 噪波 + 多层 box-shadow | **shader 程序生成**（`paper.gdshader` / `surface.gdshader`）——P3 若换烘焙 PNG，只替换材质 |
| 节点布局 | 径向分层 + 折叠/展开动画 + 镜头平移 | 4 列网格，无动画 |
| 叙事卡 | 锚在触发节点上方、可拖 | 固定在右下角的浮窗（可拖） |
| 手电筒来源 | 书桌 → 左侧抽屉 → 手电筒 | 开局直接放在画布上（抽屉链路属 P1.2） |
| 数据形态 | `data/case-a001.json` 直读 | `cases/a001/**/*.tres`（P1.1），JSON 冻结为档案 |
| 结局触发 | 推演桌布命中配方 | 切片里「分析过尸体场景」即演示（`TRUE_E` 的分幕脚本） |
| 字体回退 | VonwaonBitmap → SimSun → … | 全字形字体直导，**不配 fallback** |

## 约定

- `core/` 里的类**不继承 Node**，方便无头跑。
- 所有「延时后完成」的逻辑必须带「立即完成」旁路（`--fast` / `finish_now()`）。
- 测试钩子（`dbg_*`）只做**同名翻译**，命名对齐 Web 版 `window.__*`，方便把操作脚本逐行搬过来。
- 迁移期不改数据 schema（见计划 §九）。
