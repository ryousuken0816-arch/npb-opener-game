class_name Celebration
extends CanvasLayer
## 優勝・日本一の演出（胴上げの2D。docs/AUTORUN.md 作業23）。ハブが GameState.celebrate を受けて画面の上に重ねる。
##
## 球団カラーの帽子とユニフォームの選手（丸と角丸の簡単な形）が輪になり、真ん中の監督を胴上げする。紙吹雪と大きな見出し。
## Ⓐ/Ⓑ/クリックか AUTO_CLOSE 秒で閉じる（閉じるまでほかの入力は受けない）。実在の監督の顔・名前は出さない

signal closed

const AUTO_CLOSE := 7.0
const TOSS_PERIOD := 1.1
const TOSS_HEIGHT := 110.0
const PLAYERS := 9
const CONFETTI := 140

var _team := ""
var _title := ""
var _colors: Array[Color] = []
var _time := 0.0
var _stage: Control
var _confetti: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


## kind: "pennant"（リーグ優勝）/ "champion"（日本一）、title: 見出し（例「セ・リーグ優勝」「日本一」）
func setup(team_name: String, title: String) -> void:
	_team = team_name
	_title = title
	_colors = GameData.team_colors(team_name)
	layer = 50
	_rng.seed = hash(team_name + title)
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.draw.connect(_draw_stage)
	_stage.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(_stage)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-400, 24)
	box.custom_minimum_size = Vector2(800, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(box)
	var team_label := Label.new()
	team_label.text = team_name
	team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(team_label, 40, Color.WHITE, _colors[0].darkened(0.4), 10)
	box.add_child(team_label)
	var title_label := Label.new()
	title_label.text = title + "！"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.heading(title_label, 84, Color("ffd400"), Color("7a3d00"), 16)
	box.add_child(title_label)
	var hint_panel := PanelContainer.new()
	hint_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var h_style := UiTheme.box(Color(0, 0, 0, 0.45), 8)
	h_style.content_margin_left = 16
	h_style.content_margin_right = 16
	h_style.content_margin_top = 4
	h_style.content_margin_bottom = 4
	hint_panel.add_theme_stylebox_override("panel", h_style)
	var hint := UiTheme.small_label("Ⓐ / Ⓑ で閉じる", 18, Color.WHITE, 800)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_panel.add_child(hint)
	box.add_child(hint_panel)
	for i in CONFETTI:
		_confetti.append(_new_piece(true))
	title_label.pivot_offset = Vector2(400, 50)
	title_label.scale = Vector2(0.3, 0.3)
	create_tween().tween_property(title_label, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _new_piece(anywhere: bool) -> Dictionary:
	var palette: Array[Color] = [_colors[0], _colors[1], Color("ffd400"), Color.WHITE, Color("ff5a5a")]
	return {
		"pos": Vector2(_rng.randf_range(0, 1280), _rng.randf_range(-720, 720) if anywhere else -20.0),
		"vel": Vector2(_rng.randf_range(-30, 30), _rng.randf_range(80, 200)),
		"rot": _rng.randf_range(0, TAU), "spin": _rng.randf_range(-6, 6),
		"size": Vector2(_rng.randf_range(6, 12), _rng.randf_range(10, 18)),
		"color": palette[_rng.randi_range(0, palette.size() - 1)],
	}


func _process(delta: float) -> void:
	_time += delta
	for i in _confetti.size():
		var c := _confetti[i]
		c["pos"] += c["vel"] * delta + Vector2(sin(_time * 2.0 + i) * 20.0 * delta, 0)
		c["rot"] += c["spin"] * delta
		if c["pos"].y > 740:
			_confetti[i] = _new_piece(false)
	_stage.queue_redraw()
	if _time >= AUTO_CLOSE:
		close()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		close()
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _draw_stage() -> void:
	var size := _stage.size
	# 背景：球団カラーの夜空と照明
	_stage.draw_rect(Rect2(Vector2.ZERO, size), Color(_colors[0].darkened(0.55), 0.9))
	for i in 4:
		var x := size.x * (0.15 + 0.23 * i)
		var light := PackedVector2Array([Vector2(x - 30, 0), Vector2(x + 30, 0), Vector2(x + 260 - i * 120, size.y),
			Vector2(x - 140 - i * 40, size.y)])
		_stage.draw_colored_polygon(light, Color(1, 1, 0.85, 0.06))
	# 芝生
	_stage.draw_rect(Rect2(0, size.y * 0.82, size.x, size.y * 0.18), Color("2f8f3a"))
	var center := Vector2(size.x / 2.0, size.y * 0.94)
	# 胴上げされる監督（上下に跳ねる。手足を広げる）
	var phase := fmod(_time, TOSS_PERIOD) / TOSS_PERIOD
	var lift := sin(phase * PI) * TOSS_HEIGHT
	_draw_person(center + Vector2(0, -130 - lift), 1.15, phase * 0.6 - 0.3, true)
	# 輪になった選手（手を上げる）
	for i in PLAYERS:
		var a := PI * (0.1 + 0.8 * i / float(PLAYERS - 1))
		var offset := Vector2(cos(a) * 230.0, -sin(a) * 26.0)
		var bob := absf(sin(_time * 5.0 + i)) * 8.0
		_draw_person(center + offset + Vector2(0, -bob), 1.0, 0.0, false)
	for c in _confetti:
		_stage.draw_set_transform(c["pos"], c["rot"], Vector2.ONE)
		_stage.draw_rect(Rect2(-c["size"] / 2.0, c["size"]), c["color"])
	_stage.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 人の形（頭・帽子・ユニフォームの胴・腕・脚）。pos は足もと、tilt は傾き（ラジアン）
func _draw_person(pos: Vector2, zoom: float, tilt: float, tossed: bool) -> void:
	_stage.draw_set_transform(pos, tilt, Vector2(zoom, zoom))
	var uniform := Color.WHITE
	var trim := _colors[0]
	var cap := _colors[1] if _colors[1].get_luminance() < 0.8 else _colors[0]
	var skin := Color("f2c79b")
	var arm := 4.0
	# 脚
	var spread := 16.0 if tossed else 8.0
	_stage.draw_line(Vector2(-6, -40), Vector2(-spread, 0), trim, 7.0)
	_stage.draw_line(Vector2(6, -40), Vector2(spread, 0), trim, 7.0)
	# 胴
	_stage.draw_rect(Rect2(-16, -86, 32, 50), uniform)
	_stage.draw_rect(Rect2(-16, -86, 32, 50), trim, false, 3.0)
	_stage.draw_line(Vector2(0, -86), Vector2(0, -36), trim, 2.0)
	# 腕（上げる）
	var reach := Vector2(30, -128) if not tossed else Vector2(40, -100)
	_stage.draw_line(Vector2(-14, -80), Vector2(-reach.x, reach.y), uniform, arm * 2.0)
	_stage.draw_line(Vector2(14, -80), Vector2(reach.x, reach.y), uniform, arm * 2.0)
	_stage.draw_circle(Vector2(-reach.x, reach.y), 5.0, skin)
	_stage.draw_circle(Vector2(reach.x, reach.y), 5.0, skin)
	# 頭と帽子
	_stage.draw_circle(Vector2(0, -102), 15.0, skin)
	_stage.draw_rect(Rect2(-16, -122, 32, 12), cap)
	_stage.draw_rect(Rect2(-4 if tossed else 0, -112, 22, 4), cap)
	_stage.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
