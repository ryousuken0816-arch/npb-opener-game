class_name Lottery3D
extends Control
## ドラフト1位の抽選の3D演出（docs/AUTORUN.md 作業20・29）。godot/scenes/draft/lottery_3d.tscn のルート。
##
## 会場：ホテルの宴会場（模様の絨毯・中央に赤いじゅうたんの通路・段のある白い台と白い抽選箱・白いクロスの丸テーブルに
## 各球団の関係者・奥の壁に「DRAFT <年>」の看板）。競合した球団の代表者（スーツ・球団カラーのネクタイ・首から下げた名札）が
## 順に箱からくじを引く → 台の前に並んで同時に封筒を開ける → 当たりはこぶしを上げて紙を掲げ、外れは肩を落とす →
## 会場の関係者が立って拍手 → 当選球団の字幕。カメラは中継のように切り替える（全景・手元の寄り・横から・当選の瞬間）。
## 当たりは Draft の抽選の結果（lot["winner"]）をそのまま見せるだけで、抽選の乱数は使わない（演出が結果を変えない）。
## 人物の体格・髪型などの個体差は球団名から決める（同じ球団はいつも同じ見た目）。
## モデルは箱・カプセル・球・円柱の組み合わせで、外部の素材は使わない。実在の人物の顔・名前、ロゴ・スポンサーは出さない。
## 軽さのため、影を落とすのは平行光1つだけで、影を落とす物は代表者と台・机に絞る。遠くの関係者は簡略な形。
## 効果音（ざわめき・拍手）は最初に一度だけ波形を作って使い回す。
##
## 使い方：add_child したあと play(lot, info)。skip() で結果の場面へ飛ぶ（Ⓐ／Ⓑは呼び出し側がつなぐ）。
## クリックすると clicked（呼び出し側が飛ばす・次へ進む）。当選の瞬間になると revealed(winner)。

signal revealed(winner: String)
signal clicked

const VIEW_SIZE := Vector2i(840, 372)
## 流れの時間（秒）：全景・1人がくじを引く（歩く・手を入れる・引き抜く）・次の人が歩き出すまで・並ぶ・緊張の間・
## 当選の瞬間・拍手
const WIDE_SEC := 1.4
const WALK_SEC := 0.45
const REACH_SEC := 0.25
const PULL_SEC := 0.25
const DRAW_INTERVAL := 0.95
const LINE_SEC := 0.8
const TENSION_SEC := 1.2
const WINNER_SEC := 1.3
const APPLAUSE_SEC := 1.8
## 会場の配置：段の台（下の段・上の段）・抽選箱・代表者が並ぶ列・くじを引く位置・丸テーブル
const STAGE_Z := -4.6
const TIER1_TOP := 0.2
const TIER2_TOP := 0.4
const BOX_Z := -4.95
const ROW_Z := -2.75
const ROW_SPACING := 0.8
const DRAW_SPOT := Vector3(0.0, TIER2_TOP, -4.45)
const TABLE_XS := [-4.4, -2.5, 2.5, 4.4]
const TABLE_ZS := [-1.1, 0.9, 2.9]
const TABLE_RADIUS := 0.72
const WALL_Z := -6.6
const SKIN := Color("f0c8a0")
const SHIRT := Color("f6f7f9")
const SUITS := [Color("1f2a44"), Color("2f3238"), Color("4d535c"), Color("26324f")]
const HAIRS := [Color("1b1714"), Color("2b211b"), Color("6e6a66"), Color("b9b6b2")]
const ENVELOPE := Color("e2c48a")
const GOLD := Color("d9b24c")
const CLOTH := Color("fbfbfb")
const CARD_TEXT := "交渉権確定"
const CARD_SIZE := Vector2(0.34, 0.16)
## 効果音の大きさ（dB）
const MURMUR_DB := -20.0
const APPLAUSE_DB := -9.0
const SAMPLE_RATE := 22050

## idle / draw / open / result
var phase := "idle"
## くじを引き終えた球団の数
var drawn := 0
var winner := ""
var teams: Array[String] = []
## 再生の速さ（他球団どうしの抽選は少し速く）
var speed := 1.0
## いまのカメラ（wide / draw / draw2 / line / hands / winner / applause）と、これまでに使ったカメラ（テスト用）
var camera_shot := ""
var shots_seen: Array[String] = []

static var _sfx := {}
static var _carpet_tex: ImageTexture

var _built := false
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _cam_tween: Tween
## 代表者ごとの部品 {root, body, chest, head, sh_r, sh_l, el_r, el_l, hand_r, hand_l, home, team}
var _parts: Array[Dictionary] = []
## 関係者（着席）の部品 {root, body, head, arm_r, arm_l, legs, phase}
var _staff: Array[Dictionary] = []
## 球団 → 手に持っている封筒・紙（毎フレーム手の位置に合わせる）
var _held := {}
var _tween: Tween
var _rep_tweens: Array[Tween] = []
var _cheer: Tween
var _materials := {}
var _confetti: CPUParticles3D
var _user_team := ""
var _year := 0
var _all_teams: Array[String] = []
var _time := 0.0
var _tension := false
var _applause := false
var _murmur: AudioStreamPlayer
var _clap: AudioStreamPlayer
var _caption: PanelContainer
var _caption_label: Label


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	_time += delta
	for t: String in _held:
		var item: Node3D = _held[t]
		var p := _part_of(t)
		if p.is_empty() or not is_instance_valid(item):
			continue
		var hand: Node3D = p[item.get_meta("hand", "hand_r")]
		var offset: Vector3 = item.get_meta("offset", Vector3.ZERO)
		item.global_position = hand.global_position + offset
		item.global_basis = Basis()
	_animate_staff(delta)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		clicked.emit()


## 抽選の演出を始める。lot = Draft の抽選の記録 {id, teams, winner}、
## info = {user_team（名札に★）, speed, year（看板）, all_teams（丸テーブルの12球団。無ければ競合した球団）}
func play(lot: Dictionary, info: Dictionary = {}) -> void:
	_build()
	teams.assign(lot.get("teams", []))
	winner = str(lot.get("winner", ""))
	_user_team = str(info.get("user_team", ""))
	speed = float(info.get("speed", 1.0))
	_year = int(info.get("year", 0))
	_all_teams.assign(info.get("all_teams", []))
	if _all_teams.is_empty():
		_all_teams = teams.duplicate()
	_make_venue()
	_make_tables()
	for i in teams.size():
		_parts.append(_make_rep(teams[i], _home_position(i)))
	_cut("wide")
	_run_sequence()


## 結果の場面へ飛ぶ（もう結果なら何もしない）
func skip() -> void:
	if phase == "result" or phase == "idle":
		return
	_kill_tweens()
	for p: Dictionary in _parts:
		var root: Node3D = p["root"]
		root.position = p["home"]
		root.rotation = Vector3.ZERO
		var chest: Node3D = p["chest"]
		chest.rotation = Vector3.ZERO
		if not _held.has(p["team"]):
			_give(p["team"], _make_envelope())
	drawn = teams.size()
	_hold_pose(null)
	_open_cards()
	_show_result(true)
	_start_applause(true)
	_cut("winner")


func is_revealed() -> bool:
	return phase == "result"


## 3Dで当たりの紙（交渉権確定）を持っている球団（テスト用。結果の場面でないときは空）
func shown_winner() -> String:
	for t: String in _held:
		var item: Node3D = _held[t]
		if is_instance_valid(item) and item.get_meta("winning", false):
			return t
	return ""


## 会場の関係者の人数（テスト用）
func staff_count() -> int:
	return _staff.size()


# --- 流れ ----------------------------------------------------------------------------------

func _run_sequence() -> void:
	phase = "draw"
	drawn = 0
	_play_sfx(_murmur, "murmur", MURMUR_DB)
	_tween = create_tween()
	_tween.set_speed_scale(speed)
	_tween.tween_interval(WIDE_SEC)
	for i in _parts.size():
		_tween.tween_callback(_cut.bind("draw" if i % 2 == 0 else "draw2"))
		_tween.tween_callback(_draw_rep.bind(i))
		_tween.tween_interval(DRAW_INTERVAL if i < _parts.size() - 1 else DRAW_INTERVAL + WALK_SEC + 0.1)
	# 台の前に並んで、封筒を両手で胸の前に構える
	_tween.tween_callback(func() -> void:
		phase = "open"
		_cut("line")
		var tw := _new_rep_tween()
		_hold_pose(tw))
	_tween.tween_interval(LINE_SEC)
	# 手元の寄り：緊張の間（会場は静かになり、関係者は身を乗り出す）
	_tween.tween_callback(func() -> void:
		_cut("hands")
		_tension = true
		_fade_sfx(_murmur, -34.0, TENSION_SEC))
	_tween.tween_interval(TENSION_SEC)
	_tween.tween_callback(_open_cards)
	_tween.tween_callback(_show_result.bind(false))
	_tween.tween_interval(WINNER_SEC)
	_tween.tween_callback(_start_applause.bind(false))
	_tween.tween_interval(APPLAUSE_SEC)
	_tween.tween_callback(_cut.bind("winner"))


## 1人がくじを引く：台へ歩いて箱の方を向く → 手を入れる → 封筒を引き抜く → 列へ戻る
func _draw_rep(i: int) -> void:
	var p := _parts[i]
	var root: Node3D = p["root"]
	var chest: Node3D = p["chest"]
	var sh: Node3D = p["sh_r"]
	var el: Node3D = p["el_r"]
	var tw := _new_rep_tween()
	tw.tween_property(root, "rotation:y", PI, 0.15)
	tw.tween_property(root, "position", DRAW_SPOT, WALK_SEC).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_method(_walk.bind(p), 0.0, 1.0, WALK_SEC)
	tw.tween_property(sh, "rotation:x", -1.25, REACH_SEC).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(el, "rotation:x", -0.35, REACH_SEC)
	tw.parallel().tween_property(chest, "rotation:x", 0.22, REACH_SEC)
	tw.tween_callback(func() -> void: _give(p["team"], _make_envelope()))
	tw.tween_property(sh, "rotation:x", -0.45, PULL_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(el, "rotation:x", -1.1, PULL_SEC)
	tw.parallel().tween_property(chest, "rotation:x", 0.0, PULL_SEC)
	tw.tween_property(root, "rotation:y", 0.0, 0.15)
	tw.tween_property(root, "position", p["home"], WALK_SEC).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_method(_walk.bind(p), 0.0, 1.0, WALK_SEC)
	tw.tween_callback(func() -> void: drawn += 1)


func _new_rep_tween() -> Tween:
	var tw := create_tween()
	tw.set_speed_scale(speed)
	_rep_tweens.append(tw)
	return tw


func _kill_tweens() -> void:
	for tw: Tween in [_tween, _cam_tween] + _rep_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_rep_tweens.clear()


## 封筒を両手で胸の前に構える（tw が null ならすぐ）
func _hold_pose(tw: Tween) -> void:
	for p: Dictionary in _parts:
		# 両手を胸の前で寄せる（右肩は z を負、左肩は正で内側へ）
		var pose := {p["sh_r"]: Vector3(-0.55, 0.0, -0.32), p["el_r"]: Vector3(-1.0, 0.0, 0.0),
			p["sh_l"]: Vector3(-0.55, 0.0, 0.32), p["el_l"]: Vector3(-1.0, 0.0, 0.0)}
		_apply_pose(pose, tw, 0.35)
		var item: Node3D = _held.get(p["team"])
		if item != null:
			item.set_meta("offset", Vector3(-0.06, 0.03, 0.05))


func _apply_pose(pose: Dictionary, tw: Tween, sec: float, delay := 0.0) -> void:
	for node: Node3D in pose:
		if tw == null:
			node.rotation = pose[node]
		else:
			tw.parallel().tween_property(node, "rotation", pose[node], sec).set_trans(Tween.TRANS_BACK) \
				.set_ease(Tween.EASE_OUT).set_delay(delay)


## 封筒を紙に変える：当たりは「交渉権確定」、外れは白紙
func _open_cards() -> void:
	phase = "open"
	for p: Dictionary in _parts:
		var t: String = p["team"]
		_give(t, _make_card(t == winner))
		var item: Node3D = _held[t]
		item.set_meta("offset", Vector3(-0.06, 0.05, 0.05))


## 当選の瞬間：当たりは右のこぶしを上げ、左手で紙を掲げる。外れは肩を落とす。カメラは当たりの代表者へ
func _show_result(instant: bool) -> void:
	phase = "result"
	_tension = false
	var tw: Tween = null if instant else _new_rep_tween()
	for p: Dictionary in _parts:
		var won: bool = p["team"] == winner
		var pose := {}
		if won:
			pose = {p["sh_r"]: Vector3(0.0, 0.0, 2.3), p["el_r"]: Vector3(0.0, 0.0, 1.1),
				p["sh_l"]: Vector3(-1.45, 0.0, -0.1), p["el_l"]: Vector3(-0.75, 0.0, 0.0),
				p["head"]: Vector3(-0.12, 0.0, 0.0), p["chest"]: Vector3(-0.08, 0.0, 0.0)}
		else:
			pose = {p["sh_r"]: Vector3(-0.25, 0.0, 0.05), p["el_r"]: Vector3(-0.5, 0.0, 0.0),
				p["sh_l"]: Vector3(0.0, 0.0, -0.05), p["el_l"]: Vector3(-0.2, 0.0, 0.0),
				p["head"]: Vector3(0.5, 0.0, 0.0), p["chest"]: Vector3(0.16, 0.0, 0.0)}
		_apply_pose(pose, tw, 0.3)
		# 肩を落とす（外れ）
		for key: String in ["sh_r", "sh_l"]:
			var sh: Node3D = p[key]
			var y: float = sh.get_meta("y0", sh.position.y)
			sh.set_meta("y0", y)
			sh.position.y = y if won else y - 0.035
		var item: Node3D = _held.get(p["team"])
		if item != null:
			item.set_meta("hand", "hand_l" if won else "hand_r")
			item.set_meta("offset", Vector3(0.0, 0.11, 0.06) if won else Vector3(0.0, -0.02, 0.05))
	if not instant:
		_cut("winner")
		_fade_sfx(_murmur, -60.0, 0.4)
		var wp := _part_of(winner)
		if not wp.is_empty():
			var body: Node3D = wp["body"]
			_cheer = create_tween().set_loops(3)
			_cheer.tween_property(body, "position:y", 0.12, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_cheer.tween_property(body, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	revealed.emit(winner)


## 会場の拍手：関係者が立って拍手・紙吹雪・当選球団の字幕
func _start_applause(instant: bool) -> void:
	_applause = true
	if _murmur != null:
		_murmur.stop()
	if not instant:
		_cut("applause")
		_play_sfx(_clap, "applause", APPLAUSE_DB)
	for s: Dictionary in _staff:
		var root: Node3D = s["root"]
		var legs: Node3D = s["legs"]
		legs.visible = true
		if instant:
			root.position.y = 0.3
		else:
			create_tween().tween_property(root, "position:y", 0.3, 0.35).set_delay(float(s["phase"]) * 0.05)
	var wp := _part_of(winner)
	if not wp.is_empty():
		var root: Node3D = wp["root"]
		_confetti.position = root.position + Vector3(0.0, 2.6, 0.0)
		_tint_confetti()
		_confetti.restart()
		_confetti.emitting = true
	_caption_label.text = "%s　交渉権確定" % GameData.short_name(winner)
	var colors := GameData.team_colors(winner)
	_caption.add_theme_stylebox_override("panel", UiTheme.gloss(colors[0], 8, 3, 0, Color.WHITE))
	_caption_label.add_theme_color_override("font_color", UiTheme.text_on(colors[0]))
	_caption.visible = true
	if not instant:
		_caption.modulate.a = 0.0
		create_tween().tween_property(_caption, "modulate:a", 1.0, 0.25)


func _walk(t: float, p: Dictionary) -> void:
	var body: Node3D = p["body"]
	body.position.y = absf(sin(t * PI * 3.0)) * 0.03
	var sh_l: Node3D = p["sh_l"]
	sh_l.rotation.x = sin(t * PI * 3.0) * 0.35


## 関係者：ふだんはときどき首を動かす、緊張の間は身を乗り出す、拍手の間は立って手をたたく
func _animate_staff(delta: float) -> void:
	var lean_to := 0.28 if _tension else 0.0
	for s: Dictionary in _staff:
		var ph: float = s["phase"]
		var head: Node3D = s["head"]
		var body: Node3D = s["body"]
		head.rotation.y = sin(_time * 0.6 + ph * 2.1) * (0.05 if _tension else 0.35) * maxf(0.0, sin(_time * 0.23 + ph))
		body.rotation.x = lerpf(body.rotation.x, lean_to, minf(1.0, delta * 4.0))
		var arm_r: Node3D = s["arm_r"]
		var arm_l: Node3D = s["arm_l"]
		if _applause:
			var clap := 0.25 + 0.2 * sin(_time * 17.0 + ph * 5.0)
			arm_r.rotation = Vector3(-1.2, -clap, 0.0)
			arm_l.rotation = Vector3(-1.2, clap, 0.0)
		else:
			arm_r.rotation = Vector3(-0.9, -0.35, 0.0)
			arm_l.rotation = Vector3(-0.9, 0.35, 0.0)


# --- カメラ ---------------------------------------------------------------------------------

## カメラを切り替える（中継のカット）。寄りはゆっくり動かす
func _cut(shot: String) -> void:
	camera_shot = shot
	if not shots_seen.has(shot):
		shots_seen.append(shot)
	var pos := Vector3.ZERO
	var target := Vector3.ZERO
	var move := Vector3.ZERO
	var fov := 40.0
	var sec := 1.0
	var follow := false
	match shot:
		"wide":
			pos = Vector3(0.0, 3.6, 8.8)
			target = Vector3(0.0, 1.0, -3.2)
			move = Vector3(0.0, -0.5, -2.2)
			fov = 42.0
			sec = WIDE_SEC + DRAW_INTERVAL
		"draw", "draw2":
			var side := 1.0 if shot == "draw" else -1.0
			pos = Vector3(2.2 * side, 2.15, -3.05)
			target = Vector3(0.0, 1.55, BOX_Z + 0.2)
			move = Vector3(-0.25 * side, -0.05, -0.15)
			fov = 38.0
			sec = DRAW_INTERVAL
		"line":
			pos = Vector3(0.0, 1.7, 1.6)
			target = Vector3(0.0, 1.15, ROW_Z)
			move = Vector3(0.0, -0.1, -0.5)
			fov = 40.0
			sec = LINE_SEC
		"hands":
			# 並んだ代表者の手元を、列に沿って横に流す
			var x0 := _home_position(0).x - 0.3
			pos = Vector3(x0, 1.24, ROW_Z + 1.75)
			target = Vector3(x0, 1.12, ROW_Z + 0.3)
			move = Vector3(-2.0 * x0, 0.0, 0.0)
			follow = true
			fov = 30.0
			sec = TENSION_SEC
		"winner", "applause":
			var wp := _part_of(winner)
			var w: Vector3 = wp["home"] if not wp.is_empty() else Vector3(0.0, 0.0, ROW_Z)
			if shot == "winner":
				pos = w + Vector3(0.3, 1.75, 2.1)
				target = w + Vector3(0.0, 1.55, 0.0)
				move = Vector3(-0.1, 0.0, -0.35)
				fov = 34.0
				sec = WINNER_SEC
			else:
				pos = Vector3(5.6, 2.5, 2.4)
				target = Vector3(w.x * 0.5, 1.0, -1.6)
				move = Vector3(-0.6, 0.0, 0.4)
				fov = 44.0
				sec = APPLAUSE_SEC
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	_camera.fov = fov
	_place_camera(0.0, pos, move, target, follow)
	_cam_tween = create_tween()
	_cam_tween.set_speed_scale(speed)
	_cam_tween.tween_method(_place_camera.bind(pos, move, target, follow), 0.0, 1.0, sec) 		.set_trans(Tween.TRANS_SINE)


## follow なら見る先もカメラと一緒に動く（横に流すカット）
func _place_camera(t: float, pos: Vector3, move: Vector3, target: Vector3, follow: bool) -> void:
	_camera.position = pos + move * t
	_camera.look_at(target + (move * t if follow else Vector3.ZERO))


# --- 小物 ----------------------------------------------------------------------------------

func _give(team: String, item: Node3D) -> void:
	var old: Node3D = _held.get(team)
	if old != null and is_instance_valid(old):
		old.queue_free()
	_world.add_child(item)
	_held[team] = item
	var p := _part_of(team)
	if not p.is_empty():
		var hand: Node3D = p[item.get_meta("hand", "hand_r")]
		item.global_position = hand.global_position + item.get_meta("offset", Vector3.ZERO)


func _part_of(team: String) -> Dictionary:
	for p: Dictionary in _parts:
		if p["team"] == team:
			return p
	return {}


func _home_position(i: int) -> Vector3:
	var x := (float(i) - float(teams.size() - 1) * 0.5) * ROW_SPACING
	return Vector3(x, 0.0, ROW_Z)


## 球団名から決まる個体差（0..n-1）。抽選の乱数とは別
func _trait(team: String, salt: String, n: int) -> int:
	return absi(hash(team + salt)) % n


# --- 作る：画面の枠 -------------------------------------------------------------------------

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
	env.background_color = Color("d8d2c8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff4e6")
	env.ambient_light_energy = 0.72
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_world.add_child(world_env)
	# 宴会場の照明：正面の上からの明るい平行光1つ（影はこれだけ）
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, 18.0, 0.0)
	light.light_energy = 0.95
	light.light_color = Color("fffaf0")
	light.shadow_enabled = true
	light.shadow_opacity = 0.55
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	light.directional_shadow_max_distance = 16.0
	_world.add_child(light)
	_camera = Camera3D.new()
	_camera.fov = 42.0
	_camera.current = true
	_world.add_child(_camera)
	_confetti = _make_confetti()
	_world.add_child(_confetti)
	# 当選球団の字幕（画面の下）
	_caption = PanelContainer.new()
	_caption.visible = false
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caption.offset_bottom = -14.0
	add_child(_caption)
	_caption_label = Label.new()
	_caption_label.add_theme_font_override("font", UiTheme.font(800))
	_caption_label.add_theme_font_size_override("font_size", 26)
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_child(_caption_label)
	_murmur = AudioStreamPlayer.new()
	add_child(_murmur)
	_clap = AudioStreamPlayer.new()
	add_child(_clap)


# --- 作る：会場 ----------------------------------------------------------------------------

## 床（模様の絨毯）・赤いじゅうたんの通路・段のある白い台・白い抽選箱・奥の壁と看板・両脇の幕
func _make_venue() -> void:
	var floor_mi := _add_mesh(_world, _box_mesh(Vector3(28.0, 0.1, 22.0)), Color.WHITE, Vector3(0.0, -0.05, 0.5))
	var carpet := StandardMaterial3D.new()
	carpet.albedo_texture = _carpet_texture()
	carpet.uv1_scale = Vector3(14.0, 11.0, 1.0)
	carpet.roughness = 0.95
	floor_mi.material_override = carpet
	_add_mesh(_world, _box_mesh(Vector3(1.5, 0.02, 9.0)), Color("a3141c"), Vector3(0.0, 0.01, 0.6))
	for x: float in [-0.78, 0.78]:
		_add_mesh(_world, _box_mesh(Vector3(0.06, 0.022, 9.0)), GOLD, Vector3(x, 0.011, 0.6))
	# 段のある白い台（縁は金）
	_add_mesh(_world, _box_mesh(Vector3(5.2, TIER1_TOP, 2.6)), Color("f4f4f2"), Vector3(0.0, TIER1_TOP * 0.5, STAGE_Z),
		true)
	_add_mesh(_world, _box_mesh(Vector3(2.6, TIER2_TOP - TIER1_TOP, 1.5)), Color("fafafa"),
		Vector3(0.0, (TIER1_TOP + TIER2_TOP) * 0.5, STAGE_Z - 0.3), true)
	_add_mesh(_world, _box_mesh(Vector3(5.2, 0.03, 0.03)), GOLD, Vector3(0.0, TIER1_TOP, STAGE_Z + 1.3))
	_add_mesh(_world, _box_mesh(Vector3(2.6, 0.03, 0.03)), GOLD, Vector3(0.0, TIER2_TOP, STAGE_Z + 0.45))
	# 抽選箱：白い台座の上の白い箱、上に丸い穴
	_add_mesh(_world, _box_mesh(Vector3(0.8, 0.55, 0.6)), Color("f7f7f5"), Vector3(0.0, TIER2_TOP + 0.275, BOX_Z), true)
	_add_mesh(_world, _box_mesh(Vector3(0.62, 0.46, 0.5)), Color.WHITE, Vector3(0.0, TIER2_TOP + 0.55 + 0.23, BOX_Z), true)
	var hole := CylinderMesh.new()
	hole.top_radius = 0.12
	hole.bottom_radius = 0.12
	hole.height = 0.01
	hole.radial_segments = 20
	_add_mesh(_world, hole, Color("151515"), Vector3(0.0, TIER2_TOP + 1.015, BOX_Z))
	var rim := TorusMesh.new()
	rim.inner_radius = 0.12
	rim.outer_radius = 0.15
	rim.rings = 16
	rim.ring_segments = 6
	_add_mesh(_world, rim, Color("e2e2e2"), Vector3(0.0, TIER2_TOP + 1.012, BOX_Z))
	# 奥の壁・看板「DRAFT <年>」（ゲームの表記。ロゴやスポンサーは出さない）
	_add_mesh(_world, _box_mesh(Vector3(28.0, 8.0, 0.2)), Color("e8e4dc"), Vector3(0.0, 4.0, WALL_Z))
	_add_mesh(_world, _box_mesh(Vector3(9.4, 3.0, 0.08)), Color("12305e"), Vector3(0.0, 3.1, WALL_Z + 0.12))
	_add_mesh(_world, _box_mesh(Vector3(9.6, 0.08, 0.1)), GOLD, Vector3(0.0, 4.62, WALL_Z + 0.13))
	_add_mesh(_world, _box_mesh(Vector3(9.6, 0.08, 0.1)), GOLD, Vector3(0.0, 1.58, WALL_Z + 0.13))
	var title := _label3d("DRAFT %d" % _year if _year > 0 else "DRAFT", 160, 0.0085, Color.WHITE, Color("0a1b38"))
	title.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	title.position = Vector3(0.0, 3.45, WALL_Z + 0.18)
	_world.add_child(title)
	var sub := _label3d("プロ野球ドラフト会議", 72, 0.0075, GOLD, Color("0a1b38"))
	sub.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sub.position = Vector3(0.0, 2.35, WALL_Z + 0.18)
	_world.add_child(sub)
	# 両脇の幕と柱
	for side: float in [-1.0, 1.0]:
		_add_mesh(_world, _box_mesh(Vector3(3.2, 6.0, 0.1)), Color("7a1d26"), Vector3(side * 6.8, 3.0, WALL_Z + 0.15))
		_add_mesh(_world, _box_mesh(Vector3(0.5, 6.5, 0.5)), Color("f2efe8"), Vector3(side * 5.0, 3.25, WALL_Z + 0.3))


## 丸テーブル（白いクロス・球団カラーの旗と札）に、各球団の関係者が3人ずつ座る（台の方を向く）
func _make_tables() -> void:
	var cloth := CylinderMesh.new()
	cloth.top_radius = TABLE_RADIUS
	cloth.bottom_radius = TABLE_RADIUS + 0.06
	cloth.height = 0.74
	cloth.radial_segments = 20
	var n := 0
	for zi in TABLE_ZS.size():
		for xi in TABLE_XS.size():
			var team: String = _all_teams[n] if n < _all_teams.size() else ""
			n += 1
			var center := Vector3(TABLE_XS[xi], 0.0, TABLE_ZS[zi])
			_add_mesh(_world, cloth, CLOTH, center + Vector3(0.0, 0.37, 0.0), true)
			if team.is_empty():
				continue
			var colors := GameData.team_colors(team)
			# 旗（細い柱と球団カラーの旗）と球団名の札
			_add_mesh(_world, _cylinder(0.008, 0.42, 6), Color("c0c0c0"), center + Vector3(0.0, 0.95, 0.0))
			_add_mesh(_world, _box_mesh(Vector3(0.24, 0.15, 0.01)), colors[0], center + Vector3(0.13, 1.08, 0.0))
			_add_mesh(_world, _box_mesh(Vector3(0.24, 0.035, 0.012)), colors[1], center + Vector3(0.13, 1.02, 0.0))
			var plate := _label3d(GameData.short_name(team), 40, 0.004, Color.WHITE, colors[0].darkened(0.3))
			plate.position = center + Vector3(0.0, 1.32, 0.0)
			_world.add_child(plate)
			for k in 3:
				var ang := deg_to_rad(-50.0 + 50.0 * k)
				var off := Vector3(sin(ang), 0.0, cos(ang)) * (TABLE_RADIUS + 0.28)
				_staff.append(_make_staff(team, center + off, k))
				# 白いカバーの椅子（背もたれ）
				_add_mesh(_world, _box_mesh(Vector3(0.42, 0.95, 0.07)), CLOTH,
					center + off * 1.22 + Vector3(0.0, 0.47, 0.0))


func _carpet_texture() -> ImageTexture:
	if _carpet_tex != null:
		return _carpet_tex
	# 宴会場の絨毯：えんじの地に金の菱形の格子と小さな花
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var base := Color("6b1f2a")
	var line := Color("b08a3e")
	var dot := Color("2c4a6b")
	for y in size:
		for x in size:
			var u := absf(float(x) - 31.5)
			var v := absf(float(y) - 31.5)
			var c := base
			var d := u + v
			if absf(d - 31.5) < 1.6 or absf(d - 15.5) < 0.9:
				c = line
			elif d < 5.0:
				c = dot
			elif (x + y) % 9 == 0 and d > 18.0 and d < 28.0:
				c = base.lightened(0.08)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	_carpet_tex = ImageTexture.create_from_image(img)
	return _carpet_tex


# --- 作る：人物 ----------------------------------------------------------------------------

## 代表者：スーツ（上着・ズボン）・白いシャツ・球団カラーのネクタイ・首から下げた名札・髪・顔（目・眉・鼻・口・耳）・
## 肩とひじの関節・手。体格・髪型・髪の色・スーツの色に球団名から決まる個体差
func _make_rep(team: String, home: Vector3) -> Dictionary:
	var colors := GameData.team_colors(team)
	var suit: Color = SUITS[_trait(team, "suit", SUITS.size())]
	var hair: Color = HAIRS[_trait(team, "hair", HAIRS.size())]
	var build := 1.0 + 0.07 * float(_trait(team, "build", 4))
	var height := 0.96 + 0.025 * float(_trait(team, "height", 4))
	var root := Node3D.new()
	root.position = home
	root.scale = Vector3(1.0, height, 1.0)
	_world.add_child(root)
	var body := Node3D.new()
	root.add_child(body)
	var trousers := suit.darkened(0.12)
	for x: float in [-0.09, 0.09]:
		_add_mesh(body, _capsule(0.075, 0.84), trousers, Vector3(x * build, 0.44, 0.0), true)
		_add_mesh(body, _box_mesh(Vector3(0.1, 0.06, 0.24)), Color("141414"), Vector3(x * build, 0.03, 0.04), true)
	var chest := Node3D.new()
	chest.position = Vector3(0.0, 0.84, 0.0)
	body.add_child(chest)
	var jacket := _add_mesh(chest, _capsule(0.2, 0.7), suit, Vector3(0.0, 0.3, 0.0), true)
	jacket.scale = Vector3(build, 1.0, 0.78)
	var front_z := 0.2 * 0.78
	_add_mesh(chest, _box_mesh(Vector3(0.12, 0.24, 0.02)), SHIRT, Vector3(0.0, 0.47, front_z - 0.004))
	_add_mesh(chest, _box_mesh(Vector3(0.05, 0.05, 0.026)), colors[0].darkened(0.1), Vector3(0.0, 0.56, front_z + 0.004))
	_add_mesh(chest, _box_mesh(Vector3(0.045, 0.22, 0.02)), colors[0], Vector3(0.0, 0.42, front_z + 0.006))
	_add_mesh(chest, _box_mesh(Vector3(0.045, 0.02, 0.022)), colors[1], Vector3(0.0, 0.40, front_z + 0.008))
	# 首から下げた名札
	for side: float in [-1.0, 1.0]:
		var strap := _add_mesh(chest, _box_mesh(Vector3(0.012, 0.24, 0.006)), Color("2b3a7a"),
			Vector3(0.045 * side, 0.46, front_z + 0.012))
		strap.rotation.z = -0.22 * side
	_add_mesh(chest, _box_mesh(Vector3(0.1, 0.13, 0.008)), Color.WHITE, Vector3(0.0, 0.28, front_z + 0.016))
	_add_mesh(chest, _box_mesh(Vector3(0.1, 0.025, 0.01)), colors[0], Vector3(0.0, 0.33, front_z + 0.018))
	var tag := _label3d(("★" if team == _user_team else "") + GameData.short_name(team), 24, 0.0013,
		Color("1a1a1a"), Color.WHITE)
	tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	tag.outline_size = 2
	tag.position = Vector3(0.0, 0.27, front_z + 0.022)
	chest.add_child(tag)
	_add_mesh(chest, _cylinder(0.05, 0.08, 10), SKIN, Vector3(0.0, 0.66, 0.0))
	var head := Node3D.new()
	head.position = Vector3(0.0, 0.69, 0.0)
	chest.add_child(head)
	_make_face(head, hair, _trait(team, "style", 4))
	var arms := {}
	for side: float in [1.0, -1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(0.23 * side * build, 0.58, 0.0)
		chest.add_child(sh)
		_add_mesh(sh, _capsule(0.062, 0.36), suit, Vector3(0.0, -0.15, 0.0), true)
		var el := Node3D.new()
		el.position = Vector3(0.0, -0.31, 0.0)
		sh.add_child(el)
		_add_mesh(el, _capsule(0.056, 0.32), suit, Vector3(0.0, -0.13, 0.0), true)
		_add_mesh(el, _cylinder(0.05, 0.03, 10), SHIRT, Vector3(0.0, -0.28, 0.0))
		var hand := Node3D.new()
		hand.position = Vector3(0.0, -0.34, 0.0)
		el.add_child(hand)
		var palm := _add_mesh(hand, _sphere(0.05, 0.1), SKIN, Vector3.ZERO)
		palm.scale = Vector3(0.85, 1.15, 0.7)
		var thumb := _add_mesh(hand, _capsule(0.016, 0.07), SKIN, Vector3(-0.035 * side, 0.01, 0.025))
		thumb.rotation.z = 0.5 * side
		arms[side] = [sh, el, hand]
	return {"root": root, "body": body, "chest": chest, "head": head, "sh_r": arms[1.0][0], "sh_l": arms[-1.0][0],
		"el_r": arms[1.0][1], "el_l": arms[-1.0][1], "hand_r": arms[1.0][2], "hand_l": arms[-1.0][2],
		"home": home, "team": team}


## 顔：頭・耳・目・眉・鼻・口と、髪型（0 短髪・1 七三・2 白髪まじりの薄め・3 角刈り）
func _make_face(head: Node3D, hair: Color, style: int) -> void:
	var skull := _add_mesh(head, _sphere(0.14, 0.28), SKIN, Vector3(0.0, 0.14, 0.0), true)
	skull.scale = Vector3(0.95, 1.08, 1.0)
	for side: float in [-1.0, 1.0]:
		var ear := _add_mesh(head, _sphere(0.032, 0.064), SKIN.darkened(0.05), Vector3(0.132 * side, 0.13, 0.0))
		ear.scale = Vector3(0.6, 1.0, 0.9)
		var eye := _add_mesh(head, _sphere(0.017, 0.034), Color("1b1b1b"), Vector3(0.048 * side, 0.15, 0.125))
		eye.scale = Vector3(1.0, 1.15, 0.6)
		_add_mesh(head, _box_mesh(Vector3(0.05, 0.012, 0.012)), hair.darkened(0.2), Vector3(0.048 * side, 0.19, 0.125))
	_add_mesh(head, _sphere(0.02, 0.04), SKIN.darkened(0.08), Vector3(0.0, 0.115, 0.137))
	_add_mesh(head, _box_mesh(Vector3(0.05, 0.009, 0.01)), Color("8a4a3a"), Vector3(0.0, 0.07, 0.128))
	var cap := SphereMesh.new()
	cap.radius = 0.148
	cap.height = 0.148
	cap.is_hemisphere = true
	cap.radial_segments = 16
	cap.rings = 5
	match style:
		0:
			var h := _add_mesh(head, cap, hair, Vector3(0.0, 0.17, -0.012), true)
			h.scale = Vector3(1.0, 0.95, 1.02)
		1:
			var h := _add_mesh(head, cap, hair, Vector3(0.0, 0.175, -0.008), true)
			h.scale = Vector3(1.02, 1.0, 1.03)
			var fringe := _add_mesh(head, _box_mesh(Vector3(0.16, 0.04, 0.05)), hair, Vector3(0.03, 0.27, 0.1))
			fringe.rotation.z = -0.25
		2:
			var h := _add_mesh(head, cap, hair, Vector3(0.0, 0.12, -0.03), true)
			h.scale = Vector3(1.03, 0.75, 0.95)
		_:
			var h := _add_mesh(head, cap, hair, Vector3(0.0, 0.2, 0.0), true)
			h.scale = Vector3(0.98, 0.7, 0.98)
			_add_mesh(head, _box_mesh(Vector3(0.2, 0.05, 0.2)), hair, Vector3(0.0, 0.285, 0.0))


## 着席の関係者（遠くから見るので簡略）：胴・頭・髪・前に出した両腕・立ったときの脚
func _make_staff(team: String, pos: Vector3, k: int) -> Dictionary:
	var suit: Color = SUITS[_trait(team, "staff%d" % k, SUITS.size())]
	var hair: Color = HAIRS[_trait(team, "staffhair%d" % k, HAIRS.size())]
	var root := Node3D.new()
	root.position = pos
	# テーブル（台の方）を向く
	root.rotation.y = atan2(-pos.x * 0.15, -1.0) + PI
	_world.add_child(root)
	var legs := Node3D.new()
	legs.visible = false
	root.add_child(legs)
	_add_mesh(legs, _box_mesh(Vector3(0.26, 0.5, 0.16)), suit.darkened(0.12), Vector3(0.0, 0.25, 0.0))
	var body := Node3D.new()
	body.position = Vector3(0.0, 0.5, 0.0)
	root.add_child(body)
	var torso := _add_mesh(body, _capsule(0.18, 0.6), suit, Vector3(0.0, 0.3, 0.0))
	torso.scale = Vector3(1.0, 1.0, 0.8)
	_add_mesh(body, _box_mesh(Vector3(0.1, 0.18, 0.02)), SHIRT, Vector3(0.0, 0.42, 0.14))
	var head := Node3D.new()
	head.position = Vector3(0.0, 0.62, 0.0)
	body.add_child(head)
	_add_mesh(head, _sphere(0.13, 0.27), SKIN, Vector3(0.0, 0.13, 0.0))
	var cap := SphereMesh.new()
	cap.radius = 0.138
	cap.height = 0.138
	cap.is_hemisphere = true
	cap.radial_segments = 12
	cap.rings = 4
	_add_mesh(head, cap, hair, Vector3(0.0, 0.16, -0.01))
	var arms := []
	for side: float in [1.0, -1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.2 * side, 0.5, 0.0)
		body.add_child(arm)
		_add_mesh(arm, _capsule(0.055, 0.5), suit, Vector3(0.0, -0.22, 0.0))
		arms.append(arm)
	return {"root": root, "body": body, "head": head, "arm_r": arms[0], "arm_l": arms[1], "legs": legs,
		"phase": float(_staff.size() % 7) + 0.37 * float(k)}


func _make_envelope() -> Node3D:
	var item := Node3D.new()
	item.set_meta("offset", Vector3(0.0, 0.0, 0.04))
	_add_mesh(item, _box_mesh(Vector3(0.22, 0.12, 0.012)), ENVELOPE, Vector3.ZERO)
	_add_mesh(item, _sphere(0.016, 0.032), Color("b3261e"), Vector3(0.0, 0.02, 0.008))
	return item


## 開けた紙。当たりは赤い字で「交渉権確定」、外れは白紙
func _make_card(winning: bool) -> Node3D:
	var item := Node3D.new()
	item.set_meta("winning", winning)
	_add_mesh(item, _box_mesh(Vector3(CARD_SIZE.x, CARD_SIZE.y, 0.008)), Color.WHITE, Vector3.ZERO)
	if winning:
		var text := _label3d(CARD_TEXT, 48, 0.0012, Color("d0101a"), Color.WHITE)
		text.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		text.outline_size = 2
		text.position = Vector3(0.0, 0.0, 0.006)
		item.add_child(text)
		for y: float in [CARD_SIZE.y * 0.5 - 0.012, -CARD_SIZE.y * 0.5 + 0.012]:
			_add_mesh(item, _box_mesh(Vector3(CARD_SIZE.x, 0.012, 0.01)), Color("d0101a"), Vector3(0.0, y, 0.0))
	return item


func _make_confetti() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 90
	p.lifetime = 2.4
	p.explosiveness = 0.85
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.4
	p.gravity = Vector3(0.0, -3.0, 0.0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(1.5, 0.1, 0.4)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.04)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	p.mesh = quad
	return p


## 紙吹雪を当たりの球団の色にする
func _tint_confetti() -> void:
	var colors := GameData.team_colors(winner)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	ramp.colors = PackedColorArray([colors[0], GOLD, Color.WHITE, colors[1]])
	_confetti.color_initial_ramp = ramp


# --- 効果音（ざわめき・拍手。波形をコードで作る） -------------------------------------------------

func _play_sfx(player: AudioStreamPlayer, kind: String, db: float) -> void:
	if player == null:
		return
	player.stream = _sound(kind)
	player.volume_db = db
	player.play()


func _fade_sfx(player: AudioStreamPlayer, db: float, sec: float) -> void:
	if player == null or not player.playing:
		return
	create_tween().tween_property(player, "volume_db", db, sec)


static func _sound(kind: String) -> AudioStreamWAV:
	if _sfx.has(kind):
		return _sfx[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261101
	var secs := 3.0 if kind == "murmur" else 2.8
	var n := int(SAMPLE_RATE * secs)
	var buf := PackedFloat32Array()
	buf.resize(n)
	if kind == "murmur":
		# ざわめき：こもった雑音を、話し声のようにゆっくり大小させる（ループ）
		var lp := 0.0
		var freqs: Array[float] = []
		for k in 6:
			freqs.append(float(1 + rng.randi_range(1, 4)) / secs)
		for i in n:
			lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
			var t := float(i) / SAMPLE_RATE
			var amp := 0.0
			for k in freqs.size():
				amp += maxf(0.0, sin(TAU * freqs[k] * t + float(k) * 1.7))
			buf[i] = lp * (0.4 + 0.25 * amp)
	else:
		# 拍手：短い雑音の破裂を不規則にたくさん重ね、立ち上がり・終わりをなだらかに
		var claps := int(secs * 70.0)
		for c in claps:
			var start := rng.randi_range(0, n - 400)
			var gain := rng.randf_range(0.3, 0.8)
			var prev := 0.0
			for j in 380:
				var w := rng.randf_range(-1.0, 1.0)
				var hp := w - prev
				prev = w
				buf[start + j] += hp * gain * exp(-float(j) / 55.0)
		for i in n:
			var t := float(i) / float(n)
			buf[i] *= minf(1.0, t / 0.08) * minf(1.0, (1.0 - t) / 0.35)
	var peak := 0.001
	for v in buf:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] / peak * 0.85, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	if kind == "murmur":
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = n
	_sfx[kind] = wav
	return wav


# --- 部品 ----------------------------------------------------------------------------------

func _label3d(text: String, font_size: int, pixel: float, color: Color, outline: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UiTheme.font(800)
	l.font_size = font_size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_modulate = outline
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.double_sided = false
	return l


## 影を落とすのは shadow が true の物だけ（代表者・台・机）
func _add_mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, shadow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.8
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


func _cylinder(radius: float, height: float, segments: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = segments
	return m


func _sphere(radius: float, height: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 14
	m.rings = 7
	return m
