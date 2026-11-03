class_name ContractView
extends VBoxContainer
## オフの「契約更改」の画面（ハブの可変ボタンから開く。見た目は FaView と揃える）。
##
## 上に提示の枠（左＝選んだ選手と今季成績、中央＝前年 → 提示額と増減、右＝自球団の提示：年俸の◀▶と提示できる範囲）、
## 下にタブ（投手／野手／球団別）と自球団の選手の札の一覧（来季の提示額と前年比）。球団別は12球団の
## 来季の年俸総額と予算上限。仕組みは ContractRenewal（GameState.contracts()）。保留（交渉決裂）は無し。
## 操作：札をⒶ／クリックで選び、同じ札をもう一度Ⓐ／クリック（または右クリック）で選手詳細。十字キーで
## 上の ◀▶ と「査定額に戻す」へ。LB/RB（Q/E）でタブ、Ⓑはまず選択の取り消し→ハブへ戻る。
## 「契約更改を終える」で締める（可変ボタンで次へ進んでも締まる）。
## 新しいオフの順番（作業54）では戦力外も同じ画面で決める：選んだ選手を「戦力外にする」、上に支配下の人数（◯/70）・
## 来季の年俸総額と予算、下にドラフトで本指名できる人数の見込み。「契約更改・戦力外を確定」で両方締める
## （70人を超えていたら確認してから、足りない分はおまかせで選ぶ。仕組みは Releases）。
## 33歳以上の選手には「引退を勧める」（受け入れる見込みを★で出す。受け入れればその場で引退。作業56）。

signal message_changed(text: String)

const TABS := [["p", "投手", Color("e53935")], ["b", "野手", Color("1e63c8")],
	["teams", "球団別", Color("2e9b48")]]
const TAG_SIZE := Vector2(132, 34)
const TILE_WIDTH := 372
const DEAL_HEIGHT := 200
const UP_COLOR := Color("e8413c")
const DOWN_COLOR := Color("1e63c8")
const SAME_COLOR := Color("8a9199")
const CUT_COLOR := Color("5b3a8c")

var _palette: UiTheme.Palette
var _tab := "p"
var _selected := ""
var _message := ""
var _shown_key := ""

var _tab_buttons := {}
var _count_label: Label
var _grid: GridContainer
var _scroll: ScrollContainer
var _left_box: VBoxContainer
var _center_box: VBoxContainer
var _prev_label: Label
var _new_label: Label
var _diff_label: Label
var _reset_button: Button
var _right_box: VBoxContainer
var _amount_label: Label
var _range_label: Label
var _step_buttons: Array[Button] = []
var _status_label: Label
var _close_button: Button
var _release_button: Button
var _auto_button: Button
var _retire_button: Button
var _confirm_pending := false
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
	_close_button.text = "契約更改を終える"
	_close_button.custom_minimum_size = Vector2(250, 46)
	UiTheme.style_button(_close_button, Color("2e9b48"))
	_close_button.pressed.connect(_on_close_pressed)
	bottom.add_child(_close_button)


# --- 外から ------------------------------------------------------------------------------

func open() -> void:
	_selected = ""
	_message = ""
	_confirm_pending = false
	_shown_key = ""
	var c := GameState.contracts()
	_tab = "teams" if c != null and c.resolved else "p"
	refresh()
	focus_first()


## 戻る：選択中なら取り消す（true）。何も選んでいなければ false（ハブへ戻る）
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
	var c := GameState.contracts()
	var amount: int = c.rows[_selected]["amount"] if c != null and c.rows.has(_selected) else 0
	var r := GameState.releases()
	var key := "%s|%s|%d|%d|%s|%d|%d|%s|%s|%s|%s" % [_tab, _selected, amount, GameState.roster_version,
		str(c.resolved) if c != null else "", GameState.year, c.total_change() if c != null else 0,
		str(r.marked.keys()) if r != null else "", str(r.resolved) if r != null else "", str(_confirm_pending),
		_message]
	if key == _shown_key:
		return
	_shown_key = key
	var focus := UiInput.focus_index(self)
	var focused_id := ""
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for id: String in _tags:
		if _tags[id] == owner:
			focused_id = id
	_render_list(c)
	_render_deal(c)
	_render_tabs(c)
	_render_status(c)
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


## 上の ◀▶ を押す（テスト用）
func step(delta: int) -> void:
	_step_amount(delta)


## 選んだ選手の「戦力外にする／やめる」を押す（テスト用）
func toggle_release() -> void:
	_on_release_pressed()


## 選んだ選手に「引退を勧める」を押す（テスト用）
func offer_retire() -> void:
	_on_retire_pressed()


## 「確定」を押す（テスト用。70人を超えていると1回目は確認）
func press_close() -> void:
	_on_close_pressed()


# --- 提示の枠 ------------------------------------------------------------------------------

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

	var center := VBoxContainer.new()
	_center_box = center
	center.custom_minimum_size = Vector2(270, 0)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 4)
	row.add_child(center)
	_prev_label = UiTheme.small_label("", 18, UiTheme.TEXT_SUB, 800)
	_prev_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_prev_label)
	var arrow := Label.new()
	arrow.text = "▼"
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(arrow, 22, Color("ff8a3d"), Color.WHITE, 4)
	center.add_child(arrow)
	_new_label = Label.new()
	_new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(_new_label, 34, Color("e53935"), Color.WHITE, 6)
	center.add_child(_new_label)
	_diff_label = Label.new()
	_diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(_diff_label, 22, UiTheme.TEXT, Color.WHITE, 5)
	center.add_child(_diff_label)
	_reset_button = Button.new()
	_reset_button.text = "査定額に戻す"
	_reset_button.custom_minimum_size = Vector2(200, 40)
	UiTheme.style_button(_reset_button, Color("8a9199"), Color.WHITE, 8, 4)
	_reset_button.pressed.connect(_on_reset_pressed)
	center.add_child(_reset_button)

	_right_box = VBoxContainer.new()
	_right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_box.add_theme_constant_override("separation", 8)
	row.add_child(_right_box)
	_right_box.add_child(_band(Label.new(), GameState.team, "%sの提示（来季の年俸）" % GameData.short_name(GameState.team)))
	_amount_label = Label.new()
	_right_box.add_child(_stepper("年俸", _amount_label, 340))
	_range_label = UiTheme.small_label("", 15, UiTheme.TEXT, 700)
	_range_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_right_box.add_child(_range_label)
	var cut_row := HBoxContainer.new()
	cut_row.add_theme_constant_override("separation", 10)
	_right_box.add_child(cut_row)
	_release_button = Button.new()
	_release_button.text = "戦力外にする"
	_release_button.custom_minimum_size = Vector2(200, 42)
	UiTheme.style_button(_release_button, CUT_COLOR, Color.WHITE, 8, 4)
	_release_button.pressed.connect(_on_release_pressed)
	cut_row.add_child(_release_button)
	_auto_button = Button.new()
	_auto_button.text = "戦力外をおまかせ"
	_auto_button.custom_minimum_size = Vector2(200, 42)
	UiTheme.style_button(_auto_button, Color("ff8a3d"), Color.WHITE, 8, 4)
	_auto_button.pressed.connect(_on_auto_pressed)
	cut_row.add_child(_auto_button)
	_retire_button = Button.new()
	_retire_button.text = "引退を勧める"
	_retire_button.custom_minimum_size = Vector2(0, 42)
	UiTheme.style_button(_retire_button, Color("8a5cc8"), Color.WHITE, 8, 4)
	_retire_button.pressed.connect(_on_retire_pressed)
	_right_box.add_child(_retire_button)
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


func _stepper(title: String, value_label: Label, width: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var head := UiTheme.small_label(title, 18, UiTheme.TEXT, 800)
	head.custom_minimum_size = Vector2(52, 0)
	row.add_child(head)
	var minus := Button.new()
	minus.text = "◀"
	minus.custom_minimum_size = Vector2(52, 46)
	UiTheme.style_button(minus, Color("ff8a3d"), Color.WHITE, 8, 5)
	minus.pressed.connect(func() -> void: _step_amount(-1))
	row.add_child(minus)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiTheme.gloss(Color("ffd84d"), 8, 3, 3, Color("b8860b")))
	bar.custom_minimum_size = Vector2(width, 46)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(value_label, 26, UiTheme.TEXT, Color.WHITE, 6, false)
	bar.add_child(value_label)
	row.add_child(bar)
	var plus := Button.new()
	plus.text = "▶"
	plus.custom_minimum_size = Vector2(52, 46)
	UiTheme.style_button(plus, Color("ff8a3d"), Color.WHITE, 8, 5)
	plus.pressed.connect(func() -> void: _step_amount(1))
	row.add_child(plus)
	_step_buttons.append(minus)
	_step_buttons.append(plus)
	return row


func _render_deal(c: ContractRenewal) -> void:
	for child in _left_box.get_children():
		_left_box.remove_child(child)
		child.queue_free()
	var id := _selected
	_render_release_buttons(c)
	if c == null or not c.rows.has(id) or GameData.player(id).is_empty():
		_left_box.add_child(_band(Label.new(), GameState.team, "選手を選んでください"))
		var hint := UiTheme.small_label(_hint_text(c), 17, UiTheme.TEXT, 700)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_left_box.add_child(hint)
		_prev_label.text = ""
		_new_label.text = ""
		_diff_label.text = ""
		_amount_label.text = "-"
		_range_label.text = ""
		_set_adjust_enabled(false)
		_center_box.modulate.a = 0.0
		return
	_center_box.modulate.a = 1.0
	var p := GameData.player(id)
	var row: Dictionary = c.rows[id]
	_left_box.add_child(_band(Label.new(), GameState.team, GameState.team))
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
	pos_label.text = "%s %d歳" % [FaView.POS_SHORT.get(p.get("primary_pos"), "-"),
		FreeAgency.age_of(p, GameState.year)]
	UiTheme.heading(pos_label, 26, UiTheme.TEXT, Color.WHITE, 6)
	line.add_child(pos_label)
	_left_box.add_child(line)
	var lines: Array[String] = []
	lines.append("%s　在籍%d年目" % [str(p.get("name", "")), GameState.league.years_in_npb(id, GameState.year)])
	lines.append("今季：" + season_text(p, id))
	if not String(row["fixed"]).is_empty():
		lines.append("据え置き（%s）" % row["fixed"])
	else:
		lines.append("査定額 %s" % Salary.text(row["proposed"]))
	var info := UiTheme.small_label("\n".join(lines), 16, UiTheme.TEXT_SUB, 700)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_box.add_child(info)
	var prev: int = row["prev"]
	var amount: int = row["amount"]
	_prev_label.text = "今季 %s" % Salary.text(prev)
	_new_label.text = Salary.text(amount)
	var diff := amount - prev
	_diff_label.text = _diff_text(prev, amount)
	_diff_label.label_settings.font_color = (UP_COLOR if diff > 0 else (DOWN_COLOR if diff < 0 else SAME_COLOR))
	_amount_label.text = Salary.text(amount)
	var adjustable := c.can_adjust(id) and not _is_marked(id) and not _is_retired_by_offer(id)
	_set_adjust_enabled(adjustable)
	_reset_button.disabled = not adjustable or amount == int(row["proposed"])
	if adjustable:
		_range_label.text = "提示できる額 %s〜%s\n（減額制限%d%%・査定額の%d%%まで／上げ幅は3倍・+1億5000万円まで）" % [
			Salary.text(row["low"]), Salary.text(row["high"]),
			roundi(100 * (Salary.CUT_LIMIT_HIGH if prev > Salary.CUT_LIMIT_BORDER else Salary.CUT_LIMIT_LOW)),
			roundi(100 * Salary.ADJUST_FLOOR_RATE)]
	elif _is_retired_by_offer(id):
		_range_label.text = "引退の勧めを受け入れて引退しました"
	elif _is_marked(id):
		_range_label.text = "戦力外にする選手です（来季の契約はしません）"
	elif c.resolved:
		_range_label.text = "契約更改は終わりました"
	else:
		_range_label.text = "%sのため据え置きです" % row["fixed"]


static func _diff_text(prev: int, amount: int) -> String:
	var diff := amount - prev
	if diff == 0:
		return "現状維持"
	var pct := roundi(100.0 * diff / maxf(1.0, prev))
	return "%s%s（%+d%%）" % ["+" if diff > 0 else "−", Salary.text(absi(diff)), pct]


func _set_adjust_enabled(enabled: bool) -> void:
	for b in _step_buttons:
		b.disabled = not enabled
	_reset_button.disabled = not enabled
	_right_box.modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.55)


## 戦力外のボタン（契約更改と戦力外がひとつの段階のときだけ出す）
func _render_release_buttons(c: ContractRenewal) -> void:
	var r := GameState.releases()
	var merged := GameState.contract_with_release() and r != null
	_release_button.visible = merged
	_auto_button.visible = merged
	_retire_button.visible = merged
	if not merged:
		return
	_render_retire_button(c)
	var id := _selected
	var has_row := c != null and c.rows.has(id)
	_release_button.text = "戦力外をやめる" if r.marked.has(id) else "戦力外にする"
	var reason := r.check_mark(id) if has_row and not r.marked.has(id) else ""
	_release_button.disabled = not has_row or r.resolved or not reason.is_empty()
	_release_button.tooltip_text = reason
	_auto_button.disabled = r.resolved or r.need(GameState.league) <= 0


## 「引退を勧める」：33歳以上の選手だけ。受け入れる見込みを★（5段階）で出す。1人1オフ1回まで
func _render_retire_button(c: ContractRenewal) -> void:
	var r := GameState.releases()
	var id := _selected
	if c == null or not c.rows.has(id) or GameData.player(id).is_empty():
		_retire_button.text = "引退を勧める（33歳以上）"
		_retire_button.disabled = true
		return
	if r.retire_asked.has(id):
		_retire_button.text = "引退しました" if r.retire_asked[id] else "引退の勧めを断られました"
		_retire_button.disabled = true
		return
	var block := GameState.retire_offer_block(id)
	if not block.is_empty():
		_retire_button.text = "引退を勧める（%d歳以上）" % LeagueRoster.RETIRE_OFFER_MIN_AGE
		_retire_button.disabled = true
		_retire_button.tooltip_text = block
		return
	var chance := GameState.retire_offer_chance(id)
	_retire_button.text = "引退を勧める　受け入れ %s" % stars(chance)
	_retire_button.tooltip_text = "受け入れる見込み 約%d%%（年齢・能力・今季の成績・年俸から）" % roundi(chance * 100.0)
	_retire_button.disabled = false


## 受け入れる見込みの★（5段階）
static func stars(chance: float) -> String:
	var n := clampi(roundi(chance * 5.0), 1, 5)
	return "★".repeat(n) + "☆".repeat(5 - n)


func _is_retired_by_offer(id: String) -> bool:
	var r := GameState.releases()
	return r != null and bool(r.retire_asked.get(id, false))


func _is_marked(id: String) -> bool:
	var r := GameState.releases()
	return r != null and GameState.contract_with_release() and r.marked.has(id)


func _hint_text(c: ContractRenewal) -> String:
	if c == null:
		return "契約更改は、オフの「契約更改」の段階で行います。"
	if _tab == "teams":
		return "12球団の来季の年俸総額と予算上限です。予算の残りはFAの提示の上限にも効きます。"
	if GameState.contract_with_release():
		return "今季の成績・能力・在籍年数から査定した来季の年俸です。選手を選ぶと提示額を上げ下げするか、" \
			+ "戦力外にできます（もう一度Ⓐで選手詳細）。"
	return "今季の成績・能力・在籍年数から査定した来季の年俸です。選手を選ぶと提示額を上げ下げできます" \
		+ "（もう一度Ⓐで選手詳細）。"


## 今季のゲーム内成績の要約（打者：試合・打率・本塁打・打点、投手：登板・勝敗S・防御率）
static func season_text(p: Dictionary, id: String) -> String:
	var season: Season = GameState.season
	if season == null:
		return "成績なし"
	if p.get("is_pitcher", false):
		var s: Dictionary = season.pitching.get(id, {})
		var outs := int(s.get("outs", 0))
		if outs <= 0:
			return "登板なし"
		return "%d登板 %d勝%d敗%dS 防御率%.2f（%d回%s）" % [int(s.get("g", 0)), int(s.get("w", 0)),
			int(s.get("l", 0)), int(s.get("sv", 0)), float(s.get("er", 0)) * 27.0 / outs, outs / 3,
			"" if outs % 3 == 0 else " %d/3" % (outs % 3)]
	var b: Dictionary = season.batting.get(id, {})
	var ab := int(b.get("ab", 0))
	if int(b.get("pa", 0)) <= 0:
		return "出場なし"
	var avg := ("%.3f" % (float(b.get("h", 0)) / ab)).trim_prefix("0") if ab > 0 else "-"
	return "%d試合 打率%s %d本 %d打点（%d打席）" % [int(b.get("g", 0)), avg, int(b.get("hr", 0)),
		int(b.get("rbi", 0)), int(b.get("pa", 0))]


# --- タブと一覧 ---------------------------------------------------------------------------

func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiTheme.small_label("◀ LB", 18, UiTheme.TEXT, 800))
	for t: Array in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(160, 46)
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
	count_panel.add_theme_stylebox_override("panel", UiTheme.card(Color("2f7fd8"), 8, 3, 1.0))
	count_panel.custom_minimum_size = Vector2(420, 46)
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
	refresh()
	focus_first()


func _render_tabs(c: ContractRenewal) -> void:
	for key: String in _tab_buttons:
		var b: Button = _tab_buttons[key]
		b.set_pressed_no_signal(key == _tab)
		b.modulate = Color.WHITE if key == _tab else Color(1, 1, 1, 0.6)
	var team := GameState.team
	var total: int = GameState.league.next_payroll(team) if GameState.league != null else 0
	var budget := ContractRenewal.budget(team)
	var r := GameState.releases()
	if GameState.contract_with_release() and r != null:
		for id: String in r.marked:
			total -= GameState.league.salary_of(id)
		var projected := r.projected(GameState.league)
		_count_label.text = "支配下 %d/%d人　年俸 %s／予算 %s" % [projected, LeagueRoster.ROSTER_LIMIT,
			_short_amount(total), _short_amount(budget)]
		_count_label.label_settings.font_color = (UP_COLOR if total > budget or r.need(GameState.league) > 0
			else UiTheme.TEXT)
		var done := c == null or (c.resolved and r.resolved)
		_close_button.disabled = done
		_close_button.text = "契約更改・戦力外は終わりました" if done else (
			"もう一度押すと確定" if _confirm_pending else "契約更改・戦力外を確定")
		return
	_count_label.text = "年俸総額 %s／予算 %s" % [_short_amount(total), _short_amount(budget)]
	_count_label.label_settings.font_color = (UP_COLOR if total > budget else UiTheme.TEXT)
	_close_button.disabled = c == null or c.resolved
	_close_button.text = "契約更改を終える" if c == null or not c.resolved else "契約更改は終わりました"


## 「32.5億円」「8500万円」のような短い表示
static func _short_amount(amount: int) -> String:
	if amount >= 10000:
		return "%.1f億円" % (amount / 10000.0)
	return "%d万円" % amount


func _list_ids(c: ContractRenewal) -> Array[String]:
	var ids: Array[String] = []
	if c == null or _tab == "teams":
		return ids
	for id in c.order:
		var pitcher: bool = GameData.player(id).get("is_pitcher", false)
		if pitcher == (_tab == "p"):
			ids.append(id)
	return ids


func _render_list(c: ContractRenewal) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_tags.clear()
	_ids = _list_ids(c)
	if _tab == "teams" and GameState.league != null:
		_grid.columns = 1
		_render_teams()
		return
	_grid.columns = 3
	if _ids.is_empty():
		var empty := UiTheme.small_label("契約更改はオフの「契約更改」の段階で行います。" if c == null \
			else "対象の選手はいません。", 18, UiTheme.TEXT, 700)
		empty.custom_minimum_size = Vector2(900, 0)
		_grid.add_child(empty)
		return
	for id in _ids:
		_grid.add_child(_tile(c, id, NameTag.family_name(str(GameData.player(id).get("name", id)))))


## 選手の札1枚分：名前札＋来季の提示額＋前年比の印
func _tile(c: ContractRenewal, id: String, short_name: String) -> Control:
	var p := GameData.player(id)
	var row_data: Dictionary = c.rows[id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(TILE_WIDTH, 0)
	var tag := NameTag.new()
	tag.custom_minimum_size = TAG_SIZE
	tag.setup_player(p, short_name)
	tag.selected = id == _selected
	tag.tooltip_text = "%s　%s → %s　%s" % [p.get("name", id), Salary.text(row_data["prev"]),
		Salary.text(row_data["amount"]), season_text(p, id)]
	tag.pressed.connect(_on_tag_pressed.bind(id))
	row.add_child(tag)
	_tags[id] = tag
	var amount := Label.new()
	amount.text = Salary.text(row_data["amount"])
	amount.custom_minimum_size = Vector2(130, 0)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.heading(amount, 17, UiTheme.TEXT, Color.WHITE, 4, false)
	row.add_child(amount)
	var diff: int = int(row_data["amount"]) - int(row_data["prev"])
	var badge := Label.new()
	var color := UP_COLOR if diff > 0 else (DOWN_COLOR if diff < 0 else SAME_COLOR)
	if _is_retired_by_offer(id):
		badge.text = "引退"
		color = Color("8a5cc8")
		tag.modulate = Color(1, 1, 1, 0.55)
	elif _is_marked(id):
		badge.text = "戦力外"
		color = CUT_COLOR
		tag.modulate = Color(1, 1, 1, 0.55)
	elif not String(row_data["fixed"]).is_empty():
		badge.text = "据置"
		color = SAME_COLOR
	elif diff == 0:
		badge.text = "維持"
	else:
		badge.text = "%+d%%" % roundi(100.0 * diff / maxf(1.0, row_data["prev"]))
	badge.custom_minimum_size = Vector2(60, 26)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_font_override("font", UiTheme.font(800))
	badge.add_theme_font_size_override("font_size", 13)
	var b_style := UiTheme.gloss(color, 4, 1, 1)
	b_style.content_margin_left = 4
	b_style.content_margin_right = 4
	b_style.content_margin_top = 2
	b_style.content_margin_bottom = 2
	badge.add_theme_stylebox_override("normal", b_style)
	row.add_child(badge)
	return row


## 球団別：12球団の来季の年俸総額と予算上限（棒の長さは予算に対する割合）
func _render_teams() -> void:
	var league := GameState.league
	var rows: Array = []
	for team: String in GameData.teams():
		rows.append([team, league.next_payroll(team), ContractRenewal.budget(team)])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	for r: Array in rows:
		_grid.add_child(_team_row(r[0], r[1], r[2]))


func _team_row(team: String, total: int, budget: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var colors := GameData.team_colors(team)
	var chip := Label.new()
	chip.text = GameData.short_name(team)
	chip.custom_minimum_size = Vector2(130, 30)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_theme_color_override("font_color", UiTheme.text_on(colors[0]))
	chip.add_theme_font_override("font", UiTheme.font(800))
	chip.add_theme_font_size_override("font_size", 16)
	chip.add_theme_stylebox_override("normal", UiTheme.gloss(colors[0], 5, 1, 1))
	row.add_child(chip)
	var bar_bg := PanelContainer.new()
	bar_bg.custom_minimum_size = Vector2(500, 26)
	bar_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg_style := UiTheme.box(Color("e6e9ee"), 6)
	bg_style.set_content_margin_all(0)
	bar_bg.add_theme_stylebox_override("panel", bg_style)
	var fill := Control.new()
	var ratio := clampf(float(total) / maxf(1.0, budget), 0.0, 1.0)
	var bar := ColorRect.new()
	bar.color = UP_COLOR if total > budget else (Color("ff8a3d") if team == GameState.team else Color("2f7fd8"))
	bar.size = Vector2(500 * ratio, 26)
	fill.clip_contents = true
	fill.custom_minimum_size = Vector2(0, 26)
	fill.add_child(bar)
	bar_bg.add_child(fill)
	row.add_child(bar_bg)
	var text := Label.new()
	text.text = "%s／予算 %s（残り %s）" % [_short_amount(total), _short_amount(budget),
		_short_amount(maxi(0, budget - total)) if total <= budget else "超過"]
	UiTheme.heading(text, 17, UP_COLOR if total > budget else UiTheme.TEXT, Color.WHITE, 4, false)
	row.add_child(text)
	return row


func _render_status(c: ContractRenewal) -> void:
	if not _message.is_empty():
		_status_label.text = _message
	elif c == null:
		_status_label.text = ""
	else:
		var up := 0
		var down := 0
		for id: String in c.rows:
			var d: int = int(c.rows[id]["amount"]) - int(c.rows[id]["prev"])
			up += 1 if d > 0 else 0
			down += 1 if d < 0 else 0
		var change := c.total_change()
		_status_label.text = "%d年の契約：%d人（アップ%d人・ダウン%d人）、総額の増減 %s%s。%s" % [
			c.year + 1, c.rows.size(), up, down, "+" if change >= 0 else "−", Salary.text(absi(change)),
			"可変ボタン「戦力外・引退へ」で次へ進みます。" if c.resolved else "提示が終わったら「契約更改を終える」。"]
		var r := GameState.releases()
		if GameState.contract_with_release() and r != null:
			var league := GameState.league
			var need := r.need(league)
			var room := league.draft_room(GameState.team) + r.marked_registered()
			_status_label.text = "%d年の契約：%d人（アップ%d人・ダウン%d人）。戦力外 %d人%s。ドラフトの本指名は%d人まで。%s" % [
				c.year + 1, c.rows.size() - r.marked.size(), up, down, r.marked.size(),
				"（あと%d人。新人の見込み%d人を含む）" % [need, league.incoming(GameState.team)] if need > 0 else "",
				maxi(0, room), "可変ボタン「ドラフトへ」で次へ進みます。" if c.resolved and r.resolved
					else "決まったら「契約更改・戦力外を確定」。"]
	message_changed.emit(_status_label.text)


# --- 操作 --------------------------------------------------------------------------------

func _on_tag_pressed(id: String) -> void:
	if _selected == id:
		PlayerDetail.open(_tags.get(id, self), id, _ids)
		return
	_selected = id
	_message = ""
	refresh()


func _step_amount(delta: int) -> void:
	var c := GameState.contracts()
	if c == null or not c.can_adjust(_selected):
		return
	var amount: int = c.rows[_selected]["amount"]
	var unit := 10 if amount < 1000 else (50 if amount < 5000 else (100 if amount < 10000 else 500))
	var error := GameState.contract_set(_selected, amount + delta * unit)
	_message = error
	refresh()
	UiFx.bump(_amount_label, 1.08)


func _on_reset_pressed() -> void:
	var c := GameState.contracts()
	if c == null or not c.can_adjust(_selected):
		return
	GameState.contract_set(_selected, c.rows[_selected]["proposed"])
	_message = "査定額に戻しました。"
	refresh()


func _on_release_pressed() -> void:
	var c := GameState.contracts()
	if c == null or not c.rows.has(_selected) or not GameState.contract_with_release():
		return
	var error := GameState.release_toggle(_selected)
	_confirm_pending = false
	_message = error
	refresh()


func _on_retire_pressed() -> void:
	var c := GameState.contracts()
	if c == null or not c.rows.has(_selected) or not GameState.contract_with_release():
		return
	var result := GameState.retire_offer(_selected)
	_confirm_pending = false
	_message = str(result["text"])
	refresh()


func _on_auto_pressed() -> void:
	var n := GameState.release_auto()
	_confirm_pending = false
	_message = "おまかせで%d人を戦力外に選びました。" % n if n > 0 else ""
	refresh()


func _on_close_pressed() -> void:
	var r := GameState.releases()
	if GameState.contract_with_release() and r != null:
		var need := r.need(GameState.league)
		if need > 0 and not _confirm_pending:
			_confirm_pending = true
			_message = "支配下が%d人を超える見込みです。あと%d人はおまかせで戦力外にします。もう一度押すと確定します。" % [
				LeagueRoster.ROSTER_LIMIT, need]
			refresh()
			return
	_confirm_pending = false
	GameState.contract_resolve()
	_selected = ""
	_message = ""
	_show_tab("teams")
