/* ============ 合成：拖 A 到 B ============ */
function attemptCombo(toolKey, targetKey){
  const tool = G.nodes[toolKey], target = G.nodes[targetKey];
  if (!tool || !target || toolKey === targetKey) return;
  if (tool.hidden || target.hidden || tool.stored || target.stored) return;

  /* 发光工具门：需要点亮的工具（手电筒）没打开时照不出东西 —— 先提示，不进历史、不记「已试过」 */
  if (litToolBlocked(tool)) return;

  const triedKey = toolKey + ">" + targetKey;
  pushHistory();

  /* 1) 目标是个场景，且拖过来的容器（场景 / 书桌这类容器物品）文本里正好列着它 → 视为"前往"。
        书桌、垃圾桶是物品，但它们 content 里的 [loc:…]（如书桌的「返回花园」）照样是一条通路。 */
  if (target.kind === "loc" && (tool.kind === "loc" || isContainerNode(tool)) &&
      (sceneLocs(tool.id).indexOf(target.id) >= 0 || sceneLocs(target.id).indexOf(tool.id) >= 0)){
    revealScene(target.id);
    log("前往场景 <b>" + esc(target.label) + "</b>", "act");
    return;
  }
  /* 两个场景之间没有直接通路：这是"走不过去"，明确说清楚，不往下走反应表 */
  if (tool.kind === "loc" && target.kind === "loc"){
    fail(tool, target, "这两个场景之间没有直接通路");
    return;
  }

  /* 2) 目标直接有反应表 */
  let owner = null, hit = lookupReaction(target.kind, target.id, tool.id);
  if (hit) owner = target;

  /* 3) 反向：工具自己是反应表的所有者 */
  if (!hit){
    hit = lookupReaction(tool.kind, tool.id, target.id);
    if (hit) owner = tool;
  }

  /* 3.5) 目标的 useItem 命令正好需要这个工具（如 黑胶 → 唱机）
         这条路径必须和 runCommand 认同一道前置零件门，否则拖上去就把「先装唱针」绕过去了。 */
  if (!hit && target.kind === "item"){
    const ucmds = (ITEMS[target.id] || {}).commands || [];
    const uc = ucmds.find(c => c.type === "useItem" && c.requiredItem === tool.id);
    if (uc){
      const lack = (uc.requires || []).find(pid => !(target.installed || {})[pid]);
      if (lack){
        fail(tool, target, plain(uc.failMessage || ("「" + plain(target.label) + "」还缺零件，现在做不了这件事")));
        G.tried.add(triedKey);
        link(toolKey, targetKey, "tried");
        return;
      }
      hit = { field:"useItem", installs:!!uc.installs,
              react:{ text:uc.successMessage || "", results:uc.onSuccess || {} } };
      owner = target;
    }
  }

  /* 4) 目标是容器（场景 / 书桌这类会装东西的物品）：扫描它收着的对象 */
  if (!hit && isContainerNode(target)){
    for (const t of sceneTags(target.id)){
      const h = lookupReaction(t.kind, t.id, tool.id);
      if (h){ hit = h; owner = nodeByKey(t.kind, t.id) || ensureNode(t.kind, t.id); break; }
    }
  }
  if (!hit && isContainerNode(tool)){
    for (const t of sceneTags(tool.id)){
      const h = lookupReaction(t.kind, t.id, target.id);
      if (h){ hit = h; owner = nodeByKey(t.kind, t.id) || ensureNode(t.kind, t.id); break; }
    }
  }

  if (!hit){
    fail(tool, target, "「" + plain(target.label) + "」对「" + plain(tool.label) + "」没有反应");
    G.tried.add(triedKey);
    link(toolKey, targetKey, "tried");
    return;
  }

  /* 命中 */
  const react = hit.react;
  const text = react.text || react.message || "";
  noteSeen(text);
  const results = react.results || {};
  G.tried.add(triedKey);

  const toolLabel = plain(tool.label), targetLabel = plain(owner ? owner.label : target.label);

  /* 应用结果 */
  const gained = [];
  if (results.scene && SCENES[results.scene]){
    const isNew = !nodeByKey("loc", results.scene);
    const sn = ensureNode("loc", results.scene, { label: SCENES[results.scene].title });
    markFresh(sn);
    if (isNew) link(owner ? owner.key : targetKey, sn.key, "cond");
    gained.push("新场景「" + sn.label + "」");
  }
  const newItems = (results.items || []).concat(react.onSuccess && react.onSuccess.items || []);
  if (newItems.length){
    spawnItems(newItems, owner ? owner.key : targetKey);
    newItems.forEach(i => gained.push("「" + (labelOf("item", i) || i) + "」"));
  }
  /* 文本里的 [clue:x] 自动生成线索节点 */
  parseTags(text).forEach(t => {
    if (t.kind === "clue" && CLUES[t.id] && !nodeByKey("clue", t.id)){
      const cn = ensureNode("clue", t.id, {});
      markFresh(cn);
      link(owner ? owner.key : targetKey, cn.key, "entity");
      gained.push("线索「" + cn.label + "」");
    }
  });
  /* 反应文本里出现的线索同时计入已捕获（与 runCommand 的 gotClues 行为一致） */
  gotClues(text);

  /* 装上的零件：带 installs:true 的 useItem 命令命中后，把工具记在目标节点上（进快照） */
  if (hit.field === "useItem" && hit.installs && owner){
    owner.installed = Object.assign({}, owner.installed);
    owner.installed[tool.id] = true;
  }

  /* 消耗：与角色对话/询问不消耗任何东西 */
  const consume = tgConsume.checked && !(owner && owner.kind === "char");
  const killed = [];
  if (consume){
    const keepTool = REUSABLE_TOOLS.indexOf(tool.id) >= 0 || tool.kind === "clue";
    if (!keepTool){ killed.push(tool); }
    if (target !== tool && !isContainerNode(target) && target.key !== (owner && owner.key)) killed.push(target);
    else if (owner && owner.kind === "item" && owner.id !== tool.id && REUSABLE_TOOLS.indexOf(owner.id) < 0) killed.push(owner);
  }
  const killedSet = {};
  killed.forEach(k => { if (!killedSet[k.key]){ killedSet[k.key] = 1; deleteNode(k.key); } });

  /* 组合结果不弹提示条（成功也不弹）：这属于"节点的动作结果"，效果本来就靠画面自证 ——
     新场景 / 新物品节点会当场冒出来、被消耗的节点会当场消失，再弹一张条等于告知已知信息。
     反应正文与「获得 / 消耗」一并只写进 SYS_LOGS 因果追踪（信息不丢，只是不再打断画面）。 */
  log("组合 <b>" + esc(toolLabel) + "</b> ⇒ <b>" + esc(targetLabel) + "</b>：" + esc(plain(text)) +
      (gained.length ? "　［获得 " + esc(gained.join("、")) + "］" : "") +
      (killed.length ? "　［消耗 " + esc(killed.map(k => plain(k.label)).join("、")) + "］" : ""), "act");

  /* 收尾：重排 → 渲染 → 把这次新长出来的节点（新场景 / 新物品 / 新线索）带到视野中央。
     只框新节点本身：合成常把参与者吃掉，还活着的那个锚点可能在几百像素之外。 */
  const news = settle();
  settleSelect(news, owner ? owner.key : targetKey);
}

function fail(tool, target, msg){
  /* 组合失败同样不弹提示条（"条件不足"就是什么也没发生）；原因只留在 SYS_LOGS 里。 */
  log("组合失败：" + esc(msg), "warn");
}

function deleteNode(key){
  delete G.nodes[key];
  G.edges = G.edges.filter(e => e.a !== key && e.b !== key);
  if (sel === key){ sel = null; setDetailWin(false); }
}

/* ============ 捕获：提取节点的 hiddenClue ============ */
function capturableClues(n){
  const data = nodeData(n);
  if (!data || !data.hiddenClue) return [];
  const ids = new Set(data.hiddenClue.ids || []);
  parseTags(data.hiddenClue.text || "").forEach(t => { if (t.kind === "clue") ids.add(t.id); });
  return [...ids].filter(id => CLUES[id]);
}
function attemptCapture(key){
  const n = G.nodes[key];
  if (!n || n.kind === "clue") return;
  const data = nodeData(n);
  const hc = (data && data.hiddenClue) || {};
  const all = capturableClues(n);
  const fresh = all.filter(id => !G.captured.has(id));
  if (!fresh.length){
    if (all.length){ toast("<b>" + esc(n.label) + "</b><br>线索已经捕获过了", true); log("「" + esc(n.label) + "」没有新的可捕获线索", "warn"); }
    else { toast("<b>" + esc(n.label) + "</b><br>没有可捕获的线索", true); log("「" + esc(n.label) + "」没有可捕获的线索", "warn"); G.tried.add("cap:" + key); }
    return;
  }
  pushHistory();
  fresh.forEach(id => {
    const cn = ensureNode("clue", id, {});
    markFresh(cn);
    link(key, cn.key, "entity");
    G.captured.add(id);
  });
  const text = plain(hc.text || "");
  if (text) showBubble(n, "CAPTURE // " + n.label, text);
  log("捕获「" + esc(n.label) + "」的隐藏线索：" + esc(fresh.map(id => CLUES[id].label).join("、")) + (text ? "——" + esc(text) : ""), "cap");
  settleSelect(settle(), key);
}
