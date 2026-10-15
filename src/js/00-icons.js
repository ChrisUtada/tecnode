/* 00-icons.js —— Pixelarticons 像素图标（MIT License, pixelarticons.com / npm pixelarticons），内联 SVG。
   拍板记录：桌面九宫格 + 播放器图标与控制键统一换用本库（用户定稿方案 A「像素图形 + 圆角底盒」）。
   要点：
   - fill="currentColor" ⇒ 跟随所在元素的 CSS color，桌面的「按下变黑」、按钮 hover 反色自动生效；
   - 图形本体是 24×24 纯像素网格（无抗锯齿），与 12px 像素字完全同族；底盒 / 窗口仍是圆角；
   - 换图 / 加图：往 ICON_PATHS 塞一段 <path d>（从 npm pixelarticons 的 svg 里抄，多条 path 直接拼接）；
   - shell.html 里的静态图标用 data-icon 占位，底部 hydrateIcons() 一次性注入。 */
const ICON_PATHS = {
  music: "M4 12h4v2H4zm-2 2h2v4H2zm2 4h4v2H4zM8 6h2v12H8zm10 0h2v12h-2zm-6 8h2v4h-2zm2-2h4v2h-4zm0 6h4v2h-4zM10 4h8v2h-8z",
  play: "M15 11h-2V9h2zm0 4h-2v-2h2zm-2 2h-2v-2h2zm0-8h-2V7h2zm-2-2H9V5h2zM9 21H7V3h2zm6-8h2v-2h-2zm-6 4h2v2H9z",
  pause: "M10 20H4V4h6v16Zm8-16v16h-6V4h6Zm-4 2v12h2V6h-2ZM6 18h2V6H6v12Z",
  stop: "M20 20H4V4H20V20ZM6 18H18V6H6V18ZM14 14H10V10H14V14Z",
  star: "M5 20H8V22H3V16H5V20ZM21 22H16V20H19V16H21V22ZM10 20H8V18H10V20ZM16 20H14V18H16V20ZM14 18H10V16H14V18ZM7 16H5V13H7V16ZM19 16H17V13H19V16ZM5 13H3V11H5V13ZM21 13H19V11H21V13ZM9 9H3V11H1V7H9V9ZM23 11H21V9H15V7H23V11ZM11 7H9V3H11V7ZM15 7H13V3H15V7ZM13 3H11V1H13V3Z",
  archive: "M3 2h18v2H3zm0 5h18v2H3zM1 4h2v3H1zm20 0h2v3h-2zm-2 5h2v11h-2zM3 9h2v11H3zm2 11h14v2H5zm4-9h6v2H9z",
  notebook: "M6 2h14v2H6zm0 18h14v2H6zM20 4h2v16h-2zM4 4h2v16H4zM2 7h6v2H2zm0 4h6v2H2zm0 4h6v2H2zM16 4h2v16h-2z",
  users: "M5 2h6v2H5zm10 0h4v2h-4zM5 10h6v2H5zm10 0h4v2h-4zm4-6h2v6h-2zm-8 0h2v6h-2zM3 4h2v6H3zM0 18h2v4H0zm14 0h2v4h-2zm8 0h2v4h-2zM4 14h8v2H4zm12 0h4v2h-4zM2 16h2v2H2zm10 0h2v2h-2zm8 0h2v2h-2z",
  briefcase: "M2 8h2v12H2zm18 0h2v12h-2zM4 6h16v2H4zm0 14h16v2H4zM8 4h2v2H8zm2-2h4v2h-4zm4 2h2v2h-2z",
  /* TEC：robot-face（两条 path 直接拼接），机器人的方头 + 天线 + 双目 + 格栅嘴 */
  "robot-face": "M4 6h16v2H4zm0 14h16v2H4zM2 8h2v12H2zm18 0h2v12h-2zM11 4h2v4h-2zm-3 6h2v2H8zm6 0h4v2h-4zm-1-8h4v2h-4zM0 12h2v2H0zm22 0h2v2h-2zm-12 4h4v2h-4zm-2-2h2v2H8zm6 0h2v2h-2z",
  "clipboard-list": "M20 12h2v8h-2zm-8-2h8v2h-8zm0 10h8v2h-8zm-2-8h2v8h-2zM6 2h8v2H6zm0 4h8v2H6zm0-2h2v2H6zm6 0h2v2h-2zm2 0h2v2h-2zM16 6h2v5h-2zM4 4h2v2H4zM2 6h2v12H2zm2 12h6v2H4zm2-8h4v2H6zm0 4h2v2H6zm11 2h5v2h-5zM16 16h2v6h-2z",
  map: "M4 20h2v2H2V6h2v14Zm12 0h2v2h-4v-2h-2v-2h2V8h-2V6h4v14Zm-8 0H6v-2h2v2Zm12 0h-2v-2h2v2ZM10 4h2v2h-2v10h2v2H8V4H6V2h4v2Zm12 14h-2V4h-2V2h4v16ZM6 6H4V4h2v2Zm12 0h-2V4h2v2Z",
  /* 花园：leaf（Pixelarticons 原生，叶身斜切 + 叶柄 + 叶脉锯齿）。
     原先自绘的四瓣花与邻座风格不统一（4px 实心块 vs 2px 条带，且四瓣与
     花芯紧挨会融成一团），改用本库自带的植物类字形 —— 全表回到同一网格。 */
  leaf: "M1 18h2v4H1zm2-2h2v2H3zm2-2h6v2H5zm6-2h2v2h-2zm-6 6h4v2H5zm4 2h4v2H9zm4-2h4v2h-4zm4-2h2v2h-2zm2-8h2v8h-2zm0-4h2v4h-2zm-2-2h2v2h-2zm-4 2h4v2h-4zM7 6h6v2H7zM5 8h2v2H5zm-2 2h2v4H3z"
};
function iconSvg(name, size){
  const paths = ICON_PATHS[name];
  if (!paths) return "";
  return '<svg width="' + size + '" height="' + size + '" viewBox="0 0 24 24" fill="currentColor"' +
         ' shape-rendering="crispEdges" aria-hidden="true"><path d="' + paths + '"/></svg>';
}
/* shell.html 里的静态图标占位（<span data-icon="name" data-icon-size="24"></span>）：
   本切片按文件名排序最先拼入，且脚本在 body 末尾 ⇒ DOM 已就绪，注入一次即可。
   无头 stub 若不支持属性选择器则静默跳过（不影响断言）。 */
(function hydrateIcons(){
  try {
    document.querySelectorAll("[data-icon]").forEach(el => {
      el.innerHTML = iconSvg(el.dataset.icon, el.dataset.iconSize || 22);
    });
  } catch (e) { /* stub 环境无此能力，忽略 */ }
})();
