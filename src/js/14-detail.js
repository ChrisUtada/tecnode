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
   内容与上次逐字相同就直接跳过，不重建 DOM —— 免得打断 hover、把滚动位置弹回顶部。 */
function paintDetail(){
  const n = sel ? G.nodes[sel] : null;
  if (!n){ detailPlaceholder(sel ? "节点已不存在。" : null); return; }

  let html = "<div class='dt'>" + esc(n.label) + "</div>";
  html += "<div class='dmeta'>" + kindName(n.kind) + " · " + n.key + "</div>";

  if (isContainerNode(n)){
    /* 容器：场景给「文本入口 / 出口」，容器物品（书桌 / 垃圾桶）给「内容 / 来源」——
       两者共用「状态 + 回看重看」两行。正文只在叙事卡里出现一次，这里不重复。 */
    if (n.kind === "loc"){
      const ins = Object.keys(SCENES).filter(x => sceneLocs(x).indexOf(n.id) >= 0).map(x => SCENES[x].title);
      html += "<div class='drow'>文本入口：" + (ins.length ? esc(ins.join("、")) : "<span style='color:#2b2b26'>无</span>") + "</div>";
      html += "<div class='drow'>出口：" + (sceneLocs(n.id).length ? esc(sceneLocs(n.id).map(x => SCENES[x].title).join("、")) : "无") + "</div>";
    } else {
      const inside = sceneTags(n.id).map(t => labelOf(t.kind, t.id)).filter(Boolean);
      html += "<div class='drow'>内容：" + (inside.length ? esc(inside.join("、")) : "无") + "</div>";
      /* 容器物品的正文里也可能带出口（书桌的「返回 [loc:SCENES_garden]」就是一条） */
      const outs = sceneLocs(n.id);
      if (outs.length) html += "<div class='drow'>出口：" + esc(outs.map(x => containerTitle(x)).join("、")) + "</div>";
      if (n.homeScene && containerData(n.homeScene)) html += "<div class='drow'>来源：" + esc(containerTitle(n.homeScene)) + "</div>";
    }
    html += "<div class='drow'>状态：" + (G.explored.has(n.id) ? "已展开" : "未展开") + "</div>";
    /* 正文只在叙事卡里出现一次；详情窗只给结构信息 + 回看入口（去重） */
    if (G.explored.has(n.id))
      html += "<div class='drow'><button id='dt-renarr'>[ " + (n.kind === "loc" ? "重看场景叙事" : "重看叙事") + " ]</button></div>";
  } else if (n.kind === "clue"){
    const c = CLUES[n.id] || {};
    html += "<div class='ddesc'>" + esc(plain(c.desc || "（无描述）")) + "</div>";
    html += "<div class='drow'>感官类型：" + (SENSES[c.type] || c.type || "未知") + "</div>";
    html += "<div class='drow'>状态：" + (G.captured.has(n.id) ? "已捕获" : "未捕获") + "</div>";
  } else if (n.kind === "char"){
    const c = CHARS[n.id] || {};
    html += "<div class='ddesc'>" + esc(plain(c.desc || "（无描述）")) + "</div>";
    html += "<div class='drow'>对话进度：" + (G.talkProg[n.key] || 0) + "/" + charTalkQueue(n).length + "</div>";
    const seen = new Set();
    ["presentReactions","itemReactions","reactions"].forEach(f => Object.keys(c[f] || {}).forEach(k => seen.add(k)));
    if (seen.size){
      const names = [...seen].map(k => labelOf("item", k) || labelOf("clue", k) || k);
      html += "<div class='drow'>对这些东西有反应：" + esc(names.join("、")) + "</div>";
    }
  } else {
    /* 物品 */
    const it = ITEMS[n.id] || {};
    /* 物品描述统一由详情窗承载（不论有没有命令）：无命令物品的双击只是选中，
       描述就在详情窗里读 —— 不再靠顶部提示条闪一下。
       文本物（纸条 / 笔记这类）的正文里，被 excerpts 点名的词渲染成可点下划线：点一下就在图上长边。 */
    html += "<div class='ddesc'>" + excerptHtml(plain(it.desc || "（无描述）"), excerptsOf(n.id)) + "</div>";
    /* 需要光的物品：把条件写在详情窗里，玩家不用瞎试 */
    const litCmd = (it.commands || []).find(c => c.requiresLit);
    if (litCmd){
      html += "<div class='drow'>光照条件：" + (lightOn(litCmd.requiresLit) ? "充足" : "不足 · 需先点亮光源") + "</div>";
    }
    /* 自己能发光的物品（台灯 / 手电筒）：开关状态 + 它的用途，一并写在详情窗里 */
    if (isToggleLight(n.id)){
      html += "<div class='drow'>状态：" + (n.lit ? "已点亮" : "未点亮") +
        (it.needsLitToUse ? (n.lit ? " · 可以照亮黑暗里的东西" : " · 先点亮它，才能照亮黑暗里的东西") : "") + "</div>";
    }
    /* 装上的零件：命令上的 requires 门要靠它兑现（唱机得先装上唱针，才放得出黑胶）。
       和上面的「光照条件」一个性质 —— 把条件写在详情窗里，玩家不用瞎试。 */
    const fitted = Object.keys(n.installed || {}).map(id => labelOf("item", id) || id);
    if (fitted.length) html += "<div class='drow'>已装上：" + esc(fitted.join("、")) + "</div>";
    const needFit = [];
    (it.commands || []).forEach(c => (c.requires || []).forEach(pid => {
      if (!(n.installed || {})[pid]) needFit.push(labelOf("item", pid) || pid);
    }));
    if (needFit.length) html += "<div class='drow'>待装上：" + esc([...new Set(needFit)].join("、")) + "</div>";
    /* 来源容器：可能是场景，也可能是书桌 / 垃圾桶这类容器物品 */
    if (n.homeScene && containerData(n.homeScene)) html += "<div class='drow'>来源：" + esc(containerTitle(n.homeScene)) + "</div>";
    const outs = [];
    for (const f in (it.presentReactions || {})) outs.push({ tool:f, r:it.presentReactions[f] });
    if (outs.length){
      html += "<div class='drow'>与这些东西存在反应：" +
        esc(outs.map(o => {
          const nm = labelOf("item", o.tool) || labelOf("clue", o.tool) || o.tool;
          return (ITEMS[o.tool] || {}).needsLitToUse ? nm + "（须先点亮）" : nm;
        }).join("、")) + "</div>";
    }
    const cond = condRoutes[n.id];
    if (cond) html += "<div class='drow'>参与条件跳转</div>";
  }

  if (detailBody.__sig === html) return;     /* 状态没变：原样留着，不动 DOM */
  detailBody.__sig = html;
  detailBody.innerHTML = html;
  const rb = document.getElementById("dt-renarr");
  if (rb) rb.addEventListener("click", () => renarrScene(n.id));
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
    const key = String(list[h.i].to);
    out += esc(t.slice(cur, h.at));
    out += "<button class='ex" + (G.nodes[key] ? " got" : "") + "' data-ex=\"" + esc(key) + "\">" +
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
  const kind = target.slice(0, i), id = target.slice(i + 1);
  const nm = labelOf(kind, id);
  if (!nm) return;
  const key = kind + ":" + id;
  const isNew = !G.nodes[key];
  const newEdge = !edgeBetween(srcKey, key, "cond");
  if (isNew || newEdge){
    pushHistory();
    const n = ensureNode(kind, id, { label: nm });
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
    const isNew = !nodeByKey("loc", r.scene);
    const sn = ensureNode("loc", r.scene, { label: SCENES[r.scene].title });
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
