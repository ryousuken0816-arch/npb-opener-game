extends Control
## タイトル（ニューゲーム：球団選択）。能力値ファイルから球団一覧を作る。

const HUB_SCENE := "res://scenes/hub/hub.tscn"

@onready var _sub_label: Label = %SubLabel
@onready var _leagues: HBoxContainer = %Leagues


func _ready() -> void:
	if not GameData.load_ratings(GameState.START_YEAR, "pre"):
		_sub_label.text = "能力値ファイル（generated/ratings/%d_pre.json）が見つかりません" % GameState.START_YEAR
		return
	_sub_label.text = "%d年開幕：担当する球団を選んでください" % GameState.START_YEAR
	for league: String in GameData.LEAGUE_NAMES:
		_leagues.add_child(_make_league_column(league))


func _make_league_column(league: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(280, 0)
	var header := Label.new()
	header.text = GameData.LEAGUE_NAMES[league]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(header)
	for team in GameData.teams(league):
		var button := Button.new()
		button.text = team
		button.custom_minimum_size = Vector2(0, 44)
		button.pressed.connect(_on_team_chosen.bind(team))
		column.add_child(button)
	return column


func _on_team_chosen(team: String) -> void:
	GameState.new_game(team)
	get_tree().change_scene_to_file(HUB_SCENE)
