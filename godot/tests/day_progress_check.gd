extends SceneTree
## 日単位の進行の確認（ヘッドレス）：日付を指定して早送り → 途中で中止 → 1日ずつ → 月単位（試合へ）→
## 最終日まで早送りしてオフへ → 翌年の開幕〜オフ。各段階で日程・順位表・個人成績が今日の日付と矛盾しないか調べる。
##
##   godot --headless --path godot --script res://tests/day_progress_check.gd -- [球団名]

var _team := "阪神タイガース"
var _failures := 0
var _gs: Node
var _months_started: Array[int] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_team = args[0]
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gs.month_started.connect(func(m: int) -> void: _months_started.append(m))
	_gs.new_game(_team)
	var season: Season = _gs.season
	_check(season != null, "2008年の日程が読み込まれている")
	_check(_gs.day == season.first_day(), "開幕日から始まる: " + _gs.date_text())
	_check(_gs.event_text() == "開幕戦", "開幕日のイベント名は開幕戦")
	_verify("開幕時")

	# 4月30日まで早送り → 4月10日を過ぎたら中止
	var target := Season.day_number("2008-04-30")
	var stop_at := Season.day_number("2008-04-10")
	_gs.start_fast_forward(target)
	_check(_gs.is_fast_forwarding(), "早送りが始まる")
	while _gs.is_fast_forwarding() and _gs.day <= stop_at:
		await process_frame
	_gs.stop_fast_forward()
	var stopped_day: int = _gs.day
	_check(stopped_day == stop_at + 1, "4月10日の終了で止まった（今日=%s）" % _gs.date_text())
	for i in 20:
		await process_frame
	_check(_gs.day == stopped_day, "中止後は進まない")
	_verify("早送り中止後")

	# 1日ずつ3日
	for i in 3:
		var before: int = _gs.day
		var played_before := season.played_count()
		var todays := 0
		for g: Dictionary in season.games_on(Season.date_of_day(before)):
			if g["status"] == "played":
				todays += 1
		_gs.start_fast_forward(before)
		while _gs.is_fast_forwarding():
			await process_frame
		_check(_gs.day == before + 1, "1日進める: %s" % _gs.date_text())
		_check(season.played_count() == played_before + todays,
				"その日の%d試合だけ行った" % todays)
		_verify("1日進めた後")

	# 1週間（7日）
	var week_start: int = _gs.day
	_gs.start_fast_forward(week_start + 6)
	while _gs.is_fast_forwarding():
		await process_frame
	_check(_gs.day == week_start + 7, "1週間進める: %s" % _gs.date_text())
	_verify("1週間進めた後")

	# ハブの「試合へ」（今月の残り）→ 5月1日
	_gs.advance()
	_check(_gs.date_text() == "2008年 5月1日", "試合へで翌月1日へ: " + _gs.date_text())
	_verify("試合へ（4月）の後")

	# 月をまたいで最終日まで早送り → シーズン終了（表彰）へ
	var t0 := Time.get_ticks_msec()
	_gs.start_fast_forward(season.last_day())
	while _gs.is_fast_forwarding():
		await process_frame
	print("最終日までの早送り: %.1f 秒" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_check(_gs.phase == _gs.Phase.POSTSEASON, "最終日のあとはポストシーズンへ（%s）" % _gs.phase_name())
	_check(season.is_finished() and season.played_count() == season.scheduled_count(),
			"全%d試合を消化" % season.scheduled_count())
	for team: String in season.records:
		var rec := season.record_of(team)
		_check(rec["w"] + rec["l"] + rec["d"] == 144, "%s 144試合" % team)
	_check(_months_started == [4, 5, 6, 7, 8, 9, 10], "月替わりの通知: %s" % [_months_started])
	_verify("シーズン終了後")

	# ポストシーズン：1日ずつ進めると日付が追従し、公式戦の成績は変わらない。試合へで日本一まで → 表彰へ
	var ps_day: int = _gs.day
	_gs.start_fast_forward(ps_day)
	while _gs.is_fast_forwarding():
		await process_frame
	_check(_gs.day == ps_day + 1 and _gs.date_text() == "2008年 " + _gs.month_text(),
			"ポストシーズンの1日: " + _gs.date_text())
	var ps_guard := 0
	while _gs.phase == _gs.Phase.POSTSEASON and not _gs.postseason_done() and ps_guard < 10:
		_gs.advance()
		ps_guard += 1
		print("  ポストシーズン 試合へ → ", _gs.date_text(), " ", _gs.event_text())
	_check(_gs.postseason_done() and not _gs.postseason.champion.is_empty(),
			"日本一: " + _gs.postseason.champion)
	_check(_gs.button_text() == "表彰へ", "日本一のあとは可変ボタンが表彰へ: " + _gs.button_text())
	_verify("ポストシーズンの後")
	_gs.advance()
	_check(_gs.phase == _gs.Phase.AWARDS, "表彰へ進む（%s）" % _gs.phase_name())

	# オフ → 翌年（2009年）の開幕 → 3日進める → 試合へを繰り返してオフ
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	_check(_gs.year == 2009 and _gs.phase == _gs.Phase.SEASON, "翌年の開幕: " + _gs.date_text())
	_gs.start_fast_forward(_gs.day + 2)
	while _gs.is_fast_forwarding():
		await process_frame
	print("2009年: 3日進めた → ", _gs.date_text())
	var guard := 0
	while _gs.phase == _gs.Phase.SEASON and guard < 20:
		_gs.advance()
		guard += 1
		print("  試合へ → ", _gs.date_text())
	_check(_gs.phase == _gs.Phase.POSTSEASON, "2009年もポストシーズンまで進む")
	while _gs.phase == _gs.Phase.POSTSEASON and guard < 40:
		_gs.advance()
		guard += 1
	_check(_gs.phase == _gs.Phase.AWARDS, "2009年もオフまで進む")

	print("NG %d 件" % _failures if _failures > 0 else "すべてOK")
	quit(1 if _failures > 0 else 0)


## 今日（GameState.day）より前の試合はすべて終了、今日以降は未実施。順位表・個人成績の合計も試合数と一致
func _verify(label: String) -> void:
	var season: Season = _gs.season
	var today: int = _gs.day if _gs.phase == _gs.Phase.SEASON else season.last_day() + 1
	var bad := 0
	var played := 0
	for g: Dictionary in season.games:
		var done: bool = not g["result"].is_empty()
		if g["status"] == "played" and done != (g["day"] < today):
			bad += 1
		if done:
			played += 1
	_check(bad == 0, "%s: 今日より前の試合だけ終了している（不一致 %d）" % [label, bad])
	var w := 0
	var l := 0
	var total := 0
	for team: String in season.records:
		var rec: Dictionary = season.records[team]
		w += rec["w"]
		l += rec["l"]
		total += rec["w"] + rec["l"] + rec["d"]
	_check(w == l and total == played * 2, "%s: 順位表の勝敗の合計が試合数と一致（%d試合）" % [label, played])
	var own := season.record_of(_team)
	_check(own["w"] == _gs.wins and own["l"] == _gs.losses and own["d"] == _gs.draws,
			"%s: 自球団の成績 %s" % [label, _gs.record_text()])
	# 打撃成績：各試合の両軍の打者の打席合計＝通算成績の打席合計
	var pa := 0
	for g: Dictionary in season.games:
		if g["result"].is_empty():
			continue
		for side in 2:
			for line: Dictionary in g["result"]["batting"][side]:
				pa += line.get("pa", 0)
	var pa_total := 0
	for id: String in season.batting:
		pa_total += season.batting[id].get("pa", 0)
	_check(pa == pa_total and (played == 0 or pa > 0), "%s: 個人成績の打席合計 %d" % [label, pa_total])
	var rows: Array[Dictionary] = _gs.standings("C")
	print("  [%s] %s 試合%d  セ首位 %s %d勝%d敗" % [
		label, _gs.date_text(), played, rows[0]["team"], rows[0]["wins"], rows[0]["losses"]])


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
	print(("  OK " if ok else "  NG ") + message)
