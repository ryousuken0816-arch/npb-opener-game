extends SceneTree
## 起用設定（OrderPage）の操作の確認（ヘッドレス、数秒）。Antigravity が作り直した画面の点検用。
## 2008年の新しいゲームで OrderPage を直接開き、▲▼で打順を入れ替える・札から札で入れ替える・控えを入れる・
## 守備位置の入れ替え・DHあり／なし・自動で組む・守備充足インジケーターの表示を、ボタンを押して確かめる。
##
##   godot --headless --path godot -s res://tests/order_page_check.gd -- [球団名]

var _team := "阪神タイガース"
var _failures := 0
var _page: Control
var _gs: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_team = args[0]
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gs.new_game(_team)
	var mine: SimTeam = _gs.my_team()
	_check(mine != null, "自球団の編成がある")

	# クラスは自動読み込み（GameState など）が済んでから読む（スクリプトの先頭で型を書くと読み込み順で失敗する）
	_page = (load("res://scenes/hub/order_page.gd") as GDScript).new()
	_page.size = Vector2(1000, 600)
	root.add_child(_page)
	_page.setup((load("res://scripts/ui_theme.gd") as GDScript).neutral_palette())
	_page.refresh(true)
	await process_frame

	print("\n== ▲▼の打順入れ替え ==")
	var before := _names(mine, true)
	var downs := _buttons("▼")
	_check(downs.size() == before.size(), "▼が打順の数だけある（%d）" % downs.size())
	_check(not (downs[0] as Button).disabled and (downs[downs.size() - 1] as Button).disabled, "先頭の▼は押せて、最後の▼は押せない")
	(downs[0] as Button).pressed.emit()
	await process_frame
	var after := _names(mine, true)
	_check(after[0] == before[1] and after[1] == before[0], "▼で1番と2番が入れ替わった（%s／%s）" % [after[0], after[1]])
	var ups := _buttons("▲")
	_check((ups[0] as Button).disabled and not (ups[1] as Button).disabled, "先頭の▲は押せず、2番の▲は押せる")
	(ups[1] as Button).pressed.emit()
	await process_frame
	_check(_names(mine, true) == before, "▲で元の打順に戻った")

	print("\n== 札から札で入れ替え ==")
	var tags := _tags(_page._lineup_box)
	_check(tags.size() >= 9, "スタメンの札が9枚以上（%d）" % tags.size())
	tags[2].pressed.emit()
	await process_frame
	_check(_page._sel_index == 2, "札を選ぶと選択になる")
	_tags(_page._lineup_box)[5].pressed.emit()
	await process_frame
	var swapped := _names(mine, true)
	_check(swapped[2] == before[5] and swapped[5] == before[2], "3番と6番が入れ替わった")

	print("\n== 控えを打順に入れる ==")
	var bench_tags := _tags(_page._bench_grid)
	_check(bench_tags.size() > 0, "控えの札がある（%d）" % bench_tags.size())
	if bench_tags.size() > 0:
		bench_tags[0].pressed.emit()
		await process_frame
		var picked: SimPlayer = _page._sel_bench
		_check(picked != null, "控えの札を選ぶと選択になる")
		var target := -1
		var order := mine.lineup(true)
		for i in order.size():
			if order[i][0] != null:
				target = i
				break
		_tags(_page._lineup_box)[target].pressed.emit()
		await process_frame
		_check(mine.lineup(true)[target][0] == picked, "控えがその打順に入った（%s）" % picked.name)

	print("\n== 守備充足インジケーター ==")
	_check(_page._coverage_box.get_child_count() > 0, "インジケーターが出ている（%d個）" % _page._coverage_box.get_child_count())

	print("\n== DHなし・自動で組む ==")
	_page._no_dh_button.button_pressed = true
	await process_frame
	_check(not _page._use_dh and _tags(_page._lineup_box).size() >= 9, "DHなしに切り替わった")
	_page._on_auto()
	await process_frame
	_check(mine.lineup(false)[0][0] != null or mine.lineup(false)[0][0] == null, "自動で組み直しても落ちない")
	_page._dh_button.button_pressed = true
	await process_frame
	_check(_page._use_dh, "DHありに戻せる")

	print("\n== 結果: %s ==" % ("OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _names(team: SimTeam, dh: bool) -> Array:
	var out := []
	for e: Array in team.lineup(dh):
		out.append(e[0].name if e[0] != null else "投手")
	return out


func _buttons(text: String) -> Array:
	var out := []
	_collect_buttons(_page._lineup_box, text, out)
	return out


func _collect_buttons(node: Node, text: String, out: Array) -> void:
	for c in node.get_children():
		if c is Button and (c as Button).text == text:
			out.append(c)
		_collect_buttons(c, text, out)


func _tags(box: Node) -> Array:
	var out := []
	_collect_tags(box, out)
	return out


func _collect_tags(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c.has_method("setup_player"):
			out.append(c)
		else:
			_collect_tags(c, out)


func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["OK" if ok else "NG", label])
	if not ok:
		_failures += 1
