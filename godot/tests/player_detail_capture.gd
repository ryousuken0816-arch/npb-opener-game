extends SceneTree
## 選手詳細の見た目（投手能力の画面を、5球種・混在・左投げ・野手で1枚ずつ。1回だけ起動する）
##
##   godot --path godot --resolution 1280x720 --position <x>,<y> -s res://tests/player_detail_capture.gd -- <出力先>

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
	var five := ""
	var mix := ""
	var lefty := ""
	var batter := ""
	for team: String in gd.teams():
		for p: Dictionary in gd.players_of(team):
			if not p.get("is_pitcher", false):
				if batter.is_empty():
					batter = str(p["id"])
				continue
			var raw: Variant = p.get("pitching", {}).get("pitches", [])
			if not raw is Array:
				continue
			var ps: Array = raw
			var down := false
			var side := 0
			for x: Dictionary in ps:
				var dir := str(PitchArsenal.TYPES.get(str(x["name"]), {}).get("dir", ""))
				down = down or dir == "下"
				side += 0 if dir == "下" else 1
			if five.is_empty() and ps.size() >= 5:
				five = str(p["id"])
			if mix.is_empty() and five != str(p["id"]) and down and side >= 2 and ps.size() < 5:
				mix = str(p["id"])
			if lefty.is_empty() and str(p.get("throws", "")) == "左" and ps.size() >= 3:
				lefty = str(p["id"])
	for pair: Array in [[five, "1_pitcher_five"], [mix, "2_pitcher_mix"], [lefty, "3_pitcher_left"], [batter, "4_batter"]]:
		if str(pair[0]).is_empty():
			continue
		print("capture %s %s" % [pair[1], gd.player(pair[0]).get("name", "")])
		var detail: Node = load(DETAIL_SCRIPT).open(hub, pair[0])
		await _shot(pair[1])
		detail.close()
		await _frames(3)
	# 開幕から3週間進めたあとの成績の行（日付に追従するかの見た目）
	var ace: String = gs.my_team().rotation[0].id
	var detail_ace: Node = load(DETAIL_SCRIPT).open(hub, ace)
	gs.start_fast_forward(gs.day + 21)
	while gs.is_fast_forwarding():
		await process_frame
	print("capture 5_pitcher_after %s" % gd.player(ace).get("name", ""))
	await _shot("5_pitcher_after")
	detail_ace.close()
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
