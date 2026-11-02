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
var _mode_button: Button
var _mobile_tabs: HBoxContainer
var _selected_mobile_league: String = "C"

@onready var _title_label: Label = %TitleLabel
@onready var _sub_label: Label = %SubLabel
@onready var _leagues: HBoxContainer = %Leagues
@onready var _center: CenterContainer = $Center
@onready var _vbox: VBoxContainer = $Center/VBox
## スマホのときだけ中身を包むスクロール（横向きでは縦に入らないので）
var _scroll: ScrollContainer


func _ready() -> void:
	UiLayout.set_sub_screen_active(false)
	var palette := UiTheme.neutral_palette()
	theme = UiTheme.build(palette)
	_update_title_typography(palette)
	var guide := PadGuide.new()
	guide.set_items([["A", "決定"], ["LB/RB", "開始年"]])
	add_child(guide)
	guide.position = Vector2(size.x - guide.size.x - 24, 5)
	resized.connect(func() -> void: guide.position = Vector2(size.x - guide.size.x - 24, 5))
	UiFx.install(self)
	_debug_row = _make_debug_row()
	_vbox.add_child(_debug_row)
	_make_continue(palette)
	_make_mobile_tabs(palette)
	_make_mode_toggle_button()
	if not UiLayout.layout_changed.is_connected(_on_layout_changed):
		UiLayout.layout_changed.connect(_on_layout_changed)
	_apply_layout(UiLayout.is_portrait, UiLayout.is_mobile)
	_build_teams()
	if _continue_button.visible:
		_continue_button.grab_focus()
	else:
		UiInput.focus_first(_leagues)
	UiFx.fade_in(_vbox)


func _update_title_typography(palette: UiTheme.Palette) -> void:
	var title_size := 34 if UiLayout.is_portrait else 52
	UiTheme.heading(_title_label, title_size, palette.ink, Color.WHITE, 12 if UiLayout.is_portrait else 14)
	_title_label.label_settings.shadow_color = Color(palette.ink.darkened(0.4), 0.45)
	_title_label.label_settings.shadow_offset = Vector2(2, 4)
	UiTheme.heading(_sub_label, 16 if UiLayout.is_portrait else 20, UiTheme.TEXT, Color.WHITE, 5, false)


func _make_mode_toggle_button() -> void:
	_mode_button = Button.new()
	_mode_button.custom_minimum_size = Vector2(44, 38)
	_mode_button.focus_mode = Control.FOCUS_NONE
	_mode_button.tooltip_text = "画面表示の切り替え（パソコンの表示 / スマホの表示）"
	_update_mode_button_text()
	UiTheme.style_button(_mode_button, Color("455a64"), Color.WHITE, 6, 2)
	_mode_button.pressed.connect(func() -> void:
		UiLayout.toggle_mode())
	add_child(_mode_button)
	_update_mode_button_position()
	resized.connect(_update_mode_button_position)


func _update_mode_button_position() -> void:
	if _mode_button != null and is_instance_valid(_mode_button):
		# スマホ（とスマホでPC表示にしているとき）だけ出す。パソコンの見た目は変えない
		_mode_button.visible = UiLayout.on_phone()
		_mode_button.reset_size()
		_mode_button.position = Vector2(size.x - _mode_button.size.x - 12, UiLayout.safe_area_top + 10)


func _update_mode_button_text() -> void:
	if _mode_button != null:
		_mode_button.text = "PC表示" if UiLayout.is_mobile else "📱 スマホ表示"


func _make_mobile_tabs(palette: UiTheme.Palette) -> void:
	_mobile_tabs = HBoxContainer.new()
	_mobile_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_mobile_tabs.add_theme_constant_override("separation", 12)
	_mobile_tabs.visible = false
	var vbox: VBoxContainer = _vbox
	vbox.add_child(_mobile_tabs)
	vbox.move_child(_mobile_tabs, _leagues.get_index())
	for league: String in GameData.LEAGUE_NAMES:
		var btn := Button.new()
		btn.text = GameData.LEAGUE_NAMES[league]
		btn.custom_minimum_size = Vector2(140, 44)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_font_override("font", UiTheme.font(800))
		btn.pressed.connect(func() -> void:
			_selected_mobile_league = league
			_build_teams())
		_mobile_tabs.add_child(btn)


func _on_layout_changed(is_portrait: bool, is_mobile: bool) -> void:
	_update_mode_button_text()
	_update_mode_button_position()
	var palette := UiTheme.neutral_palette()
	_update_title_typography(palette)
	_apply_layout(is_portrait, is_mobile)
	_build_teams()


func _apply_layout(is_portrait: bool, _is_mobile: bool) -> void:
	_wrap_scroll(UiLayout.is_mobile)
	var center: Control = _scroll if UiLayout.is_mobile else _center
	if is_portrait:
		center.offset_top = UiLayout.safe_area_top + 10 + (UiLayout.touch_units() if UiLayout.on_phone() else 0.0)
		center.offset_bottom = -UiLayout.safe_area_bottom - 10
		_leagues.alignment = BoxContainer.ALIGNMENT_CENTER
		_mobile_tabs.visible = true
	else:
		center.offset_top = 0
		center.offset_bottom = 0
		_mobile_tabs.visible = false


## スマホ：中央の入れ物をスクロールで包む（パソコンでは包まない＝見た目を変えない）
func _wrap_scroll(on: bool) -> void:
	if on and _scroll == null:
		_scroll = ScrollContainer.new()
		_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.set_meta("fit_guard", true)
		add_child(_scroll)
		move_child(_scroll, _center.get_index())
		_center.reparent(_scroll, false)
		_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	elif not on and _scroll != null:
		_center.reparent(self, false)
		move_child(_center, _scroll.get_index())
		_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_scroll.queue_free()
		_scroll = null


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

	if UiLayout.is_portrait:
		# スマホ縦画面：タブで選ばれたリーグのみ表示
		_sync_mobile_tabs()
		_leagues.add_child(_make_league_column(_selected_mobile_league))
	else:
		# PC横画面：セ・パ横並び
		for league: String in GameData.LEAGUE_NAMES:
			_leagues.add_child(_make_league_column(league))


func _sync_mobile_tabs() -> void:
	if _mobile_tabs == null or not is_instance_valid(_mobile_tabs):
		return
	var idx := 0
	for league: String in GameData.LEAGUE_NAMES:
		if idx < _mobile_tabs.get_child_count():
			var btn := _mobile_tabs.get_child(idx) as Button
			if btn != null:
				var is_sel := (league == _selected_mobile_league)
				var color := (Color("1e88e5") if league == "C" else Color("2e7d32"))
				if is_sel:
					UiTheme.style_button(btn, color, Color.WHITE, 8, 3)
				else:
					UiTheme.style_button(btn, color.darkened(0.4), Color(1, 1, 1, 0.7), 8, 1)
		idx += 1


## 「続きから」のボタンと、セーブの枠の一覧（最初は隠しておく）
func _make_continue(palette: UiTheme.Palette) -> void:
	var vbox: VBoxContainer = _vbox
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
	column.custom_minimum_size = Vector2(480 if UiLayout.is_portrait else 320, 0)
	column.add_theme_constant_override("separation", 10 if UiLayout.is_portrait else 8)
	var league_color := Color("1e88e5") if league == "C" else Color("2e7d32")
	var header_panel := PanelContainer.new()
	var header_style := UiTheme.gloss(league_color, 8, 2, 3)
	header_style.content_margin_top = 4
	header_style.content_margin_bottom = 4 + header_style.depth
	header_panel.add_theme_stylebox_override("panel", header_style)
	var header := Label.new()
	header.text = GameData.LEAGUE_NAMES[league]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(header, 22, Color.WHITE, league_color.darkened(0.5), 6, false)
	header_panel.add_child(header)
	column.add_child(header_panel)
	for team in GameData.teams(league):
		column.add_child(_make_team_button(team))
	return column


## 球団カラーの立体ボタン（メイン色の地、左にサブ色の太い帯と縁取り）
func _make_team_button(team: String) -> Button:
	var colors := GameData.team_colors(team)
	var button := Button.new()
	button.text = team
	button.custom_minimum_size = Vector2(0, 56 if UiLayout.is_portrait else 46)
	button.add_theme_font_size_override("font_size", 23 if UiLayout.is_portrait else 20)
	button.add_theme_font_override("font", UiTheme.font(800))
	var ink := UiTheme.text_on(colors[0])
	UiTheme.style_button(button, colors[0], ink)
	button.add_theme_color_override("font_outline_color", UiTheme.outline_for(ink, colors[0]))
	button.add_theme_constant_override("outline_size", 6)
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
