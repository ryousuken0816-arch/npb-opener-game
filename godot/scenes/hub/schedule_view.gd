class_name ScheduleView
extends Control
## 日程表画面（docs/references/README.md「schedule_pawapuro.webp」）。
##
## 史実の日程（GameState.season）を3日分ずつ、その日の全カードのタイルで表示する。
## 終了した試合は暗色＋スコア（ツールチップに勝敗投手）、雨天中止は「中止」、試合のない日は「試合なし」。
## 表示するのは前日・今日・翌日の3日間（今日の見出しは白抜き）。
##
## 試合を進める：「1日進める」「1週間進める」、日付（列）をクリックして選び「この日まで早送り」（ダブルクリックでも可）。
## 早送り中は上の帯に「〇月〇日（〇）終了まで早送り中」、右上に「早送り中止」。進行は GameState が1日ずつ行う。
## コントローラー：日付の列も十字キーで選べる（Ⓐで目標日に選び、選んだ列でもう一度Ⓐで早送り）。
## 早送り中はⒷで中止（ハブが処理）、LB/RB で順位表のセ・パ切り替え。

const DAYS_SHOWN := 3
const WEEK_DAYS := 7
const MONDAY := 1
## 早送りの目標に選んだ日の枠の色
const SELECT_COLOR := Color("ff8f00")

var _palette: UiTheme.Palette
var _day_offset := 0
## 早送りの目標に選んだ日（通し日数）。未選択は -1
var _selected_day := -1

var _status_label: Label
var _status_bar: PanelContainer
var _stop_button: Button
var _one_day_button: Button
var _one_week_button: Button
var _to_date_button: Button
var _days_box: HBoxContainer
var _standings: StandingsPanel
var _slider: HSlider
var _prev_button: Button
var _next_button: Button
## 早送り中か（始まった・終わったときにフォーカスを移すため）
var _was_fast_forwarding := false
var _focus_before_ff := -1
## 作り直す直前のフォーカスの位置（早送りが始まったときに覚えておく）
var _focus_at_render := -1
var _focus_day_at_render := -1
## 早送りを始めたときに日付の列を選んでいたらその日（通し日数）
var _focus_day_before_ff := -1


func _ready() -> void:
	_build_layout()


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	var bar_style := UiTheme.gloss(p.main, 8, 2, 3)
	bar_style.content_margin_top = 5
	bar_style.content_margin_bottom = 5 + bar_style.depth
	_status_bar.add_theme_stylebox_override("panel", bar_style)
	UiTheme.heading(_status_label, 20, p.on_main, UiTheme.outline_for(p.on_main, p.main), 6, false)
	_standings.setup(p, GameData.league_of(GameState.team))

	UiTheme.style_button(_one_day_button, p.main, p.on_main, 8, 3)
	_one_day_button.custom_minimum_size = Vector2(140, 38)
	UiTheme.style_button(_one_week_button, p.main.darkened(0.12), p.on_main, 8, 3)
	_one_week_button.custom_minimum_size = Vector2(160, 38)
	UiTheme.style_button(_to_date_button, Color("ff8f00"), Color.WHITE, 8, 3)
	_to_date_button.custom_minimum_size = Vector2(0, 38)
	for b: Button in [_prev_button, _next_button]:
		UiTheme.style_button(b, p.main.lerp(Color.WHITE, 0.3), p.ink, 6, 2)
		b.custom_minimum_size = Vector2(36, 32)
	for b: Button in [_prev_button, _next_button, _one_day_button, _one_week_button, _to_date_button]:
		b.add_theme_font_override("font", UiTheme.font(700))
	# 早送り中止は目立つ白地のボタン（参考画像の右上）
	UiTheme.style_button(_stop_button, Color.WHITE, p.ink, 20)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var st := _stop_button.get_theme_stylebox(state) as GlossBox
		st.border_color = p.main
		st.set_border_width_all(3)
	_stop_button.add_theme_font_override("font", UiTheme.font(800))


## ハブ画面から開かれるたび・日付が進むたびに呼ばれる。前日・今日・翌日を表示する。
func refresh() -> void:
	_slider.max_value = maxi(_season_day_count() - DAYS_SHOWN, 0)
	_day_offset = clampi(_anchor_offset(), 0, maxi(_season_day_count() - DAYS_SHOWN, 0))
	if not _is_selectable(_selected_day):
		_selected_day = -1
	_render()


## 早送りの目標に選べる日か（今日〜最終日）
func _is_selectable(day: int) -> bool:
	return (GameState.phase == GameState.Phase.SEASON and day >= GameState.day
			and day <= GameState.season_last_day())


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	root.add_child(top)
	_status_bar = PanelContainer.new()
	_status_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.clip_text = true
	_status_bar.add_child(_status_label)
	top.add_child(_status_bar)
	_stop_button = _make_button("■ 早送り中止", GameState.stop_fast_forward)
	_stop_button.custom_minimum_size = Vector2(170, 0)
	_stop_button.visible = false
	top.add_child(_stop_button)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)
	_one_day_button = _make_button("▶ 1日進める", _on_advance_days.bind(1))
	actions.add_child(_one_day_button)
	_one_week_button = _make_button("▶▶ 1週間進める", _on_advance_days.bind(WEEK_DAYS))
	actions.add_child(_one_week_button)
	_to_date_button = _make_button("", _on_fast_forward_to_selected)
	_to_date_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_to_date_button)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	var days_area := VBoxContainer.new()
	days_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	days_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	days_area.add_theme_constant_override("separation", 8)
	body.add_child(days_area)

	var days_scroll := ScrollContainer.new()
	days_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	days_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	days_area.add_child(days_scroll)
	_days_box = HBoxContainer.new()
	_days_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_days_box.add_theme_constant_override("separation", 8)
	days_scroll.add_child(_days_box)

	days_scroll.follow_focus = true
	_standings = StandingsPanel.new()
	_standings.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(_standings)

	# 下に日程全体のスライダー（両端の ◀ ▶ で3日ずつ）
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	days_area.add_child(nav)
	_prev_button = _make_button("◀", _shift.bind(-DAYS_SHOWN))
	_prev_button.tooltip_text = "前の3日間"
	nav.add_child(_prev_button)
	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.step = 1
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(_on_slider_changed)
	nav.add_child(_slider)
	_next_button = _make_button("▶", _shift.bind(DAYS_SHOWN))
	_next_button.tooltip_text = "次の3日間"
	nav.add_child(_next_button)


func _make_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(on_pressed)
	return b


## 日程表を開いたとき：「1日進める」（押せなければ最初の項目）にフォーカス
func focus_default() -> void:
	if not UiInput.grab(_one_day_button):
		UiInput.focus_first(self)


## LB/RB：順位表のセ・パ切り替え
func switch_tab(delta: int) -> void:
	_standings.turn(delta)


## 今日から days 日分（今日を含む）の試合を早送りで進める
func _on_advance_days(days: int) -> void:
	GameState.start_fast_forward(GameState.day + days - 1)


func _on_fast_forward_to_selected() -> void:
	if _is_selectable(_selected_day):
		GameState.start_fast_forward(_selected_day)


## 日付の列をクリック：早送りの目標に選ぶ（ダブルクリックならすぐ早送り）。
## コントローラー・キーボードは Ⓐ（Enter）で選び、選んである列でもう一度 Ⓐ で早送り
func _on_day_clicked(event: InputEvent, day: int) -> void:
	var click := event as InputEventMouseButton
	var accept := event.is_action_pressed("ui_accept") and not event.is_echo()
	if not accept and (click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT):
		return
	if accept:
		get_viewport().set_input_as_handled()
	if GameState.is_fast_forwarding() or not _is_selectable(day):
		return
	if (click != null and click.double_click) or (accept and _selected_day == day):
		_selected_day = day
		GameState.start_fast_forward(day)
		return
	_selected_day = day
	_render()


func _shift(delta: int) -> void:
	_day_offset = clampi(_day_offset + delta, 0, maxi(_season_day_count() - DAYS_SHOWN, 0))
	_render()


func _on_slider_changed(value: float) -> void:
	var offset := int(value)
	if offset == _day_offset:
		return
	_day_offset = offset
	_render()


## 開幕日から最終日までの日数（日程データが無ければ 0）
func _season_day_count() -> int:
	var season := GameState.season
	if season == null or season.games.is_empty():
		return 0
	return season.last_day() - season.first_day() + 1


## 表示する位置（開幕日からの日数）：前日・今日・翌日の3日間。シーズン後は最後の3日間
func _anchor_offset() -> int:
	var season := GameState.season
	if season == null or season.games.is_empty():
		return 0
	if GameState.phase != GameState.Phase.SEASON:
		return _season_day_count() - DAYS_SHOWN
	return GameState.day - 1 - season.first_day()


func _render() -> void:
	# 日付の列にフォーカスがあれば、作り直したあとも同じ日の列に戻す
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	_focus_at_render = UiInput.focus_index(self) if is_inside_tree() else -1
	var focus_day := -1
	if focused != null and _days_box.is_ancestor_of(focused):
		focus_day = int(focused.get_meta("day", -1))
	_focus_day_at_render = focus_day
	for child in _days_box.get_children():
		_days_box.remove_child(child)
		child.queue_free()
	_standings.refresh()
	_update_controls()
	var season := GameState.season
	if season == null or season.games.is_empty():
		if GameState.phase == GameState.Phase.SEASON:
			_status_label.text = "今日は%s（%d年の日程データがないため試合はありません）" % [
				Season.day_label(GameState.day), GameState.year]
		else:
			_status_label.text = "%d年の日程データがありません" % GameState.year
		_prev_button.disabled = true
		_next_button.disabled = true
		return

	_slider.set_value_no_signal(_day_offset)
	var max_offset := maxi(_season_day_count() - DAYS_SHOWN, 0)
	_prev_button.disabled = _day_offset <= 0
	_next_button.disabled = _day_offset >= max_offset
	for i in DAYS_SHOWN:
		var day := season.first_day() + _day_offset + i
		if day > season.last_day():
			break
		_days_box.add_child(_make_day_column(day))
	_link_focus()
	if focus_day >= 0:
		var frames := _days_box.get_children()
		var target: Control = null
		for f: Control in frames:
			if int(f.get_meta("day", -1)) == focus_day and f.focus_mode == Control.FOCUS_ALL:
				target = f
		if target == null:
			target = UiInput.first_focusable(_days_box)
		if target != null:
			target.grab_focus()
		else:
			focus_default()

	if GameState.is_fast_forwarding():
		_status_label.text = "%s 終了まで早送り中" % Season.day_label(GameState.fast_forward_target)
	elif GameState.phase != GameState.Phase.SEASON or season.is_finished():
		_status_label.text = "全日程終了（%d試合）" % season.played_count()
	elif GameState.day == season.first_day():
		_status_label.text = "開幕前　%s 開幕" % Season.day_label(season.first_day())
	else:
		_status_label.text = "今日は%s　これまでに%d試合が終了" % [
			Season.day_label(GameState.day), season.played_count()]


## 進行ボタンの状態（早送り中は中止ボタンだけ、シーズン後はすべて無効）
func _update_controls() -> void:
	var fast_forwarding := GameState.is_fast_forwarding()
	var in_season := GameState.phase == GameState.Phase.SEASON
	_stop_button.visible = fast_forwarding
	# 早送りが始まったら「早送り中止」へ、終わったら元の項目へフォーカスを移す
	if fast_forwarding and not _was_fast_forwarding and is_visible_in_tree():
		_focus_before_ff = _focus_at_render
		_focus_day_before_ff = _focus_day_at_render
		_stop_button.grab_focus.call_deferred()
	elif not fast_forwarding and _was_fast_forwarding and is_visible_in_tree():
		_restore_focus_after_ff.call_deferred()
	_was_fast_forwarding = fast_forwarding
	_one_day_button.disabled = fast_forwarding or not in_season
	_one_week_button.disabled = fast_forwarding or not in_season
	_to_date_button.disabled = fast_forwarding or not _is_selectable(_selected_day)
	if _is_selectable(_selected_day):
		_to_date_button.text = "▶▶▶ %s 終了まで早送り" % Season.day_label(_selected_day)
	elif in_season:
		_to_date_button.text = "日付をクリックして選ぶと、その日まで早送り"
	else:
		_to_date_button.text = "シーズン終了"


## 十字キーの移動先：日付の列の上下は進行ボタンとスライダー。スライダーの行（◀ ▶ はスライダーより
## 背が高いので、自動では上に選ばれてしまう）から上は日付の列へ
func _link_focus() -> void:
	var frames: Array[Control] = []
	for f: Control in _days_box.get_children():
		if f.focus_mode == Control.FOCUS_ALL:
			frames.append(f)
	var up_target: Control = frames[0] if not frames.is_empty() else _one_day_button
	for c: Control in [_prev_button, _slider, _next_button]:
		c.focus_neighbor_top = c.get_path_to(up_target)
	for f in frames:
		f.focus_neighbor_bottom = f.get_path_to(_slider)
		f.focus_neighbor_top = f.get_path_to(_one_day_button if not _one_day_button.disabled
			else _to_date_button)


func _restore_focus_after_ff() -> void:
	var owner_control := get_viewport().gui_get_focus_owner()
	if owner_control != null and owner_control != _stop_button and is_ancestor_of(owner_control):
		return
	# 日付の列から早送りしたときは、同じ日の列（表示から外れていれば最初の列）へ
	if _focus_day_before_ff >= 0:
		for f: Control in _days_box.get_children():
			if int(f.get_meta("day", -1)) == _focus_day_before_ff and UiInput.grab(f):
				return
		if UiInput.focus_first(_days_box):
			return
	if _focus_before_ff >= 0:
		UiInput.focus_nth(self, _focus_before_ff)
	else:
		focus_default()


func _make_day_column(day: int) -> Control:
	var is_today := GameState.phase == GameState.Phase.SEASON and day == GameState.day
	var target := GameState.fast_forward_target if GameState.is_fast_forwarding() else _selected_day
	# 列全体を枠で包み、クリックで早送りの目標日に選べるようにする（選んだ日は橙の枠）
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(145, 0)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var frame_style := UiTheme.box(Color.TRANSPARENT, 10)
	frame_style.set_content_margin_all(3)
	if day == target:
		frame_style = UiTheme.box(Color(SELECT_COLOR, 0.18), 10, SELECT_COLOR, 3)
		frame_style.set_content_margin_all(3)
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.set_meta("day", day)
	if _is_selectable(day):
		frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		frame.tooltip_text = "クリック（Ⓐ）で選択、ダブルクリック（選んだ列でもう一度Ⓐ）でこの日まで早送り"
		frame.focus_mode = Control.FOCUS_ALL
		# フォーカス中は黄色い光の枠でゆっくり明滅（ボタンと同じ見た目）
		var focus_style := frame_style.duplicate() as StyleBoxFlat
		focus_style.border_color = UiTheme.FOCUS
		focus_style.set_border_width_all(3)
		focus_style.shadow_color = Color(UiTheme.FOCUS, 0.55)
		focus_style.shadow_size = 7
		frame.focus_entered.connect(func() -> void:
			frame.add_theme_stylebox_override("panel", focus_style)
			UiFx.pulse(frame))
		frame.focus_exited.connect(func() -> void:
			frame.add_theme_stylebox_override("panel", frame_style)
			var tw: Tween = frame.get_meta("_pulse") if frame.has_meta("_pulse") else null
			if tw != null:
				tw.kill()
			frame.self_modulate = Color.WHITE)
	frame.gui_input.connect(_on_day_clicked.bind(day))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	frame.add_child(column)

	var header := Label.new()
	header.text = Season.day_label(day)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.clip_text = true
	# 「10月10日（金）」など長い日付は列に収まるよう小さくする
	var header_ink := _palette.ink if is_today else _palette.on_main
	UiTheme.heading(header, 18 if header.text.length() <= 8 else 16, header_ink,
		UiTheme.outline_for(header_ink, Color.WHITE if is_today else _palette.main), 5, false)
	var header_panel := PanelContainer.new()
	header_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	# 今日は白抜きの見出し
	var header_style := UiTheme.gloss(_palette.main, 8, 2, 3)
	header_style.content_margin_top = 3
	header_style.content_margin_bottom = 3 + header_style.depth
	if is_today:
		header_style = UiTheme.gloss(Color.WHITE, 8, 3, 0, _palette.main)
		header_style.content_margin_top = 3
		header_style.content_margin_bottom = 3
	header_panel.add_theme_stylebox_override("panel", header_style)
	header_panel.add_child(header)
	column.add_child(header_panel)

	var games: Array = GameState.season.games_on(Season.date_of_day(day))
	if games.is_empty():
		var rest_panel := PanelContainer.new()
		rest_panel.mouse_filter = Control.MOUSE_FILTER_PASS
		var rest_style := UiTheme.card(UiTheme.LINE, 8, 1, 0.85)
		rest_style.shadow_size = 2
		rest_panel.add_theme_stylebox_override("panel", rest_style)
		rest_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var rest_label := Label.new()
		var weekday: int = Time.get_datetime_dict_from_unix_time(day * Season.DAY_SECONDS)["weekday"]
		rest_label.text = "移動日" if weekday == MONDAY else "試合なし"
		rest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rest_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UiTheme.heading(rest_label, 26, UiTheme.TEXT_SUB, Color.WHITE, 6, true)
		rest_panel.add_child(rest_label)
		column.add_child(rest_panel)
		return frame

	# セ・パの試合を左右の列に分け、その日の全カードがスクロールなしで見えるようにする。
	# 交流戦の日は主催が片方のリーグに偏るので、半分ずつに分ける
	var columns := {"C": [], "P": []}
	var titles := {}
	var interleague := games.any(func(g: Dictionary) -> bool: return g["kind"] == "interleague")
	if interleague:
		var half := ceili(games.size() / 2.0)
		columns = {"C": games.slice(0, half), "P": games.slice(half)}
		titles = {"C": "交流戦", "P": ""}
	else:
		for g: Dictionary in games:
			columns[GameState.season.leagues.get(g["home"], "C")].append(g)
		for league: String in columns:
			titles[league] = GameData.LEAGUE_NAMES.get(league, league).left(1)
	var leagues_row := HBoxContainer.new()
	leagues_row.mouse_filter = Control.MOUSE_FILTER_PASS
	leagues_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	leagues_row.add_theme_constant_override("separation", 4)
	column.add_child(leagues_row)
	for league in ["C", "P"]:
		leagues_row.add_child(_make_league_column(titles[league], columns[league]))
	return frame


func _make_league_column(title: String, games: Array) -> VBoxContainer:
	var league_col := VBoxContainer.new()
	league_col.mouse_filter = Control.MOUSE_FILTER_PASS
	league_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	league_col.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_font_override("font", UiTheme.font(700))
	label.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
	label.custom_minimum_size.y = 14
	league_col.add_child(label)
	for g: Dictionary in games:
		league_col.add_child(_make_game_tile(g))
	return league_col


func _make_game_tile(g: Dictionary) -> PanelContainer:
	var home: String = g["home"]
	var away: String = g["away"]
	var result: Dictionary = g["result"]
	var finished := not result.is_empty()
	var canceled: bool = g["status"] != "played"
	var is_own_game := home == GameState.team or away == GameState.team
	var tile := PanelContainer.new()
	var style: GlossBox
	if finished:
		style = UiTheme.gloss(Color("374151"), 8, 1, 0, Color("1f2937"))
		style.gloss = 0.3
	elif canceled:
		style = UiTheme.gloss(Color("e3e6ea"), 8, 1, 0, Color("d5dae0"))
		style.gloss = 0.3
	else:
		style = UiTheme.gloss(Color(1, 1, 1, 0.97), 8, 1, 0, Color("d5dae0"))
		style.gradient = 0.06
		style.gloss = 0.0
	style.shadow_size = 2
	style.shadow_color = Color(0, 0, 0, 0.15)
	if is_own_game:
		style.border_color = _palette.main
		style.set_border_width_all(3)
		style.shadow_color = Color(_palette.main, 0.35)
		style.shadow_size = 4
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	tile.add_theme_stylebox_override("panel", style)
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	if finished:
		tile.tooltip_text = _result_tooltip(g)

	# 縦積み（アウェイ→中央→ホーム）にして、列を細くしても読めるようにする
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	tile.add_child(box)
	box.add_child(_make_team_chip(away))

	var mid_label := Label.new()
	mid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid_label.clip_text = true
	mid_label.add_theme_font_size_override("font_size", 13)
	mid_label.add_theme_font_override("font", UiTheme.font(800))
	if finished:
		mid_label.text = "%d－%d" % [result["away_score"], result["home_score"]]
		mid_label.add_theme_color_override("font_color", Color.WHITE)
		mid_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		mid_label.add_theme_constant_override("outline_size", 4)
	elif canceled:
		mid_label.text = "中止"
		mid_label.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
	else:
		mid_label.text = "vs"
		mid_label.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
	box.add_child(mid_label)
	box.add_child(_make_team_chip(home))

	var stadium_label := Label.new()
	stadium_label.text = g["venue"] if not str(g["venue"]).is_empty() else "-"
	stadium_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stadium_label.clip_text = true
	stadium_label.add_theme_font_size_override("font_size", 10)
	stadium_label.add_theme_color_override(
			"font_color", Color(1, 1, 1, 0.75) if finished else UiTheme.TEXT_SUB)
	box.add_child(stadium_label)

	return tile


## 終了した試合のツールチップ（スコアと勝敗・セーブ投手）
func _result_tooltip(g: Dictionary) -> String:
	var result: Dictionary = g["result"]
	var season := GameState.season
	var lines := PackedStringArray()
	lines.append("%s %d－%d %s%s" % [
		GameData.short_name(g["away"]), result["away_score"], result["home_score"],
		GameData.short_name(g["home"]), "（延長%d回）" % result["innings"] if result["innings"] > 9 else ""])
	if result["win"].is_empty():
		lines.append("引き分け")
	else:
		lines.append("勝：%s　敗：%s" % [
			season.player_name(result["win"]), season.player_name(result["lose"])])
		if not result["save"].is_empty():
			lines.append("S：%s" % season.player_name(result["save"]))
	return "\n".join(lines)


func _make_team_chip(team: String) -> PanelContainer:
	var colors: Array[Color] = GameData.team_colors(team)
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UiTheme.gloss(colors[0], 6, 0, 0)
	style.shadow_size = 0
	style.gradient = 0.22
	style.gloss = 0.5
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 0
	style.content_margin_bottom = 0
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
