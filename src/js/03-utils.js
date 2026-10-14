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
function labelOf(kind, id){
  if (kind === "loc")  return SCENES[id] ? SCENES[id].title : null;
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
function kindName(k){ return { item:"物品", char:"角色", clue:"线索", loc:"场景" }[k] || k; }
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
          一切失败与拦截（缺线索 / 缺工具 / 密码错 / 推演不匹配）、人物与 TEC 对白、
          开局与换案的一条标记、以及「另有 N 个节点留在画布上」这类**有东西没被收走**的警告。
   ❌ 不记：展开与收起容器、收入与取出（证物袋 / 线索册）、叙事卡与记忆卡放映、
          自动布局 / 撤销 / 重置等桌面操作、案件窗离屏、可达性统计，以及
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
    if (!b){ b = document.createElement("span"); b.className = "badge cond"; icon.appendChild(b); }
    b.textContent = logUnread;
  } else if (b) b.remove();
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
function containerKind(id){ return SCENES[id] ? "loc" : "item"; }
function containerKey(id){ return containerKind(id) + ":" + id; }
function containerTitle(id){ const c = containerData(id); return c ? (c.title || c.label || id) : id; }
/* 节点是不是容器：kind 与数据表对得上、且它的数据是容器（带 content）。画布上它是唯一可展开的一类节点。 */
function isContainerNode(n){ return !!n && n.kind === containerKind(n.id) && isContainerId(n.id); }
/* 节点的数据对象（场景 / 物品 / 容器物品 / 角色 / 线索）。取代散落各处的三目链 ——
   旧写法靠「是不是场景」这一个 flag 分流到 SCENES，书桌这类容器物品一改判身份就会查空表。 */
function nodeData(n){
  if (!n) return null;
  if (n.kind === "loc")  return SCENES[n.id];
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
