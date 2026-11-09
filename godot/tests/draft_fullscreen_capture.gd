extends SceneTree
## ドラフトの画面いっぱいの見た目の確認（ウィンドウ付き、1回だけ撮る。作業81）。2008年・巨人：
##   1) 表（画面いっぱい、下の帯なし） 2) 表から入札したあとの演出（後ろに表の「済」＋入団先が透けない）
##   godot --path godot --resolution 960x540 --position <x>,<y> -s res://tests/draft_fullscreen_capture.gd -- <出力先>

const HUB_SCENE := "res://scenes/hub/hub.tscn"

var _out := ""
var _shots: Array[Image] = []


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
	gs.new_game("読売ジャイアンツ", 2008)
	gs.skip_to_phase(gs.Phase.DRAFT)
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	var hub: Node = current_scene
	hub.call("_open_sub_screen", "draft")
	await _settle()
	var view: Node = hub.get("_draft_view")
	view.call("finish_overlays")
	view.call("set_mode", "table")
	await _settle()
	var d: RefCounted = gs.draft()
	view.call("select_candidate", d.candidates[0]["id"])
	await _settle()
	await _shot()  # 1) 表（画面いっぱい。下の帯なし）
	view.call("press_action")
	await _settle()
	await _shot()  # 2) 入札のあとの演出（後ろの表が透けない）
	if not _out.is_empty() and DisplayServer.get_name() != "headless" and _shots.size() == 2:
		var w := _shots[0].get_width()
		var h := _shots[0].get_height()
		var grid := Image.create(w * 2, h, false, _shots[0].get_format())
		grid.blit_rect(_shots[0], Rect2i(0, 0, w, h), Vector2i(0, 0))
		grid.blit_rect(_shots[1], Rect2i(0, 0, w, h), Vector2i(w, 0))
		grid.save_png(_out.path_join("draft_fullscreen.png"))
		print("  スクショ: draft_fullscreen.png")
	quit(0)


func _shot() -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	_shots.append(root.get_texture().get_image())


func _settle() -> void:
	await create_timer(0.25).timeout
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
