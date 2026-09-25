extends SceneTree
## 画面の確認用：球団を選んでハブを開き、日程表で日付を選んで早送り → 途中で中止 → 1日進める を行い、
## そのあと月を進めながら日程表・采配・ハブのスクリーンショットを保存する。
##
##   xvfb-run godot --path godot --script res://tests/ui_capture.gd -- <出力先ディレクトリ> [球団名]
##
## 出力: ff_*.png（早送りの各段階）/ hub_<日付>.png / schedule_<日付>.png / roster_<日付>.png

var _out := ""
var _team := "阪神タイガース"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	if args.size() > 1:
		_team = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	var game_data: Node = root.get_node("GameData")
	var game_state: Node = root.get_node("GameState")
	game_data.load_ratings(2008, "pre")
	game_state.new_game(_team)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(5)
	var hub := current_scene
	await _shot("hub_start")
	await _fast_forward_steps(hub, game_state)
	for step in 12:
		var label := "%s_%s" % [game_state.year, game_state.month_text()]
		hub.call("_open_sub_screen", "schedule")
		await _frames(3)
		await _shot("schedule_" + label)
		if step == 0 or step == 4 or game_state.phase != game_state.Phase.SEASON:
			hub.call("_open_sub_screen", "tactics")
			var tactics: Node = hub.get_node("%TacticsView")
			tactics.call("_show_page", "list")
			var roster: TabContainer = tactics.get("_roster")
			for tab in roster.get_tab_count():
				roster.current_tab = tab
				await _frames(3)
				await _shot("roster_%s_%d" % [label, tab])
			roster.current_tab = 0
		hub.call("_close_sub_screen")
		await _frames(2)
		await _shot("hub_" + label)
		if game_state.phase != game_state.Phase.SEASON:
			break
		var t := Time.get_ticks_msec()
		game_state.advance()
		var elapsed := Time.get_ticks_msec() - t
		print("advance -> %s %s (%d ms)" % [game_state.year, game_state.month_text(), elapsed])
		await _frames(3)
	quit()


## 日程表から：4月30日を選ぶ → 早送り → 4月8日の終了後に中止 → 1日進める → 1週間進める
func _fast_forward_steps(hub: Node, game_state: Node) -> void:
	hub.call("_open_sub_screen", "schedule")
	var view: Node = hub.get_node("%ScheduleView")
	await _frames(3)
	await _shot("ff_1_open")
	view.set("_selected_day", Season.day_number("2008-04-30"))
	view.call("_render")
	await _frames(2)
	await _shot("ff_2_selected")
	view.call("_on_fast_forward_to_selected")
	var stop_at := Season.day_number("2008-04-08")
	while game_state.is_fast_forwarding() and game_state.day <= stop_at:
		await process_frame
	await _frames(1)
	await _shot("ff_3_running")
	game_state.stop_fast_forward()
	await _frames(3)
	await _shot("ff_4_stopped")
	view.set("_selected_day", game_state.day + 1)
	view.call("_render")
	await _frames(2)
	await _shot("ff_4b_select_tomorrow")
	view.call("_on_advance_days", 1)
	while game_state.is_fast_forwarding():
		await process_frame
	await _frames(3)
	await _shot("ff_5_one_day")
	view.call("_on_advance_days", 7)
	while game_state.is_fast_forwarding():
		await process_frame
	await _frames(3)
	await _shot("ff_6_one_week")
	hub.call("_close_sub_screen")
	await _frames(3)
	await _shot("ff_7_hub")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(_out.path_join(name + ".png"))
	print("saved ", name)
