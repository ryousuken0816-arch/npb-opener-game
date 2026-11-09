extends SceneTree
## 作業82の見た目の確認用スクリーンショット：起用設定（通常・入れ替え中）と 1軍登録（選んで見る・入れ替え中）。
## ウィンドウは画面の隅に置き、フォーカスを奪わない（CLAUDE.md の決まり）。マウスは動かさない。
##
##   godot --path godot --resolution 1280x720 --position 1500,800 --script res://tests/swap_capture.gd -- <出力先> [球団名]

var _out := ""
var _team := "阪神タイガース"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	if args.size() > 1:
		_team = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run.call_deferred()


func _run() -> void:
	var game_state: Node = root.get_node("GameState")
	game_state.new_game(_team)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(5)
	var hub := current_scene
	hub.call("_open_sub_screen", "tactics")
	var view: Node = hub.get_node("%TacticsView")
	await _frames(3)
	var team: SimTeam = game_state.my_team()

	view.call("_show_page", "order")
	var order: Node = view.get("_order")
	await _frames(3)
	await _shot("s1_order_normal")
	order.call("_on_lineup_swap", 2)
	await _frames(3)
	await _shot("s2_order_swapping")
	order.call("clear_selection")
	order.call("_on_bench_swap", team.bench(true)[0])
	await _frames(3)
	await _shot("s3_order_bench_swapping")
	order.call("clear_selection")

	view.call("_show_page", "pitchers")
	var pitchers: Node = view.get("_register_pitchers")
	var farm_p := team.players_where(false, true).filter(func(p: SimPlayer) -> bool: return not p.is_ikusei)
	pitchers.call("_on_player_pressed", farm_p[0])
	await _frames(3)
	await _shot("s4_register_selected")
	pitchers.call("_toggle_swap")
	await _frames(3)
	await _shot("s5_register_swapping")
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
