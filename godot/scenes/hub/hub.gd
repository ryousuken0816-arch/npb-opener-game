extends Control
## ハブ画面（常設メニュー）。左に可変ボタンとメニュー、右にメニューごとの画面。
## 各メニューの画面は未実装のものはプレースホルダー表示。

## メニュー: [キー, ボタン名, 未実装時の説明（docs/SPEC.md「UI/画面構成」）]
const MENUS := [
	["roster", "チーム", ""],
	["schedule", "日程表", "自球団の日程と結果、その日の全カード結果、セ・パ順位表。\n試合結果（ハイライト・勝敗確率グラフ）は日程表から開く。"],
	["tactics", "采配", "基本オーダー（固定、必要時のみ調整）。\n送りバント・盗塁の積極性、継投傾向などの方針。"],
	["scout", "新戦力", "トレード交渉、外国人選手の獲得、ドラフト候補の事前スカウティング。"],
	["records", "記録室", "リーグ全体の個人成績・通算成績、タイトル・表彰歴、チーム成績推移、\n達成記録（ノーヒットノーラン等）、ドラフト履歴。"],
	["system", "システム", "セーブ/ロード、難易度（CPUの未来視ノイズ）、表示/サウンド、早送り速度。"],
]

const TITLE_SCENE := "res://scenes/title/title.tscn"

var _current_menu := "roster"

@onready var _date_label: Label = %DateLabel
@onready var _phase_label: Label = %PhaseLabel
@onready var _team_label: Label = %TeamLabel
@onready var _record_label: Label = %RecordLabel
@onready var _advance_button: Button = %AdvanceButton
@onready var _menu_buttons: VBoxContainer = %MenuButtons
@onready var _roster_view: RosterView = %RosterView
@onready var _placeholder_view: VBoxContainer = %PlaceholderView
@onready var _placeholder_title: Label = %PlaceholderTitle
@onready var _placeholder_body: Label = %PlaceholderBody


func _ready() -> void:
	if GameState.team.is_empty():
		# ハブを直接実行したときはタイトルへ戻す
		get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)
		return
	_build_menu()
	_advance_button.pressed.connect(GameState.advance)
	GameState.changed.connect(_refresh)
	_refresh()


func _build_menu() -> void:
	var group := ButtonGroup.new()
	for menu: Array in MENUS:
		var button := Button.new()
		button.text = menu[1]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = menu[0] == _current_menu
		button.custom_minimum_size = Vector2(0, 48)
		button.pressed.connect(_show_menu.bind(menu[0]))
		_menu_buttons.add_child(button)


func _refresh() -> void:
	_date_label.text = GameState.date_text()
	_phase_label.text = GameState.phase_name()
	_team_label.text = GameState.team
	_record_label.text = GameState.record_text()
	_advance_button.text = GameState.button_text()
	_show_menu(_current_menu)


func _show_menu(key: String) -> void:
	_current_menu = key
	_roster_view.visible = key == "roster"
	_placeholder_view.visible = key != "roster"
	if key == "roster":
		_roster_view.show_team(GameState.team)
		return
	for menu: Array in MENUS:
		if menu[0] == key:
			_placeholder_title.text = menu[1]
			_placeholder_body.text = menu[2] + "\n\n（未実装）"
