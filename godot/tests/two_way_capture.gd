extends SceneTree
## 作業86の見た目の確認用スクリーンショット：起用設定の「二刀流」の欄と、スタメンの「二」の印（2016年の日本ハム・大谷）。
## 日付を3週間進めてから撮る。ウィンドウは画面の隅に置き、フォーカスを奪わない（CLAUDE.md の決まり）。マウスは動かさない。
##
##   godot --path godot --resolution 1280x720 --position 1500,800 --script res://tests/two_way_capture.gd -- <出力先>

var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_out)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run.call_deferred()


func _run() -> void:
	var game_state: Node = root.get_node("GameState")
	game_state.new_game("北海道日本ハムファイターズ", 2016)
	game_state.advance_through(int(game_state.day) + 21)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(5)
	var hub := current_scene
	hub.call("_open_sub_screen", "tactics")
	var view: Node = hub.get_node("%TacticsView")
	await _frames(3)
	view.call("_show_page", "order")
	await _frames(3)
	await _shot("two_way_order")
	quit(0)


func _shot(name: String, wait := 0.3) -> void:
	if wait > 0.0:
		await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(_out.path_join(name + ".png"))
	print("saved ", name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
