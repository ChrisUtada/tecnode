# T.E.C-OS · Godot 移植工程（ydgodot/）

> 迁移根目录。**后续迁移的所有内容都在这里**：工程、资源、测试、烘焙产物、转换脚本、文档。
> 计划与阶段目标见 [`GODOT_PORT_PLAN.md`](./GODOT_PORT_PLAN.md)。

## 当前状态：P2 收口；P3 视觉对拍 2.30%（目标 0.50%）；交互层 P0 八项已落地

- **P0 垂直切片**：可跑（下面这条链路）
- **P1.1 JSON → Resource 迁移**：✅ 数据全部落在 `cases/a001/**/*.tres`，运行时**不再读 JSON**
  - 逐字段对照回归 `test_migration.gd`：11 场景 / 36 物品 / 5 人物 / 20 线索 / 6 回忆 / 3 对话 / 5 结局，**全字段一致**
  - 182 条字符串引用 → **类型化引用**（重命名/移动时引擎自动维护），悬空 0 条
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
- **P2.3 回忆系统**：✅ 已落地
  - 时间轴：`memoryScenes` 驱动三档（现在 / 6月2日 / 7月4日），档案窗倒序列出已知时刻、地点 / 人物 / 摘要和「当前 / 已回顾 / 新」状态
  - 切档：改 `graph.time` 后重算可见性、带出 `debut == 该时刻` 的人物、保持原有卡片位置；首次进入自动放放映卡，已读档不重复自动播
  - 放映卡 `MemCard`：暗纸 / 双线黑框、45ms/字打字机、点击补全或推进、整卡拖动、锚在发生地点上方且不压住节点
  - 回忆小剧场：时刻 × 人物 × 地点命中 `memories` 后开演，旁白 + 带头像（缺图退首字）的多人台词；不捕获线索，失败给明确提示
  - 登场门控：`debut`、`visible_node`、时间 × 空间 × 探索三重判定接入桌面显隐与收纳取回
  - 回归：`test_p23.gd` 164 项（数据契约 / 时间图层 / debut / 快照 / 档案窗 / 放映卡 / 小剧场）
- **P2.4 多人对话系统**：✅ 已落地
  - `DialogueSystem` / `DialogueSession`：语境（when × where）先 fit 再 free，miss 不播；精确集合优先，三人剧本可由两人先命中，第三人后加入
  - `ChatWindow`：右上角 390 宽、高度随内容伸缩、45ms/字打字机、点击补全/推进、旁白 + 带头像台词、贴底不裁末行
  - 中途加入：有台词的人不在场时暂停并提示「把「X」拖进对话框」；拖对人续播，拖错提示「插不上话」；非人物提示「只有人物能加入这段对话」
  - 独白：单参与者剧本按当前语境筛选；入口是详情窗的「播放独白」按钮（交互层 P0 补上了详情窗，此前只有「双击人物卡」一条路）
  - 生命周期：切时刻 / 重置 / 切案 / 撤销恢复 / 重建运行时都会关窗，会话不跨时间
  - 回归：`test_p24.gd` 102 项（语境匹配 / loose 选中 / fallback / 状态机 / 打字机 / 拖人 / 独白 / 生命周期）
- **P2.5 音乐播放器 / 花园彩蛋**：✅ 已落地
  - 解锁：唱针（`ITEMS_cz`）装到唱机（`ITEMS_changji`）后，左侧出现「播放器」图标；失去安装态（撤销 / 读档）时播放器、dock 一并收起
  - 音乐：`MusicWin` 收录 `Air (Bach)`，支持播放 / 暂停 / 停止 / 点击进度跳转；关闭窗不打断，`–` 收成右下角 238×60 `MusicDock`，点图标或卡片还原
  - 种子：TRUE_E「确认捕获」后发种子，只发一次且不覆盖已有旁白；矩阵窗种子气泡可拖到花园图标或已开的花园窗，种下前拍快照，拖株 / 开花只自动存档
  - 花园：`GardenWin` 五阶段真实时间生长（0 / 45 / 90 / 135 / 180 秒：种子 / 嫩芽 / 展叶 / 舒叶 / 开花），落点与株位限定在花圃内；已种下的株可继续拖动
  - 旁白：开花后点花株开正文，按句 / 逗号切段（约 150 字/段），点击补字或翻页，面板随内容伸缩；正文取 `TRUE_E.message`（371 字），旧档缺 `garden` 且有 TRUE_E 时自动补种子
  - 回归：`test_p25.gd` 146 项（花园核心 / 老档迁移 / 播放器与 dock / 图标收放 / 种子投放 / 拖动 / 旁白 / 存档）
- **交互层 · P0 八项**：✅ 已落地（2026-10-21 夜，差距清单见 `docs/INTERACTION_GAP_REPORT.md` §0.1，实证截图 `docs/p0_canvas.png`）
  - 世界层：卡片活在 2000×1300 的 world 空间（`_card_layer.size`），只承担平移 + 以光标为锚的缩放（0.35–1.8）；坐标基准统一走 `NodeCard.visual_rect()`（含 8px 阴影余量），布局 / 连线端点 / 命中判定三处共用
  - 连线 `EdgeLayer`：二次贝塞尔采 24 段，四种样式照抄 `04-nodes.css`（entity 1.3px `#8a8672` / move 1.6px 实线 / cond 1.6px 虚线 5-4 / tried 1px 虚线 3-4 @55%），虚线按弧长手工切；`tried` 单独读 `graph.tried`，不混进 `graph.edges` 污染弹簧与度数
  - 单击 / 双击分离：按下只记位置，松手未位移 = 选中，280ms 内第二下 = 激活（拖动也开始选中）
  - 位置写回：松手写 `n["x"]/n["y"]` 并夹回 world 边界 + `_commit()`（旧版从不写回，下一次重排必然推翻玩家摆位）
  - 力导向布局：斥力 30000/d²、最小间距 `R_a+R_b+14`、弹簧 185/300/150、向心 0.0022、260 轮，参数逐条照抄 `07-render.js`；只给 `x < 0`（从没落过位）的节点播种，`pinned` 全程不动
  - 右键钉住：「已固定」药丸挂在左上角；拖动**不再**自动钉住（钉住只有右键一个入口）
  - 落点表：`_drop_targets()` 单一清单 11 项（3 窗口 + 5 图标 + TEC 头像 + 助手卡片 + 推演桌布），悬停高亮与松手分派共用同一份，卡片命中后 `spring_back()` 300ms 弹回
  - 反应表通道：`ComboSystem.use_item` 顺序 目标反应表 → 工具反应表 → `useItem` 命令 → 容器扫描，失败记 `tried`；实测 27 条反应（物品触发 14 + 线索触发 13）
  - 详情窗 `DetailWin`：只列简介 / 状态 / 来源（刻意不列"装着什么/谁指向它/跟谁有反应"），底部四个重看按钮；点空白收起
  - 回归：`test_ui.gd` 79 项（P0 新增 26 条：单击不激活 / 右键钉住 + 角标 / 坐标写回 / 拒收回原位 / 落点 11 项白名单 / 连线层有线段 / 滚轮缩放 / 点空白清选中 / 详情窗 / 反应表 / 袋行拖回落在松手点；批 2 新增 12 条见下）
- **交互层 · 批 1（名册 / 日志 / 图标栏）**：✅ 已落地（差距报告 §0.2，实证截图 `docs/p2_21_people.png`、`docs/p2_22_log.png`）
  - 人物名册 `PeopleWin`（`ROSTER // 人物`，324×399 body）：常驻两人（TEC / 执行者）在前，其余按 id 排序；「已结识」= 画布上有已登场节点 ∪ 到过某时刻（`card_seen`）∪ 探索过 `sceneTalks` 覆盖的场景，**纸面提及不算**
  - 名册行：48×48 头像（TEC / 执行者用各自窗里那张，其余首字方块）；状态列只给状态词（`助手窗` / `逻辑阵列` / `未交谈` / `可继续` / `已聊完` / `无对话文本`），**不给 x/y 计数**
  - 名册动作：点常驻行 = 开 TEC 窗 / 推演桌布；点普通行 = 叫到镜头中央 + 选中 + **说下一句**（`charTalkQueue` = `talkQueue` + 他所在场景的 `sceneTalks`，此前 Godot 只用 `talkQueue`，是隐性偏差）
  - 因果追踪 `LogWin`（`SYS_LOGS // 因果追踪`，320×383 body）：条目按 kind 上样式（`sys` 加粗 + `▍ ` / `warn` 灰 + `※ ` / `err` 反白 / `cap` 下划线 / `act` 浅底），自动滚到底，空档给占位行
  - 日志口径照抄 `03-utils.js:250-262`：**只记结果**（捕获线索 / 组合成与败 / 前往 / 一切失败与拦截 / 开局换案 / 「另有 N 个节点留在画布上」），不记展开收起、收入取出、台词本身、撤销重置
  - 日志未读：窗关着时 `_log_unread` 累加并挂到「日志」图标角标，开窗清零
  - 图标栏 8 项（`ICON_DEFS` = 推演器 / 档案 / 线索册 / 人物 / 证物袋 / TEC / 日志 / 案件地图）+ 动态 2 项（播放器 / 花园）；脱离 `VBoxContainer` 改绝对定位（left 18 / top 16 / 步距 85，图标变多时按 `resetIconPositions()` 压到 70 下限）
  - 图标可自由拖动（5px 阈值内算点击、超出算拖动，夹在桌面矩形内），只改位置、**不进撤销栈、重置不回位**；`DeskIcon` 从 `Button.pressed` 改成自管指针手势，拖动后不会再误触发一次点击
  - 四角标：推演器「N 条」（桌布已归位数）、证物袋「N 件」、线索册「N 条」、日志「未读」
  - 组合成功**不再弹提示条**（对齐 `05-combine.js:155-160`）：结果靠画面自证，正文与「获得 / 消耗」只进案卷（修差距报告 C8）
  - 回归：`test_p26.gd` 85 项（日志底层 / 名册收录规则 / 队列与进度 / 图标 8 项与步距 / 自由拖动不进撤销栈 / 四角标 / 日志窗样式与未读 / 日志口径 / 名册点行 / 双击图标开窗）
- **交互层 · 批 2（幽灵线 / 带坐标 chip）**：✅ 已落地（差距报告 §0.3）
  - 拖动幽灵线（差距报告 E2）：拖卡时 `EdgeLayer` 画一条 2px 实虚线（6-5 @ 0.85）从被拖卡中心直连指针 —— world 空间挂在连线层上，平移/缩放自动跟随；松手（或命中落点）即收线
  - 桌布 chip → 画布**带坐标**（反向 8 条路径的最后一条）：`MatrixWin` chip 拖出即发 `clue_dropped(key, at_global)`，`Desktop._on_matrix_took()` 把卡片落在松手那一点并写回 `n.x/n.y`（换算与 `_finish_sdrag` 同一条公式）；**双击 = 无坐标取回**沿承原「取下」按钮口径
  - chip → 线索册**窗或册图标**：两个落点都收进册子（对齐 Web `overLedgerDrop` 两条，此前只认册窗）
  - 回归：全套无头 **14 个脚本 1055 项 0 失败**；`test_ui.gd` 67 → 79（批 2 新增 12：桌布窗可开 / 测试前提 3 · 幽灵线出现 / 起点中心 / 终点跟随 / 松手收起 4 · chip 回画布 / 落在松手点 / 坐标写回 3 · chip 收进册 1 · 芯片在桌 1）
- **交互层 · 批 3（P2 细节批）**：✅ 已落地（差距报告 §0.4：N7 / N8 / V4 / V5 / V6 / D6）
  - 「无文本入口」药丸（V5 / Web `badge warn`）：`GraphState.is_no_entry()` 谓词四件套（未探索 + `[loc:]` 文本入边 0 + 命令产出通路 0 + 自己没出口）；a001 里唯一命中的是「地毯下的暗门」；药丸挂右上槽、与「新」同位，「新」盖在上层
  - 入场 pop（V4 / Web `.node.pop`）：fresh 节点初生 scale .4→1.12→1 + 淡入 0.45s，`fresh` 一次性消费、`unread`「新」角标保留；`--shot` 模式不弹（对拍要稳）
  - hover（N8）：`set_hover_state` 接上鼠标进出（shade_soft 7→10），悬停手形光标 / 拖动全局 `CURSOR_DRAG`、松手归还
  - 聚焦淡化 alpha .25 → **.32**（V6，对齐 `.node.dim`）
  - 场景命令（N7）：`SceneDef.commands` 字段进迁移；双击带命令的场景**先跑 `commands[0]` 再说**，无命令才展开折叠；a001 数据 0/11 场景用到，断言走运行时注入
  - 拖动镜像（D6 / Web `#drag-layer`）：拖起整卡「假身」浮到所有窗之上、原卡隐藏，松手换身回来；被拖卡的连线照常续画（`_drag_key` 豁免）
  - 回归：全套无头 **14 个脚本 1086 项 0 失败**；`test_ui.gd` 79 → 110（批 3 新增 31：warn 7 · pop 6 · hover 3 · dim 2 · 场景命令 5 · 镜像 8）
- **交互层 · 批 4（残余三项收口）**：✅ 已落地（差距报告 §0.5）
  - 反应表产出（R1 / Web `05-combine.js:112-123`）：`ReactionDef.results` 进迁移；`ComboSystem._apply_reaction` 三通道——`results.scene` 建场景 + fresh/unread + **新建才连** `cond` 边；`results.items` 与 `onSuccess.items` 同批走 spawnItems 公式（已上画的旧物品不重 fresh 不挪位，新物品在主人右下 `60 + i*26` + 继承 `home_scene`）；正文 `[clue:]` 照旧。命令侧 payload 通路更早已由 `CommandSystem._apply_payload` 接通
  - 重排位置过渡（R2 / Web `.node{transition: left/top .34s cubic-bezier(.4,0,.2,1)}`）：`_relayout(animated)` —— **折叠 / 展开触发的重排**才播 0.34s cubic 过渡 + 连线逐帧跟着画（`paintEdgesFor(420)` 同口径）；普通重排保持秒到（无头回归与坐标语义都依赖「重排=即刻就位」）；新节点 / 截图流水线直接落位
  - 系统窗 z 序（R3 / Web `05-apps.css`+`06-shell.css` z-index 表）：`ZR_*` 十二档 + `_place_z()`（插到第一个更高 rank 之前、同级按打开顺序）——`case_win(1)` → pw(15)/narr(16) → log(21)/detail(22)/dock(23) → icons(24) → 普通窗(25) → chat(26) → TEC(28) → toast(30) → 镜像(40)；mouse_to_front 全部替换为 rank 插队
  - 回归：全套无头 **14 个脚本 1119 项 0 失败**；`test_ui.gd` 110 → 143（批 4 新增 33：过渡 7 · 反应表 19 · z 序 7）
- **P3 视觉追平**：🔧 进行中，**全屏 diff 7.00% → 2.30%**（1280×800 / 阈值 8，计划目标 < 0.5% 且文字区外为零）
  - 对拍流水线：`tools/pixeldiff/capture_web.cjs`（CDP 无头 Edge，关 LCD 次像素）→ `--shot-p3` → `compare.py`（分区统计 + 差异图 + `start.json`）
  - 已消灭：窗框九切片烘焙（`assets/baked/win_frame.png`，`patch_margin=46`，外沿差异 **0**）、页眉几何逐坐标对齐、**页眉控件高 31 → 25/27**（Button 最小尺寸反顶 `set_size`，见 `_sync_header_sizes`）、枢纽场景双线框、图标块（渐变 150°、描边 alpha、字形高 10px、标签 4px、阴影软度）
  - 剩余：各处文字 AA（Godot 硬边 vs Web 灰度覆盖率，计划 §七 已约定「接受 AA 微小差异」）；图标栏「人物」「日志」两个空槽已随批 1 补齐（原 ≈ 0.54 pt），**待重跑 `--shot-p3` 复测总分**
  - 交互层上线后重拍：与上线前**逐像素 `max diff = 0`**，2.30% 基线原样有效
  - 契约：`test_ui.gd` 79 项含 9 条 P3 断言（页眉高 52 / 品牌 14px / 七件套 x 坐标 / 证章 318,190 / 九切片 patch_margin / 枢纽卡双线框）
  - 账目：`.workbuddy/memory/2026-10-21.md`

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

另一条已接通的线：左侧「档案」→ 时间轴切档 → 首次进入自动放映 → 人物 × 地点凑齐时开回忆小剧场。
第三条：人物 × 人物 → 多人对话（有剧本按语境播，没有给 fallback）→ 中途缺人可拖人物续播；双击有独白的人物开独白。
第四条：唱针装唱机 → 播放器 / 右下角卡片；真结局种子 → 矩阵拖进花园 → 真实时间开花 → 分段旁白。

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
"$GODOT" --headless --path ydgodot --script res://tests/headless/test_p23.gd
"$GODOT" --headless --path ydgodot --script res://tests/headless/test_p24.gd
"$GODOT" --headless --path ydgodot --script res://tests/headless/test_p25.gd
"$GODOT" --headless --path ydgodot --script res://tests/headless/test_p26.gd

# 3.5) 重跑数据迁移（JSON → .tres；只在确认数据基准后跑）
"$GODOT" --headless --path ydgodot --script res://tools/json_to_tres.gd

# 4) 视觉自查：跑一遍切片，把 15 张截图存进 docs/
"$GODOT" --path ydgodot --resolution 1280x800 -- --shot

# 4.5) 开场 / 调查员证截图（6 张，写到 docs/p1_1*.png）
"$GODOT" --path ydgodot --resolution 1280x800 -- --shot --shot-intro

# 4.6) 案件 / TEC / 回忆 / 对话 / 音乐 / 花园 / 名册 / 日志截图（22 张，写到 docs/p2_*.png）
"$GODOT" --path ydgodot --resolution 1280x800 -- --shot-p2
```

- `--fast`：把「分析计时」「结局分幕延迟」压到 0（无头/测试旁路，见计划 §四.3）。
- `--shot`：跑固定剧本并截图（`docs/p0_*.png`、`docs/p1_*.png`）。截图需要真实渲染，**不能加 `--headless`**。
- `--shot-p2`：跑案件地图 / 收起 / 关闭 / 解锁 + TEC 对话 / 分析 / 助手卡片 / 档案 + 档案窗 / 放映卡 / 回忆小剧场 + 多人对话 / 等待加入 / 独白 + 音乐播放器 / 右下角卡片 + 种子 / 花园 / 旁白 + 人物名册 / 因果追踪共 22 张截图；使用临时进度档，退出时清理。
- `--no-intro`：跳过开场适性测试（无证时也不弹）。

## 目录

| 路径 | 内容 |
|---|---|
| `core/` | 纯逻辑（不挂场景树，可无头测）：`CaseLoader` / `GraphState` / `ComboSystem` / `SaveSystem` / `Investigator` / `CaseCatalog` / `DialogueSystem` / `DialogueSession` / `GardenSystem` |
| `scenes/` | `Desktop.tscn` + `Desktop.gd`（壳与接线）、`cards/NodeCard.gd`（节点卡与指针手势）、`canvas/EdgeLayer.gd`（连线层）、`windows/*` |
| `ui/` | `TecTheme.gd`（配色/字体/StyleBox）、`shaders/surface.gdshader`（浮雕）、`shaders/paper.gdshader`（纸纹） |
| `cases/a001/` | **内容数据（唯一形态）**：`case.tres` 索引 + `scenes/` `items/` `chars/` `clues/` `memories/` `dialogues/` `endings/`，一实体一文件 |
| `core/defs/` | 25 个自定义 Resource 类（`SceneDef` / `ItemDef` / `CommandDef` 六子类 / `CharDef` …） |
| `data/` | `case-a001.json` —— **已冻结为只读档案**（迁移输入 + 对照基准，运行时不再读它） |
| `assets/raw/` | `src/assets/` 的拷贝（字体 / 头像 / OGG / 花园序列帧） |
| `tests/headless/` | `test_p0.gd`（逻辑 20）、`test_ui.gd`（真鼠标事件 143）、`test_migration.gd`（JSON ↔ `.tres` 逐字段 15）、`test_commands.gd`（六型命令 49）、`test_p12.gd`（图状态全量 37）、`test_p14.gd`（桌布 / 结局 56）、`test_p15.gd`（快照 / 撤销 / 存档 85）、`test_p16.gd`（开场 / 调查员证 61）、`test_p21.gd`（案件系统 71）、`test_p22.gd`（TEC 生态 84）、`test_p23.gd`（回忆系统 164）、`test_p24.gd`（多人对话 / 独白 103）、`test_p25.gd`（音乐 / 花园 146）、`test_p26.gd`（名册 / 日志 / 图标栏 85）—— **共 1119 项** |
| `docs/` | P0 切片 6 张 + P1 新特性 15 张 + P2 案件 / TEC / 回忆 / 对话 / 音乐 / 花园 / 名册 / 日志 22 张截图，共 43 张（P3 对拍基线从这些图起步） |
| `tools/` | P1 的 `json_to_tres.gd` 与对拍工具（待建） |

## 已做 / 明确没做

**已做**

- 数据装载 + 文本协议（`[item:X]` 标签换中文名、`<br>` 转换行、单复数前缀都认）
- 图状态：展开场景长出实体节点、幂等、`entity` / `move` / `cond` 边、收纳三态、快照撤销
- 组合与命令：发光工具门（未点亮拦下、不记 tried）、`useItem` 命中、`onSuccess.scene` 揭示、反应表五段通道
- 画布：world/view 分离（2000×1300）、力导向布局、以光标为锚缩放 0.35–1.8、平移、位置写回与边界夹回
- 连线：四种边（entity / move / cond / tried），二次贝塞尔 24 段采样，虚线按弧长切
- 节点交互：单击选中 / 双击激活 / 右键钉住 / 拖动（5px 阈值+镜像）/ `spring_back()` 弹回
- 交互细节：hover 手形与阴影（N8）/ 入场 pop（V4）/ 无文本入口药丸（V5）/ dim .32（V6）/ 场景命令前置（N7）
- 落点：11 项单一表（3 窗口 + 5 图标 + TEC 头像 + 助手卡片 + 推演桌布），悬停高亮与松手分派共用
- 窗口基类：拖动标题栏、关闭、内容流 / 定位容器分离
- 详情窗：简介 / 状态 / 来源 + 四个重看按钮
- TEC 对话 / 分析：5–8 秒进度条 + `--fast` 旁路 + 闲聊 + 档案解读 + 右下角助手卡片
- 结局演出：分幕台词按 `delay` 落下、点击继续、遮罩收幕
- 无头回归 **14 个脚本 1119 项**，全绿

**没做（P4 / 后续）**

- 无 —— README 以前列的三条（反应表产物 / 折叠过渡 / 系统窗 z 序）已随批 4 全部落地（差距报告 §0.5）。

## 与 Web 版的已知偏差

| 项 | Web 版 | Godot 现状 |
|---|---|---|
| 纸纹 / 浮雕 | 内联 SVG 噪波 + 多层 box-shadow | **shader 程序生成**（`paper.gdshader` / `surface.gdshader`）——P3 若换烘焙 PNG，只替换材质 |
| 节点布局 | 力导向 + 折叠/展开过渡动画 + 镜头自动平移 | 力导向参数**逐条照抄**（斥力/间距/弹簧/向心/260 轮）；折叠/展开重排跑 0.34s 过渡（批 4，普通重排保持瞬时——无头回归依赖即刻落位）；镜头平移只有「前往」一处 |
| 叙事卡 | 锚在触发节点上方、可拖 | 已锚定（`anchorAboveOrBelow`）且可拖，锚定前先落第一行再量高 |
| 手电筒来源 | 书桌 → 左侧抽屉 → 手电筒 | `--shot` 剧本开局直接放在画布上；正常游玩走书桌链路 |
| 数据形态 | `data/case-a001.json` 直读 | `cases/a001/**/*.tres`（P1.1），JSON 冻结为档案 |
| 结局触发 | 推演桌布命中配方 | 已接推演桌布；`--shot` 仍直接播放 `TRUE_E` 以保留 P0 对拍基线 |
| 调查员头像库 | 常驻两人 + 已结识人物，领证后可再更换 | 常驻两人 + 画布上已出现的人物；回看证件已接，换头像 / 人名册属后续 |
| 独白入口 | 人物详情窗按钮 | 已追平：详情窗「播放独白」按钮 |
| 落点表 | `nodeDropTargets()` 10 项 + 松手处单独判桌布 | 合成一条 11 项（多的是推演桌布） |
| 字体回退 | VonwaonBitmap → SimSun → … | 全字形字体直导，**不配 fallback** |

## 约定

- `core/` 里的类**不继承 Node**，方便无头跑。
- 所有「延时后完成」的逻辑必须带「立即完成」旁路（`--fast` / `finish_now()`）。
- 测试钩子（`dbg_*`）只做**同名翻译**，命名对齐 Web 版 `window.__*`，方便把操作脚本逐行搬过来。
- 迁移期不改数据 schema（见计划 §九）。
