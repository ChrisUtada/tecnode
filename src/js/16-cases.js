/* ============ 适性测试 + 调查员证（开场流程） ============ */
const store = (typeof localStorage !== "undefined") ? localStorage : null;
let investigator = null;
try { if (store){ const raw = store.getItem("tec_investigator"); if (raw) investigator = JSON.parse(raw); } } catch(_){}

/* ============ 案件库 / 案件地图（元进度）============
   解锁进度独立存档（key tec_progress），不会被「重置案件」清除。
   解锁条件：只有在本案捕获「真名」（真结局）后，才点亮下一个案件地址。 */
/* 案件数据注册表：id -> gamedata。未注册 = 数据尚未装载（地图上显示「待接入」） */
const CASE_DATA = { A001: DATA };
let CASE_ID = "A001";
const CASES = [
  { id: "A001", code: "CASE A-001", title: "植物学家的花园", note: "异动区域 · 已解锁" },
  { id: "A002", code: "CASE A-002", title: "？？？？？？", note: "加密 · 需在 A-001 捕获真名后解锁" }
];
const PROG_KEY = "tec_progress";
let progress = { unlocked: ["A001"], completed: [], last: "A001" };
try { if (store){ const raw = store.getItem(PROG_KEY); if (raw) progress = Object.assign(progress, JSON.parse(raw)); } } catch(_){}
if (!Array.isArray(progress.unlocked) || !progress.unlocked.length) progress.unlocked = ["A001"];
if (!Array.isArray(progress.completed)) progress.completed = [];
function saveProgress(){ try { if (store) store.setItem(PROG_KEY, JSON.stringify(progress)); } catch(_){} }
function caseById(id){ return CASES.find(c => c.id === id) || null; }
function caseUnlocked(id){ return progress.unlocked.indexOf(id) >= 0; }
function unlockCase(id){
  if (caseUnlocked(id)) return false;
  progress.unlocked.push(id); saveProgress();
  const c = caseById(id);
  log("<b>新案件地址已解锁：" + esc(c ? c.code : id) + "</b>", "cap");
  return true;
}
function unlockNextCase(fromId){
  const i = CASES.findIndex(c => c.id === fromId);
  const next = i >= 0 ? CASES[i + 1] : null;
  if (next) unlockCase(next.id);
}
let mapWinEl = null;
function closeMapWin(){ if (mapWinEl){ mapWinEl.remove(); mapWinEl = null; } }
function toggleMapWin(){ if (mapWinEl){ closeMapWin(); return; } openMapWin(); }
function openMapWin(){
  closeMapWin();
  const w = makeWindow("CASE MAP // 案件地图", closeMapWin);
  w.el.classList.add("map-win");
  const tip = document.createElement("div");
  tip.className = "map-tip";
  tip.textContent = "每个地址对应一宗案件。在本案捕获「真名」后，下一案的地址才会点亮。案件窗的「–」收起会落到桌面右下角的案件卡片上，「×」关闭则收进本图标；两种情况进度都会自动保存，在这里点本案那行就能展开。";
  w.body.appendChild(tip);
  CASES.forEach(c => {
    const unlocked = caseUnlocked(c.id);
    const row = document.createElement("div");
    row.className = "map-card" + (unlocked ? "" : " locked");
    const glyph = document.createElement("div");
    glyph.className = "map-glyph"; glyph.textContent = unlocked ? "▦" : "▨";
    const meta = document.createElement("div");
    meta.className = "map-meta";
    const t = document.createElement("div");
    t.className = "map-title";
    t.textContent = c.code + " · " + (unlocked ? caseTitleOf(c.id) : "？？？？？？");
    const s = document.createElement("div");
    s.className = "map-note"; s.textContent = caseNoteOf(c.id);
    meta.appendChild(t); meta.appendChild(s);
    const state = document.createElement("div");
    const loadable = unlocked && !!CASE_DATA[c.id];
    const isHere = c.id === CASE_ID;
    if (!unlocked){ state.className = "map-state lock"; state.textContent = "加密"; }
    else if (isHere){ state.className = "map-state on"; state.textContent = caseOpen ? "当前" : "进入"; }
    else if (!loadable){ state.className = "map-state pend"; state.textContent = "待接入"; }
    else { state.className = "map-state"; state.textContent = "可进入"; }
    row.appendChild(glyph); row.appendChild(meta); row.appendChild(state);
    row.dataset.case = c.id;
    if (c.id === lastEnteredCase) row.classList.add("ignite");
    /* 已经开着的本案不用再点；有地址的行都能进 */
    if (unlocked && !(isHere && caseOpen)){
      row.classList.add("clickable");
      row.addEventListener("click", () => enterCase(c.id));
    }
    w.body.appendChild(row);
  });
  desktopEl.appendChild(w.el);
  makeFloatDraggable(w.el, false);
  mapWinEl = w.el;
}

/* ==== 案件存档（各存各档）与切换 ====
   每个案件一份独立存档：tec_case_<id> = snapshot()（与撤销栈同构）。
   切换 = 存当前案 -> 载目标案数据 -> 清会话态 -> 重建（有档续档，无档全新开局）。 */
const CASE_STORE_PREFIX = "tec_case_";
let lastEnteredCase = null;
let switchingCase = false;
/* 案件窗是否开着：关掉 = 回到案件地图，进度存进本案的档 */
let caseOpen = true;
function caseStoreKey(id){ return CASE_STORE_PREFIX + id; }
function saveCaseState(id){
  try {
    if (!store) return;
    /* 在快照基础上额外记住镜头位置，回访时原位恢复（老存档没有 __view 就退回 fit） */
    const snap = JSON.parse(snapshot());
    snap.__view = { x: view.x, y: view.y, k: view.k };
    store.setItem(caseStoreKey(id), JSON.stringify(snap));
  } catch(_){}
}
function loadCaseState(id){
  try { if (store){ const raw = store.getItem(caseStoreKey(id)); if (raw) return raw; } } catch(_){}
  return null;
}
function clearCaseState(id){
  try { if (store) store.removeItem(caseStoreKey(id)); } catch(_){}
}
function hasCaseSave(id){
  try { if (store) return store.getItem(caseStoreKey(id)) != null; } catch(_){}
  return false;
}
function setCaseWinVisible(v){
  const cw = document.getElementById("case-win");
  if (cw && cw.style) cw.style.display = v ? "" : "none";
  caseOpen = !!v;
}
/* 案件窗关着的时候，画布上的操作全部拦下 —— 否则是在操作一个看不见的画布 */
function requireCase(){
  if (caseOpen) return true;
  toast("当前不在案件中，请先把它展开（右下角的案件卡片，或案件地图里的本案那行）");
  return false;
}

/* ==== 案件窗离屏后的两个落点（互斥）====
   – 收起（最小化）：缩成桌面右下角的案件卡片 #case-dock，可拖动，点卡片展开
   × 关闭：缩进桌面左侧的「案件地图」图标 #map-icon，图标打「已关闭」角标，进案件地图展开
   案件窗在屏幕上时两者都为 false。 */
let caseHeld = false;     /* 挂在「案件地图」图标上（× 关闭） */
let caseDockOn = false;   /* 停在右下角卡片上（– 收起） */

/* ---- 落点 A：右下角案件卡片 ---- */
function updateCaseDock(){
  const c = caseById(CASE_ID);
  const set = (id, txt) => { const el = document.getElementById(id); if (el) el.textContent = txt; };
  set("cd-code", c ? c.code : CASE_ID);
  set("cd-title", caseTitleOf(CASE_ID));
  set("cd-sub", hasCaseSave(CASE_ID) ? "进度已保存 · 点此展开" : "点此展开");
}
function showCaseDock(v){
  caseDockOn = !!v;
  const d = document.getElementById("case-dock");
  if (!d || !d.classList) return;
  if (v) updateCaseDock();
  d.classList.toggle("on", !!v);
}
/* 右下角卡片可拖动：按住拖动 = 挪位置（拖动过的那一次不展开），原地单击 = 展开案件。
   它原来是靠 right/bottom 定位的，首次按下时换算成 left/top。
   注意 moved 要在 pointerdown 复位 —— 这样"拖完紧跟的 click"被吞掉，下一次正常单击又能用。 */
function attachDock(el, onPick){
  if (!el || !el.addEventListener) return;
  let dragging = false, moved = false, sx = 0, sy = 0, ox = 0, oy = 0;
  el.addEventListener("pointerdown", e => {
    if (e.button !== 0) return;
    if (el.style.left === "" || el.style.left == null){
      const r = el.getBoundingClientRect(), sr = desktopEl.getBoundingClientRect();
      el.style.left = (r.left - sr.left) + "px";
      el.style.top  = (r.top  - sr.top ) + "px";
      el.style.right = "auto"; el.style.bottom = "auto";
    }
    dragging = true; moved = false;
    sx = e.clientX; sy = e.clientY;
    ox = parseFloat(el.style.left) || 0; oy = parseFloat(el.style.top) || 0;
    try { el.setPointerCapture(e.pointerId); } catch(_){}
    if (e.stopPropagation) e.stopPropagation();
  });
  el.addEventListener("pointermove", e => {
    if (!dragging) return;
    if (!moved && Math.abs(e.clientX - sx) + Math.abs(e.clientY - sy) < 5) return;
    moved = true;
    const r = desktopEl.getBoundingClientRect();
    const w = el.offsetWidth || 170, h = el.offsetHeight || 56;
    el.style.left = Math.max(0, Math.min((r.width  || 1200) - w, ox + e.clientX - sx)) + "px";
    el.style.top  = Math.max(0, Math.min((r.height ||  800) - h, oy + e.clientY - sy)) + "px";
  });
  el.addEventListener("pointerup", () => { dragging = false; });
  /* 落点默认展开案件；TEC 助手卡片传了 onPick，就展开 TEC 对话窗 */
  el.addEventListener("click", () => { if (!moved){ if (onPick) onPick(); else enterCase(CASE_ID); } });
}
/* 收缩 / 展开的位移与缩放：把案件窗和右下角卡片的中心对上。
   卡片只用 visibility 隐藏、保留布局盒，所以隐藏时也量得到（这是选它当落点的一个原因）。 */
function caseDockMotion(){
  const cw = document.getElementById("case-win"), d = document.getElementById("case-dock");
  if (!cw || !d || typeof cw.getBoundingClientRect !== "function") return null;
  if (typeof d.getBoundingClientRect !== "function") return null;
  const w = cw.getBoundingClientRect(), r = d.getBoundingClientRect();
  if (!w.width || !w.height || !r.width || !r.height) return null;
  const dx = (r.left + r.width / 2) - (w.left + w.width / 2);
  const dy = (r.top + r.height / 2) - (w.top + w.height / 2);
  const s  = Math.max(.05, Math.min(r.width / w.width, r.height / w.height));
  return { s: s, tf: "translate(" + dx + "px," + dy + "px) scale(" + s + ")" };
}

/* ---- 落点 B：「案件地图」图标 ---- */
function updateMapBadge(){
  const icon = document.getElementById("map-icon");
  if (!icon || !icon.querySelector) return;
  let b = icon.querySelector(".badge");
  if (caseHeld){
    if (!b){ b = document.createElement("span"); b.className = "badge cnt"; icon.appendChild(b); }
    b.textContent = "已关闭";
  } else if (b) b.remove();
}
function setCaseHeld(v){
  caseHeld = !!v;
  updateMapBadge();
}
/* 把案件窗和「案件地图」图标的图形（.icon-glyph，不含下面的文字标签）中心对上。
   无头 stub 不解析 HTML、取不到 .icon-glyph，就退回整个图标元素（它有 offsetWidth/Height，照样解得出来）。 */
function caseIconMotion(){
  const cw = document.getElementById("case-win");
  const icon = document.getElementById("map-icon");
  if (!cw || !icon || typeof cw.getBoundingClientRect !== "function") return null;
  const anchor = (icon.querySelector && icon.querySelector(".icon-glyph")) || icon;
  if (typeof anchor.getBoundingClientRect !== "function") return null;
  const w = cw.getBoundingClientRect(), r = anchor.getBoundingClientRect();
  if (!w.width || !w.height || !r.width || !r.height) return null;
  const dx = (r.left + r.width / 2) - (w.left + w.width / 2);
  const dy = (r.top + r.height / 2) - (w.top + w.height / 2);
  const s  = Math.max(.05, Math.min(r.width / w.width, r.height / w.height));
  return { s: s, tf: "translate(" + dx + "px," + dy + "px) scale(" + s + ")" };
}

/* ---- 两个落点的统一开关 ---- */
function caseParkPoint(p){
  if (p === "dock"){ setCaseHeld(false); showCaseDock(true); }
  else { showCaseDock(false); setCaseHeld(true); }
}
function caseParkMotion(p){ return (p === "dock") ? caseDockMotion() : caseIconMotion(); }
/* 当前案件落在哪（案件窗开着时返回 null） */
function caseParkedAt(){ return caseOpen ? null : (caseDockOn ? "dock" : (caseHeld ? "icon" : null)); }
function caseMotionReset(){
  const cw = document.getElementById("case-win");
  if (!cw) return;
  if (cw.style){
    cw.style.transition = ""; cw.style.transform = ""; cw.style.transformOrigin = ""; cw.style.opacity = "";
  }
  if (cw.classList) cw.classList.remove("case-switching");
}
/* 离屏：从当前位置缩到寄存落点上（目标点由 caseParkMotion 给） */
function caseMotionApply(tf){
  const cw = document.getElementById("case-win");
  if (!cw || !cw.style) return;
  cw.style.transition = "transform .26s cubic-bezier(.4,0,.2,1), opacity .26s ease";
  cw.style.transformOrigin = "50% 50%";
  cw.style.transform = tf;
  cw.style.opacity = "0";
}
/* 展开：从寄存落点放大回原位（窗口要已经显示出来，才量得到目标位置）。p = "dock" | "icon" */
function caseMotionPlayIn(p){
  const cw = document.getElementById("case-win");
  if (!cw || !cw.style) return;
  const m = caseParkMotion(p);
  if (!m) return;
  cw.style.transition = "none";
  cw.style.transformOrigin = "50% 50%";
  cw.style.transform = m.tf;
  cw.style.opacity = "0";
  if (typeof cw.getBoundingClientRect === "function") cw.getBoundingClientRect();   /* 强制回流，让起始态生效 */
  cw.style.transition = "transform .26s cubic-bezier(.4,0,.2,1), opacity .26s ease";
  cw.style.transform = "none";
  cw.style.opacity = "1";
  const t = setTimeout(caseMotionReset, 300);
  if (!t) caseMotionReset();
}
/* 案件标题：优先用案件数据自己声明的 config.caseTitle，否则退回案件库里的占位名 */
function caseTitleOf(id){
  const c = caseById(id);
  if (!c) return id;
  const d = CASE_DATA[id];
  return (d && d.config && d.config.caseTitle) || c.title || "？？？？？？";
}
/* 案件副标题：未解锁时用案件库里的加密提示，解锁后用数据自带说明（或通用文案） */
function caseNoteOf(id){
  const c = caseById(id);
  if (!c) return "";
  if (!caseUnlocked(id)) return c.note;
  const d = CASE_DATA[id];
  if (!d) return "地址已解锁 · 案件数据待装载";
  const base = (d.config && d.config.caseNote) || "异动区域 · 已解锁";
  return hasCaseSave(id) ? base + " · 有存档" : base;
}
/* 外壳上的案件标识（案件窗标题栏 + 顶栏副标题） */
function updateCaseChrome(){
  const c = caseById(CASE_ID);
  if (!c) return;
  const title = document.getElementById("case-title");
  if (title) title.textContent = c.code + " // " + caseTitleOf(CASE_ID);
  const sub = (typeof document.querySelector === "function") ? document.querySelector(".brand small") : null;
  if (sub) sub.textContent = "节点原型 v2 · 案件 " + c.code.replace(/^CASE\s+/, "");
}
/* 从案件地图进入案件：
   已经开着本案 -> 空操作；开着别的案 -> 存旧案 + 换档；本来关着 -> 不存，直接续档。 */
function enterCase(id){
  if (switchingCase) return false;
  if (caseOpen && id === CASE_ID) return false;
  const c = caseById(id);
  if (!c) return false;
  if (!caseUnlocked(id)){ toast("该案件地址尚未解密"); return false; }
  if (!CASE_DATA[id]){ toast("案件 <b>" + esc(c.code) + "</b> 的数据尚未装载"); return false; }
  const cw = document.getElementById("case-win");
  /* 本来已经离屏：从它当时落下的地方（右下角卡片 / 案件地图图标）放大展开回来 */
  if (!caseOpen){
    const p = caseParkedAt() || "icon";
    doEnterCase(id, null);
    caseMotionPlayIn(p);
    return true;
  }
  const from = CASE_ID;
  const swap = () => {
    switchingCase = false;
    if (cw && cw.classList) cw.classList.remove("case-switching");
    doEnterCase(id, from);
  };
  /* 屏上有案就先淡出再换档。无定时器的环境（无头驱动）立即同步换档。 */
  if (cw && cw.classList){
    cw.classList.remove("case-switching");
    cw.classList.add("case-switching");
    switchingCase = true;
    const t = setTimeout(swap, 180);
    if (!t) swap();
  } else swap();
  return true;
}
function doEnterCase(id, from){
  const c = caseById(id);
  const snap = loadCaseState(id);    /* 先把目标案的档读出来，再存旧案，免得两边撞在一起 */
  if (from){ saveCaseState(from); resetTec(); closeBagWin(); closeClueWin(); }   /* 只有换案才清 TEC 与两扇收纳窗；同案回访保留 */
  applyCaseData(CASE_DATA[id]);      /* 2. 载目标案数据 */
  CASE_ID = id;
  progress.last = id; saveProgress();
  /* 3. 清会话态：撤销栈 / 图标位置 */
  history = [];
  resetIconPositions();
  closeMapWin();
  lastEnteredCase = id;
  /* 4. 清掉两个寄存落点、打开案件窗、重建：有档续档，无档全新开局 */
  showCaseDock(false);
  setCaseHeld(false);
  caseMotionReset();
  setCaseWinVisible(true);
  boot({ fromSnapshot: snap });
  log("已进入案件 <b>" + esc(c.code) + " // " + esc(caseTitleOf(id)) + "</b>", "sys");
}
/* 案件窗离屏：p = "dock"（– 收起 → 右下角卡片）/ "icon"（× 关闭 → 「案件地图」图标）。
   两条路都先存盘、都不弹案件地图，只是落点不同。 */
function parkCase(p){
  if (!caseOpen || switchingCase) return false;
  const cw = document.getElementById("case-win");
  const finish = () => {
    switchingCase = false;
    caseMotionReset();
    saveCaseState(CASE_ID);          /* 离开现场，先把进度存进本案的档 */
    setCaseWinVisible(false);
    caseParkPoint(p);
    history = [];
    /* 浮层都锚在画布上，画布一藏就没意义了，一起收掉
       （TEC 是独立助手窗、证物袋 / 线索册是随身收纳，三扇常驻窗都保留） */
    closeBubble(); closeNarr(); closePwPop();
    clearSelection();
    setDetailWin(false);
  };
  /* – 收起：带收缩动画缩到右下角卡片（落点先亮出来当靶子，案件窗再缩过去）。
     × 关闭：不做收缩动画，直接离屏 —— 用户反馈"缩进图标"那下不舒服。
     展开回来时仍走 caseMotionPlayIn，从落点放大（保留）。 */
  const m = (p === "dock") ? caseParkMotion(p) : null;
  if (cw && cw.style && m){
    caseParkPoint(p);
    caseMotionApply(m.tf);
    switchingCase = true;
    const t = setTimeout(finish, 280);
    if (!t) finish();
  } else finish();
  return true;
}
/* – 收起：缩成右下角的案件卡片 */
function stowCase(){ return parkCase("dock"); }
/* × 关闭：直接离屏，落到「案件地图」图标（不做收缩动画） */
function closeCase(){ return parkCase("icon"); }

const SENSE_FLAVOR = {
  vision:  "你习惯先看清，再行动。",
  hearing: "世界的背面，总有声音先抵达你。",
  touch:   "你相信手的判断，胜过眼睛。",
  smell:   "气味是不会说谎的证人。",
  taste:   "真相的味道，你尝一口就知道。"
};
const QUIZ = [
  { q: "进入一片漆黑的异动区域，你首先依靠什么？", opts: [
    ["vision","眯起眼睛寻找微光"],["hearing","屏息聆听最细微的声响"],["touch","伸出手触摸前方的空气"],
    ["smell","分辨空气中气味的变化"],["taste","舌尖抵住上颚，尝一尝空气的味道"] ]},
  { q: "一份被水浸透的档案，你最先注意到什么？", opts: [
    ["vision","字迹晕染开的形状"],["hearing","纸页翻动时的脆响"],["touch","纸张潮湿的重量"],
    ["smell","霉菌与墨水的气味"],["taste","墨水淡淡的苦涩（别想歪，是用鼻子旁边的那点想象力）"] ]},
  { q: "以下哪种异常最让你不安？", opts: [
    ["vision","镜子里慢半拍的自己"],["hearing","反复倒放的人声"],["touch","没有来源的冰冷触碰"],
    ["smell","凭空出现的花香"],["taste","嘴里突然泛起的铁锈味"] ]}
];
function genInvId(){
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let a = "", n = "";
  for (let i = 0; i < 2; i++) a += chars[Math.floor(Math.random() * chars.length)];
  for (let i = 0; i < 4; i++) n += Math.floor(Math.random() * 10);
  return "TEC-" + a + "-" + n;
}

let introWinEl = null, introState = null, introBackdropEl = null;
function closeIntroLight(){
  if (introWinEl){ introWinEl.remove(); introWinEl = null; }
  if (introBackdropEl){ introBackdropEl.remove(); introBackdropEl = null; }
  introState = null;
}
function openIntro(){
  closeIntroLight();
  const bd = document.createElement("div");
  bd.id = "intro-backdrop";
  (document.body || stage).appendChild(bd);
  introBackdropEl = bd;
  const w = makeWindow("APTITUDE // 调查员适性测试", () => {});
  w.el.classList.add("intro-win");
  const x = w.bar.querySelector(".syswin-x");
  if (x) x.style.display = "none";   /* 开场测试必须完成，不允许关闭 */
  bd.appendChild(w.el);
  introWinEl = w.el;
  introState = { step: "name", name: "", nameInput: null, answers: [], card: null,
                 avatarId: AVATAR_DEFAULT_ID };
  renderIntro();
}
/* 窗标题（三个步骤各一个抬头） */
function setIntroTitle(t){
  const el = introWinEl && introWinEl.querySelector(".syswin-title");
  if (el) el.textContent = t;
}
function renderIntro(){
  if (!introWinEl || !introState) return;
  const body = introWinEl.querySelector(".syswin-body");
  if (!body) return;
  body.innerHTML = "";
  const st = introState;
  if (st.step === "name"){
    const p = document.createElement("div");
    p.textContent = "在接入异动区域之前，T.E.C-OS 需要登记你的信息，并完成一次简短的适性测试。";
    body.appendChild(p);
    const input = document.createElement("input");
    input.className = "intro-name";
    input.placeholder = "请输入姓名";
    input.maxLength = 12;
    input.value = st.name || "";
    input.addEventListener("input", e => { st.name = e.target.value; });
    body.appendChild(input);
    st.nameInput = input;
    const btn = document.createElement("button");
    btn.className = "primary";
    btn.textContent = "[ 开始测试 ]";
    btn.addEventListener("click", beginQuiz);
    body.appendChild(btn);
    return;
  }
  if (st.step === "avatar"){
    const tip = document.createElement("div");
    tip.className = "avatar-tip";
    tip.textContent = AVATAR_TIP;
    body.appendChild(tip);
    body.appendChild(buildAvatarPicker(avatarUnlocked(), st.avatarId, avatarLockedCount(), pickIntroAvatar));
    body.appendChild(avatarCounterNode());
    const btn = document.createElement("button");
    btn.className = "primary mx-sync";   /* 与下一步的「确认领证」同一条通栏按钮，流程里看着是一件事 */
    btn.textContent = "[ 用这张 ]";
    btn.addEventListener("click", confirmAvatarStep);
    body.appendChild(btn);
    return;
  }
  if (st.step === "card"){
    body.appendChild(buildCert(st.card));
    const btn = document.createElement("button");
    btn.className = "primary mx-sync";
    btn.textContent = "[ 确认领证 ]";
    btn.addEventListener("click", confirmCard);
    body.appendChild(btn);
    const back = document.createElement("button");
    back.className = "avatar-back";
    back.textContent = "[ 换一张头像 ]";
    back.addEventListener("click", backToAvatarStep);
    body.appendChild(back);
    return;
  }
  const qi = st.step, q = QUIZ[qi];
  const prog = document.createElement("div");
  prog.className = "quiz-prog";
  prog.textContent = "第 " + (qi + 1) + " / " + QUIZ.length + " 问";
  body.appendChild(prog);
  const qt = document.createElement("div");
  qt.className = "quiz-q";
  qt.textContent = q.q;
  body.appendChild(qt);
  q.opts.forEach((o, i) => {
    const b = document.createElement("button");
    b.className = "quiz-opt";
    b.textContent = o[1];
    b.addEventListener("click", () => answerQuestion(i));
    body.appendChild(b);
  });
}
function setIntroName(v){
  if (!introState) return;
  introState.name = v;
  if (introState.nameInput) introState.nameInput.value = v;
}
function beginQuiz(){
  if (!introState) return;
  const v = String((introState.nameInput && introState.nameInput.value) || introState.name || "").trim();
  if (!v){
    if (introWinEl){ introWinEl.classList.remove("shake"); void introWinEl.offsetWidth; introWinEl.classList.add("shake"); }
    return;
  }
  introState.name = v;
  introState.step = 0;
  renderIntro();
}
function answerQuestion(i){
  if (!introState || typeof introState.step !== "number") return;
  const q = QUIZ[introState.step];
  const opt = q && q.opts[i];
  if (!opt) return;
  introState.answers.push(opt[0]);
  if (introState.step < QUIZ.length - 1){ introState.step++; renderIntro(); }
  else finishQuiz();
}
function finishQuiz(){
  const counts = {};
  let best = null, bestN = 0;
  introState.answers.forEach(s => {   /* 平局取先达到的（按答题顺序） */
    counts[s] = (counts[s] || 0) + 1;
    if (counts[s] > bestN){ bestN = counts[s]; best = s; }
  });
  introState.card = { name: introState.name, id: genInvId(), sense: best,
    date: new Date().toISOString().slice(0, 10), avatarId: introState.avatarId || AVATAR_DEFAULT_ID };
  introState.step = "avatar";   /* 答完三问先挑头像，再领证 */
  setIntroTitle("AVATAR // 选择头像");
  renderIntro();
}
/* 选头像步骤：点一格 = 记下并就地重画（不动步进） */
function pickIntroAvatar(id){
  if (!introState || introState.step !== "avatar") return;
  introState.avatarId = id;
  if (introState.card) introState.card.avatarId = id;
  renderIntro();
}
/* 头像 → 领证（证件照照选中的那张画） */
function confirmAvatarStep(){
  if (!introState || introState.step !== "avatar") return;
  if (introState.card) introState.card.avatarId = introState.avatarId;
  introState.step = "card";
  setIntroTitle("INVESTIGATOR // 调查员证");
  renderIntro();
}
/* 领证前反悔：退回选头像那一步 */
function backToAvatarStep(){
  if (!introState || introState.step !== "card") return;
  introState.step = "avatar";
  setIntroTitle("AVATAR // 选择头像");
  renderIntro();
}
function confirmCard(){
  if (!introState || !introState.card) return;
  /* 老调用路径（直接 confirm 跳过选头像）不拦：拿默认头像补上，免得证件照空着 */
  if (introState.avatarId) introState.card.avatarId = introState.avatarId;
  investigator = introState.card;
  try { if (store) store.setItem("tec_investigator", JSON.stringify(investigator)); } catch(_){}
  if (introWinEl) introWinEl.classList.add("shrink");
  setTimeout(finishIntro, 420);   /* stub 的 setTimeout 是 noop：测试用 __intro.finish() 收尾 */
}
function finishIntro(){
  if (!introState) return;
  closeIntroLight();
  mountInvChip();
  /* 不在这里放起始场景的叙事卡：开局只留一个「未探索」的花园节点，
     等玩家双击展开时才出叙事卡（见 boot / revealScene）。 */
  log("调查员 <b>" + esc(investigator.name) + "</b>（" + esc(investigator.id) + "）已接入 T.E.C-OS", "sys");
}

/* 由编号确定性生成的 5×5 镜像像素识别图（div 网格，不用 canvas；cell 为每格边长 px） */
function genAvatar(id, cell){
  const px = cell || 18;
  let h = 0;
  const s = String(id || "");
  for (let i = 0; i < s.length; i++){ h = (h * 31 + s.charCodeAt(i)) >>> 0; }
  const grid = [];
  for (let y = 0; y < 5; y++){
    for (let x = 0; x < 3; x++){
      h = (h * 1103515245 + 12345) >>> 0;
      grid[y * 5 + x] = grid[y * 5 + (4 - x)] = (h >>> 16) & 1;
    }
  }
  const box = document.createElement("div");
  box.className = "cert-photo";
  box.style.gridTemplateColumns = "repeat(5, " + px + "px)";
  box.style.gridTemplateRows = "repeat(5, " + px + "px)";
  grid.forEach(on => {
    const d = document.createElement("div");
    d.className = "px" + (on ? " on" : "");
    d.style.width = px + "px"; d.style.height = px + "px";
    box.appendChild(d);
  });
  return box;
}

/* ============ AVATAR // 头像库（测试末尾选，领证后也能换）============
   可选 = 常驻两人（执行者 / TEC，一开局就在）+ 已结识的人 —— 判据直接沿用名册的 `metChars()`。
   池子是**现算**的 ⇒「每遇到一个新人物就解锁一张」不需要任何写盘逻辑；
   未解锁的只画一个虚线「？」占位，**不显示名字**（免得剧透还没出场的人）。
   选中的 id 记在 `investigator.avatarId`；没记（本轮之前的老存档）就照旧用 cert-avatar.png。 */
const AVATAR_INITIAL    = ["CHARS_EXEC", "CHARS_TEC"];   /* 初始可选，顺序 = 并排先后 */
const AVATAR_DEFAULT_ID = "CHARS_EXEC";                  /* 测试流程里默认选中的那张 */
const AVATAR_TIP = "挑一张头像印在证件上。每结识一位新人物，就会多出一张可选的头像。";
function avatarNameOf(id){
  const p = ROSTER_PINNED.find(x => x.id === id);        /* 执行者的名字写在这里，CHARS 里没有它 */
  if (p && p.name) return p.name;
  return (CHARS[id] || {}).name || id;
}
/* 已解锁的 id（有序：常驻在前，其余沿用名册顺序） */
function avatarUnlocked(){
  const ids = AVATAR_INITIAL.slice();
  metChars().forEach(id => { if (ids.indexOf(id) < 0) ids.push(id); });
  return ids;
}
/* 还没解锁的候选张数（只报数、不报是谁） */
function avatarLockedCount(){
  const have = avatarUnlocked();
  return Object.keys(CHARS).filter(id => have.indexOf(id) < 0).length;
}
/* 一格头像框（有美术稿用像素图，没有的用首字方块）—— 与名册共用同一套 `.av` 写法 */
function buildAvatarFace(id){
  const box = document.createElement("span");
  box.className = "av";
  const art = rosterAvatar(id);
  if (art){
    const im = document.createElement("img");
    im.src = "data:image/png;base64," + art;
    im.alt = ""; im.draggable = false;
    box.appendChild(im);
  } else {
    const ini = document.createElement("span");
    ini.className = "ini"; ini.textContent = avatarNameOf(id).slice(0, 1);
    box.appendChild(ini);
  }
  return box;
}
/* 选头像的格子阵列：values = 已解锁（有序）/ sel = 当前选中 / locked = 未解锁占位数 */
function buildAvatarPicker(values, sel, locked, onPick){
  const grid = document.createElement("div");
  grid.className = "avatar-grid";
  values.forEach(id => {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "avatar-pick" + (id === sel ? " sel" : "");
    b.dataset.id = id;
    b.appendChild(buildAvatarFace(id));
    const nm = document.createElement("span");
    nm.className = "nm"; nm.textContent = avatarNameOf(id);
    b.appendChild(nm);
    b.addEventListener("click", () => onPick(id));
    grid.appendChild(b);
  });
  for (let i = 0; i < (locked || 0); i++){
    const d = document.createElement("div");
    d.className = "avatar-pick locked";
    const av = document.createElement("span");
    av.className = "av"; av.textContent = "?";
    d.appendChild(av);
    const nm = document.createElement("span");
    nm.className = "nm"; nm.textContent = "未解锁";
    d.appendChild(nm);
    grid.appendChild(d);
  }
  return grid;
}
/* 解锁计数行：「已解锁 n / m」（m = 可选 + 未解锁 = 常驻 2 + CHARS 全体） */
function avatarCounterNode(){
  const d = document.createElement("div");
  d.className = "avatar-count";
  const got = avatarUnlocked().length, lock = avatarLockedCount();
  d.textContent = "已解锁 " + got + " / " + (got + lock);
  return d;
}
/* 证件照内容：选了头像就照那个画（像素图 / 首字方块）；
   没选（老存档）或该 id 取不到图 ⇒ 退回固定的调查员照片 */
function fillCertPhoto(box, c){
  const id = c && c.avatarId;
  const art = id ? rosterAvatar(id) : null;
  if (id && art){
    const im = document.createElement("img");
    im.src = "data:image/png;base64," + art;
    im.alt = "avatar";
    box.appendChild(im);
    return;
  }
  if (id){
    const ini = document.createElement("span");
    ini.className = "ini"; ini.textContent = avatarNameOf(id).slice(0, 1);
    box.appendChild(ini);
    return;
  }
  const im = document.createElement("img");
  im.src = "data:image/png;base64,@@ASSET:cert-avatar.png@@";
  im.alt = "avatar";
  box.appendChild(im);
}

/* 调查员证（发证 / 回看共用）：头部色带 + 身份区（头像+字段）+ 倾向区 + 签发区 */
function buildCert(c){
  const wrap = document.createElement("div");
  wrap.className = "inv-cert";
  const head = document.createElement("div");
  head.className = "cert-head"; head.textContent = "T.E.C-OS 调查员证";
  wrap.appendChild(head);

  const sec1 = document.createElement("div");
  sec1.className = "cert-sec cert-id";
  const avBox = document.createElement("div");
  avBox.className = "cert-photo";
  fillCertPhoto(avBox, c);
  sec1.appendChild(avBox);
  const fields = document.createElement("div");
  fields.className = "cert-fields";
  const nm = document.createElement("div"); nm.className = "cert-name"; nm.textContent = c.name;
  const idn = document.createElement("div"); idn.className = "cert-idno"; idn.textContent = c.id;
  const lv = document.createElement("div"); lv.className = "cert-frow"; lv.textContent = "等级：初级调查员";
  fields.appendChild(nm); fields.appendChild(idn); fields.appendChild(lv);
  sec1.appendChild(fields);
  wrap.appendChild(sec1);

  const sec2 = document.createElement("div");
  sec2.className = "cert-sec dashed";
  const sn = document.createElement("div"); sn.className = "cert-sense";
  sn.textContent = (SENSES[c.sense] || c.sense) + "主导型";
  const fl = document.createElement("div"); fl.className = "cert-flavor";
  fl.textContent = SENSE_FLAVOR[c.sense] || "";
  sec2.appendChild(sn); sec2.appendChild(fl);
  wrap.appendChild(sec2);

  const sec3 = document.createElement("div");
  sec3.className = "cert-sec dashed cert-issue";
  const dt = document.createElement("div"); dt.textContent = "签发日期：" + c.date;
  const stamp = document.createElement("div"); stamp.className = "cert-stamp";
  stamp.innerHTML = "T.E.C<br>核准";
  sec3.appendChild(dt); sec3.appendChild(stamp);
  wrap.appendChild(sec3);
  return wrap;
}

/* 顶栏徽标 + 证件回看 */
let invChipEl = null, invReviewEl = null;
function mountInvChip(){
  if (!investigator) return;
  if (!invChipEl){
    invChipEl = document.createElement("span");
    invChipEl.id = "inv-chip";
    invChipEl.addEventListener("click", openCardReview);
    const brand = document.querySelector(".brand");
    if (brand && brand.parentNode && brand.parentNode.insertBefore) brand.parentNode.insertBefore(invChipEl, brand.nextSibling);
    else desktopEl.appendChild(invChipEl);
  }
  invChipEl.textContent = "▣ " + investigator.name + " · " + investigator.id;
}
function closeInvReview(){ if (invReviewEl){ invReviewEl.remove(); invReviewEl = null; } }

/* ---- 换头像（领证之后）：证件窗里的「更换头像」开这扇独立窗 ----
   池子同样是现算的 ⇒ 之后结识的人会立刻出现在里面，不需要刷新任何东西。 */
let avatarWinEl = null, avatarPickId = null;
function closeAvatarWin(){ if (avatarWinEl){ avatarWinEl.remove(); avatarWinEl = null; } }
function openAvatarWin(){
  if (!investigator) return false;
  closeAvatarWin();
  avatarPickId = investigator.avatarId || AVATAR_DEFAULT_ID;
  const w = makeWindow("AVATAR // 选择头像", closeAvatarWin);
  w.el.classList.add("avatar-win");
  avatarWinEl = w.el;
  renderAvatarWin();
  desktopEl.appendChild(w.el);
  makeFloatDraggable(w.el, false);
  return true;
}
function renderAvatarWin(){
  if (!avatarWinEl) return;
  const body = avatarWinEl.querySelector(".syswin-body");
  if (!body) return;
  body.innerHTML = "";
  const tip = document.createElement("div");
  tip.className = "avatar-tip";
  tip.textContent = AVATAR_TIP;
  body.appendChild(tip);
  body.appendChild(buildAvatarPicker(avatarUnlocked(), avatarPickId, avatarLockedCount(), id => {
    avatarPickId = id; renderAvatarWin();
  }));
  body.appendChild(avatarCounterNode());
  const btn = document.createElement("button");
  btn.className = "primary";
  btn.textContent = "[ 换上这张 ]";
  btn.addEventListener("click", confirmAvatarPick);
  body.appendChild(btn);
}
function confirmAvatarPick(){
  if (!investigator || !avatarPickId) return false;
  investigator.avatarId = avatarPickId;
  try { if (store) store.setItem("tec_investigator", JSON.stringify(investigator)); } catch(_){}
  log("调查员头像更换为 <b>" + esc(avatarNameOf(avatarPickId)) + "</b>", "sys");
  closeAvatarWin();
  /* 证件窗开着就整扇重开一次，照片立刻换过来（窗位固定，看不见跳动） */
  const hadCert = !!invReviewEl;
  closeInvReview();
  if (hadCert) openCardReview();
  return true;
}

function openCardReview(){
  if (!investigator) return;
  closeInvReview();
  const w = makeWindow("INVESTIGATOR // 调查员证", closeInvReview);
  w.el.classList.add("cert-win");
  w.body.appendChild(buildCert(investigator));
  const btnAv = document.createElement("button");
  btnAv.textContent = "[ 更换头像 ]";
  btnAv.addEventListener("click", openAvatarWin);
  const btn = document.createElement("button");
  btn.textContent = "[ 重新测试 ]";
  btn.addEventListener("click", () => {
    try { if (store) store.removeItem("tec_investigator"); } catch(_){}
    investigator = null;
    if (invChipEl){ invChipEl.remove(); invChipEl = null; }
    closeInvReview();
    openIntro();
  });
  const actions = document.createElement("div");
  actions.className = "cert-actions";
  actions.appendChild(btnAv);
  actions.appendChild(btn);
  w.body.appendChild(actions);
  desktopEl.appendChild(w.el);
  makeFloatDraggable(w.el, false);
  invReviewEl = w.el;
}
