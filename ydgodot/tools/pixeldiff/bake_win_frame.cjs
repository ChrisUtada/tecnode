/* 烘焙系统窗九切片：把 Web 的「卡面 + 1px 发丝边 + 13px 圆角 + 四层 --win-shadow」
   一次性烘成一张带 alpha 的 PNG，P3 之后 Godot 侧的 SysWindow 直接拿它当 NinePatchRect。
   为什么不用 shader 算：--win-shadow 是四条 box-shadow 叠加（含一条 22px 模糊 + 一条顶部 inset
   高光），SDF 单层近似永远差一口气；烘焙是像素级准确的。

   做法：同一帧拍两次（纯白底 / 纯黑底），逐像素反解直通 alpha：
       over_bg = src*a + bg*(1-a)
     ⇒ a = 1 - (V_white - V_black)/255 ,  src = (V_white - 255*(1-a)) / a

   输出：ydgodot/assets/baked/win_frame.png（frame + 46px 外边距，供 9-slice 用）
   用法：node ydgodot/tools/pixeldiff/bake_win_frame.cjs
*/
const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");

const ROOT = path.resolve(__dirname, "../../..");
const EDGE = "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe";
const FILE = pathToFileURL(path.join(ROOT, "index.html")).href;
const OUT = path.resolve(__dirname, "../../assets/baked/win_frame.png");
const PORT = 9915;
const PROFILE = path.join(require("os").tmpdir(), "tec-bake-profile-" + Date.now());
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 窗体几何（与 data 无关，取自 #case-win 的 CSS 计算值）
const WIN = { x: 100, y: 66, w: 1164, h: 718 }; // 绝对坐标
const HEADER_H = 52;                            // #case-win 的 top/left 是相对 #desktop 的
const MARGIN = 46; // 圆角 13 + 投影 22/2*? → 46 足够装下 7,9,22 与 -5,-5,12 两层
const VW = 1400, VH = 900;

async function capturePage(edge, bg) {
  const wsUrl = await (async () => {
    for (let i = 0; i < 120; i++) {
      try {
        const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
        const p = list.find((t) => t.type === "page");
        if (p && p.webSocketDebuggerUrl) return p.webSocketDebuggerUrl;
      } catch (_) {}
      await sleep(150);
    }
    throw new Error("no devtools target");
  })();
  const ws = new WebSocket(wsUrl);
  let id = 0; const pend = new Map();
  const send = (m, p = {}) => new Promise((res, rej) => {
    const mid = ++id; pend.set(mid, { res, rej });
    ws.send(JSON.stringify({ id: mid, method: m, params: p }));
  });
  ws.addEventListener("message", (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pend.has(msg.id)) {
      const p = pend.get(msg.id); pend.delete(msg.id);
      msg.error ? p.rej(new Error(JSON.stringify(msg.error))) : p.res(msg.result);
    }
  });
  await new Promise((r) => ws.addEventListener("open", r));
  const ev = async (ex) => {
    const r = await send("Runtime.evaluate", { expression: ex, returnByValue: true, awaitPromise: true });
    if (r.exceptionDetails) throw new Error(JSON.stringify(r.exceptionDetails));
    return r.result.value;
  };

  await send("Page.enable"); await send("Runtime.enable");
  await send("Emulation.setDeviceMetricsOverride", { width: VW, height: VH, deviceScaleFactor: 1, mobile: false });
  await send("Page.navigate", { url: FILE });
  await sleep(1800);
  await ev("document.fonts.ready.then(() => true)");
  await ev(`(() => { window.__intro.name('陈调整'); window.__intro.begin();
    window.__intro.answer(0); window.__intro.answer(0); window.__intro.answer(1);
    window.__intro.confirm(); window.__intro.finish(); return true; })()`);
  await sleep(700);
  // 冻结动画 + 只留案件窗的外框：隐藏页眉 / 图标 / 窗内一切 / 其它浮窗，桌面底色换纯色
  await ev(`(() => {
    const add = (css) => { const s = document.createElement('style'); s.textContent = css; document.head.appendChild(s); };
    add('*,*::before,*::after{animation:none!important;transition:none!important}');
    add('#desktop{background:${bg}!important;background-image:none!important}');
    add('body{background:${bg}!important}');
    add('header,#icons,.desk-icon{visibility:hidden!important}');
    add('#case-win{left:${WIN.x}px!important;top:${WIN.y - HEADER_H}px!important;right:auto!important;bottom:auto!important;' +
        'width:${WIN.w}px!important;height:${WIN.h}px!important}');
    add('#case-win > *{visibility:hidden!important}');
    for (const sel of ['#tec-wrap','#toast','.tec-win','.bag-win','.goto-win','.clue-win','.infer-win','#tec-chip','#case-dock']) {
      document.querySelectorAll(sel).forEach(el => el.style.setProperty('visibility','hidden','important'));
    }
    return true;
  })()`);
  await sleep(300);
  const shot = await send("Page.captureScreenshot", { format: "png", fromSurface: true, captureBeyondViewport: false });
  const buf = Buffer.from(shot.data, "base64");
  ws.close();
  return buf;
}

(async () => {
  const edge = spawn(EDGE, ["--headless=new", `--remote-debugging-port=${PORT}`,
    `--user-data-dir=${PROFILE}`, `--window-size=${VW},${VH}`, "--hide-scrollbars",
    "--no-first-run", "--no-default-browser-check", "--force-device-scale-factor=1",
    "about:blank"], { stdio: "ignore" });
  try {
    const white = await capturePage(edge, "#ffffff");
    const black = await capturePage(edge, "#000000");
    fs.mkdirSync(path.dirname(OUT), { recursive: true });
    fs.writeFileSync(path.join(path.dirname(OUT), "_win_white.png"), white);
    fs.writeFileSync(path.join(path.dirname(OUT), "_win_black.png"), black);
    console.log("已存两张底片：_win_white.png / _win_black.png");
    console.log("下一步：python ydgodot/tools/pixeldiff/solve_alpha.py");
  } finally {
    edge.kill();
  }
})().catch((e) => { console.error("ERR", e.message || e); process.exit(1); });
