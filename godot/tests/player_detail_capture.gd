extends SceneTree
## 選手の詳細画面（作業72：能力の並び・総合を名前の横・棒なし）の見た目の確認（ウィンドウ付き、1回だけ起動して投手と野手を1枚ずつ）
##
##   godot --path godot --resolution 960x540 --position <x>,<y> -s res://tests/player_detail_capture.gd -- <出力先>

const TEAM := "読売ジャイアンツ"
const DETAIL_SCRIPT := "res://scenes/player_detail/player_detail.gd"

var _out := ""


func _initialize() -> void:
	# フォーカスを奪わない（CLAUDE.md）
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	var gs: Node = root.get_node("GameState")
	gs.new_game(TEAM, 2026)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(8)
	var hub: Node = current_scene
	var ids: Array = load(DETAIL_SCRIPT).team_order(TEAM)
	var gd: Node = root.get_node("GameData")
	var pitcher := ""
	var batter := ""
	for id: String in ids:
		if gd.player(id).get("is_pitcher", false):
			if pitcher.is_empty():
				pitcher = id
		elif batter.is_empty():
			batter = id
	for pair: Array in [[pitcher, "1_pitcher"], [batter, "2_batter"]]:
		var detail: Node = load(DETAIL_SCRIPT).open(hub, pair[0], ids)
		await _shot(pair[1])
		detail.close()
		await _frames(4)
	quit(0)


func _shot(name: String) -> void:
	await _frames(6)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	if not _out.is_empty() and DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(_out.path_join(name + ".png"))


func _frames(n: int) -> void:
	for i in n:
		await process_frame
