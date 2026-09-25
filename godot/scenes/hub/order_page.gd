class_name OrderPage
extends HBoxContainer
## 采配 → 起用設定（docs/references/README.md「order_pawapuro.webp」）。
##
## 左で DHあり／DHなし を切り替え、中央にスターティングオーダー（打順・名前札・守備位置）、右に控え（1軍の野手）。
## - スタメンの札 → 控えの札：その打順・守備位置に控えの選手を入れる（元の選手は控えへ）
## - スタメンの札 → スタメンの札：打順を入れ替える（守備位置は選手についていく）
## - 守備位置の欄：選ぶと、その位置を守っていた選手と守備位置を入れ替える
## 対左投手用のオーダーは未実装。2軍の選手は「野手1軍登録」で上げてから使う。
## コントローラー：十字キーで札・守備位置の欄を選び Ⓐ。作り直してもフォーカスは同じ位置に残る。
## 選んでいる札をもう一度 Ⓐ・クリック（または右クリック）で選手詳細。Ⓑ はまず選択を取り消す。
## オフシーズン（編成を変えられない間）は札を押すとすぐ選手詳細。

signal roster_changed

const TAG_SIZE := Vector2(150, 36)
const BENCH_TAG_SIZE := Vector2(128, 34)
const RANK_COLUMNS := [["meet", "ミ"], ["power", "パ"], ["speed", "走"]]

var _palette: UiTheme.Palette
var _team: SimTeam
var _names := {}
var _use_dh := true
var _sel_index := -1
var _sel_bench: SimPlayer = null
var _message := ""

var _dh_button: Button
var _no_dh_button: Button
var _message_label: Label
var _lineup_title: Label
var _lineup_box: VBoxContainer
var _bench_title: Label
var _bench_grid: GridContainer
## 札の並び（スタメン→控え。選手詳細の十字キーで送る順）
var _order_ids: Array[String] = []


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	add_theme_constant_override("separation", 10)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(170, 0)
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	var group := ButtonGroup.new()
	_dh_button = _toggle("DHあり", group, true)
	left.add_child(_dh_button)
	_no_dh_button = _toggle("DHなし", group, false)
	left.add_child(_no_dh_button)
	var auto := Button.new()
	auto.text = "自動で組む"
	auto.tooltip_text = "1軍の野手から能力と実績でスタメン・打順を組み直します"
	auto.pressed.connect(_on_auto)
	left.add_child(auto)
	var hint := UiTheme.small_label(
			"札を選んでから、入れ替える相手をクリック。\n\n控え → その打順・守備位置に入る\nスタメン → 打順を入れ替え\n\n"
			+ "守備位置は右の欄で変えられます。\n\nDHなしはセ・リーグ主催、DHありはパ・リーグ主催の試合で使います。", 14)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(hint)

	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 6)
	add_child(center)
	_message_label = UiTheme.small_label("", 15, UiTheme.TEXT_SUB, 700)
	_message_label.clip_text = true
	_message_label.custom_minimum_size = Vector2(460, 0)
	center.add_child(_message_label)
	var lineup := UiTheme.titled_panel(p, "スターティングオーダー")
	lineup["panel"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lineup_title = lineup["title"]
	_lineup_box = lineup["body"]
	center.add_child(lineup["panel"])

	var bench := UiTheme.titled_panel(p, "控え")
	bench["panel"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bench_title = bench["title"]
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	bench["body"].add_child(scroll)
	_bench_grid = GridContainer.new()
	_bench_grid.columns = 2
	_bench_grid.add_theme_constant_override("h_separation", 10)
	_bench_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_bench_grid)
	var note := UiTheme.small_label("2軍の選手は「野手1軍登録」で1軍に上げると控えに入ります。", 13)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bench["body"].add_child(note)
	add_child(bench["panel"])


func _toggle(text: String, group: ButtonGroup, dh: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 20)
	UiTheme.style_toggle(b, _palette.ink)
	b.toggled.connect(func(on_state: bool) -> void:
		if on_state and _use_dh != dh:
			_use_dh = dh
			_sel_index = -1
			_sel_bench = null
			_message = ""
			refresh())
	return b


func refresh(reset_selection: bool = false) -> void:
	_team = GameState.my_team()
	if reset_selection:
		_sel_index = -1
		_sel_bench = null
		_message = ""
	_dh_button.set_pressed_no_signal(_use_dh)
	_no_dh_button.set_pressed_no_signal(not _use_dh)
	# 作り直す前のフォーカスの位置（スタメン・控えの何番目か）を覚えておく
	var focus_box: Control = null
	var focus_at := -1
	for box: Control in [_lineup_box, _bench_grid]:
		var i := UiInput.focus_index(box)
		if i >= 0:
			focus_box = box
			focus_at = i
	_refresh_body()
	if focus_box != null:
		UiInput.focus_nth(focus_box, focus_at)


## 選んでいる札を取り消す（取り消したら true）
func clear_selection() -> bool:
	if _sel_index < 0 and _sel_bench == null:
		return false
	_sel_index = -1
	_sel_bench = null
	_message = ""
	refresh()
	return true


## 画面を開いたとき：スタメンの1番の札にフォーカス
func focus_first() -> void:
	if not UiInput.focus_first(_lineup_box):
		_dh_button.grab_focus()


func _refresh_body() -> void:
	_clear(_lineup_box)
	_clear(_bench_grid)
	if _team == null:
		_message_label.text = "日程データのない年は編成できません"
		return
	_names = NameTag.short_names(_team.players)
	_order_ids.clear()
	for entry: Array in _team.lineup(_use_dh):
		if entry[0] != null:
			_order_ids.append((entry[0] as SimPlayer).id)
	for p in _team.bench(_use_dh):
		_order_ids.append(p.id)
	if not GameState.can_edit_roster():
		_message_label.text = "オフシーズンは編成を変えられません（見るだけ）"
	else:
		_message_label.text = _message if not _message.is_empty() else "対左投手用のオーダーは今後追加予定"
	_lineup_title.text = "%s・スターティングオーダー" % ("DHあり" if _use_dh else "DHなし")
	_render_lineup()
	_render_bench()


func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _render_lineup() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(28 + 6 + TAG_SIZE.x + 6 + 112, 0)
	header.add_child(pad)
	for col: Array in RANK_COLUMNS + [["def", "守"]]:
		var l := UiTheme.small_label(col[1], 14, UiTheme.TEXT_SUB, 700)
		l.custom_minimum_size = Vector2(28, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_child(l)
	_lineup_box.add_child(header)

	var order := _team.lineup(_use_dh)
	for i in order.size():
		var p: SimPlayer = order[i][0]
		var pos: String = order[i][1]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var num := UiTheme.small_label(str(i + 1), 24, _palette.ink, 800)
		num.custom_minimum_size = Vector2(28, 0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(num)
		var tag := NameTag.new()
		tag.custom_minimum_size = TAG_SIZE
		if p == null:
			tag.setup_plain("投　手", NameTag.COLOR_PITCHER.lerp(Color.WHITE, 0.45))
			tag.tooltip_text = "その日の先発投手"
		else:
			tag.setup_player(GameData.player(p.id), _names.get(p.id, p.name))
			tag.tooltip_text = p.name
		tag.selected = i == _sel_index
		tag.pressed.connect(_on_lineup_pressed.bind(i))
		row.add_child(tag)
		row.add_child(_position_selector(i, pos))
		var ratings: Dictionary = {}
		if p != null:
			var batting: Variant = GameData.player(p.id).get("batting")
			if batting is Dictionary and batting.get("ratings") is Dictionary:
				ratings = batting["ratings"]
		for col: Array in RANK_COLUMNS:
			var r := UiTheme.rank_label(ratings.get(col[0]) if p != null else null, 18)
			r.custom_minimum_size = Vector2(28, 0)
			row.add_child(r)
		var def := UiTheme.rank_label(_defense_rating(p, pos), 18)
		def.custom_minimum_size = Vector2(28, 0)
		if p != null and pos != "指名打者" and not p.defense.has(SimTeam.field_key(pos)):
			def.text = "×"
			def.tooltip_text = "この守備位置の出場記録がありません（守備力が大きく下がります）"
			def.add_theme_color_override("font_color", Color("d32f2f"))
		row.add_child(def)
		_lineup_box.add_child(row)


## 守備位置の選択欄（投手の打順は固定表示）
func _position_selector(i: int, pos: String) -> Control:
	if pos == "投手":
		var l := UiTheme.small_label("投手", 17, UiTheme.TEXT, 800)
		l.custom_minimum_size = Vector2(112, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return l
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(112, 0)
	option.add_theme_font_size_override("font_size", 16)
	option.fit_to_longest_item = false
	var choices: Array[String] = []
	for candidate: String in SimTeam.LINEUP_POSITIONS:
		if candidate == "指名打者" and not _use_dh:
			continue
		choices.append(candidate)
		option.add_item(candidate)
	option.select(choices.find(pos))
	option.disabled = not GameState.can_edit_roster()
	var color := NameTag.pos_color(pos)
	var style := UiTheme.gloss(color.lerp(Color.WHITE, 0.35), 6, 2, 2, color.darkened(0.2))
	style.content_margin_left = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2 + style.depth
	var hover := style.copy()
	hover.bg_color = color.lerp(Color.WHITE, 0.55)
	for state in ["normal", "disabled"]:
		option.add_theme_stylebox_override(state, style)
	option.add_theme_stylebox_override("hover", hover)
	option.add_theme_stylebox_override("pressed", style.pressed_copy())
	option.add_theme_stylebox_override("focus", UiTheme.focus_frame(6))
	for c in UiTheme.BUTTON_FONT_COLORS + ["font_disabled_color"]:
		option.add_theme_color_override(c, UiTheme.TEXT)
	option.item_selected.connect(func(index: int) -> void:
		var new_pos := choices[index]
		_team.lineup_set_position(_use_dh, i, new_pos)
		_message = "守備位置を変更しました"
		refresh()
		roster_changed.emit())
	return option


func _defense_rating(p: SimPlayer, pos: String) -> Variant:
	if p == null or pos == "指名打者":
		return null
	var fielding: Variant = GameData.player(p.id).get("fielding")
	if fielding is Dictionary and fielding.get(SimTeam.field_key(pos)) is Dictionary:
		return fielding[SimTeam.field_key(pos)].get("defense")
	return null


func _render_bench() -> void:
	var bench := _team.bench(_use_dh)
	_bench_title.text = "控え（%d人）" % bench.size()
	for p in bench:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var tag := NameTag.new()
		tag.custom_minimum_size = BENCH_TAG_SIZE
		tag.setup_player(GameData.player(p.id), _names.get(p.id, p.name))
		tag.tooltip_text = p.name
		tag.selected = p == _sel_bench
		tag.pressed.connect(_on_bench_pressed.bind(p))
		row.add_child(tag)
		var pos_text: String = RegisterPage.POS_SHORT.get(p.primary_pos, "-")
		var pos := UiTheme.small_label(pos_text, 15, UiTheme.TEXT_SUB, 800)
		pos.custom_minimum_size = Vector2(22, 0)
		row.add_child(pos)
		_bench_grid.add_child(row)


# --- 操作 --------------------------------------------------------------------------

func _on_lineup_pressed(i: int) -> void:
	var here: SimPlayer = _team.lineup(_use_dh)[i][0]
	if here != null and (_sel_index == i or not GameState.can_edit_roster()):
		_open_detail(here)
		return
	if not GameState.can_edit_roster():
		return
	if _sel_bench != null:
		var p := _sel_bench
		if _team.lineup(_use_dh)[i][0] == null:
			_message = "投手の打順には野手を入れられません"
		else:
			_team.lineup_replace(_use_dh, i, p)
			_message = "%sを%d番に入れました" % [p.name, i + 1]
			roster_changed.emit()
		_sel_bench = null
		_sel_index = -1
	elif _sel_index == -1:
		_sel_index = i
		_message = ""
	elif _sel_index == i:
		_sel_index = -1  # 「投手」の打順の札（選手詳細はない）
	else:
		_team.lineup_swap_order(_use_dh, _sel_index, i)
		_message = "%d番と%d番を入れ替えました" % [_sel_index + 1, i + 1]
		_sel_index = -1
		roster_changed.emit()
	refresh()


func _on_bench_pressed(p: SimPlayer) -> void:
	if _sel_bench == p or not GameState.can_edit_roster():
		_open_detail(p)
		return
	if _sel_index >= 0:
		var i := _sel_index
		_sel_index = -1
		_on_bench_into(i, p)
		return
	_sel_bench = p
	_message = ""
	refresh()


func _open_detail(p: SimPlayer) -> void:
	var from: Control = get_viewport().gui_get_focus_owner()
	PlayerDetail.open(from if from != null else self, p.id, _order_ids)


func _on_bench_into(i: int, p: SimPlayer) -> void:
	if _team.lineup(_use_dh)[i][0] == null:
		_message = "投手の打順には野手を入れられません"
	else:
		_team.lineup_replace(_use_dh, i, p)
		_message = "%sを%d番に入れました" % [p.name, i + 1]
		roster_changed.emit()
	refresh()


func _on_auto() -> void:
	if not GameState.can_edit_roster() or _team == null:
		return
	_team.auto_lineup(_use_dh)
	_sel_index = -1
	_sel_bench = null
	_message = "%sのスタメンを自動で組み直しました" % ("DHあり" if _use_dh else "DHなし")
	refresh()
	roster_changed.emit()
