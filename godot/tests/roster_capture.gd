extends SceneTree
## 所属・年俸・外国人市場の確認用スクリーンショット：2008年開幕の契約タブ・情報（12球団の年俸総額）→
## シーズンを終えてオフへ進め、FA・トレード・ポスティングで新戦力（外国人市場・出来事）→ 1人獲得 →
## 契約更改後の情報 → 2009年の開幕で契約タブ（年俸の推移）と選手一覧（年俸の列）。
##
##   xvfb-run godot --path godot --resolution 1280x720 \
##       --script res://tests/roster_capture.gd -- <出力先> [球団名]

const KANEMOTO := "41343885"  # 金本知憲（阪神）

var _out := ""
var _team := "阪神タイガース"
var _gs: Node
var _hub: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	if args.size() > 1:
		_team = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	var gd: Node = root.get_node("GameData")
	_gs.new_game(_team)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(5)
	_hub = current_scene
	var star := KANEMOTO if not gd.player(KANEMOTO).is_empty() else str(gd.players_of(_team)[0]["id"])
	await _contract_shot(star, "r1_contract_2008")
	await _info_shot("r2_info_2008")

	# シーズンを終えて FA・トレード・ポスティングへ
	_gs.advance_through(_gs.season_last_day())
	while _gs.phase != _gs.Phase.FA_TRADE:
		_gs.advance()
	_hub.call("_open_sub_screen", "scout")
	await _frames(3)
	await _shot("r3_market_%s" % _gs.phase_name())
	# 一番上（提示額の高い順）の候補を獲得
	var scout: Node = _hub.get("_scout_view")
	var tree: Tree = scout.get("_market_tree")
	var first := tree.get_root().get_first_child()
	if first != null:
		tree.set_selected(first, 0)
		scout.call("_sign_selected")
	await _frames(3)
	await _shot("r4_market_signed")
	scout.call("switch_tab", 1)
	await _frames(3)
	await _shot("r5_events")
	_hub.call("_close_sub_screen")

	while _gs.phase != _gs.Phase.DRAFT:
		_gs.advance()
	await _info_shot("r6_info_after_contract")
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	await _frames(3)
	await _shot("r7_hub_%d" % _gs.year)
	await _contract_shot(star, "r8_contract_%d" % _gs.year)
	_hub.call("_open_sub_screen", "tactics")
	var view: Node = _hub.get_node("%TacticsView")
	view.call("_show_page", "list")
	await _frames(3)
	await _shot("r9_list_salary")
	var league: Variant = _gs.league
	print("%s 年俸の推移: %s" % [league.names.get(star, star), str(league.salary_history.get(star))])
	quit()


func _contract_shot(id: String, name: String) -> void:
	var detail: Control = load("res://scenes/player_detail/player_detail.gd").open(_hub, id)
	await _frames(3)
	detail.call("show_tab", 3)
	await _frames(3)
	await _shot(name)
	detail.call("close")
	await _frames(3)


func _info_shot(name: String) -> void:
	_hub.call("_open_sub_screen", "tactics")
	var view: Node = _hub.get_node("%TacticsView")
	view.call("_show_page", "info")
	await _frames(3)
	await _shot(name)
	_hub.call("_close_sub_screen")
	_hub.call("_close_sub_screen")
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, wait := 0.3) -> void:
	if wait > 0.0:
		await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(_out.path_join(name + ".png"))
	print("saved ", name)
