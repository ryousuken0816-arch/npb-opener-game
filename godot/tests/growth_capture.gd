extends SceneTree
## 成長・衰え（docs/AUTORUN.md 作業27）の見た目の確認（ウィンドウ付き、1回だけ撮る）。
## 2027年開始で、2028年の開幕と2030年の開幕に、同じ選手（自球団の若手の野手・ベテランの投手）の選手詳細を開き、
## 4枚を2x2に並べた1枚の画像にする（左が2028年、右が2030年）。ハブの日付が年に追従するかも調べる。
##
##   godot --path godot --resolution 960x540 --position <x>,<y> -s res://tests/growth_capture.gd -- <出力先>

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const USER := "北海道日本ハムファイターズ"

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node
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
	_gd = root.get_node("GameData")
	_gs.new_game(USER, 2027)
	_next_season()
	var ids := _pick_players()
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	var before := {}
	for id: String in ids:
		before[id] = _summary(id)
		await _detail_shot(id)
	_next_season()
	_next_season()
	_gs.changed.emit()
	await _frames(4)
	_check(_gs.date_text().begins_with("2030年"), "ハブの日付が2030年（%s）" % _gs.date_text())
	var changed := 0
	for id: String in ids:
		var after := _summary(id)
		print("  %s：2028年 %s → 2030年 %s" % [_gd.player(id).get("name", id), before[id], after])
		if after != before[id]:
			changed += 1
		await _detail_shot(id)
	_check(changed == ids.size(), "2人とも2028年と2030年で能力が違う")
	_save_grid(ids.size())
	print("\n%s" % ("全項目OK" if _failures == 0 else "NG %d件" % _failures))
	quit(1 if _failures > 0 else 0)


## 今のシーズンを終えて、次の年の開幕まで進める
func _next_season() -> void:
	_gs.skip_to_phase(_gs.Phase.CAMP)
	_gs.advance()


## 自球団の24歳以下でいちばん打力のある野手と、32歳以上でいちばん総合の高い投手
func _pick_players() -> Array[String]:
	var young := ""
	var veteran := ""
	var best_y := -INF
	var best_v := -INF
	for p: Dictionary in _gd.players_of(USER):
		var age := Growth.age_at(p, _gs.year)
		if Growth._side(p) == "B" and age <= 24:
			var v := float(Growth._value(p, "B", "meet")) + float(Growth._value(p, "B", "power"))
			if v > best_y:
				best_y = v
				young = p["id"]
		elif Growth._side(p) == "P" and age >= 32:
			var v := float(Growth._value(p, "P", "overall"))
			if v > best_v:
				best_v = v
				veteran = p["id"]
	return [young, veteran]


func _summary(id: String) -> String:
	var p: Dictionary = _gd.player(id)
	if Growth._side(p) == "B":
		return "ミート%s パワー%s 走力%s" % [Growth._value(p, "B", "meet"), Growth._value(p, "B", "power"), Growth._value(p, "B", "speed")]
	return "総合%s 球速%s スタミナ%s" % [Growth._value(p, "P", "overall"), Growth._value(p, "P", "velocity"), Growth._value(p, "P", "stamina")]


func _detail_shot(id: String) -> void:
	var detail: Node = load("res://scenes/player_detail/player_detail.gd").call("open", current_scene, id, [id])
	_check(detail != null, "選手詳細を開く（%s）" % _gd.player(id).get("name", id))
	await _frames(6)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	_shots.append(root.get_texture().get_image())
	if detail != null:
		detail.call("close")
	await _frames(3)


## 1列目：1人目（2028年・2030年）、2列目：2人目
func _save_grid(players: int) -> void:
	if _out.is_empty() or _shots.size() < players * 2:
		return
	var w := _shots[0].get_width()
	var h := _shots[0].get_height()
	var grid := Image.create(w * 2, h * players, false, _shots[0].get_format())
	for i in players:
		grid.blit_rect(_shots[i], Rect2i(0, 0, w, h), Vector2i(0, h * i))
		grid.blit_rect(_shots[players + i], Rect2i(0, 0, w, h), Vector2i(w, h * i))
	grid.save_png(_out.path_join("growth_2028_2030.png"))
	print("保存：%s" % _out.path_join("growth_2028_2030.png"))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, label: String) -> void:
	print("  [%s] %s" % ["OK" if ok else "NG", label])
	if not ok:
		_failures += 1
