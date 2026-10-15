/* ============ 节点交互 ============ */
function attachInteractions(el, n){
  let dragging = false, moved = false, sx = 0, sy = 0, ox = 0, oy = 0, ghost = null, overEl = null, mirror = null;

  /* 摘掉本次拖动留下的一切痕迹（镜像 / 幽灵线 / 各类落点高亮） */
  const teardownDrag = () => {
    if (mirror){ mirror.remove(); mirror = null; }
    el.classList.remove("dragging");
    el.style.visibility = "";
    if (ghost){ ghost.remove(); ghost = null; }
    if (overEl){ if (overEl.classList) overEl.classList.remove("over"); overEl = null; }
    nodeDropTargets().forEach(id => {
      const ic = dropTargetEl(id);
      if (ic && ic.classList) ic.classList.remove("over");
    });
    const mxBd = inferWinEl ? inferWinEl.querySelector(".mx-board") : null;
    if (mxBd && mxBd.classList) mxBd.classList.remove("over");
  };
  /* 被 render() 打断时的收尾：把当前位移写回 n.x/n.y（夹回界内），别让节点跳回拖动前的起点。
     只写位置、**不做落点判定** —— 此刻落点（组合对象 / 收纳窗）可能已经被重建，
     按旧引用判了也是错的；玩家的意图是「停在这里」，落点动作留给下一次拖动。 */
  const abortDrag = () => {
    if (!dragging) return;
    dragging = false;
    const x = parseFloat(el.style.left), y = parseFloat(el.style.top);
    teardownDrag();
    if (moved){
      n.x = Math.max(60, Math.min(2000 - 220, isFinite(x) ? x : n.x));
      n.y = Math.max(50, Math.min(1300 - 120, isFinite(y) ? y : n.y));
    }
  };

  el.addEventListener("pointerdown", e => {
    if (e.button !== 0) return;
    cancelViewAnim();   /* 抓住节点即接管镜头：正在跑的自动聚焦立刻停住（"拖动即可打断"） */
    if (mirror){ mirror.remove(); mirror = null; }   /* 兜底：清掉可能残留的镜像 */
    if (el.__springTimer){ clearTimeout(el.__springTimer); el.__springTimer = null; el.style.transition = ""; }   /* 打断正在进行的弹回动画 */
    el.style.visibility = "";
    dragging = true; moved = false;
    sx = e.clientX; sy = e.clientY;
    ox = parseFloat(el.style.left) || 0;
    oy = parseFloat(el.style.top)  || 0;
    registerDrag(abortDrag);   /* 拖到一半若被 render() 打断，由它收尾（见 07-render.js 的登记表） */
    try { el.setPointerCapture(e.pointerId); } catch(_){}
    e.stopPropagation();
  });

  el.addEventListener("pointermove", e => {
    if (!dragging) return;
    const dx = e.clientX - sx, dy = e.clientY - sy;
    if (!moved && Math.abs(dx) + Math.abs(dy) < 5) return;
    moved = true;
    el.classList.add("dragging");

    /* 节点跟手移动 */
    el.style.left = (ox + dx / view.k) + "px";
    el.style.top  = (oy + dy / view.k) + "px";

    /* 顶层镜像：让被拖的节点浮在窗口/图标之上 */
    if (!mirror) mirror = makeDragMirror(el);
    syncDragMirror(mirror, el);

    if (!ghost){
      ghost = document.createElementNS("http://www.w3.org/2000/svg", "path");
      ghost.setAttribute("stroke", "#2b2b26");
      ghost.setAttribute("stroke-width", 2);
      ghost.setAttribute("stroke-dasharray", "6 5");
      ghost.setAttribute("fill", "none");
      ghost.setAttribute("opacity", .85);
      svg.appendChild(ghost);
    }
    const A = center(el);
    const P = toWorld(e.clientX, e.clientY);
    ghost.setAttribute("d", "M" + A.x + " " + A.y + " L" + P.x + " " + P.y);
    paintEdges();

    /* 命中测试不用 elementFromPoint，免得被正在拖的节点自己挡住 */
    const hit = hitTest(e.clientX, e.clientY, el);
    if (hit !== overEl){
      if (overEl) overEl.classList.remove("over");
      overEl = hit;
      if (overEl) overEl.classList.add("over");
    }

    /* 桌面图标命中高亮（固定优先级 bag > tec > infer > goto） */
    nodeDropTargets().forEach(id => {
      const ic = dropTargetEl(id);
      if (!ic) return;
      const r = ic.getBoundingClientRect();
      ic.classList.toggle("over",
        e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom);
    });
    /* 阵列桌布命中高亮（窗口开着时整块桌布都是线索落点） */
    const mxBd = inferWinEl ? inferWinEl.querySelector(".mx-board") : null;
    if (mxBd){
      const r = mxBd.getBoundingClientRect();
      mxBd.classList.toggle("over", !!(n.kind === "clue" &&
        e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom));
    }
  });

  /* 拖动被系统中断（如指针被抢占）时也要收尾，否则镜像残留 / 节点被永久隐藏 */
  el.addEventListener("pointercancel", () => {
    if (!dragging) return;
    dragging = false;
    unregisterDrag(abortDrag);
    teardownDrag();
  });

  el.addEventListener("pointerup", e => {
    if (!dragging) return;
    dragging = false;
    unregisterDrag(abortDrag);
    const target = overEl;      /* teardownDrag 会清掉 overEl，先留住松手命中的那一个 */
    teardownDrag();

    /* 桌面图标命中判定（固定优先级 bag > clue > tec > infer > goto；任何路径清掉 over 高亮） */
    let iconHit = null;
    nodeDropTargets().forEach(id => {
      const ic = dropTargetEl(id);
      if (!ic) return;
      const r = ic.getBoundingClientRect();
      const inside = moved && e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom;
      if (inside && !iconHit) iconHit = id;
      ic.classList.remove("over");
    });

    if (!moved){ clearFresh(n); selectNode(n.key); return; }   /* 点一下 = 不再是「新」 */

    if (iconHit){
      /* 松手落在桌面图标上 → 对应功能，自己弹回原位 */
      springBack(el, ox, oy);
      if (iconHit === "bag-dock" || iconHit === "bag-win") bagStore(n.key);
      else if (iconHit === "clue-icon" || iconHit === "clue-win") ledgerStore(n.key);
      else if (iconHit === "tec-dock" || iconHit === "tec-avatar" || iconHit === "tec-chip") tecAnalyze(n.key);
      else if (iconHit === "infer-icon"){
        if (n.kind === "clue") assignClue(n.key, (CLUES[n.id] || {}).type);
        else toast("只有线索能进推演器", true);
      } else if (iconHit === "goto-icon"){
        if (n.kind === "loc") gotoScene(n.id);   /* 档案里列的是场景；容器物品（书桌）不在此列 */
        else toast("只有场景能进档案", true);
      }
      return;
    }

    /* 松手落在阵列桌布上 → 线索归位（归入它自己的感官），自己弹回原位 */
    const mxBdUp = inferWinEl ? inferWinEl.querySelector(".mx-board") : null;
    if (mxBdUp){
      mxBdUp.classList.remove("over");
      const r = mxBdUp.getBoundingClientRect();
      if (e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom){
        springBack(el, ox, oy);
        if (n.kind === "clue") assignClue(n.key, (CLUES[n.id] || {}).type);
        else toast("只有线索能上桌布", true);
        return;
      }
    }

    if (target && target.dataset.key){
      /* 松手落在别的节点上 → 组合，自己被弹回原位 */
      const tn = G.nodes[target.dataset.key];
      springBack(el, ox, oy);
      /* 折叠的容器节点（场景 / 书桌 / 垃圾桶）：既不收纳也不组合。原来这里会把节点
         「放回现场」（storeNode），但那与证物袋 / 线索册重叠（还没有清单、只能整场展开才能取回），
         入口已移除。组合也不放行：折叠后里面的东西看不见，隔空命中的结果没有着力点。 */
      if (tn && isContainerNode(tn) && G.collapsed.has(tn.id)){
        toast("<b>" + esc(tn.label) + "</b><br>" + (tn.kind === "loc" ? "场景已折叠" : "已折叠") +
              "：先双击展开，或把节点拖到证物袋", true);
        return;
      }
      attemptCombo(n.key, target.dataset.key);
      return;
    }
    /* 松手落在空白处 → 就停在这里。**不再自动钉住**（钉住只由右键控制，见 togglePin）：
       这里只改位置，所以下一次自动布局仍可能把它重排走 —— 想留住这一摆位就右键钉住它。 */
    const rawX = parseFloat(el.style.left) || n.x, rawY = parseFloat(el.style.top) || n.y;
    n.x = Math.max(60, Math.min(2000 - 220, rawX));
    n.y = Math.max(50, Math.min(1300 - 120, rawY));
    if (n.x !== rawX || n.y !== rawY){
      /* 拖到画布「框边」→ 越界被夹回：必须用 springBack 让节点与连线同帧走完，
         不能只写一次 left/top（CSS 过渡期间节点在滑、连线已跳到终点 → 看着就是"断线"）。 */
      springBack(el, n.x, n.y);
    } else {
      el.style.left = n.x + "px";
      el.style.top  = n.y + "px";
      paintEdges();
    }
    updateCrumbs();
  });

  el.addEventListener("dblclick", () => {
    clearFresh(n);          /* 双击也算「点过」：角标立刻摘掉 */
    if (isContainerNode(n)){   /* 容器一律双击展开 / 折叠（书桌、垃圾桶也一样） */
      if (G.collapsed.has(n.id) || G.explored.has(n.id)){ toggleCollapse(n.id); selectNode(n.key); return; }
      revealScene(n.id); selectNode(n.key); return;
    }
    runPrimary(n);
  });

  /* 右键 = 钉住 / 取消钉住（不弹提示：状态由节点左上角的「已固定」角标表达）。
     这是**唯一**的钉住入口：拖动只改位置，不再顺手钉住（旧版拖到空白即锁定，容易被当成 bug）。 */
  el.addEventListener("contextmenu", e => {
    e.preventDefault();
    e.stopPropagation();
    togglePin(n);
  });
}
/* 钉住 = 位置锁定（自动布局不再挪它）+ 折叠时不被收回。**只能由右键进入**（拖动不再自动钉住）。
   两个后果都不需要玩家记，看见角标就够 */
function togglePin(n){
  if (!requireCase()) return;
  pushHistory();
  n.pinned = !n.pinned;
  render();
}

/* 屏幕坐标命中测试：取「离光标最近」的那个节点，避免多节点重叠时选错 */
function hitTest(cx, cy, excludeEl){
  let best = null, bestD = Infinity;
  Object.values(G.nodes).forEach(n => {
    if (!n.el || n.el === excludeEl) return;
    const r = n.el.getBoundingClientRect();
    if (cx < r.left - 10 || cx > r.right + 10 || cy < r.top - 10 || cy > r.bottom + 10) return;
    const d = Math.hypot(cx - (r.left + r.right) / 2, cy - (r.top + r.bottom) / 2);
    if (d < bestD){ bestD = d; best = n.el; }
  });
  return best;
}

function toWorld(cx, cy){
  const r = stage.getBoundingClientRect();
  return { x: (cx - r.left - view.x) / view.k, y: (cy - r.top - view.y) / view.k };
}
function applyView(){
  world.style.transform = "translate(" + view.x + "px," + view.y + "px) scale(" + view.k + ")";
}

/* ============ 镜头：自动平移 ============
   只平移、不缩放（不替玩家改缩放级别）；缓动期间玩家一拖节点 / 一平移 / 一滚轮即打断。 */
let viewAnim = null;
/* 最近一次自动聚焦的「决定」（调试 + 无头验证用：镜头位移在无头环境里量不到，只能量决定） */
let lastFocus = null;
const __now = () => (typeof performance !== "undefined" ? performance.now() : Date.now());
/* 用 setTimeout 逐帧推进（不用 rAF）：无头 stub 里 setTimeout 是 no-op，既不动画也不会递归爆炸；
   浏览器里 16ms 一帧足以平滑 240ms 的位移。 */
const __schedule = cb => setTimeout(() => cb(__now()), 16);
function cancelViewAnim(){ if (viewAnim != null){ try{ clearTimeout(viewAnim); }catch(_){} viewAnim = null; } }
function animateViewTo(tx, ty, ms){
  cancelViewAnim();
  const sx = view.x, sy = view.y, t0 = __now();
  ms = ms || 240;
  const ease = t => t < .5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
  const step = () => {
    const t = Math.min(1, (__now() - t0) / ms);
    view.x = sx + (tx - sx) * ease(t);
    view.y = sy + (ty - sy) * ease(t);
    applyView();
    if (t < 1) viewAnim = __schedule(step); else viewAnim = null;
  };
  viewAnim = __schedule(step);
}
function nodeBox(n){
  return { x0: n.x, y0: n.y, x1: n.x + (NODE_W[n.kind] || 130), y1: n.y + (NODE_H[n.kind] || 46) };
}
/* 把一组节点整体平移到视野中央（只平移，不改 view.k）。 */
function focusOn(keys, ms){
  const list = (keys || []).map(k => G.nodes[k]).filter(n => n && !n.hidden && !n.stored);
  if (tgReveal && !tgReveal.checked){ lastFocus = { on:false, why:"toggle-off", keys:[] }; return false; }
  if (!list.length){ lastFocus = { on:false, why:"nothing-visible", keys:[] }; return false; }
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  list.forEach(n => {
    const b = nodeBox(n);
    x0 = Math.min(x0, b.x0); y0 = Math.min(y0, b.y0);
    x1 = Math.max(x1, b.x1); y1 = Math.max(y1, b.y1);
  });
  const names = [];
  list.forEach(n => { if (names.indexOf(n.key) < 0) names.push(n.key); });   /* 去重：调用方给的集合可能有交集 */
  const r = stage.getBoundingClientRect();
  if (!r || !r.width || !r.height){                  /* 无头/隐藏环境：量不到视口，不动镜头 */
    lastFocus = { on:false, why:"no-viewport", keys:names };
    return false;
  }
  const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
  const tx = r.width / 2 - cx * view.k, ty = r.height / 2 - cy * view.k;
  lastFocus = { on:true, why:"centered", keys:names, cx:cx, cy:cy, tx:tx, ty:ty };
  animateViewTo(tx, ty, ms || 260);
  return true;
}

/* ---- 新节点产出后的自动聚焦 ----
   「哪条路径长了新节点，它就该被看到」——把这个规则收成一处，所有产出路径共用同一套收尾。
   谁算「新」？ensureNode 新建的节点都带 n.fresh = true，而 render() 会把它擦掉，
   所以取"新节点"必须抢在 render() 之前——settle() 内部已经按这个顺序摆好了。

   为什么不沿用「已在视野内就不动镜头」的做法：缩到最小时（适应窗口 k≈0.42）整张图都在
   视野内，那个短路会让聚焦永不触发，等于没做。聚焦的意思是「看这里」，不是「勉强可见」。

   两个收尾动作按"这次要不要重排图"来选：
     settle()           —— 图结构变了（长 / 删了节点）：重排 → 渲染 → 聚焦；无新节点则只重排
     focusFresh(news)   —— 图没重排（开关灯 / 纯重绘）：只把已有结论送去聚焦
   镜头只认「新节点」这一个集合：锚点（谁产出了它）不参与框选，理由见 focusFresh 的注释。 */
function freshKeys(){
  return Object.keys(G.nodes).filter(k => {
    const n = G.nodes[k];
    return n && n.fresh && !n.hidden && !n.stored;
  });
}
/* 聚焦到「本次新长出来的节点」，把它们整体带到视野中央。
   为什么只框新节点、不把"产出它的那个锚点"也框进来：合成会消耗参与者，还活着的那个
   锚点可能在几百像素之外（实测手电筒 ↔ 尸体相距 264~763px），一起框等于把新节点推到
   舞台角落（实测最坏偏离中心 285px）——看着就是"没聚焦"。锚点本身就在玩家眼皮底下，
   不需要镜头带过去；新节点才是要找的那个。 */
function focusFresh(news){
  const live = (news || []).filter(k => { const n = G.nodes[k]; return n && !n.hidden && !n.stored; });
  if (!live.length){ lastFocus = { on:false, why:"no-new-node", keys:[] }; return false; }
  return focusOn(live);
}
/* 标准收尾：重排 → 渲染 → 把新节点带进视野。没有新节点（纯消耗 / 纯提示）时退回原来的
   「重排 + 渲染」，镜头一动不动。顶栏「新节点自动居中」关掉 → focusOn 直接返回 false。
   返回本次新节点的 key 列表，供调用方决定"该选中谁"。 */
function settle(){
  const news = freshKeys();     /* 必须抢在 render() 清掉 fresh 之前读 */
  layout();
  render();
  focusFresh(news);
  return news;
}
/* 收尾后选中"该看的东西"：原目标若在这一步被消耗掉了（合成常吃掉参与者），
   就改选这次新长出来的节点 —— 否则详情窗会弹出「节点已不存在」。
   返回实际选中的 key（无可选则 null）。 */
function settleSelect(news, preferKey){
  const keep = G.nodes[preferKey] ? preferKey : ((news || []).find(k => G.nodes[k]) || null);
  if (keep) selectNode(keep);
  return keep;
}

/* 双击物品 / 线索的主行为 */
function runPrimary(n){
  if (n.kind === "clue"){
    if (G.captured.has(n.id)){ log("线索「" + esc(n.label) + "」已经捕获过了", "warn"); return; }
    pushHistory(); G.captured.add(n.id);
    log("已捕获线索「" + esc(n.label) + "」", "cap");
    render(); selectNode(n.key);
    return;
  }
  if (n.kind === "char"){
    const ch = CHARS[n.id] || {};
    if (!charTalkQueue(n).length){ toast("<b>" + esc(ch.name || n.id) + "</b><br>（暂无对话文本）"); return; }
    showCharLine(n);            /* 双击节点 = 说下一句；点气泡 = 同一件事 */
    return;
  }
  /* 物品：有命令就跑第一条；无命令的没有主动作，双击 = 选中（描述统一在详情窗里读） */
  const it = ITEMS[n.id] || {};
  const cmds = it.commands || [];
  if (!cmds.length){ selectNode(n.key); return; }
  runCommand(n, cmds[0]);
}
