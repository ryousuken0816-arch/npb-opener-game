class_name ScheduleView
extends Control
## 日程表画面（docs/references/README.md「schedule_pawapuro.webp」）。
##
## 史実の日程（GameState.season）を3日分ずつ、その日の全カードのタイルで表示する。
## 終了した試合は暗色＋スコア（ツールチップに勝敗投手）、雨天中止は「中止」、試合のない日は「試合なし」。
## 開いたときは最後に試合をした日から3日間を表示する。

const DAYS_SHOWN := 3
const WEEKDAY_NAMES := ["日", "月", "火", "水", "木", "金", "土"]
const MONDAY := 1

var _palette: UiTheme.Palette
var _day_offset := 0

var _status_label: Label
var _status_bar: PanelContainer
var _days_box: HBoxContainer
var _standings: StandingsPanel
var _progress: ProgressBar
var _slider: HSlider
var _prev_button: Button
var _next_button: Button


func _ready() -> void:
	_build_layout()


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	var bar_style := UiTheme.box(p.main, 8)
	bar_style.content_margin_top = 6
	bar_style.content_margin_bottom = 6
	_status_bar.add_theme_stylebox_override("panel", bar_style)
	_status_label.add_theme_color_override("font_color", p.on_main)
	_status_label.add_theme_font_override("font", UiTheme.font(800))
	_status_label.add_theme_font_size_override("font_size", 20)
	_standings.setup(p, GameData.league_of(GameState.team))
	for b: Button in [_prev_button, _next_button]:
		b.add_theme_font_override("font", UiTheme.font(700))


## ハブ画面から開かれるたびに呼ばれる。最後に試合をした日の付近を表示する。
func refresh() -> void:
	_slider.max_value = maxi(_season_day_count() - DAYS_SHOWN, 0)
	_day_offset = clampi(_anchor_offset(), 0, maxi(_season_day_count() - DAYS_SHOWN, 0))
	_render()


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	_status_bar = PanelContainer.new()
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_bar.add_child(_status_label)
	root.add_child(_status_bar)

	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 8)
	_progress.show_percentage = false
	root.add_child(_progress)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	var days_area := VBoxContainer.new()
	days_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	days_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	days_area.add_theme_constant_override("separation", 8)
	body.add_child(days_area)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	_prev_button = Button.new()
	_prev_button.text = "◀ 前の3日間"
	_prev_button.focus_mode = Control.FOCUS_NONE
	_prev_button.pressed.connect(_shift.bind(-DAYS_SHOWN))
	nav.add_child(_prev_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	_next_button = Button.new()
	_next_button.text = "次の3日間 ▶"
	_next_button.focus_mode = Control.FOCUS_NONE
	_next_button.pressed.connect(_shift.bind(DAYS_SHOWN))
	nav.add_child(_next_button)
	days_area.add_child(nav)

	var days_scroll := ScrollContainer.new()
	days_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	days_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	days_area.add_child(days_scroll)
	_days_box = HBoxContainer.new()
	_days_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_days_box.add_theme_constant_override("separation", 8)
	days_scroll.add_child(_days_box)

	_standings = StandingsPanel.new()
	_standings.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(_standings)

	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.step = 1
	_slider.value_changed.connect(_on_slider_changed)
	root.add_child(_slider)


func _shift(delta: int) -> void:
	_day_offset = clampi(_day_offset + delta, 0, maxi(_season_day_count() - DAYS_SHOWN, 0))
	_render()


func _on_slider_changed(value: float) -> void:
	var offset := int(value)
	if offset == _day_offset:
		return
	_day_offset = offset
	_render()


## 開幕日から最終日までの日数（日程データが無ければ 0）
func _season_day_count() -> int:
	var season := GameState.season
	if season == null or season.games.is_empty():
		return 0
	return season.last_day() - season.first_day() + 1


## 開いたときに表示する位置（開幕日からの日数）：最後に試合をした日。開幕前は開幕日
func _anchor_offset() -> int:
	var season := GameState.season
	if season == null or season.games.is_empty():
		return 0
	var last_date := season.last_played_date()
	if last_date.is_empty():
		return 0
	return Season.day_number(last_date) - season.first_day()


func _render() -> void:
	for child in _days_box.get_children():
		_days_box.remove_child(child)
		child.queue_free()
	_standings.refresh()
	var season := GameState.season
	if season == null or season.games.is_empty():
		_status_label.text = "%d年の日程データがありません" % GameState.year
		_progress.value = 0
		_prev_button.disabled = true
		_next_button.disabled = true
		return

	_slider.set_value_no_signal(_day_offset)
	var max_offset := maxi(_season_day_count() - DAYS_SHOWN, 0)
	_prev_button.disabled = _day_offset <= 0
	_next_button.disabled = _day_offset >= max_offset
	for i in DAYS_SHOWN:
		var day := season.first_day() + _day_offset + i
		if day > season.last_day():
			break
		_days_box.add_child(_make_day_column(day))

	var last_date := season.last_played_date()
	if season.is_finished():
		_status_label.text = "全日程終了（%d試合）" % season.played_count()
	elif last_date.is_empty():
		_status_label.text = "開幕前　%s 開幕" % _date_label(season.first_day())
	else:
		_status_label.text = "%s までの試合が終了" % _date_label(Season.day_number(last_date))
	_progress.value = 100.0 * season.played_count() / maxi(season.scheduled_count(), 1)


func _date_label(day: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(day * Season.DAY_SECONDS + Season.DAY_SECONDS / 2)
	return "%d月%d日（%s）" % [dt["month"], dt["day"], WEEKDAY_NAMES[dt["weekday"]]]


func _make_day_column(day: int) -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(145, 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = _date_label(day)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.clip_text = true
	header.add_theme_color_override("font_color", _palette.on_main)
	header.add_theme_font_override("font", UiTheme.font(800))
	# 「10月10日（金）」など長い日付は列に収まるよう小さくする
	header.add_theme_font_size_override("font_size", 18 if header.text.length() <= 8 else 16)
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", UiTheme.box(_palette.main, 8))
	header_panel.add_child(header)
	column.add_child(header_panel)

	var games: Array = GameState.season.games_on(Season.date_of_day(day))
	if games.is_empty():
		var rest_panel := PanelContainer.new()
		rest_panel.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.8), 8))
		rest_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var rest_label := Label.new()
		var weekday: int = Time.get_datetime_dict_from_unix_time(day * Season.DAY_SECONDS)["weekday"]
		rest_label.text = "移動日" if weekday == MONDAY else "試合なし"
		rest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rest_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rest_label.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
		rest_label.add_theme_font_override("font", UiTheme.font(800))
		rest_label.add_theme_font_size_override("font_size", 26)
		rest_panel.add_child(rest_label)
		column.add_child(rest_panel)
		return column

	# セ・パの試合を左右の列に分け、その日の全カードがスクロールなしで見えるようにする。
	# 交流戦の日は主催が片方のリーグに偏るので、半分ずつに分ける
	var columns := {"C": [], "P": []}
	var titles := {}
	var interleague := games.any(func(g: Dictionary) -> bool: return g["kind"] == "interleague")
	if interleague:
		var half := ceili(games.size() / 2.0)
		columns = {"C": games.slice(0, half), "P": games.slice(half)}
		titles = {"C": "交流戦", "P": ""}
	else:
		for g: Dictionary in games:
			columns[GameState.season.leagues.get(g["home"], "C")].append(g)
		for league: String in columns:
			titles[league] = GameData.LEAGUE_NAMES.get(league, league).left(1)
	var leagues_row := HBoxContainer.new()
	leagues_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	leagues_row.add_theme_constant_override("separation", 4)
	column.add_child(leagues_row)
	for league in ["C", "P"]:
		leagues_row.add_child(_make_league_column(titles[league], columns[league]))
	return column


func _make_league_column(title: String, games: Array) -> VBoxContainer:
	var league_col := VBoxContainer.new()
	league_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	league_col.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_font_override("font", UiTheme.font(700))
	label.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
	label.custom_minimum_size.y = 14
	league_col.add_child(label)
	for g: Dictionary in games:
		league_col.add_child(_make_game_tile(g))
	return league_col


func _make_game_tile(g: Dictionary) -> PanelContainer:
	var home: String = g["home"]
	var away: String = g["away"]
	var result: Dictionary = g["result"]
	var finished := not result.is_empty()
	var canceled: bool = g["status"] != "played"
	var is_own_game := home == GameState.team or away == GameState.team
	var tile := PanelContainer.new()
	var style: StyleBoxFlat
	if finished:
		style = UiTheme.box(Color("3d434c"), 8)
	elif canceled:
		style = UiTheme.box(Color("e3e6ea"), 8, Color("d5dae0"), 1)
	else:
		style = UiTheme.box(Color(1, 1, 1, 0.95), 8, Color("d5dae0"), 1)
	if is_own_game:
		style.border_color = _palette.main
		style.set_border_width_all(3)
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 1
	style.content_margin_bottom = 0
	tile.add_theme_stylebox_override("panel", style)
	if finished:
		tile.tooltip_text = _result_tooltip(g)

	# 縦積み（アウェイ→中央→ホーム）にして、列を細くしても読めるようにする
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	tile.add_child(box)
	box.add_child(_make_team_chip(away))

	var mid_label := Label.new()
	mid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid_label.clip_text = true
	mid_label.add_theme_font_size_override("font_size", 12)
	mid_label.add_theme_font_override("font", UiTheme.font(800))
	if finished:
		mid_label.text = "%d－%d" % [result["away_score"], result["home_score"]]
		mid_label.add_theme_color_override("font_color", Color.WHITE)
	elif canceled:
		mid_label.text = "中止"
		mid_label.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
	else:
		mid_label.text = "vs"
		mid_label.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
	box.add_child(mid_label)
	box.add_child(_make_team_chip(home))

	var stadium_label := Label.new()
	stadium_label.text = g["venue"] if not str(g["venue"]).is_empty() else "-"
	stadium_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stadium_label.clip_text = true
	stadium_label.add_theme_font_size_override("font_size", 9)
	stadium_label.add_theme_color_override(
			"font_color", Color(1, 1, 1, 0.75) if finished else UiTheme.TEXT_SUB)
	box.add_child(stadium_label)

	return tile


## 終了した試合のツールチップ（スコアと勝敗・セーブ投手）
func _result_tooltip(g: Dictionary) -> String:
	var result: Dictionary = g["result"]
	var season := GameState.season
	var lines := PackedStringArray()
	lines.append("%s %d－%d %s%s" % [
		GameData.short_name(g["away"]), result["away_score"], result["home_score"],
		GameData.short_name(g["home"]), "（延長%d回）" % result["innings"] if result["innings"] > 9 else ""])
	if result["win"].is_empty():
		lines.append("引き分け")
	else:
		lines.append("勝：%s　敗：%s" % [
			season.player_name(result["win"]), season.player_name(result["lose"])])
		if not result["save"].is_empty():
			lines.append("S：%s" % season.player_name(result["save"]))
	return "\n".join(lines)


func _make_team_chip(team: String) -> PanelContainer:
	var colors: Array[Color] = GameData.team_colors(team)
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UiTheme.box(colors[0], 6)
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	chip.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	var short_name := GameData.short_name(team)
	label.text = short_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 13 if short_name.length() <= 3 else 10)
	label.add_theme_font_override("font", UiTheme.font(700))
	label.add_theme_color_override("font_color", UiTheme.text_on(colors[0]))
	chip.add_child(label)
	return chip
