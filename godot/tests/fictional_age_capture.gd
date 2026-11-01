extends SceneTree
## 架空の候補の年齢の見た目の確認（ウィンドウ付き、1回だけ撮る）：2028年のドラフトの候補一覧を「経歴」順にして、
## 社会人（独立を含む）の選手の年齢が「-」でなく出ていること。社会人の選手を1人選んだ要約の年齢も写す
##
##   godot --path godot --resolution 960x540 --position <x>,<y> -s res://tests/fictional_age_capture.gd -- <出力先>

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TEAM := "阪神タイガース"

var _out := ""
var _gs: Node
var _hub: Node


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
	_gs = root.get_node("GameState")
	_gs.new_game(TEAM, 2027)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	_gs.advance_through(Season.day_number("2028-04-03"))
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	_hub = current_scene
	_hub.call("_open_sub_screen", "draft")
	await _settle()
	var view: Node = _hub.get("_draft_view")
	view.call("finish_overlays")
	var d: RefCounted = _gs.draft()
	var company := ""
	var missing := 0
	for c: Dictionary in d.candidates:
		if int(c["age"]) <= 0:
			missing += 1
		if c["career"] == "社会人" and (company.is_empty() or float(c["hyouka"]) > float(d.by_id[company]["hyouka"])):
			company = c["id"]
	print("%s 年齢の出ない候補 %d人／社会人の最上位 %s" % [("OK" if missing == 0 and not company.is_empty() else "NG"), missing, company])
	view.call("set_sort", "career", true)
	view.call("select_candidate", company)
	await _settle()
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	if not _out.is_empty() and DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(_out.path_join("fictional_age.png"))
		print("  スクショ: fictional_age.png")
	quit(0 if missing == 0 else 1)


func _settle() -> void:
	await create_timer(0.25).timeout
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
