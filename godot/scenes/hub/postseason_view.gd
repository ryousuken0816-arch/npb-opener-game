class_name PostseasonView
extends VBoxContainer
## ポストシーズン（CS・日本シリーズ）の画面（ハブ。ポストシーズンの段階の可変ボタン・日程表から。広げて表示）。
##
## 上に今日の日付と次の試合、進めるボタン（次の試合へ（移動日は飛ばす）／この段階を最後まで（1日ずつ早送り）／日本一まで一気に）。
## 下に3列：セのCS（ファースト・ファイナル）／日本シリーズ／パのCS。各シリーズは両球団の勝ち数（アドバンテージ込み）と
## 1試合ずつの結果（未試合は日付）。日本一が決まると「表彰へ」（advance_requested → ハブの可変ボタンと同じ）。
## 早送り中はⒷ（ハブの「戻る」）で中止。

signal advance_requested
signal message_changed(text: String)

const COLUMN_WIDTH := 368.0
const CHIP_SIZE := Vector2(84, 40)
const WIN_COLOR := Color("e0a400")

var _palette: UiTheme.Palette
var _status: Label
var _day_button: Button
var _round_button: Button
var _all_button: Button
var _awards_button: Button
var _columns: HBoxContainer


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	add_theme_constant_override("separation", 10)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	add_child(top)
	_status = UiTheme.small_label("", 19, UiTheme.TEXT, 800)
	UiTheme.fit_label(_status)
	top.add_child(_status)
	_day_button = _button("次の試合へ", Color("e84393"), func() -> void:
		var ps := GameState.postseason
		if ps != null:
			GameState.start_fast_forward(ps.next_game_day(GameState.day)))
	top.add_child(_day_button)
	_round_button = _button("この段階を最後まで", Color("e53935"), func() -> void:
		var ps := GameState.postseason
		if ps != null:
			GameState.start_fast_forward(ps.round_last_day(ps.current_round())))
	top.add_child(_round_button)
	_all_button = _button("日本一まで一気に", Color("7e57c2"), func() -> void:
		GameState.postseason_play_all())
	top.add_child(_all_button)
	_awards_button = _button("表彰へ", Color("e0a400"), func() -> void: advance_requested.emit())
	top.add_child(_awards_button)
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 12)
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_columns)


func _button(text: String, color: Color, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	UiTheme.style_button(b, color)
	b.pressed.connect(action)
	return b


func open() -> void:
	refresh()
	focus_first()


func focus_first() -> void:
	for b: Button in [_day_button, _awards_button]:
		if b.visible and not b.disabled:
			UiInput.grab(b)
			return


func refresh() -> void:
	var ps := GameState.postseason
	var done := GameState.postseason_done()
	var ff := GameState.is_fast_forwarding()
	_day_button.visible = not done
	_round_button.visible = not done
	_all_button.visible = not done
	_awards_button.visible = done and GameState.phase == GameState.Phase.POSTSEASON
	for b: Button in [_day_button, _round_button, _all_button]:
		b.disabled = ff or GameState.phase != GameState.Phase.POSTSEASON
	_status.text = _status_text(ps)
	message_changed.emit(_message(ps))
	for c in _columns.get_children():
		_columns.remove_child(c)
		c.queue_free()
	if ps == null:
		return
	_columns.add_child(_league_column(ps, "C"))
	_columns.add_child(_js_column(ps))
	_columns.add_child(_league_column(ps, "P"))
	if done and _awards_button.visible and not _awards_button.has_focus() and is_visible_in_tree():
		UiInput.grab(_awards_button)


func _status_text(ps: Postseason) -> String:
	if ps == null:
		return "ポストシーズンはありません"
	if ps.is_finished():
		var js := ps.get_series("JS")
		return "%d年 日本一：%s（%s）" % [ps.year, GameData.short_name(ps.champion), Postseason.score_text(js)]
	var today := ps.games_on(GameState.day)
	var parts: Array[String] = []
	for e: Dictionary in today:
		var s: Dictionary = e["series"]
		if not s["winner"].is_empty() or s["low"].is_empty():
			continue
		var g: Dictionary = e["game"]
		parts.append("%s第%d戦 %s−%s" % [_short_stage(s), g["no"], GameData.short_name(g["away"]),
			GameData.short_name(g["home"])])
	var head := Season.day_label(GameState.day)
	if parts.is_empty():
		return head + "　試合なし（移動日）"
	return head + "　" + "　".join(parts)


func _message(ps: Postseason) -> String:
	if ps == null:
		return ""
	if ps.is_finished():
		return "日本シリーズが終わりました。「表彰へ」でシーズン終了・表彰へ進みます。"
	var mine := GameState.team
	if ps.team_alive(mine):
		return "%sは勝ち残っています。1日ずつ、または段階ごとに進めます（早送り中はⒷで中止）。" % GameData.short_name(mine)
	return "%sはポストシーズンに出ていません（敗退）。「日本一まで一気に」で飛ばせます。" % GameData.short_name(mine)


static func _short_stage(s: Dictionary) -> String:
	match s["stage"]:
		"first":
			return "%sCS1st " % ("セ" if s["league"] == "C" else "パ")
		"final", "final2020":
			return "%sCSファイナル " % ("セ" if s["league"] == "C" else "パ")
	return "日本シリーズ"


func _league_column(ps: Postseason, lg: String) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = COLUMN_WIDTH
	col.add_theme_constant_override("separation", 6)
	var lg_color := Color("1e88e5") if lg == "C" else Color("2e7d32")
	var title_panel := PanelContainer.new()
	var style := UiTheme.gloss(lg_color, 6, 2, 2)
	style.content_margin_top = 3
	style.content_margin_bottom = 3 + style.depth
	style.content_margin_left = 8
	style.content_margin_right = 8
	title_panel.add_theme_stylebox_override("panel", style)
	var title := Label.new()
	title.text = "%s クライマックスシリーズ" % GameData.LEAGUE_NAMES.get(lg, "")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(title, 19, Color.WHITE, lg_color.darkened(0.5), 5, false)
	title_panel.add_child(title)
	col.add_child(title_panel)
	var any := false
	for s in ps.series:
		if s["league"] == lg:
			col.add_child(_series_card(s, false))
			any = true
	if not any:
		var note := UiTheme.small_label("この年の%sはCSなし（優勝球団がそのまま日本シリーズへ）" %
			GameData.LEAGUE_NAMES.get(lg, ""), 15, UiTheme.TEXT_SUB, 700)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(note)
	_standings_note(col, ps, lg)
	return col


## 公式戦の最終順位（上位3球団）
func _standings_note(col: VBoxContainer, ps: Postseason, lg: String) -> void:
	var names: Array = ps.order.get(lg, [])
	var parts: Array[String] = []
	for i in mini(3, names.size()):
		parts.append("%d位 %s" % [i + 1, GameData.short_name(names[i])])
	var note := UiTheme.small_label("公式戦：" + "　".join(parts), 14, UiTheme.TEXT_SUB, 700)
	col.add_child(note)


func _js_column(ps: Postseason) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = COLUMN_WIDTH
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "日本シリーズ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(title, 24, WIN_COLOR.darkened(0.2), Color.WHITE, 7)
	col.add_child(title)
	var js := ps.get_series("JS")
	if not js.is_empty():
		col.add_child(_series_card(js, true))
		var mvp := Postseason.series_mvp(js)
		if not mvp.is_empty():
			var p := GameData.player(mvp["id"])
			var label := UiTheme.small_label("日本シリーズMVP：%s（%s）\n%s" % [p.get("name", mvp["id"]),
				GameData.short_name(js["winner"]), mvp["text"]], 16, UiTheme.TEXT, 800)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(label)
	return col


func _series_card(s: Dictionary, big: bool) -> Control:
	var panel := PanelContainer.new()
	var decided: bool = not s["winner"].is_empty()
	var style := UiTheme.card(WIN_COLOR if decided else _palette.main, 10, 3 if decided else 2)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var head := UiTheme.small_label(s["name"] + ("（%d勝で勝ち抜け）" % s["need"]), 15, UiTheme.TEXT_SUB, 800)
	box.add_child(head)
	for team: String in [s["high"], s["low"]]:
		box.add_child(_team_row(s, team, big))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 4)
	chips.add_theme_constant_override("v_separation", 4)
	for g: Dictionary in s["games"]:
		chips.add_child(_game_chip(s, g))
	box.add_child(chips)
	return panel


func _team_row(s: Dictionary, team: String, big: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var tag := PanelContainer.new()
	var name_label := Label.new()
	name_label.custom_minimum_size.x = 150 if big else 120
	if team.is_empty():
		tag.add_theme_stylebox_override("panel", UiTheme.box(Color("e3e6ea"), 6))
		name_label.text = "（未定）"
		name_label.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
	else:
		var colors := GameData.team_colors(team)
		tag.add_theme_stylebox_override("panel", UiTheme.gloss(colors[0], 6, 2, 2, colors[1]))
		name_label.text = GameData.short_name(team)
		name_label.add_theme_color_override("font_color", UiTheme.text_on(colors[0]))
	name_label.add_theme_font_override("font", UiTheme.font(800))
	name_label.add_theme_font_size_override("font_size", 22 if big else 17)
	tag.add_child(name_label)
	row.add_child(tag)
	var wins := Label.new()
	var adv := int(s["adv"]) if team == s["high"] and not team.is_empty() else 0
	wins.text = "%d勝" % Postseason.wins_of(s, team) if not team.is_empty() else ""
	if adv > 0:
		wins.text += "（AD%d）" % adv
	var color := UiTheme.TEXT
	if not s["winner"].is_empty():
		color = WIN_COLOR.darkened(0.25) if team == s["winner"] else UiTheme.TEXT_SUB
	UiTheme.heading(wins, 24 if big else 20, color, Color.WHITE, 5, false)
	row.add_child(wins)
	if team == s["winner"] and not team.is_empty():
		var badge := UiTheme.small_label("日本一！" if s["stage"] == "js" else "勝ち抜け", 16, WIN_COLOR.darkened(0.3), 800)
		row.add_child(badge)
	if team == GameState.team:
		var own_badge := PanelContainer.new()
		var ob_style := UiTheme.box(_palette.main, 4)
		ob_style.content_margin_left = 6
		ob_style.content_margin_right = 6
		ob_style.content_margin_top = 1
		ob_style.content_margin_bottom = 1
		own_badge.add_theme_stylebox_override("panel", ob_style)
		var own_lbl := Label.new()
		own_lbl.text = "自球団"
		UiTheme.heading(own_lbl, 13, _palette.on_main, _palette.main.darkened(0.4), 4, false)
		own_badge.add_child(own_lbl)
		row.add_child(own_badge)
	return row


func _game_chip(s: Dictionary, g: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = CHIP_SIZE
	var res: Dictionary = g["result"]
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UiTheme.font(700))
	label.add_theme_font_size_override("font_size", 12)
	var today: bool = g["day"] == GameState.day and res.is_empty()
	var bg := Color("f4f6f8")
	if res.is_empty():
		var date := Season.date_of_day(g["day"])
		label.text = "第%d戦\n%d/%d" % [g["no"], int(date.substr(5, 2)), int(date.substr(8, 2))]
		label.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
		if today:
			bg = Color("fff1c9")
	else:
		var hs: int = res["home_score"]
		var aws: int = res["away_score"]
		label.text = "第%d戦\n%s%d-%d%s" % [g["no"], _abbr(g["away"]), aws, hs, _abbr(g["home"])]
		label.add_theme_color_override("font_color", UiTheme.TEXT)
		var mine := GameState.team
		if mine in [g["home"], g["away"]] and hs != aws:
			var won: bool = (hs > aws) == (g["home"] == mine)
			bg = Color("ffe0e0") if won else Color("e0ebff")
	panel.add_theme_stylebox_override("panel", UiTheme.box(bg, 6, UiTheme.LINE, 1))
	panel.tooltip_text = "%s 第%d戦　%s　%s" % [s["name"], g["no"], Season.day_label(g["day"]), g["venue"]]
	panel.add_child(label)
	return panel


## 球団の1文字の略（巨・神・中…）。チップの中を短くする
static func _abbr(team: String) -> String:
	var short := GameData.short_name(team)
	match short:
		"ソフトバンク":
			return "ソ"
		"日本ハム":
			return "日"
		"ヤクルト":
			return "ヤ"
		"オリックス":
			return "オ"
		"DeNA":
			return "デ"
		"阪神":
			return "神"
		"西武":
			return "西"
		"巨人":
			return "巨"
	return short.substr(0, 1)
