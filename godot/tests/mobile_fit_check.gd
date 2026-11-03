extends SceneTree
## スマホの画面の点検（ヘッドレス可、約3分）。iPhone の縦（390x844）と横（844x390）で全画面を開き、次を数える。
## ① 画面からはみ出す（画面の外に出て見えない）もの。スクロールの中で、その向きにスクロールできるものは除く
## ② 押せるもの（ボタン・名前札・入力欄・タブ）で、実寸の高さが 42px（目安 44px）より小さいもの・幅が 24px より小さいもの
## ③ 押せないボタン：画面の外、または下の操作の帯（MobileNavBar）に隠れて、スクロールしても出てこないもの
## ④ 縦向きで画面ごと横にスクロールする（幅に入らない）画面。表の多い画面（横向きの案内が出る）は除く。横向きはすべて NG
## 調べる画面：タイトル・ハブ・日程表・采配の全サブ画面・選手詳細の全タブ・新戦力・トレード・記録室の全タブ・新聞・
## 作戦会議（7月）・ポストシーズン・オフの各画面（表彰・FA・契約更改・戦力外・ドラフト）・セーブ。
## 最後に指の操作（なぞってスクロール・長押しで選手詳細・下の帯の「戻る」）も調べる。
##
##   godot --headless --path godot -s res://tests/mobile_fit_check.gd -- [自球団] [開始年] [出力先]
##   （既定はソフトバンク・2008。出力先を渡してウィンドウ付きで起動すると、主な画面のスクショを縦横で撮るだけ）

const PORTRAIT := Vector2i(390, 844)
const LANDSCAPE := Vector2i(844, 390)
## 実寸の下限（CSS ピクセル）
const MIN_TOUCH_PX := 42.0
const MIN_WIDTH_PX := 24.0
const TOLERANCE := 1.0
const SETTLE_SEC := 0.25
const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TITLE_SCENE := "res://scenes/title/title.tscn"
const DETAIL_SCRIPT := "res://scenes/player_detail/player_detail.gd"
const TACTICS_PAGES := ["", "pitchers", "fielders", "practice", "order", "strategy", "rules", "info", "list"]

var _team := "福岡ソフトバンクホークス"
var _year := 2008
var _out := ""
var _shots := false
var _gs: Node
var _hub: Node
var _orient := ""
var _checked := 0
var _ng := {"①": 0, "②": 0, "③": 0, "④": 0, "操作": 0}
## 参考：実寸 11px より小さい文字（向き → {"count": 数, "sizes": {実寸: 数}}）。NG にはしない
var _small_text := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].is_empty():
		_team = args[0]
	if args.size() > 1:
		_year = int(args[1])
	_out = args[2] if args.size() > 2 else ""
	_shots = not _out.is_empty() and DisplayServer.get_name() != "headless"
	if _shots:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	root.get_node("UiLayout").set_force_mode("mobile")
	for size: Vector2i in [PORTRAIT, LANDSCAPE]:
		await _set_size(size)
		_orient = "縦" if size.x < size.y else "横"
		print("\n==== %s（%dx%d、論理 %s、1px＝実寸 %.2fpx、押しやすい大きさ %d） ====" % [_orient, size.x, size.y,
			str(root.get_visible_rect().size), _ui().px_per_unit(), int(_ui().touch_units())])
		if _shots:
			await _take_shots()
		else:
			await _check_orientation()
	if _shots:
		quit(0)
		return
	await _check_gestures()
	print("\n調べた画面：%d" % _checked)
	for o: String in _small_text:
		print("  参考[%s] 実寸11px未満の文字のべ %d（実寸px: 数 %s）" % [o, _small_text[o]["count"],
			str(_small_text[o]["sizes"])])
	var total := 0
	for k: String in _ng:
		print("  %s %d件" % [k, _ng[k]])
		total += int(_ng[k])
	print("\n== 結果: %s ==" % ("ALL OK" if total == 0 else "FAILED（%d件）" % total))
	quit(1 if total > 0 else 0)


func _ui() -> Node:
	return root.get_node("UiLayout")


func _set_size(size: Vector2i) -> void:
	if _shots:
		var usable := DisplayServer.screen_get_usable_rect()
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(usable.end - size - Vector2i(8, 8))
	root.size = size
	await _frames(4)


# --- 画面をめぐる -------------------------------------------------------------------------

func _check_orientation() -> void:
	change_scene_to_file(TITLE_SCENE)
	await _frames(6)
	await _check_screen("タイトル")
	_gs.new_game(_team, _year)
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	_hub = current_scene
	await _check_season("%d年開幕" % _year, true)
	while _gs.phase == _gs.Phase.SEASON and _gs.month < 7:
		_gs.advance()
	await _check_screen("%d年%d月：ハブ" % [_year, _gs.month])
	await _check_meeting("%d年%d月" % [_year, _gs.month])
	if _orient == "縦":
		# オフは縦だけ（横はシーズン中と同じ部品。時間を半分に）
		_gs.advance_through(_gs.season_last_day(), true)
		while _gs.phase == _gs.Phase.POSTSEASON:
			await _open("postseason")
			await _check_screen("%s：ポストシーズン" % _gs.date_text())
			_hub.call("_close_sub_screen")
			_gs.advance()
		while _gs.phase != _gs.Phase.SEASON:
			await _check_offseason()
			if _gs.phase == _gs.Phase.DRAFT:
				break
			_gs.advance()


func _check_season(when: String, full: bool) -> void:
	await _check_screen("%s：ハブ" % when)
	for key: String in ["schedule", "scout", "system"]:
		await _open(key)
		await _check_screen("%s：%s" % [when, key])
		if key != "system":
			for i in (3 if key == "scout" else 2):
				_hub.get("_" + key + "_view").switch_tab(1)
				await _check_screen("%s：%s タブ%d" % [when, key, i + 2])
		_hub.call("_close_sub_screen")
	await _open("news")
	await _check_screen("%s：新聞" % when)
	for i in 2:
		_hub.get("_news_view").switch_tab(1)
		await _check_screen("%s：新聞 タブ%d" % [when, i + 2])
	_hub.call("_close_sub_screen")
	await _check_tactics(when, TACTICS_PAGES)
	await _check_trade(when)
	if full:
		await _check_records(when)
		await _check_detail(when)


func _check_tactics(when: String, pages: Array) -> void:
	await _open("tactics")
	var tactics: Node = _hub.get("_tactics_view")
	for page: String in pages:
		tactics.call("_show_page", page, true)
		await _check_screen("%s：采配 %s" % [when, page if not page.is_empty() else "一覧"])
		if page in ["pitchers", "fielders"]:
			var team: Variant = _gs.my_team()
			var reg: Node = tactics.get("_register_" + page)
			for p: Variant in team.players:
				if p.is_pitcher == reg.get("pitchers"):
					reg.set("_selected", p)
					reg.refresh()
					await _check_screen("%s：采配 %s（%sを選ぶ）" % [when, page, p.name])
					break
			reg.clear_selection()
		elif page == "list":
			var roster: Node = tactics.get("_roster")
			for i in roster.get_tab_count() - 1:
				roster.switch_tab(1)
				await _check_screen("%s：采配 選手一覧 タブ%d" % [when, i + 2])
	tactics.call("_show_page", "")
	_hub.call("_close_sub_screen")


func _check_trade(when: String) -> void:
	await _open("trade")
	var view: Node = _hub.get("_trade_view")
	await _check_screen("%s：トレード" % when)
	view.call("clear_deal")
	var ids: Array = view.call("list_ids")
	for id: String in ids.slice(0, 3):
		view.call("select_player", id)
	view.call("set_money", 50000)
	for i in 4:
		await _check_screen("%s：トレード タブ%d（条件を入れた）" % [when, i + 1])
		view.call("switch_tab", 1)
	view.call("clear_deal")
	_hub.call("_close_sub_screen")


func _check_records(when: String) -> void:
	await _open("records")
	var view: Node = _hub.get("_records_view")
	for t: Array in view.TABS:
		view.set_tab(t[0])
		await _check_screen("%s：記録室 %s" % [when, t[1]])
		if t[0] == "pos_rank":
			for mode: String in ["list", "ability"]:
				view.set("_pv_mode", mode)
				view.refresh()
				await _check_screen("%s：記録室 位置別の戦力（%s）" % [when, mode])
			view.set("_pv_mode", "chart")
		elif t[0] == "awards":
			var inner: Node = view.get("_awards_view")
			for a: Array in inner.TABS:
				inner.set_tab(a[0])
				await _check_screen("%s：記録室 表彰の歴代 %s" % [when, a[1]])
	_hub.call("_close_sub_screen")


func _check_detail(when: String) -> void:
	var ids: Array = load(DETAIL_SCRIPT).team_order(_gs.team)
	if ids.is_empty():
		return
	var detail: Node = load(DETAIL_SCRIPT).open(_hub, ids[0], ids)
	await _frames(2)
	for i in 4:
		detail.show_tab(i)
		await _check_screen("%s：選手詳細 タブ%d" % [when, i + 1])
	detail.close()
	await _frames(2)


func _check_meeting(when: String) -> void:
	await _open("meeting")
	var view: Node = _hub.get("_meeting_view")
	await _check_screen("%s：作戦会議" % when)
	var ids: Array = view.list_ids()
	if not ids.is_empty():
		view.select_candidate(ids[0])
		view.set_mark("◎")
		await _check_screen("%s：作戦会議 候補を選んで印" % when)
	view.set_mode("table")
	await _check_screen("%s：作戦会議 表" % when)
	for i in 3:
		view.switch_tab(1)
		await _check_screen("%s：作戦会議 タブ%d" % [when, i + 2])
	view.switch_tab(1)
	view.set_mode("book")
	_hub.call("_close_sub_screen")


func _check_offseason() -> void:
	var when := "%d年オフ %s" % [_year, _gs.phase_name()]
	await _check_screen("%s：ハブ" % when)
	if _gs.phase == _gs.Phase.AWARDS:
		await _open("awards")
		var view: Node = _hub.get("_awards_view")
		for t: Array in view.TABS:
			view.set_tab(t[0])
			await _check_screen("%s：表彰 %s" % [when, t[1]])
		_hub.call("_close_sub_screen")
	if _gs.fa_open():
		await _check_phase_view("fa", "_fa_view", when)
		await _open("fa")
		var fa: Node = _hub.get("_fa_view")
		for id: String in fa.list_ids().slice(0, 3):
			fa.toggle_mark(id)
		await _check_screen("%s：FA 印を付けた表" % when)
		if fa.confirm().is_empty():
			await _check_screen("%s：FA 交渉の部屋" % when)
		while fa.back():
			pass
		_hub.call("_close_sub_screen")
	elif _gs.contract_open():
		await _check_phase_view("contract", "_contract_view", when)
	elif _gs.release_open():
		await _check_phase_view("release", "_release_view", when)
	elif _gs.draft_open():
		await _check_draft(when)


func _check_phase_view(key: String, prop: String, when: String) -> void:
	await _open(key)
	var view: Node = _hub.get(prop)
	await _check_screen("%s：%s" % [when, key])
	for i in 3:
		var ids: Array = view.list_ids()
		if not ids.is_empty():
			view.select_player(ids[0])
			await _check_screen("%s：%s タブ%d 選択" % [when, key, i + 1])
		view.switch_tab(1)
		await _check_screen("%s：%s タブ%d" % [when, key, i + 2])
	while view.back():
		pass
	_hub.call("_close_sub_screen")


func _check_draft(when: String) -> void:
	await _open("draft")
	var view: Node = _hub.get("_draft_view")
	await _check_screen("%s：ドラフト 開幕の演出" % when)
	view.finish_overlays()
	await _check_screen("%s：ドラフト 手帳" % when)
	# スカウトの手帳（作業51）：めくる・指名ボード・表のタブ
	view.switch_tab(1)
	await _check_screen("%s：ドラフト 手帳をめくる" % when)
	view.set_mode("board")
	await _check_screen("%s：ドラフト 指名ボード" % when)
	view.set_mode("table")
	await _check_screen("%s：ドラフト 表" % when)
	for i in 3:
		view.switch_tab(1)
		await _check_screen("%s：ドラフト タブ%d" % [when, i + 2])
	view.switch_tab(1)
	view.set_mode("book")
	var ids: Array = view.list_ids()
	if not ids.is_empty():
		view.select_candidate(ids[0])
		await _check_screen("%s：ドラフト 候補を選ぶ" % when)
		view.press_action()
		await _check_screen("%s：ドラフト 入札" % when)
		if view.announcing():
			view.back()
		if view.lottery_3d() != null:
			await _check_screen("%s：ドラフト 抽選の3D演出" % when)
			view.back()
		view.finish_overlays()
		await _check_screen("%s：ドラフト 入札のあと" % when)
	while view.back():
		pass
	_hub.call("_close_sub_screen")


# --- スクショ（ウィンドウ付き） ---------------------------------------------------------------

func _take_shots() -> void:
	var o := "portrait" if _orient == "縦" else "landscape"
	change_scene_to_file(TITLE_SCENE)
	await _frames(6)
	await _shot("%s_01_title" % o)
	_gs.new_game(_team, _year)
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	_hub = current_scene
	await _shot("%s_02_hub" % o)
	await _open("tactics")
	await _shot("%s_03_tactics" % o)
	var tactics: Node = _hub.get("_tactics_view")
	tactics.call("_show_page", "pitchers", true)
	await _shot("%s_04_tactics_pitchers" % o)
	tactics.call("_show_page", "order", true)
	await _shot("%s_05_tactics_order" % o)
	tactics.call("_show_page", "")
	_hub.call("_close_sub_screen")
	await _open("schedule")
	await _shot("%s_06_schedule" % o)
	_hub.call("_close_sub_screen")
	await _open("records")
	await _shot("%s_07_records" % o)
	_hub.call("_close_sub_screen")
	var ids: Array = load(DETAIL_SCRIPT).team_order(_gs.team)
	var detail: Node = load(DETAIL_SCRIPT).open(_hub, ids[0], ids)
	await _settle()
	await _shot("%s_08_player_detail" % o)
	detail.close()
	await _open("meeting")
	await _shot("%s_09_draft_meeting" % o)
	_hub.call("_close_sub_screen")


func _shot(name: String) -> void:
	await _settle()
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var path := _out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("  スクショ: ", path)


# --- 指の操作 -----------------------------------------------------------------------------

func _check_gestures() -> void:
	print("\n-- 指の操作（縦） --")
	await _set_size(PORTRAIT)
	_gs.new_game(_team, _year)
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	_hub = current_scene
	await _open("tactics")
	var tactics: Node = _hub.get("_tactics_view")
	# 長押し：1軍の名前札 → 選手詳細
	var tag := _first_visible(_hub, "NameTag")
	if tag == null:
		_gesture_ng("1軍の名前札が見つからない")
	else:
		var pos := (tag as Control).get_global_rect().get_center()
		_mouse(pos, true)
		await create_timer(0.7).timeout
		await _frames(2)
		_mouse(pos, false)
		await _frames(3)
		var detail: Node = load(DETAIL_SCRIPT).current()
		if detail == null:
			_gesture_ng("名前札を長押ししても選手詳細が開かない")
		else:
			print("OK 名前札を長押しで選手詳細が開いた")
			# 下の帯の「戻る」で閉じる
			_hub.get("_nav").press("back")
			await _frames(3)
			if load(DETAIL_SCRIPT).current() != null:
				_gesture_ng("下の帯の「戻る」で選手詳細が閉じない")
			else:
				print("OK 下の帯の「戻る」で選手詳細が閉じた")
	# なぞってスクロール：選手一覧（縦に長い）で、ボタンの上から指を動かす
	tactics.call("_show_page", "list", true)
	await _settle()
	var scroll := _scrollable(_hub)
	if scroll == null:
		_gesture_ng("縦にスクロールできる一覧が見つからない")
	else:
		var r := scroll.get_global_rect()
		var start := Vector2(r.get_center().x, r.position.y + r.size.y * 0.7)
		var bar := _vbar(scroll)
		var before := int(bar.value)
		_mouse(start, true)
		for i in 8:
			_motion(start + Vector2(0, -20.0 * (i + 1)), Vector2(0, -20))
			await _frames(1)
		_mouse(start + Vector2(0, -160), false)
		await _frames(2)
		if int(bar.value) <= before:
			_gesture_ng("指でなぞっても一覧（%s）がスクロールしない（%d→%d）" % [_cls(scroll), before, int(bar.value)])
		else:
			print("OK 指でなぞって一覧（%s）がスクロールした（%d→%d）" % [_cls(scroll), before, int(bar.value)])
	tactics.call("_show_page", "")
	# 下の帯：日程表→采配→戻る
	_hub.get("_nav").press("schedule")
	await _settle()
	if _hub.get("_open_key") != "schedule":
		_gesture_ng("下の帯の「日程表」で日程表が開かない")
	_hub.get("_nav").press("back")
	await _settle()
	if _hub.get("_open_key") != "":
		_gesture_ng("下の帯の「戻る」でハブへ戻らない")
	else:
		print("OK 下の帯の「日程表」「戻る」")


func _mouse(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	e.position = pos
	e.global_position = pos
	root.push_input(e, true)


func _motion(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.position = pos
	e.global_position = pos
	e.relative = rel
	root.push_input(e, true)


func _gesture_ng(text: String) -> void:
	_ng["操作"] += 1
	print("NG ", text)


func _first_visible(node: Node, cls: String) -> Control:
	for child in node.get_children():
		if child is Control and (child as Control).is_visible_in_tree() \
				and child.get_script() != null and child.get_script().get_global_name() == cls:
			return child
		var hit := _first_visible(child, cls)
		if hit != null:
			return hit
	return null


## 縦に長い一覧（ScrollContainer か Tree）
func _scrollable(node: Node) -> Control:
	for child in node.get_children():
		var hit := _scrollable(child)
		if hit != null:
			return hit
		if (child is ScrollContainer or child is Tree) and (child as Control).is_visible_in_tree() \
				and not child.has_meta("fit_guard"):
			var bar := _vbar(child as Control)
			if bar != null and bar.max_value > bar.page + 20:
				return child
	return null


static func _vbar(c: Control) -> ScrollBar:
	if c is ScrollContainer:
		return (c as ScrollContainer).get_v_scroll_bar()
	for child in c.get_children(true):
		if child is VScrollBar:
			return child
	return null


# --- 調べる -------------------------------------------------------------------------------

func _open(key: String) -> void:
	_hub.call("_open_sub_screen", key)
	await _settle()


func _check_screen(label: String) -> void:
	await _settle()
	_checked += 1
	var view := root.get_visible_rect().size
	var ppu: float = _ui().px_per_unit()
	# 下の操作の帯はハブにだけある（タイトルには無い）
	var nav_top: float = view.y
	if _hub != null and is_instance_valid(_hub) and current_scene == _hub:
		nav_top = view.y - float(_ui().bottom_inset())
	var found := {"①": [] as Array[String], "②": [] as Array[String], "③": [] as Array[String], "④": [] as Array[String]}
	_walk(root, Rect2(Vector2.ZERO, view), found, ppu, nav_top, label)
	var any := false
	for k: String in found:
		var items: Array = found[k]
		if items.is_empty():
			continue
		any = true
		_ng[k] += 1
		print("NG[%s] %s：%s %d件" % [_orient, label, k, items.size()])
		for line: String in items.slice(0, 6):
			print("    ", line)
	if not any:
		print("OK[%s] %s" % [_orient, label])


func _walk(node: Node, clip: Rect2, found: Dictionary, ppu: float, nav_top: float, label: String) -> void:
	if node is Window and node != root:
		return
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is CanvasLayer:
		if not (node as CanvasLayer).visible or _cls(node) == "MobileNavBar":
			return
		clip = Rect2(Vector2.ZERO, root.get_visible_rect().size)
	if node is Control:
		var c := node as Control
		if c.top_level:
			clip = Rect2(Vector2.ZERO, root.get_visible_rect().size)
		var r := _rect(c)
		if r.size.x > 0.0 and r.size.y > 0.0 and _outside(r, clip):
			found["①"].append("%s %s が枠 %s の外（最小 %s）%s" % [_name(c), _rt(r), _rt(clip),
				str(c.get_combined_minimum_size()), _widest(c)])
			if _has_button(c):
				found["③"].append("%s（画面の外）" % _name(c))
			return
		_check_touch(c, r, found, ppu, nav_top, clip)
		_count_text(c, ppu)
		if c is ScrollContainer:
			var s := c as ScrollContainer
			var hbar := s.get_h_scroll_bar()
			var vbar := s.get_v_scroll_bar()
			if s.has_meta("fit_guard") and hbar.visible and hbar.max_value > hbar.page + 2.0:
				if not (_orient == "縦" and _hinted(c)):
					found["④"].append("%s が横にスクロール（中身の幅 %d・枠 %d）%s" % [_name(c), int(hbar.max_value),
						int(hbar.page), _widest(s.get_child(0) as Control)])
			# スクロールの下端が下の帯に隠れると、最後の行が押せない
			if vbar.visible and r.end.y > nav_top + TOLERANCE and _has_button(c) and not _in_scroll(c):
				found["③"].append("%s のスクロールの下端 %d が下の帯（%d〜）に隠れる" % [_name(c), int(r.end.y), int(nav_top)])
			var inner := clip.intersection(r)
			if s.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
				inner.position.x = -1e6
				inner.size.x = 2e6
			if s.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
				inner.position.y = -1e6
				inner.size.y = 2e6
			clip = inner
		elif c.clip_contents:
			return
	for child in node.get_children():
		_walk(child, clip, found, ppu, nav_top, label)


func _check_touch(c: Control, r: Rect2, found: Dictionary, ppu: float, nav_top: float, clip: Rect2) -> void:
	var pressable := c is BaseButton or c is LineEdit or c is Slider
	if c is TabContainer:
		var bar := (c as TabContainer).get_tab_bar()
		if bar.is_visible_in_tree() and bar.size.y * ppu < MIN_TOUCH_PX:
			found["②"].append("%s のタブの高さ %.0fpx" % [_name(c), bar.size.y * ppu])
	if not pressable or c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return
	if r.size.y * ppu < MIN_TOUCH_PX - 0.5 or r.size.x * ppu < MIN_WIDTH_PX:
		found["②"].append("%s %s 実寸 %.0fx%.0fpx%s" % [_name(c), _cls(c), r.size.x * ppu, r.size.y * ppu,
			_text_of(c)])
	# 動かない（スクロールの中でない）ボタンが下の帯に隠れる
	if r.get_center().y > nav_top and not _in_scroll(c):
		found["③"].append("%s%s が下の帯に隠れる（%s）" % [_name(c), _text_of(c), _rt(r)])


func _count_text(c: Control, ppu: float) -> void:
	var fs := 0
	if c is Label:
		var l := c as Label
		if l.text.is_empty():
			return
		fs = l.label_settings.font_size if l.label_settings != null else l.get_theme_font_size("font_size")
	elif c is Button and not (c as Button).text.is_empty():
		fs = c.get_theme_font_size("font_size")
	else:
		return
	var px := int(round(fs * ppu))
	if px >= 11:
		return
	if not _small_text.has(_orient):
		_small_text[_orient] = {"count": 0, "sizes": {}}
	_small_text[_orient]["count"] += 1
	_small_text[_orient]["sizes"][px] = int(_small_text[_orient]["sizes"].get(px, 0)) + 1


## 横向きをすすめる案内（meta rotate_hint のラベル）が、同じ画面（包みの中か、包みの親の中）に出ているか
func _hinted(fit: Control) -> bool:
	return _find_hint(fit) or (fit.get_parent() != null and _find_hint(fit.get_parent()))


func _find_hint(node: Node) -> bool:
	if node.has_meta("rotate_hint") and (node as CanvasItem).is_visible_in_tree():
		return true
	for child in node.get_children():
		if _find_hint(child):
			return true
	return false


func _in_scroll(c: Node) -> bool:
	var p := c.get_parent()
	while p != null:
		var s := p as ScrollContainer
		if s != null and s.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED \
				and s.get_v_scroll_bar().visible:
			return true
		p = p.get_parent()
	return false


func _has_button(c: Node) -> bool:
	if c is BaseButton and (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return true
	for child in c.get_children():
		if child is CanvasItem and (child as CanvasItem).visible and _has_button(child):
			return true
	return false


func _rect(c: Control) -> Rect2:
	if c.scale == Vector2.ONE:
		return c.get_global_rect()
	var parent_xform := c.get_global_transform() * c.get_transform().affine_inverse()
	return parent_xform * Rect2(c.position, c.size)


func _outside(r: Rect2, clip: Rect2) -> bool:
	return r.position.x < clip.position.x - TOLERANCE or r.position.y < clip.position.y - TOLERANCE \
		or r.end.x > clip.end.x + TOLERANCE or r.end.y > clip.end.y + TOLERANCE


func _widest(c: Control) -> String:
	if c == null:
		return ""
	var chain: Array[String] = []
	var node: Control = c
	for depth in 10:
		var best: Control = null
		for child in node.get_children():
			if child is Control and (child as Control).visible:
				if best == null or child.get_combined_minimum_size().x > best.get_combined_minimum_size().x:
					best = child
		if best == null:
			break
		node = best
		chain.append("%s%s:%d" % [_cls(node), _text_of(node), int(node.get_combined_minimum_size().x)])
	return "\n        ← " + " > ".join(chain) if not chain.is_empty() else ""


static func _cls(c: Node) -> String:
	var s: Script = c.get_script()
	if s != null and not s.get_global_name().is_empty():
		return s.get_global_name()
	return c.get_class()


static func _text_of(c: Node) -> String:
	if c is Label:
		return "「%s」" % (c as Label).text.left(16)
	if c is Button:
		return "「%s」" % (c as Button).text.left(16)
	return ""


func _name(c: Control) -> String:
	var parts: Array[String] = []
	var node: Node = c
	while node != null and node != root and parts.size() < 4:
		var n := str(node.name)
		parts.push_front(_cls(node) if n.begins_with("@") else n)
		node = node.get_parent()
	return "/".join(parts)


static func _rt(r: Rect2) -> String:
	return "(%d,%d)-(%d,%d)" % [int(r.position.x), int(r.position.y), int(r.end.x), int(r.end.y)]


func _settle() -> void:
	await create_timer(SETTLE_SEC).timeout
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
