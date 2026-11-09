extends SceneTree
## ドラフトの手帳（投手の採点表・寸評の決め球）と表の「投手能力」タブ（作業79：奪三振の列 → 決め球）の見た目（ウィンドウ付き、1回の起動で2枚）
##
##   godot --path godot --resolution 960x540 --position <x>,<y> -s res://tests/draft_pitch_capture.gd -- <出力先>

const HUB_SCENE := "res://scenes/hub/hub.tscn"
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
	gs.new_game(TEAM, 2026)
	gs.skip_to_phase(gs.Phase.DRAFT)
	change_scene_to_file(HUB_SCENE)
	for i in 6:
		await process_frame
	var hub: Node = current_scene
	hub.call("_open_sub_screen", "draft")
	for i in 10:
		await process_frame
	var view: Node = hub.get("_draft_view")
	view.call("finish_overlays")
	view.call("_show_tab", "pitch")
	var d: RefCounted = gs.draft()
	var pick := ""
	for c: Dictionary in d.candidates:
		if c["pitcher"] and not c.get("best_pitch", {}).is_empty():
			pick = c["id"]
			print("投手の候補：%s 決め球 %s（%s）" % [c["name"], c["best_pitch"], c.get("pitches_text", "")])
			break
	view.call("select_candidate", pick)
	for i in 10:
		await process_frame
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	if not _out.is_empty() and DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(_out.path_join("draft_notebook_pitch.png"))
	view.call("set_mode", "table")
	view.call("_show_tab", "pitch")
	for i in 10:
		await process_frame
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	if not _out.is_empty() and DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(_out.path_join("draft_table_pitch.png"))
	quit(0)
