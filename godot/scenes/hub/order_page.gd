# gdlint: disable=max-file-lines,max-public-methods
class_name OrderPage
extends HBoxContainer
## 采配 → 起用設定（守備位置グラウンド配置 ＆ 直感オーダー編成）。
##
## - 左側：野球グラウンド（ダイヤモンド）上に守備位置ごとのスタメンをグラフィカルに配置。
##   誰がどこを守っているか、どこが空いているか（未配置）が一目瞭然。
##   ポジションをクリックすると、右側の控えや打順と連動してワンクリックで交代可能。
## - 右側上部：スターティングオーダー（打順 1〜9番）。▲▼ボタンで打順の入れ替えも可能。
## - 右側下部：控え選手一覧（グリッド表示）。クリックしてポジションを選ぶだけでスタメン入り。
## - その年にブレイク・大活躍した選手には「★ブレイク」「★主力」バッジを表示。

signal roster_changed

const TAG_SIZE := Vector2(120, 30)
const BENCH_TAG_SIZE := Vector2(108, 30)
const RANK_COLUMNS := [["meet", "ミ"], ["power", "パ"], ["speed", "走"]]

## グラウンド上の守備位置の表示定義
const FIELD_POS_LIST := [
	"左翼手", "中堅手", "右翼手",
	"遊撃手", "二塁手",
	"三塁手", "一塁手",
	"投手", "捕手", "指名打者"
]

## グラウンド上の相対座標（470 x 420 内の配置、カード幅122x56）
const POS_COORDS := {
	"中堅手": Vector2(174, 8),
	"左翼手": Vector2(8, 28),
	"右翼手": Vector2(340, 28),
	"遊撃手": Vector2(86, 118),
	"二塁手": Vector2(262, 118),
	"三塁手": Vector2(8, 208),
	"一塁手": Vector2(340, 208),
	"投手": Vector2(174, 208),
	"捕手": Vector2(174, 328),
	"指名打者": Vector2(8, 328),
}

var _palette: UiTheme.Palette
var _team: SimTeam
var _names := {}
var _use_dh := true
var _sel_index := -1
var _sel_bench: SimPlayer = null
var _sel_pos := ""
var _message := ""
var _order_ids: Array[String] = []

## ブレイク選手キャッシュ（選手ID → バッジテキスト）
var _breakout_tags := {}
var _breakout_year := -1

# UI コントロール
var _dh_button: Button
var _no_dh_button: Button
var _auto_button: Button
var _status_alert_label: Label
var _message_label: Label

var _ground_panel: PanelContainer
var _field_bg: Control
var _pos_cards := {}

var _lineup_title: Label
var _lineup_box: VBoxContainer
var _bench_title: Label
var _bench_grid: GridContainer


## グラウンドの芝生・白線・マウンドを描画する背景コントロール
class FieldBackground extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		# 芝生グラデーション風ダークグリーン
		draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.14, 0.08, 0.95))
		# 外野ウォーニングゾーン／外野フェンスの弧
		var home := Vector2(w * 0.5, 355)
		draw_arc(home, 280, deg_to_rad(-145), deg_to_rad(-35), 32, Color(1, 1, 1, 0.12), 2.0)
		draw_arc(home, 190, deg_to_rad(-140), deg_to_rad(-40), 24, Color(1, 1, 1, 0.08), 1.5)
		# 内野ダイヤモンドのライン
		var first := Vector2(w * 0.5 + 110, 235)
		var second := Vector2(w * 0.5, 145)
		var third := Vector2(w * 0.5 - 110, 235)
		var line_color := Color(1, 1, 1, 0.22)
		draw_line(home, first, line_color, 1.5)
		draw_line(first, second, line_color, 1.5)
		draw_line(second, third, line_color, 1.5)
		draw_line(third, home, line_color, 1.5)
		# マウンドの土の円
		draw_circle(Vector2(w * 0.5, 235), 16, Color(0.55, 0.38, 0.22, 0.35))
		draw_circle(Vector2(w * 0.5, 235), 7, Color(0.55, 0.38, 0.22, 0.5))
		# ホームベース周辺の土の円
		draw_circle(home, 18, Color(0.55, 0.38, 0.22, 0.3))


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	add_theme_constant_override("separation", 10)

	var main_vbox := VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 6)
	add_child(main_vbox)

	# --- 上部コントロールバー ---
	main_vbox.add_child(_build_top_bar())

	# --- メインエリア（左：グラウンド守備配置、右：打順・控え） ---
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(content_hbox)

	content_hbox.add_child(_build_ground_section())
	content_hbox.add_child(_build_right_section())


func _build_top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)

	var group := ButtonGroup.new()
	_dh_button = Button.new()
	_dh_button.text = "DHあり"
	_dh_button.toggle_mode = true
	_dh_button.button_group = group
	_dh_button.custom_minimum_size = Vector2(84, 34)
	_dh_button.add_theme_font_size_override("font_size", 15)
	UiTheme.style_toggle(_dh_button, _palette.ink)
	_dh_button.toggled.connect(func(on: bool) -> void:
		if on and not _use_dh:
			_use_dh = true
			_sel_index = -1
			_sel_bench = null
			_sel_pos = ""
			refresh())
	bar.add_child(_dh_button)

	_no_dh_button = Button.new()
	_no_dh_button.text = "DHなし"
	_no_dh_button.toggle_mode = true
	_no_dh_button.button_group = group
	_no_dh_button.custom_minimum_size = Vector2(84, 34)
	_no_dh_button.add_theme_font_size_override("font_size", 15)
	UiTheme.style_toggle(_no_dh_button, _palette.ink)
	_no_dh_button.toggled.connect(func(on: bool) -> void:
		if on and _use_dh:
			_use_dh = false
			_sel_index = -1
			_sel_bench = null
			_sel_pos = ""
			refresh())
	bar.add_child(_no_dh_button)

	_auto_button = Button.new()
	_auto_button.text = "自動で組む"
	_auto_button.custom_minimum_size = Vector2(100, 34)
	_auto_button.tooltip_text = "1軍選手から能力と実績でスタメン・打順を自動編成します"
	UiTheme.style_button(_auto_button, Color("1e88e5"), Color.WHITE, 6, 2)
	_auto_button.pressed.connect(_on_auto)
	bar.add_child(_auto_button)

	_status_alert_label = Label.new()
	_status_alert_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_alert_label.add_theme_font_size_override("font_size", 15)
	bar.add_child(_status_alert_label)

	_message_label = Label.new()
	_message_label.add_theme_font_size_override("font_size", 13)
	_message_label.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
	bar.add_child(_message_label)

	return bar


func _build_ground_section() -> Control:
	_ground_panel = PanelContainer.new()
	_ground_panel.custom_minimum_size = Vector2(474, 450)
	_ground_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.10, 0.06, 0.95)
	panel_style.set_corner_radius_all(8)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.2, 0.45, 0.28, 0.6)
	_ground_panel.add_theme_stylebox_override("panel", panel_style)

	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 2)
	_ground_panel.add_child(wrapper)

	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 24)
	var title := Label.new()
	title.text = " 守備位置（グラウンド配置）"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("81c784"))
	header.add_child(title)

	var hint := Label.new()
	hint.text = "※ポジションをクリックして交代"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UiTheme.TEXT_SUB)
	header.add_child(hint)
	wrapper.add_child(header)

	_field_bg = FieldBackground.new()
	_field_bg.custom_minimum_size = Vector2(464, 410)
	_field_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_child(_field_bg)

	return _ground_panel


func _build_right_section() -> Control:
	var right_panel := VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_constant_override("separation", 6)

	# --- 右側上部：打順（スターティングオーダー）---
	var lineup_panel := PanelContainer.new()
	lineup_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lineup_panel.custom_minimum_size = Vector2(0, 320)

	var style_l := StyleBoxFlat.new()
	style_l.bg_color = Color(0.08, 0.11, 0.15, 0.95)
	style_l.set_corner_radius_all(6)
	style_l.border_width_left = 1
	style_l.border_width_top = 1
	style_l.border_width_right = 1
	style_l.border_width_bottom = 1
	style_l.border_color = Color(0.25, 0.35, 0.45, 0.6)
	lineup_panel.add_theme_stylebox_override("panel", style_l)

	var l_vbox := VBoxContainer.new()
	l_vbox.add_theme_constant_override("separation", 4)
	lineup_panel.add_child(l_vbox)

	_lineup_title = Label.new()
	_lineup_title.add_theme_font_size_override("font_size", 14)
	_lineup_title.add_theme_color_override("font_color", Color("90caf9"))
	l_vbox.add_child(_lineup_title)

	var scroll_l := ScrollContainer.new()
	scroll_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_l.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	l_vbox.add_child(scroll_l)

	_lineup_box = VBoxContainer.new()
	_lineup_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lineup_box.add_theme_constant_override("separation", 2)
	scroll_l.add_child(_lineup_box)

	right_panel.add_child(lineup_panel)

	# --- 右側下部：控え選手 ---
	var bench_panel := PanelContainer.new()
	bench_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bench_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var style_b := StyleBoxFlat.new()
	style_b.bg_color = Color(0.07, 0.10, 0.13, 0.95)
	style_b.set_corner_radius_all(6)
	style_b.border_width_left = 1
	style_b.border_width_top = 1
	style_b.border_width_right = 1
	style_b.border_width_bottom = 1
	style_b.border_color = Color(0.2, 0.3, 0.38, 0.6)
	bench_panel.add_theme_stylebox_override("panel", style_b)

	var b_vbox := VBoxContainer.new()
	b_vbox.add_theme_constant_override("separation", 4)
	bench_panel.add_child(b_vbox)

	_bench_title = Label.new()
	_bench_title.add_theme_font_size_override("font_size", 13)
	_bench_title.add_theme_color_override("font_color", Color("80cbc4"))
	b_vbox.add_child(_bench_title)

	var scroll_b := ScrollContainer.new()
	scroll_b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_b.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	b_vbox.add_child(scroll_b)

	_bench_grid = GridContainer.new()
	_bench_grid.columns = 2
	_bench_grid.add_theme_constant_override("h_separation", 8)
	_bench_grid.add_theme_constant_override("v_separation", 4)
	scroll_b.add_child(_bench_grid)

	right_panel.add_child(bench_panel)

	return right_panel


## 画面更新
func refresh(reset_selection: bool = false) -> void:
	_team = GameState.my_team()
	if reset_selection:
		_sel_index = -1
		_sel_bench = null
		_sel_pos = ""
		_message = ""
	_dh_button.set_pressed_no_signal(_use_dh)
	_no_dh_button.set_pressed_no_signal(not _use_dh)

	# 作り直す前のフォーカスの位置（スタメン・控えの何番目か）を覚えておく
	var focus_box: Control = null
	var focus_at := -1
	for box: Control in [_lineup_box, _bench_grid]:
		var i := UiInput.focus_index(box)
		if i >= 0:
			focus_box = box
			focus_at = i

	_update_breakout_cache()
	_refresh_ground_cards()
	_render_lineup()
	_render_bench()
	_update_status_alert()

	if focus_box != null:
		UiInput.focus_nth(focus_box, focus_at)


## その年のブレイク・注目選手のキャッシュ作成
func _update_breakout_cache() -> void:
	var cur_year: int = GameState.year
	if _breakout_year == cur_year and not _breakout_tags.is_empty():
		return
	_breakout_year = cur_year
	_breakout_tags.clear()

	var post := GameData.peek_ratings(cur_year, "post")
	if post.is_empty():
		return
	var pre := GameData.peek_ratings(cur_year, "pre")
	var pre_map := {}
	for p: Dictionary in pre.get("players", []):
		pre_map[p["id"]] = p

	for p: Dictionary in post.get("players", []):
		var id: String = p["id"]
		var pre_p: Dictionary = pre_map.get(id, {})
		var tag := ""
		var is_rookie: bool = str(p.get("draft", "")).begins_with("%d年" % (cur_year - 1))
		var batting_val: Variant = p.get("batting")
		var batting: Dictionary = batting_val if batting_val is Dictionary else {}
		var ratings: Dictionary = batting.get("ratings", {}) if batting.get("ratings") is Dictionary else {}

		var pre_batting_val: Variant = pre_p.get("batting")
		var pre_batting: Dictionary = pre_batting_val if pre_batting_val is Dictionary else {}
		var pre_ratings: Dictionary = pre_batting.get("ratings", {}) if pre_batting.get("ratings") is Dictionary else {}

		var meet: int = int(ratings.get("meet", {}).get("value", 0)) if ratings.get("meet") is Dictionary else 0
		var power: int = int(ratings.get("power", {}).get("value", 0)) if ratings.get("power") is Dictionary else 0
		var pre_meet: int = int(pre_ratings.get("meet", {}).get("value", 0)) if pre_ratings.get("meet") is Dictionary else 0
		var pre_power: int = int(pre_ratings.get("power", {}).get("value", 0)) if pre_ratings.get("power") is Dictionary else 0

		var pitching_val: Variant = p.get("pitching")
		var pitching: Dictionary = pitching_val if pitching_val is Dictionary else {}
		var pr: Dictionary = pitching.get("ratings", {}) if pitching.get("ratings") is Dictionary else {}

		var pre_pitching_val: Variant = pre_p.get("pitching")
		var pre_pitching: Dictionary = pre_pitching_val if pre_pitching_val is Dictionary else {}
		var pre_pr: Dictionary = pre_pitching.get("ratings", {}) if pre_pitching.get("ratings") is Dictionary else {}

		var overall: int = int(pr.get("overall", {}).get("value", 0)) if pr.get("overall") is Dictionary else 0
		var pre_overall: int = int(pre_pr.get("overall", {}).get("value", 0)) if pre_pr.get("overall") is Dictionary else 0

		if is_rookie:
			if meet >= 65 or power >= 65 or overall >= 65:
				tag = "★ルーキー注目"
		elif (meet - pre_meet >= 8 or power - pre_power >= 8) and (meet >= 60 or power >= 65):
			tag = "★今年ブレイク！"
		elif (overall - pre_overall >= 8) and overall >= 65:
			tag = "★今年ブレイク！"
		elif meet >= 80 or power >= 85 or overall >= 80:
			tag = "★チームの柱"

		if not tag.is_empty():
			_breakout_tags[id] = tag


## グラウンド上の守備位置カードを再描画
func _refresh_ground_cards() -> void:
	for child in _field_bg.get_children():
		child.queue_free()
	_pos_cards.clear()

	if _team == null:
		return

	_names = NameTag.short_names(_team.players)
	_order_ids.clear()
	for entry: Array in _team.lineup(_use_dh):
		if entry[0] != null:
			_order_ids.append((entry[0] as SimPlayer).id)
	for p in _team.bench(_use_dh):
		_order_ids.append(p.id)

	var lineup: Array = _team.lineup(_use_dh)
	# 守備位置ごとの割り当て状況マップ {守備位置名 -> [SimPlayer, 打順index]}
	var pos_map := {}
	for i in lineup.size():
		var p: SimPlayer = lineup[i][0]
		var pos: String = lineup[i][1]
		pos_map[pos] = [p, i]

	for pos_name: String in FIELD_POS_LIST:
		if pos_name == "指名打者" and not _use_dh:
			continue
		var pos_coord: Vector2 = POS_COORDS.get(pos_name, Vector2.ZERO)
		var card := _create_position_card(pos_name, pos_map.get(pos_name, [null, -1]))
		card.position = pos_coord
		_field_bg.add_child(card)
		_pos_cards[pos_name] = card


## グラウンド上の守備位置カードを作成
func _create_position_card(pos_name: String, assigned: Array) -> Control:
	var p: SimPlayer = assigned[0]
	var order_idx: int = assigned[1]
	var is_empty: bool = (p == null and pos_name != "投手")
	var is_selected: bool = (_sel_pos == pos_name or (_sel_index >= 0 and _sel_index == order_idx))

	var card_btn := Button.new()
	card_btn.custom_minimum_size = Vector2(120, 56)
	card_btn.size = Vector2(120, 56)
	card_btn.clip_contents = true

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(6)

	if is_selected:
		style.bg_color = Color(0.2, 0.35, 0.25, 0.95)
		style.border_color = Color("ffeb3b") # 選択中は明るい黄色
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
	elif is_empty:
		style.bg_color = Color(0.35, 0.1, 0.1, 0.9)
		style.border_color = Color("ff5252") # 未配置は赤警告
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
	else:
		style.bg_color = Color(0.08, 0.20, 0.13, 0.9)
		style.border_color = Color(0.3, 0.6, 0.4, 0.6)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1

	card_btn.add_theme_stylebox_override("normal", style)
	var hover_style := style.duplicate()
	hover_style.bg_color = style.bg_color.lightened(0.15)
	card_btn.add_theme_stylebox_override("hover", hover_style)
	card_btn.add_theme_stylebox_override("pressed", style)

	var inner_vbox := VBoxContainer.new()
	inner_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner_vbox.offset_left = 6
	inner_vbox.offset_top = 2
	inner_vbox.offset_right = -6
	inner_vbox.offset_bottom = -2
	inner_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_btn.add_child(inner_vbox)

	# 1行目：ポジション名 ＋ 守備力ランク
	var row1 := HBoxContainer.new()
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pos_lbl := Label.new()
	pos_lbl.text = pos_name
	pos_lbl.add_theme_font_size_override("font_size", 11)
	pos_lbl.add_theme_color_override("font_color", NameTag.pos_color(pos_name).lerp(Color.WHITE, 0.4))
	row1.add_child(pos_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row1.add_child(spacer)

	if p != null and pos_name != "指名打者" and pos_name != "投手":
		var def_val = _defense_rating(p, pos_name)
		var def_rank := UiTheme.rank_label(def_val, 11)
		if not p.defense.has(SimTeam.field_key(pos_name)):
			def_rank.text = "適性×"
			def_rank.add_theme_color_override("font_color", Color("ff5252"))
		row1.add_child(def_rank)
	inner_vbox.add_child(row1)

	# 2行目：選手名 ＋ ★ブレイクバッジ
	var row2 := HBoxContainer.new()
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_lbl := Label.new()
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_empty:
		name_lbl.text = "⚠️ 未配置！"
		name_lbl.add_theme_color_override("font_color", Color("ff8a80"))
		name_lbl.add_theme_font_size_override("font_size", 12)
	elif p == null and pos_name == "投手":
		name_lbl.text = "先発投手"
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		name_lbl.add_theme_font_size_override("font_size", 13)
	else:
		name_lbl.text = _names.get(p.id, p.name)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		name_lbl.add_theme_font_size_override("font_size", 14)
	row2.add_child(name_lbl)

	if p != null and _breakout_tags.has(p.id):
		var star_lbl := Label.new()
		star_lbl.text = " " + _breakout_tags[p.id]
		star_lbl.add_theme_font_size_override("font_size", 10)
		star_lbl.add_theme_color_override("font_color", Color("ffd54f"))
		star_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row2.add_child(star_lbl)
	inner_vbox.add_child(row2)

	# 3行目：打順番号 ＋ 打撃能力
	var row3 := HBoxContainer.new()
	row3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if order_idx >= 0:
		var order_lbl := Label.new()
		order_lbl.text = "%d番" % (order_idx + 1)
		order_lbl.add_theme_font_size_override("font_size", 11)
		var order_color := Color("ff9800") if order_idx in [2, 3, 4] else Color("81d4fa")
		order_lbl.add_theme_color_override("font_color", order_color)
		row3.add_child(order_lbl)

	if p != null and pos_name != "投手":
		var p_data := GameData.player(p.id)
		var br: Dictionary = p_data.get("batting", {}).get("ratings", {})
		var stats_lbl := Label.new()
		stats_lbl.text = " ミ%s パ%s 走%s" % [
			br.get("meet", {}).get("rank", "-"),
			br.get("power", {}).get("rank", "-"),
			br.get("speed", {}).get("rank", "-")
		]
		stats_lbl.add_theme_font_size_override("font_size", 10)
		stats_lbl.add_theme_color_override("font_color", Color("b0bec5"))
		row3.add_child(stats_lbl)
	inner_vbox.add_child(row3)

	card_btn.pressed.connect(_on_ground_card_pressed.bind(pos_name, order_idx, p))
	return card_btn


## グラウンド上のカードがクリックされた時
func _on_ground_card_pressed(pos_name: String, order_idx: int, p: SimPlayer) -> void:
	if not GameState.can_edit_roster():
		if p != null:
			_open_detail(p)
		return

	# すでに控え選手を選んでいた場合 → このポジションにその選手を入れる
	if _sel_bench != null:
		var bench_p := _sel_bench
		if order_idx >= 0:
			_team.lineup_replace(_use_dh, order_idx, bench_p)
			_team.lineup_set_position(_use_dh, order_idx, pos_name)
			_message = "%sを%s（%d番）に配置しました" % [bench_p.name, pos_name, order_idx + 1]
		else:
			_assign_bench_to_position(bench_p, pos_name)
		_sel_bench = null
		_sel_pos = ""
		_sel_index = -1
		roster_changed.emit()
		refresh()
		return

	# すでに打順選手を選んでいた場合 → その選手の守備位置を変更
	if _sel_index >= 0 and _sel_index != order_idx:
		_team.lineup_set_position(_use_dh, _sel_index, pos_name)
		_message = "%sの守備位置を%sに変更しました" % [_team.lineup(_use_dh)[_sel_index][0].name, pos_name]
		_sel_index = -1
		_sel_pos = ""
		roster_changed.emit()
		refresh()
		return

	# ポジション選択状態の切り替え
	if _sel_pos == pos_name:
		_sel_pos = ""
		_sel_index = -1
	else:
		_sel_pos = pos_name
		_sel_index = order_idx

	refresh()


## 打順（1〜9番）リストの描画
func _render_lineup() -> void:
	_clear(_lineup_box)
	if _team == null:
		return

	_lineup_title.text = "%s・スターティングオーダー（打順）" % ("DHあり" if _use_dh else "DHなし")

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	var h_ord := UiTheme.small_label("打順", 12, UiTheme.TEXT_SUB, 700)
	h_ord.custom_minimum_size = Vector2(24, 0)
	header.add_child(h_ord)
	var h_name := UiTheme.small_label("選手名", 12, UiTheme.TEXT_SUB, 700)
	h_name.custom_minimum_size = Vector2(120, 0)
	header.add_child(h_name)
	var h_pos := UiTheme.small_label("守備", 12, UiTheme.TEXT_SUB, 700)
	h_pos.custom_minimum_size = Vector2(56, 0)
	header.add_child(h_pos)

	for col: Array in RANK_COLUMNS + [["def", "守"]]:
		var l := UiTheme.small_label(col[1], 12, UiTheme.TEXT_SUB, 700)
		l.custom_minimum_size = Vector2(20, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_child(l)

	var h_move := UiTheme.small_label("順序", 12, UiTheme.TEXT_SUB, 700)
	h_move.custom_minimum_size = Vector2(44, 0)
	h_move.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(h_move)

	_lineup_box.add_child(header)

	var order := _team.lineup(_use_dh)
	for i in order.size():
		var p: SimPlayer = order[i][0]
		var pos: String = order[i][1]
		var is_selected: bool = (i == _sel_index)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		# 打順番号
		var num_color := Color("e65100") if i in [2, 3, 4] else _palette.ink
		var num := UiTheme.small_label("%d" % (i + 1), 15, num_color, 800)
		num.custom_minimum_size = Vector2(24, 0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(num)

		# 選手札
		var tag := NameTag.new()
		tag.custom_minimum_size = TAG_SIZE
		if p == null:
			tag.setup_plain("投　手", NameTag.COLOR_PITCHER.lerp(Color.WHITE, 0.45))
			tag.tooltip_text = "その日の先発投手"
		else:
			tag.setup_player(GameData.player(p.id), _names.get(p.id, p.name))
			tag.tooltip_text = p.name
		tag.selected = is_selected
		tag.pressed.connect(_on_lineup_pressed.bind(i))
		row.add_child(tag)

		# 守備位置セレクタ（ドロップダウン）
		row.add_child(_position_selector(i, pos))

		# 能力値ランク
		var ratings: Dictionary = {}
		if p != null:
			var batting: Variant = GameData.player(p.id).get("batting")
			if batting is Dictionary and batting.get("ratings") is Dictionary:
				ratings = batting["ratings"]
		for col: Array in RANK_COLUMNS:
			var r := UiTheme.rank_label(ratings.get(col[0]) if p != null else null, 14)
			r.custom_minimum_size = Vector2(20, 0)
			row.add_child(r)

		var def := UiTheme.rank_label(_defense_rating(p, pos), 14)
		def.custom_minimum_size = Vector2(20, 0)
		if p != null and pos != "指名打者" and not p.defense.has(SimTeam.field_key(pos)):
			def.text = "×"
			def.add_theme_color_override("font_color", Color("d32f2f"))
		row.add_child(def)

		# 打順並べ替えボタン [▲] [▼]
		var up_btn := Button.new()
		up_btn.text = "▲"
		up_btn.custom_minimum_size = Vector2(20, 24)
		up_btn.focus_mode = Control.FOCUS_NONE
		up_btn.disabled = (i == 0 or not GameState.can_edit_roster())
		up_btn.pressed.connect(func() -> void:
			_team.lineup_swap_order(_use_dh, i, i - 1)
			roster_changed.emit()
			refresh())
		row.add_child(up_btn)

		var dn_btn := Button.new()
		dn_btn.text = "▼"
		dn_btn.custom_minimum_size = Vector2(20, 24)
		dn_btn.focus_mode = Control.FOCUS_NONE
		dn_btn.disabled = (i == order.size() - 1 or not GameState.can_edit_roster())
		dn_btn.pressed.connect(func() -> void:
			_team.lineup_swap_order(_use_dh, i, i + 1)
			roster_changed.emit()
			refresh())
		row.add_child(dn_btn)

		_lineup_box.add_child(row)


## 控え選手一覧の描画
func _render_bench() -> void:
	_clear(_bench_grid)
	if _team == null:
		return

	var bench := _team.bench(_use_dh).duplicate()

	# もしグラウンドで守備位置（例：三塁手）が選ばれていれば、そのポジションを守れる選手を上に並べ替え
	if not _sel_pos.is_empty():
		_bench_title.text = "控え（%d人）★【%s】の交代候補を優先表示中" % [bench.size(), _sel_pos]
		var key := SimTeam.field_key(_sel_pos)
		bench.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool:
			var has_a := a.defense.has(key)
			var has_b := b.defense.has(key)
			if has_a != has_b:
				return has_a
			var def_a: float = a.defense_at(key)
			var def_b: float = b.defense_at(key)
			return def_a > def_b)
	else:
		_bench_title.text = "控え野手（%d人）※タップしてスタメンと交代" % bench.size()

	for p in bench:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)

		var tag := NameTag.new()
		tag.custom_minimum_size = BENCH_TAG_SIZE
		tag.setup_player(GameData.player(p.id), _names.get(p.id, p.name))
		tag.tooltip_text = p.name
		tag.selected = (p == _sel_bench)
		tag.pressed.connect(_on_bench_pressed.bind(p))
		row.add_child(tag)

		var pos_text: String = RegisterPage.POS_SHORT.get(p.primary_pos, "-")
		var pos_lbl := UiTheme.small_label(pos_text, 13, UiTheme.TEXT_SUB, 800)
		pos_lbl.custom_minimum_size = Vector2(20, 0)
		row.add_child(pos_lbl)

		# ★ブレイクバッジ
		if _breakout_tags.has(p.id):
			var star := Label.new()
			star.text = "★"
			star.add_theme_color_override("font_color", Color("ffd54f"))
			star.add_theme_font_size_override("font_size", 13)
			row.add_child(star)

		_bench_grid.add_child(row)


## 控え選手を守備位置に割り当てる
func _assign_bench_to_position(bench_p: SimPlayer, pos_name: String) -> void:
	var lineup: Array = _team.lineup(_use_dh)
	var target_idx := -1
	for i in lineup.size():
		if lineup[i][1] == pos_name:
			target_idx = i
			break
	if target_idx >= 0:
		_team.lineup_replace(_use_dh, target_idx, bench_p)
		_message = "%sを%s（%d番）に配置しました" % [bench_p.name, pos_name, target_idx + 1]
	else:
		_message = "%sのポジション配置を更新しました" % bench_p.name


## ポジション選択欄（ドロップダウン）
func _position_selector(i: int, pos: String) -> Control:
	if pos == "投手":
		var l := UiTheme.small_label("投手", 14, UiTheme.TEXT, 800)
		l.custom_minimum_size = Vector2(56, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return l

	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(56, 28)
	option.add_theme_font_size_override("font_size", 12)
	option.fit_to_longest_item = false

	var choices: Array[String] = []
	for candidate: String in SimTeam.LINEUP_POSITIONS:
		if candidate == "指名打者" and not _use_dh:
			continue
		choices.append(candidate)
		option.add_item(candidate)

	option.select(choices.find(pos))
	option.disabled = not GameState.can_edit_roster()
	var color := NameTag.pos_color(pos)
	var style := UiTheme.gloss(color.lerp(Color.WHITE, 0.35), 4, 1, 1, color.darkened(0.2))
	style.content_margin_left = 3
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	option.add_theme_stylebox_override("normal", style)
	option.add_theme_stylebox_override("disabled", style)

	option.item_selected.connect(func(index: int) -> void:
		var new_pos := choices[index]
		_team.lineup_set_position(_use_dh, i, new_pos)
		_message = "守備位置を変更しました"
		refresh()
		roster_changed.emit())

	return option


func _defense_rating(p: SimPlayer, pos: String) -> Variant:
	if p == null or pos == "指名打者":
		return null
	var fielding: Variant = GameData.player(p.id).get("fielding")
	if fielding is Dictionary and fielding.get(SimTeam.field_key(pos)) is Dictionary:
		return fielding[SimTeam.field_key(pos)].get("defense")
	return null


## 未配置ポジションの有無を調べてアラート表示
func _update_status_alert() -> void:
	if _team == null:
		return
	var lineup: Array = _team.lineup(_use_dh)
	var filled_positions := {}
	for entry: Array in lineup:
		if entry[0] != null:
			filled_positions[entry[1]] = true
		elif entry[1] == "投手":
			filled_positions["投手"] = true

	var missing: Array[String] = []
	for pos: String in FIELD_POS_LIST:
		if pos == "指名打者" and not _use_dh:
			continue
		if not filled_positions.has(pos):
			missing.append(pos)

	if missing.is_empty():
		_status_alert_label.text = "✅ 全ポジション配置完了"
		_status_alert_label.add_theme_color_override("font_color", Color("81c784"))
	else:
		_status_alert_label.text = "⚠️ 未配置: %s" % "・".join(missing)
		_status_alert_label.add_theme_color_override("font_color", Color("ff5252"))

	if not _message.is_empty():
		_message_label.text = _message
	elif not GameState.can_edit_roster():
		_message_label.text = "オフは編成変更不可"
	else:
		_message_label.text = ""


# --- 既存テスト互換操作 -------------------------------------------------------------

func _on_lineup_pressed(i: int) -> void:
	var here: SimPlayer = _team.lineup(_use_dh)[i][0]
	if here != null and (_sel_index == i or not GameState.can_edit_roster()):
		_open_detail(here)
		return
	if not GameState.can_edit_roster():
		return

	if _sel_bench != null:
		var p := _sel_bench
		if _team.lineup(_use_dh)[i][0] == null:
			_message = "投手の打順には野手を入れられません"
		else:
			_team.lineup_replace(_use_dh, i, p)
			_message = "%sを%d番に入れました" % [p.name, i + 1]
			roster_changed.emit()
		_sel_bench = null
		_sel_index = -1
		_sel_pos = ""
	elif _sel_index == -1:
		_sel_index = i
		_sel_pos = _team.lineup(_use_dh)[i][1]
		_message = ""
	elif _sel_index == i:
		_sel_index = -1
		_sel_pos = ""
	else:
		_team.lineup_swap_order(_use_dh, _sel_index, i)
		_message = "%d番と%d番を入れ替えました" % [_sel_index + 1, i + 1]
		_sel_index = -1
		_sel_pos = ""
		roster_changed.emit()
	refresh()


func _on_bench_pressed(p: SimPlayer) -> void:
	if _sel_bench == p or not GameState.can_edit_roster():
		_open_detail(p)
		return

	if _sel_index >= 0:
		var i := _sel_index
		_sel_index = -1
		_on_bench_into(i, p)
		return

	if not _sel_pos.is_empty():
		_assign_bench_to_position(p, _sel_pos)
		_sel_pos = ""
		_sel_bench = null
		roster_changed.emit()
		refresh()
		return

	_sel_bench = p
	_message = "%sを選択中（グラウンドのポジションをタップして配置）" % p.name
	refresh()


func _on_bench_into(i: int, p: SimPlayer) -> void:
	if _team.lineup(_use_dh)[i][0] == null:
		_message = "投手の打順には野手を入れられません"
	else:
		_team.lineup_replace(_use_dh, i, p)
		_message = "%sを%d番に入れました" % [p.name, i + 1]
		roster_changed.emit()
	refresh()


func _open_detail(p: SimPlayer) -> void:
	var from: Control = get_viewport().gui_get_focus_owner()
	PlayerDetail.open(from if from != null else self, p.id, _order_ids)


func _on_auto() -> void:
	if not GameState.can_edit_roster() or _team == null:
		return
	_team.auto_lineup(_use_dh)
	_sel_index = -1
	_sel_bench = null
	_sel_pos = ""
	_message = "%sのスタメンを自動で組み直しました" % ("DHあり" if _use_dh else "DHなし")
	refresh()
	roster_changed.emit()


func clear_selection() -> bool:
	if _sel_index < 0 and _sel_bench == null and _sel_pos.is_empty():
		return false
	_sel_index = -1
	_sel_bench = null
	_sel_pos = ""
	_message = ""
	refresh()
	return true


func focus_first() -> void:
	# 打順1番の選手札（NameTag）を優先してフォーカス
	for row in _lineup_box.get_children():
		for child in row.get_children():
			if child is NameTag and child.is_visible_in_tree() and child.focus_mode != Control.FOCUS_NONE:
				child.grab_focus()
				return
	if not UiInput.focus_first(_lineup_box):
		if _dh_button != null:
			_dh_button.grab_focus()


func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
