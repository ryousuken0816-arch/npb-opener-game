extends SceneTree
## 大事なニュースで早送りを止める（docs/AUTORUN.md 作業35）の確認。ヘッドレス可（約1分）。ウィンドウ付きで出力先を渡すとスクショ（news_stop）。
## - テストのスクリプトの中・自動処理（skip_to_phase）では止めない（既存のテストが止まらない）
## - 日程表で開幕から9月30日まで早送り：アマ球界の号の日（3/31・6/15・7/28・8/23）で止まり、その号を開く。ハブの日付が追従。
##   Ⓑはまず「続ける」へ、「続ける」で日程表に戻って早送りの続き、「ここで止める」で日程表に戻って止まったまま
## - ハブの「試合へ」：7月の途中（都市対抗号）で止まり、「続ける」で月末まで進んで7月号を開く
## - 設定：止めない → 止まらない、すべて → 月ごとの新聞でも止まる。システムの画面の切り替え・種類ごと、セーブ→ロードで残る
##
##   godot --headless --path godot --script res://tests/news_stop_check.gd -- [出力先]

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
	_sg.set("dir", "res://.godot/test_saves_news_stop")
	_sg.set("autosave_enabled", false)
	_gs.new_game(USER, 2008)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await process_frame
	await process_frame
	_hub = current_scene
	# テストの中は既定で止めない（ハブの「試合へ」・すぐドラフトへ）
	_check(not _gs.news_stop_on() and _gs.news_stop_preset() == "important", "テストの中は止めない・初期値は大事なものだけ")
	_gs.advance_through(_day("2008-06-10"))
	_hub.call("_on_menu_chosen", "advance")
	await process_frame
	_check(_gs.news_stop.is_empty() and _gs.date_text() == "2008年 7月1日", "テストの中は「試合へ」で止まらない（%s）" % _gs.date_text())
	_hub.call("_close_sub_screen")
	_gs.news_stop_override = 1
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	_check(_gs.news_stop.is_empty() and _gs.amateur_news_done.has("2008-fall"), "すぐドラフトへでは止まらない")
	# 早送りはテストから1日ずつ進める（フレームの時間で勝手に進まないように）
	_gs.set_process(false)

	await _schedule_run()
	await _hub_run()
	await _setting_runs()
	await _settings_view()
	for slot: String in _sg.call("all_slots"):
		_sg.call("delete", slot)
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


## 日程表で開幕から9月30日まで早送り（大事なものだけ）
func _schedule_run() -> void:
	_gs.new_game(USER, 2008)
	_gs.news_stop_override = 1
	await process_frame
	_hub.call("_open_sub_screen", "schedule")
	var view: Node = _hub.get("_news_view")
	var target := _day("2008-09-30")
	_gs.start_fast_forward(target)
	var amateur_dates: Array[String] = []
	var stops := 0
	var halted := false
	var shot := false
	var guard := 0
	while guard < 400:
		guard += 1
		if not _gs.is_fast_forwarding():
			break
		_gs.call("_process", _gs.FAST_FORWARD_INTERVAL)
		await process_frame
		if _hub.get("_stop").is_empty():
			continue
		stops += 1
		var stop: Dictionary = _hub.get("_stop")
		var kinds: Array = []
		for r: Dictionary in stop["reasons"]:
			kinds.append(r["kind"])
		var date: String = _gs.season.date_of_day(_gs.day)
		var ok: bool = _hub.get("_open_key") == "news" and view.stop_shown() and not _gs.is_fast_forwarding() \
			and _hub.get("_stop_return") == "schedule" and int(stop["resume_to"]) in [target, -1]
		_check(ok and (_hub.get("_month_label") as Label).text == _gs.month_text(),
			"%s 止まってニュースを開く %s：%s" % [_gs.month_text(), str(kinds), stop["reasons"][0]["headline"]])
		if "amateur" in kinds:
			amateur_dates.append(date.substr(5))
			_check(str(view.current_issue()).contains("-amateur-") and view.get("_tab") == "paper",
				"アマ球界の号を開く（%s）" % view.current_issue())
		else:
			_check(view.get("_tab") == "flash", "速報だけのときは速報のタブ")
		if date == "2008-06-15" and not shot:
			shot = true
			if _out != "":
				await _shot("news_stop.png")
			# Ⓑはまず「続ける」へ
			_hub.call("_on_back")
			await process_frame
			_check(_hub.get("_open_key") == "news" and root.gui_get_focus_owner() == view.get("_resume_button"),
				"Ⓑでまず「続ける」にフォーカス")
		if date == "2008-07-28" and not halted:
			halted = true
			view.get("_halt_button").pressed.emit()
			await process_frame
			_check(_hub.get("_open_key") == "schedule" and not _gs.is_fast_forwarding() and _gs.day == _day(date)
				and _gs.news_stop.is_empty(), "「ここで止める」で日程表に戻って止まる（%s）" % _gs.date_text())
			_gs.start_fast_forward(target)
			continue
		if int(stop["resume_to"]) < 0:
			_hub.call("_on_back")
			await process_frame
			_check(_hub.get("_open_key") == "schedule", "最後の日：Ⓑで日程表に戻る")
			continue
		view.get("_resume_button").pressed.emit()
		await process_frame
		_check(_hub.get("_open_key") == "schedule" and _gs.is_fast_forwarding() and _gs.fast_forward_target == target,
			"「続ける」で日程表の早送りの続き")
	_check(amateur_dates == ["03-31", "04-10", "06-15", "06-30", "07-28", "08-23", "08-31", "09-30"], "候補紹介号と大会結果号の日で止まる：%s（止まった回数 %d）" % [
		str(amateur_dates), stops])
	_check(_gs.day == target + 1 and _hub.get("_stop").is_empty(), "目標の日まで進む（%s）" % _gs.date_text())
	_hub.call("_close_sub_screen")


## ハブの「試合へ」：7月の途中で止まり、続けると月末まで進んで7月号を開く
func _hub_run() -> void:
	_gs.new_game(USER, 2008)
	_gs.news_stop_override = 1
	_gs.advance_through(_day("2008-06-30"))
	await process_frame
	_hub.call("_on_menu_chosen", "advance")
	await process_frame
	var stop: Dictionary = _hub.get("_stop")
	var view: Node = _hub.get("_news_view")
	var amateur := false
	var guard := 0
	while not stop.is_empty() and guard < 40:
		guard += 1
		_check(stop["mode"] == "hub" and _hub.get("_open_key") == "news" and _gs.month == 7,
			"試合へ：%s で止まる（%s）" % [_gs.month_text(), stop["reasons"][0]["headline"]])
		if view.current_issue() == "2008-amateur-shakai":
			# 後日の速報タブにも直前に読んだ号のキーが残る。確認済みの結果を上書きしない。
			amateur = amateur or _gs.season.date_of_day(_gs.day) == "2008-07-28"
		view.get("_resume_button").pressed.emit()
		await process_frame
		stop = _hub.get("_stop")
	_check(amateur, "試合へで都市対抗号（7/28）で止まる")
	_check(_gs.date_text() == "2008年 8月1日" and _hub.get("_open_key") == "news" and view.current_issue() == "2008-07"
		and not view.stop_shown(), "続けると月末まで進んで7月号を開く（%s）" % _gs.date_text())
	_hub.call("_close_sub_screen")


## 設定：止めない → 止まらない、すべて → 月ごとの新聞で止まる
func _setting_runs() -> void:
	_gs.new_game(USER, 2008)
	_gs.news_stop_override = 1
	_gs.advance_through(_day("2008-06-10"))
	_gs.set_news_stop_preset("none")
	await process_frame
	_hub.call("_open_sub_screen", "schedule")
	_gs.start_fast_forward(_day("2008-06-20"))
	await _drive()
	_check(_gs.day == _day("2008-06-21") and _hub.get("_open_key") == "schedule" and _hub.get("_stop").is_empty()
		and not _gs.news.get_issue("2008-amateur-college").is_empty(), "止めない：号は出ても止まらない（%s）" % _gs.date_text())
	_gs.set_news_stop_preset("all")
	_check(_gs.news_stop_preset() == "all", "すべて")
	_gs.start_fast_forward(_day("2008-07-05"))
	var guard := 0
	var monthly := false
	while _gs.is_fast_forwarding() and guard < 40:
		guard += 1
		await _drive()
		var stop: Dictionary = _hub.get("_stop")
		if stop.is_empty():
			break
		for r: Dictionary in stop["reasons"]:
			if r["kind"] == "monthly" and r["issue"] == "2008-06":
				monthly = _hub.get("_news_view").current_issue() == "2008-06"
		_hub.get("_news_view").get("_resume_button").pressed.emit()
		await process_frame
	_check(monthly, "すべて：月ごとの新聞（6月号）で止まって開く")
	_hub.call("_close_sub_screen")


## 早送りが止まるまで1日ずつ進める
func _drive() -> void:
	var guard := 0
	while _gs.is_fast_forwarding() and guard < 200:
		guard += 1
		_gs.call("_process", _gs.FAST_FORWARD_INTERVAL)
	await process_frame


## システムの画面：まとめた選び方の切り替え・種類ごと、セーブ→ロードで残る、枠に収まる
func _settings_view() -> void:
	_gs.set_news_stop_preset("important")
	_hub.call("_open_sub_screen", "system")
	await process_frame
	var sv: Node = _hub.get("_save_view")
	var preset: Button = sv.get("_stop_preset_button")
	_check(preset.text == "大事なものだけ", "システム：%s" % preset.text)
	preset.pressed.emit()
	_check(_gs.news_stop_preset() == "all" and preset.text == "すべて", "押すと すべて")
	preset.pressed.emit()
	_check(_gs.news_stop_preset() == "none" and preset.text == "止めない", "押すと 止めない")
	await process_frame
	await process_frame
	_check(_fits(sv), "設定の行が枠に収まる")
	var detail: Button = sv.get("_stop_detail_button")
	detail.button_pressed = true
	await process_frame
	var buttons: Dictionary = sv.get("_stop_kind_buttons")
	var kinds: int = _gs.NEWS_STOP_KINDS.size()
	_check(sv.get("_stop_kinds_box").visible and not sv.get("_slot_buttons")["slot1"].visible and buttons.size() == kinds,
		"種類ごと：%d種類のボタン（枠の札は隠す）" % kinds)
	buttons["amateur"].button_pressed = true
	buttons["series"].button_pressed = true
	await process_frame
	await process_frame
	_check(_gs.news_stop_kinds["amateur"] and _gs.news_stop_kinds["series"] and not _gs.news_stop_kinds["mine"]
		and preset.text == "種類ごと", "種類ごとにオン：%s" % preset.text)
	_check(_fits(sv), "種類ごとのボタンが枠に収まる")
	_check(sv.back() and not sv.get("_stop_kinds_box").visible and sv.get("_slot_buttons")["slot1"].visible, "Ⓑで種類ごとを閉じる")
	_check(str(_sg.call("save", "slot1")).is_empty(), "セーブ")
	_gs.set_news_stop_preset("important")
	var error: String = _sg.call("load_slot", "slot1")
	_check(error.is_empty() and _gs.news_stop_preset() == "custom" and _gs.news_stop_kinds["series"]
		and not _gs.news_stop_kinds["pennant"], "ロードで止めるニュースの設定が戻る")
	_hub.call("_close_sub_screen")


## 見えている Control がサブ画面の枠に収まる（中身がスクロールにならない。layout_fit_check と同じ物差し）
func _fits(view: Control) -> bool:
	var frame: Rect2 = (_hub.get("_sub_screen") as Control).get_global_rect().grow(1.0)
	var fit: ScrollContainer = (_hub.get("_sub_screen") as Control).get_node("Fit")
	var ok := not fit.get_v_scroll_bar().visible and not fit.get_h_scroll_bar().visible
	if not ok:
		print("    スクロールになる：中身の最小 %s" % (fit.get_child(0) as Control).get_combined_minimum_size())
	for c: Node in view.find_children("*", "Control", true, false):
		var ctl := c as Control
		# 配置の枠（フォーカスの演出で少し拡大した分は数えない）
		var parent := ctl.get_parent() as Control
		var r := Rect2(parent.global_position + ctl.position, ctl.size) if parent != null else ctl.get_global_rect()
		if ctl.is_visible_in_tree() and not frame.encloses(r):
			print("    はみ出し：%s %s" % [ctl.name, r])
			ok = false
	return ok


func _day(date: String) -> int:
	return _gs.season.day_number(date)


func _shot(file_name: String) -> void:
	await create_timer(0.5).timeout
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(file_name))
	print("スクショ: ", _out.path_join(file_name))


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print(("OK  " if ok else "NG  ") + label)
