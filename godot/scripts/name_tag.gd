class_name NameTag
extends Button
## 選手の名前札（docs/references/README.md「全画面共通の表現」）。札の色は守備位置：
## 投手=赤、捕手=水色、内野手=黄、外野手=緑。ほかの守備位置も守る野手は右側を2つ目の色にする。
## 空き枠（「あき」）にも使う。クリック（コントローラーは Ⓐ）で pressed。選択中は橙の太枠がゆっくり明滅し、
## 選べない選手は薄く表示する。札は GlossBox（縦グラデーション＋ツヤ＋濃い縁＋下側の厚み）で立体的に描く。
## 選手の札は右クリックでも選手詳細（PlayerDetail）を開ける。
## フォーカス（十字キーの移動先・マウスを乗せた札）は UiFx が拡大・明滅させ、黄色い光の枠を付ける。
## シーズン中は右上に調子の矢印（Health の色）、故障中は左上に赤い「故」（2軍で調整中は橙の「調」）を付ける（作業45）。

const COLOR_PITCHER := Color("f47a86")
const COLOR_CATCHER := Color("5cc8f0")
const COLOR_INFIELD := Color("ffd84d")
const COLOR_OUTFIELD := Color("7fd17f")
const COLOR_UNKNOWN := Color("c9ced4")
const COLOR_EMPTY := Color("f6f7f9")
const SELECT_COLOR := Color("ff6d00")
const RADIUS := 7
const DEPTH := 3
## 選択中の枠の明滅の周期（秒）
const BLINK_SEC := 1.2
const INFIELD := ["一塁手", "二塁手", "三塁手", "遊撃手", "内野手"]
## 2つ目の色を付ける守備位置の最低試合数（能力値データの fielding の games）
const SECOND_POS_GAMES := 10
const MIN_FONT_SIZE := 11

var tag_text := ""
## 選手の札のときの選手ID（空き枠・「投手」の札は空）
var player_id := ""
var colors: Array[Color] = [COLOR_UNKNOWN]
var empty_slot := false
var selected := false:
	set(value):
		selected = value
		set_process(selected)
		queue_redraw()
var dimmed := false:
	set(value):
		dimmed = value
		queue_redraw()
var font_size := 19
## 調子・故障の印（setup_player が GameState.health から読む。show_form は調子を追っている選手のシーズン中だけ）
var show_form := false
var form_level := 0
var injury_mark := ""


var _blink := 0.0


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(128, 34)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	set_process(false)


## 右クリック：選手詳細を開く（左クリック・Ⓐは画面ごとの pressed）
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or player_id.is_empty():
		return
	if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		PlayerDetail.open(self, player_id)
		accept_event()


func _process(delta: float) -> void:
	_blink = fmod(_blink + delta, BLINK_SEC)
	queue_redraw()


## p: 能力値データの選手（GameData.player()）。text: 札に書く名前
func setup_player(p: Dictionary, text: String) -> void:
	tag_text = text
	player_id = str(p.get("id", ""))
	colors = colors_for(p)
	empty_slot = false
	_read_health()
	queue_redraw()


## 調子・故障の印を読む（オートロードの GameState を名前で探す。テストのスクリプトがこの型を読めるように）
func _read_health() -> void:
	show_form = false
	injury_mark = ""
	var tree := Engine.get_main_loop() as SceneTree
	var gs: Node = tree.root.get_node_or_null("GameState") if tree != null else null
	if gs == null or player_id.is_empty() or gs.get("health") == null or not gs.is_daily_phase():
		return
	var h: Health = gs.health
	if not h.form_next.has(player_id):
		return
	show_form = true
	form_level = h.form_level(player_id)
	match h.status(player_id, int(gs.day)):
		"故障":
			injury_mark = "故"
		"調整中":
			injury_mark = "調"


func setup_empty(text: String = "あき") -> void:
	tag_text = text
	player_id = ""
	colors = [COLOR_EMPTY]
	empty_slot = true
	queue_redraw()


## 札の色だけを指定する（「投手」の打順の札など）
func setup_plain(text: String, color: Color) -> void:
	tag_text = text
	player_id = ""
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
	var ci := get_canvas_item()
	var mode := get_draw_mode()
	var sunk := not empty_slot and (mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED)
	var lit := (is_hovered() or has_focus()) and not disabled
	var base: Color = colors[0]
	if lit:
		base = base.lightened(0.16)
	var style := _style(base)
	if sunk:
		style = style.pressed_copy()
	var two_colors := colors.size() > 1
	if two_colors:
		style.gloss = 0.0
	draw_style_box(style, rect)
	var face := style.face_rect(rect)
	var radii := style.face_radii()
	if two_colors:
		# 右側に2つ目の守備位置の色（面のグラデーションを合わせ、ツヤは札全体にまとめて重ねる）
		var second: Color = colors[1].lightened(0.16) if lit else colors[1]
		var x := size.x * 0.62
		var right := Rect2(x, face.position.y, face.end.x - x, face.size.y)
		GlossBox.paint(ci, right, [0, radii[1], radii[2], 0],
			second.lightened(style.gradient), second.darkened(style.gradient * 0.6))
		draw_line(Vector2(x, face.position.y + 1), Vector2(x, face.end.y - 1), Color(1, 1, 1, 0.5), 1.0)
		GlossBox.shine(ci, face, radii, 0.55)

	var font := UiTheme.font(800)
	var fs := font_size
	var badge := clampf(face.size.y * 0.62, 16.0, 28.0)
	var left_pad := badge + 4.0 if not injury_mark.is_empty() else 5.0
	var right_pad := badge + 3.0 if show_form else 5.0
	var width := size.x - left_pad - right_pad
	while fs > MIN_FONT_SIZE \
			and font.get_string_size(tag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 1
	var baseline := face.position.y + (face.size.y + font.get_ascent(fs) - font.get_descent(fs)) / 2.0
	var text_color := UiTheme.TEXT_SUB if empty_slot else UiTheme.TEXT
	var origin := Vector2(left_pad, baseline)
	if not empty_slot:
		draw_string_outline(font, origin + Vector2(0, 1), tag_text, HORIZONTAL_ALIGNMENT_CENTER, width,
			fs, 5, Color(0, 0, 0, 0.12))
		draw_string_outline(font, origin, tag_text, HORIZONTAL_ALIGNMENT_CENTER, width, fs, 5,
			Color(1, 1, 1, 0.92))
	draw_string(font, origin, tag_text, HORIZONTAL_ALIGNMENT_CENTER, width, fs, text_color)
	_draw_health(face, badge)

	if dimmed:
		draw_style_box(UiTheme.box(Color(1, 1, 1, 0.55), RADIUS), rect)
	if has_focus() and not disabled:
		# フォーカス（コントローラーの選択位置）：黄色い光の枠
		var glow := UiTheme.box(Color.TRANSPARENT, RADIUS + 2, UiTheme.FOCUS, 3)
		glow.draw_center = false
		glow.shadow_color = Color(UiTheme.FOCUS, 0.6)
		glow.shadow_size = 6
		draw_style_box(glow, rect.grow(2))
	if selected:
		# 選択中：橙の太枠がゆっくり明滅
		var wave := 0.5 + 0.5 * cos(_blink / BLINK_SEC * TAU)
		var frame_color := Color(SELECT_COLOR, 0.65 + 0.35 * wave)
		var frame := UiTheme.box(Color.TRANSPARENT, RADIUS + 1, frame_color, 4)
		frame.draw_center = false
		frame.shadow_color = Color(SELECT_COLOR, 0.45 * wave)
		frame.shadow_size = int(3 + 5 * wave)
		draw_style_box(frame, rect.grow(2))


## 調子の矢印（右上の丸）と故障の印（左上の角丸）
func _draw_health(face: Rect2, badge: float) -> void:
	var font := UiTheme.font(800)
	var fs := maxi(10, int(badge * 0.78))
	if show_form:
		var c := Vector2(face.end.x - badge * 0.5 - 1.0, face.position.y + badge * 0.5 + 1.0)
		draw_circle(c, badge * 0.5, Health.form_color(form_level))
		draw_arc(c, badge * 0.5, 0.0, TAU, 20, Color(1, 1, 1, 0.9), 1.5, true)
		var mark := Health.form_mark(form_level)
		var w := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + Vector2(-w * 0.5, (font.get_ascent(fs) - font.get_descent(fs)) * 0.5), mark,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if not injury_mark.is_empty():
		var r := Rect2(face.position + Vector2(1, 1), Vector2(badge, badge))
		var box := UiTheme.box(Color("d32f2f") if injury_mark == "故" else Color("ef6c00"), 4, Color.WHITE, 1)
		draw_style_box(box, r)
		var w := font.get_string_size(injury_mark, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, r.get_center() + Vector2(-w * 0.5, (font.get_ascent(fs) - font.get_descent(fs)) * 0.5),
			injury_mark, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _style(base: Color) -> GlossBox:
	var style := UiTheme.gloss(base, RADIUS, 2, DEPTH,
		UiTheme.LINE if empty_slot else base.darkened(0.38))
	style.shadow_size = 2
	style.shadow_color = Color(0, 0, 0, 0.18)
	style.gradient = 0.22
	style.gloss = 0.3 if empty_slot else 0.55
	return style
