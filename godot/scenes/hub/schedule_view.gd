class_name ScheduleView
extends Control
## 日程表画面（見た目のモックアップ）。
##
## 年間の対戦日程生成・試合シミュレーションはまだ実装されていない
## （docs/SPEC.md「試合シミュレーション」、HANDOFF.md 次にやること）。
## そのため表示するカードは実データではなく、現在の年月を起点に生成した仮のカード。
## 見た目は docs/references/README.md「schedule_pawapuro.webp」に合わせる。

const DAYS_SHOWN := 3
const DAY_SECONDS := 86400
const WEEKDAY_NAMES := ["日", "月", "火", "水", "木", "金", "土"]

var _day_offset := 0

var _range_label: Label
var _days_box: HBoxContainer
var _standings_box: HBoxContainer
var _progress: ProgressBar


func _ready() -> void:
	_build_layout()


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	var prev_button := Button.new()
	prev_button.text = "◀ 前へ"
	prev_button.pressed.connect(_shift.bind(-DAYS_SHOWN))
	nav.add_child(prev_button)
	_range_label = Label.new()
	_range_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_range_label.add_theme_font_size_override("font_size", 20)
	nav.add_child(_range_label)
	var next_button := Button.new()
	next_button.text = "次へ ▶"
	next_button.pressed.connect(_shift.bind(DAYS_SHOWN))
	nav.add_child(next_button)
	root.add_child(nav)

	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 10)
	_progress.show_percentage = false
	root.add_child(_progress)

	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	root.add_child(body)

	_days_box = HBoxContainer.new()
	_days_box.size_flags_horizontal = SIZE_EXPAND_FILL
	_days_box.size_flags_vertical = SIZE_EXPAND_FILL
	_days_box.add_theme_constant_override("separation", 8)
	body.add_child(_days_box)

	_standings_box = HBoxContainer.new()
	_standings_box.custom_minimum_size = Vector2(320, 0)
	_standings_box.add_theme_constant_override("separation", 8)
	body.add_child(_standings_box)


func refresh() -> void:
	_render()


func _shift(delta: int) -> void:
	_day_offset += delta
	_render()


func _render() -> void:
	var team_color := GameData.team_color(GameState.team)
	var base_unix := _base_unix_time()

	for child in _days_box.get_children():
		child.queue_free()
	for i in DAYS_SHOWN:
		var day_unix: int = base_unix + (_day_offset + i) * DAY_SECONDS
		var finished := i < DAYS_SHOWN - 1  # 直近2日を消化済み扱い、最終日を「これから」扱いにする（表示確認用）
		_days_box.add_child(_make_day_column(day_unix, finished, team_color))

	var last_unix := base_unix + (_day_offset + DAYS_SHOWN - 1) * DAY_SECONDS
	var first := Time.get_datetime_dict_from_unix_time(base_unix + _day_offset * DAY_SECONDS)
	var last := Time.get_datetime_dict_from_unix_time(last_unix)
	_range_label.text = "%d月%d日 〜 %d月%d日" % [first["month"], first["day"], last["month"], last["day"]]

	var season_months: Array = GameState.SEASON_MONTHS
	var month_index := season_months.find(GameState.month)
	_progress.value = 100.0 * (max(month_index, 0) + 1) / season_months.size()

	_render_standings()


func _base_unix_time() -> int:
	var in_season := GameState.phase == GameState.Phase.SEASON
	var month: int = GameState.month if in_season else GameState.SEASON_MONTHS[0]
	var dict := {
		"year": GameState.year, "month": month, "day": 1,
		"hour": 12, "minute": 0, "second": 0,
	}
	return Time.get_unix_time_from_datetime_dict(dict)


func _make_day_column(day_unix: int, finished: bool, team_color: Color) -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(220, 0)
	column.add_theme_constant_override("separation", 6)

	var dt := Time.get_datetime_dict_from_unix_time(day_unix)
	var weekday: int = dt["weekday"]

	var header := Label.new()
	header.text = "%d月%d日（%s）" % [dt["month"], dt["day"], WEEKDAY_NAMES[weekday]]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = team_color
	header_style.set_corner_radius_all(8)
	header_style.set_content_margin_all(6)
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", header_style)
	header.add_theme_color_override("font_color", GameData.team_text_color(GameState.team))
	header_panel.add_child(header)
	column.add_child(header_panel)

	if weekday == 1:  # 月曜は移動日（他球団含め全カード休み）
		var rest_label := Label.new()
		rest_label.text = "移動日"
		rest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rest_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rest_label.size_flags_vertical = SIZE_EXPAND_FILL
		rest_label.add_theme_font_size_override("font_size", 22)
		column.add_child(rest_label)
		return column

	for pair in _pairings_for(day_unix):
		column.add_child(_make_game_tile(pair[0], pair[1], day_unix, finished))
	return column


## 円卓法（circle method）で日ごとの組み合わせを作る仮のペアリング。
## リーグ内総当たりの雰囲気を出すためだけの仮ロジックで、実際の年間日程ではない。
func _pairings_for(day_unix: int) -> Array:
	var pairs := []
	var round_index := int(day_unix / DAY_SECONDS)
	for league in ["C", "P"]:
		var teams := GameData.teams(league)
		if teams.size() < 2:
			continue
		pairs.append_array(_round_robin_pairs(teams, round_index))
	return pairs


func _round_robin_pairs(teams: Array, round_index: int) -> Array:
	var n := teams.size()
	var rotating: Array = teams.slice(1)
	var r := round_index % max(n - 1, 1)
	for i in r:
		rotating.push_back(rotating.pop_front())
	var order: Array = [teams[0]] + rotating
	var pairs := []
	for i in n / 2:
		pairs.append([order[i], order[n - 1 - i]])
	return pairs


func _make_game_tile(home: String, away: String, day_unix: int, finished: bool) -> PanelContainer:
	var is_own_game := home == GameState.team or away == GameState.team
	var tile := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.55, 0.57, 0.6) if finished else Color(1, 1, 1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(6)
	if is_own_game:
		style.set_border_width_all(3)
		style.border_color = GameData.team_color(GameState.team)
	tile.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	tile.add_child(box)

	box.add_child(_make_matchup_row(home, away))

	var mid_label := Label.new()
	mid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid_label.add_theme_font_size_override("font_size", 18)
	if finished:
		var seed := hash("%s-%s-%d" % [home, away, day_unix])
		var home_score := seed % 8
		var away_score := (seed / 8) % 8
		if home_score == away_score:
			home_score += 1
		mid_label.text = "%d - %d" % [away_score, home_score]
		var score_color := Color(0.95, 0.95, 0.95) if is_own_game else Color(0.9, 0.9, 0.9)
		mid_label.add_theme_color_override("font_color", score_color)
	else:
		mid_label.text = "vs"
	box.add_child(mid_label)

	var stadium_label := Label.new()
	stadium_label.text = GameData.stadium_of(home)
	stadium_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stadium_label.add_theme_font_size_override("font_size", 12)
	var stadium_color := Color(0.9, 0.9, 0.9) if finished else Color(0.4, 0.4, 0.4)
	stadium_label.add_theme_color_override("font_color", stadium_color)
	box.add_child(stadium_label)

	return tile


func _make_matchup_row(home: String, away: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_make_team_chip(away))
	var vs_label := Label.new()
	vs_label.text = "-"
	row.add_child(vs_label)
	row.add_child(_make_team_chip(home))
	return row


func _make_team_chip(team: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = GameData.team_color(team)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(3)
	chip.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = GameData.short_name(team)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", GameData.team_text_color(team))
	chip.add_child(label)
	return chip


## セ・パ両リーグの順位表。対戦相手の勝敗は未実装のため、自球団以外は「-」表示
func _render_standings() -> void:
	for child in _standings_box.get_children():
		child.queue_free()
	for league in ["C", "P"]:
		_standings_box.add_child(_make_standings_column(league))


func _make_standings_column(league: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(150, 0)
	column.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = GameData.LEAGUE_NAMES.get(league, league)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(header)

	var rank := 1
	for team: String in GameData.teams(league):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var rank_label := Label.new()
		rank_label.text = str(rank)
		rank_label.custom_minimum_size = Vector2(16, 0)
		row.add_child(rank_label)

		var chip := ColorRect.new()
		chip.color = GameData.team_color(team)
		chip.custom_minimum_size = Vector2(12, 12)
		var chip_center := CenterContainer.new()
		chip_center.add_child(chip)
		row.add_child(chip_center)

		var name_label := Label.new()
		name_label.text = GameData.short_name(team)
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		if team == GameState.team:
			name_label.add_theme_color_override("font_color", GameData.team_color(team).darkened(0.2))
		row.add_child(name_label)

		var gb_label := Label.new()
		gb_label.text = GameState.record_text() if team == GameState.team else "-"
		row.add_child(gb_label)

		column.add_child(row)
		rank += 1
	return column
