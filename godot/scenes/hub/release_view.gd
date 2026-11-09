class_name ReleaseView
extends VBoxContainer
## オフの「戦力外・引退」の画面（ハブの可変ボタンから開く。見た目は FaView・ContractView と揃える）。
##
## 上に枠（左＝選んだ選手と今季成績・状態、中央＝「戦力外にする／取り消す」、右＝自球団の来季の支配下の見込み
## （今の支配下 − 戦力外 ＋ 新人などの見込み ／ 上限70人）と「おまかせで選ぶ」）、下にタブ（自球団の投手／野手、
## 史実の引退、他球団の戦力外）と名前札の一覧。仕組みは Releases（GameState.releases()）。
## 操作：札をⒶ／クリックで選び、同じ札をもう一度Ⓐ／クリック（または右クリック）で選手詳細。十字キーで上のボタンへ。
## LB/RB（Q/E）でタブ、Ⓑはまず確認・選択の取り消し→ハブへ戻る。「戦力外を確定」で締める（70人を超える分が
## 足りなければ1回目は確認を出し、もう一度押すと残りを自動で選んで締める。可変ボタンで次へ進んでも自動で締まる）。

signal message_changed(text: String)

const TABS := [["p", "投手", Color("e53935")], ["b", "野手", Color("1e63c8")],
	["retire", "引退（史実）", Color("8a5cc8")], ["cpu", "他球団の戦力外", Color("2e9b48")]]
const TAG_SIZE := Vector2(132, 34)
const TILE_WIDTH := 372
const DEAL_HEIGHT := 200
const CUT_COLOR := Color("e8413c")
const IKUSEI_COLOR := Color("7aa63a")
const KEEP_COLOR := Color("2e9b48")
const RETIRE_COLOR := Color("8a5cc8")
const MARKET_COLOR := Color("ff8a3d")
const GRAY := Color("8a9199")

var _palette: UiTheme.Palette
var _tab := "p"
var _selected := ""
var _message := ""
var _shown_key := ""
var _confirm_pending := false

var _tab_buttons := {}
var _count_label: Label
var _grid: GridContainer
var _scroll: ScrollContainer
var _left_box: VBoxContainer
var _center_box: VBoxContainer
var _state_label: Label
var _toggle_button: Button
var _right_box: VBoxContainer
var _projection_label: Label
var _need_label: Label
var _auto_button: Button
var _status_label: Label
var _close_button: Button
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
	_close_button.text = "戦力外を確定"
	_close_button.custom_minimum_size = Vector2(250, 46)
	UiTheme.style_button(_close_button, Color("2e9b48"))
	_close_button.pressed.connect(_on_close_pressed)
	bottom.add_child(_close_button)


# --- 外から ------------------------------------------------------------------------------

func open() -> void:
	_selected = ""
	_message = ""
	_shown_key = ""
	_confirm_pending = false
	var r := GameState.releases()
	_tab = "cpu" if r != null and r.resolved else "p"
	refresh()
	focus_first()


## 戻る：確認中・選択中なら取り消す（true）。何もなければ false（ハブへ戻る）
func back() -> bool:
	if _confirm_pending:
		_confirm_pending = false
		_message = ""
		_shown_key = ""
		refresh()
		return true
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
	var r := GameState.releases()
	var key := "%s|%s|%d|%d|%s|%d|%d|%s|%s" % [_tab, _selected, GameState.roster_version, GameState.year,
		str(r.resolved) if r != null else "", r.marked.size() if r != null else -1,
		GameState.release_need(), str(_confirm_pending), _message]
	if key == _shown_key:
		return
	_shown_key = key
	var focus := UiInput.focus_index(self)
	var focused_id := ""
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for id: String in _tags:
		if _tags[id] == owner:
			focused_id = id
	_render_list(r)
	_render_deal(r)
	_render_tabs(r)
	_render_status(r)
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


# --- 上の枠 ------------------------------------------------------------------------------

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
	_center_box.custom_minimum_size = Vector2(270, 0)
	_center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_center_box.add_theme_constant_override("separation", 8)
	row.add_child(_center_box)
	_state_label = Label.new()
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state_label.custom_minimum_size = Vector2(270, 0)
	UiTheme.heading(_state_label, 24, UiTheme.TEXT, Color.WHITE, 6)
	_center_box.add_child(_state_label)
	_toggle_button = Button.new()
	_toggle_button.text = "戦力外にする"
	_toggle_button.custom_minimum_size = Vector2(240, 52)
	UiTheme.style_button(_toggle_button, CUT_COLOR)
	_toggle_button.pressed.connect(_on_toggle_pressed)
	_center_box.add_child(_toggle_button)

	_right_box = VBoxContainer.new()
	_right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_box.add_theme_constant_override("separation", 8)
	row.add_child(_right_box)
	_right_box.add_child(_band(Label.new(), GameState.team, "%sの来季の支配下（上限%d人）" % [
		GameData.short_name(GameState.team), LeagueRoster.ROSTER_LIMIT]))
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiTheme.gloss(Color("ffd84d"), 8, 3, 3, Color("b8860b")))
	bar.custom_minimum_size = Vector2(0, 46)
	_projection_label = Label.new()
	_projection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(_projection_label, 22, UiTheme.TEXT, Color.WHITE, 6, false)
	bar.add_child(_projection_label)
	_right_box.add_child(bar)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	_right_box.add_child(line)
	_need_label = Label.new()
	_need_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.heading(_need_label, 24, CUT_COLOR, Color.WHITE, 6, false)
	line.add_child(_need_label)
	_auto_button = Button.new()
	_auto_button.text = "おまかせで選ぶ"
	_auto_button.custom_minimum_size = Vector2(200, 44)
	UiTheme.style_button(_auto_button, Color("ff8a3d"), Color.WHITE, 8, 4)
	_auto_button.pressed.connect(_on_auto_pressed)
	line.add_child(_auto_button)
	return panel


## 球団カラーの見出しの帯
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
	return band


func _render_deal(r: Releases) -> void:
	for child in _left_box.get_children():
		_left_box.remove_child(child)
		child.queue_free()
	var league := GameState.league
	if r != null:
		var reg := league.registered_count(GameState.team)
		var marked := r.marked_registered() if not r.resolved else 0
		var inc := league.incoming(GameState.team)
		var total := reg - marked + inc
		if r.resolved:
			_projection_label.text = "%d人 ＋ 新人等%d ＝ %d人" % [reg, inc, total]
		else:
			_projection_label.text = "%d人 − 戦力外%d ＋ 新人等%d ＝ %d人" % [reg, marked, inc, total]
		_projection_label.label_settings.font_color = CUT_COLOR if total > LeagueRoster.ROSTER_LIMIT else UiTheme.TEXT
		var need := r.need(league)
		_need_label.text = "あと%d人" % need if need > 0 else ("確定しました" if r.resolved else "上限以内です")
		_need_label.label_settings.font_color = CUT_COLOR if need > 0 else KEEP_COLOR
		_auto_button.disabled = r.resolved or need <= 0
	else:
		_projection_label.text = "-"
		_need_label.text = ""
		_auto_button.disabled = true
	var id := _selected
	var p := GameData.player(id)
	if r == null or id.is_empty() or p.is_empty():
		_left_box.add_child(_band(Label.new(), GameState.team, "選手を選んでください"))
		var hint := UiTheme.small_label(_hint_text(r), 17, UiTheme.TEXT, 700)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_left_box.add_child(hint)
		_center_box.modulate.a = 0.0
		_toggle_button.disabled = true
		return
	_center_box.modulate.a = 1.0
	var team := _team_of_row(r, id)
	_left_box.add_child(_band(Label.new(), team, team))
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
	pos_label.text = "%s %s" % [FaView.POS_SHORT.get(p.get("primary_pos"), "-"), _age_text(p)]
	UiTheme.heading(pos_label, 26, UiTheme.TEXT, Color.WHITE, 6)
	line.add_child(pos_label)
	_left_box.add_child(line)
	var lines: Array[String] = []
	lines.append("%s　在籍%d年目　年俸 %s" % [str(p.get("name", "")), league.years_in_npb(id, GameState.year),
		Salary.text(league.salary_of(id))])
	lines.append("今季：" + ContractView.season_text(p, id))
	lines.append(_ability_text(p))
	var info := UiTheme.small_label("\n".join(lines), 16, UiTheme.TEXT_SUB, 700)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_box.add_child(info)
	var mark := _mark(r, id)
	_state_label.text = _state_text(r, id)
	_state_label.label_settings.font_color = mark[1] if not mark.is_empty() else UiTheme.TEXT
	var own := id in r.order
	_toggle_button.visible = own
	_toggle_button.disabled = not own or r.resolved or not r.check_mark(id).is_empty() and not r.marked.has(id)
	_toggle_button.text = "取り消す" if r.marked.has(id) else "戦力外にする"


func _hint_text(r: Releases) -> String:
	if r == null:
		return "戦力外は、オフの「戦力外・引退」の段階で決めます。"
	match _tab:
		"retire":
			return "史実で今季かぎりで引退する選手です（来季の成績が無い選手）。来季の支配下の人数には数えません。"
		"cpu":
			return "CPU球団が戦力外にした選手です。来季の成績がある選手は市場に入り、新戦力の画面から獲得できます" \
				+ "（CPU球団もドラフト〜キャンプで獲得）。"
	return "支配下は%d人まで（育成は数えない）。新人の見込みを足して上限を超える分を戦力外にします。" % \
		LeagueRoster.ROSTER_LIMIT + "札は残す価値の低い順（能力・年齢・年俸）。もう一度Ⓐで選手詳細。"


## 年齢（生年月日が無い選手は「-歳」）
static func _age_text(p: Dictionary) -> String:
	var age := FreeAgency.age_of(p, GameState.year)
	return "%d歳" % age if age > 0 else "-歳"


## 主な能力のランク
func _ability_text(p: Dictionary) -> String:
	var pitcher: bool = p.get("is_pitcher", false)
	var ratings: Variant = (p.get("pitching") if pitcher else p.get("batting"))
	if not ratings is Dictionary or not ratings.get("ratings") is Dictionary:
		return "能力：-"
	var keys := [["overall", "総合"], ["stamina", "スタミナ"], ["bb9", "制球"]] if pitcher \
		else [["meet", "ミート"], ["power", "パワー"], ["speed", "走力"], ["defense", "守備"]]
	var parts: Array[String] = []
	for k: Array in keys:
		var v: Variant = ratings["ratings"].get(k[0])
		parts.append("%s%s" % [k[1], v["rank"] if v is Dictionary else "-"])
	if pitcher:
		parts.append("決め球%s" % PitchArsenal.best_label(p))  # 作業79：奪三振の代わりに持ち球の決め球
	return "能力：" + " ".join(parts)


## その選手の球団（自球団・引退・他球団の戦力外の元の球団）
func _team_of_row(r: Releases, id: String) -> String:
	if id in r.order:
		return GameState.team
	for row: Dictionary in r.retired_rows:
		if row["id"] == id:
			return row["team"]
	for row: Dictionary in r.cpu_rows:
		if row["id"] == id:
			return row["team"]
	return GameState.league.team_of.get(id, GameState.team)


## 札の横の印 [文字, 色]（印が無ければ空）
func _mark(r: Releases, id: String) -> Array:
	var league := GameState.league
	if _tab == "retire":
		for row: Dictionary in r.retired_rows:
			if row["id"] == id:
				return ["退団" if row["foreign"] else "引退", RETIRE_COLOR]
	if _tab == "cpu" or id not in r.order:
		var released: Dictionary = league.released.get(id, {})
		if released.is_empty():
			return []
		var now: String = league.team_of.get(id, "")
		if not now.is_empty():
			return ["→" + GameData.short_name(now).substr(0, 3), CUT_COLOR if now == GameState.team else Color("1e63c8")]
		return ["市場" if released["market"] else "引退", MARKET_COLOR if released["market"] else RETIRE_COLOR]
	if r.marked.has(id):
		return ["戦力外", CUT_COLOR]
	if r.ikusei.has(id):
		return ["育成", IKUSEI_COLOR]
	if r.protected.has(id):
		return ["保護", KEEP_COLOR]
	return []


func _state_text(r: Releases, id: String) -> String:
	var league := GameState.league
	if id in r.order:
		if r.marked.has(id):
			if r.resolved:
				var where := "市場へ" if league.released.get(id, {}).get("market", false) else "引退"
				return "戦力外（%s）" % where
			return "戦力外に選択中"
		if r.protected.has(id):
			return "残す（%s）" % r.protected[id]
		if r.ikusei.has(id):
			return "育成選手（支配下の人数に数えない）"
		return "残す（残す価値 低い順 %d/%d）" % [r.order.find(id) + 1, r.order.size()]
	for row: Dictionary in r.retired_rows:
		if row["id"] == id:
			return "今季かぎりで%s（史実）" % ("退団" if row["foreign"] else "引退")
	var released: Dictionary = league.released.get(id, {})
	if not released.is_empty():
		var now: String = league.team_of.get(id, "")
		if not now.is_empty():
			return "戦力外 → %sが獲得" % GameData.short_name(now)
		return "戦力外 → 市場（%s）" % Salary.text(league.market_info[id]["asking"]) if id in league.market \
			else "戦力外 → 引退"
	return ""


# --- タブと一覧 ---------------------------------------------------------------------------

func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiTheme.small_label("◀ LB", 18, UiTheme.TEXT, 800))
	for t: Array in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 46)
		b.add_theme_font_size_override("font_size", 21)
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
	count_panel.custom_minimum_size = Vector2(360, 46)
	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.heading(_count_label, 20, UiTheme.TEXT, Color.WHITE, 5, false)
	count_panel.add_child(_count_label)
	row.add_child(count_panel)
	return row


func _show_tab(key: String) -> void:
	_tab = key
	_selected = ""
	_message = ""
	_confirm_pending = false
	refresh()
	focus_first()


func _render_tabs(r: Releases) -> void:
	for key: String in _tab_buttons:
		var b: Button = _tab_buttons[key]
		b.set_pressed_no_signal(key == _tab)
		b.modulate = Color.WHITE if key == _tab else Color(1, 1, 1, 0.6)
	if r == null:
		_count_label.text = ""
	else:
		var cut := r.user_rows.size() if r.resolved else r.marked.size()
		_count_label.text = "引退 %d人・戦力外 自%d／他%d人" % [r.retired_rows.size(), cut, r.cpu_rows.size()]
	_close_button.disabled = r == null or r.resolved
	_close_button.text = "戦力外は確定しました" if r != null and r.resolved else ("もう一度押すと確定" \
		if _confirm_pending else "戦力外を確定")


func _list_ids(r: Releases) -> Array[String]:
	var ids: Array[String] = []
	if r == null:
		return ids
	match _tab:
		"retire":
			for row: Dictionary in r.retired_rows:
				ids.append(row["id"])
		"cpu":
			for row: Dictionary in r.cpu_rows:
				ids.append(row["id"])
		_:
			for id in r.order:
				if r.resolved and not GameState.league.team_of.get(id, "") == GameState.team and not r.marked.has(id):
					continue
				var pitcher: bool = GameData.player(id).get("is_pitcher", false)
				if pitcher == (_tab == "p"):
					ids.append(id)
	return ids.filter(func(id: String) -> bool: return not GameData.player(id).is_empty())


func _render_list(r: Releases) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_tags.clear()
	_ids = _list_ids(r)
	if _ids.is_empty():
		var empty := UiTheme.small_label("戦力外はオフの「戦力外・引退」の段階で決めます。" if r == null \
			else "対象の選手はいません。", 18, UiTheme.TEXT, 700)
		empty.custom_minimum_size = Vector2(900, 0)
		_grid.add_child(empty)
		return
	for id in _ids:
		_grid.add_child(_tile(r, id, NameTag.family_name(str(GameData.player(id).get("name", id)))))


## 選手の札1枚分：名前札＋（他球団なら球団）＋守備位置・年齢＋年俸＋印
func _tile(r: Releases, id: String, short_name: String) -> Control:
	var p := GameData.player(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.custom_minimum_size = Vector2(TILE_WIDTH, 0)
	var tag := NameTag.new()
	tag.custom_minimum_size = TAG_SIZE
	tag.setup_player(p, short_name)
	tag.selected = id == _selected
	tag.tooltip_text = "%s　%s" % [p.get("name", id), _state_text(r, id)]
	tag.pressed.connect(_on_tag_pressed.bind(id))
	if r.marked.has(id) and _tab in ["p", "b"]:
		tag.modulate = Color(1, 0.78, 0.78)
	row.add_child(tag)
	_tags[id] = tag
	if _tab == "retire" or _tab == "cpu":
		var team := _team_of_row(r, id)
		var colors := GameData.team_colors(team)
		var chip := Label.new()
		chip.text = GameData.short_name(team).substr(0, 2)
		chip.custom_minimum_size = Vector2(38, 34)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_theme_color_override("font_color", UiTheme.text_on(colors[0]))
		chip.add_theme_font_override("font", UiTheme.font(800))
		chip.add_theme_font_size_override("font_size", 14)
		chip.add_theme_stylebox_override("normal", UiTheme.gloss(colors[0], 5, 1, 1))
		row.add_child(chip)
	var info := Label.new()
	info.text = "%s %s" % [FaView.POS_SHORT.get(p.get("primary_pos"), "-"), _age_text(p)]
	info.custom_minimum_size = Vector2(76, 0)
	UiTheme.heading(info, 16, UiTheme.TEXT, Color.WHITE, 4, false)
	row.add_child(info)
	if _tab in ["p", "b"]:
		var amount := Label.new()
		amount.text = Salary.text(GameState.league.salary_of(id))
		amount.custom_minimum_size = Vector2(76, 0)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		UiTheme.heading(amount, 14, UiTheme.TEXT_SUB, Color.WHITE, 3, false)
		row.add_child(amount)
	var mark := _mark(r, id)
	if not mark.is_empty():
		var badge := Label.new()
		badge.text = mark[0]
		badge.custom_minimum_size = Vector2(52, 24)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.add_theme_font_override("font", UiTheme.font(800))
		badge.add_theme_font_size_override("font_size", 12)
		var b_style := UiTheme.gloss(mark[1], 4, 1, 1)
		b_style.content_margin_left = 4
		b_style.content_margin_right = 4
		b_style.content_margin_top = 2
		b_style.content_margin_bottom = 2
		badge.add_theme_stylebox_override("normal", b_style)
		row.add_child(badge)
	return row


func _render_status(r: Releases) -> void:
	if not _message.is_empty():
		_status_label.text = _message
	elif r == null:
		_status_label.text = ""
	elif r.resolved:
		var to_market := r.user_rows.filter(func(x: Dictionary) -> bool: return x["market"]).size()
		_status_label.text = "%d年オフの戦力外：自球団 %d人（市場へ %d人）・他球団 %d人、史実の引退 %d人。" % [
			r.year, r.user_rows.size(), to_market, r.cpu_rows.size(), r.retired_rows.size()] \
			+ "可変ボタン「ドラフトへ」で次へ進みます。"
	else:
		var need := r.need(GameState.league)
		_status_label.text = ("あと%d人を戦力外に選んでください（「おまかせで選ぶ」もできます）。" % need if need > 0 \
			else "支配下は上限以内です。選び終えたら「戦力外を確定」。") \
			+ "戦力外の選手は来季の成績があれば市場へ、無ければ引退します。"
	message_changed.emit(_status_label.text)


# --- 操作 --------------------------------------------------------------------------------

func _on_tag_pressed(id: String) -> void:
	if _selected == id:
		PlayerDetail.open(_tags.get(id, self), id, _ids)
		return
	_selected = id
	_message = ""
	_confirm_pending = false
	refresh()


func _on_toggle_pressed() -> void:
	if _selected.is_empty():
		return
	var error := GameState.release_toggle(_selected)
	var r := GameState.releases()
	if error.is_empty() and r != null:
		var name: String = GameState.league.names.get(_selected, _selected)
		_message = "%sを戦力外に選びました。" % name if r.marked.has(_selected) else "%sの戦力外を取り消しました。" % name
	else:
		_message = error
	_confirm_pending = false
	refresh()
	UiFx.bump(_need_label, 1.1)


func _on_auto_pressed() -> void:
	var n := GameState.release_auto()
	_message = "残す価値の低い順に%d人を選びました。" % n
	_confirm_pending = false
	refresh()


func _on_close_pressed() -> void:
	var r := GameState.releases()
	if r == null or r.resolved:
		return
	var need := r.need(GameState.league)
	if need > 0 and not _confirm_pending:
		_confirm_pending = true
		_message = "支配下があと%d人多すぎます。もう一度押すと、残りを残す価値の低い順に自動で選んで確定します（Ⓑでやめる）。" % need
		refresh()
		return
	_confirm_pending = false
	GameState.release_resolve()
	_selected = ""
	_message = ""
	_show_tab("cpu")
