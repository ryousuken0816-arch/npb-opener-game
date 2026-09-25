class_name PlayerDetail
extends Control
## 選手詳細（選手名鑑。docs/references/README.md「player_detail_pawapuro.webp」、docs/SPEC.md「選手詳細」）。
##
## どの画面からでも `PlayerDetail.open(呼び出し元のノード, 選手ID, 前後に送る選手IDの並び)` で画面の上に重ねて開く
## （並びを省くと同じ球団の全選手：投手→野手の順）。上に名前札・背番号・球団・投打・年齢・身長体重・守備位置・
## 登録状況・今季成績の見出し、その下に4つのタブ：
##   概要 … 参考画像の「選手能力／投手能力／野手能力／守備・起用」。能力はランク＋数値＋実数値、特殊能力、守備適性
##   成績 … 今季（GameState.season）と史実の年度別1軍成績（data/<年>/players.json。今の年より前だけ）、通算
##   経歴 … 参考画像の「プロフィール」。生年月日・出身校〜経歴・ドラフト（年・順位）・所属球団の推移
##   契約 … 年俸のデータがまだ無いので未実装の表示
## 自球団と他球団で情報量は変えない（SPEC）。
## 操作：LB/RB（Q/E）でタブ、十字キー（↑↓←→）で前後の選手、Ⓑ（Esc）で閉じる。マウスは上のタブ・▲▼・閉じる。
## 開いている間はキー・コントローラーの入力をすべてここで受け、下の画面には渡さない。閉じると元のフォーカスに戻る。

signal closed

## [キー, タブ名, 色]
const TABS := [
	["summary", "概要", Color("1e88e5")],
	["stats", "成績", Color("e53935")],
	["career", "経歴", Color("2e9b48")],
	["contract", "契約", Color("8e5bd6")],
]
## 画面の端からの余白
const MARGIN := 20
## 能力の行 [キー, 見出し]
const BATTER_ROWS := [
	["meet", "ミート"], ["power", "パワー"], ["eye", "選球眼"], ["speed", "走力"],
	["defense", "守備"], ["arm", "肩"],
]
const PITCHER_ROWS := [["overall", "総合"], ["bb9", "制球"], ["stamina", "スタミナ"],
	["k9", "奪三振"], ["hr9", "被弾抑制"]]
## 特殊能力で悪いもの（赤い札）。それ以外は青い札
const BAD_ABILITIES := ["三振取れず", "四球病", "一発病"]
const ABILITY_SLOTS := 8
const POS_SHORT := {
	"捕手": "捕", "一塁手": "一", "二塁手": "二", "三塁手": "三", "遊撃手": "遊", "内野手": "内",
	"外野手": "外", "左翼手": "左", "中堅手": "中", "右翼手": "右", "指名打者": "指", "投手": "投",
}
## 右スティックで成績表を送る速さ（ピクセル/秒）
const STICK_SCROLL := 900.0

static var _current: PlayerDetail = null

var player_id := ""
var tab := 0

var _ids: Array[String] = []
var _index := 0
var _data: Dictionary = {}
var _page: Dictionary = {}
var _palette: UiTheme.Palette
var _team_name := ""
var _previous_focus: Control = null
var _layer: CanvasLayer = null

var _frame: PanelContainer
var _tab_buttons: Array[Button] = []
var _counter: Label
var _header: HBoxContainer
var _body: Control
var _scroll: ScrollContainer = null


## 選手詳細を開く（もう開いていればその選手に切り替える）。ids は十字キーで送る選手IDの並び
static func open(from: Node, id: String, ids: Array = []) -> PlayerDetail:
	if GameData.player(id).is_empty():
		return null
	if is_instance_valid(_current):
		_current._set_ids(id, ids)
		_current._show_player()
		return _current
	var tree := from.get_tree()
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	var layer := CanvasLayer.new()
	layer.layer = 50
	host.add_child(layer)
	var detail := PlayerDetail.new()
	detail._layer = layer
	detail._previous_focus = from.get_viewport().gui_get_focus_owner()
	detail._set_ids(id, ids)
	layer.add_child(detail)
	_current = detail
	return detail


## 開いている選手詳細（なければ null）
static func current() -> PlayerDetail:
	return _current if is_instance_valid(_current) else null


## 同じ球団の全選手の並び（投手：先発→救援・総合の高い順、野手：守備位置順・打力の高い順）
static func team_order(team: String) -> Array[String]:
	var pitchers: Array = []
	var fielders: Array = []
	for p: Dictionary in GameData.players_of(team):
		(pitchers if p["is_pitcher"] else fielders).append(p)
	pitchers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := _role_of(a) == "先発"
		var sb := _role_of(b) == "先発"
		if sa != sb:
			return sa
		return _rating_value(a, "pitching", "overall") > _rating_value(b, "pitching", "overall"))
	fielders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := GameData.pos_index(a["primary_pos"])
		var pb := GameData.pos_index(b["primary_pos"])
		if pa != pb:
			return pa < pb
		return _rating_value(a, "batting", "meet") + _rating_value(a, "batting", "power") \
			> _rating_value(b, "batting", "meet") + _rating_value(b, "batting", "power"))
	var result: Array[String] = []
	for p: Dictionary in pitchers + fielders:
		result.append(p["id"])
	return result


func _ready() -> void:
	# CanvasLayer の直下なので画面の大きさに合わせる（アンカーだけでは広がらない）
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.07, 0.14, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame = PanelContainer.new()
	add_child(_frame)
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE,
		MARGIN)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_frame.add_child(box)
	box.add_child(_build_top_bar())
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 12)
	box.add_child(_header)
	_body = MarginContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_body)
	UiFx.install(self)
	GameState.changed.connect(_show_player)
	get_viewport().gui_release_focus()
	UiInput.hide_tip()
	_show_player()
	UiFx.fade_in(_frame)


func _fit_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _exit_tree() -> void:
	if _current == self:
		_current = null


func close() -> void:
	if _current == self:
		_current = null
	if GameState.changed.is_connected(_show_player):
		GameState.changed.disconnect(_show_player)
	var focus := _previous_focus
	if _layer != null:
		_layer.queue_free()
	else:
		queue_free()
	if is_instance_valid(focus) and focus.is_visible_in_tree():
		focus.grab_focus()
	closed.emit()


## 開いている間はキー・コントローラーの入力をすべてここで受ける（下の画面には渡さない）
func _input(event: InputEvent) -> void:
	if event is InputEventMouse or not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed(UiInput.TAB_PREV):
		switch_tab(-1)
	elif event.is_action_pressed(UiInput.TAB_NEXT):
		switch_tab(1)
	elif event.is_action_pressed("ui_up", true) or event.is_action_pressed("ui_left", true):
		step(-1)
	elif event.is_action_pressed("ui_down", true) or event.is_action_pressed("ui_right", true):
		step(1)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# 右スティックの上下で成績表を送る
	if _scroll == null or not is_instance_valid(_scroll):
		return
	var axis := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(axis) > 0.3:
		_scroll.scroll_vertical += int(axis * STICK_SCROLL * delta)


## LB/RB：タブを順に切り替える（端から反対の端へ回る）
func switch_tab(delta: int) -> void:
	show_tab(posmod(tab + delta, TABS.size()))


func show_tab(i: int) -> void:
	tab = i
	_render_body()
	UiFx.fade_in(_body)


## 十字キー：並びの前後の選手へ（端から反対の端へ回る）
func step(delta: int) -> void:
	if _ids.size() <= 1:
		return
	_index = posmod(_index + delta, _ids.size())
	player_id = _ids[_index]
	_show_player()
	UiFx.fade_in(_frame)


func _set_ids(id: String, ids: Array) -> void:
	player_id = id
	_ids.clear()
	for x: Variant in ids:
		if not GameData.player(str(x)).is_empty():
			_ids.append(str(x))
	if not _ids.has(id):
		_ids = team_order(GameData.player(id).get("team", ""))
	if not _ids.has(id):
		_ids.append(id)
	_index = _ids.find(id)


func _show_player() -> void:
	if not is_inside_tree():
		return
	_data = GameData.player(player_id)
	_page = GameData.player_page(data_year(), player_id)
	_team_name = _data.get("team", "")
	_palette = UiTheme.team_palette(_team_name)
	theme = UiTheme.build(_palette)
	var style := UiTheme.card(_palette.main, 14, 4, 0.98)
	style.bg_color = _palette.main.lerp(Color.WHITE, 0.9)
	style.set_content_margin_all(14)
	_frame.add_theme_stylebox_override("panel", style)
	_counter.text = "%d / %d" % [_index + 1, _ids.size()]
	_style_tabs()
	_render_header()
	_render_body()


## 選手ページを読む年（能力値ファイルの年。無ければゲームの年）
func data_year() -> int:
	return int(GameData.ratings.get("year", GameState.year))


# --- 上の帯（タブ・前後の選手・閉じる）-------------------------------------------------

func _build_top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.add_child(_arrow_button("◀ LB", func() -> void: switch_tab(-1), "前のタブ（LB / Q）"))
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i][1]
		b.custom_minimum_size = Vector2(104, 44)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", UiTheme.font(800))
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(show_tab.bind(i))
		bar.add_child(b)
		_tab_buttons.append(b)
	bar.add_child(_arrow_button("RB ▶", func() -> void: switch_tab(1), "次のタブ（RB / E）"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	bar.add_child(_arrow_button("▲ 前", func() -> void: step(-1), "前の選手（十字キー ↑←）"))
	_counter = UiTheme.small_label("", 17, UiTheme.TEXT, 800)
	_counter.custom_minimum_size = Vector2(70, 0)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_counter)
	bar.add_child(_arrow_button("次 ▼", func() -> void: step(1), "次の選手（十字キー ↓→）"))
	var guide := PadGuide.new()
	guide.set_items([["十字", "選手"], ["LB/RB", "タブ"], ["B", "閉じる"]])
	guide.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(guide)
	var close_button := Button.new()
	close_button.text = "✕ 閉じる"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(0, 40)
	UiTheme.style_button(close_button, Color("5f6670"), Color.WHITE, 10, 5)
	close_button.pressed.connect(close)
	bar.add_child(close_button)
	return bar


func _arrow_button(text: String, action: Callable, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 16)
	UiTheme.style_button(b, Color("4a5058"), Color.WHITE, 8, 4)
	b.pressed.connect(action)
	return b


## 選んでいるタブはタブの色の立体、ほかは淡い色（参考画像のタブの帯）
func _style_tabs() -> void:
	for i in _tab_buttons.size():
		var b := _tab_buttons[i]
		var color: Color = TABS[i][2]
		if i == tab:
			UiTheme.style_button(b, color, Color.WHITE, 10, 6)
		else:
			UiTheme.style_button(b, color.lerp(Color.WHITE, 0.62), color.darkened(0.25), 10, 0)


# --- 見出し（名前・背番号・球団・プロフィールの要点・今季成績）-------------------------------

func _render_header() -> void:
	_clear(_header)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	_header.add_child(left)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	left.add_child(name_row)
	var tag := NameTag.new()
	tag.custom_minimum_size = Vector2(250, 52)
	tag.font_size = 27
	tag.setup_player(_data, _data.get("name", ""))
	tag.focus_mode = Control.FOCUS_NONE
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(tag)
	name_row.add_child(_number_box())
	name_row.add_child(_team_chip())

	var info := GridContainer.new()
	info.columns = 6
	info.add_theme_constant_override("h_separation", 8)
	info.add_theme_constant_override("v_separation", 4)
	left.add_child(info)
	_info_pair(info, "投打", throws_bats())
	_info_pair(info, "年齢", _age_text())
	_info_pair(info, "身長/体重", body_text())
	_info_pair(info, "守備位置", _position_text())
	_info_pair(info, "登録", _status_text())
	_info_pair(info, "枠", _foreign_text())

	var season_card := PanelContainer.new()
	season_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UiTheme.card(_palette.main.lerp(Color.WHITE, 0.4), 10, 2)
	style.set_content_margin_all(10)
	season_card.add_theme_stylebox_override("panel", style)
	_header.add_child(season_card)
	var season_box := VBoxContainer.new()
	season_box.add_theme_constant_override("separation", 4)
	season_card.add_child(season_box)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	season_box.add_child(title_row)
	title_row.add_child(pill("今季成績", 110))
	var caption := UiTheme.small_label(_season_caption(), 15, UiTheme.TEXT_SUB, 700)
	caption.clip_text = true
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(caption)
	var lines := _season_lines()
	var main_line := Label.new()
	main_line.name = "SeasonMain"
	main_line.text = lines[0]
	main_line.clip_text = true
	UiTheme.heading(main_line, 28, _palette.ink, Color.WHITE, 6, false)
	season_box.add_child(main_line)
	var sub_line := UiTheme.small_label(lines[1], 16, UiTheme.TEXT, 700)
	sub_line.name = "SeasonSub"
	sub_line.clip_text = true
	season_box.add_child(sub_line)


func _number_box() -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.card(UiTheme.LINE, 8, 2)
	style.set_content_margin_all(2)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(74, 52)
	panel.tooltip_text = "背番号（データのある年のみ）"
	var label := Label.new()
	label.text = _uniform_number()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiTheme.heading(label, 30, UiTheme.TEXT, Color.WHITE, 4, false)
	panel.add_child(label)
	return panel


func _team_chip() -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.gloss(_palette.main, 10, 2, 3)
	style.content_margin_left = 16
	style.content_margin_right = 16
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(0, 52)
	var label := Label.new()
	label.text = GameData.short_name(_team_name)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var outline := UiTheme.outline_for(_palette.on_main, _palette.main)
	UiTheme.heading(label, 24, _palette.on_main, outline, 6)
	panel.add_child(label)
	panel.tooltip_text = _team_name
	return panel


func _info_pair(grid: GridContainer, key: String, value: String) -> void:
	grid.add_child(pill(key, 86, 15))
	var label := UiTheme.small_label(value, 17, UiTheme.TEXT, 700)
	label.custom_minimum_size = Vector2(112, 0)
	label.clip_text = true
	label.tooltip_text = value
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(label)


## 項目名の札（参考画像の白っぽい角丸の札）
static func pill(text: String, width: int, font_size: int = 17) -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.gloss(Color("f1f4f7"), 8, 1, 2, Color("c5ccd4"))
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 3
	style.shadow_size = 1
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(width, 0)
	var label := UiTheme.small_label(text, font_size, Color("3d5a80"), 800)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


func _uniform_number() -> String:
	return str(GameData.uniform_numbers(data_year()).get(player_id, ""))


func throws_bats() -> String:
	if _data.get("throws") == null or _data.get("bats") == null:
		return "-"
	return "%s投%s打" % [_data["throws"], _data["bats"]]


func body_text() -> String:
	if _data.get("height") == null:
		return "-"
	return "%dcm/%skg" % [int(_data["height"]),
		str(int(_data["weight"])) if _data.get("weight") != null else "-"]


func _age_text() -> String:
	var age := age()
	return "%d歳" % age if age >= 0 else "-"


## 今日（ゲーム内の日付）時点の満年齢。生年月日が無ければ -1
func age() -> int:
	var birth: Variant = _data.get("birth")
	if birth == null or str(birth).length() < 10:
		return -1
	var today := _today()
	var b := str(birth)
	var age := int(today.substr(0, 4)) - int(b.substr(0, 4))
	if today.substr(5, 5) < b.substr(5, 5):
		age -= 1
	return age


## ゲーム内の今日（"YYYY-MM-DD"）。オフは12月1日、春季キャンプは2月1日とみなす
func _today() -> String:
	if GameState.phase == GameState.Phase.SEASON:
		return Season.date_of_day(GameState.day) if GameState.day > 0 else "%d-04-01" % GameState.year
	if GameState.phase == GameState.Phase.CAMP:
		return "%d-02-01" % GameState.year
	return "%d-12-01" % GameState.year


## 守備位置：主な位置（ほかに10試合以上守った位置）。投手は先発/救援
func _position_text() -> String:
	var primary: Variant = _data.get("primary_pos")
	if _data.get("is_pitcher", false):
		var role := _role_of(_data)
		return "投手" + ("（%s）" % role if not role.is_empty() else "")
	if primary == null:
		return "不明"
	var others: Array[String] = []
	for pos: String in _fielding_positions():
		if pos != primary and int(_data["fielding"][pos].get("games", 0)) >= NameTag.SECOND_POS_GAMES:
			others.append(POS_SHORT.get(pos, pos))
	return str(primary) + ("（%s）" % "・".join(others) if not others.is_empty() else "")


## 1軍・2軍と持ち場（今季の編成。日程データのない年は「-」）
func _status_text() -> String:
	var sim := sim_team()
	if sim == null or not sim.by_id.has(player_id):
		return "-"
	var p: SimPlayer = sim.by_id[player_id]
	if not sim.is_active(p):
		return "2軍"
	if p.is_pitcher:
		var role: String = sim.pitcher_role(p)[0]
		var names := {SimTeam.ROLE_ROTATION: "先発", SimTeam.ROLE_CLOSER: "抑え"}
		return "1軍・" + names.get(role, "中継ぎ")
	for use_dh in [true, false]:
		for entry: Array in sim.lineup(use_dh):
			if entry[0] == p:
				return "1軍・スタメン"
	return "1軍・控え"


func _foreign_text() -> String:
	var sim := sim_team()
	if sim == null or not sim.by_id.has(player_id):
		return "-"
	return "外国人" if (sim.by_id[player_id] as SimPlayer).is_foreign else "日本人"


func sim_team() -> SimTeam:
	if GameState.season == null:
		return null
	return GameState.season.teams.get(_team_name)


func _season_caption() -> String:
	if GameState.season == null:
		return "（%d年は日程データがないため試合なし）" % GameState.year
	return "%d年 1軍（%s まで）" % [GameState.year, _last_played_label()]


func _last_played_label() -> String:
	var last := GameState.season.last_played_date()
	if last.is_empty():
		return "開幕前"
	return Season.day_label(Season.day_number(last))


## 見出しの今季成績 [大きい行, 小さい行]。投手は投手成績、野手は打撃成績
func _season_lines() -> Array[String]:
	if _data.get("is_pitcher", false):
		var s := _season_pitching()
		if s.is_empty():
			return ["登板なし", ""]
		return ["防%s　%d勝%d敗　%dH　%dS" % [StatTable.era_text(s), s["w"], s["l"], s["hld"], s["sv"]],
			"%d登板（先発%d）　投球回 %s　奪三振 %d　与四球 %d" % [s["g"], s.get("gs", 0),
				StatTable.ip_text(s["outs"]), s["so"], s["bb"]]]
	var b := _season_batting()
	if b.is_empty():
		return ["出場なし", ""]
	var has_ab: bool = b["ab"] > 0
	var avg := StatTable.rate_text(StatTable.avg(b), has_ab)
	var obp := StatTable.rate_text(StatTable.obp(b), StatTable.obp_den(b) > 0)
	var ops := StatTable.rate_text(StatTable.obp(b) + StatTable.slg(b), has_ab)
	return ["打率%s　%d本　%d打点　%d盗塁" % [avg, b["hr"], b["rbi"], b["sb"]],
		"%d試合　%d打席　%d安打　出塁率%s　OPS %s" % [b["g"], b["pa"], b["h"], obp, ops]]


func _season_batting() -> Dictionary:
	if GameState.season == null:
		return {}
	return GameState.season.batting.get(player_id, {})


func _season_pitching() -> Dictionary:
	if GameState.season == null:
		return {}
	return GameState.season.pitching.get(player_id, {})


# --- 本体（タブの中身）--------------------------------------------------------------

func _render_body() -> void:
	_style_tabs()
	_clear(_body)
	_scroll = null
	match TABS[tab][0]:
		"summary":
			_body.add_child(_summary_page())
		"stats":
			_body.add_child(_stats_page())
		"career":
			var page := CareerPage.new()
			_body.add_child(page)
			page.setup(self, _data, _page, _palette)
		_:
			_body.add_child(_contract_page())


func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _card(title: String) -> Dictionary:
	return UiTheme.titled_panel(_palette, title)


# --- 概要 ---

func _summary_page() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var is_pitcher: bool = _data.get("is_pitcher", false)
	var abilities := _card("投手能力" if is_pitcher else "野手能力")
	abilities["panel"].custom_minimum_size = Vector2(620, 0)
	row.add_child(abilities["panel"])
	var body: VBoxContainer = abilities["body"]
	body.add_theme_constant_override("separation", 5)
	if is_pitcher:
		var pitching := _dict(_data.get("pitching"))
		var velocity := _dict(pitching.get("velocity"))
		var kmh := "%d" % int(velocity["kmh"]) if velocity.get("kmh") != null else "-"
		body.add_child(_value_row("球速", kmh, "km/h", _velocity_note(velocity)))
		var ratings := _dict(pitching.get("ratings"))
		for r: Array in PITCHER_ROWS:
			body.add_child(_ability_row(r[1], ratings.get(r[0]), _pitching_note(r[0])))
	else:
		var batting := _dict(_data.get("batting"))
		var trajectory: Variant = batting.get("trajectory")
		body.add_child(_value_row("弾道", str(int(trajectory)) if trajectory != null else "-", "",
			"打球の上がりやすさ（1〜4）"))
		var ratings := _dict(batting.get("ratings"))
		for r: Array in BATTER_ROWS:
			body.add_child(_ability_row(r[1], ratings.get(r[0]), _batting_note(r[0])))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)
	var special := _card("特殊能力")
	right.add_child(special["panel"])
	special["body"].add_child(_ability_tiles())
	var aptitude := _card("起用・適性" if is_pitcher else "守備適性")
	aptitude["panel"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(aptitude["panel"])
	if is_pitcher:
		_pitcher_aptitude(aptitude["body"])
	else:
		_fielder_aptitude(aptitude["body"])
	return row


## 能力の行：項目名 | ランク | 数値 | 棒 | 実数値
func _ability_row(title: String, rating: Variant, note: String) -> Control:
	var row := _row_frame()
	var box: HBoxContainer = row.get_child(0)
	box.add_child(pill(title, 110, 19))
	var rank := UiTheme.rank_label(rating, 36)
	rank.custom_minimum_size = Vector2(46, 0)
	box.add_child(rank)
	var value := Label.new()
	value.text = str(int(rating["value"])) if rating is Dictionary else "-"
	value.custom_minimum_size = Vector2(58, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.heading(value, 32, UiTheme.TEXT, Color.WHITE, 5, false)
	box.add_child(value)
	var bar := ValueBar.new()
	bar.custom_minimum_size = Vector2(96, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if rating is Dictionary:
		bar.value = float(rating["value"]) / 100.0
		bar.color = GameData.rank_color(rating["rank"])
	box.add_child(bar)
	box.add_child(_note_label(note))
	return row


## 数値だけの行（球速・弾道。パワプロと同じくランクなし）
func _value_row(title: String, value_text: String, unit: String, note: String) -> Control:
	var row := _row_frame()
	var box: HBoxContainer = row.get_child(0)
	box.add_child(pill(title, 110, 19))
	var value := Label.new()
	value.text = value_text
	value.custom_minimum_size = Vector2(114, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.heading(value, 32, _palette.ink, Color.WHITE, 5, false)
	box.add_child(value)
	var unit_label := UiTheme.small_label(unit, 17, UiTheme.TEXT, 800)
	unit_label.custom_minimum_size = Vector2(96, 0)
	box.add_child(unit_label)
	box.add_child(_note_label(note))
	return row


func _row_frame() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := UiTheme.card(Color("cfe3f5"), 8, 1)
	style.bg_color = Color("f7fbff")
	style.shadow_size = 2
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.content_margin_left = 6
	style.content_margin_right = 8
	panel.add_theme_stylebox_override("panel", style)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	return panel


func _note_label(text: String) -> Label:
	var label := UiTheme.small_label(text, 13, UiTheme.TEXT_SUB, 700)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.tooltip_text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label


## 能力値の元になった実数値（ratings の detail。少ないサンプルは平均寄りに補正した値）
func _batting_note(key: String) -> String:
	var d := _dict(_dict(_data.get("batting")).get("detail"))
	var primary: Variant = _data.get("primary_pos")
	var note := ""
	match key:
		"meet":
			note = "打率 %s・コンタクト率 %s" % [_detail_rate(d, "avg"), _detail_pct(d, "contact")]
		"power":
			note = "ISO %s・本塁打率 %s" % [_detail_rate(d, "iso"), _detail_pct(d, "hr_rate")]
		"eye":
			note = "四球率 %s" % _detail_pct(d, "bb")
		"speed":
			note = "盗塁企図 %s・成功率 %s" % [_detail_pct(d, "sb_att"), _detail_pct(d, "sb_pct")]
		"defense":
			if primary != null:
				var f := _dict(_dict(_data.get("fielding")).get(primary))
				note = "%s・失策率 %s" % [primary, _detail_pct(_dict(f.get("detail")), "err")]
		"arm":
			note = str(primary) if primary != null else ""
	return note


func _pitching_note(key: String) -> String:
	var d := _dict(_dict(_data.get("pitching")).get("detail"))
	match key:
		"overall":
			return "FIP %s" % _detail_num(d, "fip", 2)
		"bb9":
			return "与四球率 BB/9 %s" % _detail_num(d, "bb9", 2)
		"stamina":
			var v: Variant = _dict(d.get("stamina")).get("blended")
			# detail の stamina は1登板あたりのアウト数
			return "1登板の平均投球回 %s" % (StatTable.ip_text(int(round(float(v)))) if v != null else "-")
		"k9":
			return "奪三振率 K/9 %s" % _detail_num(d, "k9", 2)
		"hr9":
			return "被本塁打率 HR/9 %s" % _detail_num(d, "hr9", 2)
	return ""


func _velocity_note(velocity: Dictionary) -> String:
	match velocity.get("source"):
		"observed":
			return "実測値の加重平均"
		"early_career":
			return "推定（若い頃の実測から）"
		"estimated":
			return "推定（奪三振率から）"
		"provisional":
			return "仮の値（プロの登板記録なし）"
	return ""


func _detail_value(d: Dictionary, key: String) -> Variant:
	var entry := _dict(d.get(key))
	return entry.get("blended", entry.get("observed"))


func _detail_rate(d: Dictionary, key: String) -> String:
	var v: Variant = _detail_value(d, key)
	return StatTable.rate_text(float(v), true) if v != null else "-"


func _detail_pct(d: Dictionary, key: String) -> String:
	var v: Variant = _detail_value(d, key)
	return "%.1f%%" % (float(v) * 100.0) if v != null else "-"


func _detail_num(d: Dictionary, key: String, digits: int) -> String:
	var v: Variant = _detail_value(d, key)
	return String.num(float(v), digits) if v != null else "-"


## 特殊能力の札（4列。良いものは青、悪いものは赤。空きの札も並べて枠を見せる）
func _ability_tiles() -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var list: Array = []
	for kind in ["pitching", "batting"]:
		list.append_array(_dict(_data.get(kind)).get("abilities", []))
	for i in maxi(ABILITY_SLOTS, list.size()):
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.custom_minimum_size = Vector2(0, 40)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var color := Color("eef6fb")
		if i < list.size():
			var ability: String = list[i]
			var bad := ability in BAD_ABILITIES
			color = Color("ffb3bd") if bad else Color("9fd8f5")
			label.text = ability
			UiTheme.heading(label, 20, Color("c62828") if bad else Color("0d47a1"), Color.WHITE, 5, false)
		elif i == 0:
			label.text = "なし"
			label.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
		var style := UiTheme.gloss(color, 6, 1, 2, color.darkened(0.2))
		style.shadow_size = 1
		if i >= list.size():
			style.gloss = 0.15
		panel.add_theme_stylebox_override("panel", style)
		panel.add_child(label)
		grid.add_child(panel)
	return grid


func _fielder_aptitude(body: VBoxContainer) -> void:
	var positions := _fielding_positions()
	if positions.is_empty():
		body.add_child(UiTheme.small_label("守備の記録がありません", 16))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	for pos: String in positions:
		var f: Dictionary = _data["fielding"][pos]
		var tile := HBoxContainer.new()
		tile.add_theme_constant_override("separation", 6)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var chip := NameTag.new()
		chip.setup_plain(pos, NameTag.pos_color(pos))
		chip.custom_minimum_size = Vector2(96, 32)
		chip.font_size = 17
		chip.focus_mode = Control.FOCUS_NONE
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(chip)
		var rank := UiTheme.rank_label(f.get("defense"), 24)
		rank.custom_minimum_size = Vector2(30, 0)
		tile.add_child(rank)
		var value_text := str(int(f["defense"]["value"])) if f.get("defense") is Dictionary else "-"
		tile.add_child(UiTheme.small_label(value_text, 18, UiTheme.TEXT, 800))
		var note := "%d試合" % int(f.get("games", 0))
		if f.get("gold_glove", false):
			note += "　GG賞"
		tile.add_child(UiTheme.small_label(note, 14, UiTheme.TEXT_SUB, 700))
		grid.add_child(tile)
	body.add_child(UiTheme.small_label("試合数は前年までの1軍の守備記録（出場のない位置は近い位置からの推定）", 13))


func _pitcher_aptitude(body: VBoxContainer) -> void:
	var role := _role_of(_data)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	row.add_child(pill("適性", 80))
	var role_label := Label.new()
	role_label.text = role if not role.is_empty() else "-"
	UiTheme.heading(role_label, 24, _palette.ink, Color.WHITE, 5, false)
	row.add_child(role_label)
	row.add_child(UiTheme.small_label("（1登板の平均投球回から判定）", 14))
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 10)
	body.add_child(status)
	status.add_child(pill("今季の起用", 80))
	status.add_child(UiTheme.small_label(_status_text(), 18, UiTheme.TEXT, 800))
	# 投手の打撃（野手能力の要約）
	var ratings := _dict(_dict(_data.get("batting")).get("ratings"))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	body.add_child(UiTheme.small_label("打撃・守備（野手能力）", 15, UiTheme.TEXT_SUB, 800))
	body.add_child(grid)
	for r: Array in [["meet", "ミート"], ["power", "パワー"], ["speed", "走力"], ["defense", "守備"]]:
		grid.add_child(UiTheme.small_label(r[1], 16, UiTheme.TEXT, 700))
		var rank := UiTheme.rank_label(ratings.get(r[0]), 22)
		rank.custom_minimum_size = Vector2(28, 0)
		grid.add_child(rank)


## 守備記録のある位置（試合数の多い順。主な位置は先頭）
func _fielding_positions() -> Array[String]:
	var result: Array[String] = []
	var fielding := _dict(_data.get("fielding"))
	for pos: String in fielding:
		if fielding[pos] is Dictionary:
			result.append(pos)
	var primary: Variant = _data.get("primary_pos")
	result.sort_custom(func(a: String, b: String) -> bool:
		if (a == primary) != (b == primary):
			return a == primary
		return int(fielding[a].get("games", 0)) > int(fielding[b].get("games", 0)))
	return result


# --- 成績 ---

func _stats_page() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var is_pitcher: bool = _data.get("is_pitcher", false)
	var note := UiTheme.small_label(
			"%d年より前は史実の1軍成績（npb.jp）、%d年はゲーム内の今季の成績（黄色の行）。通算はその合計です。"
			% [GameState.year, GameState.year], 14)
	box.add_child(note)
	var short := GameData.short_name(_team_name)
	var pitching_rows := StatTable.history_rows(_page.get("pitching", []), StatTable.PITCHING_KEYS,
		_season_pitching(), short)
	var batting_rows := StatTable.history_rows(_page.get("batting", []), StatTable.BATTING_KEYS,
		_season_batting(), short)
	var main := ["投手成績", StatTable.PITCHING_COLUMNS, pitching_rows] if is_pitcher \
		else ["打撃成績", StatTable.BATTING_COLUMNS, batting_rows]
	box.add_child(UiTheme.small_label(main[0], 18, _palette.ink, 800))
	var table := StatTable.build(main[1], main[2], true, _palette)
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(table)
	# 開いたときは最近の年が見えるよう下端へ送る（右スティックでも送れる）
	_scroll = table.find_child("History", true, false) as ScrollContainer
	_scroll_to_end(_scroll)
	# もう一方（投手の打撃・野手の登板）は、記録があれば今季と通算だけを下に出す
	var other := ["打撃成績（今季・通算）", StatTable.BATTING_COLUMNS, batting_rows] if is_pitcher \
		else ["投手成績（今季・通算）", StatTable.PITCHING_COLUMNS, pitching_rows]
	if StatTable.total(other[2], "pa" if is_pitcher else "g") > 0:
		box.add_child(UiTheme.small_label(other[0], 16, _palette.ink, 800))
		box.add_child(StatTable.build(other[1], other[2], false, _palette))
	return box


## 右スティックで送るスクロール（成績表・所属球団の推移）
func use_scroll(scroll: ScrollContainer) -> void:
	_scroll = scroll


func _scroll_to_end(scroll: ScrollContainer) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


# --- 契約 ---

func _contract_page() -> Control:
	var center := CenterContainer.new()
	var card := _card("契約")
	card["panel"].custom_minimum_size = Vector2(620, 220)
	center.add_child(card["panel"])
	var label := UiTheme.small_label(
			"年俸・契約年数・FA権などの契約情報は、まだデータがないため未実装です。\n"
			+ "（契約更改・FAの仕組みを作るときに追加します）", 19, UiTheme.TEXT, 700)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card["body"].add_child(label)
	return center


# --- 共通 ---

static func _role_of(p: Dictionary) -> String:
	var pitching: Variant = p.get("pitching")
	if pitching is Dictionary and pitching.get("role") != null:
		return pitching["role"]
	return ""


static func _rating_value(p: Dictionary, kind: String, key: String) -> int:
	var part: Variant = p.get(kind)
	if part is Dictionary and part.get("ratings") is Dictionary:
		var r: Variant = part["ratings"].get(key)
		if r is Dictionary:
			return int(r["value"])
	return 0


func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}
