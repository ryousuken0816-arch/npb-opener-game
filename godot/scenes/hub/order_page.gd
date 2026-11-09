class_name OrderPage
extends HBoxContainer
## 采配 → 起用設定（docs/references/README.md「order_pawapuro.webp」）。
##
## 左で DHあり／DHなし を切り替え、中央にスターティングオーダー（打順・名前札・守備位置）、右に控え（1軍の野手）。
## - 中央上部に「守備充足インジケーター」：どの守備位置を誰が守っているか／空き／重複をひと目で表示する。
##   DHありのときは投手は打順に入らない（先発投手が投げる）ので投手は警告の対象外。
## 操作（作業82）：**札を押す＝選手詳細**（見るだけ。何も入れ替わらない）。入れ替えは札の横の「⇄」から：
## - 「⇄」を押す → 入れ替え中（その札が色つきになり、上の1行に「入れ替え中：〇〇」と出る）→ 相手の札（か相手の「⇄」）を押すと入れ替わる
## - 入れ替え中にもう一度同じ「⇄」（またはその札・Ⓑ・Ⓧ）を押すと取り消し
## - スタメン ⇄ 控え：その打順・守備位置に控えの選手を入れる（元の選手は控えへ）
## - スタメン ⇄ スタメン：打順を入れ替える（守備位置は選手についていく）
## - 各行の [▲][▼]：クリックで前後の打順と即座に入れ替え
## - 守備位置の欄：選ぶと、その位置を守っていた選手と守備位置を入れ替える
## 対左投手用のオーダーは未実装。2軍の選手は「野手1軍登録」で上げてから使う。
## コントローラー：十字キーで札・守備位置の欄を選び、Ⓐ＝選手詳細、Ⓧ＝入れ替え（相手の札で Ⓐ か Ⓧ）、Ⓑ＝入れ替えの取り消し。
## 作り直してもフォーカスは同じ位置に残る。
## オフシーズン（編成を変えられない間）は「⇄」が押せず、札を押すと選手詳細だけ。

signal roster_changed

const TAG_SIZE := Vector2(136, 32)
const BENCH_TAG_SIZE := Vector2(84, 32)
const RANK_COLUMNS := [["meet", "ミ"], ["power", "パ"], ["speed", "走"]]
const FIELD_POSITIONS := ["投手", "捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "左翼手", "中堅手", "右翼手"]
const FIELD_SHORT := {
	"投手": "投", "捕手": "捕", "一塁手": "一", "二塁手": "二", "三塁手": "三",
	"遊撃手": "遊", "左翼手": "左", "中堅手": "中", "右翼手": "右", "指名打者": "指",
}

var _palette: UiTheme.Palette
var _team: SimTeam
var _names := {}
var _use_dh := true
## 入れ替え中の「元」の札（スタメンの打順の位置か、控えの選手）。どちらも空なら入れ替え中ではない
var _sel_index := -1
var _sel_bench: SimPlayer = null
var _message := ""

var _dh_button: Button
var _no_dh_button: Button
var _message_label: Label
var _coverage_box: HBoxContainer
var _lineup_title: Label
var _lineup_box: VBoxContainer
var _bench_title: Label
var _bench_grid: GridContainer
## 札の並び（スタメン→控え。選手詳細の十字キーで送る順）
var _order_ids: Array[String] = []


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	add_theme_constant_override("separation", 8)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(150, 0)
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	var group := ButtonGroup.new()
	_dh_button = _toggle("DHあり", group, true)
	left.add_child(_dh_button)
	_no_dh_button = _toggle("DHなし", group, false)
	left.add_child(_no_dh_button)
	var auto := Button.new()
	auto.text = "自動で組む"
	auto.custom_minimum_size = Vector2(0, 42)
	auto.tooltip_text = "1軍の野手から能力と実績でスタメン・打順を組み直します"
	UiTheme.style_button(auto, Color("1e88e5"), Color.WHITE, 8, 3)
	auto.pressed.connect(_on_auto)
	left.add_child(auto)
	var hint := UiTheme.small_label(
			"札を押すと選手詳細（何も変わりません）。\n入れ替えは「⇄」→相手の札（もう一度「⇄」で取り消し）。\n▲▼で打順を入れ替え。\n\n控え ⇄ スタメン → その打順に入る\n\n"
			+ "守備位置は右の欄で変えられます。\n\nDHなしはセ・リーグ主催、DHありはパ・リーグ主催の試合で使います。", 13)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(hint)

	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 4)
	add_child(center)
	_message_label = UiTheme.fit_label(UiTheme.small_label("", 14, UiTheme.TEXT_SUB, 700))
	_message_label.custom_minimum_size = Vector2(430, 0)
	center.add_child(_message_label)
	_coverage_box = HBoxContainer.new()
	_coverage_box.add_theme_constant_override("separation", 2)
	center.add_child(_coverage_box)
	var lineup := UiTheme.titled_panel(p, "スターティングオーダー")
	lineup["panel"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lineup_title = lineup["title"]
	_lineup_box = lineup["body"]
	_lineup_box.add_theme_constant_override("separation", 3)
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


## 入れ替え中か
func is_swapping() -> bool:
	return _sel_index >= 0 or _sel_bench != null


## 入れ替えを取り消す（取り消したら true。Ⓑ・Esc で画面を戻る前に呼ぶ）
func clear_selection() -> bool:
	if not is_swapping():
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
	_clear(_coverage_box)
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
		_message_label.text = _swap_message() if is_swapping() \
				else (_message if not _message.is_empty() else "札＝選手詳細／入れ替えは ⇄ から（▲▼で打順）")
	_message_label.add_theme_color_override("font_color",
			Color("e65100") if is_swapping() and GameState.can_edit_roster() else UiTheme.TEXT_SUB)
	_lineup_title.text = "%s・スターティングオーダー" % ("DHあり" if _use_dh else "DHなし")
	_render_coverage()
	_render_lineup()
	_render_bench()


## 入れ替え中の案内の1行
func _swap_message() -> String:
	var who := ""
	if _sel_bench != null:
		who = _sel_bench.name
	elif _sel_index >= 0:
		var here: SimPlayer = _team.lineup(_use_dh)[_sel_index][0]
		who = "%d番 %s" % [_sel_index + 1, here.name if here != null else "投手"]
	return "入れ替え中：%s → 相手を選択（⇄・Ⓑで取り消し）" % who


func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


## 守備充足インジケーター：各ポジションを誰が守っているか／空き／重複を表示する
func _render_coverage() -> void:
	var order := _team.lineup(_use_dh)
	# ポジション → 守っている選手名の配列
	var holders := {}
	for entry: Array in order:
		var pos: String = entry[1]
		var p: SimPlayer = entry[0]
		if not holders.has(pos):
			holders[pos] = []
		if p != null:
			holders[pos].append(_names.get(p.id, p.name))
		elif pos == "投手":
			holders[pos].append("先発")
	var positions: Array = FIELD_POSITIONS.duplicate()
	if _use_dh:
		positions.append("指名打者")
	for pos: String in positions:
		var names: Array = holders.get(pos, [])
		var state := "ok"
		if names.is_empty():
			state = "empty"
		elif names.size() > 1:
			state = "dup"
		# DH制のとき投手は打順に入らない（先発が投げる）ので空きでも警告しない
		if pos == "投手" and _use_dh and names.is_empty():
			state = "ok"
			names = ["先発"]
		_coverage_box.add_child(_coverage_cell(pos, state, names))


func _coverage_cell(pos: String, state: String, names: Array) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(40, 36)
	var bg: Color
	var fg := Color.WHITE
	var line: String
	match state:
		"empty":
			bg = Color("d32f2f")
			line = "空き"
		"dup":
			bg = Color("f9a825")
			fg = Color("3e2723")
			line = "重複"
		_:
			bg = Color("2e7d32")
			line = str(names[0]).substr(0, 3) if not names.is_empty() else "OK"
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(5)
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := UiTheme.small_label(FIELD_SHORT.get(pos, pos), 14, fg, 800)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var body := UiTheme.small_label(line, 11, fg, 700)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.clip_text = true
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body)
	panel.add_child(v)
	match state:
		"empty":
			panel.tooltip_text = "%s：空き（誰も守っていません）" % pos
		"dup":
			panel.tooltip_text = "%s：重複（%s）" % [pos, "、".join(names)]
		_:
			panel.tooltip_text = "%s：%s" % [pos, "、".join(names)]
	return panel


func _render_lineup() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(22 + 4 + TAG_SIZE.x + 4 + 96 + 4 + 66, 0)
	header.add_child(pad)
	for col: Array in RANK_COLUMNS + [["def", "守"]]:
		var l := UiTheme.small_label(col[1], 13, UiTheme.TEXT_SUB, 700)
		l.custom_minimum_size = Vector2(24, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_child(l)
	_lineup_box.add_child(header)

	var order := _team.lineup(_use_dh)
	for i in order.size():
		var p: SimPlayer = order[i][0]
		var pos: String = order[i][1]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var num_color := _palette.ink
		if i in [2, 3, 4]:
			num_color = Color("e65100")
		var num := UiTheme.small_label(str(i + 1), 22, num_color, 800)
		num.custom_minimum_size = Vector2(22, 0)
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
			if _is_breakout(p):
				tag.tooltip_text += "\n★ブレイク（この年の主力・好成績選手）"
		tag.selected = i == _sel_index
		tag.set_meta("swap_index", i)
		tag.pressed.connect(_on_lineup_pressed.bind(i))
		row.add_child(tag)
		if p != null and _is_breakout(p):
			var badge := UiTheme.small_label("★", 14, Color("f9a825"), 800)
			badge.tooltip_text = "ブレイク（この年の主力・好成績選手）"
			badge.custom_minimum_size = Vector2(14, 0)
			row.add_child(badge)
		row.add_child(_position_selector(i, pos))
		row.add_child(_move_buttons(i, order.size()))
		var ratings: Dictionary = {}
		if p != null:
			var batting: Variant = GameData.player(p.id).get("batting")
			if batting is Dictionary and batting.get("ratings") is Dictionary:
				ratings = batting["ratings"]
		for col: Array in RANK_COLUMNS:
			var r := UiTheme.rank_label(ratings.get(col[0]) if p != null else null, 17)
			r.custom_minimum_size = Vector2(24, 0)
			row.add_child(r)
		var def := UiTheme.rank_label(_defense_rating(p, pos), 17)
		def.custom_minimum_size = Vector2(24, 0)
		if p != null and pos != "指名打者" and not p.defense.has(SimTeam.field_key(pos)):
			def.text = "×"
			def.tooltip_text = "この守備位置の出場記録がありません（守備力が大きく下がります）"
			def.add_theme_color_override("font_color", Color("d32f2f"))
		row.add_child(def)
		_lineup_box.add_child(row)


## ▲▼の打順入れ替えボタン（十字キー操作を阻害しないようフォーカス対象外）
func _move_buttons(i: int, count: int) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.custom_minimum_size = Vector2(66, 0)
	var editable := GameState.can_edit_roster()
	var swap := _swap_button(editable, i == _sel_index)
	swap.pressed.connect(_on_lineup_swap.bind(i))
	box.add_child(swap)
	var up := _arrow_button("▲", editable and i > 0)
	up.tooltip_text = "1つ前の打順と入れ替え"
	up.pressed.connect(_on_move.bind(i, i - 1))
	box.add_child(up)
	var down := _arrow_button("▼", editable and i < count - 1)
	down.tooltip_text = "1つ後ろの打順と入れ替え"
	down.pressed.connect(_on_move.bind(i, i + 1))
	box.add_child(down)
	return box


## 「⇄」入れ替えボタン（押すと入れ替え中。入れ替え中の元の札のは色が変わり、押すと取り消し）。十字キーを阻害しないようフォーカス対象外（パッドは Ⓧ）
func _swap_button(enabled: bool, active: bool) -> Button:
	var b := _arrow_button("⇄", enabled)
	b.custom_minimum_size = Vector2(22, 24)
	b.tooltip_text = "入れ替え中です。もう一度押すと取り消し" if active else "入れ替える：押したあと、相手の札を押します"
	UiTheme.style_button(b, Color("e65100") if active else Color("1e88e5"), Color.WHITE, 4, 2)
	return b


func _arrow_button(text: String, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(20, 24)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", 11)
	UiTheme.style_button(b, Color("546e7a"), Color.WHITE, 4, 2)
	return b


## 当年ブレイクした選手（キャリアハイ・規定到達など）か
func _is_breakout(p: SimPlayer) -> bool:
	var data: Dictionary = GameData.player(p.id)
	if data.is_empty():
		return false
	if bool(data.get("breakout", false)) or bool(data.get("career_high", false)):
		return true
	var batting: Variant = data.get("batting")
	if batting is Dictionary:
		if bool(batting.get("breakout", false)) or bool(batting.get("career_high", false)):
			return true
		if bool(batting.get("qualified", false)) and bool(batting.get("rookie_year", false)):
			return true
	return false


## 守備位置の選択欄（投手の打順は固定表示）
func _position_selector(i: int, pos: String) -> Control:
	if pos == "投手":
		var l := UiTheme.small_label("投手", 16, UiTheme.TEXT, 800)
		l.custom_minimum_size = Vector2(96, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return l
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(96, 0)
	option.add_theme_font_size_override("font_size", 15)
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
		if _is_breakout(p):
			tag.tooltip_text += "\n★ブレイク（この年の主力・好成績選手）"
		tag.selected = p == _sel_bench
		tag.set_meta("swap_bench", p)
		tag.pressed.connect(_on_bench_pressed.bind(p))
		row.add_child(tag)
		var swap := _swap_button(GameState.can_edit_roster(), p == _sel_bench)
		swap.pressed.connect(_on_bench_swap.bind(p))
		row.add_child(swap)
		var pos_text: String = RegisterPage.POS_SHORT.get(p.primary_pos, "-")
		var pos := UiTheme.small_label(pos_text, 15, UiTheme.TEXT_SUB, 800)
		pos.custom_minimum_size = Vector2(22, 0)
		row.add_child(pos)
		if _is_breakout(p):
			var badge := UiTheme.small_label("★", 14, Color("f9a825"), 800)
			badge.tooltip_text = "ブレイク（この年の主力・好成績選手）"
			row.add_child(badge)
		_bench_grid.add_child(row)


# --- 操作 --------------------------------------------------------------------------

func _on_move(from: int, to: int) -> void:
	if not GameState.can_edit_roster():
		return
	if from < 0 or to < 0 or from >= _team.lineup(_use_dh).size() or to >= _team.lineup(_use_dh).size():
		return
	_team.lineup_swap_order(_use_dh, from, to)
	_sel_index = -1
	_sel_bench = null
	_message = "%d番と%d番を入れ替えました" % [from + 1, to + 1]
	refresh()
	roster_changed.emit()


## スタメンの札：入れ替え中でなければ選手詳細（何も変わらない）。入れ替え中なら相手として選ぶ
func _on_lineup_pressed(i: int) -> void:
	if is_swapping():
		_swap_with_lineup(i)
		return
	var here: SimPlayer = _team.lineup(_use_dh)[i][0]
	if here != null:
		_open_detail(here)


## スタメンの「⇄」（パッドは Ⓧ）：入れ替えを始める／同じ札なら取り消し／別の札なら相手として入れ替える
func _on_lineup_swap(i: int) -> void:
	if not GameState.can_edit_roster():
		return
	if is_swapping():
		_swap_with_lineup(i)
		return
	_sel_index = i
	_message = ""
	refresh()


func _swap_with_lineup(i: int) -> void:
	if _sel_bench != null:
		var p := _sel_bench
		_on_bench_into(i, p)
		return
	if _sel_index == i:
		clear_selection()
		return
	var from := _sel_index
	_team.lineup_swap_order(_use_dh, from, i)
	_message = "%d番と%d番を入れ替えました" % [from + 1, i + 1]
	_sel_index = -1
	refresh()
	roster_changed.emit()


## 控えの札：入れ替え中でなければ選手詳細。入れ替え中ならスタメンの元の札に入れる
func _on_bench_pressed(p: SimPlayer) -> void:
	if is_swapping():
		_swap_with_bench(p)
		return
	_open_detail(p)


## 控えの「⇄」（パッドは Ⓧ）
func _on_bench_swap(p: SimPlayer) -> void:
	if not GameState.can_edit_roster():
		return
	if is_swapping():
		_swap_with_bench(p)
		return
	_sel_bench = p
	_message = ""
	refresh()


func _swap_with_bench(p: SimPlayer) -> void:
	if _sel_bench == p:
		clear_selection()
	elif _sel_bench != null:
		_message = "控えの選手どうしは入れ替えられません（スタメンの札を選んでください）"
		refresh()
	else:
		_on_bench_into(_sel_index, p)


## パッドの Ⓧ（ui_swap）：フォーカス中の札の「⇄」と同じ
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed(UiInput.SWAP):
		return
	var f := get_viewport().gui_get_focus_owner()
	if f == null:
		return
	if f.has_meta("swap_index") and _lineup_box.is_ancestor_of(f):
		_on_lineup_swap(int(f.get_meta("swap_index")))
		get_viewport().set_input_as_handled()
	elif f.has_meta("swap_bench") and _bench_grid.is_ancestor_of(f):
		_on_bench_swap(f.get_meta("swap_bench") as SimPlayer)
		get_viewport().set_input_as_handled()


func _open_detail(p: SimPlayer) -> void:
	var from: Control = get_viewport().gui_get_focus_owner()
	PlayerDetail.open(from if from != null else self, p.id, _order_ids)


func _on_bench_into(i: int, p: SimPlayer) -> void:
	_sel_index = -1
	_sel_bench = null
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
