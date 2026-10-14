#!/usr/bin/env node
// -*- coding: utf-8 -*-
/* build.js —— 把 src/ 与 data/ 拼装成单文件成品（Node，零第三方依赖）
 *
 *   node build.js          写出 index.html 与 _template.html
 *   node build.js --check  只在内存构建，与盘上现存的 index.html / _template.html 比对；
 *                          不一致说明「源码改了但没重新构建」（或产物被手改过），非零退出
 *
 * 拼装规则（勿改，改了就不是逐字节等价）：
 *   - 每个切片文件【不含结尾换行】，这里用 "\r\n" 连接
 *   - gamedata 用 JSON.stringify(JSON.parse(raw)) 注入，保证产物里它是一整行
 *   - _template.html 的 gamedata 位写占位符 __GAME_DATA_A001__
 */
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = __dirname;
const NL = "\r\n";
const PLACEHOLDERS = ["@@CSS@@", "@@GAMEDATA@@", "@@JS@@"];
const DATA_PLACEHOLDER = "__GAME_DATA_A001__";
const INDEX_FILE = "index.html";
const TPL_FILE = "_template.html";

function readSlices(dir, ext) {
  const files = fs.readdirSync(dir).filter((f) => f.endsWith(ext)).sort();
  if (!files.length) throw new Error(dir + " 里没有 " + ext + " 文件");
  files.forEach((f) => {
    if (!/^\d\d-/.test(f)) throw new Error(dir + "/" + f + " 不以「NN-」前缀开头，排序不可靠");
  });
  return files.map((f) => ({ name: f, text: fs.readFileSync(path.join(dir, f), "utf8") }));
}

function assemble() {
  const shell = fs.readFileSync(path.join(ROOT, "src", "shell.html"), "utf8");
  const css = readSlices(path.join(ROOT, "src", "css"), ".css");
  const js = readSlices(path.join(ROOT, "src", "js"), ".js");

  const rawData = fs.readFileSync(path.join(ROOT, "data", "case-a001.json"), "utf8");
  const compactData = JSON.stringify(JSON.parse(rawData));   /* 单行注入 */

  for (const ph of PLACEHOLDERS) {
    const n = shell.split(ph).length - 1;
    if (n !== 1) throw new Error("src/shell.html 里占位符 " + ph + " 出现 " + n + " 次（应为 1 次）");
  }

  const cssText = css.map((f) => f.text).join(NL);
  const jsText = js.map((f) => f.text).join(NL);

  /* 用函数式替换：避免 CSS/JS 里的 $& / $1 被当成替换语法 */
  const inject = (dataText) =>
    shell.replace("@@CSS@@", () => cssText)
         .replace("@@GAMEDATA@@", () => dataText)
         .replace("@@JS@@", () => jsText);

  return {
    index: inject(compactData),
    template: inject(DATA_PLACEHOLDER),
    stats: {
      cssFiles: css.length, jsFiles: js.length,
      cssBytes: Buffer.byteLength(cssText, "utf8"),
      jsBytes: Buffer.byteLength(jsText, "utf8"),
      dataBytes: Buffer.byteLength(compactData, "utf8"),
    },
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

console.log("切片统计： css " + built.stats.cssFiles + " 片 / " + built.stats.cssBytes.toLocaleString() +
            " 字节   js " + built.stats.jsFiles + " 片 / " + built.stats.jsBytes.toLocaleString() +
            " 字节   data " + built.stats.dataBytes.toLocaleString() + " 字节");
console.log("");

if (CHECK) {
  /* 与盘上现存的产物比对（gamedata 行归一化）。
     两者一致 = 源码与产物同步；不一致 = 忘了 node build.js，或产物被手工改过。 */
  let bad = 0;
  const pairs = [[INDEX_FILE, built.index, "index"], [TPL_FILE, built.template, "template"]];
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
console.log("");
console.log("提示：改功能编辑 src/js/*，改样式编辑 src/css/*，改数据编辑 data/case-a001.json，" +
            "然后 node build.js && node verify.js");
