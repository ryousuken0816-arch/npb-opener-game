class_name HubStatusCard
extends PanelContainer
## ハブの球団の札の下に出す小さな札：1軍の故障者の知らせ（作業45。采配の1軍登録で入れ替えを促す）。
## 知らせることが無ければ隠す。パソコンは中央の球団の札の下、スマホの縦はダッシュボードの見出しの下に置く

var _palette: UiTheme.Palette
var _box: VBoxContainer
var _width := 0.0


## width：札の幅（0 なら親に合わせる）
func setup(p: UiTheme.Palette, width := 0.0) -> void:
	_palette = p
	_width = width
	var style := UiTheme.card(Color.WHITE, 10, 2, 0.94)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if width > 0.0:
		custom_minimum_size = Vector2(width, 0)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)


func refresh() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var hurt: Array[SimPlayer] = GameState.injured_on_first()
	if not hurt.is_empty():
		var names: Array[String] = []
		for p in hurt:
			names.append("%s（あと%d日）" % [p.name.split(" ")[0], GameState.health.days_left(p.id, GameState.day)])
		_line("1軍に故障者 %d人" % hurt.size(), 18, Color("d32f2f"), 800)
		_line("%s。試合に出られないので、采配の1軍登録で2軍と入れ替えましょう" % "、".join(names), 15,
			UiTheme.TEXT, 700)
	visible = _box.get_child_count() > 0


func _line(text: String, font_size: int, color: Color, weight: int) -> Label:
	var label := UiTheme.small_label(text, font_size, color, weight)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _width > 0.0:
		label.custom_minimum_size = Vector2(_width - 24.0, 0)
	_box.add_child(label)
	return label
