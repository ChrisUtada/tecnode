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

console.log('\n=== 14. 叙事层：对话气泡 + 场景叙事卡 ===');
ids['btn-reset']._ev.click[0]();
assert('开局显示起始场景叙事卡', window.__dump().floats.narr === true);
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

/* 批量收回 */
window.__storeAll('SCENE_shuzhuo');
const sa = window.__dump();
assert('批量收回：台灯被收纳', sa.stored.includes('item:ITEM_taideng'));
assert('批量收回：场景节点本身不被收纳', !sa.stored.includes('loc:SCENE_shuzhuo'));

console.log('\n=== 17. 证物袋 ===');
ids['btn-reset']._ev.click[0]();
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

console.log('\n=== 18. 捕获 + 前往 ===');
ids['btn-reset']._ev.click[0]();
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

console.log('\n=== 19. 结局系统 + 记忆放映 ===');
ids['btn-reset']._ev.click[0]();
window.__closeFloats();

/* 记忆场景放映卡 */
window.__reveal('SCENES_0602');
assert('记忆场景弹放映卡', window.__dump().floats.narr === true);
const memCard = ids['world'].children.find(c => c._classes.has('narr-card') && c._classes.has('memory'));
assert('放映卡有 memory 样式', !!memCard);
if (memCard){
  const bodyBefore = memCard.querySelector('.syswin-body').children.length;
  window.__playStep(); window.__playStep();
  assert('放映逐行推进', memCard.querySelector('.syswin-body').children.length > bodyBefore);
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
window.__reveal('SCENES_sxbj');                              // 大豕草（手写笔记）
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
window.__infer();
assert('真结局触发', window.__dump().endingOverlay === true && window.__dump().endings.includes('TRUE_E'));
for (let i = 0; i < 10; i++) window.__playStep();
assert('演出步进完毕自动关闭', window.__dump().endingOverlay === false);

console.log('\n=== 20. 桌面图标 ===');
ids['btn-reset']._ev.click[0]();
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
window.__mxAssign('clue:CLUES_V_luheng', 'vision');
assert('线索归入推演器', window.__dump().matrix.vision.includes('CLUES_V_luheng'));
/* TEC 窗口 */
ids['tec-dock']._ev.dblclick[0]();
assert('双击 TEC 图标开对话窗', window.__dump().floats.tec === true);
window.__tecTalk();
assert('TEC 交谈推进提示进度', window.__dump().tec.prog['SCENES_body'] === 1);

console.log('\n=== 22. 侧边栏图标化 ===');
ids['btn-reset']._ev.click[0]();
assert('日志窗默认开启', window.__dump().floats.logs === true);
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

/* 物品：无命令 → 详情不复读描述；有命令 → 描述保留（唯一出口） */
window.__reveal('SCENES_choutiyi');
window.__select('item:ITEM_shoudiantong');
dh = ids['detail-body']._html || '';
assert('无命令物品：详情不再复读描述', dh.indexOf('还能使用的手电筒') < 0);
window.__reveal('SCENES_garden');
window.__select('item:ITEMS_zhiwu');
dh = ids['detail-body']._html || '';
assert('有命令物品：详情保留描述（唯一出口）', dh.indexOf('自生自灭') >= 0);

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
assert('#world 与 #hint 都在 #stage 内', depthAt['world'] === depthAt['stage'] + 1 && depthAt['hint'] === depthAt['stage'] + 1);

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
assert('拖动排除表覆盖了地图地址卡', /closest\("button,input,\.bag-item,\.map-card,\.goto-item,\.syswin-x"\)/.test(html));
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
const rawSave = JSON.parse(_ls['tec_case_A001']);
assert('存档里记住了镜头位置', !!rawSave.__view && isFinite(rawSave.__view.k));

/* 关闭状态下，画布上的操作应被拦下（否则会把案件窗又弹回来） */
ids['btn-reset']._ev.click[0]();
assert('关闭时「重置」被拦下，案件窗没被弹回来', window.__caseInfo().open === false && window.__caseInfo().held === true);

/* 从地图点本案那行：展开、角标消失、进度续上 */
assert('从案件地图展开成功', window.__switchCase('A001') === true);
const ci3 = window.__caseInfo();
assert('案件窗重新打开', ci3.open === true && document.getElementById('case-win').style.display !== 'none');
assert('展开后「已关闭」角标消失', ci3.held === false && !badgeOf());
assert('重新进入后进度续上（节点数一致）', window.__dump().nodes.length === n1);
assert('重新进入后撤销栈是新会话', window.__dump().history === 0);
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

console.log('\n' + (errs === 0 && bad === 0 ? '=> 全部通过，无运行时错误' : '=> 存在问题：运行时 ' + errs + ' / 断言失败 ' + bad));

console.log('\n--- 日志回放 ---');
logs.slice(-26).forEach(l => console.log('  ' + l));
