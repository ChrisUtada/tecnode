# 交互与节点层：Web ↔ Godot 差距检查报告

> **归档（2026-10-24）**：Godot 版已领先 Web，本报告的「差距 / 追平」口径退役；Web 只作参考，不再按此报告逐项回改 Godot。内容保留为迁移期证据。
>
> 检查日期：2026-10-21 · 范围：画布节点（渲染 / 连线 / 展开 / 拖动 / 落点 / 组合 / 视角 / 反馈）
> 方法：两侧源码逐函数对照（`src/js/*.js` ↔ `ydgodot/**/*.gd`），每条差异附文件与行号，可复查。
> 结论口径：**P0 = 阻断核心玩法或让玩家判定"坏了"**；P1 = 明显缺失，玩得下去但味道不对；P2 = 细节/口径漂移。

---

## 0. 一句话结论

**渲染层（P3）已经追到像素级，交互层基本没复刻。**

上一轮把窗框、页眉、图标块、纸纹压到全屏 2.30% 差异（窗框外沿 0），但那是**静态截图的对齐**。
一旦动手，两侧就是两套东西：Web 的画布是"有连线的网 + 可钉住的自由摆位 + 六类落点"，Godot 现在
是"一堆按网格排好的卡片，点一下就展开"。

统计：**50 项差异，P0 10 项 / P1 23 项 / P2 17 项**。其中 6 项是数据层已就绪、只差 UI 通道
（反应表 14 条、tried 边、pinned 字段、bag/ledger 收纳 API），属于"接上就活"；其余需要重写画布层。

**落点（拖到图标 / 窗口）单项复核结论**（2026-10-21 补检，详见 §6）：Web 有 **11 个落点元素**，
Godot 命中 **5 个**、动作只有 **3/6**；反向「从收纳窗拖出」8 条路径只实现 2.5 条，
且"落在松手那一点"**一条都没有**。最糟的是拖到未接线的图标上：实测卡片被拖到
`position.x ≈ -193 ~ -263`，而画布从 `x=101` 起且 `clip_contents=true` ⇒ **只剩 23% 露出，
抓得靠右时 0%（整张消失）**，玩家看到的是"拖一下就丢了"。

---

### 0.1 执行状态（2026-10-21 夜 · P0 八项已落地）

§3.1 的 8 项全部做完。验收口径：

- **全套无头断言 1043 项 0 失败**（14 个脚本：`20/67/15/49/37/56/85/61/71/84/164/103/146/85`，其中 `test_ui` 41 → 67，`test_p24` 102 → 103）。
- **P3 静态对拍不退化**：连线层上线后与上线前逐像素对照 **`max diff = 0`**，对 Web 的 2.30% 基线原样有效。

| # | 项 | 落地位置 | 与本节原方案的区别 |
|---|---|---|---|
| ① | 世界层 / 边层 / 手势层 | `scenes/canvas/EdgeLayer.gd` 新增；世界层复用 `_card_layer`（`2000×1300`）；手势在 `Desktop._on_stage_input` | **没有拆出 `CanvasWorld.gd` / `CanvasInput.gd`**：`_card_layer` 本身就是世界层、`_on_stage_input` 本身就是手势层，再包一层只是多一跳间接。连线端点一律走 `NodeCard.visual_rect()`（§4.1），无手算 |
| ② | 单击/双击分离 | `NodeCard._click()`：280ms 窗口 + 6px 邻近判定（`DBL_MS`） | 窗口取 **280ms**（本节写 250ms）。**拖动开始也选中** —— 本节标了"需你拍板"，按建议做 |
| ③ | 位置写回 + 撤销 | `NodeCard._release_drop()` 写 `n["x"]/n["y"]` 并夹回 world 边界；`Desktop._on_card_drag_finished()` → `_commit()` | |
| ④ | 力导向布局 | `Desktop._layout_force()`，斥力 / 最小间距 / 弹簧 / 向心 / 260 轮全部照抄 `07-render.js` | 播种按"容器 5 列网格、实体围中心"，且**只播 `x < 0`（从没落过位）的节点**；`pinned` 的节点全程 `free=false` 不动 |
| ⑤ | 右键钉住 + 角标 | `NodeCard` 右键 → `pin_toggled`；钉住时左上「已固定」药丸，拖动不再自动钉住 | |
| ⑥ | 拖进证物袋 / 线索册 | `Desktop._drop_targets() -> [{id, rect}]`（11 项单一表）+ `_apply_drop()`；悬停高亮与松手分派共用同一份 | **推演桌布并进了同一张表**：Web 的 `nodeDropTargets()` 是 **10** 项，桌布在松手处单独判一遍；Godot 合成一条 ⇒ 表里是 **11** 项（id 白名单已在 `test_ui` 里锁住） |
| ⑦ | 反应表通道 | `ComboSystem.use_item()` 五段：目标反应表 → 工具反应表 → `useItem` 命令 → 容器扫描 → 记 `tried` | 比分节写的四段多一段「记 tried」——失败也要留下淡虚线，这是 E4 的前提。**反应表实测 27 条**（物品触发 14 + 线索触发 13），全为纯文本；`results.scene` / `results.items` / `onSuccess.items` 三条产出来源**未接**（数据不触发，接了也无从验证，已在代码注释里标成已知缺口） |
| ⑧ | 节点详情窗 | `scenes/windows/DetailWin.gd` 新增，只列简介 / 状态 / 来源 + 底部四个重看按钮 | |

**§6.7 断言表的落地情况**：`dbg_drop_target_ids()` 已加，「落点 11 项白名单」与「五个图标落点都在」两条断言已进 `test_ui`。
`dbg_drop_at()` 没有实现 —— 改为**端到端真拖拽**（`_press`/`_motion`/`_release` 打到真实图标矩形），断言的是"卡片真的收进袋了 / 真的弹回原位了"，
比直接调分派函数更严格。

**P0 之外仍未做**（属 §3.2 P1，不在本批）：
- ~~图标栏脱离 `VBoxContainer` 可自由拖动、补 `people` / `log` 两个图标与 `bag` / `clue` 角标~~ → **已随批 1 落地，见 §0.2**；
- ~~**拖动幽灵线**（§6.4 四件附带事的第四件：Web 从原点拉一条虚线到指针）~~ → **已随批 2 落地，见 §0.3**（其余三件——悬停高亮 / 弹回原位 / 边界夹回——已随 P0 / 批 1 落地）；
- ~~**桌布 chip → 画布（带坐标）**：反向 8 条路径里唯一还缺的一条~~ → **已随批 2 落地，见 §0.3**（§6.3 补检时 chip 已有拖拽手势，缺的是坐标语义与册图标入口；双击取回落默认位保持原口径）；
- ~~§3.3 P2 细节（N8 hover / V4 pop / V5 warn / V6 dim / N7 场景命令 / D6 镜像）~~ → **已随批 3 落地，见 §0.4**。

---

### 0.2 执行状态（2026-10-21 夜 · 批 1：名册 / 日志 / 图标栏已落地）

批 1 = 差距报告里 I1（人物名册）/ I2（因果追踪）/ B 组的图标栏与角标，一起做是因为它们互为前提：
名册与日志要先进图标栏才点得开，角标的计数又分别来自推演器 / 收纳（P0 已通）与日志未读。

- **全套无头断言 1043 项 0 失败**（14 个脚本），其中新增 `test_p26.gd` **85 项**。
- **实证截图**：`docs/p2_21_people.png`（名册）、`docs/p2_22_log.png`（案卷），已并入 `--shot-p2`。

| # | 项 | 落地位置 | 与本报告原方案的区别 |
|---|---|---|---|
| I1 | 人物名册 | `scenes/windows/PeopleWin.gd` 新增；`GraphState.met_char_ids()` / `char_progress()` / `char_talk_queue()` | 收录口径按 Web `metChars()` 三重并集（已登场节点 ∪ 到过时刻 ∪ 探索过的 `sceneTalks` 场景），**纸面提及不算**；常驻两人（TEC / 执行者）永远在册且排在前 |
| I2 | 因果追踪 | `scenes/windows/LogWin.gd` 新增；`GraphState.add_log()/clear_logs()/log_count()`；写入口统一走 `Desktop._log()` | 日志**不进快照**（撤销 / 读档不回滚），对应 Web「日志是 DOM 节点、重来或换案才清」；口径严格按 `03-utils.js:250-262`「只记结果」 |
| B1 | 图标栏 8 项 | `Desktop.ICON_DEFS` + `_build_icons()`，脱离 `VBoxContainer` 改绝对定位（18 / 16 / 步距 85，下限 70） | `assets/icons/users.svg`、`clipboard-list.svg` 由 `00-icons.js` 的 path 原样转出，与既有 8 个同格式 |
| B2 | 自由拖动 | `ui/DeskIcon.gd` 自管指针手势（5px 阈值内 = 点击，超出 = 拖动，夹在桌面内） | **不再用 `Button.pressed`**：Button 在「拖完松手」时也会发一次 `pressed`，吞不干净；改成单一 `clicked` 信号只给干净点击 |
| B3 | 四角标 | `_make_badge()` / `_set_badge()` / `_refresh_count_badges()` | 推演器 / 证物袋 / 线索册沿用 P0 的计数，日志角标走 `_log_unread`（窗关着才累加） |
| I3 | 名册点行 | `_on_people_row()` → `_goto_char()` / `_say_next_line()` | 点普通行 = 叫到镜头中央 + 选中 + 说下一句；`charTalkQueue` 补上了 `sceneTalks[homeScene]`（此前 Godot 只用 `talkQueue`，是隐性偏差） |
| C8 | 组合成功不弹条 | `_on_card_combo()` 成功分支只写案卷 | 对齐 `05-combine.js:155-160`：结果靠画面自证，「获得 / 消耗」并进同一条 `act` |

---

### 0.3 执行状态（2026-10-21 夜 · 批 2：幽灵线 / chip 带坐标已落地）

批 2 = 本报告剩的两条 P1（E2 + §6.3 的第 8 条）补齐验口，顺手把 chip 拖出的册**图标**入口也补上（Web `overLedgerDrop` 两条落点，原实现只认册窗）。

- **全套无头断言 1055 项 0 失败**（14 个脚本），`test_ui.gd` 67 → **79**（批 2 新增 12）。

| # | 项 | 落地位置 | 与本报告原方案的区别 |
|---|---|---|---|
| E2 | 拖动幽灵线 | `EdgeLayer.set_ghost() / clear_ghost()`，`Desktop._on_card_drag_moved()` 每帧喂指针、`_on_card_drag_finished()` 收线 | 画在连线层（**world 空间**），平移/缩放自动跟随，不做每帧屏幕坐标换算；样式照 E2：2px `#2b2b26` 虚线 6-5 @ 0.85，直线不走贝塞尔，最后画压在既有连线上 |
| §6.3 ⑧ | 桌布 chip → 画布（带坐标） | `MatrixWin` chip 拖出即 `clue_dropped(key, at_global)`；`Desktop._on_matrix_took()` 加可选 `at_global` —— 换算与 `_finish_sdrag` 同一条公式，卡片落在松手那一点并写回 `n.x / n.y` | Web 的 chip 取回**只有拖出一条路**（`finish` 里一律带 `e.clientX/e.clientY`，没有双击口）——Godot 额外保留**双击 = 无坐标取回**（沿承原「取下」按钮语义），拖出路径与 Web 同构 |
| overLedgerDrop | chip → 册窗**或册图标** = restash 进册 | `Desktop._on_matrix_dropped()` 两个落点都判（`icon_clue` 全局矩形） | 对齐 `12-panels.js:250` 的两条：窗开着算窗、图标任何时候都算（Godot 只认窗，图标本来不认） |

断言（已进 `test_ui`）：幽灵线出现 / 起点 = 被拖卡中心 / 终点 = 指针（world 换算）/ 松手收起；chip 拖出回画布落在松手点 + 坐标写回 `n.x/n.y`；chip 拖到册图标收进册。

---

### 0.4 执行状态（2026-10-21 夜 · 批 3：P2 细节批已落地）

批 3 = §3.3 P2 批次的尾巴一次收掉（N7 / N8 / V4 / V5 / V6 / D6 六项；D9 / E5 / L5 / L7 / C8 / I4 更早随 P0 / 批 1 落地）。

- **全套无头断言 1086 项 0 失败**（14 个脚本），`test_ui.gd` 79 → **110**（批 3 新增 31）。

| # | 项 | 落地位置 | 与本报告原方案的区别 |
|---|---|---|---|
| N7 | 场景命令 | `SceneDef.commands` 字段 + `tools/json_to_tres.gd` 场景命令映射；`ComboSystem.activate()` 吃 `kind=="loc"`；`Desktop._on_card_activated` 分支 = 场景带命令先跑 `commands[0]`，无命令回「展开 / 折叠」 | a001 数据 0/11 场景带命令 → `test_ui` 用**运行时注入**验证接线（注入后双击跑命令且不折叠；清掉后双击折叠） |
| N8 | hover / 光标 | `NodeCard.setup()` 接 `mouse_entered/exited` → `set_hover_state()`（shade_soft 7→10，原是死代码）；`mouse_default_cursor_shape = CURSOR_POINTING_HAND`；拖起全局 `CURSOR_DRAG`、松手归还 | |
| V4 | 入场 pop | `NodeCard.play_pop()`（scale .4→1.12→1 + 淡入，0.45s，照 Web keyframes）；`Desktop._spawn_card()` 对 `fresh` 节点弹一次 + `GraphState.consume_fresh()` —— **fresh / unread 分轨**（`unread`「新」角标要玩家点过才摘，与 Web `n.fresh` × `n.unread` 双轨一致） | `--shot` 模式里不弹（像素对拍要稳），fresh 照样消费（两次截图状态收敛） |
| V5 | warn 药丸 | `GraphState.is_no_entry()`：`kind=loc + 未探索 + [loc:] 文本入边 0（_loc_in 与 isHub 同一次遍历拆出入度）+ 命令产出通路 0（_route_scene 从 choice.options[].payload.scene、use-item 与 conditional 的 on_success.scene 枚举）+ 自己没出口（scene_locs 空）`；`NodeCard._warn_badge`（右上槽位与「新」同位、2px 墨边 + 卡底墨字，子节点序 warn 在前 ⇒ 「新」盖 warn，与 Web DOM 顺序一致） | 谓词随 hub 度数一起懒建；a001 里唯一命中的是 `SCENES_mdhm`，其余场景都带 [loc:] 通路或命令产出 |
| V6 | dim 0.32 | `NodeCard.set_dim()` 目标 alpha 0.25 → **0.32** | `test_ui` 锁了精确浮点断言 |
| D6 | 拖动镜像 | `NodeCard.build_mirror()` + `Desktop._mount_card_mirror / _sync_card_mirror / _drop_card_mirror`：拖起镜像挂桌布根（全部窗之上）、原卡隐藏，松手换身回来（可见性回读 `graph.visible_node`）；镜像吃不到输入（递归 `MOUSE_FILTER_IGNORE`） | **不能用 `duplicate()`**：脚本成员不跟着拷（探针实测 `_mat=null / card_key=""`），所以走 `setup()` 重画 + shell 态回灌；原卡隐藏期间连线照常以它为端点（`_repaint_edges` 给 `_drag_key` 开豁免，补 Web `visibility:hidden` + SVG 边照画的行为） |

断言（已进 `test_ui` 第 14–19 节）：warn 谓词三分（mdhm 真 / 枢纽假 / 命令产出假）+ 药丸挂摘 7 条；pop 初生 0.4 → 收尾 1.0 + 不透明 + fresh 消费 + unread 保留 6 条；hover shade 7↔10 + 手形光标 3 条；dim 0.32 精确断言 2 条；N7 注入往返 5 条；镜像挂桌 / 跟随 / 隐藏 / 退场 / 复位 / 坐标写回 8 条。

### 0.5 执行状态（2026-10-21 夜 · 批 4：剩余三项收口）

批 4 = README「没做」残余三项：① 反应表三条产出来源 ② 折叠 / 展开（重排）位置过渡 ③ 系统窗 z 序完整规则。批 3 之前这三条在 §3.3 里没有独立编号，按 Web 源码（`05-combine.js:112-123` / `04-nodes.css:3` / `05-apps.css`+`06-shell.css` z-index 表）补齐实现。

- **全套无头断言 1119 项 0 失败**（14 个脚本），`test_ui.gd` 110 → **143**（批 4 新增 33）。

| # | 项 | 落地位置 | 与本报告原方案的区别 |
|---|---|---|---|
| R1 | 反应表 `results` 三通道 | `ReactionDef.results: Dictionary` + `json_to_tres.gd` 原样透传 + `ComboSystem._apply_reaction()`：`results.scene` → 建场景节点 + 标 fresh/unread，**只在新建时**连 `cond` 边到 owner（对齐 Web `isNew` 判定）；`results.items` 与 `onSuccess.items` 同一批进 `spawnItems` 公式——已上画的物品显式 fresh=false 且不动位，新物品 `owner 右下 (60 + i*26)` 撒开 + `home_scene` 继承主人；正文 `[clue:]` 照旧建线索 | 命令侧的 `onSuccess.items` / choice `results.scene` 早已由 `CommandSystem._apply_payload` 接通（批 0 遗产），本批补的是反应表通道本身；a001 27 条反应全是纯文本，断言走运行时注入 |
| R2 | 重排位置过渡 | `Desktop._relayout(animated := false)`：普通重排秒到（无头回归与坐标语义建立在「重排=即刻就位」上，不能整体动）；**折叠 / 展开触发的那次重排**传 `_relayout(true)` → `_start_move_tween`（TRANS_CUBIC EASE_IN_OUT 0.34s，对齐 Web `.node{transition: left/top .34s cubic-bezier(.4,0,.2,1)}`）；动画期间 `_follow_frames` ≈420ms 每帧重画连线（对齐 `paintEdgesFor(420)`） | Web 是「每次 render 都过渡」，Godot 无头断言 / 坐标写回 / 拖放命中都依赖瞬时落位，所以动画**收窄到折叠 / 展开**这一处 + 测试显式 `_relayout(true)`；新节点与截图流水线照旧直接落位（Web 初绘无过渡来源，`--shot` 像素要稳） |
| R3 | 系统窗 z 序 | `ZR_*` 十二档常量（case 1 / pw 15 / narr 16 / log 21 / detail 22 / dock 23 / icons 24 / win 25 / chat 26 / tec 28 / toast 30 / mirror 40）+ `Desktop._place_z(ctrl, rank)`：插到第一个更高 rank 孩子之前、同级保持打开顺序（后开在上）；Desktop 内所有 `move_to_front()` 全部替换 | Web 静态 z-index 表 + DOM 顺序；Godot 没有 CSS，用 rank 插队等价——同 rank 新开窗口自然盖在旧窗口之上；`_place_z` 的索引要扣掉自身占位（踩过一次 move_child 位移坑，探针实测） |

断言（已进 `test_ui` 第 20–22 节）：过渡——折牌式重排补间挂上 / 动画在途 / 连线跟随窗口开 / 收尾到位与补间清空 6 条 + 新节点直接落位 1 条；反应表——运行时注入 A 桌面真拖（前提 2 + 新场景卡 / cond 边 / 物品卡 ×2 ⋯「新」角标 ×2 ⋯ 案卷含获得清单，共 10 条）+ 注入 B 直调数据层（前提 / fresh/unread、cond 边、`60 + i*26` 偏移 ×2、物品 fresh ×2、`[clue:]` 回归，共 9 条）；z 序——日志 < 地图 < TEC、icons 夹在中间、detail 介于 log 与 icons 之间、toast > TEC，共 7 条。

### 0.6 执行状态（2026-10-21 夜 · 批 4.5：手感三修）

实测跑起来暴露三处真机手感问题：**双击无法展开**（两下判不上）、**节点拖动卡顿**（起手与前 5px 跟动画打架）、**点窗撞翻层序**（批 4 rank 表被绕过）。三修如下：

- **F1 双击窗口 280→500ms**（`NodeCard.DBL_MS`）：原实现收紧到 280ms（「像素风节奏快」的预判），实机正常节奏的两下常被判成两次单击——浏览器 `dblclick` 默认 ~500ms，对齐它。
- **F2 按下冻结飞行卡**（`NodeCard._gui_input` press 分支 + 新信号 `pressed(key)` + `Desktop._on_card_pressed → _kill_move`）：批 4 的折叠 / 展开过渡（0.34s）导致卡片在动画中飞离指针——第二下 press 落不到卡上（双击丢失），按下到 5px 拖动阈值之间 `position` 还被补间拖着走（卡顿）。现在**按下即杀弹回弹簧**（`_spring.kill()`）**+ 通知 Desktop 杀掉落位补间**：卡冻结在指针下面，双击落准、拖起不再抢位。
- **F3 点击提层走 rank 表**（`SysWindow.raise_now` Callable + `Desktop._place_z` 统一接线 `_on_window_raise`）：`SysWindow` / `MemCard`（继承）标题栏按下原是就地 `move_to_front()`——窗是 `_desk` 直系孩子，一按就把窗顶到 icons / toast 之上，破坏批 4 层序。现在提层回调改走 `_place_z(自身 rank)` 重新插队（同 rank 归组尾 =「后来者在上」语义不变）；无 hook 时保留 `move_to_front()` 兜底。NodeCard 按下在 cards 层内 `move_to_front()`（对应 Web `.sel z-index:5`）、MatrixWin 种子弹层、EndingOverlay 自有顶层，均不受影响原地保留。

断言（已进 `test_ui` 第 23 节，6 条）：500ms 窗口内 350ms 间隔的第二下仍判双击 1；注入 `_relayout(true)` 后卡在飞行补间里（前提）→ 按下杀掉落位补间 1 + 200ms 后卡不再自漂 1；日志窗标题栏提层后仍在 icons 之下 1 + `zrank` 未变 1。**全套无头断言 1119 → 1125 项 0 失败（14 个脚本），`test_ui.gd` 143 → 149。**

### 0.7 修：拖动跟手断流（2026-10-21 · 现场反馈「是桌布在动，不是节点在动」）

**现象**：按在节点上拖，节点只挪一两像素就僵住；继续拖，整块画布跟着鼠标平移，节点像贴在原地。

**根因链**（三步，缺一不可）：

1. `Desktop._mount_card_mirror()` 是照 Web 的 `#drag-layer` 抄的：拖起时挂镜像卡、**原件 `visible = false`**。
   但 Godot 的 GUI 命中判定会跳过「树里不可见」的控件 —— 原件一隐，`mouse_focus` 就失效，
   **后续 `InputEventMouseMotion` 不再投递给这张卡**。`drag_moved` 只发了第一下（实测 `drag_moved` 调用 1 次）。
2. 卡片位置由 `_gui_input` 的 motion 驱动，事件断流 ⇒ 卡片与镜像一起冻住。
3. 松手事件同样投递不到卡上 ⇒ `_release_drop()` 从不执行 ⇒ `_drag_key` 一直挂着、镜像留在桌面上、坐标没写回。
   接着任何一次按下都落到画布手势层（`_on_stage_input`）⇒ `_panning = true` ⇒ **整个世界层跟着鼠标走**
   —— 玩家看到的就是「板子在动、那个节点不动」（残留的镜像恰好还停在原地）。

**修法**：

- `NodeCard.set_ghost(on)`：原件改用**全透明**（`modulate.a = 0`）而不是隐藏 —— 事件照收，画面交给镜像。
  与 `set_dim()` 共用一条 `_apply_alpha()` 合成，聚焦淡化不会把透明度抢回去；顺带在拖起时掐掉入场 `pop` 补间
  （它会把 `modulate.a` 渐补到 1，与让位打架，实测拖起瞬间原件还剩 `alpha = 0.68`）。
- `Desktop._card_key_at()` 跳过 `_drag_key`：原件现在可被命中，不排除自己就会被误判成「拖到别的节点上」。
- `Desktop._abort_card_drag()` + `NodeCard.cancel_drag()`：新一轮按下时若发现上一轮拖动会话没关，
  先按当前坐标落地并摘镜像，再决定要不要平移 —— 把「松手丢了」这条路的后果限死在一次操作内。

**桌布线索卡另有一处缺陷**（同一个用户反馈的「拖不动」）：`MatrixWin._on_chip_input` 只记 `_chip_moved = true`，
**从不移动 chip、也不出镜像**（Web 是 `makeMatrixNodeDraggable`：克隆到 `#drag-layer` 跟随指针，原件 `visibility:hidden`）。
现在补上：拖起时 `chip.duplicate()` 挂到 `drag_host`（Desktop 注入的 `_desk`，桌布自己 `clip_contents`，挂里面拖到边缘会被裁），
原件同样降透明度；桌布内松手 = 归位，拖出桌布才 `clue_dropped`；`refresh_matrix()` 重排前先 `_cancel_chip_drag()`。
⚠ `_chips` 的键是线索 id，信号里传的是 `clue:` 前缀的**节点键** —— 二者不能混，chip 实例直接随信号 bind 进去。

**断言**（`test_ui` 第 24 / 25 节，17 条）：这一节必须走**真实事件路由**（`root.push_input`）——
既有的拖拽用例都是直调 `card._gui_input(ev)`，绕过了命中判定与 `mouse_focus`，恰好绕开了这个 bug。
覆盖：镜像挂上 / 原件全透明 / 第二段与第三段 motion 仍跟手 / 松手清会话、镜像退场、透明度复原、坐标写回 /
残留会话的新按下只收尾不平移；桌布侧：出镜像 / 原件让位 / 镜像跟手 / 桌布内松手归位。
**全套 1125 → 1141 项 0 失败**（`test_ui` 149 → 166）。实证图：`docs/drag_fix_canvas.png`、`docs/drag_fix_matrix.png`。

---

### 0.8 修：互动即偏移 + 开局多一把手电筒（2026-10-21 · 现场反馈两条）

#### ① 每次跟节点互动，整块画布的卡都会「轻微」偏移

**根因**：`_relayout()` 无条件跑 `_layout_force()`（260 轮力导向）。而这套参数**不收敛** ——
同一批节点连跑 8 次，单次最大位移实测 **194 → 72 → 38 → 21 → 12 → 6.9 → 3.9 → 2.3 → 1.3px**（几何收敛，每次只吃掉一半差距）。
于是「每多跑一次重排，全画布就漂一次」：双击点亮手电筒 = `_apply_outcome()` 末尾一次 `_relayout()` ⇒ 8 张卡整体位移（最大 194px）。
Web 侧不是这样：`09-commands.js` 的注释把话说明白了 ——「开关灯只重绘（重排会让灯自己跳位置）」，
并且 `if (news.length) layout();`，**只有真长出节点的分支**才重排。

**修法**：给 `_relayout(animated, force)` 加「可见节点集合签名」闸门（`_layout_signature()`）。
集合没变 = 结构没变 = 一根手指都不动，只刷面包屑 / 页眉 / 连线；`force` 留给「用户显式要求现在就居中」（页眉开关）
与测试伪造数据位的场合。`_new_runtime()` 清空签名、`_rebuild_from_graph()` 就地认下存档的签名（读档 / 撤销后不许被下一次互动推走）。

修复前后（同一探针，开局展开花园 8 张卡）：

| 动作 | 修复前 | 修复后 |
|---|---|---|
| 双击手电筒点亮（纯状态） | 动 8/8，最大 **194.04px** | 动 **0/8**，0.00px |
| 连续 8 次普通重排 | 72 / 38 / 21 / 12 / 6.9 / 3.9 / 2.3 / 1.3px | 每次都 **0.00px** |
| 双击展开书桌（真结构变化） | 6.22px | 17.36px（≈Web 行为：结构变了就该重排） |

#### ② 开局画布上多出一把独立的手电筒

**确认属实**。Web `17-boot.js:42` 的开局只放**一个**「未探索」的起始场景节点
（`ensureSceneNode(START, {x:1000, y:620})`），手电筒在「花园 → 书桌 → 抽屉 → 左侧抽屉」这条链路的末端。
Godot 的 `_start_slice()` 当时为了切片省事，直接把 `ITEM_shoudiantong` 摆上画布并连了一条 `entity` 边，
顺带弹一句提示 —— 等于跳掉整个开场探索。

**修法**：`_start_slice()` 按 Web 口径只放起始场景（坐标也用 Web 的 1000/620），引导改成 Web 那两条 `log`
（`已载入案件 …` / `提示：先双击「植物学家花园」…`），删掉伪边与提示条。

**顺带挖出的第二层**：`CommandSystem._run_choice()` 用的是 `graph.reveal_scene()` ——
双击「抽屉」会把两个抽屉场景**当场展开并把里面的东西全倒出来**，两个抽屉还一出生就记成「已探索」。
Web `spawnChoiceNodes` 走的是 `ensureSceneNode` + `link(cond)`，**不 reveal**（`test_commands` 自己也是先 choice、
再手动 `reveal_scene` 才检查手电筒 —— 说明这条契约本来就该是这样）。改成只摆节点 + `cond` 边，
手电筒现在必须真的双击「左侧抽屉」才拿得到。

**断言**：`test_ui` 新增/改写 5 条（开局只有 1 张卡 / 展开花园没有手电筒 / 纯状态互动不挪任何卡 / 重新展开书桌手电筒回到画布），
`test_p15`、`test_p23` 改为自建工具节点。**全套 1141 → 1146 项 0 失败**。
实证图：`docs/start_state.png`（开局一张卡）、`docs/start_state_garden.png`（展开花园七个节点，无手电筒）。

**P3 起始页重拍**：对 Web 从 **2.30% → 1.79%**。差额全部来自左侧图标列 —— 上一版基线图拍在「人物 / 日志」两个图标入库之前，
现在两边都有这两个图标，差异反而小了；画布与窗框区域逐像素未变（`max diff = 0`）。

---

### 0.9 修：回忆放映卡压住节点（同一轮连带）

缩放 / 平移 / 重排都会让锚点节点在**屏幕上**换位置，而放映卡是按屏幕坐标摆的 ——
锚完就不管了，重排一次就压到别的节点上（实测 448×328 的卡盖住花园卡）。
修法：`_anchor_card_to()` 记住锚点键（`_mem_anchor_key`）；`_apply_view()` / `_relayout()` 收尾各重锚一次，
补间期间 `_process` 每帧重锚（只在那段时间，落地后就交给 tween 的 `finished`，免得跟玩家拖窗口打架）。

### 0.10 修：节点归属从正文里搬出来（2026-10-21 · 现场反馈「场景包含的节点不该由 content 控制」）

**症状**：在 Godot 检查器里润色 `SCENES_garden` 的正文、把 `[item:…]` 标签一并删掉之后，
展开花园一个实体节点都不长（`test_p0` 当场 11 项失败）。根子不是笔误，是**架构**：
`reveal_scene()` 拿 `case_def.tags_of(s.content)` 现推节点集合，正文与画布被焊在一起。

**改法**：`SceneDef` / `ItemDef` 各加四栏 —— `node_items` / `node_chars` / `node_locs` / `node_clues`，
在检查器里直接增删。`reveal_scene()` / `reveal_container()` / `spawn_mem_cast()` / `scene_locs()` /
`_scan_container_reaction()` / 回忆卡的在场人物全部改读这四栏，**正文只负责文字**
（`[item:X]` 标签仍用于把名字显示成物品名，`plain()` 那一路不动）。

**为什么存 id 不存资源引用**（踩过的坑）：第一版写成 `Array[ItemDef]` / `Array[SceneDef]`，
检查器里能点选资源、看着很对，但 `.tres` **一存就炸** —— 场景 → 物品 → 命令 → 场景 本身就是环
（`SCENES_lhsdst` ↔ `ITEMS_bd`、`SCENES_fkjl` ↔ `SCENES_0602`）。Godot 解析文本资源时撞到
「正在加载中」的目标会直接报 `[ext_resource] referenced non-existent resource`，
`case.tres` 整个加载失败（`不是 CaseDef`）。`node_chars` 同理（人物 `debut` 指回场景）。
所以四栏一律是 `PackedStringArray` 的 id，是纯数据，没有环。

**顺带**：`CaseLoader.validate_nodes()` 在装载时把解析不到的 id 打进输出面板
（手打 id 敲错一个字母是最容易犯的错），迁移工具 `tools/migrate_node_lists.gd`
把正文标签一次性冻结成清单（幂等，只覆盖那四栏）。
日常编辑走 `addons/case_nodes/` 插件：检查器里每栏只有一行摘要（`物品 · 6 项` + 「编辑…」），
点开弹窗后「＋ 添加」挑资源、或直接把资源拖进列表，可调序 / 解绑 / 失效标红。
检查器里只放一行是刻意的 —— 它每次刷新都会重建属性控件，把列表画在那里会卡。

**迁移口径**：13 个容器（11 场景 + 书桌 + 垃圾桶）按 JSON 档案里的标签冻结；
`CHARS_TEC` 不进清单（常驻对话方，本来就不上画布）。`_scan_container_reaction()` 原先读容器原文标签，
现在与画布同源，正文改写后组合反应照样命中。

---

### 0.11 复核：批 2 交互四项（N5 / V1-V3 / C4）早已落地，本轮补验口（2026-10-23）

**结论先行**：这四项在 `5fff486`（「交互层批 1 + 批 2」）就已随代码入库并推送，
但 §1 差异总表是**检查当时的快照**、§7 记分板也没给它们单独记账，
看上去像「还没做」。本轮只补**界面级验口**与口径，不改实现。

| # | 项 | 实现位置 | 本轮断言 |
|---|---|---|---|
| N5 | 线索双击捕获 | `Desktop._on_card_activated` → `_capture_clue_node()`：`graph.capture_clue` + 案卷 `cap` + 重复双击只留一条 warn，**不弹提示条** | 双击进 `captured` / 案卷记「已捕获线索」/ 不弹条；重复双击不重复记、案卷留「已经捕获过了」 |
| V1 | 选中态 | `NodeCard.set_selected()` + `_sel`（`DashBorder.sel_line`，2px `#2b2b26`、外扩 2px）；`Desktop._apply_focus()` 逐卡回填 | 单击出环 / 换选后新卡带环、旧卡收环 |
| V2 | 点亮态 | `_apply_lit_look()`：金框 `#e3b341` + 暖白底 `#fffbeb` + 双层光晕；`look_state()` 供断言读态 | 金框 / 暖白底 / 光晕打开 / 熄灯收回 |
| V3 | 已捕获 | `_apply_got_look()`：深反白 `#38372f → #1f1f19` + 1px 白边，虚线框让位 | 上缘 / 下缘取色 + 边框收起 |
| C4 | 场景⇄场景通路 | `ComboSystem.use_item()` ⓪ 分支：`scene_locs()` 命中 → `travel`；两场景互不列 → `no_tried` + 「这两个场景之间没有直接通路」；`Desktop._on_card_combo()` 分派 `travel` → 案卷 `act` + `_expand_scene` | 书桌 / 尸体正文 `[loc:garden]` → 前往；0602 ⇄ 尸体 → 无通路且不画 tried；界面层验证展开 + 记 act + 不弹条 |

**新增回归**：`tests/headless/test_p27.gd` **39 项**（N5 + V3 共 14 条 / V1 4 条 / V2 9 条 / C4 数据层 6 条 / C4 界面分派 6 条）。
全套无头 **15 个脚本 1250 项 0 失败**。

**写测试时踩到的坑**：`SCENES_0602` 是**时间类场景**，`dbg_ensure("loc", "SCENES_0602")` 造出来的节点 key 是
`time:SCENES_0602`；手写 `loc:SCENES_0602` 去调 `_on_card_combo` 会拿到空节点、静默什么都不做
（`use_item` 提前 `{"ok": false, "message": ""}`）。造节点后一律用 `dbg_ensure` 的返回值当 key。

---

## 1. 差异总表

> 本节是**检查当时**的现状快照（保留原文），落地后的复核值看 §7 记分板与 §0.1–§0.11 执行状态。

### 1.1 节点语义（N）

| # | 差异项 | Web | Godot 现状 | 级别 | 证据 |
|---|---|---|---|---|---|
| N1 | **单击 = 激活** | 单击只选中并刷详情窗；`dblclick` 才展开/跑命令 | 松手未位移就直接 `activated.emit()` ⇒ **单击场景即展开** | **P0** | `08-interact.js:128,192` / `NodeCard.gd:232` |
| N2 | 选中时机 | `pointerup` 且未移动才 `selectNode` | `pointerdown` 当刻就 `selected.emit()` ⇒ 拖动中全场已淡化 | P1 | `08-interact.js:33,128` / `NodeCard.gd:219` |
| N3 | 右键钉住 | 右键 = 唯一钉住入口，节点挂「已固定」角标，钉住后自动布局不挪它、折叠不收它 | 无右键处理；`pinned` 字段在 `add_node` 里、`recompute_hidden` 也读，但**没有任何 UI 能置位** | **P0** | `08-interact.js:209`、`07-render.js:140` / `NodeCard.gd:210`、`GraphState.gd:106` |
| N4 | 节点详情窗 | 常驻 `detail-win`：简介 / 状态 / 来源 + 「重看叙事」「重看对话」「播放独白」「播放音乐」 | **完全没有**。单击只留下一个 `_selected`，玩家读不到任何文本 | **P0** | `14-detail.js:18` / 全工程 grep `detail` 无命中 |
| N5 | 线索双击 | 捕获：`captured.add` + 日志 + 重绘 | `activate()` 只认 `kind=="item"`，线索双击无反应 | P1 | `08-interact.js:346` / `ComboSystem.gd:73` |
| N6 | 人物双击 | 说下一句（`showCharLine`，推进 talkQueue） | 只尝试播独白；无独白则什么都不发生 | P1 | `08-interact.js:353` / `Desktop.gd:1522` |
| N7 | 场景命令 | 有 `commands` 先跑第一条，没有才展开 | 直接 `_toggle_container`，跳过 commands（当前数据 0/11 场景有命令，暂无症状） | P2 | `08-interact.js:196` / `Desktop.gd:1512` |
| N8 | 悬停 / 光标 | `:hover` 阴影放大一档；`cursor:grab/grabbing` | `set_hover_state()` **定义了但从未被调用**；无 cursor 设置 | P2 | `04-nodes.css:9` / `NodeCard.gd:269` |

### 1.2 连线（E）

| # | 差异项 | Web | Godot 现状 | 级别 | 证据 |
|---|---|---|---|---|---|
| E1 | **画布连线** | SVG 二次贝塞尔，中点抬升 `min(70, |dx|×0.16)`；四种边各有样式：entity 1.3px `#8a8672` / move 1.6px 墨 / cond 1.6px 虚线 5-4 / tried 1px `#b8b49e` 虚线 3-4 半透明 | **一条都不画**。`edges` 只活在数据层（存档、hub 统计、聚焦淡化用），画布上一个像素都没有 | **P0** | `07-render.js:179-200` / 全工程 grep `draw_line` `Line2D` 无命中 |
| E2 | 拖动幽灵线 | 拖起即画一条虚线（6-5，2px，`.85`）从中心追到光标 | 无 | P1 | `08-interact.js:63` |
| E3 | 连线跟随 | 节点有位移动画时每 40ms 重画，回弹时同一帧重画，避免"线断开" | 无所谓（无连线） | — | `07-render.js:203`、`212` |
| E4 | 聚焦淡化连线 | 与选中无关的边 `opacity .12` | 无 | P1 | `07-render.js:196` |
| E5 | 辉光层 | `#glow` 560×560 径向渐变，点亮光源时挂在节点上 | 无（`lit` 状态只有副标题一个词） | P1 | `04-nodes.css:46` |

### 1.3 拖动与落点（D）

| # | 差异项 | Web | Godot 现状 | 级别 | 证据 |
|---|---|---|---|---|---|
| D1 | **桌面图标落点** | **11 个元素**（10 个 id + 桌布，详见 §6.2）：对话窗 / 袋窗 / 册窗 / 袋图标 / 册图标 / TEC 图标 / 推演器图标 / 档案图标 / TEC 头像 / TEC 收起卡片 / 推演桌布 | 元素 **5/11**、动作 **3/6**：对话窗 / 桌布 / TEC（图标+头像+收起卡共用一个判定）。**「拖节点进证物袋 / 线索册 / 推演器图标 / 档案图标」四个动作全缺**（`bag_store` 只有 `dbg_store` 会调） | **P0** | `08-interact.js:117-145` / `Desktop.gd:1494-1505` / **§6** |
| D2 | 拖进收纳窗 | 袋窗 / 册窗开着时本身也是落点 | `StorageWin` 只有 `take`（取回）按钮，**不接受拖入**（无 `_can_drop_data` / 无指针手势） | **P0** | `11-dialog.js:508` / `StorageWin.gd:60-92` |
| D3 | 拖到折叠容器 | 明确提示「场景已折叠：先双击展开，或把节点拖到证物袋」 | 落在 loc 上什么都不说 | P2 | `08-interact.js:167` |
| D4 | 松手回原位 | `springBack` 300ms 三次缓出，节点带线一起弹回 | 停在目标位置上，紧接着 `_relayout()` 又跳走 | P1 | `08-interact.js:132,163` |
| D5 | 落点高亮 | 目标节点 `.over` 反白 + `scale(1.06)` + 墨色描边；图标 `.over` | 无 | P1 | `04-nodes.css:19` |
| D6 | 拖动镜像 | 复制一份到顶层 `#drag-layer`，避免被窗口压住 | 只 `move_to_front()`，拖到案件窗外仍会被裁 | P2 | `07-render.js:271` |
| D7 | 边界夹回 | `x∈[60,1780]`、`y∈[50,1180]` | 无夹回；`_stage.clip_contents=true` ⇒ **拖出去就看不见了** | P1 | `08-interact.js:178` / `Desktop.gd:471` |
| D8 | 命中排除隐藏卡 | `hitTest` 排除自身；`visibleNode` 过滤 | `_card_under` 遍历全部子节点，**不检查 `visible`** ⇒ 可能拖到看不见的卡上 | P1（bug） | `NodeCard.gd:249` |
| D9 | 落点互斥 | 图标命中 → `return`，不再判组合 | 先 `drag_released`（对话/桌布/TEC）再 `combo_requested`，**两件事都会做** | P2 | `NodeCard.gd:225-229` |
| D10 | **位置写回数据** | 松手写 `n.x/n.y`，进快照、进存档 | **从不写回**。`graph.nodes[key].x/y` 永远是 `add_node` 给的 `0.0`；拖动只改 `card.position` | **P0** | `08-interact.js:177` / `GraphState.gd:102-103` |
| D11 | 拖动进撤销栈 | Web 拖动本身不入栈（只改位置） | 同样不入栈（与 Web 一致），但配合 D10 等于"什么都没留" | — | — |

### 1.4 布局与视角（L）

| # | 差异项 | Web | Godot 现状 | 级别 | 证据 |
|---|---|---|---|---|---|
| L1 | **布局算法** | 力导向：斥力 `30000/d²`、最小间距 `R_a+R_b+14`、弹簧 rest 185/300/150、向心 0.0022，260 轮；容器按网格播种 | **固定网格**：`x = 26 + (i%4)×178`、`y = 20 + (i/4)×78`，17 处调用点每次都全量归位 ⇒ **玩家摆好的位置必然被推翻** | **P0** | `07-render.js:3-60` / `Desktop.gd:2231-2258` |
| L2 | 「适应窗口」 | 只动镜头（`fit()`） | `_relayout()` + `_fit_cards()` ⇒ **按一下就把所有节点重排** | P1 | `15-desktop.js:157` / `Desktop.gd:408` |
| L3 | 滚轮缩放 | 0.35~1.8，以光标为锚，窗口上滚轮例外 | 无 | **P0** | `15-desktop.js:18-31` / `_stage` 无 `_gui_input` |
| L4 | 拖空白平移 | `stage.pointerdown` → 平移，`grabbing` 光标 | 无 | **P0** | `15-desktop.js:4-16` |
| L5 | 点空白 | 清选中（详情窗回占位） | 不清 | P2 | `15-desktop.js:9` |
| L6 | 新节点聚焦 | `focusFresh`：只把**新节点**带到视野中央，不改缩放 | `_fit_cards()`：缩到装下**全部**节点。开关语义 = 是否 fit 全图 | P1 | `08-interact.js:320` / `Desktop.gd:2255` |
| L7 | 世界边界 | 2000×1300 有界工作区 | 无 world 概念，`_card_layer` 就是视口大小 | P2 | `07-render.js:6` |

### 1.5 视觉状态（V）

| # | 差异项 | Web | Godot 现状 | 级别 | 证据 |
|---|---|---|---|---|---|
| V1 | 选中态 | `.sel{outline:2px #2b2b26; offset 2px; z-index 5}` | 无；只能靠"别的卡变淡"反推 | P1 | `04-nodes.css:13` / `NodeCard.gd` 无 sel |
| V2 | 点亮态 | `.lit` 金色边框 `#e3b341` + 双层辉光 + `#glow` 光斑 | 副标题写「物品 · 亮着」，视觉无变化 | P1 | `04-nodes.css:45` / `NodeCard.gd:166` |
| V3 | 已捕获线索 | `.got` 深色反白（`#38372f` 渐变 + inset 阴影） | 副标题写「线索 · 已捕获」 | P1 | `04-nodes.css:42` / `NodeCard.gd:168` |
| V4 | 新节点入场 | `.pop` 0.45s：`scale .4 → 1.12 → 1` | 无动画，直接出现 | P2 | `04-nodes.css:15` |
| V5 | 「无文本入口」角标 | 未探索 + 零入边 + 无条件路由 + 无出口 ⇒ 挂 warn 药丸 | 无 | P2 | `07-render.js:134` |
| V6 | 淡化强度 | `.dim{opacity:.32}` | `modulate.a = 0.25` | P2 | `04-nodes.css:14` / `NodeCard.gd:279` |

### 1.6 组合逻辑（C）

| # | 差异项 | Web | Godot 现状 | 级别 | 证据 |
|---|---|---|---|---|---|
| C1 | **反应表** | `lookupReaction` 先查目标、再反向查工具；命中即出文本 + 结果 | `ComboSystem.use_item` 只查 `useItem` 命令。数据里 **14 条反应（朱穗 6 / 陆珩松 4 / TEC 4）全部不可达** —— 把物品拖给人只会得到「没有发生任何事」 | **P0** | `05-combine.js:52-59` / `ComboSystem.gd:46-67`、`CaseLoader` 不读 reaction |
| C2 | 反向 owner | 工具自身是反应表宿主时也算命中 | 无 | P1 | `05-combine.js:56` |
| C3 | 容器内扫描 | 目标是容器时，扫它装着的对象有没有反应 | 无 | P1 | `05-combine.js:81-92` |
| C4 | 场景⇄场景 | 文本里有 `[loc:X]` 即"前往"；没有通路则明说「这两个场景之间没有直接通路」 | 两条都没有。拖场景到场景 = 「没有发生任何事」 | P1 | `05-combine.js:15,39` |
| C5 | 失败留痕 | `G.tried.add` + 画 `tried` 虚线边（"试过了"看得见） | 不记、不画 ⇒ 面包屑「已试组合」几乎不动 | P1 | `05-combine.js:95-97` / `Desktop.gd:1868` |
| C6 | 成功后聚焦 | `settle()` 把新长出的节点带进视野 | 只 `_relayout()` | P1 | `05-combine.js:164` |
| C7 | 消耗范围 | 工具（非可复用）+ 目标 / owner 都可能被消耗 | 只消耗工具（`_run_use_item`） | P1 | `05-combine.js:143-151` / `CommandSystem.gd:150` |
| C8 | 成功不弹提示 | 刻意不弹 toast，结果只进日志 —— 画面自证 | 每次都弹 toast ⇒ 屏幕被"已知信息"打断 | P2 | `05-combine.js:155-160` / `Desktop.gd:1858` |

### 1.7 信息反馈（I）

| # | 差异项 | Web | Godot 现状 | 级别 | 证据 |
|---|---|---|---|---|---|
| I1 | 因果追踪窗 | `#log-win`「SYS_LOGS // 因果追踪」，组合结果 / 失败原因全在里面 | 无。所有信息只 flash 一下 toast，转身就没了 | P1 | `shell.html` / 无 log 窗 |
| I2 | 人物名册 | `people-win`：`ROSTER_PINNED` + 登场门控 + 进度 + 首字方块 | 无 | P1 | `12-panels.js` / 无 |
| I3 | 图标栏 | 8 个（推演/档案/线索册/人物/证物袋/TEC/日志/地图），**双击打开**、单击选中、可拖动 | 6 个（缺人物、日志），`VBoxContainer` 固定竖排，**单击即开** | P1 | `15-desktop.js:106,100` / `Desktop.gd:492,516` |
| I4 | 叙事卡位置 | 锚在节点上方/下方，按当前视口做防裁钳制 | 固定 `(700, 290)` | P2 | `08-interact.js` / `Desktop.gd:1902` |

---

## 2. 这几条最伤体验（按"玩家第一次上手会怎么想"排序）

1. **点一下就展开了**（N1）——玩家的预期是"点一下看看这是什么"。现在点一下场景就直接摊开、
   点一下手电筒就开关灯，想只选中都没门。这是所有别扭感的源头。
2. **摆好的位置每次都被收走**（L1 + D10）——拖到哪里，下一次任何操作（展开、组合、收纳、
   撤销、甚至按"适应窗口"）就全部回到 4 列网格。玩家会得出"这游戏不让我摆"。
3. **什么都看不见关系**（E1）——Web 里一眼能看出"花园连着树、树连着尸体、这根虚线是我试过的"；
   Godot 里是 33 张孤立卡片。**整个案件的空间结构信息为零**。
4. **没有详情窗**（N4）——单击得不到任何文字。物品描述、线索内容、人物状态、重看入口，
   全在 Web 的 `detail-win` 里，Godot 一个字都没搬。
5. **把东西给人看没人理**（C1）——14 条反应表在数据里躺着，引擎不查。这是"拖放玩法"的主干。
6. **装不进袋子**（D1/D2）——证物袋 / 线索册只能开窗看，收不进去也拿不出来（`take` 需要行上有内容）。

---

## 3. 建议方案

### 3.1 P0 批次：让画布"能用"（8 项改动，必须先做）

**① 画布重构：世界层 + 边层 + 手势层**（新文件，约 500 行）

```
ydgodot/scenes/canvas/CanvasWorld.gd   # 世界坐标容器（2000×1300），含 card_layer + edge_layer
ydgodot/scenes/canvas/EdgeLayer.gd     # 连线绘制（Node2D._draw，贝塞尔 + 四种样式）
ydgodot/scenes/canvas/CanvasInput.gd   # 平移 / 滚轮缩放 / 点空白清选中
```

- `EdgeLayer` 用 `draw_polyline` 采样 24 段二次贝塞尔（Godot 无 SVG path）；端点取
  `card.position + Vector2(PAD, PAD) + card.inner_size/2`（**注意坐标基准，见 §4.1**）。
- 样式表照抄 `04-nodes.css` 的四种边：颜色、线宽、虚线节奏 `5-4` / `3-4`。
- 缩放范围 0.35~1.8、以光标为锚（`view.x = mx - (mx-view.x)*(k2/k)` 同一公式）；
  平移用 `_card_layer` 的 `position`，不要动 `global_position`。
- 触发重绘的时机：节点移动（每帧）/ 图结构变化 / 缩放平移 / 淡化变化。
  Godot 里没有 CSS 过渡，节点位置是离散的，不需要 Web 那套 40ms 补画与同帧 springBack，
  但**拖动过程中**必须每帧重画（`_process` 里 `if _dragging: edge_layer.queue_redraw()`）。

**② 单击/双击分离**（`NodeCard._gui_input`，约 30 行）

- 按下：只记 `_press`、`move_to_front()`，**不 emit selected**。
- 松手且未位移：`selected.emit()`（选中 + 刷详情），并启动 250ms 双击窗口。
- 250ms 内第二次按下：`activated.emit()`，取消第一下。
- 位移超阈值：进入拖动，`selected.emit()` 放在**拖动开始时**（Web 拖动不改选中，但拖动中
  目标节点需要可读，建议拖动开始也选中，这一点与 Web 有意偏离，需你拍板）。

**③ 位置写回 + 撤销**（`Desktop._on_card_drag_*`，约 20 行）

- 松手：`n["x"] = card.position.x`、`n["y"] = ...`，夹回 world 边界，`_commit()`。
- 拖动起点位置要单独存一份，供 D4 的回弹用。

**④ 力导向布局替代网格**（`Desktop._relayout` 重写，约 80 行）

照搬 `07-render.js` 的参数表，但**每张卡的外框比视觉框大 16px**（`PAD*2`），
碰撞半径要用 `R = 视觉半径 + 8`，否则间距会比 Web 紧。

关键：`seed()` 只对"从没有过坐标"的节点赋值（`x == null`），已有坐标保留；
力导向只在**结构变化**时跑，玩家拖动后不跑全量。

**⑤ 右键钉住 + 角标**（约 25 行）

`NodeCard` 加 `_gui_input` 的 `MOUSE_BUTTON_RIGHT` → `pinned.toggled`；`_apply_shell` 在
`_pinned` 时把右上角 badge 换成「已固定」（Web 是独立 `.badge.pin` 药丸，位置在左上角，
两枚角标不共存时按 Web 处理：pin 左上、new 右上）。

**⑥ 拖进证物袋 / 线索册**（`Desktop._on_card_drag_released` + `StorageWin`，约 60 行）

- 图标命中：`icon_bag` / `icon_clue` / `icon_goto` / `icon_infer` 四个矩形。
- 窗口命中：`_bag_win.get_global_rect().has_point(at)` → `graph.bag_store(key)`。
- 线索册拒收非线索时要有反馈（Web 是 toast「只有线索能进线索册」）。

**⑦ 反应表通道**（`ComboSystem.use_item` 扩展，约 70 行）

按 Web 的四段顺序重写：
`目标反应表 → 工具反应表 → useItem 命令 → 容器内扫描`，命中结果统一成
`{ok, message, reveal, captured, consumed, owner}`，让 `Desktop._on_card_combo` 只有一条收尾路径。

`CaseLoader` 需要把 `ReactionDef` 读进 `CharDef.item_reactions`（目前 `.tres` 里已有数据，
只是没有 getter）。

**⑧ 节点详情窗**（新文件 `DetailWin.gd`，约 180 行）

按 `14-detail.js` 的三种内容做：简介 / 状态 / 来源，**刻意不列**"装着什么""谁指向它""它跟谁有反应"。
状态行要照抄那套组合规则（光线、点亮、已装零件、待装零件、已捕获 + 感官、已聊完、来源）。
底部按钮：重看叙事 / 重看对话 / 播放独白 / 播放音乐。

### 3.2 P1 批次：把"手感"补齐

| 项 | 做法 | 改动面 |
|---|---|---|
| N2 选中时机 | 随 ② 一起改 | NodeCard |
| N5 线索双击捕获 | `activated` 分支加 `kind=="clue"` → `graph.capture_clue` + 日志 | Desktop 10 行 |
| N6 人物双击说话 | 接 `DialogueSystem.talk_next()`（talkQueue 已有数据） | Desktop 20 行 |
| D3 折叠容器提示 | 落点在折叠容器上先判 `is_collapsed` | Desktop 8 行 |
| D4 回弹 | 拖动起点的 tween 回弹，边层同步 | NodeCard + EdgeLayer |
| D5 落点高亮 | `_card_under` 命中时给目标卡 `set_over(true)`（反白 + 1.06 缩放） | NodeCard 20 行 |
| D7 边界夹回 | 松手 clamp 到 world 矩形 | Desktop 6 行 |
| D8 隐藏卡排除 | `_card_under` 加 `if not c.visible: continue` | 1 行（bug fix） |
| L2 适应窗口只 fit | `_fit_view` 去掉 `_relayout()` | 1 行 |
| L6 新节点聚焦 | `_relayout` 收尾改成"只平移镜头到新节点包围盒中心"，不缩放 | Desktop 40 行 |
| C2/C3 反向 + 容器扫描 | 属 ⑦ 的一部分 | ComboSystem |
| C4 场景通路 | `scene_locs()` 已有，补"前往"分支 + "没有直接通路"提示 | ComboSystem 25 行 |
| C5 tried 留痕 | 失败时 `graph.tried[k]=true` + `link(...,"tried")` | 3 行 |
| C6 成功后聚焦 | 复用 L6 | — |
| C7 消耗范围 | 补 target / owner 消耗，`is_reusable_tool` 已有 | 20 行 |
| V1 选中描边 | `DashBorder` 加 `sel_line` 模式（外扩 2px 的 2px 实线） | NodeCard 15 行 |
| V2/V3 lit/got | `_apply_shell` 加两套配色（金框 + 辉光 / 深反白） | NodeCard 40 行 |
| E2/E4 幽灵线 + 淡化 | EdgeLayer 加 `ghost` 与 `dim_keys` | EdgeLayer 40 行 |
| I1 日志窗 | `LogWin.gd` + `graph.logs` 数组（进快照） | 新文件 150 行 |
| I2 人物名册 | `PeopleWin.gd`，48×48 头像（沿用 P3 已定的名册规格） | 新文件 200 行 |
| I3 图标栏补齐 | 补 2 个图标 + 双击开 + 选中态；`VBox` 改自由摆放 | Desktop 60 行 |

### 3.3 P2 批次：口径与细节

N7 场景命令、N8 hover/cursor、D6 镜像层、D9 落点互斥、E5 glow、L5 点空白清选中、
L7 world 边界、V4 pop 动画、V5 warn 角标、V6 dim 改 0.32、C8 成功不弹 toast、
I4 叙事卡锚定。

（后注：N7 / N8 / V4 / V5 / V6 / D6 已随批 3 落地，见 §0.4；D9 / E5 / L5 / L7 / C8 / I4 更早随 P0 / 批 1 落地。剩余三项（反应表产物 / 折叠过渡 / z 序）已随批 4 落地，见 §0.5；实机手感三修（双击窗口 500ms / 按下冻结飞行卡 / 点击提层走 rank）见 §0.6。）

---

## 4. 落地前必须先统一的三件事

### 4.1 坐标基准（最容易埋雷）

- **Web**：`n.x/n.y` = 卡片**视觉框**左上角；`NODE_W.loc = 152`。
- **Godot**：`card.position` = **含 8px 阴影余量的外框**左上角，视觉框在 `+PAD`；
  `card.size = 视觉尺寸 + 16`。

⇒ 力导向、连线端点、聚焦包围盒、落点命中，**四处都必须用同一套换算**：
`visual_rect = Rect2(card.position + Vector2(PAD, PAD), card.size - Vector2(PAD*2, PAD*2))`。
建议在 `NodeCard` 上加 `func visual_rect() -> Rect2`，全工程只调它，禁止各自手算。

（P3 对拍能对齐，正是因为两侧视觉框落在同一像素上；换成"算布局"就会差 8px。）

### 4.2 「重排」这件事的语义

Web 里 `layout()` 是**松弛一次**，不是在重新排版；玩家拖过的位置大体保留。
Godot 现在 17 处 `_relayout()` 等于 17 个"全部归位"按钮。改造原则：

- 结构变化（展开 / 组合产出 / 收纳取回）→ 跑力导向；
- 纯状态变化（点亮 / 捕获 / 选中 / 缩放）→ **只重绘，不动坐标**；
- 玩家手动拖动 → 不跑布局（除非该节点被"新节点自动居中"带着一起）。

### 4.3 数据层已就绪、只差通道的清单（性价比最高）

| 数据 | 位置 | 缺什么 |
|---|---|---|
| 14 条反应表 | `cases/a001/chars/*.tres` 的 `item_reactions` | `CaseLoader` 读取 + `ComboSystem` 查询 |
| tried 边 | `GraphState.tried` / `edges{rel:"tried"}` | 失败时写 + 画（画布目前不画线） |
| pinned | `GraphState.add_node` + `recompute_hidden` | 右键入口 + 角标 |
| 收纳 API | `bag_store` / `ledger_store` / `take_back` / `restash` | 拖放落点 |
| 场景通路 | `scene_locs()` | "前往"分支 |

---

## 5. 建议的验收方式

不要再用"肉眼看对不对"，这批都应该落成**无头断言**（现有 13 个测试脚本 931 项的模式）：

1. **语义断言**：`dbg_click_once(key)` 后场景**未**展开、`dbg_double_click(key)` 后才 `explored`；
2. **位置断言**：拖动 `card.position` 后 `graph.node(key).x` 变了，且下一次 `_relayout` 后
   位移不超过 40px（力导向松弛量），而不是回到网格点；
3. **连线断言**：`edge_layer.segment_count()` 与 `graph.edges` 中可见节点对的数量一致；
   拖两个节点上再松手，`tried` 边 +1；
4. **反应表断言**：`dbg_combo("ITEMS_changji","CHARS_zs")` 返回文本非空（当前是「没有发生任何事」）；
5. **收纳断言**：`dbg_drag_to_icon(key, "bag")` 后 `stored[key] == "BAG"`；
6. **视角断言**：`dbg_zoom(1.2)` 后 `_view_k == 1.2` 且锚点世界坐标不变。

对拍（P3 那套）继续只用来守"静态构图"，交互层用上面这组断言守行为 —— 两者的 ROI 差得很远。

---

## 6. 附录 · 落点专项（2026-10-21 补检）

> 触发：用户指出「拖动节点到各个图标和弹窗的功能目前也是缺失」。逐行复核后确认属实，
> 且比 §1.3 记的更严重 —— §1.3 把 Web 落点写成「6 个」，实际是 **10 个元素 + 桌布**。

### 6.1 数据层其实全都在，缺的只是入口

`GraphState` 的四件套是完整且与 Web 同口径的（连注释都对齐了）：

| 方法 | 行 | 语义 | 谁在调 |
|---|---|---|---|
| `bag_store(key)` | `GraphState.gd:484` | 什么都收（容器除外），记 `bag_from` | **只有 `dbg_store`** |
| `ledger_store(key)` | `:496` | 只收 clue | **只有 `dbg_store`** |
| `take_back(key, x, y)` | `:509` | 取回，**坐标可选** | `StorageWin._take`（不带坐标） |
| `restash(key, from, to)` | `:526` | 袋↔册搬运 | `_on_matrix_dropped`（只 matrix→ledger） |
| `matrix_assign(key, sense)` | `:548` | 归位桌布 | `_assign_to_matrix` ✅ |

⇒ 结论：**这批活不需要写业务逻辑，只需要把 UI 手势接到已有方法上。**
（`dbg_store` 是测试钩子，`Desktop.gd:1775` 注释写着「供测试钩子 / 后续接线用」—— 一直没接。）

#### 由此推出的一个硬结论：两扇收纳窗在正常游玩里几乎是空的

`stored` 字典的全部写入点只有四处：`bag_store` / `ledger_store`（**只有 `dbg_store` 调**）、
`matrix_assign`（`_assign_to_matrix` 调）、`restash`（`_on_matrix_dropped` 调）、`store()`（无调用者）。
于是实际能装进去的东西只有：

- **证物袋：永远是空的** —— 没有任何手势能走到 `bag_store`；
- **线索册：只能收到「从推演桌布拖过来的线索」** —— 这是唯一入口（`_on_matrix_dropped`）；
  从画布直接拖线索到册图标 / 册窗都不认。

玩家点开这两扇窗看到「（空）」，会直接判定「这两个功能没做」。

### 6.2 正向：节点 → 落点（11 个元素）

Web 的清单在 `11-dialog.js:505-513`，**数组顺序即命中优先级**；
桌布另在 `08-interact.js:148` 独立判定。Godot 只有一个 `_on_card_drag_released`（`Desktop.gd:1494`）。

| # | Web 落点 id | 松手动作 | Web 行 | Godot | 备注 |
|---|---|---|---|---|---|
| 1 | `chat-win` | `chatDrop` → 人物加入对话 | `08:133` | ✅ `_chat_drop_hit` | 对话窗开着才算 |
| 2 | `bag-win` | `bagStore` | `08:134` | ❌ | 袋窗开着才算 |
| 3 | `clue-win` | `ledgerStore` | `08:135` | ❌ | 册窗开着才算 |
| 4 | `bag-dock` | `bagStore` | `08:134` | ❌ | 证物袋图标 |
| 5 | `clue-icon` | `ledgerStore` | `08:135` | ❌ | 线索册图标 |
| 6 | `tec-dock` | `tecAnalyze` | `08:136` | ✅ `_tec_drop_hit` | |
| 7 | `infer-icon` | `assignClue`（仅 clue） | `08:137` | ❌ | **桌布能收、图标不能** |
| 8 | `goto-icon` | `gotoScene`（仅场景） | `08:140` | ❌ | 前往并居中选中 |
| 9 | `tec-avatar` | `tecAnalyze` | `08:136` | ✅ 同一函数 | |
| 10 | `tec-chip` | `tecAnalyze` | `08:136` | ✅ 同一函数 | `tecChipOn` 才在表里 |
| 11 | `mx-board` | `assignClue` | `08:148` | ✅ `board_global_rect` | |

**得分：元素 5/11，动作 3/6**（bag / ledger / infer-icon / goto 四个动作全缺）。
其中 `infer-icon` 特别刺眼：桌布开着能收线索，桌布关着拖到图标就什么都不发生 —— 玩家会认为是 bug。

### 6.3 反向：从收纳处拖出（8 条路径）

Web 两侧各行都做成了**可拖**，落点三选一（顺序即优先级：另一个收纳窗 → 桌布 → 画布）：

| 起点 | 落点 | Web 动作 | 行 |
|---|---|---|---|
| 袋行 | 册窗 / 册图标 | `bagToLedger`（restash） | `06-storage.js:266` |
| 袋行 | 桌布 / 推演器图标 | `bagToMatrix` | `:267` |
| 袋行 | 画布 | `bagTake(key, x, y)` **跟手落点** | `:268` |
| 册行 | 袋窗 / 袋图标 | `ledgerToBag` | `12-panels.js:365` |
| 册行 | 桌布 / 推演器图标 | `ledgerToMatrix` | 同上 |
| 册行 | 画布 | `ledgerTake(key, x, y)` | 同上 |
| 桌布 chip | 册窗 / 册图标 | `restash` | `13-matrix.js:37` |
| 桌布 chip | 画布 | `boardTake(key, x, y)` | 同上 |

Godot 现状：

- **袋行**：`StorageWin._make_row`（`StorageWin.gd:60`）只有两个 Button（「取回」，册行多个「上桌布」）。
  行本身**没有任何指针手势** ⇒ 拖不出来。
- **取回不带坐标**：`_take()` 调 `graph.take_back(key)` → 节点回 `add_node` 的默认位，
  而 Web 是「落在松手那一点」。`take_back` 的 `x/y` 参数从未被 UI 用过。
- **唯一的拖出路径**：桌布 chip → 册**窗**（`_on_matrix_dropped`，`Desktop.gd:1701`）。
  拖到册**图标**不认；拖出到画布走 `_on_matrix_took` → `matrix_take(key)`，**同样不带坐标**。

**得分：2.5/8，且「落在松手那一点」这条路一条都没有实现。**

### 6.4 落点附带的四件事（全缺）

| 项 | Web | Godot |
|---|---|---|
| 悬停高亮 | 图标 / 窗 / 桌布 / 节点都加 `.over`（反白 + 描边，`04-nodes.css:19`），`pointermove` 每帧刷 | **无**。`dragged` 信号不带坐标，连判都没判 |
| 幽灵线 | 拖动时从原点画一条虚线到指针 | **无**（与 E1「一根连线都没有」同源） |
| 弹回原位 | `springBack(el, ox, oy)` 300ms 三次缓出 | **无**。`NodeCard` 里没有任何回位逻辑 |
| 边界夹回 | `x∈[60,1780]`、`y∈[50,1180]` | **无**（§1.3 D7） |

### 6.5 四个由此衍生的真 bug（Godot 独有，已实测）

**实测方法**：无头跑 `Desktop.tscn`，展开花园，用 `test_ui.gd` 同款的 `_press/_motion/_release`
真事件序列拖 `ITEM_shoudiantong` 到图标中心（`cards.scale = 1.3`，`stage = (101,90) 1162×693 clip=true`，
`bag = (18,323) 64×64`，`tec = (18,408) 64×64`）：

| 落点 / 抓点 | 松手后 `card.position` | 与 stage 相交比例 |
|---|---|---|
| 袋图标 / 抓卡片中部 | `(-193.2, -3.7)` | **23%** |
| 袋图标 / 抓卡片右缘 | `(-263.1, -3.7)` | **0%（完全看不见）** |
| TEC 图标 / 抓中部 | `(-193.2, 61.7)` | **23%** |
| TEC 图标 / 抓右缘 | `(-263.1, 61.7)` | **0%（完全看不见）** |

**B1 · 拖到 TEC 图标 ⇒ 节点消失在画布左缘外。**
`_tec_drop_hit` 命中后走 `_start_tec_analysis`，它**不调 `_relayout`**，`_commit()` 也不调（`Desktop.gd:1340`）。
而拖动时 `card.position = _grab + delta / s`（`NodeCard.gd:244`）**无夹回**，
`_stage.clip_contents = true`（`:471`）⇒ 卡片被拖到负坐标就再也看不见。
玩家看到的是「TEC 冒出一句『接收…』，节点不见了」。

**B2 · 拖到证物袋 / 线索册 / 档案图标 ⇒ 节点同样消失，且零提示、`stored` 不变。**
`_on_card_drag_released` 三个 `if` 全不命中 → 函数直接结束，既不执行动作也不回位。
实测 `stored` 始终为空 ⇒ 玩家会认为「拖拽坏了」，而且**丢的那张卡找不回来**（除了触发一次重排）。

**B3 · 图标命中与组合不互斥。**
`NodeCard._gui_input` 先 `drag_released.emit()`，再 `_card_under()` 判组合（`NodeCard.gd:225-229`），
两者都会执行 ⇒ 拖到 TEC 图标、而图标下面压着一张卡时，会**同时**开始分析和触发组合。（§1.3 D9）

**B4 · 拖到画布空白处松手 —— 位置留住了，但没写回数据。**
实测 `(460.7, 184.8)` 确实留在原地（这点是对的），但 `graph.node(key).x/y` 没变，
下一次任意 `_relayout()`（17 处调用点）就会把它拽回网格。（§1.3 D10）

### 6.6 改造清单（按依赖顺序，6 步）

1. **建单一落点表**（对齐 `nodeDropTargets()` 的顺序语义）：
   `Desktop._drop_targets() -> Array[{id, rect: Rect2, act: Callable}]`，
   窗口在表中排最前（`bag-win`/`clue-win` 盖住左侧图标时归属窗口）。
   画布侧只调这一处，禁止在 `_on_card_drag_released` 里继续堆 `if`。
2. **给落点加可视状态**：`DeskIcon.set_over(bool)`、`SysWindow.set_over(bool)`、
   `NodeCard.set_over(bool)`；`dragged` 信号改为带 `at_global` 参数，`Desktop` 每帧算一次命中。
3. **重写松手分派**：命中 → 执行 `act` + `NodeCard.spring_back()`（300ms Tween）；
   未命中 → 夹回 + 写回 `n.x/n.y`（依赖 §4.1 `visual_rect()`、§4.2 布局语义）。
4. **`NodeCard` 加 `spring_back()`**：记住按下时的 `_grab`，`create_tween()` 三次缓出；
   这条同时修 B1/B2（拖到任何落点都回原位，不会留在裁剪区外）。
5. **`StorageWin._make_row` 加拖出**：镜像用 `mx-chip` 观感 + `#drag-layer` 等价物（顶层 `Control`），
   落点三选一 → `restash` / `matrix_assign` / `take_back(x, y)`（**带坐标**）。
6. **图标栏脱离 `VBoxContainer`**：Web 图标可自由拖动（`15-desktop.js:75-101`，位置不进撤销栈）；
   顺手补 `people` / `log` 两个图标与 `bag` / `clue` 角标（`updateBagBadge` / `updateLedgerBadge`）。

### 6.7 验收断言（可直接接进 `tests/headless/`）

```gdscript
# 落点表完整性：11 个 id 与 Web 的 nodeDropTargets() 一一对应
check("落点表 11 项", d.dbg_drop_target_ids().size() == 11)
# 正向：四个缺失动作
check("拖到袋图标",   d.dbg_drop_at("bag-dock", "loc:SCENES_garden") == "bag_store")
check("拖到册图标(non-clue)", d.dbg_drop_at("clue-icon", "loc:SCENES_garden") == "reject")
check("拖到推演器图标", d.dbg_drop_at("infer-icon", "clue:CLUES_x") == "matrix_assign")
check("拖到档案图标",  d.dbg_drop_at("goto-icon", "loc:SCENES_body") == "goto_scene")
# 弹回：拖到图标后卡片回到原位，且没被裁出画布
check("拖到图标后位置不变", abs(card.position.x - 0) < 1.0)
# 反向：带坐标取回
check("袋行拖到画布落在松手点", abs(d.graph.node(k).x - 640.0) < 2.0)
```

---

## 7. 功能完整度记分板（只列复核过的）

> 口径：**已接通** = 玩家在界面上能用出这个动作，且落到正确的数据变更。
> 只验证"数据层有方法"不算接通。
> **「现在」列 = P0 + 批 1 + 批 2 + 批 3 + 批 4 落地后的复核值**，判据见 §0.1 / §0.2 / §0.3 / §0.4 / §0.5 / §0.6 / §0.11 与 `tests/headless/` 的 1250 项断言。

| 模块 | 检查时 | 现在 | 备注 |
|---|---|---|---|
| 窗口渲染 | 🟢 16 个类 | 🟢 19 个类 | +`DetailWin`（P0）、+`PeopleWin` / `LogWin`（批 1） |
| 窗口种类 | 🟡 缺 3 类 | 🟢 **0 缺** | 详情窗（P0）+ **人物名册 / 因果追踪**（批 1） |
| 画布静态构图 | 🟢 P3 2.30% | 🟢 2.30% | 连线层上线前后逐像素 `max diff = 0` |
| 画布行为（缩放 / 平移 / 位置写回 / 力导向） | 🔴 **0 / 4** | 🟢 **4 / 4** | `_on_stage_input` + `_layout_force()` |
| 连线 | 🔴 **0 / 4** | 🟢 **4 / 4** | 四种样式齐；`cond` 只在运行时长出线索时生成 |
| 节点交互（单击选择 / 双击激活 / 右键钉住） | 🔴 **1 / 3** | 🟢 **3 / 3** | |
| 落点（正向） | 🟡 元素 5/11、动作 3/6 | 🟢 **11 / 11** | 表里 11 项（含推演桌布） |
| 落点（反向拖出） | 🔴 **2.5 / 8**，带坐标 0 | 🟢 **8 / 8** | 批 2：桌布 chip → 画布（带坐标）补齐并写回 `n.x/n.y`；chip → 册窗 / 册图标都认 |
| 收纳窗内容 | 🔴 空窗 | 🟢 可拖入 / 可拖出 | 袋与册都成了真清单 |
| 组合 / 反应表 | 🔴 反应 **0 / 14** | 🟢 **27 / 27** | 实测 27 条（物品触发 14 + 线索触发 13）；反查 payload 三通道已接（批 4，见 §0.5） |
| 图标栏 | 🟡 6/8；不可拖动；**单击即开** | 🟢 **8/8 + 自由拖动** | 批 1：人物 / 日志两个图标补齐，脱离 `VBoxContainer` 可拖（不进撤销栈） |
| 角标 | 🟡 缺 2 个 | 🟢 **4/4** | 批 1：推演器「N 条」/ 证物袋「N 件」/ 线索册「N 条」/ 日志「未读」 |
| 因果追踪（SYS_LOGS） | 🔴 无窗、无数据 | 🟢 **有窗 + 只记结果** | 批 1：口径照 `03-utils.js:250-262`，日志不进快照 |
| 人物名册（ROSTER） | 🔴 无窗 | 🟢 **有窗 + 点行说下一句** | 批 1：收录口径按 `metChars()`，常驻两人恒在册 |
| 节点细节（N7 命令 / N8 hover / V4 pop / V5 warn / V6 dim / D6 镜像） | 🔴 **0 / 6** | 🟢 **6 / 6** | 批 3：N7 数据 0/11 场景用到，断言走运行时注入；warn 谓词四件套见 §0.4 |
| 批 4 残项（反应表产物 / 折叠过渡 / 系统窗 z 序） | 🔴 **0 / 3** | 🟢 **3 / 3** | 反应表 `results` 三通道 + `_relayout(true)` 0.34s 过渡 + `ZR_*` 十二档 `_place_z`，见 §0.5 |
| 批 4.5 手感三修（双击窗口 / 按下冻结 / 提层走 rank） | 🔴 **0 / 3** | 🟢 **3 / 3** | `DBL_MS` 280→500 + press 杀弹簧并通知 Desktop 杀落位补间 + `raise_now` 回调走 `_place_z`，见 §0.6 |
| 批 2 交互四项（N5 / V1 / V2 / V3 / C4） | 🔴 **0 / 5** | 🟢 **5 / 5** | 实现早在 `5fff486`；本轮补 `test_p27` 39 项界面级验口，见 §0.11 |

**§6.4 那四件附带的事**：悬停高亮 ✅ / 弹回原位 ✅ / 边界夹回 ✅ / ~~拖动幽灵线 ❌~~ → ✅
~~（Web 从原点拉一条虚线到指针；Godot 没有，`NodeCard` 拖动时只有卡片本身跟着走）~~ → 批 2 补齐：`EdgeLayer` 幽灵线从被拖卡中心直连指针，松手收线（§0.3）。

**读法**：渲染（"看起来对"）大致齐了；凡是"手一碰"的地方基本都在 0~1/3 之间徘徊。
这解释了为什么截图能过 P3、真机一玩就觉得"很不完整" —— **P3 量的正是静态那一层。**
（这段是检查当时的结论，保留原文；P0 之后"手一碰"的那些行已经补到 4/4 与 11/11。）

---

## 8. 如果要开工，我建议的顺序（依赖驱动）

1. **地基**：`NodeCard.visual_rect()` 统一坐标基准（§4.1）+ 布局语义改"松弛一次"（§4.2）
   —— 这两件不做，后面每一条都会返工。
2. **止损**：`NodeCard.spring_back()` + 拖出边界夹回 —— 先让"拖一下不会丢节点"（修 B1/B2）。
3. **落点表**：`_drop_targets()` 单一清单 + `.over` 高亮 + 重写松手分派（§6.6 第 1–3 步）。
4. **收纳**：两扇窗接受拖入 + 行可拖出（带坐标）—— 一次把 8 条路径补齐。
5. **单击/双击分离 + 详情窗** —— 节点从"开关"变成"可读"。
6. **连线** —— 放在最后：它依赖坐标基准、依赖 4 类边的数据写入（tried / cond / move / entity）。
7. ~~补 3 类窗口（名册 / 日志 / 详情）+ 2 个图标 + 2 个角标~~ → 详情窗随 P0、名册 / 日志 / 两个图标 / 四个角标随批 1 **已完成**。
