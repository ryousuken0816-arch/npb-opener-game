extends SceneTree
## ドラフトのCPUバランスの確認（ヘッドレス、約4分）。docs/AUTORUN.md 作業7。
## 2012・2016・2019・2024年の開始から「すぐドラフトへ」進み、自球団もおまかせで最後まで指名して次を数える：
## - お宝：史実で4位以下・育成の指名なのに、史実の活躍（ノイズなしの将来性）が B 以上の候補。
##   その一部（各年の合計の3分の1以上。2024年は史実の成績がまだ少ないので数えない）が中位（ゲームの3位）以下まで残る
## - 大物：史実で1巡目に2球団以上が競合した候補。全員がゲームの2位までに指名され（上位で消える）、6割以上が1位
## - 目玉：各CPU球団が1〜2人の目玉を持ち、目玉の多くは1〜2位で指名される
##
##   godot --headless --path godot --script res://tests/draft_balance_check.gd -- [年,年,...]

const USER := "読売ジャイアンツ"
const GEM_RANK := "B"
const GEM_SURVIVE_SHARE := 1.0 / 3.0
const STAR_FIRST_SHARE := 0.6

var _years: Array[int] = [2012, 2016, 2019, 2024]
var _failures := 0
## お宝の数（2023年より前の年の合計）と、そのうちゲームの3位以下まで残った数
var _gems_total := 0
var _gems_survived := 0
var _gs: Node
var _ds: GDScript


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].is_empty():
		_years.clear()
		for y: String in args[0].split(","):
			_years.append(int(y))
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_ds = load("res://sim/draft.gd")
	for y in _years:
		_check_year(y)
	# 1年に数人しかいないので年ごとでは乱数でぶれる（2012年は2人で 0〜2人）。合わせて判定する
	if _gems_total > 0:
		_check(_gems_survived >= ceili(_gems_total * GEM_SURVIVE_SHARE),
			"お宝（各年の合計）の3分の1以上が3位以下まで残る（%d / %d）" % [_gems_survived, _gems_total])
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_year(y: int) -> void:
	print("\n== %d年のドラフト ==" % y)
	_gs.new_game(USER, y)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	var d: RefCounted = _gs.draft()
	if d == null:
		_check(false, "%d年：ドラフトが開かない" % y)
		return
	d.auto_complete()
	var round_of := {}
	for p: Dictionary in d.picks:
		# 育成は本指名のあと（ゲームの順位に 10 を足して下位として扱う）
		round_of[p["id"]] = int(p["round"]) + (10 if p["ikusei"] else 0)
	var gem_bar: float = _ds.FUTURE_RANKS[_ds.RANK_LETTERS.find(GEM_RANK)]
	# お宝
	var gems: Array[String] = []
	var survived := 0
	for c: Dictionary in d.candidates:
		if (c["hist_round"] >= 4 or c["hist_ikusei"]) and float(c["future"]) >= gem_bar:
			var r: int = round_of.get(c["id"], 99)
			gems.append("%s（史実%s→%s）" % [c["name"], c["hist_label"], _round_text(r)])
			if r >= 3:
				survived += 1
	print("  お宝 %d人、ゲームの3位以下まで残った %d人：%s" % [gems.size(), survived, "、".join(gems.slice(0, 12))])
	if y < 2023:
		_gems_total += gems.size()
		_gems_survived += survived
	# 大物
	var stars: Array[String] = []
	var first := 0
	var late := 0
	for c: Dictionary in d.candidates:
		if int(c["bids"]) >= 2:
			var r: int = round_of.get(c["id"], 99)
			stars.append("%s（%d球団→%s）" % [c["name"], int(c["bids"]), _round_text(r)])
			if r == 1:
				first += 1
			elif r > 2:
				late += 1
	print("  大物 %d人、ゲームの1位 %d人：%s" % [stars.size(), first, "、".join(stars)])
	if not stars.is_empty():
		_check(late == 0 and first >= ceili(stars.size() * STAR_FIRST_SHARE),
			"%d年：大物が2位までに消え、6割以上が1位（1位 %d / %d、3位以下 %d）" % [y, first, stars.size(), late])
	# 目玉
	var targets: Dictionary = d.get("cpu_targets") if d.get("cpu_targets") is Dictionary else {}
	var counts: Array[int] = []
	var top := 0
	var total := 0
	for t: String in targets:
		counts.append(targets[t].size())
		for id: String in targets[t]:
			total += 1
			if int(round_of.get(id, 99)) <= 2:
				top += 1
	print("  目玉（球団ごとの人数 %s）、2位までに指名 %d / %d" % [str(counts), top, total])
	_check(not counts.is_empty() and counts.all(func(n: int) -> bool: return n >= 1 and n <= 2),
		"%d年：各CPU球団の目玉は1〜2人（%s）" % [y, str(counts)])
	_check(total > 0 and top >= total * 0.6, "%d年：目玉の6割以上が2位までに指名（%d / %d）" % [y, top, total])
	# 何位まで指名が続くか（6巡もつか）：本指名の各順位で、残っている候補の中の将来性（ノイズなし）の最大
	var best_left := []
	for r in range(1, 8):
		var best := -INF
		for c: Dictionary in d.candidates:
			if int(round_of.get(c["id"], 99)) >= r:
				best = maxf(best, float(c["future"]))
		best_left.append("%d位%s" % [r, _ds.rank_of(best, _ds.FUTURE_RANKS)])
	print("  各順位の時点で残っている最高の将来性（ノイズなし）：%s" % " ".join(best_left))


func _round_text(r: int) -> String:
	if r >= 99:
		return "指名なし"
	if r > 10:
		return "育成%d位" % (r - 10)
	return "%d位" % r


func _check(ok: bool, label: String) -> void:
	print(("OK " if ok else "NG ") + label)
	if not ok:
		_failures += 1
