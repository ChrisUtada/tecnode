class_name Investigator
extends RefCounted

const PATH := "user://tec_investigator.json"
const AVATAR_DEFAULT_ID := "CHARS_EXEC"
const AVATAR_INITIAL: Array[String] = ["CHARS_EXEC", "CHARS_TEC"]
const SENSE_ORDER: Array[String] = ["vision", "hearing", "touch", "smell", "taste"]
const SENSE_NAMES := {
	"vision": "视觉",
	"hearing": "听觉",
	"touch": "触觉",
	"smell": "嗅觉",
	"taste": "味觉",
}
const SENSE_FLAVOR := {
	"vision": "你习惯先看清，再行动。",
	"hearing": "世界的背面，总有声音先抵达你。",
	"touch": "你相信手的判断，胜过眼睛。",
	"smell": "气味是不会说谎的证人。",
	"taste": "真相的味道，你尝一口就知道。",
}
const QUIZ := [
	{
		"q": "进入一片漆黑的异动区域，你首先依靠什么？",
		"opts": [
			["vision", "眯起眼睛寻找微光"],
			["hearing", "屏息聆听最细微的声响"],
			["touch", "伸出手触摸前方的空气"],
			["smell", "分辨空气中气味的变化"],
			["taste", "舌尖抵住上颚，尝一尝空气的味道"],
		],
	},
	{
		"q": "一份被水浸透的档案，你最先注意到什么？",
		"opts": [
			["vision", "字迹晕染开的形状"],
			["hearing", "纸页翻动时的脆响"],
			["touch", "纸张潮湿的重量"],
			["smell", "霉菌与墨水的气味"],
			["taste", "墨水淡淡的苦涩（别想歪，是用鼻子旁边的那点想象力）"],
		],
	},
	{
		"q": "以下哪种异常最让你不安？",
		"opts": [
			["vision", "镜子里慢半拍的自己"],
			["hearing", "反复倒放的人声"],
			["touch", "没有来源的冰冷触碰"],
			["smell", "凭空出现的花香"],
			["taste", "嘴里突然泛起的铁锈味"],
		],
	},
]


static func load_from(p_path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(p_path):
		return {}
	var f := FileAccess.open(p_path, FileAccess.READ)
	if f == null:
		return {}
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed
	var name := String(d.get("name", "")).strip_edges()
	var id := String(d.get("id", "")).strip_edges()
	if name == "" or id == "":
		return {}
	var date := String(d.get("date", ""))
	if date == "":
		date = Time.get_date_string_from_system()
	var avatar := String(d.get("avatarId", d.get("avatar_id", AVATAR_DEFAULT_ID)))
	if avatar == "":
		avatar = AVATAR_DEFAULT_ID
	var out := {"name": name, "id": id, "date": date, "avatarId": avatar}
	## C4：新证件不写 sense；旧 IntroWin 档案里若还有，只在读取时原样保留，不补默认值。
	if d.has("sense"):
		var sense := String(d.get("sense", ""))
		if SENSE_NAMES.has(sense):
			out["sense"] = sense
	return out


static func save_to(p_card: Dictionary, p_path: String = PATH) -> bool:
	if p_card.is_empty():
		return false
	var f := FileAccess.open(p_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(p_card, "\t"))
	f.close()
	return true


static func clear(p_path: String = PATH) -> void:
	if FileAccess.file_exists(p_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p_path))


static func pick_sense(p_answers: Array) -> String:
	var counts := {}
	var best := ""
	var best_n := 0
	for raw in p_answers:
		var sense := String(raw)
		counts[sense] = int(counts.get(sense, 0)) + 1
		if int(counts[sense]) > best_n:
			best_n = int(counts[sense])
			best = sense
	return best if best != "" else SENSE_ORDER[0]


static func gen_id(p_rng: RandomNumberGenerator = null) -> String:
	var rng := p_rng
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var code := "TEC-"
	code += letters[rng.randi_range(0, letters.length() - 1)]
	code += letters[rng.randi_range(0, letters.length() - 1)]
	code += "-%04d" % rng.randi_range(0, 9999)
	return code


static func make_card(p_name: String, p_answers: Array, p_avatar_id: String = AVATAR_DEFAULT_ID,
		p_date: String = "", p_rng: RandomNumberGenerator = null) -> Dictionary:
	var date := p_date
	if date == "":
		date = Time.get_date_string_from_system()
	var avatar := p_avatar_id
	if avatar == "":
		avatar = AVATAR_DEFAULT_ID
	return {
		"name": p_name.strip_edges(),
		"id": gen_id(p_rng),
		"sense": pick_sense(p_answers),
		"date": date,
		"avatarId": avatar,
	}
