extends SceneTree
## トレード交渉の確認（docs/AUTORUN.md 作業8。ヘッドレス可、約1分）。2008年の阪神で：
## - 新戦力の「トレード」タブ →「トレード交渉へ」で交渉の画面が開く
## - 相手の主力と自球団の控えの交換は★1つで断られる → 同じ日はもう交渉できない → 翌日はできる
## - 自球団の主力と相手の控え（＋金銭）の交換は成立する：所属・ペナントの編成・出来事に反映、日付を進めても試合が進む
## - 7月31日までは交渉できて、8月1日からはできない（画面の文言・ボタン・ハブの日付が追従）
## - オフ：表彰の段階はできない、FA・トレード・ポスティングでできる（FA宣言中の選手は出せない）、契約更改は締めてから、
##   オフの成立で支配下の人数が入れ替わる
## ウィンドウ付きで出力先を渡すと、交渉の画面（条件を入れた状態）と、ドラフトの候補一覧（表の野手能力）をスクショ。
##
##   godot --headless --path godot -s res://tests/trade_check.gd -- [出力先]

const USER := "阪神タイガース"
const PARTNER := "読売ジャイアンツ"
const PARTNER2 := "中日ドラゴンズ"

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node
var _hub: Node
var _view: Node


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_gs.new_game(USER, 2008)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	_hub = current_scene
	await _check_open()
	if _view != null:
		await _check_refused()
		await _check_success()
		await _check_deadline()
		await _check_offseason()
		await _shot_draft()
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("OK ", label)
	else:
		_failures += 1
		print("NG ", label)


func _check_open() -> void:
	print("== 新戦力 → トレード ==")
	_hub.call("_open_sub_screen", "scout")
	await _frames(2)
	var scout: Node = _hub.get("_scout_view")
	scout.set("current_tab", 0)
	var text: String = scout.get("_trade_label").text
	_check(text.contains("交渉できます"), "新戦力の「トレード」タブ：今日は交渉できる（%s）" % text.get_slice("\n", 4))
	scout.get("_trade_button").pressed.emit()
	await _frames(3)
	_view = _hub.get("_trade_view")
	_check(_hub.get("_open_key") == "trade" and _view.is_visible_in_tree(), "「トレード交渉へ」で交渉の画面が開く")


## 相手の主力と自球団の控えの交換は断られる
func _check_refused() -> void:
	print("== 断られる ==")
	_view.call("set_partner", PARTNER)
	_view.call("switch_tab", 2)  # 相手の投手
	var theirs: Array = _view.call("list_ids")
	_view.call("select_player", theirs[0])
	_view.call("switch_tab", -1)  # 自球団の野手
	var mine: Array = _view.call("list_ids")
	_view.call("select_player", mine[-1])
	await _frames(2)
	var est: Dictionary = _gs.trade_estimate(PARTNER, [mine[-1]], [theirs[0]], 0)
	_check(int(est["stars"]) == 1 and float(est["chance"]) == 0.0 and _view.call("action_enabled"),
		"巨人のエース（%s）と控え（%s）：★%d（成功率 %.2f）" % [_name(theirs[0]), _name(mine[-1]), est["stars"],
			est["chance"]])
	_view.call("press_action")
	await _frames(2)
	var league: RefCounted = _gs.league
	_check(league.team_of[theirs[0]] == PARTNER and league.team_of[mine[-1]] == USER
		and str(_view.call("status_text")).contains("断られ"), "断られて所属は変わらない（%s）" % _view.call("status_text"))
	_check(not _view.call("action_enabled") and _view.get("_odds_label").text.contains("断られ"),
		"同じ日はもう依頼できない（%s）" % _view.get("_odds_label").text)
	var again: Dictionary = _gs.trade_request(PARTNER, [mine[-1]], [theirs[0]], 0)
	_check(not again["ok"] and str(again["text"]).contains("今日はもう"), "同じ日に申し込んでも断られる（%s）" % again["text"])
	_gs.advance_through(_gs.day)
	_view.call("refresh")
	await _frames(2)
	_check(_view.call("action_enabled"), "翌日（%s）はもう一度依頼できる" % _gs.date_text())
	_view.call("clear_deal")


## 自球団の主力（＋金銭）と相手の控えの交換は成立する
func _check_success() -> void:
	print("== 成立 ==")
	_view.call("set_partner", PARTNER)
	_view.call("switch_tab", -1)  # 自球団の投手
	while _view.get("_tab") != "my_p":
		_view.call("switch_tab", 1)
	var mine: Array = _view.call("list_ids")
	var give: Array = [mine[0], mine[1]]
	for id: String in give:
		_view.call("select_player", id)
	_view.call("switch_tab", 3)  # 相手の野手
	var theirs: Array = _view.call("list_ids")
	var get_ids: Array = [theirs[-1]]
	_view.call("select_player", theirs[-1])
	_view.call("set_money", 5000)
	await _frames(2)
	var est: Dictionary = _gs.trade_estimate(PARTNER, give, get_ids, 5000)
	_check(int(est["stars"]) == 5, "主力2人＋5000万円と控え1人：★%d（成功率 %.2f）" % [est["stars"], est["chance"]])
	await _shot("trade_deal")
	_view.call("press_action")
	await _frames(2)
	var league: RefCounted = _gs.league
	var moved := true
	for id: String in give:
		moved = moved and league.team_of[id] == PARTNER and _gs.season.players[id]["team"] == PARTNER \
			and _gs.sim_team_of(PARTNER).by_id.has(id) and not _gs.my_team().by_id.has(id)
	moved = moved and league.team_of[get_ids[0]] == USER and _gs.my_team().by_id.has(get_ids[0])
	_check(moved, "成立：所属とペナントの編成が入れ替わる（%s）" % _view.call("status_text"))
	var logged := 0
	for e: Dictionary in league.events(2008, "trade"):
		if e["id"] in give or e["id"] in get_ids:
			logged += 1
	_check(logged == 3, "出来事に3人の移籍が残る（%d件）" % logged)
	_check((_view.call("give_ids") as Array).is_empty() and (_view.call("get_ids") as Array).is_empty(),
		"成立したら交渉の枠が空く")
	var before: int = _gs.games_played()
	_gs.advance_through(_gs.day + 14)
	_check(_gs.games_played() > before and _gs.my_team().by_id.has(get_ids[0]),
		"日付を進めても試合が進み、獲得した選手は自球団にいる（%s）" % _gs.date_text())


func _check_deadline() -> void:
	print("== 7月31日まで ==")
	var last: int = _gs.day
	while _gd_date(last + 1).substr(5) <= "07-31":
		last += 1
	_gs.advance_through(last - 1)  # 今日＝7月31日
	await _refresh_view()
	_check(_gs.trade_block_reason() == "" and str(_view.call("status_text")).contains("7月31日"),
		"7月31日は交渉できる（%s）" % _view.call("status_text"))
	_view.call("set_partner", PARTNER2)
	while _view.get("_tab") != "their_b":
		_view.call("switch_tab", 1)
	_view.call("select_player", (_view.call("list_ids") as Array)[-1])
	await _refresh_view()
	_check(_view.call("action_enabled"), "7月31日：依頼するを押せる")
	_gs.advance_through(_gs.day)  # 今日＝8月1日
	await _refresh_view()
	var month_text: String = _hub.get_node("%MonthLabel").text
	_check(not _gs.trade_block_reason().is_empty() and not _view.call("action_enabled")
		and str(_view.call("status_text")).contains("8月1日") and month_text.contains("8月1日"),
		"8月1日からは交渉できない（%s／ハブ %s）" % [_view.call("status_text"), month_text])
	var r: Dictionary = _gs.trade_request(PARTNER2, [], _view.call("get_ids"), 0)
	_check(not r["ok"], "8月1日に申し込んでも成立しない（%s）" % r["text"])
	_gs.advance_through(_gs.day + 40)
	_check(not _gs.trade_block_reason().is_empty(), "9月（%s）も交渉できない" % _gs.date_text())
	_view.call("clear_deal")


func _check_offseason() -> void:
	print("== オフ ==")
	_gs.advance_through(_gs.season_last_day())
	_check(_gs.phase == _gs.Phase.AWARDS and not _gs.trade_block_reason().is_empty(),
		"表彰の段階は交渉できない（%s）" % _gs.trade_block_reason())
	_gs.advance()
	_check(_gs.phase == _gs.Phase.FA_TRADE and _gs.trade_block_reason().is_empty(),
		"FA・トレード・ポスティングの段階は交渉できる（%s）" % _gs.phase_name())
	var f: RefCounted = _gs.fa()
	var excluded: Dictionary = _gs.trade_excluded()
	_check(f != null and excluded.size() == f.declared.size(), "FA宣言中の選手 %d人は交渉の対象外" % excluded.size())
	for id: String in excluded:
		var team: String = _gs.league.team_of.get(id, "")
		if team.is_empty() or team == USER:
			continue
		var err: String = _gs.trade_request(team, [], [id], 0)["text"]
		_check(err.contains("FA宣言中"), "FA宣言中の選手は獲れない（%s）" % err)
		break
	_gs.advance()
	_check(_gs.phase == _gs.Phase.CONTRACT and _gs.trade_block_reason().contains("契約更改"),
		"契約更改の途中は交渉できない（%s）" % _gs.trade_block_reason())
	_gs.contract_resolve()
	_check(_gs.trade_block_reason().is_empty(), "契約更改を締めたら交渉できる")
	# オフの成立：自球団の主力1人と相手の控え2人（支配下の人数が1人増える）
	var league: RefCounted = _gs.league
	var mine: Array = []
	for id: String in league.players_of(USER):
		if not _gd.player(id).get("is_pitcher", false):
			mine.append(id)
	mine.sort_custom(func(a: String, b: String) -> bool:
		return _value(a) > _value(b))
	var theirs: Array = league.players_of(PARTNER2)
	theirs.sort_custom(func(a: String, b: String) -> bool: return _value(a) < _value(b))
	var count_before: int = league.players_of(USER).size()
	var r: Dictionary = _gs.trade_request(PARTNER2, [mine[0]], [theirs[0], theirs[1]], 0)
	_check(r["ok"] and league.players_of(USER).size() == count_before + 1 and league.team_of[mine[0]] == PARTNER2,
		"オフの成立（%s、自球団 %d → %d人）" % [r["text"], count_before, league.players_of(USER).size()])
	_check((_gs.league.to_save() as Dictionary).has("trade_refused"), "断られた記録はセーブに入る")


## スクショ：ドラフトの候補一覧（表の野手能力のタブ。横幅の確認）
func _shot_draft() -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	_hub.call("_close_sub_screen")
	await _frames(2)
	_hub.call("_open_sub_screen", "draft")
	await _frames(2)
	var view: Node = _hub.get("_draft_view")
	view.call("finish_overlays")
	view.call("set_mode", "table")
	view.call("switch_tab", 2)
	view.call("set_sort", "hyouka", true)
	var ids: Array = view.call("list_ids")
	if not ids.is_empty():
		view.call("select_candidate", ids[0])
	await _shot("draft_first_year")


func _value(id: String) -> float:
	return load("res://sim/trade.gd").player_value(_gd.player(id), _gs.year, _gs.league.salary_of(id))


func _name(id: String) -> String:
	return str(_gs.league.names.get(id, id))


func _gd_date(day: int) -> String:
	return load("res://sim/season.gd").date_of_day(day)


## 画面で日付を進めたときと同じく changed を出して、ハブと交渉の画面を作り直す
func _refresh_view() -> void:
	_gs.changed.emit()
	_view.call("refresh")
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("  スクショ: %s.png" % name)
