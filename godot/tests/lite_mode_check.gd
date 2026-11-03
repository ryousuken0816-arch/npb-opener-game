extends SceneTree
## 軽量モード（docs/AUTORUN.md 作業75）とサブ画面を開くときに作る形の確認（ヘッドレス、約1分）。
## - ハブを開いた時点ではサブ画面（ドラフト・記録室など）を作っていない。開くと作る
## - 軽量モードのオン：閉じたら捨てる（新戦力 → トレードのように画面から画面へ移ったときも前の画面を捨てる）・
##   記録室を閉じたら字の画像の覚えを捨てる・開き直しても中身が出る・エラーが出ない
## - 軽量モードのオフ：閉じても残す（今までどおり）
## - 歴代ドラフトの通算成績・評価が、持っておく年を減らしても変わらない（2020年開始・2010年のソフトバンク）
## - システムの画面の「軽量モード」のボタンで切り替わる
##
##   godot --headless --path godot -s res://tests/lite_mode_check.gd

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TEAM := "福岡ソフトバンクホークス"
const START := 2020

var _failures := 0
var _gs: Node
var _hub: Node
var _rh: GDScript
var _lite: GDScript
var _theme: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_rh = load("res://scenes/hub/records_history.gd")
	_lite = load("res://scripts/lite_mode.gd")
	_theme = load("res://scripts/ui_theme.gd")
	_lite.set_on(false)
	_gs.new_game(TEAM, START)
	change_scene_to_file(HUB_SCENE)
	await _frames(4)
	_hub = current_scene
	_check(_hub.get("_views").is_empty() and _count("DraftView") == 0 and _count("RecordsView") == 0,
		"ハブを開いた時点ではサブ画面を作っていない")

	# 歴代ドラフトの通算成績（持っておく年を減らしても同じ）
	var full: Dictionary = _rh.draft_picks(2010, TEAM)
	_lite.set_on(true)
	_rh.clear_caches()
	var lite: Dictionary = _rh.draft_picks(2010, TEAM)
	_check(_picks_text(full) == _picks_text(lite) and not _picks_text(full).is_empty(),
		"歴代ドラフト（2010年）の通算・評価が軽量モードでも同じ（%s）" % _picks_text(lite).left(80))

	# 軽量モードのオン：記録室を開いて閉じると捨てる・字の画像の覚えも捨てる
	await _open("records")
	var records: Node = _hub.get("_records_view")
	records.call("set_tab", "members")
	await _frames(2)
	records.call("set_tab", "drafts")
	await _frames(2)
	_check(_glyph_textures() > 0, "記録室を開くと字の画像がある（%d枚）" % _glyph_textures())
	_hub.call("_close_sub_screen")
	_check(_glyph_textures() == 0, "軽量モード：記録室を閉じたら字の画像の覚えを捨てる")
	await _frames(2)
	_check(not is_instance_valid(records) and not _hub.get("_views").has("records"), "軽量モード：閉じたら記録室を捨てる")
	_check(_glyph_textures() > 0, "閉じたあとのハブの字は描き直す（%d枚）" % _glyph_textures())
	await _open("records")
	records = _hub.get("_records_view")
	records.call("set_tab", "members")
	await _frames(2)
	_check(records.visible and not (records.call("list_ids") as Array).is_empty(), "開き直しても歴代メンバーが出る")
	_hub.call("_close_sub_screen")
	await _frames(2)

	# 新戦力 → トレード：前の画面を捨てる
	await _open("scout")
	var scout: Node = _hub.get("_scout_view")
	scout.emit_signal("trade_requested")
	await _frames(2)
	_check(_hub.get("_open_key") == "trade" and not is_instance_valid(scout), "軽量モード：新戦力からトレードへ移ると新戦力を捨てる")
	_hub.call("_close_sub_screen")
	await _frames(2)
	_check(_hub.get("_views").is_empty() and _count("TradeView") == 0, "軽量モード：閉じたらサブ画面が残らない")

	# システム：軽量モードのボタン
	await _open("system")
	var save: Node = _hub.get("_save_view")
	var button: Button = save.get("_lite_button")
	_check(button != null and button.button_pressed and button.text.contains("オン"), "システムの軽量モードのボタンはオン")
	button.button_pressed = false
	_check(not _lite.on() and button.text.contains("オフ"), "ボタンで軽量モードをオフに")
	_hub.call("_close_sub_screen")
	await _frames(2)

	# 軽量モードのオフ：閉じても残す
	await _open("records")
	records = _hub.get("_records_view")
	_hub.call("_close_sub_screen")
	await _frames(2)
	_check(is_instance_valid(records) and _hub.get("_views").has("records"),
		"軽量モードのオフ：閉じても記録室を残す")
	_check(is_instance_valid(save) and _hub.get("_views").has("system"), "軽量モードのオフ：システムも残す")
	_lite.set_on(false)
	print("\n%s" % ("全項目OK" if _failures == 0 else "NG %d件" % _failures))
	quit(1 if _failures > 0 else 0)


func _picks_text(picks: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in picks:
		var list: Variant = picks[key]
		if not list is Array:
			continue
		for r: Variant in list:
			if r is Dictionary:
				var c: Dictionary = (r as Dictionary).get("career", {})
				var e: Dictionary = (r as Dictionary).get("entry", {})
				parts.append("%s:%s:%d:%d" % [e.get("name", (r as Dictionary).get("id", "")), (r as Dictionary).get("rank", ""),
					int(c.get("b", {}).get("g", 0)), int(c.get("p", {}).get("g", 0))])
	return ",".join(PackedStringArray(parts))


## 2つの字（Medium・ExtraBold）の字の画像の枚数
func _glyph_textures() -> int:
	var n := 0
	for bold: bool in [false, true]:
		var f: Font = _theme.font(700 if bold else 400)
		if f is FontFile:
			var ff := f as FontFile
			for i in ff.get_cache_count():
				for sz: Vector2i in ff.get_size_cache_list(i):
					n += ff.get_texture_count(i, sz)
	return n


func _count(cls: String) -> int:
	return _count_in(_hub, cls)


func _count_in(node: Node, cls: String) -> int:
	var n := 1 if node.get_script() != null and node.get_script().get_global_name() == cls else 0
	for c in node.get_children():
		n += _count_in(c, cls)
	return n


func _open(key: String) -> void:
	_hub.call("_open_sub_screen", key)
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["OK" if ok else "NG", label])
	if not ok:
		_failures += 1
