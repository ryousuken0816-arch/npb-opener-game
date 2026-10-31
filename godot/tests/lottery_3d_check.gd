extends SceneTree
## ドラフトの抽選の3D演出の確認（docs/AUTORUN.md 作業20・29。ヘッドレス可、約1分半）。
## 1) 演出のシーン（scenes/draft/lottery_3d.tscn）だけ：5球団の抽選を最後まで流すと、くじを引く → 開ける → 結果の場面へ進み、
##    「交渉権確定」の紙を持つのが渡した当たりの球団。会場の丸テーブルに関係者がいて、カメラが
##    全景 → くじを引く手元 → 並んだ列 → 手元の寄り → 当選の瞬間 → 拍手 と切り替わる。途中で skip() すると結果の場面へ飛ぶ
## 2) 2024年開始（巨人）：ドラフトの画面で宗山塁（5球団競合）に入札 → 抽選が3Dの演出で出る（宗山・金丸の両方）。
##    結果は、入札の直前の Draft を写したもの（to_save → from_save）で同じ入札をしたときの抽選と一致（演出が結果を変えない）。
##    宗山の抽選は最後まで流してカメラの切り替えを確かめ、3Dで当たりの紙を持つ球団＝抽選の当たり。
##    Ⓐ（「結果を見る」に決定）・演出のクリックで飛ばせる。早送り中は2Dの演出
## 3) 2012年開始（巨人）：藤浪晋太郎（4球団競合）に入札 → 3Dの演出・結果が一致・Ⓑ（ハブの戻る）で飛ばせる
##
##   godot --headless --path godot -s res://tests/lottery_3d_check.gd -- [出力先]
##   （出力先はウィンドウ付きのときだけ。宗山の抽選の全景・手元の寄り・当選の瞬間を、同じ起動の中でスクショ）

const USER := "読売ジャイアンツ"
const MUNETAKA := "宗山 塁"
const KANEMARU := "金丸 夢斗"
const FUJINAMI := "藤浪 晋太郎"
## 使うはずのカメラ
const SHOTS := ["wide", "draw", "line", "hands", "winner", "applause"]
const SCENE := "res://scenes/draft/lottery_3d.tscn"
const SAMPLE_TEAMS := ["東北楽天ゴールデンイーグルス", "広島東洋カープ", "北海道日本ハムファイターズ",
	"福岡ソフトバンクホークス", "埼玉西武ライオンズ"]
## 演出が最後まで進むのを待つ上限（秒）
const PLAY_LIMIT_SEC := 20.0

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node
var _ds: GDScript
var _dv: GDScript
var _first := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(1280, 720)
	else:
		# ウィンドウ付き（スクショ）のときもフォーカスを奪わない（CLAUDE.md）
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_ds = load("res://sim/draft.gd")
	_dv = load("res://scenes/hub/draft_view.gd")
	_first = _ds.Stage["FIRST"]
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	await _check_scene()
	await _check_2024()
	await _check_2012()
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("OK ", label)
	else:
		_failures += 1
		print("NG ", label)


# --- 1) 演出のシーンだけ ----------------------------------------------------------------------

func _check_scene() -> void:
	print("== 演出のシーン ==")
	var scene: PackedScene = load(SCENE)
	var winner: String = SAMPLE_TEAMS[3]
	var lot := {"id": "x", "teams": SAMPLE_TEAMS, "winner": winner}
	# 最後まで流す（速さ4倍）
	var view: Control = scene.instantiate()
	root.add_child(view)
	var got := [""]
	view.connect("revealed", func(w: String) -> void: got[0] = w)
	view.call("play", lot, {"user_team": SAMPLE_TEAMS[1], "speed": 4.0})
	var phases := {}
	var t0 := Time.get_ticks_msec()
	while not view.call("is_revealed") and Time.get_ticks_msec() - t0 < PLAY_LIMIT_SEC * 1000.0:
		phases[view.get("phase")] = int(view.get("drawn"))
		await process_frame
	_check(view.call("is_revealed") and got[0] == winner and view.call("shown_winner") == winner,
		"最後まで流すと結果の場面（revealed=%s、当たりの紙=%s、期待=%s）" % [_gd.short_name(got[0]),
			_gd.short_name(view.call("shown_winner")), _gd.short_name(winner)])
	_check(phases.has("draw") and phases.has("open") and int(view.get("drawn")) == SAMPLE_TEAMS.size(),
		"くじを引く → 開ける の順に進み、%d球団すべてが引いた（%s）" % [SAMPLE_TEAMS.size(), str(phases)])
	await _wait_shot(view, "applause")
	_check(_has_shots(view), "カメラが切り替わる（%s）" % ", ".join(view.get("shots_seen")))
	_check(int(view.call("staff_count")) == SAMPLE_TEAMS.size() * 3,
		"会場の丸テーブルに関係者（all_teams が無いときは競合した球団×3人：%d人）" % int(view.call("staff_count")))
	view.queue_free()
	# 途中で飛ばす
	var view2: Control = scene.instantiate()
	root.add_child(view2)
	view2.call("play", lot, {"user_team": SAMPLE_TEAMS[1]})
	await create_timer(0.6).timeout
	var mid_phase: String = view2.get("phase")
	view2.call("skip")
	await _frames(2)
	_check(mid_phase == "draw" and view2.call("is_revealed") and view2.call("shown_winner") == winner,
		"途中（%s）で skip() → 結果の場面で当たりは%s" % [mid_phase, _gd.short_name(view2.call("shown_winner"))])
	view2.queue_free()
	await _frames(2)


# --- 2) 2024年・ドラフトの画面 ------------------------------------------------------------------

func _check_2024() -> void:
	print("== 2024年開始・ドラフトの画面（%s） ==" % USER)
	var opened := await _open_draft(2024)
	if opened.is_empty():
		return
	var d: RefCounted = opened[0]
	var view: Node = opened[1]
	var mune: Dictionary = _find(d, MUNETAKA)
	var kane: Dictionary = _find(d, KANEMARU)
	_check(not mune.is_empty() and not kane.is_empty(), "候補に宗山塁・金丸夢斗がいる")
	if mune.is_empty():
		return
	var pair := await _bid(d, view, mune)
	var expected: Dictionary = pair[0]
	var actual: Dictionary = pair[1]
	_check(actual.has(kane["id"]), "金丸も競合して抽選（%d球団）" % \
		(actual[kane["id"]]["teams"].size() if actual.has(kane["id"]) else 0))
	# 1つ目（自球団の入った宗山）：3Dの演出を最後まで流す（全景・手元の寄り・当選の瞬間をスクショ）
	var seen := {}
	var lot3d: Node = view.call("lottery_3d")
	_check(lot3d != null and view.call("use_3d_lottery"), "抽選が3Dの演出で出る（1つ目）")
	if lot3d == null:
		return
	var lot1: Dictionary = _lot_of(actual, lot3d)
	_check(int(lot3d.call("staff_count")) == 36, "会場の丸テーブルに12球団の関係者（%d人）" % int(lot3d.call("staff_count")))
	await create_timer(0.8).timeout
	await _shot("lottery3d_wide", 0.0)
	await _wait_shot(lot3d, "hands")
	await create_timer(0.5).timeout
	await _shot("lottery3d_hands", 0.0)
	await _wait_until(func() -> bool: return lot3d.call("is_revealed"))
	_check(lot3d.get("phase") == "result" and int(lot3d.get("drawn")) == lot1.get("teams", []).size(),
		"最後まで流すと全球団がくじを引いて結果の場面（%d球団）" % int(lot3d.get("drawn")))
	await create_timer(0.6).timeout
	await _shot("lottery3d_winner", 0.0)
	_check(lot3d.call("shown_winner") == lot1.get("winner", "?"),
		"3Dで当たりの紙を持つのは抽選の当たり（%s：%s）" % [_cand_name(d, lot1), _gd.short_name(lot3d.call("shown_winner"))])
	_check(_result_text(view).find(_gd.short_name(lot1.get("winner", "?"))) >= 0,
		"結果の文言に当たりの球団（%s）" % _result_text(view))
	await _wait_shot(lot3d, "applause")
	_check(_has_shots(lot3d), "カメラが中継のように切り替わる（%s）" % ", ".join(lot3d.get("shots_seen")))
	seen[lot1.get("id", "")] = true
	# 2つ目：「次へ」をⒶで押す → 次の抽選の3D → Ⓐ（「結果を見る」）で飛ばす
	await _accept()
	lot3d = view.call("lottery_3d")
	_check(lot3d != null and not lot3d.call("is_revealed"), "Ⓐで次へ → 2つ目の抽選も3Dの演出")
	if lot3d != null:
		var lot2: Dictionary = _lot_of(actual, lot3d)
		await create_timer(0.3).timeout
		await _accept()
		_check(lot3d.call("is_revealed") and lot3d.call("shown_winner") == lot2.get("winner", "?"),
			"Ⓐで飛ばす → 結果の場面で当たりは%s（%s）" % [_gd.short_name(lot3d.call("shown_winner")), _cand_name(d, lot2)])
		seen[lot2.get("id", "")] = true
	# 3つ目があればクリックで飛ばす（無ければ、外れ1位の入札の結果へ）
	await _accept()
	lot3d = view.call("lottery_3d")
	if lot3d != null:
		var lot3: Dictionary = _lot_of(actual, lot3d)
		await create_timer(0.3).timeout
		await _click_center(lot3d)
		_check(lot3d.call("is_revealed") and lot3d.call("shown_winner") == lot3.get("winner", "?"),
			"クリックで飛ばす → 結果の場面で当たりは%s（%s）" % [_gd.short_name(lot3d.call("shown_winner")), _cand_name(d, lot3)])
		seen[lot3.get("id", "")] = true
	_check(seen.has(mune["id"]) and seen.has(kane["id"]), "宗山・金丸の両方の抽選を3Dで見た")
	# クリックで飛ばす（3つ目が無いときも確かめる）：写した Draft の宗山の抽選を、画面の外で再生してクリック
	if lot3d == null:
		var scene: PackedScene = load(SCENE)
		var solo: Control = scene.instantiate()
		var layer := CanvasLayer.new()
		layer.layer = 100  # ドラフトの画面の演出より上に置く
		root.add_child(layer)
		layer.add_child(solo)
		solo.position = Vector2(100, 100)
		var clicked := [false]
		solo.connect("clicked", func() -> void:
			clicked[0] = true
			solo.call("skip"))
		solo.call("play", expected[mune["id"]], {"user_team": USER})
		await create_timer(0.3).timeout
		await _click_center(solo)
		_check(clicked[0] and solo.call("is_revealed") and solo.call("shown_winner") == expected[mune["id"]]["winner"],
			"演出をクリック → clicked で飛ばせる（当たりは%s）" % _gd.short_name(solo.call("shown_winner")))
		layer.queue_free()
	view.call("finish_overlays")
	await _frames(2)
	_check(not view.call("overlay_visible"), "演出をすべて閉じられる（段階=%s）" % d.stage_text())
	# 早送り中は2Dの演出
	view.set("_fast", true)
	_check(not view.call("use_3d_lottery"), "早送り中は2Dの演出")
	view.set("_fast", false)


# --- 3) 2012年・藤浪 ----------------------------------------------------------------------------

func _check_2012() -> void:
	print("== 2012年開始・ドラフトの画面（%s） ==" % USER)
	var opened := await _open_draft(2012)
	if opened.is_empty():
		return
	var d: RefCounted = opened[0]
	var view: Node = opened[1]
	var fuji: Dictionary = _find(d, FUJINAMI)
	_check(not fuji.is_empty(), "候補に藤浪晋太郎がいる")
	if fuji.is_empty():
		return
	var pair := await _bid(d, view, fuji)
	var actual: Dictionary = pair[1]
	var lot3d: Node = view.call("lottery_3d")
	_check(lot3d != null, "藤浪の抽選も3Dの演出")
	if lot3d == null:
		return
	var lot1: Dictionary = _lot_of(actual, lot3d)
	await create_timer(1.6).timeout
	_check(lot3d.get("phase") == "draw" and lot3d.get("shots_seen").has("draw"),
		"演出が進む（%s、カメラ %s）" % [lot3d.get("phase"), ", ".join(lot3d.get("shots_seen"))])
	view.call("back")  # Ⓑ（ハブの戻るは DraftView.back を呼ぶ）
	await _frames(2)
	_check(lot3d.call("is_revealed") and view.call("overlay_visible") and view.call("lottery_3d") == lot3d,
		"Ⓑで飛ばす → 結果の場面（演出は閉じずに結果を見せる）")
	_check(lot3d.call("shown_winner") == lot1.get("winner", "?") and lot3d.get("camera_shot") == "winner",
		"Ⓑで飛ばしても当たりの紙を持つのは抽選の当たり（%s：%s）" % [_cand_name(d, lot1),
			_gd.short_name(lot3d.call("shown_winner"))])
	view.call("finish_overlays")
	await _frames(2)


# --- 共通 ---------------------------------------------------------------------------------

## その年から始めてドラフトの画面を開き、開幕の演出を閉じる。[Draft, DraftView]（開けなければ []）
func _open_draft(year: int) -> Array:
	_gs.new_game(USER, year)
	_gs.skip_to_phase(_gs.Phase.RELEASE)
	_gs.release_resolve()
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub: Node = current_scene
	hub.call("_on_menu_chosen", "advance")
	await _frames(3)
	var d: RefCounted = _gs.draft()
	var view: Node = _find_draft_view(hub)
	if d == null or view == null:
		_check(false, "%d年：ドラフトの画面が開く" % year)
		return []
	view.call("finish_overlays")
	await _frames(2)
	return [d, view]


## 自球団がその候補に1位で入札する。入札の直前の Draft を写して同じ入札をしたとき（演出なし）の抽選と比べる。
## [写した方の抽選, 画面の方の抽選]（候補の id → 抽選の記録）
func _bid(d: RefCounted, view: Node, cand: Dictionary) -> Array:
	# 候補などの辞書は参照で共有されるので深く写す
	var copy: RefCounted = _ds.from_save(d.to_save().duplicate(true))
	copy.user_bid(cand["id"])
	copy.run_first_wave()
	var expected := {}
	for lot: Dictionary in copy.last_lotteries():
		expected[lot["id"]] = lot
	view.call("select_candidate", cand["id"])
	await _frames(2)
	view.call("press_action")
	await _frames(3)
	var actual := {}
	for lot: Dictionary in d.last_lotteries():
		actual[lot["id"]] = lot
	var same := expected.size() == actual.size()
	for id: String in expected:
		if not actual.has(id) or actual[id]["winner"] != expected[id]["winner"] \
				or Array(actual[id]["teams"]) != Array(expected[id]["teams"]):
			same = false
	_check(same and not actual.is_empty(), "抽選の結果が演出なしで同じ入札をしたときと一致（%s）" % _lots_text(actual, d))
	_check(actual.has(cand["id"]) and actual[cand["id"]]["teams"].size() >= 2,
		"%sは競合して抽選（%d球団）" % [cand["name"],
			actual[cand["id"]]["teams"].size() if actual.has(cand["id"]) else 0])
	return [expected, actual]


func _has_shots(lot3d: Node) -> bool:
	var seen: Array = lot3d.get("shots_seen")
	for shot: String in SHOTS:
		if not seen.has(shot):
			return false
	return true


func _wait_shot(lot3d: Node, shot: String) -> void:
	await _wait_until(func() -> bool: return lot3d.get("camera_shot") == shot)


func _wait_until(cond: Callable) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < PLAY_LIMIT_SEC * 1000.0:
		await process_frame


func _lot_of(lots: Dictionary, lot3d: Node) -> Dictionary:
	for id: String in lots:
		if lots[id]["winner"] == lot3d.get("winner") and Array(lots[id]["teams"]) == Array(lot3d.get("teams")):
			return lots[id]
	return {}


func _lots_text(lots: Dictionary, d: RefCounted) -> String:
	var parts: Array[String] = []
	for id: String in lots:
		parts.append("%s %d球団→%s" % [d.by_id[id]["name"], lots[id]["teams"].size(), _gd.short_name(lots[id]["winner"])])
	return "、".join(parts)


func _cand_name(d: RefCounted, lot: Dictionary) -> String:
	return d.by_id.get(lot.get("id", ""), {}).get("name", "?")


func _result_text(view: Node) -> String:
	var label := view.find_child("LotteryResult", true, false) as Label
	return label.text if label != null else ""


func _find(d: RefCounted, name: String) -> Dictionary:
	for c: Dictionary in d.candidates:
		if c["name"] == name:
			return c
	return {}


func _find_draft_view(node: Node) -> Node:
	if node.get_script() == _dv:
		return node
	for child in node.get_children():
		var found := _find_draft_view(child)
		if found != null:
			return found
	return null


## Ⓐ：フォーカスしたボタンに決定（ui_accept）を送る
func _accept() -> void:
	for pressed: bool in [true, false]:
		var e := InputEventAction.new()
		e.action = "ui_accept"
		e.pressed = pressed
		root.push_input(e)
		await _frames(2)


## マウスのクリック（ヘッドレスでは Input.parse_input_event のマウスが GUI に届かないので、ビューポートへ直接送る）
func _click_center(c: Control) -> void:
	var pos := root.get_final_transform() * c.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = pos
	move.global_position = pos
	root.push_input(move)
	await _frames(1)
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		root.push_input(e)
		await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, wait := 0.35) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	if wait > 0.0:
		await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("  スクショ: %s.png" % name)
