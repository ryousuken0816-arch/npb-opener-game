extends SceneTree
## 作業21・22・32の見た目の確認（ウィンドウ付き、1回だけ撮る）。4枚を2x2に並べた1枚にする：
##   1) 2028年4月のハブで開いた「2028年 センバツ号」（架空の候補・転生選手の記事）
##   2) 2028年のドラフト：転生選手を選んだところ（一覧の「転生」の印と、要約の元の選手）
##   3) 2028年のドラフト：架空の候補のいちばん評価の高い選手（実在の学校名）
##   4) ハブの「システム」：当たりの頻度・転生選手の設定
##
##   godot --path godot --resolution 960x540 --position <x>,<y> -s res://tests/fictional_capture.gd -- <出力先>

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TEAM := "阪神タイガース"

var _out := ""
var _failures := 0
var _gs: Node
var _hub: Node
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
	_gs = root.get_node("GameState")
	_gs.new_game(TEAM, 2027)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	_gs.advance_through(Season.day_number("2028-04-03"))
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	_hub = current_scene
	_check(not _gs.news.get_issue("2028-amateur-spring").is_empty(), "2028年のセンバツ号（%s）" % _gs.date_text())
	_hub.call("open_news", "2028-amateur-spring")
	await _settle()
	await _shot()
	_hub.call("_close_sub_screen")
	await _settle()
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	_hub.call("_open_sub_screen", "draft")
	await _settle()
	var view: Node = _hub.get("_draft_view")
	view.call("finish_overlays")
	var d: RefCounted = _gs.draft()
	var rei := ""
	var top := ""
	for c: Dictionary in d.candidates:
		if rei.is_empty() and not c.get("reincarnation", {}).is_empty():
			rei = c["id"]
		if top.is_empty() or float(c["hyouka"]) > float(d.by_id[top]["hyouka"]):
			top = c["id"]
	_check(d.year == 2028 and not top.is_empty(), "2028年のドラフト（転生選手 %s）" % ("あり" if not rei.is_empty() else "なし"))
	view.call("select_candidate", rei if not rei.is_empty() else top)
	await _settle()
	await _shot()
	view.set("_selected", "")
	view.call("refresh")
	view.call("select_candidate", top)
	await _settle()
	await _shot()
	_hub.call("_close_sub_screen")
	await _settle()
	_hub.call("_open_sub_screen", "system")
	await _settle()
	await _shot()
	_save_grid()
	print("\n%s" % ("全項目OK" if _failures == 0 else "NG %d件" % _failures))
	quit(1 if _failures > 0 else 0)


func _shot() -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	_shots.append(root.get_texture().get_image())


func _save_grid() -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless" or _shots.is_empty():
		return
	var w := _shots[0].get_width()
	var h := _shots[0].get_height()
	var grid := Image.create(w * 2, h * 2, false, _shots[0].get_format())
	for i in _shots.size():
		grid.blit_rect(_shots[i], Rect2i(0, 0, w, h), Vector2i((i % 2) * w, (i / 2) * h))
	grid.save_png(_out.path_join("fictional_2028.png"))
	print("  スクショ: fictional_2028.png")


func _check(ok: bool, label: String) -> void:
	print(("OK " if ok else "NG ") + label)
	if not ok:
		_failures += 1


func _settle() -> void:
	await create_timer(0.25).timeout
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
