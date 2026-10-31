extends SceneTree
## 史実との分岐ニュースの確認（docs/AUTORUN.md 作業24）。ヘッドレス可（約2分）。ウィンドウ付きで出力先を渡すとスクショも保存。
## 1) 史実の材料：2008年の順位（日程のスコアから。セ1位巨人・パ1位西武）、タイトル（本塁打王 村田・中村、首位打者 内川）
## 2) 2008年（巨人）を回す：リーグ優勝が史実と違えば速報、日本シリーズ号に史実との比較、表彰のあとオフ号にタイトルの違い、
##    ドラフトのあと自球団の指名と史実・各球団の1位の違い、春季キャンプで「2008年 史実との比較」の号（順位・優勝・日本一・移籍・ドラフト1位）。
##    ハブが春季キャンプでその号を開く。史実と違う球団にいる選手の選手詳細（経歴）に「史実の所属」
## 3) 2025年：史実で入団しなかった佐々木麟太郎を指名した球団があれば記事になる
##
##   godot --headless --path godot --script res://tests/history_check.gd -- [出力先]

var _out := ""
var _failures := 0
var _gs: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_check_materials()
	await _check_2008()
	_check_2025()
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_materials() -> void:
	print("\n-- 1) 史実の材料（2008年）--")
	_gs.new_game("読売ジャイアンツ", 2008)
	var hc: Object = _gs.history()
	var st: Dictionary = hc.hist_standings(2008)
	_check(st["C"][0]["team"] == "読売ジャイアンツ" and st["P"][0]["team"] == "埼玉西武ライオンズ",
		"史実の順位：セ1位 %s（%d勝）・パ1位 %s（%d勝）" % [st["C"][0]["team"], st["C"][0]["w"], st["P"][0]["team"],
			st["P"][0]["w"]])
	var titles: Dictionary = hc.hist_titles(2008)
	var hr_c := _title(titles["C"], "hr")
	var hr_p := _title(titles["P"], "hr")
	var avg_c := _title(titles["C"], "avg")
	_check(hr_c.contains("村田") and hr_p.contains("中村") and avg_c.contains("内川"),
		"史実のタイトル：セ本塁打王 %s・パ本塁打王 %s・セ首位打者 %s" % [hr_c, hr_p, avg_c])
	_check(hc.hist_champion(2008, "js") == "埼玉西武ライオンズ", "史実の日本一（2008年 西武）")


func _title(list: Array, key: String) -> String:
	for t: Dictionary in list:
		if t["key"] == key:
			var names: Array[String] = []
			for w: Dictionary in t["winners"]:
				names.append("%s %s" % [w["name"], t["value_text"]])
			return "・".join(names)
	return ""


func _check_2008() -> void:
	print("\n-- 2) 2008年（巨人）--")
	_gs.new_game("読売ジャイアンツ", 2008)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await process_frame
	await process_frame
	var hub: Node = current_scene
	_gs.advance_through(_gs.season_last_day(), true)
	var news: Object = _gs.news
	for lg: String in ["C", "P"]:
		var team: String = _gs.pennant_race[lg].get("team", "")
		var hist: String = _gs.history().hist_champion(2008, lg)
		var found := false
		for a: Dictionary in news.of_kind("divergence", 2008):
			if a["flash"] and team in a["teams"] and hist in a["teams"]:
				found = true
		_check(found == (team != hist), "%s 優勝 %s（史実 %s）→ 史実と違うときだけ速報（%s）" % [lg, team, hist, found])
	_gs.postseason_play_all()
	var js_div := _in_issue(news, "2008-js", "divergence")
	_check(not js_div.is_empty(), "日本シリーズ号に史実との比較：%s" % js_div)
	_gs.advance()
	_check(_gs.phase == _gs.Phase.AWARDS, "表彰へ")
	var titles_div := _in_issue(news, "2008-off", "divergence")
	_check(not titles_div.is_empty() and titles_div.contains("タイトル"), "オフ号にタイトルの違い：%s" % titles_div)
	var guard := 0
	while _gs.phase != _gs.Phase.CAMP and guard < 12:
		hub.call("_on_menu_chosen", "advance")
		await process_frame
		if hub.get("_open_key") == "draft":
			# ドラフトはおまかせで終え、画面を閉じてから可変ボタン（春季キャンプへ）
			_gs.draft_resolve()
			hub.call("_close_sub_screen")
		elif hub.get("_open_key") in ["fa", "contract", "release", "awards", "trade"]:
			_gs.advance()
			hub.call("_close_sub_screen")
		guard += 1
	_check(_gs.phase == _gs.Phase.CAMP and _gs.year == 2009, "春季キャンプへ（%s）" % _gs.date_text())
	var draft_items: Array[String] = []
	for a: Dictionary in news.of_issue("2008-off"):
		if a["kind"] == "divergence" and a["headline"].contains("ドラフト"):
			draft_items.append(a["headline"])
	_check(not draft_items.is_empty(), "オフ号にドラフトの違い：%s" % [draft_items])
	var summary: Array = news.of_issue("2008-history")
	_check(summary.size() >= 1 and summary[0]["kind"] == "history" and summary[0]["body"].contains("【日本一】")
		and summary[0]["body"].contains("【セ・リーグ順位】"), "「2008年 史実との比較」の号：%s" % (
			summary[0]["headline"] if not summary.is_empty() else "なし"))
	if not summary.is_empty():
		for line: String in summary[0]["body"].split("\n"):
			print("      ", line)
	_check(hub.get("_open_key") == "news" and hub.get("_news_view").current_issue() == "2008-history",
		"春季キャンプでハブが史実との比較の号を開く")
	if _out != "":
		await _shot("history_summary.png")
	var tl: Dictionary = _gs.history().transfer_lines()
	_check(int(tl["others_total"]) + tl["mine_kept"].size() + tl["mine_lost"].size() > 0,
		"史実と所属が違う選手（他 %d人・自球団に残った %d人・出た %d人）" % [tl["others_total"], tl["mine_kept"].size(),
			tl["mine_lost"].size()])
	# 選手詳細の経歴に「史実の所属」
	var pid := ""
	for p: Dictionary in _gs.get_node("/root/GameData").ratings["players"]:
		var hist: String = str(p.get("hist_team", ""))
		if not hist.is_empty() and not str(p.get("team", "")).is_empty() and hist != p["team"] \
				and not hist.begins_with("横浜") and not str(p["team"]).begins_with("横浜"):
			pid = p["id"]
			break
	if pid.is_empty():
		_check(true, "（史実と所属が違う選手がいないので選手詳細は飛ばす）")
	else:
		var detail: Node = load("res://scenes/player_detail/player_detail.gd").open(hub, pid, [])
		await process_frame
		detail.show_tab(2)
		await process_frame
		await process_frame
		var text := _all_text(detail)
		_check(text.contains("史実の所属"), "選手詳細の経歴に史実の所属（%s）" % _gs.get_node("/root/GameData").player(pid)["name"])
		detail.close()
		await process_frame


func _check_2025() -> void:
	print("\n-- 3) 2025年ドラフト --")
	_gs.new_game("福岡ソフトバンクホークス", 2025)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	var d: Object = _gs.draft()
	var target := ""
	for c: Dictionary in d.candidates:
		if c["name"].replace(" ", "") == "佐々木麟太郎":
			target = c["id"]
	_check(not target.is_empty(), "2025年の候補に佐々木麟太郎")
	if target.is_empty():
		return
	d.user_bid(target)
	_gs.draft_resolve()
	var c: Dictionary = d.by_id[target]
	_gs.advance()
	var found := ""
	for a: Dictionary in _gs.news.of_kind("divergence", 2025):
		if target in a["players"] and a["headline"].contains("入団しなかった"):
			found = a["headline"]
	_check(str(c["picked_by"]).is_empty() == found.is_empty(), "指名 %s %s → 記事：%s" % [c["picked_by"], c["pick_label"],
		found])


## 号の中のその種類の記事の見出し（無ければ空）
func _in_issue(news: Object, key: String, kind: String) -> String:
	for a: Dictionary in news.of_issue(key):
		if a["kind"] == kind:
			return a["headline"]
	return ""


func _all_text(node: Node) -> String:
	var text := ""
	if node is Label:
		text += (node as Label).text + "\n"
	for c in node.get_children():
		text += _all_text(c)
	return text


func _shot(file_name: String) -> void:
	await create_timer(0.5).timeout
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(file_name))
	print("スクショ: ", _out.path_join(file_name))


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print(("OK  " if ok else "NG  ") + label)
