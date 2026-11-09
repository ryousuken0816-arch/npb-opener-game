extends SceneTree
## ドラフトの「スカウトの手帳」（docs/AUTORUN.md 作業51）の確認。ヘッドレス可。出力先を渡してウィンドウ付きで流すと
## 1回の起動の中でスクショを6枚撮り、3x2に並べた1枚（draft_notebook.png）にする：
##   1) 2026年の手帳（◎を付けた投手のページ）と指名ボード
##   2) 1位が決まったあとの指名ボード（12球団のマグネット）と、自球団の番の手帳
##   3) 表に切り替えた候補一覧（1年目・将来性の列が無い）
##   4) 作戦会議の手帳
##   5) 2028年（架空の候補）の手帳
##   6) 2028年のドラフトの終わりの指名ボード
## 確かめること：手帳が最初の画面・左右にめくれる・採点表（投手6項目＝球速の数字、野手6項目）と色分け・寸評3〜4行・札・
## 切り抜き・◎とメモが DraftBoard に残る・「この男でいく」で入札・指名できる・指名ボードが埋まる・表に切り替えられる・
## 画面のどこにも「1年目」「将来性」が出ない・縦長の画面で手帳とボードを切り替えられる・2027年→2028年へ進めてもボードの年が追従
##
##   godot --headless --path godot -s res://tests/draft_notebook_check.gd
##   godot --path godot --resolution 960x540 --position <x>,<y> -s res://tests/draft_notebook_check.gd -- <出力先>

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TEAM := "阪神タイガース"
const BANNED := ["1年目", "将来性"]

var _out := ""
var _failures := 0
var _gs: Node
var _hub: Node
var _shots: Array[Image] = []
var _ds: GDScript
var _sn: GDScript
var _db: GDScript


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
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(1280, 720)  # layout_fit_check と同じ画面の大きさで測る
	_gs = root.get_node("GameState")
	_ds = load("res://sim/draft.gd")
	_ds.lottery_seed = 1  # 抽選の当たりはテストのときだけ決めた種で引く（作業58。本番はその場で引く）
	_sn = load("res://sim/scout_notes.gd")
	_db = load("res://sim/draft_board.gd")
	_gs.new_game(TEAM, 2026)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	_hub = current_scene
	await _check_2026()
	await _check_meeting()
	await _check_portrait()
	await _check_2028()
	_save_grid()
	print("\n%s" % ("全項目OK" if _failures == 0 else "NG %d件" % _failures))
	quit(1 if _failures > 0 else 0)


# --- 2026年 ------------------------------------------------------------------------------

func _check_2026() -> void:
	print("== 2026年のドラフト：手帳・指名ボード・表 ==")
	_hub.call("_open_sub_screen", "draft")
	await _settle()
	var view: Node = _hub.get("_draft_view")
	view.call("finish_overlays")
	await _settle()
	var d: RefCounted = _gs.draft()
	var nb: Control = view.call("notebook")
	var board: Control = view.call("pick_board")
	_check(view.call("mode") == "book" and nb.is_visible_in_tree() and board.is_visible_in_tree(),
		"最初は手帳と指名ボード（%s）" % view.call("mode"))
	_check(_banned_texts(view).is_empty(), "手帳の画面に「1年目」「将来性」が無い %s" % str(_banned_texts(view)))
	var first: String = view.call("selected_id")
	_check(not first.is_empty() and d.by_id.has(first), "手帳に1人目のページ（%s）" % d.by_id.get(first, {}).get("name", "?"))
	await _check_fit(view, nb, board)
	view.call("switch_tab", 1)
	var second: String = view.call("selected_id")
	view.call("flip", -1)
	_check(second != first and view.call("selected_id") == first, "LB/RB・めくるでページが変わり、戻せる")
	# 投手のページ：採点表は球速の数字＋5項目
	var pitcher := _first_where(d, func(c: Dictionary) -> bool: return c["pitcher"] and int(c["velocity"]) > 0)
	var batter := _first_where(d, func(c: Dictionary) -> bool: return not c["pitcher"])
	var cells: Array = _sn.sheet(d, d.by_id[pitcher])
	_check(cells.size() == 6 and cells[0]["label"] == "球速" and str(cells[0]["text"]).is_valid_int()
		and cells[1]["label"] == "決め球" and cells[1]["text"] != "-" and cells[3]["label"] == "球種" and cells[3]["text"] != "-",
		"投手の採点表：球速の数字と決め球・制球・球種・スタミナ・総合（作業79。%s）" % _cells_text(cells))
	var bcells: Array = _sn.sheet(d, d.by_id[batter])
	_check(bcells.size() == 6 and bcells[5]["label"] == "肩", "野手の採点表：ミート・パワー・選球眼・走力・守備・肩（%s）"
		% _cells_text(bcells))
	var tiers := {}
	for c: Dictionary in d.candidates:
		for cell: Dictionary in _sn.sheet(d, c):
			tiers[cell["tier"]] = int(tiers.get(cell["tier"], 0)) + 1
	_check(int(tiers.get("good", 0)) > 0 and int(tiers.get("normal", 0)) > 0 and int(tiers.get("weak", 0)) > 0,
		"採点表の色分け：良い・ふつう・弱点がそろう %s" % str(tiers))
	var short := 0
	var no_trait := 0
	var clips := 0
	for c: Dictionary in d.candidates:
		var lines: Array = _sn.comments(d, c)
		if lines.size() < 3 or lines.size() > 4:
			short += 1
		if _sn.traits(d, c).is_empty():
			no_trait += 1
		if _sn.clipping(c, d.year).get("source", "") == "スポーツ紙":
			clips += 1
	_check(short == 0, "全員の寸評が3〜4行（外れ %d人）" % short)
	_check(no_trait * 10 < d.candidates.size(), "ほぼ全員に特徴の札（札なし %d/%d人）" % [no_trait, d.candidates.size()])
	print("  スポーツ紙の切り抜きがある候補 %d/%d人（無ければスカウトのメモ）" % [clips, d.candidates.size()])
	print("  例：%s" % _page_text(d, d.by_id[pitcher]))
	print("  例：%s" % _page_text(d, d.by_id[batter]))
	# ◎とメモ
	view.call("select_candidate", pitcher)
	await _settle()
	nb.emit_signal("mark_requested", "◎")
	(nb.call("memo_edit") as LineEdit).text = "真っすぐで押せる"
	(nb.call("memo_edit") as LineEdit).text_changed.emit("真っすぐで押せる")
	await _settle()
	var key: String = _db.key_of(d.by_id[pitcher])
	_check(_gs.draft_board.mark_of(d.year, key) == "◎" and _gs.draft_board.memo_of(d.year, key) == "真っすぐで押せる",
		"手帳の◎と書き込みが作戦会議の印・メモに残る")
	_check(d.user_recommend() == pitcher, "◎を付けた候補がおすすめ（1位入札の初期値）になる")
	await _shot()
	# 1位入札：「この男でいく」
	var guard := 0
	while d.stage == _ds.Stage["FIRST"] and guard < 10:
		guard += 1
		if d.first_pick_of(TEAM).is_empty():
			var target := _best_left(d)
			if view.call("selected_id") != target:
				view.call("select_candidate", target)
			await _settle()
			_check((nb.call("go_button") as Button).text.begins_with("この男でいく") and not (nb.call("go_button") as Button).disabled,
				"「%s」で入札できる" % (nb.call("go_button") as Button).text)
			nb.emit_signal("go_pressed")
		else:
			view.call("_continue_first")
		view.call("finish_overlays")
		await _settle()
	_check(d.stage == _ds.Stage["WAIVER"] and not d.first_pick_of(TEAM).is_empty(),
		"1位が決まりウェーバーへ（自球団：%s）" % d.by_id.get(d.first_pick_of(TEAM), {}).get("name", "?"))
	_check(_board_magnets(board) >= 12, "指名ボードに12球団の1位のマグネット（%d枚）" % _board_magnets(board))
	# 2位以降：自球団の番まで飛ばして、手帳で指名
	var picked := 0
	guard = 0
	while d.stage == _ds.Stage["WAIVER"] and picked < 2 and guard < 50:
		guard += 1
		if d.is_user_turn():
			view.call("set_filter", "left")
			await _settle()
			view.call("flip", 1)
			await _settle()
			var before: int = d.picks_of(TEAM).size()
			if picked == 1:
				await _shot()
			nb.emit_signal("go_pressed")
			view.call("finish_overlays")
			await _settle()
			if d.picks_of(TEAM).size() > before:
				picked += 1
		else:
			view.call("_on_skip_pressed")
			view.call("finish_overlays")
			await _settle()
	_check(picked == 2, "2位・3位を手帳の「この男でいく」で指名（%s）" % _names(d, TEAM))
	_check(_own_row_magnets(board, d) == d.picks_of(TEAM).size(), "自球団の行に指名のマグネット（%d枚）"
		% _own_row_magnets(board, d))
	# 表に切り替え
	view.call("set_filter", "all")
	nb.emit_signal("table_requested")
	await _settle()
	_check(view.call("mode") == "table" and not (view.call("list_ids") as Array).is_empty() and not nb.is_visible_in_tree(),
		"表に切り替えると候補一覧（%d人）" % (view.call("list_ids") as Array).size())
	var header_keys: Array = (view.get("_header_buttons") as Dictionary).keys()
	_check(not "first" in header_keys and not "future" in header_keys and "hyouka" in header_keys,
		"表の列に1年目・将来性が無い（%s）" % ",".join(header_keys))
	for i in 3:
		view.call("finish_overlays")  # CPU 球団の指名の発表が出ているとタブが変わらない
		view.call("switch_tab", 1)
		await _settle()
		_check(_banned_texts(view).is_empty(), "表のタブ「%s」に1年目・将来性が無い %s" % [view.get("_tab"), str(_banned_texts(view))])
	view.call("finish_overlays")
	view.call("switch_tab", 1)  # 情報へ戻る
	await _settle()
	await _shot()
	view.call("set_mode", "book")
	await _settle()
	_check(view.call("mode") == "book" and nb.is_visible_in_tree(), "手帳に戻せる")
	view.call("_on_complete_pressed")
	await _settle()
	_check(d.resolved and d.stage == _ds.Stage["DONE"], "残りをおまかせで終える")
	_check(board.get("_sub").text.contains("終わり"), "指名ボードの見出しが終わり（%s）" % board.get("_sub").text)


## 横長（1280x720）で手帳の1ページがスクロールなしで収まるか（最初の30枚で一番長いページ）・ボードの行が何行見えるか
func _check_fit(view: Node, nb: Control, board: Control) -> void:
	var sc: ScrollContainer = nb.get("_scroll")
	var worst := 0.0
	var worst_name := ""
	var start: String = view.call("selected_id")
	for i in 30:
		await _frames(2)
		var need: float = (sc.get_child(0) as Control).get_combined_minimum_size().y
		if need > worst:
			print("    %s：左 %d・右 %d" % [_gs.draft().by_id[view.call("selected_id")]["name"],
				int((nb.get("_left") as Control).get_combined_minimum_size().y), int((nb.get("_right") as Control).get_combined_minimum_size().y)])
			worst = need
			worst_name = _gs.draft().by_id[view.call("selected_id")]["name"]
		view.call("flip", 1)
	view.call("select_candidate", start)
	await _settle()
	_check(worst <= sc.size.y + 1.0, "横長で手帳の1ページがスクロールなしで収まる（いちばん長い %s：中身 %d／枠 %d、手帳 %dx%d）"
		% [worst_name, int(worst), int(sc.size.y), int(nb.size.x), int(nb.size.y)])
	var rows_scroll: ScrollContainer = board.get("_rows_scroll")
	var row_h: float = (board.get("_rows") as Control).get_child(0).size.y if (board.get("_rows") as Control).get_child_count() > 0 else 1.0
	print("  指名ボード：行の欄 %d（1行 %d → %.1f行見える）、ボード %dx%d" % [int(rows_scroll.size.y), int(row_h),
		rows_scroll.size.y / maxf(row_h, 1.0), int(board.size.x), int(board.size.y)])


# --- 作戦会議 -----------------------------------------------------------------------------

func _check_meeting() -> void:
	print("== 作戦会議の手帳 ==")
	_hub.call("_close_sub_screen")
	await _settle()
	_hub.call("_open_sub_screen", "meeting")
	await _settle()
	var view: Node = _hub.get("_meeting_view")
	var nb: Control = view.call("notebook")
	_check(view.call("mode") == "book" and nb != null and nb.is_visible_in_tree(), "作戦会議も手帳の見た目")
	_check(_banned_texts(view).is_empty(), "作戦会議に「1年目」「将来性」が無い %s" % str(_banned_texts(view)))
	var first: String = view.call("selected_id")
	view.call("switch_tab", 1)
	_check(view.call("selected_id") != first, "作戦会議でもめくれる")
	nb.emit_signal("mark_requested", "☆")
	await _settle()
	var d: RefCounted = view.call("source")
	_check(_gs.draft_board.mark_of(d.year, _db.key_of(d.by_id[view.call("selected_id")])) == "☆",
		"作戦会議の手帳で印を付けられる")
	await _shot()
	view.call("set_mode", "table")
	await _settle()
	_check(not (view.call("list_ids") as Array).is_empty() and _banned_texts(view).is_empty(), "作戦会議の表（1年目・将来性なし）")
	view.call("set_mode", "book")
	_hub.call("_close_sub_screen")
	await _settle()


# --- 縦長の画面 ---------------------------------------------------------------------------

func _check_portrait() -> void:
	print("== 縦長の画面（スマホ） ==")
	var layout: Node = root.get_node("UiLayout")
	var old_size := root.size
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(390, 844)  # 縦かどうかは画面の向きで決まる（担当M）
	layout.call("set_force_mode", "mobile")
	await _settle()
	_hub.call("_open_sub_screen", "draft")
	await _settle()
	var view: Node = _hub.get("_draft_view")
	view.call("finish_overlays")
	var nb: Control = view.call("notebook")
	var board: Control = view.call("pick_board")
	_check(nb.is_visible_in_tree() and not board.is_visible_in_tree(), "縦長では手帳だけ")
	view.call("set_mode", "board")
	await _settle()
	_check(not nb.is_visible_in_tree() and board.is_visible_in_tree(), "「ボード」で指名ボードだけ")
	_check(view.call("back") == true and view.call("mode") == "book", "Ⓑでボードから手帳へ戻る")
	_hub.call("_close_sub_screen")
	root.size = old_size
	layout.call("set_force_mode", "pc")
	await _settle()


# --- 2028年（架空の候補） ------------------------------------------------------------------

func _check_2028() -> void:
	print("== 2028年のドラフト（架空の候補） ==")
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	_gs.skip_to_phase(_gs.Phase.DRAFT)  # 2027年のドラフト
	_gs.draft_resolve()
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	_check(_gs.year == 2028, "2028年へ進む（%s）" % _gs.date_text())
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	_gs.changed.emit()
	await _settle()
	_hub.call("_open_sub_screen", "draft")
	await _settle()
	var view: Node = _hub.get("_draft_view")
	view.call("finish_overlays")
	view.call("set_filter", "all")
	await _settle()
	var d: RefCounted = _gs.draft()
	var nb: Control = view.call("notebook")
	var board: Control = view.call("pick_board")
	var c: Dictionary = d.by_id.get(view.call("selected_id"), {})
	_check(d.year == 2028 and c.get("fictional", false), "2028年の手帳に架空の候補（%s・%s）" % [c.get("name", "?"),
		c.get("school", "?")])
	_check(board.get("_title").text == "指名ボード 2028", "指名ボードの年が追従（%s）" % board.get("_title").text)
	print("  例：%s" % _page_text(d, c))
	await _shot()
	var guard := 0
	while d.stage == _ds.Stage["FIRST"] and guard < 10:
		guard += 1
		if d.first_pick_of(TEAM).is_empty():
			var best := _best_left(d)
			if view.call("selected_id") != best:  # 選んでいる候補をもう一度選ぶと選手詳細が開く
				view.call("select_candidate", best)
			await _settle()
			nb.emit_signal("go_pressed")
		else:
			view.call("_continue_first")
		view.call("finish_overlays")
		await _settle()
	_check(not d.first_pick_of(TEAM).is_empty(), "2028年も手帳から1位を入札して決まる（%s）"
		% d.by_id.get(d.first_pick_of(TEAM), {}).get("name", "?"))
	guard = 0
	while d.stage == _ds.Stage["WAIVER"] and d.picks_of(TEAM).size() < 2 and guard < 50:
		guard += 1
		if d.is_user_turn():
			view.call("set_filter", "left")
			await _settle()
			nb.emit_signal("go_pressed")
		else:
			view.call("_on_skip_pressed")
		view.call("finish_overlays")
		await _settle()
	_check(d.picks_of(TEAM).size() >= 2, "2028年の2位を手帳で指名（%s）" % _names(d, TEAM))
	view.call("_on_complete_pressed")
	await _settle()
	_check(d.resolved and _board_magnets(board) == d.picks.size(), "ドラフトの終わりに指名ボードが全員分埋まる（%d／%d枚）"
		% [_board_magnets(board), d.picks.size()])
	await _shot()
	_hub.call("_close_sub_screen")
	guard = 0
	while _gs.phase != _gs.Phase.CAMP and guard < 10:  # 作業54：ドラフトのあとに FA・現役ドラフト
		guard += 1
		_gs.advance()
	_check(_gs.phase == _gs.Phase.CAMP and _gs.year == 2029, "春季キャンプへ（%s）" % _gs.date_text())


# --- 道具 --------------------------------------------------------------------------------

## 画面に出ている文字のうち「1年目」「将来性」を含むもの
func _banned_texts(node: Node) -> Array[String]:
	var found: Array[String] = []
	_collect_banned(node, found)
	return found


func _collect_banned(node: Node, found: Array[String]) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	var texts: Array[String] = []
	if node is Label:
		texts.append((node as Label).text)
	if node is Button:
		texts.append((node as Button).text)
	if node is Control:
		texts.append((node as Control).tooltip_text)
	for t: String in texts:
		for word: String in BANNED:
			if word in t:
				found.append(t.substr(0, 30))
	for child in node.get_children():
		_collect_banned(child, found)


func _first_where(d: RefCounted, pred: Callable) -> String:
	for c: Dictionary in d.candidates:
		if pred.call(c):
			return c["id"]
	return ""


func _best_left(d: RefCounted) -> String:
	var best := ""
	for c: Dictionary in d.candidates:
		if str(c["picked_by"]).is_empty() and (best.is_empty() or float(c["hyouka"]) > float(d.by_id[best]["hyouka"])):
			best = c["id"]
	return best


func _cells_text(cells: Array) -> String:
	var parts: Array[String] = []
	for cell: Dictionary in cells:
		parts.append("%s%s(%s)" % [cell["label"], cell["text"], cell["tier"]])
	return " ".join(parts)


func _page_text(d: RefCounted, c: Dictionary) -> String:
	var lines: Array[String] = []
	for l: Dictionary in _sn.comments(d, c):
		lines.append(str(l["text"]))
	var traits: Array[String] = []
	for t: Dictionary in _sn.traits(d, c):
		traits.append(str(t["text"]))
	return "%s（%s）%s／寸評：%s／札：%s／切り抜き：%s" % [c["name"], c["school"], _cells_text(_sn.sheet(d, c)),
		" ・".join(lines), ",".join(traits), _sn.clipping(c, d.year).get("headline", "-")]


func _names(d: RefCounted, team: String) -> String:
	var names: Array[String] = []
	for rec: Dictionary in d.picks_of(team):
		names.append("%s %s" % [rec["label"], rec["name"]])
	return "、".join(names)


func _board_magnets(board: Control) -> int:
	var n := 0
	for row in (board.get("_rows") as VBoxContainer).get_children():
		n += _row_magnets(row)
	return n


func _own_row_magnets(board: Control, d: RefCounted) -> int:
	var rows := (board.get("_rows") as VBoxContainer).get_children()
	var i: int = (d.order as Array).find(TEAM)
	return _row_magnets(rows[i]) if i >= 0 and i < rows.size() else -1


func _row_magnets(row: Node) -> int:
	var flow: Node = row.get_child(0).get_child(2)
	var n := 0
	for m in flow.get_children():
		if m is Button:
			n += 1
	return n


func _check(ok: bool, label: String) -> void:
	print(("OK " if ok else "NG ") + label)
	if not ok:
		_failures += 1


func _shot() -> void:
	if DisplayServer.get_name() == "headless" or _out.is_empty():
		return
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	_shots.append(root.get_texture().get_image())


func _save_grid() -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless" or _shots.is_empty():
		return
	var w := _shots[0].get_width()
	var h := _shots[0].get_height()
	var grid := Image.create(w * 3, h * 2, false, _shots[0].get_format())
	for i in _shots.size():
		_shots[i].convert(_shots[0].get_format())
		grid.blit_rect(_shots[i], Rect2i(0, 0, w, h), Vector2i((i % 3) * w, (i / 3) * h))
	grid.save_png(_out.path_join("draft_notebook.png"))
	print("  スクショ: draft_notebook.png（%d枚）" % _shots.size())


func _settle() -> void:
	await create_timer(0.25).timeout
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
