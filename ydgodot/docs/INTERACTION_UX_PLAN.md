# 交互与操作手感优化计划

> 日期：2026-10-23
> **方向（2026-10-24 修订）**：Godot 为产品主线，Web 只作参考，不再为「对齐 Web」而改交互；本计划以 Godot 真机手感 / 状态一致性为准。
> 范围：操作层 —— 文字渲染与缩放、叙事/详情时序、收纳规则、窗口层叠，以及一轮全代码库操作手感排查的新发现。
> 关系：迁移期的 Web↔Godot 差距报告已完成使命，随 2026-10-25 文档清理删除（仅存 git 历史）；
> 本文档是后续交互工作的**唯一口径**，与视觉无关（视觉见 `UI_AESTHETIC_PLAN.md`）。
> 优先级：**P0 = 会丢东西/像坏了**；**P1 = 明显别扭或真 bug**；**P2 = 可以更顺手**。
> 证据：全部为源码核实，附文件:行号。

---

## ⚠ 进度总览（2026-10-25 逐项核查，未完成置顶）

**48 条：✅ 46 / 🟡 1 / ❌ 1。** 除 S6（切时刻镜头对焦，未进 BACKLOG）与 K11 已拍板外，其余全部落地。
**2026-10-25 收口批**：U1/U3/W7–W28/S2–S16/G14/A9/A10/K2/K11 已全部完成；F1/F3–F6/F9 与 §7 标签退役见 `UX_FLOW_PLAN.md`。

### 已完成 · 止损批（2026-10-25）

| # | 问题 | 结果 |
|---|---|---|
| U5 | 连线残留 / 孤儿线 | ✅ 组合消耗走 `_despawn_card` 删卡；`delete_node` 清 tried；连线过滤排除 alpha=0 遮罩卡；`_commit` 增加 `_sync_canvas` 兜底 |
| U6 | 案件窗最小化卡片不可见 | ✅ `case_dock` 纳入布局贴右下重排，1280×720 / 960×560 均在桌面内 |
| S1 | 重置 / 换案后镜头不复位 | ✅ `_start_slice` 统一 `_reset_camera`，重置后自动 fit，起始节点可见 |
| W4 | 窗口能拖丢 / TEC 等重开在屏外 | ✅ `SysWindow` 拖动钳制至少留 40px；打开 / resize 时统一夹回桌面 |
| S4 | 撤销 / 读档销毁音乐播放器 | ✅ `_rebuild_from_graph()` 不再无条件 `queue_free` 音乐窗 / dock；无关撤销保留播放器与音频。撤销「装针」本身仍按锁定态正常收起 |
| S5 | 结局遮罩期间退出丢真名种子 | ✅ 真名结局触发时即 `normalize` 发种并立即写档；收幕只做演出。旧档（TRUE_E + 空花园 + seed=false）由 `GardenSystem.normalize()` 补回 |
| S8 | 撤销把玩家知识退回快照 | ✅ `SaveSystem.undo()` 走 `restore(s, keep_knowledge=true)`：unread / cardSeen / debuted 以当前值合并；普通读档仍按存档知识恢复 |

### 未完成 · 其余（按批次）

- **批 2**：W5/W22 已完成（叙事卡按视口夹取，不再写死 740 / (700,290)）。
- **批 4 文字与缩放**：U1/W10/W13/W14 已完成（12/24 字牌、fit 只缩不放、LOD 0.95、镜像随缩放）。
- **批 5 时序**：U2/W17/W21 已完成；S6 未进 BACKLOG（切时刻镜头对焦）。
- **批 6**：U3/W23 已完成（容器话术、无效落点反馈）。
- **批 7 手感**：W7/W8/W9/W11/W12/W15/W18/W19/W20 全部完成。
- **批 8 状态一致性**：S2/S7/S9–S11/S13/S15/S16 全部完成；S4/S5/S8/S12/S14 于 2026-10-25 前已落地。

### 已完成 ✅

W2（拖回原窗误取回）、W3（幽灵牌 52px 偏移）、W24（隐形可点卡）、W25（淡化压高亮——以统一虚线框取代反白实现）、S3（详情窗跨案旧图）；
U5（消耗卡/孤儿线）、U6（case_dock 可见）、S1（重置镜头）、W4（窗口拖丢钳制）、S4（音乐跨撤销）、S5（结局即写种）、S8（知识不回滚）、S12（名册点行改开人物档案卡，对话窗开着时不再误报）；
U2（叙事播完再出详情，连带 W17 点击补全 / W21 双击不闪）、U7（案件卡片 / 音乐坞 / TEC 胶囊可拖且不被重排吸回）、W1（标题栏 / 头像 / 放映卡标题栏事件不再冒泡）、W6（详情窗 × 只收起，`_commit` 不复活）、W26（TEC 打字中点击只补全、同文本提示去重）、W27（签发窗恢复标题栏拖动）、S14（`catalog.last` 启动读取，继续回上次可装载案件）；
U4①②（后开在上 + 点窗口任意处提层）已落地；W16 半（TEC 胶囊已入落点表，花园仍不在）。

---

## 0.0 下一步（2026-10-24 建议）

先做 **P0 止损批**，不碰视觉、不扩玩法：

1. **U5 · 连线残留**：新增 `_despawn_card()`，组合消耗后删卡；`delete_node` 清 `tried`；`_repaint_edges` 排除矩阵遮罩卡。
2. **U6 · 案件窗最小化**：`case_dock` 纳入 `_layout_root()` 贴右下重排，修掉 1280×720 下整张卡片落在裁切区外的问题。
3. **S1 · 重置/换案镜头**：复位 `_view_user/_view_k/_view_pos`，重置后至少让唯一节点可见。

验收：全套无头 + 三条真事件路由用例（组合消耗 / 最小化 / 重置后镜头）；960×560 与 1280×720 各过一遍。

之后顺序：**U1 文字清晰度 → U2 叙事/详情时序 → U7 最小化部件拖动 → U4 窗口带（需拍板）→ S2–S6 → P2 收口。**

---

## 0. 一句话结论

第一轮反馈的 4 个问题里，**2 个是真 bug（文字、层叠），1 个是时序设计（叙事/详情），1 个是既定设计需要话术优化（物品）**；
第二轮反馈的 3 个问题里，**连线残留是 P0 真 bug（组合消耗的僵尸卡 + 推演窗遮罩用透明度代替可见性）、案件窗最小化是 P0 真 bug（右下角卡片定位在裁切区外、从未可见）、最小化部件不可拖动属实（三个部件都无拖动手势）**。
两轮专项排查共另外发现 **P0 1 条（重置后镜头不复位）、P1 15 条、P2 25 条**，最伤的四类是：**会丢东西/丢状态**、**事件冒泡乱触发**、**坐标写死 1280 口径**、**撤销/读档的连带刷新有漏**。

---

## 1. 玩家反馈的四个问题（根因 + 方案）

### U1 · 节点文字「像加粗」、缩放时糊在一起（P1，渲染纪律）

**根因（两处叠加，都不是真加粗）**：

1. **圆形字牌用了违规字号**：`ui/KindGlyph.gd:40-43` 的 `glyph_font_px()` 算出 **9px**（及缩略档 13/20/21px 等）——
   项目纪律是「字号只能是 12 的整数倍」（`ui/TecTheme.gd:189-198`），9px 渲染 12px 原生格点阵字，
   笔画重采样后粘连发胖，读作「比别处粗、糊」。全项目无 `variation_embolden`，标题本身与窗口同源同管线。
2. **画布任意倍率缩放重采样**：`Desktop._apply_view()`（`Desktop.gd:2199-2208`）对 `_card_layer` 整体 scale，
   点阵字只在 1x 光栅化一次，非 1.0 倍率下缩小丢列、放大糊边。更糟的是 `_fit_cards()` 不吸附 1.0，
   **开局只有 1 张卡时 `_view_k` 直接顶到 `FIT_MAX=1.3`**（`Desktop.gd:4044`、`:62`）——玩家第一眼就是糊字。
   只有 NodeCard 在缩放层里，MemCard/NarrCard/窗口/图标全部不受影响。

**方案**：

- `KindGlyph` 字号收 12/24 两档；文字档圈内放不下 12px 就把 `GLYPH_BOX` 16 → 18~20。
- `_fit_cards()` 的结果过一遍 1.0 吸附带（滚轮已有 ±6% 吸附，fit 没有）；开局 k 钉 1.0，单卡居中即可，不要放大。
- `LOD_TITLE` 0.86 → ~0.95：缩短「有字但已糊」的过渡区间。
- 备选（彻底档）：字体开 `oversampling=0` 跟随变换重光栅——`TecTheme.gd:272-275` 记录过窗口级实测无收益，
  画布 0.6~2.0 的大倍率范围值得重测一次再定。

### U2 · 叙事文本应先播完，再显示节点详情（P1，时序）

**根因**：`NodeCard._click()` 双击分支是 **`selected.emit` 在前、`activated.emit` 在后**（`NodeCard.gd:707-708`）——
详情窗随选中**立即**弹出（`_on_card_selected → _refresh_detail`，`Desktop.gd:2311/2528`），
叙事卡反而晚一步才创建（`_toggle_container → _show_narr`，`Desktop.gd:2842`），且层序详情(22) 压叙事(16)。
另外叙事卡**没有对外暴露「播完」信号**（`NarrCard.gd` 内部有 `TypewriterLabel.typing_finished`，没转发）。

**方案**：

1. `NarrCard` 转发 `typing_finished` 并暴露 `is_typing()`（前置，两行）。
2. `_refresh_detail()`（`Desktop.gd:2528`）加闸：叙事打字中 → 记下 `_pending_detail` 并 return，
   `finished` 一到补显示。这一处闸门同时盖住「双击先弹详情」和「打字中点别的节点插队」两条路。
3. 打字中点新节点的策略：**立即补全旧叙事**（调 `finish_typing()`，单击补全已是 MemCard 的既有惯例）再切详情。
4. 补显示时详情简介**整段出现**，不再二次打字（`DetailWin._rebuild` 区分首次/刷新）。

### U3 · 书桌收不进物品（P3，既定设计，改话术优先）

**根因**：不是 bug。`GraphState.bag_store` 拒收容器（`GraphState.gd:582-590`），
「容器」= loc/time 场景、或 `node_items/node_locs` 清单非空的物品（`GraphState.gd:223-230`）——
书桌正是装着笔记/台灯/抽屉/垃圾桶的容器物品（`cases/a001/items/ITEM_shuzhuo.tres:21-23`）。
Web 原版同样拒收（`06-storage.js:73`），且 Web 是**静默弹回**，Godot 已多给了一句 toast。
语义上「容器是现场，不是证物」是成立的。

**现状反馈链**：拖到袋 → toast「场景与容器收不进收纳袋」→ 弹回原位。不算沉默，但话术像「功能没做」。

**方案（按推荐度）**：

1. **改话术**（推荐，成本最低）：「『书桌』是现场的一部分，收不走；它装着的东西可以单独收。」
2. 收容器 = 连带折叠（复用 `collapsed` + `recompute_hidden`，取回时展开）——行为可预测，
   但钉住的子节点会悬空，需补规则。
3. 收容器 = 整棵子树连带收纳——语义最完整，改动面最大（袋清单分组、取回、存档兼容）。

**需拍板**：先上 1；是否进一步支持收纳容器（2 或 3）看玩法需要。

### U4 · 窗口层叠与拖动（P1，真语义缺陷）

**根因（三层叠加）**：

1. **静态 rank 档**（`Desktop.gd:944-987`）：日志 21 / 详情 22 < 普通窗 25 < 对话 26 < TEC 28 ——
   「插到第一个更高 rank 之前」意味着**后开的日志/详情永远开在别人脚下**，`_on_window_raise` 只在同 rank 内挪位，跨不了档。
   这是照抄 Web 的 CSS z-index 表，与真实桌面「后开/后点在上」的预期直接冲突。
2. **只有标题栏按下才提层**（`SysWindow._on_bar_input`，`SysWindow.gd:382-396`），点窗口内容区不提层。
3. **拖动无边界钳制**（`SysWindow.gd:395-396`）：窗口能拖出 `_desk`（`clip_contents=true`）永久拿不回——
   主案件窗拖丢后连重开都不复位（复用实例的 TEC/音乐窗同样如此）。

**方案**（推荐「窗口带合并」而非最小修）：

1. 把 PW 15 / NARR 16 / LOG 21 / DETAIL 22 / WIN 25 / CHAT 26 / TEC 28 **合并为一个窗口带**（同 rank），
   同 rank「后到在组尾」的既有语义正好就是「后开在上、点击置顶」。CASE(1)/DOCK(23)/ICONS(24)/TOAST(30)/MIRROR(40) 保留。
   ⚠ 两条历史设计需确认：NarrCard/MemCard/PasswordPop 目前**故意**低于系统窗（`Desktop.gd:948` 注释）——
   建议保留叙事类低半档（不被普通窗打断阅读），其余合并。
2. **点击窗口任意处提层**：`SysWindow` 根挂 `gui_input`，按下即 `raise_now`（子控件先收事件，不冲突）。
3. **拖动钳制**：标题栏至少留 40px 在 desk 内且 `y ≥ 0`，杜绝拖丢；TEC/音乐窗打开时若完全在屏外则复位默认位。
4. **测试改写**：`test_ui.gd` §22（:982-1006）/§23（:1009-1054）锁的正是旧口径
   （「后开的日志压不过地图」「提层后仍在 icons 之下」），需按新语义重写断言。

### U5 · 连线有时候不消失 / 有时候只有连线没有节点（P0，真 bug）

两个现象，**两条不同的根因**，都已定位：

**① 连线不消失 = 组合消耗留下僵尸卡**：

- `CommandSystem.gd:156-158`：useItem 成功且「合成消耗」开着时，`graph.delete_node(have_key)` 把工具节点从**数据层**删掉；
- 但**卡片层没人收尸**：`_on_card_combo` 成功分支（`Desktop.gd:3668-3694`）与 `_apply_outcome`（`Desktop.gd:3093-3122`）都不处理 `res["consumed"]`——卡片还在 `_cards` 里、`visible=true`；
- 同时 `GraphState.delete_node`（`GraphState.gd:150-161`）**不清 `tried`**，`"a>b"` 虚线痕迹键永久残留。

⇒ 僵尸卡 + 残留 tried 键，每次重绘都继续画线。撤销/读档走 `_rebuild_from_graph` 会顺带清掉——所以表现为「**有时候**不消失」。附带损害：力导向布局把僵尸卡当活节点播种，可见集合签名也一直把它算进去。

**② 只有连线没有节点 = 推演窗遮罩用透明度代替可见性**：

- `Desktop._sync_matrix_occlusion`（`Desktop.gd:3389-3407`）：被矩阵窗盖住 60% 的卡用 `modulate.a = 0` + 禁输入来「藏」——故意不动 `visible`，怕触发重排；
- 但 `_repaint_edges` 的过滤只看 `card.visible`（`Desktop.gd:2667`），alpha=0 的卡照样通过过滤 ⇒ **端点不可见、连线照画**。
  开着推演时任何一次重绘（选中/聚焦/重排）都会把这些孤儿线画出来。

**方案**：

1. 新增 `_despawn_card(key)`（杀补间 → 移出 `_cards` → `queue_free` → 顺带清 `_selected`/`_drag_key`），
   在 `_on_card_combo` 与 `_apply_outcome` 里遍历 `res["consumed"]` 调用。
2. `GraphState.delete_node` 顺手清掉 `tried` 中含该 key 的条目（否则节点日后再上画时旧虚线还魂）。
3. `_repaint_edges` 的可见性过滤改为单一来源：`graph.visible_node(...)` **且** `card.modulate.a > 0`（把矩阵遮罩态排除）。
4. 收口：`_commit()` 固定调一个 `_sync_canvas()`（清理 `_cards` 里 graph 已不存在的 key + `_apply_hidden()`），
   让任何改图路径——包括未来新增——都不可能漏重绘。

### U6 · 案件窗最小化「没到右下角」（P0，真 bug）

**接线没接反**：`Desktop.gd:993-995` —— `× → _park_case("icon")`（收进「案件」图标）、`– → _park_case("dock")`（右下角案件卡片），
与提示文案语义一致。**真正的 bug 是右下角卡片从来不可见**：

- `case_dock` 定位写死 `Vector2(1094, 678)` 且全项目只赋值一次（`Desktop.gd:1661`），`_layout_root()` 从不重排它；
- `_desk` 高 = 视口高 − 52，1280×720 下是 **668**，且 `_desk.clip_contents = true` ⇒ 卡片整张（y 678..734）**在裁切区外**。

⇒ 最小化后窗口凭空消失，唯一找回入口只剩「案件」图标——玩家的体感「最小化 = 进了案件」就是这么来的。
（实证截图已随 2026-10-25 历史档案清理删除；当时右下角空无一物，同流程的 MusicDock 可见，因为它走 `_place_music_windows()` 重排。）
`case_dock` 修复后随 `_layout_root()` 贴右下现算，不再依赖写死坐标。

### U7 · 最小化部件都无法移动（P1，功能缺失）

三个最小化部件全部是「绝对定位 + 纯点击」，没有任何拖动手势：

| 部件 | 类型 | 现状 | 恢复路径 |
|---|---|---|---|
| `case_dock` 案件卡片 | 裸 `Button`（`Desktop.gd:1657-1716`） | 无 `_gui_input`，只有 `pressed`；定位写死（且越界，见 U6） | 点击 `_reopen_case()` ✅（卡片可见时） |
| `MusicDock` 音乐坞 | `MusicDock.gd:82-85` | `gui_input` 左键按下即恢复，无 motion 分支 | 点击 `_restore_music()` ✅ |
| `TecChip` TEC 胶囊 | `TecChip.gd`（extends Button） | 类内无输入处理，只有 `pressed → _open_tec` | 点击 `_open_tec()` ✅ |

**方案**：

1. 抽一个共用的「小部件拖动」行为，照搬 `DeskIcon` 的成熟模式（`DeskIcon.gd:132-164`）：
   按下记原点 → motion 超 5px 进拖动 → 钳到 `_desk` 矩形 → 松手若拖过则吞掉点击
   （Button 在拖完松手时会再发一次 `pressed`，必须自管输入——DeskIcon 踩过这个坑）。
2. **防吸回**：`MusicDock`/`TecChip` 每次 resize 被 `_place_music_windows()`/`_place_floating_windows()` 重算——
   加拖动后要给部件记「玩家拖过」标记（参照 `_view_user` 口径），resize 时只夹取越界轴、不收走玩家摆位。
3. `_place_toast_anchor()` 读这两个部件位置做避让（`Desktop.gd:2199-2208`），拖动支持后避让天然成立，不用改。

---

## 2. 专项排查新发现（源码核实，未在既有文档中记录）

### P1（明显别扭 / 真 bug）

| # | 问题 | 证据 |
|---|---|---|
| W1 | **事件不 `accept_event()` 导致冒泡乱触发**：拖 TEC 窗标题栏 = 先白聊一句；点 TEC 头像一次出**两句**台词；点 MemCard 标题栏会误触发 `advance()` 翻行 | `TecWindow.gd:136-143`、`:63-65`；`SysWindow.gd:382-396`；`MemCard.gd:282-296` |
| W2 | **收纳行拖回「原来那扇窗」松手 = 被取回画布**：`_finish_sdrag` 对 `to==from` 不 return，继续判到窗底下的画布；悬停时窗还亮着 over 高亮误导 | `Desktop.gd:464-497` |
| W3 | **收纳行拖拽幽灵牌偏移 52px**：取的是全局坐标、赋的是 `_desk` 局部坐标（`_desk` 在 y=52）。无头测试走 `dbg_` 钩子绕开了这段，所以没拦住 | `Desktop.gd:375-387`、`:418-434` |
| W4 | **窗口能拖丢**（U4 第 3 层的完整面）：主案窗拖走后关闭/重开也不复位；TEC/音乐窗复用实例、拖丢后重开仍在屏外 | `Desktop.gd:273-296`、`:4064-4075` |
| W5 | **960×560 最小窗口下半数窗体开出屏幕**：聊天窗 (858,58)、TEC (906,264)、音乐坞 (1026,532)、叙事卡 (700,290)、详情窗 x=952 等全写死 1280 口径；`_relayout_edge_windows` 只管名册/日志两扇 | `Desktop.gd:16-17`、`:3764`、`:576`、`:1325`、`:3449`；`DetailWin.gd:33` |
| W6 | **详情窗关掉后会被任意操作重新弹开**：点 × 只是 `hide()`，而 `_commit()` 每次都 `_refresh_detail()` 且 `refresh()` 里 `show()` 无条件 | `DetailWin.gd:34`、`:52-64`；`Desktop.gd:2028` |
| W7 | **窗口一拉高，玩家摆好的图标全部归位**：`_layout_root` 对 `_desk.size.y` 变化无条件 `_reset_icon_positions()`；且 `DeskIcon.set_bounds` 钉死 1280×668，resize 后不更新，图标可拖出屏 | `Desktop.gd:238-240`、`:1005`；`DeskIcon.gd:148-151` |
| W8 | **悬停高亮与组合命中不是同一张卡**：高亮从后往前取最上层（`_card_key_at`），松手组合从前往后取最底层（`_card_under`）——两卡重叠时亮 A 打 B | `Desktop.gd:2734-2744`；`NodeCard.gd:783-795` |
| W9 | **TEC/Chat 窗无滚动、只长不收**：`_fit_height` 只有 `maxf` 无上限，长出桌布底被裁，新台词看不见 | `TecWindow.gd:81-86`、`:165-174`；`ChatWindow.gd:244-253` |
| W10 | **开局即 1.3x 糊字档**：单卡 fit 顶到 `FIT_MAX`；并入 U1 一起修 | `Desktop.gd:4044` |

### P2（可以更顺手）

| # | 问题 | 证据 |
|---|---|---|
| W11 | 全程零键盘：无 Esc 关窗、无 Ctrl+Z、无快捷键 | 全工程无 `_unhandled_input` 处理 |
| W12 | 画布平移无边界（能把世界整个推出视口，找回只能靠「适应窗口」）、平移中光标不变 grabbing | `Desktop.gd:2162-2180` |
| W13 | 滚轮从 1.0 往下滚一档 = 0.89，字已糊但 LOD（0.86）还没切符号档 | `NodeCard.gd:102`；并入 U1 |
| W14 | 缩放/平移中拖卡，镜像失真：镜像 scale 只在挂载时取一次；`build_mirror` 不拷 LOD（0.86 以下原件只剩符号、镜像还带完整标题） | `Desktop.gd:2375`；`NodeCard.gd:855-863` |
| W15 | 密码弹窗无边界钳制：位置 = 卡底 +10，卡在画布下缘时弹窗下半身被裁、输入框摸不到 | `Desktop.gd:3311-3316` |
| W16 | 种子拖向花园无悬停反馈（花园不在 `_drop_targets()`）；TEC 收起胶囊是 11 落点里唯一没有 over 态的 | `Desktop.gd:1417-1448`、`:2599-2602` |
| W17 | 叙事卡不能点击跳过（MemCard 有单击补全，NarrCard 没有任何点击处理），长旁白只能干等 | `NarrCard.gd` 全文 |
| W18 | 音乐进度条只能点、不能拖（只认 pressed，不跟手） | `MusicWin.gd:221-224` |
| W19 | 花园慢拖不触发：用**单帧**位移 >2px 当阈值，慢速拖永远过不了阈、松手被当成点击（别处都是累计位移） | `GardenWin.gd:230-232` |
| W20 | 图标双击窗口 300ms vs 卡片 500ms，同一玩家两套节奏 | `Desktop.gd:1157`；`NodeCard.gd:50` |
| W21 | 双击第二下先触发一次选中刷新（详情窗按旧态闪一帧）；随 U2 的闸门一并消化 | `NodeCard.gd:705-712` |
| W22 | 写死的 740 钳制线三处（实际桌布底 668，允许窗底没入不可见区 72px）；IntroWin 居中写死 1280 | `DetailWin.gd:134`、`NarrCard.gd:30`、`GardenWin.gd:444`、`IntroWin.gd:91` |
| W23 | 拖到无效区零反馈：卡默默留在原地，无任何提示 | `Desktop.gd:481-483` |
| W24 | 丢释放事件的残余态：旧卡的 ghost 透明态不被复位时，留下一张**隐形但可点**的卡 | `NodeCard.gd:821-834`；`Desktop.gd:2397-2399` |
| W25 | 拖动中的组合目标被聚焦淡化压到 0.32 alpha，over 反白只剩一层灰，高亮难读 | `Desktop.gd:2327-2333`；`NodeCard.gd:831-834` |

### 第三轮：用户反馈补充（W26–W28，2026-10-25）

| # | 级别 | 问题 | 证据 |
|---|---|---|---|
| W26 | P1 | **快速点击 TEC 空白处/头像，多条台词同时打出甚至重复**：每次点击立即 `append_line`，上一行还在打字就再加一行；闲聊耗尽后每点一次都追加同一句提示 | `Desktop._tec_talk`（`:5916` 起）；`TecWindow._on_talk_input:197-199` |
| W27 | P1 | **签发窗（CertWin）基础功能缺档**：`set_drag_enabled(false)` 不可拖动、× 隐藏、无 Esc——「所有窗口基础功能一致」规则的破口 | `CertWin.gd:37-40` |
| W28 | P2 | **案件窗缺「进行中」提示**：案件窗 × 收进「案件」图标后，图标角标只有「已关闭」（`_case_held`），玩家在案件窗里分不清哪个案件正开着 | `Desktop.gd:1658`、`:2284` |

修法方向：

- **W26**：打字中再点 = 先 `finish_typing()` 补全当前行（对齐 MemCard 单击补全惯例），补全后才接受下一句；提示行同文本不重复追加。
- **W27**：恢复标题栏拖动（签发期可以没有 ×——流程强制——但拖动不该缺席）；证件签发后的查看态应可关闭。规则入档：**模态窗可以没有 ×，但不能牺牲拖动**。
- **W28**：CaseMapWin 当前案件行加「进行中」状态牌；「案件」图标角标区分「进行中 / 已关闭」。

**已验证无需处理**：案件窗 `–` 最小化到右下角卡片链路正常（探针：min 按钮存在 → `_dock_card` 出现于 (1094,596)、在 `_desk` 边界内、原窗隐藏）。用户报告的「没有最小化到右下角」为旧构建的遗留印象（U6 已修）。

### 第二轮：状态一致性排查（S 组，撤销/读档/换案的连带刷新）

| # | 级别 | 问题 | 证据 |
|---|---|---|---|
| S1 | **P0** | **「重置」与「换案」后镜头不复位**：`_view_user/_view_k/_view_pos` 任何地方都不复位，`_fit_cards()` 有 `not _view_user` 闸门——玩家动过一次相机，重置后唯一节点可以整屏不可见，且「适应窗口」收在调试面板里 ⇒ 玩家判定「重置把案子清空了」 | `Desktop.gd:2392`、`:4148`、`:1986`、`:808` |
| S2 | P1 | 读档后镜头停在 (0,0)@1.0 不做 fit：`_rebuild_from_graph()` respawn 后不调 `_apply_view`/`_fit_cards`，x>1162 的节点开局即在视口外 | `Desktop.gd:2318-2370` |
| S3 | P1 | **DetailWin 持有旧 graph 跨重置/换案**：`_new_runtime()` 清了全部会话窗唯独漏它；`setup_detail()` 存着旧 GraphState 引用——重置后详情窗读旧图、显示陈旧状态，直到玩家手动点 × | `Desktop.gd:1920-1983`；`DetailWin.gd:29-31` |
| S4 | P1 | **任何撤销/读档都会销毁音乐播放器**：`_rebuild_from_graph()` 无条件 `queue_free` `_music_win`/`_music_dock`，撤销一个无关操作（如点亮手电）就把正在播的歌掐了（Web 的 undo 不碰 audio，Godot 独有过失） | `Desktop.gd:2332-2337` |
| S5 | P1 | **结局遮罩亮起期间退出游戏 → 真名种子永久丢失**：种子只在玩家点击收幕时发放；存档里结局已记但 `garden.seed=false`，老档迁移分支够不到（新档永远带 garden 字段）；唯一自救是再按一次推演，但没有任何提示 | `Desktop.gd:1641-1654`；`GardenSystem.gd:44-45`；`SaveSystem.gd:94` |
| S6 | P1 | **切换时刻不把镜头对焦到回忆发生地点**：Web `applyTimeNow` 换档后 `centerOnNode(memPlace)`；Godot `_select_time()` 无等价动作——地点在视口外时切档后画布空白，放映卡退回默认位 | `Desktop.gd:3816-3836`；Web `03-utils.js:155-172` |
| S7 | P2 | 撤销/收起案件静默掐断进行中的 TEC 分析：5–8 秒等待作废，transcript 留半截「（接收…，开始分析…）」，无任何反馈 | `Desktop.gd:2356`、`:1880-1893` |
| S8 | P2 | **玩家知识不接力**：Web 撤销时用当前值合并 unread/cardSeen/debuted（「认识了就是认识了」）；Godot 整表覆盖 ⇒ 撤销能复活已点掉的「新」角标、重播已看过的放映卡、摘掉人物登场 | `SaveSystem.gd:121-123`；Web `02-state.js:41-52` |
| S9 | P2 | 撤销无条件清掉档案图标「新」角标且不再补标（respawn 期间 `_suppress_archive_new=true`） | `Desktop.gd:2353-2361` |
| S10 | P2 | 撤销后推演桌布的遮挡淡出不重算（`_matrix_faded` 残留、新卡 alpha 全 1，被压卡片全部显形） | `Desktop.gd:2318-2370` vs `:3389-3416` |
| S11 | P2 | 案件收起后详情窗不收（内容陈旧）；袋/册/花园窗仍可写进度——Web 的 `ledgerTake/bagTake/gardenPlant` 都有 `requireCase()` 闸，Godot 没有 | `Desktop.gd:1880-1896`；`StorageWin.gd:163-170` |
| S12 | P2 | ✅ 已由人物档案卡吸收：对话窗开着时点名册/双击人物不再直接叫人，卡内「前往此人」只提层现有对话，不误报「暂无对话文本」 | `Desktop._goto_char`；`PEOPLE_CARD_PLAN.md` §7 |
| S13 | P2 | 「重看对话」只重放基础 talkQueue，漏 sceneTalks 场景限定台词 | `Desktop.gd:2783`；`GraphState.gd:430-450` |
| S14 | P2 | ✅ `CaseCatalog.resume_case_id()` 启动读取 `last`；不可用（老档 / 数据未接入）回 A-001。C2 同项，已于 2026-10-25 落地 | `CaseCatalog.gd`、`Desktop._ready` |
| S15 | P2 | 存档 `format` 字段只写不校验，将来改格式时旧档被静默按新格式解析 | `SaveSystem.gd:11`、`:76-81` |
| S16 | P2 | 撤销/读档后 fresh 被消费，新节点不再重演入场 pop（纯表现层，「新」角标不受影响） | `Desktop.gd:2511-2515` |

### 第二轮确认「没问题」的项（免得重复报）

- 撤销覆盖面：拖动/收纳/展开/点亮/捕获/对话进度/TEC 分析/桌布归位/下种均进栈；计数角标每次 `_commit` 全量重算，无漏记。
- TEC 闲聊、切时刻、花园挪株不进撤销栈；无 redo——均与 Web 一致。
- EndingOverlay 冻结/恢复正确（全屏 STOP + z 100）。
- 180ms 合并写盘 + 退出时 flush，正常退出不丢档。
- 换案清理（`_new_runtime`）对卡片/连线/日志/会话窗是彻底的，唯一漏网的是 S3 的 DetailWin。

### 排查中确认「没问题」的易疑项（免得重复报）

- 滚轮悬停卡片上：事件正常冒泡到画布缩放。
- 卡片拖到非落点窗口上松手：有夹回 + 坐标写回，不会丢。
- 密码窗 Enter 提交 / 错误抖动 / 焦点回收、IntroWin 真模态、中文 IME 候选框：都在。
- 桌布 chip 双击 / 拖出 / 种子 3px 阈值：正常。

---

## 3. 执行批次

原则不变：**先止损（会丢东西的）→ 再修语义（层叠/时序）→ 再修手感**。每批单独改、单独回归。

| 批次 | 内容 | 涉及 | 主要文件 | 完成标志 |
|---|---|---|---|---|
| 1 | **止损：不许丢东西/丢状态** | U5 U6 S1 W3 W4 W24 | `Desktop.gd`、`GraphState.gd`、`EdgeLayer.gd`、`SysWindow.gd` | 消耗节点即删卡删虚线；遮罩卡不出线；case_dock 右下可见；窗口拖不出可恢复区；重置后镜头回中 |
| 2 | **小分辨率布点** | W5 W22 | `Desktop.gd`、各窗默认位 | 960×560 下所有窗体完整可及；钳制线全部改读桌布实际矩形 |
| 3 | **窗口层叠语义** | U4①② W1 W6 S3 | `Desktop.gd`（rank 合并）、`SysWindow.gd`、`TecWindow.gd`、`DetailWin.gd`、`test_ui.gd` §22/23 | 后开在上、点击任意处提层；拖 TEC 标题栏不闲聊；详情窗关了不复活、换案不读旧图；断言按新口径全绿 |
| 4 | **文字与缩放** | U1 W10 W13 W14 | `KindGlyph.gd`、`Desktop.gd`（fit 吸附/开局 k）、`NodeCard.gd` | 字牌 12/24 档；开局 1.0；0.95 以下才切符号；镜像随缩放 |
| 5 | **叙事/详情时序** | U2 W17 W21 S6 | `NarrCard.gd`、`Desktop.gd`（`_refresh_detail` 闸）、`DetailWin.gd` | 叙事播完（或点击补全）后详情整段出现；打字中不插队；切时刻镜头对焦回忆地点 |
| 6 | **收纳规则与反馈** | U3 W2 W16 W23 W25 | `Desktop.gd`、话术文案 | 容器话术改「现场收不走」；拖回原窗不再误取回；无效落点有反馈；淡化不压高亮 |
| 7 | **最小化部件与手感收口** | U7 W7 W8 W9 W11 W12 W15 W18 W19 W20 | `Desktop.gd`、`MusicDock.gd`、`TecChip.gd`、各对应文件 | 三个最小化部件可拖且 resize 不吸回；高亮=命中同一张卡；TEC/Chat 超高滚动；Esc 关窗；平移有界；双击节奏统一 500ms |
| 8 | **状态一致性** | S2 S4 S5 S7–S16 | `Desktop.gd`、`SaveSystem.gd`、`GraphState.gd` | 读档 fit 镜头；撤销不掐音乐；结局种子不丢；知识不随撤销回滚；归档角标/遮挡淡出撤销后正确重建 |

每批验收统一走：全套无头测试（现 **1558 项**基线，16 个脚本）→ 960×560 / 1280×720 / 1920×1080 三档真机过一遍 → 必要时补断言（W3/W24 这类无头钩子测不到的路径，要补**真事件路由**用例——迁移期踩过一次这个坑，报告已删，教训留此）。

---

## 4. 需拍板的决策点

1. **U3 容器收纳**：只改话术（推荐），还是支持「收容器 = 连带折叠」？
2. **U4 叙事卡档位**：NarrCard/MemCard/PasswordPop 是否保持「故意低于系统窗」（不被普通窗打断阅读）？
   建议：叙事类保留低半档，其余窗口合并为一带。
3. **W11 键盘**：本轮只做 Esc 关最上层窗 + Ctrl+Z 撤销，还是一次补齐快捷键表？
4. **U1 缩放糊字**：最小档（吸附+LOD，推荐先做）之外，是否要重测 `oversampling=0` 的彻底档？
5. **S5 真名种子**：改为「结局触发即写档（收幕只是演出）」，还是退出时检测补发？推荐前者，种子是进度不是演出。
6. **S8 玩家知识接力**：确认对齐 Web 口径（撤销用当前值合并 unread/cardSeen/debuted，不回滚）。

---

## 5. 本轮不做

- 不重排玩法逻辑（组合、反应表、解锁流程）；W8/W25 只修「高亮与命中一致」「淡化不压高亮」这类表现层。
- 不动迁移期已锁定的行为（500ms 双击窗、落点表 10 项、幽灵线样式等），除非本文档显式列出（W20 属于统一既有口径）。
- 不做视觉改版（圆角、配色、头像框等——归 `UI_AESTHETIC_PLAN.md`）。
- 不引入新的窗口类型或 Dock 结构变化。


---

## 6. 止损批执行记录（2026-10-25）

- **U5**：新增 `_despawn_card()`，`_on_card_combo` / `_apply_outcome` 遍历 `consumed` 收尸；`GraphState.delete_node()` 清理相关 `tried`；`_repaint_edges()` 通过 `_edge_card_shown()` 排除 `modulate.a=0` 的矩阵遮罩卡；`_commit()` 增加 `_sync_canvas()` 兜底。
- **U6**：新增 `_place_case_dock()`，`_layout_root()` 与 `_update_case_park_ui()` 都按桌面实际尺寸贴右下重排。
- **S1**：新增 `_reset_camera()`，`_start_slice()` 开头复位 `_view_k/_view_pos/_view_user`，随后由 `_relayout()` 自动 fit。
- **W4**：`SysWindow` 标题栏拖动增加 `_clamp_window_pos()`，窗口至少保留 40px 在桌面内且 y≥0；打开 / resize 时 `clamp_into_parent()` 兜底。
- **验证**：`test_ui` 421、`test_p12` 39、`test_p16` 72、`test_p21` 73、`test_p25` 166、`test_p26` 98；全套 1506 项、p28 4/4。960×560 的 dock / TEC 边界由 `test_p21` / `test_ui` 覆盖。

### 跨计划口径（2026-10-25，UX_FLOW_PLAN 批 3 收尾）

- K4/K6 已把画布卡片 / 收纳行 / 桌布线索引合成 `_dispatch_drop()`；W2「拖回原来那扇窗 = 被取回画布」由 `to == from` 的早退覆盖。
- K5 移除「场景 → 档案图标 = 前往」落点：落点表由 11 项减为 **10 项**；`_drop_blocker_at()` 仍拦截并说明「档案只收时间点」，不会穿透画布。
- K7：TEC 的「关闭」= 取消分析并提示，「最小化」= 后台继续并保留进度卡片；与 W9/W11 的窗口语义一致。

### S4 / S5 / S8 执行记录（2026-10-25）

- **S4**：`_rebuild_from_graph()` 删除对 `_music_win/_music_dock` 的无条件 `queue_free`。撤销无关操作时播放器与音频原样保留；撤销「装针」后音乐重新锁定，`_refresh_app_icons()` 仍按锁定态收起播放器。换案仍由 `_new_runtime()` 正常释放。
- **S5**：`_run_inference()` 在 `mark_ending()` 后立即 `GardenSystem.normalize()` 发种，并在 `_commit()` 后立刻 `_autosave()`；`_on_ending_finished()` 只负责收幕展示。`GardenSystem.normalize()` 对「结局已入账、花园空、seed=false」的旧档补发种子与真名旁白；已有株不重复补。
- **S8**：`SaveSystem.restore(s, keep_knowledge=false)` 新增知识合并开关；`undo()` 传 `true`，unread / cardSeen / debuted 以撤销前的当前值覆盖快照值，图结构仍按快照回滚。`restore_json()` / 读档保持原口径，不把运行时知识并进旧档。
- **回归**：`test_p14` 61、`test_p15` 97、`test_p25` 182、`test_ui` 444、`test_p26` 102；全套 1572 项、`test_p28` 4/4 通过。新增 S5 触发即发种 / 旧档补种、S8 撤销知识合并与读档不合并、S4 无关撤销保播放器断言。

### 人物档案卡 + S12（2026-10-25）

- 新增 `PersonCard`：名册点行只开卡，跳转降级为卡内「前往此人」；调查员入册首位，TEC / 执行者 / 普通角色共用同一张卡。
- 备注 `GraphState.notes`（`INVESTIGATOR` 为调查员）进入 `SaveSystem` 快照；撤销保留当前备注，读档按存档恢复，换案隔离。
- `CharDef` 新增 `role / fate / relation`；A-001 角色数据已填，死者卡显示死因，活人显示存活。
- S12：`_goto_char` 检测到对话窗开着时只提层对话，不再误报「暂无对话文本」。
- **回归**：`test_p15` 102、`test_p26` 135；全套 1610 项、`test_p28` 4/4、`mono_audit` 通过。

### U2 / U7 / W1 / W6 / W26 / W27（2026-10-25）

- **U2**：`NarrCard` 转发 `typing_finished` / `is_typing()` / 单击补全；`_refresh_detail` 在叙事打字中挂起详情，播完或关闭后补显示，简介 `show_full_once()` 整段出现。连带 W17（叙事卡单击跳过）与 W21（双击不按旧态闪详情）。
- **U7**：案件卡片改自管手势 `PanelContainer`；`MusicDock` / `TecChip` 增加按下 → 5px 阈值拖动 → 桌面内钳制；拖过后吞掉点击。三者都记 `user_placed`，重排 / resize 只夹取不吸回；换案/重置恢复默认贴边。
- **W1**：`SysWindow` 标题栏事件 `accept_event`；TEC 头像单独吞事件；`MemCard` 标题栏不再冒泡到 `advance()`。
- **W6**：`DetailWin` 改 `enable_controls` 手动关闭；`_user_closed` 让 × 只收起，后台 `_commit` 不复活；再点卡片 / 换节点可重新打开。
- **W26**：`TecWindow.append_line` 落新行前先补全上一行；`_tec_talk` 打字中点击只补全并返回；`_tec_hint` 同文本去重。
- **W27**：`CertWin` 恢复标题栏拖动；签发期仍隐藏 ×（流程强制）。
- **回归**：`test_ui` 456、`test_p21` 76、`test_p22` 103、`test_p23` 171、`test_p25` 185、`test_p26` 135；全套 1639 项、`test_p28` 4/4、`mono_audit` 通过。

### C2/S14 + C4–C6（2026-10-25）

- **C2/S14**：`CaseCatalog.resume_case_id()` 在启动时读 `last`，仅当案件存在、已解锁且数据可装载才采用，否则回 A-001；`Desktop._ready` 用它决定 `_active_case`。
- **C4**：`CertWin` 证件卡删除 `"sense": "vision"`；`Investigator.load_from` 只保留旧档中显式存在的 sense，不再给新证件补默认值。
- **C5**：`_tutorial_correct()` 统一教学期拒收话术；非线索拖推演、物品拖证据等不再落系统 toast，改由 TEC 口头纠正。
- **C6**：`_on_ledger_to_matrix` 补 `STORE_SUPPLIES → INFER` 守卫，并同步 `_tutorial_on_matrix_changed()`，证据行内按钮不再绕开教学步骤。
- **回归**：`test_ui` 465、`test_p21` 78；全套 1650 项、`test_p28` 4/4、`mono_audit` 通过。C3 仍等专属美术。
