class_name PickBoard
extends PanelContainer
## ドラフト会場の指名ボード（docs/AUTORUN.md 作業51。参考：docs/references/draft_notebook_mock.html の右）。
## 12球団の行に、指名した選手がマグネットの札（「1 山田」）で埋まっていく。自球団の行は金色の字で、まだ指名する枠は点線の札。
## いま指名している球団の行に印。下に、手帳で◎を付けた残りの候補（寸評のひとこと）と「手帳を開いて N位を選ぶ」。
## 札を押すと candidate_pressed（その候補の手帳のページを開く）

signal candidate_pressed(id: String)
signal notebook_requested

const BOARD := Color("2C2C2A")
const CHALK := Color("F1EFE8")
const LINE := Color("5F5E5A")
const GOLD := Color("FAC775")
const TEAM_WIDTH := 76
## ◎の残りの候補を出す数
const FAVORITE_COUNT := 2

var _title: Label
var _sub: Label
var _rows: VBoxContainer
var _rows_scroll: ScrollContainer
var _favs: VBoxContainer
## 横長（手帳と並べる）なら「手帳を開いて」を出さない（手帳がすぐ横にある）
var _compact := false
var _favs_title: Label
var _open_button: Button


## 点線の札（自球団のまだ埋まっていない枠）
class DashedSlot:
	extends Label

	func _init(text_value: String) -> void:
		text = text_value
		add_theme_font_override("font", ScoutNotebook.hand_font(true))
		add_theme_font_size_override("font_size", 15)
		add_theme_color_override("font_color", PickBoard.GOLD)
		custom_minimum_size = Vector2(54, 24)
		horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	func _draw() -> void:
		var r := Rect2(Vector2(1, 1), size - Vector2(2, 2))
		var dash := 5.0
		for side: int in 4:
			var a: Vector2 = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)][side]
			var b: Vector2 = [Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position][side]
			var length := a.distance_to(b)
			var t := 0.0
			while t < length:
				draw_line(a.lerp(b, t / length), a.lerp(b, minf(t + dash, length) / length), PickBoard.GOLD, 1.5)
				t += dash * 2.0


func _init() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = BOARD
	s.set_corner_radius_all(10)
	s.border_color = Color("8a8478")
	s.set_border_width_all(3)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	add_theme_stylebox_override("panel", s)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	_title = ScoutNotebook.hand_label("", 20, CHALK, true)
	head.add_child(_title)
	_sub = ScoutNotebook.hand_label("", 16, CHALK)
	_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sub.clip_text = true
	_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_sub)
	_rows_scroll = ScrollContainer.new()
	_rows_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_rows_scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_scroll.add_child(_rows)
	_favs_title = ScoutNotebook.hand_label("手帳に◎を付けた残りの候補", 15, CHALK, true)
	box.add_child(_favs_title)
	_favs = VBoxContainer.new()
	_favs.add_theme_constant_override("separation", 3)
	box.add_child(_favs)
	_open_button = Button.new()
	_open_button.custom_minimum_size = Vector2(0, 44)
	_open_button.add_theme_font_size_override("font_size", 18)
	UiTheme.style_button(_open_button, ScoutNotebook.RED, Color("FCEBEB"), 8, 3)
	_open_button.add_theme_font_override("font", ScoutNotebook.hand_font(true))
	_open_button.pressed.connect(func() -> void: notebook_requested.emit())
	box.add_child(_open_button)


## 縦長の画面（ボードだけを出す）では行の欄を広げる
func set_rows_min_height(h: float) -> void:
	_rows_scroll.custom_minimum_size = Vector2(0, h)


func set_compact(on: bool) -> void:
	_compact = on


func open_button() -> Button:
	return _open_button


func show_board(d: Draft, user_team: String, pick_word: String) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for child in _favs.get_children():
		_favs.remove_child(child)
		child.queue_free()
	if d == null:
		_title.text = "指名ボード"
		_sub.text = ""
		_favs_title.visible = false
		_open_button.visible = false
		return
	_title.text = "指名ボード %d" % d.year
	_sub.text = _sub_text(d, user_team)
	var current := d.current_team()
	var teams: Array[String] = []
	teams.assign(d.order if not d.order.is_empty() else d.teams)
	for t: String in teams:
		_rows.add_child(_team_row(d, t, t == user_team, t == current, pick_word))
	_render_favorites(d)
	_open_button.visible = d.stage != Draft.Stage.DONE and not _compact
	_open_button.text = "手帳を開いて%sを選ぶ" % pick_word
	_open_button.disabled = not (d.is_user_turn() or (d.stage == Draft.Stage.FIRST and d.first_pick_of(user_team).is_empty()))


func _sub_text(d: Draft, user_team: String) -> String:
	match d.stage:
		Draft.Stage.FIRST:
			return "1位入札（%d回目）" % d.wave if d.first_pick_of(user_team).is_empty() else "1位の入札・抽選"
		Draft.Stage.WAIVER, Draft.Stage.IKUSEI:
			var head := ("育成 第%d巡" if d.stage == Draft.Stage.IKUSEI else "第%d巡") % d.round
			if d.is_user_turn():
				return head + "・自球団の番"
			var n := d.teams_before_user()
			if n > 0:
				return head + "・あと%d球団" % n
			return head + "・%s指名中" % GameData.short_name(d.current_team())
	return "全球団の指名が終わりました"


func _team_row(d: Draft, team: String, mine: bool, current: bool, pick_word: String) -> Control:
	var panel := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.06) if current else Color(0, 0, 0, 0)
	s.border_color = LINE
	s.border_width_bottom = 1
	if current:
		s.border_color = GOLD
		s.set_border_width_all(1)
		s.set_corner_radius_all(4)
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	s.content_margin_left = 2
	panel.add_theme_stylebox_override("panel", s)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var team_label := ScoutNotebook.hand_label(("▶" if current else "") + GameData.short_name(team), 15,
		GOLD if mine else CHALK, mine)
	team_label.custom_minimum_size = Vector2(TEAM_WIDTH, 0)
	team_label.clip_text = true
	team_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	team_label.tooltip_text = team
	team_label.mouse_filter = Control.MOUSE_FILTER_PASS
	var colors := GameData.team_colors(team)
	var swatch := ColorRect.new()
	swatch.color = colors[0]
	swatch.custom_minimum_size = Vector2(5, 22)
	row.add_child(swatch)
	row.add_child(team_label)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 3)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(flow)
	for rec: Dictionary in d.picks_of(team):
		flow.add_child(_pick_magnet(d, rec))
	if mine and d.stage != Draft.Stage.DONE:
		var slot := "1 ？"
		if d.stage == Draft.Stage.FIRST:
			slot = "1 入札中" if d.bids.has(team) else "1 ？"
			if not d.first_pick_of(team).is_empty():
				slot = ""
		elif not d.is_user_turn() and d.teams_before_user() < 0:
			slot = ""
		else:
			slot = pick_word.replace("位", "") + " ？"
		if not slot.is_empty():
			flow.add_child(DashedSlot.new(slot))
	return panel


func _pick_magnet(d: Draft, rec: Dictionary) -> Control:
	var c: Dictionary = d.by_id.get(rec["id"], {})
	var pos: String = str(c.get("pos", ""))
	var base := NameTag.pos_color(pos)
	var label: String = str(rec["label"]).replace("位", "").replace("育成", "育")
	var b := Button.new()
	b.text = "%s %s" % [label, NameTag.family_name(str(rec.get("name", c.get("name", ""))))]
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", ScoutNotebook.hand_font(true))
	b.add_theme_font_size_override("font_size", 14)
	var ink := base.darkened(0.55)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, ink)
	var s := StyleBoxFlat.new()
	s.bg_color = base.lerp(Color.WHITE, 0.72) if not bool(rec["ikusei"]) else base.lerp(Color.WHITE, 0.88)
	s.set_corner_radius_all(4)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 2
	s.shadow_offset = Vector2(1, 2)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	var hover := s.duplicate() as StyleBoxFlat
	hover.bg_color = s.bg_color.lightened(0.3)
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.tooltip_text = "%s %s：%s（%s・%s）" % [GameData.short_name(rec["team"]), rec["label"], c.get("name", ""),
		pos, c.get("school", "")]
	var id: String = rec["id"]
	b.pressed.connect(func() -> void: candidate_pressed.emit(id))
	return b


func _render_favorites(d: Draft) -> void:
	var by_key := {}
	for c: Dictionary in d.candidates:
		by_key[DraftBoard.key_of(c)] = c
	var shown := 0
	for key: Variant in GameState.draft_board.favorite_list(d.year):
		var c: Dictionary = by_key.get(str(key), {})
		if c.is_empty() or not str(c["picked_by"]).is_empty():
			continue
		_favs.add_child(_favorite_card(d, c))
		shown += 1
		if shown >= FAVORITE_COUNT:
			break
	_favs_title.visible = true
	if shown == 0:
		var hint := ScoutNotebook.hand_label("（手帳で◎を付けると、ここに残りが並びます）", 14, Color(CHALK, 0.7))
		hint.clip_text = true
		hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_favs.add_child(hint)


## ◎の残りの候補の札（紙の帯1行：名前・守備位置と区分・寸評のひとこと）
func _favorite_card(d: Draft, c: Dictionary) -> Control:
	var b := Button.new()
	var one := ScoutNotes.one_liner(d, c)
	b.text = "◎ %s（%s・%s）%s" % [c["name"], DraftView.POS_SHORT.get(c["pos"], "-"),
		str(c["career"]).replace("生", ""), one]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_override("font", ScoutNotebook.hand_font(true))
	b.add_theme_font_size_override("font_size", 14)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, ScoutNotebook.INK)
	var s := StyleBoxFlat.new()
	s.bg_color = ScoutNotebook.PAPER
	s.set_corner_radius_all(6)
	s.content_margin_left = 8
	s.content_margin_right = 8
	var hover := s.duplicate() as StyleBoxFlat
	hover.bg_color = ScoutNotebook.PAPER.lightened(0.4)
	var focus := s.duplicate() as StyleBoxFlat
	focus.draw_center = false
	focus.border_color = UiTheme.FOCUS
	focus.set_border_width_all(3)
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", focus)
	b.tooltip_text = one
	var id: String = c["id"]
	b.pressed.connect(func() -> void: candidate_pressed.emit(id))
	return b
