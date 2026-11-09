# gdlint: disable=max-file-lines,max-public-methods
class_name FaView
extends VBoxContainer
## オフの「FA・トレード・ポスティング」の画面（ハブの可変ボタンから開く。作業36でパワプロのペナントの
## 「FA選手交渉選択」「FA交渉」の2画面の流れに作り直し。背番号は出さない）。仕組みは FreeAgency（GameState.fa()）。
##
## (1) 一覧（交渉する選手を選ぶ）：上に支配下の人数と守備位置の内訳・予算の残り、中央に行＝FA宣言した選手
##     （とメジャー移籍する選手）、列＝球団（LB/RB でセ・パ）の表。マスは「交」＝入札・交渉中、「残」＝元の球団の
##     残留交渉、「✕」＝交渉しない、「米」＝メジャーへ、締め切ったあとは「決」＝移籍先。色付きのマス＝選手が
##     行きたがっている球団（好み）、自球団の列は黄色。下に選手の要約と希望のひとこと。
##     左のメニュー：OK（印を付けた選手と交渉の部屋へ）／交渉する（印を付ける・外す。マスのⒶでも）／
##     キャンセル（印を外す。印が無ければハブへ）／締め切る
## (2) 交渉の部屋：机の向こうに選手（球団カラーのデフォルメ）、右に今季成績と能力、下の左に自球団の提示
##     （年俸・年数を ◀▶）、右に選手の希望。成功率の★は提示で変わる。LB/RB で印を付けた選手を前後に送る。
##     Ⓑ で一覧へ戻る。メジャー移籍する自球団の選手は「引き留める」（1回だけ）
## 名前札をⒶ／クリックで選手詳細（右クリックでも）。

signal message_changed(text: String)
## 一覧で印が無いときの「キャンセル」（ハブへ戻る）
signal close_requested

const Figure := preload("res://scenes/hub/fa_figure.gd")
const LEAGUES := [["C", "セ・リーグ", Color("1e63c8")], ["P", "パ・リーグ", Color("2e9b48")]]
const POS_SHORT := {
	"捕手": "捕", "一塁手": "一", "二塁手": "二", "三塁手": "三", "遊撃手": "遊", "内野手": "内",
	"外野手": "外", "左翼手": "外", "中堅手": "外", "右翼手": "外", "指名打者": "指", "投手": "投",
}
## 上の帯の守備位置の内訳 [見出し, 守備位置]
const POS_GROUPS := [["投", ["投手"]], ["捕", ["捕手"]], ["一", ["一塁手"]], ["二", ["二塁手"]],
	["三", ["三塁手"]], ["遊", ["遊撃手"]], ["外", ["外野手", "左翼手", "中堅手", "右翼手"]]]
const STAR_WORDS := ["", "かなり低い", "低い", "五分五分", "高い", "かなり高い"]
const MENU_WIDTH := 140
const ROW_HEIGHT := 38
const CELL_WIDTH := 100
const TAG_SIZE := Vector2(128, 34)
const OWN_TINT := Color("fff1b0")
const WANT_TINT := Color("ffc4cf")
const DONE_TINT := Color("ffd84d")
const MARK_COLOR := Color("ff6d00")
const ROOM_MIDDLE := 222
const ROOM_BOTTOM := 214

var _palette: UiTheme.Palette
var _league := "C"
var _marked: Array[String] = []
var _cursor := ""
var _room := false
var _room_index := 0
var _amount := 0
var _years := 3
var _message := ""
var _shown_key := ""
## 一覧の選手の並び・マス（id → {球団 → Button}）・名前札
var _ids: Array[String] = []
var _cells := {}
var _tags := {}
var _rank_cache := {}
var _want_cache := {}

# (1) 一覧
var _list_page: VBoxContainer
var _roster_label: Label
var _pos_box: HBoxContainer
var _budget_label: Label
var _league_buttons := {}
var _header_row: HBoxContainer
var _rows_box: VBoxContainer
var _scroll: ScrollContainer
var _summary_box: HBoxContainer
var _ok_button: Button
var _mark_button: Button
var _cancel_list_button: Button
var _close_button: Button
var _mark_count_label: Label

# (2) 交渉の部屋
var _room_page: VBoxContainer
var _room_title: Label
var _room_count: Label
var _room_band: PanelContainer
var _room_band_label: Label
var _figure: Figure
var _speech_label: Label
var _stats_box: VBoxContainer
var _offer_band_label: Label
var _amount_bar: Button
var _years_bar: Button
var _range_label: Label
var _cancel_offer_button: Button
var _offer_steppers: Array[Button] = []
var _offer_box: VBoxContainer
var _stars_label: Label
var _odds_label: Label
var _change_button: Button
var _action_button: Button
var _back_button: Button
var _ask_amount_label: Label
var _ask_years_label: Label
var _diff_label: Label
var _wish_label: Label


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	add_theme_constant_override("separation", 0)
	_list_page = _build_list()
	_list_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_list_page)
	_room_page = _build_room()
	_room_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_page.visible = false
	add_child(_room_page)


# --- 外から ------------------------------------------------------------------------------

func open() -> void:
	_room = false
	_room_index = 0
	_message = ""
	_shown_key = ""
	_cursor = ""
	_league = GameData.league_of(GameState.team) if not GameData.league_of(GameState.team).is_empty() else "C"
	_rank_cache.clear()
	_want_cache.clear()
	# 提示済みの選手には最初から印を付けておく（交渉の続き）
	_marked.clear()
	var f := GameState.fa()
	if f != null:
		for id: String in f.user_bids:
			_marked.append(id)
	refresh()
	focus_first()


## 戻る：交渉の部屋なら一覧へ（true）。一覧なら false（ハブへ戻る）
func back() -> bool:
	if not _room:
		return false
	var id := room_id()
	_room = false
	_message = ""
	_shown_key = ""
	if not id.is_empty():
		_cursor = id
	refresh()
	focus_first()
	return true


## LB/RB：一覧ではセ・パの切り替え、交渉の部屋では印を付けた選手の前後
func switch_tab(delta: int) -> void:
	if _room:
		_step_room(delta)
		return
	_league = "P" if _league == "C" else "C"
	_message = ""
	refresh()
	focus_first()


func focus_first() -> void:
	if _room:
		UiInput.grab(_change_button if not _change_button.disabled else _back_button)
		return
	var id := _cursor if _cells.has(_cursor) else (_ids[0] if not _ids.is_empty() else "")
	if id.is_empty():
		UiInput.grab(_close_button if not _close_button.disabled else _cancel_list_button)
		return
	var row: Dictionary = _cells[id]
	var target: Button = row.get(GameState.team, row.values()[0])
	target.grab_focus()


func refresh() -> void:
	var f := GameState.fa()
	var key := _current_key(f)
	if key == _shown_key:
		return
	_shown_key = key
	_list_page.visible = not _room
	_room_page.visible = _room
	if _room:
		_render_room(f)
	else:
		var focused := _focused_cell()
		var scrolled := _scroll.scroll_vertical
		_render_top(f)
		_render_grid(f)
		# 作り直すと中身が一度空になってスクロールが一番上に戻るので、並べ直したあと（次のフレーム）に戻す
		_scroll.scroll_vertical = scrolled
		get_tree().process_frame.connect(func() -> void:
			if is_instance_valid(_scroll):
				_scroll.scroll_vertical = scrolled
				var owner := get_viewport().gui_get_focus_owner()
				if owner != null and _scroll.is_ancestor_of(owner):
					_scroll.ensure_control_visible(owner), CONNECT_ONE_SHOT)
		_render_menu(f)
		_render_summary(f)
		if not focused.is_empty() and _cells.has(focused[0]) and _cells[focused[0]].has(focused[1]):
			(_cells[focused[0]][focused[1]] as Button).grab_focus()
		elif not focused.is_empty():
			focus_first()
	message_changed.emit(_status_text(f))


## いまの選手（交渉の部屋ならその選手、一覧ならカーソルの選手。テスト用）
func selected_id() -> String:
	return room_id() if _room else _cursor


## 一覧の選手ID（表の行の並び。テスト用）
func list_ids() -> Array[String]:
	return _ids


## 表のカーソルをその選手の行へ（下の要約が変わる）
func select_player(id: String) -> void:
	_set_cursor(id)
	if _room:
		return
	if _cells.has(id):
		var row: Dictionary = _cells[id]
		(row.get(GameState.team, row.values()[0]) as Button).grab_focus()


func marked_ids() -> Array[String]:
	return _marked


func in_room() -> bool:
	return _room


## 交渉の部屋の選手（部屋でなければ空）
func room_id() -> String:
	if not _room or _marked.is_empty():
		return ""
	return _marked[clampi(_room_index, 0, _marked.size() - 1)]


## 表のマス（テスト用）
func cell(id: String, team: String) -> Button:
	return _cells.get(id, {}).get(team)


## 印を付ける・外す。付けられない選手なら理由の文
func toggle_mark(id: String) -> String:
	var f := GameState.fa()
	var reason := _mark_block(f, id)
	if not reason.is_empty():
		_message = reason
	elif id in _marked:
		_marked.erase(id)
		_message = "%sの印を外しました。" % _name(id)
	else:
		_marked.append(id)
		_message = "%sに印を付けました。選び終わったら「OK」で交渉の部屋へ。" % _name(id)
	_cursor = id
	_shown_key = ""
	refresh()
	return reason


## 「OK」：印を付けた選手と交渉の部屋へ（印が無ければカーソルの選手）。だめなら理由の文
func confirm() -> String:
	var f := GameState.fa()
	if f == null:
		return "FAの交渉はオフの「FA・トレード・ポスティング」で行います"
	if _marked.is_empty() and not _cursor.is_empty() and _mark_block(f, _cursor).is_empty():
		_marked.append(_cursor)
	if _marked.is_empty():
		_message = "交渉する選手を「交渉する」（マスのⒶ）で選んでから「OK」を押してください。"
		_shown_key = ""
		refresh()
		return _message
	_room = true
	_room_index = maxi(0, _marked.find(_cursor))
	_message = ""
	_load_offer(f, room_id())
	_shown_key = ""
	refresh()
	focus_first()
	UiFx.slide_in(_room_page)
	return ""


# --- (1) 一覧 ------------------------------------------------------------------------------

func _build_list() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.add_child(_build_top())
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 10)
	page.add_child(middle)
	middle.add_child(_build_menu())
	var table := PanelContainer.new()
	var style := UiTheme.card(Color("2f7fd8"), 10, 3, 0.98)
	style.content_margin_left = 10
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	table.add_theme_stylebox_override("panel", style)
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(table)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	table.add_child(box)
	_header_row = HBoxContainer.new()
	_header_row.add_theme_constant_override("separation", 4)
	box.add_child(_header_row)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 3)
	_scroll.add_child(_rows_box)
	var summary := PanelContainer.new()
	var sum_style := UiTheme.gloss(Color("eadfc6"), 10, 3, 0, Color("a88a5c"))
	sum_style.gloss = 0.0
	sum_style.gradient = 0.08
	sum_style.content_margin_left = 12
	sum_style.content_margin_right = 12
	sum_style.content_margin_top = 8
	sum_style.content_margin_bottom = 8
	summary.add_theme_stylebox_override("panel", sum_style)
	summary.custom_minimum_size = Vector2(0, 96)
	page.add_child(summary)
	_summary_box = HBoxContainer.new()
	_summary_box.add_theme_constant_override("separation", 12)
	summary.add_child(_summary_box)
	return page


## 上の帯：支配下の人数と守備位置の内訳、予算の残り、セ・パの切り替え
func _build_top() -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.card(_palette.main, 10, 3, 0.98)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	row.add_child(left)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	left.add_child(line)
	_roster_label = Label.new()
	UiTheme.heading(_roster_label, 20, UiTheme.TEXT, Color.WHITE, 5, false)
	line.add_child(_roster_label)
	_pos_box = HBoxContainer.new()
	_pos_box.add_theme_constant_override("separation", 4)
	line.add_child(_pos_box)
	_budget_label = UiTheme.small_label("", 16, UiTheme.TEXT, 800)
	left.add_child(_budget_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(UiTheme.small_label("◀ LB", 17, UiTheme.TEXT, 800))
	for lg: Array in LEAGUES:
		var b := Button.new()
		b.text = lg[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 42)
		b.add_theme_font_size_override("font_size", 20)
		UiTheme.style_button(b, lg[2], Color.WHITE, 10, 6)
		var key: String = lg[0]
		b.pressed.connect(func() -> void:
			if _league != key:
				switch_tab(1))
		row.add_child(b)
		_league_buttons[key] = b
	row.add_child(UiTheme.small_label("RB ▶", 17, UiTheme.TEXT, 800))
	return panel


## 左のメニュー：OK／交渉する／キャンセル、下に締め切る
func _build_menu() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	box.add_theme_constant_override("separation", 8)
	_ok_button = _menu_button("OK", Color("2e9b48"), 56, 28)
	_ok_button.pressed.connect(func() -> void: confirm())
	box.add_child(_ok_button)
	_mark_button = _menu_button("交渉する", Color("ff8a3d"), 50, 22)
	_mark_button.pressed.connect(func() -> void:
		if not _cursor.is_empty():
			toggle_mark(_cursor))
	box.add_child(_mark_button)
	_cancel_list_button = _menu_button("キャンセル", Color("8a9199"), 46, 20)
	_cancel_list_button.pressed.connect(_on_cancel_list)
	box.add_child(_cancel_list_button)
	_mark_count_label = UiTheme.small_label("", 16, UiTheme.TEXT, 800)
	_mark_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mark_count_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_mark_count_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	_close_button = _menu_button("締め切る", Color("1e63c8"), 50, 20)
	_close_button.tooltip_text = "FA宣言した選手の移籍先を決めます（提示はここまで）"
	_close_button.pressed.connect(_on_close_pressed)
	box.add_child(_close_button)
	return box


func _menu_button(text: String, color: Color, height: int, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(MENU_WIDTH, height)
	b.add_theme_font_override("font", UiTheme.font(800))
	b.add_theme_font_size_override("font_size", font_size)
	UiTheme.style_button(b, color, Color.WHITE, 10, 6)
	return b


func _render_top(f: FreeAgency) -> void:
	var league := GameState.league
	var team := GameState.team
	var counts := {}
	var total := 0
	if league != null:
		total = league.registered_count(team)
		for id: String in league.players_of(team):
			if league.ikusei_now(id):
				continue
			var pos: String = GameData.player(id).get("primary_pos", "")
			for g: Array in POS_GROUPS:
				if pos in g[1]:
					counts[g[0]] = int(counts.get(g[0], 0)) + 1
	_roster_label.text = "%s 支配下 計%d/%d人" % [GameData.short_name(team), total, LeagueRoster.ROSTER_LIMIT]
	for c in _pos_box.get_children():
		_pos_box.remove_child(c)
		c.queue_free()
	for g: Array in POS_GROUPS:
		_pos_box.add_child(_chip("%s %d" % [g[0], int(counts.get(g[0], 0))],
			NameTag.pos_color((g[1] as Array)[0]), UiTheme.TEXT, 15, 50))
	if f == null:
		_budget_label.text = ""
	else:
		var room := f.budget_room()
		_budget_label.text = "予算の残り %s（予算 %s・提示した分を含む）" % [Salary.text(room) if room >= 0 \
			else "−" + Salary.text(-room), Salary.text(ContractRenewal.budget(team))]
		_budget_label.add_theme_color_override("font_color", Color("d32f2f") if room < 0 else UiTheme.TEXT)
	for key: String in _league_buttons:
		var b: Button = _league_buttons[key]
		b.set_pressed_no_signal(key == _league)
		b.modulate = Color.WHITE if key == _league else Color(1, 1, 1, 0.55)


func _render_grid(f: FreeAgency) -> void:
	for c in _header_row.get_children():
		_header_row.remove_child(c)
		c.queue_free()
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	_cells.clear()
	_tags.clear()
	_ids = _list_ids(f)
	var teams := GameData.teams(_league)
	_header_row.add_child(_head("印", 30))
	_header_row.add_child(_head("選手", TAG_SIZE.x))
	_header_row.add_child(_head("位置", 34))
	_header_row.add_child(_head("年齢", 46))
	_header_row.add_child(_head("ランク", 44))
	_header_row.add_child(_head("所属", 54))
	for team in teams:
		_header_row.add_child(_team_head(team))
	if _ids.is_empty():
		var empty := UiTheme.small_label(_empty_text(f), 18, UiTheme.TEXT, 700)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(800, 0)
		_rows_box.add_child(empty)
		return
	if _cursor.is_empty() or _cursor not in _ids:
		_cursor = _ids[0]
	for id in _ids:
		_rows_box.add_child(_row(f, id, teams))


func _head(text: String, width: float) -> Label:
	var label := UiTheme.small_label(text, 14, UiTheme.TEXT_SUB, 800)
	label.custom_minimum_size = Vector2(width, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## 列の見出し：球団カラーの札（自球団は太い黄色の縁と「自」）
func _team_head(team: String) -> Control:
	var colors := GameData.team_colors(team)
	var own := team == GameState.team
	var label := Label.new()
	label.text = ("★" if own else "") + GameData.short_name(team)
	label.custom_minimum_size = Vector2(CELL_WIDTH, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	var ink := UiTheme.text_on(colors[0])
	label.add_theme_color_override("font_color", ink)
	label.add_theme_color_override("font_outline_color", UiTheme.outline_for(ink, colors[0]))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_override("font", UiTheme.font(800))
	label.add_theme_font_size_override("font_size", 15)
	var style := UiTheme.gloss(colors[0], 6, 3 if own else 1, 1, Color("ffd400") if own else Color.TRANSPARENT)
	style.content_margin_left = 2
	style.content_margin_right = 2
	label.add_theme_stylebox_override("normal", style)
	return label


## 表の1行：印・名前札・位置・年齢・ランク・所属・球団ごとのマス
func _row(f: FreeAgency, id: String, teams: Array[String]) -> Control:
	var p := GameData.player(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var marked := id in _marked
	row.add_child(_chip("✔" if marked else "", MARK_COLOR if marked else Color("eef1f4"), Color.WHITE, 16, 30))
	var tag := NameTag.new()
	tag.custom_minimum_size = TAG_SIZE
	tag.setup_player(p, NameTag.family_name(str(p.get("name", id))))
	tag.selected = marked
	tag.tooltip_text = "%s（Ⓐ／クリックで選手詳細）" % p.get("name", id)
	tag.pressed.connect(func() -> void: PlayerDetail.open(tag, id, _ids))
	tag.focus_entered.connect(_set_cursor.bind(id))
	row.add_child(tag)
	_tags[id] = tag
	row.add_child(_cell_label(POS_SHORT.get(p.get("primary_pos"), "-"), 34, 18))
	row.add_child(_cell_label("%d歳" % FreeAgency.age_of(p, f.year), 46, 16))
	if f.mlb_info.has(id):
		row.add_child(_chip("米", Color("1e63c8"), Color.WHITE, 15, 44))
	else:
		var rank := _rank(f, id)
		row.add_child(_chip(rank, {"A": Color("e53935"), "B": Color("ff8a3d")}.get(rank, Color("8a9199")),
			Color.WHITE, 17, 44))
	var from := _from_team(f, id)
	var colors := GameData.team_colors(from)
	row.add_child(_chip(GameData.short_name(from).substr(0, 3), colors[0], UiTheme.text_on(colors[0]), 14, 54))
	var cells := {}
	for team in teams:
		var b := _grid_cell(f, id, team)
		row.add_child(b)
		cells[team] = b
	_cells[id] = cells
	return row


## マス1つ（Ⓐ／クリックで印を付ける・外す）
func _grid_cell(f: FreeAgency, id: String, team: String) -> Button:
	var state := _cell_state(f, id, team)
	var b := Button.new()
	b.text = state[0]
	b.custom_minimum_size = Vector2(CELL_WIDTH, ROW_HEIGHT - 4)
	b.add_theme_font_override("font", UiTheme.font(800))
	b.add_theme_font_size_override("font_size", 20)
	var bg := Color("ffffff")
	if team == GameState.team:
		bg = OWN_TINT
	if _wants(f, id, team):
		bg = WANT_TINT if team != GameState.team else WANT_TINT.lerp(OWN_TINT, 0.4)
	if state[2]:
		bg = DONE_TINT
	var border := Color("ffb300") if team == GameState.team else UiTheme.LINE
	var normal := UiTheme.box(bg, 6, border, 2 if team == GameState.team else 1)
	normal.content_margin_top = 0
	normal.content_margin_bottom = 0
	var hover := UiTheme.box(bg.lerp(Color("fff7d6"), 0.5), 6, Color("ffb74d"), 2)
	for s in ["normal", "disabled"]:
		b.add_theme_stylebox_override(s, normal)
	for s in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(s, hover)
	b.add_theme_stylebox_override("focus", UiTheme.focus_frame(6))
	var ink: Color = state[1]
	for c in UiTheme.BUTTON_FONT_COLORS:
		b.add_theme_color_override(c, ink)
	b.add_theme_color_override("font_outline_color", Color.WHITE)
	b.add_theme_constant_override("outline_size", 4)
	b.tooltip_text = _cell_tip(f, id, team)
	b.set_meta("fa_cell", [id, team])
	b.focus_entered.connect(_set_cursor.bind(id))
	b.pressed.connect(func() -> void: toggle_mark(id))
	return b


## マスの [文字, 文字色, 決まった球団か]
func _cell_state(f: FreeAgency, id: String, team: String) -> Array:
	var user := GameState.team
	if f.mlb_info.has(id):
		var m: Dictionary = f.mlb_info[id]
		if team != m["from"]:
			return ["", UiTheme.TEXT_SUB, false]
		match m["status"]:
			"kept":
				return ["残", Color("2e9b48"), true]
			"failed":
				return ["米", Color("a3aab3"), false]
		return ["米", Color("1e63c8"), false]
	var from := _from_team(f, id)
	var bidders := f.bidder_teams(id)
	var bid := team in bidders or (team == user and f.user_bids.has(id))
	if f.resolved:
		var res := _result(f, id)
		if not res.is_empty() and res["to"] == team:
			return ["残" if team == from else "決", Color("c62828") if team == user else UiTheme.TEXT, true]
		return ["交" if bid else "✕", Color("c3c8ce"), false]
	if team == from:
		return ["残", Color("2e9b48"), false] if bid else ["✕", Color("a3aab3"), false]
	if team == user:
		return ["交", MARK_COLOR, false] if bid else ["", UiTheme.TEXT_SUB, false]
	return ["交", Color("e8413c"), false] if bid else ["✕", Color("a3aab3"), false]


func _cell_tip(f: FreeAgency, id: String, team: String) -> String:
	var name := GameData.short_name(team)
	var state: String = _cell_state(f, id, team)[0]
	var text: String = {"交": "%sが交渉中" % name, "残": "%sが残留交渉" % name, "✕": "%sは交渉しない" % name,
		"米": "メジャーへ移籍", "決": "%sへ移籍" % name}.get(state, "%s（自球団）：まだ提示していない" % name)
	if _wants(f, id, team):
		text += "（選手が行きたがっている球団）"
	return text + "\nⒶ／クリックで交渉する選手の印を付ける・外す"


func _cell_label(text: String, width: float, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiTheme.heading(label, font_size, UiTheme.TEXT, Color.WHITE, 4, false)
	return label


## 塗りの札（ランク・所属・守備位置の内訳など）
func _chip(text: String, color: Color, ink: Color, font_size: int, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_color_override("font_color", ink)
	label.add_theme_font_override("font", UiTheme.font(800))
	label.add_theme_font_size_override("font_size", font_size)
	if ink.get_luminance() > 0.6:
		label.add_theme_color_override("font_outline_color", color.darkened(0.45))
		label.add_theme_constant_override("outline_size", 3)
	var style := UiTheme.gloss(color, 5, 1, 1)
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 1
	style.content_margin_bottom = 2
	label.add_theme_stylebox_override("normal", style)
	return label


func _render_menu(f: FreeAgency) -> void:
	var open := f != null and not f.resolved
	_ok_button.disabled = f == null or _ids.is_empty()
	_mark_button.disabled = not open or _cursor.is_empty()
	_mark_button.text = "印を外す" if _cursor in _marked else "交渉する"
	_cancel_list_button.text = "キャンセル"
	_close_button.disabled = not open
	_close_button.text = "締め切る" if open or f == null else "締め切り済"
	_mark_count_label.text = "印 %d人" % _marked.size() if open else ("結果を表示中" if f != null else "")


func _render_summary(f: FreeAgency) -> void:
	for c in _summary_box.get_children():
		_summary_box.remove_child(c)
		c.queue_free()
	var id := _cursor
	if f == null or id.is_empty() or GameData.player(id).is_empty():
		var hint := UiTheme.small_label(_hint_text(f), 17, UiTheme.TEXT, 700)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_summary_box.add_child(hint)
		return
	var p := GameData.player(id)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	_summary_box.add_child(left)
	var from := _from_team(f, id)
	left.add_child(_band(Label.new(), from, GameData.short_name(from), 18))
	var tag := NameTag.new()
	tag.custom_minimum_size = Vector2(170, 40)
	tag.font_size = 22
	tag.focus_mode = Control.FOCUS_NONE
	tag.setup_player(p, NameTag.family_name(str(p.get("name", ""))))
	tag.pressed.connect(func() -> void: PlayerDetail.open(tag, id, _ids))
	left.add_child(tag)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 2)
	mid.custom_minimum_size = Vector2(330, 0)
	_summary_box.add_child(mid)
	var head := Label.new()
	head.text = "%s　%s %d歳" % [p.get("name", id), POS_SHORT.get(p.get("primary_pos"), "-"),
		FreeAgency.age_of(p, f.year)]
	UiTheme.heading(head, 20, UiTheme.TEXT, Color.WHITE, 5, false)
	mid.add_child(head)
	mid.add_child(UiTheme.small_label(_ability_text(p), 15, UiTheme.TEXT, 700))
	var wish := UiTheme.small_label(_wish_text(f, id), 15, UiTheme.TEXT_SUB, 700)
	mid.add_child(wish)
	# 希望のひとこと（吹き出し）と状況
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	_summary_box.add_child(right)
	right.add_child(_balloon(_words_text(f, id), 17))
	var state := UiTheme.small_label(_state_text(f, id), 15, UiTheme.TEXT, 700)
	UiTheme.fit_label(state)
	right.add_child(state)


func _balloon(text: String, font_size: int) -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.box(Color.WHITE, 14, Color("a88a5c"), 2)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var label := UiTheme.small_label(text, font_size, UiTheme.TEXT, 800)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	return panel


func _list_ids(f: FreeAgency) -> Array[String]:
	var ids: Array[String] = []
	if f == null:
		return ids
	var order := {}
	var all := GameData.teams()
	for i in all.size():
		order[all[i]] = i
	var fa_ids: Array[String] = []
	fa_ids.assign(f.declared)
	var mine := GameState.team
	# 自球団の選手・自球団が提示した選手を先に、あとは元の球団の順。メジャー移籍は最後（自球団の選手が先）
	fa_ids.sort_custom(func(a: String, b: String) -> bool:
		var ma := _from_team(f, a) == mine or f.user_bids.has(a)
		var mb := _from_team(f, b) == mine or f.user_bids.has(b)
		if ma != mb:
			return ma
		var oa: int = order.get(_from_team(f, a), 99)
		var ob: int = order.get(_from_team(f, b), 99)
		return oa < ob if oa != ob else a < b)
	ids.append_array(fa_ids)
	var mlb_ids: Array[String] = []
	for id in f.mlb:
		if _from_team(f, id) == mine:
			mlb_ids.append(id)
	for id in f.mlb:
		if _from_team(f, id) != mine:
			mlb_ids.append(id)
	ids.append_array(mlb_ids)
	return ids


func _empty_text(f: FreeAgency) -> String:
	if f == null:
		return "FA・ポスティングの交渉はオフの「FA・トレード・ポスティング」の段階で行います。"
	return "今オフにFA宣言・メジャー移籍する選手はいません。「締め切る」で次へ進めます。"


func _on_cancel_list() -> void:
	if _marked.is_empty():
		close_requested.emit()
		return
	_marked.clear()
	_message = "印をすべて外しました。選び直してください。"
	_shown_key = ""
	refresh()
	focus_first()


func _set_cursor(id: String) -> void:
	if _cursor == id:
		return
	_cursor = id
	if _room or not _list_page.visible:
		return
	var f := GameState.fa()
	_render_menu(f)
	_render_summary(f)
	# カーソルが動いただけなら表は作り直さない
	_shown_key = _current_key(f)


## 表示の鍵（変わったときだけ作り直す）
func _current_key(f: FreeAgency) -> String:
	return "%s|%s|%s|%d|%s|%d|%d|%d|%d|%s|%d|%s" % [_league, str(_room), ",".join(_marked), _room_index,
		_cursor, _amount, _years, GameState.roster_version, f.user_bids.size() if f != null else -1,
		str(f.resolved) if f != null else "", GameState.year, _mlb_key(f)]


func _focused_cell() -> Array:
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner != null and owner.has_meta("fa_cell") and is_ancestor_of(owner):
		return owner.get_meta("fa_cell")
	return []


# --- (2) 交渉の部屋 ----------------------------------------------------------------------

func _build_room() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	# 見出し：◀LB ○人目/○人 RB▶ と球団の帯
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 10)
	page.add_child(title)
	title.add_child(UiTheme.small_label("◀ LB", 17, UiTheme.TEXT, 800))
	_room_count = Label.new()
	UiTheme.heading(_room_count, 22, UiTheme.TEXT, Color.WHITE, 6, false)
	title.add_child(_room_count)
	title.add_child(UiTheme.small_label("RB ▶", 17, UiTheme.TEXT, 800))
	_room_band_label = Label.new()
	_room_band = _band(_room_band_label, GameState.team, "", 20)
	_room_band.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(_room_band)
	_room_title = Label.new()
	UiTheme.heading(_room_title, 22, UiTheme.TEXT, Color.WHITE, 6, false)
	title.add_child(_room_title)
	# 中段：部屋の場面（左）と今季成績・能力（右）
	var middle := HBoxContainer.new()
	middle.custom_minimum_size = Vector2(0, ROOM_MIDDLE)
	middle.add_theme_constant_override("separation", 10)
	page.add_child(middle)
	var scene := PanelContainer.new()
	var scene_style := UiTheme.box(Color("f3ead8"), 10, Color("a88a5c"), 3)
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		scene_style.set_content_margin(side, 3)
	scene.add_theme_stylebox_override("panel", scene_style)
	scene.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene.clip_contents = true
	middle.add_child(scene)
	var stage := Control.new()
	scene.add_child(stage)
	_figure = Figure.new()
	_figure.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_figure)
	var balloon := PanelContainer.new()
	var bstyle := UiTheme.box(Color.WHITE, 16, Color("a88a5c"), 2)
	bstyle.content_margin_left = 14
	bstyle.content_margin_right = 14
	bstyle.content_margin_top = 6
	bstyle.content_margin_bottom = 6
	balloon.add_theme_stylebox_override("panel", bstyle)
	balloon.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	balloon.offset_left = -250
	balloon.offset_top = 64
	balloon.offset_right = -14
	balloon.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	stage.add_child(balloon)
	_speech_label = UiTheme.small_label("", 16, UiTheme.TEXT, 800)
	_speech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech_label.custom_minimum_size = Vector2(208, 0)
	balloon.add_child(_speech_label)
	var stats := PanelContainer.new()
	var stats_style := UiTheme.card(Color("2f7fd8"), 10, 3, 0.98)
	stats_style.content_margin_left = 12
	stats_style.content_margin_right = 12
	stats_style.content_margin_top = 6
	stats_style.content_margin_bottom = 6
	stats.add_theme_stylebox_override("panel", stats_style)
	stats.custom_minimum_size = Vector2(450, 0)
	middle.add_child(stats)
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 4)
	stats.add_child(_stats_box)
	# 下段：自球団の提示（左）・成功率とボタン（中央）・選手の希望（右）
	var bottom := HBoxContainer.new()
	bottom.custom_minimum_size = Vector2(0, ROOM_BOTTOM)
	bottom.add_theme_constant_override("separation", 10)
	page.add_child(bottom)
	bottom.add_child(_build_offer())
	bottom.add_child(_build_room_center())
	bottom.add_child(_build_ask())
	return page


func _build_offer() -> Control:
	var panel := _deal_panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_offer_box = VBoxContainer.new()
	_offer_box.add_theme_constant_override("separation", 6)
	panel.add_child(_offer_box)
	_offer_band_label = Label.new()
	_offer_box.add_child(_band(_offer_band_label, GameState.team, "%sの提示" % GameData.short_name(GameState.team), 19))
	_amount_bar = Button.new()
	_offer_box.add_child(_stepper("年俸", _amount_bar, _step_amount, 250))
	_years_bar = Button.new()
	_offer_box.add_child(_stepper("年数", _years_bar, _step_years, 110))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	_offer_box.add_child(line)
	_range_label = UiTheme.small_label("", 14, UiTheme.TEXT_SUB, 700)
	UiTheme.fit_label(_range_label)
	line.add_child(_range_label)
	_cancel_offer_button = Button.new()
	_cancel_offer_button.text = "提示を取り消す"
	_cancel_offer_button.custom_minimum_size = Vector2(140, 34)
	UiTheme.style_button(_cancel_offer_button, Color("8a9199"), Color.WHITE, 8, 4)
	_cancel_offer_button.pressed.connect(_on_cancel_offer)
	line.add_child(_cancel_offer_button)
	return panel


func _build_room_center() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(220, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	_stars_label = Label.new()
	_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(_stars_label, 28, Color("e53935"), Color.WHITE, 6)
	box.add_child(_stars_label)
	_odds_label = UiTheme.small_label("", 17, UiTheme.TEXT, 800)
	_odds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_odds_label)
	_change_button = Button.new()
	_change_button.text = "変更する"
	_change_button.custom_minimum_size = Vector2(220, 38)
	_change_button.add_theme_font_size_override("font_size", 19)
	UiTheme.style_button(_change_button, Color("ff8a3d"), Color.WHITE, 10, 5)
	_change_button.pressed.connect(func() -> void: UiInput.grab(_amount_bar))
	box.add_child(_change_button)
	_action_button = Button.new()
	_action_button.text = "提示する"
	_action_button.custom_minimum_size = Vector2(220, 54)
	_action_button.add_theme_font_override("font", UiTheme.font(800))
	_action_button.add_theme_font_size_override("font_size", 26)
	UiTheme.style_button(_action_button, Color("e8413c"), Color.WHITE, 12, 7)
	_action_button.pressed.connect(_on_action_pressed)
	box.add_child(_action_button)
	_back_button = Button.new()
	_back_button.text = "一覧へ戻る"
	_back_button.custom_minimum_size = Vector2(220, 36)
	_back_button.add_theme_font_size_override("font_size", 17)
	UiTheme.style_button(_back_button, Color("8a9199"), Color.WHITE, 10, 4)
	_back_button.pressed.connect(func() -> void: back())
	box.add_child(_back_button)
	return box


func _build_ask() -> Control:
	var panel := _deal_panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(_band(Label.new(), "", "選手の希望", 19, Color("7b5e3b")))
	_ask_amount_label = Label.new()
	box.add_child(_value_row("年俸", _ask_amount_label, 250))
	_ask_years_label = Label.new()
	box.add_child(_value_row("年数", _ask_years_label, 110))
	_diff_label = UiTheme.small_label("", 15, UiTheme.TEXT, 800)
	UiTheme.fit_label(_diff_label)
	box.add_child(_diff_label)
	_wish_label = UiTheme.small_label("", 14, UiTheme.TEXT_SUB, 700)
	UiTheme.fit_label(_wish_label)
	box.add_child(_wish_label)
	return panel


func _deal_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := UiTheme.gloss(Color("eadfc6"), 12, 3, 0, Color("a88a5c"))
	style.gloss = 0.0
	style.gradient = 0.08
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	return panel


## 球団カラーの見出しの帯（team が空なら color の帯）
func _band(label: Label, team: String, text: String, font_size: int, color := Color.TRANSPARENT) -> PanelContainer:
	var band := PanelContainer.new()
	var main := color if team.is_empty() else GameData.team_colors(team)[0]
	var style := UiTheme.gloss(main, 6, 2, 2)
	style.content_margin_top = 1
	style.content_margin_bottom = 3
	band.add_theme_stylebox_override("panel", style)
	label.text = text
	var ink := UiTheme.text_on(main)
	UiTheme.heading(label, font_size, ink, UiTheme.outline_for(ink, main), 5, false)
	label.clip_text = true
	band.add_child(label)
	return band


func _restyle_band(band: PanelContainer, label: Label, team: String, text: String) -> void:
	var main := GameData.team_colors(team)[0]
	var style := UiTheme.gloss(main, 6, 2, 2)
	style.content_margin_top = 1
	style.content_margin_bottom = 3
	band.add_theme_stylebox_override("panel", style)
	label.text = text
	var ink := UiTheme.text_on(main)
	label.label_settings.font_color = ink
	label.label_settings.outline_color = UiTheme.outline_for(ink, main)


## 年俸・年数の行：◀（クリック用）・値の札（フォーカスして十字キーの左右で変える）・▶
func _stepper(title: String, bar: Button, on_step: Callable, width: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var head := UiTheme.small_label(title, 18, UiTheme.TEXT, 800)
	head.custom_minimum_size = Vector2(48, 0)
	row.add_child(head)
	var minus := Button.new()
	minus.text = "◀"
	minus.focus_mode = Control.FOCUS_NONE
	minus.custom_minimum_size = Vector2(46, 44)
	UiTheme.style_button(minus, Color("ff8a3d"), Color.WHITE, 8, 5)
	minus.pressed.connect(func() -> void: on_step.call(-1))
	row.add_child(minus)
	bar.custom_minimum_size = Vector2(width, 44)
	bar.add_theme_font_override("font", UiTheme.font(800))
	bar.add_theme_font_size_override("font_size", 24)
	UiTheme.style_button(bar, Color("ffd84d"), UiTheme.TEXT, 8, 6)
	bar.tooltip_text = "十字キーの ◀▶ で変える"
	bar.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_left", true):
			on_step.call(-1)
			bar.accept_event()
		elif event.is_action_pressed("ui_right", true):
			on_step.call(1)
			bar.accept_event())
	bar.pressed.connect(func() -> void: UiInput.grab(_action_button))
	row.add_child(bar)
	var plus := Button.new()
	plus.text = "▶"
	plus.focus_mode = Control.FOCUS_NONE
	plus.custom_minimum_size = Vector2(46, 44)
	UiTheme.style_button(plus, Color("ff8a3d"), Color.WHITE, 8, 5)
	plus.pressed.connect(func() -> void: on_step.call(1))
	row.add_child(plus)
	_offer_steppers.append_array([minus, bar, plus])
	return row


## 希望の値の行（見るだけ）
func _value_row(title: String, value: Label, width: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var head := UiTheme.small_label(title, 18, UiTheme.TEXT, 800)
	head.custom_minimum_size = Vector2(48, 0)
	row.add_child(head)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiTheme.gloss(Color("fffaf0"), 8, 2, 2, Color("a88a5c")))
	bar.custom_minimum_size = Vector2(width, 44)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiTheme.heading(value, 24, UiTheme.TEXT, Color.WHITE, 6, false)
	bar.add_child(value)
	row.add_child(bar)
	return row


func _render_room(f: FreeAgency) -> void:
	var id := room_id()
	if f == null or id.is_empty() or GameData.player(id).is_empty():
		return
	var p := GameData.player(id)
	var from := _from_team(f, id)
	_room_count.text = "交渉 %d/%d人目" % [_room_index + 1, _marked.size()]
	_restyle_band(_room_band, _room_band_label, from, "%s　%s" % [GameData.short_name(from), p.get("name", id)])
	_room_title.text = "%s %d歳" % [POS_SHORT.get(p.get("primary_pos"), "-"), FreeAgency.age_of(p, f.year)]
	var star_count := _room_stars(f, id)
	_figure.setup(from, NameTag.family_name(str(p.get("name", ""))), NameTag.colors_for(p)[0], star_count)
	_speech_label.text = _speech_text(f, id)
	_render_stats(f, id, p)
	# 提示
	var mlb := f.mlb_info.has(id)
	var own := from == GameState.team
	var r: Array = f.bid_range(id)
	_amount_bar.text = Salary.text(_amount) if _amount > 0 else "-"
	_years_bar.text = "%d年" % _years
	_range_label.text = "提示できる額 %s〜%s" % [Salary.text(r[0]), Salary.text(r[1])]
	var can := _can_offer(f, id)
	for b in _offer_steppers:
		b.disabled = not can
	_offer_box.modulate = Color.WHITE if can else Color(1, 1, 1, 0.6)
	_change_button.disabled = not can
	_action_button.disabled = not can
	_action_button.text = "引き留める" if own else "提示する"
	_cancel_offer_button.visible = not mlb and f.user_bids.has(id) and not f.resolved
	_stars_label.text = _stars(star_count, 3 if mlb else 5) if star_count > 0 else ""
	_odds_label.text = _odds_text(f, id)
	# 希望
	var asking: int = f.mlb_info[id]["asking"] if mlb else f.info[id]["asking"]
	_ask_amount_label.text = Salary.text(asking)
	var want := 0 if mlb else f.want_years_of(id)
	_ask_years_label.text = "%d年" % want if want > 0 else "-"
	_diff_label.text = _diff_text(asking, want)
	_wish_label.text = "　".join(f.pref_words(id)) if not mlb else "（%s）" % f.mlb_info[id]["route"]


func _can_offer(f: FreeAgency, id: String) -> bool:
	if f.mlb_info.has(id):
		return f.mlb_info[id]["from"] == GameState.team and f.mlb_info[id]["status"] == "leave"
	return f.info.has(id) and not f.resolved


func _room_stars(f: FreeAgency, id: String) -> int:
	if f.mlb_info.has(id):
		var m: Dictionary = f.mlb_info[id]
		if m["from"] != GameState.team:
			return 0
		var chance: float = f.keep_chance(id, _amount, _years) if m["status"] == "leave" else float(m["chance"])
		return clampi(1 + int(chance * 10.0 + 0.001), 1, 3)
	if not f.info.has(id):
		return 0
	if f.resolved:
		var res := _result(f, id)
		return 5 if not res.is_empty() and res["to"] == GameState.team else 1
	return f.stars(GameState.league, id, _amount, _years)


func _odds_text(f: FreeAgency, id: String) -> String:
	if f.mlb_info.has(id):
		var m: Dictionary = f.mlb_info[id]
		if m["from"] != GameState.team:
			return "他球団の選手（メジャーへ）"
		match m["status"]:
			"kept":
				return "引き留めに成功"
			"failed":
				return "引き留めは失敗"
		return "成功率：%d%%" % roundi(f.keep_chance(id, _amount, _years) * 100.0)
	if f.resolved:
		var res := _result(f, id)
		return "締め切りました" if res.is_empty() else "結果：%s" % (
			"残留" if res["to"] == res["from"] else GameData.short_name(res["to"]) + "へ")
	return "成功率：%s" % STAR_WORDS[f.stars(GameState.league, id, _amount, _years)]


func _diff_text(asking: int, want: int) -> String:
	if _amount <= 0:
		return ""
	var gap := _amount - asking
	var money := "希望どおり" if gap == 0 else ("希望より %s%s" % ["+" if gap > 0 else "−", Salary.text(absi(gap))])
	if want <= 0:
		return "提示は" + money
	var years := "" if _years == want else "・年数 %+d年" % (_years - want)
	return "提示は%s%s" % [money, years]


func _speech_text(f: FreeAgency, id: String) -> String:
	if f.mlb_info.has(id):
		var m: Dictionary = f.mlb_info[id]
		match m["status"]:
			"kept":
				return "もう一度、このチームでやります！"
			"failed":
				return "メジャーで挑戦したい気持ちは変わりません。"
		return "メジャーに挑戦したいんです。" if m["from"] == GameState.team else "メジャーへ行きます。"
	var words := f.pref_words(id)
	if f.resolved:
		var res := _result(f, id)
		if not res.is_empty():
			return "%sでがんばります！" % GameData.short_name(res["to"])
	var bidders := f.cpu_bidder_count(id)
	var head := "%s。" % "、".join(words) if not words.is_empty() else "条件しだいです。"
	return head + ("\nほかに%d球団から話が来ています。" % bidders if bidders > 0 else "")


## 今季成績と主な能力のランク
func _render_stats(f: FreeAgency, id: String, p: Dictionary) -> void:
	for c in _stats_box.get_children():
		_stats_box.remove_child(c)
		c.queue_free()
	var head := Label.new()
	head.text = "%d年の成績と主な能力" % f.year
	UiTheme.heading(head, 19, Color("1e63c8"), Color.WHITE, 5, false)
	_stats_box.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	_stats_box.add_child(grid)
	var pitcher: bool = p.get("is_pitcher", false)
	var season := GameState.season
	var pairs: Array = []
	if pitcher:
		var s: Dictionary = season.pitching.get(id, {}) if season != null else {}
		pairs = [["防御率", StatTable.era_text(s)], ["勝敗", "%d勝%d敗" % [int(s.get("w", 0)), int(s.get("l", 0))]],
			["セーブ", str(int(s.get("sv", 0)))], ["ホールド", str(int(s.get("hld", 0)))],
			["登板", str(int(s.get("g", 0)))], ["投球回", StatTable.ip_text(int(s.get("outs", 0)))],
			["奪三振", str(int(s.get("so", 0)))], ["与四球", str(int(s.get("bb", 0)))]]
	else:
		var b: Dictionary = season.batting.get(id, {}) if season != null else {}
		var has_ab := int(b.get("ab", 0)) > 0
		pairs = [["打率", StatTable.rate_text(StatTable.avg(b), has_ab)], ["本塁打", str(int(b.get("hr", 0)))],
			["打点", str(int(b.get("rbi", 0)))], ["盗塁", str(int(b.get("sb", 0)))],
			["試合", str(int(b.get("g", 0)))], ["安打", str(int(b.get("h", 0)))],
			["出塁率", StatTable.rate_text(StatTable.obp(b), StatTable.obp_den(b) > 0)],
			["OPS", StatTable.rate_text(StatTable.obp(b) + StatTable.slg(b), has_ab)]]
	for pair: Array in pairs:
		grid.add_child(UiTheme.small_label(pair[0], 14, UiTheme.TEXT_SUB, 700))
		var value := Label.new()
		value.text = pair[1]
		value.custom_minimum_size = Vector2(96, 0)
		UiTheme.heading(value, 19, UiTheme.TEXT, Color.WHITE, 4, false)
		grid.add_child(value)
	_stats_box.add_child(HSeparator.new())
	var ranks := GridContainer.new()
	ranks.columns = 6
	ranks.add_theme_constant_override("h_separation", 6)
	_stats_box.add_child(ranks)
	var block: Variant = p.get("pitching") if pitcher else p.get("batting")
	var ratings: Dictionary = block.get("ratings", {}) if block is Dictionary else {}
	# 投手の総合は詳細画面では名前の横（作業72）。ここでは球速の次に並べる
	var rows: Array = ([["overall", "総合"]] + PlayerDetail.PITCHER_ROWS) if pitcher else PlayerDetail.BATTER_ROWS
	if pitcher:
		var velo: Variant = (block as Dictionary).get("velocity") if block is Dictionary else null
		ranks.add_child(UiTheme.small_label("球速", 14, UiTheme.TEXT_SUB, 700))
		var kmh := UiTheme.small_label("%dkm" % int(velo.get("kmh", 0)) if velo is Dictionary
			and velo.get("kmh") != null else "-", 17, UiTheme.TEXT, 800)
		ranks.add_child(kmh)
	for row: Array in rows:
		if pitcher and ranks.get_child_count() >= 12:
			break
		ranks.add_child(UiTheme.small_label(row[1], 14, UiTheme.TEXT_SUB, 700))
		ranks.add_child(UiTheme.rank_label(ratings.get(row[0]), 20))


func _step_room(delta: int) -> void:
	if _marked.is_empty():
		return
	_room_index = posmod(_room_index + delta, _marked.size())
	_message = ""
	_load_offer(GameState.fa(), room_id())
	refresh()
	focus_first()


## 交渉の部屋の提示の初期値（提示済みならその条件、なければ希望どおり）
func _load_offer(f: FreeAgency, id: String) -> void:
	if f == null or id.is_empty():
		return
	if f.user_bids.has(id):
		_amount = f.user_bids[id]["amount"]
		_years = f.user_bids[id]["years"]
	elif f.info.has(id):
		_amount = f.info[id]["asking"]
		_years = f.want_years_of(id)
	elif f.mlb_info.has(id):
		var m: Dictionary = f.mlb_info[id]
		_amount = m["amount"] if int(m["amount"]) > 0 else m["asking"]
		_years = int(m["years"]) if int(m["years"]) > 0 else 3
	var r := f.bid_range(id)
	_amount = clampi(_amount, r[0], r[1])


func _step_amount(delta: int) -> void:
	var f := GameState.fa()
	var id := room_id()
	if f == null or id.is_empty() or not _can_offer(f, id):
		return
	var r := f.bid_range(id)
	var step := 100 if _amount < 3000 else (500 if _amount < 10000 else 1000)
	_amount = clampi(_amount + delta * step, r[0], r[1])
	refresh()
	UiFx.bump(_amount_bar, 1.06)


func _step_years(delta: int) -> void:
	var f := GameState.fa()
	if f == null or not _can_offer(f, room_id()):
		return
	_years = clampi(_years + delta, 1, FreeAgency.YEARS_MAX)
	refresh()
	UiFx.bump(_years_bar, 1.06)


func _on_action_pressed() -> void:
	var f := GameState.fa()
	var id := room_id()
	if f == null or id.is_empty():
		return
	if f.mlb_info.has(id):
		_message = GameState.mlb_keep(id, _amount, _years)["text"]
	else:
		var error := GameState.fa_offer(id, _amount, _years)
		_message = error if not error.is_empty() else "%sに %s・%d年 を提示しました（締め切りで決まります）。" % [
			_name(id), Salary.text(_amount), _years]
	_shown_key = ""
	refresh()
	UiFx.bump(_action_button, 1.06)
	if _action_button.disabled:
		UiInput.grab(_back_button)


func _on_cancel_offer() -> void:
	var id := room_id()
	if id.is_empty():
		return
	GameState.fa_cancel(id)
	_message = "%sへの提示を取り消しました。" % _name(id)
	_shown_key = ""
	refresh()


func _on_close_pressed() -> void:
	GameState.fa_resolve()
	_room = false
	_message = ""
	_shown_key = ""
	refresh()
	focus_first()


# --- 共通 --------------------------------------------------------------------------------

## 印を付けられない理由（付けられるなら空）
func _mark_block(f: FreeAgency, id: String) -> String:
	if f == null:
		return "FAの交渉はオフの「FA・トレード・ポスティング」で行います"
	if f.resolved:
		return "FAの交渉は締め切りました。"
	if f.mlb_info.has(id):
		if f.mlb_info[id]["from"] != GameState.team:
			return "%sはメジャーへ移籍します（他球団の選手は引き留められません）。" % _name(id)
		if f.mlb_info[id]["status"] != "leave":
			return "%sの引き留めの交渉は終わっています。" % _name(id)
		return ""
	return "" if f.info.has(id) else "FA宣言した選手ではありません。"


func _wants(f: FreeAgency, id: String, team: String) -> bool:
	if not f.info.has(id):
		return false
	var key := "%s|%s" % [id, team]
	if not _want_cache.has(key):
		_want_cache[key] = f.wants(GameState.league, id, team)
	return _want_cache[key]


## 年俸ランク（旧球団の日本人選手の年俸順位。FAの補償のランクと同じ）
func _rank(f: FreeAgency, id: String) -> String:
	if not _rank_cache.has(id):
		var debut := GameData.load_debut_years(f.year)
		_rank_cache[id] = FaCompensation.rank_of(GameState.league, id, _from_team(f, id), f.year, debut) \
			if GameState.league.team_of.has(id) else "C"
	return _rank_cache[id]


func _result(f: FreeAgency, id: String) -> Dictionary:
	for r: Dictionary in f.results:
		if r["id"] == id:
			return r
	return {}


func _mlb_key(f: FreeAgency) -> String:
	if f == null:
		return ""
	var parts: Array[String] = []
	for id in f.mlb:
		parts.append(str(f.mlb_info[id]["status"]).substr(0, 1))
	return "".join(parts)


func _wish_text(f: FreeAgency, id: String) -> String:
	if f.mlb_info.has(id):
		return "引き留めの目安 %s〜（%s）" % [Salary.text(f.mlb_info[id]["asking"]), f.mlb_info[id]["route"]]
	if not f.info.has(id):
		return ""
	return "希望 %s・%d年　今季 %s" % [Salary.text(f.info[id]["asking"]), f.want_years_of(id),
		Salary.text(int(f.info[id]["salary"]))]


func _words_text(f: FreeAgency, id: String) -> String:
	if f.mlb_info.has(id):
		return "「メジャーに挑戦したい」"
	var words := f.pref_words(id)
	return "「%s」" % "」「".join(words) if not words.is_empty() else "「条件しだいです」"


func _state_text(f: FreeAgency, id: String) -> String:
	if f.mlb_info.has(id):
		var m: Dictionary = f.mlb_info[id]
		match m["status"]:
			"kept":
				return "引き留めに成功（%s・%d年、成功率%d%%）" % [Salary.text(m["amount"]), m["years"],
					roundi(m["chance"] * 100.0)]
			"failed":
				return "引き留めは失敗（成功率%d%%）。メジャーへ" % roundi(m["chance"] * 100.0)
		if m["from"] == GameState.team:
			return "メジャー移籍予定（%s）。引き留めは1回だけ" % m["route"]
		return "メジャー移籍（%s）" % m["route"]
	if f.resolved:
		var r := _result(f, id)
		if not r.is_empty():
			var where := "残留" if r["to"] == r["from"] else "%sへ移籍" % GameData.short_name(r["to"])
			return "%s（%s・%d年、入札%d球団）" % [where, Salary.text(r["amount"]), r["years"], r["bidders"]]
	var parts: Array[String] = ["FA宣言（交渉中の他球団：%d）" % f.cpu_bidder_count(id)]
	if f.user_bids.has(id):
		parts.append("提示済み %s・%d年" % [Salary.text(f.user_bids[id]["amount"]), f.user_bids[id]["years"]])
	return "　".join(parts)


func _hint_text(f: FreeAgency) -> String:
	if f == null:
		return "FA・ポスティングの交渉は、オフの「FA・トレード・ポスティング」の段階で行います。"
	return "交渉したい選手を「交渉する」（マスのⒶ）で選び、「OK」で交渉の部屋へ進みます。"


func _status_text(f: FreeAgency) -> String:
	if not _message.is_empty():
		return _message
	if f == null:
		return ""
	if f.resolved:
		var moved := 0
		for r: Dictionary in f.results:
			if r["to"] != r["from"]:
				moved += 1
		return "FA宣言 %d人のうち %d人が移籍しました（表の「決」が移籍先）。%s" % [f.declared.size(), moved,
			"自球団が決めるFAの補償があります（可変ボタン「FAの補償」）。" if GameState.comp_open()
			else "可変ボタン「契約更改へ」で次へ進みます。"]
	if _room:
		return "◀▶で年俸・年数を変えて「%s」。LB/RBで次の選手、Ⓑで一覧へ。" % _action_button.text
	return "FA宣言 %d人・メジャー移籍 %d人。交渉する選手に印を付けて「OK」、提示が終わったら「締め切る」。" % [
		f.declared.size(), f.mlb.size()]


## 交渉の相手の元の球団（FA宣言・メジャー移籍のときの所属）
func _from_team(f: FreeAgency, id: String) -> String:
	if f != null and f.info.has(id):
		return f.info[id]["from"]
	if f != null and f.mlb_info.has(id):
		return f.mlb_info[id]["from"]
	return GameState.league.team_of.get(id, "")


func _name(id: String) -> String:
	return GameState.league.names.get(id, id) if GameState.league != null else id


static func _stars(n: int, total := 5) -> String:
	return "★".repeat(n) + "☆".repeat(maxi(0, total - n))


func _ability_text(p: Dictionary) -> String:
	var pitcher: bool = p.get("is_pitcher", false)
	var parts: Array[String] = []
	var ratings: Variant = (p.get("pitching") if pitcher else p.get("batting"))
	if not ratings is Dictionary or not ratings.get("ratings") is Dictionary:
		return ""
	var keys := [["overall", "総合"], ["stamina", "スタミナ"], ["bb9", "制球"]] if pitcher \
		else [["meet", "ミート"], ["power", "パワー"], ["speed", "走力"], ["defense", "守備"]]
	for k: Array in keys:
		var r: Variant = ratings["ratings"].get(k[0])
		parts.append("%s%s" % [k[1], r["rank"] if r is Dictionary else "-"])
	if pitcher:
		parts.append("決め球%s" % PitchArsenal.best_label(p))  # 作業79：奪三振の代わりに持ち球の決め球
	return " ".join(parts)
