/* ============ 布局：力导向（拖拽不改变位置） ============ */
let layoutTimer = null, edgeTimer = null;
function layout(){
  const list = Object.values(G.nodes).filter(n => !n.hidden && !n.stored);
  if (!list.length) return;
  const W = 2000, H = 1300;

  const seed = n => {
    if (n.x != null) return;
    if (isContainerNode(n)){                       /* 容器（场景 + 书桌这类物品）按网格落位 */
      const i = Object.keys(G.nodes).filter(k => isContainerNode(G.nodes[k])).indexOf(n.key);
      n.x = 200 + (i % 5) * 380;
      n.y = 160 + Math.floor(i / 5) * 300;
    } else {
      n.x = 700 + (Math.random() - .5) * 420;
      n.y = 560 + (Math.random() - .5) * 420;
    }
  };
  list.forEach(seed);

  const R = n => isContainerNode(n) ? 80 : 68;
  const free = n => !n.pinned;
  for (let it = 0; it < 260; it++){
    for (let i = 0; i < list.length; i++){
      const a = list[i];
      for (let j = i + 1; j < list.length; j++){
        const b = list[j];
        let dx = b.x - a.x, dy = b.y - a.y;
        let d2 = dx * dx + dy * dy;
        if (d2 < 1){ dx = Math.random() - .5; dy = Math.random() - .5; d2 = 1; }
        const d = Math.sqrt(d2), ux = dx / d, uy = dy / d;
        const rep = 30000 / d2;
        if (free(a)){ a.x -= ux * rep; a.y -= uy * rep; }
        if (free(b)){ b.x += ux * rep; b.y += uy * rep; }
        const min = R(a) + R(b) + 14;
        if (d < min){
          const push = (min - d) / 2;
          if (free(a)){ a.x -= ux * push; a.y -= uy * push; }
          if (free(b)){ b.x += ux * push; b.y += uy * push; }
        }
      }
    }
    G.edges.forEach(e => {
      const a = G.nodes[e.a], b = G.nodes[e.b];
      if (!a || !b) return;
      const dx = b.x - a.x, dy = b.y - a.y;
      const d = Math.hypot(dx, dy) || 1, ux = dx / d, uy = dy / d;
      const rest = e.kind === "entity" ? 185 : e.kind === "move" ? 300 : 150;
      const f = (d - rest) * 0.014;
      if (free(a)){ a.x += ux * f; a.y += uy * f; }
      if (free(b)){ b.x -= ux * f; b.y -= uy * f; }
    });
    list.forEach(n => { if (free(n)){ n.x += (W / 2 - n.x) * 0.0022; n.y += (H / 2 - n.y) * 0.0022; } });
  }
  list.forEach(n => {
    if (n.pinned) return;                  /* 右键钉住的节点不再动 */
    n.x = Math.max(60, Math.min(W - 220, n.x));
    n.y = Math.max(50, Math.min(H - 120, n.y));
  });
}

/* ============ 渲染 ============ */
const NODE_W = { loc:152, item:130, char:130, clue:130 };
const NODE_H = { loc:54, item:46, char:46, clue:46 };

/* ============ 拖动收尾登记表 ============
   任何「拖到一半可能被 render() 打断」的手势都在这里登记一个 abort 回调。
   为什么必须收尾：render() 会 nodeLayer.innerHTML = "" 重建**全部**节点 DOM。被拖的那个元素
   一旦离树，指针捕获被隐式释放，pointerup / pointercancel 就再也不会派发过来 —— 收尾逻辑跑不到，
   镜像就永久留在 #drag-layer（画布上多出一个点不动也拖不动的节点），同时这次拖放的落点动作丢失。
   真实触发路径：TEC 分析是 setTimeout（11-dialog.js），玩家一边拖节点一边等分析，
   分析完成且**本次真产出新线索**时 settle() → render() —— 正是「拖着拖着线索掉下来」那一刻。
   在重建之前统一收尾：把位移写回 n.x/n.y、摘掉镜像与幽灵线、清掉落点高亮。 */
const dragAborters = new Set();
function abortActiveDrags(){
  if (!dragAborters.size) return;
  Array.from(dragAborters).forEach(fn => { try { fn(); } catch(_){} });
  dragAborters.clear();
}
function registerDrag(fn){ dragAborters.add(fn); return fn; }
function unregisterDrag(fn){ dragAborters.delete(fn); }
/* 兜底：重建时清空镜像层。走到这里时各手势自己的 abort 已经摘掉各自那一片，
   这句只为「万一还有没登记的镜像」收尾，保证 #drag-layer 绝不带着旧镜像跨过一次重建。 */
function clearDragLayer(){
  const l = document.getElementById("drag-layer");
  if (l) l.innerHTML = "";
}

function render(){
  abortActiveDrags();     /* 先给拖动中的手势收尾，再动 DOM（见上） */
  clearDragLayer();
  nodeLayer.innerHTML = "";
  svg.innerHTML = "";

  Object.values(G.nodes).forEach(n => {
    if (n.hidden || n.stored){ n.el = null; return; }
    const el = document.createElement("div");
    /* 画布上的长相只看 kind：场景是宽节点（■），书桌 / 垃圾桶是普通物品节点（□）。
       「能不能展开」是容器的事 —— 由 unexplored / collapsed 两个类表达，与 kind 无关。 */
    const kindCls = n.kind === "loc" ? "scene-node" : "ent-node ent-" + n.kind;
    let cls = "node " + kindCls;
    if (isContainerNode(n) && !G.explored.has(n.id)) cls += " unexplored";
    if (isContainerNode(n) && G.collapsed.has(n.id)) cls += " collapsed";
    if (n.kind === "loc" && isHub(n.id)) cls += " hub";
    if (n.kind === "clue" && G.captured.has(n.id)) cls += " got";
    if (n.fresh) cls += " pop";
    if (n.lit) cls += " lit";
    el.className = cls;
    if (!isFinite(n.x)) n.x = 200 + Math.random() * 1600;
    if (!isFinite(n.y)) n.y = 120 + Math.random() * 1000;
    el.style.left = n.x + "px";
    el.style.top  = n.y + "px";
    el.dataset.key = n.key;

    let sub = isContainerNode(n) ? (G.collapsed.has(n.id) ? "已折叠 · 双击展开" : (G.explored.has(n.id) ? "已探索" : "未探索 · 双击展开")) : kindName(n.kind);
    if (n.kind === "clue" && G.captured.has(n.id)) sub = "线索 · 已捕获";
    el.innerHTML = "<div class='n-title'>" + esc(n.label) + "</div><div class='n-sub'>" + esc(sub) + "</div>";

    /* 「条件进入」角标已撤（2026-10-14，用户要求）。它是一枚**实心**药丸，和「新 / 对话 N」
       挤在右上角同一排；而它想说的那件事别处已经说过两遍 —— 详情窗有「参与条件跳转」行，
       可达性统计里有「需条件触发才能进 N 个」。节点上只该留「真的没路走」这一种警告。
       注意 `!condRoutes[n.id]`：条件场景**本来就不该**掉进下面这条（旧代码靠 else-if 达到同一效果），
       否则撤掉一枚角标的当天就会在同一个位置冒出另一枚，玩家只会以为"角标换了个字"。
       condRoutes 本身保留 —— 上面说的那两处还在用它。 */
    if (n.kind === "loc" && !G.explored.has(n.id) && inbound[n.id] === 0 &&
        !condRoutes[n.id] && !sceneLocs(n.id).length){
      const b = document.createElement("span"); b.className = "badge warn"; b.textContent = "无文本入口"; el.appendChild(b);
    }
    /* 已固定：右键钉住的节点。必须看得见——它同时意味着「自动布局不挪它」
       与「折叠不收它」，不标出来玩家只会看到"有的收有的不收"而判定成 bug */
    if (n.pinned){
      const b = document.createElement("span"); b.className = "badge pin"; b.textContent = "已固定"; el.appendChild(b);
    }
    /* 「新」角标认 n.unread（不是 n.fresh）：unread 一直挂着，**只有玩家点过这个节点才会被
       clearFresh() 摘掉**。旧版拿 n.fresh 当条件，而 fresh 是「本轮镜头聚焦」的一次性标记 ——
       render() 末尾就会擦掉它，于是任何一次重绘（右键钉住 / 自动布局 / 撤销 / 折叠…）
       都会把全场「新」角标一起洗掉，看着就像"钉一下所有新都没了"。 */
    if (n.unread){
      const b = document.createElement("span"); b.className = "badge new"; b.textContent = "新"; el.appendChild(b);
    }
    /* 「对话 N」角标已撤（2026-10-15，用户要求节点上不显示条数）：能不能继续聊，
       详情窗状态行与名册行都有状态词，对话呈现统一走 TEC 式对话窗（11-dialog.js）。 */
    attachInteractions(el, n);
    nodeLayer.appendChild(el);
    n.el = el;
    n.fresh = false;   /* 只擦「聚焦用」的一次性标记；n.unread（角标）留着等玩家来点 */
  });

  paintEdgesFor(420);
  updateCrumbs();
  updateTecBadge();
  updateBagBadge();
  updateLedgerBadge();
  updateInferBadge();
  refreshClueWin();     /* 开着的索引窗跟着图刷新（关着时是空操作） */
  refreshPeopleWin();
  refreshInferWin();    /* 推演窗同理：阵列与执行者头顶的种子对话框都是状态驱动的，
                           撤销 / 续档把 G 滚回去之后，开着的窗不能留着旧 DOM */
  /* 重建 DOM 后恢复选中态并重挂聚焦淡化 */
  if (sel && G.nodes[sel] && G.nodes[sel].el) G.nodes[sel].el.classList.add("sel"); else sel = null;
  applyFocus();
  paintDetail();     /* 详情窗「状态」跟着图一起刷新（点亮 / 捕获 / 展开 / 对话进度都会变） */
}
function paintEdges(){
  svg.innerHTML = "";
  const focusSel = (tgFocus.checked && sel && G.nodes[sel]) ? sel : null;
  G.edges.forEach(e => {
    const a = G.nodes[e.a], b = G.nodes[e.b];
    if (!a || !b || !a.el || !b.el || a.hidden || b.hidden || a.stored || b.stored) return;
    const A = center(a.el), B = center(b.el);
    const p = document.createElementNS("http://www.w3.org/2000/svg", "path");
    const mx = (A.x + B.x) / 2, my = (A.y + B.y) / 2 - Math.min(70, Math.abs(B.x - A.x) * 0.16);
    p.setAttribute("d", "M" + A.x + " " + A.y + " Q" + mx + " " + my + " " + B.x + " " + B.y);
    p.setAttribute("fill", "none");
    if (e.kind === "tried"){ p.setAttribute("stroke", "#b8b49e"); p.setAttribute("stroke-width", 1);
      p.setAttribute("stroke-dasharray", "3 4"); p.setAttribute("opacity", .55); }
    else if (e.kind === "move"){ p.setAttribute("stroke", "#2b2b26"); p.setAttribute("stroke-width", 1.6); }
    else if (e.kind === "cond"){ p.setAttribute("stroke", "#2b2b26"); p.setAttribute("stroke-width", 1.6);
      p.setAttribute("stroke-dasharray", "5 4"); }
    else { p.setAttribute("stroke", "#8a8672"); p.setAttribute("stroke-width", 1.3); }
    if (focusSel && e.a !== focusSel && e.b !== focusSel) p.setAttribute("opacity", .12);
    svg.appendChild(p);
  });
  paintGlow();
}
/* 让连线在一段动画期间持续跟随节点：节点回弹 / 自动布局时 left/top 有 .34s 过渡，
   只画一次会在动画期间"脱线"。这里按帧重画，center() 读的是动画中的当前值。 */
function paintEdgesFor(ms){
  paintEdges();
  clearInterval(edgeTimer);
  const t0 = Date.now();
  edgeTimer = setInterval(() => { paintEdges(); if (Date.now() - t0 > ms) clearInterval(edgeTimer); }, 40);
}
/* 弹回原位：用 JS 每帧同时推进「节点位置 + 连线」。
   不能只改 left/top 交给 CSS 过渡去跑——过渡期间节点在动、连线只在别处按 40ms 补画，
   两者必然错开（实测最多差 ~130px），视觉上就是"线断了"。这里在同一次回调里一起更新，永远同步。 */
function springBack(el, ox, oy){
  if (el.__springTimer){ clearTimeout(el.__springTimer); el.__springTimer = null; }
  const sx = parseFloat(el.style.left) || 0, sy = parseFloat(el.style.top) || 0;
  el.style.transition = "none";            /* 交给 JS 接管，别让 CSS 过渡掺一脚 */
  const now = () => (typeof performance !== "undefined" && performance.now) ? performance.now() : Date.now();
  const t0 = now(), DUR = 300, ease = p => 1 - Math.pow(1 - p, 3);
  const finish = () => {
    el.__springTimer = null;
    el.style.left = ox + "px"; el.style.top = oy + "px";
    el.style.transition = "";              /* 还原 CSS 过渡 */
    paintEdges();
  };
  const step = () => {
    const p = Math.min(1, (now() - t0) / DUR), e = ease(p);
    el.style.left = (sx + (ox - sx) * e) + "px";
    el.style.top  = (sy + (oy - sy) * e) + "px";
    paintEdges();
    if (p < 1){
      el.__springTimer = setTimeout(step, 16);
      if (!el.__springTimer) finish();     /* 无定时器环境（无头 stub）：同步收尾 */
    } else finish();
  };
  step();
}
function center(el){
  /* 优先读「当前渲染值」：节点 left/top 带 .34s 过渡，弹回时内联样式已经写成终点值，
     只有 getComputedStyle 才拿得到动画进行中的当前位置，否则连线会在回弹期间与节点脱开。 */
  let l = parseFloat(el.style.left), t = parseFloat(el.style.top);
  if (typeof getComputedStyle === "function"){
    const cs = getComputedStyle(el);
    const cl = parseFloat(cs.left), ct = parseFloat(cs.top);
    if (isFinite(cl)) l = cl;
    if (isFinite(ct)) t = ct;
  }
  return { x: (isFinite(l) ? l : 0) + el.offsetWidth / 2,
           y: (isFinite(t) ? t : 0) + el.offsetHeight / 2 };
}
function updateCrumbs(){
  const total = Object.keys(G.nodes).length;
  const visible = Object.values(G.nodes).filter(n => !n.hidden && !n.stored).length;
  crumbs.innerHTML = "节点 <b>" + visible + "/" + total + "</b> · 已探索场景 <b>" +
    G.explored.size + "/" + Object.keys(SCENES).length + "</b> · 已试组合 <b>" + G.tried.size +
    "</b> · 捕获线索 <b>" + G.captured.size + "</b> · 结局 <b>" + G.endings.size + "/" + ENDINGS.length + "</b>";
}

/* 顶层拖拽镜像：复制一份被拖节点放到 #drag-layer（z 高于窗口/图标），原节点暂时隐藏。
   否则往右下角拖（TEC 窗所在地）时，节点会被 #case-win 的层叠上下文压在窗口下层。 */
/* 定位改用「布局坐标(left/top)」而不是 transform:translate。
   原因：新插入的元素若用 transform 平移来定位，真实 GPU 合成器可能先提交一帧
   「还没加上平移、停在层原点 (0,0)＝桌面左上角」的画面，表现为拖动时左上角闪一下。
   布局坐标（left/top）在绘制前必定生效，不会出现这种半成品帧。
   缩放仍用 transform（transform-origin:0 0，只缩放不移位）。 */
function positionDragMirror(m, el){
  const r = el.getBoundingClientRect(), sr = desktopEl.getBoundingClientRect();
  const k = view.k || 1;
  m.style.left = (r.left - sr.left) + "px";
  m.style.top  = (r.top  - sr.top ) + "px";
  m.style.transform = "scale(" + k + ")";
}
function makeDragMirror(el){
  const layer = document.getElementById("drag-layer");
  if (!layer || !el.cloneNode) return null;
  const m = el.cloneNode(true);
  m.classList.add("drag-mirror");
  m.style.transformOrigin = "0 0";
  positionDragMirror(m, el);      /* 入 DOM 前就把 left/top/scale 写好，首帧即正确位置 */
  m.style.visibility = "hidden";
  layer.appendChild(m);
  el.style.visibility = "hidden";
  void m.offsetWidth;             /* 强制一次布局，确保显示时位置已落定 */
  m.style.visibility = "visible";
  return m;
}
function syncDragMirror(m, el){ if (m) positionDragMirror(m, el); }
