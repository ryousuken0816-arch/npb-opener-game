class_name Lottery3D
extends Control
## ドラフト1位の抽選の3D演出（docs/AUTORUN.md 作業20）。godot/scenes/draft/lottery_3d.tscn のルート。
##
## 競合した球団の監督（デフォルメの3Dキャラ。球団カラーの帽子とユニフォーム、顔は点の目だけ）が
## 抽選箱から順に封筒を引く → 全員で同時に開ける → 当たりの球団が「交渉権確定」を掲げて喜び、外れはうなだれる。
## 当たりは Draft の抽選の結果（lot["winner"]）をそのまま見せるだけで、乱数は使わない（演出が結果を変えない）。
## モデルは箱・カプセル・球の組み合わせで、外部の素材は使わない。実在の監督の顔・名前は出さず、球団名とカラーだけ。
## 軽さのため影は付けず、光は平行光1つと環境光だけ。SubViewport は自分専用の World3D で描く。
##
## 使い方：add_child したあと play(lot, info)。skip() で結果の場面へ飛ぶ（Ⓐ／Ⓑは呼び出し側がつなぐ）。
## クリックすると clicked（呼び出し側が飛ばす・次へ進む）。結果の場面になると revealed(winner)。

signal revealed(winner: String)
signal clicked

## 1球団がくじを引く時間（秒）：箱まで歩く・手を入れる・引き抜く（戻りも歩く時間）
const WALK_SEC := 0.32
const REACH_SEC := 0.22
const PULL_SEC := 0.2
## 全員が引いたあと、封筒を胸の前に構える → 間 → 開ける
const HOLD_SEC := 0.4
const OPEN_WAIT_SEC := 0.3
## 結果の場面：当たりの監督が机の前へ出る時間と、カメラが寄る時間
const STEP_OUT_SEC := 0.45
const ZOOM_SEC := 0.75
const VIEW_SIZE := Vector2i(840, 372)
## 監督の並び（奥の列の z と横幅）、くじを引く位置（箱の後ろ）
const ROW_Z := -1.5
const ROW_WIDTH := 5.6
const MAX_SPACING := 1.2
const DRAW_Z := -0.78
## 当たりの監督が紙を掲げる位置（机の前）
const FRONT_SPOT := Vector3(0.0, 0.0, 0.8)
## 監督の大きさ（下の寸法は scale 1 のとき）
const CHAR_SCALE := 1.3
const SHOULDER_Y := 0.68
const TABLE_TOP := 0.45
const BOX_Z := -0.3
const SKIN := Color("f2c9a0")
const PANTS := Color("f4f4f4")
const ENVELOPE := Color("f3e3c3")
const GOLD := Color("e8c25a")
const CARD_TEXT := "交渉権確定"
const CARD_SIZE := Vector2(0.78, 0.32)
## カメラ：全体（最初）と、当たりの球団に寄ったとき（当たりの監督の位置からの差）
const CAM_HOME := Vector3(0.0, 1.95, 3.4)
const CAM_HOME_TARGET := Vector3(0.0, 0.92, -1.0)
const CAM_NEAR_OFFSET := Vector3(0.0, 0.6, 2.35)
const CAM_NEAR_TARGET_OFFSET := Vector3(0.25, 1.3, 0.0)

## idle / draw / open / result
var phase := "idle"
## くじを引き終えた球団の数
var drawn := 0
var winner := ""
var teams: Array[String] = []
## 再生の速さ（他球団どうしの抽選は少し速く）
var speed := 1.0

var _built := false
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _cam_near := Vector3.ZERO
var _cam_near_target := Vector3.ZERO
## 監督ごとの部品 {root, body, head, arm_r, arm_l, hand, tag, home, team}
var _parts: Array[Dictionary] = []
## 球団 → 手に持っている封筒・紙（毎フレーム手の位置に合わせる）
var _held := {}
var _tween: Tween
var _cheer: Tween
var _materials := {}
var _confetti: CPUParticles3D
var _user_team := ""


func _ready() -> void:
	_build()


func _process(_delta: float) -> void:
	for t: String in _held:
		var item: Node3D = _held[t]
		var p := _part_of(t)
		if p.is_empty() or not is_instance_valid(item):
			continue
		var hand: Node3D = p["hand"]
		var offset: Vector3 = item.get_meta("offset", Vector3.ZERO)
		item.global_position = hand.global_position + offset
		item.global_basis = Basis()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		clicked.emit()


## 抽選の演出を始める。lot = Draft の抽選の記録 {id, teams, winner}、
## info = {user_team（名札に★）, speed}
func play(lot: Dictionary, info: Dictionary = {}) -> void:
	_build()
	teams.assign(lot.get("teams", []))
	winner = str(lot.get("winner", ""))
	_user_team = str(info.get("user_team", ""))
	speed = float(info.get("speed", 1.0))
	_make_stage()
	for i in teams.size():
		_parts.append(_make_manager(teams[i], _home_position(i)))
	_set_camera(0.0)
	_run_sequence()


## 結果の場面へ飛ぶ（もう結果なら何もしない）
func skip() -> void:
	if phase == "result" or phase == "idle":
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	for p: Dictionary in _parts:
		var root: Node3D = p["root"]
		root.position = p["home"]
		var body: Node3D = p["body"]
		body.position.y = 0.0
		body.rotation.x = 0.0
		_set_tag_active(p, false)
		if not _held.has(p["team"]):
			_give(p["team"], _make_envelope())
	drawn = teams.size()
	_open_cards()
	_show_result(true)


func is_revealed() -> bool:
	return phase == "result"


## 3Dで当たりの紙（交渉権確定）を持っている球団（テスト用。結果の場面でないときは空）
func shown_winner() -> String:
	for t: String in _held:
		var item: Node3D = _held[t]
		if is_instance_valid(item) and item.get_meta("winning", false):
			return t
	return ""


# --- 進行 ----------------------------------------------------------------------------------

func _run_sequence() -> void:
	phase = "draw"
	drawn = 0
	_tween = create_tween()
	_tween.set_speed_scale(speed)
	_tween.tween_interval(0.25)
	for i in _parts.size():
		var p := _parts[i]
		var root: Node3D = p["root"]
		var body: Node3D = p["body"]
		var arm: Node3D = p["arm_r"]
		var spot := Vector3(0.0, 0.0, DRAW_Z)
		_tween.tween_callback(_set_tag_active.bind(p, true))
		_tween.tween_property(root, "position", spot, WALK_SEC).set_trans(Tween.TRANS_SINE)
		_tween.parallel().tween_method(_hop.bind(body), 0.0, 1.0, WALK_SEC)
		_tween.tween_property(arm, "rotation:x", -1.35, REACH_SEC).set_trans(Tween.TRANS_SINE)
		_tween.parallel().tween_property(body, "rotation:x", 0.28, REACH_SEC)
		_tween.tween_callback(func() -> void: _give(p["team"], _make_envelope()))
		_tween.tween_property(arm, "rotation:x", -0.55, PULL_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.parallel().tween_property(body, "rotation:x", 0.0, PULL_SEC)
		_tween.tween_property(root, "position", p["home"], WALK_SEC).set_trans(Tween.TRANS_SINE)
		_tween.parallel().tween_method(_hop.bind(body), 0.0, 1.0, WALK_SEC)
		_tween.tween_callback(func() -> void:
			_set_tag_active(p, false)
			drawn += 1)
	# 全員で封筒を胸の前に構えて、同時に開ける
	_tween.tween_callback(func() -> void: phase = "open")
	for p: Dictionary in _parts:
		var arm: Node3D = p["arm_r"]
		var arm_l: Node3D = p["arm_l"]
		_tween.parallel().tween_property(arm, "rotation:x", -1.45, HOLD_SEC).set_trans(Tween.TRANS_SINE)
		_tween.parallel().tween_property(arm_l, "rotation:x", -1.2, HOLD_SEC).set_trans(Tween.TRANS_SINE)
	_tween.tween_interval(OPEN_WAIT_SEC)
	_tween.tween_callback(_open_cards)
	_tween.tween_interval(0.35)
	_tween.tween_callback(_show_result.bind(false))


## 封筒を紙に変える：当たりは「交渉権確定」、外れは白紙
func _open_cards() -> void:
	phase = "open"
	for p: Dictionary in _parts:
		var t: String = p["team"]
		var arm: Node3D = p["arm_r"]
		arm.rotation.x = -1.45
		_give(t, _make_card(t == winner))


## 結果の場面：当たりは机の前へ出て両手を上げ、紙を掲げて跳ねる・紙吹雪。外れはうなだれる。カメラが当たりへ寄る
func _show_result(instant: bool) -> void:
	phase = "result"
	var tw: Tween = null if instant else create_tween().set_parallel(true)
	var wp := _part_of(winner)
	if not wp.is_empty():
		var wroot: Node3D = wp["root"]
		if tw == null:
			wroot.position = FRONT_SPOT
		else:
			tw.tween_property(wroot, "position", FRONT_SPOT, STEP_OUT_SEC).set_trans(Tween.TRANS_SINE)
			tw.tween_method(_hop.bind(wp["body"]), 0.0, 1.5, STEP_OUT_SEC)
	for p: Dictionary in _parts:
		var won: bool = p["team"] == winner
		var arm_r: Node3D = p["arm_r"]
		var arm_l: Node3D = p["arm_l"]
		var head: Node3D = p["head"]
		var body: Node3D = p["body"]
		var pose := {
			arm_r: Vector3(0.0, 0.0, 2.45) if won else Vector3(-0.85, 0.0, 0.0),
			arm_l: Vector3(0.0, 0.0, -2.45) if won else Vector3(0.0, 0.0, 0.0),
			head: Vector3(-0.15, 0.0, 0.0) if won else Vector3(0.5, 0.0, 0.0),
			body: Vector3(0.0, 0.0, 0.0) if won else Vector3(0.14, 0.0, 0.0),
		}
		for node: Node3D in pose:
			if tw == null:
				node.rotation = pose[node]
			else:
				tw.tween_property(node, "rotation", pose[node], 0.3).set_trans(Tween.TRANS_BACK) 					.set_ease(Tween.EASE_OUT).set_delay(STEP_OUT_SEC if won else 0.0)
		var item: Node3D = _held.get(p["team"])
		if item != null:
			item.set_meta("offset", Vector3(0.22, 0.22, 0.12) if won else Vector3(0.0, 0.02, 0.1))
		# 当たりの名札は金色で大きく、外れは薄く小さく（寄ったときに重ならないように）
		var tag: Label3D = p["tag"]
		tag.modulate = GOLD if won else Color(1.0, 1.0, 1.0, 0.45)
		tag.scale = Vector3.ONE * (1.35 if won else 0.8)
	if not wp.is_empty():
		_cam_near = FRONT_SPOT + CAM_NEAR_OFFSET
		_cam_near_target = FRONT_SPOT + CAM_NEAR_TARGET_OFFSET
		if tw == null:
			_set_camera(1.0)
			_start_cheer()
		else:
			tw.tween_method(_set_camera, 0.0, 1.0, ZOOM_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_callback(_start_cheer).set_delay(STEP_OUT_SEC + 0.1)
	revealed.emit(winner)


## 当たりの監督が跳ね続ける・紙吹雪
func _start_cheer() -> void:
	var wp := _part_of(winner)
	if wp.is_empty() or (_cheer != null and _cheer.is_valid()):
		return
	_confetti.position = FRONT_SPOT + Vector3(0.0, 2.3, 0.0)
	_tint_confetti()
	_confetti.restart()
	_confetti.emitting = true
	var body: Node3D = wp["body"]
	_cheer = create_tween().set_loops()
	_cheer.tween_property(body, "position:y", 0.22, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_cheer.tween_property(body, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_cheer.tween_interval(0.15)


func _set_camera(t: float) -> void:
	var near := _cam_near if t > 0.0 else CAM_HOME
	var near_target := _cam_near_target if t > 0.0 else CAM_HOME_TARGET
	_camera.position = CAM_HOME.lerp(near, t)
	_camera.look_at(CAM_HOME_TARGET.lerp(near_target, t))


func _hop(t: float, body: Node3D) -> void:
	body.position.y = absf(sin(t * PI * 2.0)) * 0.07


func _set_tag_active(p: Dictionary, active: bool) -> void:
	var tag: Label3D = p["tag"]
	tag.scale = Vector3.ONE * (1.25 if active else 1.0)


func _give(team: String, item: Node3D) -> void:
	var old: Node3D = _held.get(team)
	if old != null and is_instance_valid(old):
		old.queue_free()
	_world.add_child(item)
	_held[team] = item
	var p := _part_of(team)
	if not p.is_empty():
		var hand: Node3D = p["hand"]
		item.global_position = hand.global_position + item.get_meta("offset", Vector3.ZERO)


func _part_of(team: String) -> Dictionary:
	for p: Dictionary in _parts:
		if p["team"] == team:
			return p
	return {}


func _home_position(i: int) -> Vector3:
	var n := teams.size()
	var spacing := minf(MAX_SPACING, ROW_WIDTH / maxf(1.0, float(n - 1)))
	var x := (float(i) - float(n - 1) * 0.5) * spacing
	# 両端を少し手前に（扇形）。真ん中は箱の真後ろになるので少し奥
	var edge := absf(x) / maxf(0.01, ROW_WIDTH * 0.5)
	return Vector3(x, 0.0, ROW_Z + 0.35 * edge * edge)


# --- 作る ----------------------------------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	custom_minimum_size = Vector2(VIEW_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.size = VIEW_SIZE
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.positional_shadow_atlas_size = 0
	container.add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("13264a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_world.add_child(world_env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 28.0, 0.0)
	light.light_energy = 1.05
	light.shadow_enabled = false
	_world.add_child(light)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.current = true
	_world.add_child(_camera)
	_camera.position = CAM_HOME
	_camera.look_at(CAM_HOME_TARGET)
	_confetti = _make_confetti()
	_world.add_child(_confetti)


## 会場：床・後ろの壁（金の線と「交渉権 抽選」）・机・抽選箱
func _make_stage() -> void:
	_add_mesh(_world, _box_mesh(Vector3(16.0, 0.1, 9.0)), Color("8c1d24"), Vector3(0.0, -0.05, -0.5))
	_add_mesh(_world, _box_mesh(Vector3(16.0, 6.0, 0.2)), Color("1d3a6e"), Vector3(0.0, 3.0, -3.3))
	for y: float in [0.55, 3.55]:
		_add_mesh(_world, _box_mesh(Vector3(16.0, 0.08, 0.05)), GOLD, Vector3(0.0, y, -3.18))
	var head := _label3d("交渉権 抽選", 80, 0.005, GOLD, Color("0d1e3d"))
	head.position = Vector3(0.0, 2.3, -3.15)
	_world.add_child(head)
	# 机（白い布）と前の幕
	_add_mesh(_world, _box_mesh(Vector3(2.4, 0.06, 0.75)), Color("fafafa"), Vector3(0.0, TABLE_TOP - 0.03, -0.2))
	_add_mesh(_world, _box_mesh(Vector3(2.4, TABLE_TOP - 0.06, 0.04)), Color("b3261e"),
		Vector3(0.0, (TABLE_TOP - 0.06) * 0.5, 0.16))
	_add_mesh(_world, _box_mesh(Vector3(2.4, 0.05, 0.05)), GOLD, Vector3(0.0, TABLE_TOP - 0.08, 0.18))
	# 抽選箱：白い箱・上に丸い穴・正面に「抽選」
	var box := Node3D.new()
	box.position = Vector3(0.0, TABLE_TOP, BOX_Z)
	_world.add_child(box)
	_add_mesh(box, _box_mesh(Vector3(0.58, 0.4, 0.5)), Color("f7f2e8"), Vector3(0.0, 0.2, 0.0))
	_add_mesh(box, _box_mesh(Vector3(0.6, 0.05, 0.52)), Color("b3261e"), Vector3(0.0, 0.4, 0.0))
	var hole := CylinderMesh.new()
	hole.top_radius = 0.13
	hole.bottom_radius = 0.13
	hole.height = 0.012
	hole.radial_segments = 20
	_add_mesh(box, hole, Color("1a1a1a"), Vector3(0.0, 0.43, 0.0))
	var mark := _label3d("抽選", 64, 0.0042, Color("b3261e"), Color.WHITE)
	mark.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	mark.position = Vector3(0.0, 0.2, 0.26)
	box.add_child(mark)


## デフォルメの監督：大きな頭・点の目・球団カラーの帽子（つばはサブカラー）とユニフォーム（ベルトはサブカラー）
func _make_manager(team: String, home: Vector3) -> Dictionary:
	var colors := GameData.team_colors(team)
	var main: Color = colors[0]
	var sub: Color = colors[1]
	var root := Node3D.new()
	root.position = home
	root.scale = Vector3.ONE * CHAR_SCALE
	_world.add_child(root)
	var body := Node3D.new()
	root.add_child(body)
	for x: float in [-0.08, 0.08]:
		_add_mesh(body, _capsule(0.075, 0.34), PANTS, Vector3(x, 0.17, 0.0))
		_add_mesh(body, _box_mesh(Vector3(0.1, 0.05, 0.15)), Color("222222"), Vector3(x, 0.025, 0.03))
	_add_mesh(body, _capsule(0.18, 0.52), main, Vector3(0.0, 0.5, 0.0))
	var belt := CylinderMesh.new()
	belt.top_radius = 0.183
	belt.bottom_radius = 0.183
	belt.height = 0.045
	belt.radial_segments = 16
	_add_mesh(body, belt, sub, Vector3(0.0, 0.34, 0.0))
	# 胸のライン（サブカラー）
	_add_mesh(body, _box_mesh(Vector3(0.03, 0.26, 0.02)), sub, Vector3(0.0, 0.52, 0.175))
	var head := Node3D.new()
	head.position = Vector3(0.0, 0.76, 0.0)
	body.add_child(head)
	_add_mesh(head, _sphere(0.21, 0.42), SKIN, Vector3(0.0, 0.2, 0.0))
	for x: float in [-0.075, 0.075]:
		_add_mesh(head, _sphere(0.028, 0.056), Color("1a1a1a"), Vector3(x, 0.21, 0.19))
	var cap := SphereMesh.new()
	cap.radius = 0.218
	cap.height = 0.218
	cap.is_hemisphere = true
	cap.radial_segments = 16
	cap.rings = 6
	_add_mesh(head, cap, main, Vector3(0.0, 0.25, 0.0))
	var brim := CylinderMesh.new()
	brim.top_radius = 0.15
	brim.bottom_radius = 0.15
	brim.height = 0.025
	brim.radial_segments = 16
	var brim_mesh := _add_mesh(head, brim, sub, Vector3(0.0, 0.26, 0.17))
	brim_mesh.scale = Vector3(1.0, 1.0, 0.75)
	_add_mesh(head, _sphere(0.03, 0.06), sub, Vector3(0.0, 0.47, 0.0))
	var arms := {}
	for side: float in [1.0, -1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.21 * side, SHOULDER_Y, 0.0)
		body.add_child(arm)
		_add_mesh(arm, _capsule(0.058, 0.34), main, Vector3(0.0, -0.15, 0.0))
		_add_mesh(arm, _sphere(0.065, 0.13), SKIN, Vector3(0.0, -0.33, 0.0))
		var hand := Node3D.new()
		hand.position = Vector3(0.0, -0.36, 0.0)
		arm.add_child(hand)
		arms[side] = [arm, hand]
	var mine := team == _user_team
	var tag := _label3d(("★" if mine else "") + GameData.short_name(team), 44, 0.0034, Color.WHITE,
		main.darkened(0.35) if main.get_luminance() > 0.25 else main.lightened(0.15))
	tag.outline_size = 14
	tag.position = Vector3(0.0, 1.38, 0.0)
	root.add_child(tag)
	return {"root": root, "body": body, "head": head, "arm_r": arms[1.0][0], "arm_l": arms[-1.0][0],
		"hand": arms[1.0][1], "tag": tag, "home": home, "team": team}


func _make_envelope() -> Node3D:
	var item := Node3D.new()
	item.set_meta("offset", Vector3(0.0, 0.0, 0.06))
	_add_mesh(item, _box_mesh(Vector3(0.24, 0.15, 0.015)), ENVELOPE, Vector3.ZERO)
	_add_mesh(item, _sphere(0.025, 0.05), Color("b3261e"), Vector3(0.0, 0.0, 0.01))
	return item


## 開けた紙。当たりは赤い字で「交渉権確定」、外れは白紙
func _make_card(winning: bool) -> Node3D:
	var item := Node3D.new()
	item.set_meta("offset", Vector3(0.0, 0.02, 0.1))
	item.set_meta("winning", winning)
	_add_mesh(item, _box_mesh(Vector3(CARD_SIZE.x, CARD_SIZE.y, 0.012)), Color.WHITE, Vector3.ZERO)
	if winning:
		var text := _label3d(CARD_TEXT, 64, 0.0021, Color("d0101a"), Color.WHITE)
		text.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		text.outline_size = 4
		text.position = Vector3(0.0, 0.0, 0.008)
		item.add_child(text)
		for y: float in [CARD_SIZE.y * 0.5 - 0.02, -CARD_SIZE.y * 0.5 + 0.02]:
			_add_mesh(item, _box_mesh(Vector3(CARD_SIZE.x, 0.022, 0.014)), Color("d0101a"), Vector3(0.0, y, 0.0))
	return item


func _make_confetti() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 70
	p.lifetime = 2.2
	p.explosiveness = 0.85
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.4
	p.gravity = Vector3(0.0, -3.2, 0.0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.045)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	p.mesh = quad
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	ramp.colors = PackedColorArray([GOLD, Color.WHITE, Color("e53935"), Color("1e88e5")])
	p.color_initial_ramp = ramp
	return p


## 結果の場面の紙吹雪を当たりの球団の色にする
func _tint_confetti() -> void:
	var colors := GameData.team_colors(winner)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	ramp.colors = PackedColorArray([colors[0], GOLD, Color.WHITE, colors[1]])
	_confetti.color_initial_ramp = ramp


func _label3d(text: String, font_size: int, pixel: float, color: Color, outline: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UiTheme.font(800)
	l.font_size = font_size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_modulate = outline
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.double_sided = false
	return l


func _add_mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.75
		_materials[key] = m
	return _materials[key]


func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 4
	return m


func _sphere(radius: float, height: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 16
	m.rings = 8
	return m
