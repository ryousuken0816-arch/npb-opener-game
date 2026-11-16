extends SceneTree
## 架空のドラフト候補（新人）の持ち球の分布を数える（docs/AUTORUN.md 作業83。表示だけ。ヘッドレスで十数秒）。
## 当時の評価（S〜D・怪物・転生）ごとに、持ち球の数・決め球の変化量の平均・いちばん大きい変化量の分布・持ち球の合計・7を持つ人の数。
## 方針：新人は2〜3球種で決め球 3〜5、7 はまず無い（怪物・転生は例外でよい）
##
##   godot --headless --path godot -s res://tests/arsenal_rookie_dump.gd -- [年数] [種の数]

var _years := 15
var _seeds := 2


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_years = int(args[0])
	if args.size() > 1:
		_seeds = int(args[1])
	_run.call_deferred()


func _run() -> void:
	var fd_script: GDScript = load("res://sim/fictional_draft.gd")
	var by := {}
	for s in _seeds:
		var fd: RefCounted = fd_script.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 8300 + s
		for y in range(2028, 2028 + _years):
			var cls: Array = fd.generate_year(y, rng)
			var pitchers: Array = cls.filter(func(p: Dictionary) -> bool: return bool(p.get("is_pitcher", false)))
			PitchArsenal.ensure_all(pitchers, y + 1)  # GameData.set_draft_class と同じ
			for p: Dictionary in pitchers:
				var am: Dictionary = p["amateur"]
				var g := str(am.get("grade", "?"))
				if bool(am.get("reincarnation", false)) or str(p.get("id", "")).begins_with("rei:"):
					g = "転生"
				elif bool(p.get("is_monster", false)):
					g = "怪物"
				_add(by, g, p)
				_add(by, "全体", p)
	print("== 架空のドラフト候補の投手の持ち球（%d年 × %d通り） ==" % [_years, _seeds])
	print("評価: 人数 | 持ち球の数 | 決め球の平均 | いちばん大きい変化量の分布 | 合計の平均 | 7を持つ人 | 例")
	for g: String in ["怪物", "転生", "S", "A", "B", "C", "D", "全体"]:
		if not by.has(g):
			continue
		var d: Dictionary = by[g]
		var n := int(d["n"])
		print("%s: %d人 | %s | %.2f | %s | %.1f | %d | %s" % [g, n, _hist(d["counts"]), float(d["best"]) / n, _hist(d["max"]),
			float(d["sum"]) / n, int(d["seven"]), "　".join(d["ex"])])
	quit(0)


func _add(by: Dictionary, g: String, p: Dictionary) -> void:
	if not by.has(g):
		by[g] = {"n": 0, "counts": {}, "best": 0.0, "max": {}, "sum": 0.0, "seven": 0, "ex": []}
	var d: Dictionary = by[g]
	var ps: Array = p["pitching"]["pitches"]
	var mx := 0
	var total := 0
	for x: Dictionary in ps:
		mx = maxi(mx, int(x["move"]))
		total += int(x["move"])
	d["n"] = int(d["n"]) + 1
	d["counts"][ps.size()] = int(d["counts"].get(ps.size(), 0)) + 1
	d["max"][mx] = int(d["max"].get(mx, 0)) + 1
	d["best"] = float(d["best"]) + float(PitchArsenal.best_pitch(p).get("move", 0))
	d["sum"] = float(d["sum"]) + total
	d["seven"] = int(d["seven"]) + (1 if mx >= PitchArsenal.MOVE_MAX else 0)
	if d["ex"].size() < 3:
		d["ex"].append("%s %dkm（%s）" % [p["name"], int(p["pitching"].get("velocity", {}).get("kmh", 0)), PitchArsenal.summary(p)])


static func _hist(h: Dictionary) -> String:
	var ks: Array = h.keys()
	ks.sort()
	return " ".join(ks.map(func(k: Variant) -> String: return "%s:%d" % [k, h[k]]))
