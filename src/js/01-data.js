"use strict";
/* ===== 案件数据（可切换）=====
   每个案件一份与 <script id="gamedata"> 同构的数据对象。applyCaseData() 负责把数据
   装进下面这些模块级绑定，因此它们必须是 let（切换案件时整体替换）。 */
let DATA, SCENES, ITEMS, CHARS, CLUES, START, ENDINGS;
let REUSABLE_TOOLS, LIGHT_SOURCES, SCENE_MEMORY;

function applyCaseData(data){
  DATA   = data || {};
  SCENES = DATA.scenes || {};
  ITEMS  = DATA.items  || {};
  CHARS  = DATA.chars  || {};
  CLUES  = DATA.clues  || {};
  /* 节点版跳过 T.E.C-OS 引导场景（那里教学的是原作命令行玩法），直接进入异动区域现场 */
  START  = SCENES.SCENES_garden ? "SCENES_garden"
         : (DATA.config && DATA.config.startScene) || Object.keys(SCENES)[0];
  ENDINGS = DATA.endings || [];
  const cfg = DATA.config || {};
  /* 合成后视为可重复使用、不消耗的道具。**权威清单写在案件数据里**（config.reusableTools），
     这里是"案件没写"时的兜底；两处保持一致。
     唱针（ITEMS_cz）不在其中：它装上唱机就被"用掉"（见唱机「装上唱针」命令的 installs）。 */
  REUSABLE_TOOLS = cfg.reusableTools || ["ITEM_shoudiantong", "ITEMS_htys", "ITEMS_changji"];
  /* 可以点亮的光源：双击执行命令后切换发光状态（光晕跟随节点） */
  LIGHT_SOURCES  = cfg.lightSources  || ["ITEM_taideng"];
  /* 日期闪回场景：首次展开时放 MEMORY 放映卡 */
  SCENE_MEMORY   = cfg.memoryScenes  || ["SCENES_0602", "SCENES_0704"];
}
applyCaseData(JSON.parse(document.getElementById("gamedata").textContent));
/* 五感槽位名 */
const SENSES = {vision:"视觉", hearing:"听觉", touch:"触觉", smell:"嗅觉", taste:"味觉"};

const stage = document.getElementById("stage");
/* 桌面层：外壳（图标 / 各类应用窗口 / 浮窗）都挂这里；画布仍以 #stage 为视口基准 */
const desktopEl = document.getElementById("desktop");
const world = document.getElementById("world");
const svg   = document.getElementById("edges");
const nodeLayer = document.getElementById("nodes");
const detailBody = document.getElementById("detail-body");
const logBox = document.getElementById("log");
const crumbs = document.getElementById("crumbs");
const verdict = document.getElementById("verdict");
const toastEl = document.getElementById("toast");
const btnUndo = document.getElementById("btn-undo");
const tgConsume = document.getElementById("tg-consume");
const tgFocus = document.getElementById("tg-focus");
const tgReveal = document.getElementById("tg-reveal");
