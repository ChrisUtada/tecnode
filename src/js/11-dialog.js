/* ============ 角色对话队列 + 锚定气泡 ============ */
function charTalkQueue(n){
  const ch = CHARS[n.id] || {};
  const norm = arr => (arr || []).map(o => typeof o === "string" ? o : (o && o.text) || "").filter(Boolean);
  const base = norm(ch.talkQueue);
  const scene = norm((ch.sceneTalks || {})[n.homeScene]);
  return base.concat(scene);
}
let bubbleEl = null;
function closeBubble(){
  if (bubbleEl){
    const bd = bubbleEl.querySelector && bubbleEl.querySelector(".syswin-body");
    if (bd) cancelType(bd);
    bubbleEl.remove(); bubbleEl = null;
  }
}
/* 气泡：opts.adv 传了才支持「点框内任意位置推进」（捕获结果那种一次性提示不带推进）。
   拖动仍是整框可拖，靠 _dragged 区分点/拖。 */
function showBubble(n, titleText, text, opts){
  closeBubble();
  const w = makeWindow(titleText, closeBubble);
  const b = w.el;
  b.className = "bubble syswin";
  const adv = (opts && opts.adv) || null;
  w.body.textContent = text;                 /* 先放全文 → 按整框实测高度定位 */
  makeFloatDraggable(b, true);
  world.appendChild(b);
  const bubTop = clampFloatY(n.y - b.offsetHeight - 12, b.offsetHeight);
  b.style.top = bubTop + "px";
  b.style.left = avoidHint(clampFloatX(n.x + NODE_W[n.kind] / 2 - b.offsetWidth / 2, b.offsetWidth), bubTop) + "px";
  if (adv){
    b.title = "单击任意位置继续，按住可拖动";
    b._typing = true;
    b.addEventListener("click", () => {
      if (b._dragged) return;                       /* 刚拖过 -> 那一下不算点击 */
      if (b._typing){                               /* 先补全本句，再点才推进 */
        cancelType(w.body); w.body.textContent = text; b._typing = false;
        return;
      }
      adv();
    });
    w.body.style.minHeight = (w.body.offsetHeight || 0) + "px";   /* 预占高度，打字时框不跳 */
    typeInto(w.body, text, { done: () => { b._typing = false; } });
  }
  bubbleEl = b;
}
/* 对话专用的线索入口：**台词本身不进案卷**（气泡与 TEC 窗里逐字都在），
   只把「这一句给出了线索」这个结果留档 —— 否则玩家回头查不到线索到手的时刻。
   对话是本案唯一「说了话才拿到线索」的通道：陆珩松 7月4日 那句带 [clue:CLUES_zhpt]，
   朱穗密室那句带 [clue:CLUES_qsan]，都不能因为不记台词而连线索一起丢。 */
function talkClues(text, who){
  const before = new Set(G.captured);
  gotClues(text);
  const fresh = [...G.captured].filter(id => !before.has(id));
  if (fresh.length)
    log("「" + esc(who) + "」的话里提到了线索：" + esc(fresh.map(id => (CLUES[id] && CLUES[id].label) || id).join("、")), "cap");
}
/* 角色说下一句：双击节点 / 点名册行 / 点对话窗 共用这一条路径。
   呈现统一按 TEC 对话窗的布局（用户定稿）：头像列 + 文字历史逐条追加，不再用锚定气泡；
   但**落位仍按旧气泡的规矩**（用户定稿）：窗体锚定在人物节点上方（挂 #world、JS 写内联
   top/left），上方放不下退到下方 —— TEC 自己的助手窗才留在桌面右下角。
   台词不循环：队列说完（prog >= queue.length）就停止推进 —— 点了也不再有新句。 */
let dlgWinEl = null;                 /* 当前对话窗（单例：换角色 = 关旧开新；同角色 = 追加） */
function closeDlgWin(){
  if (dlgWinEl){ dlgWinEl.remove(); dlgWinEl = null; }
}
function openDlgWin(n, ch, lineText){
  const name = ch.name || n.id;
  const sameChar = dlgWinEl && dlgWinEl._charKey === n.key;
  if (!sameChar) closeDlgWin();
  if (!dlgWinEl){
    const w = makeWindow("DIALOG // " + name, closeDlgWin);
    const b = w.el;
    /* 复用 TEC 对话窗的布局语言：CSS 用 .tec-win,.dlg-win 并列选择器（窗本体不挂 tec-win，
       否则 verify 的 tecWinNode() 会把对话窗误认成 TEC 窗） */
    b.className = "dlg-win syswin";
    const body = document.createElement("div");
    body.className = "tec-body";
    const avCol = document.createElement("div");
    avCol.className = "tec-avatar-col";
    const av = document.createElement("div");
    av.className = "tec-avatar";
    const art = rosterAvatar(n.id);
    if (art){
      const im = document.createElement("img");
      im.src = art; im.alt = name; im.draggable = false;
      av.appendChild(im);
    } else {
      const ini = document.createElement("span");
      ini.className = "dlg-ini"; ini.textContent = name.slice(0, 1);
      av.appendChild(ini);
    }
    const avLabel = document.createElement("div");
    avLabel.className = "tec-avatar-label"; avLabel.textContent = name;
    avCol.appendChild(av); avCol.appendChild(avLabel);
    const main = document.createElement("div");
    main.className = "tec-main";
    const lines = document.createElement("div");
    lines.className = "tec-lines dlg-lines";
    main.appendChild(lines);
    const hint = document.createElement("div");
    hint.className = "tec-hint";
    hint.textContent = "点框内任意位置继续对话";
    main.appendChild(hint);
    body.appendChild(avCol); body.appendChild(main);
    w.body.appendChild(body);
    /* 点窗内任意位置 = 说下一句（与 TEC 窗同一套口径：拖过不算，挂窗根） */
    b.addEventListener("click", () => {
      if (b._dragged) return;
      showCharLine(b._talkNode);
    });
    world.appendChild(b);                 /* 挂世界层：跟着画布坐标走，锚在人物节点上 */
    makeFloatDraggable(b, true);          /* inWorld：拖动位移按视图缩放换算（同气泡 / 叙事卡） */
    dlgWinEl = b;
  }
  dlgWinEl._charKey = n.key;
  dlgWinEl._talkNode = n;
  dlgWinEl.querySelector(".syswin-title").textContent = "DIALOG // " + name;
  const lines = dlgWinEl.querySelector(".dlg-lines");
  const d = document.createElement("div");
  d.className = "tec-line";
  d.textContent = lineText;
  lines.appendChild(d);
  lines.scrollTop = lines.scrollHeight;
  /* 仅首次为该角色开窗时锚定一次（旧气泡规矩：底边压在人物上方 12px，上方放不下退下方）。
     同角色后续台词只追加不重锚定 —— 否则玩家拖动对话框后，一点「继续对话」就会弹回原位。
     首次开窗后位置交还玩家自由拖动，刷新/换角色重开时仍会重新锚定。 */
  if (!sameChar) anchorAboveOrBelow(dlgWinEl, n, 12);
  return dlgWinEl;
}
function showCharLine(n){
  const ch = CHARS[n.id] || {};
  const queue = charTalkQueue(n);
  if (!queue.length) return false;
  const prog = G.talkProg[n.key] || 0;
  if (prog >= queue.length) return false;      /* 台词说完：停止推进，点了也不再有新句 */
  const line = queue[prog];
  pushHistory();
  G.talkProg[n.key] = prog + 1;
  talkClues(line, ch.name || n.id);
  openDlgWin(n, ch, plain(line));
  render();
  selectNode(n.key);
  return true;
}

/* 重看对话（详情窗按钮，与场景的「重看叙事」同一口径）：把已说过的话整段重放进对话窗 ——
   **不推进队列、不再拿线索、不进撤销栈**（重看是回放，不是把流程再走一遍）；
   台词说完就停在说过的最后一句，点窗继续 = 接着说没说过的（prog 没动，衔接自然）。 */
function renarrTalk(n){
  const ch = CHARS[n.id] || {};
  const queue = charTalkQueue(n);
  const prog = Math.min(G.talkProg[n.key] || 0, queue.length);
  if (!prog) return false;                     /* 一句都没聊过：没有可重看的东西 */
  closeDlgWin();                               /* 从头重放：旧窗整扇收掉（换角色同一口径），首行落下时重新锚定 */
  for (let i = 0; i < prog; i++) openDlgWin(n, ch, plain(queue[i]));
  return true;
}

/* 浮窗初始位置避开左上角操作提示区 */
function avoidHint(x, y){
  const hint = document.getElementById("hint");
  if (!hint) return x;
  const hr = hint.getBoundingClientRect(), sr = stage.getBoundingClientRect();
  const hintRight = (hr.right - sr.left - view.x) / view.k;
  const hintBottom = (hr.bottom - sr.top - view.y) / view.k;
  if (y < hintBottom && x < hintRight) return hintRight + 12;
  return x;
}

/* 浮窗初始位置收拢到当前可视范围内（世界坐标），避免标题栏被裁掉 */
function clampFloatX(x, w){
  const stageW = stage.getBoundingClientRect().width || 1200;
  const minX = (8 - view.x) / view.k, maxX = (stageW - 8 - view.x) / view.k - (w || 200);
  return Math.max(minX, Math.min(Math.max(minX, maxX), x));
}
function clampFloatY(y, h){
  const stageH = stage.getBoundingClientRect().height || 700;
  const minY = (8 - view.y) / view.k, maxY = (stageH - 8 - view.y) / view.k - (h || 100);
  return Math.max(minY, Math.min(Math.max(minY, maxY), y));
}
/* 浮窗锚定在节点上方；上方放不下（节点太靠顶 / 被视图上沿裁掉）时退到节点下方，保证不盖住节点。
   c 已在 world 内（offsetHeight 为未缩放的布局高），n 为节点模型（世界坐标）。gap 为与节点的间距。 */
function anchorAboveOrBelow(c, n, gap){
  const h = c.offsetHeight || 120, w = c.offsetWidth || 200;
  const nH = (NODE_H[n.kind] || 46);
  const above = n.y - h - gap;            /* 世界坐标：卡底 = n.y - gap */
  const below = n.y + nH + gap;           /* 世界坐标：卡顶 = n.y + nH + gap */
  let top = above;
  if (clampFloatY(above, h) !== above) top = below;   /* 上方被视图上沿裁掉 → 放到下方 */
  top = clampFloatY(top, h);
  c.style.top = top + "px";
  c.style.left = avoidHint(clampFloatX(n.x + NODE_W[n.kind] / 2 - w / 2, w), top) + "px";
}

/* ============ 场景首次展开叙事卡 ============ */
function narrText(html){
  return String(html || "")
    .replace(/\[(item|loc|char|clue):(.+?)\]/g, (m, k, id) => labelOf(k, id) || id)
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "").trim();
}
let narrEl = null;
/* 打字机：逐字写入用 setTimeout 轮询——无头 stub 里 setTimeout 返回 0（回调永不执行），
   于是走「同步写全文」分支，既不会挂死也保证断言读到完整文本。
   计时器记在**元素自己身上**（el._twTimer）：叙事卡 / 记忆放映卡 / 对话气泡可以同时在屏幕上，
   共用一根全局 timer 会让后开的那个把先开的打字中途掐断（记忆放映卡还是**每行一个 div**）。 */
function cancelType(el){
  if (el && el._twTimer){ clearTimeout(el._twTimer); el._twTimer = null; }
}
function typeInto(el, text, opts){
  const full = String(text == null ? "" : text);
  const speed = (opts && opts.speed) || 45;      /* ms / 字（约每秒 22 字，逐字看得清、不赶） */
  const done = (opts && opts.done) || null;
  cancelType(el);
  let i = 0;
  const step = () => {
    i += 1;
    el.textContent = full.slice(0, i);
    if (i >= full.length){ el._twTimer = null; if (done) done(); return; }
    const t = setTimeout(step, speed);
    if (!t){ el.textContent = full; el._twTimer = null; if (done) done(); }   /* stub：无定时能力 → 直接满字 */
    else el._twTimer = t;
  };
  step();
}
function closeNarr(){
  if (narrEl){
    const nb = narrEl.querySelector && narrEl.querySelector(".syswin-body");
    if (nb) cancelType(nb);
    narrEl.remove(); narrEl = null;
  }
  if (memoryPlay && memoryPlay.cur) cancelType(memoryPlay.cur);
  if (memoryPlay && memoryPlay.timer) clearTimeout(memoryPlay.timer);
  memoryPlay = null;
}
function showNarrCard(n, s){
  closeNarr();
  const text = narrText(s.content || s.desc || "");
  if (!text) return;
  /* 卡头按 kind 取名：书桌 / 垃圾桶是物品，别把它们的叙事卡标成「 SCENE_FEED 」 */
  const w = makeWindow((isSceneKind(n.kind) ? "SCENE_FEED" : "OBJECT_FEED") + " // " + (s.title || s.label || n.id), closeNarr);
  const c = w.el;
  c.className = "narr-card syswin";
  w.body.textContent = text;                 /* 先放全文 → 按整卡实测高度定位 */
  makeFloatDraggable(c, true);
  world.appendChild(c);
  anchorAboveOrBelow(c, n, 14);            /* 锚在节点上方，上方放不下则退到下方，不盖节点 */
  /* 预占整卡高度：打字时卡片不塌缩、位置不跳，字符逐字「长」在既有卡框里 */
  w.body.style.minHeight = (w.body.offsetHeight || 0) + "px";
  narrEl = c;
  typeInto(w.body, text);                    /* 清空重放为打字机 */
  /* 全文只留在卡片里：正文不进日志，也不再单记一条「叙事卡已放映」（放映是过程，不是结果） */
}

/* 重看场景叙事（详情窗按钮与测试钩子共用同一入口） */
function renarrScene(sid){
  const node = G.nodes[containerKey(sid)];
  if (!node) return;
  /* 身处回忆时刻且这是那天发生故事的地点：放**那一时刻**的放映卡 ——
     叙事跟着时刻走，不把现在的花园正文放给 7月4日 的花园。 */
  const mp = (G.time && G.time !== PRESENT_TIME) ? memPlaceOf(G.time) : null;
  if (mp && containerKey(mp) === containerKey(sid)){
    showMemoryCard(G.time, node);
    return;
  }
  if (SCENE_MEMORY.indexOf(sid) >= 0) showMemoryCard(sid, node); else showNarrCard(node, containerData(sid) || {});
}

/* ============ TEC 对话窗口（桌面图标应用） ============ */
const tecHistory = [];   /* 页面会话级，不进 G/快照 */
let tecWinEl = null;
let tecMin = false;      /* 「– 收起」把窗口缩成桌面右下角那块带头像的助手卡片（#tec-chip） */
let tecDot = false;      /* 分析完成、玩家还没看过 -> 卡片角上点一个小圆点 */
let tecTask = null;      /* 分析中的任务：{ key, label, ms, endAt }，空闲为 null */
let tecChipBarKey = null;/* 进度条已按哪一个任务起播（防止每次 render 都把进度钉回 0%） */
function closeTecWin(){
  if (tecWinEl){ tecWinEl.remove(); tecWinEl = null; }
  tecMin = false;                     /* 窗口不在屏幕上就不再是「收起」态 */
  updateTecBadge();
}
/* TEC 是常驻助手：只有「换案」和「重置」才清空它；同案回访（– 收起 / × 关闭后再展开）
   必须保留窗口与对话内容，否则会被 boot() 顺带收掉、再打开就只剩空壳。 */
function resetTec(){
  closeTecWin();
  tecHistory.length = 0;
  tecTask = null; tecDot = false; tecChipBarKey = null;
  showTecChip(false);
  updateTecBadge();
}
function tecSay(text){
  tecHistory.push(text);
  /* 台词不进案卷：TEC 窗自带对话历史，日志再抄一遍只会把案卷冲成流水账
     （7月4日那组闪回档案一次就有八条长句）。要留档的是结果，不是台词。 */
  if (tecWinEl){
    const lines = tecWinEl.querySelector(".tec-lines");
    if (lines){
      const d = document.createElement("div");
      d.className = "tec-line";
      d.textContent = text;
      lines.appendChild(d);
      lines.scrollTop = lines.scrollHeight;   /* 滚动条跟随到最新一条 */
    }
  }
}
/* 素材占位符本身就代表一个完整可用的 src（index 成品 = assets/ 外链，standalone = data: 内联） */
const TEC_AVATAR = "@@ASSET:tec-avatar.png@@";

function toggleTecWin(){
  if (tecMin){                                /* 收在右下角卡片上 -> 点图标 = 还原，不是关闭 */
    openTecWin();                             /* 先把窗口建回 DOM，才量得到放大动画的终点 */
    tecMotionPlayIn();                        /* 从卡片位置放大回来 */
    return;
  }
  if (tecWinEl){ closeTecWin(); return; }     /* 开着 -> 点图标 = 关闭（原语义） */
  openTecWin();
}
function openTecWin(){
  const w = makeWindow("TEC // 对话", closeTecWin, minTecWin);
  w.el.classList.add("tec-win");
  const body = document.createElement("div");
  body.className = "tec-body";
  /* 左：助手头像列 */
  const avCol = document.createElement("div");
  avCol.className = "tec-avatar-col";
  const av = document.createElement("div");
  av.id = "tec-avatar"; av.className = "tec-avatar";
  av.title = "TEC 助手：拖节点到我身上分析，点对话窗任意位置闲聊";
  const avImg = document.createElement("img");
  avImg.src = TEC_AVATAR;
  avImg.alt = "TEC"; avImg.draggable = false;
  av.appendChild(avImg);
  const avLabel = document.createElement("div");
  avLabel.className = "tec-avatar-label"; avLabel.textContent = "TEC";
  avCol.appendChild(av); avCol.appendChild(avLabel);
  /* 右：对话 + 操作 */
  const main = document.createElement("div");
  main.className = "tec-main";
  const lines = document.createElement("div");
  lines.className = "tec-lines";
  tecHistory.forEach(t => {
    const d = document.createElement("div");
    d.className = "tec-line"; d.textContent = t;
    lines.appendChild(d);
  });
  main.appendChild(lines);
  const hint = document.createElement("div");
  hint.className = "tec-hint";
  hint.textContent = "拖节点到我身上分析 · 点框内任意位置闲聊";
  main.appendChild(hint);
  body.appendChild(avCol); body.appendChild(main);
  w.body.appendChild(body);
  /* 点窗内任意位置 = 交谈推进（与角色对话气泡 / 记忆放映卡同一套口径）：拖过的那一下不算点击
     （_dragged，所以整窗仍可拖动）。**必须挂在窗口根 `w.el` 上、不能挂在正文上** ——
     makeFloatDraggable 在 pointerdown 里对窗口根做了 setPointerCapture，随后的 click 会被
     **重定向到窗口根**（事件路径不再经过 .syswin-body），挂正文上的话点历史/提示行都不会触发；
     只有头像例外（它在拖动排除表里，起手时提前 return、没设捕获，click 才照常从它冒泡上来）。
     标题栏的 − / × 各自的 click 处理器里有 stopPropagation，落不到这里，语义不变。 */
  w.el.addEventListener("click", () => {
    if (w.el._dragged) return;
    tecTalk();
  });
  desktopEl.appendChild(w.el);
  makeFloatDraggable(w.el, false);
  tecWinEl = w.el;
  tecMin = false;
  showTecChip(false);                             /* 卡片熄掉（保留布局盒，展开动画还要量它） */
  tecDot = false;                                 /* 看过即已读 */
  if (tecTask){                                   /* 收起期间发起的分析还在跑 -> 补一根按剩余时间续播的进度条 */
    const live = G.nodes[tecTask.key];
    if (live) tecShowAnalyzing(live, tecTaskLeft());
  }
  updateTecBadge();
  if (lines) lines.scrollTop = lines.scrollHeight;   /* 打开时就停在最新一条 */
}
/* 收起 / 展开的位移与缩放：把 TEC 窗和右下角助手卡片的中心对上。
   卡片只用 visibility 隐藏、保留布局盒，所以熄掉之后也量得到（与案件卡片同一套做法）。 */
function tecChipMotion(){
  const w = tecWinEl, c = document.getElementById("tec-chip");
  if (!w || !c || typeof w.getBoundingClientRect !== "function") return null;
  if (typeof c.getBoundingClientRect !== "function") return null;
  const a = w.getBoundingClientRect(), b = c.getBoundingClientRect();
  if (!a.width || !a.height || !b.width || !b.height) return null;
  const dx = (b.left + b.width / 2) - (a.left + a.width / 2);
  const dy = (b.top + b.height / 2) - (a.top + a.height / 2);
  const s  = Math.max(.05, Math.min(b.width / a.width, b.height / a.height));
  return "translate(" + dx + "px," + dy + "px) scale(" + s + ")";
}
function tecMotionReset(){
  const w = tecWinEl;
  if (!w || !w.style) return;
  w.style.transition = ""; w.style.transform = ""; w.style.transformOrigin = ""; w.style.opacity = "";
}
function tecMotionApply(tf){
  const w = tecWinEl;
  if (!w || !w.style) return;
  w.style.transition = "transform .26s cubic-bezier(.4,0,.2,1), opacity .26s ease";
  w.style.transformOrigin = "50% 50%";
  w.style.transform = tf; w.style.opacity = "0";
}
/* 展开：从卡片位置放大回原位（窗口必须已经在 DOM 里，才量得到起点） */
function tecMotionPlayIn(){
  const tf = tecChipMotion();
  const w = tecWinEl;
  if (!w || !w.style || !tf) return;
  w.style.transition = "none";
  w.style.transformOrigin = "50% 50%";
  w.style.transform = tf; w.style.opacity = "0";
  if (typeof w.getBoundingClientRect === "function") w.getBoundingClientRect();   /* 强制回流，让起始态生效 */
  w.style.transition = "transform .26s cubic-bezier(.4,0,.2,1), opacity .26s ease";
  w.style.transform = "none"; w.style.opacity = "1";
  const t = setTimeout(tecMotionReset, 300);
  if (!t) tecMotionReset();
}
/* – 收起：窗口带位移与缩放地缩进右下角那块助手卡片（与案件卡片同一套语言）。
   分析进行中时，卡片上的进度条接着播（按剩余时间）。 */
function minTecWin(){
  if (!tecWinEl) return false;
  const w0 = tecWinEl;                       /* 记住这一块窗：110ms 内被还原/换掉时别摘错 */
  const tf = tecChipMotion();
  const land = () => {
    if (w0 && w0.parentNode) w0.remove();
    if (tecWinEl === w0){ tecWinEl = null; updateTecBadge(); }
  };
  /* 落点**先亮出来当靶子**，窗口再缩过去（与案件卡片 caseParkPoint 同一套做法）：
     卡片先淡入、窗口在它上面缩着淡出，两者交叠 —— 否则窗口先缩没、卡片才淡入，
     中间会"闪一下"再出现（用户反馈"不够顺滑"）。 */
  tecMin = true;                             /* 先置真：窗口不在屏幕上，但助手驻留在右下角卡片上 */
  tecChipBarKey = null;                      /* 让进度条按剩余时间重新起播 */
  showTecChip(true);
  updateTecChip();
  if (tf){
    tecMotionApply(tf);
    const t = setTimeout(land, 280);
    if (!t) land();                          /* 无头 stub：setTimeout 返回 0，同步收尾 */
  } else land();
  return true;
}

/* ============ TEC 分析：拖节点入 TEC -> 约 5~8s 分析 -> 提取线索 / 无线索提示 ============ */
const TEC_ANALYZE_MIN = 5000, TEC_ANALYZE_MAX = 8000;
let tecBusy = false;
/* ---- 右下角助手卡片（#tec-chip）：收起态的可视化 ----
   还剩多少毫秒：收起 / 还原之间要接着播同一根进度 */
function tecTaskLeft(){ return tecTask ? Math.max(400, tecTask.endAt - Date.now()) : 0; }
let tecChipOn = false;
/* 卡片的文案 / 进度条 / 完成圆点都在这里刷新（updateTecBadge 每次 render 都会调它） */
function updateTecChip(){
  const chip = document.getElementById("tec-chip");
  if (!chip) return;
  const st = document.getElementById("tc-status");
  if (st) st.textContent = tecTask ? ("分析中 · " + tecTask.label)
                       : (tecDot ? "分析完成 · 点此展开" : "助手已收起 · 点此展开");
  if (chip.classList) chip.classList.toggle("busy", !!tecTask);
  /* 进度条只在本轮任务的**第一次**刷新时起播：updateTecChip 会被 render 反复调到，
     每次都重启动画会把进度条永远钉在 0%。key 里带 endAt，换任务自然重播；
     minTecWin 把 key 清空，所以"分析途中才收起"也会按剩余时间重新起播。 */
  const key = tecTask ? (tecTask.key + "@" + tecTask.endAt) : null;
  const fill = document.getElementById("tc-bar-fill");
  if (fill && fill.style){
    if (!key){
      /* 空闲：把进度条停回 0。这里不能只写 `key !== tecChipBarKey` —— 两边都可能是 null，
         判不出来，进度条会一直停在"分析完成"的那一刻（踩过）。 */
      tecChipBarKey = null;
      if (fill.style.animationDuration !== "") fill.style.animationDuration = "";
    } else if (key !== tecChipBarKey){
      tecChipBarKey = key;
      fill.style.animationDuration = Math.round(tecTaskLeft()) + "ms";
      /* 重启动画只能用 animationName 长写：animation 是**简写**，写 "none" 会把 inline 的
         animation-duration 一起清零，动画退化成 0s 瞬间跑完（真机实测踩到；DOM stub 的
         style 不展开简写，所以 verify.js 查不出来）。 */
      fill.style.animationName = "none";
      void chip.offsetWidth;               /* 强制回流，让动画从头播 */
      fill.style.animationName = "";
    }
  }
  /* 完成圆点：压在卡片右上角，打开 TEC 窗口即清除 */
  let d = chip.querySelector ? chip.querySelector(".tc-dot") : null;
  if (tecDot){
    if (!d && chip.appendChild){ d = document.createElement("span"); d.className = "tc-dot"; chip.appendChild(d); }
  } else if (d) d.remove();
}
function showTecChip(v){
  tecChipOn = !!v;
  const c = document.getElementById("tec-chip");
  if (!c || !c.classList) return;
  if (v) updateTecChip();
  c.classList.toggle("on", !!v);
}
/* 卡片与「案件卡片 #case-dock」是两个独立落点：本卡片排在上方（bottom:84px vs 14px），不叠在一起 */
function initTecChip(){
  const img = document.getElementById("tc-av-img");
  if (img) img.src = TEC_AVATAR;
  attachDock(document.getElementById("tec-chip"), openTecWin);   /* 单击展开；拖完那一次不误展开 */
  showTecChip(false);
}
/* 节点可以拖到哪几个"外挂落点"上（悬停高亮 + 松手命中共用一份清单）。
   收起态才把右下角助手卡片加进来：卡片即使熄着也保留布局盒，不加这道门，
   窗口开着时拖节点划过卡片所在位置会被误判成"拖到了 TEC"。 */
/* 顺序即命中优先级。两扇收纳窗（证物袋 / 线索册）排在最前：它们在图标层之上
   （.bag-win / .clue-win z-index:25 > #icons z-index:24），窗口开着时会盖住左侧图标栏，
   按「看得见的最上面那个算数」的口径，被盖住的区域应判给窗口，而不是底下那张看不见的图标
   （否则拖物品到窗口上会莫名其妙落进被遮住的推演器 / 档案）。
   代价：窗口盖住的图标在窗口开着时点不到 —— 窗口可以拖走，这是可接受的取舍。 */
function nodeDropTargets(){
  const list = [];
  if (chatWinEl) list.push("chat-win");                                  /* 多人对话窗开着时，窗口优先于下面所有图标 */
  if (bagWinEl) list.push("bag-win");                                    /* 只在证物袋窗口开着时才是落点 */
  if (clueWinEl) list.push("clue-win");                                  /* 同上：线索册窗口开着才算落点 */
  list.push("bag-dock","clue-icon","tec-dock","infer-icon","goto-icon","tec-avatar");
  if (tecChipOn) list.push("tec-chip");
  return list;
}
/* 落点元素解析：两扇收纳窗是每次开窗临时建的，没有稳定的 DOM 查询入口，直接引用变量（关窗即置 null）；
   其余都是静态图标 / 头像，按 id 取即可。 */
function dropTargetEl(id){
  if (id === "chat-win") return chatWinEl;
  if (id === "bag-win") return bagWinEl;
  if (id === "clue-win") return clueWinEl;
  return document.getElementById(id);
}
function tecAnalyzingEl(){ return tecWinEl ? tecWinEl.querySelector(".tec-analyzing") : null; }
function tecClearAnalyzing(){ const e = tecAnalyzingEl(); if (e) e.remove(); }
function tecShowAnalyzing(n, ms){
  if (!tecWinEl) return;
  const main = tecWinEl.querySelector(".tec-main");
  if (!main) return;
  tecClearAnalyzing();
  const box = document.createElement("div");
  box.className = "tec-analyzing";
  const head = document.createElement("div");
  head.className = "ta-head";
  const nm = document.createElement("span"); nm.className = "ta-name"; nm.textContent = "分析中 · " + n.label;
  head.appendChild(nm);
  const bar = document.createElement("div"); bar.className = "ta-bar";
  const fill = document.createElement("i"); fill.style.animationDuration = ms + "ms";
  bar.appendChild(fill);
  box.appendChild(head); box.appendChild(bar);
  const anchor = main.querySelector(".tec-actions") || main.querySelector(".tec-hint");
  if (anchor) main.insertBefore(box, anchor); else main.appendChild(box);
}
function tecAnalyzeStart(key, ms){
  const n = G.nodes[key];
  if (!n) return false;
  if (n.kind === "clue"){ toast("线索节点不需要再让 TEC 分析", true); return false; }
  if (tecBusy){ toast("TEC 正在分析中，请稍候…", true); return false; }
  if (!tecWinEl && !tecMin) openTecWin();      /* 收起着就不弹窗：进度改画到右下角卡片上 */
  pushHistory();
  tecBusy = true;
  const dur = (typeof ms === "number" && ms > 0) ? ms
            : TEC_ANALYZE_MIN + Math.random() * (TEC_ANALYZE_MAX - TEC_ANALYZE_MIN);
  tecTask = { key: key, label: plain(n.label), ms: dur, endAt: Date.now() + dur };
  tecShowAnalyzing(n, dur);
  updateTecBadge();                            /* 收在卡片上 -> 卡片状态行 / 进度条同步起播 */
  tecSay("（接收「" + plain(n.label) + "」，开始分析…）");
  return true;
}
function tecAnalyzeFinish(key){
  const n = G.nodes[key];
  tecBusy = false;
  tecTask = null;              /* 进度条的收尾交给 updateTecChip（key 变 null 时会把动画停掉） */
  tecClearAnalyzing();
  if (!n) return false;
  /* 场景 / 时间节点：评述由「档案解读」承担（见下），不走通用反应表（它们在表里没有条目，只会落兜底噪音） */
  if (!isSceneKind(n.kind)) tecReaction(key);      /* TEC 对该节点的评述（沿用原有反应表） */
  const talks = isSceneKind(n.kind) ? (((CHARS["CHARS_TEC"] || {}).sceneTalks || {})[n.id] || []) : null;
  const unread = talks ? talks.length - (G.tecProg[n.id] || 0) : 0;
  {
    const fresh = capturableClues(n).filter(id => !G.captured.has(id));
    if (fresh.length){
      const src = nodeData(n);
      const hc = (src && src.hiddenClue) || {};
      fresh.forEach(id => {
        const cn = ensureNode("clue", id, {});
        markFresh(cn);
        link(key, cn.key, "entity");
        G.captured.add(id);
      });
      const names = fresh.map(id => (CLUES[id] && CLUES[id].label) || id).join("、");
      tecSay("分析完成：「" + plain(n.label) + "」中提取到线索 —— " + names + "。（已落到画布上，可自由拖动）");
      const text = plain(hc.text || "");
      if (text) tecSay(text);
      log("TEC 捕获「" + esc(n.label) + "」的隐藏线索：" + esc(names), "cap");
      settle();   /* 分析完把新线索带到视野中央（TEC 窗收在右下角，不挡画面） */
    } else if (!unread){
      tecSay("分析完成：「" + plain(n.label) + "」中没有可以捕获的线索。");
      log("TEC 分析「" + esc(n.label) + "」：无可捕获线索", "warn");
    }
  }
  /* 场景档案：每次分析解读一条（提示的唯一来源就是分析；进度记 tecProg，进存档/撤销） */
  if (talks && unread > 0){
    const prog = G.tecProg[n.id] || 0;
    G.tecProg[n.id] = prog + 1;
    tecSay(plain(talks[prog].text || ""));
    talkClues(talks[prog].text || "", "TEC");
    log("TEC 解读了「" + esc(n.label) + "」的档案（" + (prog + 1) + "/" + talks.length + "）", "sys");
  } else if (talks && !unread){
    tecSay("「" + plain(n.label) + "」的档案已经全部解读完毕。");
  }
  /* 窗口收在右下角卡片上：分析完成后在卡片角上点一个小圆点，打开 TEC 窗口即清除 */
  if (tecMin && !tecWinEl) tecDot = true;
  updateTecBadge();
  return true;
}
function tecAnalyze(key){
  const ms = TEC_ANALYZE_MIN + Math.random() * (TEC_ANALYZE_MAX - TEC_ANALYZE_MIN);
  if (!tecAnalyzeStart(key, ms)) return false;
  const t = setTimeout(() => tecAnalyzeFinish(key), ms);
  if (!t) tecAnalyzeFinish(key);               /* 无头 stub：setTimeout 返回 0，同步收尾 */
  return true;
}

function tecTalk(){
  /* 点击 = 闲聊（talkQueue 逐条推进，不循环：说完就停，点了也不再有新句）。
     不给实质提示：提示的唯一来源是「拖节点 → 分析」。不进撤销栈——一句闲聊没有可撤销的状态。 */
  const tec = CHARS["CHARS_TEC"] || {};
  const def = tec.talkQueue || [];
  if (!def.length){ if (!tecWinEl) toggleTecWin(); tecSay("（把节点拖到我身上，我来分析）"); return; }
  const idx = G.tecProg._def || 0;
  if (idx >= def.length) return;              /* 台词说完：停止推进 */
  G.tecProg._def = idx + 1;
  const line = plain(def[idx].text || "");
  if (!tecWinEl) toggleTecWin();
  tecSay(line);
  updateTecBadge();
}

/* TEC 对某个节点的「评述」：不含开窗/历史副作用，供 tecConsult 与 tecAnalyze 复用 */
function tecReaction(toolKey){
  const tool = G.nodes[toolKey];
  if (!tool) return false;
  const hit = lookupReaction("char", "CHARS_TEC", tool.id);
  if (hit){
    const text = plain(hit.react.text || hit.react.message || "");
    tecSay("（分析 " + tool.label + "）" + text);
    talkClues(hit.react.text || hit.react.message || "", "TEC");
    noteSeen(hit.react.text || hit.react.message || "");
  } else {
    tecSay("关于「" + plain(tool.label) + "」，我暂时没有更多线索。试试把它和别的节点组合。");
    log("TEC 对「" + esc(tool.label) + "」没有特别的反应", "warn");
    G.tried.add(toolKey + ">tec-dock");
  }
  return !!hit;
}
/* 立即咨询（保底 API：window.__tec 走这里；不改延迟语义） */
function tecConsult(toolKey){
  const tool = G.nodes[toolKey];
  if (!tool) return false;
  pushHistory();
  if (!tecWinEl) toggleTecWin();
  return tecReaction(toolKey);
}

function updateTecBadge(){
  /* 提示没有"未读数"了：提示只在分析后产出，图标不再挂「提示 N」角标（免费频道的广告位一并拆掉） */
  const dock = document.getElementById("tec-dock");
  if (dock){
    const b = dock.querySelector(".badge.talk");
    if (b) b.remove();
    dock.classList.remove("pulse");
  }
  /* 驻留态（– 收起）= 右下角那块助手卡片，不落在图标上（用户明确要求"收进右下角带头像的一块"） */
  showTecChip(tecMin);
  updateTecChip();
}

/* ============ 多人对话（会话级，不进 G / 撤销栈） ============
   participants 是本剧本允许出场的全集；初始拖过来的两人只是「已加入」子集。
   因此三人剧本可以由两人命中，播到第三人的第一句时才暂停等那个人被拖进窗。 */
let chatSession = null, chatWinEl = null;

function dialogueSetKey(ids){ return (ids || []).slice().sort().join("|"); }
function lookupDialogue(ids){
  const key = dialogueSetKey(ids);
  const exact = (DIALOGUES || []).find(d => dialogueSetKey(d.participants) === key);
  if (exact) return exact;
  return (DIALOGUES || []).find(d => ids.every(id => (d.participants || []).indexOf(id) >= 0)) || null;
}
function monologueOf(charId){
  return (DIALOGUES || []).find(d => (d.participants || []).length === 1 && d.participants[0] === charId) || null;
}
function closeChatWin(){
  if (chatSession && chatSession.current) cancelType(chatSession.current.el);
  if (chatWinEl){ chatWinEl.remove(); chatWinEl = null; }
  chatSession = null;
}
function chatHint(text){
  if (!chatWinEl) return;
  const h = chatWinEl.querySelector(".chat-hint");
  if (h) h.textContent = text;
}
function openChatSession(entry, initialIds){
  closeChatWin();
  const ids = initialIds.slice();
  chatSession = { entry, joined:new Set(ids), idx:0, waitingFor:null, typing:false, current:null, done:false };
  const solo = (entry.participants || []).length === 1;
  const title = (solo ? "独白 // " : "DIALOGUE // ") +
    ids.map(id => labelOf("char", id) || id).join(" × ");
  const w = makeWindow(title, closeChatWin);
  const b = w.el;
  b.className = "chat-win syswin";
  const lines = document.createElement("div");
  lines.className = "chat-lines";
  const hint = document.createElement("div");
  hint.className = "chat-hint";
  hint.textContent = "点框内任意位置继续";
  w.body.appendChild(lines);
  w.body.appendChild(hint);
  b.addEventListener("click", () => { if (!b._dragged) chatNext(); });
  desktopEl.appendChild(b);
  makeFloatDraggable(b, false);
  chatWinEl = b;
  chatAdvance();
  return true;
}
function startChatCombo(a, b){
  const ids = [a.id, b.id];
  const entry = lookupDialogue(ids) ||
    { id:null, participants:ids, script:[{ t:"narr", text:"他们没什么可说的。" }] };
  return openChatSession(entry, ids);
}
function startMonologue(charId){
  const entry = monologueOf(charId);
  if (!entry) return false;
  return openChatSession(entry, [charId]);
}
function chatAdvance(){
  const s = chatSession;
  if (!s || s.done || s.waitingFor) return false;
  const line = s.entry.script[s.idx];
  if (!line){
    s.done = true;
    chatHint("对话结束");
    return false;
  }
  if (line.t === "say" && !s.joined.has(line.who)){
    s.waitingFor = line.who;
    chatHint("把「" + (labelOf("char", line.who) || line.who) + "」拖进对话框");
    return false;
  }
  s.idx += 1;
  const lines = chatWinEl.querySelector(".chat-lines");
  const d = document.createElement("div");
  d.className = "chat-line " + (line.t === "say" ? "say" : "narr");
  const full = plain(line.text || "");
  if (line.t === "say"){
    const who = document.createElement("span");
    who.className = "chat-who";
    who.textContent = labelOf("char", line.who) || line.who;
    d.appendChild(who);
  }
  const txt = document.createElement("span");
  txt.className = "chat-text";
  d.appendChild(txt);
  lines.appendChild(d);
  lines.scrollTop = lines.scrollHeight;
  const cur = { el:txt, full };
  s.current = cur;
  s.typing = true;
  chatHint("点窗内补全本句");
  typeInto(txt, full, { done:() => {
    if (chatSession === s && s.current === cur){
      s.typing = false;
      if (!s.waitingFor && !s.done) chatHint("点框内任意位置继续");
    }
  } });
  return true;
}
function chatNext(){
  const s = chatSession;
  if (!s) return false;
  if (s.typing && s.current){
    cancelType(s.current.el);
    s.current.el.textContent = s.current.full;
    s.typing = false;
    chatHint("点框内任意位置继续");
    return true;
  }
  if (s.waitingFor || s.done) return false;
  return chatAdvance();
}
function chatJoin(key){
  const n = G.nodes[key], s = chatSession;
  if (!n || n.kind !== "char" || !s) return false;
  if (s.joined.has(n.id)) return false;          /* 已在场：忽略 */
  if (!s.waitingFor || n.id !== s.waitingFor){
    chatHint("插不上话");
    return false;
  }
  s.joined.add(n.id);
  s.waitingFor = null;
  chatHint("点框内任意位置继续");
  chatAdvance();                                /* 从被截住的那一句立刻续播 */
  return true;
}
function chatDrop(key){
  const n = G.nodes[key];
  if (!n || n.kind !== "char"){
    if (chatSession) chatHint("只有人物能加入这段对话");
    return false;
  }
  return chatJoin(key);
}
function chatState(){
  const s = chatSession;
  if (!s) return { open:false, id:null, participants:[], joined:[], idx:0, total:0, waitingFor:null, typing:false, done:false };
  return { open:!!chatWinEl, id:s.entry.id, participants:(s.entry.participants || []).slice(),
    joined:[...s.joined], idx:s.idx, total:(s.entry.script || []).length,
    waitingFor:s.waitingFor, typing:!!s.typing, done:!!s.done,
    lines:chatWinEl ? chatWinEl.querySelector(".chat-lines").children.length : 0 };
}
