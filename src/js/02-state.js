/* ============ 图状态 ============ */
let G, history = [], view = {x:0, y:0, k:1};
let sel = null;

function blankGraph(){
  return { nodes:{}, edges:[], explored:new Set(), captured:new Set(), tried:new Set(), talkProg:{}, tecProg:{}, lastScene:null, collapsed:new Set(), seenTexts:[],
    matrix:{vision:[], hearing:[], touch:[], smell:[], taste:[]}, endings:new Set() };
}
function snapshot(){
  const nodes = {};
  /* 节点上只存「图结构 + 真正会变的状态」；容器身份不存（kind + 数据表现算），
     「新」角标（n.unread）也不存 —— 那是"玩家还没点过这个节点"，属于玩家知识，
     跟 seenTexts 一个性质，不随撤销 / 续档回滚（见 restore 里的接力）。 */
  for (const k in G.nodes){ const n = G.nodes[k]; nodes[k] = { key:n.key, kind:n.kind, id:n.id, label:n.label, x:n.x, y:n.y, lit:n.lit, pinned:n.pinned, homeScene:n.homeScene, stored:n.stored, storedIn:n.storedIn, bagFrom:n.bagFrom }; }
  return JSON.stringify({
    nodes: nodes, edges: G.edges,
    explored:[...G.explored], captured:[...G.captured], tried:[...G.tried],
    talkProg: Object.assign({}, G.talkProg),
    tecProg: Object.assign({}, G.tecProg), lastScene: G.lastScene,
    collapsed: [...G.collapsed],
    matrix: JSON.parse(JSON.stringify(G.matrix)), endings: [...G.endings]
  });
}
function pushHistory(){ history.push(snapshot()); if (history.length > 60) history.shift(); }
function restore(str){
  const s = JSON.parse(str);
  /* 玩家知识不随快照回滚：seenTexts（听说过什么）与 unread（还没点过哪些节点）都接力带回新图。
     不接力的话，撤销 / 续档会顺手把全场「新」角标洗掉 —— 和"右键钉一下就没了"是同一类毛病。 */
  const unread = {};
  Object.keys(G.nodes).forEach(k => { if (G.nodes[k].unread) unread[k] = true; });
  G = { nodes:s.nodes, edges:s.edges, explored:new Set(s.explored), captured:new Set(s.captured), tried:new Set(s.tried), talkProg: s.talkProg || {}, tecProg: s.tecProg || {}, lastScene: s.lastScene || null, collapsed: new Set(s.collapsed || []), seenTexts: G.seenTexts || [],
    matrix: s.matrix || {vision:[], hearing:[], touch:[], smell:[], taste:[]}, endings: new Set(s.endings || []) };
  Object.keys(G.nodes).forEach(k => { if (unread[k]) G.nodes[k].unread = true; });
  Object.values(G.nodes).forEach(n => { n.el = null; });
  recomputeHidden();
}
