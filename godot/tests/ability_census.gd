extends SceneTree
## 能力ごとの S（90以上）の人数と160km超えの投手を年ごとに数える（docs/AUTORUN.md 作業80。表示だけ。ヘッドレスで長い：1年1〜2分）。
## START 年に始め、毎年シーズン → オフ（ドラフトはおまかせ）→ 開幕まで進め、開幕の日の所属選手（1軍・2軍・育成）を数える。
## 実在（2027年までの選手・史実の新人）と架空（2028年以降のドラフトの候補 fic:・転生 rei:）、架空の外国人（fgn:）に分ける。
## 架空の選手は最初に見た年（入団した年）の値と、それまでにいちばん高かった値（ピーク）も覚えて最後に出す。
##
##   godot --headless --path godot -s res://tests/ability_census.gd -- [終わりの年] [始めの年]

const USER := "読売ジャイアンツ"
const BAT_KEYS := ["meet", "power", "eye", "speed", "defense", "arm"]
const PIT_KEYS := ["overall", "k9", "bb9", "hr9", "stamina"]
const WORD := {"meet": "ミート", "power": "パワー", "eye": "選球眼", "speed": "走力", "defense": "守備", "arm": "肩",
	"overall": "総合", "k9": "奪三振", "bb9": "制球", "hr9": "球威", "stamina": "スタミナ", "kmh160": "160km+", "kmh155": "155km+"}

var _start := 2026
var _end := 2040
var _gs: Node
var _gd: Node
var _entry := {}  ## 架空の選手 id → {能力 → 入団した年の値}
var _peak := {}  ## 架空の選手 id → {能力 → それまでの最高}
var _entry_year := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_end = int(args[0])
	if args.size() > 1:
		_start = int(args[1])
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	var t0 := Time.get_ticks_msec()
	_gs.new_game(USER, _start)
	_census()
	while _gs.year < _end:
		_gs.skip_to_phase(_gs.Phase.FA_TRADE)
		_gs.fa_resolve()
		_gs.skip_to_phase(_gs.Phase.CAMP)
		_gs.advance()
		_census()
		print("  （%d秒）" % ((Time.get_ticks_msec() - t0) / 1000))
	_summary()
	quit(0)


func _vals(p: Dictionary) -> Dictionary:
	var out := {}
	if bool(p.get("is_pitcher", false)) and p.get("pitching") is Dictionary:
		var r: Dictionary = p["pitching"].get("ratings", {})
		for k: String in PIT_KEYS:
			if r.get(k) is Dictionary and r[k].get("value") != null:
				out[k] = int(r[k]["value"])
		var v: Variant = p["pitching"].get("velocity")
		if v is Dictionary and v.get("kmh") != null:
			out["kmh"] = int(v["kmh"])
	elif p.get("batting") is Dictionary:
		var r: Dictionary = p["batting"].get("ratings", {})
		var f: Dictionary = {}
		if p.get("fielding") is Dictionary:
			f = p["fielding"].get(str(p.get("primary_pos", "")), {})
		for k: String in BAT_KEYS:
			var x: Variant = r.get(k)
			if not x is Dictionary and f.get(k) is Dictionary:
				x = f[k]
			if x is Dictionary and x.get("value") != null:
				out[k] = int(x["value"])
	return out


static func _kind(id: String) -> String:
	if id.begins_with("fic:") or id.begins_with("rei:"):
		return "架空"
	if id.begins_with("fgn:"):
		return "外国"
	return "実在"


func _census() -> void:
	var y: int = _gs.year
	var s := {"実在": {}, "架空": {}, "外国": {}}
	var a := {"実在": 0, "架空": 0, "外国": 0}
	var n := {"実在": 0, "架空": 0, "外国": 0}
	for p: Dictionary in _gd.rostered_players():
		var id := str(p.get("id", ""))
		var kind := _kind(id)
		n[kind] += 1
		var v := _vals(p)
		for k: String in v:
			var x := int(v[k])
			if k == "kmh":
				if x >= 160:
					s[kind]["kmh160"] = int(s[kind].get("kmh160", 0)) + 1
				if x >= 155:
					s[kind]["kmh155"] = int(s[kind].get("kmh155", 0)) + 1
				continue
			if x >= 90:
				s[kind][k] = int(s[kind].get(k, 0)) + 1
			elif x >= 80:
				a[kind] += 1
		if kind == "架空":
			if not _entry.has(id):
				_entry[id] = v.duplicate()
				_peak[id] = v.duplicate()
				_entry_year[id] = y
			else:
				for k: String in v:
					_peak[id][k] = maxi(int(_peak[id].get(k, 0)), int(v[k]))
	var parts: Array = []
	for kind: String in ["実在", "架空", "外国"]:
		parts.append("%s %d人（S %s・A %d）" % [kind, n[kind], _fmt(s[kind]), a[kind]])
	print("%d年 開幕：%s" % [y, "　".join(parts)])


func _fmt(d: Dictionary) -> String:
	if d.is_empty():
		return "0"
	var parts: Array = []
	for k: String in d:
		parts.append("%s %d" % [WORD.get(k, k), d[k]])
	return "・".join(parts)


func _summary() -> void:
	print("\n== 架空の選手（%d人）：入団した年と、それまでのピーク ==" % _entry.size())
	for label: String in ["入団した年", "ピーク"]:
		var src: Dictionary = _entry if label == "入団した年" else _peak
		var s := {}
		var any_s := 0
		var any_a := 0
		for id: String in src:
			var has_s := false
			var has_a := false
			for k: String in src[id]:
				var x := int(src[id][k])
				if k == "kmh":
					if x >= 160:
						s["kmh160"] = int(s.get("kmh160", 0)) + 1
					if x >= 155:
						s["kmh155"] = int(s.get("kmh155", 0)) + 1
					continue
				if x >= 90:
					s[k] = int(s.get(k, 0)) + 1
					has_s = true
				elif x >= 80:
					has_a = true
			any_s += 1 if has_s else 0
			any_a += 1 if has_a or has_s else 0
		print("%s：S を持つ選手 %d人・A 以上を持つ選手 %d人。能力ごとの S：%s" % [label, any_s, any_a, _fmt(s)])
