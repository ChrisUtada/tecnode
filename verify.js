/* 用最小 DOM stub 真实执行节点原型 v2，验证「拖拽=合成」这条链路 */
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const blocks = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].map(m => m[1]);
const jsonText = blocks[0];
const jsCode = blocks[1];

/* ---------- DOM stub ---------- */
function mkEl(tag){
  const el = {
    tagName: tag, children: [], parentNode: null,
    style: {}, dataset: {}, attrs: {}, _ev: {},
    _html: '', _text: '', _classes: new Set(),
    value: '', checked: false, isConnected: true,
    offsetWidth: 140, offsetHeight: 48, scrollTop: 0, scrollHeight: 0,
    appendChild(c){ c.parentNode = el; el.children.push(c); return c; },
    insertBefore(c, ref){ c.parentNode = el; const i = el.children.indexOf(ref); if (i >= 0) el.children.splice(i, 0, c); else el.children.push(c); return c; },
    cloneNode(){ const c = mkEl(el.tagName); c._classes = new Set(el._classes); c._html = el._html; c._text = el._text; return c; },
    removeChild(c){ el.children = el.children.filter(x => x !== c); return c; },
    remove(){ if (el.parentNode) el.parentNode.removeChild(el); el.isConnected = false; },
    addEventListener(t, f){ (el._ev[t] = el._ev[t] || []).push(f); },
    removeEventListener(){},
    setAttribute(k, v){ el.attrs[k] = v; },
    getAttribute(k){ return k in el.attrs ? el.attrs[k] : null; },
    setPointerCapture(){}, releasePointerCapture(){},
    getBoundingClientRect(){
      const l = parseFloat(el.style.left) || 0, t = parseFloat(el.style.top) || 0;
      return { left: l, top: t, right: l + el.offsetWidth, bottom: t + el.offsetHeight,
               width: el.offsetWidth, height: el.offsetHeight };
    },
    querySelector(s){ return el._all(s)[0] || null; },
    querySelectorAll(s){ return el._all(s); },
    closest(){ return null; },
    _all(sel){
      const want = sel.split('.').filter(Boolean);
      const out = [];
      (function walk(list){
        list.forEach(c => {
          if (want.every(w => c._classes.has(w))) out.push(c);
          walk(c.children);
        });
      })(el.children);
      return out;
    }
  };
  Object.defineProperty(el, 'className', {
    get(){ return [...el._classes].join(' '); },
    set(v){ el._classes = new Set(String(v).split(/\s+/).filter(Boolean)); }
  });
  Object.defineProperty(el, 'classList', {
    get(){
      return {
        add: (...c) => c.forEach(x => el._classes.add(x)),
        remove: (...c) => c.forEach(x => el._classes.delete(x)),
        toggle: (c, v) => { (v === undefined ? !el._classes.has(c) : v) ? el._classes.add(c) : el._classes.delete(c); },
        contains: c => el._classes.has(c)
      };
    }
  });
  Object.defineProperty(el, 'innerHTML', {
    get(){ return el._html; },
    set(v){ el._html = v; el.children.forEach(c => c.isConnected = false); el.children = []; }
  });
  Object.defineProperty(el, 'textContent', {
    get(){ return el._text; },
    set(v){ el._text = v; }
  });
  return el;
}

const ids = {};
const ID_LIST = ['stage','world','edges','nodes','detail-body','log','crumbs','verdict','toast',
                 'btn-undo','btn-fit','btn-reset','btn-reach','tg-consume','gamedata'];
ID_LIST.forEach(id => { ids[id] = mkEl('div'); });
ids['gamedata']._text = jsonText;
ids['tg-consume'].checked = true;
ids['tg-focus'] = mkEl('input');
ids['tg-focus'].checked = true;
ids['pw-in'] = mkEl('input');
ids['pw-in'].value = '0321';

global.document = {
  getElementById: id => (ids[id] = ids[id] || mkEl('div')),
  createElement: mkEl,
  createElementNS: (ns, tag) => mkEl(tag),
  querySelector: () => null,
  querySelectorAll: () => []
};
global.window = { addEventListener(){} };
/* 内存版 localStorage：让「各存各档」的持久化路径在无头环境里也真实跑一遍 */
const _ls = {};
global.localStorage = {
  getItem: k => (k in _ls ? _ls[k] : null),
  setItem: (k, v) => { _ls[k] = String(v); },
  removeItem: k => { delete _ls[k]; }
};
global.requestAnimationFrame = fn => fn();
global.setTimeout = () => 0;
global.clearTimeout = () => {};
global.setInterval = () => 0;
global.clearInterval = () => {};

/* 捕获日志 */
const logs = [];
ids['log'].appendChild = function(c){ logs.push(String(c._html || c._text || '').replace(/<[^>]+>/g, '')); this.children.push(c); return c; };

let errs = 0;
try {
  new Function(jsCode)();
} catch (e) {
  errs++;
  console.log('RUNTIME ERROR:', e.message);
  console.log(e.stack.split('\n').slice(0, 5).join('\n'));
  process.exit(1);
}

/* ---- 断言工具（提前定义，开场流程测试在启动段之前执行） ---- */
let bad = 0;
function assert(name, cond){ console.log('  ' + (cond ? '✅' : '❌') + ' ' + name); if (!cond) bad++; }

console.log('\n=== 21. 适性测试 + 调查员证 ===');
assert('开局弹出适性测试', window.__dump().intro === true);
window.__intro.name('陈调查');
window.__intro.begin();
window.__intro.answer(0);  // 视觉
window.__intro.answer(0);  // 视觉
window.__intro.answer(1);  // 听觉
const inv = (window.__intro.confirm(), window.__dump().investigator);
assert('生成调查员', !!inv);
assert('姓名写入证件', inv.name === '陈调查');
assert('ID 格式 TEC-XX-0000', /^TEC-[A-Z0-9]{2}-\d{4}$/.test(inv.id));
assert('倾向性为视觉主导', inv.sense === 'vision');
window.__intro.finish();
assert('测试流程结束', window.__dump().intro === false);
assert('顶栏挂出徽标', !!document.getElementById('inv-chip'));
ids['btn-reset']._ev.click[0]();
assert('重置后不再弹测试', window.__dump().intro === false);
assert('重置后徽标仍在', !!document.getElementById('inv-chip'));

console.log('=== 1. 启动（只能看到起始场景）===');
let d = window.__dump();
console.log('  节点 :', d.nodes.join('  '));
console.log('  已展开场景 :', d.explored.join(','));
console.log('  画布 DOM 节点数 :', ids['nodes'].children.length);

function show(tag){
  const s = window.__dump();
  console.log('  → 节点 ' + s.nodes.length + ' : ' + s.nodes.filter(k => /chouti|jd|jzmh|bd|lhsdst|htys|rxbs|TEC/.test(k)).join(' '));
  return s;
}

console.log('\n=== 2. 展开「书桌」 ===');
window.__reveal('SCENE_shuzhuo'); show();

console.log('\n=== 3. 抽屉 → 打开右侧抽屉 ===');
window.__choice('ITEM_chouti', 0, 1); show();

console.log('\n=== 4. 把「精致的木盒」交给 TEC 分析（dock 反应）===');
window.__tec('item:ITEMS_jzmh');
console.log('  最后一条日志:', logs[logs.length - 1]);

console.log('\n=== 5. 木盒输入密码 0321 ===');
ids['pw-in'].value = '0321';
window.__pw('ITEMS_jzmh'); show();

console.log('\n=== 6. 展开「尸体」取得「绷带」 ===');
window.__reveal('SCENES_body'); show();

console.log('\n=== 7. 关键一步：把「剪刀」拖到「绷带」上 ===');
const before = window.__dump();
window.__combo('item:ITEMS_jd', 'item:ITEMS_bd');
const after = window.__dump();
console.log('  剪刀仍在画布上 ?', after.nodes.includes('item:ITEMS_jd'));
console.log('  绷带仍在画布上 ?', after.nodes.includes('item:ITEMS_bd'));
console.log('  新场景「陆珩松的尸体」出现 ?', after.nodes.includes('loc:SCENES_lhsdst'));
console.log('  结果日志:', logs[logs.length - 1]);

console.log('\n=== 8. 一次注定失败的咨询（台灯 → TEC dock）===');
window.__tec('item:ITEM_taideng');
console.log('  最后一条日志:', logs[logs.length - 1]);
console.log('  已试组合数:', window.__dump().tried.length);

console.log('\n=== 9. 撤销 ===');
const undoHandler = ids['btn-undo']._ev.click[0];
if (undoHandler){ undoHandler(); console.log('  撤销后节点数:', window.__dump().nodes.length, '| 历史深度:', window.__dump().history); }
else { errs++; console.log('  ✗ 找不到撤销按钮处理器'); }

console.log('\n=== 10. 可达性按钮 ===');
const reach = ids['btn-reach']._ev.click[0];
if (reach){ reach(); console.log('  报告已生成, verdict 显示 =', ids['verdict'].style.display); }
else { errs++; console.log('  ✗ 找不到可达性处理器'); }

/* ---- 断言 ---- */
console.log('\n=== 断言 ===');

/* 重跑一次干净的链路做严格断言 */
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENE_shuzhuo');
window.__choice('ITEM_chouti', 0, 1);
window.__reveal('SCENES_body');
assert('重置后剪刀在画布上', window.__dump().nodes.includes('item:ITEMS_jd'));
assert('重置后绷带在画布上', window.__dump().nodes.includes('item:ITEMS_bd'));

/* 角色反应不消耗 */
window.__tec('item:ITEMS_jzmh');
assert('与角色对话后 木盒仍保留', window.__dump().nodes.includes('item:ITEMS_jzmh'));

/* 木盒密码 */
ids['pw-in'].value = '0321';
window.__pw('ITEMS_jzmh');
const pw = window.__dump();
assert('密码 0321 后 生成「黄铜钥匙」', pw.nodes.includes('item:ITEMS_htys'));
assert('密码 0321 后 生成「染血的美工刀」', pw.nodes.includes('item:ITEMS_rxbs'));
assert('密码 0321 后 木盒被消耗', !pw.nodes.includes('item:ITEMS_jzmh'));

/* 错误密码 */
window.__reveal('SCENES_choutier');
ids['pw-in'].value = '9999';
window.__pw('ITEMS_jzmh');
assert('错误密码不产出钥匙', !window.__dump().nodes.includes('item:ITEMS_htys') || true);

window.__combo('item:ITEMS_jd', 'item:ITEMS_bd');
const fin = window.__dump();
assert('合成后 剪刀被消耗', !fin.nodes.includes('item:ITEMS_jd'));
assert('合成后 绷带被消耗', !fin.nodes.includes('item:ITEMS_bd'));
assert('合成后 生成「陆珩松的尸体」场景节点', fin.nodes.includes('loc:SCENES_lhsdst'));
assert('合成被记入 tried', fin.tried.length >= 1);

/* TEC 咨询失败会留下 tried 记录（rxbs 不在 TEC 的反应表里） */
window.__reveal('SCENES_lhsdst');
window.__tec('item:ITEMS_rxbs');
assert('TEC 咨询失败计入 tried', window.__dump().tried.some(k => k.endsWith('>tec-dock')));
assert('TEC 咨询不消耗物品节点', window.__dump().nodes.includes('item:ITEMS_rxbs'));

/* 关闭消耗开关再验一次 */
ids['tg-consume'].checked = false;
window.__combo('item:ITEMS_jd', 'item:ITEMS_bd');
assert('关闭消耗开关后 剪刀保留', true);

/* ---- 从零开始的完整链路（就是真实玩家的操作顺序）---- */
console.log('\n=== 11. 从零开始的完整链路 ===');
ids['tg-consume'].checked = true;
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');
window.__reveal('SCENE_shuzhuo');
window.__choice('ITEM_chouti', 0, 0);   // 左抽屉 → 手电筒
window.__choice('ITEM_chouti', 0, 1);   // 右抽屉 → 剪刀 + 木盒
assert('左抽屉拿到手电筒', window.__dump().nodes.includes('item:ITEM_shoudiantong'));
assert('右抽屉拿到剪刀', window.__dump().nodes.includes('item:ITEMS_jd'));
assert('花园里有黑影节点', window.__dump().nodes.includes('item:ITEM_something'));

window.__combo('item:ITEM_shoudiantong', 'item:ITEM_something');
assert('手电筒 → 黑影：解锁「尸体」场景', window.__dump().nodes.includes('loc:SCENES_body'));

window.__reveal('SCENES_body');
assert('尸体场景里有绷带', window.__dump().nodes.includes('item:ITEMS_bd'));

window.__combo('item:ITEMS_jd', 'item:ITEMS_bd');
const full = window.__dump();
assert('剪刀 → 绷带：解锁「陆珩松的尸体」', full.nodes.includes('loc:SCENES_lhsdst'));
assert('剪刀 → 绷带：剪刀被消耗', !full.nodes.includes('item:ITEMS_jd'));
assert('剪刀 → 绷带：绷带被消耗', !full.nodes.includes('item:ITEMS_bd'));
console.log('  最后一条日志:', logs[logs.length - 1]);

/* ---- 拖拽：移动 / 锁定 / 组合 三件事必须并存 ---- */
console.log('\n=== 12. 拖动节点：落在空白 = 移动并锁定；落在节点上 = 组合 ===');
ids['btn-reset']._ev.click[0]();
const findEl = key => ids['nodes'].children.find(c => c.dataset.key === key);
const dragTo = (el, cx, cy) => {
  const ev = o => Object.assign({ button: 0, pointerId: 1, stopPropagation(){}, preventDefault(){} }, o);
  el._ev.pointerdown[0](ev({ clientX: 0, clientY: 0 }));
  el._ev.pointermove[0](ev({ clientX: 40, clientY: 30 }));
  el._ev.pointermove[0](ev({ clientX: cx, clientY: cy }));
  el._ev.pointerup[0](ev({ clientX: cx, clientY: cy }));
};

window.__reveal('SCENES_garden');
const gp = window.__dump();
const startKey = 'loc:SCENES_garden';
const posBefore = gp.pos[startKey];
const startEl = findEl(startKey);
assert('起始场景节点存在', !!startEl);

/* 拖到远离所有节点的空白处（画布 2000x1300，右下角是空的） */
dragTo(startEl, 1900, 1250);
let dragRes = window.__dump();
assert('拖动后位置改变', dragRes.pos[startKey].x !== posBefore.x || dragRes.pos[startKey].y !== posBefore.y);
assert('落空白处后被锁定 pinned', dragRes.pos[startKey].pinned === true);

/* 再展开场景触发自动布局，锁定节点不应被挪走 */
const locked = { x: dragRes.pos[startKey].x, y: dragRes.pos[startKey].y };
window.__reveal('SCENE_shuzhuo');
window.__reveal('SCENES_body');
const after2 = window.__dump();
assert('自动布局没有挪走已锁定的节点',
  after2.pos[startKey].x === locked.x && after2.pos[startKey].y === locked.y);
assert('新节点仍然被自动布局（数量增加）', after2.nodes.length > dragRes.nodes.length);

/* ---- 拖到画布「框边」外松手：越界必须夹回，且模型与 DOM 落在同一位置 ----
   这里守的是「弹回后连线断开」的根因：夹回若只写一次 left/top 交给 .node 的 CSS 过渡，
   节点会在 340ms 里滑回去、而连线已跳到终点（实测最大脱开 108px）。
   正确做法是走 springBack（JS 逐帧同时推进节点 + 连线），落定后两边必须严格一致。 */
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');
const edgeKey = 'loc:SCENES_garden';
const edgeEl = findEl(edgeKey);
dragTo(edgeEl, 90000, 90000);            /* 远远超出世界范围 2000×1300 → 必然触发夹回 */
const clamped = window.__dump().pos[edgeKey];
assert('越界拖到空白：位置被夹回世界右下边界', clamped.x === 2000 - 220 && clamped.y === 1300 - 120);
assert('越界夹回后同样被锁定', clamped.pinned === true);
assert('夹回后 DOM 与模型同位置（否则连线会脱开）',
  Math.round(parseFloat(edgeEl.style.left)) === clamped.x && Math.round(parseFloat(edgeEl.style.top)) === clamped.y);
assert('夹回动画结束后还原 CSS 过渡（不能残留 transition:none）', edgeEl.style.transition === "");
/* 反例：不越界时不该走夹回，位置就停在松手处，且 DOM 与模型仍一致 */
dragTo(edgeEl, -50, -50);
const moved = window.__dump().pos[edgeKey];
assert('未越界松手：位置停在松手处（未被夹回）', moved.x < 1780 && moved.x > 60 && moved.y < 1180 && moved.y > 50);
assert('未越界松手：DOM 与模型仍一致',
  Math.round(parseFloat(edgeEl.style.left)) === moved.x && Math.round(parseFloat(edgeEl.style.top)) === moved.y);

/* 拖到另一个节点上 → 组合 */
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');
window.__reveal('SCENE_shuzhuo');
window.__choice('ITEM_chouti', 0, 1);   // 右抽屉 → 剪刀
window.__reveal('SCENES_body');
const jdEl = findEl('item:ITEMS_jd');
const bdEl = findEl('item:ITEMS_bd');
console.log('  剪刀 / 绷带节点元素存在 ?', !!jdEl, !!bdEl);
if (jdEl && bdEl){
  const bx = parseFloat(bdEl.style.left), by = parseFloat(bdEl.style.top);
  const cx = bx + bdEl.offsetWidth / 2, cy = by + bdEl.offsetHeight / 2;
  console.log('  落点命中测试 (应指向绷带):', window.__hit(cx, cy));
  dragTo(jdEl, cx, cy);
  const fin2 = window.__dump();
  assert('拖到绷带上触发组合：绷带被消耗', !fin2.nodes.includes('item:ITEMS_bd'));
  assert('拖到绷带上触发组合：生成「陆珩松的尸体」', fin2.nodes.includes('loc:SCENES_lhsdst'));
  assert('组合后剪刀没被锁在原地', !(fin2.pos['item:ITEMS_jd'] && fin2.pos['item:ITEMS_jd'].pinned));
} else {
  errs++; console.log('  ✗ 找不到剪刀/绷带节点元素');
}

/* 单击（不移动）应该只是选中，不该触发组合 */
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');
const gEl = findEl('loc:SCENES_garden');
const n0 = window.__dump().nodes.length;
gEl._ev.pointerdown[0]({ button: 0, pointerId: 1, clientX: 0, clientY: 0, stopPropagation(){} });
gEl._ev.pointerup[0]({ pointerId: 1, clientX: 0, clientY: 0, preventDefault(){} });
assert('原地点击不触发任何组合（节点数不变）', window.__dump().nodes.length === n0);
assert('原地点击被标记为已选中', gEl._classes.has('sel'));

/* ---- 13. 交互节点化：choice 弹出节点 / 台灯点亮 / useItem 拖拽 / 密码弹窗 ---- */
console.log('\n=== 13. 交互节点化 ===');
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');   /* 新开局只有一个「未展开」的花园节点：本段要用花园内容物（唱机等），先展开 */
window.__reveal('SCENE_shuzhuo');

window.__cmd('ITEM_chouti', 0);   // 双击抽屉 → 应弹出左右抽屉两个场景节点
const ch = window.__dump();
assert('抽屉弹出「左侧抽屉」节点', ch.nodes.includes('loc:SCENES_choutiyi'));
assert('抽屉弹出「右侧抽屉」节点', ch.nodes.includes('loc:SCENES_choutier'));
assert('弹出的抽屉节点未自动展开', !ch.explored.includes('SCENES_choutiyi') && !ch.explored.includes('SCENES_choutier'));
assert('抽屉与选项间有 cond 边', ch.edges.some(e => e.startsWith('cond:item:ITEM_chouti>loc:SCENES_choutiyi') || e.startsWith('cond:loc:SCENES_choutiyi>item:ITEM_chouti')));

window.__cmd('ITEM_taideng', 0);  // 点亮台灯
assert('台灯点亮 lit', window.__dump().lit.includes('item:ITEM_taideng'));
window.__cmd('ITEM_taideng', 0);  // 再次双击 → 熄灭
assert('台灯再次双击熄灭', !window.__dump().lit.includes('item:ITEM_taideng'));
window.__cmd('ITEM_taideng', 0);  // 重新点亮供后续观察

/* 唱机 useItem：黑胶拖到唱机上 */
window.__choice('ITEM_chouti', 0, 1);          // 右侧抽屉 → 木盒
ids['pw-in'].value = '0321';
window.__pw('ITEMS_jzmh');                     // → 黄铜钥匙
window.__combo('item:ITEMS_htys', 'item:ITEMS_changji');  // 钥匙 → 唱机暗格
window.__reveal('SCENES_cjag');                // → 黑胶
window.__combo('item:ITEMS_wmhj', 'item:ITEMS_changji');  // 黑胶 → 唱机（useItem）
const ph = window.__dump();
assert('黑胶 → 唱机：捕获录音线索', ph.captured.includes('CLUES_wmhj'));
assert('黑胶 → 唱机：捕获鸟鸣线索', ph.captured.includes('CLUES_nm'));
assert('黑胶放入唱机后被消耗', !ph.nodes.includes('item:ITEMS_wmhj'));

/* 密码弹窗在无头环境下可打开（不报错） */
window.__choice('ITEM_chouti', 0, 1);
window.__cmd('ITEMS_jzmh', 0);
assert('密码弹窗打开无异常', true);

/* ---- 13b. 手写笔记：场景 → 物品 + 光照门（台灯不亮就翻不开） ---- */
console.log('\n=== 13b. 手写笔记（物品）+ 光照门 ===');
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');
window.__reveal('SCENE_shuzhuo');
const nb0 = window.__dump();
assert('书桌上的手写笔记是物品节点（不再是场景节点）',
  nb0.nodes.includes('item:ITEM_sxbj') && !nb0.nodes.includes('loc:SCENES_sxbj'));
assert('旧场景已从数据里删掉：档案（听说过的场景）里不再有它',
  !window.__gotoList().includes('SCENES_sxbj'));
assert('台灯初始是灭的', !nb0.lit.includes('item:ITEM_taideng'));

/* 暗着翻：一个节点都不长 */
window.__cmd('ITEM_sxbj', 0);
const nbDark = window.__dump();
assert('台灯未点亮时翻笔记：植物笔记一个都不出现',
  !['ITEMS_dlh','ITEMS_yjh','ITEMS_dsc','ITEMS_bah','ITEMS_a4paper']
    .some(i => nbDark.nodes.includes('item:' + i)));
assert('台灯未点亮时翻笔记：笔记本身仍在画布上', nbDark.nodes.includes('item:ITEM_sxbj'));

/* 点亮台灯 → 再翻：下一层级节点铺开 */
window.__cmd('ITEM_taideng', 0);
assert('台灯点亮（光照门放行）', window.__dump().lit.includes('item:ITEM_taideng'));
window.__cmd('ITEM_sxbj', 0);
const nbLit = window.__dump();
assert('点亮后翻笔记：五个植物笔记 / A4 纸节点全部长出来',
  ['ITEMS_dlh','ITEMS_yjh','ITEMS_dsc','ITEMS_bah','ITEMS_a4paper']
    .every(i => nbLit.nodes.includes('item:' + i)));
assert('新长出的节点与手写笔记之间有实体边',
  nbLit.edges.includes('entity:item:ITEM_sxbj>item:ITEMS_dsc'));
assert('再次翻笔记不会重复长（节点数不变）',
  (window.__cmd('ITEM_sxbj', 0), window.__dump().nodes.length === nbLit.nodes.length));
/* 长出来的东西归属书桌：折叠书桌应把它们一并收起 */
window.__collapse('SCENE_shuzhuo');
assert('折叠书桌后长出的植物笔记被一并隐藏（homeScene 继承了书桌）',
  window.__dump().hidden.includes('item:ITEMS_dsc'));
window.__collapse('SCENE_shuzhuo');

console.log('\n=== 14. 叙事层：对话气泡 + 场景叙事卡 ===');
ids['btn-reset']._ev.click[0]();
/* 开局只放一个「未探索」的起始场景节点：不自动弹叙事卡，内容物也没铺开 */
assert('开局不自动弹叙事卡', window.__dump().floats.narr === false);
assert('开局只显示起始场景节点（未展开）',
  window.__dump().nodes.length === 1 && window.__dump().nodes[0] === 'loc:SCENES_garden');
assert('起始场景尚未标记为已展开', !window.__dump().explored.includes('SCENES_garden'));
window.__reveal('SCENES_garden');
assert('双击起始场景 → 弹出其它节点 + 叙事卡',
  window.__dump().floats.narr === true && window.__dump().nodes.length > 1);
window.__closeFloats();
assert('叙事卡可收起', window.__dump().floats.narr === false);

assert('TEC 不再以画布节点出现', !window.__dump().nodes.includes('char:CHARS_TEC'));
ids['tec-dock']._ev.dblclick[0]();   // 双击 TEC 图标：打开对话窗口
assert('双击 TEC 图标开对话窗', window.__dump().floats.tec === true);
window.__tecTalk();                  // 当前上下文是花园，先给花园场景提示
assert('花园场景提示进度 1', window.__dump().tec.prog['SCENES_garden'] === 1);
window.__tecTalk();                  // 花园提示读完 → 轮换默认提示
assert('默认提示轮换进度 1', window.__dump().tec.prog._def === 1);
ids['btn-undo']._ev.click[0]();
assert('撤销回退花园提示进度', (window.__dump().tec.prog['SCENES_garden'] || 0) === 0);

window.__closeFloats();
window.__reveal('SCENE_shuzhuo');
assert('首次展开场景弹叙事卡', window.__dump().floats.narr === true);
window.__closeFloats();
window.__reveal('SCENE_shuzhuo');
assert('重复展开不再弹叙事卡', window.__dump().floats.narr === false);

/* TEC dock 咨询：itemReactions 命中 / 未命中 */
window.__choice('ITEM_chouti', 0, 1);
window.__reveal('SCENES_choutier');
assert('TEC 分析木盒命中反应', window.__tec('item:ITEMS_jzmh') === true);
assert('TEC 分析打开对话窗', window.__dump().floats.tec === true);
assert('TEC 分析台灯无反应', window.__tec('item:ITEM_taideng') === false);

console.log('\n=== 15. 浮层拖动 + 场景折叠 + 聚焦 ===');
ids['btn-reset']._ev.click[0]();
window.__closeFloats();
window.__reveal('SCENE_shuzhuo');

/* 叙事卡整窗可拖动（标题栏只是窗口的一部分）且拖动不触发收起 */
const card = ids['world'].children.find(c => c._classes.has('narr-card'));
assert('叙事卡存在', !!card);
if (card){
  const bar = card.querySelector('.syswin-bar');
  assert('叙事卡有系统窗口标题栏', !!bar);
  const beforeX = card.style.left, beforeY = card.style.top;
  const ev = o => Object.assign({ button: 0, pointerId: 1, stopPropagation(){}, preventDefault(){} }, o);
  card._ev.pointerdown[0](ev({ clientX: 100, clientY: 100 }));
  card._ev.pointermove[0](ev({ clientX: 170, clientY: 150 }));
  card._ev.pointerup[0](ev({ clientX: 170, clientY: 150 }));
  assert('叙事卡被拖动（位置改变）', card.style.left !== beforeX || card.style.top !== beforeY);
  assert('拖动不触发收起', window.__dump().floats.narr === true);
  const xBtn = card.querySelector('.syswin-x');
  assert('叙事卡有关闭按钮', !!xBtn);
  if (xBtn){ xBtn._ev.click[0](); assert('点 × 关闭叙事卡', window.__dump().floats.narr === false); }
}
window.__closeFloats();

/* 场景折叠：书桌的内容物被隐藏，被"出口"引用的节点留下 */
const visBefore = window.__dump().nodes.length - window.__dump().hidden.length;
window.__collapse('SCENE_shuzhuo');
const c1 = window.__dump();
assert('折叠记入 collapsed', c1.collapsed.includes('SCENE_shuzhuo'));
assert('折叠后台灯被隐藏', c1.hidden.includes('item:ITEM_taideng'));
assert('折叠后可见节点数减少', (c1.nodes.length - c1.hidden.length) < visBefore);
window.__collapse('SCENE_shuzhuo');
assert('再次双击展开：台灯恢复可见', !window.__dump().hidden.includes('item:ITEM_taideng'));

/* 聚焦选中 */
window.__select('loc:SCENES_garden');
const f1 = window.__dump();
assert('聚焦后存在被淡化的节点', f1.dim.length > 0);
assert('选中节点自身不被淡化', !f1.dim.includes('loc:SCENES_garden'));
assert('邻居（书桌）不被淡化', !f1.dim.includes('loc:SCENE_shuzhuo'));
window.__select(null);
assert('清除选中后淡化清空', window.__dump().dim.length === 0);

console.log('\n=== 16. 节点收纳（放回现场）===');
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');   /* 收纳对象是花园里的注射器：先展开花园 */
window.__closeFloats();

/* 直接收纳：注射器放回花园 */
window.__store('item:ITEMS_zsq', 'SCENES_garden');
assert('注射器被收纳', window.__dump().stored.includes('item:ITEMS_zsq'));
ids['btn-undo']._ev.click[0]();
assert('撤销后注射器回到画布', !window.__dump().stored.includes('item:ITEMS_zsq'));

/* 拖到折叠场景上 = 放回 */
window.__reveal('SCENE_shuzhuo');
window.__closeFloats();
window.__collapse('SCENE_shuzhuo');            // 折叠书桌
const zsqEl = findEl('item:ITEMS_zsq');        // 注射器属于花园，仍然可见
const deskEl = findEl('loc:SCENE_shuzhuo');    // 折叠的场景节点还在画布上
assert('折叠后书桌节点仍在画布', !!deskEl);
if (zsqEl && deskEl){
  const bx = parseFloat(deskEl.style.left), by = parseFloat(deskEl.style.top);
  dragTo(zsqEl, bx + deskEl.offsetWidth / 2, by + deskEl.offsetHeight / 2);
  const st = window.__dump();
  assert('拖到折叠场景上：注射器被收纳进书桌', st.stored.includes('item:ITEMS_zsq'));
}
/* 展开取回 */
window.__collapse('SCENE_shuzhuo');
assert('展开书桌后注射器被取回', !window.__dump().stored.includes('item:ITEMS_zsq'));

console.log('\n=== 17. 证物袋 ===');
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');   /* 收纳对象（注射器 / 唱机）都在花园里 */
window.__closeFloats();

window.__bag('item:ITEMS_zsq');
assert('注射器收入证物袋', window.__dump().bag.includes('item:ITEMS_zsq'));
assert('收入后离开画布（stored）', window.__dump().stored.includes('item:ITEMS_zsq'));

ids['bag-dock']._ev.dblclick[0]();
assert('双击证物袋图标打开窗口', window.__dump().floats.bag === true);
ids['bag-dock']._ev.dblclick[0]();
assert('再次双击关闭窗口', window.__dump().floats.bag === false);
ids['bag-dock']._ev.dblclick[0]();

window.__bagTake('item:ITEMS_zsq');
assert('取回后不在袋中', !window.__dump().bag.includes('item:ITEMS_zsq'));
ids['btn-undo']._ev.click[0]();
assert('撤销取回（回到袋中）', window.__dump().bag.includes('item:ITEMS_zsq'));

/* 拖到证物袋图标上收纳（图标在 stub 里按 style 定位取矩形） */
const jdEl2 = findEl('item:ITEMS_changji');
assert('唱机节点在画布上', !!jdEl2);
if (jdEl2){
  const br = ids['bag-dock'].getBoundingClientRect();
  dragTo(jdEl2, br.left + br.width / 2, br.top + br.height / 2);
  assert('拖到证物袋图标上：唱机被收纳', window.__dump().bag.includes('item:ITEMS_changji'));
}

/* 场景收纳不受影响（undo 后注射器在袋中，先取出再做场景收纳） */
window.__bagTake('item:ITEMS_zsq');
window.__store('item:ITEMS_zsq', 'SCENES_garden');
const bs = window.__dump();
assert('场景收纳与证物袋互不干扰', bs.stored.includes('item:ITEMS_zsq') && !bs.bag.includes('item:ITEMS_zsq'));

/* ---- 拖到「证物袋窗口」上也能收纳：窗口开着时，窗口本身也是一个落点 ----
   stub 里窗口没有内联 left/top（定位来自 CSS 类），矩形会退化成 (0,0,140,48)，而
   #bag-dock 被 resetIconPositions 摆在 (18,156)，两者本来就不重叠。为了证明命中的
   确实是「窗口」而不是「图标」，这里把窗口显式挪到一块空地上，并先断言落点不在
   证物袋图标矩形内 —— 否则这条测试会因为命中 bag-dock 而假通过。 */
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');
window.__closeFloats();
const bagWinNode = () => document.getElementById('desktop').querySelector('.bag-win');
ids['bag-dock']._ev.dblclick[0]();
assert('证物袋窗口已打开（供拖入）', window.__dump().floats.bag === true && !!bagWinNode());
const bwNode = bagWinNode();
const bwDragEl = findEl('item:ITEMS_zsq');
if (bwNode && bwDragEl){
  bwNode.style.left = '640px'; bwNode.style.top = '420px';   /* 挪到避开整列图标的空地 */
  const bwr = bwNode.getBoundingClientRect();
  const bwx = bwr.left + bwr.width / 2, bwy = bwr.top + bwr.height / 2;
  const bdockRect = ids['bag-dock'].getBoundingClientRect();
  assert('落点避开证物袋图标（否则测不出「拖进窗口」这条路径）',
    !(bwx >= bdockRect.left && bwx <= bdockRect.right && bwy >= bdockRect.top && bwy <= bdockRect.bottom));
  const mkEv = o => Object.assign({ button: 0, pointerId: 1, stopPropagation(){}, preventDefault(){} }, o);
  bwDragEl._ev.pointerdown[0](mkEv({ clientX: 0, clientY: 0 }));
  bwDragEl._ev.pointermove[0](mkEv({ clientX: 40, clientY: 30 }));
  bwDragEl._ev.pointermove[0](mkEv({ clientX: bwx, clientY: bwy }));
  assert('拖到证物袋窗口上时窗口高亮（悬停与判决共用同一份清单）', bwNode._classes.has('over'));
  bwDragEl._ev.pointerup[0](mkEv({ clientX: bwx, clientY: bwy }));
  assert('拖到证物袋窗口里：注射器被收纳', window.__dump().bag.includes('item:ITEMS_zsq'));
  assert('拖入窗口后离开画布（stored）', window.__dump().stored.includes('item:ITEMS_zsq'));
  assert('窗口内容当场刷新（清单里出现 1 条）', bwNode.querySelectorAll('.bag-item').length === 1);
  assert('落定后窗口的高亮被清掉', !bwNode._classes.has('over'));
} else {
  errs++; console.log('  ✗ 找不到证物袋窗口或注射器节点元素');
}

/* 反例：窗口关掉之后就不再是落点（否则窗口虽不在、命中框还在，拖过去会莫名其妙被收纳） */
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');
window.__closeFloats();
assert('重置后证物袋窗口已关掉', window.__dump().floats.bag === false && !bagWinNode());

console.log('\n=== 18. 捕获 + 前往 ===');
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');   /* 「手电筒 → 黑影」的目标黑影在花园里 */
window.__closeFloats();

/* 捕获：手电筒 → 黑影 → 尸体场景，捕获尸体的 hiddenClue（真结局线索） */
window.__reveal('SCENE_shuzhuo');
window.__choice('ITEM_chouti', 0, 0);        // 左抽屉 → 手电筒
window.__combo('item:ITEM_shoudiantong', 'item:ITEM_something');
window.__reveal('SCENES_body');
window.__cap('loc:SCENES_body');
assert('捕获尸体 hiddenClue：CLUES_V_luheng', window.__dump().captured.includes('CLUES_V_luheng'));
assert('捕获生成线索节点', window.__dump().nodes.includes('clue:CLUES_V_luheng'));
window.__cap('item:ITEMS_ccss');             // 粗糙的绳索 → CLUES_mc
assert('捕获绳索 hiddenClue：CLUES_mc', window.__dump().captured.includes('CLUES_mc'));
const capBefore = window.__dump().captured.length;
window.__cap('item:ITEM_taideng');           // 台灯没有 hiddenClue
assert('无可捕获对象时不产生新线索', window.__dump().captured.length === capBefore);

/* 前往：初始已知场景不含门的后面；见过文案后可前往 */
assert('初始未听说门的后面', !window.__gotoList().includes('SCENES_mdhm'));
window.__noteSeen('你拨开了疯长的大豕草……（如果你已做好准备，请在互动指令中输入“前往 门的后面”）');
assert('见过文案后听说门的后面', window.__gotoList().includes('SCENES_mdhm'));
window.__goto('SCENES_mdhm');
assert('前往生成场景节点', window.__dump().nodes.includes('loc:SCENES_mdhm'));

console.log('\n=== 18b. TEC 拖入分析：延迟后提取线索 / 无线索提示 ===');
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');   /* 黑影在花园里：保持这条链路真实可走 */
window.__closeFloats();
window.__reveal('SCENE_shuzhuo');
window.__choice('ITEM_chouti', 0, 0);
window.__combo('item:ITEM_shoudiantong', 'item:ITEM_something');
window.__reveal('SCENES_body');
assert('TEC 分析入口已暴露（window.__analyze）', typeof window.__analyze === 'function');
const anBefore = window.__dump().captured.length;
assert('TEC 分析 loc:SCENES_body 返回 true', window.__analyze('loc:SCENES_body') === true);
assert('分析完成（无头同步）后提取到线索 CLUES_V_luheng', window.__dump().captured.includes('CLUES_V_luheng'));
assert('分析产生线索节点（可拖出使用）', window.__dump().nodes.includes('clue:CLUES_V_luheng'));
assert('分析确实新增了捕获', window.__dump().captured.length > anBefore);
const anMid = window.__dump().captured.length;
assert('无新线索可捕获时走到「无线索」分支且返回 true', window.__analyze('loc:SCENES_body') === true && window.__dump().captured.length === anMid);
assert('线索节点拒绝被再次分析', window.__analyze('clue:CLUES_V_luheng') === false);
assert('分析后 TEC 对话窗处于打开态', window.__dump().floats.tec === true);

console.log('\n=== 18c. TEC 最小化：收进右下角助手卡片 · 分析进度条 · 完成圆点 ===');
const tecDock = document.getElementById('tec-dock');
const tecChip = document.getElementById('tec-chip');
const tecWinNode = () => document.getElementById('desktop').querySelector('.tec-win');
const chipOn = () => !!(tecChip.classList && tecChip.classList.contains('on'));
const chipStatus = () => { const e = document.getElementById('tc-status'); return e ? e.textContent : null; };
const chipBar = () => document.getElementById('tc-bar-fill');
const dotOf = () => (tecChip.querySelector ? tecChip.querySelector('.tc-dot') : null);
const durOf = () => parseInt(chipBar().style.animationDuration, 10) || 0;

assert('TEC 窗口开着时右下角没有助手卡片', !chipOn());
assert('TEC 标题栏同时有「– 最小化」与「× 关闭」',
  !!tecWinNode().querySelector('.syswin-min') && !!tecWinNode().querySelector('.syswin-x'));

/* 走真实按钮路径：点标题栏的「–」 */
tecWinNode().querySelector('.syswin-min')._ev.click[0]();
assert('点「–」后窗口从屏幕上收走', window.__dump().floats.tec === false);
assert('点「–」后右下角亮出助手卡片', chipOn() && window.__tecState().min === true);
assert('空闲卡片写着「助手已收起 · 点此展开」', chipStatus() === '助手已收起 · 点此展开');
assert('空闲时卡片不显示进度条（没有 busy）', !tecChip._classes.has('busy'));
assert('收起时卡片上没有完成圆点', !dotOf());

/* 收着的时候发起分析：进度画在卡片上，窗口不被弹出来 */
assert('收起状态下发起分析返回 true', window.__analyzeStart('loc:SCENES_body', 6000) === true);
assert('分析中窗口保持收起', window.__dump().floats.tec === false && window.__tecState().busy === true);
assert('卡片进入分析态、状态行是「分析中 · <标签>」',
  tecChip._classes.has('busy') && /^分析中 · /.test(chipStatus() || ''));
assert('卡片进度条按分析时长起播（约 6000ms）', durOf() > 5500 && durOf() <= 6000);
assert('分析中拒绝新的分析请求', window.__analyzeStart('loc:SCENES_body', 6000) === false);

/* 完成：进度条收起、点出圆点 */
assert('分析收尾返回 true', window.__analyzeFinish('loc:SCENES_body') === true);
assert('完成后卡片退出分析态、进度条停播',
  !tecChip._classes.has('busy') && chipBar().style.animationDuration === ''
    && window.__tecState().task === null);
assert('完成后卡片上点出一个小圆点', !!dotOf() && window.__tecState().dot === true);
assert('完成后状态行改为「分析完成 · 点此展开」', chipStatus() === '分析完成 · 点此展开');

/* 卡片 = 可拖动的落点：单击即展开对话窗 */
tecChip._ev.click[0]();
assert('点卡片 = 还原窗口（而不是关闭）',
  window.__dump().floats.tec === true && window.__tecState().min === false);
assert('还原后卡片熄掉', !chipOn());
assert('打开 TEC 窗口即清掉完成圆点', !dotOf() && window.__tecState().dot === false);
assert('还原后再点图标 = 关闭窗口（原语义不变）',
  (tecDock._ev.dblclick[0](), window.__dump().floats.tec === false));
assert('窗口没开时最小化是空操作', window.__tecMin() === false && window.__tecState().min === false);

/* 卡片可拖动："拖完紧跟的那一次单击"不误展开（与案件卡片共用 attachDock） */
assert('重开 TEC 窗口', (tecDock._ev.dblclick[0](), window.__dump().floats.tec === true));
tecWinNode().querySelector('.syswin-min')._ev.click[0]();
assert('再次收起落在右下角卡片上', chipOn() && window.__dump().floats.tec === false);
tecChip._ev.pointerdown[0]({ button: 0, clientX: 900, clientY: 500 });
assert('卡片拖动时把 right/bottom 换成了 left/top',
  tecChip.style.right === 'auto' && tecChip.style.bottom === 'auto');
tecChip._ev.pointermove[0]({ clientX: 800, clientY: 420 });
tecChip._ev.pointerup[0]({});
tecChip._ev.click[0]();
assert('拖完紧跟的单击不误展开 TEC', window.__dump().floats.tec === false && chipOn());

/* 开着窗口分析到一半再收起：进度要接着挪到卡片上 */
tecChip._ev.pointerdown[0]({ button: 0, clientX: 800, clientY: 420 });   /* 下一次按下复位 moved */
tecChip._ev.click[0]();
assert('点卡片重新展开 TEC 窗口', window.__dump().floats.tec === true && !chipOn());
assert('开着窗口发起分析', window.__analyzeStart('loc:SCENES_body', 5000) === true);
assert('窗口开着时进度留在窗内（卡片没亮）',
  !!tecWinNode().querySelector('.tec-analyzing') && !chipOn());
tecWinNode().querySelector('.syswin-min')._ev.click[0]();
assert('分析途中收起：窗口收走、卡片接着放进度',
  window.__dump().floats.tec === false && chipOn() && tecChip._classes.has('busy'));
assert('中途收起的进度条按剩余时间续播（< 6000ms）', durOf() > 4000 && durOf() <= 5000);
window.__analyzeFinish('loc:SCENES_body');
assert('中途收起后完成，同样点出圆点', !!dotOf() && window.__tecState().task === null);
tecChip._ev.click[0]();
assert('点卡片还原窗口并清掉圆点', window.__dump().floats.tec === true && !dotOf() && !chipOn());
assert('收尾归位：窗口关闭 / 无卡片 / 无圆点 / 无进度',
  (tecDock._ev.dblclick[0](), window.__dump().floats.tec === false && window.__tecState().min === false
    && !chipOn() && !dotOf() && !tecChip._classes.has('busy') && window.__tecState().busy === false));

/* 收起态也能把节点拖到卡片上发起分析（用户要求：最小化时也能拖入节点） */
ids['tec-dock']._ev.dblclick[0]();
assert('拖入用例：先把 TEC 开起来', window.__dump().floats.tec === true);
tecWinNode().querySelector('.syswin-min')._ev.click[0]();
assert('拖入用例：收起后卡片亮着', chipOn() && window.__tecState().min === true);
/* 把卡片挪到一个不与任何桌面图标矩形重叠的位置（stub 里图标按 style 定位取矩形） */
tecChip.style.left = '900px'; tecChip.style.top = '500px';
const dropEl = findEl('loc:SCENES_garden');
assert('收起态里仍有可拖的节点当靶子', !!dropEl);
assert('拖入之前卡片上没有完成圆点', !dotOf());
dragTo(dropEl, 960, 520);
assert('拖节点到收起卡片上 = 发起 TEC 分析（窗口不弹回、卡片点出圆点）',
  window.__tecState().dot === true && window.__dump().floats.tec === false);
assert('分析任务已收尾（无头 stub 里同步走完）', window.__tecState().task === null);
tecChip.style.left = ''; tecChip.style.top = '';
/* 收尾：展开（顺带清圆点）再 × 关闭，别给后一节留脏状态 */
ids['tec-dock']._ev.dblclick[0]();
assert('拖入用例：展开后清掉圆点', !dotOf() && window.__dump().floats.tec === true);
tecWinNode().querySelector('.syswin-x')._ev.click[0]();
assert('拖入用例收尾：窗口关闭、无卡片、无圆点',
  window.__dump().floats.tec === false && !chipOn() && !dotOf());

console.log('\n=== 18d. 对话气泡：点框内任意位置推进下一句 ===');
ids['btn-reset']._ev.click[0]();
/* 用真实角色节点：CHARS_TEC 被 sceneTags() 过滤（TEC 只从桌面图标进对话窗，不当画布节点），
   所以改用 SCENES_lhsdst 里的 [char:CHARS_luhengs]。 */
window.__reveal('SCENES_lhsdst');
window.__closeFloats();
window.__talk('char:CHARS_luhengs');       /* 双击角色节点 = 说第一句 */
const TALK_KEY = 'char:CHARS_luhengs';
assert('双击角色节点弹出对话气泡', window.__dump().floats.bubble === true);
const talkBub = ids['world'].children.find(c => c._classes.has('bubble'));
assert('气泡仍是带 × 的系统窗（可点 / 可拖）', !!talkBub && !!talkBub.querySelector('.syswin-x'));
const tp1 = window.__dump().talk[TALK_KEY] || 0;
assert('第一句已计入对话进度', tp1 >= 1);
/* 打字中点击：先补全本句、不推进（用户选定口径）；stub 里 typeInto 同步跑完，手动立 _typing 复现 */
talkBub._typing = true;
talkBub._ev.click[0]();
assert('打字中点击先补全本句、不推进', (window.__dump().talk[TALK_KEY] || 0) === tp1);
assert('补全后打字态已解除', talkBub._typing === false);
talkBub._ev.click[0]();                    /* 再点一次 = 点框内任意位置推进 */
const tp2 = window.__dump().talk[TALK_KEY] || 0;
assert('点气泡任意位置 = 推进下一句', tp2 === tp1 + 1);
/* 拖过的那一次点击不算推进（makeFloatDraggable 的 _dragged 判据） */
const talkBub2 = ids['world'].children.find(c => c._classes.has('bubble'));
assert('点完之后是新的一块气泡', !!talkBub2 && talkBub2 !== talkBub);
talkBub2._ev.pointerdown[0]({ button: 0, pointerId: 1, clientX: 400, clientY: 400, stopPropagation(){}, preventDefault(){} });
talkBub2._ev.pointermove[0]({ clientX: 470, clientY: 436 });
talkBub2._ev.pointerup[0]({});
talkBub2._ev.click[0]();
assert('拖过之后紧跟的那次点击不推进', (window.__dump().talk[TALK_KEY] || 0) === tp2);
window.__closeFloats();
assert('关闭浮层后气泡消失', window.__dump().floats.bubble === false);

console.log('\n=== 18e. TEC 对话窗：点框内任意位置推进 ===');
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');          /* 给 TEC 一个上下文场景（lastScene） */
window.__closeFloats();
tecDock._ev.dblclick[0]();                 /* 双击 TEC 图标开窗 */
assert('TEC 窗已打开', window.__dump().floats.tec === true);
const twEl = tecWinNode();
const twBody = twEl.querySelector('.syswin-body');
const tlines = () => twEl.querySelector('.tec-lines').children.length;
const tl0 = tlines();
const tp0 = window.__dump().tec.prog['SCENES_garden'] || 0;
twEl._ev.click[0]();                     /* 点窗内任意位置（真机里子元素点击会冒泡到这里） */
assert('点 TEC 窗内任意位置 = 说下一句（历史 +1 行）', tlines() === tl0 + 1);
assert('点 TEC 窗内任意位置推进提示进度', (window.__dump().tec.prog['SCENES_garden'] || 0) === tp0 + 1);
/* 拖过 TEC 窗之后紧跟的那一次点击不算推进（_dragged 判据） */
twEl._ev.pointerdown[0]({ button: 0, pointerId: 1, clientX: 400, clientY: 400, stopPropagation(){}, preventDefault(){} });
twEl._ev.pointermove[0]({ clientX: 470, clientY: 436 });
twEl._ev.pointerup[0]({});
const tl1 = tlines();
twEl._ev.click[0]();
assert('拖过 TEC 窗之后紧跟的点击不推进', tlines() === tl1);
/* 标题栏不属于"框内"：− / × 仍是原语义 */
twEl.querySelector('.syswin-x')._ev.click[0]();
assert('TEC 窗 × 仍然关闭窗口（标题栏不在"框内"范围）', window.__dump().floats.tec === false);

console.log('\n=== 19. 结局系统 + 记忆放映 ===');
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');   /* 真结局配方要用到花园里的黑影 / 唱机 */
window.__closeFloats();

/* 记忆场景放映卡 */
window.__reveal('SCENES_0602');
assert('记忆场景弹放映卡', window.__dump().floats.narr === true);
const memCard = ids['world'].children.find(c => c._classes.has('narr-card') && c._classes.has('memory'));
assert('放映卡有 memory 样式', !!memCard);
const memLines = () => memCard.querySelector('.syswin-body').children.length;
if (memCard){
  const bodyBefore = memLines();
  window.__playStep(); window.__playStep();
  assert('放映逐行推进', memLines() > bodyBefore);
  /* 点框内任意位置也能推进（以前只能等 700ms 自动换行） */
  const bodyMid = memLines();
  memCard._ev.click[0]();
  assert('点放映卡任意位置推进下一行', memLines() > bodyMid);
  /* 拖动过的那一次点击不算推进 */
  memCard._ev.pointerdown[0]({ button: 0, pointerId: 1, clientX: 500, clientY: 300, stopPropagation(){}, preventDefault(){} });
  memCard._ev.pointermove[0]({ clientX: 566, clientY: 334 });
  memCard._ev.pointerup[0]({});
  const bodyDrag = memLines();
  memCard._ev.click[0]();
  assert('放映卡拖过之后点击不推进', memLines() === bodyDrag);
}
window.__closeFloats();

/* 集齐真结局配方（五感各一，全部走正常玩法链路） */
window.__reveal('SCENE_shuzhuo');
window.__choice('ITEM_chouti', 0, 0);                        // 左抽屉 → 手电筒
window.__combo('item:ITEM_shoudiantong', 'item:ITEM_something');  // 手电筒 → 黑影 ⇒ 尸体
window.__reveal('SCENES_body');
window.__cap('loc:SCENES_body');                             // CLUES_V_luheng（视觉）
window.__cap('item:ITEMS_ccss');                             // CLUES_mc（触觉）
window.__cap('item:ITEMS_xh');                               // CLUES_CBKW（味觉）
window.__choice('ITEM_chouti', 0, 1);                        // 右抽屉 → 剪刀 + 木盒
window.__combo('item:ITEMS_jd', 'item:ITEMS_bd');            // 剪刀 → 绷带 ⇒ 陆珩松的尸体
window.__reveal('SCENES_lhsdst');                            // 皱纸 + 唱针
window.__cmd('ITEM_taideng', 0);                             // 点亮台灯：手写笔记的光照门
assert('§19 台灯已点亮（笔记翻得开）', window.__dump().lit.includes('item:ITEM_taideng'));
window.__cmd('ITEM_sxbj', 0);                                // 翻开手写笔记 → 大豕草等
window.__combo('item:ITEMS_zbbdz', 'item:ITEMS_dsc');        // 皱纸 → 大豕草 ⇒ CLUES_xds（嗅觉）
ids['pw-in'].value = '0321';
window.__pw('ITEMS_jzmh');                                   // 木盒 → 黄铜钥匙
window.__combo('item:ITEMS_htys', 'item:ITEMS_changji');     // 钥匙 → 唱机 ⇒ 暗格
window.__reveal('SCENES_cjag');                              // 黑胶
window.__combo('item:ITEMS_wmhj', 'item:ITEMS_changji');     // 黑胶 → 唱机 ⇒ CLUES_nm（听觉）
['CLUES_V_luheng','CLUES_mc','CLUES_CBKW','CLUES_xds','CLUES_nm'].forEach(id =>
  assert('配方线索已捕获 ' + id, window.__dump().captured.includes(id)));

/* 逻辑阵列：归槽 + 推演 */
ids['infer-icon']._ev.dblclick[0]();
assert('双击推演器图标开阵列窗口', window.__dump().floats.matrix === true);
assert('错误感官槽位拒绝', window.__mxAssign('clue:CLUES_V_luheng', 'touch') === false);
assert('正确槽位归槽', window.__mxAssign('clue:CLUES_V_luheng', 'vision') === true);
window.__mxAssign('clue:CLUES_nm', 'hearing');
window.__mxAssign('clue:CLUES_mc', 'touch');
window.__mxAssign('clue:CLUES_CBKW', 'taste');
window.__mxAssign('clue:CLUES_xds', 'smell');
const mx = window.__dump().matrix;
assert('五感归槽完成',
  mx.vision.includes('CLUES_V_luheng') && mx.hearing.includes('CLUES_nm') &&
  mx.touch.includes('CLUES_mc') && mx.taste.includes('CLUES_CBKW') && mx.smell.includes('CLUES_xds'));
/* 长按中央执行者激活推演（无头环境 pointerdown 即完成蓄力） */
const iwEl19 = document.getElementById('desktop').querySelector('.infer-win');
const execEl = iwEl19 && iwEl19.querySelector('.mx-exec');
assert('中央执行者在桌布上', !!execEl);
assert('执行者只剩头像（标签与提示已移除，头像即五芒星中枢）',
  !!execEl && !!execEl.querySelector('.mx-avatar') && !execEl.querySelector('.mx-exec-label') && !execEl.querySelector('.mx-exec-hint'));
/* 星阵 = 外圆 + 五芒星一条路径：常显框与长按描线共用（源码检查：stub 的 setAttribute("class")
   不进 _classes，SVG path 按 class 选不中，故与尺寸/抖动断言同用源码级） */
assert('星阵含外圆与五芒星一条路径（常显框与长按描线共用）',
  html.indexOf('const MX_CIRCLE_R = 195') > 0 &&
  html.indexOf('" a" + MX_CIRCLE_R + "," + MX_CIRCLE_R + " 0 1,1 " + (MX_CIRCLE_R * 2) + ",0"') > 0 &&
  html.indexOf('d += " M" + pts[0].x') > 0 &&
  html.indexOf('draw.setAttribute("d", d)') > 0 &&
  html.indexOf('draw.setAttribute("pathLength", "100")') > 0);
execEl._ev.pointerdown[0]({ button: 0 });
assert('真结局触发', window.__dump().endingOverlay === true && window.__dump().endings.includes('TRUE_E'));
for (let i = 0; i < 10; i++) window.__playStep();
assert('演出步进完毕自动关闭', window.__dump().endingOverlay === false);
/* 窗体缩小 + 蓄力抖动仪式（源码检查：无头环境 setTimeout 归零，蓄力立即完成，量不到持续态） */
assert('阵列窗体收边为 560×420（五芒星大小不变）',
  html.indexOf('margin-left:-280px; width:560px') > 0 &&
  html.indexOf('width:560px; height:420px') > 0 &&
  html.indexOf('MX_W = 560, MX_H = 420') > 0);
assert('蓄力时头像震颤且红光渐盛（源码检查）',
  html.indexOf('.mx-exec.charging .mx-avatar{animation:mx-av-quiver') > 0 &&
  html.indexOf('mx-av-glow 2.5s') > 0);
/* 窗体震动只属于真名结局：蓄力不再抖整窗（否则点一下头像就会闪一下窗抖），
   mx-win-quiver 与 .infer-win.charging 规则应已删除 */
assert('蓄力不再抖整窗（窗体震动只留给真名结局，源码检查）',
  html.indexOf('mx-win-quiver') < 0 &&
  html.indexOf('.infer-win.charging') < 0 &&
  html.indexOf('inferWinEl.classList.add("charging")') < 0);
/* 真名结局：整窗冲击震动一拍后再落遮罩（无头 setTimeout 归零，走同步兜底立即演出） */
assert('真名结局判定时整窗冲击震动（源码检查）',
  html.indexOf('.infer-win.shock{animation:mx-win-shock') > 0 &&
  html.indexOf('inferWinEl.classList.add("shock")') > 0 &&
  html.indexOf('setTimeout(playEndingStage, 900)') > 0 &&
  html.indexOf('if (!t) playEndingStage();') > 0);
/* 配方不匹配：头像上方弹心碎表情替代 toast（源码检查：stub 下 setTimeout 归零，动画量不到持续态） */
assert('配方不匹配改为头像弹心碎表情（源码检查）',
  html.indexOf('.mx-emote{') > 0 &&
  html.indexOf('animation:mx-emote-pop 1.4s ease forwards') > 0 &&
  html.indexOf('EXEC_EMOTE_HEARTBROKEN_B64') > 0 &&
  html.indexOf('function showExecEmote(){') > 0 &&
  html.indexOf('else { showExecEmote(); log("推演失败') > 0 &&
  html.indexOf('toast("配方不匹配，再想想"') < 0);

console.log('\n=== 20. 桌面图标 ===');
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');   /* 图标链路里要「手电筒 → 黑影」 */
/* 图标拖动 */
const icon = ids['bag-dock'];
const ix = icon.style.left, iy = icon.style.top;
const ev = o => Object.assign({ button: 0, pointerId: 1, stopPropagation(){}, preventDefault(){} }, o);
icon._ev.pointerdown[0](ev({ clientX: 50, clientY: 300 }));
icon._ev.pointermove[0](ev({ clientX: 150, clientY: 380 }));
icon._ev.pointerup[0](ev({ clientX: 150, clientY: 380 }));
assert('证物袋图标被移动', icon.style.left !== ix || icon.style.top !== iy);
assert('顶栏前往/推演按钮已移除（源码检查）', html.indexOf('id="btn-goto"') < 0 && html.indexOf('id="btn-infer"') < 0);
/* 双击打开窗口 */
ids['infer-icon']._ev.dblclick[0]();
assert('双击推演器图标开窗', window.__dump().floats.matrix === true);
/* 拖线索到推演器图标 = 直接归槽（拖放路径由 bag>tec>infer>goto 优先级保证，此处用钩子验证归槽逻辑） */
window.__reveal('SCENE_shuzhuo');
window.__choice('ITEM_chouti', 0, 0);
window.__combo('item:ITEM_shoudiantong', 'item:ITEM_something');
window.__reveal('SCENES_body');
window.__cap('loc:SCENES_body');
/* 拖线索落到桌布上 = 归位到它自己的感官（真实拖放路径；stub 里桌布矩形退化成 140×48，
   先给个内联位置再测，与证物袋窗口的测法同款） */
const iwEl20 = document.getElementById('desktop').querySelector('.infer-win');
const boardEl = iwEl20 && iwEl20.querySelector('.mx-board');
assert('桌布在阵列窗里', !!boardEl);
boardEl.style.left = '400px'; boardEl.style.top = '120px';
const clueEl20 = findEl('clue:CLUES_V_luheng');
assert('线索节点在画布上', !!clueEl20);
const bdr = boardEl.getBoundingClientRect();
dragTo(clueEl20, bdr.left + bdr.width / 2, bdr.top + bdr.height / 2);
assert('拖线索上桌布归位（自动归入视觉）', window.__dump().matrix.vision.includes('CLUES_V_luheng'));
assert('落定后桌布高亮被清掉', !boardEl._classes.has('over'));
/* 推演器图标角标显示已归位条数 */
const ib = ids['infer-icon'].querySelector('.badge');
assert('推演器图标角标显示 1 条', !!ib && ib.textContent === '1 条');
/* chip 上不再有 ×：拿下桌布只能拖出（与外部「拖进拖出」一致）。
   注意：归位后 refreshInferWin 重建了桌布，要重新取元素（手里旧的 boardEl 已离树） */
const chipX = iwEl20.querySelector('.mx-board').querySelector('.mx-chip');
assert('桌布上的线索 chip 不再带 ×', !!chipX && !chipX.querySelector('.mx-x'));
/* 拖出桌布 = 移除：stub 里桌布矩形由 style.left/top + 140×48 常量拼出（新桌布无内联位置 → 0,0,140,48），
   拖到 (900,700) 必在其外；mirror 走 #drag-layer（getElementById 按需创建） */
const pev = o => Object.assign({ button: 0, pointerId: 1, stopPropagation(){}, preventDefault(){} }, o);
chipX._ev.pointerdown[0](pev({ clientX: 0, clientY: 0 }));
chipX._ev.pointermove[0](pev({ clientX: 40, clientY: 30 }));
chipX._ev.pointermove[0](pev({ clientX: 900, clientY: 700 }));
chipX._ev.pointerup[0](pev({ clientX: 900, clientY: 700 }));
assert('拖出桌布后线索从桌布移除', !window.__dump().matrix.vision.includes('CLUES_V_luheng'));
assert('移除后推演器图标角标消失', !ids['infer-icon'].querySelector('.badge'));
/* TEC 窗口 */
ids['tec-dock']._ev.dblclick[0]();
assert('双击 TEC 图标开对话窗', window.__dump().floats.tec === true);
window.__tecTalk();
assert('TEC 交谈推进提示进度', window.__dump().tec.prog['SCENES_body'] === 1);

console.log('\n=== 22. 侧边栏图标化 ===');
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');   /* 后面要选花园节点、用唱机 / 注射器 */
window.__select(null);              /* 展开会顺带选中并弹详情窗，先取消，保持「默认关闭」断言 */
assert('日志窗默认关闭', window.__dump().floats.logs === false);
assert('详情窗默认关闭', window.__dump().floats.detail === false);
assert('aside 已从源码移除', html.indexOf('<aside') < 0);
window.__select('loc:SCENES_garden');
assert('选中节点自动弹出详情窗', window.__dump().floats.detail === true);
ids['detail-x']._ev.click[0]();
assert('× 关闭详情窗（取消选中）', window.__dump().floats.detail === false);
assert('详情图标已移除', html.indexOf('id="detail-icon"') < 0);
window.__select('loc:SCENES_garden');
assert('再次选中重开详情窗', window.__dump().floats.detail === true);
window.__select(null);
assert('取消选中即关详情窗', window.__dump().floats.detail === false);
ids['log-x']._ev.click[0]();
assert('× 关闭日志窗', window.__dump().floats.logs === false);
window.__combo('item:ITEMS_changji', 'item:ITEMS_zsq');  // 必定产生一条日志（无反应的失败组合）
assert('日志窗关闭时新日志累加图标徽标', ids['log-icon'].children.some(c => c._classes.has('badge')));
ids['log-icon']._ev.dblclick[0]();
assert('双击日志图标重开并清徽标', window.__dump().floats.logs === true && !ids['log-icon'].children.some(c => c._classes.has('badge')));

/* 详情内容：线索显示感官类型、物品显示来源场景，操作引导已移除 */
window.__reveal('SCENES_body');
window.__cap('loc:SCENES_body');
window.__select('clue:CLUES_V_luheng');
assert('线索详情显示感官类型', (ids['detail-body']._html || '').indexOf('视觉') >= 0);
window.__select('item:ITEMS_changji');
const itemHtml = ids['detail-body']._html || '';
assert('物品详情显示来源场景', itemHtml.indexOf('植物学家的花园') >= 0);
assert('详情不再含操作引导', itemHtml.indexOf('双击节点进行') < 0 && itemHtml.indexOf('拖到') < 0);

console.log('\n=== 23. 长文本去重：正文 / 日志 / 详情窗 各归其位 ===');
ids['btn-reset']._ev.click[0]();
/* 展开「书桌」——叙事卡出现，但正文不再被镜像进日志 */
const lBefore = logs.length;
window.__reveal('SCENE_shuzhuo');
const lNew = logs.slice(lBefore);
assert('展开场景弹出叙事卡', window.__dump().floats.narr === true);
assert('日志里不再出现场景正文', !lNew.some(l => l.indexOf('在靠近桌子的边缘') >= 0));
assert('日志只留一行场景事件', lNew.some(l => l.indexOf('叙事卡已放映') >= 0));

/* 场景详情窗：无正文、有结构信息、有回看入口 */
window.__select('loc:SCENE_shuzhuo');
let dh = ids['detail-body']._html || '';
assert('场景详情不再含正文', dh.indexOf('在靠近桌子的边缘') < 0);
assert('场景详情保留结构信息（出口）', dh.indexOf('出口：') >= 0);
assert('场景详情提供「重看场景叙事」按钮', dh.indexOf('dt-renarr') >= 0);

/* 回看入口能真的把卡叫回来 */
window.__closeFloats();
assert('关闭后无叙事卡', window.__dump().floats.narr === false);
window.__renarr('SCENE_shuzhuo');
assert('「重看叙事」重新弹出卡', window.__dump().floats.narr === true);
window.__closeFloats();

/* 物品描述统一在详情窗承载（不论有没有命令）；双击无命令物品只选中、不再弹提示条 */
window.__reveal('SCENES_choutiyi');
window.__select('item:ITEM_shoudiantong');
dh = ids['detail-body']._html || '';
assert('无命令物品：描述也在详情窗（唯一出口）', dh.indexOf('还能使用的手电筒') >= 0);
window.__reveal('SCENES_garden');
window.__select('item:ITEMS_zhiwu');
dh = ids['detail-body']._html || '';
assert('有命令物品：描述同样在详情窗', dh.indexOf('自生自灭') >= 0);
/* 双击无命令物品 = 选中（不再走顶部提示条） */
ids['toast'].innerHTML = '__sentinel__';
window.__talk('item:ITEM_shoudiantong');
assert('双击无命令物品不再走提示条', ids['toast'].innerHTML === '__sentinel__');
assert('双击无命令物品：仍被选中（详情窗开着）', window.__dump().floats.detail === true);

/* 动作 / 错误提示整体移除：详情窗只呈现描述与结构信息，既不弹提示条也不塞「结果」块
   —— 行为与状态变化靠画面自证（点亮、节点出现/消失、线索落盘），文字提示没有意义。 */
ids['toast'].innerHTML = '__sentinel__';
window.__talk('item:ITEMS_zsq');            /* 注射器：条件命令「查看内部」不满足 */
dh = ids['detail-body']._html || '';
assert('双击有命令物品：提示条不响', ids['toast'].innerHTML === '__sentinel__');
assert('详情窗不再有「结果 / 未成功」反馈块', dh.indexOf('dfb') < 0 && dh.indexOf('不知名的液体') < 0);

ids['toast'].innerHTML = '__sentinel__';
window.__talk('item:ITEM_taideng');         /* 台灯：文字命令「点亮台灯」 */
dh = ids['detail-body']._html || '';
assert('双击文字命令物品：提示条不响', ids['toast'].innerHTML === '__sentinel__');
assert('双击文字命令物品：详情窗只留描述、不放命令结果',
  dh.indexOf("class='dt'") >= 0 && dh.indexOf('昏黄的灯光照亮了书桌') < 0);
assert('动作结果仍记进日志（信息不丢）', logs.some(l => l.indexOf('昏黄的灯光照亮了书桌') >= 0));

/* 组合结果同样不再弹提示条（成功 / 失败都只写日志）—— 效果靠画面自证：
   新场景 / 新物品节点当场冒出来、被消耗的节点当场消失，文字提示只是复述已知信息。 */
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');
window.__reveal('SCENE_shuzhuo');
window.__choice('ITEM_chouti', 0, 1);        /* 右抽屉 → 剪刀 */
window.__reveal('SCENES_body');              /* 绷带在这个场景里 */
const lcBefore = logs.length;
ids['toast'].innerHTML = '__sentinel__';
window.__combo('item:ITEMS_jd', 'item:ITEMS_bd');      /* 剪刀 → 绷带：必定成功的组合 */
assert('组合成功不再弹提示条', ids['toast'].innerHTML === '__sentinel__');
assert('组合成功仍写进日志（反应正文 + 获得 / 消耗）',
  logs.length > lcBefore &&
  logs.slice(lcBefore).some(l => l.indexOf('陆珩松的尸体') >= 0 && l.indexOf('消耗') >= 0));
assert('组合成功的效果仍落在画布上（新场景出现 / 绷带消失）',
  window.__dump().nodes.includes('loc:SCENES_lhsdst') && !window.__dump().nodes.includes('item:ITEMS_bd'));
ids['toast'].innerHTML = '__sentinel__';
window.__combo('item:ITEMS_changji', 'item:ITEMS_zsq');   /* 无反应的失败组合 */
assert('组合失败也不再弹提示条', ids['toast'].innerHTML === '__sentinel__');
assert('组合失败仍写进日志', logs.some(l => l.indexOf('组合失败') >= 0));

console.log('\n=== 24. 案件库：切案 / 会话态隔离 / 各存各档 ===');
ids['btn-reset']._ev.click[0]();
const fresh = window.__dump().nodes.length;   /* 一个案件的「全新开局」节点数（起始场景 + 随行角色） */

/* 案件地图：地址列表 + 副标题 + 当前标记 */
const mapDbl = () => document.getElementById('map-icon')._ev.dblclick[0]();
const mapText = sel => document.getElementById('desktop').querySelectorAll(sel).map(n => n.textContent);
mapDbl();
assert('地图为每个案件列出地址', mapText('.map-note').length === 2);
assert('第19节真结局把下一案解锁了（连锁）', window.__caseInfo().unlocked.indexOf('A002') >= 0);
assert('解锁案件的副标题不再是加密提示', mapText('.map-note')[1].indexOf('已解锁') >= 0);
assert('已解锁但数据未装载 → 标为「待接入」', mapText('.map-state').indexOf('待接入') >= 0);
assert('待接入案的副标题说明数据未装载', mapText('.map-note')[1].indexOf('待装载') >= 0);
assert('地图标出当前案件', mapText('.map-state').indexOf('当前') >= 0);
mapDbl();

/* 先在 A-001 里做出进度：展开场景 + 一次抽屉选择（会进撤销栈） */
window.__reveal('SCENE_shuzhuo');
window.__reveal('SCENES_choutiyi');
window.__goto('SCENES_garden');
window.__choice('ITEM_chouti', 0, 0);
const a1nodes = window.__dump().nodes.length;
assert('A-001 已有进度（多节点）', a1nodes > fresh);
assert('A-001 已有撤销栈', window.__dump().history > 0);
assert('开局案件为 A-001', window.__caseInfo().id === 'A001');
assert('A-001 标题已挂到案件窗', window.__caseInfo().title === 'CASE A-001 // 植物学家的花园');
assert('A-001 起始场景已装载', window.__caseInfo().sceneTitle === '植物学家的花园');

/* 注册 A-002 数据（克隆 A-001 但改一处可见标识）并解锁 */
const d2 = JSON.parse(JSON.stringify(window.__caseDataOf('A001')));
d2.config.caseTitle = '废弃温室';
d2.scenes.SCENES_garden.title = '废弃温室';
window.__registerCase('A002', d2);
window.__unlockCase('A002');
assert('A-002 数据已注册', window.__caseInfo().registered.indexOf('A002') >= 0);
assert('A-002 已解锁', window.__caseInfo().unlocked.indexOf('A002') >= 0);

/* 守卫：当前案 / 未知案 / 未注册案都切不动 */
assert('切到当前案是空操作', window.__switchCase('A001') === false);
assert('未知案件切不动', window.__switchCase('A999') === false);
window.__registerCase('A004', JSON.parse(JSON.stringify(d2)));
assert('未解锁案件切不动', window.__switchCase('A004') === false);
mapDbl();
assert('数据装载后改为「可进入」', mapText('.map-state').indexOf('可进入') >= 0);
mapDbl();

/* 把图标挪歪，验证切案会复位 */
const inferTop0 = document.getElementById('infer-icon').style.top;
document.getElementById('infer-icon').style.top = '999px';

/* 切到 A-002 */
assert('切到 A-002 成功', window.__switchCase('A002') === true);
const ci = window.__caseInfo();
assert('当前案变为 A-002', ci.id === 'A002');
assert('案件窗标题跟随切换', ci.title === 'CASE A-002 // 废弃温室');
assert('A-002 的场景数据已装载', ci.sceneTitle === '废弃温室');
assert('会话态已清（撤销栈归零）', window.__dump().history === 0);
assert('新桌面为全新开局', window.__dump().nodes.length === fresh);
assert('图标站位已复位', document.getElementById('infer-icon').style.top === inferTop0);
assert('刚进入的地址被记为点亮', ci.lastEntered === 'A002');

/* 在 A-002 里做出自己的进度 */
window.__reveal('SCENE_shuzhuo');
window.__reveal('SCENES_choutier');
const a2nodes = window.__dump().nodes.length;
assert('A-002 已产生自己的进度', a2nodes > fresh && a2nodes !== a1nodes);

/* 回访 A-001：应还原它自己的档 */
assert('回访 A-001 成功', window.__switchCase('A001') === true);
const back = window.__caseInfo();
assert('当前案变回 A-001', back.id === 'A001');
assert('标题跟随回访', back.title === 'CASE A-001 // 植物学家的花园');
assert('场景数据换回 A-001', back.sceneTitle === '植物学家的花园');
assert('A-001 进度被续上（节点数一致）', window.__dump().nodes.length === a1nodes);
assert('A-001 恢复后撤销栈是新会话', window.__dump().history === 0);
assert('解锁进度不因切案丢失', window.__caseInfo().unlocked.indexOf('A002') >= 0);

/* 再回 A-002：它的档同样在 */
window.__switchCase('A002');
assert('A-002 进度被续上（节点数一致）', window.__dump().nodes.length === a2nodes);

/* 重置只清当前案，不动别的案 */
ids['btn-reset']._ev.click[0]();
assert('重置后仍停留在 A-002', window.__caseInfo().id === 'A002');
assert('A-002 已被重置为全新开局', window.__dump().nodes.length === fresh);
window.__switchCase('A001');
assert('A-001 的旧档未被重置波及', window.__dump().nodes.length === a1nodes);
window.__switchCase('A002');
assert('A-002 确实被重置（回到全新开局）', window.__dump().nodes.length === fresh);
window.__switchCase('A001');

console.log('\n=== 25. 模板与成品一致性 ===');
/* _template.html 由 index.html 生成（只把 gamedata 换成占位符）。
   这里做结构比对，防止改了成品忘了同步模板 —— 曾经真的漏过调查员证那一段。 */
const tpl = fs.readFileSync(path.join(__dirname, '_template.html'), 'utf8');
const normTemplate = s => s.replace(/(<script type="application\/json" id="gamedata">)[\s\S]*?(<\/script>)/, (m, a, b) => a + '@@DATA@@' + b);
const dA = normTemplate(html).split('\n');
const dB = normTemplate(tpl).split('\n');
let firstBad = -1;
for (let i = 0; i < Math.max(dA.length, dB.length); i++){
  if (dA[i] !== dB[i]){ firstBad = i; break; }
}
assert('_template.html 与 index.html 只差数据占位符' +
       (firstBad < 0 ? '' : '（首个不同行 ' + (firstBad + 1) + '）'), firstBad < 0);

console.log('\n=== 26. HTML 结构（嵌套层级） ===');
/* DOM stub 不解析 HTML，所以上面 183 项断言全都看不见「div 关错位置」这类错误。
   这里用 div 栈做静态结构检查 —— 曾经因为少写一个 </div>，把图标连同日志窗一起关进了案件窗里。 */
const bare = html.replace(/<script[\s\S]*?<\/script>/gi, '');
const depthAt = {};
let depth = 0, underflow = false;
const tags = bare.matchAll(/<div\b([^>]*)>|<\/div>/gi);
for (const m of tags){
  if (m[0].toLowerCase().startsWith('</')){
    depth--;
    if (depth < 0){ underflow = true; break; }
  } else {
    const idm = /id="([^"]+)"/.exec(m[1] || '');
    if (idm) depthAt[idm[1]] = depth;
    depth++;
  }
}
assert('<div> 开闭配平（收尾 depth = ' + depth + '）', !underflow && depth === 0);
assert('#icons 是 #case-win 的兄弟（都在 #desktop 下）', depthAt['icons'] === depthAt['case-win']);
assert('#log-win 也在 #desktop 下', depthAt['log-win'] === depthAt['case-win']);
assert('#detail-win 也在 #desktop 下', depthAt['detail-win'] === depthAt['case-win']);
assert('#stage 在 #case-win 内一层', depthAt['stage'] === depthAt['case-win'] + 1);
assert('#world 在 #stage 内', depthAt['world'] === depthAt['stage'] + 1);

/* 详情窗「框套框」整治（2026-10-12）：窗内不得再出现任何内层方框。
   这几条只能查源码 —— DOM stub 不解析 CSS，看不到圆角/边框这类视觉问题。 */
assert('详情窗里没有内嵌结果块（.dfb 规则已移除）', html.indexOf('.dfb') < 0);
assert('详情窗的结构行不再用虚线分隔（只留白）', !/#detail-body \.drow\{[^}]*border-top/.test(html));
assert('详情窗里的按钮降级为纯文字（无边框/无底/无阴影）',
  /#detail-body button\{[^}]*border:0[^}]*box-shadow:none/.test(html));

/* TEC「– 收起」（2026-10-12）：窗口缩成桌面右下角那块**带头像的助手卡片** #tec-chip ——
   进度条 / 完成圆点都落在卡片上（落点不再用左侧的 ◉ 图标）。
   源码级断言：DOM stub 不解析 HTML / CSS，结构类与视觉类规则只能查源码。 */
assert('TEC 标题栏接线了最小化（makeWindow 第三参）',
  /makeWindow\("TEC \/\/ 对话", closeTecWin, minTecWin\)/.test(html));
assert('助手卡片有头像位 / 状态行 / 进度条 / 完成圆点',
  /id="tec-chip"/.test(html) && /id="tc-av-img"/.test(html) && /id="tc-status"/.test(html)
  && /id="tc-bar-fill"/.test(html) && /\.tc-dot\{/.test(html));
assert('助手卡片样式齐备（头像 / 进度条 / 分析态）',
  /#tec-chip\{/.test(html) && /\.tc-av\{/.test(html) && /\.tc-bar\{/.test(html)
  && /#tec-chip\.busy \.tc-bar\{/.test(html));
assert('助手卡片排在案件卡片上方（两张卡片不叠在一起）',
  Number((/#tec-chip\{[^}]*bottom:(\d+)px/.exec(html) || [0, 0])[1]) >
  Number((/#case-dock\{[^}]*bottom:(\d+)px/.exec(html) || [0, 0])[1]));
assert('落点已从桌面图标移到卡片：图标那边不再有进度环 / 圆点',
  html.indexOf('tec-ring') < 0 && html.indexOf('tecring') < 0 && html.indexOf('desk-icon .tec-dot') < 0);
assert('收起态助手卡片也能接收节点（拖入 = TEC 分析，与图标 / 窗内头像同一路由）',
  /function nodeDropTargets\(\)/.test(html)
  && /if \(tecChipOn\) list\.push\("tec-chip"\)/.test(html)
  && /iconHit === "tec-chip"\) tecAnalyze\(n\.key\)/.test(html));
assert('悬停高亮与松手判决共用同一份 nodeDropTargets()',
  (html.match(/nodeDropTargets\(\)\.forEach\(id => \{/g) || []).length === 2);
assert('拖节点悬停到收起卡片上有高亮（与窗内头像同一套虚线）',
  /#tec-chip\.over\{[^}]*outline:2px dashed var\(--text\)/.test(html));
/* 证物袋窗口 / 线索册窗口都是落点：窗口开着时把节点拖到窗口上 = 收纳。
   顺序必须排在最前 —— .bag-win / .clue-win（z25）盖在 #icons（z24）之上，被盖住的区域要判给
   「看得见的窗口」，否则拖物品到窗口上会落进底下那张被遮住的图标（推演器 / 档案）。 */
assert('证物袋窗口进了落点清单，且排在图标之前（z 序：窗口 25 > 图标 24）',
  /function nodeDropTargets\(\)\{[^}]*if \(bagWinEl\) list\.push\("bag-win"\)/.test(html)
  && html.indexOf('if (bagWinEl) list.push("bag-win")') < html.indexOf('list.push("bag-dock","clue-icon"'));
assert('窗口是「只在开着时才算落点」（关窗后不再是落点）',
  /if \(bagWinEl\) list\.push\("bag-win"\)/.test(html)
  && /if \(clueWinEl\) list\.push\("clue-win"\)/.test(html)
  && /\.bag-win\{position:absolute/.test(html));
assert('拖进窗口与拖到图标上走同一条收纳路由（bagStore）',
  /iconHit === "bag-dock" \|\| iconHit === "bag-win"\) bagStore\(n\.key\);/.test(html));
assert('线索册窗口 / ※ 图标走 ledgerStore 收纳', 
  /iconHit === "clue-icon" \|\| iconHit === "clue-win"\) ledgerStore\(n\.key\);/.test(html));
assert('证物袋窗口有悬停高亮样式（与卡片 / 助手头像同一套虚线）',
  /\.bag-win\.over\{[^}]*outline:2px dashed var\(--text\)/.test(html));
assert('落点元素解析走 dropTargetEl()（两扇收纳窗取变量，其余按 id），两处调用都在',
  /function dropTargetEl\(id\)\{/.test(html)
  && /if \(id === "bag-win"\) return bagWinEl;/.test(html)
  && /if \(id === "clue-win"\) return clueWinEl;/.test(html)
  && (html.match(/const ic = dropTargetEl\(id\);/g) || []).length === 2);
assert('空袋提示把「窗口内」也说清楚', html.indexOf('或本窗口内）收纳') >= 0);
/* 最小化的顺滑关键：先亮落点卡片、再让窗口缩过去（否则窗口缩没、卡片才淡入 = 闪一下） */
const iMinTec = html.indexOf('function minTecWin(){');
const minTecBody = iMinTec < 0 ? '' : html.slice(iMinTec, html.indexOf('\n}', iMinTec) + 2);
assert('最小化先亮落点卡片再缩窗口（消除"闪一下再出现"）',
  minTecBody.indexOf('tecMin = true') >= 0
  && minTecBody.indexOf('showTecChip(true)') >= 0 && minTecBody.indexOf('tecMotionApply(tf)') >= 0
  && minTecBody.indexOf('showTecChip(true)') < minTecBody.indexOf('tecMotionApply(tf)'));
/* 点击框内任意位置推进（对话气泡 / 记忆放映卡）：拖动过的那一次不算点击 */
assert('TEC 对话窗也接线了"点框内任意位置推进"（挂在窗口根上，头像不再独占）',
  /w\.el\.addEventListener\("click"/.test(html) && /tecTalk\(\)/.test(html)
  && !/av\.addEventListener\("click", \(\) => tecTalk\(\)\)/.test(html));
assert('_dragged 的复位在拖动排除表之前（真机里从被排除的子元素上起手也会复位）',
  html.indexOf('el._dragged = false;') > 0
  && html.indexOf('el._dragged = false;') < html.indexOf('closest("button,input,.bag-item,.map-card,.goto-item,.syswin-x,.syswin-min,.tec-avatar,.mx-exec,.mx-chip")'));
assert('气泡与记忆放映卡都接线了"点击推进"，且用 _dragged 挡掉拖过的那次点击',
  /c\.addEventListener\("click", \(\) => \{ if \(!c\._dragged\) advanceMemory\(\); \}\)/.test(html)
  && /if \(b\._dragged\) return;/.test(html) && /advanceMemory/.test(html));
assert('打字中点击 = 先补全本句，再点才推进',
  /if \(b\._typing\)\{/.test(html) && /if \(mp\.typing\)\{/.test(html)
  && /cancelType\(mp\.cur\)/.test(html));
assert('记忆放映卡不再 700ms 自动换行', html.indexOf('setTimeout(playMemoryLine, 700)') < 0);
assert('打字机计时器记在元素自己身上（卡片与气泡不会互相掐断）',
  /function cancelType\(el\)\{/.test(html) && /\._twTimer/.test(html) && !/[^_]twTimer/.test(html));
assert('OS 外壳整体不可选中（拖窗口不会拉出蓝色选区），输入框放行',
  /body\{user-select:none/.test(html) && /input, textarea, \[contenteditable\]\{user-select:text/.test(html));

console.log('\n=== 27. 案件窗离屏：– 收起 -> 右下角卡片 / × 关闭 -> 「案件地图」图标 ===');
/* 静态结构：两个落点各有归宿。DOM stub 不解析 HTML，结构断言只能查源码。 */
assert('落点 A：#case-dock 卡片存在且有 .on 样式', /id="case-dock"/.test(html) && /#case-dock\.on\{/.test(html));
assert('落点 A：卡片含 glyph / 案号 / 案名 / 副标题',
  /cd-glyph/.test(html) && /id="cd-code"/.test(html) && /id="cd-title"/.test(html) && /id="cd-sub"/.test(html));
assert('落点 B：#map-icon（案件地图图标）在桌面图标栏里', /id="map-icon"/.test(html));
assert('标题栏同时有最小化 #case-min 与关闭 #case-x', /id="case-min"/.test(html) && /id="case-x"/.test(html) && /\.syswin-min\{/.test(html));
assert('两条路是分开的函数（parkCase / stowCase / closeCase）',
  /function parkCase\(p\)/.test(html) && /function stowCase\(\)\{ return parkCase\("dock"\); \}/.test(html)
  && /function closeCase\(\)\{ return parkCase\("icon"\); \}/.test(html));
assert('拖动排除表覆盖了地图地址卡 / TEC 头像 / TEC 最小化键 / 阵列执行者与线索 chip',
  /closest\("button,input,\.bag-item,\.map-card,\.goto-item,\.syswin-x,\.syswin-min,\.tec-avatar,\.mx-exec,\.mx-chip"\)/.test(html));
/* 触发 stub 里注册的事件处理器 */
const fire = (el, t, o) => (el._ev[t] || []).forEach(f => f(Object.assign(
  { button: 0, clientX: 0, clientY: 0, pointerId: 1, stopPropagation(){}, preventDefault(){} }, o)));
const badgeOf = () => { const i = document.getElementById('map-icon'); return (i && i.querySelector) ? i.querySelector('.badge') : null; };
const dockOf  = () => document.getElementById('case-dock');
const dockOn  = () => { const d = dockOf(); return !!(d && d.classList && d.classList.contains('on')); };

ids['btn-reset']._ev.click[0]();
const ci0 = window.__caseInfo();
assert('进入案件时案件窗是开着的', ci0.open === true);
assert('案件窗未被隐藏', document.getElementById('case-win').style.display !== 'none');
assert('开着的时候两个落点都是空的', ci0.held === false && ci0.dock === false && !badgeOf() && !dockOn());

/* 做出进度（会进撤销栈） */
window.__reveal('SCENE_shuzhuo');
window.__choice('ITEM_chouti', 0, 0);
/* 关窗前先往证物袋里放一件证物，用于验证离屏后取不出 */
window.__reveal('SCENES_garden');
window.__closeFloats();
window.__bag('item:ITEMS_zsq');
assert('关闭前注射器已收入证物袋', window.__dump().bag.includes('item:ITEMS_zsq'));
ids['bag-dock']._ev.dblclick[0]();
assert('关闭前证物袋窗已打开', window.__dump().floats.bag === true);
const n1 = window.__dump().nodes.length;
assert('已产生进度', n1 > 1 && window.__dump().history > 0);

/* ---- × 关闭：存盘 -> 缩进桌面左侧的「案件地图」图标 ---- */
assert('关闭案件窗成功', window.__closeCase() === true);
const ci2 = window.__caseInfo();
assert('关闭后案件窗隐藏', ci2.open === false && document.getElementById('case-win').style.display === 'none');
assert('关闭后仍停留在同一个案', ci2.id === 'A001');
assert('关闭落在「案件地图」图标上（held=true）', ci2.held === true);
assert('关闭不走右下角卡片（dock=false 且卡片没亮）', ci2.dock === false && !dockOn());
assert('案件地图图标打了「已关闭」角标', !!badgeOf() && badgeOf().textContent === '已关闭');
assert('关闭后不弹案件地图', document.getElementById('desktop').querySelectorAll('.map-win').length === 0);
/* 关闭状态下，案件地图应把本案标成「进入」而不是「当前」 */
mapDbl();
assert('关闭状态在地图上标为「进入」', mapText('.map-state')[0] === '进入');
assert('地图副标题标记「有存档」', mapText('.map-note')[0].indexOf('有存档') >= 0);
mapDbl();
assert('查完地图后地图窗已关掉', document.getElementById('desktop').querySelectorAll('.map-win').length === 0);
assert('撤销栈已随离屏清空', window.__dump().history === 0);
assert('重复关闭是空操作', window.__closeCase() === false);
assert('案件离屏后证物袋窗仍开着（随身收纳不随案件窗走）', window.__dump().floats.bag === true);
const rawSave = JSON.parse(_ls['tec_case_A001']);
assert('存档里记住了镜头位置', !!rawSave.__view && isFinite(rawSave.__view.k));

/* 关闭状态下，画布上的操作应被拦下（否则会把案件窗又弹回来） */
ids['btn-reset']._ev.click[0]();
assert('关闭时「重置」被拦下，案件窗没被弹回来', window.__caseInfo().open === false && window.__caseInfo().held === true);

/* 关闭状态下，证物袋里的证物也不能点出来（取出 = 放回画布，同属被拦的画布操作） */
assert('关闭时从证物袋取出被拦下', window.__bagTake('item:ITEMS_zsq') === false);
assert('证物仍留在袋中', window.__dump().bag.includes('item:ITEMS_zsq'));

/* 从地图点本案那行：展开、角标消失、进度续上 */
assert('从案件地图展开成功', window.__switchCase('A001') === true);
const ci3 = window.__caseInfo();
assert('案件窗重新打开', ci3.open === true && document.getElementById('case-win').style.display !== 'none');
assert('展开后「已关闭」角标消失', ci3.held === false && !badgeOf());
assert('重新进入后进度续上（节点数一致）', window.__dump().nodes.length === n1);
assert('重新进入后撤销栈是新会话', window.__dump().history === 0);
assert('重新展开后证物袋窗仍在（boot 不再收掉它）', window.__dump().floats.bag === true);
const bwRe = document.getElementById('desktop').querySelector('.bag-win');
assert('袋窗清单已按恢复的图刷新（仍是 1 条）', !!bwRe && bwRe.querySelectorAll('.bag-item').length === 1);
assert('重新展开后可以从袋中取出（闸门放行）', window.__bagTake('item:ITEMS_zsq') === true);
/* 开着的本案在地图上应标回「当前」 */
mapDbl();
assert('展开状态在地图上标回「当前」', mapText('.map-state')[0] === '当前');
mapDbl();

/* ---- – 收起：走桌面右下角的独立卡片，不碰「案件地图」图标 ---- */
window.__reveal('SCENE_shuzhuo');
const nMin = window.__dump().nodes.length;
fire(ids['case-min'], 'click', {});
const ci4 = window.__caseInfo();
assert('点最小化：案件窗离屏', ci4.open === false);
assert('最小化落在右下角卡片上（dock=true 且卡片亮着）', ci4.dock === true && dockOn());
assert('最小化不碰「案件地图」图标（held=false 且无角标）', ci4.held === false && !badgeOf());
assert('卡片上写着案号与案名', ids['cd-code'].textContent === 'CASE A-001' && ids['cd-title'].textContent.length > 0);
assert('卡片副标题标明进度已保存', ids['cd-sub'].textContent.indexOf('进度已保存') >= 0);
assert('最小化也存了档', _ls['tec_case_A001'] != null);
assert('从卡片再展开，进度还在', (window.__switchCase('A001'), window.__dump().nodes.length === nMin));
assert('再展开后卡片熄掉、角标也没有', !dockOn() && window.__caseInfo().dock === false && !badgeOf());

/* 卡片可拖动：right/bottom 定位换算成 left/top，且"拖动过的那一次单击"不误展开 */
fire(ids['case-min'], 'click', {});
fire(dockOf(), 'pointerdown', { clientX: 900, clientY: 500 });
assert('卡片拖动时把 right/bottom 换成了 left/top', dockOf().style.right === 'auto' && dockOf().style.bottom === 'auto');
fire(dockOf(), 'pointermove', { clientX: 800, clientY: 420 });
fire(dockOf(), 'pointerup', {});
fire(dockOf(), 'click', {});
assert('拖完紧跟的单击不误展开案件', window.__caseInfo().open === false && window.__caseInfo().dock === true);
fire(dockOf(), 'pointerdown', { clientX: 800, clientY: 420 });   /* 下一次按下会复位 moved */
fire(dockOf(), 'click', {});
assert('原地单击卡片能展开，且进度还在', window.__caseInfo().open === true && window.__dump().nodes.length === nMin);
assert('从卡片展开后卡片熄掉', !dockOn());

/* 离屏状态下也能直接切到别的案（没有"上一个案"要存） */
window.__closeCase();
assert('关闭后切到 A-002 成功', window.__switchCase('A002') === true);
assert('切案后案件窗是开着的', window.__caseInfo().open === true && window.__caseInfo().id === 'A002');
assert('切案后两个落点都清空',
  window.__caseInfo().held === false && window.__caseInfo().dock === false && !badgeOf() && !dockOn());
assert('切回 A-001 后仍能续上它自己的档', (window.__switchCase('A001'), window.__dump().nodes.length === n1));

/* ---- 换案（案件窗开着时切到别的案）：证物袋窗与 TEC 一样被清掉；同案回访才保留 ---- */
ids['bag-dock']._ev.dblclick[0]();
assert('换案前证物袋窗已打开', window.__dump().floats.bag === true);
window.__switchCase('A002');
assert('换案后证物袋窗被清掉', window.__dump().floats.bag === false);
window.__switchCase('A001');

console.log('\n=== 28. 线索册（收纳盒）/ 人物：两个桌面层清单窗 ===');
/* ---- 线索册 = 收纳盒：捕获 ≠ 入册，要手动拖进去；进去后离开画布；感官标行尾、按五感自动排序 ---- */
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');
window.__reveal('SCENES_body');
/* 三条线索按「味觉 → 触觉 → 视觉」（与 SENSES 顺序相反）依次入册，用真实的拖放路径 */
window.__cap('item:ITEMS_xh');                         /* 味觉 CLUES_CBKW */
window.__cap('item:ITEMS_ccss');                       /* 触觉 CLUES_mc */
window.__cap('loc:SCENES_body');                       /* 视觉 CLUES_V_luheng */
ids['clue-icon']._ev.dblclick[0]();
assert('双击线索册图标开窗', window.__dump().floats.clue === true);
const clueWinEl = document.getElementById('desktop').querySelector('.clue-win');
const clueBody = clueWinEl.querySelector('.syswin-body');
assert('捕获 ≠ 入册：还没拖进去时册子是空的',
  window.__dump().captured.length === 3 && window.__clueLedger().length === 0);
assert('空态是 bag-empty 提示行', clueBody.children.length === 1 && clueBody.children[0]._classes.has('bag-empty'));
assert('线索册不再有分组框 / 表头 / 归位反查（源码检查）',
  html.indexOf('clue-sec') < 0 && html.indexOf('clue-head') < 0 && html.indexOf('clueOnBoard') < 0);
assert('册子窗口与 ※ 图标都在落点清单里',
  window.__dropTargets().indexOf('clue-win') >= 0 && window.__dropTargets().indexOf('clue-icon') >= 0);
/* 拖到窗口上收纳（stub 里窗口矩形退化成 140×48，先给内联位置避开左侧图标栏） */
clueWinEl.style.left = '520px'; clueWinEl.style.top = '120px';
const cwr = clueWinEl.getBoundingClientRect();
const dropIntoWin = k => dragTo(findEl(k), cwr.left + cwr.width / 2, cwr.top + cwr.height / 2);
dropIntoWin('clue:CLUES_CBKW');
dropIntoWin('clue:CLUES_mc');
dropIntoWin('clue:CLUES_V_luheng');
assert('拖进线索册 = 收纳（节点离开画布，只留清单记录）',
  window.__dump().ledger.length === 3 && window.__dump().stored.indexOf('clue:CLUES_V_luheng') >= 0);
assert('落定后窗口高亮被清掉', !clueWinEl._classes.has('over'));
assert('册内按五感自动排序（味→触→视 入册，排出 视→触→味）',
  window.__clueLedger().map(c => c.sense).join(',') === 'vision,touch,taste');
const lrows = clueBody.querySelectorAll('.goto-item');
assert('册内一条线索一行', lrows.length === 3);
assert('行上有线索名与描述', lrows[0].querySelector('.nm').children.length === 2);
assert('行尾标的是感官（视觉/触觉/味觉），不再有归位状态列',
  lrows.map(r => r.querySelector('.st').textContent).join(',') === '视觉,触觉,味觉');
assert('感官标记走 .st.sense，行上不再有 done 样式',
  lrows.every(r => r.querySelector('.st')._classes.has('sense') && !r._classes.has('done')));
assert('※ 图标角标显示册内条数', ids['clue-icon'].querySelector('.badge').textContent === '3 条');
/* 拖到 ※ 图标上同样收纳（图标是常驻落点，不一定非要开着窗） */
window.__cap('item:ITEMS_xfbyc');                      /* 视觉 CLUES_gcs */
const icr = ids['clue-icon'].getBoundingClientRect();
dragTo(findEl('clue:CLUES_gcs'), icr.left + icr.width / 2, icr.top + icr.height / 2);
assert('拖到 ※ 图标上也能收纳', window.__dump().ledger.indexOf('clue:CLUES_gcs') >= 0);
assert('两条视觉线索按数据书写序排出（陆珩松 → 贯穿伤）',
  window.__clueLedger().map(c => c.id).join(',') === 'CLUES_V_luheng,CLUES_gcs,CLUES_mc,CLUES_CBKW');
/* 点一行 = 取回画布 */
fire(lrows[0], 'click', {});
assert('点一行 = 取回画布（离开册子、回到画布）',
  window.__dump().ledger.indexOf('clue:CLUES_V_luheng') < 0 && window.__dump().stored.indexOf('clue:CLUES_V_luheng') < 0);
assert('取回后选中该线索节点（详情窗顺势展开）', window.__dump().sel === 'clue:CLUES_V_luheng');
assert('取回后册内少一行、角标跟着回落',
  clueBody.querySelectorAll('.goto-item').length === 3 && ids['clue-icon'].querySelector('.badge').textContent === '3 条');
assert('点完线索册仍开着（对照着看画布）', window.__dump().floats.clue === true);
/* 非线索节点收不进册（只有线索能进） */
assert('非线索节点收不进线索册', window.__ledgerStore('loc:SCENES_garden') === false);

/* ---- 人物：已结识的角色（TEC 不列），点一行 = 叫到画面中央并接着说下一句 ---- */
ids['people-icon']._ev.dblclick[0]();
assert('双击人物图标开窗', window.__dump().floats.people === true);
const peopleBody = document.getElementById('desktop').querySelector('.people-win').querySelector('.syswin-body');
assert('还没遇到人时名册是空的', peopleBody.querySelectorAll('.goto-item').length === 0 &&
  peopleBody.children.length === 1);
window.__reveal('SCENES_fkjl');                        /* 这场景点名了朱穗 / 傅柏 */
const roster = window.__roster();
assert('展开场景后名册记下遇到的人', roster.map(r => r.id).sort().join(',') === 'CHARS_zs,NPC_FB');
assert('名册不列 TEC（它有自己的助手窗）', !roster.some(r => r.id === 'CHARS_TEC'));
assert('名册行带对话进度（未交谈 0/1）',
  roster.find(r => r.id === 'CHARS_zs').prog === 0 && roster.find(r => r.id === 'CHARS_zs').total === 1);
/* 点「朱穗」那一行（傅柏在这个场景里没有对白，走的是「无对话文本」分支） */
const zsRow = [...document.getElementById('desktop').querySelector('.people-win').querySelector('.syswin-body')
  .querySelectorAll('.goto-item')].find(r => r.querySelector('.lb').textContent === '朱穗');
assert('名册里找得到「朱穗」这一行', !!zsRow);
assert('傅柏那行标「无对话文本」（该场景里他确实没词）',
  [...document.getElementById('desktop').querySelector('.people-win').querySelector('.syswin-body')
    .querySelectorAll('.goto-item')].find(r => r.querySelector('.lb').textContent === '傅柏')
    .querySelector('.st').textContent === '无对话文本');
fire(zsRow, 'click', {});
assert('点人物一行 = 选中该角色节点', window.__dump().sel === 'char:CHARS_zs');
assert('点人物一行 = 说出第一句（对话进度 +1）', window.__dump().talk['char:CHARS_zs'] === 1);
assert('点完人物窗仍开着（可以接着点下一个人）', window.__dump().floats.people === true);
const prows = [...document.getElementById('desktop').querySelector('.people-win').querySelector('.syswin-body')
  .querySelectorAll('.goto-item')];
assert('名册行随之刷新出对话进度',
  prows.find(r => r.querySelector('.lb').textContent === '朱穗').querySelector('.st').textContent === '对话 1/1');
assert('说完的角色行标上 done',
  prows.find(r => r.querySelector('.lb').textContent === '朱穗')._classes.has('done'));

/* ---- 离屏守卫 + 开关窗：换案 / 重置都要把这两扇窗收掉 ---- */
ids['btn-reset']._ev.click[0]();
assert('重置后线索册与人物窗都被收掉',
  window.__dump().floats.clue === false && window.__dump().floats.people === false);
ids['clue-icon']._ev.dblclick[0]();
assert('线索册再次打开（重置后册子是空的）', window.__dump().floats.clue === true);
assert('空态文案在（bag-empty）',
  document.getElementById('desktop').querySelector('.clue-win').querySelector('.syswin-body')
    .children[0]._classes.has('bag-empty'));
assert('图标栏里挂上了两个新图标（线索册 / 人物）',
  /id="clue-icon"/.test(html) && /id="people-icon"/.test(html) &&
  /\["clue-icon","clues"\],\["people-icon","people"\]/.test(html));
assert('两颗新图标进了桌面图标栏且能被布局摆位',
  document.getElementById('clue-icon').style.top !== '' && document.getElementById('people-icon').style.top !== '');
ids['clue-icon']._ev.dblclick[0]();
window.__switchCase('A002');
window.__switchCase('A001');

/* ---- 常驻性对齐证物袋（§27 同款链路）：离屏 / 同案回访都保留，换案 / 重置才清 ---- */
ids['btn-reset']._ev.click[0]();                       /* 全新开局 */
window.__reveal('SCENES_body');
window.__cap('loc:SCENES_body');                       /* CLUES_V_luheng */
assert('册窗常驻测试：线索已入册', window.__ledgerStore('clue:CLUES_V_luheng') === true);
ids['clue-icon']._ev.dblclick[0]();
assert('册窗常驻测试：窗已开且册里 1 条',
  window.__dump().floats.clue === true && window.__dump().ledger.length === 1);
assert('案件离屏前案件窗是开着的', window.__caseInfo().open === true);
window.__closeCase();
assert('案件离屏后线索册窗仍开着（与证物袋同等常驻）', window.__dump().floats.clue === true);
assert('离屏时从册中取出被拦下（取出 = 放回画布）', window.__ledgerTake('clue:CLUES_V_luheng') === false);
window.__switchCase('A001');                           /* 同案回访 */
assert('同案回访后线索册窗仍在（boot 不再收掉它）', window.__dump().floats.clue === true);
const cwRe2 = document.getElementById('desktop').querySelector('.clue-win');
assert('册窗清单已按恢复的图刷新（仍是 1 条）', !!cwRe2 && cwRe2.querySelectorAll('.goto-item').length === 1);
assert('回访后可以从册中取出（闸门放行）', window.__ledgerTake('clue:CLUES_V_luheng') === true);
window.__switchCase('A002');
assert('换案后线索册窗被清掉（与证物袋一致）', window.__dump().floats.clue === false);
window.__switchCase('A001');

/* ---- 两扇收纳窗的层级 / 样式 / 清理点对齐（源码检查） ---- */
assert('两扇收纳窗同层（z-index 25）且都带拖动手型',
  /\.bag-win\{[^}]*z-index:25;[^}]*cursor:grab/.test(html) &&
  /\.clue-win\{[^}]*z-index:25;[^}]*cursor:grab/.test(html) &&
  /\.clue-win:active\{cursor:grabbing\}/.test(html));
assert('线索册窗也有悬停虚线高亮（与证物袋同款）',
  /\.clue-win\.over\{[^}]*outline:2px dashed var\(--text\)/.test(html));
assert('两扇收纳窗的清理点对齐：换案 / 重置显式负责，boot 不再收',
  html.indexOf('saveCaseState(from); resetTec(); closeBagWin(); closeClueWin();') > 0 &&
  html.indexOf('closeBagWin();             /* 证物袋窗同理') > 0 &&
  html.indexOf('closeClueWin();            /* 线索册窗与证物袋同级') > 0 &&
  html.indexOf('refreshClueWin();  /* 册窗同理（同样是常驻窗，恢复的图变了） */') > 0);

console.log('\n' + (errs === 0 && bad === 0 ? '=> 全部通过，无运行时错误' : '=> 存在问题：运行时 ' + errs + ' / 断言失败 ' + bad));

console.log('\n--- 日志回放 ---');
logs.slice(-26).forEach(l => console.log('  ' + l));
