/* ============ INFERENCE_MATRIX // 逻辑阵列 ============ */
/* ============ 逻辑阵列：桌布式推演窗 ============
   桌布几何与 CSS .mx-board 的尺寸对应（DOM stub 里 offsetWidth 是常量，量不出真尺寸时退回这两个值）。
   560×420：去掉文字标签后窗体收边，但**五芒星绝对大小不变**——顶点间距与 640×460 版一致，
   仅整体平移（水平 -40px、垂直 -20px）重新居中：五芒星**形心与桌布中心重合**，
   这样中央头像正好坐在星的中枢上（五芒星横跨 332px、纵跨 316px，是窗体缩小的物理下限）。 */
const MX_W = 560, MX_H = 420;
/* 星阵外圆半径：五感顶点外接圆(≈175) + 20 缓冲，圆心 = 桌布中心 = 五芒星形心。
   外圆与五芒星合成一条路径（先圆后星），常显框与长按描线共用。 */
const MX_CIRCLE_R = 195;
/* 五感锚点：环绕中央执行者的方位（桌布宽高的分数）。数值按 560×420 反推：
   顶点（卡中心）= (MX_ANCHORS.xy × 桌布) + 27px 卡占位，换算后与原 640×460 版的顶点绝对坐标一致。 */
/* 五感锚点：以「卡片中心」近似正五边形（桌布坐标下半径≈137px，绕板心 72° 均布）摆放，
   这样证据（卡片中心）正好是五芒星的五个顶点。锚点 top 已减去卡片占位（≈27px）：
   去掉文字标签后 chip 从锚点顶起，margin4 + 半卡高23 即中心偏移。 */
const MX_ANCHORS = { vision:[.5000,.0192], hearing:[.7971,.3073], touch:[.6840,.7727], smell:[.3160,.7727], taste:[.2029,.3073] };
/* 执行者头像：暂借 TEC 的（同风格同尺寸），新头像做好只改这一行 */
const EXECUTOR_AVATAR = "@@ASSET:executor-avatar.png@@";
/* 执行者表情：配方不匹配时在头像上方弹出（心碎，16×16 像素，含气泡框） */
const EXEC_EMOTE_HEARTBROKEN = "@@ASSET:emote-heartbroken.png@@";

let inferWinEl = null;
function closeInferWin(){ if (inferWinEl){ inferWinEl.remove(); inferWinEl = null; } }
function toggleInferWin(){
  if (inferWinEl){ closeInferWin(); return; }
  const w = makeWindow("INFERENCE // 逻辑阵列", closeInferWin);
  w.el.classList.add("infer-win");
  desktopEl.appendChild(w.el);
  makeFloatDraggable(w.el, false);
  inferWinEl = w.el;
  refreshInferWin();
}
/* 阵列内的线索卡：**拖出桌布 = 取回画布**（与外部「拖进拖出」一致，卡上不放 ×）。
   桌布 overflow:hidden，所以拖动时把卡片克隆到全局 #drag-layer 跟随指针，松手落在桌布外即取回。 */
function makeMatrixNodeDraggable(card, cid, sense){
  let dragging = false, moved = false, sx = 0, sy = 0, mirror = null, offx = 0, offy = 0, sr = null;
  /* 拖出桌布的方向：**线索册（窗 / 图标）也是落点** —— 与「册 → 桌布」对称的那一半 */
  const clearDropOver = () => {
    if (clueWinEl && clueWinEl.classList) clueWinEl.classList.remove("over");
    const ic = document.getElementById("clue-icon");
    if (ic && ic.classList) ic.classList.remove("over");
  };
  /* 被 render() 打断时的收尾（见 07-render.js 的登记表）：摘镜像、把卡片放回来 */
  const abortCardDrag = () => {
    if (!dragging) return;
    dragging = false;
    card.classList.remove("dragging");
    if (mirror){ mirror.remove(); mirror = null; }
    card.style.visibility = "";
    clearDropOver();
  };
  card.addEventListener("pointerdown", e => {
    if (e.button !== 0) return;
    dragging = true; moved = false; sx = e.clientX; sy = e.clientY;
    sr = desktopEl.getBoundingClientRect();
    registerDrag(abortCardDrag);
    try { card.setPointerCapture(e.pointerId); } catch(_){}
    e.stopPropagation();
  });
  card.addEventListener("pointermove", e => {
    if (!dragging) return;
    const dx = e.clientX - sx, dy = e.clientY - sy;
    if (!moved && Math.abs(dx) + Math.abs(dy) < 5) return;
    moved = true;
    card.classList.add("dragging");
    if (!mirror){
      const layer = document.getElementById("drag-layer");
      const r = card.getBoundingClientRect();
      offx = e.clientX - r.left; offy = e.clientY - r.top;
      mirror = card.cloneNode(true);
      mirror.classList.add("drag-mirror");
      mirror.classList.remove("dragging");
      mirror.style.position = "absolute";
      mirror.style.transform = "none";
      mirror.style.width = r.width + "px"; mirror.style.height = r.height + "px";
      mirror.style.left = (r.left - sr.left) + "px";
      mirror.style.top  = (r.top  - sr.top ) + "px";
      mirror.style.visibility = "hidden";
      layer.appendChild(mirror);
      card.style.visibility = "hidden";
      void mirror.offsetWidth;             /* 强制布局，显示即正确位置 */
      mirror.style.visibility = "visible";
    }
    mirror.style.left = (e.clientX - offx - sr.left) + "px";
    mirror.style.top  = (e.clientY - offy - sr.top ) + "px";
    /* 线索册落点高亮（窗开着 / 图标常驻，谁被压中就亮谁） */
    const lw = clueWinEl;
    if (lw && lw.classList){
      const r = lw.getBoundingClientRect();
      lw.classList.toggle("over", e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom);
    }
    const lic = document.getElementById("clue-icon");
    if (lic && lic.classList){
      const r = lic.getBoundingClientRect();
      lic.classList.toggle("over", e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom);
    }
  });
  const finish = e => {
    if (!dragging) return;
    dragging = false;
    unregisterDrag(abortCardDrag);
    card.classList.remove("dragging");
    if (mirror){ mirror.remove(); mirror = null; }
    card.style.visibility = "";
    clearDropOver();
    if (!moved) return;                    /* 纯点击，不移除 */
    /* 落在线索册上 → 改归册子（回头路有两条：回画布 / 回册子） */
    if (overLedgerDrop(e.clientX, e.clientY)){ boardToLedger(cid, sense); return; }
    const bd = inferWinEl && inferWinEl.querySelector(".mx-board");
    if (bd){
      const r = bd.getBoundingClientRect();
      const inside = e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom;
      if (!inside){                        /* 拖出桌布 → 取回画布 */
        boardTake(cid, sense, e.clientX, e.clientY);
        return;
      }
    }
    refreshInferWin();                     /* 仍在桌布内：复位 */
  };
  card.addEventListener("pointerup", finish);
  card.addEventListener("pointercancel", () => { unregisterDrag(abortCardDrag); abortCardDrag(); });
}
function refreshInferWin(){
  if (!inferWinEl) return;
  const body = inferWinEl.querySelector(".syswin-body");
  if (!body) return;
  body.innerHTML = "";

  const board = document.createElement("div");
  board.className = "mx-board";
  body.appendChild(board);
  const bw = board.offsetWidth || MX_W, bh = board.offsetHeight || MX_H;
  const cx = bw / 2, cy = bh / 2;

  /* 连线层铺在最底：放五芒星描线（faint 框常显，长按时描出亮线） */
  const links = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  links.setAttribute("class", "mx-links");
  links.setAttribute("width", bw); links.setAttribute("height", bh);
  board.appendChild(links);

  /* 五感锚点 + 归位线索 chip（同感官按序向下叠；连线终点用解析坐标，不量 DOM） */
  const verts = {};   /* 五感星形顶点（board 坐标）：证据落在哪，五芒星就连到哪 */
  Object.keys(SENSES).forEach(sense => {
    const a = MX_ANCHORS[sense];
    const ax = a[0] * bw, ay = a[1] * bh;
    const anchor = document.createElement("div");
    anchor.className = "mx-anchor";
    anchor.style.left = ax + "px"; anchor.style.top = ay + "px";
    anchor.title = SENSES[sense];   /* 无文字标签：感官名只进 tooltip，不进排布 */
    const list = G.matrix[sense];
    let child = null;
    if (list.length){
      list.forEach((cid, i) => {
        const chip = document.createElement("div");
        let cls = "mx-chip node ent-node ent-clue";
        if (G.captured.has(cid)) cls += " got";
        chip.className = cls;
        chip.title = "拖出桌布 = 取回画布；拖到线索册 = 收进册子";   /* 回头路两条：回画布 / 回册子 */
        /* 归位 = 线索搬到了桌布上（画布上那份已经收走），所以这里说「已归位」，
           与画布上那枚「线索 · 已捕获」分开说 —— 两者是两个地方的两个状态 */
        const sub = G.captured.has(cid) ? "线索 · 已归位" : "线索";
        chip.innerHTML = "<div class='n-title'>" + esc((CLUES[cid] || {}).label || cid) + "</div>" +
                        "<div class='n-sub'>" + esc(sub) + "</div>";
        anchor.appendChild(chip);
        if (i === 0) child = chip;   /* 顶点取该感官第一条线索的中心 */
        makeMatrixNodeDraggable(chip, cid, sense);
      });
    }
    board.appendChild(anchor);
    /* 记录该感官的星形顶点：用卡片实测中心；stub 量不出时退回解析坐标（锚点+27） */
    const cr = child ? child.getBoundingClientRect() : null;
    const br = board.getBoundingClientRect();
    verts[sense] = (cr && cr.width) ? { x: cr.left + cr.width / 2 - br.left, y: cr.top + cr.height / 2 - br.top }
                                    : { x: ax, y: ay + 27 };
  });

  /* 星阵 = 外圆 + 五芒星，合成一条路径：常显虚线框与长按描线都包含它。
     蓄力时按路径顺序描绘——先描外圆（划定法阵），再描五芒星（建立逻辑归因）。
     外圆半径 = 五感顶点外接圆(≈175) + 20 缓冲；圆心 = 桌布中心 = 五芒星形心。 */
  const STAR_ORDER = ["vision","touch","taste","hearing","smell"];   /* 顺时针 视觉→触觉→味觉→听觉→嗅觉 */
  const pts = STAR_ORDER.map(s => verts[s]).filter(Boolean);
  if (pts.length === 5){
    let d = "M" + (cx - MX_CIRCLE_R) + " " + cy +
            " a" + MX_CIRCLE_R + "," + MX_CIRCLE_R + " 0 1,1 " + (MX_CIRCLE_R * 2) + ",0" +
            " a" + MX_CIRCLE_R + "," + MX_CIRCLE_R + " 0 1,1 " + (-MX_CIRCLE_R * 2) + ",0";
    d += " M" + pts[0].x + " " + pts[0].y;
    for (let i = 1; i < pts.length; i++) d += " L" + pts[i].x + " " + pts[i].y;
    d += " Z";
    const frame = document.createElementNS("http://www.w3.org/2000/svg", "path");
    frame.setAttribute("class", "mx-star-frame");
    frame.setAttribute("d", d);
    links.appendChild(frame);
    const draw = document.createElementNS("http://www.w3.org/2000/svg", "path");
    draw.setAttribute("class", "mx-star-draw");
    draw.setAttribute("d", d);
    draw.setAttribute("pathLength", "100");   /* 归一化长度 → dasharray:100 即整条线 */
    links.appendChild(draw);
  }

  /* 中央执行者：长按激活归因 */
  const exec = document.createElement("div");
  exec.className = "mx-exec";
  exec.title = "长按 2.5 秒激活归因";
  const av = document.createElement("div"); av.className = "mx-avatar";
  const img = document.createElement("img");
  img.src = EXECUTOR_AVATAR;
  img.alt = "执行者"; img.draggable = false;
  av.appendChild(img);
  exec.appendChild(av);   /* 执行者只留头像：头像即五芒星中枢，标签/提示已移除 */
  exec.addEventListener("pointerdown", riteStart);
  board.appendChild(exec);

  /* 「确认捕获」之后的余韵：执行者头顶挂一枚没种下的种子（对话框）。
     显隐只看 G.garden.seed —— 窗重开 / 每次重绘都从这里重建，不是一次性 DOM：
     种子没被拖进花园之前，关掉推理窗再打开，对话框还在。 */
  if (G.garden && G.garden.seed) exec.appendChild(buildSeedPop());
}

/* ============ 种子对话框（「确认捕获」落定 → 花园的前奏） ============
   位置与心碎表情同款（.mx-exec 上方），但不自动消失：种子拖进花园才收走。
   气泡里**只有一张种子图**，没有任何文字 —— 要说的都由画面说了。
   **拖拽把手 = 种子图本身**（用户口径）：按在图上才算搬运，气泡白卡的空白处拖不动。
   指针捕获与监听必须下在**同一个元素**（下面 handle）—— 捕获会把 pointermove / up
   重定向到捕获元素，挂在别人身上就收不到移动。落进花园窗 / 花园图标 = 下种
   （gardenPlant，16-cases.js），落在别处 = 弹回原位。 */
function buildSeedPop(){
  const pop = document.createElement("div");
  pop.className = "mx-seedpop";
  pop.title = "拖动种子，种进花园";
  const im = document.createElement("img");
  im.src = GARDEN_IMG.seed;
  im.alt = "花魄的种子"; im.draggable = false;
  im.title = "拖到花园里种下";
  pop.appendChild(im);
  makeSeedDraggable(pop, im);
  return pop;
}
function makeSeedDraggable(pop, handle){
  const h = handle || pop;                 /* 把手缺省退整块（老调用点兼容） */
  let dragging = false, moved = false, sx = 0, sy = 0, mirror = null, offx = 0, offy = 0, sr = null;
  /* 被 render() 打断时的收尾（见 07-render.js 的登记表）：摘镜像、把原气泡放回来 */
  const abortSeedDrag = () => {
    if (!dragging) return;
    dragging = false;
    pop.classList.remove("dragging");
    if (mirror){ mirror.remove(); mirror = null; }
    pop.style.visibility = "";
  };
  h.addEventListener("pointerdown", e => {
    if (e.button !== 0) return;
    dragging = true; moved = false; sx = e.clientX; sy = e.clientY;
    sr = desktopEl.getBoundingClientRect();
    registerDrag(abortSeedDrag);
    try { h.setPointerCapture(e.pointerId); } catch(_){}
    e.stopPropagation();
  });
  h.addEventListener("pointermove", e => {
    if (!dragging) return;
    const dx = e.clientX - sx, dy = e.clientY - sy;
    if (!moved && Math.abs(dx) + Math.abs(dy) < 5) return;
    moved = true;
    pop.classList.add("dragging");
    if (!mirror){
      const layer = document.getElementById("drag-layer");
      /* 跟手的是**种子图本身**（用户口径）——镜像只克隆那张图，不是整块白卡气泡 */
      const r = h.getBoundingClientRect();
      offx = e.clientX - r.left; offy = e.clientY - r.top;
      mirror = h.cloneNode(true);
      mirror.className = "mx-seed-mirror drag-mirror";
      mirror.style.position = "absolute"; mirror.style.transform = "none";
      /* 尺寸取**布局**尺寸（offsetWidth），不取 rect：种子气泡带着 pop 缩放动画（scale .6→1），
         动画没走完就起拖时 rect 量到的是缩放后的值（实测 32 → 19）。 */
      mirror.style.width = (h.offsetWidth || 32) + "px";
      mirror.style.height = (h.offsetHeight || 32) + "px";
      mirror.style.left = (r.left - sr.left) + "px";
      mirror.style.top  = (r.top  - sr.top ) + "px";
      mirror.style.visibility = "hidden";
      layer.appendChild(mirror);
      pop.style.visibility = "hidden";     /* 原气泡（含白卡）整体隐去，画面上只剩跟手的种子 */
      void mirror.offsetWidth;             /* 强制布局，显示即正确位置 */
      mirror.style.visibility = "visible";
    }
    mirror.style.left = (e.clientX - offx - sr.left) + "px";
    mirror.style.top  = (e.clientY - offy - sr.top ) + "px";
  });
  const finish = e => {
    if (!dragging) return;
    dragging = false;
    unregisterDrag(abortSeedDrag);
    pop.classList.remove("dragging");
    if (mirror){ mirror.remove(); mirror = null; }
    pop.style.visibility = "";
    if (!moved) return;                    /* 纯点击：不动 */
    if (overGardenDrop(e.clientX, e.clientY)){ gardenPlant(e.clientX, e.clientY); return; }
    refreshInferWin();                     /* 没拖进花园：弹回原位（对话框照旧） */
  };
  h.addEventListener("pointerup", finish);
  h.addEventListener("pointercancel", () => { unregisterDrag(abortSeedDrag); abortSeedDrag(); });
}

/* 长按蓄力：pointerdown 起 2.5s 完成 → executeInference；pointerup / pointerleave 提前 = 中断复位。
   无头环境 setTimeout 返回 0 就立即完成（与 enterCase 换档的兜底同款）。 */
let riteTimer = null;
function riteEnd(commit){
  if (riteTimer){ clearTimeout(riteTimer); riteTimer = null; }
  if (inferWinEl){
    const ex = inferWinEl.querySelector(".mx-exec");
    if (ex){
      ex.classList.remove("charging");
      if (ex._riteOff){
        ex.removeEventListener("pointerup", ex._riteOff);
        ex.removeEventListener("pointerleave", ex._riteOff);
        ex._riteOff = null;
      }
    }
    const bd = inferWinEl.querySelector(".mx-board");
    if (bd) bd.classList.remove("charging");
  }
  if (commit) executeInference();
}
function riteStart(e){
  if (e && e.button !== 0) return;
  if (!inferWinEl || riteTimer) return;
  const ex = inferWinEl.querySelector(".mx-exec");
  if (!ex) return;
  ex.classList.add("charging");
  const bd = inferWinEl.querySelector(".mx-board");
  if (bd) bd.classList.add("charging");   /* 描星与头像震颤起；窗体不抖（窗口震动只属于真名结局） */
  const t = setTimeout(() => riteEnd(true), 2500);
  if (!t){ riteEnd(true); return; }
  riteTimer = t;
  const off = () => riteEnd(false);
  ex._riteOff = off;
  ex.addEventListener("pointerup", off);
  ex.addEventListener("pointerleave", off);
}
/* 归位 = 把这枚线索**从画布收进桌布**（与证物袋 / 线索册共用 stored 机制，storedIn === "MATRIX"）。
   桌布自己就是这份线索的清单 —— 归位后画布上不该再留一份：
   「拖上台」和「拖进袋 / 册」在玩家手里是同一个动作，落下之后节点也该同样消失。
   回头路只有一条：把桌布上的 chip 拖出去（boardTake）。 */
const MATRIX_STORE = "MATRIX";
function matrixItems(){ return Object.values(G.nodes).filter(n => n.stored && n.storedIn === MATRIX_STORE); }
function assignClue(clueKey, sense){
  const n = G.nodes[clueKey];
  if (!n || n.kind !== "clue") return false;
  const c = CLUES[n.id];
  if (!c || c.type !== sense){ toast("「" + esc(n.label) + "」的感官类型不是" + SENSES[sense], true); return false; }
  if (G.matrix[sense].indexOf(n.id) >= 0) return false;
  pushHistory();
  G.matrix[sense].push(n.id);
  n.stored = true; n.storedIn = MATRIX_STORE; n.pinned = false;
  /* 只重画、**不调 layout()**：收纳入袋 / 入册那两处会顺手跑 260 轮弹簧迭代，
     把画布上**别的**节点全推走（真机实测：18 个节点全动，最大 210px、平均 64px）——
     那正是「自动布局」按钮被删掉的那个毛病。归位一个线索不该顺手重排玩家的摆位。 */
  render(); refreshInferWin();
  return true;
}
/* 拖出桌布 = 取回画布。归位时线索已经离开画布，这里是唯一的回头路。
   落在哪儿就放回哪儿（松手那一点换算成世界坐标，卡片中心对着指针），镜头不抢，只亮一次「新」。
   案件窗关着时取不回来 —— 与 bagTake / ledgerTake 同一条门（取出是往画布上放东西的动作）。 */
function boardTake(cid, sense, cx, cy){
  const n = nodeByKey("clue", cid);
  if (!n) return false;
  if (!requireCase()){ refreshInferWin(); return false; }
  pushHistory();
  G.matrix[sense] = G.matrix[sense].filter(x => x !== cid);
  n.stored = false; n.storedIn = null; n.hidden = false; n.pinned = false; markFresh(n);
  if (cx != null && cy != null){
    /* 先换成世界坐标、**再**减去半张卡 —— 卡片尺寸是世界单位，不能在屏幕坐标里先减：
       镜头缩放 k≠1 时两者差一个 k 倍（k=0.35 时落点会偏出 120 多世界像素，实测被 verify 逮住） */
    const wpt = toWorld(cx, cy);
    n.x = wpt.x - (NODE_W.clue || 130) / 2; n.y = wpt.y - (NODE_H.clue || 46) / 2;
  }
  render(); refreshInferWin();
  return true;
}
/* 配方不匹配：头像上方弹心碎表情（1.4s 自动消失；连发时先撤旧的再弹，重置动画） */
function showExecEmote(){
  if (!inferWinEl) return;
  const ex = inferWinEl.querySelector(".mx-exec");
  if (!ex) return;
  const old = ex.querySelector(".mx-emote");
  if (old) old.remove();
  const em = document.createElement("div");
  em.className = "mx-emote";
  const im = document.createElement("img");
  im.src = EXEC_EMOTE_HEARTBROKEN;
  im.alt = "心碎"; im.draggable = false;
  em.appendChild(im);
  ex.appendChild(em);
  setTimeout(() => em.remove(), 1500);
}
function executeInference(){
  const inMatrix = new Set();
  Object.keys(G.matrix).forEach(s => G.matrix[s].forEach(id => inMatrix.add(id)));
  const hit = ENDINGS.find(e => {
    const r = e.recipe || [];
    return r.length === inMatrix.size && r.every(id => inMatrix.has(id));
  });
  if (hit){ refreshInferWin(); triggerEnding(hit); }
  else { showExecEmote(); log("推演失败：当前阵列不匹配任何结局配方", "warn"); }
}

/* ============ 结局演出（步进状态机：setTimeout 自动推进 / 点击跳过 / 钩子手动推进） ============ */
let endingState = null;
function triggerEnding(ending){
  G.endings.add(ending.id);
  /* 只有捕获「真名」（真结局）才点亮下一案的地址。
     种子**不在这里发**：它要等玩家在结局遮罩上亲手点下「确认捕获」才发（15-desktop.js 的
     遮罩点击分支）—— 演出还没谢幕就先掉奖励，等于把结局的余韵抢在观众离场前倒掉了。 */
  if (ending.isTrueCapture){ unlockNextCase(CASE_ID); }
  log("<b>结局达成：" + esc(ending.name) + "</b>", "cap");
  /* 真名结局：先让推演器整窗冲击震动一拍，再落下结局遮罩 */
  const shock = !!(ending.isTrueCapture && inferWinEl);
  if (shock){
    /* 拖过推演窗的手势会在窗口上留下内联 `animation:none`（makeFloatDraggable 防「pop 动画
       没走完就拖动会错位」那句），而内联样式优先于 .shock 的类动画 —— 只要玩家挪过窗口，
       真名震动就永远不会出现。加震之前先把这条内联清掉，并强制一次 reflow 让动画从 0 起跑。 */
    inferWinEl.style.animation = "";
    void inferWinEl.offsetWidth;
    inferWinEl.classList.add("shock");
    setTimeout(() => { if (inferWinEl) inferWinEl.classList.remove("shock"); }, 1000);
  }
  endingState = { ending, step: 0, stages: buildStages(ending) };
  const t = shock ? setTimeout(playEndingStage, 900) : 0;
  if (!t) playEndingStage();
}
function buildStages(e){
  const st = [];
  (e.lines || []).forEach(l => st.push({ html: esc(l.text), delay: l.delay || 1200 }));
  if (e.isTrueCapture && e.truename) st.push({ html: "<div class='truename'>真名已识别<br>『" + esc(e.truename) + "』</div>", delay: 2000 });
  /* 真名结局的大段「真名形成说明」不放进遮罩播 —— 改为开花后点花、用花园里的叙事框承载
     （16-cases.js 的 openGardenNarr）。其余结局的 message 仍是遮罩主内容，照旧显示。 */
  if (!e.isTrueCapture && e.message) st.push({ html: esc(e.message || ""), delay: 1600 });
  st.push({ html: "<div style='text-align:center'><span class='ebtn'>" + (e.isTrueCapture ? "确认捕获" : "收下这份记录") + "</span></div>", final: true });
  return st;
}
function playEndingStage(){
  const st = endingState; if (!st) return;
  const overlay = document.getElementById("ending-overlay");
  if (st.step >= st.stages.length){ closeEnding(); return; }
  const stage = st.stages[st.step];
  const eol = overlay.querySelector(".eol") || (function(){ const d = document.createElement("div"); d.className = "eol"; overlay.appendChild(d); return d; })();
  const div = document.createElement("div");
  div.innerHTML = stage.html;
  eol.appendChild(div);
  overlay.style.display = "block";
  st.step++;
  if (!stage.final) st.timer = setTimeout(playEndingStage, stage.delay);
}
function closeEnding(){
  const overlay = document.getElementById("ending-overlay");
  overlay.style.display = "none";
  overlay.innerHTML = "";
  endingState = null;
  updateCrumbs();
}

/* ============ 记忆放映卡 / 回忆小剧场（A-001 日期闪回） ============
   两种载体共用同一台状态机（memoryPlay + playMemoryLine + advanceMemory）：
     · 放映卡 showMemoryCard —— 展开日期节点时放，正文 +「——角色：台词」逐行；
     · 小剧场 showMemoryPlay —— 时间 × 地点 × 人物 凑齐时演，旁白 + 带头像的多人对话。
   行的形状统一成对象 {t:"narr"|"talk"|"say", text, who}；旧的纯字符串行也兜得住
   （memLineSpec 会在读的时候现归一到同一个形状）。 */
let memoryPlay = null;
function memLineSpec(raw){
  if (raw && typeof raw === "object")
    return { t: raw.t || "narr", text: String(raw.text == null ? "" : raw.text), who: raw.who || null };
  const s = String(raw == null ? "" : raw);
  return { t: s.startsWith("——") ? "talk" : "narr", text: s, who: null };
}
function showMemoryCard(n, s){
  closeNarr();
  const w = makeWindow("MEMORY // " + (s.title || n.id), closeNarr);
  const c = w.el;
  c.className = "narr-card memory syswin";
  c.title = "单击任意位置推进下一行，按住可拖动";
  makeFloatDraggable(c, true);                       /* 整卡可拖（与对话气泡一致），点/拖靠 _dragged 区分 */
  c.addEventListener("click", () => { if (!c._dragged) advanceMemory(); });
  world.appendChild(c);
  narrEl = c;
  const lines = narrText(s.content || s.desc || "").split("\n").map(t => t.trim()).filter(Boolean)
    .map(t => ({ t: "narr", text: t }));
  sceneTags(n.id).forEach(t => {
    if (t.kind !== "char") return;
    const ch = CHARS[t.id];
    const st = ch && (ch.sceneTalks || {})[n.id];
    (st || []).forEach(l => lines.push({ t: "talk", text: "——" + (ch.name || t.id) + "：" + plain(l.text || "") }));
  });
  memoryPlay = { el: c, body: w.body, lines: lines, idx: 0, typing: false, cur: null, curText: "" };
  playMemoryLine();
  /* 锚定必须放在第一行落下去之后：空窗口量到的高度只有标题栏那点，算出来的 top 偏下，
     第一行一出现卡片就压住节点（`anchorAboveOrBelow` 承诺的是"不盖节点"）。 */
  anchorAboveOrBelow(c, n, 14);
}

/* ---- 回忆小剧场：时间 × 地点 × 人物 三者凑齐后的演出（05-combine.js 里接线） ---- */
/* 匹配器：when（时间节点 id）× who（人物 id）× where（绑在时间节点上的地点 id）三者全中才算命中 */
function lookupMemory(when, who, where){
  if (!when || !who || !where) return null;
  return MEMORIES.find(m => m.when === when && m.who === who && m.where === where) || null;
}
/* 脚本 → 行对象。文本走 plain()：数据里若写了 [clue:…] / [char:…] 这类标签，这里就地换成可读名字。
   注意**不在这里捕获线索** —— 回忆是"重看"，不该变成第二条拿线索的路（展开日期节点放的放映卡同样是只看不拿）。 */
function memLinesOf(entry){
  return (entry && entry.script || [])
    .map(x => ({ t: x.t === "say" ? "say" : "narr", who: x.t === "say" ? x.who : null, text: plain(x.text || "") }))
    .filter(x => x.text);
}
function showMemoryPlay(entry, n){
  if (!entry || !n) return false;
  closeNarr();                              /* 单例：开演前先收掉放映卡 / 上一场 */
  const w = makeWindow("MEMORY // " + (entry.title || entry.id), closeNarr);
  const c = w.el;
  c.className = "narr-card memory mem-play syswin";   /* memory 血统 + mem-play 只加剧场的那几处排版 */
  c.title = "单击任意位置推进下一行，按住可拖动";
  makeFloatDraggable(c, true);              /* 整框可拖（与放映卡同一套），点/拖靠 _dragged 区分 */
  c.addEventListener("click", () => { if (!c._dragged) advanceMemory(); });
  world.appendChild(c);
  narrEl = c;
  memoryPlay = { el: c, body: w.body, lines: memLinesOf(entry), idx: 0, typing: false, cur: null, curText: "", entry: entry.id };
  playMemoryLine();
  anchorAboveOrBelow(c, n, 14);   /* 同放映卡：等第一行落下去再锚，空窗口的高度算不准 */
  return true;
}
function playMemoryLine(){
  const mp = memoryPlay;
  if (!mp || !narrEl || mp.el !== narrEl){ memoryPlay = null; return; }
  if (mp.idx >= mp.lines.length){ memoryPlay = null; return; }
  const spec = memLineSpec(mp.lines[mp.idx]);
  let target;
  if (spec.t === "say"){
    /* 带头像的一行：左头像列（有美术稿用图，没有退首字方块 —— 与名册 / 对话窗同一退路）+ 右名字与台词。
       **头像不加 .tec-avatar 类**：那个类在窗口拖动排除表里，挂上去这一行就没法拖着走了
       （剧场整框该能拖，与放映卡一致）；带自己的点击处理器才需要进排除表，这里没有。 */
    const ch = CHARS[spec.who] || {};
    const nm = ch.name || spec.who || "";
    const row = document.createElement("div");
    row.className = "mem-say";
    const av = document.createElement("div");
    av.className = "mp-av";
    const art = rosterAvatar(spec.who);
    if (art){
      const im = document.createElement("img");
      im.src = art; im.alt = nm; im.draggable = false;
      av.appendChild(im);
    } else {
      const ini = document.createElement("span");
      ini.className = "mp-ini"; ini.textContent = nm.slice(0, 1);
      av.appendChild(ini);
    }
    const main = document.createElement("div");
    main.className = "mp-say-main";
    const nmEl = document.createElement("div");
    nmEl.className = "mp-name"; nmEl.textContent = nm;
    target = document.createElement("div");
    target.className = "mp-text";
    main.appendChild(nmEl); main.appendChild(target);
    row.appendChild(av); row.appendChild(main);
    mp.body.appendChild(row);
  } else {
    target = document.createElement("div");
    target.className = "mem-line" + (spec.t === "talk" ? " talk" : "");
    mp.body.appendChild(target);
  }
  mp.idx++;
  /* 每行也走打字机；打完就停在那儿等玩家点 —— 不再 700ms 自动换行（改成点击推进） */
  mp.typing = true; mp.cur = target; mp.curText = spec.text;
  typeInto(target, spec.text, { done: () => { mp.typing = false; } });
}
/* 单次推进：本行还在打字 -> 先补全本句；已打完 -> 换下一行（视觉小说通行做法） */
function advanceMemory(){
  const mp = memoryPlay;
  if (!mp) return false;
  if (mp.typing){
    cancelType(mp.cur);
    if (mp.cur) mp.cur.textContent = mp.curText;
    mp.typing = false;
    return true;
  }
  playMemoryLine();
  return true;
}
