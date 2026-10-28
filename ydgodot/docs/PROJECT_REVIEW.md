# ydgodot 项目体检与重构建议

> **日期**：2026-10-28
> **范围**：`ydgodot/` 全部 GDScript（core / scenes / ui / tests / tools）
> **方法**：静态阅读 + 规模度量 + 17 个无头脚本全量回归
> **结论**：功能与回归底子很好，问题不在正确性，而在**结构性集中**。最优先的动作是划清产品代码与测试基础设施的边界，然后按子系统拆分 `Desktop.gd`。

---

## 0. 摘要

### 0.1 健康度判断

| 维度 | 评价 | 说明 |
|---|---|---|
| 正确性 | **好** | 17 个无头脚本全绿；有汇总的 16 个共 **1858 项 / 0 失败** |
| 数据层 | **好** | 106 个 typed `.tres`，加载即校验；运行时不再读 JSON |
| 依赖方向 | **方向对** | `core/` 不依赖 `scenes/`、`ui/`；无 autoload 隐式全局 |
| 内聚性 | **差** | `Desktop.gd` 8358 行、517 函数、158 字段，承担 15+ 个子系统 |
| 可测试性 | **中** | 覆盖率高，但测试直接访问私有字段与 `dbg_*`，重构成本高 |
| 工程化 | **中** | 无 CI、无统一测试入口、无 GDScript 警告配置 |

### 0.2 三个关键数字

- **8358 行 / 517 函数 / 158 字段** —— `scenes/Desktop.gd` 是单点瓶颈。
- **1158 行** —— 藏在产品类里的测试/截图代码（143 个 `dbg_*` = 805 行，6 个 `_shot_*` = 353 行）。
- **18 份** —— 测试脚本各自复制的 `check()/fails/total` 脚手架与退出逻辑。

> 以上为**批次执行前**的体检快照，用于说明改造动机。批次 0–3 完成后的实时数字与验证结果见 §7。

### 0.3 建议的 Top 5 动作

1. 先提交当前术语收敛改动，清理调试残留与失效 UID（P0）。
2. 建统一测试基类 + 总运行器 + CI，统一测试口径。
3. 把 `dbg_*` 与截图流程抽成 `DesktopDebug`。
4. 按「画布 → 拖放 → TEC → 桌布/花园 → 名册 → 教学 → 案件会话」顺序拆 `Desktop.gd`。
5. 再拆 `GraphState` 的领域状态，最后做节点模型的类型化。

---

## 1. 现状快照

### 1.1 规模分布（体检时）

| 文件 | 行数 | 职责 |
|---|---:|---|
| `scenes/Desktop.gd` | 8358 | 桌面外壳 + 画布 + 所有子系统接线 + 测试 API |
| `tests/headless/test_ui.gd` | 2513 | 真鼠标事件 UI 回归（501 项） |
| `core/GraphState.gd` | 1191 | 图拓扑 + 收纳 + 五感 + 时间轴 + 名册 + 主张 + 花园 |
| `scenes/cards/NodeCard.gd` | 937 | 卡片绘制 + 指针手势 + LOD + 弹回 |
| `tests/headless/test_p26.gd` | 653 | 名册 / 日志 / 图标栏（143 项） |
| `tools/json_to_tres.gd` | 651 | 一次性迁移工具 |
| `core/CaseLoader.gd` | 629 | 装载 + 索引 + 三类校验 + 查询 |
| `scenes/windows/MatrixWin.gd` | 580 | 推演桌布 |
| `scenes/windows/IntroWin.gd` | 565 | 开场适性测试 |
| `ui/TecTheme.gd` | 537 | 调色板 / 字体 / StyleBox |
| `core/SaveSystem.gd` | 362 | 快照 / 撤销栈 / 磁盘存档 |

`core/` 共 20 余个文件，除 `CaseLoader` 的校验段与 `SaveSystem.restore()` 外，单文件规模都在合理范围。

### 1.2 回归基线（2026-10-28 实跑）

| 脚本 | 项数 | 结果 |
|---|---:|---|
| `test_commands.gd` | 51 | ✅ |
| `test_evidence.gd` | 113 | ✅ |
| `test_migration.gd` | 21 | ✅ |
| `test_p0.gd` | 23 | ✅ |
| `test_p12.gd` | 55 | ✅ |
| `test_p14.gd` | 63 | ✅ |
| `test_p15.gd` | 104 | ✅ |
| `test_p16.gd` | 72 | ✅ |
| `test_p21.gd` | 81 | ✅ |
| `test_p22.gd` | 105 | ✅ |
| `test_p23.gd` | 176 | ✅ |
| `test_p24.gd` | 118 | ✅ |
| `test_p25.gd` | 193 | ✅ |
| `test_p26.gd` | 143 | ✅ |
| `test_p27.gd` | 39 | ✅ |
| `test_p28.gd` | 无汇总 | ✅（自行 quit） |
| `test_ui.gd` | 501 | ✅ |
| **合计** | **1858 + P28** | **0 失败** |

> 批次 1 后 P28 也接入汇总（7 项），全量口径固定为 **1865 项**；见 §7。

另有 `bench_f7_f2.gd`、`bench_perf.gd` 两个基准脚本，不在回归口径内。

### 1.3 依赖方向

```
                ┌─────────────────────────────┐
                │          core/              │
                │  GraphState / CaseLoader    │  ← 纯 RefCounted，可无头测
                │  SaveSystem / ComboSystem   │
                │  CommandSystem / Dialogue…  │
                └─────────────▲───────────────┘
                              │ 只读查询（46 处 graph.*）
        ┌─────────────────────┴─────────────────────┐
        │              scenes/Desktop.gd            │
        │   所有子系统接线 / 窗口注册 / 存档 / 教学   │
        └───────▲──────────────▲──────────────▲─────┘
                │ signal       │ signal       │ 直接读
        ┌───────┴──────┐ ┌─────┴──────┐ ┌─────┴──────────┐
        │ scenes/      │ │ scenes/    │ │ scenes/windows │
        │ cards/       │ │ canvas/    │ │ 8 个窗口读     │
        │ NodeCard     │ │ EdgeLayer  │ │ graph          │
        └──────────────┘ └────────────┘ └────────────────┘
```

**方向总体正确**：`core` 不反向依赖 UI。问题在于 `Desktop` 同时是「外壳、画布、交互、业务编排、测试宿主」，任何改动都会牵动全局。

### 1.4 耦合 / 内聚评级

| 层 | 耦合 | 内聚 | 备注 |
|---|---|---|---|
| `core/defs/` | 低 | 高 | typed Resource，`@export` 字段清晰 |
| `core/` 服务 | 低 | 中 | `GraphState`、`CaseLoader` 偏大 |
| `scenes/windows/` | 中 | 中高 | signal 出、`graph` 入；`StorageWin` 有一处直接写 |
| `scenes/Desktop.gd` | **高** | **低** | 上帝对象 |
| `tests/` | 中高 | 中 | 复制脚手架 + 访问私有成员 |
| `ui/` | 低 | 高 | 主题集中，`mono_audit.py` 机器守卫 |

---

## 2. 值得保留的做法

这些是项目的资产，重构时应保持，不要顺手改掉：

1. **显式依赖注入**：无 autoload 单例，`Desktop._new_runtime()`（`scenes/Desktop.gd:2566`）显式组装 `GraphState / ComboSystem / CommandSystem / SaveSystem / DialogueSystem`。
2. **数据即资源**：内容全部落在 `cases/a001/**/*.tres`，`CaseLoader.load_case()` 装载时做节点、证据链、退役标签三类校验。
3. **主题单一来源**：颜色只在 `ui/TecTheme.gd`，`tools/mono_audit.py --check` 可把「漏改颜色」变成可执行检查。
4. **性能意识**：`EdgeLayer` 贝塞尔缓存、`ForceLayout` 分帧收敛、`NodeCard` LOD、`bench_*.gd` 基准。
5. **窗口用 signal 向外**：208 处 `connect`，窗口本身不反向持有 Desktop。
6. **回归覆盖广**：逻辑、数据迁移、真鼠标 UI 三层都有独立脚本，且能无头运行。

---

## 3. 问题清单

### P0 · 立即处理（低风险，约 1 小时）

#### P0-1 工作区未收敛

当前有 25 个已修改文件（术语收敛：推演器→推演、证物袋→物品、证据册→证据）与未跟踪的调试探针：

- `tests/headless/probe_ghost.gd`（+ `.uid`）
- 根目录 `_debug_drag.png`

**动作**：先提交术语改动；删除或移出探针与临时截图。结构化重构必须在干净基线上进行。

#### P0-2 生产环境残留诊断代码

`scenes/cards/NodeCard.gd:806-807`：

```gdscript
## 临时诊断：同时写 Godot 输出面板；Desktop 会把它接到游戏日志（只跟当前诊断节点）。
var debug_event := Callable()

func _debug_event(text: String) -> void:
    print("DBG 卡片：" + text)
    if debug_event.is_valid():
        debug_event.call(text)
```

5 处调用（`:652`、`:773`、`:814`、`:819`、`:831`），每次 `set_home / spring_back / drop` 都会刷输出。

**动作**：删除 `_debug_event` 与全部调用；若仍需要，改为 `if OS.is_debug_build()` 门控。

同类残留：

- `tools/_shot_drag_offset.gd`（一次性截图定位脚本）
- `tests/headless/probe_ghost.gd`（未跟踪探针）

#### P0-3 失效资源 UID

`cases/a001/case.tres:76-81` 引用的 6 个 `MemoryDef` UID 与目标文件头部 UID 不一致，每次装载刷 6 条警告：

| case.tres 中 | 实际文件 UID |
|---|---|
| `uid://0dnvgqkbnl03` | `uid://glitr1t7mmp8`（MEM_0602_fb） |
| `uid://gjes0o4xqiqh` | `uid://bp1jhbyhyhr2s`（MEM_0602_js） |
| `uid://bknj07gk1l1n5` | `uid://bk65rksktdrg8`（MEM_0602_lhs） |
| `uid://crvkasb3obv2y` | `uid://bcq6bekmnbpek`（MEM_0602_zs） |
| `uid://dm5juynxbbgaw` | `uid://bou0y648h4j8x`（MEM_0704_lhs） |
| `uid://djelbc7x3jytj` | `uid://dqjgen3mxkdq`（MEM_0704_zs） |

**动作**：把 `case.tres` 的 UID 更新为实际值，或让 Godot 编辑器重存该资源。修复后装载应无 `invalid UID` 警告。

#### P0-4 文档漂移

- `README.md:230-247` 手写 15 个测试脚本，实际 17 个（漏 `test_evidence`、`test_p28`）。
- README 写「共 1340 项」，实际 1858+；`docs/BACKLOG.md` 写「1860 项」，又和 README 不一致。
- `test_p0.gd` 用例名仍叫「装载 data/case-a001.json」，运行时实际上是 `.tres`。

**动作**：删除手写数字，改为由测试运行器输出汇总（P1-4）；顺手修正用例名。

---

### P1 · 结构性最大债：拆分 `Desktop.gd`

#### 证据

| 指标 | 数值 |
|---|---:|
| 行数 | 8358 |
| 顶层函数 | 517 |
| 成员变量 | 158 |
| `_on_*` 回调 | 54 |
| `.new()` 构造点 | 69 |
| `dbg_*` 测试 API | 143 个函数 / 805 行 |
| `_shot_*` 截图流程 | 6 个函数 / 353 行 |
| `connect` 接线 | 208 处（全项目，非测试） |

它同时承担：

- 根布局、页眉、图标栏、窗口 z 序（窗口管理器）
- 画布相机、卡片增删、连线、力导向布局、LOD
- 卡片拖拽、收纳行拖拽、落点判定、drop 分发
- TEC 窗 / 助手卡 / 分析 / 提示 / 反应表
- 证据链、五感桌布、推演、真名结局
- 花园、音乐播放器、种子、旁白
- 人物名册、档案卡、主张 / 核对 / 盖章
- 回忆时间轴、放映卡、小剧场
- 多人对话、独白
- 案件进入 / 停靠 / 重置 / 续档 / 自动存档 / 撤销
- 6 幕教学流程
- 测试 API 与截图流程

#### 目标切分

按现有函数前缀自然分界，不重新发明模块：

| 新模块 | 职责 | 主要函数来源 |
|---|---|---|
| `scenes/Desktop.gd` | 启动、根布局、页眉、图标栏、窗口注册表、输入路由、toast | `_ready / _build_ui / _build_header / _build_icons / _raise_* / _close_top_window / _notification` |
| `scenes/canvas/CanvasController.gd` | 相机、卡片同步、连线、布局、fit、LOD | `_apply_view / _spawn_card / _sync_canvas / _rebuild_from_graph / _relayout / _fit_cards / _repaint_edges` |
| `scenes/interaction/DragDropController.gd` | 卡片拖拽、收纳行拖拽、落点表、drop 分发、密码 / 组合投放 | `_on_card_drag* / _drop_targets / _dispatch_drop / _finish_sdrag` |
| `scenes/systems/TecController.gd` | TEC 窗 / 助手卡 / 分析 / 提示 / 闲聊 / 反应表 | `_open_tec / _start_tec_analysis / _tec_*` |
| `scenes/systems/MatrixController.gd` | 桌布归位 / 取回、推演、隐藏线索捕获 | `_toggle_matrix / _assign_to_matrix / _run_inference / _capture_*` |
| `scenes/systems/GardenMusicController.gd` | 音乐窗 / dock、花园、种子、真名结局 | `_open_music / _open_garden / _drop_seed / _on_ending_finished` |
| `scenes/systems/PeopleController.gd` | 名册、档案卡、主张 / 字段 / 盖章 | `_toggle_people / _open_person_card / _person_*_field*` |
| `scenes/flows/TutorialFlow.gd` | 6 幕教学 | `_begin_tutorial / _tutorial_*` |
| `scenes/flows/CaseSession.gd` | 进案 / 停靠 / 重置 / 续档 / 自动存档 / 撤销 | `_enter_case / _park_case / _reset_case / _commit / _undo` |
| `scenes/debug/DesktopDebug.gd` | `dbg_*` + 截图流程 | 约 1150 行测试专用代码 |

**目标**：`Desktop.gd` 收敛到 **800–1200 行**。

如果嫌 10 个模块太碎，可先做 4 个：`Canvas`、`DragDrop`、`Systems`、`Debug`，收益 / 风险比最好。

#### 迁移规则

1. **绞杀式**：一次只搬一个子系统，一次提交，17 个测试保持全绿。
2. **不要引入 autoload 单例**：否则会从「一个上帝对象」变成「一组隐式全局耦合」。
3. **模块间通信**：共享一个窄接口的 `DesktopContext`（持 `graph / save / cards / 窗口注册表`），或继续用 signal；不要让控制器互相直接调用。
4. **公开 API 保持稳定**：迁移期在 `Desktop` 上保留 `dbg_*` 转发 shim，测试逐步改为访问新位置。
5. **先搬无状态纯逻辑**（Canvas、Debug），再搬有状态编排（CaseSession、Tutorial）。

---

### P2 · 内聚性与耦合细节

#### P2-1 测试 API 混在产品代码里

143 个 `dbg_*` + 6 个 `_shot_*` 共约 1150 行，和业务逻辑交错。测试还大量直读私有成员：

```gdscript
# tests/headless/test_p28.gd:30-36
scene._view_k = 1.0
scene._view_pos = Vector2.ZERO
scene._view_user = true
scene._apply_view()
scene.dbg_expand("SCENES_garden")
```

**动作**：

- 抽 `DesktopDebug`，Desktop 保留 `var debug` 引用；
- 测试从 `desk.dbg_xxx` 改为 `desk.debug.xxx`（同一批次内可加一次性转发 shim，见 §6.C.1）；
- 截图流程随 `dbg_*` 一并进 `DesktopDebug`，不再单独建 `tools/shot_flow.gd`（它只在 `--shot` 下由 Desktop 调度，单列一个工具反而多一层入口）。

#### P2-2 `GraphState` 是模型层的大杂烩

1191 行，19 个状态字典：节点 / 边、收纳（`stored`）、五感（`matrix`）、时间轴（`time / card_seen / debuted`）、名册（`talk_prog`）、人物档案（`notes / claims / confirmed_fields`）、花园、日志。

**建议拆分**：

| 新类 | 持有状态 |
|---|---|
| `GraphState` | `nodes / edges / explored / captured / hidden / stored / collapsed` |
| `MatrixState` | `matrix`、五感槽位操作 |
| `TimelineState` | `time / card_seen / debuted`、时间轴查询 |
| `PersonaState` | `talk_prog / notes / claims / confirmed_fields` |
| `GardenState` | `garden / seed / plots` |

每个状态提供 `to_dict() / from_dict()`，`SaveSystem` 负责组合，**保持现有存档格式不变**（`format: 1`）。这样 `SaveSystem.restore()`（159 行）会自然拆短。

#### P2-3 UI 直接读 / 写领域状态

8 个窗口共 46 处 `graph.*`：

- `ArchiveWin` / `DetailWin` / `GardenWin` / `LogWin` / `MatrixWin` / `PeopleWin` / `PersonCard` 以**只读**为主，可接受；
- `StorageWin._take()`（`scenes/windows/StorageWin.gd:195`）直接调用 `graph.take_back()`，属于**写入**。

**动作**：窗口写操作统一改为意图信号（`take_requested`），由 `CaseSession` / `Desktop` 执行，保持「一个写入口」。只读访问可保留，但建议收敛成查询方法而不是直接摸字典。

#### P2-4 节点是字符串字典

全项目约 **457 处** `get("key")`、**448 处** `["key"]` 访问。拼错 key 不会报错，只会静默取默认值。

**渐进方案**：

1. 先在 `GraphState` 定义 `const K_ID := &"id"` 等 `StringName` 常量；
2. 补 typed accessor（`node_x(key) -> float`、`node_label(key) -> String`）；
3. 长期引入 `NodeState` 类 + `to_dict()/from_dict()`，但必须排在 Desktop 拆分之后。

#### P2-5 重复的 UI 小工具

| 重复 | 位置 |
|---|---|
| `_clamp_pos()` 逐字相同 | `MusicDock.gd:127`、`TecChip.gd:163` |
| `_fit_height()` 各写一份 | `ChatWindow` / `GardenWin` / `MemCard` / `NarrCard` / `TecWindow` |
| `_scroll_to_end()` 3 份 | `LogWin` / `ArchiveWin` / `PeopleWin` |
| `_make_row()` 5 份 | `PeopleWin` / `LogWin` / `StorageWin` / `ArchiveWin` / `CaseMapWin` |

**动作**：`ui/ListPanel.gd`（行构建 + 滚动 + 自适应高度）、`ui/FloatingPanel.gd`（夹边定位），窗口组合使用。

#### P2-6 超长函数

| 函数 | 行数 | 位置 |
|---|---:|---|
| `CaseLoader.validate_evidence()` | 117 | `core/CaseLoader.gd:143` |
| `SaveSystem.restore()` | 159 | `core/SaveSystem.gd:91` |
| `Desktop._shot_p2_flow()` | 189 | `scenes/Desktop.gd:8120` |

前两个按字段域拆成私有小函数即可，风险很低，适合作为热身重构；`_shot_p2_flow` 随 P1 一起移出。

#### P2-7 测试脚手架 18 份复制

17 个测试脚本 + 1 个基准脚本各自复制了同一份 `check()/fails/total`，`_finish/_cleanup` 也有多份。

**动作**：新增 `tests/headless/_test_base.gd`（下划线前缀，避免被运行器当成用例）：

```gdscript
# tests/headless/_test_base.gd
extends SceneTree

var fails := 0
var total := 0

func check(name: String, cond: bool, detail: String = "") -> void: ...
func _cleanup() -> void: pass          # 子类覆盖
func _finish() -> void:
    _cleanup()
    print("=== %d 项，失败 %d ===" % [total, fails])
    quit(0 if fails == 0 else 1)
```

测试改为 `extends "res://tests/headless/_test_base.gd"`，保留 `_initialize()`，结束时调 `_finish()`；需要删临时档时覆盖 `_cleanup()`。P28 的自行退出逻辑也由基类统一。

---

### P3 · 性能与工程化

#### P3-1 `Desktop._process` 常开

`scenes/Desktop.gd:467` 每帧都跑，但只在四种状态下有活干：布局任务、收纳行拖拽、连线跟随、待自动存档。

**动作**：默认 `set_process(false)`，进入这些状态时开启、结束后关闭。窗口类已经正确使用 `set_process(true/false)`，Desktop 应保持一致。

`GardenWin._process`（`scenes/windows/GardenWin.gd:259`）也应在 `visible == false` 时停掉，而不是函数内空转返回。

#### P3-2 没有 CI、没有统一测试入口

全套测试已能返回正确退出码，但需要人工逐条执行；README / BACKLOG 的手写清单已经开始漂移。

**动作**：

1. 新增 `tools/run_tests.sh` / `.ps1`：遍历 `tests/headless/test_*.gd`，汇总项数与失败数，任一失败返回非 0；
2. 接 GitHub Actions（Godot 4.7 headless），把「0 失败」变成强制门槛。

#### P3-3 未配置 GDScript 警告

`project.godot` 没有任何 `debug/gdscript/warnings/*` 配置。

**动作**：先以警告（非错误）开启 `unused_parameter`、`shadowed_variable`、`unsafe_property_access`，可选 `untyped_declaration`；可配合 `gdlint / gdformat` 逐步收敛。这个代码库注释质量很高，补上机器检查收益明显。

#### P3-4 全代码构建 UI（只有 1 个 `.tscn`）

所有窗口都在 `_build()` 里手写像素坐标。这是 Web 移植期的合理选择，但长期代价是：编辑器无法预览、无法可视化调整、布局常量与业务逻辑混在一起。

**动作**：不必现在改。等 Desktop 拆分完成后，先把 `SysWindow` 壳做成 `.tscn`（保留 `body/content` 命名，测试依赖这些节点名），逐步迁移文本类窗口；画布类保持代码构建。

---

## 4. 目标架构与通信规则

### 4.1 推荐分层

```
core/            纯领域逻辑（RefCounted，可无头测）
  defs/          typed Resource
  state/         GraphState + MatrixState / TimelineState / PersonaState / GardenState
  services/      CaseLoader / ComboSystem / CommandSystem / SaveSystem / DialogueSystem

scenes/          表现层
  Desktop.gd     外壳 / 布局 / 窗口注册 / 输入路由（≤ 1200 行）
  canvas/        相机 / 卡片 / 连线 / 布局
  interaction/   拖拽 / 落点 / 分发
  systems/       TEC / 桌布 / 花园音乐 / 名册
  flows/         教学 / 案件会话
  windows/       各系统窗（signal 出，只读 graph）
  debug/         dbg_* + 截图流程（仅调试/测试构建使用）

ui/              可复用控件与主题
tests/           基类 + 各阶段回归
tools/           迁移 / 基准 / 截图 / 审计
```

### 4.2 通信规则

1. **窗口 → 外部**：只用 signal 表达意图，不直接改 `graph`。
2. **控制器 → 控制器**：通过 `DesktopContext` 或 Desktop 中转，不互相持引用。
3. **core → 表现层**：禁止。
4. **测试 → 产品**：只走公开 API 或 `DesktopDebug`，不摸 `_private` 字段。
5. **不引入 autoload**：需要全局能力时，通过 Desktop 显式注入。

### 4.3 存档兼容

任何模型拆分都必须满足：

- 磁盘格式仍为 `format: 1`；
- `user://tec_case_<id>.save` 可被旧档直接读取；
- `SaveSystem.restore()` 对缺失字段继续使用默认值；
- 每次拆分后跑 `test_p15.gd`（快照 / 撤销 / 存档，104 项）。

---

## 5. 执行路线图

| 批次 | 内容 | 风险 | 验收标准 |
|---|---|---|---|
| **0 · 卫生** | 提交术语改动；删调试残留；修 6 个 UID；更新 README | 极低 | 装载无 UID 警告；17 脚本全绿；工作区干净 |
| **1 · 测试基建** | `_test_base.gd` + 统一运行器 + CI + `test_audit.py` | 低 | 一条命令跑完全部；失败必返回非 0；README 不再手写计数；测试不新增私有字段访问 |
| **2 · Debug 抽离** | `DesktopDebug`（含截图流程） | 低-中 | Desktop 减少约 1150 行；17 个测试改为 `desk.debug.*`；发布构建不实例化 |
| **3 · Desktop 拆分** | 边界清晰者优先：Garden/Music → People → Tec → Matrix → Tutorial → CaseSession → Canvas → DragDrop → Launcher → Narrative → CardUi → Windows → Chrome | 中 | 每步 17 脚本全绿；`Desktop.gd` ≤ 1200 行 |
| **4 · 模型收敛** | GraphState 领域拆分 + NodeState 类型化 | 中-高（动存档） | `test_p15` 全绿；旧档可读；魔法字符串显著减少 |
| **5 · 表现层收尾** | `ListPanel` / `FloatingPanel`；`_process` 门控；测试私有访问清零 | 低 | 重复 helper 归零；空闲帧无 `_process`；测试只走公开接缝 |

### 5.1 每批的通用做法

1. 先跑一遍基线（17 脚本），记录项数。
2. 只动一个关注点，一次提交。
3. 提交信息写清「搬了什么、没改什么」。
4. 若测试需要改，优先加兼容 shim，而不是改测试预期。
5. 完成后重跑全套，确认失败数为 0 且项数不下降。

---

## 6. 附录

### A. 复现体检的命令

```bash
GODOT="/d/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe"

# 全量回归（建议批次 1 固化成脚本）
for f in tests/headless/test_*.gd; do
  "$GODOT" --headless --path . --script "res://$f"
done
```

### B. 度量口径

| 指标 | 口径 |
|---|---|
| 行数 | `wc -l`（不含空尾行） |
| 函数数 | 顶层 `^func ` |
| 字符串键访问 | `get("…")` / `["…"]` 的文本匹配 |
| graph 访问 | `scenes/windows/*.gd` 中 `graph.` 出现次数 |
| 测试项数 | 各脚本 `=== N 项，失败 M ===` 汇总行 |

### C. 已建议口径（2026-10-28，默认按此执行）

以下取舍已给出推荐；除非后续明确推翻，否则按此实施。

| # | 事项 | 建议 | 核心理由 |
|---|---|---|---|
| 1 | `dbg_*` API 是否保留转发 shim | **不保留长期 shim**：`DesktopDebug` 原样保留函数名，测试机械替换 `desk.dbg_` → `desk.debug.dbg_` | 143 个函数的 shim 会把公开 API 面翻倍；测试是我们自己的，文本替换可控 |
| 2 | 测试访问私有成员 | **不接受长期访问 `_` 字段**：读走 `DesktopDebug` 查询，动作用 `dbg_*` 或真实输入事件；新增 `test_audit.py` 守卫 | 拆分 Desktop 时私有字段会移动，测试耦合会让每一步都变成双倍改动 |
| 3 | 存档兼容 | **必须兼容**：保持 `format: 1`，只做增量字段，缺省值兜底；加 golden save 夹具 | 调查员证、备注、花园都是玩家真实进度；兼容成本低，破坏信任成本高 |
| 4 | `.tscn` 化范围 | **本轮不做迁移**；最多做 `SysWindow` 壳且非必须；优先做代码组件 `ListPanel` / `FloatingPanel` | 现 UI 是刻意像素精确、测试依赖节点路径；场景化收益低、视觉回归风险高 |
| 5 | 调试代码构建策略 | `DesktopDebug` 仅在 `OS.is_debug_build()` / `--shot` / 无头测试时实例化；产品代码不得依赖它 | 发布构建零测试代码运行；一个开关，避免满项目 null 检查 |

#### C.1 `dbg_*` 迁移方式

- `DesktopDebug` 作为 `Desktop` 的子节点（或 RefCounted），持有 `desk` 引用；
- 函数名保持 `dbg_xxx` 不变，只换宿主：`desk.dbg_state()` → `desk.debug.dbg_state()`；
- 同一批次内完成替换并删除任何临时转发；**不保留跨批次 shim**，避免出现两套入口；
- 若测试改动量过大，可在批次 2 的第一个提交加一次性转发，第二个提交删除——shim 生命周期不超过一个提交。

#### C.2 测试私有访问的边界

允许：

- 通过 `DesktopDebug` 暴露的查询 / 动作；
- 通过真实 `InputEvent`（`Input.parse_input_event`）驱动 UI；
- 只读 Godot 内置公开属性（`signal`、`visible`、`size` 等）。

不允许：

- 读写 `scene._view_k`、`scene._cards` 一类私有字段；
- 直接调用 `_on_card_selected()` 等私有回调；
- 为了测试方便在产品类里新增 `_test_only` 方法。

落地方式：

1. 新测试立即遵守；
2. 触碰到的旧测试顺手改（童子军规则）；
3. 批次 5 结束时清零；
4. `tools/test_audit.py` 扫描 `tests/**/*.gd` 中的 `\._` 访问，白名单逐条登记，接入 CI。做法与现有 `mono_audit.py` 一致：默认报错，白名单放行。

#### C.3 存档兼容的具体约束

- `FORMAT` 保持 `1`；新增字段只写不读也必须能被旧代码忽略；
- `restore()` 对缺失字段继续用默认值，不因新字段报错；
- 新增 `tests/fixtures/save_v1.json` 作为 golden fixture，`test_p15` 增加「旧档往返」用例；
- 只有必须删除 / 改语义时才升 `format: 2`，并提供 `migrate_v1_to_v2()` + 迁移测试；
- 每次模型拆分后必须跑 `test_p15.gd`（104 项），并手工验证一份真实旧档。

#### C.4 `.tscn` 的边界

- **不做**：把现有文本窗口批量改成 `.tscn`；
- **可选**：`SysWindow` 壳做成场景，保留 `body` / `content` 节点名；
- **优先**：把重复的 `_make_row` / `_fit_height` / `_scroll_to_end` / `_clamp_pos` 抽成代码组件；
- 如果只是想在编辑器里预览，增加一个 dev-only 预览场景实例化各窗口即可，不动产品路径。

#### C.5 调试构建开关

```gdscript
# Desktop._ready()
if OS.is_debug_build() or _shot_mode():
    debug = load("res://scenes/debug/DesktopDebug.gd").new()
    debug.desk = self
    add_child(debug)
```

- 用 `load()` 而不是 `preload`，避免发布构建强行打包调试脚本；
- 产品代码不得出现 `if debug != null` 式的分支；测试与截图是唯一消费者；
- `--fast` 只是计时旁路，不作为调试开关；
- 导出预设可用 `exclude_filter` 排除 `scenes/debug/`，但前提是产品代码不直接引用该路径。

#### C.6 决策影响

- **批次 2** 会修改全部 17 个测试文件（机械替换），但换来「产品代码零测试宿主」；
- **批次 1** 需要新增 `test_audit.py`，与现有 `mono_audit.py` 同一套路；
- **批次 4** 的模型拆分自由度受限（必须兼容 `format: 1`），但避免玩家进度丢失；
- **批次 5** 不做 `.tscn` 迁移，节省的时间投入到 UI 组件复用与 `_process` 门控；
- 所有决策都服务于同一个目标：**产品代码不含测试宿主，测试不依赖私有实现**。

---

## 7. 执行记录

> 批次按 §5 的顺序落地，每个批次独立提交；验证口径固定为 `tools/run_tests.sh` 全量回归 + 两项审计。

| 批次 | 状态 | 落地内容 | 验证 |
|---|---|---|---|
| **0 · 卫生** | ✅ | 术语统一（`e6130ea`）、清理调试残留与失效 UID（`ca84a8d`）、体检文档（`b77ce61`） | 装载无 UID 警告；17 脚本全绿 |
| **1 · 测试基建** | ✅ | `tests/headless/_test_base.gd`；`tools/run_tests.sh`；`tools/test_audit.py` + 124 条基线；`mono_audit.py` UTF-8 修复；GitHub Actions；README 去手写计数（`1196076`） | **1865 项 / 0 失败**；两项审计通过 |
| **2 · Debug 抽离** | ✅ | 新增 `scenes/debug/DesktopDebug.gd`；`Desktop.gd` 8358 → 6807 行；`class_name Desktop`；测试 776 处改为 `scene.debug.dbg_*` | **1865 项 / 0 失败**；发布构建不实例化；审计 124 条无新增 |
| **3 · Desktop 拆分** | ✅ | 13 个子系统控制器；`Desktop.gd` 6807 → 1022 行；测试私有访问审计扩到 `scene.<controller>._` | **1865 项 / 0 失败**；`Desktop.gd` ≤ 1200 行 |
| **4 · 模型收敛** | ⏳ | 待执行：`GraphState` 领域拆分 + 节点模型类型化 | 旧档可读（`format: 1`） |
| **5 · 表现层收尾** | ⏳ | 待执行：UI 组件复用、`_process` 门控、测试私有访问清零 | 审计基线归零 |

**批次 2 的实际结果与预估差异**

- 实际减少 **1551 行**（预估约 1150 行）：抽走了 143 个 `dbg_*`、6 个 `_shot_*` 流程，以及 `_installed_map` / `_lit_map` / `_dbg_node_key` / `_show_chat_lines` / `_show_mem_lines` / `_ensure_card` / `_wait` 共 7 个仅被测试使用的辅助函数。
- `DesktopDebug` 最终为 `Node` 子节点而非 `RefCounted`：`RefCounted` 持有 `Desktop` 会被 `Desktop` 的引用反向持有，形成引用环；挂成子节点后生命周期随场景销毁，`get_tree()` / `get_viewport()` 走 `desk.`。
- 未新增长期转发 shim：测试一次性机械替换完成，`Desktop` 上不保留 `dbg_*` 入口。
- 截图流程留在 `DesktopDebug` 内，`tools/shoot_aesthetic.gd` 改走 `scene.debug.dbg_*`。

**批次 3 的实际结果**

拆分顺序从「低耦合 → 高耦合」推进，而不是照 §5 从 Canvas 开始：先搬边界清晰的 Garden/Music、People、Tec、Matrix、Tutorial、CaseSession，再搬 Canvas、DragDrop、Launcher、Narrative、CardUi、Windows、Chrome。每一步只搬一个子系统并跑全套，避免在最大依赖块上同时引入两类风险。

| 控制器 | 行数 | 职责 |
|---|---:|---|
| `scenes/Desktop.gd` | 1022 | 生命周期、根布局、输入路由、toast、日志、`_process` 编排 |
| `scenes/desktop/CanvasController.gd` | 870 | 相机、卡片同步、连线、力导向、布局、命中查询 |
| `scenes/desktop/CaseSession.gd` | 759 | 进案 / 停靠 / 重置 / 续档 / 存档 / 撤销 / 开局 |
| `scenes/desktop/DragDropController.gd` | 676 | 卡片拖拽、收纳行拖拽、落点表、drop 分派 |
| `scenes/desktop/CardUiController.gd` | 584 | 详情窗、右键菜单、容器展开、密码、组合、叙事卡 |
| `scenes/desktop/TutorialFlow.gd` | 522 | 6 幕教学 |
| `scenes/desktop/TecController.gd` | 459 | TEC 窗、分析、提示、反应表 |
| `scenes/desktop/NarrativeController.gd` | 457 | 时间轴、档案、放映卡、对话 / 独白 |
| `scenes/desktop/PeopleController.gd` | 406 | 名册、档案卡、主张 / 字段 / 盖章 |
| `scenes/desktop/ChromeController.gd` | 402 | 页眉、调试面板、面包屑 / 目标、聚焦选项 |
| `scenes/desktop/LauncherController.gd` | 372 | 图标栏、角标、app 开窗 |
| `scenes/desktop/WindowController.gd` | 297 | 主窗、z 序、提层、浮窗落点 |
| `scenes/desktop/MatrixController.gd` | 239 | 桌布、归位 / 取回、推演、结局 |
| `scenes/desktop/GardenMusicController.gd` | 224 | 音乐播放器、花园、种子、收幕 |
| `scenes/debug/DesktopDebug.gd` | 1246 | 测试 / 截图 API（批次 2 的 1198 + 本批新增查询） |

**结构约定（过渡期）**

- 每个控制器都是 `Desktop` 的 `Node` 子节点，由 `_mount_parts()` 在 `_build_ui()` 之前挂载，`desk` 注入宿主引用。
- 控制器之间不互相持有；跨子系统调用统一走 `desk.<controller>.<method>`，宿主仍是唯一装配点，后续可逐步收窄成显式接口 / signal。
- 搬出的函数名保持原样（`_open_tec` 等），减少测试与调用点的一次性改动。
- 仍直接访问 `desk._field` 是**有意保留的过渡态**：它把耦合显式化、可审计，但不等于最终形态。批次 4/5 再把「共享状态」收进 `DesktopContext` 与领域对象。

**本批踩到并修正的坑**

- 原 `Desktop.gd` 里有若干**声明夹在函数之间**（`_move_twens`、`_follow_frames`、`_layout_job`、`_layout_sig`、`_fresh_spawns`、`_last_rebuild_stats`、`_mem_anchor_key`、`ZR_*`、`ICON_*`、`ForceLayoutScript`）。按顶层函数切块时会把这些声明误并入前一个函数，必须逐个确认归属：画布状态归 `CanvasController`，层级 / 图标常量归 `Desktop`，放映锚点归 `NarrativeController`。
- 控制器从 `Control` 变成 `Node` 后，`accept_event()` 这类控件方法要显式走 `desk._stage.`；`add_child()` 建页眉时也必须挂回 `desk`，否则 `scene.get_node("header/...")` 与锚点布局都会偏。
- `Callable(self, "_handle_card_drop")` 在搬家后会指向控制器自身；改为 `Callable(desk.drag, ...)`。
- 用 `:=` 接收 `desk.<controller>.method()` 的返回值会因宿主无类型而推断失败，统一补显式类型。
- 前缀替换不能只按子串：`_autosave` 会误伤 `_autosave_due_msec`，`_undo` 会误伤 `_undo_btn`。批量改写后需再做一次「引用是否真实存在」的静态核对。

**测试基建补强**

- `tools/run_tests.sh` 现在把 `SCRIPT ERROR` / `Parse Error` / `Failed to load script` 直接判失败。此前 Desktop 解析失败时测试会少跑一大段却仍报「0 失败」，本批前半程真实踩到过。
- `tools/test_audit.py` 的扫描口径扩到 `scene.<controller>._xxx`。基线从 124 条收敛到 **108 条**（其中 50 条是控制器私有访问）；口径变宽而总数下降，说明批次 3 本身没有增加测试对私有的新依赖。

**仍待收敛的测试接缝**

- 窗口 / 画布组件里还有 **45 个 `dbg_*`**（`IntroWin` 10、`CertWin` 6、`EdgeLayer` 4、`GardenWin` 4、`LogWin` 4、`CaseMapWin` 3 等）。它们位于组件边界，不在 `Desktop` 内；批次 5 统一评估：能由真实输入驱动的删掉，其余改名为 `test_*` 或并入 `DesktopDebug` 的查询层。
- `ChromeController` 把调试面板按钮命名为 `dbg_btn_*`，`test_ui.gd` 仍依赖该名称查找；批次 5 改为按文案查找。

**下一步**：批次 4 拆 `GraphState`（`MatrixState` / `TimelineState` / `PersonaState` / `GardenState`）并类型化节点模型，保持 `format: 1` 存档可读；每步以 `test_p15` + 全量回归为门槛。

---

> 本报告起初只描述现状与建议；批次 0–3 已按 §5 落地，现状与本节的差异以本节为准。
