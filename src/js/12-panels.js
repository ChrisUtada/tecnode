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
  Object.keys(G.nodes).forEach(k => { if (k.startsWith("loc:")) known.add(k.slice(4)); });
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
  const isNew = !nodeByKey("loc", sid);
  if (isNew) pushHistory();
  const sn = ensureNode("loc", sid, { label: SCENES[sid].title });
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
    st.textContent = (G.explored.has(sid) ? "已展开" : "未展开") + " · " + (nodeByKey("loc", sid) ? "在画布" : "未在画布");
    d.appendChild(label); d.appendChild(st);
    d.addEventListener("click", () => { gotoScene(sid); closeGotoWin(); });
    body.appendChild(d);
  });
}

/* ============ CLUE LEDGER // 线索册：收纳盒 ============
   线索捕获后先落在画布上，要做的是「把它拖进线索册」（拖到窗口里或左侧图标上）——收进来即离开画布。
   册子里只有已收纳的线索：一条一行，感官直接标在行尾，整表按五感顺序自动排序（同感自然相邻），
   不再分组、不再标归位状态，也不给未捕获 / 未收纳的线索留位——册子就是盒子，装什么显示什么。
   点一行 = 取回画布（回到线索册图标旁并选中，详情窗顺势展开全文）。 */
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
function ledgerTake(key){
  const n = G.nodes[key];
  if (!n || n.storedIn !== "LEDGER") return false;
  /* 案件窗关着时不能取：取出是放回画布的操作，不能对看不见的画布施展 */
  if (!requireCase()) return false;
  pushHistory();
  n.stored = false; n.storedIn = null; n.hidden = false; markFresh(n);
  /* 取回到线索册图标附近的画布位置（屏幕坐标换算成世界坐标） */
  const icon = document.getElementById("clue-icon");
  if (icon){
    const r = icon.getBoundingClientRect();
    const wpt = toWorld(r.left + r.width / 2, r.top - 40);
    n.x = wpt.x; n.y = wpt.y;
  }
  layout(); render(); refreshClueWin();
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
    d.addEventListener("click", () => takeFromLedger(n.key));
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

/* ============ ROSTER // 人物：已结识角色的索引 ============
   已结识 = 画布上有节点 ∪ 文本里点过名 ∪ 在已展开的场景里说过话；TEC 有自己的助手窗，不列进名册。
   点一行 = 把人叫到画面中央、选中，并接着说下一句（没有节点就补一个）。 */
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
function metChars(){
  const ids = new Set();
  Object.keys(G.nodes).forEach(k => { if (k.indexOf("char:") === 0) ids.add(k.slice(5)); });
  G.seenTexts.forEach(txt => parseTags(txt).forEach(t => { if (t.kind === "char" && CHARS[t.id]) ids.add(t.id); }));
  G.explored.forEach(sid => Object.keys(CHARS).forEach(id => {
    if ((CHARS[id].sceneTalks || {})[sid]) ids.add(id);
  }));
  return Object.keys(CHARS).filter(id => id !== "CHARS_TEC" && ids.has(id));
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
    const ch = CHARS[id] || {};
    const pr = charProgress(id);
    const d = document.createElement("div");
    d.className = "goto-item" + ((pr.total && pr.prog >= pr.total) ? " done" : "");
    const box = document.createElement("span"); box.className = "nm";
    const lb = document.createElement("span"); lb.className = "lb"; lb.textContent = ch.name || id;
    box.appendChild(lb);
    const ds = document.createElement("span"); ds.className = "ds"; ds.textContent = ch.desc || "";
    box.appendChild(ds);
    const st = document.createElement("span"); st.className = "st";
    st.textContent = pr.total ? (pr.prog ? "对话 " + pr.prog + "/" + pr.total : "未交谈") : "无对话文本";
    d.appendChild(box); d.appendChild(st);
    d.addEventListener("click", () => gotoChar(id));
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
