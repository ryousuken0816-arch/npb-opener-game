class_name StandingsPanel
extends PanelContainer
## 順位表パネル（◀ ▶ でセ・パを切り替え）。球団名は各球団のチームカラーの札で表示。

const LEAGUES := ["C", "P"]
const ROW_HEIGHT := 44

var _page := 0
var _palette: UiTheme.Palette
var _header := PanelContainer.new()
var _title := Label.new()
var _rows := VBoxContainer.new()
var _arrows: Array[Button] = []


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
	var header_style := UiTheme.box(p.main, 8)
	header_style.content_margin_top = 2
	header_style.content_margin_bottom = 2
	_header.add_theme_stylebox_override("panel", header_style)
	_title.add_theme_color_override("font_color", p.on_main)
	for arrow in _arrows:
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			arrow.add_theme_color_override(c, p.on_main)
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


func _turn(delta: int) -> void:
	_page = posmod(_page + delta, LEAGUES.size())
	refresh()


func _make_arrow(text: String, delta: int) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(_turn.bind(delta))
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
	hbox.add_child(gb_label)
	return container


## 球団カラーの札（メイン色の地にサブ色の縁、略称）
func _team_badge(team: String) -> Control:
	var colors := GameData.team_colors(team)
	var badge := PanelContainer.new()
	var style := UiTheme.box(colors[0], 4, colors[1], 0)
	style.border_width_left = 6
	style.border_width_bottom = 3
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", style)
	badge.custom_minimum_size = Vector2(122, 0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var short_name := GameData.short_name(team)
	var font_size := 18 if short_name.length() <= 5 else 15
	var name_label := _label(short_name, font_size, UiTheme.text_on(colors[0]), 800)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
