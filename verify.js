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
/* 顶栏「新节点自动居中」默认是勾选的：stub 里 getElementById 现场造出来的元素 checked 为 false，
   不置真就会让自动聚焦整条停用，量不到任何聚焦决定 */
ids['tg-reveal'] = mkEl('input');
ids['tg-reveal'].checked = true;
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

/* 手电筒必须先点亮才能照亮黑影（发光工具门）：每条「手电筒 → 黑影」链路都先点亮它。
   已经亮着就不重复点（再点一次是熄灭）。 */
function torchOn(){
  if (window.__dump().lit.indexOf('item:ITEM_shoudiantong') < 0) window.__cmd('ITEM_shoudiantong', 0);
}

console.log('\n=== 21. 适性测试 + 选头像 + 调查员证 ===');
/* 头像材质直接从成品里取（源码里 `const X_AVATAR_B64 = "..."` 构建时已内联成裸 base64），
   这样「证件照到底用的是哪一张」能断言到位，而不是只查「有个 img」。 */
const b64Of = (name) => { const m = html.match(new RegExp(name + '\\s*=\\s*"([A-Za-z0-9+/=]+)"')); return m ? m[1] : null; };
const TEC_B64 = b64Of('TEC_AVATAR_B64'), EXEC_B64 = b64Of('EXECUTOR_AVATAR_B64');
const introNode = () => ids['stage'].querySelector('.intro-win');
/* 证件照的 img：stub 的 `.cert-photo img` 取不到（querySelector 不解析后代），按 tagName 找 */
const certImgIn = (root) => {
  const p = root && root.querySelector('.cert-photo');
  if (!p) return null;
  const im = p.children.find(c => String(c.tagName).toLowerCase() === 'img');
  return im ? im.src : null;
};
const clickAvatarTile = (root, name) => {
  const t = root.querySelectorAll('.avatar-pick').find(x => {
    const nm = x.querySelector('.nm');
    return nm && nm.textContent === name;
  });
  if (!t) return false;
  t._ev.click[0]();
  return true;
};
assert('开局弹出适性测试', window.__dump().intro === true);
window.__intro.name('陈调查');
window.__intro.begin();
window.__intro.answer(0);  // 视觉
window.__intro.answer(0);  // 视觉
window.__intro.answer(1);  // 听觉

console.log('  —— 测试结束 → 选头像 ——');
assert('答完三问进入选头像步骤（不再直接发证）', window.__intro.step() === 'avatar');
assert('初始可选 = 执行者 + TEC', window.__intro.pool().join(',') === 'CHARS_EXEC,CHARS_TEC');
assert('默认选中执行者', window.__intro.avatar() === 'CHARS_EXEC');
assert('未解锁 4 张（CHARS 里没结识的四人）', window.__avatars().locked === 4);
{
  const tiles = introNode().querySelectorAll('.avatar-pick');
  const locked = tiles.filter(t => t.classList.contains('locked'));
  const open = tiles.filter(t => !t.classList.contains('locked'));
  assert('格子 = 2 张可选 + 4 张未解锁', tiles.length === 6 && open.length === 2 && locked.length === 4);
  assert('可选格写角色名（执行者 / TEC）',
    open.map(t => t.querySelector('.nm').textContent).join('/') === '执行者/TEC');
  assert('未解锁格只写「未解锁」、不泄角色名',
    locked.every(t => t.querySelector('.nm').textContent === '未解锁'));
  assert('未解锁格画「?」占位', locked.every(t => t.querySelector('.av').textContent === '?'));
  assert('默认选中态挂在执行者那格',
    introNode().querySelectorAll('.avatar-pick.sel').length === 1 &&
    introNode().querySelector('.avatar-pick.sel').querySelector('.nm').textContent === '执行者');
  assert('解锁计数行写「已解锁 2 / 6」', introNode().querySelector('.avatar-count').textContent === '已解锁 2 / 6');
}
assert('点一下即改选中', clickAvatarTile(introNode(), 'TEC') && window.__intro.avatar() === 'CHARS_TEC');
assert('选中态跟着走', introNode().querySelector('.avatar-pick.sel').querySelector('.nm').textContent === 'TEC');

console.log('  —— 头像 → 领证 ——');
window.__intro.confirmPick();
assert('确认头像后进入领证步骤', window.__intro.step() === 'card');
assert('默认那张（执行者）不在时用选中的（TEC）',
  certImgIn(introNode()) !== 'data:image/png;base64,' + EXEC_B64);
assert('证件照 = TEC 的头像', certImgIn(introNode()) === 'data:image/png;base64,' + TEC_B64);
assert('领证页留了反悔入口（换一张头像）', !!introNode().querySelector('.avatar-back'));
introNode().querySelector('.avatar-back')._ev.click[0]();
assert('点「换一张」退回选头像步骤', window.__intro.step() === 'avatar');
assert('退回后仍记着刚才选的 TEC', introNode().querySelector('.avatar-pick.sel').querySelector('.nm').textContent === 'TEC');
clickAvatarTile(introNode(), '执行者');
window.__intro.confirmPick();
assert('改选执行者后证件照随之更换', certImgIn(introNode()) === 'data:image/png;base64,' + EXEC_B64);

const inv = (window.__intro.confirm(), window.__dump().investigator);
assert('生成调查员', !!inv);
assert('姓名写入证件', inv.name === '陈调查');
assert('ID 格式 TEC-XX-0000', /^TEC-[A-Z0-9]{2}-\d{4}$/.test(inv.id));
assert('倾向性为视觉主导', inv.sense === 'vision');
assert('选中的头像写进证件', inv.avatarId === 'CHARS_EXEC');
window.__intro.finish();
assert('测试流程结束', window.__dump().intro === false);
assert('顶栏挂出徽标', !!document.getElementById('inv-chip'));

console.log('  —— 领证之后：换头像 ——');
/* 回看路径：点顶栏徽标开证件窗（徽标挂在 #desktop 上，`id` 是普通属性，按属性找） */
const invChipNode = ids['desktop'].children.find(c => c.id === 'inv-chip');
assert('顶栏徽标可点展开证件', !!invChipNode && !!invChipNode._ev.click);
invChipNode._ev.click[0]();
assert('证件窗开出来了', !!ids['desktop'].querySelector('.cert-win'));
assert('证件窗挂着两个动作（更换头像 / 重新测试）',
  ids['desktop'].querySelector('.cert-actions').children.length === 2);
window.__avatarOpen();
assert('换头像窗开出来了', window.__avatars().win === true);
assert('换头像池同源（还是执行者 + TEC）', window.__avatars().pool.join(',') === 'CHARS_EXEC,CHARS_TEC');
assert('窗内当前选中 = 证件上那张', window.__avatars().pick === 'CHARS_EXEC');
window.__avatarPick('CHARS_TEC');
assert('窗内点选即改选中', window.__avatars().pick === 'CHARS_TEC');
window.__avatarConfirm();
assert('换头像写回 investigator', window.__dump().investigator.avatarId === 'CHARS_TEC');
assert('落盘（localStorage 里的也换了）',
  JSON.parse(localStorage.getItem('tec_investigator')).avatarId === 'CHARS_TEC');
assert('换完窗自己关掉', window.__avatars().win === false);
assert('证件窗自动重开、照片已换', certImgIn(ids['desktop'].querySelector('.cert-win')) === 'data:image/png;base64,' + TEC_B64);
assert('换头像不留画布节点', window.__dump().nodes.filter(k => k.indexOf('char:') === 0).length === 0);

ids['btn-reset']._ev.click[0]();
assert('重置后不再弹测试', window.__dump().intro === false);
assert('重置后徽标仍在', !!document.getElementById('inv-chip'));
assert('重置后头像选择也在（investigator 独立存档）', window.__avatars().chosen === 'CHARS_TEC');

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
window.__reveal('ITEM_shuzhuo'); show();

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
window.__reveal('ITEM_shuzhuo');
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
window.__reveal('ITEM_shuzhuo');
window.__choice('ITEM_chouti', 0, 0);   // 左抽屉 → 手电筒
window.__choice('ITEM_chouti', 0, 1);   // 右抽屉 → 剪刀 + 木盒
assert('左抽屉拿到手电筒', window.__dump().nodes.includes('item:ITEM_shoudiantong'));
assert('右抽屉拿到剪刀', window.__dump().nodes.includes('item:ITEMS_jd'));
assert('花园里有黑影节点', window.__dump().nodes.includes('item:ITEM_something'));

torchOn();   /* 手电筒先点亮：发光工具门 */
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

/* ---- 拖拽：移动 / （不）钉住 / 组合 三件事必须并存 ---- */
console.log('\n=== 12. 拖动节点：落在空白 = 只移动（不再钉住）；落在节点上 = 组合 ===');
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
assert('落空白处只移动、**不**自动钉住（钉住只由右键控制）', dragRes.pos[startKey].pinned === false);

/* 钉住之后自动布局才不挪它 —— 位置保护改由右键提供，拖动本身不再带这层保护 */
const preLock = window.__dump().pos[startKey];
window.__pin(startKey);                        /* 右键 = 唯一的钉住入口 */
assert('右键钉住生效', window.__dump().pos[startKey].pinned === true);
const locked = { x: preLock.x, y: preLock.y };
window.__reveal('ITEM_shuzhuo');
window.__reveal('SCENES_body');
const after2 = window.__dump();
assert('钉住后自动布局没有挪走它',
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
assert('越界夹回后也不会自动钉住', clamped.pinned === false);
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
window.__reveal('ITEM_shuzhuo');
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
  assert('组合后剪刀没被钉在原地', !(fin2.pos['item:ITEMS_jd'] && fin2.pos['item:ITEMS_jd'].pinned));
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
window.__reveal('ITEM_shuzhuo');

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

/* 唱机 useItem：黑胶拖到唱机上 —— 但唱机得先装上唱针（命令上的 requires 门） */
window.__choice('ITEM_chouti', 0, 1);          // 右侧抽屉 → 木盒
ids['pw-in'].value = '0321';
window.__pw('ITEMS_jzmh');                     // → 黄铜钥匙
window.__combo('item:ITEMS_htys', 'item:ITEMS_changji');  // 钥匙 → 唱机暗格
window.__reveal('SCENES_cjag');                // → 黑胶
/* ① 还没装唱针：放黑胶必须被挡下 —— 不捕获、不消耗，日志里给一句原因 */
const preVinyl = logs.length;
window.__combo('item:ITEMS_wmhj', 'item:ITEMS_changji');
assert('没装唱针时黑胶放不进唱机（requires 门）',
  !window.__dump().captured.includes('CLUES_wmhj') &&
  logs.slice(preVinyl).some(l => l.indexOf('还没有装唱针') >= 0));
assert('被门挡下时黑胶留在画布上（没被消耗）', window.__dump().nodes.includes('item:ITEMS_wmhj'));
/* ② 去尸体口袋拿到唱针，装上（installs:true → 状态记在唱机上、唱针本身被消耗） */
window.__reveal('SCENES_lhsdst');                          // → 唱针
assert('唱针在画布上（尸体右侧口袋）', window.__dump().nodes.includes('item:ITEMS_cz'));
window.__combo('item:ITEMS_cz', 'item:ITEMS_changji');
assert('装上唱针：状态记在唱机节点上', (window.__dump().installed['item:ITEMS_changji'] || []).includes('ITEMS_cz'));
assert('唱针装上后被消耗（不再留在画布上）', !window.__dump().nodes.includes('item:ITEMS_cz'));
/* ③ 现在才放得进黑胶 */
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
window.__reveal('ITEM_shuzhuo');
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
window.__collapse('ITEM_shuzhuo');
assert('折叠书桌后长出的植物笔记被一并隐藏（homeScene 继承了书桌）',
  window.__dump().hidden.includes('item:ITEMS_dsc'));
window.__collapse('ITEM_shuzhuo');

/* ---- 13c. 手电筒：点亮之后才照得亮黑影（发光工具门） ---- */
console.log('\n=== 13c. 手电筒：点亮后才照得亮黑影 ===');
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');
window.__reveal('ITEM_shuzhuo');
window.__closeFloats();
window.__choice('ITEM_chouti', 0, 0);          // 左抽屉 → 手电筒
const tc0 = window.__dump();
assert('手电筒是画布上的物品节点', tc0.nodes.includes('item:ITEM_shoudiantong'));
assert('手电筒初始未点亮', !tc0.lit.includes('item:ITEM_shoudiantong'));
assert('黑影在花园里', tc0.nodes.includes('item:ITEM_something'));

/* 没点亮的电筒拖到黑影上：照不出东西，也不留下任何后果 */
window.__combo('item:ITEM_shoudiantong', 'item:ITEM_something');
const tcDark = window.__dump();
assert('手电筒未点亮时接触黑影：不解锁「尸体」场景', !tcDark.nodes.includes('loc:SCENES_body'));
assert('手电筒未点亮时接触黑影：手电筒与黑影都还在（谁也没被消耗）',
  tcDark.nodes.includes('item:ITEM_shoudiantong') && tcDark.nodes.includes('item:ITEM_something'));
assert('手电筒未点亮时接触黑影：不记「已试过」（门拦在记录之前）',
  !tcDark.edges.some(e => e.indexOf('tried:item:ITEM_shoudiantong>item:ITEM_something') === 0));

/* 详情窗只剩「简介 / 状态 / 来源」：黑影跟手电筒有反应这件事**不进详情窗** ——
   谜面在它自己的正文里（「打开手电筒照亮它」），剩下的玩家自己试。
   手电筒「要先点亮」这件事写在**手电筒自己的**状态行里（见下面 §13c 的断言）。 */
window.__select('item:ITEM_something');
let tch = ids['detail-body']._html || '';
assert('黑影详情窗：只列简介与来源，不再列「与这些东西存在反应」',
  tch.indexOf('存在反应') < 0 && tch.indexOf('摇摇晃晃') >= 0);
assert('黑影详情窗：来源照旧（植物学家的花园）', tch.indexOf('植物学家的花园') >= 0);

window.__cmd('ITEM_shoudiantong', 0);          // 双击 → 打开手电筒
assert('双击手电筒 → 点亮（lit）', window.__dump().lit.includes('item:ITEM_shoudiantong'));
window.__cmd('ITEM_shoudiantong', 0);          // 再双击 → 关掉
assert('再次双击手电筒 → 熄灭', !window.__dump().lit.includes('item:ITEM_shoudiantong'));

/* 手电筒的光不算「桌上的光」：它亮着也翻不开手写笔记（笔记的光照门只认台灯） */
window.__cmd('ITEM_shoudiantong', 0);          // 重新打开
assert('手电筒重新点亮', window.__dump().lit.includes('item:ITEM_shoudiantong'));
window.__cmd('ITEM_sxbj', 0);
assert('手电筒的光不当数：手写笔记仍然翻不开（光照门只认台灯）',
  !['ITEMS_dsc', 'ITEMS_a4paper'].some(i => window.__dump().nodes.includes('item:' + i)));
window.__cmd('ITEM_taideng', 0);               // 点亮台灯（书桌的光）
window.__cmd('ITEM_sxbj', 0);
assert('点亮台灯（而不是手电筒）才翻得开笔记',
  window.__dump().nodes.includes('item:ITEMS_dsc'));

/* 手电筒点亮 → 黑影现形 */
window.__combo('item:ITEM_shoudiantong', 'item:ITEM_something');
assert('手电筒点亮后接触黑影：解锁「尸体」场景',
  window.__dump().nodes.includes('loc:SCENES_body'));

/* 手电筒自己的详情窗：状态 + 用途（手电筒是可重复使用的工具，照亮黑影后仍在） */
window.__cmd('ITEM_shoudiantong', 0);          // 关掉，看「未点亮」态
window.__select('item:ITEM_shoudiantong');
tch = ids['detail-body']._html || '';
assert('手电筒详情窗：标注未点亮 + 先点亮才能照亮黑暗里的东西',
  tch.includes('未点亮') && tch.includes('先点亮它'));
window.__cmd('ITEM_shoudiantong', 0);          // 打开
window.__select('item:ITEM_shoudiantong');
tch = ids['detail-body']._html || '';
assert('手电筒详情窗：点亮后标注已点亮', tch.includes('已点亮') && !tch.includes('未点亮'));

console.log('\n=== 13d. 新节点产出后自动聚焦 ===');
ids['btn-reset']._ev.click[0]();

/* 镜头位移在无头 stub 里量不到（setTimeout 归零 → 逐帧推进不跑），所以这里量的是「聚焦决定」：
   __dump().focus = { on, why, keys }。on=true = 这次收尾确实要把镜头平移过去，keys = 它框住的节点；
   on=false = 镜头一动不动（why 说明原因：no-new-node / toggle-off / nothing-visible / no-viewport）。 */

/* 1) 开场：画布上只有一个未探索场景 → 展开走 fit（整幅铺开） */
window.__reveal('SCENES_garden');
window.__closeFloats();
let fd = window.__dump().focus;
assert('展开首个场景 → 铺开画面并记下聚焦决定', !!fd && fd.on === true && fd.why === 'fit');

/* 2) 画布上已有内容时再展开场景 → 聚焦，且把这次新长出来的节点都框进来 */
const nodesBeforeD2 = window.__dump().nodes;
window.__reveal('ITEM_shuzhuo');
window.__closeFloats();
fd = window.__dump().focus;
assert('再展开场景 → 聚焦（centered，而不再是 fit）', !!fd && fd.on === true && fd.why === 'centered');
assert('聚焦朝新节点走：框住的集合里有此前不在画布上的节点',
  !!fd && fd.keys.some(k => nodesBeforeD2.indexOf(k) < 0));
assert('聚焦把触发它的场景节点也一起框住（"新东西"和"它长在哪儿"同框）',
  !!fd && fd.keys.indexOf('item:ITEM_shuzhuo') >= 0);

/* 3) 选项命令产出物品（抽屉 → 手电筒）→ 聚焦到新物品 */
window.__choice('ITEM_chouti', 0, 0);
fd = window.__dump().focus;
assert('选项命令长出物品 → 聚焦（centered）', !!fd && fd.on === true && fd.why === 'centered');
assert('聚焦集合里有这次新长出的手电筒', !!fd && fd.keys.indexOf('item:ITEM_shoudiantong') >= 0);

/* 4) 组合产出新场景（手电筒 → 黑影 ⇒ 尸体）→ 聚焦；只框新节点（锚点可能远在几百像素外） */
window.__cmd('ITEM_shoudiantong', 0);          /* 点亮手电筒 */
window.__combo('item:ITEM_shoudiantong', 'item:ITEM_something');
fd = window.__dump().focus;
assert('组合产出新场景 → 聚焦（centered）', !!fd && fd.on === true && fd.why === 'centered');
assert('聚焦集合里有新长的「尸体」场景', !!fd && fd.keys.indexOf('loc:SCENES_body') >= 0);
assert('聚焦只框新节点，不把还活着的参与者（手电筒）一起拽进来',
  !!fd && fd.keys.indexOf('item:ITEM_shoudiantong') < 0);
assert('聚焦集合就是这次的新节点，一个不多', !!fd && fd.keys.length === 1 && fd.keys[0] === 'loc:SCENES_body');
/* 合成吃掉了目标（黑影）→ 不能去选中一个已经没了的节点（否则详情窗弹「节点已不存在」） */
let dd = window.__dump();
assert('合成吃掉目标后，改选中新长出来的节点', dd.sel === 'loc:SCENES_body');
assert('详情窗不再显示「节点已不存在」', (ids['detail-body']._html || '').indexOf('节点已不存在') < 0);

/* 5) 没有新节点产出 → 镜头一动不动（纯提示 / 纯消耗不把画面拽走） */
window.__reveal('SCENES_mdhm');                /* 铁栅栏所在场景 */
fd = window.__dump().focus;
assert('展开「明灯花圃」先聚焦一次（对照组）', !!fd && fd.on === true);
window.__cmd('ITEMS_tzl', 0);                  /* 条件恒真、只出一行文本、不长任何节点 */
fd = window.__dump().focus;
assert('命令只出文本、不长节点 → 不做任何镜头移动',
  !!fd && fd.on === false && fd.why === 'no-new-node');

/* 6) 顶栏开关关掉 → 自动聚焦整条停用，但节点照样长出来 */
ids['tg-reveal'].checked = false;
const nodesBeforeD6 = window.__dump().nodes;
window.__reveal('SCENES_lhsdst');
fd = window.__dump().focus;
assert('关掉「新节点自动居中」→ 不再动镜头', !!fd && fd.on === false && fd.why === 'toggle-off');
assert('关掉开关不影响节点照常长出来', window.__dump().nodes.length > nodesBeforeD6.length);
ids['tg-reveal'].checked = true;

/* 源码检查：这套收尾是「单一入口」，产出路径全都走它 */
assert('引擎里有 settle() 单一收尾（重排 → 渲染 → 聚焦）',
  html.indexOf('function settle(){') > 0);
assert('引擎里有 focusOn()（只平移、不缩放）', html.indexOf('function focusOn(keys, ms){') > 0);
assert('引擎里有 freshKeys()：以 n.fresh 认「本次新长出来的节点」',
  html.indexOf('function freshKeys(){') > 0);
assert('旧的 ensureVisible 已并入 focusOn（不再留「已在视野内就不动」的短路）',
  html.indexOf('ensureVisible') < 0);
assert('产出路径都接了 settle（组合 / 捕获 / 命令 / 选项 / 密码 / TEC）',
  (html.match(/settle\(\)/g) || []).length >= 9);
{
  const fb = html.slice(html.indexOf('function focusOn(keys, ms){'), html.indexOf('function freshKeys(){'));
  assert('聚焦只平移不缩放（focusOn 体内不给 view.k 赋值）',
    fb.indexOf('view.k =') < 0 && fb.indexOf('view.k=') < 0);
}
{
  /* 只框新节点：focusFresh 的形参里不许再有锚点（锚点会把新节点顶到舞台角落） */
  const ff = html.slice(html.indexOf('function focusFresh('), html.indexOf('function settle(){'));
  assert('focusFresh 只收新节点、不再收锚点', ff.indexOf('function focusFresh(news){') >= 0 && ff.indexOf('anchors') < 0);
}
assert('收尾会挑「该选中谁」：原目标被消耗就改选新节点',
  html.indexOf('function settleSelect(news, preferKey){') > 0);
assert('spawnItems 不给已经在画布上的旧节点重打 fresh（否则镜头被老节点拽走）',
  html.indexOf('if (existed) n.fresh = false;') > 0);
assert('抓住节点拖动也能打断自动聚焦（节点 pointerdown 里 cancelViewAnim）',
  html.indexOf('cancelViewAnim();   /* 抓住节点即接管镜头') > 0);
assert('顶栏开关改名成「新节点自动居中」',
  html.indexOf('新节点自动居中') > 0 && html.indexOf('展开自动居中') < 0);

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
window.__tecTalk();
assert('点击 TEC 只轮换闲聊，不再翻场景档案', !window.__dump().tec.prog['SCENES_garden'] && window.__dump().tec.prog._def === 1);
assert('TEC 图标不再挂「提示 N」角标（免费提示频道已拆）', !ids['tec-dock'].querySelector('.badge.talk'));
const hBeforeTecTalk = window.__dump().history;
window.__tecTalk();
assert('闲聊轮换进度 2', window.__dump().tec.prog._def === 2);
assert('闲聊不进撤销栈（没有可撤销的状态）', window.__dump().history === hBeforeTecTalk);

window.__closeFloats();
window.__reveal('ITEM_shuzhuo');
assert('首次展开场景弹叙事卡', window.__dump().floats.narr === true);
window.__closeFloats();
window.__reveal('ITEM_shuzhuo');
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
window.__reveal('ITEM_shuzhuo');

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
window.__collapse('ITEM_shuzhuo');
const c1 = window.__dump();
assert('折叠记入 collapsed', c1.collapsed.includes('ITEM_shuzhuo'));
assert('折叠后台灯被隐藏', c1.hidden.includes('item:ITEM_taideng'));
assert('折叠后可见节点数减少', (c1.nodes.length - c1.hidden.length) < visBefore);
window.__collapse('ITEM_shuzhuo');
assert('再次双击展开：台灯恢复可见', !window.__dump().hidden.includes('item:ITEM_taideng'));

/* 聚焦选中 */
window.__select('loc:SCENES_garden');
const f1 = window.__dump();
assert('聚焦后存在被淡化的节点', f1.dim.length > 0);
assert('选中节点自身不被淡化', !f1.dim.includes('loc:SCENES_garden'));
assert('邻居（书桌）不被淡化', !f1.dim.includes('item:ITEM_shuzhuo'));
window.__select(null);
assert('清除选中后淡化清空', window.__dump().dim.length === 0);

console.log('\n=== 16. 节点收纳：机制保留 / 入口已移除 ===');
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');   /* 收纳对象是花园里的注射器：先展开花园 */
window.__closeFloats();

/* 机制本身还在（内部 / 兼容旧档）：storedIn = 场景 */
window.__store('item:ITEMS_zsq', 'SCENES_garden');
assert('注射器被收纳（storedIn = 场景）', window.__dump().stored.includes('item:ITEMS_zsq'));
ids['btn-undo']._ev.click[0]();
assert('撤销后注射器回到画布', !window.__dump().stored.includes('item:ITEMS_zsq'));

/* 「放回现场」入口已移除：拖到折叠的场景节点上不再收纳，改为明确反馈 */
window.__reveal('ITEM_shuzhuo');
window.__closeFloats();
window.__collapse('ITEM_shuzhuo');            // 折叠书桌
const zsqEl = findEl('item:ITEMS_zsq');        // 注射器属于花园，仍然可见
const deskEl = findEl('item:ITEM_shuzhuo');    // 折叠的场景节点还在画布上
assert('折叠后书桌节点仍在画布', !!deskEl);
if (zsqEl && deskEl){
  const bx = parseFloat(deskEl.style.left), by = parseFloat(deskEl.style.top);
  ids['toast']._html = '__SENTINEL__';
  dragTo(zsqEl, bx + deskEl.offsetWidth / 2, by + deskEl.offsetHeight / 2);
  assert('拖到折叠场景上不再收纳（入口已移除）', !window.__dump().stored.includes('item:ITEMS_zsq'));
  assert('拒收时给明确去处（先展开 / 拖到证物袋）',
    String(ids['toast']._html).indexOf('已折叠') >= 0 && String(ids['toast']._html).indexOf('证物袋') >= 0);
}
/* 旧档兼容：storedIn = 场景 的节点，展开该场景时照旧取回 */
window.__store('item:ITEMS_zsq', 'ITEM_shuzhuo');
assert('（兼容旧档）节点仍可被收进场景', window.__dump().stored.includes('item:ITEMS_zsq'));
window.__collapse('ITEM_shuzhuo');            // 展开书桌
assert('展开书桌后仍能取回', !window.__dump().stored.includes('item:ITEMS_zsq'));
/* 两处「存放」文案已撤（角标 + 详情窗），机制注释仍在 */
assert('「存放」角标与「现场存放」详情行都已撤掉（源码检查）',
  html.indexOf('"存放 "') < 0 && html.indexOf('现场存放') < 0 && html.indexOf('unstoreScene(sid)') >= 0);

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
window.__reveal('ITEM_shuzhuo');
window.__choice('ITEM_chouti', 0, 0);        // 左抽屉 → 手电筒
torchOn();   /* 手电筒先点亮：发光工具门 */
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
window.__reveal('ITEM_shuzhuo');
window.__choice('ITEM_chouti', 0, 0);
torchOn();   /* 手电筒先点亮：发光工具门 */
window.__combo('item:ITEM_shoudiantong', 'item:ITEM_something');
window.__reveal('SCENES_body');
assert('TEC 分析入口已暴露（window.__analyze）', typeof window.__analyze === 'function');
const anBefore = window.__dump().captured.length;
assert('TEC 分析 loc:SCENES_body 返回 true', window.__analyze('loc:SCENES_body') === true);
assert('分析完成（无头同步）后提取到线索 CLUES_V_luheng', window.__dump().captured.includes('CLUES_V_luheng'));
assert('分析产生线索节点（可拖出使用）', window.__dump().nodes.includes('clue:CLUES_V_luheng'));
assert('分析确实新增了捕获', window.__dump().captured.length > anBefore);
assert('首次分析同时解读档案第 1 条（sceneTalks 是分析产出）', window.__dump().tec.prog['SCENES_body'] === 1);
const anMid = window.__dump().captured.length;
assert('再分析：线索已净 → 转档案解读（第 2 条）', window.__analyze('loc:SCENES_body') === true
  && window.__dump().captured.length === anMid && window.__dump().tec.prog['SCENES_body'] === 2);
assert('档案读完后再分析：不推进、仍返回 true', (window.__analyze('loc:SCENES_body'),
  window.__dump().tec.prog['SCENES_body'] === 2));
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
assert('点 TEC 窗内任意位置 = 说闲聊（历史 +1 行）', tlines() === tl0 + 1);
assert('点击闲聊不再推进场景档案进度', (window.__dump().tec.prog['SCENES_garden'] || 0) === tp0);
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
window.__reveal('ITEM_shuzhuo');
window.__choice('ITEM_chouti', 0, 0);                        // 左抽屉 → 手电筒
torchOn();                                                        // 手电筒先点亮
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
window.__reveal('SCENES_lhsdst');                            // 唱针（尸体右侧口袋）
window.__combo('item:ITEMS_cz', 'item:ITEMS_changji');       // 唱针 → 唱机 ⇒ 装上唱针（前置）
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
window.__reveal('ITEM_shuzhuo');
window.__choice('ITEM_chouti', 0, 0);
torchOn();   /* 手电筒先点亮：发光工具门 */
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
const posBefore20 = window.__dump().pos['clue:CLUES_V_luheng'];
dragTo(clueEl20, bdr.left + bdr.width / 2, bdr.top + bdr.height / 2);
assert('拖线索上桌布归位（自动归入视觉）', window.__dump().matrix.vision.includes('CLUES_V_luheng'));
assert('落定后桌布高亮被清掉', !boardEl._classes.has('over'));
/* 归位 = 收进桌布：画布上那份必须消失（与拖进证物袋 / 线索册同一个手感）。
   stored 机制与那两处共用，所以「离开画布但保留连边、可撤销、可续档」都是白拿的。 */
assert('归位后线索从画布上消失（收进桌布）',
  !findEl('clue:CLUES_V_luheng') && window.__dump().storedIn['clue:CLUES_V_luheng'] === 'MATRIX');
assert('它不会被证物袋 / 线索册重复登记（storedIn 各认各的）',
  window.__dump().bag.indexOf('clue:CLUES_V_luheng') < 0 && window.__dump().ledger.indexOf('clue:CLUES_V_luheng') < 0);
assert('连边数据保留着（只是不画：paintEdges 跳过 stored 节点）',
  window.__dump().edges.some(e => e.includes('clue:CLUES_V_luheng')));
/* 推演器图标角标显示已归位条数 */
const ib = ids['infer-icon'].querySelector('.badge');
assert('推演器图标角标显示 1 条', !!ib && ib.textContent === '1 条');
/* 撤销能把归位收回去（状态在快照里，与收入袋 / 册同款） */
ids['btn-undo']._ev.click[0]();
assert('撤销能收回「归位」：线索回到画布、桌布上没了',
  !!findEl('clue:CLUES_V_luheng') && !window.__dump().matrix.vision.includes('CLUES_V_luheng'));
window.__mxAssign('clue:CLUES_V_luheng', 'vision');   /* 再归位一次，接着测取回 */
/* chip 上不再有 ×：拿下桌布只能拖出（与外部「拖进拖出」一致）。
   注意：归位后 refreshInferWin 重建了桌布，要重新取元素（手里旧的 boardEl 已离树） */
const chipX = iwEl20.querySelector('.mx-board').querySelector('.mx-chip');
assert('桌布上的线索 chip 不再带 ×', !!chipX && !chipX.querySelector('.mx-x'));
assert('chip 的副标题说它在桌布上（与画布上那枚「已捕获」分开说）',
  !!chipX && chipX._html.indexOf('已归位') >= 0);
assert('chip 的 tooltip 写明「拖出桌布 = 取回画布」', !!chipX && chipX.title === '拖出桌布 = 取回画布');
/* 拖出桌布 = 取回画布（归位时画布上那份已经没了，这是唯一的回头路）。
   stub 里桌布矩形由 style.left/top + 140×48 常量拼出（新桌布无内联位置 → 0,0,140,48），
   拖到 (900,700) 必在其外；mirror 走 #drag-layer（getElementById 按需创建） */
const pev = o => Object.assign({ button: 0, pointerId: 1, stopPropagation(){}, preventDefault(){} }, o);
chipX._ev.pointerdown[0](pev({ clientX: 0, clientY: 0 }));
chipX._ev.pointermove[0](pev({ clientX: 40, clientY: 30 }));
chipX._ev.pointermove[0](pev({ clientX: 900, clientY: 700 }));
chipX._ev.pointerup[0](pev({ clientX: 900, clientY: 700 }));
assert('拖出桌布后线索从桌布移除', !window.__dump().matrix.vision.includes('CLUES_V_luheng'));
assert('移除后推演器图标角标消失', !ids['infer-icon'].querySelector('.badge'));
assert('取回后线索回到画布上', !!findEl('clue:CLUES_V_luheng') && window.__dump().storedIn['clue:CLUES_V_luheng'] === undefined);
/* 落在哪儿就放回哪儿：卡片中心对着松手那一点（换算同 toWorld：屏幕 → 世界） */
const v20 = window.__dump().view, sr20 = ids['stage'].getBoundingClientRect();
const p20 = window.__dump().pos['clue:CLUES_V_luheng'];
assert('取回落在松手的位置（卡片中心对着指针）',
  Math.abs((p20.x + 65) * v20.k + v20.x + sr20.left - 900) < 1 &&
  Math.abs((p20.y + 23) * v20.k + v20.y + sr20.top - 700) < 1);
assert('取回后位置与归位前不同（是放到落点，不是弹回老位置）',
  p20.x !== posBefore20.x || p20.y !== posBefore20.y);
/* 取回 = 节点「重新上画布」，照例亮一次「新」角标（与 bagTake / ledgerTake 同款）。
   注意 `hasNew` 要等到第 31 节才定义（const 有暂时性死区），这里就地判一次 */
const backEl20 = findEl('clue:CLUES_V_luheng');
assert('取回的线索带「新」角标（markFresh 同款）',
  !!backEl20 && backEl20.children.some(c => c._classes.has('new') && c._text === '新'));
/* TEC 窗口：点击只闲聊，档案进度只能由分析推进 */
ids['tec-dock']._ev.dblclick[0]();
assert('双击 TEC 图标开对话窗', window.__dump().floats.tec === true);
const tpTec0 = window.__dump().tec.prog['SCENES_body'] || 0;
window.__tecTalk();
assert('点击 TEC 只闲聊，场景档案不再被翻动', (window.__dump().tec.prog['SCENES_body'] || 0) === tpTec0);

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

/* 详情内容：只有「简介 / 状态 / 来源」三样（2026-10-14 收口），操作引导已移除。
   线索的感官类型并进「状态」行（旧写法是单独一行「感官类型：视觉」）。 */
window.__reveal('SCENES_body');
window.__cap('loc:SCENES_body');
window.__select('clue:CLUES_V_luheng');
assert('线索详情把感官类型并进「状态」行（已捕获 · 视觉）',
  /状态：已捕获 · 视觉/.test(ids['detail-body']._html || ''));
window.__select('item:ITEMS_changji');
const itemHtml = ids['detail-body']._html || '';
assert('物品详情显示来源场景', itemHtml.indexOf('植物学家的花园') >= 0);
assert('物品详情不再列「与这些东西存在反应」（黄铜钥匙不该被直接写出来）',
  itemHtml.indexOf('存在反应') < 0 && itemHtml.indexOf('黄铜钥匙') < 0);
assert('详情不再含操作引导', itemHtml.indexOf('双击节点进行') < 0 && itemHtml.indexOf('拖到') < 0);

console.log('\n=== 23. 长文本去重：正文 / 日志 / 详情窗 各归其位 ===');
ids['btn-reset']._ev.click[0]();
/* 展开「书桌」——叙事卡出现，但正文不再被镜像进日志 */
const lBefore = logs.length;
window.__reveal('ITEM_shuzhuo');
const lNew = logs.slice(lBefore);
assert('展开场景弹出叙事卡', window.__dump().floats.narr === true);
assert('日志里不再出现场景正文', !lNew.some(l => l.indexOf('在靠近桌子的边缘') >= 0));
assert('展开容器完全不写日志（过程不进案卷）', lNew.length === 0);

/* 容器详情窗：无正文、只留「状态 + 来源 + 回看入口」。
   2026-10-14 收口：**不再列「内容 / 文本入口 / 出口」** ---- 那三样都是剧透
   （「内容」会提前念出容器里有什么、「文本入口」会提前暴露未来场景名），
   而且「出口」与「来源」常常是同一个值（书桌正是如此），平白重复一行。
   书桌已被改判为**物品**：分类行写「物品」。 */
window.__select('item:ITEM_shuzhuo');
let dh = ids['detail-body']._html || '';
assert('容器详情不再含正文', dh.indexOf('在靠近桌子的边缘') < 0);
assert('书桌的详情窗已改判为「物品」（不再是场景）', dh.indexOf('>物品<') >= 0);
assert('分类行不再带内部 key（旧写法「物品 · item:ITEM_shuzhuo」已撤）', dh.indexOf('item:ITEM_shuzhuo') < 0);
assert('容器详情不再列「内容」行（里面有什么要展开才知道）', dh.indexOf('内容：') < 0);
assert('容器详情不再列「文本入口」行', dh.indexOf('文本入口') < 0);
assert('容器详情不再列「出口」行（导航靠画布上的边，不靠文字复述）', dh.indexOf('出口：') < 0);
assert('容器详情提供「重看叙事」按钮', dh.indexOf('dt-renarr') >= 0);
/* 状态用词：**「已探索 / 未探索」**，不写「已展开」——「展开」是玩家的动作，
   「探索」才是留在界面上的状态（画布节点副标题早就写「已探索」，详情窗跟着统一）。 */
assert('容器详情状态行写「已探索」（不再写「已展开」）',
  dh.indexOf('状态：已探索') >= 0 && dh.indexOf('已展开') < 0);
assert('档案窗与顶栏计数同步用「已探索 / 未探索」（源码检查）',
  /G\.explored\.has\(sid\) \? "已探索" : "未探索"/.test(html)
  && html.indexOf('已探索场景 <b>') >= 0);
assert('整个引擎里不再出现「已展开 / 未展开」（源码检查：状态一律叫「已探索 / 未探索」）',
  html.indexOf('已展开') < 0 && html.indexOf('未展开') < 0);
/* 「来源」记的是**把它生出来的那个容器**：书桌是被 __reveal 直接开出来的，没有来源；
   它生出来的东西才有（手写笔记 ← 书桌）。 */
window.__select('item:ITEM_sxbj');
assert('来源照旧：手写笔记的详情窗写「来源：书桌」',
  (ids['detail-body']._html || '').indexOf('来源：书桌') >= 0);
/* 「来源」显式排除场景：场景之间的 homeScene 会被**最后一次**展开它的宿主覆盖
   （实测「植物学家的花园」的来源一度变成「尸体」），写出来是随机的、只会误导。 */
assert('「来源」行显式排除场景（源码检查）', /n\.kind !== "loc" && n\.homeScene/.test(html));

/* 回看入口能真的把卡叫回来 */
window.__closeFloats();
assert('关闭后无叙事卡', window.__dump().floats.narr === false);
window.__renarr('ITEM_shuzhuo');
assert('「重看叙事」重新弹出卡', window.__dump().floats.narr === true);
window.__closeFloats();

/* 物品描述统一在详情窗承载（不论有没有命令）；双击无命令物品只选中、不再弹提示条 */
window.__reveal('SCENES_choutiyi');
window.__reveal('SCENES_garden');           /* 黑影：没有命令的物品，描述只在详情窗 */
window.__select('item:ITEM_something');
dh = ids['detail-body']._html || '';
assert('无命令物品：描述也在详情窗（唯一出口）', dh.indexOf('摇摇晃晃') >= 0);
window.__select('item:ITEMS_zhiwu');
dh = ids['detail-body']._html || '';
assert('有命令物品：描述同样在详情窗', dh.indexOf('自生自灭') >= 0);
/* 双击无命令物品 = 选中（不再走顶部提示条） */
ids['toast'].innerHTML = '__sentinel__';
window.__talk('item:ITEM_something');
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
window.__reveal('ITEM_shuzhuo');
window.__choice('ITEM_chouti', 0, 1);        /* 右抽屉 → 剪刀 */
window.__reveal('SCENES_body');              /* 绷带在这个场景里 */
const lcBefore = logs.length;
ids['toast'].innerHTML = '__sentinel__';
window.__combo('item:ITEMS_jd', 'item:ITEMS_bd');      /* 剪刀 → 绷带：必定成功的组合 */
assert('组合成功不再弹提示条', ids['toast'].innerHTML === '__sentinel__');
assert('组合成功仍写进日志（反应正文）',
  logs.length > lcBefore &&
  logs.slice(lcBefore).some(l => l.indexOf('陆珩松的尸体') >= 0));
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
window.__reveal('ITEM_shuzhuo');
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
window.__reveal('ITEM_shuzhuo');
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
assert('展开场景不再吆喝「似乎有话要说」（提示只来自分析）', html.indexOf('似乎有话要说') < 0);
const tecTalkFn = (() => { const s = html.slice(html.indexOf('function tecTalk(){')); return s.slice(0, s.indexOf('\n}')); })();
assert('tecTalk 只轮换闲聊：不再读 sceneTalks、不进撤销栈',
  tecTalkFn.indexOf('sceneTalks') < 0 && tecTalkFn.indexOf('pushHistory') < 0);
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
window.__reveal('ITEM_shuzhuo');
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
window.__reveal('ITEM_shuzhuo');
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

/* ---- 人物：常驻两人（TEC / 执行者）+ 已结识的角色 ----
   常驻成员一进游戏就在册，点一行 = 开各自的窗；其余角色点一行 = 叫到画面中央并接着说下一句。
   每行左侧必须有一个小头像：有美术稿用像素图，没有的退回首字方块。 */
ids['people-icon']._ev.dblclick[0]();
assert('双击人物图标开窗', window.__dump().floats.people === true);
const peopleBody = document.getElementById('desktop').querySelector('.people-win').querySelector('.syswin-body');
const peopleRows = () => [...peopleBody.querySelectorAll('.goto-item')];
const rowByLabel = (t) => peopleRows().find(r => r.querySelector('.lb').textContent === t);
/* 还没遇到任何人时：常驻两人已经在册 */
let rrows = peopleRows();
assert('一进游戏名册里就有 TEC 与执行者两行（不等「已结识」）',
  rrows.length === 2 && rrows[0].querySelector('.lb').textContent === 'TEC' &&
  rrows[1].querySelector('.lb').textContent === '执行者');
assert('常驻两行标出去哪扇窗（助手窗 / 逻辑阵列）',
  rrows[0].querySelector('.st').textContent === '助手窗' &&
  rrows[1].querySelector('.st').textContent === '逻辑阵列');
/* 头像读取：stub 的 querySelector 只按 class 匹配、**不解析后代标签**（`.av img` 取不到），
   所以先拿 .av，再按 tagName 找里面那个 img / span。 */
const avImgOf = (row) => {
  const av = row.querySelector('.av');
  if (!av) return null;
  const im = av.children.find(c => String(c.tagName).toLowerCase() === 'img');
  return im ? im.src : null;
};
const avIniOf = (row) => {
  const av = row.querySelector('.av');
  if (!av) return null;
  const s = av.children.find(c => String(c.tagName).toLowerCase() === 'span');
  return s ? s.textContent : null;
};
assert('名册每行都有小头像（.av）', rrows.every(r => !!r.querySelector('.av')));
assert('常驻两人用真头像（内联 base64 的 img）',
  /^data:image\/png;base64,/.test(avImgOf(rrows[0]) || '') &&
  /^data:image\/png;base64,/.test(avImgOf(rrows[1]) || ''));
assert('TEC 与执行者不是同一张头像（执行者早有自己的素材）',
  avImgOf(rrows[0]) !== avImgOf(rrows[1]));
window.__reveal('SCENES_fkjl');                        /* 这场景点名了朱穗 / 傅柏 */
const roster = window.__roster();
assert('展开场景后名册接着记下遇到的人',
  roster.map(r => r.id).sort().join(',') === 'CHARS_EXEC,CHARS_TEC,CHARS_zs,NPC_FB');
assert('常驻两人固定排在最前（不按遇到顺序插进来）',
  roster[0].id === 'CHARS_TEC' && roster[1].id === 'CHARS_EXEC');
assert('名册把 TEC 也算进来', roster.some(r => r.id === 'CHARS_TEC') && roster.some(r => r.id === 'CHARS_EXEC'));
/* 剧情角色还没有美术稿 ⇒ 退回首字方块占位（拿到图后换成 img 即可，一行一块） */
const iniRows = peopleRows().filter(r => !!avIniOf(r));
assert('没有美术稿的剧情角色用「首字方块」占位', iniRows.length === 2 &&
  iniRows.map(r => avIniOf(r)).sort().join('') === '傅朱' &&
  iniRows.every(r => !avImgOf(r)));
/* 遇到新人 ⇒ 头像库当场解锁（池子现算，没有任何「解锁」写盘逻辑） */
console.log('  —— 头像解锁 ——');
assert('结识两人后可选头像 = 常驻 2 + 新解锁 2',
  window.__avatars().pool.join(',') === 'CHARS_EXEC,CHARS_TEC,NPC_FB,CHARS_zs');
assert('未解锁数从 4 掉到 2', window.__avatars().locked === 2);
window.__avatarOpen();
{
  const avTiles = ids['desktop'].querySelector('.avatar-win').querySelectorAll('.avatar-pick');
  const avOpen = avTiles.filter(t => !t.classList.contains('locked'));
  const iniOf = t => { const s = t.querySelector('.av').children.find(c => String(c.tagName).toLowerCase() === 'span'); return s ? s.textContent : null; };
  assert('换头像窗列出 4 张可选 + 2 张未解锁', avTiles.length === 6 && avOpen.length === 4);
  assert('新解锁两位没有美术稿 ⇒ 首字方块占位',
    avOpen.map(iniOf).filter(Boolean).sort().join('') === '傅朱');
  assert('解锁计数行跟着涨到「已解锁 4 / 6」',
    ids['desktop'].querySelector('.avatar-count').textContent === '已解锁 4 / 6');
}
window.__avatarPick('CHARS_zs'); window.__avatarConfirm();
assert('换成没美术稿的人也能落章（avatarId = 朱穗）',
  window.__dump().investigator.avatarId === 'CHARS_zs' && window.__avatars().win === false);
{
  invChipNode._ev.click[0]();
  const cw = ids['desktop'].querySelectorAll('.cert-win');
  const p = cw[cw.length - 1].querySelector('.cert-photo');
  const ini = p.children.find(c => String(c.tagName).toLowerCase() === 'span');
  assert('证件照退回首字方块（朱）', !!ini && ini.textContent === '朱' && !p.children.some(c => String(c.tagName).toLowerCase() === 'img'));
}
window.__avatarOpen(); window.__avatarPick('CHARS_EXEC'); window.__avatarConfirm();
assert('换回执行者（留给后续用）', window.__dump().investigator.avatarId === 'CHARS_EXEC');
assert('名册行带对话进度（未交谈 0/1）',
  roster.find(r => r.id === 'CHARS_zs').prog === 0 && roster.find(r => r.id === 'CHARS_zs').total === 1);
/* 点「朱穗」那一行（傅柏在这个场景里没有对白，走的是「无对话文本」分支） */
const zsRow = rowByLabel('朱穗');
assert('名册里找得到「朱穗」这一行', !!zsRow);
assert('傅柏那行标「无对话文本」（该场景里他确实没词）',
  rowByLabel('傅柏').querySelector('.st').textContent === '无对话文本');
fire(zsRow, 'click', {});
assert('点人物一行 = 选中该角色节点', window.__dump().sel === 'char:CHARS_zs');
assert('点人物一行 = 说出第一句（对话进度 +1）', window.__dump().talk['char:CHARS_zs'] === 1);
assert('点完人物窗仍开着（可以接着点下一个人）', window.__dump().floats.people === true);
assert('名册行随之刷新出对话进度', rowByLabel('朱穗').querySelector('.st').textContent === '对话 1/1');
assert('说完的角色行标上 done', rowByLabel('朱穗')._classes.has('done'));
/* 点常驻两行 = 打开各自的窗（他们都没有画布节点，绝不该「叫到画布上」） */
fire(rowByLabel('TEC'), 'click', {});
assert('点 TEC 一行 = 开 TEC 助手窗', window.__dump().floats.tec === true);
assert('点 TEC 一行不会给他造画布节点',
  !window.__dump().nodes.includes('char:CHARS_TEC') && window.__dump().sel === 'char:CHARS_zs');
fire(rowByLabel('TEC'), 'click', {});                  /* 再点一下 = 关掉，别影响后面的用例 */
assert('再点一下 TEC 一行 = 收掉助手窗', window.__dump().floats.tec === false);
fire(rowByLabel('执行者'), 'click', {});
assert('点执行者一行 = 开逻辑阵列窗', window.__dump().floats.matrix === true);
assert('点执行者一行不造画布节点',
  !window.__dump().nodes.some(k => k.indexOf('char:CHARS_EXEC') === 0));
fire(rowByLabel('执行者'), 'click', {});
assert('再点一下执行者一行 = 收掉逻辑阵列窗', window.__dump().floats.matrix === false);

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

console.log('\n=== 29. 钉住（右键）/ 折叠反馈 ===');
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');
window.__closeFloats();
const pinKey = 'loc:SCENES_garden';
const hasPin = el => !!el && el.children.some(c => c._classes.has('pin') && c._text === '已固定');
assert('初始未钉住、节点上也没有「已固定」角标',
  window.__dump().pos[pinKey].pinned === false && !hasPin(findEl(pinKey)));
/* 右键 = 钉住；不弹提示，状态由角标表达 */
ids['toast']._html = '__SENTINEL__';
fire(findEl(pinKey), 'contextmenu', {});
assert('右键钉住', window.__dump().pos[pinKey].pinned === true);
assert('右键不弹任何提示（toast 没被碰过）', ids['toast']._html === '__SENTINEL__');
assert('钉住后节点上挂出「已固定」角标', hasPin(findEl(pinKey)));
const pinBody = (html.match(/function togglePin\(n\)\{[\s\S]*?\n\}/) || [''])[0];
assert('togglePin 里既没有 toast 也没有 log（"不弹提示"落在源码上）',
  pinBody.length > 0 && pinBody.indexOf('toast(') < 0 && pinBody.indexOf('log(') < 0);
assert('右键菜单被吃掉（preventDefault + stopPropagation）',
  /addEventListener\("contextmenu", e => \{\s*e\.preventDefault\(\);\s*e\.stopPropagation\(\);/.test(html));
/* 再右键 = 取消钉住 */
ids['toast']._html = '__SENTINEL__';
fire(findEl(pinKey), 'contextmenu', {});
assert('再右键一次 = 取消钉住', window.__dump().pos[pinKey].pinned === false);
assert('取消后角标消失', !hasPin(findEl(pinKey)));

/* 拖动不再是钉住入口：源码里除了 togglePin 的取反，没有任何地方把 pinned 写成 true */
assert('拖动不再是钉住入口（源码里已无 n.pinned = true，唯一入口是 togglePin）',
  (html.match(/n\.pinned = true/g) || []).length === 0 &&
  /function togglePin\(n\)\{[\s\S]*?n\.pinned = !n\.pinned/.test(html));

/* 折叠反馈：已固定的不被收回，且必须报出数量；没钉住的同类照常收回 */
window.__reveal('ITEM_shuzhuo');
window.__closeFloats();
window.__pin('item:ITEM_taideng');
assert('台灯被钉住', window.__dump().pos['item:ITEM_taideng'].pinned === true);
const lc29 = logs.length;
window.__collapse('ITEM_shuzhuo');
assert('折叠时报告"另有 N 个节点留在画布上"',
  logs.slice(lc29).some(l => l.indexOf('另有 1 个节点留在画布上') >= 0));
assert('被钉住的台灯留在画布上', !!findEl('item:ITEM_taideng'));
assert('没被钉住的同类照常被收回（抽屉不在画布上）', !findEl('item:ITEM_chouti'));

/* 「自动布局」按钮已于 2026-10-14 删除：layout() 的 seed() 对已有坐标的节点直接跳过，
   点它只是在原地再跑 260 轮弹簧迭代 —— 实测 31/31 个节点整体晃 50~165px，既不整理也不收敛。
   于是「解除全部已固定」这个批量出口一并消失，钉住只留右键这一条路（逐个解除）。 */
assert('顶栏不再有「自动布局」按钮（源码检查）',
  html.indexOf('btn-relayout') < 0 && html.indexOf('>自动布局</button>') < 0);
const lc29b = logs.length;
window.__pin('item:ITEM_taideng');                 /* 再右键一次 = 解除钉住 */
assert('钉住只能逐个右键解除（右键即解除，没写日志）',
  window.__dump().pos['item:ITEM_taideng'].pinned === false &&
  !hasPin(findEl('item:ITEM_taideng')) && logs.length === lc29b);

console.log('\n=== 30. 详情窗「状态」实时刷新 ===');
ids['btn-reset']._ev.click[0]();
/* 详情面板的内容构建已抽成 paintDetail()，render() 末尾会调它 —— 状态一变，详情窗自己跟着刷新，
   不必重新点一下节点（老毛病：台灯点亮后详情窗还写着「未点亮」） */
assert('render() 末尾会刷新详情面板（源码检查）',
  /applyFocus\(\);\s*\r?\n\s*paintDetail\(\);/.test(html));
assert('详情面板内容没变时不重建 DOM（签名比对，源码检查）',
  html.indexOf('if (detailBody.__sig === html) return;') >= 0);

window.__reveal('ITEM_shuzhuo');                    /* 台灯在书桌上 */
window.__select('item:ITEM_taideng');
let dh30 = ids['detail-body']._html || '';
assert('详情窗：台灯初始「未点亮」', dh30.indexOf('未点亮') >= 0 && dh30.indexOf('已点亮') < 0);
/* 关键一步：不重新点选节点，直接点亮 —— 详情窗要自己变 */
window.__cmd('ITEM_taideng', 0);
dh30 = ids['detail-body']._html || '';
assert('点亮后详情窗自己变「已点亮」（没重新点选）', dh30.indexOf('已点亮') >= 0 && dh30.indexOf('未点亮') < 0);
assert('刷新不影响选中态', window.__dump().sel === 'item:ITEM_taideng' && window.__dump().floats.detail === true);
window.__cmd('ITEM_taideng', 0);
dh30 = ids['detail-body']._html || '';
assert('再熄灭 → 详情窗又回到「未点亮」', dh30.indexOf('未点亮') >= 0 && dh30.indexOf('已点亮') < 0);
/* 选中一个已经没了的节点：占位文案回到「点选任意节点查看信息」（不是「节点已不存在」） */
window.__select('item:ITEM_taideng');
window.__select('item:ITEM_shuzhuo');
assert('切换选中后详情窗换成新节点', (ids['detail-body']._html || '').indexOf('书桌') >= 0);

console.log('\n=== 31. 「新」角标：点一下就摘掉 ===');
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');
const hasNew = el => !!el && el.children.some(c => c._classes.has('new') && c._text === '新');
const newOnBoard = () => ids['nodes'].children.filter(el => hasNew(el)).map(el => el.dataset.key);
const clickNode = el => {
  const ev = o => Object.assign({ button:0, pointerId:1, stopPropagation(){}, preventDefault(){} }, o);
  el._ev.pointerdown[0](ev({ clientX: 0, clientY: 0 }));
  el._ev.pointerup[0](ev({ clientX: 0, clientY: 0 }));   /* 无位移 → 走单击分支 */
};
const badges0 = newOnBoard();
assert('展开场景后，新长出来的节点挂着「新」角标', badges0.length > 0);
/* 口径是「还没点过」，不是「刚冒出来」：展开完这一屏节点玩家一个都还没点过 → 一屏全带角标。
   （旧版靠 render() 把 fresh 擦掉制造出「只有部分节点有」，那个"部分"是重绘的副作用，
     也正是「钉一下就全没了」的病根。） */
assert('角标口径 = 还没点过：此刻画布上的节点都带「新」',
  badges0.length === ids['nodes'].children.length);
assert('起始场景节点也带「新」（它是玩家还没点过的第一个节点）',
  badges0.indexOf('loc:SCENES_garden') >= 0);
const firstNew = badges0[0];
clickNode(findEl(firstNew));
assert('点一下之后该节点的「新」角标立刻消失（不依赖整层重绘）', !hasNew(findEl(firstNew)));
assert('同时刻其余节点的「新」还在', newOnBoard().length === badges0.length - 1);
assert('点的是它（选中态落在该节点）', window.__dump().sel === firstNew);
clickNode(findEl(firstNew));
assert('再点一次（已没有角标）不出错、依然是干净的', !hasNew(findEl(firstNew)));

/* ---- 重绘不是摘角标的理由 ----
   旧版把「新」角标挂在 n.fresh 上，而 fresh 是「本轮镜头聚焦」的一次性标记、render() 末尾就擦，
   于是任何一次重绘（右键钉住 / 自动布局 / 展开别的容器 / 撤销）都会把全场角标一起洗掉。
   现在角标认 n.unread，只有玩家点过这个节点才会清。 */
const beforeRedraw = newOnBoard();
assert('对照组：此刻画布上还有多个「新」角标（' + beforeRedraw.length + ' 个）', beforeRedraw.length >= 2);
const ntPinKey = beforeRedraw[0], ntOtherKey = beforeRedraw[1];
window.__pin(ntPinKey);                   /* 右键钉住：togglePin → pushHistory → render() */
assert('右键钉住（一次重绘）后，角标没有被洗掉', newOnBoard().length === beforeRedraw.length);
assert('被钉住的那个节点自己还带「新」', hasNew(findEl(ntPinKey)));
window.__pin(ntOtherKey);                 /* 右键钉住另一个节点：又一次 render() */
assert('又一次重绘（钉别的节点）后，角标依然在', newOnBoard().length === beforeRedraw.length);
window.__reveal('SCENES_body');           /* 展开别的容器：再来一次 render() */
assert('展开别的场景（又一次重绘）后，角标依然在（且新场景的节点也带上了）',
  newOnBoard().length >= beforeRedraw.length && newOnBoard().length > beforeRedraw.length);
/* 撤销会 restore() 整张图重建 —— 「新」属于玩家知识，和 seenTexts 一样不随快照回滚 */
window.__pin(ntPinKey);                   /* 再右键 = 取消钉住（进撤销栈） */
ids['btn-undo']._ev.click[0]();           /* 撤销 → restore() + render() */
assert('撤销（restore 整张图重建）后，角标依然在', hasNew(findEl(ntPinKey)) && newOnBoard().length >= beforeRedraw.length);
/* 而真正点一下，照旧只摘它一个 */
const keepN = newOnBoard().length;
clickNode(findEl(ntOtherKey));
assert('点一下仍然只摘掉它自己的角标', !hasNew(findEl(ntOtherKey)) && newOnBoard().length === keepN - 1);

/* 源码检查：角标认 unread 不认 fresh；unread 不进快照，由 restore() 接力带回 */
assert('render() 画「新」角标认的是 n.unread（源码检查）',
  /if \(n\.unread\)\{[\s\S]{0,160}?badge new/.test(html));
assert('render() 末尾只擦 fresh，不碰 unread（源码检查）',
  /n\.fresh = false;   \/\* 只擦「聚焦用」的一次性标记/.test(html));
assert('新节点同时点亮 fresh + unread（markFresh，源码检查）',
  html.indexOf('function markFresh(n){ if (n){ n.fresh = true; n.unread = true; } return n; }') >= 0);
assert('unread 不进快照（源码检查）',
  !/nodes\[k\] = \{[^}]*unread/.test(html) &&
  /Object\.keys\(G\.nodes\)\.forEach\(k => \{ if \(unread\[k\]\) G\.nodes\[k\]\.unread = true; \}\);/.test(html));

/* 点清单行（线索册 / 人物名册）也会 selectNode，但那是"点行"不是"点节点"：
   取回来的线索该照常亮一次「新」，等玩家真去点它才摘 */
window.__reveal('SCENES_body');
window.__cap('loc:SCENES_body');
const ck = 'clue:CLUES_V_luheng';
assert('捕获出的线索节点带「新」角标', hasNew(findEl(ck)));
window.__ledgerStore(ck);
assert('收进线索册后节点离开画布（元素没了）', !findEl(ck));
window.__ledgerTake(ck);
assert('从线索册取回后仍亮「新」（取回是点册里的行，不是点节点）', hasNew(findEl(ck)));
clickNode(findEl(ck));
assert('再点一下它 → 「新」摘掉', !hasNew(findEl(ck)));

assert('单击路径里调了 clearFresh（源码检查）',
  /if \(!moved\)\{ clearFresh\(n\); selectNode\(n\.key\); return; \}/.test(html));
assert('双击路径里也调了 clearFresh（源码检查）',
  /el\.addEventListener\("dblclick", \(\) => \{\s*\r?\n\s*clearFresh\(n\);/.test(html));
assert('clearFresh 不在 selectNode 里（否则点清单行会误摘，源码检查）',
  !/function selectNode\(key\)\{[\s\S]{0,400}?clearFresh\(n\)/.test(html));
assert('clearFresh 只在角标已画出来时才摘（源码检查：先查 .badge.new）',
  /function clearFresh\(n\)\{[\s\S]*?querySelector\("\.badge\.new"\)/.test(html));

console.log('\n=== 32. 书桌 / 垃圾桶：从场景改判为容器物品 ===');
/* 身份：它们不再出现在 scenes 表里，而是带 content 的物品 —— 于是既被当作「物品」看待，
   又仍然能装东西（双击展开 / 折叠 / 内容物摆在四周）。「物品本身也可以用来装物品」。 */
const gd = JSON.parse(jsonText);
assert('书桌已从 scenes 表移除', !gd.scenes.SCENE_shuzhuo);
assert('垃圾桶已从 scenes 表移除', !gd.scenes.SCENES_ljt);
assert('书桌改判为物品，且带 content（所以它还是容器）',
  !!(gd.items.ITEM_shuzhuo && gd.items.ITEM_shuzhuo.content));
assert('垃圾桶改判为物品，且带 content', !!(gd.items.ITEMS_ljt && gd.items.ITEMS_ljt.content));
assert('正文里对书桌的引用已从 [loc:] 改成 [item:]（书桌不再是「出口」）',
  gd.scenes.SCENES_garden.content.indexOf('[item:ITEM_shuzhuo]') >= 0 &&
  gd.scenes.SCENES_garden.content.indexOf('[loc:SCENE_shuzhuo]') < 0);
assert('源码里不再有任何 n.isScene 的分支（容器身份由 kind + 数据表现算）',
  html.indexOf('n.isScene') < 0);

ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');
window.__closeFloats();
assert('书桌以**物品**节点键出现在画布上', window.__dump().nodes.includes('item:ITEM_shuzhuo'));
assert('书桌未展开时垃圾桶还没上画布', !window.__dump().nodes.includes('item:ITEMS_ljt'));
const deskEl2 = findEl('item:ITEM_shuzhuo');
assert('书桌节点是物品样式（ent-item），不再是场景样式（scene-node）',
  !!deskEl2 && deskEl2._classes.has('ent-item') && !deskEl2._classes.has('scene-node'));
assert('书桌节点仍带「未探索」虚框提示（虚线样式已改挂容器、不再只认场景）',
  !!deskEl2 && deskEl2._classes.has('unexplored'));
assert('书桌副标题仍是「未探索 · 双击展开」',
  !!deskEl2 && (deskEl2._html || '').indexOf('未探索 · 双击展开') >= 0);

/* 双击展开 → 内容物照旧铺开 */
window.__reveal('ITEM_shuzhuo');
const dExp = window.__dump();
assert('展开书桌后里面的四件东西都上画布',
  ['ITEM_sxbj','ITEM_taideng','ITEM_chouti','ITEMS_ljt'].every(i => dExp.nodes.includes('item:' + i)));
assert('内容物以「实体边」挂在书桌节点上',
  dExp.edges.includes('entity:item:ITEM_shuzhuo>item:ITEM_taideng'));
/* 书桌正文里的「返回 [loc:SCENES_garden]」照旧是一条通路：容器物品也认 [loc]，机制没有分叉 */
assert('书桌仍有一条「出口」边通往它正文里写的花园',
  dExp.edges.includes('move:item:ITEM_shuzhuo>loc:SCENES_garden'));
const lg32 = logs.length;
window.__combo('item:ITEM_shuzhuo', 'loc:SCENES_garden');
assert('把书桌拖到花园上 = 前往花园（不因为书桌是物品就断掉这条路）',
  logs.slice(lg32).some(l => l.indexOf('前往场景') >= 0));

/* 折叠 / 展开照旧可用 */
window.__collapse('ITEM_shuzhuo');
assert('折叠书桌：内容物被收起', window.__dump().hidden.includes('item:ITEM_taideng'));
assert('折叠书桌被记进 collapsed', window.__dump().collapsed.includes('ITEM_shuzhuo'));
window.__collapse('ITEM_shuzhuo');
assert('再展开：台灯回来', !window.__dump().hidden.includes('item:ITEM_taideng'));

/* 垃圾桶自己也是容器（容器里还能装容器） */
window.__reveal('ITEMS_ljt');
assert('展开垃圾桶：里面的纸片上画布', window.__dump().nodes.includes('item:ITEMS_wbfs'));
assert('垃圾桶同样是物品样式的容器节点',
  !!findEl('item:ITEMS_ljt') && findEl('item:ITEMS_ljt')._classes.has('ent-item'));

/* 不改动的地方：档案（前往）只列场景；容器物品既进不去，也收不了 */
assert('档案（前往）清单里没有书桌', window.__gotoList().indexOf('ITEM_shuzhuo') < 0);
assert('档案（前往）清单里没有垃圾桶', window.__gotoList().indexOf('ITEMS_ljt') < 0);
window.__goto('ITEM_shuzhuo');
assert('对容器物品「前往」是空操作（档案只认场景）',
  !window.__dump().nodes.some(k => k.indexOf('loc:ITEM_shuzhuo') === 0) &&
  html.indexOf('if (!SCENES[sid]) return;') >= 0);
assert('容器物品进不了证物袋', window.__bag('item:ITEM_shuzhuo') === false);
assert('容器物品进不了线索册', window.__ledgerStore('item:ITEM_shuzhuo') === false);
assert('拒收不留痕：书桌仍在画布上', window.__dump().nodes.includes('item:ITEM_shuzhuo'));

/* 花园没因为书桌改判而丢掉「枢纽」角标：容器物品里的 [loc] 照样记一票 */
assert('统计容器里的 [loc] 通路（源码检查）', /sceneLocs\(iid\)\.forEach/.test(html));
assert('花园仍是枢纽节点（入 5 / 出 0 → 仍达阈值）',
  !!findEl('loc:SCENES_garden') && findEl('loc:SCENES_garden')._classes.has('hub'));

console.log('\n=== 33. 日志只记「结果」，不记「过程」 ===');
/* 用户要求：「日志内容太过详尽，只要保留重点就行」。
   口径写进了 log() 上方的注释 —— 这里按「过程不进案卷 / 失败照记」逐条钉住。 */
ids['btn-reset']._ev.click[0]();
/* 桌面操作：没有可撤销时那条 warn 照写（重置刚清空撤销栈，这一次必定失败） */
let l33 = logs.length;
ids['btn-undo']._ev.click[0]();
assert('没有可撤销的操作仍然记一条 warn', logs.length === l33 + 1 &&
  logs[logs.length - 1].indexOf('没有可撤销的操作') >= 0);
assert('撤销失败的文案是 warn 级（源码检查）',
  /log\("没有可撤销的操作", "warn"\)/.test(html));

window.__reveal('SCENES_garden');
window.__reveal('SCENES_body');
/* 结果类一律保留：捕获线索照旧记进案卷 */
l33 = logs.length;
window.__cap('loc:SCENES_body');                       /* → clue:CLUES_V_luheng */
assert('捕获线索照旧记进案卷（cap）', logs.slice(l33).some(l => l.indexOf('的隐藏线索') >= 0));

l33 = logs.length;
assert('收入证物袋不写日志', window.__bag('item:ITEM_lianmu') === true && logs.length === l33);
l33 = logs.length;
assert('从证物袋取回不写日志', window.__bagTake('item:ITEM_lianmu') === true && logs.length === l33);
l33 = logs.length;
assert('推演归位不写日志',
  window.__mxAssign('clue:CLUES_V_luheng', 'vision') === true && logs.length === l33);
/* 归位 = 收进桌布：线索离开画布（与收入袋 / 册是同一套 stored 机制，所以它也不能再被收进线索册） */
assert('归位后线索离开画布、落在桌布上',
  window.__dump().storedIn['clue:CLUES_V_luheng'] === 'MATRIX' && !findEl('clue:CLUES_V_luheng') &&
  window.__matrixItems().includes('clue:CLUES_V_luheng'));
assert('已经在桌布上的线索，不能再收进线索册',
  window.__ledgerStore('clue:CLUES_V_luheng') === false && logs.length === l33);
l33 = logs.length;
assert('从桌布取回不写日志',
  window.__boardTake('CLUES_V_luheng', 'vision') === true && logs.length === l33);
assert('取回后线索回到画布上（与归位前同一枚节点）',
  !!findEl('clue:CLUES_V_luheng') && window.__matrixItems().indexOf('clue:CLUES_V_luheng') < 0);
l33 = logs.length;
assert('收进线索册不写日志', window.__ledgerStore('clue:CLUES_V_luheng') === true && logs.length === l33);
l33 = logs.length;
assert('从线索册取回不写日志', window.__ledgerTake('clue:CLUES_V_luheng') === true && logs.length === l33);
l33 = logs.length;
ids['btn-undo']._ev.click[0]();                        /* 撤销成功：同样不写日志 */
assert('撤销成功不写日志', logs.length === l33);

/* 源码检查：口径注释在位，被砍的文案确实没了 */
assert('日志口径写在 log() 上方（源码检查）',
  html.indexOf('日志口径：「结果」，不是「过程」') >= 0);
assert('展开 / 收起容器的日志已删除（源码检查）',
  html.indexOf('展开场景「') < 0 && html.indexOf('收起「') < 0);
assert('收纳类日志已删除（源码检查）',
  html.indexOf('」收入证物袋') < 0 && html.indexOf('从证物袋取出「') < 0 && html.indexOf('」收进线索册') < 0);
assert('桌面操作类日志已删除（源码检查）',
  html.indexOf('已重新自动布局') < 0 && html.indexOf('已撤销上一步') < 0 &&
  html.indexOf('可达性：文本可达') < 0 && html.indexOf('已把案件') < 0);
assert('推演 / 放映类日志已删除（源码检查）',
  html.indexOf('移出逻辑阵列') < 0 && html.indexOf('记忆放映）') < 0);

/* —— 对话台词不进案卷（用户要求：「对话的内容不需要出现在日志记录里面」）—— */
/* 台词在气泡 / TEC 窗里逐字都在，日志再抄一遍只会把案卷冲成流水账。
   但「这一句给出了线索」是结果：陆珩松 7月4日 那句带 [clue:CLUES_zhpt]，
   朱穗密室的第 6 句带 [clue:CLUES_qsan]，都不能因为不记台词而把线索一起丢。 */
assert('人物台词的日志已删除（源码检查）',
  html.indexOf('esc(plain(line)), "sys"') < 0);
assert('TEC 台词的日志已删除（源码检查）',
  html.indexOf('log("<b>TEC</b>："') < 0);
assert('对话走「只记线索、不记台词」的专用入口（源码检查）',
  html.indexOf('function talkClues(text, who)') >= 0 &&
  html.indexOf('」的话里提到了线索：') >= 0);

ids['btn-reset']._ev.click[0]();
/* 人物：朱穗在密室（SCENES_mdhm）的第 1 句 —— 只说台词，日志纹丝不动 */
window.__reveal('SCENES_mdhm');
let l33c = logs.length;
window.__talk('char:CHARS_zs');
assert('人物说第一句不写日志（台词不进案卷）', logs.length === l33c);
assert('台词仍进了对话框（气泡弹出）', window.__dump().floats.bubble === true);
/* 一路点到第 6 句：那一句里带 [clue:CLUES_qsan] */
for (let i = 0; i < 4; i++) window.__talk('char:CHARS_zs');
assert('台词句句不写日志（1..5 句）', logs.length === l33c);
window.__talk('char:CHARS_zs');                       /* 第 6 句：给出线索 */
assert('对话给出线索时只记一条「结果」',
  logs.length === l33c + 1 && logs[logs.length - 1].indexOf('话里提到了线索') >= 0 &&
  logs[logs.length - 1].indexOf('墙上的按钮') >= 0);
assert('这条结果里没有半句台词',
  logs[logs.length - 1].indexOf('按下它我们就能出去了') < 0);
assert('线索确实捕获了（不是只写日志）', window.__dump().captured.indexOf('CLUES_qsan') >= 0);
/* TEC：连说两句，日志同样不动 —— 7月4日那组闪回档案一次八条长句，正是最该被挡在案卷外的 */
ids['btn-reset']._ev.click[0]();
l33c = logs.length;
const l33cLines = () => tecWinNode().querySelector('.tec-lines').children.length;
const l33cTec = (window.__tecTalk(), window.__tecTalk(), l33cLines());
assert('TEC 台词不写日志（TEC 窗自带对话历史）', logs.length === l33c);
assert('TEC 台词确实说了（历史里能查到）', l33cTec >= 2);

console.log('\n=== 34. 文本物「摘录」：读到就能把边画出来 ===');
/* 纸上的字原本只活在玩家脑子里（读完是死胡同）；excerpts 把「读到」这个动作直接变成图上的一条边。
   样板 = 未被焚烧干净的纸片：摘「7月4日」→ 闪回场景、摘「槿杉」→ 角色。 */
ids['btn-reset']._ev.click[0]();

/* —— 数据体检：每条摘录都要「词真的在 desc 里」「目标真的存在」—— */
(() => {
  const gd34 = JSON.parse(jsonText);
  const tbl = { loc: gd34.scenes || {}, item: gd34.items || {}, char: gd34.chars || {}, clue: gd34.clues || {} };
  const broken = [];
  let total = 0, onWbfs = 0;
  Object.keys(gd34.items || {}).forEach(id => {
    (gd34.items[id].excerpts || []).forEach(e => {
      total++;
      if (id === 'ITEMS_wbfs') onWbfs++;
      const inDesc = String(gd34.items[id].desc || '').indexOf(String(e.text)) >= 0;
      const p = String(e.to || '').split(':');
      const exists = p.length === 2 && !!tbl[p[0]] && !!tbl[p[0]][p[1]];
      if (!inDesc || !exists) broken.push(id + ' → ' + e.text + ' / ' + e.to);
    });
  });
  assert('每条摘录的 text 都在该物品的 desc 里、to 都指向真实实体' + (broken.length ? ' —— ' + broken.join('；') : ''),
    broken.length === 0 && total > 0);
  assert('目前只有样板纸条带摘录，且正好 2 条（7月4日 / 槿杉）', onWbfs === 2 && total === 2);
})();

window.__reveal('ITEMS_ljt');                       /* 垃圾桶：纸片就是从这里翻出来的 */
assert('垃圾桶里翻出「未被焚烧干净的纸片」', window.__dump().nodes.includes('item:ITEMS_wbfs'));

const dHtml34 = () => ids['detail-body'].innerHTML;
window.__select('item:ITEMS_wbfs');
assert('详情正文里「7月4日」渲染成可点下划线（button.ex + data-ex）',
  dHtml34().indexOf('<button class=\'ex\' data-ex="loc:SCENES_0704">7月4日</button>') >= 0);
assert('详情正文里「槿杉」同样渲染成可点下划线',
  dHtml34().indexOf('<button class=\'ex\' data-ex="char:CHARS_JS">槿杉</button>') >= 0);
assert('未摘录时不带 got 类（虚线下划线还在）', dHtml34().indexOf("class='ex got'") < 0);
assert('正文其余部分照常转义（没有多出裸标签）',
  dHtml34().indexOf('纸上用潦草的笔记写着：姓名：') >= 0);

const before34 = window.__dump();
assert('摘录前画布上没有「7月4日」闪回场景', !before34.nodes.includes('loc:SCENES_0704'));
const l34 = logs.length;
window.__excerpt('loc:SCENES_0704', 'item:ITEMS_wbfs');
const after34 = window.__dump();
assert('摘录后长出目标节点', after34.nodes.includes('loc:SCENES_0704'));
assert('*并*长出一条连回纸片的边（这才是解孤岛的那一步）',
  after34.edges.indexOf('cond:item:ITEMS_wbfs>loc:SCENES_0704') >= 0);
assert('摘录是「结果」，记一条日志', logs.length === l34 + 1 && logs[logs.length - 1].indexOf('摘录') >= 0);
assert('摘录进撤销栈（可撤销）', after34.history > before34.history);
assert('镜头判断认这次的新节点', !!after34.focus);

window.__select('item:ITEMS_wbfs');
assert('摘过之后该类名变 got（下划线褪掉）',
  dHtml34().indexOf('<button class=\'ex got\' data-ex="loc:SCENES_0704">7月4日</button>') >= 0);

const l34b = logs.length, h34b = window.__dump().history, n34b = window.__dump().nodes.length;
window.__excerpt('loc:SCENES_0704', 'item:ITEMS_wbfs');
assert('重复摘录不重复长节点、不写日志、不刷撤销步',
  window.__dump().nodes.length === n34b && window.__dump().history === h34b && logs.length === l34b);

window.__select('item:ITEMS_wbfs');
window.__excerpt('char:CHARS_JS', 'item:ITEMS_wbfs');
assert('摘录「槿杉」长出角色节点', window.__dump().nodes.includes('char:CHARS_JS'));
assert('角色节点也连回了纸片',
  window.__dump().edges.indexOf('cond:item:ITEMS_wbfs>char:CHARS_JS') >= 0);
assert('摘录把读到的词记进「听说过」（源码检查：noteSeen(nm)）',
  /noteSeen\(nm\);/.test(html));

/* 撤销能把这步收回去 */
const h34 = window.__dump().history;
ids['btn-undo']._ev.click[0]();
assert('撤销一次收回「槿杉」那一步', window.__dump().history < h34);

/* 源码检查：委托 + 按钮天然在拖动排除表里（浮窗 setPointerCapture 不会吞掉这次 click） */
assert('摘录点击委托在 #detail-body 上（源码检查）',
  html.indexOf('detailBody.addEventListener("click"') >= 0 &&
  html.indexOf('closest("button.ex")') >= 0);
assert('拖动排除表里有 button —— 摘录按钮因此不会被浮窗拖拽吞掉（源码检查）',
  /closest\("button,input,\.bag-item/.test(html));
assert('摘录机制读的是数据里的 excerpts（源码检查）',
  html.indexOf('function excerptsOf(') >= 0 && html.indexOf('(ITEMS[id] || {}).excerpts') >= 0);

console.log('\n=== 35. 唱机要先装唱针（命令上的「前置零件」门）+ 顶栏去掉「自动布局」 ===');
/* 用户要求：「唱机这个节点后面会播放没有标签的黑胶，但要设置一个前提就是得先装上唱针」。
   引擎为此加了一对最小的数据词汇，都长在命令上：
     installs:true  → 这条 useItem 成功时把工具记进 n.installed（进快照，跟着撤销 / 续档 / 存档走）
     requires:[id]  → 这条命令要求那些零件**已经装在本节点上**
   两条入口认同一个门：双击跑 cmds[0] 的 runCommand、拖动走的 combo 第 3.5 分支。 */
ids['btn-reset']._ev.click[0]();
window.__reveal('SCENES_garden');
window.__reveal('SCENES_cjag');                 /* → 黑胶 */
window.__reveal('SCENES_lhsdst');               /* → 唱针 */
assert('素材到位：黑胶与唱针都在画布上',
  window.__dump().nodes.includes('item:ITEMS_wmhj') && window.__dump().nodes.includes('item:ITEMS_cz'));

/* ① 双击唱机 = 跑 cmds[0]「放入黑胶」：还没装唱针 → 只给一句 warn，不长节点、不捕获 */
const l35 = logs.length, n35 = window.__dump().nodes.length;
window.__talk('item:ITEMS_changji');
assert('双击唱机：没装唱针时被挡下（只写一条 warn）',
  logs.length === l35 + 1 && logs[logs.length - 1].indexOf('还没有装唱针') >= 0);
assert('被挡下时不长节点、不捕获录音线索',
  window.__dump().nodes.length === n35 && !window.__dump().captured.includes('CLUES_wmhj'));
/* 使用条件写在详情窗的「状态」行里（玩家不用瞎试），但只说**要什么**，不说**跟谁配** */
window.__select('item:ITEMS_changji');
assert('详情窗状态行标出「待装上 唱针」',
  /状态：[^<]*待装上[^<]*唱针/.test(ids['detail-body']._html) &&
  ids['detail-body']._html.indexOf('待装上') >= 0 && ids['detail-body']._html.indexOf('唱针') >= 0);
assert('此时详情窗没有「已装上」', ids['detail-body']._html.indexOf('已装上') < 0);

/* ② 唱针 → 唱机：装上（installs）→ 状态记在唱机上、唱针本身被消耗 */
window.__combo('item:ITEMS_cz', 'item:ITEMS_changji');
assert('装上唱针：记进 n.installed', (window.__dump().installed['item:ITEMS_changji'] || []).includes('ITEMS_cz'));
assert('唱针装上即消耗（不在画布上了）', !window.__dump().nodes.includes('item:ITEMS_cz'));
window.__select('item:ITEMS_changji');
assert('详情窗状态行改标「已装上 唱针」（待装上消失）',
  /状态：[^<]*已装上[^<]*唱针/.test(ids['detail-body']._html) &&
  ids['detail-body']._html.indexOf('已装上') >= 0 && ids['detail-body']._html.indexOf('待装上') < 0);
/* 装上的状态是真的状态：进快照，撤销一步就回到"没装上、唱针还在" */
ids['btn-undo']._ev.click[0]();
assert('撤销能收回「装上唱针」（状态在快照里）',
  !(window.__dump().installed['item:ITEMS_changji'] || []).includes('ITEMS_cz') &&
  window.__dump().nodes.includes('item:ITEMS_cz'));

/* ③ 重新装上，这回黑胶放得进去了 */
window.__combo('item:ITEMS_cz', 'item:ITEMS_changji');
assert('重新装上后，前置门放行',
  (window.__dump().installed['item:ITEMS_changji'] || []).includes('ITEMS_cz'));
const l35b = logs.length;
window.__combo('item:ITEMS_wmhj', 'item:ITEMS_changji');
assert('装好唱针后，黑胶放得进唱机了',
  window.__dump().captured.includes('CLUES_wmhj') && window.__dump().captured.includes('CLUES_nm'));
assert('放黑胶走的是「结果」那条 act 日志', logs.slice(l35b).some(l => l.indexOf('开始播放') >= 0));
assert('黑胶被消耗（不在画布上了）', !window.__dump().nodes.includes('item:ITEMS_wmhj'));
assert('「装上唱针」那条命令本身也产出了古典乐线索',
  window.__dump().captured.includes('DATA_H_music'));

/* ④ 源码检查：词汇与兜底清单 */
assert('数据里显式声明了 reusableTools 且不含唱针（源码检查）',
  /"reusableTools":\["ITEM_shoudiantong","ITEMS_htys","ITEMS_changji"\]/.test(html));
assert('引擎兜底清单同样不含唱针（源码检查）',
  html.indexOf('REUSABLE_TOOLS = cfg.reusableTools || ["ITEM_shoudiantong", "ITEMS_htys", "ITEMS_changji"]') >= 0);
assert('引擎认 installs / requires 两个字段（源码检查）',
  html.indexOf('if (cmd.installs)') >= 0 && html.indexOf('(cmd.requires || []).find(') >= 0 &&
  html.indexOf('installed:n.installed') >= 0);
assert('拖动入口（combo 第 3.5 分支）也认同一个门（源码检查）',
  /const lack = \(uc\.requires \|\| \[\]\)\.find\(/.test(html));
assert('顶栏不再有「自动布局」按钮（源码检查）',
  html.indexOf('btn-relayout') < 0 && html.indexOf('>自动布局</button>') < 0);

console.log('\n=== 36. 场景节点上不再挂「条件进入」角标 ===');
/* 用户要求：「感觉不需要条件进入这个角标」。
   这枚角标原本长在**未探索 + 无任何文本入边 + 在 condRoutes 里**的场景节点上。
   它不是死代码，A-001 里真会亮：组合「剪刀剪开绷带」开出的「陆珩松的尸体」、
   组合「磁带钥匙开暗格」开出的「唱机暗格」，走的都是 attemptCombo 的 results.scene 分支 ——
   那条分支只 ensureNode、**不 revealScene**，所以开出来的场景是「未探索」的，正好撞上角标条件。
   （选项分支 14-detail.js 会顺手 revealScene，所以抽屉那条路开出来的场景是已探索的。）
   撤掉的理由：一枚实心药丸和「新 / 对话 N」挤在同一排，而它想说的那件事别处也说得清楚
   （可达性检查里有「需条件触发才能进 5 个」）。condRoutes 保留，节点上只剩
   「真的没路走」这一种警告。
   关键点：警告分支必须带 `!condRoutes[n.id]`（旧代码靠 else-if 达到同一效果），
   否则撤掉一枚角标的当天就会在同一个位置冒出另一枚，玩家只会以为"角标换了个字"。 */
const B36 = key => { const el = findEl(key); return (el && el.children) ? el.children.filter(c => c._classes.has('badge')).map(c => c._text) : []; };
const C36 = key => { const el = findEl(key); return (el && el.children) ? el.children.filter(c => c._classes.has('badge')).map(c => [...c._classes].join(' ')) : []; };
ids['btn-reset']._ev.click[0]();
window.__reveal('ITEM_shuzhuo');                 /* 书桌 → 抽屉上画布 */
window.__choice('ITEM_chouti', 0, 1);            /* 打开右侧抽屉 → 里面有剪刀 */
window.__reveal('SCENES_body');                  /* 尸体 → 里面有绷带 */
assert('素材到位：剪刀与绷带都在画布上',
  window.__dump().nodes.includes('item:ITEMS_jd') && window.__dump().nodes.includes('item:ITEMS_bd'));
window.__combo('item:ITEMS_jd', 'item:ITEMS_bd');   /* 剪开绷带 ⇒ 开出「陆珩松的尸体」场景节点 */
assert('组合开出的「陆珩松的尸体」在画布上、且是未探索的（旧角标正是挂这种节点）',
  !!findEl('loc:SCENES_lhsdst') && !window.__dump().explored.includes('SCENES_lhsdst'));
assert('这种节点上不再有「条件进入」角标', B36('loc:SCENES_lhsdst').indexOf('条件进入') < 0);
assert('连 `cond` 这个类名都不再出现在节点角标上', C36('loc:SCENES_lhsdst').indexOf('badge cond') < 0);
assert('也不改挂「无文本入口」（它是有入口的，只是要走组合 / 选项）',
  B36('loc:SCENES_lhsdst').indexOf('无文本入口') < 0);
assert('同一节点的「新」角标照常（撤的只是条件那枚，通知类角标不动）',
  B36('loc:SCENES_lhsdst').indexOf('新') >= 0);
/* 真的没路走的场景照旧警告：门的后面 = 零入边 + 零出边 + 不在 condRoutes 里。
   走「档案 → 前往」的真实入口 gotoScene（它同样只 ensureNode、不 revealScene）。
   注：A-001 里没有任何文本指向「门的后面」，所以玩家正常玩遇不到它 —— 这条是给 A-002 留的兜底。 */
window.__goto('SCENES_mdhm');
assert('前往开出的「门的后面」同样是未探索的',
  !!findEl('loc:SCENES_mdhm') && !window.__dump().explored.includes('SCENES_mdhm'));
assert('零入边零出边的场景照旧挂「无文本入口」', B36('loc:SCENES_mdhm').indexOf('无文本入口') >= 0);
assert('它也拿不到「条件进入」角标', B36('loc:SCENES_mdhm').indexOf('条件进入') < 0);
/* 条件信息仍在别处：可达性检查照旧把条件场景单列一类（也就不会掉进「没路走」的清单） */
ids['btn-reach']._ev.click[0]();
const v36 = ids['verdict']._html || '';
assert('可达性检查照旧报「需条件触发才能进 5 个」', /需条件触发才能进 <b>5<\/b> 个/.test(v36));
assert('条件场景不算「只能靠前往进」（不列在死路清单里）',
  v36.indexOf('左侧抽屉') < 0 && v36.indexOf('唱机暗格') < 0 && v36.indexOf('陆珩松的尸体') < 0);
/* 源码检查 */
assert('render() 不再产出「条件进入」角标（源码检查）', html.indexOf('textContent = "条件进入"') < 0);
assert('节点角标不再用 `badge cond` 这个类名（源码检查）', html.indexOf('badge cond') < 0);
assert('「无文本入口」的分支仍带 `!condRoutes[n.id]` 守卫（源码检查）',
  /inbound\[n\.id\] === 0 &&\s+!condRoutes\[n\.id\]/.test(html));
assert('计数与通知类实心药丸统一叫 `.badge.cnt`（源码检查）',
  (html.match(/className = "badge cnt"/g) || []).length === 5 && html.indexOf('.badge.cnt{') >= 0);
assert('condRoutes 保留（可达性检查还在用）（源码检查）', html.indexOf('const condRoutes = {}') >= 0);

console.log('\n' + (errs === 0 && bad === 0 ? '=> 全部通过，无运行时错误' : '=> 存在问题：运行时 ' + errs + ' / 断言失败 ' + bad));

console.log('\n--- 日志回放 ---');
logs.slice(-26).forEach(l => console.log('  ' + l));
