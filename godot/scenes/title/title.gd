extends Control
## タイトル（ニューゲーム：球団選択）。能力値ファイルから球団一覧を作る。
## 球団ボタンは各球団のチームカラーで表示する。

const HUB_SCENE := "res://scenes/hub/hub.tscn"

@onready var _title_label: Label = %TitleLabel
@onready var _sub_label: Label = %SubLabel
@onready var _leagues: HBoxContainer = %Leagues


func _ready() -> void:
	var palette := UiTheme.neutral_palette()
	theme = UiTheme.build(palette)
	_title_label.add_theme_font_override("font", UiTheme.font(800))
	_title_label.add_theme_color_override("font_color", palette.ink)
	_title_label.add_theme_color_override("font_outline_color", Color.WHITE)
	_title_label.add_theme_constant_override("outline_size", 12)
	_title_label.add_theme_font_size_override("font_size", 48)
	_sub_label.add_theme_font_size_override("font_size", 20)
	if not GameData.load_ratings(GameState.START_YEAR, "pre"):
		_sub_label.text = "能力値ファイル（generated/ratings/%d_pre.json）が見つかりません" % GameState.START_YEAR
		return
	_sub_label.text = "%d年開幕：担当する球団を選んでください" % GameState.START_YEAR
	for league: String in GameData.LEAGUE_NAMES:
		_leagues.add_child(_make_league_column(league))


func _make_league_column(league: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(320, 0)
	column.add_theme_constant_override("separation", 10)
	var header := Label.new()
	header.text = GameData.LEAGUE_NAMES[league]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_override("font", UiTheme.font(800))
	header.add_theme_font_size_override("font_size", 24)
	column.add_child(header)
	for team in GameData.teams(league):
		column.add_child(_make_team_button(team))
	return column


## 球団カラーのボタン（メイン色の地、左にサブ色の帯）
func _make_team_button(team: String) -> Button:
	var colors := GameData.team_colors(team)
	var button := Button.new()
	button.text = team
	button.custom_minimum_size = Vector2(0, 48)
	button.add_theme_font_size_override("font_size", 20)
	var normal := UiTheme.box(colors[0], 8, colors[1], 0)
	normal.border_width_left = 10
	normal.shadow_color = Color(0, 0, 0, 0.2)
	normal.shadow_size = 2
	normal.shadow_offset = Vector2(0, 3)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = colors[0].lightened(0.15)
	hover.set_border_width_all(3)
	hover.border_width_left = 10
	hover.border_color = colors[1] if colors[1].get_luminance() < 0.8 else UiTheme.TEXT
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", hover)
	for c in UiTheme.BUTTON_FONT_COLORS:
		button.add_theme_color_override(c, UiTheme.text_on(colors[0]))
	button.pressed.connect(_on_team_chosen.bind(team))
	return button


func _on_team_chosen(team: String) -> void:
	GameState.new_game(team)
	get_tree().change_scene_to_file(HUB_SCENE)
