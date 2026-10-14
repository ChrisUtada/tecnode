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

/* ============ 证物袋：随身携带的收纳 dock（与场景收纳共用 stored 机制） ============ */
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
function bagTake(key){
  const n = G.nodes[key];
  if (!n || n.storedIn !== "BAG") return false;
  /* 案件窗关着时不能取：取出是放回画布的操作，不能对看不见的画布施展 */
  if (!requireCase()) return false;
  pushHistory();
  n.stored = false; n.storedIn = null; n.hidden = false; markFresh(n);
  /* 取回到袋子附近的画布位置（屏幕坐标换算成世界坐标） */
  const dock = document.getElementById("bag-dock");
  const r = dock.getBoundingClientRect();
  const wpt = toWorld(r.left + r.width / 2, r.top - 40);
  n.x = wpt.x; n.y = wpt.y;
  layout(); render(); refreshBagWin();
  return true;
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
    d.addEventListener("click", () => bagTake(n.key));
    body.appendChild(d);
  });
}
function updateBagBadge(){
  const dock = document.getElementById("bag-dock");
  if (!dock) return;
  const cnt = bagItems().length;
  let b = dock.querySelector(".badge");
  if (cnt > 0){
    if (!b){ b = document.createElement("span"); b.className = "badge cond"; dock.appendChild(b); }
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
    if (!b){ b = document.createElement("span"); b.className = "badge cond"; icon.appendChild(b); }
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
    if (!b){ b = document.createElement("span"); b.className = "badge cond"; icon.appendChild(b); }
    b.textContent = cnt + " 条";
  } else if (b) b.remove();
}
