extends SceneTree
## 架空のドラフト候補の入団時の能力の分布を数える（docs/AUTORUN.md 作業80。表示だけ。ヘッドレスで数十秒）。
## 当時の評価（S〜D・怪物）ごと・順位の帯（1位・2-3位・4-5位・6位以下・育成）ごとに、B（70）以上・A（80）以上・S（90）以上の
## 能力が1人あたり何個あるか、いちばん高い能力の平均、B 以上が1つも無い割合を出す。怪物の出る年の割合・1年あたりの人数も。
## 野手はミート・パワー・選球眼・走力・守備・肩、投手は奪三振・制球・球威・スタミナ（球速は別に150km以上・155km以上の割合）
##
##   godot --headless --path godot -s res://tests/draft_spread_dump.gd -- [年数] [種の数]

const BAT_KEYS := ["meet", "power", "eye", "speed", "defense", "arm"]
const PIT_KEYS := ["k9", "bb9", "hr9", "stamina"]

var _years := 40
var _seeds := 3


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_years = int(args[0])
	if args.size() > 1:
		_seeds = int(args[1])
	_run.call_deferred()


func _run() -> void:
	var fd_script: GDScript = load("res://sim/fictional_draft.gd")
	var by_grade := {}
	var by_band := {}
	var mon_years := 0
	var mon_total := 0
	var classes := 0
	var mon_tops: Array = []
	var mon_bids: Array = []
	for s in _seeds:
		var fd: RefCounted = fd_script.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 8000 + s
		for y in range(2028, 2028 + _years):
			var cls: Array = fd.generate_year(y, rng)
			classes += 1
			var mons := 0
			for p: Dictionary in cls:
				var am: Dictionary = p["amateur"]
				if bool(am.get("reincarnation", false)) or str(p.get("id", "")).begins_with("rei:"):
					continue
				var monster := bool(p.get("is_monster", false))
				var g := "怪物" if monster else str(am.get("grade", "?"))
				if monster:
					mons += 1
					mon_bids.append(int(am.get("bids", 1)))
				var band := str(am.get("band", "?"))
				var vals := _values(p)
				_add(by_grade, g + ("投" if bool(p["is_pitcher"]) else "野"), vals, p)
				_add(by_grade, g, vals, p)
				_add(by_band, band, vals, p)
				if monster:
					mon_tops.append(vals.max() if not vals.is_empty() else 0)
			if mons > 0:
				mon_years += 1
			mon_total += mons
	print("== 架空のドラフト候補（%d年 × %d通り＝%d年分） ==" % [_years, _seeds, classes])
	print("怪物：1人以上いる年 %.0f%%・1年あたり %.2f人。武器（いちばん高い能力）の平均 %.1f（%s）・競合の見込み平均 %.1f球団" % [
		100.0 * mon_years / classes, float(mon_total) / classes, _mean(mon_tops), _hist(mon_tops), _mean(mon_bids)])
	print("\n-- 当時の評価ごと（人数/年・B以上の数・A以上の数・S以上の数・B以上なしの割合・いちばん高い能力の平均・入団時の総合の平均・球速150km以上/155km以上） --")
	for g: String in ["怪物", "S", "A", "B", "C", "D", "怪物野", "S野", "A野", "B野", "C野", "D野", "怪物投", "S投", "A投", "B投", "C投", "D投"]:
		_print_row(g, by_grade.get(g, {}), classes)
	print("\n-- 順位の帯ごと --")
	for b: String in ["1", "2-3", "4-5", "6-", "育成"]:
		_print_row(b, by_band.get(b, {}), classes)
	quit(0)


func _values(p: Dictionary) -> Array:
	var out: Array = []
	if bool(p["is_pitcher"]):
		var r: Dictionary = p["pitching"]["ratings"]
		for k: String in PIT_KEYS:
			if r.get(k) is Dictionary:
				out.append(int(r[k]["value"]))
	else:
		var r: Dictionary = p["batting"]["ratings"]
		for k: String in BAT_KEYS:
			if r.get(k) is Dictionary:
				out.append(int(r[k]["value"]))
	return out


func _add(acc: Dictionary, key: String, vals: Array, p: Dictionary) -> void:
	if not acc.has(key):
		acc[key] = {"n": 0, "b": 0, "a": 0, "s": 0, "none": 0, "top": 0.0, "lv": 0.0, "pn": 0, "v150": 0, "v155": 0}
	var a: Dictionary = acc[key]
	a["n"] += 1
	var nb := 0
	for v: int in vals:
		nb += 1 if v >= 70 else 0
		a["a"] += 1 if v >= 80 else 0
		a["s"] += 1 if v >= 90 else 0
	a["b"] += nb
	a["none"] += 1 if nb == 0 else 0
	a["top"] += float(vals.max()) if not vals.is_empty() else 0.0
	a["lv"] += FictionalDraft.entry_level(p)
	if bool(p["is_pitcher"]):
		a["pn"] += 1
		var kmh := int(p["pitching"].get("velocity", {}).get("kmh", 0))
		a["v150"] += 1 if kmh >= 150 else 0
		a["v155"] += 1 if kmh >= 155 else 0


func _print_row(label: String, a: Dictionary, classes: int) -> void:
	if a.is_empty():
		print("%-6s（なし）" % label)
		return
	var n := float(a["n"])
	var velo := ""
	if int(a["pn"]) > 0:
		velo = "　150km+ %.0f%%・155km+ %.0f%%" % [100.0 * a["v150"] / a["pn"], 100.0 * a["v155"] / a["pn"]]
	print("%-6s %5.1f人/年　B+ %.2f　A+ %.2f　S %.2f　B+なし %3.0f%%　最高 %.1f　総合 %.1f%s" % [label, n / classes,
		a["b"] / n, a["a"] / n, a["s"] / n, 100.0 * a["none"] / n, a["top"] / n, a["lv"] / n, velo])


static func _mean(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var s := 0.0
	for x: Variant in xs:
		s += float(x)
	return s / xs.size()


static func _hist(xs: Array) -> String:
	var h := {}
	for x: Variant in xs:
		var b := int(x) / 5 * 5
		h[b] = int(h.get(b, 0)) + 1
	var ks: Array = h.keys()
	ks.sort()
	var parts: Array = []
	for k: int in ks:
		parts.append("%d台 %d" % [k, h[k]])
	return "・".join(parts)
