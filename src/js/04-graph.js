/* ============ 图操作 ============ */
function ensureNode(kind, id, opts){
  const key = kind + ":" + id;
  if (G.nodes[key]) return G.nodes[key];
  const o = opts || {};
  /* 不再往节点上写「是不是场景」这类身份 flag：容器与否由 isContainerNode(n) 现算
     （kind + 数据表即可判定），节点只留「位置 / 标签 / 状态」这些真正会变的东西。 */
  G.nodes[key] = {
    key, kind, id,
    label: o.label || labelOf(kind, id) || id,
    x: o.x, y: o.y, fresh: true, unread: true
  };
  return G.nodes[key];
}
/* 建「场景类」节点（场景 / 时间）的唯一入口：kind 由 containerKind() 现算。
   原先 7 处各自写死要建 loc 节点 —— 一旦某个 id 被划成时间节点（config.memoryScenes），
   那些入口会造出 loc 键的节点，而 containerKey() 按 containerKind() 算的是 time 键，
   同一个 id 就分裂成两个节点、状态各记一半。凡是要建场景节点，一律走这里。
   新时刻收录提示也挂在这里：无论哪条路（展开场景带出 / 摘录点名 / 前往 / 组合产出），
   真的新建了 time: 节点就 toast + 档案「新」角标（announceTimeCollected）。 */
function ensureSceneNode(id, opts){
  const key = containerKey(id);
  const isNew = !G.nodes[key];
  const n = ensureNode(containerKind(id), id, opts);
  if (isNew && containerKind(id) === "time" && !(opts && opts.silent)) announceTimeCollected();
  return n;
}
/* 「刚上画布 / 刚被取回」的节点有两件事要记，别混成一个 flag：
     fresh  —— 只给这一轮的镜头聚焦用，render() 末尾就擦（一次性）；
     unread —— 节点上那枚「新」角标，一直挂着，**只由玩家点这个节点**摘（clearFresh）。
   混在一起的后果：任何一次重绘都会顺手把角标洗掉（右键钉住、自动布局、撤销…全中招）。 */
function markFresh(n){ if (n){ n.fresh = true; n.unread = true; } return n; }
function link(aKey, bKey, kind){
  if (!G.nodes[aKey] || !G.nodes[bKey]) return;
  if (edgeBetween(aKey, bKey, kind)) return;
  G.edges.push({ a:aKey, b:bKey, kind });
}

/* 揭示一个容器（场景 / 书桌这类会装东西的物品）的内容。可重复调用，幂等。
   sid 既可以是场景 id，也可以是容器物品的 id —— 键由 containerKind() 决定。 */
function revealScene(sid, silent){
  const s = containerData(sid);
  if (!s) return 0;
  /* 画布上此时只有这一个「未探索」的容器节点？展开后需要重排视野（只平移会溢出）。 */
  const soloBefore = Object.keys(G.nodes).length <= 1;
  const sn = ensureSceneNode(sid, { label: containerTitle(sid), silent });
  const firstTime = !G.explored.has(sid);
  G.explored.add(sid);
  /* G.lastScene 是「玩家最后打开的**场景**」，供 TEC 的 sceneTalks 与相遇人物的 homeScene 兜底：
     展开容器物品（书桌 / 垃圾桶）时不改它，否则 TEC 的上下文会指到一个没有 sceneTalks 的 id 上。 */
  if (SCENES[sid]) G.lastScene = sid;

  const home = { x: sn.x, y: sn.y };
  let added = 0;
  const newKeys = [];

  sceneTags(sid).forEach((t, i) => {
    const existed = !!nodeByKey(t.kind, t.id);
    const en = ensureNode(t.kind, t.id, { x: home.x, y: home.y });
    if (!en.homeScene) en.homeScene = sid;
    if (!existed){ added++; newKeys.push(en.key); }
    link(sn.key, en.key, "entity");
  });

  sceneLocs(sid).forEach(tid => {
    const existed = !!nodeByKey(containerKind(tid), tid);
    const tn = ensureSceneNode(tid, { label: SCENES[tid].title || tid, silent });
    if (!tn.homeScene) tn.homeScene = sid;
    if (!existed){ added++; newKeys.push(tn.key); }
    link(sn.key, tn.key, "move");
  });

  /* 展开容器不写日志：这是全局最高频的动作，日志只留「结果 / 剧情 / 失败」（口径见 log() 上方） */
  unstoreScene(sid);   /* 展开容器时取回存放在这里的节点 */
  const fresh = freshKeys();   /* 抢在 render() 之前：本次新建的 + 从收纳里取回的，都要一起框住 */
  layout();          /* 必须重新布局，否则新节点没有坐标 */
  render();
  /* 新时刻收录提示不在 revealScene 里做：它认「新建了 time: 节点」，而带出日期的入口
     不止「直接揭示日期」一条（展开场景带出 / 摘录点名都绕过这里）——统一挂在 ensureSceneNode。 */
  if (firstTime && !silent){
    /* 先定镜头（fit / 聚焦），再弹叙事卡：卡片用当前视图做「不裁出屏幕」钳制，
       镜头定了之后钳制才准，否则卡片会盖到节点上（实测） */
    if (soloBefore) fit();
    else focusOn([sn.key].concat(fresh, newKeys));
    renarrScene(sid);
  }
  /* 时间节点：它同时是「回忆小剧场」的锚点（时间 × 地点 × 人物，见 05-combine.js）。
     这里的两行提示都会出 —— 「TEC 档案解读」与「回忆组合」是两条互不替代的路。 */
  if (firstTime && !silent && isTimeId(sid))
    log("「" + esc(s.title || sid) + "」可以当一段回忆的锚点（把它拖到一个地点上，再拖一个人物上去）", "sys");
  if (firstTime && !silent && ((CHARS["CHARS_TEC"] || {}).sceneTalks || {})[sid])
    log("「" + esc(s.title || sid) + "」似乎有可以解读的档案（把场景节点拖给 TEC 分析）", "sys");
  updateTecBadge();
  return added;
}

/* 生成一批物品节点（由合成产出）。只把真正新上画布的那些算「新」——
   已经在画布上的旧节点若也被标记成 fresh，会跟着一起进聚焦集合，把镜头拽到别处。 */
function spawnItems(ids, nearKey){
  const src = G.nodes[nearKey];
  const sx = src ? src.x : 900, sy = src ? src.y : 600;
  ids.forEach((iid, i) => {
    const existed = !!G.nodes["item:" + iid];
    const n = ensureNode("item", iid, { x: sx + 60 + i * 26, y: sy + 60 + i * 26 });
    if (existed) n.fresh = false;   /* 本来就在画布上的：不抢镜头，也不重挂「新」角标 */
    n.homeScene = (G.nodes[nearKey] || {}).homeScene || null;
  });
}
