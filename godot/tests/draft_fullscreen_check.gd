extends SceneTree
## ドラフトの画面は画面いっぱいで、後ろ（ハブ・下の帯・速報の帯・候補の表の「済」＋入団先）が見えないこと（docs/AUTORUN.md 作業81）。
## パソコン横・スマホ縦・スマホ横で、表・手帳・演出（開幕・発表・抽選）のどれを開いていても確かめる。2008年（史実の年）で
##   godot --headless --path godot -s res://tests/draft_fullscreen_check.gd

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TEAM := "読売ジャイアンツ"

var _failures := 0
var _gs: Node
var _layout: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_layout = root.get_node("UiLayout")
	for mode: Array in [["pc", Vector2i(1280, 720)], ["mobile", Vector2i(390, 844)], ["mobile", Vector2i(844, 390)]]:
		await _check_mode(mode[0], mode[1])
	print("\n%s" % ("全項目OK" if _failures == 0 else "NG %d件" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_mode(mode: String, size: Vector2i) -> void:
	var tag := "%s %dx%d" % [mode, size.x, size.y]
	root.size = size
	await process_frame
	_layout.call("set_force_mode", mode)
	_gs.new_game(TEAM, 2008)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	var hub: Node = current_scene
	var ticker: CanvasLayer = hub.get("_ticker")
	var sub: Control = hub.get_node("%SubScreen")
	var bottom_bar: Control = hub.get_node("%BottomBar")
	var screen := root.get_visible_rect()

	# 開く前：ふつうの配置（下の帯・速報の帯が見える）
	_check(ticker.visible, "[%s] 開く前は速報の帯が有効" % tag)
	hub.call("_open_sub_screen", "draft")
	await _settle()
	var view: Node = hub.get("_draft_view")
	_check_full(hub, sub, bottom_bar, ticker, screen, tag + " 開幕の演出")
	_check(_backdrop_opaque(view), "[%s] 演出の後ろは透けない" % tag)
	_check(view.call("overlay_visible"), "[%s] 開幕の演出が出ている" % tag)
	view.call("finish_overlays")
	await _settle()
	_check_full(hub, sub, bottom_bar, ticker, screen, tag + " 手帳")
	if mode == "pc":
		var status: Label = view.get("_status_label")
		_check(status.visible and not status.text.is_empty(), "[%s] 手帳でも説明の1行が画面の中に出る（下の帯を隠すので）" % tag)

	# 表から入札 → 発表・抽選の演出（後ろの表に「済」＋入団先が出ていても透けない）
	view.call("set_mode", "table")
	await _settle()
	_check_full(hub, sub, bottom_bar, ticker, screen, tag + " 表")
	var d: RefCounted = _gs.draft()
	var id: String = d.candidates[0]["id"]
	view.call("select_candidate", id)
	await _settle()
	view.call("press_action")
	await _settle()
	_check(view.call("overlay_visible"), "[%s] 入札のあと演出が出る" % tag)
	_check_full(hub, sub, bottom_bar, ticker, screen, tag + " 入札の演出")
	_check(_backdrop_opaque(view), "[%s] 発表・抽選の後ろは透けない" % tag)
	view.call("finish_overlays")
	await _settle()
	_check_full(hub, sub, bottom_bar, ticker, screen, tag + " 演出のあと")
	# 速報が来ても帯は見えない
	_gs.call("post_news", News.article("2008-10-30", "draft", "テスト見出し", "本文"), "", true)
	await _frames(3)
	_check(not ticker.visible, "[%s] ドラフト中は速報の帯が見えない" % tag)

	# 閉じるとハブの配置に戻る
	hub.call("_close_sub_screen")
	await _settle()
	_check(ticker.visible, "[%s] 閉じると速報の帯が戻る" % tag)
	_check(not sub.visible, "[%s] 閉じるとサブ画面は消える" % tag)
	if mode == "pc":
		_check(bottom_bar.visible, "[%s] 閉じると下の帯が戻る" % tag)
	# ほかのサブ画面は今までどおり余白あり（全画面にしない）
	hub.call("_open_sub_screen", "fa")
	await _settle()
	_check(not is_zero_approx(sub.offset_left) or not is_zero_approx(sub.offset_top), "[%s] FA の画面は全画面にしない" % tag)
	_check(ticker.visible, "[%s] FA の画面は速報の帯が見える" % tag)
	hub.call("_close_sub_screen")
	hub.queue_free()
	await _frames(2)


func _check_full(_hub: Node, sub: Control, bottom_bar: Control, ticker: CanvasLayer, screen: Rect2, label: String) -> void:
	_check(sub.visible, "[%s] サブ画面が出ている" % label)
	var r := sub.get_global_rect()
	var inset: float = _layout.call("bottom_inset")
	var top: float = _layout.get("safe_area_top") if bool(_layout.get("is_mobile")) else 0.0
	_check(is_equal_approx(r.position.x, screen.position.x) and is_equal_approx(r.end.x, screen.end.x),
		"[%s] 左右いっぱい（%s）" % [label, str(r)])
	_check(is_equal_approx(r.position.y, screen.position.y + top) and is_equal_approx(r.end.y, screen.end.y - inset),
		"[%s] 上下いっぱい（%s。上の余白 %s・下の帯 %s）" % [label, str(r), str(top), str(inset)])
	_check(not bottom_bar.visible, "[%s] 下の帯は隠す" % label)
	_check(not ticker.visible, "[%s] 速報の帯は隠す" % label)
	var style: StyleBox = sub.get_theme_stylebox("panel")
	_check(style is GlossBox and (style as GlossBox).bg_color.a >= 1.0, "[%s] サブ画面の地は透けない" % label)


func _backdrop_opaque(view: Node) -> bool:
	var overlay: Control = view.get("_overlay")
	for child in overlay.get_children():
		if child is ColorRect:
			return (child as ColorRect).color.a >= 1.0
	return false


func _check(ok: bool, label: String) -> void:
	print(("OK " if ok else "NG ") + label)
	if not ok:
		_failures += 1


func _settle() -> void:
	await create_timer(0.25).timeout
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
