extends SceneTree
## 意中の球団の見た目の確認（ウィンドウ付き、1回だけ撮る。作業77）。2027年・阪神で始めて2028年のドラフトへ進め、
## 「巨人以外なら会社に残留」の候補を2位で強行指名したあと：
##   1) 手帳の入団交渉のページ（上の帯・誠意の選び方・「説得する」） 2) 表の画面の要約の欄（意中の球団・誠意）
##   godot --path godot --resolution 960x540 --position <x>,<y> -s res://tests/draft_intent_capture.gd -- <出力先>

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const USER := "阪神タイガース"

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
	var ds: GDScript = load("res://sim/draft.gd")
	ds.lottery_seed = 1
	gs.new_game(USER, 2027)
	gs.skip_to_phase(gs.Phase.DRAFT)
	gs.draft_resolve()
	while gs.phase != gs.Phase.CAMP:
		gs.advance()
	gs.advance()  # 2028年の開幕
	var target_name := ""
	for p: Dictionary in gs.draft_class(2028):
		var am: Dictionary = p["amateur"]
		if am["grade"] == "B" and not bool(am.get("as_ikusei", false)) and not (am.get("mlb_intent") is Dictionary) \
				and not am.has("team_intent"):
			am["team_intent"] = {"team": "読売ジャイアンツ", "hard": true, "alt": "残留",
				"note": "%sの%sは「巨人以外なら会社に残留」と明言" % [am["school"], p["name"]]}
			target_name = p["name"]
			break
	gs.skip_to_phase(gs.Phase.DRAFT)
	var d: RefCounted = gs.draft()
	var target := ""
	for c: Dictionary in d.candidates:
		if c["name"] == target_name:
			target = c["id"]
	var guard := 0
	while d.stage == ds.Stage["FIRST"] and guard < 10:
		guard += 1
		if d.first_pick_of(USER).is_empty() and not d.bids.has(USER):
			for c: Dictionary in d.remaining():
				if c["id"] != target and not c.get("mlb_intent", false) and c.get("intent", {}).is_empty():
					d.user_bid(c["id"])
					break
		d.run_first_wave()
	d.run_until_user()
	if not str(d.by_id[target]["picked_by"]).is_empty():
		# 先に指名された（意中の巨人など）：残りの架空の候補に付け直す
		var it: Dictionary = d.by_id[target]["intent"]
		for c: Dictionary in d.remaining():
			if c.get("fictional", false) and c.get("intent", {}).is_empty() and not c.get("mlb_intent", false):
				target = c["id"]
				break
		d.by_id[target]["intent"] = it
	print("  指名：%s %s" % [d.by_id[target]["name"], d.user_pick(target)])
	d.auto_complete()
	gs.draft_sync()
	print("  %d年 %s・交渉の待ち %s" % [gs.year, gs.date_text(), str(d.pending_talks())])
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	var hub: Node = current_scene
	hub.call("_open_sub_screen", "draft")
	await _settle()
	var view: Node = hub.get("_draft_view")
	view.call("finish_overlays")
	await _settle()
	await _shot()  # 1) 手帳の入団交渉のページ
	view.call("set_mode", "table")
	await _settle()
	view.call("select_candidate", target)
	await _settle()
	await _shot()  # 2) 表の画面の要約の欄
	if not _out.is_empty() and DisplayServer.get_name() != "headless" and _shots.size() == 2:
		var w := _shots[0].get_width()
		var h := _shots[0].get_height()
		var grid := Image.create(w * 2, h, false, _shots[0].get_format())
		grid.blit_rect(_shots[0], Rect2i(0, 0, w, h), Vector2i(0, 0))
		grid.blit_rect(_shots[1], Rect2i(0, 0, w, h), Vector2i(w, 0))
		grid.save_png(_out.path_join("draft_intent.png"))
		print("  スクショ: draft_intent.png")
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
