extends SceneTree
## 画面の確認用（作業45）：2008年の阪神で5月まで進め、主力を故障させてから、ハブ（故障者の知らせ）・
## 野手／投手の1軍登録（調子の矢印・故障の印・要約）・選手詳細を撮り、3日進めて1軍登録をもう一度撮る（残りの日数が減る）。
## ウィンドウ付きで撮るときも前面に出さない（CLAUDE.md）。
##
##   godot --path godot --position 640,330 --resolution 1280x720 --script res://tests/health_capture.gd -- <出力先>

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
	gs.advance_through(Season.day_number("2008-05-09"))
	var mine: SimTeam = gs.my_team()
	var star: SimPlayer = mine.lineup(false)[2][0]
	gs.health.injure(star, mine, gs.day, 18)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub := current_scene
	await _shot("hub")
	hub.call("_open_sub_screen", "tactics")
	var tactics: Node = hub.get_node("%TacticsView")
	tactics.call("_show_page", "fielders")
	await _frames(3)
	var fielders: Node = tactics.get("_register_fielders")
	fielders.call("_on_player_pressed", star)
	await _frames(3)
	await _shot("register_fielders")
	tactics.call("_show_page", "pitchers")
	await _frames(3)
	await _shot("register_pitchers")
	var detail: Node = load("res://scenes/player_detail/player_detail.gd").open(hub, star.id)
	await _frames(4)
	await _shot("detail")
	detail.call("close")
	await _frames(2)
	gs.advance_through(gs.day + 2)
	tactics.call("_show_page", "fielders")
	await _frames(3)
	await _shot("register_fielders_3days")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("saved ", name)
