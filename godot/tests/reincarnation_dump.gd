extends SceneTree
## 転生選手の入団時・ピークの能力を数える（docs/AUTORUN.md 作業84。表示だけ。ヘッドレスで数秒）。
## 全員（legends）を1人ずつ何回か作って、入団時の能力の分布（B以上・A以上・S以上の数、いちばん高い能力）、ピークの分布、
## 投手の球速・持ち球・決め球を出す。あと、野手・投手それぞれ評価の高い順の上位・中位・下位の何人かは、入団時とピークの全部の能力も並べる。
##
##   godot --headless --path godot -s res://tests/reincarnation_dump.gd -- [1人あたりの回数] [並べる選手のID,…]
## 大物＝全盛期に 90 以上の能力が2つ以上ある名選手、中堅＝全盛期の最高が 80〜89 の名選手（90 以上は1つまで）として、それぞれの平均も出す

const BAT_KEYS := ["meet", "power", "eye", "speed", "defense", "arm"]
const PIT_KEYS := ["overall", "stamina", "k9", "bb9", "hr9"]

var _times := 10
var _ids: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_times = int(args[0])
	if args.size() > 1:
		_ids = str(args[1]).split(",")
	_run.call_deferred()


func _run() -> void:
	var fd: RefCounted = (load("res://sim/fictional_draft.gd") as GDScript).new()
	var legends: Array = fd.data.get("legends", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = 8400
	var acc := {"B": _new_acc(), "P": _new_acc(), "大物": _new_acc(), "中堅": _new_acc()}
	var strong_hits := 0
	var strong_total := 0
	var named: Array = []
	var shown := {}
	for id: String in _ids:
		shown[id] = true
	if shown.is_empty():
		shown = _pick_shown(legends)
	for l: Dictionary in legends:
		for i in _times:
			var p: Dictionary = fd.make_reincarnation(l, 2030, rng)
			var side: String = l["side"]
			var keys: Array = BAT_KEYS if side == "B" else PIT_KEYS
			var entry: Dictionary = p["batting"]["ratings"] if side == "B" else p["pitching"]["ratings"]
			var peak: Dictionary = p["growth"]["peak"]
			var ent_vals: Array = []
			var peak_vals: Array = []
			for k: String in keys:
				if k == "overall":
					continue
				ent_vals.append(int(entry[k]["value"]))
				peak_vals.append(float(peak.get(k, 50.0)))
			_add(acc[side], ent_vals, peak_vals, p)
			var n90 := 0
			var top := 0.0
			for k: String in keys:
				if k == "overall":
					continue
				var ov := float(l["peak"].get(k, 0.0))
				n90 += 1 if ov >= 90.0 else 0
				top = maxf(top, ov)
			if n90 >= 2:
				_add(acc["大物"], ent_vals, peak_vals, p)
			elif top >= 80.0:
				_add(acc["中堅"], ent_vals, peak_vals, p)
			# 元の選手が S（90）以上の能力：全盛期のピークが S に届くか・入団時にいくつ B 以上か
			for k: String in keys:
				if k == "overall" or float(l["peak"].get(k, 0)) < 90.0:
					continue
				strong_total += 1
				if float(peak.get(k, 0)) >= 90.0:
					strong_hits += 1
			if i == 0 and shown.has(str(l["id"])):
				named.append([l, p])
	print("== 転生選手 %d人 × %d回 ==" % [legends.size(), _times])
	for side: String in ["B", "P", "大物", "中堅"]:
		_print({"B": "野手", "P": "投手"}.get(side, side), acc[side])
	print("元の選手が S（90以上）の能力がピークでも S に届く割合：%d / %d（%.0f%%）" % [strong_hits, strong_total,
		100.0 * strong_hits / maxi(strong_total, 1)])
	for pair: Array in named:
		_print_one(pair[0], pair[1])
	quit(0)


## 野手・投手それぞれ、評価（score）の高い順で 上位3人・中位2人・下位1人
func _pick_shown(legends: Array) -> Dictionary:
	var out := {}
	for side: String in ["B", "P"]:
		var xs: Array = legends.filter(func(l: Dictionary) -> bool: return l["side"] == side)
		xs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
		if xs.size() < 8:
			continue
		for i: int in [0, 1, 2, xs.size() / 2, xs.size() / 2 + 1, xs.size() - 1]:
			out[str(xs[i]["id"])] = true
	return out


func _new_acc() -> Dictionary:
	return {"n": 0, "eb": 0, "ea": 0, "es": 0, "etop": 0.0, "pb": 0, "pa": 0, "ps": 0, "ptop": 0.0, "kmh": 0.0, "none": 0,
		"elv": 0.0, "k150": 0, "max_move": 0.0, "pn": 0}


func _add(a: Dictionary, ent: Array, peak: Array, p: Dictionary) -> void:
	a["n"] += 1
	var nb := 0
	for v: int in ent:
		nb += 1 if v >= 70 else 0
		a["ea"] += 1 if v >= 80 else 0
		a["es"] += 1 if v >= 90 else 0
	a["eb"] += nb
	a["none"] += 1 if nb == 0 else 0
	a["etop"] += float(ent.max())
	for v: float in peak:
		a["pb"] += 1 if v >= 70.0 else 0
		a["pa"] += 1 if v >= 80.0 else 0
		a["ps"] += 1 if v >= 90.0 else 0
	a["ptop"] += float(peak.max())
	a["elv"] += FictionalDraft.entry_level(p)
	if bool(p["is_pitcher"]):
		a["pn"] += 1
		a["kmh"] += float(p["pitching"]["velocity"]["kmh"])
		a["k150"] += 1 if int(p["pitching"]["velocity"]["kmh"]) >= 150 else 0
		PitchArsenal.ensure(p, 2031)
		var mx := 0
		for x: Dictionary in p["pitching"].get("pitches", []):
			mx = maxi(mx, int(x["move"]))
		a["max_move"] += float(mx)


func _print(label: String, a: Dictionary) -> void:
	var n := float(a["n"])
	var extra := ""
	if int(a["pn"]) > 0:
		extra = "　球速 %.1f（150km+ %.0f%%）・決め球の変化量 %.2f" % [a["kmh"] / a["pn"], 100.0 * a["k150"] / a["pn"], a["max_move"] / a["pn"]]
	print("%s：入団時 B+ %.2f・A+ %.2f・S %.2f・B+なし %.0f%%・最高 %.1f・総合 %.1f ／ ピーク B+ %.2f・A+ %.2f・S %.2f・最高 %.1f%s" % [
		label, a["eb"] / n, a["ea"] / n, a["es"] / n, 100.0 * a["none"] / n, a["etop"] / n, a["elv"] / n,
		a["pb"] / n, a["pa"] / n, a["ps"] / n, a["ptop"] / n, extra])


func _print_one(l: Dictionary, p: Dictionary) -> void:
	var side: String = l["side"]
	var keys: Array = BAT_KEYS if side == "B" else PIT_KEYS
	var entry: Dictionary = p["batting"]["ratings"] if side == "B" else p["pitching"]["ratings"]
	var line := "%s %s（%s・元 %d年）" % [l["id"], l["name"], "野手" if side == "B" else "投手", int(l["peak_year"])]
	var parts: Array = []
	for k: String in keys:
		parts.append("%s 入%d→ピ%.0f（元%.0f）" % [k, int(entry[k]["value"]), float(p["growth"]["peak"].get(k, 0.0)),
			float(l["peak"].get(k, 0.0))])
	line += "　" + "　".join(parts)
	if side == "P":
		line += "　球速 入%d→ピ%.0f（元%.0f）" % [int(p["pitching"]["velocity"]["kmh"]), float(p["growth"]["peak"].get("velocity", 0.0)),
			float(l["peak"].get("velocity", 0.0))]
		PitchArsenal.ensure(p, 2031)
		var ps: Array = []
		for x: Dictionary in p["pitching"].get("pitches", []):
			ps.append("%s%d" % [x["name"], int(x["move"])])
		line += "　持ち球 " + "・".join(ps)
	print(line)
