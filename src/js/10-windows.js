/* ============ 统一系统窗口：标题栏（拖动把手）+ × 关闭 + 内容区 ============ */
function makeWindow(titleText, onClose, onMin){
  const el = document.createElement("div");
  el.className = "syswin";
  const bar = document.createElement("div");
  bar.className = "syswin-bar";
  const rule1 = document.createElement("span");
  rule1.className = "syswin-rule";
  const title = document.createElement("span");
  title.className = "syswin-title";
  title.textContent = titleText;
  const rule2 = document.createElement("span");
  rule2.className = "syswin-rule";
  const x = document.createElement("span");
  x.className = "syswin-x";
  x.textContent = "×";
  x.title = "关闭";
  x.addEventListener("pointerdown", e => { if (e) e.stopPropagation(); });
  x.addEventListener("click", e => { if (e) e.stopPropagation(); onClose(); });
  bar.appendChild(rule1); bar.appendChild(title); bar.appendChild(rule2);
  /* 最小化键（可选）：只有传了 onMin 的窗口才有（如 TEC 对话窗），位置排在 × 左边 */
  if (onMin){
    const mn = document.createElement("span");
    mn.className = "syswin-min";
    mn.textContent = "–";
    mn.title = "最小化";
    mn.addEventListener("pointerdown", e => { if (e) e.stopPropagation(); });
    mn.addEventListener("click", e => { if (e) e.stopPropagation(); onMin(); });
    bar.appendChild(mn);
  }
  bar.appendChild(x);
  const body = document.createElement("div");
  body.className = "syswin-body";
  el.appendChild(bar); el.appendChild(body);
  return { el, bar, body };
}

/* ============ 浮层通用拖动（元素自身 pointer 捕获模式，可指定把手） ============ */
function makeFloatDraggable(el, inWorld, handle){
  const h = handle || el;
  let dragging = false, moved = false, sx = 0, sy = 0, ox = 0, oy = 0;
  h.addEventListener("pointerdown", e => {
    if (e.button !== 0) return;
    /* 「本次手势拖过没」在这里就复位 —— **必须在下面那张排除表之前**：从被排除的子元素
       （TEC 头像 / 清单项 / × 关窗键）上起手时，下面会提前 return，若复位写在后面，_dragged
       会一直留着上一次拖窗口的 true，那些元素自己的"点击"就被误吞了（真机才有；DOM stub 的
       closest() 恒返回 null，排除表在 stub 里等于不存在，所以这条测不出来）。 */
    el._dragged = false;
    /* 交互子元素（按钮/输入框/清单项/× 关窗键/阵列执行者与线索 chip/花园叙事框）不启动拖动——否则
       setPointerCapture 会把 pointerup 与 click 一起重定向到窗口自身，行内可点的东西永远收不到 click。
       新增可点清单项时记得往这里加。花园叙事框是「整框点一下 = 看下一段」，必须在此列（真机才暴露：
       合成 click 直接投递给元素，绕过了这层重定向，探针会假通过）。 */
    if (e.target && e.target.closest && e.target.closest("button,input,.bag-item,.map-card,.goto-item,.syswin-x,.syswin-min,.tec-avatar,.mx-exec,.mx-chip,.music-row,.gd-narr")) return;
    /* CSS 定位的浮窗（right/bottom/margin 居中），首次拖动时换算成 left/top，并清掉 margin 防止跳位 */
    if (el.style.left === "" || el.style.left == null){
      const r = el.getBoundingClientRect(), sr = desktopEl.getBoundingClientRect();
      el.style.left = (r.left - sr.left) + "px"; el.style.top = (r.top - sr.top) + "px";
      el.style.right = "auto"; el.style.bottom = "auto"; el.style.margin = "0";
    }
    dragging = true; moved = false; sx = e.clientX; sy = e.clientY;
    /* _dragged（本次手势拖过没）已在函数开头复位：点击推进靠它区分「点一下」和「按住挪一下」（阈值 5px） */
    ox = parseFloat(el.style.left) || 0; oy = parseFloat(el.style.top) || 0;
    try { el.setPointerCapture(e.pointerId); } catch(_){}
    e.stopPropagation();
  });
  h.addEventListener("pointermove", e => {
    if (!dragging) return;
    const k = inWorld ? view.k : 1;
    if (!moved && Math.abs(e.clientX - sx) + Math.abs(e.clientY - sy) < 5) return;
    moved = true; el._dragged = true;
    /* 弹窗的 pop 缩放动画未结束时拖动会让光标对不上，开始拖动即定格到最终形态 */
    if (el.style.animation !== "none") el.style.animation = "none";
    el.style.left = (ox + (e.clientX - sx) / k) + "px";
    el.style.top  = (oy + (e.clientY - sy) / k) + "px";
  });
  h.addEventListener("pointerup", () => { dragging = false; });
}
