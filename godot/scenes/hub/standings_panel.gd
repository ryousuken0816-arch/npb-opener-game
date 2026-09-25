class_name StandingsPanel
extends PanelContainer
## 順位表パネル（◀ ▶・コントローラーの LB/RB でセ・パを切り替え）。球団名は各球団のチームカラーの札（立体）で表示。
## 勝敗・ゲーム差・順位が前回から変わった行は数字を軽く弾ませる。

const LEAGUES := ["C", "P"]
const ROW_HEIGHT := 44

var _page := 0
var _palette: UiTheme.Palette
var _header := PanelContainer.new()
var _title := Label.new()
var _rows := VBoxContainer.new()
var _arrows: Array[Button] = []
## 球団 → 前回表示した「順位|勝敗|ゲーム差」（変わった数字を弾ませる）
var _last := {}


func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var bar := HBoxContainer.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", UiTheme.font(800))
	_title.add_theme_font_size_override("font_size", 22)
	bar.add_child(_make_arrow("◀", -1))
	bar.add_child(_title)
	bar.add_child(_make_arrow("▶", 1))
	_header.add_child(bar)
	vbox.add_child(_header)

	_rows.add_theme_constant_override("separation", 4)
	vbox.add_child(_rows)


func setup(p: UiTheme.Palette, league: String) -> void:
	_palette = p
	var header_style := UiTheme.gloss(p.main, 8, 2, 3)
	header_style.content_margin_top = 2
	header_style.content_margin_bottom = 2 + header_style.depth
	_header.add_theme_stylebox_override("panel", header_style)
	UiTheme.heading(_title, 22, p.on_main, UiTheme.outline_for(p.on_main, p.main), 6, false)
	for arrow in _arrows:
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			arrow.add_theme_color_override(c, p.on_main)
		arrow.add_theme_color_override("font_outline_color", UiTheme.outline_for(p.on_main, p.main))
		arrow.add_theme_constant_override("outline_size", 6)
	_page = maxi(LEAGUES.find(league), 0)
	refresh()


func refresh() -> void:
	var league: String = LEAGUES[_page]
	_title.text = "%s  %d／%d" % [GameData.LEAGUE_NAMES[league], _page + 1, LEAGUES.size()]
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var standings := GameState.standings(league)
	for i in standings.size():
		_rows.add_child(_make_row(standings[i], i == 0))


## セ・パの切り替え（◀▶ ボタン、ハブ・日程表の LB/RB）
func turn(delta: int) -> void:
	_page = posmod(_page + delta, LEAGUES.size())
	refresh()
	UiFx.fade_in(_rows)


func _make_arrow(text: String, delta: int) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(turn.bind(delta))
	_arrows.append(button)
	return button


func _make_row(row: Dictionary, is_top: bool) -> Control:
	var team: String = row["team"]
	var own := team == GameState.team
	var container := PanelContainer.new()
	var bg := UiTheme.box(_palette.tint if own else Color(0, 0, 0, 0), 6)
	bg.content_margin_top = 2
	bg.content_margin_bottom = 2
	bg.content_margin_left = 6
	bg.content_margin_right = 8
	container.add_theme_stylebox_override("panel", bg)
	container.custom_minimum_size.y = ROW_HEIGHT

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	container.add_child(hbox)

	var rank := _label(str(row["rank"]), 26, UiTheme.TEXT, 800)
	rank.custom_minimum_size.x = 28
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(rank)
	hbox.add_child(_team_badge(team))

	var record := _label("%d-%d-%d" % [row["wins"], row["losses"], row["draws"]], 15, UiTheme.TEXT_SUB)
	record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(record)

	var gb := "−" if is_top else "%.1f" % row["games_behind"]
	var gb_label := _label(gb, 24, _palette.ink, 800)
	gb_label.custom_minimum_size.x = 52
	gb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gb_label.add_theme_color_override("font_outline_color", Color.WHITE)
	gb_label.add_theme_constant_override("outline_size", 5)
	hbox.add_child(gb_label)
	rank.add_theme_color_override("font_outline_color", Color.WHITE)
	rank.add_theme_constant_override("outline_size", 5)

	# 前回から変わった数字を弾ませる
	var now := "%s|%s|%s" % [rank.text, record.text, gb]
	if _last.has(team) and _last[team] != now:
		var old: PackedStringArray = str(_last[team]).split("|")
		if old[0] != rank.text:
			UiFx.bump(rank, 1.3)
		if old[1] != record.text:
			UiFx.bump(record, 1.2)
		if old[2] != gb:
			UiFx.bump(gb_label, 1.25)
	_last[team] = now
	return container


## 球団カラーの札（メイン色の地にサブ色の縁、略称）
func _team_badge(team: String) -> Control:
	var colors := GameData.team_colors(team)
	var badge := PanelContainer.new()
	var style := UiTheme.gloss(colors[0], 4, 0, 3, colors[1])
	style.border_width_left = 6
	style.shadow_size = 2
	style.content_margin_top = 1
	style.content_margin_bottom = 1 + style.depth
	badge.add_theme_stylebox_override("panel", style)
	badge.custom_minimum_size = Vector2(122, 0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var short_name := GameData.short_name(team)
	var font_size := 18 if short_name.length() <= 5 else 15
	var ink := UiTheme.text_on(colors[0])
	var name_label := _label(short_name, font_size, ink, 800)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_outline_color", UiTheme.outline_for(ink, colors[0]))
	name_label.add_theme_constant_override("outline_size", 5)
	badge.add_child(name_label)
	return badge


func _label(text: String, font_size: int, color: Color, weight: int = 500) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_override("font", UiTheme.font(weight))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
