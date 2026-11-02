extends SceneTree
## 画面の確認用（作業46）：2008年の阪神で、ハブの今年の目標（開幕・6月1日・シーズン終了）、表彰のあとの評価、
## 記録室の「順位の推移」のオーナーの評価の歴代、翌年の春季キャンプの目標を撮る。
## ウィンドウ付きで撮るときも前面に出さない（CLAUDE.md）。
##
##   godot --path godot --position 640,330 --resolution 1280x720 --script res://tests/owner_capture.gd -- <出力先>

var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_out)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run.call_deferred()


func _run() -> void:
	var gs: Node = root.get_node("GameState")
	gs.new_game("阪神タイガース", 2008)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub := current_scene
	await _shot("hub_opening")
	gs.advance_through(Season.day_number("2008-05-31"))
	gs.changed.emit()
	await _frames(3)
	await _shot("hub_june")
	gs.advance_through(gs.season_last_day())
	gs.changed.emit()
	await _frames(3)
	await _shot("hub_awards")
	gs.advance()
	await _frames(3)
	await _shot("hub_evaluated")
	hub.call("_open_sub_screen", "records")
	var records: Node = hub.get("_records_view")
	records.call("set_tab", "teams")
	await _frames(3)
	var scroll: ScrollContainer = records.get("_scroll")
	scroll.scroll_vertical = 100000
	await _frames(3)
	await _shot("records_owner")
	hub.call("_close_sub_screen")
	gs.skip_to_phase(gs.Phase.CAMP)
	gs.changed.emit()
	await _frames(3)
	await _shot("hub_camp_2009")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("saved ", name)
