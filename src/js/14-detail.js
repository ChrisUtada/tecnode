/* ============ 详情面板 ============ */
/* 占位内容（清空选中 / 重置）。顺手把签名对上，免得下一次 paintDetail 误判「内容没变」而跳过重绘。 */
function detailPlaceholder(msg){
  const html = "<div class='empty'>" + (msg || "点选任意节点查看信息。") + "</div>";
  detailBody.__sig = html;
  detailBody.innerHTML = html;
}

/* 把「当前选中节点」的实时状态写进 #detail-body。selectNode 会调它，render() 末尾也会调它 ——
   所以点亮台灯 / 捕获线索 / 展开场景 / 推进对话之后，详情窗里那一行「状态」自己就变了，
   不必重新点一下节点（旧版只在点选那一刻渲染一次，所以台灯点亮后详情窗还写着「未点亮」）。
   内容与上次逐字相同就直接跳过，不重建 DOM —— 免得打断 hover、把滚动位置弹回顶部。

   **详情窗只有三种内容：简介（ddesc）/ 状态（drow）/ 来源（drow）。**（2026-10-14 收口）
   刻意不列「容器里装着什么」「谁的正文指向它」「它跟谁有反应」——那是玩家该自己动手
   （展开 / 组合 / 拖给 TEC 分析）试出来的东西，写在详情窗里等于直接递答案。
   唯一例外是「状态」里的**使用条件**（要光 / 要零件 / 开关与否）：那是防瞎试的前馈，不是答案。 */
function paintDetail(){
  const n = sel ? G.nodes[sel] : null;
  if (!n){ detailPlaceholder(sel ? "节点已不存在。" : null); return; }

  /* 回忆时刻：叙事文本跟着时刻走 —— 地点讲那天的正文、人物讲那天的回忆，
     都是从 memories 派生的时刻专属叙述（memNarrOf）；present 档返回 null，照旧用静态文本。 */
  const mn = memNarrOf(G.time, n);
  const tlabel = timeLabelOf(G.time);

  let html = "<div class='dt'>" + esc(n.label) + "</div>";
  html += "<div class='dmeta'>" + kindName(n.kind) + "</div>";

  if (isContainerNode(n)){
    if (mn){
      html += "<div class='ddesc'>" + esc(mn) + "</div>";
      html += "<div class='drow'>时刻：" + esc(tlabel) + "</div>";
    }
    /* 用「已探索 / 未探索」，与画布节点副标题（07-render.js）统一 —— 展开是动作，探索才是状态。 */
    html += "<div class='drow'>状态：" + (G.explored.has(n.id) ? "已探索" : "未探索") + "</div>";
    /* 正文只在叙事卡里出现一次；详情窗只给回看入口（去重） */
    if (G.explored.has(n.id))
      html += "<div class='drow'><button id='dt-renarr'>[ " + (isSceneKind(n.kind) ? "重看场景叙事" : "重看叙事") + " ]</button></div>";
  } else if (n.kind === "clue"){
    const c = CLUES[n.id] || {};
    html += "<div class='ddesc'>" + esc(plain(c.desc || "（无描述）")) + "</div>";
    html += "<div class='drow'>状态：" + (G.captured.has(n.id) ? "已捕获" : "未捕获") +
      " · " + (SENSES[c.type] || c.type || "未知") + "</div>";
  } else if (n.kind === "char"){
    const c = CHARS[n.id] || {};
    /* 身处回忆时刻且这个人物在那一天有回忆：简介换成一整段回忆脚本，并注明时刻 */
    html += "<div class='ddesc'>" + esc(mn || plain(c.desc || "（无描述）")) + "</div>";
    if (mn) html += "<div class='drow'>时刻：" + esc(tlabel) + "</div>";
    html += "<div class='drow'>状态：" + ((G.talkProg[n.key] || 0) >= charTalkQueue(n).length ? "已聊完" : "可对话") + "</div>";
    /* 聊过就有回看入口（与场景的「重看叙事」同一套）：把已说过的话整段重放进对话窗 */
    if ((G.talkProg[n.key] || 0) > 0)
      html += "<div class='drow'><button id='dt-renarr-talk'>[ 重看对话 ]</button></div>";
  } else {
    /* 物品 */
    const it = ITEMS[n.id] || {};
    /* 物品描述统一由详情窗承载（不论有没有命令）：无命令物品的双击只是选中，
       描述就在详情窗里读 —— 不再靠顶部提示条闪一下。
       文本物（纸条 / 笔记这类）的正文里，被 excerpts 点名的词渲染成可点下划线：点一下就在图上长边。 */
    html += "<div class='ddesc'>" + excerptHtml(plain(it.desc || "（无描述）"), excerptsOf(n.id)) + "</div>";
    /* 「状态」= 使用条件（要光 / 要零件 / 开关与否），合成一行。
       不写「它跟谁有反应」：那正是玩家要自己试的东西。 */
    const st = [];
    const litCmd = (it.commands || []).find(c => c.requiresLit);
    if (litCmd) st.push(lightOn(litCmd.requiresLit) ? "光线充足" : "光线不足，需先点亮光源");
    /* 自己能发光的物品（台灯 / 手电筒）：开关状态；手电筒这类再附一句「要先点亮才能用」 */
    if (isToggleLight(n.id)){
      st.push(n.lit ? "已点亮" : "未点亮");
      if (it.needsLitToUse) st.push(n.lit ? "可照亮黑暗里的东西" : "先点亮它，才能照亮黑暗里的东西");
    }
    /* 装上的零件：命令上的 requires 门要靠它兑现（唱机得先装上唱针，才放得出黑胶） */
    const fitted = Object.keys(n.installed || {}).map(id => labelOf("item", id) || id);
    if (fitted.length) st.push("已装上 " + fitted.join("、"));
    const needFit = [];
    (it.commands || []).forEach(c => (c.requires || []).forEach(pid => {
      if (!(n.installed || {})[pid]) needFit.push(labelOf("item", pid) || pid);
    }));
    if (needFit.length) st.push("待装上 " + [...new Set(needFit)].join("、"));
    if (st.length) html += "<div class='drow'>状态：" + esc(st.join(" · ")) + "</div>";
    /* 唱机装上唱针后：详情里直接给一个播放按钮（音乐随游戏内置，base64 内联） */
    if (n.id === "ITEMS_changji" && n.installed && n.installed["ITEMS_cz"])
      html += "<div class='drow'><button id='dt-play-music'>" + iconSvg("play", 12) + " 播放音乐</button></div>";
  }

  /* 来源：物品 / 容器物品 / 线索 / 人物都可能记着「从哪来」（在哪展开、在哪遇见）。
     **场景不给**：场景之间是叙事链接，不是「谁装下了谁」——而且 homeScene 会被
     最后一次展开的宿主覆盖（实测「植物学家的花园」的来源变成过「尸体」），
     写出来是随机的、纯误导。详情窗自此只剩「简介 / 状态 / 来源」三种内容。 */
  if (!isSceneKind(n.kind) && n.homeScene && containerData(n.homeScene))
    html += "<div class='drow'>来源：" + esc(containerTitle(n.homeScene)) + "</div>";

  if (detailBody.__sig === html) return;     /* 状态没变：原样留着，不动 DOM */
  detailBody.__sig = html;
  detailBody.innerHTML = html;
  const rb = document.getElementById("dt-renarr");
  if (rb) rb.addEventListener("click", () => renarrScene(n.id));
  const rtb = document.getElementById("dt-renarr-talk");
  if (rtb) rtb.addEventListener("click", () => renarrTalk(n));
}

/* ============ 摘录：文本物正文里可点的一小段 → 图上长出「目标节点 + 一条连回这张纸的边」 ============
   数据写在 items 那一条上（正文 desc 保持干净、不掺标签，可读性不受影响）：
     "excerpts": [ { "text": "7月4日", "to": "loc:SCENES_0704" }, { "text": "槿杉", "to": "char:CHARS_JS" } ]
   重点是「长出边」而不是「长出节点」：纸上的信息原本只活在玩家脑子里（读完是死胡同），
   现在「读到」这个动作本身把那条边画了出来 —— 于是它进了快照、可撤销、也被枢纽统计认。 */
function excerptsOf(id){
  const list = (ITEMS[id] || {}).excerpts;
  return Array.isArray(list) ? list.filter(e => e && e.text && e.to) : [];
}
/* 按摘录表把命中的词包成可点按钮，其余部分照常转义。
   从左到右扫一遍，重叠的命中以「先出现的、且更长的」为准。 */
function excerptHtml(text, list){
  const t = String(text == null ? "" : text);
  if (!list.length) return esc(t);
  const hits = [];
  list.forEach((ex, i) => {
    const w = String(ex.text);
    for (let at = t.indexOf(w); at >= 0; at = t.indexOf(w, at + w.length)) hits.push({ at, len:w.length, i });
  });
  if (!hits.length) return esc(t);
  hits.sort((a, b) => (a.at - b.at) || (b.len - a.len));
  let out = "", cur = 0;
  hits.forEach(h => {
    if (h.at < cur) return;                                  /* 与已输出的片段重叠：跳过 */
    const ref = String(list[h.i].to);                  /* 数据里的引用原样写进 data-ex，点它时才解析 */
    const ri = ref.indexOf(":");
    const nkey = ri < 0 ? ref : nodeKeyOfRef(ref.slice(0, ri), ref.slice(ri + 1));
    out += esc(t.slice(cur, h.at));
    out += "<button class='ex" + (G.nodes[nkey] ? " got" : "") + "' data-ex=\"" + esc(ref) + "\">" +
           esc(t.slice(h.at, h.at + h.len)) + "</button>";
    cur = h.at + h.len;
  });
  return out + esc(t.slice(cur));
}
/* 点下划线 = 读到了它：ensureNode（已有就复用）+ 一条 cond 边（连回那张纸）+ noteSeen + 镜头带过去。
   已经摘过的（节点与边都在）不重复长、不记历史 —— 免得连着点几下刷出一堆撤销步。
   **详情窗留在原来那张纸上**：玩家是在文档里读的，连着摘几个词不该被反复踢走
   （目标节点靠「新」角标 + 镜头自动居中告诉他东西长出来了）。 */
function takeExcerpt(target, srcKey){
  if (!requireCase()) return;
  const src = G.nodes[srcKey];
  const i = String(target || "").indexOf(":");
  if (!src || i < 0) return;
  const refKind = target.slice(0, i), id = target.slice(i + 1);
  /* 数据里写的是 [loc:SCENES_0704]，但画布上那是时间节点 —— kind 要按 containerKind 规整，
     否则这里会长出一个 loc:SCENES_0704，与 containerKey() 算出的 time: 分裂成两个节点 */
  const kind = isSceneKind(refKind) ? containerKind(id) : refKind;
  const nm = labelOf(kind, id);
  if (!nm) return;
  const key = kind + ":" + id;
  const isNew = !G.nodes[key];
  const newEdge = !edgeBetween(srcKey, key, "cond");
  if (isNew || newEdge){
    pushHistory();
    /* 场景 / 时间引用走 ensureSceneNode（唯一入口）：新时刻收录提示挂在它身上，
       摘录点出「7月4日」这类日期时 toast + 角标才会响 —— 直接 ensureNode 会绕过提示。 */
    const n = isSceneKind(refKind) ? ensureSceneNode(id, { label: nm }) : ensureNode(refKind, id, { label: nm });
    if (isNew) markFresh(n);
    link(srcKey, key, "cond");
    noteSeen(nm);
    settle();
    log("摘录：从「" + esc(src.label) + "」上读到「" + esc(nm) + "」", "act");
  }
  if (sel !== srcKey) selectNode(key);     /* 已经在这张纸上读：留住他，别把详情窗踢走 */
}
/* 委托挂在 #detail-body 上（innerHTML 每次重绘都会换掉子节点，绑定按钮本身会漏）。
   按钮天然在 makeFloatDraggable 的排除表里（表里有 button），所以浮窗的 setPointerCapture
   不会把这次 click 重定向到窗口根 —— 这正是 details 窗内其它按钮一直在用的那条通路。 */
detailBody.addEventListener("click", e => {
  const b = (e.target && e.target.closest) ? e.target.closest("button.ex") : null;
  if (b) takeExcerpt(b.getAttribute("data-ex"), sel);
  /* 唱机详情里的「播放音乐」按钮：直接播放内置曲目（无手势被拦时静默） */
  const pm = (e.target && e.target.closest) ? e.target.closest("#dt-play-music") : null;
  if (pm) playMusic("Air_Bach");
});

/* 「新」角标**只有玩家点过这个节点才会摘**：这里把 DOM 上那枚角标摘掉，同时清 n.unread
   （render() 画角标认的就是 unread，重绘不会动它 —— 只有这里会清）。
   只在角标**已经画在屏上**时才动手（n.el 为空说明还没重绘出来，留着让 render 正常亮一下）。
   刻意不放进 selectNode：从线索册 / 人物名册**点清单行**也会 selectNode，那不是"点节点"，
   取回来的线索该照常亮一次「新」。 */
function clearFresh(n){
  const el = n.el;
  const b = (el && el.querySelector) ? el.querySelector(".badge.new") : null;
  if (b && b.remove){ b.remove(); n.unread = false; n.fresh = false; }
}

function selectNode(key){
  const n = G.nodes[key];
  if (!n){ sel = null; detailPlaceholder("节点已不存在。"); return; }
  nodeLayer.querySelectorAll(".node.sel").forEach(e => e.classList.remove("sel"));
  if (n.el) n.el.classList.add("sel");
  sel = key;
  if (!detailWinOpen) setDetailWin(true);   /* 选中节点时自动弹出详情窗 */
  paintDetail();
  applyFocus();
}

window.__reveal = function(sid){ revealScene(sid); selectNode(containerKey(sid)); };
window.__cmd = function(id, i){ const n = nodeByKey("item", id); if (n) runCommand(n, (ITEMS[id].commands || [])[i]); };
window.__choice = function(id, ci, oi){
  const n = nodeByKey("item", id);
  const cmd = (ITEMS[id].commands || [])[ci];
  const opt = (cmd.options || [])[oi];
  if (!n || !opt) return;
  pushHistory();
  if (opt.message){ log(esc(plain(opt.message)), "sys"); noteSeen(opt.message); }
  const r = opt.results || {};
  if (r.scene && SCENES[r.scene]){
    const isNew = !nodeByKey(containerKind(r.scene), r.scene);
    const sn = ensureSceneNode(r.scene, { label: SCENES[r.scene].title });
    markFresh(sn);
    link(n.key, sn.key, "cond");
    revealScene(r.scene);
    layout(); render();
    selectNode(sn.key);
    return;
  }
  applyPayload(r, n.key);
  settleSelect(settle(), n.key);
};
window.__pw = function(id){
  const n = nodeByKey("item", id);
  const cmd = (ITEMS[id].commands || []).find(c => c.type === "password");
  const input = document.getElementById("pw-in");
  if (!n || !cmd) return;
  const v = (input && input.value || "").trim();
  if (v !== String(cmd.value)){
    /* 密码错：只抖一下 + 记一行日志（不再弹提示 / 不再往详情窗塞文字） */
    log("「" + esc(n.label) + "」密码 " + esc(v || "(空)") + " 不正确", "warn");
    if (pwPop){ pwPop.classList.remove("shake"); void pwPop.offsetWidth; pwPop.classList.add("shake"); }
    return;
  }
  pushHistory();
  closePwPop();
  const os = cmd.onSuccess || {};
  const pwMsg = plain(os.message || "打开了。");
  log("「" + esc(n.label) + "」已打开：" + esc(pwMsg), "act");
  noteSeen(os.message || "");
  if (os.items) spawnItems(os.items, n.key);
  gotClues(os.message || "");
  if (tgConsume.checked){ deleteNode(n.key); }
  settleSelect(settle(), n.key);
};
