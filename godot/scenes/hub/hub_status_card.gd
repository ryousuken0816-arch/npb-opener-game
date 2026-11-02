class_name HubStatusCard
extends PanelContainer
## ハブの球団の札の下に出す小さな札：1軍の故障者の知らせ（作業45。采配の1軍登録で入れ替えを促す）と、
## オーナーの今年の目標と進み具合（作業46。○＝今のところ達成のペース）。表彰のあとの評価が出たら、春季キャンプまで評価を出す。
## 知らせることが無ければ隠す。パソコンは中央の球団の札の下、スマホの縦はダッシュボードの見出しの下に置く

const DONE_COLOR := Color("2e7d32")
const MISS_COLOR := Color("d32f2f")
const GRADE_COLORS := {"S": Color("d81b60"), "A": Color("e65100"), "B": Color("2e7d32"), "C": Color("1565c0"),
	"D": Color("6d4c41"), "E": Color("455a64")}

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
	_owner_lines()
	visible = _box.get_child_count() > 0


## オーナーの目標（今年）か、表彰のあとの評価
func _owner_lines() -> void:
	var og: OwnerGoals = GameState.owner_goals
	if og == null:
		return
	var y: int = GameState.year
	var e := og.eval_of(y)
	if not e.is_empty() and GameState.phase not in [GameState.Phase.SEASON, GameState.Phase.POSTSEASON,
			GameState.Phase.AWARDS, GameState.Phase.CAMP]:
		var head := _line("オーナーの評価（%d年）：%s" % [y, e["grade"]], 18, GRADE_COLORS.get(e["grade"], UiTheme.TEXT), 800)
		head.tooltip_text = str(e["comment"])
		var delta := int(e["budget_delta"])
		_line("「%s」%s" % [e["comment"], "" if delta == 0 else "　来季の予算 %s%s" % [
			"+" if delta > 0 else "−", OwnerGoals.money_text(absi(delta))]], 15, UiTheme.TEXT, 700)
		return
	var rows: Array = GameState.owner_progress()
	if rows.is_empty():
		return
	_line("オーナーの目標（%d年）" % y, 18, _palette.ink if _palette != null else UiTheme.TEXT, 800)
	for r: Dictionary in rows:
		var mark := "・" if not r["started"] else ("○" if r["done"] else "×")
		var color: Color = UiTheme.TEXT if not r["started"] else (DONE_COLOR if r["done"] else MISS_COLOR)
		_line("%s %s　%s" % [mark, r["text"], r["actual"]], 15, color, 700)


func _line(text: String, font_size: int, color: Color, weight: int) -> Label:
	var label := UiTheme.small_label(text, font_size, color, weight)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _width > 0.0:
		label.custom_minimum_size = Vector2(_width - 24.0, 0)
	_box.add_child(label)
	return label
