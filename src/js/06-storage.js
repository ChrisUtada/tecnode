/* ============ 场景折叠收纳 ============ */
function recomputeHidden(){
  Object.values(G.nodes).forEach(n => { n.hidden = false; });
  let changed = true;
  while (changed){
    changed = false;
    G.collapsed.forEach(sid => {
      const sceneKey = containerKey(sid);   /* 折叠的可能是场景，也可能是书桌这类容器物品 */
      Object.values(G.nodes).forEach(n => {
        if (n.stored || n.hidden || n.pinned || n.key === sceneKey) return;
        if (n.homeScene !== sid) return;
        /* 只要还有一条边连着"会保持可见"的节点，就不藏（被用到别处的节点会留下） */
        const exported = G.edges.some(e => {
          if (e.a !== n.key && e.b !== n.key) return false;
          const other = G.nodes[e.a === n.key ? e.b : e.a];
          return other && !other.hidden && !other.stored && other.key !== sceneKey && other.homeScene !== sid;
        });
        if (!exported){ n.hidden = true; changed = true; }
      });
    });
  }
}
function toggleCollapse(sid){
  if (!G.explored.has(sid)) return;
  pushHistory();
  const collapsing = !G.collapsed.has(sid);
  if (collapsing) G.collapsed.add(sid); else { G.collapsed.delete(sid); unstoreScene(sid); }
  closeBubble(); closeNarr(); closePwPop();   /* 锚在画布上的浮层收掉；TEC 是常驻助手窗，保留 */
  recomputeHidden(); layout(); render();
  /* 折叠不是「全收」：已固定的节点、以及跟场外还有连线的节点会留在画布上。
     必须报个数，否则玩家看到"有的收有的不收"只会当成 bug（留在画布上的都有「已固定」角标可查） */
  if (collapsing){
    const left = Object.values(G.nodes).filter(x => !isContainerNode(x) && !x.stored && !x.hidden && x.homeScene === sid).length;
    if (left) log("「" + esc(containerTitle(sid)) + "」另有 " + left + " 个节点留在画布上（已固定 / 与场外相连）", "sys");
  }
}

/* ============ 节点收纳：把节点放回场景（现场=仓库，画布=线索板） ============
   机制保留、入口已移除：拖到折叠场景上「放回现场」那条路在 v2 里与证物袋 / 线索册重叠
   （没有清单、只能整场展开才能取回），已改为提示。这里只剩内部 / 测试入口（window.__store），
   以及展开场景时的取回（unstoreScene）——旧存档里 storedIn = 场景 的节点仍能正常取回。 */
function storeNode(key, sid){
  const n = G.nodes[key];
  if (!n || isContainerNode(n) || n.stored) return false;   /* 容器（场景 / 书桌 / 垃圾桶）是不可收纳的落脚点 */
  pushHistory();
  n.stored = true; n.storedIn = sid; n.homeScene = sid; n.pinned = false;
  closeBubble(); closePwPop();
  recomputeHidden(); layout(); render();
  return true;
}
function unstoreScene(sid){
  const sn = G.nodes[containerKey(sid)];
  let i = 0;
  Object.values(G.nodes).forEach(n => {
    if (!n.stored || n.storedIn !== sid) return;
    n.stored = false; n.hidden = false; markFresh(n);
    if (sn){ n.x = sn.x + 60 + (i % 4) * 40; n.y = sn.y + 60 + Math.floor(i / 4) * 40; }
    i++;
  });
}

/* ============ 证物袋：随身携带的收纳 dock（与场景收纳共用 stored 机制） ============
   两个方向都要能走（2026-10-16）：
   · 拖进 —— 画布上的节点拖到袋图标 / 袋窗上松手（08-interact.js 的 iconHit 分支）；
   · 拖出 —— 袋里的行按住拖走：另一个收纳窗（跨窗搬运）/ 推演桌布（线索归位）/ 画布（取回）。
   单击一行仍是取回画布（回到袋子旁边），拖拽是它的加速版。 */
let bagWinEl = null;
function closeBagWin(){ if (bagWinEl){ bagWinEl.remove(); bagWinEl = null; } }
function bagItems(){ return Object.values(G.nodes).filter(n => n.stored && n.storedIn === "BAG"); }

function bagStore(key){
  const n = G.nodes[key];
  if (!n || isContainerNode(n) || n.stored) return false;   /* 容器（场景 / 书桌 / 垃圾桶）进不了袋子 */
  pushHistory();
  n.bagFrom = n.homeScene || null;   /* 记住来源场景，用于清单标注 */
  n.stored = true; n.storedIn = "BAG"; n.pinned = false;
  recomputeHidden(); layout(); render(); refreshBagWin();
  return true;
}
/* 取回画布。两种入口共用这一支（cx/cy 是「拖出来」时松手的那一点）：
   · 带落点 —— 落在松手那一点，与 boardTake 同一口径：先换算成世界坐标、**再**减去半张卡
     （卡片尺寸是世界单位，不能在屏幕坐标里先减；k≠1 时两者差一个 k 倍，实测差过 120 世界像素）。
     这条路上**不跑 layout()**：跟手落下的位置不该被弹簧立刻推走。
   · 不带落点（单击一行）—— 仍旧放回袋子旁边，并重整一次版（旧口径，别改）。 */
function bagTake(key, cx, cy){
  const n = G.nodes[key];
  if (!n || n.storedIn !== "BAG") return false;
  /* 案件窗关着时不能取：取出是放回画布的操作，不能对看不见的画布施展 */
  if (!requireCase()) return false;
  pushHistory();
  n.stored = false; n.storedIn = null; n.hidden = false; markFresh(n);
  const dropped = (cx != null && cy != null);
  if (dropped){
    const wpt = toWorld(cx, cy);
    n.x = wpt.x - (NODE_W[n.kind] || 130) / 2; n.y = wpt.y - (NODE_H[n.kind] || 46) / 2;
  } else {
    /* 取回到袋子附近的画布位置（屏幕坐标换算成世界坐标） */
    const dock = document.getElementById("bag-dock");
    const r = dock.getBoundingClientRect();
    const wpt = toWorld(r.left + r.width / 2, r.top - 40);
    n.x = wpt.x; n.y = wpt.y;
    layout();
  }
  render(); refreshBagWin();
  return true;
}
/* 证物袋落点：袋窗（开着时）或袋图标。与 overMatrixDrop / overLedgerDrop 并排看，三个收纳落点一目了然。
   袋窗本体在 06、册窗在 12、推演窗在 13 —— 函数声明提升，互相调用没问题：只在函数**运行时**
   读别的切片的 `let`（bagWinEl / clueWinEl / inferWinEl），不踩 TDZ；顶层读才会。 */
function overBagDrop(cx, cy){
  if (bagWinEl && bagWinEl.style.display !== "none"){
    const r = bagWinEl.getBoundingClientRect();
    if (cx >= r.left && cx <= r.right && cy >= r.top && cy <= r.bottom) return true;
  }
  const ic = document.getElementById("bag-dock");
  if (ic){
    const r = ic.getBoundingClientRect();
    if (cx >= r.left && cx <= r.right && cy >= r.top && cy <= r.bottom) return true;
  }
  return false;
}
/* ---- 两扇收纳窗之间直接搬运（证物袋 ↔ 线索册）----
   与 boardToLedger 同款：只改 storedIn，重画两个清单，**不跑 layout()**
   （搬一个条目不该顺手重排玩家的摆位）。
   from/to 都要显式写出来：这是「搬」不是「收」—— ledgerStore / bagStore 对已收纳的节点一律拒收，
   所以不能复用它们。requireCase 与 boardToLedger 同一道门：这类手势的另一半落点是画布。 */
function restash(key, from, to){
  const n = G.nodes[key];
  if (!n || !n.stored || n.storedIn !== from || from === to) return false;
  if (!requireCase()) return false;
  pushHistory();
  n.storedIn = to; n.pinned = false;
  if (to === "BAG") n.bagFrom = n.homeScene || null;   /* 袋清单的「来自 ×××」标注 */
  render();   /* 三扇清单窗都在 render() 里跟着图刷新，不必各自再叫一次 */
  return true;
}
/* 袋 → 册：只有线索进得了册子。话术与 ledgerStore 逐字一致，别让同一条规则有两种说法。 */
function bagToLedger(key){
  const n = G.nodes[key];
  if (!n || n.kind !== "clue"){ toast("只有线索能收进线索册", true); return false; }
  return restash(key, "BAG", "LEDGER");
}
/* 袋 → 桌布：复用 assignClue（它认 G.nodes 里任何线索，不管现在收在哪儿），
   storedIn 从 BAG 改写成 MATRIX，撤销栈照记。 */
function bagToMatrix(key){
  const n = G.nodes[key];
  if (!n || n.kind !== "clue"){ toast("只有线索能上桌布", true); return false; }
  const sense = (CLUES[n.id] || {}).type;
  if (!sense){ toast("这条线索没有感官类型，上不了桌布", true); return false; }
  return assignClue(key, sense);
}
function toggleBagWin(){
  if (bagWinEl){ closeBagWin(); return; }
  const w = makeWindow("STORAGE // 证物袋", closeBagWin);
  w.el.classList.add("bag-win");
  desktopEl.appendChild(w.el);
  makeFloatDraggable(w.el, false);
  bagWinEl = w.el;
  refreshBagWin();
}
function refreshBagWin(){
  if (!bagWinEl) return;
  const body = bagWinEl.querySelector(".syswin-body");
  if (!body) return;
  body.innerHTML = "";
  const items = bagItems();
  if (!items.length){
    const d = document.createElement("div");
    d.className = "bag-empty";
    d.textContent = "（空）把画布上的节点拖到袋子上（或本窗口内）收纳";
    body.appendChild(d);
    return;
  }
  items.forEach(n => {
    const d = document.createElement("div");
    d.className = "bag-item";
    const label = document.createElement("span"); label.textContent = n.label;
    const src = document.createElement("span"); src.className = "src";
    src.textContent = n.bagFrom && containerData(n.bagFrom) ? "来自 " + containerTitle(n.bagFrom) : "";
    d.appendChild(label); d.appendChild(src);
    makeBagRowDraggable(d, n.key);   /* 点击 = 取回画布；按住拖走 = 三个落点（见下） */
    body.appendChild(d);
  });
}
/* 袋中一行的指针拖拽：与线索册那一行（makeLedgerRowDraggable）同款，落点也是三个 ——
   另一个收纳窗（跨窗搬运）/ 推演桌布（线索归位）/ 画布（取回，就落在松手那一点）。
   镜像**不克隆整窗**，一旦拖离就以「节点块」现身（mx-chip.node，与桌布上的归位 chip 同款观感），
   居中跟手（#drag-layer）；松手在三个落点之外 = 取回画布，不弹回。
   纯点击仍是取回画布（回到袋子旁边）—— 拖过的那一下吞掉紧跟的 click，两个动作不连发。 */
function makeBagRowDraggable(row, key){
  let dragging = false, moved = false, wasMoved = false, sx = 0, sy = 0,
      mirror = null, mw = 0, mh = 0, sr = null;
  /* 三个落点的高亮都要能撤（册窗 / 册图标 / 桌布 / 推演器图标） */
  const clearOver = () => {
    if (clueWinEl && clueWinEl.classList) clueWinEl.classList.remove("over");
    const ci = document.getElementById("clue-icon");
    if (ci && ci.classList) ci.classList.remove("over");
    const bd = inferWinEl ? inferWinEl.querySelector(".mx-board") : null;
    if (bd) bd.classList.remove("over");
    const ii = document.getElementById("infer-icon");
    if (ii && ii.classList) ii.classList.remove("over");
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
      const n = G.nodes[key];
      mirror = document.createElement("div");
      /* 副行按真实种类写（袋里装的不只是线索：物品 / 角色 / 线索都在这个袋子里） */
      mirror.className = "mx-chip node ent-node ent-" + n.kind + " drag-mirror";
      mirror.innerHTML = "<div class='n-title'>" + esc(n.label) + "</div><div class='n-sub'>" + esc(kindName(n.kind)) + "</div>";
      mirror.style.position = "absolute";
      mirror.style.width = "140px";
      layer.appendChild(mirror);
      mw = mirror.offsetWidth || 140; mh = mirror.offsetHeight || 40;
      row.style.visibility = "hidden";
    }
    mirror.style.left = (e.clientX - sr.left - mw / 2) + "px";
    mirror.style.top  = (e.clientY - sr.top  - mh / 2) + "px";
    /* 落点高亮：册窗 / 册图标（跨窗搬运）、桌布（线索归位）。桌布只在推演窗开着时存在。 */
    const lw = clueWinEl;
    if (lw && lw.classList){
      const r = lw.getBoundingClientRect();
      lw.classList.toggle("over", e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom);
    }
    const ci = document.getElementById("clue-icon");
    if (ci && ci.classList){
      const r = ci.getBoundingClientRect();
      ci.classList.toggle("over", e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom);
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
    /* 落点判定顺序即优先级：先判「另一个收纳窗」，再判桌布，其余一律算画布。
       册窗与袋窗各占一个角、桌面图标也在不同位置，实际不会互相盖住。 */
    if (overLedgerDrop(e.clientX, e.clientY)){ bagToLedger(key); return; }
    if (overMatrixDrop(e.clientX, e.clientY)){ bagToMatrix(key); return; }
    bagTake(key, e.clientX, e.clientY);
  };
  row.addEventListener("pointerup", finish);
  row.addEventListener("pointercancel", () => { unregisterDrag(abortRowDrag); abortRowDrag(); });
  /* 点击 = 取回画布（回袋子旁边）；刚拖完的那一下（wasMoved）不算点击 */
  row.addEventListener("click", () => {
    if (wasMoved){ wasMoved = false; return; }
    bagTake(key);
  });
}
function updateBagBadge(){
  const dock = document.getElementById("bag-dock");
  if (!dock) return;
  const cnt = bagItems().length;
  let b = dock.querySelector(".badge");
  if (cnt > 0){
    if (!b){ b = document.createElement("span"); b.className = "badge cnt"; dock.appendChild(b); }
    b.textContent = cnt + " 件";
  } else if (b) b.remove();
}
/* 线索册图标角标：册子里（已收纳、不在画布上）的线索条数 */
function updateLedgerBadge(){
  const icon = document.getElementById("clue-icon");
  if (!icon) return;
  const cnt = ledgerItems().length;
  let b = icon.querySelector(".badge");
  if (cnt > 0){
    if (!b){ b = document.createElement("span"); b.className = "badge cnt"; icon.appendChild(b); }
    b.textContent = cnt + " 条";
  } else if (b) b.remove();
}
/* 推演器图标角标：桌布上已归位的线索数（与证物袋角标同一套） */
function updateInferBadge(){
  const icon = document.getElementById("infer-icon");
  if (!icon) return;
  const cnt = Object.keys(G.matrix).reduce((s, k) => s + G.matrix[k].length, 0);
  let b = icon.querySelector(".badge");
  if (cnt > 0){
    if (!b){ b = document.createElement("span"); b.className = "badge cnt"; icon.appendChild(b); }
    b.textContent = cnt + " 条";
  } else if (b) b.remove();
}
