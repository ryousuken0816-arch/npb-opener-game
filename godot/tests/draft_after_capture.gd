extends SceneTree
## ドラフトのあと（作業65）の見た目の確認（ウィンドウ付き、1回だけ起動して2枚撮る）：
## 1) 2026年・巨人で織田翔希を1位で指名してドラフトを終えたところ（手帳の説得のページ・上の帯・下の「説得せずに次へ」）
## 2) 指名一覧（表）を見ているとき（上の帯の「説得のページへ」）
##
##   godot --path godot --resolution 960x540 --position <x>,<y> -s res://tests/draft_after_capture.gd -- <出力先>

const TEAM := "読売ジャイアンツ"

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
	var ds: GDScript = load("res://sim/draft.gd")
	var d: RefCounted = null
	var oda := ""
	for attempt in 8:
		ds.lottery_seed = 1 + attempt
		gs.new_game(TEAM, 2026)
		gs.skip_to_phase(gs.Phase.DRAFT)
		d = gs.draft()
		for c: Dictionary in d.remaining():
			if c["name"] == "織田 翔希":
				oda = c["id"]
		d.user_bid(oda)
		d.run_first_wave()
		if d.first_pick_of(TEAM) == oda:
			break
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(8)
	var hub: Node = current_scene
	hub.call("_open_sub_screen", "draft")
	await _frames(4)
	var view: Node = hub.get("_draft_view")
	view.call("finish_overlays")
	view.call("_on_complete_pressed")
	view.call("finish_overlays")
	await _shot("1_talk_page")
	view.call("set_mode", "table")
	view.call("_show_tab", "picks")
	await _shot("2_picks_banner")
	quit(0)


func _shot(name: String) -> void:
	await _frames(6)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	if not _out.is_empty() and DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(_out.path_join(name + ".png"))


func _frames(n: int) -> void:
	for i in n:
		await process_frame
