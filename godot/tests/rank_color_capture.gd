extends SceneTree
## 名簿（采配の選手一覧）のランクの色の確認用スクリーンショット（作業64）。投手タブ（ランク・球速の色）を1枚撮る。
## ウィンドウは画面の隅に小さく置き、フォーカスを奪わない：
##   godot --path godot --resolution 960x540 --position 950,500 --script res://tests/rank_color_capture.gd -- <出力先>

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
	gs.new_game("読売ジャイアンツ", 2008)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(8)
	var hub := current_scene
	hub.call("_open_sub_screen", "tactics")
	await _frames(3)
	var tactics: Node = hub.get("_tactics_view")
	tactics.call("_show_page", "list")
	await _frames(3)
	var roster: TabContainer = tactics.get("_roster")
	for i in roster.get_tab_count():
		if roster.get_tab_title(i).begins_with("投手 ") or roster.get_tab_title(i).begins_with("投手（"):
			roster.current_tab = i
	await _frames(6)
	var img := root.get_texture().get_image()
	var path := _out.path_join("rank_colors.png")
	img.save_png(path)
	print("saved ", path)
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
