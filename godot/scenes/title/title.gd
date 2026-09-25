extends Control
## タイトル（ニューゲーム：球団選択）。能力値ファイルから球団一覧を作る。
## 球団ボタンは各球団のチームカラーの立体ボタン（縁は球団のサブカラー）。
## コントローラー：十字キーで球団を選び Ⓐ で決定（右上に操作ガイド）。

const HUB_SCENE := "res://scenes/hub/hub.tscn"

@onready var _title_label: Label = %TitleLabel
@onready var _sub_label: Label = %SubLabel
@onready var _leagues: HBoxContainer = %Leagues


func _ready() -> void:
	var palette := UiTheme.neutral_palette()
	theme = UiTheme.build(palette)
	UiTheme.heading(_title_label, 52, palette.ink, Color.WHITE, 14)
	_title_label.label_settings.shadow_color = Color(palette.ink.darkened(0.4), 0.45)
	_title_label.label_settings.shadow_offset = Vector2(3, 5)
	UiTheme.heading(_sub_label, 20, UiTheme.TEXT, Color.WHITE, 6, false)
	var guide := PadGuide.new()
	guide.set_items([["A", "決定"]])
	add_child(guide)
	guide.position = Vector2(size.x - guide.size.x - 24, 5)
	resized.connect(func() -> void: guide.position = Vector2(size.x - guide.size.x - 24, 5))
	UiFx.install(self)
	if not GameData.load_ratings(GameState.START_YEAR, "pre"):
		_sub_label.text = "能力値ファイル（generated/ratings/%d_pre.json）が見つかりません" % GameState.START_YEAR
		return
	_sub_label.text = "%d年開幕：担当する球団を選んでください" % GameState.START_YEAR
	for league: String in GameData.LEAGUE_NAMES:
		_leagues.add_child(_make_league_column(league))
	UiInput.focus_first(_leagues)
	UiFx.fade_in($Center/VBox)


func _make_league_column(league: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(320, 0)
	column.add_theme_constant_override("separation", 10)
	var header := Label.new()
	header.text = GameData.LEAGUE_NAMES[league]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(header, 24, UiTheme.TEXT, Color.WHITE, 8)
	column.add_child(header)
	for team in GameData.teams(league):
		column.add_child(_make_team_button(team))
	return column


## 球団カラーの立体ボタン（メイン色の地、左にサブ色の太い帯と縁取り）
func _make_team_button(team: String) -> Button:
	var colors := GameData.team_colors(team)
	var button := Button.new()
	button.text = team
	button.custom_minimum_size = Vector2(0, 48)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_font_override("font", UiTheme.font(800))
	UiTheme.style_button(button, colors[0])
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var st := button.get_theme_stylebox(state) as GlossBox
		st.border_color = colors[1].darkened(0.1)
		st.border_width_left = 10
	button.pressed.connect(_on_team_chosen.bind(team))
	return button


func _on_team_chosen(team: String) -> void:
	GameState.new_game(team)
	get_tree().change_scene_to_file(HUB_SCENE)
