extends SceneTree
## 記録室の確認（ヘッドレス）。2008年を最後まで回し、2009年の6月末まで進めて次を調べる：
## - セイバー指標：各リーグで wRC+ の打席で重み付けた平均がほぼ100（±1）、OPS+ もほぼ100（±6）
## - ランキングの1位が成績の1位と一致（打率は規定打席以上、本塁打・防御率・奪三振）
## - 通算＝ゲーム開始前の史実＋2008年＋2009年（今季）
## - デプス：自球団の全守備位置に選手がいる、正選手が先、12球団のチームの位置ランクがそろう、有望株の印が付く選手がいる
## - 画面：ハブの「記録室」で全タブを開いてエラーが出ない・右にはみ出さない、通算・全員・リーグの切り替え・並び替え、
##   守備位置ランクの球団名からデプスへ、2008年の表彰の歴代・達成記録・ドラフトの年の切り替え
##
##   godot --headless --path godot --script res://tests/records_check.gd -- [自球団] [スクショの出力先]
## 出力先を渡してウィンドウ付きで流すと各タブを撮る（--position で画面の隅に置き、フォーカスを奪わない）

var _team := "読売ジャイアンツ"
var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node
## オートロードを参照するクラスは型として書かずに読み込む（テストのスクリプトはオートロードより先にコンパイルされるため）
var _depth: GDScript


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_team = args[0]
	if args.size() > 1:
		_out = args[1]
		DirAccess.make_dir_recursive_absolute(_out)
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_depth = load("res://sim/depth.gd")
	_gs.new_game(_team)
	_gs.advance_through(_gs.season_last_day())
	_check(_gs.phase == _gs.Phase.AWARDS, "2008年 シーズン終了")
	_check_sabr(2008)
	_check_depth()
	# 2009年の6月末まで
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	_gs.advance_through(Season.day_number("2009-06-30"))
	_check(_gs.records_years() == [2008, 2009], "記録室の年は2008・2009（%s）" % str(_gs.records_years()))
	_check_sabr(2009)
	await _check_ui()
	print("\n%s" % ("全項目OK" if _failures == 0 else "NG %d件" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_sabr(y: int) -> void:
	var st: Dictionary = _gs.season_stats(y)
	for lg: String in ["C", "P"]:
		var league_of := func(id: String) -> String:
			return st["leagues"].get(st["players"].get(id, {}).get("team", ""), "")
		var c := Records.coefficients(st["batting"], st["pitching"], league_of, lg)
		var pa := 0.0
		var wrc := 0.0
		var ops := 0.0
		for id: String in st["batting"]:
			if league_of.call(id) != lg:
				continue
			var b: Dictionary = st["batting"][id]
			if int(b.get("pa", 0)) <= 0:
				continue
			var r := Records.batting_row(b, c)
			pa += float(b["pa"])
			wrc += float(r["wrc_plus"]) * float(b["pa"])
			ops += float(r["ops_plus"]) * float(b["pa"])
		var wrc_avg := wrc / pa
		var ops_avg := ops / pa
		print("%d年 %s：wRC+ 平均 %.1f・OPS+ 平均 %.1f・wOBA %.3f（スケール %.2f）・FIP定数 %.2f・1勝 %.1f点" % [
			y, lg, wrc_avg, ops_avg, c["lg_woba"], c["woba_scale"], c["fip_const"], c["runs_per_win"]])
		_check(absf(wrc_avg - 100.0) <= 1.0, "%d年 %s：wRC+ の平均がほぼ100（%.1f）" % [y, lg, wrc_avg])
		_check(absf(ops_avg - 100.0) <= 6.0, "%d年 %s：OPS+ の平均がほぼ100（%.1f）" % [y, lg, ops_avg])
		# 投手：FIP のアウトで重み付けた平均＝リーグの防御率
		var outs := 0.0
		var fip := 0.0
		var war_b := 0.0
		var war_p := 0.0
		for id: String in st["pitching"]:
			if league_of.call(id) != lg:
				continue
			var p: Dictionary = st["pitching"][id]
			if int(p.get("outs", 0)) <= 0:
				continue
			var r := Records.pitching_row(p, c)
			outs += float(p["outs"])
			fip += float(r["fip"]) * float(p["outs"])
			war_p += float(r["war"])
		for id: String in st["batting"]:
			if league_of.call(id) == lg and int(st["batting"][id].get("pa", 0)) > 0:
				war_b += float(Records.batting_row(st["batting"][id], c)["war"])
		_check(absf(fip / outs - float(c["lg_era"])) < 0.02, "%d年 %s：FIP の平均＝リーグの防御率（%.2f / %.2f）" % [
			y, lg, fip / outs, c["lg_era"]])
		print("  WAR 合計：野手 %.1f・投手 %.1f" % [war_b, war_p])


func _check_depth() -> void:
	var depth: Dictionary = _gs.depth_of(_team)
	for pos: String in _depth.POSITIONS:
		var list: Array = depth[pos]
		_check(not list.is_empty(), "デプス：%s に選手がいる" % pos)
		if list.size() > 1 and list.any(func(e: Dictionary) -> bool: return e["regular"]):
			_check(list[0]["regular"], "デプス：%s の先頭は正選手" % pos)
		var names: Array[String] = []
		for e: Dictionary in list.slice(0, 4):
			names.append("%s(%s→%s,%d歳)" % [e["name"], e["now_rank"], e["future_rank"], e["age"]])
		print("  %s：%s" % [pos, "、".join(names)])
	var prospects := 0
	var lines: Array[String] = []
	for team: String in _gd.teams():
		var d: Dictionary = _gs.depth_of(team)
		var ranks: Dictionary = _depth.team_ranks(d)
		var parts: Array[String] = []
		for pos: String in _depth.POSITIONS:
			_check(ranks[pos].has("now_rank") and ranks[pos].has("future_rank"), "%s %s のランク" % [team, pos])
			parts.append("%s%s%s" % [_depth.POS_SHORT[pos], ranks[pos]["now_rank"], ranks[pos]["future_rank"]])
		for pos: String in d:
			for e: Dictionary in d[pos]:
				if e["prospect"]:
					prospects += 1
		lines.append("%s %s" % [_gd.short_name(team), " ".join(parts)])
	print("  位置ランク（現在・将来）：\n    " + "\n    ".join(lines))
	_check(prospects > 0, "有望株の印が付く若手がいる（%d人）" % prospects)
	# 史実の大物の若手は将来性が高い（2008年の田中将大・坂本勇人・中田翔）
	for pair: Array in [["田中 将大", "東北楽天ゴールデンイーグルス"], ["坂本 勇人", "読売ジャイアンツ"]]:
		var d: Dictionary = _gs.depth_of(pair[1])
		for pos: String in d:
			for e: Dictionary in d[pos]:
				if e["name"] == pair[0]:
					_check(_depth.rank_index(e["future_rank"]) <= _depth.rank_index("B"),
							"%sの将来性はB以上（%s）" % [pair[0], e["future_rank"]])


func _check_ui() -> void:
	var hub: Control = load("res://scenes/hub/hub.tscn").instantiate()
	root.add_child(hub)
	await process_frame
	hub.call("_on_menu_chosen", "records")
	await process_frame
	var view: Control = hub.get("_records_view")
	_check(hub.get("_open_key") == "records" and view.visible, "ハブの「記録室」で記録室が開く")
	_check(view.call("shown_year") == 2009, "最初は今季（2009年）")
	# 打撃：規定到達の打率順の1位
	var st: Dictionary = _gs.season_stats(2009)
	var ids: Array = view.call("list_ids")
	_check(not ids.is_empty(), "打撃成績のランキングに選手がいる")
	if not ids.is_empty():
		var best := -1.0
		for id: String in st["batting"]:
			var b: Dictionary = st["batting"][id]
			var team: String = st["players"][id]["team"]
			var rec: Dictionary = st["records"][team]
			if float(b["pa"]) >= (rec["w"] + rec["l"] + rec["d"]) * 3.1:
				best = maxf(best, Season.batting_avg(b))
		_check(is_equal_approx(Season.batting_avg(st["batting"][ids[0]]), best), "打率1位が規定打席以上の最高打率（%.3f）" % best)
	await _capture(hub, "records_bat")
	# 並び替え：本塁打
	_set_sort(view, "bat", "hr")
	ids = view.call("list_ids")
	var max_hr := 0
	for id: String in st["batting"]:
		max_hr = maxi(max_hr, int(st["batting"][id].get("hr", 0)))
	_check(not ids.is_empty() and int(st["batting"][ids[0]].get("hr", 0)) == max_hr, "本塁打順の1位（%d本）" % max_hr)
	# 全員・通算
	view.set("_qualified", false)
	view.set("_career", true)
	view.call("refresh")
	ids = view.call("list_ids")
	_check(not ids.is_empty(), "通算・全員のランキング")
	if not ids.is_empty():
		var id: String = ids[0]
		var base: Dictionary = _gs.career_base()["batting"].get(id, {})
		var want := int(base.get("hr", 0)) + int(_gs.season_stats(2008)["batting"].get(id, {}).get("hr", 0)) \
			+ int(st["batting"].get(id, {}).get("hr", 0))
		var got := -1
		for r: Dictionary in view.call("_ranking_rows", false):
			if r["id"] == id:
				got = int(r["row"]["hr"])
		print("  通算本塁打1位：%s %d本（史実%d＋2008年＋2009年）" % [_gs.league.names.get(id, id), want, int(base.get("hr", 0))])
		_check(got == want, "通算＝史実＋ゲーム内（表示 %d / 計算 %d）" % [got, want])
	view.set("_career", false)
	view.set("_qualified", true)
	view.set("_league", "P")
	# 全タブ
	var tabs: Array = view.get("TABS")
	for i in tabs.size():
		hub.call("_unhandled_input", _tab_event())
		await process_frame
		var tab: String = view.call("current_tab")
		await _capture(hub, "records_" + tab)
	_check(view.call("current_tab") == "bat", "全タブを回って打撃成績に戻る")
	# 投手：防御率1位（パ・規定）
	view.call("set_tab", "pit")
	ids = view.call("list_ids")
	_check(view.call("shown_year") == 2009, "全タブを回っても年は2009年のまま")
	var best_era := 99.0
	for id: String in st["pitching"]:
		var p: Dictionary = st["pitching"][id]
		var team: String = st["players"][id]["team"]
		var rec: Dictionary = st["records"][team]
		if st["leagues"][team] == "P" and int(p["outs"]) >= (rec["w"] + rec["l"] + rec["d"]) * 3:
			best_era = minf(best_era, Season.era(p))
	_check(not ids.is_empty() and is_equal_approx(Season.era(st["pitching"][ids[0]]), best_era),
			"パの防御率1位（%.2f / 表示の1位 %s %.2f）" % [best_era, _gs.league.names.get(ids[0], "") if not ids.is_empty() else "",
				Season.era(st["pitching"][ids[0]]) if not ids.is_empty() else 0.0])
	# 守備位置ランク → デプス
	view.call("set_tab", "pos_rank")
	view.call("set_team", "阪神タイガース")
	_check(view.call("current_tab") == "depth" and view.get("_team") == "阪神タイガース", "守備位置ランクから阪神のデプスへ")
	for key: String in ["future", "age"]:
		view.set("_depth_sort", key)
		view.call("refresh")
		await process_frame
	# 表彰の歴代（2008年）・ドラフト・達成記録
	view.set("_awards_year", 2008)
	view.call("set_tab", "awards")
	_check(view.get("_awards_view").call("shown_year") == 2008, "表彰の歴代に2008年")
	view.set("_year", 2008)
	view.call("set_tab", "history")
	view.set("_dr_year", 2008)
	view.call("set_tab", "drafts")
	_check(not view.call("list_ids").is_empty(), "2008年のドラフトの指名が出る（歴代ドラフト）")
	view.call("set_tab", "members")
	_check(not view.call("list_ids").is_empty(), "歴代メンバーに今季の選手が出る")
	await _capture(hub, "records_history_2008")
	hub.queue_free()
	await process_frame


func _set_sort(view: Control, tab: String, key: String) -> void:
	var sort: Dictionary = view.get("_sort")
	sort[tab] = [key, true]
	view.call("refresh")


## 右にはみ出す部品がないか（スクロールの中は下に伸びてよい）を調べ、出力先があればスクショ
func _capture(hub: Control, file_name: String) -> void:
	await process_frame
	var view: Control = hub.get("_records_view")
	var bar: Control = hub.get_node("%BottomBar")
	var over: Array[String] = []
	for c: Node in view.find_children("*", "Control", true, false):
		var ctrl := c as Control
		if not ctrl.is_visible_in_tree():
			continue
		var r := ctrl.get_global_rect()
		var in_scroll := false
		var n: Node = ctrl.get_parent()
		while n != null and n != view:
			if n is ScrollContainer:
				in_scroll = true
			n = n.get_parent()
		if r.end.x > 1281.0 or (not in_scroll and r.end.y > bar.get_global_rect().position.y + 1.0):
			over.append("%s%s" % [ctrl.name, r])
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
