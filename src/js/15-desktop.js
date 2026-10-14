/* ============ 画布平移 / 缩放 ============ */
(function(){
  let panning = false, sx = 0, sy = 0, ox = 0, oy = 0;
  stage.addEventListener("pointerdown", e => {
    /* 窗口/浮层/图标上不触发平移与清除选中（操作不穿透） */
    if (e.target.closest(".node") || e.target.closest(".syswin, #toast, #verdict, .desk-icon")) return;
    cancelViewAnim();   /* 玩家开始平移 → 接管镜头，打断自动居中 */
    /* 点空白不再收浮窗（文本框用 × 关闭），只清除选中/聚焦 */
    clearSelection();
    panning = true; sx = e.clientX; sy = e.clientY; ox = view.x; oy = view.y;
    stage.classList.add("grabbing");
  });
  stage.addEventListener("pointermove", e => {
    if (!panning) return;
    view.x = ox + (e.clientX - sx); view.y = oy + (e.clientY - sy); applyView();
  });
  window.addEventListener("pointerup", () => { panning = false; stage.classList.remove("grabbing"); });
  stage.addEventListener("wheel", e => {
    /* 光标在窗口/浮层上时滚轮交给窗口自己的滚动条，不触发画布缩放 */
    const t = e.target;
    if (t && t.closest && t.closest(".syswin, #toast, #verdict")) return;
    cancelViewAnim();   /* 玩家缩放 → 接管镜头 */
    e.preventDefault();
    const r = stage.getBoundingClientRect();
    const mx = e.clientX - r.left, my = e.clientY - r.top;
    const k2 = Math.max(.35, Math.min(1.8, view.k * (e.deltaY < 0 ? 1.12 : 1 / 1.12)));
    view.x = mx - (mx - view.x) * (k2 / view.k);
    view.y = my - (my - view.y) * (k2 / view.k);
    view.k = k2; applyView();
  }, { passive: false });
})();

function fit(){
  const keys = Object.keys(G.nodes).filter(k => !G.nodes[k].hidden && !G.nodes[k].stored);
  if (!keys.length) return;
  let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
  keys.forEach(k => {
    const n = G.nodes[k];
    x0 = Math.min(x0, n.x); y0 = Math.min(y0, n.y);
    x1 = Math.max(x1, n.x + NODE_W[n.kind]); y1 = Math.max(y1, n.y + NODE_H[n.kind]);
  });
  const r = stage.getBoundingClientRect();
  const pad = 60;
  const k = Math.max(.35, Math.min(1.3, Math.min((r.width - pad * 2) / (x1 - x0), (r.height - pad * 2) / (y1 - y0))));
  view.k = k;
  view.x = (r.width - (x1 - x0) * k) / 2 - x0 * k;
  view.y = (r.height - (y1 - y0) * k) / 2 - y0 * k;
  applyView();
  /* 「适应窗口」也是自动动镜头（开场只有一个场景节点时的展开就走这条路），一并记账 */
  lastFocus = { on:true, why:"fit", keys:keys.slice() };
}

/* ============ 桌面图标：单击选中 / 拖动移动 / 双击打开 / 拖节点直达功能 ============ */
function openApp(app){
  if (app === "infer") toggleInferWin();
  else if (app === "goto") toggleGotoWin();
  else if (app === "clues") toggleClueWin();
  else if (app === "people") togglePeopleWin();
  else if (app === "bag") toggleBagWin();
  else if (app === "tec") toggleTecWin();
  else if (app === "log") toggleLogWin();
  else if (app === "map") toggleMapWin();
  else if (app === "music") toggleMusicWin();
}
function selectIcon(el){
  document.querySelectorAll(".desk-icon.sel").forEach(x => x.classList.remove("sel"));
  el.classList.add("sel");
}
/* attachIcon(el, app, onQuick)：onQuick 提供时「单击 = 选中并直接打开」
   （播放器图标用，用户要求单击即开）；不提供时保持全桌一致的双击打开。 */
function attachIcon(el, app, onQuick){
  app = app || el.dataset.app;
  let dragging = false, moved = false, sx = 0, sy = 0, ox = 0, oy = 0;
  el.addEventListener("pointerdown", e => {
    if (e.button !== 0) return;
    dragging = true; moved = false;
    sx = e.clientX; sy = e.clientY;
    ox = parseFloat(el.style.left) || 0; oy = parseFloat(el.style.top) || 0;
    try { el.setPointerCapture(e.pointerId); } catch(_){}
    e.stopPropagation();
  });
  el.addEventListener("pointermove", e => {
    if (!dragging) return;
    if (!moved && Math.abs(e.clientX - sx) + Math.abs(e.clientY - sy) < 5) return;
    moved = true;
    const r = desktopEl.getBoundingClientRect();
    el.style.left = Math.max(0, Math.min((r.width || 1200) - 64, ox + e.clientX - sx)) + "px";
    el.style.top  = Math.max(0, Math.min((r.height || 800) - 64, oy + e.clientY - sy)) + "px";
  });
  el.addEventListener("pointerup", e => {
    if (!dragging) return;
    dragging = false;
    if (!moved){
      selectIcon(el);
      if (onQuick) onQuick();
    }
  });
  if (!onQuick) el.addEventListener("dblclick", () => openApp(app));
}
/* 默认站位：桌面层左侧竖排。
   图标现在在案件窗之外的独立栏里，不用再避开画布左上角的 hint，所以从桌面顶部开始排；
   桌面高度不够时压缩间距，避免最后一个图标被 #desktop{overflow:hidden} 裁掉。
   位置不进撤销栈、重置不回位。 */
const ICON_LAYOUT = [["infer-icon","infer"],["goto-icon","goto"],["clue-icon","clues"],["people-icon","people"],["bag-dock","bag"],["tec-dock","tec"],["log-icon","log"],["map-icon","map"]];
const ICON_LEFT = 18, ICON_TOP = 16, ICON_PITCH = 85, ICON_H = 64;
function resetIconPositions(){
  const n = ICON_LAYOUT.length;
  const H = (desktopEl.getBoundingClientRect().height) || 600;
  const pitch = Math.max(ICON_H + 6, Math.min(ICON_PITCH, Math.floor((H - ICON_TOP - 12) / n)));
  ICON_LAYOUT.forEach(([id], i) => {
    const el = document.getElementById(id);
    if (el && el.style){ el.style.left = ICON_LEFT + "px"; el.style.top = (ICON_TOP + i * pitch) + "px"; }
  });
}
ICON_LAYOUT.forEach(([id, app]) => attachIcon(document.getElementById(id), app));
resetIconPositions();
/* 详情 / 日志静态窗口：× 与拖动 */
document.getElementById("detail-x").addEventListener("click", () => clearSelection());
document.getElementById("log-x").addEventListener("click", () => setLogWin(false));
/* × 关闭 = 把案件放进桌面左侧的「案件地图」图标（进度存进本案的档，进案件地图即可再展开） */
document.getElementById("case-x").addEventListener("click", e => {
  if (e && e.stopPropagation) e.stopPropagation();
  closeCase();
});
/* – 收起 = 把案件缩成桌面右下角的案件卡片（可拖动，点卡片展开） */
document.getElementById("case-min").addEventListener("click", e => {
  if (e && e.stopPropagation) e.stopPropagation();
  stowCase();
});
attachDock(document.getElementById("case-dock"));
attachDock(document.getElementById("music-dock"), restoreMusicWin);   /* 播放器最小化卡片：单击唤回 */
initMusicDock();        /* 卡片上的播放/暂停、停止控制键（renderMusicDock 负责换键面） */
initTecChip();          /* 右下角的 TEC 助手卡片：头像取 base64 + 可拖动 + 单击展开 */
makeFloatDraggable(document.getElementById("detail-win"), false);
makeFloatDraggable(document.getElementById("log-win"), false);
setDetailWin(false);
setLogWin(false);

/* ============ 按钮 ============ */
document.getElementById("btn-fit").addEventListener("click", () => { if (requireCase()) fit(); });
document.getElementById("ending-overlay").addEventListener("click", () => {
  if (!endingState) return;
  const cur = endingState.stages[endingState.step - 1];
  if (cur && cur.final){ closeEnding(); return; }
  clearTimeout(endingState.timer);
  playEndingStage();
});
tgFocus.addEventListener("change", applyFocus);
/* 这里原本有个「自动布局」按钮（重排 + 解除全部「已固定」）。2026-10-14 删掉：
   layout() 的 seed() 对已有坐标的节点直接跳过，所以它只是在当前位置上再跑 260 轮弹簧迭代 ——
   实测点一次会让 31/31 个节点整体晃 50~165px（既没整理出更清楚的图，也不收敛），
   玩家能看见的实际效果只有"我摆好的位置被抖散了 + 钉住全没了"。
   位置要留住就右键钉住（唯一的钉住入口），要重排就自己拖 —— 不再有全局重排这个动作。 */
document.getElementById("btn-undo").addEventListener("click", () => {
  if (!requireCase()) return;
  if (!history.length){ log("没有可撤销的操作", "warn"); return; }
  restore(history.pop());
  layout(); render();
});
document.getElementById("btn-reset").addEventListener("click", () => {
  if (!requireCase()) return;
  history = [];
  clearCaseState(CASE_ID);   /* 重置也清掉本案存档，避免下次回访又续上旧进度 */
  resetTec();                /* 重置是全新开局，TEC 也一并清空 */
  closeDlgWin();             /* 角色对话窗跟着清（台词进度已随 G 重置，旧窗挂在失效节点上） */
  closeBagWin();             /* 证物袋窗同理：常驻于离屏/回访，不常驻于重置 */
  closeClueWin();            /* 线索册窗与证物袋同级：同样只在此处与换案时清 */
  boot();
  refreshMusicIcon();        /* 重置后重新评估唱针状态：若针已不在，图标/窗口/最小化卡片一并收 */
  log("已重置为初始状态", "sys");
});
document.getElementById("btn-reach").addEventListener("click", () => {
  if (!requireCase()) return;
  const total = Object.keys(SCENES).length;
  const adj = {};
  Object.keys(SCENES).forEach(s => sceneLocs(s).forEach(t => (adj[s] = adj[s] || []).push(t)));
  const seen = new Set([START]), q = [START];
  while (q.length){ const c = q.shift(); (adj[c] || []).forEach(n => { if (!seen.has(n)){ seen.add(n); q.push(n); } }); }
  const extra = new Set(Object.keys(condRoutes));
  const bad = Object.keys(SCENES).filter(s => !seen.has(s) && !extra.has(s));

  let html = "<span class='close' onclick=\"document.getElementById('verdict').style.display='none'\">×</span>";
  html += "<h4>可达性检查 · " + total + " 个场景</h4>";
  html += "<div class='vrow'><span class='dot' style='background:#2b2b26'></span><div>沿文本链接可达 <b>" + seen.size + "</b> 个</div></div>";
  html += "<div class='vrow'><span class='dot' style='background:#5c584a'></span><div>需条件触发才能进 <b>" + extra.size + "</b> 个</div></div>";
  html += "<div class='vrow'><span class='dot' style='background:#8a8672'></span><div>只能靠「前往」命令进 <b>" + bad.length + "</b> 个</div></div>";
  if (bad.length){
    html += "<div style='margin-top:8px;padding-top:8px;border-top:1px solid #e8eaed'>";
    bad.forEach(s => { html += "<div style='margin:2px 0'>· " + esc(SCENES[s].title) + " <code>" + s + "</code></div>"; });
    html += "</div>";
  }
  verdict.innerHTML = html;
  verdict.style.display = "block";
});
