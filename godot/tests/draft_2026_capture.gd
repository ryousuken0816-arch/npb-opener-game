extends SceneTree
## 2026年・2027年のドラフトとメジャー志望の説得の見た目の確認（ウィンドウ付き、1回だけ撮る）。docs/AUTORUN.md
## 作業16・17・26。4枚を2x2に並べた1枚にする：
##   1) 2026年のドラフト（巨人）：織田翔希（米志望）を選んだところ
##   2) ドラフト会議のあと：織田翔希の説得（約束の選択と★）
##   3) 2027年5月15日まで進めたハブ（日付・順位が追従）
##   4) 2027年のドラフト：実在のアマ選手の候補（1年目は「未来」）
##
##   godot --path godot --resolution 960x540 --position <x>,<y> -s res://tests/draft_2026_capture.gd -- <出力先>

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TEAM := "読売ジャイアンツ"

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
	_gs.new_game(TEAM, 2026)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	_hub = current_scene
	_hub.call("_open_sub_screen", "draft")
	await _settle()
	var view: Node = _hub.get("_draft_view")
	view.call("finish_overlays")
	var d: RefCounted = _gs.draft()
	var oda := _find(d, "織田 翔希")
	_check(not oda.is_empty() and d.by_id[oda]["mlb_intent"], "2026年の候補に織田翔希（米志望）")
	view.call("select_candidate", oda)
	await _settle()
	await _shot()
	d.user_bid(oda)
	d.run_first_wave()
	d.auto_complete()
	_gs.draft_sync()
	_check(oda in d.pending_talks(), "ドラフト会議のあと織田翔希の説得が残る（%s）" % d.first_pick_of(TEAM))
	view.set("_selected", "")  # 同じ候補をもう一度選ぶと選手詳細が開くので、選び直す
	view.call("refresh")
	view.call("select_candidate", oda)
	await _settle()
	await _shot()
	view.call("press_action")
	await _settle()
	_check(d.talks.has(oda), "説得した（%s）" % str(d.talks.get(oda, {})))
	_hub.call("_close_sub_screen")
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	_gs.advance_through(Season.day_number("2027-05-15"))
	_gs.changed.emit()
	await _frames(4)
	_check(_gs.date_text().begins_with("2027年 5月16日") and _gs.games_played() > 30,
		"2027年5月まで進めると日付・成績が追従（%s %d試合）" % [_gs.date_text(), _gs.games_played()])
	await _settle()
	await _shot()
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	_hub.call("_open_sub_screen", "draft")
	await _settle()
	view.call("finish_overlays")
	d = _gs.draft()
	var top := _find(d, "川本 晴大")
	_check(d.year == 2027 and not top.is_empty() and d.by_id[top]["amateur"], "2027年のドラフトに実在のアマ選手")
	view.call("select_candidate", top)
	await _settle()
	await _shot()
	_save_grid()
	print("\n%s" % ("全項目OK" if _failures == 0 else "NG %d件" % _failures))
	quit(1 if _failures > 0 else 0)


func _find(d: RefCounted, name: String) -> String:
	for c: Dictionary in d.candidates:
		if c["name"] == name:
			return c["id"]
	return ""


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
	grid.save_png(_out.path_join("draft_2026_2027.png"))
	print("  スクショ: draft_2026_2027.png")


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
