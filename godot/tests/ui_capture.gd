extends SceneTree
## 画面の確認用：球団を選んでハブを開き、日程表・采配を表示しながら月を進めてスクリーンショットを保存する。
##
##   xvfb-run godot --path godot --script res://tests/ui_capture.gd -- <出力先ディレクトリ> [球団名]
##
## 出力: hub_<月>.png / schedule_<月>.png / roster_<月>.png（オフに入ったら off_*.png）

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
	for step in 12:
		var label := "%s_%s" % [game_state.year, game_state.month_text()]
		hub.call("_open_sub_screen", "schedule")
		await _frames(3)
		await _shot("schedule_" + label)
		if step == 0 or step == 4 or game_state.phase != game_state.Phase.SEASON:
			hub.call("_open_sub_screen", "tactics")
			var roster: TabContainer = hub.get_node("%RosterView")
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


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(_out.path_join(name + ".png"))
	print("saved ", name)
