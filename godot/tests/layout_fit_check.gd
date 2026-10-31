extends SceneTree
## 画面のはみ出しの確認（ヘッドレス可、約3分）。docs/AUTORUN.md 作業11。
## 2008年から始めて最後の年のオフまで進めながら、ハブを開いたままで次の画面を開き、表示中の全 Control の
## 右端・下端（左端・上端も）が画面（1280x720）の内側か調べる。はみ出したものを列挙して NG にする。
## - 毎年の開幕・7月：ハブ、日程表、采配の一覧と全サブ画面（1軍登録は全選手を1人ずつ選ぶ）、新戦力、システム、選手詳細の4タブ
## - 毎年のオフの各段階：ハブ、采配（オフは「見るだけ」の文言が出る）、FA・契約更改・戦力外の画面（全タブ・選手を選ぶ）、
##   ドラフト（開幕の演出・候補を選んで入札・抽選・指名一覧）、新戦力
## スクロールの中（clip_contents の子）は親が画面内なら見えないので調べない。
##
##   godot --headless --path godot -s res://tests/layout_fit_check.gd -- [自球団] [最後の年] [出力先]
##   （出力先はウィンドウ付きのときだけ。はみ出した画面のスクショを保存）

const SCREEN := Vector2(1280, 720)
## 端の許容（ピクセル）。フォーカスしたボタンの拡大（1.045倍）などの小さな揺れは許す
const TOLERANCE := 1.0
## 画面を開いてから調べるまで（UiFx の切り替えの演出 0.16秒が終わるまで）
const SETTLE_SEC := 0.2
const HUB_SCENE := "res://scenes/hub/hub.tscn"
const DETAIL_SCRIPT := "res://scenes/player_detail/player_detail.gd"
const TACTICS_PAGES := ["", "pitchers", "fielders", "practice", "order", "strategy", "rules", "info", "list"]

var _team := "福岡ソフトバンクホークス"
var _last_year := 2012
var _out := ""
var _failures := 0
var _checked := 0
var _gs: Node
var _hub: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].is_empty():
		_team = args[0]
	if args.size() > 1:
		_last_year = int(args[1])
	_out = args[2] if args.size() > 2 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	print("== 画面のはみ出し（%s、2008〜%d年オフ、画面 %s） ==" % [_team, _last_year, str(root.get_visible_rect().size)])
	_gs.new_game(_team)
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	_hub = current_scene
	while true:
		var y: int = _gs.year
		await _check_season(y, "%d年開幕" % y)
		while _gs.phase == _gs.Phase.SEASON and _gs.month < 7:
			_gs.advance()
		await _check_season(y, "%d年%d月" % [y, _gs.month])
		_gs.advance_through(_gs.season_last_day())
		while _gs.phase != _gs.Phase.SEASON:
			await _check_offseason(y)
			if y == _last_year and _gs.phase == _gs.Phase.DRAFT:
				break
			_gs.advance()
		if y >= _last_year:
			break
	print("\n調べた画面：%d" % _checked)
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


# --- シーズン中 ---------------------------------------------------------------------------

func _check_season(y: int, when: String) -> void:
	print("\n-- %s --" % when)
	await _check_screen("%s：ハブ" % when)
	for key in ["schedule", "scout", "system"]:
		await _open(key)
		await _check_screen("%s：%s" % [when, key])
		if key != "system":
			for i in 2:
				_hub.get("_" + ("schedule" if key == "schedule" else "scout") + "_view").switch_tab(1)
				await _check_screen("%s：%s タブ%d" % [when, key, i + 1])
		_hub.call("_close_sub_screen")
	await _check_tactics(when)
	await _check_detail(when)
	await _settle()
	_check(y == _gs.year, "%s：年が変わっていない" % when)


func _check_tactics(when: String) -> void:
	await _open("tactics")
	var tactics: Node = _hub.get("_tactics_view")
	for page: String in TACTICS_PAGES:
		tactics.call("_show_page", page, true)
		await _check_screen("%s：采配 %s" % [when, page if not page.is_empty() else "一覧"])
		if page in ["pitchers", "fielders"]:
			await _select_all(tactics.get("_register_" + page), "%s：采配 %s" % [when, page])
		elif page == "list":
			var roster: Node = tactics.get("_roster")
			for i in roster.get_tab_count() - 1:
				roster.switch_tab(1)
				await _check_screen("%s：采配 選手一覧 タブ%d" % [when, i + 2], 0.0)
	tactics.call("_show_page", "")
	_hub.call("_close_sub_screen")


## 1軍登録：全選手を1人ずつ選んで右の要約を出す（長い状態の文言・名前で広がらないか）
func _select_all(page: Node, label: String) -> void:
	var team: Variant = _gs.my_team()
	if team == null:
		return
	var worst := ""
	for p: Variant in team.players:
		if p.is_pitcher != page.get("pitchers"):
			continue
		page.set("_selected", p)
		page.refresh()
		await _frames(2)
		var over := _overflows()
		if not over.is_empty() and worst.is_empty():
			worst = "%s（%s を選んだとき）" % [label, p.name]
			_report(worst, over)
	_checked += 1
	if worst.is_empty():
		print("OK %s：全選手を選んでもはみ出さない" % label)
	page.clear_selection()


## 選手詳細：自球団の先頭の選手と名前の長い選手の4タブ
func _check_detail(when: String) -> void:
	var ids: Array = load(DETAIL_SCRIPT).team_order(_gs.team)
	if ids.is_empty():
		return
	var longest: String = ids[0]
	for id: String in ids:
		if str(root.get_node("GameData").player(id).get("name", "")).length() \
				> str(root.get_node("GameData").player(longest).get("name", "")).length():
			longest = id
	for id: String in [ids[0], longest]:
		var detail: Node = load(DETAIL_SCRIPT).open(_hub, id, ids)
		await _frames(2)
		for i in 4:
			detail.show_tab(i)
			await _check_screen("%s：選手詳細（%s）タブ%d" % [when, detail.get("_data").get("name", id), i + 1])
		detail.close()
		await _frames(2)


# --- オフ ---------------------------------------------------------------------------------

func _check_offseason(y: int) -> void:
	var when := "%d年オフ %s" % [y, _gs.phase_name()]
	print("\n-- %s --" % when)
	await _check_screen("%s：ハブ" % when)
	await _open("tactics")
	var tactics: Node = _hub.get("_tactics_view")
	for page: String in ["", "pitchers", "fielders", "order"]:
		tactics.call("_show_page", page, true)
		await _check_screen("%s：采配 %s" % [when, page if not page.is_empty() else "一覧"])
		if page == "pitchers":
			await _select_all(tactics.get("_register_pitchers"), "%s：采配 pitchers" % when)
	tactics.call("_show_page", "")
	_hub.call("_close_sub_screen")
	await _open("scout")
	await _check_screen("%s：新戦力" % when)
	_hub.call("_close_sub_screen")
	if _gs.fa_open():
		await _check_phase_view("fa", "_fa_view", when)
	elif _gs.contract_open():
		await _check_phase_view("contract", "_contract_view", when)
	elif _gs.release_open():
		await _check_phase_view("release", "_release_view", when)
	elif _gs.draft_open():
		await _check_draft(when)


## FA・契約更改・戦力外：全タブを開き、各タブの先頭の選手を選ぶ
func _check_phase_view(key: String, prop: String, when: String) -> void:
	await _open(key)
	var view: Node = _hub.get(prop)
	await _check_screen("%s：%s" % [when, key])
	for i in 4:
		var ids: Array = view.list_ids()
		if not ids.is_empty():
			view.select_player(ids[-1])
			await _check_screen("%s：%s タブ%d 選択" % [when, key, i + 1], 0.0)
			view.select_player(ids[0])
			await _check_screen("%s：%s タブ%d 選択" % [when, key, i + 1], 0.0)
		view.switch_tab(1)
		await _check_screen("%s：%s タブ%d" % [when, key, i + 2], 0.0)
	while view.back():
		pass
	_hub.call("_close_sub_screen")


func _check_draft(when: String) -> void:
	await _open("draft")
	var view: Node = _hub.get("_draft_view")
	await _check_screen("%s：ドラフト 開幕の演出" % when)
	view.finish_overlays()
	await _check_screen("%s：ドラフト 候補一覧" % when)
	for i in 3:
		view.switch_tab(1)
		await _check_screen("%s：ドラフト タブ%d" % [when, i + 2], 0.0)
	var ids: Array = view.list_ids()
	if not ids.is_empty():
		view.select_candidate(ids[0])
		await _check_screen("%s：ドラフト 候補を選ぶ" % when, 0.0)
		view.press_action()
		await _check_screen("%s：ドラフト 入札" % when)
		view.finish_overlays()
		await _check_screen("%s：ドラフト 入札のあと" % when)
	while view.back():
		pass
	_hub.call("_close_sub_screen")


# --- 調べる -------------------------------------------------------------------------------

func _open(key: String) -> void:
	_hub.call("_open_sub_screen", key)
	await _settle()


func _check_screen(label: String, wait := SETTLE_SEC) -> void:
	if wait > 0.0:
		await create_timer(wait).timeout
	await _frames(2)
	_checked += 1
	var over := _overflows()
	if not over.is_empty():
		_report(label, over)


func _report(label: String, over: Array[String]) -> void:
	_failures += 1
	print("NG %s：画面からはみ出す %d件" % [label, over.size()])
	for line in over.slice(0, 8):
		print("    ", line)
	if not _out.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out.path_join("overflow_%d.png" % _failures))


## 表示中の Control で画面からはみ出すもの（はみ出した枝の一番上だけ。中身の最小幅の内訳を添える）
func _overflows() -> Array[String]:
	var result: Array[String] = []
	_walk(root, result)
	return result


func _walk(node: Node, result: Array[String]) -> void:
	if node is Window and node != root:
		return  # ツールチップ・ポップアップは別のウィンドウ
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is CanvasLayer and not (node as CanvasLayer).visible:
		return
	if node is Control:
		var c := node as Control
		var r := c.get_global_rect()
		if r.size.x > 0.0 and r.size.y > 0.0 and _outside(r):
			result.append("%s %s（最小 %s）%s" % [_name(c), _rect_text(r), str(c.get_combined_minimum_size()),
				_widest(c)])
			return
		if c.clip_contents:
			return  # スクロールの中など：親の枠で切り取られる
	for child in node.get_children():
		_walk(child, result)


func _outside(r: Rect2) -> bool:
	return r.position.x < -TOLERANCE or r.position.y < -TOLERANCE \
		or r.end.x > SCREEN.x + TOLERANCE or r.end.y > SCREEN.y + TOLERANCE


## 最小幅がいちばん大きい子をたどる（どこで広がったかの手がかり）
func _widest(c: Control) -> String:
	var chain: Array[String] = []
	var node: Control = c
	for depth in 8:
		var best: Control = null
		for child in node.get_children():
			if child is Control and (child as Control).visible:
				if best == null or child.get_combined_minimum_size().x > best.get_combined_minimum_size().x:
					best = child
		if best == null:
			break
		node = best
		var text := ""
		if node is Label:
			text = "「%s」" % (node as Label).text.left(30)
		elif node is Button:
			text = "「%s」" % (node as Button).text.left(30)
		chain.append("%s%s:%d" % [node.get_class(), text, int(node.get_combined_minimum_size().x)])
	return "\n        ← " + " > ".join(chain) if not chain.is_empty() else ""


func _name(c: Control) -> String:
	var parts: Array[String] = []
	var node: Node = c
	while node != null and node != root and parts.size() < 4:
		var n := str(node.name)
		parts.push_front(node.get_class() if n.begins_with("@") else n)
		node = node.get_parent()
	return "/".join(parts)


func _rect_text(r: Rect2) -> String:
	return "(%d,%d)-(%d,%d)" % [int(r.position.x), int(r.position.y), int(r.end.x), int(r.end.y)]


func _check(ok: bool, label: String) -> void:
	if not ok:
		print("NG ", label)
		_failures += 1


func _settle() -> void:
	await create_timer(SETTLE_SEC).timeout
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
