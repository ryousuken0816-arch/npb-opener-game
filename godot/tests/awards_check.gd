extends SceneTree
## 表彰（オフの「シーズン終了・表彰」）の確認（ヘッドレス）。2008年・2009年を最後まで回して次を調べる：
## - 各リーグで MVP・新人王が1人、ベストナインが位置ごと（セ9人・パ10人）、GGが9人、沢村賞は0〜1人
## - タイトルの受賞者が成績の1位と一致（規定打席・規定投球回は試合数×3.1・×1.0）
## - 新人王の受賞者に資格がある（入団5年以内・前年までの1軍60打席・30回以内・外国人でない）
## - 翌年も前の年の表彰が残る、選手の受賞歴が引ける、セーブ→ロードで残る
## - 表彰の画面（AwardsView）が開いてエラーが出ない
##
##   godot --headless --path godot --script res://tests/awards_check.gd -- [自球団] [スクショの出力先]
## 出力先を渡してウィンドウ付きで流すと各タブを撮る（--position で画面の隅に置き、フォーカスを奪わない）

var _team := "読売ジャイアンツ"
var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_team = args[0]
	if args.size() > 1:
		_out = args[1]
		DirAccess.make_dir_recursive_absolute(_out)
		# ウィンドウ付きで撮るときも前面に出さない（CLAUDE.md「ローカルでテスト・スクショを撮るときの絶対ルール」）
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_gs.new_game(_team)
	for y in [2008, 2009]:
		_gs.advance_through(_gs.season_last_day())
		_check(_gs.phase == _gs.Phase.AWARDS, "%d年 シーズン終了・表彰へ" % y)
		var res: Dictionary = _gs.awards_of(y)
		_check(not res.is_empty(), "%d年の表彰がある" % y)
		_print_awards(res)
		_check_awards(y, res)
		await _check_view(y)
		if y == 2008:
			_skip_to_next_season()
	# 翌年も前の年が残る・受賞歴
	_check(_gs.awards_history.has("2008") and _gs.awards_history.has("2009"), "2008・2009年の表彰が両方残る")
	var mvp: Dictionary = _gs.awards_of(2008)["leagues"]["C"]["mvp"]
	var hist: Array = _gs.player_awards(mvp["id"])
	_check(hist.any(func(e: Dictionary) -> bool: return e["year"] == 2008 and e["name"] == "MVP"),
			"2008年セMVP %s の受賞歴にMVPがある（%s）" % [mvp["name"], str(hist)])
	_check(_gs.stats_history.has("2008") and _gs.stats_history["2008"]["batting"].size() > 200,
			"2008年の成績が履歴に残る（打者%d人）" % _gs.stats_history.get("2008", {}).get("batting", {}).size())
	# セーブ→ロード
	var text := JSON.stringify(_gs.to_save())
	var loaded: Dictionary = SaveUtil.ints(JSON.parse_string(text))
	_gs.new_game("阪神タイガース")
	_check(_gs.awards_history.is_empty(), "新しく始めると表彰の履歴は空")
	_gs.load_state(loaded)
	_check(_gs.awards_history.size() == 2 and _gs.awards_of(2008)["leagues"]["C"]["mvp"]["id"] == mvp["id"],
			"ロードで表彰の履歴が戻る")
	_check(_gs.first_year == 2008, "ロードで開始年が戻る")
	print("\n%s" % ("全項目OK" if _failures == 0 else "NG %d件" % _failures))
	quit(1 if _failures > 0 else 0)


func _skip_to_next_season() -> void:
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()


func _check_awards(y: int, res: Dictionary) -> void:
	var season: Season = _gs.season
	var awarded := 0
	for lg: String in ["C", "P"]:
		var a: Dictionary = res["leagues"][lg]
		_check(a["mvp"] is Dictionary, "%d年 %s MVP" % [y, lg])
		_check(a["rookie"] is Dictionary, "%d年 %s 新人王" % [y, lg])
		if a["rookie"] is Dictionary:
			_check(_gs.is_rookie(a["rookie"]["id"]), "%d年 %s 新人王 %s に資格がある" % [y, lg, a["rookie"]["name"]])
		var want_nine := 10 if lg == "P" else 9
		_check(a["best_nine"].size() == want_nine, "%d年 %s ベストナイン %d人（%d）" % [y, lg, want_nine, a["best_nine"].size()])
		_check(a["gold_glove"].size() == 9, "%d年 %s GG 9人（%d）" % [y, lg, a["gold_glove"].size()])
		var ids := {}
		for e: Dictionary in a["best_nine"]:
			_check(not ids.has(e["id"]), "ベストナインに同じ選手が2回いない: " + e["name"])
			ids[e["id"]] = true
			_check(season.leagues.get(e["team"], "") == lg, "ベストナインは同じリーグの選手: " + e["name"])
		for t: Dictionary in a["titles"]:
			# 最高勝率は13勝以上の投手がいなければ該当者なし（史実でもある）
			_check(not t["winners"].is_empty() or t["key"] == "pct", "%d年 %s %s に受賞者がいる" % [y, lg, t["name"]])
			awarded += t["winners"].size()
			_check_title_top(lg, t)
	if res["sawamura"] is Dictionary:
		_check(Awards.sawamura_met(season.pitching[res["sawamura"]["id"]]) >= Awards.SAWAMURA_MIN_MET, "沢村賞の基準")
	print("  タイトルの受賞者 のべ%d人" % awarded)


## タイトルの受賞者が、そのリーグの資格のある選手の中で1位（独自に計算し直して比べる）
func _check_title_top(lg: String, t: Dictionary) -> void:
	var season: Season = _gs.season
	var key: String = t["key"]
	var batting: bool = t["kind"] == "b"
	var src: Dictionary = season.batting if batting else season.pitching
	var best := -INF
	for id: String in src:
		var team: String = season.players[id]["team"]
		if season.leagues.get(team, "") != lg:
			continue
		var rec: Dictionary = season.records[team]
		var games: int = rec["w"] + rec["l"] + rec["d"]
		var s: Dictionary = src[id]
		var v := 0.0
		match key:
			"avg":
				if s["pa"] < games * 3.1:
					continue
				v = Season.batting_avg(s)
			"obp":
				if s["pa"] < games * 3.1:
					continue
				v = Awards.obp(s)
			"era":
				if s["outs"] < games * 3:
					continue
				v = -Season.era(s)
			"pct":
				if s.get("w", 0) < 13:
					continue
				v = Awards.win_pct(s)
			"hp":
				v = s.get("hld", 0) + maxi(s.get("w", 0) - mini(s.get("w", 0), s.get("gs", 0)), 0)
			_:
				v = s.get(key, 0)
		best = maxf(best, v)
	for e: Dictionary in t["winners"]:
		var s: Dictionary = src[e["id"]]
		var got := 0.0
		match key:
			"avg":
				got = Season.batting_avg(s)
			"obp":
				got = Awards.obp(s)
			"era":
				got = -Season.era(s)
			"pct":
				got = Awards.win_pct(s)
			"hp":
				got = s.get("hld", 0) + maxi(s.get("w", 0) - mini(s.get("w", 0), s.get("gs", 0)), 0)
			_:
				got = s.get(key, 0)
		_check(is_equal_approx(got, best), "%s %s の %s が1位（%s / 1位 %s）" % [lg, e["name"], t["name"], got, best])


func _print_awards(res: Dictionary) -> void:
	print("\n=== %d年 表彰" % res["year"])
	for lg: String in ["C", "P"]:
		var a: Dictionary = res["leagues"][lg]
		print("[%s] MVP %s / 新人王 %s" % [lg, _who(a["mvp"]), _who(a["rookie"])])
		var nine: Array[String] = []
		for e: Dictionary in a["best_nine"]:
			nine.append("%s %s" % [Awards.pos_label(e["pos"]), e["name"]])
		print("  ベストナイン：", "、".join(nine))
		var gg: Array[String] = []
		for e: Dictionary in a["gold_glove"]:
			gg.append("%s %s" % [Awards.pos_label(e["pos"]), e["name"]])
		print("  GG：", "、".join(gg))
		for t: Dictionary in a["titles"]:
			var names: Array[String] = []
			for e: Dictionary in t["winners"]:
				names.append(e["name"])
			print("  %s %s（%s）" % [t["name"], "・".join(names), t["value_text"]])
	print("沢村賞 ", _who(res["sawamura"]))


static func _who(e: Variant) -> String:
	if not (e is Dictionary):
		return "該当者なし"
	return "%s（%s）%s" % [e["name"], e["team"], e["text"]]


## ハブを開き、可変ボタン（表彰式）で表彰の画面が開いてタブを全部見られる（エラーが出ない）。2回目の可変ボタンは次の段階へ
func _check_view(y: int) -> void:
	_check(_gs.awards_pending and _gs.button_text() == "表彰式", "%d年：可変ボタンは「表彰式」（%s）" % [y, _gs.button_text()])
	var hub: Control = load("res://scenes/hub/hub.tscn").instantiate()
	root.add_child(hub)
	await process_frame
	hub.call("_on_menu_chosen", "advance")
	await process_frame
	var view: Control = hub.get("_awards_view")
	_check(hub.get("_open_key") == "awards" and view.visible, "%d年：可変ボタンで表彰の画面が開く" % y)
	_check(view.call("shown_year") == y, "%d年：表彰の画面に今年の表彰" % y)
	var tabs: Array = view.get("TABS")
	for i in tabs.size():
		hub.call("_unhandled_input", _tab_event())
		await process_frame
		var tags := 0
		for c: Node in view.find_children("*", "NameTag", true, false):
			tags += 1
		_check(tags > 0, "%d年：タブ「%s」に名前札がある" % [y, view.get("_tab")])
		await _capture(hub, "awards_%d_%s" % [y, view.get("_tab")])
	_check(not _gs.awards_pending and _gs.button_text() != "表彰式", "%d年：表彰を見たら可変ボタンは次の段階へ（%s）" % [y, _gs.button_text()])
	hub.queue_free()
	await process_frame


## 画面をはみ出す部品がないか（右端が 1280 の内側、下端が下の帯より上）を調べ、出力先があればスクショ
func _capture(hub: Control, file_name: String) -> void:
	var view: Control = hub.get("_awards_view")
	# 画面（1280x720）の内側で、下の帯（説明・日付）より上
	var bar: Control = hub.get_node("%BottomBar")
	var limit := Rect2(Vector2.ZERO, Vector2(1280, bar.get_global_rect().position.y)).grow(1.0)
	var over: Array[String] = []
	for c: Node in view.find_children("*", "Control", true, false):
		var ctrl := c as Control
		if ctrl.is_visible_in_tree() and not limit.encloses(ctrl.get_global_rect()):
			over.append("%s%s" % [ctrl.name, ctrl.get_global_rect()])
	_check(over.is_empty(), "%s：画面からはみ出さない %s" % [file_name, " ".join(over.slice(0, 3))])
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(_out.path_join(file_name + ".png"))


static func _tab_event() -> InputEvent:
	var e := InputEventAction.new()
	e.action = "ui_tab_next"
	e.pressed = true
	return e


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("NG ", label)
