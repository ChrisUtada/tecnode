extends Node
## 测试 / 截图专用 API 的公共底座。
##
## 只在 OS.is_debug_build() / --shot 下由 Desktop 实例化；产品代码不得依赖它。
## 分层（方法名全部保持 dbg_*，测试仍走 scene.debug.dbg_*）：
##   Base → Query → Action → Windows → Apps → DesktopDebug（截图）
## 中间层不带 class_name，避免污染全局脚本类缓存。

var desk: Desktop

func dbg_undo() -> bool:
	return desk.session._undo()


func dbg_history_size() -> int:
	return desk._save.history.size() if desk._save != null else 0


func dbg_last_rebuild_stats() -> Dictionary:
	return desk.canvas._last_rebuild_stats.duplicate(true)


## 批次 5：清空所有逐帧待办，供测试断言空闲态（不写盘）。
func dbg_settle_idle() -> void:
	desk._autosave_pending = false
	desk.canvas._cancel_layout_job()
	desk.canvas._follow_frames = 0
	desk._edges_dirty = false
	desk._panning = false
	desk._sdrag_key = ""
	if desk.narrative != null:
		desk.narrative._mem_anchor_key = ""


func dbg_is_processing() -> bool:
	return desk.is_processing()


func dbg_wake() -> void:
	desk._wake_process()
