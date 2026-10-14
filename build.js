#!/usr/bin/env node
// -*- coding: utf-8 -*-
/* build.js —— 把 src/ 与 data/ 拼装成单文件成品（Node，零第三方依赖）
 *
 *   node build.js          写出 index.html、_template.html 与 editor.html
 *   node build.js --check  只在内存构建，与盘上现存的三个产物比对；
 *                          不一致说明「源码改了但没重新构建」（或产物被手改过），非零退出
 *
 * 拼装规则（勿改，改了就不是逐字节等价）：
 *   - 每个切片文件【不含结尾换行】，这里用 "\r\n" 连接
 *   - gamedata 用 JSON.stringify(JSON.parse(raw)) 注入，保证产物里它是一整行
 *   - _template.html 的 gamedata 位写占位符 __GAME_DATA_A001__
 *   - editor.html 与 index.html 同规则构建（壳在 src/editor/shell.html，
 *     CSS = src/css/01-font.css + 02-base.css + src/editor/*.css，JS = src/editor/*.js），
 *     gamedata 同样包在 <script type="application/json" id="gamedata"> 里，--check 的归一化直接适用
 *
 * 素材内联（@@ASSET:<文件名>@@）：
 *   图片/字体等二进制素材放 src/assets/，源码里只写占位符，
 *   例如  const TEC_AVATAR_B64 = "@@ASSET:tec-avatar.png@@";
 *        src:url(data:font/ttf;base64,@@ASSET:font.ttf@@) format("truetype");
 *   构建时把占位符整体换成该文件的 base64（不带 data: 前缀，mime 由源码自己写）。
 *   这样源码可读、原图可 diff 可替换，而成品仍是单文件。
 */
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = __dirname;
const NL = "\r\n";
const PLACEHOLDERS = ["@@CSS@@", "@@GAMEDATA@@", "@@JS@@"];
const DATA_PLACEHOLDER = "__GAME_DATA_A001__";
const ASSET_DIR = path.join("src", "assets");
const INDEX_FILE = "index.html";
const TPL_FILE = "_template.html";
const EDITOR_FILE = "editor.html";

/* 把 @@ASSET:<filename>@@ 换成 src/assets/<filename> 的 base64（纯 base64，无 data: 前缀） */
function inlineAssets(text, where) {
  let hits = 0;
  const out = text.replace(/@@ASSET:([^@]+)@@/g, (m, name) => {
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name)) {
      throw new Error(where + " 里的素材名不合法：@@ASSET:" + name + "@@（只允许字母数字与 . _ -）");
    }
    const p = path.join(ROOT, ASSET_DIR, name);
    if (!fs.existsSync(p)) throw new Error(where + " 引用了不存在的素材：" + ASSET_DIR + "/" + name);
    hits++;
    return fs.readFileSync(p).toString("base64");
  });
  /* base64 字母表不含 @，所以替换后不该再有残留 */
  const left = out.match(/@@ASSET:/g);
  if (left) throw new Error(where + " 里还有 " + left.length + " 个 @@ASSET: 未被替换（命名是否多写了 @ ？）");
  if (hits) console.log("  内联素材 " + hits + " 处 ← " + ASSET_DIR + "/");
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
   index/_template 与 editor 共用这一条路径，保证切片拼接规则
   （"\r\n" 连接、素材内联、函数式替换防 $& 误伤）只有一份实现。 */
function assembleTarget(shellLabel, shellFile, css, js, cssWhere, jsWhere) {
  const shell = fs.readFileSync(shellFile, "utf8");
  for (const ph of PLACEHOLDERS) {
    const n = shell.split(ph).length - 1;
    if (n !== 1) throw new Error(shellLabel + " 里占位符 " + ph + " 出现 " + n + " 次（应为 1 次）");
  }

  const cssText = inlineAssets(css.map((f) => f.text).join(NL), cssWhere);
  const jsText = inlineAssets(js.map((f) => f.text).join(NL), jsWhere);

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

  const game = assembleTarget(
    "src/shell.html", path.join(ROOT, "src", "shell.html"),
    readSlices(path.join(ROOT, "src", "css"), ".css"),
    readSlices(path.join(ROOT, "src", "js"), ".js"),
    "src/css/", "src/js/");

  const editor = assembleTarget(
    "src/editor/shell.html", path.join(ROOT, "src", "editor", "shell.html"),
    readSharedBaseCss().concat(readSlices(path.join(ROOT, "src", "editor"), ".css")),
    readSlices(path.join(ROOT, "src", "editor"), ".js"),
    "src/css/ + src/editor/", "src/editor/");

  return {
    index: game.inject(compactData),
    template: game.inject(DATA_PLACEHOLDER),
    editor: editor.inject(compactData),
    stats: Object.assign({ dataBytes: Buffer.byteLength(compactData, "utf8") }, game.stats),
    editorStats: editor.stats,
  };
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
            " 字节   data " + built.stats.dataBytes.toLocaleString() + " 字节");
console.log("编辑器　： css " + built.editorStats.cssFiles + " 片 " + sizeCell(built.editorStats.srcCssBytes, built.editorStats.cssBytes) +
            " 字节   js " + built.editorStats.jsFiles + " 片 " + sizeCell(built.editorStats.srcJsBytes, built.editorStats.jsBytes) + " 字节");
console.log("");

if (CHECK) {
  /* 与盘上现存的产物比对（gamedata 行归一化）。
     两者一致 = 源码与产物同步；不一致 = 忘了 node build.js，或产物被手工改过。 */
  let bad = 0;
  const pairs = [[INDEX_FILE, built.index, "index"], [TPL_FILE, built.template, "template"], [EDITOR_FILE, built.editor, "editor"]];
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
  if (bad) { console.error("\n=> 产物已过期，请运行：node build.js"); process.exit(1); }
  console.log("\n=> 源码与产物同步，无需重新构建");
  process.exit(0);
}

console.log("写出成品：");
write("index.html", built.index);
write("_template.html", built.template);
write("editor.html", built.editor);
console.log("");
console.log("提示：改功能编辑 src/js/*，改样式编辑 src/css/*，改数据编辑 data/case-a001.json（或用 editor.html 编辑后导出覆盖），" +
            "换图片/字体放 src/assets/*（源码里用 @@ASSET:<文件名>@@ 引用），编辑器源码在 src/editor/*，" +
            "然后 node build.js && node verify.js");
