extends SceneTree
## オーナーの目標と評価（作業46）の確認（ヘッドレス）：
## 目標の決め方（強い球団は優勝・弱い球団は最下位脱出や若手）、開始時の目標とニュース、進み具合が日付で追従するか、
## 表彰のあとの評価・講評・予算の増減・ニュース、D・E が続いたときの「監督の進退」、翌年の目標、セーブ／ロード。
##
##   godot --headless --path godot --script res://tests/owner_check.gd

var _failures := 0
var _gs: Node
var _gd: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_check_choose()
	_check_grades()

	_gs.new_game("阪神タイガース", 2008)
	var goals: Array = _gs.owner_goals.goals_of(2008)
	var texts: Array = goals.map(func(g: Dictionary) -> String: return OwnerGoals.goal_text(g))
	print("  2008年 阪神の目標: ", texts)
	_check(goals.size() >= 1 and goals.size() <= 3, "開始時に目標が1〜3個（%d個）" % goals.size())
	var owner_news: Array = _gs.news.of_kind("owner", 2008)
	_check(owner_news.size() == 1 and owner_news[0]["flash"], "目標をオーナーの速報で知らせる：%s" % [
		owner_news[0]["headline"] if not owner_news.is_empty() else "-"])
	if not owner_news.is_empty():
		print("    ", owner_news[0]["body"].replace("\n", " / "))

	# 12球団の戦力の順位と目標
	var team_save: String = _gs.team
	for lg in ["C", "P"]:
		var rows: Array = []
		for t: String in _gd.teams(lg):
			rows.append([t, _gs._team_strength(t)])
		rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
		var line: Array = []
		for r: Array in rows:
			line.append("%s %.2f" % [_gd.short_name(r[0]), r[1]])
		print("  %s の戦力: %s" % [lg, ", ".join(line)])
		var top: String = rows[0][0]
		var bottom: String = rows[-1][0]
		_gs.team = top
		_gs.owner_goals.goals.erase("2008")
		_gs._owner_set_goals()
		var g_top: Array = _gs.owner_goals.goals_of(2008)
		_gs.team = bottom
		_gs.owner_goals.goals.erase("2008")
		_gs._owner_set_goals()
		var g_bottom: Array = _gs.owner_goals.goals_of(2008)
		_check(g_top[0]["kind"] == "rank" and g_top[0]["target"] == 1, "%sの戦力1位 %s はリーグ優勝" % [lg,
			_gd.short_name(top)])
		_check(g_bottom[0]["kind"] == "rank" and g_bottom[0]["target"] == 5, "%sの戦力6位 %s は最下位脱出（%s）" % [
			lg, _gd.short_name(bottom), OwnerGoals.goal_text(g_bottom[0])])
	_gs.team = team_save
	_gs.owner_goals.goals["2008"] = goals
	_gs._apply_owner_budget()

	# 進み具合は日付を進めると追従する
	var p0: Array = _gs.owner_progress()
	_gs.advance_through(Season.day_number("2008-05-31"))
	var p1: Array = _gs.owner_progress()
	print("  6月1日の進み具合: ", p1.map(func(r: Dictionary) -> String: return "%s %s %s" % [
		r["text"], r["actual"], "○" if r["done"] else "×"]))
	_check(p1.size() == goals.size(), "ハブに出す進み具合が目標の数だけある")
	var youth0: int = _gs.youth_usage()
	_gs.advance_through(_gs.day + 6)
	_check(_gs.youth_usage() >= youth0, "若手の出場は日付を進めると増える（%d → %d）" % [youth0, _gs.youth_usage()])

	# セーブ／ロード
	var saved: Variant = _norm(_gs.to_save())
	var o_before := JSON.stringify(_norm(_gs.owner_goals.to_save()))
	_gs.new_game("読売ジャイアンツ", 2010)
	_gs.load_state(saved)
	_check(JSON.stringify(_norm(_gs.owner_goals.to_save())) == o_before, "ロードで目標・評価が一致")

	# 1年回して評価（表彰のあと、次の段階へ進むとき）
	var base_budget: int = _budget("阪神タイガース")
	_gs.advance_through(_gs.season_last_day())
	_check(_gs.phase == _gs.Phase.AWARDS and _gs.owner_goals.eval_of(2008).is_empty(), "表彰の段階ではまだ評価しない")
	_print_youth()
	_gs.advance()
	var e: Dictionary = _gs.owner_goals.eval_of(2008)
	_check(not e.is_empty() and e["grade"] in OwnerGoals.GRADES, "表彰のあとに評価：%s（%.2f点）%s" % [
		e.get("grade", "-"), e.get("score", 0.0), e.get("comment", "")])
	for r: Dictionary in e.get("results", []):
		print("    %s %s（%s・%.2f点）" % ["○" if r["done"] else "×", r["text"], r["actual"], r["score"]])
	_check(_budget("阪神タイガース") == base_budget + int(e.get("budget_delta", 0)),
		"評価で予算が動く（%s → %s）" % [OwnerGoals.money_text(base_budget),
			OwnerGoals.money_text(_budget("阪神タイガース"))])
	var eval_news: Array = _gs.news.of_kind("owner", 2008).filter(func(a: Dictionary) -> bool:
		return str(a["headline"]).contains("評価"))
	_check(eval_news.size() == 1 and eval_news[0]["issue"] == "2008-off", "評価をオフ号に載せる：%s" % [
		eval_news[0]["headline"] if not eval_news.is_empty() else "-"])

	# 翌年の春季キャンプで目標
	_gs.skip_to_phase(_gs.Phase.CAMP)
	_check(_gs.phase == _gs.Phase.CAMP and _gs.year == 2009, "2009年の春季キャンプへ")
	var g09: Array = _gs.owner_goals.goals_of(2009)
	print("  2009年の目標: ", g09.map(func(g: Dictionary) -> String: return OwnerGoals.goal_text(g)))
	_check(not g09.is_empty(), "春季キャンプで今年の目標が出る")
	_check(_gs.owner_progress().size() == g09.size(), "キャンプ中も今年の目標をハブに出せる")
	_gs.advance()
	_check(_gs.phase == _gs.Phase.SEASON and _gs.owner_goals.goals_of(2009) == g09, "開幕しても目標は同じ")
	_check(_budget("阪神タイガース") == base_budget + int(_gs.owner_goals.bonus),
		"翌年の予算に評価の増減が残る")
	print("ALL OK" if _failures == 0 else "NG %d件" % _failures)
	quit(1 if _failures > 0 else 0)


## 目標の決め方（球団の状況に合っているか）
func _check_choose() -> void:
	var rng := RandomNumberGenerator.new()
	var g1 := OwnerGoals.choose(1, 1, true, 300000, 420000, rng)
	_check(g1[0]["target"] == 1 and g1.any(func(g: Dictionary) -> bool: return g["kind"] == "japan"),
		"戦力1位・前年日本一は優勝と日本一")
	var g3 := OwnerGoals.choose(3, 4, false, 200000, 280000, rng)
	_check(g3[0]["kind"] == "rank" and g3[0]["target"] == 3, "戦力3位・前年4位は Aクラス")
	var g5 := OwnerGoals.choose(5, 4, false, 200000, 280000, rng)
	_check(g5[0]["kind"] == "winpct", "戦力5位・前年4位は勝率5割")
	var g6 := OwnerGoals.choose(6, 6, false, 290000, 280000, rng)
	_check(g6[0]["target"] == 5 and g6.any(func(g: Dictionary) -> bool: return g["kind"] == "budget"),
		"戦力6位・予算超過は最下位脱出と予算を守る")
	var youth := 0
	for i in 100:
		if OwnerGoals.choose(6, 6, false, 0, 280000, rng).any(func(g: Dictionary) -> bool: return g["kind"] == "youth"):
			youth += 1
	_check(youth > 50 and youth < 90, "弱い球団は若手の起用の目標が出やすい（100回中%d回）" % youth)


## 採点と評価・予算・進退
func _check_grades() -> void:
	var o := OwnerGoals.new()
	o.set_goals(2008, [{"kind": "rank", "target": 1}])
	var e := o.evaluate(2008, {"rank": 1, "final": true}, "t")
	_check(e["grade"] == "A" and o.bonus == 10000, "優勝が目標で優勝 → A・予算+1億")
	e = o.evaluate(2008, {"rank": 6, "final": true}, "t")
	_check(e["grade"] == "E" and o.bonus == -10000, "同じ年を採点し直すと予算は1回分だけ（6位 → E・−1億）")
	o.set_goals(2009, [{"kind": "rank", "target": 3}, {"kind": "youth", "target": 2000}])
	e = o.evaluate(2009, {"rank": 6, "youth": 300, "final": true}, "t")
	_check(e["grade"] in ["D", "E"] and e["streak"] == 2, "2年続けて D・E（%s・%d年）" % [e["grade"], e["streak"]])
	o.set_goals(2010, [{"kind": "rank", "target": 5}])
	e = o.evaluate(2010, {"rank": 1, "final": true}, "t")
	_check(e["grade"] == "S" and e["streak"] == 0, "最下位脱出が目標で優勝 → S（%.2f点）" % e["score"])
	for i in 10:
		o.set_goals(2011 + i, [{"kind": "rank", "target": 1}])
		o.evaluate(2011 + i, {"rank": 6, "final": true}, "t")
	_check(o.bonus == OwnerGoals.BONUS_MIN, "予算の減り方には下限がある（%s）" % OwnerGoals.money_text(o.bonus))


func _print_youth() -> void:
	var save: String = _gs.team
	var line: Array = []
	for t: String in _gd.teams():
		_gs.team = t
		line.append("%s %d" % [_gd.short_name(t), _gs.youth_usage()])
	_gs.team = save
	print("  2008年の若手（25歳以下）の打席＋対戦打者: ", ", ".join(line))


## 予算（ContractRenewal はオートロードに依る型なので、テストのスクリプトからは実行時に読む）
func _budget(team_name: String) -> int:
	return load("res://sim/contract_renewal.gd").budget(team_name)


func _norm(v: Variant) -> Variant:
	return SaveUtil.ints(JSON.parse_string(JSON.stringify(v, "", false, true)))


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
	print(("  OK " if ok else "  NG ") + message)
