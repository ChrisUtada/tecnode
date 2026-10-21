const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");

const ROOT = path.resolve(__dirname, "../../..");
const EDGE = "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe";
const FILE = pathToFileURL(path.join(ROOT, "index.html")).href;
const OUT = path.resolve(__dirname, "../../docs/p3/web");
const PORT = 9913;
const PROFILE = path.join(require("os").tmpdir(), "tec-pixeldiff-profile-" + Date.now());
const W = 1280;
const H = 720;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const CASES = {
  start: {
    setup: "",
  },
  garden: {
    setup: `
      window.__reveal('SCENES_garden');
      window.__closeFloats();
    `,
  },
  paper: {
    setup: `
      window.__closeFloats();
      for (const sel of ['#nodes', '#edges', '#glow']) {
        const el = document.querySelector(sel);
        if (el) el.style.visibility = 'hidden';
      }
    `,
  },
};

function args() {
  const out = { only: "" };
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--only") out.only = argv[++i] || "";
    if (argv[i] === "--out") out.out = path.resolve(argv[++i]);
  }
  return out;
}

async function getWsUrl() {
  for (let i = 0; i < 100; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${PORT}/json/list`);
      const list = await r.json();
      const page = list.find((t) => t.type === "page");
      if (page && page.webSocketDebuggerUrl) return page.webSocketDebuggerUrl;
    } catch (_) {}
    await sleep(150);
  }
  throw new Error("DevTools target not found on port " + PORT);
}

(async () => {
  const opts = args();
  const outDir = opts.out || OUT;
  fs.mkdirSync(outDir, { recursive: true });

  // 关掉 LCD 次像素渲染：默认抓出来的文字带红/蓝彩边（Chromium 的 subpixel AA），
  // 而 Godot 只有灰度抗锯齿 —— 不关的话对拍会把「渲染器差异」当成「实现差异」，
  // 页眉 / 标题栏 / 卡片文字全被这几万像素的彩边淹没。同时钉住 sRGB，
  // 免得不同机器的色彩配置让底色漂 1~2 个色阶。
  const edge = spawn(EDGE, [
    "--headless=new",
    `--remote-debugging-port=${PORT}`,
    `--user-data-dir=${PROFILE}`,
    `--window-size=${W},${H}`,
    "--hide-scrollbars",
    "--no-first-run",
    "--no-default-browser-check",
    "--force-device-scale-factor=1",
    "--disable-lcd-text",
    "--disable-font-subpixel-positioning",
    "--font-render-hinting=full",
    "--force-color-profile=srgb",
    "about:blank",
  ], { stdio: "ignore" });

  const ws = new WebSocket(await getWsUrl());
  let id = 0;
  const pending = new Map();
  const send = (method, params = {}) => new Promise((res, rej) => {
    const mid = ++id;
    pending.set(mid, { res, rej });
    ws.send(JSON.stringify({ id: mid, method, params }));
  });
  ws.addEventListener("message", (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      const p = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.error) p.rej(new Error(JSON.stringify(msg.error)));
      else p.res(msg.result);
    }
  });
  await new Promise((res, rej) => {
    ws.addEventListener("open", res);
    ws.addEventListener("error", rej);
  });

  const evaluate = async (expression) => {
    const r = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
    if (r.exceptionDetails) throw new Error(JSON.stringify(r.exceptionDetails));
    return r.result.value;
  };
  const shot = async (name) => {
    const r = await send("Page.captureScreenshot", {
      format: "png",
      fromSurface: true,
      captureBeyondViewport: false,
    });
    const file = path.join(outDir, name + ".png");
    fs.writeFileSync(file, Buffer.from(r.data, "base64"));
    return file;
  };

  try {
    await send("Page.enable");
    await send("Runtime.enable");
    await send("Emulation.setDeviceMetricsOverride", {
      width: W,
      height: H,
      deviceScaleFactor: 1,
      mobile: false,
    });
    await send("Page.navigate", { url: FILE });
    await sleep(1800);
    await evaluate("document.fonts.ready.then(() => true)");

    await evaluate(`(() => {
      window.__intro.name('陈调整');
      window.__intro.begin();
      window.__intro.answer(0);
      window.__intro.answer(0);
      window.__intro.answer(1);
      window.__intro.confirm();
      window.__intro.finish();
      return true;
    })()`);
    await sleep(350);

    const names = Object.keys(CASES).filter((n) => !opts.only || n === opts.only);
    const manifest = { viewport: [W, H], cases: [] };

    for (const name of names) {
      await evaluate(`(() => {
        document.getElementById('btn-reset').click();
        if (window.__intro && window.__intro.step() !== null) window.__intro.finish();
        window.__closeFloats();
        return true;
      })()`);
      await sleep(900);
      await evaluate(`(() => {
        ${CASES[name].setup}
        window.__closeFloats();
        const t = document.getElementById('toast');
        if (t) t.style.display = 'none';
        return true;
      })()`);
      await sleep(900);
      await evaluate(`(() => {
        const t = document.getElementById('toast');
        if (t) t.style.display = 'none';
        const s = document.createElement('style');
        s.id = '__pixeldiff_freeze';
        s.textContent = '*,*::before,*::after{animation-play-state:paused!important;transition:none!important;caret-color:transparent!important}';
        document.head.appendChild(s);
        return true;
      })()`);
      await sleep(120);
      const viewport = await evaluate("JSON.stringify({w:innerWidth,h:innerHeight,dpr:devicePixelRatio,scrollX,scrollY})");
      const state = await evaluate("JSON.stringify(window.__dump())");
      const rects = await evaluate(`(() => {
        const out = {};
        for (const [name, sel] of [['header', 'header'], ['desktop', '#desktop'], ['case', '#case-win'],
          ['bar', '#case-win .syswin-bar'], ['stage', '#stage'], ['icons', '#icons']]) {
          const el = document.querySelector(sel);
          if (!el) continue;
          const r = el.getBoundingClientRect();
          out[name] = [r.x, r.y, r.width, r.height];
        }
        return JSON.stringify(out);
      })()`);
      const file = await shot(name);
      manifest.cases.push({
        name,
        file,
        viewport: JSON.parse(viewport),
        state: JSON.parse(state),
        rects: JSON.parse(rects),
      });
      await evaluate("document.getElementById('__pixeldiff_freeze')?.remove()");
      console.log("saved", file);
    }

    fs.writeFileSync(path.join(outDir, "manifest.json"), JSON.stringify(manifest, null, 2));
    console.log("saved", path.join(outDir, "manifest.json"));
  } finally {
    ws.close();
    edge.kill();
  }
})().catch((e) => {
  console.error("ERR", e.message || e);
  process.exit(1);
});
