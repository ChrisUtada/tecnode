/* ============ 图状态 ============ */
let G, history = [], view = {x:0, y:0, k:1};
let sel = null;

function blankGraph(){
  return { nodes:{}, edges:[], explored:new Set(), captured:new Set(), tried:new Set(), talkProg:{}, tecProg:{}, lastScene:null, collapsed:new Set(), seenTexts:[], time:"present",
    /* cardSeen：每个时刻的放映卡是否**自动**放过（记在该时刻名下，切档不重放；见 03-utils.js 的 openTimeCardOnce） */
    cardSeen:{},
    matrix:{vision:[], hearing:[], touch:[], smell:[], taste:[]}, endings:new Set(),
    /* 花园（真名结局的后续温柔）：seed = 执行者头顶还挂着一枚没种下的种子；
       plots = 花坛（{at:下种时刻, hit:开花提示已弹}），长成看真实时间，见 16-cases.js 的花园模块 */
    garden:{ seed:false, plots:[] } };
}
function snapshot(){
  const nodes = {};
  /* 节点上只存「图结构 + 真正会变的状态」；容器身份不存（kind + 数据表现算），
     「新」角标（n.unread）也不存 —— 那是"玩家还没点过这个节点"，属于玩家知识，
     跟 seenTexts 一个性质，不随撤销 / 续档回滚（见 restore 里的接力）。
     `installed` 要存：它是**真的会变的状态**（给唱机装上唱针），装没装上得跟着撤销 / 续档走。
     `place` 同理：时间节点绑上的「发生地点」（回忆小剧场的第一步），撤销要能把这一步退回去。 */
  for (const k in G.nodes){ const n = G.nodes[k]; nodes[k] = { key:n.key, kind:n.kind, id:n.id, label:n.label, x:n.x, y:n.y, lit:n.lit, pinned:n.pinned, homeScene:n.homeScene, stored:n.stored, storedIn:n.storedIn, bagFrom:n.bagFrom, installed:n.installed, place:n.place }; }
  return JSON.stringify({
    nodes: nodes, edges: G.edges,
    explored:[...G.explored], captured:[...G.captured], tried:[...G.tried],
    talkProg: Object.assign({}, G.talkProg),
    tecProg: Object.assign({}, G.tecProg), lastScene: G.lastScene,
    collapsed: [...G.collapsed], time: G.time || "present",
    cardSeen: Object.assign({}, G.cardSeen || {}),
    matrix: JSON.parse(JSON.stringify(G.matrix)), endings: [...G.endings],
    garden: JSON.parse(JSON.stringify(G.garden || { seed:false, plots:[] }))
  });
}
function pushHistory(){ history.push(snapshot()); if (history.length > 60) history.shift(); }
function restore(str){
  const s = JSON.parse(str);
  /* 玩家知识不随快照回滚：seenTexts（听说过什么）与 unread（还没点过哪些节点）都接力带回新图。
     不接力的话，撤销 / 续档会顺手把全场「新」角标洗掉 —— 和"右键钉一下就没了"是同一类毛病。 */
  const unread = {};
  Object.keys(G.nodes).forEach(k => { if (G.nodes[k].unread) unread[k] = true; });
  G = { nodes:s.nodes, edges:s.edges, explored:new Set(s.explored), captured:new Set(s.captured), tried:new Set(s.tried), talkProg: s.talkProg || {}, tecProg: s.tecProg || {}, lastScene: s.lastScene || null, collapsed: new Set(s.collapsed || []), seenTexts: G.seenTexts || [], time: s.time || "present",
    /* cardSeen 是玩家知识：撤销 / 续档不回滚（当前 G 的优先），重开游戏则从存档里接回来 */
    cardSeen: Object.assign({}, s.cardSeen || {}, G.cardSeen || {}),
    matrix: s.matrix || {vision:[], hearing:[], touch:[], smell:[], taste:[]}, endings: new Set(s.endings || []),
    garden: s.garden || { seed:false, plots:[] } };
  /* 旧档迁移：花园字段是「真名结局掉种子」之后才有的。捕获过真名的旧档没有 garden ——
     按结局语义补发那枚种子（种没种下看 plots，不会重复发）；没到过真结局的照默认空。 */
  if (!s.garden){
    const t = (typeof ENDINGS !== "undefined") && ENDINGS.find(e => e.isTrueCapture);
    if (t && G.endings.has(t.id)) G.garden = { seed:true, plots:[] };
  }
  Object.keys(G.nodes).forEach(k => { if (unread[k]) G.nodes[k].unread = true; });
  Object.values(G.nodes).forEach(n => { n.el = null; });
  recomputeHidden();
}
