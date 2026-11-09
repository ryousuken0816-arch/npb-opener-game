class_name PitcherBoard
extends VBoxContainer
## 選手詳細の投手能力（実況パワフルプロ野球の投手能力画面に寄せた配置。ゲーム側の持ち球・能力だけを使う）。
## 上のタブは 選手能力／投手能力／野手能力／守備・起用／プロフィール。成績・経歴・契約へは、これまでどおり外側のタブ。
## データが無い能力（対ピンチ・クイック・ケガ・回復など）は作らない。

const CHART := preload("res://scenes/player_detail/pitch_chart.tscn")
const SUBS := [
	["player", "選手能力", Color("1e88e5")],
	["pitch", "投手能力", Color("e53935")],
	["bat", "野手能力", Color("1e88e5")],
	["use", "守備・起用", Color("8d6e63")],
	["profile", "プロフィール", Color("2e9b48")],
]
const GRID_COLS := 4
const GRID_SLOTS := 16
const BAD := ["三振取れず", "四球病", "一発病", "キレ×"]
const FLAG_COLORS := {
	"日本": [Color("ffffff"), Color("bc002d")],
	"米国": [Color("3c3b6e"), Color("b22234"), Color("ffffff")],
	"韓国": [Color("ffffff"), Color("cd2e3a"), Color("0047a0")],
	"台湾": [Color("fe0000"), Color("000095")],
	"キューバ": [Color("002a8f"), Color("cb1515"), Color("ffffff")],
	"ドミニカ": [Color("002d62"), Color("ce1126"), Color("ffffff")],
	"ベネズエラ": [Color("cf142b"), Color("ffcc00"), Color("00247d")],
	"メキシコ": [Color("006847"), Color("ffffff"), Color("ce1126")],
	"プエルトリコ": [Color("ffffff"), Color("ed0000"), Color("0050f0")],
	"パナマ": [Color("ffffff"), Color("005293"), Color("d21034")],
	"コロンビア": [Color("fcd116"), Color("003893"), Color("ce1126")],
}

var _detail: PlayerDetail
var _sub := 1


func setup(detail: PlayerDetail, sub: int) -> void:
	_detail = detail
	_sub = clampi(sub, 0, SUBS.size() - 1)
	_build()


func _build() -> void:
	for c in get_children():
		c.free()
	PitchArsenal.ensure(_detail._data)
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_sub_tabs())
	var sheet := PanelContainer.new()
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var skin := UiTheme.card(Color("e07b86"), 14, 3)
	skin.bg_color = Color("e7f4fb")
	skin.shadow_size = 2
	skin.set_content_margin_all(8)
	sheet.add_theme_stylebox_override("panel", skin)
	add_child(sheet)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.add_child(body)
	body.add_child(_header())
	var lower := _lower()
	lower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(lower)


func _sub_tabs() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	var font_size := 15 if UiLayout.is_portrait else 17
	for i in SUBS.size():
		var b := Button.new()
		b.name = "Sub_" + str(SUBS[i][0])
		b.text = SUBS[i][1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", UiTheme.font(800))
		b.add_theme_font_size_override("font_size", font_size)
		var color: Color = SUBS[i][2]
		if i == _sub:
			UiTheme.style_button(b, color, Color.WHITE, 8, 5)
		else:
			UiTheme.style_button(b, color.lerp(Color.WHITE, 0.55), color.darkened(0.35), 8, 3)
		var index := i
		b.pressed.connect(func() -> void: _detail.call_deferred("set_pitch_sub", index))
		row.add_child(b)
	return row


func _header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var data: Dictionary = _detail._data
	var tag := NameTag.new()
	tag.custom_minimum_size = Vector2(176, 48)
	tag.font_size = 22
	tag.setup_player(data, str(data.get("name", "")))
	tag.focus_mode = Control.FOCUS_NONE
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tag)
	var country := _country(data)
	if not country.is_empty():
		row.add_child(_flag(country))
	row.add_child(_number_box())
	row.add_child(_portrait())
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	row.add_child(info)
	info.add_child(_aptitude_line(data))
	info.add_child(_record_line())
	info.add_child(_form_line())
	return row


func _country(data: Dictionary) -> String:
	var imp: Variant = data.get("import")
	if imp is Dictionary and str(imp.get("country", "")).strip_edges() != "":
		return str(imp["country"])
	return ""


func _flag(country: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(36, 26)
	c.tooltip_text = country
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var colors: Array = FLAG_COLORS.get(country, [])
	c.draw.connect(func() -> void: _paint_flag(c, country, colors))
	return c


func _paint_flag(c: Control, country: String, colors: Array) -> void:
	var rect := Rect2(Vector2.ZERO, c.size)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("f7f7f7")
	box.border_color = Color("9aa8b5")
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	c.draw_style_box(box, rect)
	var inner := rect.grow(-2.0)
	if country == "日本":
		c.draw_rect(inner, Color.WHITE)
		c.draw_circle(inner.get_center(), inner.size.y * 0.28, Color("bc002d"))
		return
	if colors.is_empty():
		var font := c.get_theme_default_font()
		if font == null:
			font = ThemeDB.fallback_font
		c.draw_rect(inner, Color("4a6fa5"))
		c.draw_string(font, inner.position + Vector2(0, font.get_ascent(12)), country.substr(0, 1),
			HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 12, Color.WHITE)
		return
	var band_h := inner.size.y / float(colors.size())
	for i in colors.size():
		c.draw_rect(Rect2(inner.position + Vector2(0, band_h * i), Vector2(inner.size.x, band_h + 0.5)), colors[i] as Color)


func _number_box() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(52, 48)
	var style := UiTheme.card(Color("7eb0d4"), 8, 2)
	style.bg_color = Color("f4fbff")
	style.shadow_size = 1
	style.set_content_margin_all(2)
	panel.add_theme_stylebox_override("panel", style)
	panel.tooltip_text = "背番号（データのある年のみ）"
	var label := Label.new()
	label.name = "UniformNumber"
	var num := _detail._uniform_number()
	label.text = num if not num.is_empty() else "－"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiTheme.heading(label, 26, Color("1a4f8b"), Color.WHITE, 4, false)
	panel.add_child(label)
	return panel


func _portrait() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(64, 72)
	c.tooltip_text = "顔写真は未収録"
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void: _paint_portrait(c))
	return c


func _paint_portrait(c: Control) -> void:
	var rect := Rect2(Vector2.ZERO, c.size)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("f7fbfe")
	box.border_color = Color("b7c9d6")
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	c.draw_style_box(box, rect)
	var cx := c.size.x * 0.5
	c.draw_circle(Vector2(cx, c.size.y * 0.36), c.size.x * 0.2, Color("c5d4e0"))
	var shoulder := c.size.x * 0.34
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(cx - shoulder, c.size.y * 0.92),
		Vector2(cx + shoulder, c.size.y * 0.92),
		Vector2(cx + shoulder * 0.72, c.size.y * 0.58),
		Vector2(cx - shoulder * 0.72, c.size.y * 0.58),
	]), Color("c5d4e0"))


func _aptitude_line(data: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(PlayerDetail.pill("適性", 64, 15))
	var active := _aptitude_key(data)
	row.tooltip_text = "今季の登録（先発・中継ぎ・抑え）。登録が無ければ、能力の先発／救援（救援は中継ぎ側に置く）"
	for pair: Array in [["先", "先発"], ["中", "中継ぎ"], ["抑", "抑え"]]:
		row.add_child(_apt_chip(pair[0], pair[0] == active))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	row.add_child(_overall(data))
	return row


func _aptitude_key(data: Dictionary) -> String:
	var sim := _detail.sim_team()
	if sim != null and sim.by_id.has(_detail.player_id):
		var p: SimPlayer = sim.by_id[_detail.player_id]
		if sim.is_active(p) and p.is_pitcher:
			match str(sim.pitcher_role(p)[0]):
				SimTeam.ROLE_ROTATION:
					return "先"
				SimTeam.ROLE_CLOSER:
					return "抑"
				_:
					return "中"
	match PlayerDetail._role_of(data):
		"先発":
			return "先"
		"救援":
			return "中"
		_:
			return ""


func _apt_chip(text: String, active: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(36, 30)
	var bg := Color("2f9e55") if active else Color("eef3f7")
	var edge := Color("1d7a40") if active else Color("c5d0da")
	var style := UiTheme.gloss(bg, 6, 2, 2, edge)
	style.shadow_size = 1
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 0
	style.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(label, 16, Color.WHITE if active else Color("5c6b7a"), Color.WHITE, 3, false)
	panel.add_child(label)
	return panel


func _overall(data: Dictionary) -> HBoxContainer:
	var rating: Variant = _detail._dict(_detail._dict(data.get("pitching")).get("ratings")).get("overall")
	var row := HBoxContainer.new()
	row.name = "Overall"
	row.add_theme_constant_override("separation", 4)
	row.tooltip_text = "投手の総合（制球・スタミナ・奪三振・被弾抑制などからの見立て）"
	var star := Control.new()
	star.custom_minimum_size = Vector2(46, 46)
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var value_text := str(int(rating["value"])) if rating is Dictionary else "－"
	star.draw.connect(func() -> void: _paint_star(star, value_text))
	row.add_child(star)
	row.add_child(UiTheme.rank_label(rating, 28))
	return row


func _paint_star(c: Control, value_text: String) -> void:
	var center := c.size * 0.5
	var radius := minf(c.size.x, c.size.y) * 0.48
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI * 0.5 + float(i) * PI / 5.0
		var rad := radius if i % 2 == 0 else radius * 0.42
		pts.append(center + Vector2.from_angle(ang) * rad)
	c.draw_colored_polygon(pts, Color("f5c518"))
	var outline := pts.duplicate()
	outline.append(pts[0])
	c.draw_polyline(outline, Color("c48a00"), 1.4, true)
	var font := c.get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	var fs := 15 if value_text.length() >= 3 else 18
	var sz := font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := center - Vector2(sz.x * 0.5, sz.y * 0.42)
	c.draw_string(font, pos + Vector2(0, font.get_ascent(fs)), value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color("6b4a00"))


func _record_line() -> Label:
	var label := Label.new()
	label.name = "SeasonMain"
	label.text = _record_text()
	label.clip_text = true
	UiTheme.heading(label, 20, Color("1a4f8b"), Color.WHITE, 4, false)
	label.tooltip_text = "今季の1軍成績。HPはホールド＋救援での勝利"
	return label


func _record_text() -> String:
	var s := _detail._season_pitching()
	if s.is_empty() or int(s.get("g", 0)) <= 0:
		return "防---　--勝--敗　--HP　--S"
	var era := StatTable.era_text(s)
	if era == "-":
		era = "---"
	var hp := int(s.get("hld", 0)) + maxi(int(s.get("w", 0)) - int(s.get("gs", 0)), 0)
	return "防%s　%d勝%d敗　%dHP　%dS" % [era, int(s.get("w", 0)), int(s.get("l", 0)), hp, int(s.get("sv", 0))]


func _form_line() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(PlayerDetail.pill("フォーム", 86, 14))
	var form := Label.new()
	form.name = "PitchForm"
	form.text = "―"
	form.tooltip_text = "投球フォームのデータは未収録"
	UiTheme.heading(form, 16, Color("5c6b7a"), Color.WHITE, 3, false)
	row.add_child(form)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(12, 0)
	row.add_child(gap)
	row.add_child(PlayerDetail.pill("投打", 56, 14))
	var tb := Label.new()
	tb.text = _detail.throws_bats()
	UiTheme.heading(tb, 16, Color("1e3348"), Color.WHITE, 3, false)
	row.add_child(tb)
	return row


func _lower() -> Control:
	match str(SUBS[_sub][0]):
		"pitch":
			return _pitch_columns()
		"player":
			return _detail.pitcher_overview()
		"bat":
			return _detail.pitcher_batting_view()
		"use":
			return _detail.pitcher_usage_view()
		_:
			return _detail.pitcher_profile_view()


func _pitch_columns() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.15
	row.add_child(left)
	left.add_child(_velocity_row())
	left.add_child(_rated_row("コントロール", _rating("bb9"), "与四球の少なさ（BB/9）"))
	left.add_child(_rated_row("スタミナ", _rating("stamina"), _detail._pitching_note("stamina")))
	var pitching: Dictionary = _detail._dict(_detail._data.get("pitching"))
	var pitches: Array = pitching.get("pitches", []) if pitching.get("pitches") is Array else []
	var best: Dictionary = PitchArsenal.best_pitch(_detail._data)
	var velo: Dictionary = _detail._dict(pitching.get("velocity"))
	var kmh := float(velo["kmh"]) if velo.get("kmh") != null else -1.0
	var chart: PitchChart = CHART.instantiate()
	chart.name = "PitchChart"
	chart.set_pitches(pitches, str(best.get("name", "")), kmh)
	chart.custom_minimum_size = Vector2(340, 196)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(chart)
	var cap := Label.new()
	cap.name = "BestPitch"
	cap.text = "決め球　%s" % str(best["name"]) if not best.is_empty() else "決め球　―"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(cap, 15, Color("8a5a00"), Color.WHITE, 3, false)
	left.add_child(cap)
	row.add_child(_ability_grid())
	return row


func _rating(key: String) -> Variant:
	return _detail._dict(_detail._dict(_detail._data.get("pitching")).get("ratings")).get(key)


func _velocity_row() -> PanelContainer:
	var velo: Dictionary = _detail._dict(_detail._dict(_detail._data.get("pitching")).get("velocity"))
	var text := "%d" % int(velo["kmh"]) if velo.get("kmh") != null else "－"
	var row := _row_shell()
	var box: HBoxContainer = row.get_child(0)
	box.add_child(PlayerDetail.pill("球速", 118, 16))
	var value := Label.new()
	value.text = text
	value.custom_minimum_size = Vector2(78, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.heading(value, 32, Color("1a4f8b"), Color.WHITE, 4, false)
	box.add_child(value)
	var unit := Label.new()
	unit.text = "km/h"
	UiTheme.heading(unit, 16, Color("3d5a80"), Color.WHITE, 3, false)
	box.add_child(unit)
	var note := _detail.note_label(_detail._velocity_note(velo))
	box.add_child(note)
	return row


func _rated_row(title: String, rating: Variant, note_text: String) -> PanelContainer:
	var row := _row_shell()
	var box: HBoxContainer = row.get_child(0)
	box.add_child(PlayerDetail.pill(title, 118, 16))
	var rank := UiTheme.rank_label(rating, 30)
	rank.custom_minimum_size = Vector2(36, 0)
	box.add_child(rank)
	var value := Label.new()
	value.text = str(int(rating["value"])) if rating is Dictionary else "－"
	value.custom_minimum_size = Vector2(48, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var color := UiTheme.rank_color(rating["rank"]).darkened(0.05) if rating is Dictionary else UiTheme.TEXT
	UiTheme.heading(value, 28, color, Color.WHITE, 4, false)
	box.add_child(value)
	box.add_child(_detail.note_label(note_text))
	return row


func _row_shell() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := UiTheme.card(Color("c5d8ea"), 8, 1)
	style.bg_color = Color("f7fbff")
	style.shadow_size = 1
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	style.content_margin_left = 6
	style.content_margin_right = 6
	panel.add_theme_stylebox_override("panel", style)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	return panel


func _ability_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.name = "AbilityGrid"
	grid.columns = GRID_COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.size_flags_stretch_ratio = 1.0
	# 縦画面ではこの幅で左の図と折り返す（実幅はタイル4列より小さいので、横画面はそのまま横に並ぶ）
	grid.custom_minimum_size = Vector2(360, 0)
	var entries := _grid_entries()
	while entries.size() < GRID_SLOTS:
		entries.append({"kind": "empty"})
	for e: Dictionary in entries:
		grid.add_child(_tile(e))
	return grid


func _grid_entries() -> Array:
	var out: Array = []
	out.append(_rank_entry("奪三振", _rating("k9"), "奪三振の能力（球速と持ち球から計算した値）"))
	out.append(_rank_entry("打たれ強さ", _rating("hr9"), "被本塁打の少なさ（球速と持ち球から計算した値）"))
	out.append(_rank_entry("対左打者", _vs_left(), "左打者への奪三振の上下（持ち球の左右の得意から。平均付近はD）"))
	out.append(_rank_entry("ゴロ", _groundball_rating(), "ゴロの多さ（持ち球から。高いほどゴロが多い）"))
	var abilities: Array = _detail._dict(_detail._data.get("pitching")).get("abilities", [])
	for ability: Variant in abilities:
		var text := str(ability)
		out.append({"kind": "name", "title": text, "bad": text in BAD,
			"tip": "成績から付いた特殊能力"})
	var best := PitchArsenal.best_pitch(_detail._data)
	if not best.is_empty():
		var move := int(best.get("move", 0))
		if move >= 6:
			out.append({"kind": "name", "title": "キレ○", "bad": false,
				"tip": "決め球 %s の変化量 %d" % [best["name"], move]})
		elif move <= 2:
			out.append({"kind": "name", "title": "キレ×", "bad": true,
				"tip": "決め球 %s の変化量 %d" % [best["name"], move]})
	return out


func _rank_entry(title: String, rating: Variant, tip: String) -> Dictionary:
	return {"kind": "rank", "title": title, "rating": rating, "tip": tip}


func _vs_left() -> Dictionary:
	var pitches: Array = _detail._dict(_detail._data.get("pitching")).get("pitches", [])
	if not pitches is Array:
		pitches = []
	var throws := str(_detail._data.get("throws", "右"))
	var pl: Array = PitchArsenal.platoon(pitches, throws)
	var v := float(pl[0] if throws == "左" else pl[1])
	var value := clampi(roundi(50.0 + v * 35.0), 1, 99)
	return {"value": value, "rank": Growth.rank_of(float(value))}


func _groundball_rating() -> Dictionary:
	var pitches: Array = _detail._dict(_detail._data.get("pitching")).get("pitches", [])
	if not pitches is Array:
		pitches = []
	var z := PitchArsenal.groundball(pitches)
	var value := clampi(roundi(50.0 + z * 15.0), 1, 99)
	return {"value": value, "rank": Growth.rank_of(float(value))}


func _tile(e: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(108, 52)
	var kind := str(e.get("kind", "empty"))
	var bg := Color("e7f3fb")
	var edge := Color("d0e3f0")
	var bad := bool(e.get("bad", false))
	if kind == "name":
		bg = Color("ffc3cb") if bad else Color("b7e4f8")
		edge = Color("e08b96") if bad else Color("7ec4e4")
	var style := UiTheme.gloss(bg, 8, 1, 2, edge)
	style.shadow_size = 1
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	if kind == "empty":
		return panel
	panel.tooltip_text = str(e.get("tip", ""))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if kind == "rank":
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		var title := Label.new()
		title.text = str(e["title"])
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.clip_text = true
		UiTheme.heading(title, 15, Color("1e3348"), Color.WHITE, 3, false)
		box.add_child(title)
		var rank := UiTheme.rank_label(e.get("rating"), 26)
		rank.custom_minimum_size = Vector2(28, 0)
		box.add_child(rank)
		panel.add_child(box)
		return panel
	var name := Label.new()
	name.text = str(e["title"])
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiTheme.heading(name, 18, Color("c62828") if bad else Color("0d47a1"), Color.WHITE, 4, false)
	panel.add_child(name)
	return panel
