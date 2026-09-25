class_name ScheduleView
extends Control
## 日程表画面（docs/references/README.md「schedule_pawapuro.webp」）。
##
## 年間の対戦日程生成・試合シミュレーションはまだ実装されていない
## （docs/SPEC.md「試合シミュレーション」、HANDOFF.md「次にやること」）。
## そのため表示するカードとスコアは実データではなく、現在の年月を起点に生成した仮データ。

const DAYS_SHOWN := 3
const DAY_SECONDS := 86400
const WEEKDAY_NAMES := ["日", "月", "火", "水", "木", "金", "土"]
const OFF_WEEKDAY := 1  ## 月曜は全カード移動日（参考画像どおり）

## 仮の本拠地球場（実データが無いため、見た目確認用の固定値）
const STADIUMS := {
	"読売ジャイアンツ": "東京ドーム",
	"阪神タイガース": "甲子園",
	"中日ドラゴンズ": "バンテリンドーム",
	"横浜ベイスターズ": "横浜スタジアム",
	"横浜DeNAベイスターズ": "横浜スタジアム",
	"広島東洋カープ": "マツダスタジアム",
	"東京ヤクルトスワローズ": "神宮球場",
	"埼玉西武ライオンズ": "ベルーナドーム",
	"オリックス・バファローズ": "京セラドーム",
	"福岡ソフトバンクホークス": "みずほPayPayドーム",
	"北海道日本ハムファイターズ": "エスコンフィールド",
	"千葉ロッテマリーンズ": "ZOZOマリン",
	"東北楽天ゴールデンイーグルス": "楽天モバイルパーク",
}

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


## ハブ画面から開かれるたびに呼ばれる。現在の年月を起点に表示位置をリセットする。
func refresh() -> void:
	_day_offset = 0
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
	_slider.max_value = _season_day_count()
	_slider.step = DAYS_SHOWN
	_slider.value_changed.connect(_on_slider_changed)
	root.add_child(_slider)


func _shift(delta: int) -> void:
	_day_offset = clampi(_day_offset + delta, 0, _season_day_count())
	_render()


func _on_slider_changed(value: float) -> void:
	var offset := int(value)
	if offset == _day_offset:
		return
	_day_offset = offset
	_render()


func _season_day_count() -> int:
	var months: Array = GameState.SEASON_MONTHS
	return months.size() * 30


func _season_start_unix() -> int:
	var dict := {
		"year": GameState.year, "month": GameState.SEASON_MONTHS[0], "day": 1,
		"hour": 12, "minute": 0, "second": 0,
	}
	return Time.get_unix_time_from_datetime_dict(dict)


## 開幕からの経過日数。現フェーズの月を起点に「消化済み／これから」の境目に使う。
func _elapsed_days() -> int:
	if GameState.phase != GameState.Phase.SEASON:
		return _season_day_count()
	var months: Array = GameState.SEASON_MONTHS
	var month_index := months.find(GameState.month)
	return maxi(month_index, 0) * 30


func _render() -> void:
	_slider.set_value_no_signal(_day_offset)
	_prev_button.disabled = _day_offset <= 0
	_next_button.disabled = _day_offset >= _season_day_count()

	var season_start := _season_start_unix()
	var elapsed := _elapsed_days()

	for child in _days_box.get_children():
		_days_box.remove_child(child)
		child.queue_free()
	var last_dt := {}
	for i in DAYS_SHOWN:
		var day_index := _day_offset + i
		var day_unix := season_start + day_index * DAY_SECONDS
		var finished := day_index < elapsed
		last_dt = Time.get_datetime_dict_from_unix_time(day_unix)
		_days_box.add_child(_make_day_column(day_unix, day_index, finished))

	var last_label := "%d月%d日（%s）" % [
		last_dt["month"], last_dt["day"], WEEKDAY_NAMES[last_dt["weekday"]]]
	_status_label.text = "%s 終了まで早送り中" % last_label
	_progress.value = 100.0 * (_day_offset + DAYS_SHOWN) / _season_day_count()

	_standings.refresh()


func _make_day_column(day_unix: int, day_index: int, finished: bool) -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(140, 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)

	var dt := Time.get_datetime_dict_from_unix_time(day_unix)
	var weekday: int = dt["weekday"]

	var header := Label.new()
	header.text = "%d月%d日（%s）" % [dt["month"], dt["day"], WEEKDAY_NAMES[weekday]]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", _palette.on_main)
	header.add_theme_font_override("font", UiTheme.font(800))
	header.add_theme_font_size_override("font_size", 18)
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", UiTheme.box(_palette.main, 8))
	header_panel.add_child(header)
	column.add_child(header_panel)

	if weekday == OFF_WEEKDAY:
		var rest_panel := PanelContainer.new()
		rest_panel.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.8), 8))
		rest_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var rest_label := Label.new()
		rest_label.text = "移動日"
		rest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rest_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rest_label.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
		rest_label.add_theme_font_override("font", UiTheme.font(800))
		rest_label.add_theme_font_size_override("font_size", 26)
		rest_panel.add_child(rest_label)
		column.add_child(rest_panel)
		return column

	for pair: Array in _pairings_for(day_index):
		column.add_child(_make_game_tile(pair[0], pair[1], day_unix, finished))
	return column


## 円卓法（circle method）で日ごとの組み合わせを作る仮のペアリング。
## リーグ内総当たりの雰囲気を出すためだけの仮ロジックで、実際の年間日程ではない。
func _pairings_for(day_index: int) -> Array:
	var pairs: Array = []
	for league in ["C", "P"]:
		var teams: Array = GameData.teams(league)
		if teams.size() < 2:
			continue
		pairs.append_array(_round_robin_pairs(teams, day_index))
	return pairs


func _round_robin_pairs(teams: Array, round_index: int) -> Array:
	var n := teams.size()
	var rotating: Array = teams.slice(1)
	var r := round_index % maxi(n - 1, 1)
	for i in r:
		rotating.push_back(rotating.pop_front())
	var order: Array = [teams[0]]
	order.append_array(rotating)
	var pairs: Array = []
	for i in n / 2:
		pairs.append([order[i], order[n - 1 - i]])
	return pairs


func _make_game_tile(home: String, away: String, day_unix: int, finished: bool) -> PanelContainer:
	var is_own_game := home == GameState.team or away == GameState.team
	var tile := PanelContainer.new()
	var style: StyleBoxFlat
	if finished:
		style = UiTheme.box(Color("3d434c"), 8)
	else:
		style = UiTheme.box(Color(1, 1, 1, 0.95), 8, Color("d5dae0"), 1)
	if is_own_game:
		style.border_color = _palette.main
		style.set_border_width_all(3)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	tile.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	tile.add_child(box)
	box.add_child(_make_matchup_row(home, away))

	var mid_label := Label.new()
	mid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid_label.clip_text = true
	mid_label.add_theme_font_size_override("font_size", 20)
	mid_label.add_theme_font_override("font", UiTheme.font(800))
	if finished:
		var seed := hash("%s-%s-%d" % [home, away, day_unix])
		var home_score := seed % 8
		var away_score := (seed / 8) % 8
		if home_score == away_score:
			home_score += 1
		mid_label.text = "%d － %d" % [away_score, home_score]
		mid_label.add_theme_color_override("font_color", Color.WHITE)
	else:
		mid_label.text = STADIUMS.get(home, "-")
		mid_label.add_theme_font_size_override("font_size", 14)
		mid_label.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
	box.add_child(mid_label)

	if finished:
		var stadium_label := Label.new()
		stadium_label.text = STADIUMS.get(home, "-")
		stadium_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stadium_label.clip_text = true
		stadium_label.add_theme_font_size_override("font_size", 12)
		stadium_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
		box.add_child(stadium_label)

	return tile


func _make_matchup_row(home: String, away: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_make_team_chip(away))
	row.add_child(_make_team_chip(home))
	return row


func _make_team_chip(team: String) -> PanelContainer:
	var colors: Array[Color] = GameData.team_colors(team)
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UiTheme.box(colors[0], 6)
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 2
	style.content_margin_bottom = 2
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
