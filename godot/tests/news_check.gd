extends SceneTree
## 新聞・速報の確認（docs/AUTORUN.md 作業25）。ヘッドレス可（約1分）。ウィンドウ付きで出力先を渡すとスクショも保存。
## 2008年（阪神）をハブの「試合へ」で1か月ずつ進める：
## - 月替わりに新聞の号が出る（3月は試合が少ないので「3・4月号」）。号の日付＝翌月1日、ハブの日付と一致。首位争い・月間MVP（両リーグ）・自球団の記事
## - 「試合へ」のあとハブが新しい号を開く。右下のニュースの札に最新の見出し。タブ（LB/RB）で速報・自球団の話題、選手名の札から選手詳細
## - 通算の節目を越えた選手は全員、速報の記事がある（史実の通算＋今季の成績から数え直して照合）。ノーヒットノーラン・サイクル安打も記事に
## - マジック点灯・優勝決定の速報、公式戦の最終号、日本シリーズ号。速報はハブの帯に出る
## - セーブ→ロードで記事・号が元どおり。翌年も新聞が続く
##
##   godot --headless --path godot --script res://tests/news_check.gd -- [出力先]

const USER := "阪神タイガース"

var _out := ""
var _failures := 0
var _gs: Node
var _sg: GDScript
var _hub: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_sg = load("res://scripts/save_game.gd")
	_sg.set("dir", "user://test_saves")
	_sg.set("autosave_enabled", false)
	_gs.new_game(USER, 2008)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await process_frame
	await process_frame
	_hub = current_scene
	var tickers: Array[String] = []
	_gs.news_posted.connect(func(a: Dictionary) -> void: tickers.append(a["headline"]))
	var news: Object = _gs.news
	var saved_count := -1
	# 公式戦：試合へで1か月ずつ
	var guard := 0
	while _gs.phase == _gs.Phase.SEASON and guard < 12:
		var before_issues: int = news.issues.size()
		_hub.call("_on_menu_chosen", "advance")
		await process_frame
		guard += 1
		if _gs.phase != _gs.Phase.SEASON:
			break
		if news.issues.size() == before_issues:
			print("    （%s：号なし＝翌月とまとめる）" % _gs.date_text())
			continue
		var issue: Dictionary = news.issues[-1]
		var items: Array = news.of_issue(issue["key"])
		var kinds := {}
		for a: Dictionary in items:
			kinds[a["kind"]] = int(kinds.get(a["kind"], 0)) + 1
		var ok: bool = issue["date"] == _gs.season.date_of_day(_gs.day) and int(kinds.get("race", 0)) == 2 \
			and int(kinds.get("mvp", 0)) == 2 and int(kinds.get("team", 0)) == 1
		_check(ok, "%s（%s）：%d本 %s" % [issue["title"], _gs.date_text(), items.size(), JSON.stringify(kinds)])
		_check(_hub.get("_open_key") == "news" and _hub.get("_news_view").current_issue() == issue["key"],
			"試合へのあとハブが新しい号を開く")
		for a: Dictionary in items.slice(0, 3):
			print("      ", a["headline"])
		if issue["key"] == "2008-06" and _out != "":
			await _shot("news_paper.png")
		if issue["key"] == "2008-06":
			# 6月号のあとでセーブ
			_check(str(_sg.call("save", "slot1")).is_empty(), "6月号のあとでセーブ")
			saved_count = news.articles.size()
		_hub.call("_close_sub_screen")
		await process_frame
		if issue["key"] == "2008-06" and _out != "":
			# ハブ：右下のニュースの札と上端の速報の帯
			_hub.get("_ticker").push({"headline": "%s（試し）" % news.latest(1)[0]["headline"], "mine": true})
			await _shot("news_hub.png")
	_hub.call("_close_sub_screen")
	await process_frame
	_check(news.get_issue("2008-04").get("title", "") == "2008年 3・4月号", "3月は4月とまとめて「3・4月号」")
	_check(_gs.phase == _gs.Phase.POSTSEASON and not news.get_issue("2008-10").is_empty()
		and news.get_issue("2008-10")["title"].contains("最終号"), "公式戦の最後に最終号")
	# 速報
	var flashes: Array = news.latest(400, "", true)
	var kinds := {}
	for a: Dictionary in flashes:
		kinds[a["kind"]] = int(kinds.get(a["kind"], 0)) + 1
	_check(int(kinds.get("pennant", 0)) == 2, "優勝決定の速報が両リーグ：%s" % JSON.stringify(kinds))
	_check(int(kinds.get("race", 0)) >= 1, "マジック点灯の速報")
	_check(tickers.size() >= flashes.size() - 1, "速報がハブの帯へ（%d件）" % tickers.size())
	_check_milestones(news)
	_check_feats(news)
	# 右下のニュースの札・タブ
	var card: Button = _hub.get("_news_card")
	_check(card.visible and not (_hub.get("_news_lines")[0] as Label).text.is_empty(),
		"ハブの右下のニュース：%s" % (_hub.get("_news_lines")[0] as Label).text)
	card.pressed.emit()
	await process_frame
	var view: Node = _hub.get("_news_view")
	_check(_hub.get("_open_key") == "news", "ニュースの札で新聞の画面")
	view.switch_tab(1)
	await process_frame
	_check(view.get("_tab") == "flash", "LB/RB で速報のタブ")
	view.switch_tab(1)
	await process_frame
	_check(view.get("_tab") == "mine", "自球団の話題のタブ")
	_hub.call("_close_sub_screen")
	# ポストシーズン → 日本シリーズ号
	_gs.postseason_play_all()
	var js_issue: Dictionary = news.get_issue("2008-js")
	_check(not js_issue.is_empty() and news.of_issue("2008-js").size() >= 3, "日本シリーズ号：%s" % (
		news.of_issue("2008-js")[0]["headline"] if not js_issue.is_empty() else "なし"))
	var ps_flash := 0
	for a: Dictionary in news.latest(400, "postseason", true):
		ps_flash += 1
	_check(ps_flash == 5, "シリーズの勝ち抜けの速報 5件（%d）" % ps_flash)
	# ロード
	var error: String = _sg.call("load_slot", "slot1")
	await process_frame
	_check(error.is_empty() and _gs.news.articles.size() == saved_count and _gs.news.issues[-1]["key"] == "2008-06",
		"ロードで記事・号が元どおり（%d件）" % _gs.news.articles.size())
	# 翌年も続く
	_gs.new_game(USER, 2008)
	_gs.advance_through(_gs.season_last_day())
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	_gs.advance()
	_gs.advance()
	_check(not _gs.news.get_issue("2009-04").is_empty(), "2009年も新聞が出る（%s）" % _gs.news.issues[-1]["title"])
	for slot: String in _sg.call("all_slots"):
		_sg.call("delete", slot)
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


## 通算の節目を越えた選手は全員、記録達成の速報がある
func _check_milestones(news: Object) -> void:
	var desk: Object = _gs.desk()
	var season: Object = _gs.season
	var expected := 0
	var found := 0
	var heads: Array[String] = []
	for kind: String in ["b", "p"]:
		var src: Dictionary = season.batting if kind == "b" else season.pitching
		for id: String in src:
			var before: Dictionary = desk.career_before(id, kind)
			for m: Array in desk.MILESTONES[kind]:
				var b0 := int(before.get(m[0], 0))
				var b1 := b0 + int(src[id].get(m[0], 0))
				for mark: int in m[2]:
					if b0 < mark and b1 >= mark:
						expected += 1
						var title := "通算%d%s" % [mark, m[1]]
						for a: Dictionary in news.of_kind("milestone", 2008):
							if a["flash"] and id in a["players"] and a["headline"].contains(title):
								found += 1
								heads.append(a["headline"])
								break
	_check(expected == found, "通算の節目 %d件すべて速報（%d件）%s" % [expected, found, heads.slice(0, 4)])


func _check_feats(news: Object) -> void:
	var season: Object = _gs.season
	var team_of := func(id: String) -> String: return season.players.get(id, {}).get("team", "")
	var feats: Array = load("res://sim/records.gd").feats(season.games, season.player_name, team_of)
	_check(news.of_kind("feat", 2008).size() == feats.size(), "ノーヒットノーラン・サイクル安打 %d件すべて記事" % feats.size())


func _shot(file_name: String) -> void:
	await create_timer(0.5).timeout
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(file_name))
	print("スクショ: ", _out.path_join(file_name))


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print(("OK  " if ok else "NG  ") + label)
