extends SceneTree
## ドラフトのあと先へ進める（docs/AUTORUN.md 作業65）の確認。ヘッドレス、数分。
## 2026年（巨人）のドラフトを画面で最後まで進め（自球団の番は「選択終了」、ほかは「自球団の番まで飛ばす」）、
## 可変ボタン（パソコンはハブのボタン、スマホは下の帯の「▶」）だけで FA → 現役ドラフト → 春季キャンプ → 2027年の開幕まで進める。
##   - パソコン（1280x720）と Web（環境変数 NPB_SIM_WEB=1 でスマホの配置。横 844x390・縦 390x844）
##   - メジャー志望の織田翔希を1位で指名した場合：ドラフトのあと可変ボタンは「説得の交渉へ」、押すと手帳の説得のページ。
##     「説得する」のボタンと「説得せずに次へ」が画面の中に見えて押せる。説得して成功・説得せずに次へ（期限切れで渡米）の両方
##   - 指名しない場合：ドラフトのあと、ドラフトの画面の下の帯に「次へ」のボタンがあり、押すと FA の画面
##   - 先へ進むボタン（可変ボタン・ドラフトの「次へ」・FA の「締め切る」）がどの段階でも画面の中に見えて押せる
##
##   godot --headless --path godot -s res://tests/draft_after_flow_check.gd

const USER := "読売ジャイアンツ"
const CASES := [
	{"name": "パソコン・織田を指名・説得する", "layout": "pc", "mlb": true, "talk": true},
	{"name": "パソコン・メジャー志望なし", "layout": "pc", "mlb": false, "talk": false},
	{"name": "Web 縦・織田を指名・説得せずに次へ", "layout": "portrait", "mlb": true, "talk": false},
	{"name": "Web 横・メジャー志望なし", "layout": "landscape", "mlb": false, "talk": false},
]

var _failures := 0
var _gs: Node
var _ds: GDScript
var _ui: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_ui = root.get_node("UiLayout")
	_ds = load("res://sim/draft.gd")
	for c: Dictionary in CASES:
		await _check_case(c)
	_set_layout("pc")
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _set_layout(layout: String) -> void:
	OS.set_environment("NPB_SIM_WEB", "0" if layout == "pc" else "1")
	match layout:
		"portrait":
			root.size = Vector2i(390, 844)
			_ui.call("set_force_mode", "mobile")
		"landscape":
			root.size = Vector2i(844, 390)
			_ui.call("set_force_mode", "mobile")
		_:
			root.size = Vector2i(1280, 720)
			_ui.call("set_force_mode", "pc")


func _check_case(c: Dictionary) -> void:
	var tag: String = c["name"]
	print("\n== %s ==" % tag)
	var layout: String = c["layout"]
	_set_layout(layout)
	var mobile := layout != "pc"
	# 1位の入札（織田か、メジャー志望でない評価の一番高い候補）。織田は抽選に勝つまで種を変える
	var d: RefCounted = null
	var target := ""
	for attempt in 8:
		_ds.lottery_seed = 1 + attempt
		_gs.new_game(USER, 2026)
		_gs.skip_to_phase(_gs.Phase.DRAFT)
		d = _gs.draft()
		target = _pick_target(d, bool(c["mlb"]))
		d.user_bid(target)
		d.run_first_wave()
		if not c["mlb"] or d.first_pick_of(USER) == target:
			break
	if c["mlb"] and d.first_pick_of(USER) != target:
		_check(false, "%s：織田を1位で獲得できない" % tag)
		return
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(8)
	var hub: Node = current_scene
	_check(_ui.get("is_mobile") == mobile and _ui.get("is_portrait") == (layout == "portrait"),
		"%s：配置（スマホ %s・縦 %s）" % [tag, str(_ui.get("is_mobile")), str(_ui.get("is_portrait"))])
	await _press_advance(hub, tag)
	_check(hub.get("_open_key") == "draft", "%s：可変ボタンでドラフトの画面（%s）" % [tag, hub.get("_open_key")])
	var view: Node = hub.get("_draft_view")
	view.call("finish_overlays")
	var guard := 0
	while d.stage != _ds.Stage["DONE"] and guard < 300:
		guard += 1
		if d.stage == _ds.Stage["FIRST"] and d.first_pick_of(USER).is_empty():
			view.call("_on_auto_pick_pressed")  # 外れ1位の入札（おまかせ）
		elif d.stage == _ds.Stage["FIRST"]:
			view.call("_continue_first")
		elif d.is_user_turn():
			view.call("_on_finish_pressed")
		else:
			view.call("_on_skip_pressed")
		view.call("finish_overlays")
		await _frames(1)
	await _frames(4)
	_check(d.stage == _ds.Stage["DONE"], "%s：ドラフトが最後まで進む" % tag)
	var next: Button = view.call("next_button")
	if c["mlb"]:
		_check(d.pending_talks().has(target) and not d.resolved, "%s：織田の説得の待ち" % tag)
		_check(_gs.button_text() == "説得の交渉へ", "%s：可変ボタンは「説得の交渉へ」（%s）" % [tag, _gs.button_text()])
		var nb: Control = view.call("notebook")
		var go: Button = nb.call("go_button")
		if not _in_view(go):
			print("    " + _chain(go))
		_check(view.call("selected_id") == target and go.text.begins_with("説得する") and _in_view(go),
			"%s：手帳の織田のページに「説得する」が見えて押せる（%s・%s）" % [tag, go.text, _rect_text(go)])
		_check(next.text.contains("説得せずに") and _in_view(next),
			"%s：「説得せずに次へ」が見えて押せる（%s・%s）" % [tag, next.text, _rect_text(next)])
		# 可変ボタンを押しても説得のページのまま（同じ画面を開き直すだけにならない）
		view.call("set_mode", "board" if layout == "portrait" else "table")
		await _frames(2)
		await _press_advance(hub, tag)
		_check(hub.get("_open_key") == "draft" and view.call("mode") == "book" and view.call("selected_id") == target
			and _in_view(go), "%s：可変ボタン「説得の交渉へ」で手帳の説得のページ（%s・%s）" % [tag, view.call("mode"), _rect_text(go)])
		if c["talk"]:
			d.force_roll = 0.0
			go.pressed.emit()
			await _frames(3)
			_check(d.resolved and _gs.league.team_of.get(target, "") == USER, "%s：説得して成功・入団" % tag)
		else:
			next.pressed.emit()
			await _frames(2)
			_check(not d.resolved and next.text.contains("もう一度"), "%s：1回目は確かめるだけ（%s）" % [tag, next.text])
			next.pressed.emit()
			await _frames(4)
			_check(d.resolved and d.talks.get(target, {}).get("expired", false) and not _gs.league.team_of.has(target),
				"%s：説得せずに次へで期限切れ・渡米" % tag)
			_check(_gs.phase == _gs.Phase.FA_TRADE and hub.get("_open_key") == "fa",
				"%s：そのまま FA の画面へ（%s・%s）" % [tag, _gs.PHASE_NAMES[_gs.phase], hub.get("_open_key")])
	else:
		_check(d.resolved, "%s：ドラフトのあと入団の処理まで済む" % tag)
	if _gs.phase == _gs.Phase.DRAFT:
		await _frames(2)
		_check(next.text.begins_with("次へ") and _in_view(next),
			"%s：ドラフトの画面に「次へ」が見えて押せる（%s・%s）" % [tag, next.text, _rect_text(next)])
		next.pressed.emit()
		await _frames(4)
		_check(_gs.phase == _gs.Phase.FA_TRADE and hub.get("_open_key") == "fa",
			"%s：「次へ」で FA の画面（%s・%s）" % [tag, _gs.PHASE_NAMES[_gs.phase], hub.get("_open_key")])
	# FA → 現役ドラフト → 春季キャンプ → 2027年の開幕（可変ボタンと FA の「締め切る」だけ）
	var seen: Array[String] = []
	guard = 0
	while not (_gs.year == 2027 and _gs.phase == _gs.Phase.SEASON) and guard < 20:
		guard += 1
		var name: String = _gs.PHASE_NAMES[_gs.phase]
		if seen.is_empty() or seen[-1] != name:
			seen.append(name)
		var key: String = hub.get("_open_key")
		if key == "fa":
			var close: Button = hub.get("_fa_view").get("_close_button")
			if _gs.fa_open():
				_check(_in_view(close), "%s：FA の「締め切る」が見えて押せる（%s）" % [tag, _rect_text(close)])
				close.pressed.emit()
				await _frames(2)
		elif not key.is_empty() and not mobile:
			hub.call("_close_sub_screen")
			await _frames(2)
		await _press_advance(hub, tag)
	seen.append("%d年 %s" % [_gs.year, _gs.PHASE_NAMES[_gs.phase]])
	print("  進んだ段階：%s" % " → ".join(seen))
	_check(_gs.year == 2027 and _gs.phase == _gs.Phase.SEASON and seen.has("FA・トレード・ポスティング")
		and seen.has("現役ドラフト") and seen.has("春季キャンプ"), "%s：FA → 現役ドラフト → 春季キャンプ → 2027年の開幕まで進む" % tag)
	if c["mlb"]:
		_check(_gs.league.team_of.has(target) == bool(c["talk"]), "%s：織田は%s" % [tag,
			"巨人" if _gs.league.team_of.has(target) else "NPB にいない"])


## 可変ボタンを押す：パソコンはハブのボタン（サブ画面を開いていれば先に戻る）、スマホは下の帯の「▶」。押す前に画面の中に見えるか
func _press_advance(hub: Node, tag: String) -> void:
	if _ui.get("is_mobile"):
		var nav: Node = hub.get("_nav")
		var adv: Button = nav.get("_advance")
		await _frames(1)
		_check(_in_view(adv, false), "%s：下の帯の「%s」が見えて押せる（%s）" % [tag, adv.text, _rect_text(adv)])
		nav.call("press", "advance")
	else:
		if not str(hub.get("_open_key")).is_empty():
			hub.call("_close_sub_screen")
			await _frames(2)
		var button: Control = hub.get("_buttons")["advance"]
		_check(button.is_visible_in_tree(), "%s：ハブの可変ボタンが見える" % tag)
		hub.call("_on_menu_chosen", "advance")
	await _frames(4)


## 押せて、画面の中（スマホの下の帯より上）に見えるか（横にはみ出すボタンは、見えている部分が押せる幅なら OK）
func _in_view(c: Control, above_nav := true) -> bool:
	if c == null or not c.is_visible_in_tree() or (c is BaseButton and (c as BaseButton).disabled):
		return false
	var r := c.get_global_rect()
	var view := c.get_viewport_rect().size
	var bottom := view.y - (float(_ui.call("bottom_inset")) if above_nav else 0.0)
	var shown := r.intersection(Rect2(0, 0, view.x, bottom))
	return r.size.x > 0 and shown.size.y >= r.size.y - 1 and shown.size.x >= minf(r.size.x, 80.0)


func _chain(c: Control) -> String:
	var parts: Array[String] = []
	var n: Node = c
	while n != null and n != root:
		if n is Control:
			var r := (n as Control).get_global_rect()
			parts.append("%s(%s) %d,%d %dx%d min%d" % [n.name, n.get_class(), r.position.x, r.position.y, r.size.x, r.size.y,
				(n as Control).get_combined_minimum_size().y])
		n = n.get_parent()
	return "
    ".join(parts)


func _rect_text(c: Control) -> String:
	if c == null:
		return "なし"
	var r := c.get_global_rect()
	return "%s %d,%d %dx%d／画面 %dx%d" % ["見える" if c.is_visible_in_tree() else "隠れている", r.position.x, r.position.y,
		r.size.x, r.size.y, c.get_viewport_rect().size.x, c.get_viewport_rect().size.y]


func _pick_target(d: RefCounted, mlb: bool) -> String:
	var best := ""
	for c: Dictionary in d.remaining():
		if mlb:
			if c["name"] == "織田 翔希":
				return c["id"]
			continue
		if c.get("mlb_intent", false) or bool(c.get("as_ikusei", false)):
			continue
		if best.is_empty() or float(c["hyouka"]) > float(d.by_id[best]["hyouka"]):
			best = c["id"]
	return best


func _check(ok: bool, label: String) -> void:
	print(("OK " if ok else "NG ") + label)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame
