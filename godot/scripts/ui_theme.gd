class_name UiTheme
extends RefCounted
## 画面の配色とテーマ。明るい背景に球団カラーのアクセントを乗せる（docs/references/README.md）。

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


## 画面全体のテーマ（ルートの Control に設定すると子に継承される）
static func build(p: Palette) -> Theme:
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = 18

	t.set_color("font_color", "Label", TEXT)

	# ボタン（球団カラー）
	t.set_stylebox("normal", "Button", box(p.main))
	t.set_stylebox("hover", "Button", box(p.main.lightened(0.15)))
	t.set_stylebox("pressed", "Button", box(p.main.darkened(0.15)))
	t.set_stylebox("hover_pressed", "Button", box(p.main.darkened(0.1)))
	t.set_stylebox("disabled", "Button", box(Color("c9ced4")))
	var focus := box(Color.TRANSPARENT, 8, p.sub if p.sub.get_luminance() < 0.8 else TEXT, 3)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	for c in BUTTON_FONT_COLORS:
		t.set_color(c, "Button", p.on_main)
	t.set_color("font_disabled_color", "Button", TEXT_SUB)
	t.set_font("font", "Button", font(700))

	# パネル（白カード）
	var card := box(Color(1, 1, 1, 0.95), 12, p.main.lerp(Color.WHITE, 0.55), 2)
	t.set_stylebox("panel", "Panel", card)
	t.set_stylebox("panel", "PanelContainer", card)

	# タブ
	var tab_selected := box(p.main, 0)
	tab_selected.corner_radius_top_left = 8
	tab_selected.corner_radius_top_right = 8
	var tab_unselected := tab_selected.duplicate() as StyleBoxFlat
	tab_unselected.bg_color = Color("e6e9ed")
	var tab_hovered := tab_selected.duplicate() as StyleBoxFlat
	tab_hovered.bg_color = p.tint
	t.set_stylebox("tab_selected", "TabContainer", tab_selected)
	t.set_stylebox("tab_unselected", "TabContainer", tab_unselected)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hovered)
	t.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("panel", "TabContainer", box(Color.WHITE, 0, p.main, 2))
	t.set_color("font_selected_color", "TabContainer", p.on_main)
	t.set_color("font_unselected_color", "TabContainer", TEXT_SUB)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
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
	t.set_stylebox("title_button_normal", "Tree", box(p.main, 0))
	t.set_stylebox("title_button_hover", "Tree", box(p.main.lightened(0.15), 0))
	t.set_stylebox("title_button_pressed", "Tree", box(p.main.darkened(0.15), 0))
	t.set_color("title_button_color", "Tree", p.on_main)
	t.set_font("title_button_font", "Tree", font(700))
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("font_selected_color", "Tree", TEXT)
	t.set_color("guide_color", "Tree", Color(0, 0, 0, 0.08))
	t.set_constant("v_separation", "Tree", 8)

	# スクロールバー
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, box(Color("eceff2"), 4))
		t.set_stylebox("grabber", type, box(p.main.lerp(Color.WHITE, 0.4), 4))
		t.set_stylebox("grabber_highlight", type, box(p.main, 4))
		t.set_stylebox("grabber_pressed", type, box(p.main.darkened(0.15), 4))

	# ツールチップ
	t.set_stylebox("panel", "TooltipPanel", box(Color.WHITE, 4, LINE, 1))
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t


## 見出しの帯つきの白いパネル（参考画像の「1軍」「2軍」の枠）。
## 戻り値は {panel: PanelContainer, body: VBoxContainer（中身を入れる）, title: Label}
static func titled_panel(p: Palette, title: String) -> Dictionary:
	var panel := PanelContainer.new()
	var style := box(Color(1, 1, 1, 0.97), 10, p.main, 3)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	var head := PanelContainer.new()
	var head_style := box(p.main, 0)
	head_style.corner_radius_top_left = 8
	head_style.corner_radius_top_right = 8
	head_style.content_margin_top = 3
	head_style.content_margin_bottom = 3
	head.add_theme_stylebox_override("panel", head_style)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font(800))
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", p.on_main)
	head.add_child(label)
	vbox.add_child(head)
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	vbox.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	margin.add_child(body)
	return {"panel": panel, "body": body, "title": label}


## ランク（S〜G）の色付きラベル。rating は能力値データの {value, rank}（null なら「-」）
static func rank_label(rating: Variant, font_size: int = 20) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font(800))
	label.add_theme_font_size_override("font_size", font_size)
	if rating is Dictionary and rating.get("rank") != null:
		label.text = rating["rank"]
		label.add_theme_color_override("font_color", GameData.rank_color(rating["rank"]))
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
