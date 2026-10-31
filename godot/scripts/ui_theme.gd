class_name UiTheme
extends RefCounted
## 画面の配色とテーマ。明るい背景に球団カラーのアクセントを乗せる（docs/references/README.md）。
## ボタン・見出し帯・名前札は GlossBox（縦グラデーション＋ツヤ＋縁取り＋厚み）で立体的に描く。
## 見出し・ボタン・日付の文字は太字に縁取り＋軽い影、本文は読みやすさ優先で縁取りなし。

## 同梱フォント（M PLUS Rounded 1c、SIL OFL。assets/fonts/OFL.txt）
const FONT_MEDIUM := "res://assets/fonts/MPLUSRounded1c-Medium.ttf"
const FONT_EXTRA_BOLD := "res://assets/fonts/MPLUSRounded1c-ExtraBold.ttf"
## 同梱フォントにない字（選手名の一部の人名漢字など）は OS のフォントで表示する
const FALLBACK_FONT_NAMES := [
	"Yu Gothic UI", "Meiryo UI", "Meiryo", "Hiragino Sans", "Hiragino Kaku Gothic ProN",
	"Noto Sans CJK JP", "Noto Sans JP", "IPAGothic", "sans-serif",
]

## Button の文字色の各状態
const BUTTON_FONT_COLORS := [
	"font_color", "font_hover_color", "font_pressed_color",
	"font_focus_color", "font_hover_pressed_color",
]

const TEXT := Color("2b2f36")
const TEXT_SUB := Color("5f6670")
const LINE := Color("d5dae0")
## 選ばれている（トグルが入っている）ボタンの色（参考画像の采配メニューの橙）
const ACCENT := Color("ff9800")
## トグルの通常時（淡い水色）とホバー（淡い黄）
const TOGGLE_OFF := Color("e3f3fc")
const TOGGLE_HOVER := Color("fff1c9")
const BUTTON_DEPTH := 4
## 選択中（フォーカス＝十字キーの選択位置、マウスを乗せた項目）の光の枠の色
const FOCUS := Color("ffd400")


## 球団カラーから作る配色
class Palette:
	var main: Color      ## 球団のメインカラー（帯・見出しの塗り）
	var sub: Color       ## サブカラー（縁取り・差し色）
	var on_main: Color   ## main の上に置く文字色
	var ink: Color       ## 明るい背景の上に置く強調文字色（main が明るすぎる球団は sub か黒）
	var tint: Color      ## main をごく薄くした色（選択行など）
	var bg_top: Color    ## 背景グラデーション
	var bg_bottom: Color

	func _init(main_color: Color, sub_color: Color) -> void:
		main = main_color
		sub = sub_color
		on_main = Color.WHITE if main.get_luminance() < 0.6 else TEXT
		if main.get_luminance() < 0.58:
			ink = main
		elif sub.get_luminance() < 0.58:
			ink = sub
		else:
			ink = TEXT
		tint = main.lerp(Color.WHITE, 0.85)
		bg_top = main.lerp(Color.WHITE, 0.94)
		bg_bottom = main.lerp(Color.WHITE, 0.8)


static var _fonts := {}


static func team_palette(team: String) -> Palette:
	var colors := GameData.team_colors(team)
	return Palette.new(colors[0], colors[1])


static func neutral_palette() -> Palette:
	return Palette.new(Color(GameData.DEFAULT_TEAM_COLORS[0]), Color(GameData.DEFAULT_TEAM_COLORS[1]))


## weight: 600 以下は本文用（Medium）、700 以上は見出し用（ExtraBold）
static func font(weight: int = 500) -> Font:
	var bold := weight >= 700
	if not _fonts.has(bold):
		var fallback := SystemFont.new()
		fallback.font_names = PackedStringArray(FALLBACK_FONT_NAMES)
		fallback.font_weight = 700 if bold else 400
		var f: Font = load(FONT_EXTRA_BOLD if bold else FONT_MEDIUM)
		f.fallbacks = [fallback]
		_fonts[bold] = f
	return _fonts[bold]


## 明度に応じて白か濃い文字色を返す
static func text_on(color: Color) -> Color:
	return Color.WHITE if color.get_luminance() < 0.6 else TEXT


static func box(color: Color, radius: int = 8, border_color := Color.TRANSPARENT,
		border := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_color = border_color
	s.set_border_width_all(border)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


## 立体的なボタン・帯の StyleBox（縦グラデーション＋ツヤ＋縁取り＋下側の厚み＋影）
static func gloss(color: Color, radius: int = 10, border := 2, depth := BUTTON_DEPTH,
		border_color := Color.TRANSPARENT) -> GlossBox:
	var s := GlossBox.new()
	s.bg_color = color
	s.border_color = border_color if border_color.a > 0.0 else edge_color(color)
	s.set_border_width_all(border)
	s.set_corner_radius_all(radius)
	s.depth = depth
	s.shadow_color = Color(0, 0, 0, 0.22)
	s.shadow_size = 3 if depth > 0 else 0
	s.shadow_offset = Vector2(0, 2)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 5
	s.content_margin_bottom = 5 + depth
	return s


## 白いカード（ツヤなし、ごく薄い縦グラデーションと影）
static func card(border_color: Color, radius: int = 12, border := 2, alpha := 0.96) -> GlossBox:
	var s := GlossBox.new()
	s.bg_color = Color(1, 1, 1, alpha)
	s.border_color = border_color
	s.set_border_width_all(border)
	s.set_corner_radius_all(radius)
	s.gloss = 0.0
	s.gradient = 0.05
	s.shadow_color = Color(0, 0, 0, 0.16)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


## 選択中（フォーカス）の光の枠。ボタンの上に重ねて描かれる
static func focus_frame(radius := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = FOCUS
	s.set_border_width_all(3)
	s.set_corner_radius_all(radius + 2)
	s.set_expand_margin_all(3)
	s.shadow_color = Color(FOCUS, 0.55)
	s.shadow_size = 7
	s.anti_aliasing = true
	return s


## 塗りの色に合う縁取りの色（少し暗く、彩度はそのまま）
static func edge_color(color: Color) -> Color:
	return Color(color.darkened(0.32 if color.get_luminance() > 0.35 else 0.45), maxf(color.a, 0.6))


## 文字の縁取りの色：白い文字には塗りの色を暗くした色、濃い文字には白
static func outline_for(text_color: Color, bg: Color) -> Color:
	if text_color.get_luminance() > 0.6:
		return bg.darkened(0.6)
	return Color(1, 1, 1, 0.9)


## ボタンの全状態の見た目をまとめて付ける（通常・ホバーで明るく・押すと沈む・無効は灰色）
static func style_button(b: Button, color: Color, text_color := Color.TRANSPARENT, radius := 10,
		outline := 6) -> void:
	for state_style: Array in button_styles(color, radius):
		b.add_theme_stylebox_override(state_style[0], state_style[1])
	var ink := text_color if text_color.a > 0.0 else text_on(color)
	for c in BUTTON_FONT_COLORS:
		b.add_theme_color_override(c, ink)
	b.add_theme_color_override("font_outline_color", outline_for(ink, color))
	b.add_theme_constant_override("outline_size", outline)


## [状態名, StyleBox] の一覧
static func button_styles(color: Color, radius := 10) -> Array:
	var normal := gloss(color, radius)
	var hover := gloss(color.lightened(0.14), radius)
	hover.border_color = edge_color(color)
	var pressed := normal.pressed_copy()
	var disabled := gloss(Color("d3d8de"), radius, 2, 2)
	disabled.gloss = 0.25
	var focus := focus_frame(radius)
	return [["normal", normal], ["hover", hover], ["pressed", pressed],
		["hover_pressed", pressed], ["disabled", disabled], ["focus", focus]]


## 選ぶボタン（采配メニュー・思考設定・DHあり/なし）：通常は淡い水色、ホバーは淡い黄、
## 選ばれている間は橙で沈み、ゆっくり明滅する（UiFx）
static func style_toggle(b: Button, ink: Color, radius := 10) -> void:
	var normal := gloss(TOGGLE_OFF, radius, 2, 3, Color("8ecae6"))
	var hover := gloss(TOGGLE_HOVER, radius, 3, 3, Color("ffb74d"))
	var on := gloss(ACCENT, radius, 3, 3, Color("e65100")).pressed_copy()
	on.gloss = 0.55
	var disabled := gloss(Color("eef1f4"), radius, 2, 2, Color("cfd6dd"))
	disabled.gloss = 0.2
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", focus_frame(radius))
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(c, ink)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	b.add_theme_constant_override("outline_size", 5)
	# 選ばれている間の白い文字には濃い橙の縁取り。縁取りの色は Button の状態ごとに持てないので、
	# 描いたあとに状態を見て入れ替える（set_pressed_no_signal で切り替えられても追従する）。
	# 描いている最中に変えると描き直しが起きず古い色のまま残るので、描き終わってから変える
	var sync := func() -> void:
		if not is_instance_valid(b):
			return
		var want := Color("b34700") if b.button_pressed and not b.disabled else Color(1, 1, 1, 0.9)
		if b.get_theme_color("font_outline_color") != want:
			b.add_theme_color_override("font_outline_color", want)
	b.draw.connect(func() -> void: sync.call_deferred())


## 見出し・日付などの太字に縁取りと軽い影を付ける（Label）
static func heading(label: Label, font_size: int, color: Color, outline_color := Color.WHITE,
		outline := 8, shadow := true) -> void:
	var s := LabelSettings.new()
	s.font = font(800)
	s.font_size = font_size
	s.font_color = color
	s.outline_size = outline
	s.outline_color = outline_color
	if shadow:
		s.shadow_color = Color(0, 0, 0, 0.22)
		s.shadow_size = maxi(outline, 1)
		s.shadow_offset = Vector2(1, 3)
	else:
		s.shadow_color = Color.TRANSPARENT
	label.label_settings = s


## 画面全体のテーマ（ルートの Control に設定すると子に継承される）
static func build(p: Palette) -> Theme:
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = 18

	t.set_color("font_color", "Label", TEXT)

	# ボタン（球団カラー、立体）
	for state_style: Array in button_styles(p.main):
		t.set_stylebox(state_style[0], "Button", state_style[1])
	for c in BUTTON_FONT_COLORS:
		t.set_color(c, "Button", p.on_main)
	t.set_color("font_disabled_color", "Button", TEXT_SUB)
	t.set_color("font_outline_color", "Button", outline_for(p.on_main, p.main))
	t.set_constant("outline_size", "Button", 6)
	t.set_font("font", "Button", font(700))

	# パネル（白カード＋影）
	var card_style := card(p.main.lerp(Color.WHITE, 0.55))
	t.set_stylebox("panel", "Panel", card_style)
	t.set_stylebox("panel", "PanelContainer", card_style)

	# タブ（選択中は球団カラーの立体、ほかは淡い灰色）
	var tab_selected := gloss(p.main, 0, 2, 0)
	tab_selected.corner_radius_top_left = 9
	tab_selected.corner_radius_top_right = 9
	tab_selected.border_width_bottom = 0
	tab_selected.shadow_size = 0
	var tab_unselected := gloss(Color("e3e7eb"), 0, 1, 0, LINE)
	tab_unselected.corner_radius_top_left = 9
	tab_unselected.corner_radius_top_right = 9
	tab_unselected.border_width_bottom = 0
	tab_unselected.gloss = 0.3
	var tab_hovered := tab_unselected.copy()
	tab_hovered.bg_color = p.tint
	t.set_stylebox("tab_selected", "TabContainer", tab_selected)
	t.set_stylebox("tab_unselected", "TabContainer", tab_unselected)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hovered)
	t.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("panel", "TabContainer", box(Color.WHITE, 0, p.main, 2))
	t.set_color("font_selected_color", "TabContainer", p.on_main)
	t.set_color("font_unselected_color", "TabContainer", TEXT_SUB)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_color("font_outline_color", "TabContainer", outline_for(p.on_main, p.main))
	t.set_constant("outline_size", "TabContainer", 5)
	t.set_font("font", "TabContainer", font(700))

	# 一覧（Tree）
	t.set_stylebox("panel", "Tree", box(Color.WHITE, 0))
	t.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("selected", "Tree", box(p.tint, 0))
	t.set_stylebox("selected_focus", "Tree", box(p.tint, 0))
	var cursor := box(Color.TRANSPARENT, 0, p.main, 2)
	cursor.draw_center = false
	t.set_stylebox("cursor", "Tree", cursor)
	t.set_stylebox("cursor_unfocused", "Tree", cursor)
	var title_button := gloss(p.main, 0, 1, 0)
	title_button.shadow_size = 0
	var title_hover := title_button.copy()
	title_hover.bg_color = p.main.lightened(0.14)
	t.set_stylebox("title_button_normal", "Tree", title_button)
	t.set_stylebox("title_button_hover", "Tree", title_hover)
	t.set_stylebox("title_button_pressed", "Tree", title_button.pressed_copy())
	t.set_color("title_button_color", "Tree", p.on_main)
	t.set_font("title_button_font", "Tree", font(700))
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("font_selected_color", "Tree", TEXT)
	t.set_color("guide_color", "Tree", Color(0, 0, 0, 0.08))
	t.set_constant("v_separation", "Tree", 8)

	# スクロールバー（つまみも立体）
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, box(Color("e6eaee"), 5))
		var grabber := gloss(p.main.lerp(Color.WHITE, 0.3), 5, 1, 0)
		grabber.shadow_size = 0
		grabber.set_content_margin_all(4)
		var grabber_hi := grabber.copy()
		grabber_hi.bg_color = p.main
		t.set_stylebox("grabber", type, grabber)
		t.set_stylebox("grabber_highlight", type, grabber_hi)
		t.set_stylebox("grabber_pressed", type, grabber_hi)

	# ツールチップ
	var tip := box(Color.WHITE, 6, p.main.lerp(Color.WHITE, 0.3), 2)
	tip.shadow_color = Color(0, 0, 0, 0.18)
	tip.shadow_size = 4
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t


## 見出しの帯つきの白いパネル（参考画像の「1軍」「2軍」の枠）。見出しの帯は球団カラーの立体。
## 戻り値は {panel: PanelContainer, body: VBoxContainer（中身を入れる）, title: Label}
static func titled_panel(p: Palette, title: String) -> Dictionary:
	var panel := PanelContainer.new()
	var style := card(p.main, 10, 3, 0.97)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	var head := PanelContainer.new()
	var head_style := gloss(p.main, 0, 0, 0)
	head_style.corner_radius_top_left = 8
	head_style.corner_radius_top_right = 8
	head_style.shadow_size = 0
	head_style.gloss = 0.5
	head_style.content_margin_top = 2
	head_style.content_margin_bottom = 3
	head.add_theme_stylebox_override("panel", head_style)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading(label, 19, p.on_main, outline_for(p.on_main, p.main), 6, false)
	head.add_child(label)
	vbox.add_child(head)
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	vbox.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	margin.add_child(body)
	return {"panel": panel, "body": body, "title": label}


## ランク（S〜G）の色付きラベル（太字＋白と濃い色の二重の縁取り）。rating は能力値データの {value, rank}（null なら「-」）
static func rank_label(rating: Variant, font_size: int = 20) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font(800))
	label.add_theme_font_size_override("font_size", font_size)
	if rating is Dictionary and rating.get("rank") != null:
		label.text = rating["rank"]
		var color := GameData.rank_color(rating["rank"])
		label.add_theme_color_override("font_color", color)
		# 色付きの太字に白の縁取り、その外側に濃い色の縁（影を縁取りとして使う）
		label.add_theme_color_override("font_outline_color", Color.WHITE)
		var outline := maxi(font_size / 5, 3)
		label.add_theme_constant_override("outline_size", outline)
		label.add_theme_color_override("font_shadow_color", color.darkened(0.45))
		label.add_theme_constant_override("shadow_outline_size", outline + 2)
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.tooltip_text = str(int(rating["value"]))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
	else:
		label.text = "-"
		label.add_theme_color_override("font_color", TEXT_SUB)
	return label


## 小さな文字のラベル
static func small_label(text: String, font_size: int = 15, color: Color = TEXT_SUB,
		weight: int = 500) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font(weight))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## 長くなりうる1行の文言（メッセージ・見出し）：最小幅を0にして、入りきらない分は「…」で省く。
## 文言の長さで HBox の最小幅が広がり、画面の外へはみ出さないようにする（docs/AUTORUN.md 作業11）
static func fit_label(label: Label) -> Label:
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label

## 画面のルートのパネル（ハブのサブ画面・選手詳細）の中身を包む ScrollContainer の設定。
## 中身の最小の大きさが枠を超えたときだけスクロールバーが出て、パネルが画面の外へ広がらない
## （収まっているときは見た目は変わらない。docs/AUTORUN.md 作業11）
static func fit_scroll(scroll: ScrollContainer, content: Control) -> void:
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.focus_mode = Control.FOCUS_NONE
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
