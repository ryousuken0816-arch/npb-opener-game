extends SceneTree
## 采配（1軍登録・オーダー・先発ローテ・采配方針）の確認（ヘッドレス）。
##
##   godot --headless --path godot --script res://tests/tactics_check.gd -- [球団名]
##
## - 全球団の1軍が登録人数の上限・外国人枠（史実のルール）を守っている
## - 上限・外国人枠を超える登録、抹消から10日以内の再登録ができない
## - 2軍から上げてスタメン・先発ローテに入れた選手が、数日進めると実際に試合に出て成績が付く。
##   2軍に落とした選手は試合に出ない（毎日、その日の試合の出場選手が全員1軍だったかを調べる）
## - 采配方針（送りバント・盗塁・継投）が試合の結果に効く

var _team := "阪神タイガース"
var _failures := 0
var _gs: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_team = args[0]
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gs.new_game(_team)
	var season: Season = _gs.season
	var mine: SimTeam = _gs.my_team()
	_check(mine != null, "自球団の編成がある")
	var limit := RosterRules.roster_limit(season.year)

	print("\n== 自動編成（全球団）==")
	for team_name: String in season.teams:
		var t: SimTeam = season.teams[team_name]
		var fc := t.foreign_counts()
		print("  %s: 1軍%d人（投%d 野%d）外国人 投%d 野%d / 先発%d 中継ぎ%d 抑え%s" % [
			team_name, t.active_count(), t.active_players(true).size(), t.active_players(false).size(),
			fc[0], fc[1], t.rotation.size(), t.relievers.size(), "1" if t.closer != null else "0"])
		_check(t.active_count() <= limit, "%s: 1軍は%d人以内" % [team_name, limit])
		_check(fc[0] + fc[1] <= RosterRules.foreign_limit(season.year)
				and fc[0] <= RosterRules.foreign_type_limit(season.year)
				and fc[1] <= RosterRules.foreign_type_limit(season.year), "%s: 外国人枠を守っている" % team_name)
		_check(_lineup_ok(t, true) and _lineup_ok(t, false), "%s: スタメンは1軍の野手だけ・守備位置の重複なし" % team_name)

	_check_limits(mine)
	_check_foreign(mine)

	print("\n== スタメン・先発ローテの変更が試合に反映される ==")
	var today: int = _gs.day
	# 2軍の野手で最も打力の高い選手を、スタメンの4番打者（DHあり・なし両方）と入れ替える
	var new_bat: SimPlayer = _best_farm(mine, false)
	var old_bat: SimPlayer = mine.lineup(true)[3][0]
	var old_bat_g := int(season.batting.get(old_bat.id, {}).get("g", 0))
	var err := mine.swap_registration(old_bat, new_bat, today)
	_check(err.is_empty(), "野手を入れ替え: %s（2軍）→ %s の打順（%s）" % [new_bat.name, old_bat.name, err])
	_check(mine.lineup(true)[3][0] == new_bat, "DHありの4番が%sになった" % new_bat.name)
	# 2軍の投手を先発ローテの1番手と入れ替える
	var new_sp: SimPlayer = _best_farm(mine, true)
	var old_sp: SimPlayer = mine.rotation[0]
	err = mine.swap_registration(old_sp, new_sp, today)
	_check(err.is_empty() and mine.rotation[0] == new_sp,
			"先発ローテ1番手: %s → %s（%s）" % [old_sp.name, new_sp.name, err])
	# 打順の入れ替え（1番と2番）
	var first: SimPlayer = mine.lineup(true)[0][0]
	mine.lineup_swap_order(true, 0, 1)
	_check(mine.lineup(true)[1][0] == first, "打順の入れ替え（1番→2番）")
	# 守備位置の入れ替え
	var pos0: String = mine.lineup(true)[0][1]
	var pos1: String = mine.lineup(true)[1][1]
	mine.lineup_set_position(true, 0, pos1)
	_check(mine.lineup(true)[0][1] == pos1 and mine.lineup(true)[1][1] == pos0, "守備位置の入れ替え")
	mine.lineup_set_position(true, 0, pos0)

	# 自球団の試合が7試合終わるまで進める（セ・リーグの開幕はパより遅い年がある）
	var played := 0
	while played < 7:
		var date := Season.date_of_day(_gs.day)
		for g: Dictionary in season.games_on(date):
			if g["status"] == "played" and _team in [g["home"], g["away"]]:
				played += 1
		_advance_day_checked(season)
	print("  %sまで進めた" % Season.day_label(_gs.day - 1))
	var nb: Dictionary = season.batting.get(new_bat.id, {})
	var ns: Dictionary = season.pitching.get(new_sp.id, {})
	print("  %s: %d試合 %d打席 %d安打 %d本塁打" % [new_bat.name, nb.get("g", 0), nb.get("pa", 0),
		nb.get("h", 0), nb.get("hr", 0)])
	print("  %s: 登板%d 先発%d 投球回%d" % [new_sp.name, ns.get("g", 0), ns.get("gs", 0),
		ns.get("outs", 0) / 3])
	_check(nb.get("g", 0) >= 5 and nb.get("pa", 0) >= 15, "上げた野手がスタメンで出場して成績が付いた")
	_check(ns.get("gs", 0) >= 1, "上げた投手が先発した")
	_check(int(season.batting.get(old_bat.id, {}).get("g", 0)) == old_bat_g, "落とした野手は試合に出ていない")

	_check_reregister(mine, old_bat)
	_check_tactics()

	print("\n%s（失敗 %d件）" % ["すべてOK" if _failures == 0 else "失敗あり", _failures])
	quit(1 if _failures > 0 else 0)


## 1日進め、その日の自球団の試合に出た選手が全員1軍だったかを調べる
func _advance_day_checked(season: Season) -> void:
	var date := Season.date_of_day(_gs.day)
	var snapshot := {}
	for team_name: String in season.teams:
		snapshot[team_name] = season.teams[team_name].active.duplicate()
	_gs.advance_through(_gs.day)
	for g: Dictionary in season.games_on(date):
		if g["result"].is_empty():
			continue
		for side in 2:
			var team_name: String = g["away"] if side == 0 else g["home"]
			var ok := true
			for line: Dictionary in g["result"]["batting"][side] + g["result"]["pitching"][side]:
				if not snapshot[team_name].has(line["id"]):
					ok = false
					print("    2軍の選手が出場: %s %s" % [team_name, season.player_name(line["id"])])
			if not ok:
				_check(false, "%s %s: 出場選手は全員1軍" % [date, team_name])


func _check_limits(t: SimTeam) -> void:
	print("\n== 登録人数の上限 ==")
	var today: int = _gs.day
	var limit := RosterRules.roster_limit(t.year)
	# 上限まで2軍の日本人野手（育成は1軍に上げられないので除く）を上げる
	var farm := t.players_where(false, false).filter(func(p: SimPlayer) -> bool:
		return not p.is_foreign and not p.is_ikusei)
	var added: Array[SimPlayer] = []
	while t.active_count() < limit and not farm.is_empty():
		var p: SimPlayer = farm.pop_front()
		_check(t.promote(p, today).is_empty(), "上限未満なら上げられる: " + p.name)
		added.append(p)
	_check(t.active_count() == limit, "1軍が上限の%d人になった" % limit)
	if not farm.is_empty():
		var err := t.promote(farm[0], today)
		print("  → %s" % err)
		_check(not err.is_empty() and t.active_count() == limit, "上限を超える登録はできない")
		# 入れ替えならできる（控えの野手と）
		var out: SimPlayer = t.bench(true)[-1]
		_check(t.swap_registration(out, farm[0], today).is_empty(), "上限でも入れ替えはできる")
		t.swap_registration(farm[0], out, today)
	# 開幕日の試合前に落としたので再登録の制限はかからない（元に戻す）
	for p in added:
		t.demote(p, today)
	_check(t.demoted_day.is_empty(), "開幕日の試合前の入れ替えは抹消の記録を残さない")


func _check_foreign(t: SimTeam) -> void:
	print("\n== 外国人枠 ==")
	var today: int = _gs.day
	var year := t.year
	var farm_foreign := t.players.filter(func(p: SimPlayer) -> bool:
		return p.is_foreign and not t.is_active(p))
	var blocked := 0
	for p: SimPlayer in farm_foreign:
		# 同じ種類の日本人選手（先発ローテ・スタメン以外）と入れ替えてみる
		var out: SimPlayer = null
		for q in t.active_players(p.is_pitcher):
			if not q.is_foreign and q not in t.rotation and not _in_lineup(t, q):
				out = q
				break
		if out == null:
			continue
		var err := t.swap_registration(out, p, today)
		var fc := t.foreign_counts()
		print("  %s（%s）: %s → 外国人 投%d 野%d" % [p.name, "投" if p.is_pitcher else "野",
			"登録" if err.is_empty() else err, fc[0], fc[1]])
		if not err.is_empty():
			blocked += 1
		_check(fc[0] + fc[1] <= RosterRules.foreign_limit(year)
				and fc[0] <= RosterRules.foreign_type_limit(year)
				and fc[1] <= RosterRules.foreign_type_limit(year), "外国人枠を超えていない")
	_check(blocked > 0 or farm_foreign.is_empty(), "外国人枠を超える登録は断られた（%d件）" % blocked)
	t.auto_register()


func _check_reregister(t: SimTeam, p: SimPlayer) -> void:
	print("\n== 抹消後10日間の再登録制限 ==")
	# p は開幕日より後に落としていないので、いったん上げて落とし直す
	var today: int = _gs.day
	if not t.is_active(p):
		var out: SimPlayer = t.bench(true)[-1] if not t.bench(true).is_empty() else null
		if out != null:
			t.swap_registration(out, p, today)
	var bench_p: SimPlayer = t.bench(true)[0]
	var err := t.demote(bench_p, today)
	_check(err.is_empty(), "控えの%sを抹消（%s）" % [bench_p.name, Season.day_label(today)])
	_check(t.promote(bench_p, today).is_empty(), "同じ日のうちなら取り消せる")
	t.demote(bench_p, today)
	var season: Season = _gs.season
	_advance_day_checked(season)
	err = t.promote(bench_p, _gs.day)
	print("  → %s" % err)
	_check(not err.is_empty(), "翌日は再登録できない")
	while _gs.day < today + RosterRules.REREGISTER_DAYS:
		_advance_day_checked(season)
	err = t.promote(bench_p, _gs.day)
	_check(err.is_empty(), "10日後（%s）は再登録できる %s" % [Season.day_label(_gs.day), err])


## 采配方針を全球団 −2 と +2 にした2シーズンで、犠打・盗塁・先発の投球回を比べる
func _check_tactics() -> void:
	print("\n== 采配方針 ==")
	_gs.set_tactic("bunt", 2)
	_check(_gs.my_team().tactics["bunt"] == 2, "自球団の方針が今季の編成に反映される")
	_gs.set_tactic("bunt", 0)
	var game_data: Node = root.get_node("GameData")
	var schedule: Array = game_data.load_schedule(2008)
	var totals := []
	for level in [-2, 0, 2]:
		var s := Season.new(2008, game_data.ratings, schedule, 7, game_data.load_debut_years(2008))
		for team_name: String in s.teams:
			for key: String in SimTeam.TACTIC_KEYS:
				s.teams[team_name].set_tactic(key, level)
		s.sim_until_day(Season.day_number("2008-06-01"))
		var t := s.league_totals()
		var starter_outs := 0
		var starts := 0
		for id: String in s.pitching:
			var pl: Dictionary = s.pitching[id]
			if pl.get("gs", 0) > 0:
				starts += pl["gs"]
		for g: Dictionary in s.games:
			if g["result"].is_empty():
				continue
			for side in 2:
				starter_outs += int(g["result"]["pitching"][side][0].get("outs", 0))
		totals.append({"sh": t["sh"], "sb": t["sb"] + t["cs"], "sp_ip": starter_outs / 3.0 / starts})
		print("  方針%+d: 犠打%d 盗塁企図%d 先発の平均投球回%.2f" % [level, t["sh"], t["sb"] + t["cs"],
			starter_outs / 3.0 / starts])
	_check(totals[2]["sh"] > totals[1]["sh"] and totals[1]["sh"] > totals[0]["sh"],
			"送りバント：積極的なほど犠打が多い")
	_check(totals[2]["sb"] > totals[1]["sb"] and totals[1]["sb"] > totals[0]["sb"], "盗塁：積極的なほど企図が多い")
	_check(totals[2]["sp_ip"] < totals[1]["sp_ip"] and totals[1]["sp_ip"] < totals[0]["sp_ip"],
			"継投：継投重視なほど先発の投球回が短い")


func _best_farm(t: SimTeam, pitchers: bool) -> SimPlayer:
	var best: SimPlayer = null
	for p in t.players_where(false, pitchers):
		if p.is_foreign or p.is_ikusei or (pitchers and not p.has_pitching):
			continue
		var v := p.overall if pitchers else p.batting_value()
		if best == null or v > (best.overall if pitchers else best.batting_value()):
			best = p
	return best


func _in_lineup(t: SimTeam, p: SimPlayer) -> bool:
	for use_dh in [true, false]:
		for entry: Array in t.lineup(use_dh):
			if entry[0] == p:
				return true
	return false


func _lineup_ok(t: SimTeam, use_dh: bool) -> bool:
	var seen := {}
	for entry: Array in t.lineup(use_dh):
		if seen.has(entry[1]):
			return false
		seen[entry[1]] = true
		if entry[0] != null and not t.is_active(entry[0]):
			return false
	return seen.size() == 9


func _check(ok: bool, label: String) -> void:
	print("  [%s] %s" % ["OK" if ok else "NG", label])
	if not ok:
		_failures += 1
