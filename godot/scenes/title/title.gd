extends Control
## タイトル（ニューゲーム：球団選択）。能力値ファイルから球団一覧を作る。
## 球団ボタンは各球団のチームカラーの立体ボタン（縁は球団のサブカラー）。
## コントローラー：十字キーで球団を選び Ⓐ で決定（右上に操作ガイド）。
##
## デバッグ用（下の控えめな行）：開始年（2008〜2027。LB/RB＝Q/E でも変えられる）と
## 「すぐドラフトへ」（シーズンを自動で消化して、その年のオフのドラフトの段階から始める。
## GameState.skip_to_phase）。十字キーで球団の一覧の下へ移ると選べる
##
## 続きから（セーブが1つでもあるときだけ、球団の一覧の上に出る。最初はここにフォーカス）：押すとセーブの枠の一覧
## （SaveView のロードだけ）→ 枠を選ぶとロードしてハブへ。Ⓑ（Esc）／「戻る」で球団選択に戻る

const HUB_SCENE := "res://scenes/hub/hub.tscn"
## 「すぐドラフトへ」で飛ぶ段階
const SKIP_TARGET := GameState.Phase.DRAFT

var start_year := GameState.START_YEAR
var _year_option: OptionButton
var _skip_check: CheckButton
var _debug_row: Control
var _continue_button: Button
var _continue_panel: PanelContainer
var _save_view: SaveView

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
	guide.set_items([["A", "決定"], ["LB/RB", "開始年"]])
	add_child(guide)
	guide.position = Vector2(size.x - guide.size.x - 24, 5)
	resized.connect(func() -> void: guide.position = Vector2(size.x - guide.size.x - 24, 5))
	UiFx.install(self)
	_debug_row = _make_debug_row()
	$Center/VBox.add_child(_debug_row)
	_make_continue(palette)
	_build_teams()
	if _continue_button.visible:
		_continue_button.grab_focus()
	else:
		UiInput.focus_first(_leagues)
	UiFx.fade_in($Center/VBox)


func _unhandled_input(event: InputEvent) -> void:
	if _continue_panel.visible:
		if event.is_action_pressed("ui_cancel"):
			if not _save_view.back():
				show_continue(false)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(UiInput.TAB_PREV) or event.is_action_pressed(UiInput.TAB_NEXT):
		set_start_year(start_year + (-1 if event.is_action_pressed(UiInput.TAB_PREV) else 1))
		get_viewport().set_input_as_handled()


## 開始年を変えて球団の一覧を作り直す（範囲外は端で止める）
func set_start_year(new_year: int) -> void:
	new_year = clampi(new_year, GameState.DEBUG_FIRST_YEAR, GameState.DEBUG_LAST_YEAR)
	if new_year == start_year:
		return
	start_year = new_year
	_year_option.select(start_year - GameState.DEBUG_FIRST_YEAR)
	var focused := get_viewport().gui_get_focus_owner()
	var had_focus := focused == null or _leagues.is_ancestor_of(focused)
	_build_teams()
	if had_focus:
		UiInput.focus_first(_leagues)


func _build_teams() -> void:
	for child in _leagues.get_children():
		_leagues.remove_child(child)
		child.queue_free()
	if not GameData.load_ratings(start_year, "pre"):
		_sub_label.text = "能力値ファイル（generated/ratings/%d_pre.json）が見つかりません" % start_year
		return
	_sub_label.text = "%d年開幕：担当する球団を選んでください" % start_year
	for league: String in GameData.LEAGUE_NAMES:
		_leagues.add_child(_make_league_column(league))


## 「続きから」のボタンと、セーブの枠の一覧（最初は隠しておく）
func _make_continue(palette: UiTheme.Palette) -> void:
	var vbox: VBoxContainer = $Center/VBox
	_continue_button = Button.new()
	_continue_button.text = "続きから"
	_continue_button.custom_minimum_size = Vector2(320, 48)
	_continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_button.add_theme_font_size_override("font_size", 22)
	_continue_button.add_theme_font_override("font", UiTheme.font(800))
	_continue_button.tooltip_text = "セーブした続きから遊びます（スロット1〜3・オートセーブ）"
	UiTheme.style_button(_continue_button, Color("7e57c2"))
	_continue_button.pressed.connect(show_continue.bind(true))
	_continue_button.visible = SaveGame.has_any()
	vbox.add_child(_continue_button)
	vbox.move_child(_continue_button, _leagues.get_index())
	_continue_panel = PanelContainer.new()
	var style := UiTheme.card(palette.main, 12, 3, 0.97)
	style.set_content_margin_all(14)
	_continue_panel.add_theme_stylebox_override("panel", style)
	_continue_panel.custom_minimum_size = Vector2(720, 0)
	_continue_panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_continue_panel.add_child(box)
	_save_view = SaveView.new()
	_save_view.setup(palette, true)
	_save_view.loaded.connect(func() -> void: get_tree().change_scene_to_file(HUB_SCENE))
	box.add_child(_save_view)
	var back := Button.new()
	back.text = "戻る"
	back.custom_minimum_size = Vector2(160, 44)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.add_theme_font_size_override("font_size", 20)
	UiTheme.style_button(back, Color("8a9199"), Color.WHITE)
	back.pressed.connect(show_continue.bind(false))
	box.add_child(back)
	vbox.add_child(_continue_panel)
	vbox.move_child(_continue_panel, _leagues.get_index())


## セーブの枠の一覧を出す／隠す（隠すと球団選択に戻る）
func show_continue(on: bool) -> void:
	_continue_panel.visible = on
	_leagues.visible = not on
	_debug_row.visible = not on
	_continue_button.visible = not on and SaveGame.has_any()
	if on:
		_sub_label.text = "続きから：ロードする枠を選んでください"
		_save_view.open()
	else:
		_sub_label.text = "%d年開幕：担当する球団を選んでください" % start_year
		if _continue_button.visible:
			_continue_button.grab_focus()
		else:
			UiInput.focus_first(_leagues)


## デバッグ用の行（小さめの文字・半透明の地）：開始年のプルダウンと「すぐドラフトへ」
func _make_debug_row() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := UiTheme.box(Color(1, 1, 1, 0.55), 8, Color(0, 0, 0, 0.15), 1)
	style.set_content_margin_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var caption := UiTheme.small_label("デバッグ用　開始年", 14)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	_year_option = OptionButton.new()
	_year_option.add_theme_font_size_override("font_size", 14)
	for y in range(GameState.DEBUG_FIRST_YEAR, GameState.DEBUG_LAST_YEAR + 1):
		_year_option.add_item("%d年" % y, y)
	_year_option.select(start_year - GameState.DEBUG_FIRST_YEAR)
	_year_option.tooltip_text = "開始年（その年の所属・能力・日程で始めます）。LB/RB（Q/E）でも変えられます"
	_year_option.item_selected.connect(func(index: int) -> void:
		set_start_year(_year_option.get_item_id(index)))
	row.add_child(_year_option)
	_skip_check = CheckButton.new()
	_skip_check.text = "すぐドラフトへ"
	_skip_check.add_theme_font_size_override("font_size", 14)
	_skip_check.tooltip_text = "シーズンを自動で消化し（試合はシミュレーション）、その年のオフのドラフトの段階から始めます。ハブでは F9 でも同じことができます"
	row.add_child(_skip_check)
	return panel


## 「すぐドラフトへ」が入っているか（テスト用に外からも切り替えられる）
func set_skip_to_draft(on: bool) -> void:
	_skip_check.button_pressed = on


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
	GameState.new_game(team, start_year)
	if _skip_check.button_pressed:
		_sub_label.text = "%d年のシーズンを消化中…" % start_year
		await get_tree().process_frame
		await get_tree().process_frame
		GameState.skip_to_phase(SKIP_TARGET)
	get_tree().change_scene_to_file(HUB_SCENE)
