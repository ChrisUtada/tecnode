/* ============ 工具 ============ */
function esc(s){
  return String(s == null ? "" : s)
    .replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
}
function stripTags(text){ return String(text || "").replace(TAG_RE, m => m); }
function plain(text){
  return String(text || "")
    .replace(/\[(item|loc|char|clue):(.+?)\]/g, (m, k, id) => labelOf(k, id) || id)
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/<[^>]+>/g, "");
}
const TAG_RE = /\[(item|loc|char|clue):(.+?)\]/g;
function parseTags(text){
  const seen = {}, out = []; let m;
  TAG_RE.lastIndex = 0;
  while ((m = TAG_RE.exec(text || "")) !== null){
    const kind = m[1], id = m[2].trim(), k = kind + ":" + id;
    if (!seen[k]) { seen[k] = 1; out.push({kind, id}); }
  }
  return out;
}
/* ============ 时间节点（第五类） ============
   6月2日 / 7月4日 这类「日期闪回」在画布上是独立的一类节点（kind:"time"），
   可展开、可组合，但它**仍从 SCENES 表读数据** —— 身份由 config.memoryScenes 裁决。
   之所以不把数据迁去独立的 times 表：那样要连带改 7 处 sceneTalks 的 key、
   content 里的 [loc:] 标签、摘录的 to 字段与 config.memoryScenes 自身，收益不值。
   于是「是不是时间节点」只在这一个函数里判一次，全项目共用。 */
function isTimeId(id){ return SCENE_MEMORY.indexOf(id) >= 0; }
/* 场景类节点（场景 / 时间）：凡是「双击展开、有 content、算通路」的判定都要同时认这两类 */
function isSceneKind(k){ return k === "loc" || k === "time"; }
/* 从「数据里的引用」推「画布上的节点键」。
   数据侧的标签与摘录 to 仍写 [loc:SCENES_0602]（时间节点没有迁表），但画布上它的键是 time:SCENES_0602。
   凡是要拿引用去查 / 建画布节点的地方，都必须过这一道 —— 否则会凭空造出一个 loc: 节点，
   与 containerKey() 算出的 time: 分裂成同一 id 的两个节点。 */
function nodeKeyOfRef(kind, id){ return isSceneKind(kind) ? containerKey(id) : kind + ":" + id; }
/* ============ 时间轴 / 时刻图层（方案 B，P1 内核）============
   时间不再只是「一类节点」，而是画布的一个维度：G.time 记当前所在时刻。
   "present" = 现在（基准层，显示全部节点）；其余时刻取自 config.memoryScenes，
   某时刻的节点集**由回忆数据派生**（data.memories）：该 when 下所有 where 的地点 +
   who 的人物 —— 不新建节点，只按时刻显隐（见 visibleNow）。

   与空间折叠（n.hidden / G.collapsed，由 recomputeHidden 管）**正交**：
   最终可见 = visibleNow(n) && !n.hidden && !n.stored。两维各写各的标志，互不干扰。 */
const PRESENT_TIME = "present";
/* 派生「某时刻的节点键集合」；present 返回 null（= 全显，不做时间过滤）。 */
function timeStageKeys(t){
  if (t === PRESENT_TIME) return null;
  const keys = new Set();
  (MEMORIES || []).forEach(m => {
    if (m.when !== t) return;
    if (m.where) keys.add(containerKey(m.where));        /* 地点：场景节点（loc:xxx） */
    if (m.who)   keys.add(nodeKeyOfRef("char", m.who));  /* 人物：角色节点（char:xxx） */
  });
  return keys;
}
/* 「现在」那一档的显示名：案件可在 config.nowLabel 写明它对应的日期（A-001 = 7月5日，
   见 SCENES_garden 正文「时间：7月5日」）；没写就退回「现在」。 */
function nowLabel(){ return (DATA && DATA.config && DATA.config.nowLabel) || "现在"; }
/* 时间轴各档：present 在首位，其余按 SCENE_MEMORY 顺序。P2 的 UI 与 §41 都用它。 */
function timelineStages(){
  const out = [{ id: PRESENT_TIME, label: nowLabel(), keys: null }];
  (SCENE_MEMORY || []).forEach(id => {
    out.push({ id: id, label: (SCENES[id] && SCENES[id].title) || id, keys: timeStageKeys(id) });
  });
  return out;
}
function currentStage(){
  const t = (G && G.time) || PRESENT_TIME;
  const list = timelineStages();
  return list.find(s => s.id === t) || list[0];
}
/* 时间可见性：当前时刻的节点集里没有它 ⇒ 不可见；present 档全通过。 */
function visibleNow(n){ if (!n) return false; const st = currentStage(); return !st.keys || st.keys.has(n.key); }
/* ============ 人物登场门控（2026-10-16）============
   「文本里提到」≠「遇到了」：访客记录纸面提到朱穗、摘录点名槿杉，都不该让她上画布。
   人物的**最早登场点**由数据显式配置（CHARS[id].debut = 时刻 id 或现在档场景 id）：
     · 朱穗 debut=7/4 回忆（只能在那被找到）；陆珩松 debut=lhsdst（现在档房间）；
     · 槿杉/傅柏 debut=6/2（只在回忆）；TEC 没配 = 常驻不门控。
   两道门：
     · charDebuted —— 玩家到达过 debut（进过那个时刻 / 探索过那个场景），置位在 G.debuted；
     · charNowMet —— 「现在」档的登场（sceneTalks 里最早的非回忆场景被探索）。
   回忆档可见 = 时刻派生含她 且 charDebuted（陆没在 lhsdst 出现前，7/4 里也不出现）；
   现在档可见 = charNowMet（朱穗回到 7/5 要等「门的后面」，不会因为进过回忆就提前）。 */
function charDebut(id){ const c = CHARS[id]; return (c && c.debut) || null; }
function charDebuted(id){
  const d = charDebut(id);
  if (!d) return true;
  return !!(G.debuted && G.debuted[id]);
}
/* 到达 debut（幂等）：spawnMemCast 进入时刻 / revealScene 探索场景时调用 */
function meetCharAt(id, sid){
  if (charDebut(id) !== sid) return;
  if (!G.debuted) G.debuted = {};
  G.debuted[id] = true;
}
/* 人物在「现在」档的登场点：sceneTalks 里第一个非回忆场景；没有 = 现在档不登场。 */
function charNowScene(id){
  const st = (CHARS[id] || {}).sceneTalks || {};
  return Object.keys(st).find(sid => (SCENE_MEMORY || []).indexOf(sid) < 0) || null;
}
function charNowMet(id){
  if (id === "CHARS_TEC") return true;
  const s = charNowScene(id);
  return !!s && G.explored.has(s);
}
/* 综合可见（时间 × 空间 × 登场）：渲染 / 交互 / 聚焦一律认这一个。 */
function visibleNode(n){
  if (!n || n.hidden || n.stored) return false;
  if (n.kind === "char"){
    if (!charDebuted(n.id)) return false;      /* 没到 debut：任何档都不出现 */
    if (!visibleNow(n)) return false;          /* 时刻派生：这一档没她的戏份 */
    const st = currentStage();
    if (!st.keys && !charNowMet(n.id)) return false;   /* 现在档：登场点未达成 */
    return true;
  }
  return visibleNow(n);
}
/* 切换时刻。只重绘、**不重排**（layout）：节点 x/y 跨时刻共享，
   重排会把玩家摆好的位置推走 —— 「该时刻的节点留在同一位置」靠的就是这一点。 */
/* 某时刻回忆发生在哪个地点（数据侧 memories 的 where）；没有就 null。放映卡按它定锚点。 */
function memPlaceOf(t){ const m = (MEMORIES || []).find(x => x.when === t); return m ? m.where : null; }
/* 时刻的显示名：present 档用 config.nowLabel（A-001 = 7月5日），其余用日期场景标题。 */
function timeLabelOf(t){ return t === PRESENT_TIME ? nowLabel() : ((SCENES[t] && SCENES[t].title) || t); }
/* 回忆时刻的叙述文本（「进入新的时间点后，叙事文本应该随着改变」）。
   非 present 档时：
     · 地点节点（该时刻 memories 的 where）→ 那个日期场景的正文 —— 与放映卡同源，
       详情窗简介与「重看叙事」讲的就都是那一天的事；
     · 人物节点（该时刻 memories 的 who）→ 他在这天的回忆脚本（旁白 + 台词合成纯文本）。
   其余情况返回 null = 没有时刻专属叙述，调用方退回静态文本（现在的描述）。 */
function memNarrOf(t, n){
  if (!n || !t || t === PRESENT_TIME) return null;
  const mems = (MEMORIES || []).filter(m => m.when === t);
  if (!mems.length) return null;
  if (mems.some(m => m.where && n.key === containerKey(m.where))){
    const s = SCENES[t] || {};
    return plain(s.content || s.desc || "") || null;
  }
  if (n.kind === "char"){
    const m = mems.find(x => x.who === n.id);
    if (m) return memLinesOf(m).map(l =>
      l.t === "say" ? "——" + ((CHARS[l.who] || {}).name || l.who) + "：" + l.text : l.text
    ).join("\n") || null;
  }
  return null;
}
/* 进入某个回忆时刻 = 打开那天的放映卡（P5：时间节点下画布后，这是读回忆的主入口）。
   锚在该时刻的「地点」节点上方（memories 的 where，一般就是花园）；找不到就不锚定。 */
function openTimeCard(t){
  if (!t || t === PRESENT_TIME || !SCENES[t]) return;
  const ph = memPlaceOf(t);
  showMemoryCard(t, (ph && G.nodes[containerKey(ph)]) || null);
}
/* 真正换档（原子）：改 G.time → 收掉锚在画布上的浮层 → 重绘 → 首次自动开放映卡。
   （切时刻的入口在**档案窗**按时间记录那一列；放映卡每时刻只自动放一遍，见 openTimeCardOnce，
     重放走「档案里点当前档」的手动口。） */
function applyTimeNow(t){
  G.time = t;
  closeBubble(); closeNarr(); closePwPop(); closeDlgWin();  /* 锚在画布上的浮层收掉，别指向已隐藏的节点 */
  if (t !== PRESENT_TIME) spawnMemCast(t);   /* 那天文本里在场的人物跟到画布上（朱穗们）——须赶在 render 前 */
  render();
  /* 进入回忆时刻：镜头聚焦在该时刻的发生地点上（memories 的 where；不在画布就跳过）。
     必须在开放映卡**之前**对焦 —— 卡片按当前视图做「不裁出屏幕」钳制（与 revealScene 同一口径）。 */
  if (t !== PRESENT_TIME){
    const ph = memPlaceOf(t);
    const n = ph ? G.nodes[containerKey(ph)] : null;
    if (n && visibleNode(n)) centerOnNode(n);
  }
  openTimeCardOnce(t);
}
/* 每个时刻的放映卡只**自动**放一遍：看没看过记在该时刻名下（G.cardSeen，进快照存档）。
   之后切档不再重放 —— 想重看点时间轴上当前档的小圆点即可（15-desktop.js 的 endDrag）。 */
function openTimeCardOnce(t){
  if (!t || t === PRESENT_TIME || !SCENES[t]) return;
  if (!G.cardSeen) G.cardSeen = {};
  if (G.cardSeen[t]) return;
  G.cardSeen[t] = true;
  openTimeCard(t);
}
/* 切时刻的过场：**整块世界慢慢淡出 → 换档 → 慢慢淡入**。
   特例：无头验证器里 setTimeout 是空实现（返回 0）→ 同步换档，动画只是装饰（与切案过场同一口径）。 */
const TIME_FADE_MS = 380;   /* 与 03-desktop.css 里 #world 的 transition 时长保持一致 */
let timeFadeTimer = 0;
function swapTime(t){
  const w = (typeof world !== "undefined") ? world : null;
  if (!w || !w.classList){ applyTimeNow(t); return; }
  if (timeFadeTimer){ clearTimeout(timeFadeTimer); timeFadeTimer = 0; }  /* 上一次没落地：新的接管 */
  if (w.style) w.style.opacity = "";                                      /* 清掉可能留下的内联 opacity */
  w.classList.add("time-fade");                                          /* 整块淡出 */
  const tm = setTimeout(() => { timeFadeTimer = 0; applyTimeNow(t); w.classList.remove("time-fade"); }, TIME_FADE_MS);
  if (!tm){ applyTimeNow(t); w.classList.remove("time-fade"); }          /* 无头：同步换档 */
  else timeFadeTimer = tm;
}
function setTime(t){
  if (!G) return false;
  if (t !== PRESENT_TIME && (SCENE_MEMORY || []).indexOf(t) < 0) return false;
  if (((G && G.time) || PRESENT_TIME) === t) return true;   /* 同档：不换、也不淡 */
  swapTime(t);
  return true;
}
function labelOf(kind, id){
  if (isSceneKind(kind)) return SCENES[id] ? SCENES[id].title : null;
  if (kind === "item") return ITEMS[id]  ? ITEMS[id].label  : (id.startsWith("DATA_") ? id.replace(/^DATA_/, "") : null);
  if (kind === "char") return CHARS[id]  ? CHARS[id].name   : null;
  if (kind === "clue") return CLUES[id]  ? CLUES[id].label  : null;
  return null;
}
function findReactable(kind, id){
  if (kind === "item") return ITEMS[id];
  if (kind === "char") return CHARS[id];
  if (kind === "clue") return CLUES[id];
  return null;
}
function kindName(k){ return { item:"物品", char:"角色", clue:"线索", loc:"场景", time:"时间" }[k] || k; }
function nodeByKey(kind, id){ return G.nodes[kind + ":" + id]; }
/* 光照判定（点灯 = 双击执行它的文本命令）：
   lightOn()           → config.lightSources 里任意一盏「环境光源」（台灯）点亮即可
   lightOn("ITEM_x")   → 指定那一盏必须亮着（可传数组：任一即可） */
function lightOn(src){
  const want = (src === undefined || src === true)
    ? LIGHT_SOURCES
    : (Array.isArray(src) ? src : [src]);
  return want.some(id => {
    const n = nodeByKey("item", String(id).replace(/^item:/, ""));
    return !!(n && n.lit);
  });
}
/* 可以被点亮 / 熄灭的物品：数据开关 toggleLight: true，或 config.lightSources 里的环境光源 */
function isToggleLight(id){
  return !!(ITEMS[id] || {}).toggleLight || LIGHT_SOURCES.indexOf(id) >= 0;
}
/* 发光工具：needsLitToUse 的物品（手电筒）必须先点亮，才能当作工具去接触别的节点 */
function toolNeedsLit(n){
  return !!(n && n.kind === "item" && (ITEMS[n.id] || {}).needsLitToUse);
}
/* 工具没点亮时拦下并提示（返回 true = 已拦下）。不进撤销栈、不记「已试过」。 */
function litToolBlocked(tool){
  if (!toolNeedsLit(tool) || tool.lit) return false;
  const why = plain((ITEMS[tool.id] || {}).litFailMessage || "还没有点亮，照不出任何东西。");
  const msg = "「" + plain(tool.label) + "」" + why;
  log(msg, "warn");
  toast("<b>" + esc(tool.label) + "</b><br>" + esc(why), true);
  return true;
}
function edgeBetween(aId, bId, kind){
  return G.edges.some(e => e.kind === kind && ((e.a === aId && e.b === bId) || (e.a === bId && e.b === aId)));
}

/* ============ 日志口径：「结果」，不是「过程」 ============
   日志窗是本案的**案卷**，只记玩家关心的事，不记操作流水。写之前先问一句：
   「这条是玩家读得懂的结果吗，还是我刚替他按了一下按钮？」
   ✅ 记：捕获线索 / 结局 / 案件解锁、组合结果与失败、使用物品的结果、前往、
          一切失败与拦截（缺线索 / 缺工具 / 密码错 / 推演不匹配）、
          开局与换案的一条标记、以及「另有 N 个节点留在画布上」这类**有东西没被收走**的警告。
   ❌ 不记：展开与收起容器、收入与取出（证物袋 / 线索册）、叙事卡与记忆卡放映、
          撤销 / 重置等桌面操作、案件窗离屏、可达性统计、
          **对话台词本身**（人物气泡与 TEC 窗里逐字都在，日志再抄一遍只是流水账；
          但「这一句给出了线索」是结果，照记），以及
          「［消耗 X］［出现 X］［获得 X］」这类附属小行（已经并进上一条结果里）。
   理由：展开容器是全局最高频动作，一次一屏日志会把它冲成流水账；
   而真正要回头查的「我什么时候拿到这条线索」反被埋掉。（2026-10-14 按用户要求收口） */
function log(msg, kind){
  const d = document.createElement("div");
  if (kind) d.className = kind;
  d.innerHTML = msg;
  logBox.appendChild(d);
  logBox.scrollTop = logBox.scrollHeight;
  if (!logWinOpen){ logUnread++; updateLogBadge(); }
}
/* 详情 / 日志窗口可见性（引擎内变量，兼容无头环境） */
let detailWinOpen = false, logWinOpen = false, logUnread = 0;
function setDetailWin(open){
  detailWinOpen = open;
  document.getElementById("detail-win").style.display = open ? "block" : "none";
}
function setLogWin(open){
  logWinOpen = open;
  document.getElementById("log-win").style.display = open ? "block" : "none";
  if (open){ logUnread = 0; updateLogBadge(); }
}
function toggleDetailWin(){ setDetailWin(!detailWinOpen); }
function toggleLogWin(){ setLogWin(!logWinOpen); }
function updateLogBadge(){
  const icon = document.getElementById("log-icon");
  if (!icon) return;
  let b = icon.querySelector(".badge");
  if (logUnread > 0){
    if (!b){ b = document.createElement("span"); b.className = "badge cnt"; icon.appendChild(b); }
    b.textContent = logUnread;
  } else if (b) b.remove();
}
/* 档案角标：新时刻收录（revealScene 建出 time: 节点）时点亮，打开档案窗 / 重置即清。
   与日志计数角标同一族（.badge，桌面图标上的定位见 05-apps.css 的 .desk-icon .badge）。 */
let archiveUnread = false;
function markArchiveNew(){ archiveUnread = true; updateArchiveBadge(); }
function clearArchiveNew(){ archiveUnread = false; updateArchiveBadge(); }
function updateArchiveBadge(){
  const icon = document.getElementById("goto-icon");
  if (!icon) return;
  let b = icon.querySelector(".badge");
  if (archiveUnread){
    if (!b){ b = document.createElement("span"); b.className = "badge new"; icon.appendChild(b); }
    b.textContent = "新";
  } else if (b) b.remove();
}
/* 新时刻收录进档案的统一提示口：toast + 档案图标「新」角标。
   时刻节点的创建口不止一处（展开场景带出 / 摘录点名 / 前往 / 组合与命令产出），
   提示只认「真的新建了 time: 节点」这一件事 —— 挂在 ensureSceneNode（建场景类节点的唯一入口）上。
   restore / 读档直接替换 G.nodes、不走 ensureSceneNode ⇒ 开机 / 续档不会乱响。 */
function announceTimeCollected(){
  toast("新的档案已收录");
  markArchiveNew();
}
let toastTimer = null;
function toast(html, fail){
  toastEl.innerHTML = html;
  toastEl.className = fail ? "fail" : "";
  toastEl.style.display = "block";
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { toastEl.style.display = "none"; }, fail ? 3200 : 6000);
}

/* ============ 反应索引 ============ */
/* 数据语义：目标.presentReactions[工具] / 目标.itemReactions[工具] / 目标.reactions[工具] */
function lookupReaction(ownerKind, ownerId, toolId){
  const owner = findReactable(ownerKind, ownerId);
  if (!owner) return null;
  for (const f of ["presentReactions", "itemReactions", "reactions"]){
    const tbl = owner[f];
    if (tbl && tbl[toolId]) return { field:f, react:tbl[toolId] };
  }
  return null;
}

/* ============ 容器解析：场景 / 会装东西的物品 ============
   场景天生是容器：content 里的 [item] / [char] 是被它收着的对象，[loc] 是通往别处的出口。
   物品也可以是容器 —— 只要它在 ITEMS 里带上 content 字段（书桌、垃圾桶就是这样），
   于是它同样「双击展开、可折叠、内容物摆在四周」，只是画布上仍是物品节点的样子（□ 前缀）。
   下面这套一律按 id 查表（先场景后物品）：节点键用 containerKey(id)，标题用 containerTitle(id)。 */
function containerData(id){ return SCENES[id] || ((ITEMS[id] && ITEMS[id].content) ? ITEMS[id] : null); }
function isContainerId(id){ return !!containerData(id); }
/* 容器节点的 kind：时间节点优先判（它的数据也在 SCENES 表里，不先判就会落回 "loc"） */
function containerKind(id){ return isTimeId(id) ? "time" : (SCENES[id] ? "loc" : "item"); }
function containerKey(id){ return containerKind(id) + ":" + id; }
function containerTitle(id){ const c = containerData(id); return c ? (c.title || c.label || id) : id; }
/* 节点是不是容器：kind 与数据表对得上、且它的数据是容器（带 content）。画布上它是唯一可展开的一类节点。 */
function isContainerNode(n){ return !!n && n.kind === containerKind(n.id) && isContainerId(n.id); }
/* 节点的数据对象（场景 / 物品 / 容器物品 / 角色 / 线索）。取代散落各处的三目链 ——
   旧写法靠「是不是场景」这一个 flag 分流到 SCENES，书桌这类容器物品一改判身份就会查空表。 */
function nodeData(n){
  if (!n) return null;
  if (isSceneKind(n.kind)) return SCENES[n.id];   /* 场景与时间节点同表：SCENES */
  if (n.kind === "item") return ITEMS[n.id];
  if (n.kind === "char") return CHARS[n.id];
  if (n.kind === "clue") return CLUES[n.id];
  return null;
}

/* ============ 场景解析 ============ */
function sceneTags(sid){
  const s = containerData(sid);
  if (!s) return [];
  return parseTags(s.content).filter(t => t.kind !== "loc" && labelOf(t.kind, t.id) &&
    !(t.kind === "char" && t.id === "CHARS_TEC"));
}
function sceneLocs(sid){
  const s = containerData(sid);
  if (!s) return [];
  return parseTags(s.content).filter(t => t.kind === "loc" && SCENES[t.id]).map(t => t.id);
}

/* 场景入/出边统计（用于枢纽标记）。容器物品里的 [loc] 也算一条通路：
   它们自己不是场景、不参与枢纽判定，但它指向的场景照常记一票 —— 否则花园会因为
   书桌改成物品而平白掉一个「枢纽」角标（通路其实还在，只是承载它的节点换了身份）。 */
const inbound = {}, outbound = {};
for (const sid in SCENES){ inbound[sid] = 0; outbound[sid] = 0; }
for (const sid in SCENES) sceneLocs(sid).forEach(t => { outbound[sid]++; inbound[t] = (inbound[t] || 0) + 1; });
for (const iid in ITEMS){
  if (!(ITEMS[iid] && ITEMS[iid].content)) continue;
  sceneLocs(iid).forEach(t => { inbound[t] = (inbound[t] || 0) + 1; });
}
const isHub = sid => (inbound[sid] + outbound[sid]) >= 5;

/* 条件入口统计 */
const condRoutes = {};
for (const iid in ITEMS){
  (function walk(o){
    if (Array.isArray(o)) return o.forEach(walk);
    if (o && typeof o === "object"){
      for (const k in o){
        if (k === "scene" && typeof o[k] === "string" && SCENES[o[k]]) (condRoutes[o[k]] = condRoutes[o[k]] || []).push(iid);
        else walk(o[k]);
      }
    }
  })(ITEMS[iid]);
}
