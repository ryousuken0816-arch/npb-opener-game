class_name AwardsView
extends VBoxContainer
## 表彰の画面（オフの「シーズン終了・表彰」）。仕組みは Awards（GameState.awards_history）。
##
## 上にタブ（主要な賞／ベストナイン／ゴールデングラブ／打撃タイトル／投手タイトル。LB/RB＝Q/E でも）、
## その下にセ・リーグとパ・リーグを左右に並べ、賞・名前札・球団・成績の行。自球団の受賞は金色の帯と★で目立たせる。
## 名前札は Ⓐ／クリックで選手詳細（そのタブの受賞者を前後で見られる）。Ⓑ はハブへ戻る。

signal message_changed(text: String)

const TABS := [["main", "主要な賞"], ["best_nine", "ベストナイン"], ["gold_glove", "ゴールデングラブ"],
	["bat_titles", "打撃タイトル"], ["pit_titles", "投手タイトル"]]
## 行の高さ。パ・リーグのベストナイン（10人）が1280x720 のサブ画面にスクロールなしで収まる高さ
const ROW_HEIGHT := 32
const MINE_COLOR := Color("ffd54f")
const LEAGUE_COLORS := {"C": Color("1e88e5"), "P": Color("43a047")}

var _palette: UiTheme.Palette
var _tab := "main"
var _year := 0
var _tab_buttons := {}
var _banner: Label
var _columns: HBoxContainer
var _bottom: VBoxContainer
var _ids: Array = []


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiTheme.small_label("◀ LB", 18, UiTheme.TEXT, 800))
	for t: Array in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(160, 40)
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_font_override("font", UiTheme.font(800))
		UiTheme.style_toggle(b, p.ink)
		var key: String = t[0]
		b.pressed.connect(func() -> void: set_tab(key))
		row.add_child(b)
		_tab_buttons[key] = b
	row.add_child(UiTheme.small_label("RB ▶", 18, UiTheme.TEXT, 800))
	add_child(row)
	# 自球団の受賞の数（タブの行の右）
	_banner = Label.new()
	_banner.clip_text = true
	_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.heading(_banner, 20, p.ink, Color.WHITE, 6)
	row.add_child(_banner)
	# 賞の行は縦のスクロールの中へ（記録室の「表彰の歴代」に入れたときは高さが足りないことがある。作業11と同じ考え）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 16)
	body.add_child(_columns)
	_bottom = VBoxContainer.new()
	_bottom.add_theme_constant_override("separation", 4)
	body.add_child(_bottom)


# --- 外から ------------------------------------------------------------------------------

func open() -> void:
	_year = _latest_year()
	_tab = "main"
	refresh()
	focus_first()


## 年を指定して表示する（記録室の「表彰の歴代」）。タブはそのまま
func open_year(y: int) -> void:
	_year = y
	refresh()


func back() -> bool:
	return false


func switch_tab(delta: int) -> void:
	var i := 0
	for j in TABS.size():
		if TABS[j][0] == _tab:
			i = j
	set_tab(TABS[posmod(i + delta, TABS.size())][0])


func set_tab(key: String) -> void:
	_tab = key
	refresh()
	focus_first()


## 表示している表彰の年（テスト用。無ければ 0）
func shown_year() -> int:
	return _year


func focus_first() -> void:
	for child in _ids_tags():
		if UiInput.grab(child):
			return
	UiInput.grab(_tab_buttons[_tab])


func refresh() -> void:
	for key: String in _tab_buttons:
		_tab_buttons[key].set_pressed_no_signal(key == _tab)
	for c in _columns.get_children() + _bottom.get_children():
		c.queue_free()
		c.get_parent().remove_child(c)
	_ids = []
	var res: Dictionary = GameState.awards_of(_year)
	if res.is_empty():
		_banner.text = "表彰はシーズン終了後に発表されます"
		message_changed.emit(_banner.text)
		return
	var mine := _count_mine(res)
	_banner.text = "★自球団の受賞 %d" % mine if mine > 0 else "自球団の受賞なし"
	for lg: String in ["C", "P"]:
		_columns.add_child(_league_column(lg, res["leagues"][lg]))
	if _tab == "main":
		_bottom.add_child(_section_label("両リーグ", _palette.main))
		_bottom.add_child(_row("沢村賞", res.get("sawamura")))
	message_changed.emit("%d年の表彰：%s。名前札をⒶ／クリックで選手詳細、LB/RB で賞の種類を切り替えます。" % [
		_year, _tab_name()])


# --- 内部 ----------------------------------------------------------------------------

func _latest_year() -> int:
	var best := 0
	for key: String in GameState.awards_history:
		best = maxi(best, int(key))
	return best


func _tab_name() -> String:
	for t: Array in TABS:
		if t[0] == _tab:
			return t[1]
	return ""


func _league_column(lg: String, a: Dictionary) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.add_child(_section_label(GameData.LEAGUE_NAMES.get(lg, lg), LEAGUE_COLORS[lg]))
	match _tab:
		"main":
			col.add_child(_row("MVP", a.get("mvp")))
			col.add_child(_row("新人王", a.get("rookie")))
		"best_nine", "gold_glove":
			for e: Dictionary in a.get(_tab, []):
				col.add_child(_row(Awards.pos_label(e.get("pos", "")), e))
		"bat_titles", "pit_titles":
			var kind := "b" if _tab == "bat_titles" else "p"
			for t: Dictionary in a.get("titles", []):
				if t["kind"] != kind:
					continue
				var winners: Array = t.get("winners", [])
				if winners.is_empty():
					col.add_child(_row(t["name"], null))
				for i in winners.size():
					var e: Dictionary = winners[i].duplicate()
					e["text"] = t["value_text"] + ("（同数）" if winners.size() > 1 else "")
					col.add_child(_row(t["name"] if i == 0 else "", e))
	return col


func _section_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	UiTheme.heading(label, 22, color, Color.WHITE, 6)
	return label


## 1行：賞の名前・名前札・球団・成績。自球団は金色の帯と★
func _row(award: String, e: Variant) -> PanelContainer:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var is_mine: bool = e is Dictionary and e.get("team", "") == GameState.team
	var style := UiTheme.box(Color(MINE_COLOR, 0.85) if is_mine else Color(1, 1, 1, 0.55), 8)
	style.content_margin_left = 6
	style.content_margin_right = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var name_label := UiTheme.small_label(("★" if is_mine else "") + award, 17, UiTheme.TEXT, 800)
	# 位置だけのタブ（ベストナイン・GG）は狭く、賞の名前のタブは広く
	name_label.custom_minimum_size = Vector2(66 if _tab in ["best_nine", "gold_glove"] else 118, 0)
	name_label.clip_text = true
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)
	if not (e is Dictionary):
		row.add_child(UiTheme.small_label("該当者なし", 18, UiTheme.TEXT_SUB, 700))
		return panel
	var id: String = e["id"]
	_ids.append(id)
	var tag := NameTag.new()
	tag.custom_minimum_size = Vector2(140, 30)
	tag.font_size = 17
	var p := GameData.player(id)
	if p.is_empty():
		tag.setup_plain(NameTag.family_name(str(e.get("name", ""))), NameTag.COLOR_UNKNOWN)
	else:
		tag.setup_player(p, NameTag.family_name(str(e.get("name", ""))))
	tag.tooltip_text = "%s（Ⓐ／クリックで選手詳細）" % e.get("name", "")
	var ids := _ids
	tag.pressed.connect(func() -> void: PlayerDetail.open(tag, id, ids))
	tag.disabled = p.is_empty()
	row.add_child(tag)
	var team_label := UiTheme.small_label(GameData.short_name(e.get("team", "")), 16, UiTheme.TEXT, 800)
	team_label.custom_minimum_size = Vector2(96, 0)
	team_label.clip_text = true
	team_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(team_label)
	var text_label := UiTheme.small_label(str(e.get("text", "")), 16, UiTheme.TEXT, 700)
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.clip_text = true
	text_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_label.tooltip_text = text_label.text
	text_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(text_label)
	return panel


func _ids_tags() -> Array[Control]:
	var result: Array[Control] = []
	for c in UiInput.focusables(self):
		if c is NameTag:
			result.append(c)
	return result


## 自球団の受賞の数（タイトルは人数分）
func _count_mine(res: Dictionary) -> int:
	var n := 0
	var mine := func(e: Variant) -> int:
		return 1 if e is Dictionary and e.get("team", "") == GameState.team else 0
	for lg: String in res["leagues"]:
		var a: Dictionary = res["leagues"][lg]
		n += mine.call(a.get("mvp")) + mine.call(a.get("rookie"))
		for key: String in ["best_nine", "gold_glove"]:
			for e: Variant in a.get(key, []):
				n += mine.call(e)
		for t: Dictionary in a.get("titles", []):
			for e: Variant in t.get("winners", []):
				n += mine.call(e)
	n += mine.call(res.get("sawamura"))
	return n
