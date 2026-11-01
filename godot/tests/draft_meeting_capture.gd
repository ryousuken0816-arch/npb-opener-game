extends SceneTree
## ドラフト前の作戦会議・有識者の予想の見た目の確認（ウィンドウ付き、1回だけ起動して4枚撮る。作業37・38）：
## 1) 2024年7月の作戦会議（印を付けた候補一覧・補強ポイント・本命の順番） 2) 有識者の予想のタブ
## 3) ドラフト会議の開幕の演出（有識者の12球団の1位予想） 4) ドラフトの候補一覧（印・予想の列、本命の1番目を選んである）
##
##   godot --path godot --resolution 960x540 --position <x>,<y> -s res://tests/draft_meeting_capture.gd -- <出力先>

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TEAM := "読売ジャイアンツ"

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
	_gs.new_game(TEAM, 2024)
	_gs.advance_through(Season.day_number("2024-07-10"))
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	_hub = current_scene
	_hub.call("_open_sub_screen", "meeting")
	await _settle()
	var view: Node = _hub.get("_meeting_view")
	var d: RefCounted = view.call("source")
	var by_hyouka: Array = d.candidates.duplicate()
	by_hyouka.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["hyouka"] > b["hyouka"])
	var plan := [[0, "◎"], [1, "◎"], [3, "○"], [5, "○"], [2, "✕"], [18, "☆"], [30, "△"]]
	for item: Array in plan:
		view.call("select_candidate", by_hyouka[item[0]]["id"])
		view.call("set_mark", item[1])
	view.call("set_memo", "制球が安定。中位で残っていれば")
	view.call("select_candidate", by_hyouka[0]["id"])
	await _shot("meeting_list")
	view.call("switch_tab", -1)
	await _shot("meeting_experts")
	_hub.call("_close_sub_screen")
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	_hub = current_scene
	_hub.call("_open_sub_screen", "draft")
	await _shot("draft_opening")
	var dv: Node = _hub.get("_draft_view")
	dv.call("finish_overlays")
	await _shot("draft_list")
	quit(0)


func _shot(name: String) -> void:
	await _settle()
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	if not _out.is_empty() and DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
		print("  スクショ: %s.png" % name)


func _settle() -> void:
	await create_timer(0.25).timeout
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
