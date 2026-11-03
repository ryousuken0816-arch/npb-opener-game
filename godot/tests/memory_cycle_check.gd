extends SceneTree
## 画面の開け閉めでメモリが漏れないかの点検（docs/AUTORUN.md 作業55、ヘッドレス）。
## iPhone の Web 版で、ボタンを何回か押すと「WebGL context lost」で落ちた件の調べ。
## スマホの縦（390x844、TouchAdapt が効く）で、画面ごとに「開く→中を一通り操作→閉じる」を繰り返し、
## 1回あたりのオブジェクト数・ノード数・取り残されたノード（ツリーの外で解放されていない）・リソース数・メモリの増え方を出す。
## 最初の2回は準備（読み込みのキャッシュ）として数えない。増え方が 1回あたり OBJ_LIMIT 個を超える画面は NG。
## 最後に起動直後・ハブ・1シーズン後のメモリも出す。
##
##   godot --headless --path godot -s res://tests/memory_cycle_check.gd -- [回数] [pc]
##   （既定は 10 回・スマホ表示。pc を付けるとパソコン表示）

const PORTRAIT := Vector2i(390, 844)
const PC := Vector2i(1280, 720)
const HUB_SCENE := "res://scenes/hub/hub.tscn"
const DETAIL_SCRIPT := "res://scenes/player_detail/player_detail.gd"
const TACTICS_PAGES := ["", "pitchers", "fielders", "practice", "order", "strategy", "rules", "info", "list"]
const WARMUP := 2
## 1回あたりこれより多く増え続けたら漏れとみなす（文字や一覧の行の数の小さな揺れは許す）
const OBJ_LIMIT := 5.0
const MB := 1048576.0

var _cycles := 10
var _mobile := true
var _gs: Node
var _hub: Node
var _ng := 0
var _rows: Array[String] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].is_empty():
		_cycles = int(args[0])
	_mobile = not (args.size() > 1 and args[1] == "pc")
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	var mem_boot := OS.get_static_memory_usage()
	if _mobile:
		root.get_node("UiLayout").set_force_mode("mobile")
	root.size = PORTRAIT if _mobile else PC
	await _frames(4)
	print("==== 開け閉めの点検（%s、%d回） ====" % ["スマホの縦" if _mobile else "パソコン", _cycles])
	print("起動直後: %s" % _mem_text(mem_boot))
	_gs.new_game("福岡ソフトバンクホークス", 2008)
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	_hub = current_scene
	await _settle()
	var mem_hub := OS.get_static_memory_usage()
	print("新しいゲーム・ハブ: %s" % _mem_text(mem_hub))

	await _measure("ハブ（何もしない）", _idle)
	await _measure("采配（全ページ）", _cycle_tactics)
	await _measure("選手詳細（4タブ）", _cycle_detail)
	await _measure("日程表", _cycle_simple.bind("schedule"))
	await _measure("新戦力", _cycle_scout)
	await _measure("記録室（全タブ）", _cycle_records)
	await _measure("作戦会議", _cycle_meeting)
	await _measure("新聞", _cycle_simple.bind("news"))
	await _measure("システム", _cycle_simple.bind("system"))
	# 歴代メンバー・歴代ドラフトで年を全部見る（年ごとの持ち物が増え続けないか。1回だけ）
	var history: GDScript = load("res://scenes/hub/records_history.gd")
	var m0 := OS.get_static_memory_usage()
	for y: int in history.member_years():
		history.members(y, _gs.team)
	for y: int in history.draft_years():
		history.draft_picks(y, _gs.team)
	await _settle()
	print("歴代メンバー %d年・歴代ドラフト %d年を見る: %+.1fMB" % [history.member_years().size(),
		history.draft_years().size(), (OS.get_static_memory_usage() - m0) / MB])

	_gs.advance_through(_gs.season_last_day())
	await _settle()
	print("1シーズン後: %s" % _mem_text(OS.get_static_memory_usage()))
	if _gs.skip_to_phase(_gs.Phase.CONTRACT):
		await _measure("契約更改（選んで・タブ）", _cycle_contract)
	if _gs.skip_to_phase(_gs.Phase.DRAFT):
		await _measure("ドラフト（手帳・ボード・表）", _cycle_draft)

	print("\n%-26s %10s %8s %8s %8s %10s" % ["画面", "オブジェクト", "ノード", "取り残し", "リソース", "メモリKB"])
	for r in _rows:
		print(r)
	print("\n== 結果: %s ==" % ("ALL OK" if _ng == 0 else "FAILED（%d件）" % _ng))
	quit(0 if _ng == 0 else 1)


func _measure(label: String, cycle: Callable) -> void:
	for i in WARMUP:
		await cycle.call()
	await _settle()
	var a := _snap()
	for i in _cycles:
		await cycle.call()
	await _settle()
	var b := _snap()
	var per := {}
	for k: String in a:
		per[k] = float(b[k] - a[k]) / _cycles
	var bad: bool = per["objects"] > OBJ_LIMIT or per["orphans"] > 0.5
	if bad:
		_ng += 1
	_rows.append("%-26s %10.1f %8.1f %8.1f %8.1f %10.1f %s" % [label, per["objects"], per["nodes"], per["orphans"],
		per["resources"], per["mem"] / 1024.0, "NG" if bad else "OK"])
	print("%s：%d回で オブジェクト %+d・ノード %+d・取り残し %+d・リソース %+d・メモリ %+.1fMB %s" % [label, _cycles,
		b["objects"] - a["objects"], b["nodes"] - a["nodes"], b["orphans"] - a["orphans"],
		b["resources"] - a["resources"], (b["mem"] - a["mem"]) / MB, "NG" if bad else "OK"])


func _snap() -> Dictionary:
	return {
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"mem": OS.get_static_memory_usage(),
	}


func _mem_text(bytes: int) -> String:
	return "%.1fMB（オブジェクト %d・ノード %d）" % [bytes / MB, int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))]


# --- 1回ぶんの操作 --------------------------------------------------------------------------

func _idle() -> void:
	await _frames(2)


func _cycle_simple(key: String) -> void:
	await _open(key)
	_hub.call("_close_sub_screen")
	await _frames(2)


func _cycle_tactics() -> void:
	await _open("tactics")
	var tactics: Node = _hub.get("_tactics_view")
	for page: String in TACTICS_PAGES:
		tactics.call("_show_page", page, true)
		await _frames(2)
		if page in ["pitchers", "fielders"]:
			var reg: Node = tactics.get("_register_" + page)
			for p: Variant in _gs.my_team().players:
				if p.is_pitcher == reg.get("pitchers"):
					reg.set("_selected", p)
					reg.refresh()
					await _frames(1)
					break
			reg.clear_selection()
		elif page == "list":
			var roster: Node = tactics.get("_roster")
			for i in roster.get_tab_count():
				roster.switch_tab(1)
				await _frames(1)
	tactics.call("_show_page", "")
	_hub.call("_close_sub_screen")
	await _frames(2)


func _cycle_detail() -> void:
	var ids: Array = load(DETAIL_SCRIPT).team_order(_gs.team)
	var detail: Node = load(DETAIL_SCRIPT).open(_hub, ids[0], ids)
	await _frames(2)
	for i in 4:
		detail.show_tab(i)
		await _frames(1)
	detail.close()
	await _frames(2)


func _cycle_scout() -> void:
	await _open("scout")
	for i in 4:
		_hub.get("_scout_view").switch_tab(1)
		await _frames(1)
	_hub.call("_close_sub_screen")
	await _frames(2)


func _cycle_records() -> void:
	await _open("records")
	var view: Node = _hub.get("_records_view")
	for t: Array in view.TABS:
		view.set_tab(t[0])
		await _frames(2)
	view.set_tab(view.TABS[0][0])
	_hub.call("_close_sub_screen")
	await _frames(2)


func _cycle_meeting() -> void:
	await _open("meeting")
	var view: Node = _hub.get("_meeting_view")
	var ids: Array = view.list_ids()
	if not ids.is_empty():
		view.select_candidate(ids[0])
	view.set_mode("table")
	await _frames(1)
	for i in 4:
		view.switch_tab(1)
		await _frames(1)
	view.set_mode("book")
	_hub.call("_close_sub_screen")
	await _frames(2)


func _cycle_contract() -> void:
	await _open("contract")
	var view: Node = _hub.get("_contract_view")
	for i in 3:
		var ids: Array = view.list_ids()
		for id: String in ids.slice(0, 3):
			view.select_player(id)
			await _frames(1)
		view.switch_tab(1)
		await _frames(1)
	while view.back():
		pass
	_hub.call("_close_sub_screen")
	await _frames(2)


func _cycle_draft() -> void:
	await _open("draft")
	var view: Node = _hub.get("_draft_view")
	view.finish_overlays()
	view.switch_tab(1)
	await _frames(1)
	view.set_mode("board")
	await _frames(1)
	view.set_mode("table")
	await _frames(1)
	for i in 3:
		view.switch_tab(1)
		await _frames(1)
	view.set_mode("book")
	var ids: Array = view.list_ids()
	for id: String in ids.slice(0, 3):
		view.select_candidate(id)
		await _frames(1)
	while view.back():
		pass
	_hub.call("_close_sub_screen")
	await _frames(2)


func _open(key: String) -> void:
	_hub.call("_open_sub_screen", key)
	await _settle()


func _settle() -> void:
	await create_timer(0.25).timeout
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
