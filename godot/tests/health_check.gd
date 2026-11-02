extends SceneTree
## 調子・故障（作業45）の確認（ヘッドレス）：
## 1年回して故障の人数・全治の日数がそれらしいか、CPU球団の1軍に故障者がいないか、自球団の故障者は試合に出ないか、
## 日付を進めると全治の日数が減るか、抹消と入れ替え、調子の波が成績に出るか、ニュース、セーブ／ロードで一致するか。
##
##   godot --headless --path godot --script res://tests/health_check.gd

var _failures := 0
var _gs: Node
var _team := "阪神タイガース"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gs.new_game(_team, 2008)
	var season: Season = _gs.season
	var h: Health = _gs.health
	_check(h != null, "故障・調子の状態がある")

	# 調子は全員に付き、散らばっている
	_gs.advance_through(_gs.day)
	var levels := {}
	for t: SimTeam in season.teams.values():
		for p in t.players:
			levels[p.form] = int(levels.get(p.form, 0)) + 1
	print("  開幕の調子の分布: ", levels)
	_check(levels.size() == 5, "調子が5段階に散らばる")

	# 5月1日まで進め、故障者を1人見つけて1日進めると残りの日数が減る
	_gs.advance_through(Season.day_number("2008-04-30"))
	var some_id := ""
	for id: String in h.injuries:
		if h.days_left(id, _gs.day) > 3:
			some_id = id
			break
	_check(not some_id.is_empty(), "4月までに故障者が出ている（%d人）" % h.injuries.size())
	if not some_id.is_empty():
		var before := h.days_left(some_id, _gs.day)
		_gs.advance_through(_gs.day)
		_check(h.days_left(some_id, _gs.day) == before - 1, "1日進めると全治までの日数が減る（%d → %d）" % [
			before, h.days_left(some_id, _gs.day)])

	# CPU球団の1軍に故障者はいない
	var cpu_bad := 0
	for t: SimTeam in season.teams.values():
		if t.name == _team:
			continue
		cpu_bad += t.injured_active().size()
	_check(cpu_bad == 0, "CPU球団の1軍に故障者がいない（%d人）" % cpu_bad)

	# 自球団：主力を故障させると速報、今日の試合に出ない、抹消して入れ替えられる
	var mine: SimTeam = _gs.my_team()
	var star: SimPlayer = mine.lineup(false)[3][0]
	var flashes := 0
	var on_flash := func(a: Dictionary) -> void:
		if a["kind"] == "injury":
			flashes += 1
	_gs.news_posted.connect(on_flash)
	var inj := h.injure(star, mine, _gs.day, 20)
	_check(inj["key"] and star.injured, "%sを故障させる（主力：%s）" % [star.name, inj["part"]])
	_check(_gs.injured_on_first().has(star), "自球団の1軍の故障者として出る（抹消を促す）")
	var today := Season.date_of_day(_gs.day)
	_gs.advance_through(_gs.day)
	var played_star := false
	var my_games := 0
	for g: Dictionary in season.games_on(today):
		if g["result"].is_empty() or not (g["home"] == _team or g["away"] == _team):
			continue
		my_games += 1
		for side in 2:
			for line: Dictionary in g["result"]["batting"][side]:
				if line["id"] == star.id:
					played_star = true
	_check(my_games == 0 or not played_star, "故障中の%sは試合に出ない（自球団の試合 %d）" % [star.name, my_games])
	_check(not mine.promote_error(star, _gs.day).is_empty() or mine.is_active(star), "故障中は1軍に上げられない")
	var swapped: Array = _gs.swap_out_injured()
	_check(not mine.is_active(star) and not swapped.is_empty() and swapped[0][1] != null,
		"抹消して2軍から代わりを上げる（%s）" % (swapped[0][1].name if not swapped.is_empty() and swapped[0][1] != null else "-"))
	_check(not mine.promote_error(star, _gs.day + 1).is_empty(), "2軍に落とした故障者は上げられない：" +
		mine.promote_error(star, _gs.day + 1))

	# セーブ／ロード：故障・調子が一致し、続きも同じになる
	var saved: Variant = _norm(_gs.to_save())
	var h_before := JSON.stringify(_norm(h.to_save()))
	_gs.advance_through(_gs.day + 6)
	var direct := JSON.stringify(_norm(_gs.health.to_save()))
	var direct_record: String = _gs.record_text()
	_gs.load_state(saved)
	_check(JSON.stringify(_norm(_gs.health.to_save())) == h_before, "ロードで故障・調子が一致")
	_check(_gs.my_team().by_id[star.id].injured, "ロード後も%sは故障中" % star.name)
	_gs.advance_through(_gs.day + 6)
	_check(JSON.stringify(_norm(_gs.health.to_save())) == direct and _gs.record_text() == direct_record,
		"ロードして7日進めると、そのまま進めたときと一致（%s）" % direct_record)

	# 1年回す
	h = _gs.health
	season = _gs.season
	var t0 := Time.get_ticks_msec()
	_gs.advance_through(_gs.season_last_day(), true)
	print("  シーズンの残り（%d ms）" % (Time.get_ticks_msec() - t0))
	var total := h.summary()
	var counts: Array = []
	var too_few := 0
	var too_many := 0
	for t: String in season.teams:
		var s := h.summary(t)
		counts.append("%s %d" % [root.get_node("GameData").short_name(t), s["count"]])
		if s["count"] < 2:
			too_few += 1
		if s["count"] > 30:
			too_many += 1
	var long_n := 0
	var first_n := 0
	for e: Dictionary in h.log:
		if int(e["until"]) - int(e["start"]) >= 60:
			long_n += 1
		if e.get("first", false):
			first_n += 1
	print("  球団ごとの故障: ", ", ".join(counts))
	print("  合計 %d人（うち1軍 %d、全治60日以上 %d）・平均の全治 %.1f日" % [total["count"], first_n, long_n,
		total["avg_days"]])
	var per_team: float = total["count"] / 12.0
	_check(per_team >= 5.0 and per_team <= 18.0 and too_few == 0 and too_many == 0,
		"1球団で年に数人〜十数人（平均 %.1f人）" % per_team)
	_check(total["avg_days"] >= 15.0 and total["avg_days"] <= 55.0, "平均の全治 %.1f日" % total["avg_days"])
	_check(long_n > 0, "長期の離脱もある（%d人）" % long_n)
	# CPU球団の主力は治ったら1軍に戻る（シーズンの終わりの15日より前に治った選手）
	var back := 0
	var should := 0
	var cpu_bad_end := 0
	for e: Dictionary in h.log:
		var t: SimTeam = season.teams.get(e["team"])
		if e["team"] == _team or not e["key"] or int(e["until"]) > _gs.season_last_day() - 15 or t == null:
			continue
		if not t.by_id.has(e["id"]) or h.is_injured(e["id"]):
			continue
		should += 1
		if t.is_active(t.by_id[e["id"]]):
			back += 1
	for t: SimTeam in season.teams.values():
		if t.name != _team:
			cpu_bad_end += t.injured_active().size()
	_check(should > 0 and back >= should * 0.8, "CPU球団の主力は治ると1軍に戻る（%d／%d人）" % [back, should])
	_check(cpu_bad_end == 0, "シーズンの終わりもCPU球団の1軍に故障者がいない（%d人）" % cpu_bad_end)
	var inj_news: Array = _gs.news.of_kind("injury", 2008)
	var cpu_long := inj_news.filter(func(a: Dictionary) -> bool: return not a["mine"] and a["flash"])
	_check(not inj_news.is_empty() and not cpu_long.is_empty(),
		"故障のニュース %d本（他球団の長期離脱の速報 %d本）。例：%s" % [inj_news.size(), cpu_long.size(),
			inj_news[0]["headline"] if not inj_news.is_empty() else "-"])
	_check(_gs._stop_kind_of(cpu_long[0], "") == "injury" if not cpu_long.is_empty() else false,
		"他球団の長期離脱は早送りを止める種類「injury」")

	_check_form_effect(season)
	print("ALL OK" if _failures == 0 else "NG %d件" % _failures)
	quit(1 if _failures > 0 else 0)


## 調子の効き方：同じ2球団で、両方の打者を絶好調・投手を絶不調にしたときと逆のときで得点を比べる
func _check_form_effect(season: Season) -> void:
	var a: SimTeam = season.teams[_team]
	var b: SimTeam = season.teams["読売ジャイアンツ"]
	var runs := {}
	for lv in [2, -2]:
		for t in [a, b]:
			for p in t.players:
				p.injured = false
				p.form = lv if not p.is_pitcher else -lv
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var total := 0
		for i in 300:
			var res := GameSim.new(a, b, 1000 + i * 7, true, rng).play()
			total += int(res["home_score"]) + int(res["away_score"])
		runs[lv] = total / 300.0
	var ratio: float = runs[2] / runs[-2]
	print("  1試合の両チームの得点：打者絶好調 %.2f / 打者絶不調 %.2f（%.2f倍）" % [runs[2], runs[-2], ratio])
	_check(ratio > 1.15 and ratio < 2.2, "調子の波が成績に出る（打者・投手とも振り切ったとき %.2f倍）" % ratio)
	for t in [a, b]:
		for p in t.players:
			p.form = 0


func _norm(v: Variant) -> Variant:
	return SaveUtil.ints(JSON.parse_string(JSON.stringify(v, "", false, true)))


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
	print(("  OK " if ok else "  NG ") + message)
