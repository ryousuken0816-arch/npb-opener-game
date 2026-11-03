class_name ScoutNotebook
extends PanelContainer
## スカウトの手帳の1ページ（docs/AUTORUN.md 作業51。参考：docs/references/draft_notebook_mock.html の左）。
## ドラフト画面（DraftView）と作戦会議（DraftMeetingView）で使う。候補1人を1ページに書く：
## 罫線の紙・手書き風の字、No.・出身・名前・守備位置・投打・年齢・身長、当時の評価の赤いハンコ、採点表（投手は球速の数字と
## 奪三振・制球・被本塁打・スタミナ・総合、野手はミート・パワー・選球眼・走力・守備・肩。良い＝赤・ふつう＝青・弱点＝灰）、
## アマのニュースの切り抜き、スカウトの寸評（長所・弱点・他球団の噂）、特徴のマグネットの札、◎○△☆✕の印、書き込みのメモ。
## 下に「◀ めくる」「この男でいく」「めくる ▶」と「表に切り替え」。中身の文言は ScoutNotes が作る。
## 横長の画面では見開き（左のページに名前・採点表・札、右のページに切り抜き・寸評・メモ）、縦長では1列に並べる。
## 入団前に見えるのは今の能力だけ（将来性・1年目は書かない）

signal flip_requested(delta: int)
signal go_pressed
signal mark_requested(mark: String)
signal memo_changed(text: String)
signal detail_requested
signal table_requested

const PAPER := Color("FAEEDA")
const PAPER_EDGE := Color("BA7517")
const INK := Color("412402")
const INK_SUB := Color("854F0B")
const RED := Color("A32D2D")
const RULE := Color(0.73, 0.46, 0.09, 0.18)
const MARGIN_RULE := Color(0.64, 0.18, 0.18, 0.28)
const RULE_STEP := 30.0
## 手書き風の字：教科書体・明朝（無ければ同梱の丸ゴシック）
const HAND_FONT_NAMES := ["HGKyokashotai", "HG教科書体", "Yu Mincho", "YuMincho", "游明朝", "BIZ UDMincho",
	"MS Mincho", "Hiragino Mincho ProN", "Noto Serif CJK JP", "Noto Serif JP", "serif"]

static var _hand_fonts := {}

var _cols: BoxContainer
var _left: VBoxContainer
var _right: VBoxContainer
var _no_label: Label
var _name_button: Button
var _mark_label: Label
var _profile_label: Label
var _state_label: Label
var _stamp: Stamp
var _sheet: GridContainer
var _magnets: HFlowContainer
var _clip_panel: PanelContainer
var _clip_source: Label
var _clip_headline: Label
var _comments: VBoxContainer
var _memo: LineEdit
var _mark_buttons := {}
var _extra: VBoxContainer
var _go_button: Button
var _prev_button: Button
var _next_button: Button
var _page_label: Label
var _table_button: Button
## 縦長のときだけ出す下の行（何枚目か・表に切り替え）。横長は見出しに枚数、表は上の「表」で
var _footer: HBoxContainer
var _empty_label: Label
var _scroll: ScrollContainer
var _memo_key := ""


## 当時の評価のハンコ（赤い丸に「当時の評価」と大きなランク。少し傾ける）
class Stamp:
	extends Control
	var rank := ""

	func _init() -> void:
		custom_minimum_size = Vector2(64, 64)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if rank.is_empty():
			return
		var c := size / 2.0
		draw_set_transform(c, deg_to_rad(-12.0), Vector2.ONE)
		var r := minf(size.x, size.y) / 2.0 - 3.0
		var red := ScoutNotebook.RED
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, red, 3.0, true)
		draw_arc(Vector2.ZERO, r - 5.0, 0.0, TAU, 48, Color(red, 0.5), 1.0, true)
		var font := ScoutNotebook.hand_font(true)
		draw_string(font, Vector2(-r, -r * 0.28), "当時の評価", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 10, red)
		draw_string(font, Vector2(-r, r * 0.48), rank, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 26 if rank.length() <= 1 else 20,
			red)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 罫線の紙（横の罫線と、左の赤い余白の線）
class Ruled:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## 紙の余白（PaperStyle の content_margin）の分だけ外側まで引く
	func _draw() -> void:
		var y := ScoutNotebook.RULE_STEP
		while y < size.y + 6.0:
			draw_line(Vector2(-30, y), Vector2(size.x + 10, y), ScoutNotebook.RULE, 1.0)
			y += ScoutNotebook.RULE_STEP
		draw_line(Vector2(-10, -8), Vector2(-10, size.y + 8), ScoutNotebook.MARGIN_RULE, 1.5)


## 手書き風の字（bold：見出し・ハンコ）
static func hand_font(bold := false) -> Font:
	if not _hand_fonts.has(bold):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(HAND_FONT_NAMES)
		f.font_weight = 700 if bold else 400
		f.fallbacks = [UiTheme.font(700 if bold else 500)]
		_hand_fonts[bold] = f
	return _hand_fonts[bold]


static func hand_label(text: String, font_size: int, color := INK, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", hand_font(bold))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## 紙の色の枠（作戦会議の左右の欄もこの見た目にそろえる）
static func paper_style(radius := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PAPER
	s.border_color = PAPER_EDGE
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0.25, 0.14, 0.02, 0.25)
	s.shadow_size = 4
	s.shadow_offset = Vector2(2, 3)
	s.content_margin_left = 34
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func magnet(text: String, kind: String, font_size := 15) -> PanelContainer:
	var colors: Array = ScoutNotes.MAGNET_COLORS.get(kind, ScoutNotes.MAGNET_COLORS["role"])
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = colors[0]
	s.set_corner_radius_all(4)
	s.border_color = Color(colors[1], 0.35)
	s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.22)
	s.shadow_size = 2
	s.shadow_offset = Vector2(1, 2)
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", s)
	p.add_child(hand_label(text, font_size, colors[1], true))
	return p


func _init() -> void:
	add_theme_stylebox_override("panel", paper_style())
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(Ruled.new())
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	_empty_label = hand_label("", 18, INK_SUB)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.visible = false
	root.add_child(_empty_label)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	root.add_child(_scroll)
	_cols = BoxContainer.new()
	_cols.add_theme_constant_override("separation", 22)
	_cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_cols)
	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 6)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cols.add_child(_left)
	_right = VBoxContainer.new()
	_right.add_theme_constant_override("separation", 6)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cols.add_child(_right)
	_build_head()
	_build_sheet()
	_magnets = HFlowContainer.new()
	_magnets.add_theme_constant_override("h_separation", 6)
	_magnets.add_theme_constant_override("v_separation", 4)
	_left.add_child(_magnets)
	_build_clip()
	_comments = VBoxContainer.new()
	_comments.add_theme_constant_override("separation", 2)
	_right.add_child(_comments)
	_build_memo()
	_extra = VBoxContainer.new()
	_extra.add_theme_constant_override("separation", 2)
	_right.add_child(_extra)
	root.add_child(_build_buttons())
	root.add_child(_build_footer())


func _build_head() -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	_left.add_child(head)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	_no_label = hand_label("", 14, INK_SUB)
	_no_label.clip_text = true
	_no_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(_no_label)
	var name_line := HBoxContainer.new()
	name_line.add_theme_constant_override("separation", 4)
	info.add_child(name_line)
	_mark_label = hand_label("", 26, RED, true)
	name_line.add_child(_mark_label)
	_name_button = Button.new()
	_name_button.flat = true
	_name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_button.add_theme_font_override("font", hand_font(true))
	_name_button.add_theme_font_size_override("font_size", 28)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		_name_button.add_theme_stylebox_override(state, sb)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_name_button.add_theme_color_override(state, INK)
	_name_button.tooltip_text = "Ⓐ／クリックで選手詳細"
	_name_button.pressed.connect(func() -> void: detail_requested.emit())
	name_line.add_child(_name_button)
	_profile_label = hand_label("", 15, INK)
	info.add_child(_profile_label)
	_state_label = hand_label("", 15, RED, true)
	_state_label.visible = false
	info.add_child(_state_label)
	_stamp = Stamp.new()
	head.add_child(_stamp)


func _build_sheet() -> void:
	var panel := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.25)
	s.border_color = PAPER_EDGE
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", s)
	_left.add_child(panel)
	_sheet = GridContainer.new()
	_sheet.columns = 3
	_sheet.add_theme_constant_override("h_separation", 4)
	_sheet.add_theme_constant_override("v_separation", 0)
	panel.add_child(_sheet)


func _build_clip() -> void:
	_clip_panel = PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color("F1EFE8")
	s.border_color = Color("B4B2A9")
	s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.15)
	s.shadow_size = 3
	s.shadow_offset = Vector2(2, 2)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 5
	_clip_panel.add_theme_stylebox_override("panel", s)
	_clip_panel.rotation_degrees = 1.2
	_clip_panel.resized.connect(func() -> void: _clip_panel.pivot_offset = _clip_panel.size / 2.0)
	_right.add_child(_clip_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_clip_panel.add_child(box)
	_clip_source = UiTheme.small_label("", 12, Color("5F5E5A"), 500)
	box.add_child(_clip_source)
	_clip_headline = UiTheme.small_label("", 15, Color("2C2C2A"), 800)
	_clip_headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_clip_headline)


func _build_memo() -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	_right.add_child(line)
	line.add_child(hand_label("✎", 20, INK_SUB))
	_memo = LineEdit.new()
	_memo.placeholder_text = "書き込む（1行）"
	_memo.max_length = 40
	_memo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_memo.add_theme_font_override("font", hand_font())
	_memo.add_theme_font_size_override("font_size", 17)
	_memo.add_theme_color_override("font_color", Color("1D3E8A"))
	_memo.add_theme_color_override("font_placeholder_color", Color(INK_SUB, 0.6))
	var under := StyleBoxFlat.new()
	under.bg_color = Color(1, 1, 1, 0.0)
	under.border_color = Color(INK_SUB, 0.5)
	under.border_width_bottom = 1
	under.content_margin_left = 4
	var focus := under.duplicate() as StyleBoxFlat
	focus.border_color = UiTheme.FOCUS
	focus.border_width_bottom = 2
	_memo.add_theme_stylebox_override("normal", under)
	_memo.add_theme_stylebox_override("read_only", under)
	_memo.add_theme_stylebox_override("focus", focus)
	_memo.text_changed.connect(func(t: String) -> void: memo_changed.emit(t))
	line.add_child(_memo)


## めくる・この男でいく・◎○△☆✕（縦長の画面では折り返す）
func _build_buttons() -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	_prev_button = _paper_button("◀ めくる")
	_prev_button.pressed.connect(func() -> void: flip_requested.emit(-1))
	row.add_child(_prev_button)
	_go_button = Button.new()
	_go_button.text = "この男でいく"
	_go_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_go_button.size_flags_stretch_ratio = 1.6
	_go_button.custom_minimum_size = Vector2(190, 44)
	_go_button.add_theme_font_override("font", hand_font(true))
	_go_button.add_theme_font_size_override("font_size", 20)
	UiTheme.style_button(_go_button, RED, Color("FCEBEB"), 8, 3)
	_go_button.add_theme_font_override("font", hand_font(true))
	_go_button.pressed.connect(func() -> void: go_pressed.emit())
	row.add_child(_go_button)
	_next_button = _paper_button("めくる ▶")
	_next_button.pressed.connect(func() -> void: flip_requested.emit(1))
	row.add_child(_next_button)
	_build_marks(row)
	return row


## ◎○△☆✕（「めくる ▶」の右）
func _build_marks(parent: Container) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	for mark: String in DraftBoard.MARKS:
		var b := Button.new()
		b.text = mark
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(38, 44)
		b.add_theme_font_size_override("font_size", 20)
		UiTheme.style_toggle(b, DraftBoard.MARK_COLORS[mark], 8)
		b.tooltip_text = "%s（もう一度押すと外す）" % DraftBoard.MARK_NAMES[mark]
		b.pressed.connect(func() -> void: mark_requested.emit(mark))
		row.add_child(b)
		_mark_buttons[mark] = b


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	_footer = row
	_page_label = hand_label("", 15, INK_SUB)
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_page_label)
	_table_button = _paper_button("表に切り替え")
	_table_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_table_button.custom_minimum_size = Vector2(130, 44)
	_table_button.pressed.connect(func() -> void: table_requested.emit())
	row.add_child(_table_button)
	return row


func _paper_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(88, 44)
	b.add_theme_font_size_override("font_size", 17)
	UiTheme.style_button(b, Color("E9D3AE"), INK, 8, 3)
	b.add_theme_font_override("font", hand_font(true))
	return b


# --- 外から ------------------------------------------------------------------------------

## 横長（見開き：左右のページ）か縦長（1列）か
func set_spread(on: bool) -> void:
	_cols.vertical = not on
	_footer.visible = not on


func go_button() -> Button:
	return _go_button


func memo_edit() -> LineEdit:
	return _memo


## 説得の約束など、ページの右下に足す欄（呼ぶたびに空にする）
func extra_box() -> VBoxContainer:
	return _extra


func clear_extra() -> void:
	for child in _extra.get_children():
		_extra.remove_child(child)
		child.queue_free()


## 「この男でいく」の文言と押せるか
func set_action(text: String, enabled: bool) -> void:
	_go_button.text = text
	_go_button.disabled = not enabled


func set_table_button_visible(on: bool) -> void:
	_table_button.visible = on


## 候補がいないとき
func show_empty(text: String) -> void:
	_empty_label.text = text
	_empty_label.visible = true
	_scroll.visible = false
	_stamp.rank = ""
	_stamp.queue_redraw()
	for b: Button in [_prev_button, _next_button, _go_button]:
		b.disabled = true
	for mark: String in _mark_buttons:
		(_mark_buttons[mark] as Button).disabled = true
	_page_label.text = ""


## 1ページ書く。index・total はめくる順の何枚目か
func show_page(d: Draft, c: Dictionary, index: int, total: int) -> void:
	_empty_label.visible = false
	_scroll.visible = true
	var key := DraftBoard.key_of(c)
	var board := GameState.draft_board
	_no_label.text = "No.%02d／%d　%s（%s）" % [index + 1, total, c["school"], c["career"]]
	var mark := board.mark_of(d.year, key)
	_mark_label.text = mark
	_mark_label.visible = not mark.is_empty()
	if not mark.is_empty():
		_mark_label.add_theme_color_override("font_color", DraftBoard.MARK_COLORS.get(mark, RED))
	_name_button.text = str(c["name"])
	_profile_label.text = ScoutNotes.profile_line(c)
	var state := ""
	if not str(c["picked_by"]).is_empty():
		state = "指名済み：%s %s" % [GameData.short_name(c["picked_by"]), c["pick_label"]]
	elif d.bids.get(GameState.team, "") == c["id"]:
		state = "1位で入札中"
	_state_label.text = state
	_state_label.visible = not state.is_empty()
	_stamp.rank = _stamp_text(str(c["hyouka_rank"]))
	_stamp.queue_redraw()
	_render_sheet(d, c)
	_render_magnets(d, c)
	_render_clip(d, c)
	_render_comments(d, c)
	if _memo_key != "%d|%s" % [d.year, key] or not _memo.has_focus():
		_memo_key = "%d|%s" % [d.year, key]
		var memo := board.memo_of(d.year, key)
		if _memo.text != memo:
			_memo.text = memo
	for m: String in _mark_buttons:
		var b: Button = _mark_buttons[m]
		b.disabled = false
		b.set_pressed_no_signal(m == mark)
	_prev_button.disabled = total <= 1
	_next_button.disabled = total <= 1
	_page_label.text = "%d / %d 枚" % [index + 1, total]


## 当時の評価のハンコの字（S は「特A」、ほかはそのまま）
static func _stamp_text(rank: String) -> String:
	return "特A" if rank == "S" else rank


func _render_sheet(d: Draft, c: Dictionary) -> void:
	for child in _sheet.get_children():
		_sheet.remove_child(child)
		child.queue_free()
	for cell: Dictionary in ScoutNotes.sheet(d, c):
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l := UiTheme.small_label(cell["label"], 12, INK_SUB, 700)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
		var v := hand_label(cell["text"], 25, ScoutNotes.TIER_COLORS[cell["tier"]], true)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if int(cell["value"]) >= 0 and cell["key"] != "velocity":
			v.tooltip_text = "%s %d" % [cell["label"], int(cell["value"])]
			v.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(v)
		_sheet.add_child(box)


func _render_magnets(d: Draft, c: Dictionary) -> void:
	for child in _magnets.get_children():
		_magnets.remove_child(child)
		child.queue_free()
	for t: Dictionary in ScoutNotes.traits(d, c):
		_magnets.add_child(magnet(t["text"], t["kind"]))


func _render_clip(d: Draft, c: Dictionary) -> void:
	var clip := ScoutNotes.clipping(c, d.year)
	_clip_panel.visible = not clip.is_empty()
	if clip.is_empty():
		return
	_clip_source.text = "%s %s" % [clip["source"], clip["date"]]
	_clip_headline.text = clip["headline"]


func _render_comments(d: Draft, c: Dictionary) -> void:
	for child in _comments.get_children():
		_comments.remove_child(child)
		child.queue_free()
	_comments.add_child(UiTheme.small_label("スカウトの寸評", 12, INK_SUB, 700))
	for line: Dictionary in ScoutNotes.comments(d, c):
		var l := hand_label("・" + str(line["text"]), 16, RED if line["rumor"] else INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_comments.add_child(l)
