extends SceneTree
## 怪物（is_monster）の入団時・ピークの能力を並べる（docs/AUTORUN.md 作業85。表示だけ。ヘッドレスで数十秒）。
## 区分（高校・大学・社会人・独立）× 投手・野手ごとに何人かを作って、全員の平均と、1人ずつの入団時・ピークの全部の能力を出す。
##
##   godot --headless --path godot -s res://tests/monster_dump.gd -- [年数] [種の数] [1人ずつ出す人数]

const BAT_KEYS := ["meet", "power", "eye", "speed", "defense", "arm"]
const PIT_KEYS := ["k9", "bb9", "hr9", "stamina"]

var _years := 60
var _seeds := 3
var _show := 12


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_years = int(args[0])
	if args.size() > 1:
		_seeds = int(args[1])
	if args.size() > 2:
		_show = int(args[2])
	_run.call_deferred()


func _run() -> void:
	var fd_script: GDScript = load("res://sim/fictional_draft.gd")
	var mons: Array = []
	for s in _seeds:
		var fd: RefCounted = fd_script.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 8500 + s
		for y in range(2028, 2028 + _years):
			for p: Dictionary in fd.generate_year(y, rng):
				if bool(p.get("is_monster", false)):
					if bool(p["is_pitcher"]):
						PitchArsenal.ensure(p, y + 1)  # ゲームと同じ（GameData.set_draft_class）：持ち球に合わせて k9・hr9 が書き戻る
					mons.append(p)
	print("== 怪物 %d人（%d年 × %d通り） ==" % [mons.size(), _years, _seeds])
	for label: String in ["高校投", "高校野", "高校", "大学以外投", "大学以外野", "大学以外"]:
		var rows: Array = mons.filter(func(p: Dictionary) -> bool: return _in(p, label))
		_print_group(label, rows)
	# 1人ずつ：高校・それ以外 × 投手・野手がまんべんなく出るように順に拾う
	var shown := 0
	var want := ["高校投", "高校野", "大学以外投", "大学以外野"]
	var i := 0
	var guard := 0
	while shown < _show and guard < 1000:
		guard += 1
		var w: String = want[i % want.size()]
		i += 1
		var pick: Dictionary = {}
		for p: Dictionary in mons:
			if _in(p, w) and not p.has("_shown"):
				pick = p
				break
		if pick.is_empty():
			continue
		pick["_shown"] = true
		_print_one(pick)
		shown += 1
	quit(0)


func _in(p: Dictionary, label: String) -> bool:
	var hs := str(p["category"]) == "高校"
	var pit := bool(p["is_pitcher"])
	if label == "高校":
		return hs
	if label == "大学以外":
		return not hs
	if label.begins_with("高校"):
		return hs and pit == label.ends_with("投")
	return (not hs) and pit == label.ends_with("投")


func _keys(p: Dictionary) -> Array:
	return PIT_KEYS if bool(p["is_pitcher"]) else BAT_KEYS


func _vals(p: Dictionary) -> Array:
	var out: Array = []
	var r: Dictionary = p["pitching"]["ratings"] if bool(p["is_pitcher"]) else p["batting"]["ratings"]
	for k: String in _keys(p):
		out.append(float(r[k]["value"]))
	return out


func _peak_vals(p: Dictionary) -> Array:
	var out: Array = []
	for k: String in _keys(p):
		out.append(float(p["growth"]["peak"].get(k, 0.0)))
	return out


func _print_group(label: String, rows: Array) -> void:
	if rows.is_empty():
		print("%-10s（なし）" % label)
		return
	var n := float(rows.size())
	var e_top := 0.0
	var e_2 := 0.0
	var e_3 := 0.0
	var e_min := 0.0
	var e_s := 0.0
	var e_a := 0.0
	var e_d := 0
	var p_top := 0.0
	var p_s := 0.0
	var lv := 0.0
	var kmh := 0.0
	var kn := 0
	var kmin := 999
	var kmax := 0
	for p: Dictionary in rows:
		var v := _vals(p)
		var vs := v.duplicate()
		if bool(p["is_pitcher"]):
			vs = v.slice(0, 3)  # 奪三振・制球・被弾抑制（スタミナは別）
		vs.sort()
		vs.reverse()
		e_top += vs[0]
		e_2 += vs[1]
		e_3 += vs[2]
		e_min += v.min()
		for x: float in v:
			e_s += 1.0 if x >= 90.0 else 0.0
			e_a += 1.0 if x >= 80.0 else 0.0
		e_d += 1 if v.min() < 60.0 else 0
		var pv := _peak_vals(p)
		p_top += pv.max()
		for x: float in pv:
			p_s += 1.0 if x >= 90.0 else 0.0
		lv += FictionalDraft.entry_level(p)
		if bool(p["is_pitcher"]):
			var k := int(p["pitching"]["velocity"]["kmh"])
			kmh += k
			kn += 1
			kmin = mini(kmin, k)
			kmax = maxi(kmax, k)
	var extra := ""
	if kn > 0:
		extra = "　球速 平均%.1f（%d〜%d）" % [kmh / kn, kmin, kmax]
	print("%-10s %3d人　入団時：1番目 %.1f・2番目 %.1f・3番目 %.1f・最低 %.1f・A以上 %.2f個・S %.2f個・C未満を持つ人 %.0f%%・総合 %.1f ／ ピーク：最高 %.1f・S %.2f個%s" % [
		label, rows.size(), e_top / n, e_2 / n, e_3 / n, e_min / n, e_a / n, e_s / n, 100.0 * e_d / n, lv / n,
		p_top / n, p_s / n, extra])


func _print_one(p: Dictionary) -> void:
	var r: Dictionary = p["pitching"]["ratings"] if bool(p["is_pitcher"]) else p["batting"]["ratings"]
	var parts: Array = []
	for k: String in _keys(p):
		parts.append("%s %d(%s)→%.0f" % [k, int(r[k]["value"]), str(r[k]["rank"]), float(p["growth"]["peak"].get(k, 0.0))])
	var arsenal := ""
	if bool(p["is_pitcher"]):
		var ps: Array = []
		for x: Dictionary in p["pitching"].get("pitches", []):
			ps.append("%s%d" % [x["name"], int(x["move"])])
		arsenal = "　持ち球 " + "・".join(ps)
	var line := "%s %s %s（%s）総合%.0f　%s" % [p["category"], "投手" if bool(p["is_pitcher"]) else "野手", p["primary_pos"],
		str(p["amateur"].get("type", "")), FictionalDraft.entry_level(p), "　".join(parts)]
	if bool(p["is_pitcher"]):
		line += "　球速 %d→%.0f" % [int(p["pitching"]["velocity"]["kmh"]), float(p["growth"]["peak"].get("velocity", 0.0))]
		line += arsenal
	print(line)
