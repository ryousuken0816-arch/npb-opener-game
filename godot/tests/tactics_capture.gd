extends SceneTree
## 采配画面の確認用スクリーンショット：一覧 → 投手1軍登録（2軍の投手を先発ローテへ）→ 野手1軍登録（2軍の野手と入れ替え）
## → 起用設定（DHあり・なし）→ 思考設定 → 数日進めて、入れ替えた選手の成績が付いた画面を保存する。
##
##   xvfb-run godot --path godot --resolution 1280x720 \
##       --script res://tests/tactics_capture.gd -- <出力先> [球団名]

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
	var game_state: Node = root.get_node("GameState")
	game_state.new_game(_team)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(5)
	var hub := current_scene
	hub.call("_open_sub_screen", "tactics")
	var view: Node = hub.get_node("%TacticsView")
	await _frames(3)
	await _shot("t1_home")

	var team: SimTeam = game_state.my_team()
	# 投手：2軍で最も総合力の高い投手を選び、先発ローテ1番手と入れ替える
	view.call("_show_page", "pitchers")
	var pitchers: Node = view.get("_register_pitchers")
	var farm_p := team.players_where(false, true)
	farm_p.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool: return a.overall > b.overall)
	var new_sp: SimPlayer = farm_p[0]
	pitchers.call("_on_player_pressed", new_sp)
	await _frames(3)
	await _shot("t2_pitchers_selected")
	pitchers.call("_on_player_pressed", team.rotation[0])
	await _frames(3)
	await _shot("t3_pitchers_swapped")
	# 上限を超える登録を試す（1軍は上限人数）
	pitchers.call("_on_player_pressed", farm_p[1])
	pitchers.call("_promote_selected")
	await _frames(3)
	await _shot("t4_pitchers_limit")

	# 野手：2軍で最も打力の高い野手を選び、DHありの4番と入れ替える
	view.call("_show_page", "fielders")
	var fielders: Node = view.get("_register_fielders")
	var farm_f := team.players_where(false, false)
	farm_f.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool:
		return a.batting_value() > b.batting_value())
	var new_bat: SimPlayer = farm_f[0]
	fielders.call("_on_player_pressed", new_bat)
	await _frames(3)
	await _shot("t5_fielders_selected")
	fielders.call("_on_player_pressed", team.lineup(true)[3][0])
	await _frames(3)
	await _shot("t6_fielders_swapped")

	view.call("_show_page", "order")
	var order: Node = view.get("_order")
	await _frames(3)
	await _shot("t7_order_dh")
	order.call("_on_lineup_pressed", 0)
	await _frames(2)
	await _shot("t8_order_selected")
	order.call("_on_lineup_pressed", 1)
	order.set("_use_dh", false)
	order.call("refresh")
	await _frames(3)
	await _shot("t9_order_no_dh")

	view.call("_show_page", "strategy")
	game_state.set_tactic("bunt", 1)
	view.call("refresh")
	await _frames(3)
	await _shot("t10_strategy")

	# 日付を進めて、入れ替えた選手に成績が付き、日付の表示が進むことを確認する
	# 日程表の「1週間進める」を2回（実際の操作と同じく GameState の早送りで1日ずつ進む）
	hub.call("_close_sub_screen")
	hub.call("_close_sub_screen")
	hub.call("_open_sub_screen", "schedule")
	var schedule: Node = hub.get_node("%ScheduleView")
	for i in 2:
		schedule.call("_on_advance_days", 7)
		while game_state.is_fast_forwarding():
			await process_frame
	await _frames(3)
	await _shot("t10b_schedule_%s" % game_state.month_text())
	hub.call("_close_sub_screen")
	hub.call("_open_sub_screen", "tactics")
	view.call("_show_page", "fielders")
	fielders.call("_on_player_pressed", new_bat)
	await _frames(3)
	await _shot("t11_fielders_after_%s" % game_state.month_text())
	view.call("_show_page", "pitchers")
	pitchers.call("_on_player_pressed", new_sp)
	await _frames(3)
	await _shot("t12_pitchers_after")
	view.call("_show_page", "list")
	var roster: TabContainer = view.get("_roster")
	roster.current_tab = 2
	await _frames(3)
	await _shot("t13_list_batting")
	view.call("back")
	await _frames(3)
	await _shot("t14_home_after")
	print("%s: %s / %s: %s" % [new_bat.name, str(game_state.season.batting.get(new_bat.id, {})),
		new_sp.name, str(game_state.season.pitching.get(new_sp.id, {}))])
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(_out.path_join(name + ".png"))
	print("saved ", name)
