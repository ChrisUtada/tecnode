/* ============ 启动 ============ */
function boot(opts){
  opts = opts || {};
  G = blankGraph();
  closePwPop();
  closeBubble();
  closeNarr();
  /* 注意：TEC 窗、证物袋窗、线索册窗都不在这里关。三扇常驻窗（独立助手 / 随身收纳 / 随身册子），
     只有换案 / 重置才清（resetTec / closeBagWin / closeClueWin 在各自调用点），
     否则「– 收起 → 展开」回访同一案件时会被顺带收掉。 */
  closeGotoWin();
  closeInferWin();
  closePeopleWin();
  closeMapWin();
  closeGardenWin();    /* 花园窗同理：开局 / 换案 / 重置都收（图标由 refreshGardenIcon 按状态重挂） */
  view = { x: 40, y: 20, k: 1 };
  applyView();
  logBox.innerHTML = "";
  setDetailWin(false);
  detailPlaceholder();
  updateCaseChrome();
  /* 续档：直接恢复目标案快照（不重放起始场景的叙事卡） */
  if (opts.fromSnapshot){
    let saved = null;
    try { saved = JSON.parse(opts.fromSnapshot).__view || null; } catch(_){}
    restore(opts.fromSnapshot);
    render();
    /* 存档里带了镜头就原位恢复，否则兜底 fit */
    if (saved && isFinite(saved.x) && isFinite(saved.y) && isFinite(saved.k)){
      view = { x: saved.x, y: saved.y, k: saved.k };
      applyView();
    } else fit();
    refreshBagWin();   /* 袋窗若开着，清单按恢复后的图刷新（G 刚重建过） */
    refreshClueWin();  /* 册窗同理（同样是常驻窗，恢复的图变了） */
    mountInvChip();
    return;
  }
  /* 开局只放一个「未探索」的起始场景节点：里面的东西和叙事卡都要等玩家双击展开时才出现，
     开场画面保持干净，第一次交互就是「双击这个节点」。 */
  ensureNode("loc", START, { label: SCENES[START].title || START, x: 1000, y: 620 });
  G.lastScene = START;   /* 交谈 / TEC 的上下文仍认起始场景，只是画面还没展开 */
  layout();
  render();
  fit();
  refreshBagWin();   /* 同上：全新开局时袋窗若开着，刷成空清单 */
  refreshClueWin();  /* 册窗同理 */
  mountInvChip();
  if (!investigator) openIntro();
  const _cc = caseById(CASE_ID);
  const _code = (_cc ? _cc.code : CASE_ID).replace(/^CASE\s+/, "");
  log("已载入案件 <b>" + esc(_code) + "</b>：双击 <b>场景节点</b> 展开里面的东西，把节点 <b>拖到另一个节点上</b> 组合使用。", "sys");
  if (CASE_ID === "A001") log("提示：先双击「植物学家的花园」展开场景，再双击「书桌」等继续展开，拖动手电筒到黑影上试试。", "sys");
}

/* 测试钩子（供 verify.js 无头驱动） */
window.__combo = (a, b) => attemptCombo(a, b);
window.__talk = key => { const n = G.nodes[key]; if (n) runPrimary(n); };
window.__tec = key => tecConsult(key);
window.__analyze = key => tecAnalyze(key);
window.__analyzeStart = (key, ms) => tecAnalyzeStart(key, ms);   /* 只起任务、不排收尾（测「分析中」态） */
window.__analyzeFinish = key => tecAnalyzeFinish(key);
window.__tecMin = () => minTecWin();
window.__tecState = () => ({ min: tecMin, dot: tecDot, busy: tecBusy, task: tecTask ? tecTask.key : null });
window.__tecTalk = () => tecTalk();
window.__collapse = sid => toggleCollapse(sid);
window.__store = (key, sid) => storeNode(key, sid);
window.__bag = key => bagStore(key);
window.__bagTake = key => bagTake(key);
window.__pin = key => { const n = G.nodes[key]; if (n) togglePin(n); };
window.__bagToggle = () => toggleBagWin();
window.__cap = key => attemptCapture(key);
window.__noteSeen = t => noteSeen(t);
window.__goto = sid => gotoScene(sid);
window.__gotoList = () => heardScenes();
window.__clueToggle = () => toggleClueWin();
window.__clueLedger = () => ledgerList().map(n => ({ key:n.key, id:n.id, label:n.label, sense:(CLUES[n.id] || {}).type }));
window.__ledgerStore = key => ledgerStore(key);
window.__ledgerTake  = key => ledgerTake(key);
window.__ledgerToMatrix = key => ledgerToMatrix(key);   /* 等价于把册中一行拖上推演桌布 */
window.__dropTargets = () => nodeDropTargets();
window.__peopleToggle = () => togglePeopleWin();
window.__roster = () => metChars().map(id => {
  const pin = ROSTER_PINNED.find(p => p.id === id);
  const p = charProgress(id);
  return { id, name:(pin && pin.name) || (CHARS[id] || {}).name || id,
           pinned:!!pin, art:!!rosterAvatar(id), prog:p.prog, total:p.total };
});
window.__mxAssign = (k, s) => assignClue(k, s);
window.__boardTake = (id, sense, cx, cy) => boardTake(id, sense, cx, cy);   /* 等价于把桌布上的 chip 拖出去 */
window.__matrixItems = () => matrixItems().map(n => n.key);
window.__infer = () => executeInference();
window.__inferToggle = () => toggleInferWin();
window.__ensure = (kind, id) => {
  const d = kind === "clue" ? (CLUES[id] || {}) : (ITEMS[id] || {});
  return ensureNode(kind, id, { label: d.label || id });
};
/* 花园（无头验证 / 调试）：plant(cx,cy) 等价于把种子拖进花园（无坐标 = 中部）；plantAt(ms)
   直接种一枚「ms 毫秒前」下种的种子 —— 生长走真实时钟，钩子靠倒拨 at 来测各档位，不用真等三分钟 */
window.__garden = {
  state: () => ({
    seed: gardenOK() ? G.garden.seed : null,
    plots: gardenOK() ? gardenPlots().map(p => ({ stage: gardenStageOf(p), at: p.at, hit: !!p.hit, x: p.x, y: p.y })) : null,
    icon: !!gardenIconEl, win: !!gardenWinEl
  }),
  grant: () => grantGardenSeed(),
  plant: (cx, cy) => gardenPlant(cx, cy),
  plantAt: ms => { if (!gardenOK()) return false;
    const i = gardenPlots().length;
    gardenPlots().push({ at: Date.now() - (ms || 0), hit: ms >= GARDEN_STAGES[4] + 10000,
      x: 24 + (i % 4) * 18, y: 58 });
    refreshGardenWin(); refreshGardenIcon(); return true; },
  open: () => openGardenWin(),
  close: () => closeGardenWin()
};
window.__playStep = () => { if (memoryPlay) advanceMemory(); else if (endingState) playEndingStage(); };
window.__intro = {
  step: () => introState && introState.step,
  name: v => setIntroName(v),
  begin: () => beginQuiz(),
  answer: i => answerQuestion(i),
  /* confirm 会**跳过**选头像那一步直接领证（老调用路径保留）：拿默认头像补上 */
  confirm: () => confirmCard(),
  pick: id => pickIntroAvatar(id),
  confirmPick: () => confirmAvatarStep(),
  avatar: () => introState && introState.avatarId,
  pool: () => avatarUnlocked(),
  finish: () => finishIntro()
};
/* 头像库全局态（无头环境量不到点击，量状态）：池子现算 ⇒ 遇到新人后这里立刻变长 */
window.__avatars = () => ({
  pool: avatarUnlocked(),
  locked: avatarLockedCount(),
  chosen: (investigator && investigator.avatarId) || null,
  win: !!avatarWinEl,
  pick: avatarPickId
});
window.__avatarOpen = () => openAvatarWin();
window.__avatarPick = id => { avatarPickId = id; renderAvatarWin(); };
window.__avatarConfirm = () => confirmAvatarPick();
window.__select = key => key ? selectNode(key) : clearSelection();
window.__closeFloats = () => { closeBubble(); closeDlgWin(); closeNarr(); closePwPop(); };
window.__renarr = sid => renarrScene(sid);
window.__hit   = (cx, cy) => { const e = hitTest(cx, cy, null); return e ? e.dataset.key : null; };
window.__switchCase = id => enterCase(id);
window.__closeCase = () => closeCase();
window.__registerCase = (id, data) => { CASE_DATA[id] = data; };
window.__caseDataOf = id => CASE_DATA[id];
window.__unlockCase = id => unlockCase(id);
window.__excerpt = (target, srcKey) => takeExcerpt(target, srcKey || sel);   /* 等价于点正文里的下划线 */
window.__excerpts = id => excerptsOf(id).map(e => ({ text:e.text, to:e.to }));
window.__caseInfo = () => ({
  id: CASE_ID,
  open: caseOpen,
  held: caseHeld,
  dock: caseDockOn,
  registered: Object.keys(CASE_DATA),
  lastEntered: lastEnteredCase,
  unlocked: progress.unlocked.slice(),
  title: (document.getElementById("case-title") || {}).textContent,
  start: START,
  sceneTitle: (SCENES[START] || {}).title || null
});
window.__dump  = () => ({
  nodes: Object.keys(G.nodes),
  lit: Object.keys(G.nodes).filter(k => G.nodes[k].lit),
  talk: Object.assign({}, G.talkProg),
  tec: { prog: Object.assign({}, G.tecProg), lastScene: G.lastScene },
  hidden: Object.keys(G.nodes).filter(k => G.nodes[k].hidden),
  stored: Object.keys(G.nodes).filter(k => G.nodes[k].stored),
  /* 被收走的节点去哪儿了：BAG / LEDGER / MATRIX（归位的线索离开画布后落在桌布上） */
  storedIn: (() => { const o = {}; for (const k in G.nodes){ if (G.nodes[k].stored) o[k] = G.nodes[k].storedIn; } return o; })(),
  bag: bagItems().map(n => n.key),
  ledger: ledgerItems().map(n => n.key),
  collapsed: [...G.collapsed],
  dim: G._dimKeys || [],
  sel: sel,
  floats: { bubble: !!bubbleEl, dlg: !!dlgWinEl, narr: !!narrEl, pw: !!pwPop, bag: !!bagWinEl, goto: !!gotoWinEl, matrix: !!inferWinEl, tec: !!tecWinEl, clue: !!clueWinEl, people: !!peopleWinEl, detail: detailWinOpen, logs: logWinOpen },
  matrix: JSON.parse(JSON.stringify(G.matrix)),
  endings: [...G.endings],
  garden: G.garden ? { seed: !!G.garden.seed, plots: gardenPlots().filter(Boolean).length } : null,
  gardenIcon: !!gardenIconEl,
  endingOverlay: !!endingState,
  investigator: investigator ? { name: investigator.name, id: investigator.id, sense: investigator.sense,
                                 avatarId: investigator.avatarId || null } : null,
  intro: !!introWinEl,
  edges: G.edges.map(e => e.kind + ":" + e.a + ">" + e.b),
  explored: [...G.explored], captured: [...G.captured], tried: [...G.tried],
  history: history.length,
  /* 镜头（无头环境量不到位移，但能读状态）：拖进拖出的落点换算 / 自动聚焦的对账都要它 */
  view: { x: view.x, y: view.y, k: view.k },
  pos: (() => { const o = {}; for (const k in G.nodes){
    o[k] = { x: Math.round(G.nodes[k].x), y: Math.round(G.nodes[k].y), pinned: !!G.nodes[k].pinned }; } return o; })(),
  /* 装上的零件（唱机 ← 唱针）：节点上的状态，撤销 / 续档跟着走 */
  installed: (() => { const o = {}; for (const k in G.nodes){ if (G.nodes[k].installed) o[k] = Object.keys(G.nodes[k].installed); } return o; })(),
  /* 最近一次自动聚焦的「决定」（无头环境量不到镜头位移，量决定；on=false 表示镜头没动） */
  focus: lastFocus ? { on:lastFocus.on, why:lastFocus.why, keys:(lastFocus.keys || []).slice() } : null
});

boot();
refreshMusicIcon();          /* 还原存档时若唱机已装针，桌面播放器图标要补回来 */
refreshGardenIcon();         /* 还原存档时若捕获过真名（种子未种 / 坛里有花），桌面花园图标要补回来 */

/* 无头验证 / 调试用的音乐钩子（不依赖真实音频设备：只查 DOM 与库状态） */
window.__music = {
  state: () => ({ lib: MUSIC_LIB.map(m => ({ id: m.id, title: m.title })), current: musicCurrent,
    fitted: changjiNeedleFitted(), icon: !!musicIconEl,
    win: !!musicWinEl, min: musicMin,
    time: musicAudio ? Math.round(musicAudio.currentTime * 10) / 10 : 0,
    paused: musicAudio ? musicAudio.paused : true,
    dock: (() => { const d = document.getElementById("music-dock"); return !!(d && d.classList && d.classList.contains("on")); })() }),
  fitNeedle: () => { let c = nodeByKey("item", "ITEMS_changji");
    if (!c) c = ensureNode("item", "ITEMS_changji", { label: "唱机" });
    c.installed = Object.assign({}, c.installed); c.installed["ITEMS_cz"] = true; refreshMusicIcon(); },
  open: () => { if (musicWinEl && musicMin) return restoreMusicWin(); return openMusicWin(); },
  min: () => minMusicWin(),
  restore: () => restoreMusicWin(),
  close: () => closeMusicWin()
};