extends SceneTree
## 投手能力の画面（PitcherBoard・PitchChart）。ヘッドレスで数十秒。
## 8方向の向き、5球種の投手、タブ（選手能力／野手能力／守備・起用／プロフィール）、
## 日付を進めると成績の行が変わること。
##
##   godot --headless --path godot --script res://tests/pitcher_board_check.gd

const DETAIL := "res://scenes/player_detail/player_detail.gd"
const CHART := "res://scenes/player_detail/pitch_chart.gd"
const TEAM := "読売ジャイアンツ"

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_directions()
	var gs: Node = root.get_node("GameState")
	gs.new_game(TEAM, 2026)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(8)
	var hub: Node = current_scene
	var gd: Node = root.get_node("GameData")
	var five := ""
	var two := ""
	var lefty := ""
	for team: String in gd.teams():
		for p: Dictionary in gd.players_of(team):
			if not p.get("is_pitcher", false):
				continue
			var ps: Variant = p.get("pitching", {}).get("pitches", [])
			if not ps is Array:
				continue
			if ps.size() >= 5 and five.is_empty():
				five = str(p["id"])
			if ps.size() == 2 and two.is_empty():
				two = str(p["id"])
			if str(p.get("throws", "")) == "左" and ps.size() >= 3 and lefty.is_empty():
				lefty = str(p["id"])
	_check("5球種の投手がいる", not five.is_empty(), five)
	_check("2球種の投手がいる", not two.is_empty(), two)
	_check("左投げで持ち球がある", not lefty.is_empty(), lefty)
	if five.is_empty():
		_finish()
		return
	var detail: Node = load(DETAIL).open(hub, five)
	await _frames(3)
	_check("投手能力を開く", detail != null and detail.find_child("PitcherBoard", true, false) != null, "")
	_check("球速", _has_label(detail, "球速"), "")
	_check("コントロール", _has_label(detail, "コントロール"), "")
	_check("スタミナ", _has_label(detail, "スタミナ"), "")
	_check("適性", _has_label(detail, "適性"), "")
	_check("フォーム", _has_label(detail, "フォーム"), "")
	_check("投打", _has_label(detail, "投打"), "")
	_check("決め球", _has_label(detail, "決め球"), "")
	var record := _season_text(detail)
	_check("成績の行", record.begins_with("防"), record)
	var chart: Node = detail.find_child("PitchChart", true, false)
	var rows: Array = chart.call("placed")
	var breaking := 0
	var straight_up := false
	for row: Dictionary in rows:
		if row.get("synthetic", false):
			straight_up = float(row["dy"]) < -0.7
		else:
			breaking += 1
	_check("5球種が図に出る", breaking >= 5, str(breaking))
	_check("ストレートは上", straight_up, "")
	var grid: Node = detail.find_child("AbilityGrid", true, false)
	_check("能力のマスが16", grid != null and grid.get_child_count() >= 16, str(grid.get_child_count()) if grid != null else "なし")
	_check("外側の経歴タブが残っている", _button(detail, "経歴") != null, "")

	await _press(detail, "Sub_bat")
	_check("野手能力にミート", _has_label(detail, "ミート"), "")
	await _press(detail, "Sub_use")
	_check("守備・起用に今季の起用", _has_label(detail, "今季の起用"), "")
	await _press(detail, "Sub_profile")
	_check("プロフィールに生年月日", _has_label(detail, "生年月日"), "")
	await _press(detail, "Sub_player")
	_check("選手能力に現在の能力", _has_label(detail, "現在の能力"), "")
	await _press(detail, "Sub_pitch")
	_check("投手能力に戻ると図がある", detail.find_child("PitchChart", true, false) != null, "")

	if not two.is_empty():
		detail = load(DETAIL).open(hub, two)
		await _frames(2)
		var n := 0
		for row: Dictionary in detail.find_child("PitchChart", true, false).call("placed"):
			if not row.get("synthetic", false):
				n += 1
		_check("2球種の図", n == 2, str(n))
	if not lefty.is_empty():
		detail = load(DETAIL).open(hub, lefty)
		await _frames(2)
		_check("左投げも図がある", detail.find_child("PitchChart", true, false) != null, "")
		var side := false
		var down := false
		for row: Dictionary in detail.find_child("PitchChart", true, false).call("placed"):
			if row.get("synthetic", false):
				continue
			side = side or absf(float(row["dx"])) > 0.5
			down = down or float(row["dy"]) > 0.5
		_check("左投げの球が左右か下に分かれる", side or down, "")

	var ace: String = gs.my_team().rotation[0].id
	detail = load(DETAIL).open(hub, ace)
	await _frames(2)
	var before := _season_text(detail)
	gs.start_fast_forward(gs.day + 21)
	while gs.is_fast_forwarding():
		await process_frame
	await _frames(3)
	var after := _season_text(detail)
	var g := int(gs.season.pitching.get(ace, {}).get("g", 0))
	_check("日付を進めると成績の行が変わる", g > 0 and after != before and after.begins_with("防")
		and not after.contains("--勝"), "%s → %s（%d登板）" % [before, after, g])
	detail.call("close")
	_finish()


func _directions() -> void:
	var chart: Node = load(CHART).new()
	chart.set_pitches([
		{"name": "スライダー", "move": 5}, {"name": "カットボール", "move": 4}, {"name": "カーブ", "move": 3},
		{"name": "シュート", "move": 2}, {"name": "ツーシーム", "move": 3}, {"name": "シンカー", "move": 4},
		{"name": "フォーク", "move": 6}, {"name": "チェンジアップ", "move": 5},
	], "フォーク", 163.0)
	var by := {}
	for row: Dictionary in chart.placed():
		by[str(row["name"])] = row
	_check("ストレートは上", float(by["ストレート"]["dy"]) < -0.7, _xy(by["ストレート"]))
	_check("スライダーは右", float(by["スライダー"]["dx"]) > 0.7, _xy(by["スライダー"]))
	_check("シュートは左", float(by["シュート"]["dx"]) < -0.7, _xy(by["シュート"]))
	_check("フォークは下", float(by["フォーク"]["dy"]) > 0.7, _xy(by["フォーク"]))
	_check("カーブは右下", float(by["カーブ"]["dx"]) > 0.3 and float(by["カーブ"]["dy"]) > 0.3, _xy(by["カーブ"]))
	_check("カットは右上", float(by["カットボール"]["dx"]) > 0.3 and float(by["カットボール"]["dy"]) < -0.3, _xy(by["カットボール"]))
	_check("シンカーは左下", float(by["シンカー"]["dx"]) < -0.3 and float(by["シンカー"]["dy"]) > 0.3, _xy(by["シンカー"]))
	_check("ツーシームは左上", float(by["ツーシーム"]["dx"]) < -0.3 and float(by["ツーシーム"]["dy"]) < -0.3, _xy(by["ツーシーム"]))
	_check("チェンジアップはシンカーとずれる", float(by["チェンジアップ"]["dy"]) > 0.2
		and absf(float(by["チェンジアップ"]["dx"]) - float(by["シンカー"]["dx"])) > 0.05, _xy(by["チェンジアップ"]))
	_check("決め球に印", bool(by["フォーク"]["best"]) and not bool(by["スライダー"]["best"]), "")
	_check("160km台のストレートは長め", int(by["ストレート"]["move"]) >= 6, str(by["ストレート"]["move"]))
	chart.free()


func _xy(row: Dictionary) -> String:
	return "(%.2f, %.2f)" % [float(row["dx"]), float(row["dy"])]


func _press(detail: Node, node_name: String) -> void:
	var b := detail.find_child(node_name, true, false) as BaseButton
	_check("タブ " + node_name, b != null, "")
	if b != null:
		b.pressed.emit()
	await _frames(3)


func _season_text(detail: Node) -> String:
	var label := detail.find_child("SeasonMain", true, false) as Label
	return label.text if label != null else ""


func _has_label(node: Node, text: String) -> bool:
	for label in node.find_children("*", "Label", true, false):
		if (label as Label).text.contains(text):
			return true
	for button in node.find_children("*", "Button", true, false):
		if (button as Button).text.contains(text):
			return true
	return false


func _button(node: Node, text: String) -> Button:
	for button in node.find_children("*", "Button", true, false):
		if (button as Button).text == text:
			return button
	return null


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s %s%s" % ["OK" if ok else "NG", label, "" if detail.is_empty() else "（%s）" % detail])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _finish() -> void:
	print("ALL OK" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(0 if _failures == 0 else 1)
