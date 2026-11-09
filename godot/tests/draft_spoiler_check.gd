extends SceneTree
## ドラフトが終わる前に、史実の入団先が画面に出ないこと（docs/AUTORUN.md 作業81）。2008年（史実の年）で
## 候補を1人ずつ選び、表の右の要約・選手詳細の全タブの文字（札・ツールチップ込み）に「史実」と史実の入団先が無いこと。
## ドラフトが終わったあとは、要約に史実の入団先が出る（記録として見てよい）
##   godot --headless --path godot -s res://tests/draft_spoiler_check.gd

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TEAM := "読売ジャイアンツ"
## 調べる候補の数（先頭から。史実の入団先が球団ごとに違う候補が混ざる）
const SAMPLE := 10

var _failures := 0
var _gs: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gs.new_game(TEAM, 2008)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	change_scene_to_file(HUB_SCENE)
	await _frames(6)
	var hub: Node = current_scene
	hub.call("_open_sub_screen", "draft")
	await _settle()
	var view: Node = hub.get("_draft_view")
	view.call("finish_overlays")
	view.call("set_mode", "table")
	await _settle()
	var d: RefCounted = _gs.draft()
	var summary: Control = view.get("_summary_box")
	var detail_class: GDScript = load("res://scenes/player_detail/player_detail.gd")
	var tabs: Array = detail_class.get_script_constant_map()["TABS"]
	var teams := {}
	var checked := 0
	var per_team := {}
	for c: Dictionary in d.candidates:
		if checked >= SAMPLE:
			break
		var hist := str(c["hist_team"])
		if hist.is_empty() or int(per_team.get(hist, 0)) >= 2:
			continue  # 球団がばらけるように、1球団2人まで
		per_team[hist] = int(per_team.get(hist, 0)) + 1
		teams[hist] = true
		checked += 1
		view.set("_selected", "")
		view.call("select_candidate", c["id"])
		await _settle()
		var short: String = root.get_node("GameData").call("short_name", hist)
		var texts := _texts(summary)
		_check(not _has(texts, "史実"), "[%s] 要約に「史実」が出ない（ドラフトの最中）" % c["name"])
		_check(not _has(texts, short), "[%s] 要約に史実の入団先（%s）が出ない" % [c["name"], short])
		_check(_has(texts, "実在の選手"), "[%s] 要約に「実在の選手」と出る" % c["name"])
		# 選手詳細の全タブ
		var detail: Node = detail_class.call("open", view, c["id"], [c["id"]])
		_check(detail != null, "[%s] 選手詳細が開く" % c["name"])
		if detail != null:
			for i in tabs.size():
				detail.call("show_tab", i)
				await _frames(2)
				var dt := _texts(detail)
				_check(not _has(dt, "史実"), "[%s] 選手詳細（%s）に「史実」が出ない" % [c["name"], tabs[i][0]])
				_check(not _has(dt, short), "[%s] 選手詳細（%s）に史実の入団先（%s）が出ない" % [c["name"], tabs[i][0], short])
			detail.call("close")
			await _frames(2)
	_check(teams.size() >= 3, "調べた候補の史実の入団先が3球団以上にまたがる（%d球団）" % teams.size())

	# ドラフトが終わったあとは出る
	d.auto_complete()
	_gs.draft_sync()
	view.call("refresh")
	view.set("_selected", "")
	var after: Dictionary = {}
	for c: Dictionary in d.candidates:
		if not str(c["hist_team"]).is_empty() and not c.get("amateur", false):
			after = c
			break
	view.call("select_candidate", after["id"])
	await _settle()
	_check(_has(_texts(summary), "史実："), "ドラフトのあとは要約に史実の入団先が出る")
	print("\n%s" % ("全項目OK" if _failures == 0 else "NG %d件" % _failures))
	quit(1 if _failures > 0 else 0)


## 子孫の Label・Button・RichTextLabel の文字とツールチップを全部集める
func _texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	_collect(node, out)
	return out


func _collect(node: Node, out: Array[String]) -> void:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	elif node is RichTextLabel:
		out.append((node as RichTextLabel).get_parsed_text())
	if node is Control and not (node as Control).tooltip_text.is_empty():
		out.append((node as Control).tooltip_text)
	for child in node.get_children():
		_collect(child, out)


## 成績の画面の固定の説明文（「…より前は史実の1軍成績（npb.jp）…」）は成績の出典の説明で、入団先ではない
const SOURCE_NOTE := "史実の1軍成績（npb.jp）"


func _has(texts: Array[String], needle: String) -> bool:
	for t in texts:
		if t.contains(SOURCE_NOTE):
			continue
		if _contains_team(t, needle):
			print("   見つけた文字：", t.substr(0, 60))
			return true
	return false


## 球団名が入っているか。学校名の一部（広島商・日本大・東北高など）は除く
func _contains_team(text: String, team: String) -> bool:
	if team == "史実":
		return text.contains(team)
	var re := RegEx.create_from_string("%s(?![商高大学工農])" % team)
	return re.search(text) != null


func _check(ok: bool, label: String) -> void:
	print(("OK " if ok else "NG ") + label)
	if not ok:
		_failures += 1


func _settle() -> void:
	await create_timer(0.2).timeout
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
