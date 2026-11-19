extends SceneTree
## 架空のドラフト候補の型の偏りを数える（docs/AUTORUN.md 作業89。表示だけ。ヘッドレスで数十秒）。
## - 型ごとの人数（1年あたり）・1年に同じ型が3人以上いる型の数・1年でいちばん多い型の人数
## - 同じ型の中のばらつき：形（選手の中でいちばん高い能力＞2番目／いちばん低い能力）の種類と、いちばん多い形の割合
## - 「そっくりさん」：同じ年に同じ型で形まで同じ2人の組の数（1年あたり）
## - 評価ごとの長所（66以上）・短所（50未満）の数
## - 型なしの割合（type_key が空）
## - 1年分の10人の例
## 転生選手・掘り出し物（gem）は数えない。投手は奪三振・制球・球威・スタミナ＋球速（150km以上を長所・141km以下を短所）
##
## 型の名前を3つ目に渡すと、1通り目のその型の候補（育成を除く）を全部並べる
##
##   godot --headless --path godot -s res://tests/type_spread_dump.gd -- [年数] [種の数] [型の名前]

const BAT_KEYS := ["meet", "power", "eye", "speed", "defense", "arm"]
const PIT_KEYS := ["k9", "bb9", "hr9", "stamina"]
const WORD := {"meet": "ミ", "power": "パ", "eye": "眼", "speed": "走", "defense": "守", "arm": "肩",
	"k9": "三", "bb9": "制", "hr9": "球", "stamina": "ス", "velocity": "速"}

var _years := 20
var _seeds := 3
var _list_type := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_years = int(args[0])
	if args.size() > 1:
		_seeds = int(args[1])
	if args.size() > 2:
		_list_type = args[2]
	_run.call_deferred()


func _run() -> void:
	var fd_script: GDScript = load("res://sim/fictional_draft.gd")
	var classes := 0
	var all_n := 0
	var typeless := 0
	var side_n := {"投手": [0, 0], "野手": [0, 0]}
	var per_type := {}  # 型 → 人数
	var sigs := {}  # 型 → {組み合わせ: 人数}
	var max_in_year: Array = []
	var three_plus := 0
	var four_plus := 0
	var lookalike := 0
	var lookalike_pos := 0
	var by_grade_s := {}
	var example: Array = []
	var listed: Array = []
	for s in _seeds:
		var fd: RefCounted = fd_script.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 8900 + s
		for y in range(2028, 2028 + _years):
			var cls: Array = fd.generate_year(y, rng)
			classes += 1
			var year_count := {}
			var year_sig := {}
			var year_pos_sig := {}
			for p: Dictionary in cls:
				var am: Dictionary = p["amateur"]
				if p.has("reincarnation") or bool(am.get("gem", false)):
					continue
				all_n += 1
				var key := str(am.get("type_key", ""))
				var label := FictionalTypes.label_of(key) if not key.is_empty() else ""
				var sig := _sig(p)
				var g := str(am.get("grade", "?"))
				if not by_grade_s.has(g):
					by_grade_s[g] = [0, 0, 0]
				by_grade_s[g][0] += 1
				by_grade_s[g][1] += sig[1]
				by_grade_s[g][2] += sig[2]
				var grp := FictionalTypes.pos_group(p)
				year_pos_sig[grp + sig[3]] = int(year_pos_sig.get(grp + sig[3], 0)) + 1
				var side := "投手" if bool(p["is_pitcher"]) else "野手"
				side_n[side][0] += 1
				side_n[side][1] += 1 if label.is_empty() else 0
				if label.is_empty():
					typeless += 1
				else:
					per_type[label] = int(per_type.get(label, 0)) + 1
					year_count[label] = int(year_count.get(label, 0)) + 1
					if not sigs.has(label):
						sigs[label] = {}
					sigs[label][sig[3]] = int(sigs[label].get(sig[3], 0)) + 1
					year_sig[label + sig[3]] = int(year_sig.get(label + sig[3], 0)) + 1
				if s == 0 and label == _list_type and not bool(am.get("as_ikusei", false)):
					listed.append("%d年 %s" % [y, _line(p, label)])
				if s == 0 and y == 2030 and example.size() < 12 and not bool(am.get("as_ikusei", false)) \
						and int(am.get("as_round", 9)) <= 3:
					example.append(_line(p, label))
			var mx := 0
			for k: String in year_count:
				mx = maxi(mx, int(year_count[k]))
				three_plus += 1 if int(year_count[k]) >= 3 else 0
				four_plus += 1 if int(year_count[k]) >= 4 else 0
			max_in_year.append(mx)
			for k: String in year_sig:
				var n := int(year_sig[k])
				lookalike += n * (n - 1) / 2
			for k: String in year_pos_sig:
				var n := int(year_pos_sig[k])
				lookalike_pos += n * (n - 1) / 2
	print("== 架空の候補の型（%d年 × %d通り = %d年分、%d人。転生・掘り出し物を除く） ==" % [_years, _seeds, classes, all_n])
	print("型なし %.1f%%（%d人。投手 %.1f%%・野手 %.1f%%）、型の種類 %d" % [100.0 * typeless / maxf(1, all_n), typeless,
		100.0 * side_n["投手"][1] / maxf(1, side_n["投手"][0]), 100.0 * side_n["野手"][1] / maxf(1, side_n["野手"][0]), per_type.size()])
	var mx_sum := 0
	var mx_max := 0
	for m: int in max_in_year:
		mx_sum += m
		mx_max = maxi(mx_max, m)
	print("1年でいちばん多い型の人数 平均 %.2f・最大 %d、1年に3人以上いる型 %.2f個／年・4人以上 %.2f個／年"
		% [float(mx_sum) / classes, mx_max, float(three_plus) / classes, float(four_plus) / classes])
	print("そっくりさん（同じ年・同じ型・同じ形＝1番目＞2番目／いちばん低い能力 の組）%.2f組／年、守備位置の区分と形が同じ組（型を問わず）%.1f組／年"
		% [float(lookalike) / classes, float(lookalike_pos) / classes])
	var names := per_type.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return int(per_type[a]) > int(per_type[b]))
	var tot_types := 0
	var tot_kinds := 0.0
	var tot_top := 0.0
	print("| 型 | 1年あたり | 形の種類 | いちばん多い形 |")
	for nm: String in names:
		var d: Dictionary = sigs[nm]
		var top := 0
		var top_sig := ""
		for k: String in d:
			if int(d[k]) > top:
				top = int(d[k])
				top_sig = k
		var n := int(per_type[nm])
		tot_types += n
		tot_kinds += float(d.size())
		tot_top += float(top)
		print("| %s | %.2f | %d | %.0f%%（%s） |" % [nm, float(n) / classes, d.size(), 100.0 * top / n, top_sig])
	print("型あり全体：いちばん多い形の割合（人数で重み）%.0f%%、1つの型の形の種類 平均 %.1f"
		% [100.0 * tot_top / maxf(1, tot_types), tot_kinds / maxf(1, names.size())])
	for g: String in ["S", "A", "B", "C", "D"]:
		if by_grade_s.has(g):
			var a: Array = by_grade_s[g]
			print("評価 %s：長所（66以上）%.2f・短所（50未満）%.2f／人" % [g, float(a[1]) / a[0], float(a[2]) / a[0]])
	print("== 例（1通り目の2030年、3位までの候補から12人） ==")
	for l: String in example:
		print(l)
	if not _list_type.is_empty():
		print("== 「%s」の候補（1通り目、育成を除く） ==" % _list_type)
		for l: String in listed:
			print(l)
	quit(0)


## [組み合わせの文字列, 長所の数, 短所の数]
func _sig(p: Dictionary) -> Array:
	var pit := bool(p["is_pitcher"])
	var r: Dictionary = p["pitching"]["ratings"] if pit else p["batting"]["ratings"]
	var keys: Array = PIT_KEYS if pit else BAT_KEYS
	var st: Array = []
	var wk: Array = []
	for k: String in keys:
		var v := int(r[k]["value"]) if r.get(k) is Dictionary else 50
		if v >= 66:
			st.append(WORD[k])
		elif v < 50:
			wk.append(WORD[k])
	if pit:
		var kmh := int(p["pitching"].get("velocity", {}).get("kmh", 145))
		if kmh >= 150:
			st.append(WORD["velocity"])
		elif kmh <= 141:
			wk.append(WORD["velocity"])
	return ["+" + "".join(st) + "/-" + "".join(wk), st.size(), wk.size(), _rel(p, r, keys)]


## 選手の中での形：いちばん高い能力＞2番目／いちばん低い能力（投手の球速は 145km＝50・1km＝2.5 に換算して並べる）
func _rel(p: Dictionary, r: Dictionary, keys: Array) -> String:
	var vals := {}
	for k: String in keys:
		vals[k] = float(r[k]["value"]) if r.get(k) is Dictionary else 50.0
	if bool(p["is_pitcher"]):
		vals["velocity"] = 50.0 + (float(p["pitching"].get("velocity", {}).get("kmh", 145)) - 145.0) * 2.5
	var ks: Array = vals.keys()
	ks.sort_custom(func(a: String, b: String) -> bool: return float(vals[a]) > float(vals[b]))
	return "%s＞%s／%s" % [WORD[ks[0]], WORD[ks[1]], WORD[ks[-1]]]


func _line(p: Dictionary, label: String) -> String:
	var am: Dictionary = p["amateur"]
	var pit := bool(p["is_pitcher"])
	var r: Dictionary = p["pitching"]["ratings"] if pit else p["batting"]["ratings"]
	var keys: Array = PIT_KEYS if pit else BAT_KEYS
	var parts: Array = []
	for k: String in keys:
		parts.append("%s%d" % [WORD[k], int(r[k]["value"])])
	if pit:
		parts.push_front("%dkm" % int(p["pitching"]["velocity"]["kmh"]))
	return "%s %s %s 評価%s %s：%s" % [str(am.get("category", "")), str(p.get("primary_pos", "投手" if pit else "")),
		label if not label.is_empty() else "（型なし）", str(am.get("grade", "")), str(am.get("projected", "")), "・".join(parts)]
