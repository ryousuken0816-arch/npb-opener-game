class_name FaView
extends VBoxContainer
## オフの「FA・トレード・ポスティング」の画面（ハブの可変ボタンから開く。docs/references/trade_pawapuro.webp が参考）。
##
## 上に交渉の枠（左＝選んだ選手、中央＝「提示する／引き留める」と成功率の★、右＝自球団の提示：年俸・年数）、
## 下にタブ（FA宣言／メジャー移籍／結果）と選手の札の一覧。仕組みは FreeAgency（GameState.fa()）。
## - FA宣言：宣言した選手に年俸・年数を提示する（自球団の選手なら引き留め）。「締め切る」で移籍先が決まる
## - メジャー移籍：史実でこのオフにメジャーへ行く選手。自球団の選手は1回だけ引き留めを試せる（成功はまれ）
## - 結果：締め切ったあとの移籍・残留の一覧（締め切る前は自球団の提示の一覧）
## 操作：札をⒶ／クリックで選び、同じ札をもう一度Ⓐ／クリック（または右クリック）で選手詳細。十字キーで
## 上の ◀▶（年俸・年数）と「提示する」へ。LB/RB（Q/E）でタブ、Ⓑはまず選択の取り消し→ハブへ戻る。

signal message_changed(text: String)

const TABS := [["fa", "FA宣言", Color("e53935")], ["mlb", "メジャー移籍", Color("1e63c8")],
	["result", "結果", Color("2e9b48")]]
const TAG_SIZE := Vector2(132, 34)
## 一覧の1枚分の幅（3列で画面に収まる幅）
const TILE_WIDTH := 372
const DEAL_HEIGHT := 250
const POS_SHORT := {
	"捕手": "捕", "一塁手": "一", "二塁手": "二", "三塁手": "三", "遊撃手": "遊", "内野手": "内",
	"外野手": "外", "左翼手": "外", "中堅手": "外", "右翼手": "外", "指名打者": "指", "投手": "投",
}
const STAR_WORDS := ["", "かなり低い", "低い", "五分五分", "高い", "かなり高い"]

var _palette: UiTheme.Palette
var _tab := "fa"
var _selected := ""
var _amount := 0
var _years := 2
var _message := ""
var _shown_key := ""

var _tab_buttons := {}
var _count_label: Label
var _grid: GridContainer
var _scroll: ScrollContainer
var _left_box: VBoxContainer
var _center_box: VBoxContainer
var _right_box: VBoxContainer
var _action_button: Button
var _odds_label: Label
var _stars_label: Label
var _amount_label: Label
var _years_label: Label
var _range_label: Label
var _offer_buttons: Array[Button] = []
var _cancel_button: Button
var _close_button: Button
var _status_label: Label
var _right_title: Label
## 一覧の札の並び（選手詳細の十字キーで送る順）
var _ids: Array[String] = []
var _tags := {}


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	add_theme_constant_override("separation", 8)
	add_child(_build_deal())
	add_child(_build_tabs())
	var list_panel := PanelContainer.new()
	var list_style := UiTheme.card(Color("2f7fd8"), 10, 4, 0.97)
	list_style.content_margin_left = 14
	list_style.content_margin_right = 14
	list_style.content_margin_top = 10
	list_style.content_margin_bottom = 10
	list_panel.add_theme_stylebox_override("panel", list_style)
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(list_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	list_panel.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 8)
	_scroll.add_child(_grid)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	add_child(bottom)
	_status_label = UiTheme.small_label("", 17, UiTheme.TEXT, 700)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_status_label)
	_close_button = Button.new()
	_close_button.text = "締め切って結果を見る"
	_close_button.custom_minimum_size = Vector2(250, 46)
	UiTheme.style_button(_close_button, Color("2e9b48"))
	_close_button.pressed.connect(_on_close_pressed)
	bottom.add_child(_close_button)


# --- 外から ------------------------------------------------------------------------------

func open() -> void:
	_selected = ""
	_message = ""
	_shown_key = ""
	var f := GameState.fa()
	_tab = "result" if f != null and f.resolved else "fa"
	refresh()
	focus_first()


## 戻る：選択中なら取り消す（true）。何も選んでいなければ false（ハブへ戻る）
func back() -> bool:
	if _selected.is_empty():
		return false
	_selected = ""
	_message = ""
	_shown_key = ""
	refresh()
	focus_first()
	return true


func switch_tab(delta: int) -> void:
	var keys: Array = []
	for t: Array in TABS:
		keys.append(t[0])
	_show_tab(keys[posmod(keys.find(_tab) + delta, keys.size())])


func focus_first() -> void:
	if not _ids.is_empty() and _tags.has(_ids[0]):
		var target: Control = _tags.get(_selected, _tags[_ids[0]])
		target.grab_focus()
	else:
		UiInput.grab(_tab_buttons[_tab])


func refresh() -> void:
	var f := GameState.fa()
	var key := "%s|%s|%d|%d|%d|%d|%s|%d" % [_tab, _selected, _amount, _years, GameState.roster_version,
		f.user_bids.size() if f != null else -1, str(f.resolved) if f != null else "", GameState.year]
	if key == _shown_key:
		return
	_shown_key = key
	var focus := UiInput.focus_index(self)
	var focused_id := ""
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for id: String in _tags:
		if _tags[id] == owner:
			focused_id = id
	_render_list(f)
	_render_deal(f)
	_render_tabs(f)
	_render_status(f)
	if not focused_id.is_empty() and _tags.has(focused_id):
		_tags[focused_id].grab_focus()
	elif focus >= 0:
		UiInput.focus_nth(self, focus)


## いま選んでいる選手（テスト用）
func selected_id() -> String:
	return _selected


## 一覧の選手ID（テスト用）
func list_ids() -> Array[String]:
	return _ids


func select_player(id: String) -> void:
	_on_tag_pressed(id)


# --- 交渉の枠 ------------------------------------------------------------------------------

func _build_deal() -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.gloss(Color("eadfc6"), 12, 4, 0, Color("a88a5c"))
	style.gloss = 0.0
	style.gradient = 0.08
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(0, DEAL_HEIGHT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	_left_box = VBoxContainer.new()
	_left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_box.size_flags_stretch_ratio = 1.15
	_left_box.add_theme_constant_override("separation", 6)
	row.add_child(_left_box)

	_center_box = VBoxContainer.new()
	_center_box.custom_minimum_size = Vector2(250, 0)
	_center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_center_box.add_theme_constant_override("separation", 6)
	row.add_child(_center_box)
	_action_button = Button.new()
	_action_button.text = "提示する"
	_action_button.custom_minimum_size = Vector2(240, 110)
	_action_button.add_theme_font_override("font", UiTheme.font(800))
	_action_button.add_theme_font_size_override("font_size", 32)
	UiTheme.style_button(_action_button, Color("e8413c"), Color.WHITE, 26, 8)
	_action_button.pressed.connect(_on_action_pressed)
	_center_box.add_child(_action_button)
	_odds_label = UiTheme.small_label("", 20, UiTheme.TEXT, 800)
	_odds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_box.add_child(_odds_label)
	_stars_label = Label.new()
	_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(_stars_label, 34, Color("e53935"), Color.WHITE, 6)
	_center_box.add_child(_stars_label)

	_right_box = VBoxContainer.new()
	_right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_box.add_theme_constant_override("separation", 8)
	row.add_child(_right_box)
	_right_title = Label.new()
	_right_box.add_child(_band(_right_title, GameState.team, "%sの提示" % GameData.short_name(GameState.team)))
	_amount_label = Label.new()
	_right_box.add_child(_stepper("年俸", _amount_label, _step_amount, 340))
	_years_label = Label.new()
	_right_box.add_child(_stepper("年数", _years_label, _step_years, 140))
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	_right_box.add_child(bottom)
	_range_label = UiTheme.small_label("", 14)
	_range_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_range_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_range_label)
	_cancel_button = Button.new()
	_cancel_button.text = "提示を取り消す"
	_cancel_button.custom_minimum_size = Vector2(150, 38)
	UiTheme.style_button(_cancel_button, Color("8a9199"), Color.WHITE, 8, 4)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	bottom.add_child(_cancel_button)
	return panel


## 球団カラーの見出しの帯（参考画像の「広島東洋カープ」の帯）
func _band(label: Label, team: String, text: String) -> PanelContainer:
	var band := PanelContainer.new()
	var colors := GameData.team_colors(team)
	var style := UiTheme.gloss(colors[0], 6, 2, 2)
	style.content_margin_top = 2
	style.content_margin_bottom = 4
	band.add_theme_stylebox_override("panel", style)
	label.text = text
	var ink := UiTheme.text_on(colors[0])
	UiTheme.heading(label, 22, ink, UiTheme.outline_for(ink, colors[0]), 6, false)
	band.add_child(label)
	band.set_meta("team", team)
	return band


func _stepper(title: String, value_label: Label, on_step: Callable, width: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var head := UiTheme.small_label(title, 18, UiTheme.TEXT, 800)
	head.custom_minimum_size = Vector2(52, 0)
	row.add_child(head)
	var minus := Button.new()
	minus.text = "◀"
	minus.custom_minimum_size = Vector2(52, 46)
	UiTheme.style_button(minus, Color("ff8a3d"), Color.WHITE, 8, 5)
	minus.pressed.connect(func() -> void: on_step.call(-1))
	row.add_child(minus)
	var bar := PanelContainer.new()
	var style := UiTheme.gloss(Color("ffd84d"), 8, 3, 3, Color("b8860b"))
	bar.add_theme_stylebox_override("panel", style)
	bar.custom_minimum_size = Vector2(width, 46)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(value_label, 26, UiTheme.TEXT, Color.WHITE, 6, false)
	bar.add_child(value_label)
	row.add_child(bar)
	var plus := Button.new()
	plus.text = "▶"
	plus.custom_minimum_size = Vector2(52, 46)
	UiTheme.style_button(plus, Color("ff8a3d"), Color.WHITE, 8, 5)
	plus.pressed.connect(func() -> void: on_step.call(1))
	row.add_child(plus)
	_offer_buttons.append(minus)
	_offer_buttons.append(plus)
	return row


func _render_deal(f: FreeAgency) -> void:
	for c in _left_box.get_children():
		_left_box.remove_child(c)
		c.queue_free()
	var id := _selected
	if f == null or id.is_empty() or GameData.player(id).is_empty():
		_left_box.add_child(_band(Label.new(), GameState.team, "選手を選んでください"))
		var hint := UiTheme.small_label(_hint_text(f), 17, UiTheme.TEXT, 700)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_left_box.add_child(hint)
		_set_offer_enabled(false, "提示する")
		_odds_label.text = ""
		_stars_label.text = ""
		_amount_label.text = "-"
		_years_label.text = "-"
		_range_label.text = ""
		_cancel_button.visible = false
		return
	var p := GameData.player(id)
	var from := _from_team(f, id)
	_left_box.add_child(_band(Label.new(), from, from))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var tag := NameTag.new()
	tag.custom_minimum_size = Vector2(190, 44)
	tag.font_size = 24
	tag.setup_player(p, NameTag.family_name(str(p.get("name", ""))))
	tag.tooltip_text = "Ⓐ／クリックで選手詳細"
	tag.pressed.connect(func() -> void: PlayerDetail.open(tag, id, _ids))
	line.add_child(tag)
	var pos_label := Label.new()
	pos_label.text = "%s %d歳" % [POS_SHORT.get(p.get("primary_pos"), "-"),
		FreeAgency.age_of(p, GameState.year)]
	UiTheme.heading(pos_label, 26, UiTheme.TEXT, Color.WHITE, 6)
	line.add_child(pos_label)
	_left_box.add_child(line)
	_left_box.add_child(UiTheme.small_label(str(p.get("name", "")) + "　" + _ability_text(p), 16, UiTheme.TEXT, 700))
	var league := GameState.league
	var lines: Array[String] = []
	lines.append("今季の年俸 %s　在籍%d年目" % [Salary.text(league.salary_of(id)),
		league.years_in_npb(id, GameState.year)])
	if f.info.has(id):
		lines.append("希望額（目安） %s" % Salary.text(f.info[id]["asking"]))
	elif f.mlb_info.has(id):
		lines.append("引き留めの目安 %s〜（%s）" % [Salary.text(f.mlb_info[id]["asking"]), f.mlb_info[id]["route"]])
	lines.append(_state_text(f, id))
	var info := UiTheme.small_label("\n".join(lines), 16, UiTheme.TEXT_SUB, 700)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_box.add_child(info)
	_render_offer(f, id)


func _render_offer(f: FreeAgency, id: String) -> void:
	var r: Array = f.bid_range(id) if (f.info.has(id) or f.mlb_info.has(id)) else [0, 0]
	_amount_label.text = Salary.text(_amount) if _amount > 0 else "-"
	_years_label.text = "%d年" % _years
	_range_label.text = "提示できる額 %s〜%s" % [Salary.text(r[0]), Salary.text(r[1])] if r[1] > 0 else ""
	_cancel_button.visible = false
	var own := _from_team(f, id) == GameState.team
	if f.mlb_info.has(id):
		var m: Dictionary = f.mlb_info[id]
		var can: bool = own and m["status"] == "leave"
		_set_offer_enabled(can, "引き留める")
		var chance: float = f.keep_chance(id, _amount, _years) if can else float(m["chance"])
		if not own:
			_odds_label.text = "他球団の選手"
			_stars_label.text = ""
		else:
			# 引き留めは最大でも20%なので★は3つまで（成功はまれ）
			_odds_label.text = "成功率：%d%%" % roundi(chance * 100.0)
			_stars_label.text = _stars(clampi(1 + int(chance * 10.0 + 0.001), 1, 3))
		return
	if not f.info.has(id):
		_set_offer_enabled(false, "提示する")
		_odds_label.text = ""
		_stars_label.text = ""
		return
	_set_offer_enabled(not f.resolved, "引き留める" if own else "提示する")
	_cancel_button.visible = f.user_bids.has(id) and not f.resolved
	if f.resolved:
		_odds_label.text = "締め切りました"
		_stars_label.text = ""
		return
	var s := f.stars(GameState.league, id, _amount, _years)
	_odds_label.text = "成功率：%s" % STAR_WORDS[s]
	_stars_label.text = _stars(s)


func _set_offer_enabled(enabled: bool, text: String) -> void:
	_action_button.text = text
	_action_button.disabled = not enabled
	for b in _offer_buttons:
		b.disabled = not enabled
	_right_box.modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.55)


static func _stars(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(5 - n)


func _hint_text(f: FreeAgency) -> String:
	if f == null:
		return "FA・ポスティングの交渉は、オフの「FA・トレード・ポスティング」の段階で行います。"
	match _tab:
		"fa":
			return "FA宣言した選手に年俸と年数を提示します。自球団の選手への提示は引き留めです。\n" \
				+ "下の一覧から選手を選んでください（もう一度Ⓐで選手詳細）。"
		"mlb":
			return "史実でこのオフにメジャーへ移籍する選手です。自球団の選手は1回だけ引き留めを試せます" \
				+ "（大きな額を出しても成功はまれ）。"
	return "「締め切って結果を見る」で、FA宣言した選手の移籍先が決まります。"


# --- タブと一覧 ---------------------------------------------------------------------------

func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lb := UiTheme.small_label("◀ LB", 18, UiTheme.TEXT, 800)
	row.add_child(lb)
	for t: Array in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(190, 46)
		b.add_theme_font_size_override("font_size", 22)
		UiTheme.style_button(b, t[2], Color.WHITE, 10, 6)
		var key: String = t[0]
		b.pressed.connect(func() -> void: _show_tab(key))
		row.add_child(b)
		_tab_buttons[key] = b
	row.add_child(UiTheme.small_label("RB ▶", 18, UiTheme.TEXT, 800))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var count_panel := PanelContainer.new()
	var style := UiTheme.card(Color("2f7fd8"), 8, 3, 1.0)
	count_panel.add_theme_stylebox_override("panel", style)
	count_panel.custom_minimum_size = Vector2(170, 46)
	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.heading(_count_label, 26, UiTheme.TEXT, Color.WHITE, 6, false)
	count_panel.add_child(_count_label)
	row.add_child(count_panel)
	return row


func _show_tab(key: String) -> void:
	_tab = key
	_selected = ""
	_message = ""
	refresh()
	focus_first()


func _render_tabs(f: FreeAgency) -> void:
	for key: String in _tab_buttons:
		var b: Button = _tab_buttons[key]
		b.set_pressed_no_signal(key == _tab)
		b.modulate = Color.WHITE if key == _tab else Color(1, 1, 1, 0.6)
	_count_label.text = "%d人" % _ids.size()
	_close_button.disabled = f == null or f.resolved
	_close_button.text = "締め切って結果を見る" if f == null or not f.resolved else "締め切りました"


func _list_ids(f: FreeAgency) -> Array[String]:
	var ids: Array[String] = []
	if f == null:
		return ids
	match _tab:
		"fa":
			ids.assign(f.declared)
		"mlb":
			ids.assign(f.mlb)
		"result":
			if f.resolved:
				for r: Dictionary in f.results:
					ids.append(r["id"])
			else:
				ids.assign(f.user_bids.keys())
			for id in f.mlb:
				if f.mlb_info[id]["status"] != "leave":
					ids.append(id)
	# 自球団の選手・自球団が関わる選手を先に、あとは球団順
	var mine := GameState.team
	var sorted: Array[String] = ids.duplicate()
	sorted.sort_custom(func(a: String, b: String) -> bool:
		var ma := _from_team(f, a) == mine or f.user_bids.has(a)
		var mb := _from_team(f, b) == mine or f.user_bids.has(b)
		if ma != mb:
			return ma
		return ids.find(a) < ids.find(b))
	return sorted


func _render_list(f: FreeAgency) -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_tags.clear()
	_ids = _list_ids(f)
	if _ids.is_empty():
		var empty := UiTheme.small_label(_empty_text(f), 18, UiTheme.TEXT, 700)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(900, 0)
		_grid.add_child(empty)
		return
	for id in _ids:
		_grid.add_child(_tile(f, id, NameTag.family_name(str(GameData.player(id).get("name", id)))))


func _empty_text(f: FreeAgency) -> String:
	if f == null:
		return "FA・ポスティングの交渉はオフの「FA・トレード・ポスティング」の段階で行います。"
	match _tab:
		"fa":
			return "今オフにFA宣言した選手はいません。"
		"mlb":
			return "今オフにメジャーへ移籍する選手はいません。"
	return "まだ結果はありません。" if not f.resolved else "今オフのFAの移籍はありませんでした。"


## 選手の札1枚分：名前札＋球団の略称＋守備位置＋年齢＋状態
func _tile(f: FreeAgency, id: String, short_name: String) -> Control:
	var p := GameData.player(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.custom_minimum_size = Vector2(TILE_WIDTH, 0)
	var tag := NameTag.new()
	tag.custom_minimum_size = TAG_SIZE
	tag.setup_player(p, short_name)
	tag.selected = id == _selected
	tag.tooltip_text = "%s（%s）　%s" % [p.get("name", id), _from_team_short(f, id), _state_text(f, id)]
	tag.pressed.connect(_on_tag_pressed.bind(id))
	row.add_child(tag)
	_tags[id] = tag
	var team := _from_team(f, id)
	var colors := GameData.team_colors(team)
	var chip := Label.new()
	chip.text = GameData.short_name(team).substr(0, 2)
	chip.custom_minimum_size = Vector2(38, 34)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ink := UiTheme.text_on(colors[0])
	chip.add_theme_color_override("font_color", ink)
	chip.add_theme_font_override("font", UiTheme.font(800))
	chip.add_theme_font_size_override("font_size", 14)
	chip.add_theme_stylebox_override("normal", UiTheme.gloss(colors[0], 5, 1, 1))
	row.add_child(chip)
	var info := Label.new()
	info.text = "%s %d歳" % [POS_SHORT.get(p.get("primary_pos"), "-"), FreeAgency.age_of(p, GameState.year)]
	UiTheme.heading(info, 17, UiTheme.TEXT, Color.WHITE, 4, false)
	row.add_child(info)
	var mark := _mark(f, id)
	if not mark.is_empty():
		var badge := Label.new()
		badge.text = mark[0]
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.add_theme_font_override("font", UiTheme.font(800))
		badge.add_theme_font_size_override("font_size", 13)
		badge.add_theme_stylebox_override("normal", UiTheme.gloss(mark[1], 5, 1, 1))
		row.add_child(badge)
	return row


## 札の横の印 [文字, 色]
func _mark(f: FreeAgency, id: String) -> Array:
	if f.mlb_info.has(id):
		match f.mlb_info[id]["status"]:
			"kept":
				return ["残留", Color("2e9b48")]
			"failed":
				return ["失敗", Color("8a9199")]
		return ["交渉可", Color("e8413c")] if f.mlb_info[id]["from"] == GameState.team else []
	if f.resolved:
		for r: Dictionary in f.results:
			if r["id"] == id:
				if r["to"] == r["from"]:
					return ["残留", Color("2e9b48")]
				return ["→" + GameData.short_name(r["to"]).substr(0, 3), Color("e8413c") \
					if r["to"] == GameState.team else Color("1e63c8")]
	if f.user_bids.has(id):
		return ["提示済", Color("ff8a3d")]
	return []


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
		for r: Dictionary in f.results:
			if r["id"] == id:
				var where := "残留" if r["to"] == r["from"] else "%sへ移籍" % GameData.short_name(r["to"])
				return "%s（%s・%d年、入札%d球団）" % [where, Salary.text(r["amount"]), r["years"], r["bidders"]]
	var parts: Array[String] = ["FA宣言（他球団の関心：%d球団）" % f.cpu_bidder_count(id)]
	if f.user_bids.has(id):
		parts.append("提示済み %s・%d年" % [Salary.text(f.user_bids[id]["amount"]), f.user_bids[id]["years"]])
	return "　".join(parts)


func _render_status(f: FreeAgency) -> void:
	if not _message.is_empty():
		_status_label.text = _message
	elif f == null:
		_status_label.text = ""
	elif f.resolved:
		var moved := 0
		for r: Dictionary in f.results:
			if r["to"] != r["from"]:
				moved += 1
		_status_label.text = "FA宣言 %d人のうち %d人が移籍しました。可変ボタン「契約更改へ」で次へ進みます。" % [
			f.declared.size(), moved]
	else:
		_status_label.text = "FA宣言 %d人・メジャー移籍 %d人。提示が終わったら「締め切って結果を見る」。" % [
			f.declared.size(), f.mlb.size()]
	message_changed.emit(_status_label.text)


# --- 操作 --------------------------------------------------------------------------------

func _on_tag_pressed(id: String) -> void:
	if _selected == id:
		PlayerDetail.open(_tags.get(id, self), id, _ids)
		return
	_selected = id
	_message = ""
	var f := GameState.fa()
	if f != null:
		if f.user_bids.has(id):
			_amount = f.user_bids[id]["amount"]
			_years = f.user_bids[id]["years"]
		elif f.info.has(id):
			_amount = f.info[id]["asking"]
			_years = 3 if int(f.info[id]["age"]) <= 31 else 2
		elif f.mlb_info.has(id):
			_amount = f.mlb_info[id]["amount"] if f.mlb_info[id]["amount"] > 0 else f.mlb_info[id]["asking"]
			_years = maxi(1, f.mlb_info[id]["years"]) if f.mlb_info[id]["years"] > 0 else 3
		if f.info.has(id) or f.mlb_info.has(id):
			var r := f.bid_range(id)
			_amount = clampi(_amount, r[0], r[1])
	refresh()


func _step_amount(delta: int) -> void:
	var f := GameState.fa()
	if f == null or _selected.is_empty():
		return
	var r := f.bid_range(_selected)
	var step := 100 if _amount < 3000 else (500 if _amount < 10000 else 1000)
	_amount = clampi(_amount + delta * step, r[0], r[1])
	refresh()
	UiFx.bump(_amount_label, 1.08)


func _step_years(delta: int) -> void:
	_years = clampi(_years + delta, 1, FreeAgency.YEARS_MAX)
	refresh()
	UiFx.bump(_years_label, 1.08)


func _on_action_pressed() -> void:
	var f := GameState.fa()
	if f == null or _selected.is_empty():
		return
	var id := _selected
	var name: String = GameState.league.names.get(id, id)
	if f.mlb_info.has(id):
		var result := GameState.mlb_keep(id, _amount, _years)
		_message = result["text"]
	else:
		var error := GameState.fa_offer(id, _amount, _years)
		_message = error if not error.is_empty() else "%sに %s・%d年 を提示しました（締め切りで決まります）。" % [
			name, Salary.text(_amount), _years]
	_shown_key = ""
	refresh()
	UiFx.bump(_action_button, 1.06)


func _on_cancel_pressed() -> void:
	if _selected.is_empty():
		return
	GameState.fa_cancel(_selected)
	_message = "提示を取り消しました。"
	_shown_key = ""
	refresh()


func _on_close_pressed() -> void:
	GameState.fa_resolve()
	_selected = ""
	_message = ""
	_show_tab("result")


# --- 共通 --------------------------------------------------------------------------------

## 交渉の相手の元の球団（FA宣言・メジャー移籍のときの所属）
func _from_team(f: FreeAgency, id: String) -> String:
	if f != null and f.info.has(id):
		return f.info[id]["from"]
	if f != null and f.mlb_info.has(id):
		return f.mlb_info[id]["from"]
	return GameState.league.team_of.get(id, "")


func _from_team_short(f: FreeAgency, id: String) -> String:
	return GameData.short_name(_from_team(f, id))


func _ability_text(p: Dictionary) -> String:
	var pitcher: bool = p.get("is_pitcher", false)
	var parts: Array[String] = []
	var ratings: Variant = (p.get("pitching") if pitcher else p.get("batting"))
	if not ratings is Dictionary or not ratings.get("ratings") is Dictionary:
		return ""
	var keys := [["overall", "総合"], ["stamina", "スタミナ"], ["k9", "奪三振"], ["bb9", "制球"]] if pitcher \
		else [["meet", "ミート"], ["power", "パワー"], ["speed", "走力"], ["defense", "守備"]]
	for k: Array in keys:
		var r: Variant = ratings["ratings"].get(k[0])
		parts.append("%s%s" % [k[1], r["rank"] if r is Dictionary else "-"])
	return " ".join(parts)
