extends Control
## ハブ画面（パワプロのペナント画面が参考。docs/references/README.md）。
## 左に大きなメニュー、右上に順位表、上にイベント名、下に選択中メニューの説明と日付。
## 配色は自球団のチームカラー。メニューを押すと中央〜右にその画面を開く（未実装はプレースホルダー）。

## [キー, ボタン名, アイコン, ボタン色, 説明文]。先頭は可変ボタン（文言・説明は GameState から）
const MENUS := [
	["advance", "試合へ", "game", Color("e53935"), ""],
	["schedule", "日程表", "schedule", Color("e84393"),
		"自球団の日程と結果、その日の全カードの結果、セ・パの順位表を見ます。"],
	["tactics", "采配", "tactics", Color("f57c00"),
		"1・2軍の入れ替え、オーダーや起用法の設定、所属選手の確認をします。"],
	["scout", "新戦力", "scout", Color("00a396"),
		"トレード交渉、外国人選手の獲得、ドラフト候補のスカウティングをします。"],
	["records", "記録室", "records", Color("e0a400"),
		"個人成績・通算成績、タイトル・表彰歴、チーム成績の推移などを見ます。"],
	["system", "システム", "system", Color("7e57c2"),
		"セーブ／ロード、難易度、表示・サウンド、早送り速度の設定をします。"],
]

## 未実装画面の内容（docs/SPEC.md「UI/画面構成」）
const PLACEHOLDERS := {
	"scout": "トレード交渉、外国人選手の獲得、ドラフト候補の事前スカウティング。",
	"records": "リーグ全体の個人成績・通算成績、タイトル・表彰歴、チーム成績推移、\n達成記録（ノーヒットノーラン等）、ドラフト履歴。",
	"system": "セーブ/ロード、難易度（CPUの未来視ノイズ）、表示/サウンド、早送り速度。",
}

const ICON_DIR := "res://assets/icons"
const TITLE_SCENE := "res://scenes/title/title.tscn"

var _palette: UiTheme.Palette
var _buttons := {}
var _focused_key := "advance"
var _open_key := ""

@onready var _background: TeamBackground = %Background
@onready var _event_label: Label = %EventLabel
@onready var _menu_box: VBoxContainer = %MenuBox
@onready var _emblem: TeamEmblem = %Emblem
@onready var _team_name_label: Label = %TeamNameLabel
@onready var _summary_label: Label = %SummaryLabel
@onready var _center_area: Control = %CenterArea
@onready var _standings: StandingsPanel = %Standings
@onready var _sub_screen: PanelContainer = %SubScreen
@onready var _sub_title_label: Label = %SubTitleLabel
@onready var _roster_view: RosterView = %RosterView
@onready var _schedule_view: ScheduleView = %ScheduleView
@onready var _placeholder_label: Label = %PlaceholderLabel
@onready var _bottom_bar: PanelContainer = %BottomBar
@onready var _description_label: Label = %DescriptionLabel
@onready var _year_label: Label = %YearLabel
@onready var _month_label: Label = %MonthLabel


func _ready() -> void:
	if GameState.team.is_empty():
		# ハブを直接実行したときはタイトルへ戻す
		get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)
		return
	_palette = UiTheme.team_palette(GameState.team)
	theme = UiTheme.build(_palette)
	_background.set_palette(_palette)
	_style_labels()
	_build_menu()
	_standings.setup(_palette, GameData.league_of(GameState.team))
	_schedule_view.setup(_palette)
	%BackButton.pressed.connect(_close_sub_screen)
	GameState.changed.connect(_refresh)
	_refresh()
	_buttons["advance"].grab_button_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _open_key.is_empty():
		_close_sub_screen()
		get_viewport().set_input_as_handled()


func _style_labels() -> void:
	var p := _palette
	_event_label.label_settings = _label_settings(64, p.ink, 12, Color.WHITE, Color(p.ink, 0.35))
	_team_name_label.label_settings = _label_settings(34, p.ink, 8, Color.WHITE)
	_summary_label.label_settings = _label_settings(20, UiTheme.TEXT, 0, Color.WHITE)
	_year_label.label_settings = _label_settings(32, p.ink, 8, Color.WHITE, Color.TRANSPARENT, 800)
	_month_label.label_settings = _label_settings(56, p.ink, 10, Color.WHITE, Color(p.ink, 0.3))
	_sub_title_label.label_settings = _label_settings(28, p.ink, 0, Color.WHITE)
	_description_label.add_theme_font_size_override("font_size", 21)
	_description_label.add_theme_font_override("font", UiTheme.font(700))

	# 下の帯：白地に球団カラーの上線
	var bar := UiTheme.box(Color(1, 1, 1, 0.9), 0, _palette.main, 0)
	bar.border_width_top = 5
	bar.content_margin_left = 32
	bar.content_margin_right = 32
	bar.content_margin_top = 4
	bar.content_margin_bottom = 4
	_bottom_bar.add_theme_stylebox_override("panel", bar)

	var screen := UiTheme.box(Color(1, 1, 1, 0.97), 12, _palette.main, 3)
	screen.content_margin_left = 16
	screen.content_margin_right = 16
	screen.content_margin_top = 12
	screen.content_margin_bottom = 16
	_sub_screen.add_theme_stylebox_override("panel", screen)


func _label_settings(font_size: int, color: Color, outline: int, outline_color: Color,
		shadow := Color.TRANSPARENT, weight := 800) -> LabelSettings:
	var s := LabelSettings.new()
	s.font = UiTheme.font(weight)
	s.font_size = font_size
	s.font_color = color
	s.outline_size = outline
	s.outline_color = outline_color
	s.shadow_color = shadow
	s.shadow_size = 0
	s.shadow_offset = Vector2(3, 4)
	return s


func _build_menu() -> void:
	for menu: Array in MENUS:
		var button := HubMenuButton.new()
		var icon: Texture2D = load(ICON_DIR.path_join(menu[2] + ".svg"))
		button.setup(menu[0], menu[1], icon, menu[3], _palette.ink)
		button.focused.connect(_on_menu_focused)
		button.chosen.connect(_on_menu_chosen)
		_menu_box.add_child(button)
		_buttons[menu[0]] = button


func _refresh() -> void:
	_event_label.text = GameState.event_text()
	# 長いフェーズ名（FA・トレード・ポスティング 等）は枠に収まるよう縮める
	var fit_size := int(_event_label.size.x / _event_label.text.length())
	_event_label.label_settings.font_size = clampi(fit_size, 32, 64)
	_year_label.text = GameState.year_text()
	_month_label.text = GameState.month_text()
	_buttons["advance"].set_text(GameState.button_text())
	_emblem.setup(_palette, GameData.short_name(GameState.team))
	_team_name_label.text = GameState.team
	_summary_label.text = _summary_text()
	_standings.refresh()
	_description_label.text = _description(_focused_key)
	if _open_key == "tactics":
		_roster_view.show_team(GameState.team)
	elif _open_key == "schedule":
		_schedule_view.refresh()


func _summary_text() -> String:
	var league := GameData.league_of(GameState.team)
	var rank := 0
	for row: Dictionary in GameState.standings(league):
		if row["team"] == GameState.team:
			rank = row["rank"]
	var pct := GameState.win_pct({"wins": GameState.wins, "losses": GameState.losses})
	return "%s %d位　%s　勝率 %s" % [
		GameData.LEAGUE_NAMES.get(league, ""), rank, GameState.record_text(),
		("%.3f" % pct).trim_prefix("0")]


func _description(key: String) -> String:
	if key == "advance":
		if GameState.phase == GameState.Phase.SEASON:
			return "%d月の試合を行い、次の月へ進みます。（試合シミュレーションは未実装）" % GameState.month
		return "オフシーズンを進めます。次は「%s」です。" % GameState.PHASE_NAMES[GameState.next_phase()]
	for menu: Array in MENUS:
		if menu[0] == key:
			return menu[4]
	return ""


func _on_menu_focused(key: String) -> void:
	_focused_key = key
	_description_label.text = _description(key)


func _on_menu_chosen(key: String) -> void:
	if key == "advance":
		GameState.advance()
		return
	_open_sub_screen(key)


func _open_sub_screen(key: String) -> void:
	_open_key = key
	_sub_screen.visible = true
	_center_area.visible = false
	_standings.visible = false
	for menu: Array in MENUS:
		if menu[0] == key:
			_sub_title_label.text = menu[1]
	var is_roster := key == "tactics"
	var is_schedule := key == "schedule"
	_roster_view.visible = is_roster
	_schedule_view.visible = is_schedule
	_placeholder_label.visible = not is_roster and not is_schedule
	if is_roster:
		_sub_title_label.text = "采配 ― 選手一覧"
		_roster_view.show_team(GameState.team)
	elif is_schedule:
		_sub_title_label.text = "日程表"
		_schedule_view.refresh()
	else:
		_placeholder_label.text = PLACEHOLDERS.get(key, "") + "\n\n（未実装）"


func _close_sub_screen() -> void:
	var key := _open_key
	_open_key = ""
	_sub_screen.visible = false
	_center_area.visible = true
	_standings.visible = true
	if _buttons.has(key):
		_buttons[key].grab_button_focus()
