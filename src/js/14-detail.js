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
       描述就在详情窗里读 —— 不再靠顶部提示条闪一下。 */
    html += "<div class='ddesc'>" + esc(plain(it.desc || "（无描述）")) + "</div>";
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
