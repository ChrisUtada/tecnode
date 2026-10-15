/* ============ 物品命令 ============ */
function runCommand(n, cmd){
  const it = ITEMS[n.id] || {};
  const t = cmd.type;

  /* 光照门（可选）：requiresLit = true（任意环境光源）/ "ITEM_x"（指定的那一盏）的命令，
     必须先点亮才执行得下去。暗着双击 = 只给一行提示，不生成任何节点、不进撤销栈。 */
  if (cmd.requiresLit && !lightOn(cmd.requiresLit)){
    const dark = plain(cmd.failMessage || "光线太暗，什么也看不清。");
    log("「" + esc(n.label) + "」：" + esc(dark), "warn");
    noteSeen(cmd.failMessage || "");
    toast("<b>" + esc(n.label) + "</b><br>" + esc(dark), true);
    return;
  }

  if (t === "text"){
    const news = freshKeys();          /* 抢在 render() 清掉 fresh 之前 */
    gotClues(plain(cmd.value || ""));
    noteSeen(cmd.value || cmd.message || "");
    log("「" + esc(n.label) + "」：" + esc(plain(cmd.value || "")), "sys");
    if (isToggleLight(n.id)){
      pushHistory();
      n.lit = !n.lit;
      const flavor = n.lit ? (it.litOnMessage || "亮了起来") : (it.litOffMessage || "熄灭了");
      log("「" + esc(n.label) + "」" + esc(plain(flavor)), n.lit ? "act" : "sys");
    } else if (!news.length){
      return;                      /* 纯文本、也没长出节点：维持原来的"不动画面" */
    }
    /* 开关灯只重绘（重排会让灯自己跳位置）；正文里真带出 [clue:] 时才重排并聚焦过去 */
    if (news.length) layout();
    render();
    focusFresh(news);
    return;
  }
  if (t === "choice"){ spawnChoiceNodes(n, cmd); return; }
  if (t === "password"){ openPasswordPop(n); return; }
  if (t === "useItem"){
    const need = cmd.requiredItem;
    const needLabel = labelOf("item", need) || need;
    const have = nodeByKey("item", need);
    if (!have){
      log("「" + esc(n.label) + "」需要「" + esc(needLabel) + "」，但画布上还没有这个节点", "warn");
      noteSeen(cmd.failMessage || "");
      return;
    }
    /* 前置零件（可选）：requires 里列的东西必须**已经装在本节点上** ——
       由带 installs:true 的 useItem 命令成功时写进 n.installed。
       例：唱机得先装上唱针，才放得出黑胶（数据写在唱机的「放入黑胶」命令上）。 */
    const lack = (cmd.requires || []).find(pid => !(n.installed || {})[pid]);
    if (lack){
      const why = plain(cmd.failMessage || ("还缺「" + (labelOf("item", lack) || lack) + "」没装上，现在做不了这件事。"));
      log("「" + esc(n.label) + "」：" + esc(why), "warn");
      noteSeen(cmd.failMessage || "");
      return;
    }
    /* 工具本身要发光却没点亮（手电筒）：先拦下 */
    if (litToolBlocked(have)) return;
    pushHistory();
    log("「" + esc(n.label) + "」使用「" + esc(needLabel) + "」：" + esc(plain(cmd.successMessage || "")), "act");
    gotClues(cmd.successMessage || "");
    noteSeen(cmd.successMessage || "");
    /* 装上的零件：记在节点上（进快照，撤销 / 续档跟着走），后续命令用 requires 认它 */
    if (cmd.installs){ n.installed = Object.assign({}, n.installed); n.installed[need] = true; refreshMusicIcon(); }
    if (cmd.onSuccess) applyPayload(cmd.onSuccess, n.key);
    if (tgConsume.checked && REUSABLE_TOOLS.indexOf(need) < 0) deleteNode("item:" + need);
    settleSelect(settle(), n.key);
    return;
  }
  if (t === "conditional"){
    const conds = cmd.conditions || [];
    const missing = conds.filter(c => !G.captured.has(c.clue));
    if (missing.length){
      const m = missing[0];
      log("「" + esc(n.label) + "」条件不足，缺线索：" + esc(labelOf("clue", m.clue) || m.clue), "warn");
      noteSeen(m.failMessage || "");
      return;
    }
    pushHistory();
    log("「" + esc(n.label) + "」：" + esc(plain(cmd.successMessage || "")), "act");
    noteSeen(cmd.successMessage || "");
    if (cmd.onSuccess) applyPayload(cmd.onSuccess, n.key);
    settleSelect(settle(), n.key);
    return;
  }
  if (t === "reveal"){
    /* 揭示：接触本节点后，把「下一层级」的节点摆到它旁边，并连上实体边
       （区别于场景展开：不产生新的场景节点，只在原地长出一层内容物） */
    pushHistory();
    const text = cmd.successMessage || cmd.value || "";
    log("「" + esc(n.label) + "」：" + esc(plain(text)), "act");
    gotClues(text);
    noteSeen(text);
    const kids = cmd.items || [];
    if (kids.length){
      spawnItems(kids, n.key);
      kids.forEach(iid => link(n.key, "item:" + iid, "entity"));
    }
    settleSelect(settle(), n.key);
    return;
  }
  log("「" + esc(n.label) + "」的命令类型 " + esc(t) + " 暂不支持", "warn");
}

function applyPayload(payload, nearKey){
  if (!payload) return;
  if (payload.items) spawnItems(payload.items, nearKey);
  if (payload.scene && SCENES[payload.scene]){
    const sn = ensureSceneNode(payload.scene, { label: SCENES[payload.scene].title });
    markFresh(sn);
  }
  gotClues(payload.message || payload.text || "");
  noteSeen(payload.message || payload.text || "");
}
function gotClues(text){
  parseTags(text).forEach(t => {
    if (t.kind === "clue" && CLUES[t.id]){
      if (!nodeByKey("clue", t.id)){ const cn = ensureNode("clue", t.id, {}); markFresh(cn); }
      G.captured.add(t.id);
    }
  });
}

/* ============ 光源光晕 ============ */
function paintGlow(){
  const g = document.getElementById("glow");
  if (!g) return;
  const lamp = Object.values(G.nodes).filter(n => n.lit)[0];
  if (!lamp || !lamp.el){ g.style.display = "none"; return; }
  const c = center(lamp.el);
  g.style.display = "block";
  g.style.left = (c.x - 280) + "px";
  g.style.top  = (c.y - 280) + "px";
}

/* ============ 节点上的密码弹窗 ============ */
let pwPop = null, pwTarget = null;
function closePwPop(){ if (pwPop){ pwPop.remove(); pwPop = null; pwTarget = null; } }
function openPasswordPop(n){
  closePwPop();
  const cmd = (ITEMS[n.id].commands || []).find(c => c.type === "password");
  if (!cmd) return;
  const w = makeWindow("LOCK // " + n.label, closePwPop);
  const pop = w.el;
  pop.className = "pw-pop syswin";
  const hint = document.createElement("div");
  hint.className = "pw-title";
  hint.textContent = (cmd.label || "输入密码") + "（四位数字）";
  const row = document.createElement("div");
  row.className = "pw-row";
  const input = document.createElement("input");
  input.id = "pw-in";
  input.maxLength = 4;
  input.placeholder = "····";
  input.setAttribute("inputmode", "numeric");
  const ok = document.createElement("button");
  ok.className = "primary";
  ok.id = "pw-ok";
  ok.textContent = "确定";
  row.appendChild(input); row.appendChild(ok);
  w.body.appendChild(hint); w.body.appendChild(row);
  pop.style.left = (n.x + NODE_W[n.kind] / 2 - 95) + "px";
  pop.style.top  = (n.y + NODE_H[n.kind] + 10) + "px";
  pop.addEventListener("pointerdown", e => e.stopPropagation());
  makeFloatDraggable(pop, true);
  world.appendChild(pop);
  pwPop = pop; pwTarget = n.id;
  ok.addEventListener("click", () => window.__pw(n.id));
  input.addEventListener("keydown", e => { if (e.key === "Enter") window.__pw(n.id); });
  if (input.focus) input.focus();
  selectNode(n.key);
}

/* ============ 选项命令：把选项弹成画布上的节点 ============ */
function spawnChoiceNodes(n, cmd){
  const opts = cmd.options || [];
  if (!opts.length) return;
  pushHistory();
  const added = [];
  opts.forEach((o, i) => {
    if (o.message){ log(esc(plain(o.message)), "sys"); noteSeen(o.message); }
    const r = o.results || {};
    if (r.scene && SCENES[r.scene]){
      const existed = !!nodeByKey(containerKind(r.scene), r.scene);
      const sn = ensureSceneNode(r.scene, { label: SCENES[r.scene].title });
      if (!existed){
        sn.x = n.x + (i - (opts.length - 1) / 2) * 190;
        sn.y = n.y + 110;
        markFresh(sn);
        added.push("「" + sn.label + "」");
      }
      link(n.key, sn.key, "cond");
    } else {
      applyPayload(r, n.key);
    }
  });
  log("「" + esc(n.label) + "」" + esc(cmd.label || "选项") + "：" + (added.length ? "出现 " + esc(added.join("、")) : "选项节点已在画布上"), "act");
  settleSelect(settle(), n.key);
}
