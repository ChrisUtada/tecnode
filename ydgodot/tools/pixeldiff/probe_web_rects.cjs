/* 量 Web 侧关键元素的外框，供 Godot 侧按数字复刻（不靠目测）。
   输出：docs/p3/web/rects.json */
const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");

const ROOT = path.resolve(__dirname, "../../..");
const EDGE = "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe";
const FILE = pathToFileURL(path.join(ROOT, "index.html")).href;
const OUT = path.resolve(__dirname, "../../docs/p3/web");
const PORT = 9914;
const PROFILE = path.join(require("os").tmpdir(), "tec-rects-profile-" + Date.now());
const W = 1280, H = 800;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const SEL = {
  header: "header",
  brand: "header .brand",
  brandSmall: "header .brand small",
  chip: "#inv-chip",
  crumbs: "header .crumbs",
  tools: "header .tools",
  tog1: "header .tools .tog:nth-of-type(1)",
  tog2: "header .tools .tog:nth-of-type(2)",
  tog3: "header .tools .tog:nth-of-type(3)",
  togConsume: "#tg-consume",
  togFocus: "#tg-focus",
  togReveal: "#tg-reveal",
  btnFit: "#btn-fit",
  btnUndo: "#btn-undo",
  btnReset: "#btn-reset",
  btnReach: "#btn-reach",
  desktop: "#desktop",
  caseWin: "#case-win",
  caseBar: "#case-win .syswin-bar",
  stage: "#stage",
  // 每个桌面图标（含 glyph / label）
  icons: "#icons > *",
};

(async () => {
  const edge = spawn(EDGE, ["--headless=new", `--remote-debugging-port=${PORT}`,
    `--user-data-dir=${PROFILE}`, `--window-size=${W},${H}`, "--hide-scrollbars",
    "--no-first-run", "--no-default-browser-check", "--force-device-scale-factor=1",
    "about:blank"], { stdio: "ignore" });
  let ws;
  for (let i = 0; i < 100; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
      const p = list.find((t) => t.type === "page");
      if (p && p.webSocketDebuggerUrl) { ws = new WebSocket(p.webSocketDebuggerUrl); break; }
    } catch (_) {}
    await sleep(150);
  }
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
  try {
    await send("Page.enable"); await send("Runtime.enable");
    await send("Emulation.setDeviceMetricsOverride", { width: W, height: H, deviceScaleFactor: 1, mobile: false });
    await send("Page.navigate", { url: FILE });
    await sleep(1800);
    await ev("document.fonts.ready.then(() => true)");
    await ev(`(() => { window.__intro.name('陈调整'); window.__intro.begin();
      window.__intro.answer(0); window.__intro.answer(0); window.__intro.answer(1);
      window.__intro.confirm(); window.__intro.finish(); return true; })()`);
    await sleep(900);
    await ev(`(() => { document.getElementById('toast')?.style.setProperty('display','none'); return true; })()`);

    const out = await ev(`(() => {
      const sel = ${JSON.stringify(SEL)};
      const rect = (el) => { if (!el) return null; const r = el.getBoundingClientRect();
        const cs = getComputedStyle(el);
        return { x:+r.x.toFixed(1), y:+r.y.toFixed(1), w:+r.width.toFixed(1), h:+r.height.toFixed(1),
          font: cs.fontSize + "/" + cs.lineHeight, color: cs.color, bg: cs.backgroundColor,
          border: cs.borderTopWidth + " " + cs.borderTopColor,
          radius: cs.borderTopLeftRadius, pad: cs.padding };
      };
      const res = {};
      for (const [k, s] of Object.entries(sel)) {
        if (k === 'icons') {
          res.icons = [...document.querySelectorAll(s)].map(el => ({
            id: el.id,
            ...rect(el),
            glyph: rect(el.querySelector('.icon-glyph')),
            label: rect(el.querySelector('.icon-label')),
            text: (el.querySelector('.icon-label') || {}).textContent || '',
          }));
        } else {
          res[k] = rect(document.querySelector(s));
        }
      }
      res._headerText = document.querySelector('header') ? document.querySelector('header').innerText : '';
      return res;
    })()`);
    fs.mkdirSync(OUT, { recursive: true });
    fs.writeFileSync(path.join(OUT, "rects.json"), JSON.stringify(out, null, 2));
    console.log(JSON.stringify(out, null, 2));
  } finally { ws.close(); edge.kill(); }
})().catch((e) => { console.error("ERR", e.message || e); process.exit(1); });
