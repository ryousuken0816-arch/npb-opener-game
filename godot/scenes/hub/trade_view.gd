class_name TradeView
extends VBoxContainer
## トレード交渉の画面（ハブの「新戦力」→「トレード」から開く。docs/references/trade_pawapuro.webp が参考。docs/AUTORUN.md 作業8）。
##
## 上に交渉の枠（左＝自球団が出す選手 最大3人＋金銭、中央＝「依頼する」と成功率の★、右＝相手の球団（◀▶で切り替え）と
## 受け取る選手 最大3人）、下にタブ（自球団の投手／自球団の野手／相手の投手／相手の野手）と選手の札の一覧。
## 仕組みは Trade、交渉できる時期は GameState.trade_block_reason()（シーズン中は7月31日まで）。
## 操作：一覧の札をⒶ／クリックで交渉の枠に入れる・外す（右クリックで選手詳細）。枠の中の札はⒶ／クリックで選手詳細。
## LB/RB（Q/E）でタブ、Ⓑでハブへ戻る（交渉の条件は残る）。

signal message_changed(text: String)

const TABS := [["my_p", "自球団の投手", Color("e53935")], ["my_b", "自球団の野手", Color("1e63c8")],
	["their_p", "相手の投手", Color("ff8a3d")], ["their_b", "相手の野手", Color("2e9b48")]]
const TAG_SIZE := Vector2(132, 34)
const SLOT_SIZE := Vector2(170, 36)
## 一覧の1枚分の幅（3列で画面に収まる幅）
const TILE_WIDTH := 372
const DEAL_HEIGHT := 250
const POS_SHORT := {
	"捕手": "捕", "一塁手": "一", "二塁手": "二", "三塁手": "三", "遊撃手": "遊", "内野手": "内",
	"外野手": "外", "左翼手": "外", "中堅手": "外", "右翼手": "外", "指名打者": "指", "投手": "投",
}

var _palette: UiTheme.Palette
var _tab := "my_p"
var _partner := ""
var _give: Array[String] = []
var _get: Array[String] = []
var _money := 0
var _message := ""
## _message を出した日（日付・段階が変わったら消す）
var _message_day := ""
var _shown_key := ""

var _tab_buttons := {}
var _count_label: Label
var _grid: GridContainer
var _scroll: ScrollContainer
var _give_box: VBoxContainer
var _get_box: VBoxContainer
var _left_band: PanelContainer
var _right_band: PanelContainer
var _right_title: Label
var _partner_buttons: Array[Button] = []
var _money_label: Label
var _money_buttons: Array[Button] = []
var _action_button: Button
var _odds_label: Label
var _stars_label: Label
var _clear_button: Button
var _status_label: Label
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
	_status_label = UiTheme.fit_label(UiTheme.small_label("", 17, UiTheme.TEXT, 700))
	bottom.add_child(_status_label)
	_clear_button = Button.new()
	_clear_button.text = "条件をクリア"
	_clear_button.custom_minimum_size = Vector2(200, 46)
	UiTheme.style_button(_clear_button, Color("8a9199"))
	_clear_button.pressed.connect(clear_deal)
	bottom.add_child(_clear_button)


# --- 外から ------------------------------------------------------------------------------

func open() -> void:
	_message = ""
	_shown_key = ""
	var teams := _partners()
	if _partner.is_empty() or _partner not in teams:
		_partner = teams[0] if not teams.is_empty() else ""
	_prune()
	refresh()
	focus_first()


## 戻る：何もせず false（ハブへ戻る。交渉の条件は残す）
func back() -> bool:
	return false


func switch_tab(delta: int) -> void:
	var keys: Array = []
	for t: Array in TABS:
		keys.append(t[0])
	_show_tab(keys[posmod(keys.find(_tab) + delta, keys.size())])


func focus_first() -> void:
	if not _ids.is_empty() and _tags.has(_ids[0]):
		_tags[_ids[0]].grab_focus()
	else:
		UiInput.grab(_tab_buttons[_tab])


func refresh() -> void:
	if GameState.league == null:
		return
	var key := "%s|%s|%s|%s|%d|%d|%d|%d|%d|%s" % [_tab, _partner, ",".join(_give), ",".join(_get), _money,
		GameState.roster_version, GameState.year, GameState.day, GameState.phase,
		GameState.league.trade_refused.get(_partner, "")]
	if key == _shown_key:
		return
	_shown_key = key
	if _message_day != GameState.trade_day_key():
		_message = ""
	var focus := UiInput.focus_index(self)
	var focused_id := ""
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for id: String in _tags:
		if _tags[id] == owner:
			focused_id = id
	_prune()
	_render_list()
	_render_deal()
	_render_tabs()
	_render_status()
	if not focused_id.is_empty() and _tags.has(focused_id):
		_tags[focused_id].grab_focus()
	elif focus >= 0:
		UiInput.focus_nth(self, focus)


## 一覧の札を押したのと同じ（テスト用）
func select_player(id: String) -> void:
	_on_tag_pressed(id)


func list_ids() -> Array[String]:
	return _ids


func give_ids() -> Array[String]:
	return _give


func get_ids() -> Array[String]:
	return _get


func set_partner(team: String) -> void:
	if team == _partner or team not in _partners():
		return
	_partner = team
	_get.clear()
	_message = ""
	refresh()


func partner() -> String:
	return _partner


func set_money(amount: int) -> void:
	_money = clampi(amount, 0, Trade.MONEY_MAX)
	refresh()


func action_enabled() -> bool:
	return not _action_button.disabled


func status_text() -> String:
	return _status_label.text


## 「依頼する」を押す（テスト用）
func press_action() -> void:
	_on_action_pressed()


func clear_deal() -> void:
	_give.clear()
	_get.clear()
	_money = 0
	_message = ""
	refresh()


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

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 5)
	row.add_child(left)
	_left_band = _band(Label.new(), GameState.team, "%s（出す）" % GameData.short_name(GameState.team))
	left.add_child(_left_band)
	_give_box = VBoxContainer.new()
	_give_box.add_theme_constant_override("separation", 4)
	left.add_child(_give_box)
	left.add_child(_money_stepper())

	var center := VBoxContainer.new()
	center.custom_minimum_size = Vector2(250, 0)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 6)
	row.add_child(center)
	_action_button = Button.new()
	_action_button.text = "依頼する"
	_action_button.custom_minimum_size = Vector2(240, 110)
	_action_button.add_theme_font_override("font", UiTheme.font(800))
	_action_button.add_theme_font_size_override("font_size", 32)
	UiTheme.style_button(_action_button, Color("e8413c"), Color.WHITE, 26, 8)
	_action_button.pressed.connect(_on_action_pressed)
	center.add_child(_action_button)
	_odds_label = UiTheme.fit_label(UiTheme.small_label("", 20, UiTheme.TEXT, 800))
	_odds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_odds_label)
	_stars_label = Label.new()
	_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(_stars_label, 34, Color("e53935"), Color.WHITE, 6)
	center.add_child(_stars_label)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 5)
	row.add_child(right)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	right.add_child(head)
	for delta: int in [-1, 1]:
		var b := Button.new()
		b.text = "◀" if delta < 0 else "▶"
		b.custom_minimum_size = Vector2(44, 36)
		UiTheme.style_button(b, Color("ff8a3d"), Color.WHITE, 8, 5)
		b.pressed.connect(_step_partner.bind(delta))
		b.tooltip_text = "相手の球団を切り替える"
		_partner_buttons.append(b)
	head.add_child(_partner_buttons[0])
	_right_title = Label.new()
	_right_band = _band(_right_title, GameState.team, "")
	_right_band.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_right_band)
	head.add_child(_partner_buttons[1])
	_get_box = VBoxContainer.new()
	_get_box.add_theme_constant_override("separation", 4)
	right.add_child(_get_box)
	return panel


## 球団カラーの見出しの帯（参考画像の「広島東洋カープ」の帯）
func _band(label: Label, team: String, text: String) -> PanelContainer:
	var band := PanelContainer.new()
	label.text = text
	band.add_child(label)
	_paint_band(band, label, team)
	return band


func _paint_band(band: PanelContainer, label: Label, team: String) -> void:
	var colors := GameData.team_colors(team)
	var style := UiTheme.gloss(colors[0], 6, 2, 2)
	style.content_margin_top = 2
	style.content_margin_bottom = 4
	band.add_theme_stylebox_override("panel", style)
	var ink := UiTheme.text_on(colors[0])
	UiTheme.heading(label, 22, ink, UiTheme.outline_for(ink, colors[0]), 6, false)
	UiTheme.fit_label(label)


func _money_stepper() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UiTheme.small_label("＋金銭", 18, UiTheme.TEXT, 800))
	var minus := Button.new()
	minus.text = "◀"
	minus.custom_minimum_size = Vector2(48, 42)
	UiTheme.style_button(minus, Color("ff8a3d"), Color.WHITE, 8, 5)
	minus.pressed.connect(_step_money.bind(-1))
	row.add_child(minus)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiTheme.gloss(Color("ffd84d"), 8, 3, 3, Color("b8860b")))
	bar.custom_minimum_size = Vector2(200, 42)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_money_label = Label.new()
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(_money_label, 24, UiTheme.TEXT, Color.WHITE, 6, false)
	bar.add_child(_money_label)
	row.add_child(bar)
	var plus := Button.new()
	plus.text = "▶"
	plus.custom_minimum_size = Vector2(48, 42)
	UiTheme.style_button(plus, Color("ff8a3d"), Color.WHITE, 8, 5)
	plus.pressed.connect(_step_money.bind(1))
	row.add_child(plus)
	_money_buttons = [minus, plus]
	return row


## 交渉の枠の1人分（空いていれば「あき」）
func _slot(id: String, ids: Array[String]) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var tag := NameTag.new()
	tag.custom_minimum_size = SLOT_SIZE
	if id.is_empty():
		tag.setup_empty()
		tag.focus_mode = Control.FOCUS_NONE
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tag)
		return row
	var p := GameData.player(id)
	tag.setup_player(p, NameTag.family_name(str(p.get("name", id))))
	tag.tooltip_text = "Ⓐ／クリックで選手詳細"
	tag.pressed.connect(func() -> void: PlayerDetail.open(tag, id, ids))
	row.add_child(tag)
	var info := UiTheme.fit_label(UiTheme.small_label(_info_text(id), 17, UiTheme.TEXT, 800))
	row.add_child(info)
	return row


func _render_deal() -> void:
	var league := GameState.league
	for box: VBoxContainer in [_give_box, _get_box]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	for i in Trade.MAX_PLAYERS:
		_give_box.add_child(_slot(_give[i] if i < _give.size() else "", _give))
		_get_box.add_child(_slot(_get[i] if i < _get.size() else "", _get))
	_paint_band(_right_band, _right_title, _partner)
	_right_title.text = "%s（受け取る）" % GameData.short_name(_partner) if not _partner.is_empty() else "相手の球団"
	_money_label.text = Salary.text(_money) if _money > 0 else "0"
	var block := GameState.trade_block_reason()
	var open := block.is_empty()
	for b in _money_buttons + _partner_buttons:
		b.disabled = not open
	_action_button.disabled = true
	_stars_label.text = ""
	if not open:
		_odds_label.text = "いまは交渉できません"
		return
	if _get.is_empty():
		_odds_label.text = "相手の選手を選んでください"
		return
	if league.trade_refused.get(_partner, "") == GameState.trade_day_key():
		_odds_label.text = "今日はもう断られました"
		return
	var est := GameState.trade_estimate(_partner, _give, _get, _money)
	_action_button.disabled = false
	_odds_label.text = "成功率：%s" % Trade.STAR_WORDS[est["stars"]]
	_stars_label.text = "★".repeat(est["stars"]) + "☆".repeat(5 - int(est["stars"]))


# --- タブと一覧 ---------------------------------------------------------------------------

func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiTheme.small_label("◀ LB", 18, UiTheme.TEXT, 800))
	for t: Array in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(170, 46)
		b.add_theme_font_size_override("font_size", 20)
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
	count_panel.add_theme_stylebox_override("panel", UiTheme.card(Color("2f7fd8"), 8, 3, 1.0))
	count_panel.custom_minimum_size = Vector2(150, 46)
	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.heading(_count_label, 26, UiTheme.TEXT, Color.WHITE, 6, false)
	count_panel.add_child(_count_label)
	row.add_child(count_panel)
	return row


func _show_tab(key: String) -> void:
	_tab = key
	_message = ""
	refresh()
	focus_first()


func _render_tabs() -> void:
	for key: String in _tab_buttons:
		var b: Button = _tab_buttons[key]
		b.set_pressed_no_signal(key == _tab)
		b.modulate = Color.WHITE if key == _tab else Color(1, 1, 1, 0.6)
	_count_label.text = "%d人" % _ids.size()


## いまのタブの選手（価値の高い順）
func _list_ids() -> Array[String]:
	var league := GameState.league
	var team := GameState.team if _tab.begins_with("my") else _partner
	var pitchers := _tab.ends_with("_p")
	var ids: Array[String] = []
	var value := {}
	for id in league.players_of(team):
		var p := GameData.player(id)
		if p.is_empty() or bool(p.get("is_pitcher", false)) != pitchers:
			continue
		ids.append(id)
		value[id] = Trade.player_value(p, GameState.year, league.salary_of(id))
	ids.sort_custom(func(a: String, b: String) -> bool: return value[a] > value[b])
	return ids


func _render_list() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_tags.clear()
	_ids = _list_ids() if not _partner.is_empty() else []
	if _ids.is_empty():
		_grid.add_child(UiTheme.small_label("選手がいません。", 18, UiTheme.TEXT, 700))
		return
	var excluded := GameState.trade_excluded()
	for id in _ids:
		_grid.add_child(_tile(id, excluded))


## 選手の札1枚分：名前札＋守備位置・年齢・年俸＋（交渉の枠に入れていれば）印
func _tile(id: String, excluded: Dictionary) -> Control:
	var p := GameData.player(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(TILE_WIDTH, 0)
	var tag := NameTag.new()
	tag.custom_minimum_size = TAG_SIZE
	tag.setup_player(p, NameTag.family_name(str(p.get("name", id))))
	tag.selected = id in _give or id in _get
	tag.dimmed = excluded.has(id)
	tag.tooltip_text = "%s　%s%s" % [p.get("name", id), _ability_text(p),
		"（%s）" % excluded[id] if excluded.has(id) else ""]
	tag.pressed.connect(_on_tag_pressed.bind(id))
	row.add_child(tag)
	_tags[id] = tag
	var info := UiTheme.fit_label(UiTheme.small_label(_info_text(id), 16, UiTheme.TEXT, 800))
	row.add_child(info)
	if id in _give or id in _get:
		var badge := Label.new()
		badge.text = "交渉中"
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.add_theme_font_override("font", UiTheme.font(800))
		badge.add_theme_font_size_override("font_size", 12)
		var b_style := UiTheme.gloss(Color("e65100"), 4, 1, 1)
		b_style.content_margin_left = 6
		b_style.content_margin_right = 6
		b_style.content_margin_top = 2
		b_style.content_margin_bottom = 2
		badge.add_theme_stylebox_override("normal", b_style)
		row.add_child(badge)
	return row


## 守備位置・年齢・年俸（例「投 27歳 1億2000万円」）
func _info_text(id: String) -> String:
	var p := GameData.player(id)
	var age := FreeAgency.age_of(p, GameState.year)
	return "%s %s %s" % [POS_SHORT.get(p.get("primary_pos"), "-"), ("%d歳" % age) if age > 0 else "",
		Salary.text(GameState.league.salary_of(id))]


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


func _render_status() -> void:
	_message_day = GameState.trade_day_key()
	var block := GameState.trade_block_reason()
	if not _message.is_empty():
		_status_label.text = _message
	elif not block.is_empty():
		_status_label.text = "%s。（%s）" % [block, GameState.date_text()]
	elif GameState.phase == GameState.Phase.SEASON:
		_status_label.text = "%s：7月31日まで交渉できます。札を選んで枠に入れ、「依頼する」。" % GameState.date_text()
	else:
		_status_label.text = "%s（%s）：自球団の選手（最大%d人）＋金銭と、相手の選手（最大%d人）を交換します。" % [
			GameState.date_text(), GameState.phase_name(), Trade.MAX_PLAYERS, Trade.MAX_PLAYERS]
	message_changed.emit(_status_label.text)


# --- 操作 --------------------------------------------------------------------------------

func _on_tag_pressed(id: String) -> void:
	var excluded := GameState.trade_excluded()
	var mine: bool = GameState.league.team_of.get(id, "") == GameState.team
	var side: Array[String] = _give if mine else _get
	if id in side:
		side.erase(id)
		_message = ""
	elif excluded.has(id):
		_message = "%sは%s。" % [GameState.league.names.get(id, id), excluded[id]]
	elif side.size() >= Trade.MAX_PLAYERS:
		_message = "選手は片側%d人までです。" % Trade.MAX_PLAYERS
	else:
		side.append(id)
		_message = ""
	refresh()


func _step_partner(delta: int) -> void:
	var teams := _partners()
	if teams.is_empty():
		return
	set_partner(teams[posmod(teams.find(_partner) + delta, teams.size())])
	UiFx.bump(_right_band, 1.04)


func _step_money(delta: int) -> void:
	_money = clampi(_money + delta * Trade.MONEY_STEP, 0, Trade.MONEY_MAX)
	refresh()
	UiFx.bump(_money_label, 1.08)


func _on_action_pressed() -> void:
	var result := GameState.trade_request(_partner, _give, _get, _money)
	_message = result["text"]
	if result["ok"]:
		_give.clear()
		_get.clear()
		_money = 0
	_shown_key = ""
	refresh()
	UiFx.bump(_action_button, 1.06)


## 相手にできる球団（自球団以外）
func _partners() -> Array[String]:
	var result: Array[String] = []
	for t in GameData.teams():
		if t != GameState.team:
			result.append(t)
	return result


## 所属が変わった選手を交渉の枠から外す
func _prune() -> void:
	var league := GameState.league
	if league == null:
		return
	for id in _give.duplicate():
		if league.team_of.get(id, "") != GameState.team:
			_give.erase(id)
	for id in _get.duplicate():
		if league.team_of.get(id, "") != _partner:
			_get.erase(id)
