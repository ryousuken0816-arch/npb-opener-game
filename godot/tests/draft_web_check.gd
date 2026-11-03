extends SceneTree
## Web 版のドラフト（docs/AUTORUN.md 作業63）の確認。ヘッドレス、約3分。環境変数 NPB_SIM_WEB=1 で Web 版の動きをまねる：
##   - 抽選は3Dを使わず2Dの演出（Web 版・スマホは重いので。当たりは同じ）
##   - 発表は読み上げの終わりを待たない（声が止まっても進む）・読み上げはいつでもすぐ止める
##   - 2012年（阪神）・2020年（ソフトバンク）で、自球団は毎回 CPU の入札が最も多い候補に入札して外れ1位を何度も起こし、
##     演出の「次へ」を1つずつ押してドラフトの最後まで進める。入札の回ごとにノード数・オブジェクト数を測り、増え続けない
##   - ドラフトの画面を閉じると、演出の部品（抽選・発表の札）が残っていない
##
##   godot --headless --path godot -s res://tests/draft_web_check.gd

const CASES := [{"year": 2012, "team": "阪神タイガース"}, {"year": 2020, "team": "福岡ソフトバンクホークス"}]
## 入札の回ごとのノード数の増え方の上限（最初の回の終わりと比べる）
const NODE_GROWTH_MAX := 150
const OBJECT_GROWTH_MAX := 600

var _failures := 0
var _gs: Node
var _ds: GDScript


func _initialize() -> void:
	OS.set_environment("NPB_SIM_WEB", "1")
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_ds = load("res://sim/draft.gd")
	_ds.lottery_seed = 3  # 抽選の当たりはテストの種で（作業58）
	_check(load("res://scripts/draft_voice.gd").web_like(), "Web 版の動きをまねる（NPB_SIM_WEB=1）")
	for c: Dictionary in CASES:
		await _check_year(int(c["year"]), str(c["team"]))
	await _check_pc_3d()
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_year(year: int, team: String) -> void:
	print("\n== %d年 %s ==" % [year, team])
	_gs.new_game(team, year)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub: Node = current_scene
	hub.call("_open_sub_screen", "draft")
	await _frames(4)
	var view: Node = hub.get("_draft_view")
	var d: RefCounted = _gs.draft()
	_check(not view.call("use_3d_lottery"), "%d年：抽選は2Dの演出" % year)
	await _walk_overlays(view)
	var counts: Array = []
	var saw_3d := false
	var waves := 0
	var guard := 0
	# 外れ1位が起きるまで（入札が2回以上）、入札の前の状態に戻して抽選の種を変えて試す
	var snap: Dictionary = d.to_save().duplicate(true)
	for attempt in 6:
		if attempt > 0:
			_gs.league.draft = _ds.from_save(snap.duplicate(true))
			d = _gs.draft()
			view.call("refresh")
		_ds.lottery_seed = 3 + attempt
		counts = []
		waves = 0
		guard = 0
		while d.stage == _ds.Stage["FIRST"] and guard < 12:
			guard += 1
			if d.first_pick_of(team).is_empty():
				var target := _most_bid(d)
				if view.call("selected_id") != target:
					view.call("select_candidate", target)
				await _frames(2)
				(view.call("notebook") as Control).emit_signal("go_pressed")
			else:
				view.call("_continue_first")
			waves += 1
			saw_3d = saw_3d or await _walk_overlays(view)
			await _frames(3)
			counts.append([Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				Performance.get_monitor(Performance.OBJECT_COUNT)])
		if waves >= 2:
			break
	_check(not saw_3d, "%d年：3Dの抽選の場面は出ない" % year)
	_check(waves >= 2 and d.stage == _ds.Stage["WAIVER"], "%d年：外れ1位を含めて%d回の入札で全球団の1位が決まる" % [year, waves])
	var grow_nodes := 0
	var grow_objects := 0
	for c: Array in counts:
		grow_nodes = maxi(grow_nodes, int(c[0]) - int(counts[0][0]))
		grow_objects = maxi(grow_objects, int(c[1]) - int(counts[0][1]))
	print("  入札の回ごとのノード数：%s" % ", ".join(counts.map(func(c: Array) -> String: return str(int(c[0])))))
	print("  入札の回ごとのオブジェクト数：%s" % ", ".join(counts.map(func(c: Array) -> String: return str(int(c[1])))))
	_check(grow_nodes <= NODE_GROWTH_MAX and grow_objects <= OBJECT_GROWTH_MAX,
		"%d年：外れ1位が続いてもノード数・オブジェクト数が増え続けない（最大 +%d・+%d）" % [year, grow_nodes, grow_objects])
	# 2位以降：自球団の番まで飛ばして指名、発表は「次へ」で1つずつ
	guard = 0
	var picked := 0
	while d.stage != _ds.Stage["DONE"] and guard < 300:
		guard += 1
		if d.is_user_turn():
			if picked < 2 and d.stage == _ds.Stage["WAIVER"]:
				view.call("set_filter", "left")
				(view.call("notebook") as Control).emit_signal("go_pressed")
				picked += 1
			else:
				view.call("_on_finish_pressed")
		else:
			view.call("_on_skip_pressed")
		await _walk_overlays(view)
	_check(d.stage == _ds.Stage["DONE"], "%d年：ドラフトの最後まで進む（自球団 %d人）" % [year, d.picks_of(team).size()])
	var before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	hub.call("_close_sub_screen")
	await _frames(4)
	var overlay_box: Control = view.get("_overlay_box")
	_check(overlay_box.get_child_count() == 0 and not view.call("overlay_visible"),
		"%d年：演出を閉じると部品が残らない（演出の中身 %d、ノード %d → %d）" % [year, overlay_box.get_child_count(), int(before),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])


## パソコン（NPB_SIM_WEB を外す）は3Dの抽選のまま。演出を最後まで進めると3Dの場面が解放されている（作業63）
func _check_pc_3d() -> void:
	print("
== パソコン：2024年 巨人（3Dの抽選） ==")
	OS.set_environment("NPB_SIM_WEB", "0")
	_gs.new_game("読売ジャイアンツ", 2024)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub: Node = current_scene
	hub.call("_open_sub_screen", "draft")
	await _frames(4)
	var view: Node = hub.get("_draft_view")
	var d: RefCounted = _gs.draft()
	_check(view.call("use_3d_lottery"), "パソコンは3Dの抽選")
	await _walk_overlays(view)
	var target := _most_bid(d)
	if view.call("selected_id") != target:
		view.call("select_candidate", target)
	await _frames(2)
	(view.call("notebook") as Control).emit_signal("go_pressed")
	var during := 0
	var guard := 0
	while view.call("overlay_visible") and view.call("lottery_3d") == null and guard < 100:
		guard += 1
		(view.get("_overlay_next") as Button).pressed.emit()
		await _frames(2)
	if view.call("lottery_3d") != null:
		during = root.find_children("*", "Lottery3D", true, false).size()
	var saw_3d := during > 0
	await _walk_overlays(view)
	await _frames(4)
	var left := root.find_children("*", "Lottery3D", true, false).size()
	_check(saw_3d and left == 0, "3Dの抽選を見たあと、演出を閉じると3Dの場面が残っていない（抽選中 %d → 閉じたあと %d）"
		% [during, left])
	OS.set_environment("NPB_SIM_WEB", "1")


## 演出（入札の発表・抽選・結果）を「次へ」で1つずつ最後まで進める。3Dの抽選が出たら true
func _walk_overlays(view: Node) -> bool:
	var saw_3d := false
	var guard := 0
	while view.call("overlay_visible") and guard < 400:
		guard += 1
		if view.call("lottery_3d") != null:
			saw_3d = true
		(view.get("_overlay_next") as Button).pressed.emit()
		await _frames(2)
	return saw_3d


## CPU球団の入札が最も多い候補（自球団も入れて抽選を起こす）。無ければ評価の一番高い残り
func _most_bid(d: RefCounted) -> String:
	var count := {}
	var bids: Dictionary = d.cpu_first_bids()
	for t: String in bids:
		count[bids[t]] = int(count.get(bids[t], 0)) + 1
	var best := ""
	for c: Dictionary in d.remaining():
		if best.is_empty() or int(count.get(c["id"], 0)) > int(count.get(best, 0)) \
				or (int(count.get(c["id"], 0)) == int(count.get(best, 0)) and float(c["hyouka"]) > float(d.by_id[best]["hyouka"])):
			best = c["id"]
	return best


func _check(ok: bool, label: String) -> void:
	print(("OK " if ok else "NG ") + label)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame
