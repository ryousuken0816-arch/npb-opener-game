class_name CompView
extends VBoxContainer
## FA移籍の補償の画面（FAを締め切ったあと、自球団が関わる補償が残っていれば可変ボタン「FAの補償」で開く。作業18）。
##
## 上に選んだ補償の枠（左＝移籍した選手・ランク・ルール、中央＝決めるボタンと「金銭のみ」「おまかせ」、右＝説明）、
## 下にタブ（補償の一覧／選手）と札の一覧。仕組みは FaCompensation（GameState.comp()）。
## - 自球団が獲得した側：「選手」タブに自球団のプロテクトできる選手が並び、Ⓐ／クリックでプロテクトの入れ・外し（28人まで）。
##   「プロテクトを確定」で旧球団（CPU）が人的補償の選手か金銭かを選ぶ
## - 自球団が旧球団の側：「選手」タブに相手のプロテクト外の選手が並び、1人選んで「この選手を獲る」か「金銭のみ」。
##   2027年オフからのルールでは「指名権をもらう」か「金銭にする」
## LB/RB（Q/E）でタブ、Ⓑでハブへ戻る（決めていない補償は可変ボタンで次へ進むとおまかせで決まる）。

signal message_changed(text: String)

const TABS := [["cases", "補償の一覧", Color("8a5cc8")], ["players", "選手", Color("1e63c8")]]
const TAG_SIZE := Vector2(132, 34)
const TILE_WIDTH := 372
const DEAL_HEIGHT := 230
const POS_SHORT := {
	"捕手": "捕", "一塁手": "一", "二塁手": "二", "三塁手": "三", "遊撃手": "遊", "内野手": "内",
	"外野手": "外", "左翼手": "外", "中堅手": "外", "右翼手": "外", "指名打者": "指", "投手": "投",
}

var _palette: UiTheme.Palette
var _tab := "cases"
var _index := -1
## 自球団のプロテクトの案（確定するまで画面で持つ）
var _protect: Array[String] = []
## 人的補償で選んだ相手の選手
var _pick := ""
var _message := ""
var _shown_key := ""

var _tab_buttons := {}
var _count_label: Label
var _grid: GridContainer
var _left_box: VBoxContainer
var _info_label: Label
var _action_button: Button
var _money_button: Button
var _auto_button: Button
var _status_label: Label
var _all_button: Button
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
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	list_panel.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	add_child(bottom)
	_status_label = UiTheme.fit_label(UiTheme.small_label("", 17, UiTheme.TEXT, 700))
	bottom.add_child(_status_label)
	_all_button = Button.new()
	_all_button.text = "残りをおまかせで決める"
	_all_button.custom_minimum_size = Vector2(260, 46)
	UiTheme.style_button(_all_button, Color("2e9b48"))
	_all_button.pressed.connect(_on_all_pressed)
	bottom.add_child(_all_button)


# --- 外から ------------------------------------------------------------------------------

func open() -> void:
	_message = ""
	_shown_key = ""
	_index = -1
	var c := GameState.comp()
	if c != null:
		for i in c.cases.size():
			if c.cases[i]["state"] != "done":
				_select_case(i)
				break
	_tab = "players" if _index >= 0 else "cases"
	refresh()
	focus_first()


func back() -> bool:
	return false


func switch_tab(delta: int) -> void:
	_show_tab(TABS[posmod(_tab_index() + delta, TABS.size())][0])


func focus_first() -> void:
	if not _ids.is_empty() and _tags.has(_ids[0]):
		_tags[_ids[0]].grab_focus()
	elif not _action_button.disabled:
		_action_button.grab_focus()
	else:
		UiInput.grab(_tab_buttons[_tab])


func refresh() -> void:
	var c := GameState.comp()
	var key := "%s|%d|%s|%s|%d|%d|%s" % [_tab, _index, ",".join(_protect), _pick, GameState.roster_version,
		GameState.year, str(c.resolved) if c != null else ""]
	if key == _shown_key:
		return
	_shown_key = key
	_render_list(c)
	_render_deal(c)
	_render_tabs()
	_render_status(c)


## テスト用
func list_ids() -> Array[String]:
	return _ids


func selected_case() -> int:
	return _index


func protect_ids() -> Array[String]:
	return _protect


func select_case(index: int) -> void:
	_select_case(index)
	_message = ""
	_show_tab("players")


func select_player(id: String) -> void:
	_on_tag_pressed(id)


func press_action() -> void:
	_on_action_pressed()


func press_money() -> void:
	_on_money_pressed()


func press_auto() -> void:
	_on_auto_pressed()


# --- 上の枠 ------------------------------------------------------------------------------

func _build_deal() -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.gloss(Color("eadfc6"), 12, 4, 0, Color("a88a5c"))
	style.gloss = 0.0
	style.gradient = 0.08
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(0, DEAL_HEIGHT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	_left_box = VBoxContainer.new()
	_left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_box.add_theme_constant_override("separation", 6)
	row.add_child(_left_box)
	var center := VBoxContainer.new()
	center.custom_minimum_size = Vector2(300, 0)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 8)
	row.add_child(center)
	_action_button = Button.new()
	_action_button.custom_minimum_size = Vector2(300, 80)
	_action_button.add_theme_font_override("font", UiTheme.font(800))
	_action_button.add_theme_font_size_override("font_size", 24)
	UiTheme.style_button(_action_button, Color("e8413c"), Color.WHITE, 20, 7)
	_action_button.clip_text = true
	_action_button.pressed.connect(_on_action_pressed)
	center.add_child(_action_button)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	center.add_child(line)
	_money_button = Button.new()
	_money_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_money_button.custom_minimum_size = Vector2(0, 44)
	_money_button.clip_text = true
	UiTheme.style_button(_money_button, Color("ff8a3d"), Color.WHITE, 8, 4)
	_money_button.pressed.connect(_on_money_pressed)
	line.add_child(_money_button)
	_auto_button = Button.new()
	_auto_button.text = "おまかせ"
	_auto_button.custom_minimum_size = Vector2(110, 44)
	UiTheme.style_button(_auto_button, Color("6d7680"), Color.WHITE, 8, 4)
	_auto_button.pressed.connect(_on_auto_pressed)
	line.add_child(_auto_button)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	_info_label = UiTheme.small_label("", 15, UiTheme.TEXT, 700)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(300, 0)
	right.add_child(_info_label)
	return panel


func _render_deal(comp: FaCompensation) -> void:
	for ch in _left_box.get_children():
		_left_box.remove_child(ch)
		ch.queue_free()
	_action_button.disabled = true
	_money_button.disabled = true
	_money_button.visible = true
	_auto_button.disabled = true
	_action_button.text = "決める"
	_money_button.text = "金銭のみ"
	_info_label.text = _rule_text(comp)
	if comp == null or _index < 0 or _index >= comp.cases.size():
		_left_box.add_child(_band(GameState.team, "補償を一覧から選んでください"))
		return
	var c: Dictionary = comp.cases[_index]
	_left_box.add_child(_band(c["to"], "%s → %s" % [GameData.short_name(c["from"]), GameData.short_name(c["to"])]))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var tag := NameTag.new()
	tag.custom_minimum_size = Vector2(180, 42)
	tag.font_size = 22
	var p := GameData.player(c["id"])
	tag.setup_player(p, NameTag.family_name(str(c["name"])))
	tag.pressed.connect(func() -> void: PlayerDetail.open(tag, c["id"]))
	line.add_child(tag)
	var rank := Label.new()
	rank.text = "%sランク" % c["rank"]
	UiTheme.heading(rank, 26, Color("b3261e") if c["rank"] == "A" else UiTheme.TEXT, Color.WHITE, 6)
	line.add_child(rank)
	_left_box.add_child(line)
	var detail := UiTheme.small_label(_case_text(comp, c), 16, UiTheme.TEXT, 700)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_box.add_child(detail)
	match c["state"]:
		"protect":
			# 人数は「選手」タブの見出し（プロテクト 28/28）に出す
			_action_button.text = "プロテクトを確定"
			_action_button.disabled = false
			_auto_button.disabled = false
			_money_button.visible = false
		"choose":
			_auto_button.disabled = false
			_money_button.disabled = false
			if c["kind"] == "pick":
				_action_button.text = "%d巡目の指名権をもらう" % int(FaCompensation.rule(comp.year)["pick_round"][c["rank"]])
				_action_button.disabled = false
				_money_button.text = "金銭にする（%s）" % Salary.text(comp.money_of(c, false))
			else:
				var who := GameState.league.names.get(_pick, "") as String
				_action_button.text = "%sを獲る" % who if not who.is_empty() else "選手を選んでください"
				_action_button.disabled = _pick.is_empty()
				_money_button.text = "金銭のみ（%s）" % Salary.text(comp.money_of(c, false))


func _band(team: String, text: String) -> PanelContainer:
	var band := PanelContainer.new()
	var colors := GameData.team_colors(team)
	var style := UiTheme.gloss(colors[0], 6, 2, 2)
	style.content_margin_top = 2
	style.content_margin_bottom = 4
	band.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	var ink := UiTheme.text_on(colors[0])
	UiTheme.heading(label, 22, ink, UiTheme.outline_for(ink, colors[0]), 6, false)
	UiTheme.fit_label(label)
	band.add_child(label)
	return band


## 選んだ補償の説明（年俸・ルール・状態）
func _case_text(comp: FaCompensation, c: Dictionary) -> String:
	var lines: Array[String] = ["%d歳　移籍前の年俸 %s" % [c["age"], Salary.text(c["salary"])]]
	match c["state"]:
		"protect":
			lines.append("自球団のプロテクトを選んでください（%d人まで。外国人・育成・今オフのFA加入は自動）" % FaCompensation.PROTECT)
		"choose":
			if c["kind"] == "pick":
				lines.append("%sの指名権か金銭かを選んでください" % GameData.short_name(c["to"]))
			else:
				lines.append("%sのプロテクト外から1人（＋金銭%s）か、金銭のみを選んでください" % [
					GameData.short_name(c["to"]), Salary.text(comp.money_of(c, true))])
		_:
			lines.append(_result_text(c))
	return "\n".join(lines)


func _result_text(c: Dictionary) -> String:
	match c["result"]:
		"player":
			return "人的補償：%s（＋金銭%s）" % [GameState.league.names.get(c["player"], c["player"]),
				Salary.text(c["amount"])]
		"pick":
			return "%sの%d巡目の指名権" % [GameData.short_name(c["to"]), c["round"]]
		"money":
			return "金銭%s" % Salary.text(c["amount"])
	return "補償なし（%s）" % c["reason"] if not str(c["reason"]).is_empty() else ""


func _rule_text(comp: FaCompensation) -> String:
	var at_year := comp.year if comp != null else GameState.year
	var r := FaCompensation.rule(at_year)
	var lines: Array[String] = ["%d年オフのルール" % at_year]
	lines.append("ランク：旧球団の日本人選手の年俸 A＝1〜%d位、B＝%d〜%d位、C＝補償なし" % [r["a_max"],
		int(r["a_max"]) + 1, r["b_max"]])
	if r["kind"] == "pick":
		lines.append("指名権（A＝2巡目、B＝3巡目）か金銭（A %d%%・B %d%%）。人的補償なし" % [
			roundi(r["money_only"]["A"] * 100), roundi(r["money_only"]["B"] * 100)])
	else:
		lines.append("人的補償＋金銭（A %d%%・B %d%%）か金銭のみ（A %d%%・B %d%%）。プロテクト%d人" % [
			roundi(r["with_player"]["A"] * 100), roundi(r["with_player"]["B"] * 100),
			roundi(r["money_only"]["A"] * 100), roundi(r["money_only"]["B"] * 100), FaCompensation.PROTECT])
	if int(r["age_limit"]) > 0:
		lines.append("%d歳以上の選手の移籍は補償なし" % r["age_limit"])
	return "\n".join(lines)


# --- タブと一覧 ---------------------------------------------------------------------------

func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiTheme.small_label("◀ LB", 18, UiTheme.TEXT, 800))
	for t: Array in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(220, 46)
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


func _tab_index() -> int:
	for i in TABS.size():
		if TABS[i][0] == _tab:
			return i
	return 0


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
	var c := _case()
	var players_title := "選手"
	if not c.is_empty() and c["state"] == "protect":
		players_title = "プロテクト（%d/%d）" % [_protect.size(), FaCompensation.PROTECT]
	elif not c.is_empty() and c["state"] == "choose" and c["kind"] == "player":
		players_title = "相手のプロテクト外"
	(_tab_buttons["players"] as Button).text = players_title
	_count_label.text = "%d%s" % [_ids.size(), "件" if _tab == "cases" else "人"]


func _case() -> Dictionary:
	var comp := GameState.comp()
	if comp == null or _index < 0 or _index >= comp.cases.size():
		return {}
	return comp.cases[_index]


func _render_list(comp: FaCompensation) -> void:
	for ch in _grid.get_children():
		_grid.remove_child(ch)
		ch.queue_free()
	_tags.clear()
	_ids.clear()
	if comp == null:
		_grid.add_child(UiTheme.small_label("FAの補償は、オフの「FA・トレード・ポスティング」でFAを締め切ったあとに決めます。",
			18, UiTheme.TEXT, 700))
		return
	if _tab == "cases":
		for i in comp.cases.size():
			var c: Dictionary = comp.cases[i]
			_ids.append(c["id"])
			_grid.add_child(_case_tile(c, i))
		if comp.cases.is_empty():
			_grid.add_child(UiTheme.small_label("今オフはFAで球団を移った選手がいません。", 18, UiTheme.TEXT, 700))
		return
	var c := _case()
	if c.is_empty() or c["state"] == "done" or c["kind"] == "pick":
		_grid.add_child(UiTheme.small_label("選ぶ選手はありません（補償の一覧から、自球団が決める補償を選んでください）。",
			18, UiTheme.TEXT, 700))
		return
	_ids = comp.protectable(GameState.league, c) if c["state"] == "protect" else comp.unprotected(GameState.league, c)
	var value := {}
	for id in _ids:
		value[id] = GameState.league.keep_score(id, comp.year + 1)
	_ids.sort_custom(func(a: String, b: String) -> bool: return value[a] > value[b])
	for id in _ids:
		_grid.add_child(_player_tile(id, id in _protect or id == _pick))


func _case_tile(c: Dictionary, index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(TILE_WIDTH, 0)
	var tag := NameTag.new()
	tag.custom_minimum_size = TAG_SIZE
	tag.setup_player(GameData.player(c["id"]), NameTag.family_name(str(c["name"])))
	tag.selected = index == _index
	tag.pressed.connect(func() -> void: select_case(index))
	row.add_child(tag)
	_tags[c["id"]] = tag
	var text := "%s %s→%s" % [c["rank"], GameData.short_name(c["from"]).substr(0, 2),
		GameData.short_name(c["to"]).substr(0, 2)]
	row.add_child(UiTheme.fit_label(UiTheme.small_label(text, 16, UiTheme.TEXT, 800)))
	var mark := "要決定" if c["state"] != "done" else _short_result(c)
	var badge := Label.new()
	badge.text = mark
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_font_override("font", UiTheme.font(800))
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_stylebox_override("normal", UiTheme.gloss(Color("e8413c") if c["state"] != "done" \
		else Color("8a9199"), 5, 1, 1))
	row.add_child(badge)
	return row


func _short_result(c: Dictionary) -> String:
	match c["result"]:
		"player":
			return "人的"
		"pick":
			return "指名権"
		"money":
			return "金銭"
	return "なし"


func _player_tile(id: String, chosen: bool) -> Control:
	var p := GameData.player(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(TILE_WIDTH, 0)
	var tag := NameTag.new()
	tag.custom_minimum_size = TAG_SIZE
	tag.setup_player(p, NameTag.family_name(str(p.get("name", id))))
	tag.selected = chosen
	tag.pressed.connect(_on_tag_pressed.bind(id))
	row.add_child(tag)
	_tags[id] = tag
	var age := FreeAgency.age_of(p, GameState.year + 1)
	var text := "%s %s %s" % [POS_SHORT.get(p.get("primary_pos"), "-"), ("%d歳" % age) if age > 0 else "",
		Salary.text(GameState.league.salary_of(id))]
	row.add_child(UiTheme.fit_label(UiTheme.small_label(text, 16, UiTheme.TEXT, 800)))
	return row


func _render_status(comp: FaCompensation) -> void:
	if not _message.is_empty():
		_status_label.text = _message
	elif comp == null:
		_status_label.text = ""
	else:
		var left := comp.pending().size()
		_status_label.text = "FAの移籍 %d件の補償。自球団が決める補償：残り%d件。" % [comp.cases.size(), left] \
			+ ("可変ボタンで次へ進むと、残りはおまかせで決まります。" if left > 0 else "可変ボタンで契約更改へ進みます。")
	_all_button.disabled = comp == null or comp.pending().is_empty()
	message_changed.emit(_status_label.text)


# --- 操作 --------------------------------------------------------------------------------

func _select_case(index: int) -> void:
	_index = index
	_pick = ""
	_protect.clear()
	var c := _case()
	if not c.is_empty():
		_protect.assign(c["protect"])


func _on_tag_pressed(id: String) -> void:
	var c := _case()
	if c.is_empty() or _tab != "players":
		return
	if c["state"] == "protect":
		if id in _protect:
			_protect.erase(id)
		elif _protect.size() >= FaCompensation.PROTECT:
			_message = "プロテクトは%d人までです。外す選手を先に選んでください。" % FaCompensation.PROTECT
		else:
			_protect.append(id)
	elif c["state"] == "choose":
		_pick = "" if _pick == id else id
	refresh()


func _on_action_pressed() -> void:
	var c := _case()
	if c.is_empty():
		return
	if c["state"] == "protect":
		var error := GameState.comp_protect(_index, _protect)
		if not error.is_empty():
			_message = error
			refresh()
			return
		GameState.comp_confirm(_index)
		_message = "プロテクトを確定しました。%s" % _result_text(c)
	elif c["state"] == "choose":
		var error := GameState.comp_choose(_index, "pick" if c["kind"] == "pick" else "player", _pick)
		_message = error if not error.is_empty() else "補償を決めました：%s" % _result_text(c)
	_after_change()


func _on_money_pressed() -> void:
	var c := _case()
	if c.is_empty() or c["state"] != "choose":
		return
	var error := GameState.comp_choose(_index, "money")
	_message = error if not error.is_empty() else "補償を決めました：%s" % _result_text(c)
	_after_change()


## おまかせ：プロテクトは残す価値の高い順に28人、旧球団の側は CPU と同じ考え方で選ぶ
func _on_auto_pressed() -> void:
	var comp := GameState.comp()
	var c := _case()
	if comp == null or c.is_empty():
		return
	if c["state"] == "protect":
		_protect.assign(comp.auto_protect(GameState.league, c))
		_message = "プロテクトをおまかせで選びました（確定はまだです）。"
		_shown_key = ""
		refresh()
		return
	if c["state"] == "choose":
		var best := ""
		if c["kind"] == "player":
			var best_value := -1.0
			for id in comp.unprotected(GameState.league, c):
				var v := Trade.player_value(GameData.player(id), comp.year + 1, GameState.league.salary_of(id))
				if v > best_value:
					best_value = v
					best = id
		if c["kind"] == "pick" or (not best.is_empty() and
				Trade.player_value(GameData.player(best), comp.year + 1, GameState.league.salary_of(best))
				>= FaCompensation.CPU_TAKE_VALUE):
			GameState.comp_choose(_index, c["kind"], best)
		else:
			GameState.comp_choose(_index, "money")
		_message = "おまかせで決めました：%s" % _result_text(c)
	_after_change()


func _on_all_pressed() -> void:
	GameState.comp_resolve()
	_message = "残りの補償をおまかせで決めました。"
	_index = -1
	_after_change()
	_show_tab("cases")


## 決めたあと：次の決める補償へ（無ければ一覧へ）
func _after_change() -> void:
	var comp := GameState.comp()
	var next := -1
	if comp != null:
		for i in comp.cases.size():
			if comp.cases[i]["state"] != "done":
				next = i
				break
	if next >= 0:
		_select_case(next)
	else:
		_tab = "cases"
	_shown_key = ""
	refresh()
	focus_first()
