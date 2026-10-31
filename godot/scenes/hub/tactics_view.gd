class_name TacticsView
extends HBoxContainer
## 「采配」画面（docs/references/README.md「saihai_menu_pawapuro.webp」）。
##
## 左にサブメニュー、右に選んだ画面。最初は全選手を1軍・2軍に分けた名前札の一覧（守備位置の色。押すと選手詳細）。
## - 投手1軍登録／野手1軍登録 … RegisterPage
## - 起用設定 … OrderPage（DHあり／なしのスタメンと控え）
## - 思考設定 … 采配方針（送りバント・盗塁の積極性・継投の傾向。docs/SPEC.md「采配」）
## - 選手一覧 … RosterView（能力のランクと今季の成績）
## - 情報 … InfoPage（12球団の年俸総額と自球団の年俸）
## - 練習設定・登録設定 … 未実装
## 編成は今季の自球団の SimTeam（GameState.my_team()）を直接書き換え、次の試合から反映される。
## コントローラー：サブメニューは十字キー＋Ⓐ、Ⓑで一覧→ハブへ戻る。LB/RB でサブ画面を順に切り替え
## （選手一覧ではタブを切り替え）。画面を開くと最初の項目にフォーカスする。

## 画面の見出し・説明文が変わった（ハブの見出しと下の帯に出す）
signal title_changed(text: String)
signal description_changed(text: String)

## [キー, ボタン名, 説明文, 実装済みか]
const MENUS := [
	["pitchers", "投手1軍登録", "投手の1軍・2軍を入れ替え、先発・中継ぎ・抑えの持ち場を決めます。", true],
	["fielders", "野手1軍登録", "野手の1軍・2軍を入れ替えます。", true],
	["practice", "練習設定", "選手ごとの練習（育成方針）を決めます。（未実装）", false],
	["order", "起用設定", "DHあり・なしのスタメン（打順と守備位置）と控えを決めます。", true],
	["strategy", "思考設定", "送りバント・盗塁・継投など、チームの采配方針を決めます。", true],
	["rules", "登録設定", "1・2軍の入れ替えを自動で行うかなどを決めます。（未実装）", false],
	["info", "情報", "12球団の年俸総額と、自球団の選手の年俸を見ます。", true],
	["list", "選手一覧", "所属選手の能力（ランク）と今季の打撃成績・投手成績を見ます。", true],
]
const HOME_DESCRIPTION := "1・2軍の入れ替え、オーダーや起用法の設定、所属選手の確認をします。"

## 采配方針 [キー, 見出し, 説明, 5段階の名前]
const TACTICS := [
	["bunt", "送りバント",
		"無死一塁・二塁で、打力の低い打者に送りバントをさせる頻度です。「使わない」でも投手は送りバントをすることがあります。",
		["使わない", "少なめ", "普通", "多め", "積極的"]],
	["steal", "盗塁",
		"走者が盗塁を試みる頻度です。積極的にすると足の遅い走者も走るため、成功率は下がります。",
		["しない", "少なめ", "普通", "多め", "積極的"]],
	["relief", "継投",
		"先発投手をどこまで引っ張るかです。継投寄りにすると先発を早めに代え、救援投手を多く使います。",
		["先発完投型", "先発重視", "普通", "継投重視", "早めの継投"]],
]

var _palette: UiTheme.Palette
var _page := ""
var _menu_buttons := {}
var _names := {}

var _content: Control
var _home: VBoxContainer
var _register_pitchers: RegisterPage
var _register_fielders: RegisterPage
var _order: OrderPage
var _strategy: VBoxContainer
var _roster: RosterView
var _info: InfoPage
var _placeholder: Label


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	add_theme_constant_override("separation", 14)
	add_child(_build_menu())
	_content = Control.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_content)

	_home = VBoxContainer.new()
	_register_pitchers = RegisterPage.new()
	_register_pitchers.setup(p, true)
	_register_fielders = RegisterPage.new()
	_register_fielders.setup(p, false)
	_order = OrderPage.new()
	_order.setup(p)
	_strategy = VBoxContainer.new()
	_strategy.add_theme_constant_override("separation", 12)
	_roster = RosterView.new()
	_info = InfoPage.new()
	_info.setup(p)
	_placeholder = Label.new()
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder.add_theme_font_size_override("font_size", 22)
	for page: Control in _pages():
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.visible = false
		_content.add_child(page)


## ハブから開かれたとき：サブメニューの一覧（1軍・2軍の名前札）から始める
func open() -> void:
	_show_page("")
	_menu_buttons[MENUS[0][0]].grab_focus()


## 戻る（Esc・Ⓑ）：札を選んでいれば選択の取り消し、サブ画面なら一覧へ戻って true、一覧なら false（ハブが采配を閉じる）
func back() -> bool:
	if _page.is_empty():
		return false
	# 1軍登録・起用設定で札を選んでいるときは、まず選択を取り消す
	match _page:
		"pitchers":
			if _register_pitchers.clear_selection():
				return true
		"fielders":
			if _register_fielders.clear_selection():
				return true
		"order":
			if _order.clear_selection():
				return true
	var left := _page
	_show_page("")
	if _menu_buttons.has(left):
		_menu_buttons[left].grab_focus()
	return true


## LB/RB：実装済みのサブ画面を順に切り替える（選手一覧ではタブを切り替える）
func switch_tab(delta: int) -> void:
	if _page == "list" and _roster.get_tab_count() > 1:
		var next := _roster.current_tab + delta
		if next >= 0 and next < _roster.get_tab_count():
			_roster.switch_tab(delta)
			return
	var keys: Array[String] = [""]
	for menu: Array in MENUS:
		if menu[3]:
			keys.append(menu[0])
	var i := keys.find(_page)
	_show_page(keys[posmod(i + delta, keys.size())], true)


## 日付が進んだときなど（表示中の画面を作り直す）
func refresh() -> void:
	match _page:
		"":
			_render_home()
		"pitchers":
			_register_pitchers.refresh()
		"fielders":
			_register_fielders.refresh()
		"order":
			_order.refresh()
		"strategy":
			_render_strategy()
		"list":
			_roster.show_team(GameState.team)
		"info":
			_info.refresh()


func _build_menu() -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.card(_palette.main.lerp(Color.WHITE, 0.3), 12, 3, 0.92)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(200, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	var head := Label.new()
	head.text = "MENU"
	UiTheme.heading(head, 20, _palette.ink, Color.WHITE, 6)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	for menu: Array in MENUS:
		var b := Button.new()
		b.text = menu[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_override("font", UiTheme.font(800))
		b.add_theme_font_size_override("font_size", 21)
		_style_menu_button(b, menu[3])
		b.pressed.connect(_show_page.bind(menu[0], true))
		# 説明文はマウスを乗せたとき・十字キーで選んだときに出す
		b.focus_entered.connect(func() -> void: description_changed.emit(menu[2]))
		b.focus_exited.connect(func() -> void: description_changed.emit(_page_description()))
		b.mouse_entered.connect(func() -> void: description_changed.emit(menu[2]))
		b.mouse_exited.connect(func() -> void:
			if not b.has_focus():
				description_changed.emit(_page_description()))
		box.add_child(b)
		_menu_buttons[menu[0]] = b
	return panel


func _style_menu_button(b: Button, implemented: bool) -> void:
	UiTheme.style_toggle(b, Color("1d4f73") if implemented else Color("9aa7b2"))


## focus_page：開いた画面の最初の項目にフォーカスを移す（メニューをⒶで押したとき・LB/RB）
func _show_page(key: String, focus_page: bool = false) -> void:
	var changed := key != _page
	_page = key
	for k: String in _menu_buttons:
		_menu_buttons[k].set_pressed_no_signal(k == key)
	for page: Control in _pages():
		page.visible = false
	var title := "采配"
	match key:
		"":
			_home.visible = true
			_render_home()
		"pitchers":
			_register_pitchers.visible = true
			_register_pitchers.refresh(true)
		"fielders":
			_register_fielders.visible = true
			_register_fielders.refresh(true)
		"order":
			_order.visible = true
			_order.refresh(true)
		"strategy":
			_strategy.visible = true
			_render_strategy()
		"list":
			_roster.visible = true
			_roster.show_team(GameState.team)
		"info":
			_info.visible = true
			_info.refresh()
		_:
			_placeholder.visible = true
			_placeholder.text = "（未実装）"
	for menu: Array in MENUS:
		if menu[0] == key:
			title += " ― " + menu[1]
	title_changed.emit(title)
	description_changed.emit(_page_description())
	var shown := _current_page()
	if changed and shown != null:
		UiFx.fade_in(shown)
	if focus_page:
		_focus_page.call_deferred()


func _current_page() -> Control:
	for page: Control in _pages():
		if page.visible:
			return page
	return null


func _focus_page() -> void:
	match _page:
		"pitchers":
			_register_pitchers.focus_first()
		"fielders":
			_register_fielders.focus_first()
		"order":
			_order.focus_first()
		"list":
			_roster.focus_content()
		"info":
			_info.focus_first()
		"strategy":
			for b in UiInput.focusables(_strategy):
				if b is Button and (b as Button).button_pressed:
					b.grab_focus()
					return
			UiInput.focus_first(_strategy)
		"":
			if not UiInput.focus_first(_home):
				_menu_buttons[MENUS[0][0]].grab_focus()
		_:
			if _menu_buttons.has(_page):
				_menu_buttons[_page].grab_focus()


func _pages() -> Array[Control]:
	return [_home, _register_pitchers, _register_fielders, _order, _strategy, _roster, _info,
		_placeholder]


func _page_description() -> String:
	for menu: Array in MENUS:
		if menu[0] == _page:
			return menu[2]
	return HOME_DESCRIPTION


func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


# --- 一覧（1軍・2軍の名前札）-----------------------------------------------------------

func _render_home() -> void:
	_clear(_home)
	_home.add_theme_constant_override("separation", 8)
	var team := GameState.my_team()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_home.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	if team == null:
		box.add_child(UiTheme.small_label("日程データのない年は1軍・2軍の編成がありません。「選手一覧」で所属選手を見られます。",
				18, UiTheme.TEXT))
		return
	_names = NameTag.short_names(team.players)
	var actives: Array[SimPlayer] = []
	actives.append_array(team.rotation)
	if team.closer != null:
		actives.append(team.closer)
	actives.append_array(team.relievers)
	var fielders := team.active_players(false)
	fielders.sort_custom(_fielder_before)
	actives.append_array(fielders)
	var farm := team.players_where(false, true)
	farm.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool: return a.overall > b.overall)
	var farm_fielders := team.players_where(false, false)
	farm_fielders.sort_custom(_fielder_before)
	farm.append_array(farm_fielders)
	var fc := team.foreign_counts()
	var active_text := "%d/%d人\n投%d 野%d\n外国人%d" % [team.active_count(),
		RosterRules.roster_limit(team.year), team.active_players(true).size(), fielders.size(),
		fc[0] + fc[1]]
	# 札を押すと選手詳細。十字キーの前後はこの一覧の並び（1軍→2軍）
	var ids: Array[String] = []
	for p in actives + farm:
		ids.append(p.id)
	box.add_child(_tag_block("1軍", active_text, actives, ids))
	var line := ColorRect.new()
	line.color = _palette.main.lerp(Color.WHITE, 0.4)
	line.custom_minimum_size = Vector2(0, 3)
	box.add_child(line)
	box.add_child(_tag_block("2軍", "%d人" % farm.size(), farm, ids))


func _tag_block(title: String, sub: String, members: Array[SimPlayer],
		ids: Array[String]) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var head := VBoxContainer.new()
	head.custom_minimum_size = Vector2(96, 0)
	var badge := PanelContainer.new()
	var badge_style := UiTheme.gloss(_palette.main, 8, 2, 4)
	badge.add_theme_stylebox_override("panel", badge_style)
	var label := Label.new()
	label.text = title
	var outline := UiTheme.outline_for(_palette.on_main, _palette.main)
	UiTheme.heading(label, 30, _palette.on_main, outline, 7)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(label)
	head.add_child(badge)
	var sub_label := UiTheme.small_label(sub, 13)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(sub_label)
	row.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	for p in members:
		var tag := NameTag.new()
		# 6列＋見出しが采配の広げた画面（1280x720 で幅986、縦のスクロールバーを含む）に収まる幅
		tag.custom_minimum_size = Vector2(134, 34)
		tag.setup_player(GameData.player(p.id), _names.get(p.id, p.name))
		var pos := p.primary_pos if not p.primary_pos.is_empty() else "守備位置不明"
		tag.tooltip_text = "%s（%s）" % [p.name, pos]
		tag.pressed.connect(func() -> void: PlayerDetail.open(tag, p.id, ids))
		grid.add_child(tag)
	row.add_child(grid)
	return row


func _fielder_before(a: SimPlayer, b: SimPlayer) -> bool:
	var pa := GameData.pos_index(a.primary_pos if not a.primary_pos.is_empty() else null)
	var pb := GameData.pos_index(b.primary_pos if not b.primary_pos.is_empty() else null)
	if pa != pb:
		return pa < pb
	return a.batting_value() > b.batting_value()


# --- 思考設定（采配方針）-------------------------------------------------------------

func _render_strategy() -> void:
	_clear(_strategy)
	var editable := GameState.phase == GameState.Phase.SEASON or GameState.my_team() == null
	var note := UiTheme.small_label("チーム全体の采配方針です。次の試合から反映されます（CPU球団はすべて「普通」）。", 16)
	_strategy.add_child(note)
	for tactic: Array in TACTICS:
		var panel := UiTheme.titled_panel(_palette, tactic[1])
		var desc := UiTheme.small_label(tactic[2], 15, UiTheme.TEXT)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel["body"].add_child(desc)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var group := ButtonGroup.new()
		var current := int(GameState.tactics.get(tactic[0], 0))
		var labels: Array = tactic[3]
		for i in labels.size():
			var level := i + SimTeam.TACTIC_MIN
			var b := Button.new()
			b.text = labels[i]
			b.toggle_mode = true
			b.button_group = group
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(0, 40)
			b.disabled = not editable
			_style_menu_button(b, true)
			b.set_pressed_no_signal(level == current)
			b.pressed.connect(func() -> void: GameState.set_tactic(tactic[0], level))
			row.add_child(b)
		panel["body"].add_child(row)
		_strategy.add_child(panel["panel"])
