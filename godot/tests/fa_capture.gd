extends SceneTree
## FA画面（作業36）の見た目の確認（ウィンドウ付き、1回の起動で2枚）：2011年オフ・日本ハムで
## (1) 選手×球団の表（パ・リーグの列、ダルビッシュとFA宣言の選手2人に印、カーソルは好みのある選手）と
## (2) 交渉の部屋（印を付けたFA宣言の選手、提示を少し上げた状態）
##
##   godot --path godot --resolution 960x540 --position <x>,<y> -s res://tests/fa_capture.gd -- <出力先>

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TEAM := "北海道日本ハムファイターズ"
const DARVISH := "61965110"

var _out := ""
var _gs: Node


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
	_gs.new_game(TEAM, 2011)
	_gs.skip_to_phase(_gs.Phase.FA_TRADE)
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	var hub := current_scene
	hub.call("_open_sub_screen", "fa")
	await _settle()
	var view: Node = hub.get("_fa_view")
	var f: RefCounted = _gs.fa()
	# 好みが2つある選手を優先して2人に印
	var picks: Array[String] = []
	for want_two in [true, false]:
		for id: String in f.declared:
			if picks.size() < 2 and id not in picks and (f.prefs_of(id).size() == 2) == want_two:
				picks.append(id)
	view.toggle_mark(DARVISH)
	for id in picks:
		view.toggle_mark(id)
	view.select_player(picks[0])
	await _settle()
	await _shot("fa_list")
	print("印：%s／表の行 %d" % [str(view.marked_ids()), view.list_ids().size()])
	view.confirm()
	for i in view.marked_ids().size():
		if view.room_id() == picks[0]:
			break
		view.switch_tab(1)
	view.call("_step_amount", 1)
	view.call("_step_years", 1)
	await _settle()
	await create_timer(0.3).timeout
	await _shot("fa_room")
	print("OK 撮影：表（印 %d人）と交渉の部屋（%s）" % [view.marked_ids().size(), _gs.league.names[picks[0]]])
	quit(0)


func _shot(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("  スクショ: %s.png" % name)


func _settle() -> void:
	await create_timer(0.3).timeout
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
