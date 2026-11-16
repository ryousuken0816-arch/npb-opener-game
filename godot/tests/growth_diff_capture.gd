extends SceneTree
## 前の年からの変化（作業83）と新しい変化量の見た目：野手の詳細（↑）・投手能力（↑・持ち球の変化）・名簿の決め球の色。1回だけ起動する
##
##   godot --path godot --resolution 1280x720 --position <x>,<y> -s res://tests/growth_diff_capture.gd -- <出力先>

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
	var gd: Node = root.get_node("GameData")
	var diff: GDScript = load("res://sim/growth_diff.gd")
	# いちばん伸びた自球団の野手と、持ち球が変わった投手
	var batter := ""
	var best := -1.0
	var pitcher := ""
	var pbest := -1.0
	var prev: Dictionary = diff.prev_values(2026)
	for p: Dictionary in gd.players_of(TEAM):
		if not prev.has(p["id"]):
			continue
		var g: Dictionary = diff.growth_of(prev[p["id"]], diff.of(p), bool(p.get("is_pitcher", false)))
		if g.is_empty():
			continue
		if bool(p.get("is_pitcher", false)):
			if not diff.pitch_changes(p).is_empty() and float(g["score"]) > pbest:
				pbest = float(g["score"])
				pitcher = p["id"]
		elif float(g["score"]) > best:
			best = float(g["score"])
			batter = p["id"]
	print("野手 %s・投手 %s" % [gd.player(batter).get("name", ""), gd.player(pitcher).get("name", "")])
	var detail: Node = load(DETAIL_SCRIPT).open(hub, batter)
	await _frames(6)
	_shot("growth_batter")
	detail.call("close")
	await _frames(3)
	detail = load(DETAIL_SCRIPT).open(hub, pitcher)
	await _frames(6)
	_shot("growth_pitcher")
	detail.call("close")
	await _frames(3)
	quit(0)


func _shot(name: String) -> void:
	if _out.is_empty():
		return
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("保存：%s" % _out.path_join(name + ".png"))


func _frames(n: int) -> void:
	for i in n:
		await process_frame
