#!/usr/bin/env node
// -*- coding: utf-8 -*-
/* build.js —— 把 src/ 与 data/ 拼装成成品（Node，零第三方依赖）
 *
 *   node build.js          写出 index.html、_template.html、tecnode-standalone.html，
 *                          以及 src/editor/ 在盘上时的 editor.html（见下方「editor 是可选项」）
 *   node build.js --check  只在内存构建，与盘上现存的产物比对；
 *                          不一致说明「源码改了但没重新构建」（或产物被手改过），非零退出
 *
 * 拼装规则（勿改，改了就不是逐字节等价）：
 *   - 每个切片文件【不含结尾换行】，这里用 "\r\n" 连接
 *   - gamedata 用 JSON.stringify(JSON.parse(raw)) 注入，保证产物里它是一整行
 *   - _template.html 的 gamedata 位写占位符 __GAME_DATA_A001__
 *   - editor.html 与 index.html 同规则构建（壳在 src/editor/shell.html，
 *     CSS = src/css/01-font.css + 02-base.css + src/editor/*.css，JS = src/editor/*.js），
 *     gamedata 同样包在 <script type="application/json" id="gamedata"> 里，--check 的归一化直接适用
 *   - **editor 是可选项**：src/editor/shell.html 不在盘上时跳过 editor 目标（另一台机器
 *     没提交编辑器源码的常见情形），index/_template/standalone 照常构建。判据只认「壳在不在」：
 *     壳在就照常拼、照常报错（缺切片 / 命名不规范都是真 bug，不能一起吞掉）。
 *
 * 素材双模式（@@ASSET:<文件名>@@）：
 *   图片/字体/音频等二进制素材放 src/assets/，源码里只写占位符（占位符本身就代表一个
 *   「完整可用的 src」），例如
 *       const TEC_AVATAR = "@@ASSET:tec-avatar.png@@";
 *       src:url(@@ASSET:font.ttf@@) format("truetype");
 *       { id: "Air_Bach", src: "@@ASSET:Air_Bach.ogg@@" }
 *   external 模式（index.html / _template.html）：占位符 → assets/<文件名>，
 *     成品走外链 —— HTML 轻、浏览器按文件缓存、音频可流式可拖进度。构建时把
 *     src/assets/* 复制到根目录 assets/（已在 .gitignore，属构建产物）。
 *   inline 模式（tecnode-standalone.html / editor.html）：占位符 → data:<mime>;base64,<正文>，
 *     单文件自包含，双击即玩、离线分发。mime 由扩展名推导（MIME 表）。
 */
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = __dirname;
const NL = "\r\n";
const PLACEHOLDERS = ["@@CSS@@", "@@GAMEDATA@@", "@@JS@@"];
const DATA_PLACEHOLDER = "__GAME_DATA_A001__";
const ASSET_DIR = path.join("src", "assets");
const ASSET_OUT_DIR = "assets";
const INDEX_FILE = "index.html";
const TPL_FILE = "_template.html";
const STANDALONE_FILE = "tecnode-standalone.html";
const EDITOR_FILE = "editor.html";

/* 内联模式的 data: 前缀需要显式 mime，按扩展名推导；没登记的扩展名直接报错 */
const MIME = {
  ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif",
  ".svg": "image/svg+xml", ".webp": "image/webp",
  ".ttf": "font/ttf", ".otf": "font/otf", ".woff": "font/woff", ".woff2": "font/woff2",
  ".ogg": "audio/ogg", ".oga": "audio/ogg", ".mp3": "audio/mpeg", ".wav": "audio/wav",
  ".m4a": "audio/mp4", ".flac": "audio/flac"
};

/* 把 @@ASSET:<filename>@@ 换成完整可用的 src：
 *   external → assets/<filename>        inline → data:<mime>;base64,<正文> */
function resolveAssets(text, where, mode) {
  let hits = 0;
  const out = text.replace(/@@ASSET:([^@]+)@@/g, (m, name) => {
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name)) {
      throw new Error(where + " 里的素材名不合法：@@ASSET:" + name + "@@（只允许字母数字与 . _ -）");
    }
    const p = path.join(ROOT, ASSET_DIR, name);
    if (!fs.existsSync(p)) throw new Error(where + " 引用了不存在的素材：" + ASSET_DIR + "/" + name);
    hits++;
    if (mode === "external") return ASSET_OUT_DIR + "/" + name;
    const mime = MIME[path.extname(name).toLowerCase()];
    if (!mime) {
      throw new Error(where + " 的素材 " + name + " 扩展名没有登记 mime（内联模式需要），" +
                      "请把它加进 build.js 顶部的 MIME 表");
    }
    return "data:" + mime + ";base64," + fs.readFileSync(p).toString("base64");
  });
  /* base64 字母表不含 @，所以替换后不该再有残留 */
  const left = out.match(/@@ASSET:/g);
  if (left) throw new Error(where + " 里还有 " + left.length + " 个 @@ASSET: 未被替换（命名是否多写了 @ ？）");
  if (hits) console.log("  素材 " + hits + " 处 ← " + ASSET_DIR + "/（" + mode + "）");
  return out;
}

function readSlices(dir, ext) {
  const files = fs.readdirSync(dir).filter((f) => f.endsWith(ext)).sort();
  if (!files.length) throw new Error(dir + " 里没有 " + ext + " 文件");
  files.forEach((f) => {
    if (!/^\d\d-/.test(f)) throw new Error(dir + "/" + f + " 不以「NN-」前缀开头，排序不可靠");
  });
  return files.map((f) => ({ name: f, text: fs.readFileSync(path.join(dir, f), "utf8") }));
}

/* 通用拼装：一个壳 + 一组 CSS 切片 + 一组 JS 切片 → inject(dataText)。
   index/_template/standalone 与 editor 共用这一条路径，保证切片拼接规则
   （"\r\n" 连接、素材解析、函数式替换防 $& 误伤）只有一份实现。 */
function assembleTarget(shellLabel, shellFile, css, js, cssWhere, jsWhere, mode) {
  const shell = fs.readFileSync(shellFile, "utf8");
  for (const ph of PLACEHOLDERS) {
    const n = shell.split(ph).length - 1;
    if (n !== 1) throw new Error(shellLabel + " 里占位符 " + ph + " 出现 " + n + " 次（应为 1 次）");
  }

  const cssText = resolveAssets(css.map((f) => f.text).join(NL), cssWhere, mode);
  const jsText = resolveAssets(js.map((f) => f.text).join(NL), jsWhere, mode);

  /* 用函数式替换：避免 CSS/JS 里的 $& / $1 被当成替换语法 */
  const inject = (dataText) =>
    shell.replace("@@CSS@@", () => cssText)
         .replace("@@GAMEDATA@@", () => dataText)
         .replace("@@JS@@", () => jsText);

  const srcCssBytes = css.reduce((n, f) => n + Buffer.byteLength(f.text, "utf8"), 0);
  const srcJsBytes = js.reduce((n, f) => n + Buffer.byteLength(f.text, "utf8"), 0);

  return {
    inject,
    stats: {
      cssFiles: css.length, jsFiles: js.length,
      srcCssBytes, srcJsBytes,
      cssBytes: Buffer.byteLength(cssText, "utf8"),
      jsBytes: Buffer.byteLength(jsText, "utf8"),
    },
  };
}

/* 编辑器只共享游戏的前两片 CSS（字体 + 主题变量 / header / 按钮），
   桌面、节点、浮窗那些游戏专用切片不进编辑器 */
function readSharedBaseCss() {
  return ["01-font.css", "02-base.css"].map((f) => ({
    name: "src/css/" + f,
    text: fs.readFileSync(path.join(ROOT, "src", "css", f), "utf8"),
  }));
}

function assemble() {
  const rawData = fs.readFileSync(path.join(ROOT, "data", "case-a001.json"), "utf8");
  const compactData = JSON.stringify(JSON.parse(rawData));   /* 单行注入 */

  const gameCss = readSlices(path.join(ROOT, "src", "css"), ".css");
  const gameJs = readSlices(path.join(ROOT, "src", "js"), ".js");

  /* index / _template 走外链（轻、可缓存、音频可流式）；
     standalone 单文件全内联（双击即玩、离线分发）。同一份源码两种产物。 */
  const gameExt = assembleTarget(
    "src/shell.html", path.join(ROOT, "src", "shell.html"),
    gameCss, gameJs,
    "src/css/", "src/js/", "external");
  const gameInl = assembleTarget(
    "src/shell.html", path.join(ROOT, "src", "shell.html"),
    gameCss, gameJs,
    "src/css/", "src/js/", "inline");

  /* 这台机器有没有编辑器源码。只认「壳」：壳不在就是没有，跳过；
     壳在但里面缺东西，交给 assembleTarget / readSlices 照常抛错。 */
  const hasEditor = fs.existsSync(path.join(ROOT, "src", "editor", "shell.html"));

  const editor = hasEditor ? assembleTarget(
    "src/editor/shell.html", path.join(ROOT, "src", "editor", "shell.html"),
    readSharedBaseCss().concat(readSlices(path.join(ROOT, "src", "editor"), ".css")),
    readSlices(path.join(ROOT, "src", "editor"), ".js"),
    "src/css/ + src/editor/", "src/editor/", "inline") : null;

  return {
    index: gameExt.inject(compactData),
    template: gameExt.inject(DATA_PLACEHOLDER),
    standalone: gameInl.inject(compactData),
    editor: hasEditor ? editor.inject(compactData) : null,
    hasEditor: hasEditor,
    stats: Object.assign({ dataBytes: Buffer.byteLength(compactData, "utf8") }, gameExt.stats),
    statsInl: gameInl.stats,
    editorStats: hasEditor ? editor.stats : null,
  };
}

/* 外链产物引用 assets/<name>：构建时把 src/assets/* 复制到根目录 assets/
   （.gitignore 里只忽略根目录的 /assets/，源素材 src/assets/ 照常入库） */
function copyAssets() {
  const src = path.join(ROOT, "src", "assets");
  if (!fs.existsSync(src)) return;
  const dst = path.join(ROOT, ASSET_OUT_DIR);
  fs.mkdirSync(dst, { recursive: true });
  let n = 0;
  for (const f of fs.readdirSync(src).sort()) {
    const p = path.join(src, f);
    if (!fs.statSync(p).isFile()) continue;
    fs.copyFileSync(p, path.join(dst, f));
    n++;
  }
  console.log("  外链素材目录 " + ASSET_OUT_DIR + "/ 同步 " + n + " 个文件 ← " + ASSET_DIR + "/");
}

function write(file, text) {
  fs.writeFileSync(path.join(ROOT, file), text, "utf8");
  const lines = text.split(NL).length - 1;
  console.log("  写出 " + file.padEnd(16) + String(lines).padStart(5) + " 行  " +
              Buffer.byteLength(text, "utf8").toLocaleString().padStart(10) + " 字节");
}

/* gamedata 段归一化：比对时把两边的数据都换成占位符 */
function normalizeData(s) {
  return s.replace(/(<script type="application\/json" id="gamedata">)[\s\S]*?(<\/script>)/,
    (m, a, b) => a + "@@DATA@@" + b);
}

function firstDiffLine(a, b) {
  const A = a.split(NL), B = b.split(NL);
  const n = Math.max(A.length, B.length);
  for (let i = 0; i < n; i++) {
    if (A[i] !== B[i]) {
      return { line: i + 1, ref: A[i] === undefined ? "<无此行>" : A[i], got: B[i] === undefined ? "<无此行>" : B[i] };
    }
  }
  return null;
}

/* ------------------------------- 主流程 ------------------------------- */
const CHECK = process.argv.includes("--check");
const built = assemble();

/* 源码体积 → 内联素材后的体积，一样时只报一个数 */
function sizeCell(srcBytes, builtBytes) {
  const a = srcBytes.toLocaleString();
  return srcBytes === builtBytes ? a : a + " → " + builtBytes.toLocaleString();
}

console.log("切片统计： css " + built.stats.cssFiles + " 片 " + sizeCell(built.stats.srcCssBytes, built.stats.cssBytes) +
            " 字节   js " + built.stats.jsFiles + " 片 " + sizeCell(built.stats.srcJsBytes, built.stats.jsBytes) +
            " 字节（external，index/_template 用）");
console.log("       　 css " + built.statsInl.cssFiles + " 片 " + sizeCell(built.statsInl.srcCssBytes, built.statsInl.cssBytes) +
            " 字节   js " + built.statsInl.jsFiles + " 片 " + sizeCell(built.statsInl.srcJsBytes, built.statsInl.jsBytes) +
            " 字节（inline，standalone 用）");
if (built.editorStats) {
  console.log("编辑器　： css " + built.editorStats.cssFiles + " 片 " + sizeCell(built.editorStats.srcCssBytes, built.editorStats.cssBytes) +
              " 字节   js " + built.editorStats.jsFiles + " 片 " + sizeCell(built.editorStats.srcJsBytes, built.editorStats.jsBytes) + " 字节");
} else {
  console.log("编辑器　： 跳过 —— 盘上没有 src/editor/shell.html（这台机器没有编辑器源码）。" +
              "index / _template / standalone 与 assets/ 照常构建。");
}
console.log("");

if (CHECK) {
  /* 与盘上现存的产物比对（gamedata 行归一化）。
     两者一致 = 源码与产物同步；不一致 = 忘了 node build.js，或产物被手工改过。 */
  let bad = 0;
  const pairs = [
    [INDEX_FILE, built.index, "index"],
    [TPL_FILE, built.template, "template"],
    [STANDALONE_FILE, built.standalone, "standalone"],
  ];
  if (built.hasEditor) pairs.push([EDITOR_FILE, built.editor, "editor"]);
  for (const [file, text, label] of pairs) {
    const p = path.join(ROOT, file);
    if (!fs.existsSync(p)) {
      console.error("✗ 盘上没有 " + file + "（" + label + " 尚未构建）");
      bad++; continue;
    }
    const d = firstDiffLine(normalizeData(fs.readFileSync(p, "utf8")), normalizeData(text));
    if (d) {
      console.error("✗ " + file + " 与源码构建结果不一致，首个差异在第 " + d.line + " 行：");
      console.error("  盘上: " + JSON.stringify(d.ref.slice(0, 200)));
      console.error("  构建: " + JSON.stringify(d.got.slice(0, 200)));
      bad++; continue;
    }
    console.log("✓ " + file + " 与源码构建结果逐字节一致（gamedata 行归一化后，共 " +
                (text.split(NL).length - 1) + " 行）");
  }
  if (!built.hasEditor) {
    /* 说清楚，免得有人以为 editor.html 也被校验过了 */
    console.log("· 编辑器　： 跳过（src/editor/ 缺失，editor.html 不参与比对" +
                (fs.existsSync(path.join(ROOT, EDITOR_FILE)) ? "；盘上那份是旧的、无法重新生成" : "") + "）");
  }
  if (bad) { console.error("\n=> 产物已过期，请运行：node build.js"); process.exit(1); }
  console.log("\n=> 源码与产物同步，无需重新构建");
  process.exit(0);
}

console.log("写出成品：");
copyAssets();
write(INDEX_FILE, built.index);
write(TPL_FILE, built.template);
write(STANDALONE_FILE, built.standalone);
if (built.editor) write(EDITOR_FILE, built.editor);
else console.log("  跳过 editor.html（src/editor/ 缺失）");
console.log("");
console.log("提示：改功能编辑 src/js/*，改样式编辑 src/css/*，改数据编辑 data/case-a001.json（或用 editor.html 编辑后导出覆盖），" +
            "换图片/字体/音频放 src/assets/*（源码里用 @@ASSET:<文件名>@@ 引用，index 走外链 assets/、standalone 走内联），" +
            (built.hasEditor ? "编辑器源码在 src/editor/*，" : "") +
            "然后 node build.js && node verify.js");
