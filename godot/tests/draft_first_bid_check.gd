extends SceneTree
## CPU球団の1位入札の競合の分布（docs/AUTORUN.md 作業68）。ヘッドレス、約20秒。
## 2008〜2027年の史実の年と2028〜2037年の架空の年（30年分、各2回）で、ドラフトを組み立てて1回目の1位入札だけを行い、
## 「何人に何球団」を数える。史実（2008年以降の1回目の入札：競合する選手 年平均2.6人、単独の1位 34%、
## 6球団以上の競合は19年で3回）に近いこと：
##   - 競合する選手は年に平均 1.2〜3.0人、いちばん多い年でも5人まで
##   - 6球団以上の競合は2割の年まで（今までは半分の年で起きていた）
##   - 単独の1位（ほかの球団と重ならない入札）が 30〜60%（今までは16%）
##   - 本当の目玉（当時の評価がいちばん高い候補）には、競合がよく集まる（複数球団の年が半分以上）
##   - 球団の性格（強気・堅実・補強重視）がそろって出て、堅実な球団は強気な球団より単独の1位が多い。自球団のおまかせの入札は変わらない（Draft._best_for のまま）
## 比べるために、史実の1巡目の競合（data/draft_first_round.json の bids）も同じ形で出す。
##
##   godot --headless --path godot -s res://tests/draft_first_bid_check.gd

const USER := "読売ジャイアンツ"
const HIST_YEARS := [2008, 2027]
const FICT_YEARS := [2028, 2037]
## 1年に何回組み立てるか（乱数の違い）
const REPS := 2

var _failures := 0
var _gs: Node
var _gd: Node
var _ds: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_ds = load("res://sim/draft.gd")
	_gs.new_game(USER, 2027)
	var hist := _collect(HIST_YEARS[0], HIST_YEARS[1], false)
	var fict := _collect(FICT_YEARS[0], FICT_YEARS[1], true)
	_report("史実の年（%d〜%d年）" % HIST_YEARS, hist)
	_report("架空の年（%d〜%d年）" % FICT_YEARS, fict)
	var all := {}
	all["rows"] = (hist["rows"] as Array) + (fict["rows"] as Array)
	var s := _report("30年分", all)
	_real()
	_check(s["contested_avg"] >= 1.2 and s["contested_avg"] <= 3.0,
		"競合する選手は年に平均 %.2f 人（1.2〜3.0）" % s["contested_avg"])
	_check(s["contested_max"] <= 5, "競合する選手がいちばん多い年でも %d 人（5人まで）" % s["contested_max"])
	_check(s["six_plus"] <= 0.2, "6球団以上の競合は %.0f%% の年（2割まで）" % (s["six_plus"] * 100.0))
	_check(s["solo_share"] >= 0.3 and s["solo_share"] <= 0.6, "単独の1位入札は %.0f%%（30〜60%%）" % (s["solo_share"] * 100.0))
	var styles: Dictionary = {}
	for k: String in ["styles"]:
		for st: String in hist[k]:
			styles[st] = (hist[k][st] as Array).duplicate()
		for st: String in fict[k]:
			if not styles.has(st):
				styles[st] = [0, 0]
			styles[st][0] += int(fict[k][st][0])
			styles[st][1] += int(fict[k][st][1])
	var total := 0
	var parts: Array[String] = []
	for st: String in styles:
		total += int(styles[st][0])
	var solo_rate := {}
	for st: String in ["強気", "堅実", "補強重視"]:
		var a: Array = styles.get(st, [0, 0])
		solo_rate[st] = float(a[1]) / maxf(float(a[0]), 1.0)
		parts.append("%s %.0f%%（単独 %.0f%%）" % [st, float(a[0]) * 100.0 / maxf(float(total), 1.0), solo_rate[st] * 100.0])
	print("  CPU球団の性格：%s" % "・".join(parts))
	var spread := true
	for st: String in solo_rate:
		spread = spread and float(styles[st][0]) >= total * 0.15
	_check(spread, "性格（強気・堅実・補強重視）がそれぞれ15%以上の球団に出る")
	_check(float(solo_rate["堅実"]) > float(solo_rate["強気"]), "堅実な球団は強気な球団より単独の1位が多い（%.0f%% と %.0f%%）"
		% [float(solo_rate["堅実"]) * 100.0, float(solo_rate["強気"]) * 100.0])
	_check(s["top_contested"] >= 0.5, "当時の評価がいちばん高い候補に複数球団が来る年が %.0f%%（半分以上）" % (s["top_contested"] * 100.0))
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


## 年ごとに1回目の1位入札を行い、[{contested, max, solo, top_bidders}] を集める
func _collect(from_year: int, to_year: int, fictional: bool) -> Dictionary:
	var rows: Array = []
	var styles := {}  # 性格 → [球団の数, 単独の1位の数]（CPU球団）
	var user_same := 0
	var user_total := 0
	for y in range(from_year, to_year + 1):
		var entries := {}
		if fictional:
			for p: Dictionary in _gs.draft_class(y):
				entries[p["id"]] = p
		for rep in REPS:
			var d: RefCounted = _ds.new()
			d.setup(y, USER, _gd.teams(), entries, {}, _gd.teams(), hash("%d|%d" % [y, rep]))
			if d.candidates.is_empty():
				continue
			var expect: String = d.call("_best_for", USER, true, false)
			d.run_first_wave()
			user_total += 1
			var count := {}
			var user_bid := ""
			for r: Dictionary in d.last_wave:
				count[r["id"]] = int(count.get(r["id"], 0)) + 1
				if r["team"] == USER:
					user_bid = r["id"]
			if user_bid == expect:
				user_same += 1
			for r: Dictionary in d.last_wave:
				if r["team"] == USER:
					continue
				var st: String = d.style_of(r["team"])
				if not styles.has(st):
					styles[st] = [0, 0]
				styles[st][0] += 1
				if int(count[r["id"]]) == 1:
					styles[st][1] += 1
			var top := ""
			for c: Dictionary in d.candidates:
				if top.is_empty() or float(c["hyouka"]) > float(d.by_id[top]["hyouka"]):
					top = c["id"]
			var contested := 0
			var mx := 0
			var solo := 0
			for id: String in count:
				mx = maxi(mx, int(count[id]))
				if int(count[id]) >= 2:
					contested += 1
				else:
					solo += 1
			rows.append({"year": y, "contested": contested, "max": mx, "solo": solo, "top": int(count.get(top, 0)),
				"dist": _dist(count)})
	_check(user_same == user_total, "%s：自球団のおまかせの入札は変わらない（%d/%d）" % ["架空" if fictional else "史実", user_same,
		user_total])
	return {"rows": rows, "styles": styles}


func _dist(count: Dictionary) -> String:
	var ns: Array = count.values()
	ns.sort()
	ns.reverse()
	var parts: Array[String] = []
	for n: int in ns:
		if n >= 2:
			parts.append(str(n))
	return "+".join(parts) if not parts.is_empty() else "競合なし"


func _report(title: String, data: Dictionary) -> Dictionary:
	var rows: Array = data["rows"]
	var contested := 0
	var contested_max := 0
	var six := 0
	var solo := 0
	var top_c := 0
	var hist := {}
	var line: Array[String] = []
	for r: Dictionary in rows:
		contested += int(r["contested"])
		contested_max = maxi(contested_max, int(r["contested"]))
		if int(r["max"]) >= 6:
			six += 1
		solo += int(r["solo"])
		if int(r["top"]) >= 2:
			top_c += 1
		hist[int(r["max"])] = int(hist.get(int(r["max"]), 0)) + 1
		line.append("%d:%s" % [r["year"], r["dist"]])
	var n := maxf(float(rows.size()), 1.0)
	var s := {"contested_avg": contested / n, "contested_max": contested_max, "six_plus": six / n,
		"solo_share": solo / (n * 12.0), "top_contested": top_c / n}
	print("\n== %s（%d回） ==" % [title, rows.size()])
	print("  年ごとの競合（何球団の競合か）：%s" % "  ".join(line))
	var keys: Array = hist.keys()
	keys.sort()
	var hl: Array[String] = []
	for k: int in keys:
		hl.append("%d球団 %d回" % [k, hist[k]])
	print("  いちばん多い競合：%s" % "、".join(hl))
	print("  競合する選手 年平均 %.2f人（最多 %d人）・単独の1位 %.0f%%・評価1番の候補に競合 %.0f%%" % [s["contested_avg"],
		contested_max, s["solo_share"] * 100.0, s["top_contested"] * 100.0])
	return s


## 史実の1巡目の1回目の入札（data/draft_first_round.json）：2008年以降、1回目の入札で2球団以上が来た選手
func _real() -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path("res://").path_join("../data/draft_first_round.json"), FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not data is Array:
		return
	var by_year := {}
	for r: Variant in data:
		if not r is Dictionary or int(r.get("draft_year", 0)) < HIST_YEARS[0]:
			continue
		var y := int(r["draft_year"])
		if not by_year.has(y):
			by_year[y] = []
		if int(r.get("wave", 1)) <= 1 and int(r.get("bids", 1)) >= 2:
			by_year[y].append(int(r["bids"]))
	var line: Array[String] = []
	var contested := 0
	var solo := 0
	var keys: Array = by_year.keys()
	keys.sort()
	for y: int in keys:
		var ns: Array = by_year[y]
		ns.sort()
		ns.reverse()
		contested += ns.size()
		var used := 0
		for n: int in ns:
			used += n
		solo += 12 - used
		line.append("%d:%s" % [y, "+".join(ns.map(func(n: int) -> String: return str(n))) if not ns.is_empty() else "競合なし"])
	var n := maxf(float(keys.size()), 1.0)
	print("
== 史実（参考） ==
  %s
  競合する選手 年平均 %.2f人・単独の1位 %.0f%%" % ["  ".join(line), contested / n,
		solo / (n * 12.0) * 100.0])


func _check(ok: bool, label: String) -> void:
	print(("OK " if ok else "NG ") + label)
	if not ok:
		_failures += 1
