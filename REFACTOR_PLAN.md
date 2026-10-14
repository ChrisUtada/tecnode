# index.html 拆分重构方案

> 状态：已执行（2026-10-14）｜ 适用范围：nodes-mvp 项目

## 一、背景与目标

`index.html` 当前 4531 行 / 627KB，全部内容内联在单个文件中，难以维护和扩展。

| 区段 | 行范围 | 内容 |
|---|---|---|
| head | 1–6 | 文档头 |
| `<style>` | 7–574 | CSS（含 ~343KB base64 点阵字体 @font-face） |
| body 骨架 | 576–651 | 桌面层 / 案件窗 / 图标 / 浮窗 DOM |
| gamedata | 652 | 案件 A-001 数据 JSON（一整行，22131 字符） |
| `<script>` | 653–4529 | JS 引擎，232 个函数，已按 `/* ==== */` 注释分成 ~35 个功能区 |

**目标**：把 CSS / JS / 游戏数据拆分为独立源码文件，按功能模块组织，便于后续管理和扩展；同时保持「单文件、双击即玩」的成品形态不变。

## 二、方案选型（已确认）

- ✅ **源码拆分 + 构建脚本**：源码拆到 `src/`，由 `build.js` 拼装出单文件 `index.html`
- ✅ **JS 按功能区拆**：归并现有 ~35 个注释区段为 17 个模块
- ✅ **游戏数据抽出**：独立为 `data/case-a001.json`，为多案件（A-002 等）铺路

否决项：直接多文件引用（失去单文件特性、verify.js 需重写）；ES Module（破坏 file:// 双击运行）。

## 三、已核实的技术约束

1. **verify.js（564 项断言）大量断言直接针对成品 html 源码文本**：CSS 规则正则（如 `/body\{user-select:none/`）、JS 片段（如 `html.indexOf('function settle(){')`）、模板逐行比对（`_template.html` 与 `index.html` 只允许差 gamedata 行）。
   → 拆分必须是**纯物理切割 + 原样拼接**，构建产物与现 index.html **逐字节一致**（gamedata 行除外），verify.js 零改动。
2. **「单文件、双击即玩」是设计特性**（README 明示）→ index.html 保留为单文件成品，改为**构建产物**。
3. 内联 gamedata 已验证等于 `JSON.stringify(JSON.parse(...))`，无 `<\/` 转义 → 构建注入逻辑就是一行 `JSON.stringify`。
4. **`_gamedata.json` 已过期**（还是旧的 `SCENE_shuzhuo` 数据模型，与当前内联数据不一致），且无任何文件引用它。
5. `_sync_tpl.py`（index → template 反向生成）将被 build.js 正向生成取代。
6. JS 各功能区共享顶层作用域；拼接成同一 `<script>` 后作用域关系与今天完全一致，**不需要 import/export 改造**，零逻辑风险。

## 四、目标目录结构

```
src/
  shell.html          # 文档骨架（head + body），3 个占位符：@@CSS@@ / @@GAMEDATA@@ / @@JS@@
  css/
    01-font.css       # @font-face base64 字体（约 343KB，独立隔离）
    02-base.css       # :root 变量、body、滚动条、user-select
    03-desktop.css    # 桌面层 / 案件窗 / 顶栏外壳
    04-nodes.css      # 节点 / 连线 / 角标 / 拖拽镜像层
    05-windows.css    # 系统窗 / 浮层 / toast / 详情 / 日志 / 叙事卡 / 气泡
    06-apps.css       # 桌面图标、TEC 卡片、证物袋、线索册、人物、档案、案件地图、逻辑阵列、结局、适性测试
  js/
    01-data.js        # 案件数据装载 applyCaseData + SENSES + DOM 引用      (现 653–698)
    02-state.js       # 图状态 blankGraph/snapshot/restore                    (699–735)
    03-utils.js       # 工具 + 光照判定 + 反应索引 + 容器/场景解析           (736–918)
    04-graph.js       # 图操作 ensureNode/link/revealScene/spawnItems         (919–1012)
    05-combine.js     # 合成（拖 A 到 B）+ 捕获 hiddenClue                    (1013–1180)
    06-storage.js     # 场景折叠收纳 + 节点收纳 + 证物袋                      (1181–1341)
    07-render.js      # 力导向布局 + 渲染                                     (1342–1582)
    08-interact.js    # 节点交互 + 镜头自动平移                               (1583–1918)
    09-commands.js    # 物品命令 + 光源光晕 + 密码弹窗 + 选项命令             (1919–2109)
    10-windows.js     # 统一系统窗口 + 浮层通用拖动                           (2110–2185)
    11-dialog.js      # 对话队列/气泡 + 叙事卡 + TEC 对话窗 + TEC 分析        (2186–2754)
    12-panels.js      # 选中聚焦 + GOTO 档案 + 线索册 + 人物名册              (2755–3034)
    13-matrix.js      # 逻辑阵列 + 结局演出 + 记忆放映卡                      (3035–3390)
    14-detail.js      # 详情面板                                              (3391–3553)
    15-desktop.js     # 画布平移缩放 + 桌面图标 + 顶栏按钮                    (3554–3742)
    16-cases.js       # 适性测试/调查员证 + 案件库/地图 + 存档切换 + 离屏落点  (3743–4388)
    17-boot.js        # 启动 boot() + window.__ 测试钩子                      (4389–4529)
data/
  case-a001.json      # 案件 A-001 数据（美化格式，从现 index.html 内联提取）
build.js              # 构建脚本（Node，无依赖）
index.html            # 【构建产物】单文件成品，勿直接编辑
_template.html        # 【构建产物】gamedata 为 __GAME_DATA_A001__ 占位符
```

切割边界一律落在现有 `/* ==== */` 区段注释上（JS）和现有 CSS 注释块上，**不跨函数切割**；上表行号是切割蓝本，执行时以区段注释为准微调。

## 五、执行步骤

**0. 留参照**
`cp index.html _index.ref.html` —— 作为字节比对的基准，全部验证通过后删除。

**1. 提取案件数据 → `data/case-a001.json`**
Node 一行脚本：从 index.html 正则取出 gamedata 行 → `JSON.parse` → 2 空格美化写出。同时断言 `JSON.stringify(解析结果) === 原内联行`。

**2. 生成 `src/shell.html`**
取现 index.html 的 1–6 行 + 576–651 行 + 首尾标签，三个内容位替换为占位符：
- `<style>\n@@CSS@@\n</style>`
- `<script type="application/json" id="gamedata">@@GAMEDATA@@</script>`（占位符与 JSON 同一行，保证 gamedata 仍是一整行）
- `<script>\n@@JS@@\n</script>`

**3. 切割 CSS → `src/css/01–06`**
按蓝本从 7–574 行切出。**铁律：每个切片文件不含结尾换行，构建时用 `"\n"` 连接**，保证拼接还原逐字节一致。

**4. 切割 JS → `src/js/01–17`**
同上，从 653–4529 行切出（`"use strict";` 进 01-data.js 开头）。纯移动，不改任何一个字符。

**5. 编写 `build.js`**（Node，无第三方依赖）
- 读 `src/shell.html`、`src/css/*.css`（按文件名排序，`join("\n")`）、`src/js/*.js`（同理）、`data/case-a001.json`
- 输出 `index.html`：占位符替换，gamedata 用 `JSON.stringify(JSON.parse(raw))` 注入（单行）
- 输出 `_template.html`：同上，但 gamedata 位写 `__GAME_DATA_A001__`（沿用现有占位符约定，verify.js 的模板一致性检查自然通过）
- 支持 `node build.js --check`：只构建到内存，与 `_index.ref.html` 比对（gamedata 行归一化后逐行 diff），不一致时打印首个差异行并以非零码退出

**6. 验证（验收标准，全部必须通过）**
1. `node build.js --check` → 与参照文件逐字节一致（gamedata 行除外）
2. `node build.js` 正式写出两个产物
3. `node verify.js` → 564 项断言全绿（零改动直接通过，因为产物字节级等价）
4. 浏览器真机抽查：双击 index.html → 过适性测试 → 展开花园 → 拉开书桌 → 抽屉 → 点灯，画面与交互正常

**7. 清理与文档**
- 删除 `_index.ref.html`（参照用完）
- 删除 `_gamedata.json`（已过期且无引用，由 `data/case-a001.json` 取代）
- 删除 `_sync_tpl.py`（由 build.js 正向生成取代）
- `index.html.bak`~`.bak4` 是历史备份，**保留不动**
- 更新 README「文件」一节：新的目录结构、`node build.js` 构建流程、「新增一个案件」改为「在 `data/` 加 JSON + 改 build.js 案件表 + `node build.js`」；其余文档内容不变

## 六、后续维护方式

- 改功能 → 编辑 `src/js/` 对应模块 → `node build.js` → `node verify.js`
- 改样式 → 编辑 `src/css/` 对应文件 → 同上
- 改案件数据 → 编辑 `data/case-a001.json` → 同上
- index.html / _template.html 不再手工编辑

## 七、明确不做的事

- 不引入 ES Module / import-export（拼接即还原，无必要，且会破坏 file:// 双击运行）
- 不引入 npm / 打包器 / 任何第三方依赖
- 不改任何 JS 逻辑、CSS 规则、HTML 结构（本次纯物理拆分）
- 不动 `_cdp_*.cjs` 真机测试脚本（它们操作的是 index.html 副本，产物等价故不受影响）
