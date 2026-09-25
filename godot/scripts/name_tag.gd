class_name NameTag
extends Button
## 選手の名前札（docs/references/README.md「全画面共通の表現」）。札の色は守備位置：
## 投手=赤、捕手=水色、内野手=黄、外野手=緑。ほかの守備位置も守る野手は右側を2つ目の色にする。
## 空き枠（「あき」）にも使う。クリックで pressed。選択中は橙の太枠、選べない選手は薄く表示する。

const COLOR_PITCHER := Color("f47a86")
const COLOR_CATCHER := Color("5cc8f0")
const COLOR_INFIELD := Color("ffd84d")
const COLOR_OUTFIELD := Color("7fd17f")
const COLOR_UNKNOWN := Color("c9ced4")
const COLOR_EMPTY := Color("f6f7f9")
const SELECT_COLOR := Color("ff6d00")
const INFIELD := ["一塁手", "二塁手", "三塁手", "遊撃手", "内野手"]
## 2つ目の色を付ける守備位置の最低試合数（能力値データの fielding の games）
const SECOND_POS_GAMES := 10
const MIN_FONT_SIZE := 11

var tag_text := ""
var colors: Array[Color] = [COLOR_UNKNOWN]
var empty_slot := false
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var dimmed := false:
	set(value):
		dimmed = value
		queue_redraw()
var font_size := 19


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(128, 34)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## p: 能力値データの選手（GameData.player()）。text: 札に書く名前
func setup_player(p: Dictionary, text: String) -> void:
	tag_text = text
	colors = colors_for(p)
	empty_slot = false
	queue_redraw()


func setup_empty(text: String = "あき") -> void:
	tag_text = text
	colors = [COLOR_EMPTY]
	empty_slot = true
	queue_redraw()


## 札の色だけを指定する（「投手」の打順の札など）
func setup_plain(text: String, color: Color) -> void:
	tag_text = text
	colors = [color]
	empty_slot = false
	queue_redraw()


static func pos_color(pos: Variant) -> Color:
	if pos == "投手":
		return COLOR_PITCHER
	if pos == "捕手":
		return COLOR_CATCHER
	if pos in INFIELD:
		return COLOR_INFIELD
	if pos in ["外野手", "左翼手", "中堅手", "右翼手"]:
		return COLOR_OUTFIELD
	return COLOR_UNKNOWN


## 札の色：主な守備位置の色＋（あれば）ほかの守備位置の色
static func colors_for(p: Dictionary) -> Array[Color]:
	if p.get("is_pitcher", false):
		return [COLOR_PITCHER]
	var first := pos_color(p.get("primary_pos"))
	var result: Array[Color] = [first]
	var fielding: Variant = p.get("fielding")
	if fielding is Dictionary:
		var best_games := 0
		var second := first
		for pos: String in fielding:
			var games := int(fielding[pos].get("games", 0))
			var c := pos_color(pos)
			if c != first and games >= SECOND_POS_GAMES and games > best_games:
				best_games = games
				second = c
		if second != first:
			result.append(second)
	return result


## 札に書く名前（名字。同じ球団に同じ名字がいれば名前の1文字目を足す）。選手ID → 名前
static func short_names(team_players: Array) -> Dictionary:
	var family := {}
	var count := {}
	for p: SimPlayer in team_players:
		var f := family_name(p.name)
		family[p.id] = f
		count[f] = int(count.get(f, 0)) + 1
	var result := {}
	for p: SimPlayer in team_players:
		var f: String = family[p.id]
		var parts := p.name.split(" ", false)
		if int(count[f]) > 1 and parts.size() >= 2 and not _is_katakana(parts[0]):
			f += parts[1].substr(0, 1)
		result[p.id] = f
	return result


## "阿部 慎之助" → "阿部"、"A.ラミレス" → "ラミレス"、"タイロン・ウッズ" → "ウッズ"
static func family_name(full: String) -> String:
	var parts := full.split(" ", false)
	if parts.size() >= 2 and not _is_katakana(parts[0]):
		return parts[0]
	var s := full
	var dot := s.rfind(".")
	if dot >= 0:
		s = s.substr(dot + 1)
	var sep := s.rfind("・")
	if sep >= 0:
		s = s.substr(sep + 1)
	return s.replace(" ", "")


static func _is_katakana(s: String) -> bool:
	if s.is_empty():
		return false
	var c := s.unicode_at(0)
	return c >= 0x30A0 and c <= 0x30FF


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var base: Color = colors[0]
	if is_hovered() and not disabled:
		base = base.lightened(0.18)
	var style := UiTheme.box(base, 7, base.darkened(0.25) if not empty_slot else UiTheme.LINE, 2)
	draw_style_box(style, rect)
	if colors.size() > 1:
		# 右側に2つ目の守備位置の色
		var second: Color = colors[1].lightened(0.18) if is_hovered() else colors[1]
		var right := StyleBoxFlat.new()
		right.bg_color = second
		right.corner_radius_top_right = 6
		right.corner_radius_bottom_right = 6
		var x := size.x * 0.62
		draw_style_box(right, Rect2(x, 2, size.x - x - 2, size.y - 4))
	# 下側を少し暗くして札らしく
	draw_rect(Rect2(3, size.y - 6, size.x - 6, 3), Color(0, 0, 0, 0.08))

	var font := UiTheme.font(800)
	var fs := font_size
	var width := size.x - 10
	while fs > MIN_FONT_SIZE \
			and font.get_string_size(tag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 1
	var baseline := (size.y + font.get_ascent(fs) - font.get_descent(fs)) / 2.0
	var text_color := UiTheme.TEXT_SUB if empty_slot else UiTheme.TEXT
	var origin := Vector2(5, baseline)
	if not empty_slot:
		draw_string_outline(font, origin, tag_text, HORIZONTAL_ALIGNMENT_CENTER, width, fs, 4,
				Color(1, 1, 1, 0.85))
	draw_string(font, origin, tag_text, HORIZONTAL_ALIGNMENT_CENTER, width, fs, text_color)

	if dimmed:
		draw_style_box(UiTheme.box(Color(1, 1, 1, 0.55), 7), rect)
	if selected:
		var frame := UiTheme.box(Color.TRANSPARENT, 8, SELECT_COLOR, 4)
		frame.draw_center = false
		draw_style_box(frame, rect.grow(2))
