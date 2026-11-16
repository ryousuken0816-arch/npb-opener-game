extends SceneTree
## 成長が見える（docs/AUTORUN.md 作業83。GrowthDiff）の確認。ヘッドレスで約1分。
## - 前の年の開幕時点の写しが無いとき（新しく始めた年）は、前の年の能力値から作る。差は能力値ファイルの差と同じ
## - 開幕時点の能力値を続けて読むと、前の年の写しが回る（GameData.load_ratings）。セーブに入り、読み直すと戻る
## - 選手詳細（野手の能力・投手の選手能力・投手能力）に「↑差」が出る。日付を進めても今の値と比べる
## - 春季キャンプのニュース：この1年でいちばん伸びた選手（野手・投手）、覚醒した若手
##
##   godot --headless --path godot -s res://tests/growth_diff_check.gd

const DETAIL := "res://scenes/player_detail/player_detail.gd"
const TEAM := "読売ジャイアンツ"
## GrowthDiff は GameData（自動読み込み）を使うので、テストのスクリプトからは読み込んで呼ぶ
var _diff: GDScript = load("res://sim/growth_diff.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gs: Node = root.get_node("GameState")
	var gd: Node = root.get_node("GameData")
	gs.new_game(TEAM, 2026)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(8)
	var hub: Node = current_scene
	_check("新しく始めた年は写しの前の年が無い", int(gd.growth_prev.get("year", -1)) != 2025, str(gd.growth_prev.get("year")))

	# 前の年（2025年の開幕前）の能力値ファイルと比べる
	var before: Dictionary = gd.peek_ratings(2025, "pre", false)
	var by_id := {}
	for p: Dictionary in before.get("players", []):
		by_id[p["id"]] = p
	var batter := ""
	var pitcher := ""
	var expect := 0
	for p: Dictionary in gd.players_of(TEAM):
		var q: Dictionary = by_id.get(p["id"], {})
		if q.is_empty():
			continue
		if not bool(p.get("is_pitcher", false)) and batter.is_empty():
			var d := int(p["batting"]["ratings"]["power"]["value"]) - int(q["batting"]["ratings"]["power"]["value"])
			if d > 0:
				batter = p["id"]
				expect = d
		elif bool(p.get("is_pitcher", false)) and pitcher.is_empty() and p["pitching"]["ratings"].get("bb9") is Dictionary:
			var d2 := int(p["pitching"]["ratings"]["bb9"]["value"]) - int(q["pitching"]["ratings"]["bb9"]["value"])
			if d2 > 0:
				pitcher = p["id"]
	_check("パワーが上がった野手がいる", not batter.is_empty(), batter)
	_check("制球が上がった投手がいる", not pitcher.is_empty(), pitcher)
	var t0 := Time.get_ticks_msec()
	var got: Variant = _diff.delta(gd.player(batter), "b", "power")
	print("  前の年の写しを作る %dミリ秒" % (Time.get_ticks_msec() - t0))
	_check("前の年の写しを能力値ファイルから作る", int(gd.growth_prev.get("year", -1)) == 2025 and gd.growth_prev["values"].size() > 500,
		"%s年 %d人" % [gd.growth_prev.get("year"), gd.growth_prev.get("values", {}).size()])
	_check("差は能力値ファイルの差と同じ（パワー +%d）" % expect, got != null and int(got) == expect, str(got))

	# 選手詳細：野手
	var detail: Node = load(DETAIL).open(hub, batter)
	await _frames(3)
	var ups := _growth_texts(detail)
	print("  野手 %s：%s" % [gd.player(batter)["name"], ups])
	_check("野手の能力に「↑」が出る", ups.any(func(t: String) -> bool: return t.begins_with("↑")), str(ups))
	_check("パワーの行に ↑%d" % expect, ups.has("↑%d" % expect), str(ups))
	detail.call("close")
	await _frames(2)

	# 選手詳細：投手（投手能力＝最初の画面、選手能力）
	detail = load(DETAIL).open(hub, pitcher)
	await _frames(3)
	var pups := _growth_texts(detail)
	print("  投手 %s：%s（%s）" % [gd.player(pitcher)["name"], pups, _caption(detail)])
	_check("投手能力に「↑」が出る", pups.any(func(t: String) -> bool: return t.begins_with("↑")), str(pups))
	await _press(detail, "Sub_player")
	var pups2 := _growth_texts(detail)
	_check("投手の選手能力にも「↑」", pups2.any(func(t: String) -> bool: return t.begins_with("↑")), str(pups2))
	detail.call("close")
	await _frames(2)

	# 日付を進める：シーズン中に混ぜた能力（SeasonBlend）も今の値として比べる
	gs.start_fast_forward(gs.day + 40)
	while gs.is_fast_forwarding():
		await process_frame
	await _frames(3)
	var now := int(gd.player(batter)["batting"]["ratings"]["power"]["value"])
	var prev_v := int(by_id[batter]["batting"]["ratings"]["power"]["value"])
	var got2: Variant = _diff.delta(gd.player(batter), "b", "power")
	_check("日付を進めても今の値と前の年を比べる（%d → %d）" % [prev_v, now], got2 != null and int(got2) == now - prev_v, str(got2))
	detail = load(DETAIL).open(hub, batter)
	await _frames(3)
	var ups3 := _growth_texts(detail)
	_check("日付を進めた後の画面も今の差", now == prev_v or ups3.has("%s%d" % ["↑" if now > prev_v else "↓", absi(now - prev_v)]), str(ups3))
	detail.call("close")
	await _frames(2)

	# 春季キャンプのニュース
	var arts: Array = _diff.camp_articles(2026, gs.league.team_of, TEAM)
	for a: Dictionary in arts:
		print("  記事：%s　%s" % [a["headline"], a["body"]])
	_check("いちばん伸びた選手の記事", not arts.is_empty() and str(arts[0]["headline"]).begins_with("この1年でいちばん伸びたのは"),
		str(arts.size()))
	var awaken := arts.filter(func(a: Dictionary) -> bool: return str(a["headline"]).ends_with("覚醒の1年"))
	_check("覚醒の記事は多すぎない（%d本）" % awaken.size(), awaken.size() <= 4, "")

	# セーブ：写しが入り、読み直すと戻る
	var d: Dictionary = gs.to_save()
	_check("セーブに前の年の写しが入る", d.get("growth_prev") is Dictionary and int(d["growth_prev"].get("year", -1)) == 2025, "")
	var size := JSON.stringify(d.get("growth_prev")).length()
	print("  写しの大きさ %dKB" % (size / 1024))
	gd.reset_growth(JSON.parse_string(JSON.stringify(d["growth_prev"])))
	_check("読み直すと写しが戻る", int(gd.growth_prev.get("year", -1)) == 2025 and gd.growth_prev["values"].size() > 500, "")

	# 開幕時点を続けて読むと前の年の写しが回る（春季キャンプで新しい年を読むときと同じ）
	gd.reset_growth()
	gd.load_ratings(2025, "pre")
	gd.load_ratings(2026, "pre")
	_check("開幕時点を続けて読むと前の年の写しが回る", int(gd.growth_prev.get("year", -1)) == 2025, str(gd.growth_prev.get("year")))
	var got3: Variant = _diff.delta(gd.player(batter), "b", "power")
	_check("回した写しでも差は同じ", got3 != null and int(got3) == expect, str(got3))
	_finish()


func _growth_texts(node: Node) -> Array:
	var out: Array = []
	for n: Node in node.find_children("Growth", "Label", true, false):
		if not (n as Label).text.is_empty():
			out.append((n as Label).text)
	return out


func _caption(detail: Node) -> String:
	var n: Node = detail.find_child("BestPitch", true, false)
	return (n as Label).text if n != null else ""


func _press(detail: Node, node_name: String) -> void:
	var b: Node = detail.find_child(node_name, true, false)
	if b is Button:
		(b as Button).pressed.emit()
	await _frames(3)


func _check(label: String, ok: bool, detail: String) -> void:
	print("  %s  %s%s" % ["OK" if ok else "NG", label, "（%s）" % detail if not detail.is_empty() and not ok else ""])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _finish() -> void:
	print("ALL OK" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(1 if _failures > 0 else 0)
