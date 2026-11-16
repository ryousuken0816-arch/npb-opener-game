extends SceneTree
## 架空のドラフト候補の入団時の能力と伸びしろ（ピーク − 入団時）を数える（docs/AUTORUN.md 作業83③。表示だけ。ヘッドレスで数十秒）。
## 評価（S〜D）× 区分（高校・大学・社会人/独立）ごとに：B（70）以上・A（80）以上の数、長所（いちばん高い能力）の平均、
## ほかの能力（いちばん高いもの以外）の平均と D 未満（50未満）の割合、ピークまでの伸び（主な能力の平均・いちばん伸びる能力）、
## 伸びが 3 未満しかない人の割合。怪物・転生は除く。野手は6つ、投手は奪三振・制球・被弾抑制・スタミナ（＋総合）
##
##   godot --headless --path godot -s res://tests/entry_growth_dump.gd -- [年数] [種の数]

const BAT_KEYS := ["meet", "power", "eye", "speed", "defense", "arm"]
const PIT_KEYS := ["k9", "bb9", "hr9", "stamina"]

var _years := 30
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
	var examples := {}
	for s in _seeds:
		var fd: RefCounted = fd_script.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 8300 + s
		for y in range(2028, 2028 + _years):
			for p: Dictionary in fd.generate_year(y, rng):
				var am: Dictionary = p["amateur"]
				if bool(am.get("reincarnation", false)) or str(p.get("id", "")).begins_with("rei:") or bool(p.get("is_monster", false)):
					continue
				var g := str(am.get("grade", "?"))
				var cat := str(am.get("category", "?"))
				cat = "社会人・独立" if cat in ["社会人", "独立"] else cat
				var side := "投" if bool(p["is_pitcher"]) else "野"
				for key: String in [g, g + side, g + cat]:
					_add(by, key, p)
				var ek := g + side + cat
				if not examples.has(ek):
					examples[ek] = _example(p)
	print("== 架空のドラフト候補の入団時と伸びしろ（%d年 × %d通り。怪物・転生を除く） ==" % [_years, _seeds])
	print("区分: 人数 | B以上 | A以上 | いちばん高い能力 | ほかの平均 | ほかがD未満 | 主な能力の伸び | いちばん伸びる | 伸び3未満の人 | 投手の総合 入団→ピーク")
	for g: String in ["S", "A", "B", "C", "D"]:
		for suf: String in ["", "野", "投", "高校", "大学", "専門", "社会人・独立"]:
			if by.has(g + suf):
				_print_row(g + suf, by[g + suf])
	print("\n-- 例（入団時 → ピーク） --")
	var ks: Array = examples.keys()
	ks.sort()
	for k: String in ks:
		print("%s：%s" % [k, examples[k]])
	quit(0)


func _vals(p: Dictionary) -> Array:
	var pit := bool(p["is_pitcher"])
	var r: Dictionary = p["pitching" if pit else "batting"]["ratings"]
	var peak: Dictionary = p.get("growth", {}).get("peak", {})
	var out: Array = []
	for k: String in (PIT_KEYS if pit else BAT_KEYS):
		if r.get(k) is Dictionary:
			var v := float(r[k]["value"])
			out.append([k, v, float(peak.get(k, v))])
	return out


func _add(by: Dictionary, key: String, p: Dictionary) -> void:
	if not by.has(key):
		by[key] = {"n": 0, "b": 0, "a": 0, "top": 0.0, "rest": 0.0, "rest_n": 0, "rest_low": 0, "gain": 0.0, "gain_n": 0,
			"gain_top": 0.0, "flat": 0, "ov": 0.0, "ovp": 0.0, "ov_n": 0}
	var d: Dictionary = by[key]
	var vals := _vals(p)
	if vals.is_empty():
		return
	vals.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	d["n"] += 1
	d["top"] += float(vals[0][1])
	var gtop := 0.0
	var gsum := 0.0
	for i in vals.size():
		var v := float(vals[i][1])
		d["b"] += 1 if v >= 70.0 else 0
		d["a"] += 1 if v >= 80.0 else 0
		if i > 0 and vals[i][0] != "stamina":
			d["rest"] += v
			d["rest_n"] += 1
			d["rest_low"] += 1 if v < 50.0 else 0
		var gain := float(vals[i][2]) - v
		gtop = maxf(gtop, gain)
		gsum += gain
	d["gain"] += gsum / vals.size()
	d["gain_n"] += 1
	d["gain_top"] += gtop
	d["flat"] += 1 if gtop < 3.0 else 0
	if bool(p["is_pitcher"]):
		var r: Dictionary = p["pitching"]["ratings"]
		var pk: Dictionary = p.get("growth", {}).get("peak", {})
		if r.get("overall") is Dictionary:
			d["ov"] += float(r["overall"]["value"])
			d["ovp"] += float(pk.get("overall", r["overall"]["value"]))
			d["ov_n"] += 1


func _print_row(key: String, d: Dictionary) -> void:
	var n := maxf(1, d["n"])
	var ov := "-"
	if int(d["ov_n"]) > 0:
		ov = "%.1f→%.1f" % [d["ov"] / d["ov_n"], d["ovp"] / d["ov_n"]]
	print("%s: %d | %.2f | %.2f | %.1f | %.1f | %.0f%% | %.1f | %.1f | %.0f%% | %s" % [key, d["n"], d["b"] / n, d["a"] / n,
		d["top"] / n, d["rest"] / maxf(1, d["rest_n"]), 100.0 * d["rest_low"] / maxf(1, d["rest_n"]),
		d["gain"] / maxf(1, d["gain_n"]), d["gain_top"] / maxf(1, d["gain_n"]), 100.0 * d["flat"] / n, ov])


func _example(p: Dictionary) -> String:
	var parts: Array = []
	for x: Array in _vals(p):
		parts.append("%s %d→%d" % [x[0], int(x[1]), int(x[2])])
	return "%s（%s・%s）%s" % [p["name"], p["amateur"].get("category", ""), p["amateur"].get("type_key", ""), "・".join(parts)]
