extends Control
## ハブ画面（常設メニュー）。左に可変ボタンとメニュー、右に日程・順位表。
## 配色は自球団の球団カラーをテーマにする（docs/references/README.md の要望）。

## メニュー: [キー, ボタン名, 説明文, テーマ色]
const MENUS := [
	["roster", "チーム", "自球団の野手・投手一覧です。", Color("2ec4b6")],
	["schedule", "日程表", "自球団の日程と結果、その日の全カード結果、セ・パ順位表。", Color("ff5d8f")],
	["tactics", "采配", "基本オーダー（固定、必要時のみ調整）。\n送りバント・盗塁の積極性、継投傾向などの方針。", Color("ffd23c")],
	["scout", "新戦力", "トレード交渉、外国人選手の獲得、ドラフト候補の事前スカウティング。", Color("6a8cff")],
	["records", "記録室", "リーグ全体の個人成績・通算成績、タイトル・表彰歴、チーム成績推移、\n達成記録（ノーヒットノーラン等）、ドラフト履歴。", Color("ffb703")],
	["system", "システム", "セーブ/ロード、難易度（CPUの未来視ノイズ）、表示/サウンド、早送り速度。", Color("8d6ae8")],
]

const TITLE_SCENE := "res://scenes/title/title.tscn"

var _current_menu := "roster"
var _menu_button_by_key := {}
var _standings_league := "C"

@onready var _background: ColorRect = %Background
@onready var _top_bar: PanelContainer = %TopBar
@onready var _event_label: Label = %EventLabel
@onready var _menu_buttons: VBoxContainer = %MenuButtons
@onready var _desc_panel: PanelContainer = %DescPanel
@onready var _desc_label: Label = %DescLabel
@onready var _roster_view: RosterView = %RosterView
@onready var _schedule_view: ScheduleView = %ScheduleView
@onready var _placeholder_view: VBoxContainer = %PlaceholderView
@onready var _placeholder_title: Label = %PlaceholderTitle
@onready var _placeholder_body: Label = %PlaceholderBody
@onready var _standings_panel: PanelContainer = %StandingsPanel
@onready var _standings_list: VBoxContainer = %StandingsList
@onready var _page_label: Label = %PageLabel
@onready var _prev_button: Button = %PrevButton
@onready var _next_button: Button = %NextButton
@onready var _date_panel: PanelContainer = %DatePanel
@onready var _team_label: Label = %TeamLabel
@onready var _date_label: Label = %DateLabel
@onready var _record_label: Label = %RecordLabel
@onready var _advance_button: Button = %AdvanceButton


func _ready() -> void:
	if GameState.team.is_empty():
		# ハブを直接実行したときはタイトルへ戻す
		get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)
		return
	_standings_league = GameData.league_of(GameState.team)
	if _standings_league.is_empty():
		_standings_league = "C"
	_apply_theme()
	_build_menu()
	_advance_button.pressed.connect(GameState.advance)
	_prev_button.pressed.connect(_switch_league.bind(-1))
	_next_button.pressed.connect(_switch_league.bind(1))
	GameState.changed.connect(_refresh)
	_refresh()


## 自球団の色を基調にした明るい配色にする（黒基調は避ける、というユーザー要望）
func _apply_theme() -> void:
	var team_color := GameData.team_color(GameState.team)
	_background.color = team_color.lightened(0.88)

	var top_style := StyleBoxFlat.new()
	top_style.bg_color = team_color
	top_style.set_corner_radius_all(10)
	top_style.set_content_margin_all(8)
	_top_bar.add_theme_stylebox_override("panel", top_style)
	_event_label.add_theme_color_override("font_color", GameData.team_text_color(GameState.team))

	for panel: PanelContainer in [_desc_panel, _standings_panel, _date_panel]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1, 1, 1, 0.85)
		style.border_color = team_color
		style.set_border_width_all(3)
		style.set_corner_radius_all(12)
		style.set_content_margin_all(12)
		panel.add_theme_stylebox_override("panel", style)

	_advance_button.add_theme_stylebox_override("normal", _button_style(team_color, false))
	_advance_button.add_theme_stylebox_override("hover", _button_style(team_color, true))
	_advance_button.add_theme_stylebox_override("pressed", _button_style(team_color, true))
	_advance_button.add_theme_color_override("font_color", GameData.team_text_color(GameState.team))


func _build_menu() -> void:
	for menu: Array in MENUS:
		var key: String = menu[0]
		var button := Button.new()
		button.text = menu[1]
		button.toggle_mode = true
		button.button_pressed = key == _current_menu
		button.custom_minimum_size = Vector2(0, 56)
		button.add_theme_font_size_override("font_size", 20)
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_pressed_color", Color.WHITE)
		button.add_theme_color_override("font_outline_color", Color(0.15, 0.15, 0.15))
		button.add_theme_constant_override("outline_size", 4)
		button.pressed.connect(_show_menu.bind(key))
		_menu_buttons.add_child(button)
		_menu_button_by_key[key] = button
		_style_menu_button(key)


func _style_menu_button(key: String) -> void:
	var button: Button = _menu_button_by_key[key]
	var menu := MENUS.filter(func(m): return m[0] == key)[0]
	var color: Color = menu[3]
	var selected := key == _current_menu
	button.custom_minimum_size.y = 68 if selected else 56
	button.add_theme_font_size_override("font_size", 24 if selected else 20)
	var style := _button_style(color if selected else color.lightened(0.15), selected)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)


func _button_style(color: Color, emphasized: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(14)
	style.set_content_margin_all(8)
	if emphasized:
		style.set_border_width_all(4)
		style.border_color = Color.WHITE
		style.shadow_size = 4
		style.shadow_color = Color(0, 0, 0, 0.25)
	return style


func _refresh() -> void:
	_date_label.text = GameState.date_text()
	var is_opening_day := GameState.phase == GameState.Phase.SEASON and GameState.month == 4
	_event_label.text = "開幕戦" if is_opening_day else GameState.phase_name()
	_team_label.text = GameState.team
	_record_label.text = GameState.record_text()
	_advance_button.text = GameState.button_text()
	_refresh_standings()
	_show_menu(_current_menu)


func _show_menu(key: String) -> void:
	_current_menu = key
	for menu_key: String in _menu_button_by_key:
		_menu_button_by_key[menu_key].button_pressed = menu_key == key
		_style_menu_button(menu_key)

	_roster_view.visible = key == "roster"
	_schedule_view.visible = key == "schedule"
	_placeholder_view.visible = key != "roster" and key != "schedule"

	if key == "roster":
		_roster_view.show_team(GameState.team)
	elif key == "schedule":
		_schedule_view.refresh()
	else:
		for menu: Array in MENUS:
			if menu[0] == key:
				_placeholder_title.text = menu[1]
				_placeholder_body.text = menu[2] + "\n\n（未実装）"

	for menu: Array in MENUS:
		if menu[0] == key:
			_desc_label.text = menu[2]


func _switch_league(_direction: int) -> void:
	_standings_league = "P" if _standings_league == "C" else "C"
	_refresh_standings()


## 順位表：本来はセ・パ全12球団の勝敗を表示するが、対戦相手の成績シミュレーションは
## 未実装のため、自球団以外は「-」表示のプレースホルダーとする。
func _refresh_standings() -> void:
	_page_label.text = GameData.LEAGUE_NAMES.get(_standings_league, _standings_league)
	for child in _standings_list.get_children():
		child.queue_free()
	var rank := 1
	for team: String in GameData.teams(_standings_league):
		_standings_list.add_child(_make_standings_row(rank, team))
		rank += 1


func _make_standings_row(rank: int, team: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var rank_label := Label.new()
	rank_label.text = str(rank)
	rank_label.custom_minimum_size = Vector2(20, 0)
	row.add_child(rank_label)

	var chip := ColorRect.new()
	chip.color = GameData.team_color(team)
	chip.custom_minimum_size = Vector2(14, 14)
	var chip_center := CenterContainer.new()
	chip_center.add_child(chip)
	row.add_child(chip_center)

	var name_label := Label.new()
	name_label.text = GameData.short_name(team)
	name_label.custom_minimum_size = Vector2(72, 0)
	if team == GameState.team:
		name_label.add_theme_color_override("font_color", GameData.team_color(team).darkened(0.2))
	row.add_child(name_label)

	var record_label := Label.new()
	record_label.size_flags_horizontal = SIZE_EXPAND_FILL
	record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	record_label.text = GameState.record_text() if team == GameState.team else "-"
	row.add_child(record_label)

	return row
