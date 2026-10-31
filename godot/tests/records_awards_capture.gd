extends SceneTree
## 表彰・記録室の見た目の確認（ウィンドウ付き、1回だけ撮る）。docs/AUTORUN.md 作業9・10。
## 2008年のオフ（表彰）で表彰の画面を開き、2009年6月末まで進めてから記録室（打撃成績・デプス・守備位置ランク）を開いて、
## 4画面を2x2に並べた1枚の画像にして保存する。日付を進めたあとに開き直すと記録室が今季（2009年）を出すかも調べる。
##
##   godot --path godot --resolution 960x540 --position <x>,<y> -s res://tests/records_awards_capture.gd -- <出力先> [自球団]

const HUB_SCENE := "res://scenes/hub/hub.tscn"

var _out := ""
var _team := "福岡ソフトバンクホークス"
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
	if args.size() > 1:
		_team = args[1]
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gs.new_game(_team, 2008)
	_gs.advance_through(_gs.season_last_day())
	_check(_gs.phase == _gs.Phase.AWARDS, "2008年 シーズン終了・表彰")
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	_hub = current_scene
	_hub.call("_open_sub_screen", "awards")
	await _settle()
	var awards: Node = _hub.get("_awards_view")
	_check(awards.call("shown_year") == 2008, "表彰の画面に2008年（%d）" % awards.call("shown_year"))
	await _shot()
	_hub.call("_open_sub_screen", "records")
	await _settle()
	var view: Node = _hub.get("_records_view")
	_check(view.call("shown_year") == 2008, "オフの記録室は2008年（%d）" % view.call("shown_year"))
	_hub.call("_close_sub_screen")
	# 日付を進める：2009年6月末まで
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	_gs.advance_through(Season.day_number("2009-06-30"))
	_gs.changed.emit()  # advance_through は通知しない（ハブの日付を合わせる）
	await _frames(4)
	_hub.call("_open_sub_screen", "records")
	await _settle()
	_check(view.call("shown_year") == 2009, "日付を進めて開き直すと記録室は2009年（%d）" % view.call("shown_year"))
	var ids: Array = view.call("list_ids")
	var games := 0
	if not ids.is_empty():
		games = int(_gs.season.batting.get(ids[0], {}).get("g", 0))
	_check(games > 50, "打撃成績の1位の今季の試合数が6月末の数（%d）" % games)
	await _shot()
	view.call("set_tab", "depth")
	await _settle()
	await _shot()
	view.call("set_tab", "pos_rank")
	await _settle()
	await _shot()
	_save_grid()
	print("\n%s" % ("全項目OK" if _failures == 0 else "NG %d件" % _failures))
	quit(1 if _failures > 0 else 0)


func _shot() -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	_shots.append(root.get_texture().get_image())


## 4枚を2x2に並べた1枚にする
func _save_grid() -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless" or _shots.is_empty():
		return
	var w := _shots[0].get_width()
	var h := _shots[0].get_height()
	var grid := Image.create(w * 2, h * 2, false, _shots[0].get_format())
	for i in _shots.size():
		grid.blit_rect(_shots[i], Rect2i(0, 0, w, h), Vector2i((i % 2) * w, (i / 2) * h))
	grid.save_png(_out.path_join("records_awards.png"))
	print("  スクショ: records_awards.png")


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
