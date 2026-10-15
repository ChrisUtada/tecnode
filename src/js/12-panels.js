/* ============ 选中聚焦（dim 非邻居） ============ */
function applyFocus(){
  const on = tgFocus.checked && sel && G.nodes[sel];
  const keep = {};
  if (on){
    keep[sel] = 1;
    G.edges.forEach(e => {
      if (e.a === sel) keep[e.b] = 1;
      if (e.b === sel) keep[e.a] = 1;
    });
  }
  G._dimKeys = [];
  Object.values(G.nodes).forEach(n => {
    if (!n.el) return;
    const dim = on && !keep[n.key];
    n.el.classList.toggle("dim", dim);
    if (dim) G._dimKeys.push(n.key);
  });
  paintEdges();
}
function clearSelection(){
  sel = null;
  nodeLayer.querySelectorAll(".node.sel").forEach(e => e.classList.remove("sel"));
  document.querySelectorAll(".desk-icon.sel").forEach(x => x.classList.remove("sel"));
  detailPlaceholder();
  setDetailWin(false);
  applyFocus();
}

/* ============ GOTO // 前往：听说过的场景索引 ============ */
/* seenTexts 不进 snapshot：已经"听说过"的知识不随撤销丢失 */
function noteSeen(text){
  if (!text) return;
  G.seenTexts.push(String(text));
  if (G.seenTexts.length > 200) G.seenTexts.shift();
}
function heardScenes(){
  const known = new Set(G.explored);
  Object.keys(G.nodes).forEach(k => {
    const m = /^(?:loc|time):(.+)$/.exec(k);   /* 时间节点也是「听说的场景」，一并进档案 */
    if (m) known.add(m[1]);
  });
  G.explored.forEach(sid => sceneLocs(sid).forEach(t => known.add(t)));
  G.seenTexts.forEach(txt => {
    parseTags(txt).forEach(t => { if (t.kind === "loc" && SCENES[t.id]) known.add(t.id); });
    for (const id in SCENES){
      const t = SCENES[id].title;
      if (t && t.length >= 2 && txt.indexOf(t) >= 0) known.add(id);
    }
  });
  return [...known].filter(id => SCENES[id]);
}
function gotoScene(sid){
  if (!SCENES[sid]) return;                 /* 档案里只有场景；容器物品（书桌 / 垃圾桶）不在此列 */
  const isNew = !nodeByKey(containerKind(sid), sid);
  if (isNew) pushHistory();
  const sn = ensureSceneNode(sid, { label: SCENES[sid].title });
  if (isNew){ markFresh(sn); layout(); }
  render();
  const r = stage.getBoundingClientRect();
  view.x = r.width / 2 - (sn.x + 76) * view.k;
  view.y = r.height / 2 - (sn.y + 27) * view.k;
  applyView();
  selectNode(sn.key);
  log("前往「" + esc(SCENES[sid].title || sid) + "」", "act");
}
let gotoWinEl = null;
function closeGotoWin(){ if (gotoWinEl){ gotoWinEl.remove(); gotoWinEl = null; } }
function toggleGotoWin(){
  if (gotoWinEl){ closeGotoWin(); return; }
  const w = makeWindow("ARCHIVE // 档案", closeGotoWin);
  w.el.classList.add("goto-win");
  desktopEl.appendChild(w.el);
  makeFloatDraggable(w.el, false);
  gotoWinEl = w.el;
  refreshGotoWin();
}
function refreshGotoWin(){
  if (!gotoWinEl) return;
  const body = gotoWinEl.querySelector(".syswin-body");
  if (!body) return;
  body.innerHTML = "";
  const list = heardScenes();
  if (!list.length){
    const d = document.createElement("div");
    d.className = "bag-empty";
    d.textContent = "（还没有听说任何场景）";
    body.appendChild(d);
    return;
  }
  list.forEach(sid => {
    const d = document.createElement("div");
    d.className = "goto-item";
    const label = document.createElement("span"); label.textContent = SCENES[sid].title || sid;
    const st = document.createElement("span"); st.className = "st";
    st.textContent = (G.explored.has(sid) ? "已探索" : "未探索") + " · " + (nodeByKey(containerKind(sid), sid) ? "在画布" : "未在画布");
    d.appendChild(label); d.appendChild(st);
    d.addEventListener("click", () => { gotoScene(sid); closeGotoWin(); });
    body.appendChild(d);
  });
}

/* ============ CLUE LEDGER // 线索册：收纳盒 ============
   线索捕获后先落在画布上，要做的是「把它拖进线索册」（拖到窗口里或左侧图标上）——收进来即离开画布。
   册子里只有已收纳的线索：一条一行，感官直接标在行尾，整表按五感顺序自动排序（同感自然相邻），
   不再分组、不再标归位状态，也不给未捕获 / 未收纳的线索留位——册子就是盒子，装什么显示什么。
   点一行 = 取回画布（回到线索册图标旁并选中，详情窗顺势展开全文）；
   按住一行拖走 = 三个落点（2026-10-16 补齐）：另一个收纳窗（证物袋）/ 推演桌布（或推演器图标）/ 画布。
   拖到画布松手 = 取回，**就落在松手那一点**（跟手，与推演桌布拖出同一口径）；
   前两者不必先点回画布再拖一遍。 */
let clueWinEl = null;
function closeClueWin(){ if (clueWinEl){ clueWinEl.remove(); clueWinEl = null; } }
function toggleClueWin(){
  if (clueWinEl){ closeClueWin(); return; }
  const w = makeWindow("CLUE LEDGER // 线索册", closeClueWin);
  w.el.classList.add("clue-win");
  desktopEl.appendChild(w.el);
  makeFloatDraggable(w.el, false);
  clueWinEl = w.el;
  refreshClueWin();
}
/* 册中条目（与证物袋共用 stored 机制：收纳 = 离开画布，只留一条清单记录） */
function ledgerItems(){
  return Object.values(G.nodes).filter(n => n.stored && n.storedIn === "LEDGER");
}
function ledgerStore(key){
  const n = G.nodes[key];
  if (!n || n.stored) return false;
  if (n.kind !== "clue"){ toast("只有线索能收进线索册", true); return false; }
  pushHistory();
  n.stored = true; n.storedIn = "LEDGER"; n.pinned = false;
  recomputeHidden(); layout(); render(); refreshClueWin();
  return true;
}
function ledgerTake(key, cx, cy){
  const n = G.nodes[key];
  if (!n || n.storedIn !== "LEDGER") return false;
  /* 案件窗关着时不能取：取出是放回画布的操作，不能对看不见的画布施展 */
  if (!requireCase()) return false;
  pushHistory();
  n.stored = false; n.storedIn = null; n.hidden = false; markFresh(n);
  /* 带落点 = 从册里**拖出来**：落在松手那一点（与 bagTake / boardTake 同一口径 ——
     先换算成世界坐标、**再**减去半张卡；这条路上不跑 layout()，跟手落下的位置不该被弹簧推走）。
     不带落点 = 单击一行：仍旧放回线索册图标旁边的画布位置，并重整一次版（旧口径）。 */
  const dropped = (cx != null && cy != null);
  if (dropped){
    const wpt = toWorld(cx, cy);
    n.x = wpt.x - (NODE_W[n.kind] || 130) / 2; n.y = wpt.y - (NODE_H[n.kind] || 46) / 2;
  } else {
    const icon = document.getElementById("clue-icon");
    if (icon){
      const r = icon.getBoundingClientRect();
      const wpt = toWorld(r.left + r.width / 2, r.top - 40);
      n.x = wpt.x; n.y = wpt.y;
    }
    layout();
  }
  render(); refreshClueWin();
  return true;
}
/* 排序键 = 五感顺序（SENSES 的键序）* 1000 + 线索在数据里的书写顺序，等价于「先按感官、再按原序」 */
function ledgerRank(id){
  const order = Object.keys(SENSES), ti = order.indexOf((CLUES[id] || {}).type);
  return (ti < 0 ? order.length : ti) * 1000 + Object.keys(CLUES).indexOf(id);
}
function ledgerList(){
  return ledgerItems().sort((a, b) => ledgerRank(a.id) - ledgerRank(b.id));
}
/* 把镜头拉到某个节点上（档案的 gotoScene 同款算法，按节点宽度取心） */
function centerOnNode(n){
  const r = stage.getBoundingClientRect();
  view.x = r.width / 2 - (n.x + (NODE_W[n.kind] || 152) / 2) * view.k;
  view.y = r.height / 2 - (n.y + 27) * view.k;
  applyView();
}
function refreshClueWin(){
  if (!clueWinEl) return;
  const body = clueWinEl.querySelector(".syswin-body");
  if (!body) return;
  body.innerHTML = "";
  const items = ledgerList();
  if (!items.length){
    const d = document.createElement("div");
    d.className = "bag-empty";
    d.textContent = "（空）把画布上的线索拖到这里收纳";
    body.appendChild(d);
    return;
  }
  items.forEach(n => {
    const c = CLUES[n.id] || {};
    const d = document.createElement("div");
    d.className = "goto-item";
    const box = document.createElement("span"); box.className = "nm";
    const lb = document.createElement("span"); lb.className = "lb"; lb.textContent = c.label || n.label;
    box.appendChild(lb);
    if (c.desc){
      const ds = document.createElement("span"); ds.className = "ds"; ds.textContent = c.desc;
      box.appendChild(ds);
    }
    const st = document.createElement("span"); st.className = "st sense";
    st.textContent = SENSES[c.type] || "";
    d.appendChild(box); d.appendChild(st);
    makeLedgerRowDraggable(d, n.key);
    body.appendChild(d);
  });
}
/* 点一行 = 取回画布：放回图标旁、镜头拉到它身上并选中 */
function takeFromLedger(key){
  if (!requireCase()) return false;
  const n = G.nodes[key];
  if (!n || !ledgerTake(key)) return false;
  centerOnNode(n); selectNode(n.key);
  return true;
}

/* ---- 册中一行直拖推演器：按住行拖到桌布（或推演器图标）上松手 = 归位 ----
   落点判定与画布拖拽同源（桌布 + infer-icon）；拖动中给落点打 over 高亮。
   纯点击仍是取回画布 —— 拖过的那一下吞掉紧跟的 click，两个动作不连发。 */
function overMatrixDrop(cx, cy){
  const bd = inferWinEl ? inferWinEl.querySelector(".mx-board") : null;
  if (bd){
    const r = bd.getBoundingClientRect();
    if (cx >= r.left && cx <= r.right && cy >= r.top && cy <= r.bottom) return true;
  }
  const ic = document.getElementById("infer-icon");
  if (ic){
    const r = ic.getBoundingClientRect();
    if (cx >= r.left && cx <= r.right && cy >= r.top && cy <= r.bottom) return true;
  }
  return false;
}
/* ---- 反向：桌布上的 chip 拖回线索册（与「册 → 桌布」对称的那一半）----
   落点 = 线索册窗（开着时）或线索册图标；两个都没命中才退回「拖出桌布 = 取回画布」。 */
function overLedgerDrop(cx, cy){
  if (clueWinEl && clueWinEl.style.display !== "none"){
    const r = clueWinEl.getBoundingClientRect();
    if (cx >= r.left && cx <= r.right && cy >= r.top && cy <= r.bottom) return true;
  }
  const ic = document.getElementById("clue-icon");
  if (ic){
    const r = ic.getBoundingClientRect();
    if (cx >= r.left && cx <= r.right && cy >= r.top && cy <= r.bottom) return true;
  }
  return false;
}
/* 桌布 → 册：把归位的线索**改写收纳位置**（storedIn MATRIX → LEDGER），并从阵列里摘掉。
   不能复用 ledgerStore —— 它对 `n.stored` 的节点直接 return false，而归位的线索正是 stored 状态。
   与 assignClue / boardTake 同款：只重画、**不跑 layout()**（归位一个线索不该顺手重排玩家的摆位）。 */
function boardToLedger(cid, sense){
  const n = nodeByKey("clue", cid);
  if (!n) return false;
  if (!requireCase()){ refreshInferWin(); return false; }
  pushHistory();
  G.matrix[sense] = (G.matrix[sense] || []).filter(x => x !== cid);
  n.stored = true; n.storedIn = "LEDGER"; n.pinned = false;
  render(); refreshInferWin(); refreshClueWin();
  return true;
}
/* 归位 = 直接从册子搬上桌布（复用 assignClue：它认 G.nodes 里任何线索，不管现在收在哪儿；
   storedIn 从 LEDGER 改写成 MATRIX，撤销栈照记，render() 顺手把册窗清单刷成少一行）。 */
function ledgerToMatrix(key){
  const n = G.nodes[key];
  if (!n || n.storedIn !== "LEDGER") return false;
  const sense = (CLUES[n.id] || {}).type;
  if (!sense){ toast("这条线索没有感官类型，上不了桌布", true); return false; }
  if (!requireCase()) return false;
  return assignClue(key, sense);
}
/* 册 → 袋：跨窗搬运（与 bagToLedger 对称的那一半）。袋什么都收，所以不设种类门；
   内核走 restash（只改 storedIn、重画两个清单、不跑 layout()），与 boardToLedger 同款。 */
function ledgerToBag(key){
  return restash(key, "LEDGER", "BAG");
}
/* 行上的指针拖拽：镜像**不克隆行** —— 一旦拖离册子就以「节点块」现身
   （mx-chip.node，与桌布上的归位 chip 同款观感），居中跟手（#drag-layer）；
   松手落在三个落点之外 = 取回画布（跟手），不弹回册中。 */
function makeLedgerRowDraggable(row, key){
  let dragging = false, moved = false, wasMoved = false, sx = 0, sy = 0,
      mirror = null, mw = 0, mh = 0, sr = null;
  /* 三个落点的高亮都要能撤（袋窗 / 袋图标 / 桌布 / 推演器图标） */
  const clearOver = () => {
    const bd = inferWinEl ? inferWinEl.querySelector(".mx-board") : null;
    if (bd) bd.classList.remove("over");
    const ic = document.getElementById("infer-icon");
    if (ic && ic.classList) ic.classList.remove("over");
    if (bagWinEl && bagWinEl.classList) bagWinEl.classList.remove("over");
    const bi = document.getElementById("bag-dock");
    if (bi && bi.classList) bi.classList.remove("over");
  };
  /* 被 render() 打断时的收尾（见 07-render.js 的登记表）：摘镜像、把行放回来 */
  const abortRowDrag = () => {
    if (!dragging) return;
    dragging = false;
    if (mirror){ mirror.remove(); mirror = null; }
    row.style.visibility = "";
    clearOver();
  };
  row.addEventListener("pointerdown", e => {
    if (e.button !== 0) return;
    dragging = true; moved = false; wasMoved = false; sx = e.clientX; sy = e.clientY;
    sr = desktopEl.getBoundingClientRect();
    registerDrag(abortRowDrag);
    try { row.setPointerCapture(e.pointerId); } catch(_){}
  });
  row.addEventListener("pointermove", e => {
    if (!dragging) return;
    const dx = e.clientX - sx, dy = e.clientY - sy;
    if (!moved && Math.abs(dx) + Math.abs(dy) < 5) return;
    moved = true;
    if (!mirror){
      const layer = document.getElementById("drag-layer");
      const n = G.nodes[key], c = CLUES[n.id] || {};
      mirror = document.createElement("div");
      mirror.className = "mx-chip node ent-node ent-clue drag-mirror";
      mirror.innerHTML = "<div class='n-title'>" + esc(c.label || n.label) + "</div><div class='n-sub'>线索</div>";
      mirror.style.position = "absolute";
      mirror.style.width = "140px";
      layer.appendChild(mirror);
      mw = mirror.offsetWidth || 140; mh = mirror.offsetHeight || 40;
      row.style.visibility = "hidden";
    }
    mirror.style.left = (e.clientX - sr.left - mw / 2) + "px";
    mirror.style.top  = (e.clientY - sr.top  - mh / 2) + "px";
    /* 落点高亮：袋窗 / 袋图标（跨窗搬运）、桌布（归位）。桌布只在推演窗开着时存在。 */
    if (bagWinEl && bagWinEl.classList){
      const r = bagWinEl.getBoundingClientRect();
      bagWinEl.classList.toggle("over", e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom);
    }
    const bi = document.getElementById("bag-dock");
    if (bi && bi.classList){
      const r = bi.getBoundingClientRect();
      bi.classList.toggle("over", e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom);
    }
    const bd = inferWinEl ? inferWinEl.querySelector(".mx-board") : null;
    if (bd){
      const r = bd.getBoundingClientRect();
      bd.classList.toggle("over", e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom);
    }
  });
  const finish = e => {
    if (!dragging) return;
    dragging = false;
    unregisterDrag(abortRowDrag);
    if (mirror){ mirror.remove(); mirror = null; }
    row.style.visibility = "";
    clearOver();
    if (moved) wasMoved = true;
    if (!moved || !e) return;
    /* 落点判定顺序即优先级：先判「另一个收纳窗」，再判桌布，其余一律算画布。 */
    if (overBagDrop(e.clientX, e.clientY)){ ledgerToBag(key); return; }
    if (overMatrixDrop(e.clientX, e.clientY)){ ledgerToMatrix(key); return; }
    ledgerTake(key, e.clientX, e.clientY);   /* 落在画布上：取回，就落在松手那一点 */
  };
  row.addEventListener("pointerup", finish);
  row.addEventListener("pointercancel", () => { unregisterDrag(abortRowDrag); abortRowDrag(); });
  /* 点击 = 取回画布；刚拖完的那一下（wasMoved）不算点击 */
  row.addEventListener("click", () => {
    if (wasMoved){ wasMoved = false; return; }
    takeFromLedger(key);
  });
}

/* ============ ROSTER // 人物：名册 ============
   两部分：
   · **常驻成员**（TEC / 执行者）—— 一进游戏就在册，不靠「已结识」判定。他们不是「遇到的人」，
     而是随时可用的两个角色；也没有画布节点，所以点一行 = **打开各自的窗**（助手窗 / 逻辑阵列）。
   · **遇到的人** —— 已结识 = 画布上有节点 ∪ 文本里点过名 ∪ 在已探索的场景里说过话；
     点一行 = 把人叫到画面中央、选中，并接着说下一句（没有节点就补一个）。
   每行左侧一个小头像：有美术稿用像素图，没有的用「首字方块」占位（2026-10-14 用户决定）。 */
let peopleWinEl = null;
function closePeopleWin(){ if (peopleWinEl){ peopleWinEl.remove(); peopleWinEl = null; } }
function togglePeopleWin(){
  if (peopleWinEl){ closePeopleWin(); return; }
  const w = makeWindow("ROSTER // 人物", closePeopleWin);
  w.el.classList.add("people-win");
  desktopEl.appendChild(w.el);
  makeFloatDraggable(w.el, false);
  peopleWinEl = w.el;
  refreshPeopleWin();
}
/* 常驻成员：一进游戏就在名册里。id 就是名册里的键 —— 执行者没有 CHARS 条目也没关系，
   name / desc 就地写死；TEC 则从数据里取（保持可编辑）。
   open = 点这一行做什么（两者都没有画布节点，所以是「开窗」而不是「叫到画布上」）。
   toggleTecWin / toggleInferWin 都是函数声明，同处一个 <script>，提升后可直接引用。 */
const ROSTER_PINNED = [
  { id: "CHARS_TEC",  tag: "助手窗",   open: toggleTecWin },
  { id: "CHARS_EXEC", tag: "逻辑阵列", open: toggleInferWin,
    name: "执行者", desc: "逻辑阵列中央的执行者，长按 2.5 秒激活归因。" }
];
/* 小头像：TEC / 执行者复用各自窗里的那一张（同一份素材）。rosterAvatar 返回的是
   「完整可用的 src」（构建时由素材占位符换成 assets/ 外链或 data: 内联）。
   剧情角色暂无美术稿 ⇒ 返回 null，名册改用「首字方块」占位。
   拿到图后：把图放进 src/assets/，在下面按 id 补一行素材占位符（写法与 11-dialog.js 里
   `TEC_AVATAR` 那行完全一样）即可。
   ⚠ 两条坑：① 本函数必须**惰性读取**常量 —— 所有切片拼进同一个 <script>，而
   `EXECUTOR_AVATAR` 定义在 13-matrix.js（本文件之后），顶层直接引用会踩 TDZ。
   ② 任何**注释里也不要写素材占位符的字面量**：build.js 是对整段源码做替换的，
   注释同样会被扫到，守卫会以「素材名不合法」直接中止构建。 */
function rosterAvatar(id){
  if (id === "CHARS_TEC")  return TEC_AVATAR;
  if (id === "CHARS_EXEC") return EXECUTOR_AVATAR;
  return null;
}
/* 常驻在前、遇到的在后；CHARS_TEC 已在常驻里，从「遇到的人」里排除，免得排两遍 */
function metChars(){
  const ids = new Set();
  Object.keys(G.nodes).forEach(k => { if (k.indexOf("char:") === 0) ids.add(k.slice(5)); });
  G.seenTexts.forEach(txt => parseTags(txt).forEach(t => { if (t.kind === "char" && CHARS[t.id]) ids.add(t.id); }));
  G.explored.forEach(sid => Object.keys(CHARS).forEach(id => {
    if ((CHARS[id].sceneTalks || {})[sid]) ids.add(id);
  }));
  return ROSTER_PINNED.map(p => p.id)
    .concat(Object.keys(CHARS).filter(id => id !== "CHARS_TEC" && ids.has(id)));
}
/* 对话进度：有节点就按真实队列算（含场景对白），没节点时退回基础队列 */
function charProgress(id){
  const n = nodeByKey("char", id);
  if (n) return { prog: G.talkProg[n.key] || 0, total: charTalkQueue(n).length };
  const base = ((CHARS[id] || {}).talkQueue) || [];
  return { prog: 0, total: base.filter(Boolean).length };
}
function refreshPeopleWin(){
  if (!peopleWinEl) return;
  const body = peopleWinEl.querySelector(".syswin-body");
  if (!body) return;
  body.innerHTML = "";
  const list = metChars();
  if (!list.length){
    const d = document.createElement("div");
    d.className = "bag-empty";
    d.textContent = "（还没有结识任何人）展开场景、读一读文本，就会记下遇到的人";
    body.appendChild(d);
    return;
  }
  list.forEach(id => {
    const pin = ROSTER_PINNED.find(p => p.id === id);
    const ch = CHARS[id] || {};
    const name = (pin && pin.name) || ch.name || id;
    const pr = pin ? null : charProgress(id);   /* 常驻成员不走对话进度（他们的词在各自的窗里） */
    const d = document.createElement("div");
    d.className = "goto-item" + ((pr && pr.total && pr.prog >= pr.total) ? " done" : "");
    /* 小头像：有美术稿用像素图，没有的用「首字方块」占位 */
    const av = document.createElement("span"); av.className = "av";
    const art = rosterAvatar(id);
    if (art){
      const im = document.createElement("img");
      im.src = art;
      im.alt = ""; im.draggable = false;
      av.appendChild(im);
    } else {
      const ini = document.createElement("span");
      ini.className = "ini"; ini.textContent = name.slice(0, 1);
      av.appendChild(ini);
    }
    const box = document.createElement("span"); box.className = "nm";
    const lb = document.createElement("span"); lb.className = "lb"; lb.textContent = name;
    box.appendChild(lb);
    const ds = document.createElement("span"); ds.className = "ds"; ds.textContent = (pin && pin.desc) || ch.desc || "";
    box.appendChild(ds);
    const st = document.createElement("span"); st.className = "st";
    /* 对话状态只给状态词不给条数（用户要求 UI 上不出现 x/y 计数） */
    st.textContent = pin ? pin.tag
      : (pr.total ? (pr.prog >= pr.total ? "已聊完" : (pr.prog ? "可继续" : "未交谈")) : "无对话文本");
    d.appendChild(av); d.appendChild(box); d.appendChild(st);
    d.addEventListener("click", () => { if (pin) pin.open(); else gotoChar(id); });
    body.appendChild(d);
  });
}
/* 点一行 = 把角色叫到画面中央、选中，然后接着说下一句 */
function gotoChar(id){
  if (!requireCase()) return;
  const ch = CHARS[id] || {};
  let n = nodeByKey("char", id);
  if (!n){
    pushHistory();
    n = ensureNode("char", id, { label: ch.name || id });
    if (!n.homeScene) n.homeScene = G.lastScene || null;
    layout(); render();
  }
  if (n.stored) bagTake(n.key);
  centerOnNode(n); selectNode(n.key);
  if (!charTalkQueue(n).length){ toast("<b>" + esc(ch.name || id) + "</b><br>（暂无对话文本）"); return; }
  showCharLine(n);
}
