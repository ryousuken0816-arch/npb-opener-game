extends SceneTree
## メジャー志望の選手の指名と説得（docs/AUTORUN.md 作業26。ヘッドレスで数分）：
##   1) 成功率：強行指名の基本は10%前後、約束（3〜6年）で +30%前後、★の段階
##   2) 2026年（巨人）：織田翔希を1位で指名 → ドラフト会議が終わっても説得が済むまで入団の処理を待つ →
##      約束なしで失敗 → 入団せずメジャーへ（ゲームの NPB にいない・出来事に残る）
##   3) 2026年（巨人）：約束（3年）ありで成功 → 入団し、約束の年のオフにポスティングでメジャーへ
##   4) 2025年（DeNA）：佐々木麟太郎（海外の大学。期限は翌年7月末）も同じ交渉になり、成功すると入団する
##   5) CPU球団は史実で強行指名した球団以外はふだん避ける（メジャー志望の候補の評価が下がる）
##   6) 作業57：画面で進める（2026年・巨人）。手帳に「メジャー志望」の札、絞り込み「未指名」・「残りをおまかせで終える」でも
##      ドラフトのあと織田のページで説得へ（勝手に入団しない）、ハブの可変ボタンも説得へ戻る。
##      ①「説得する」で成功 ②説得しないまま次の段階へ進むと期限切れで渡米（出来事に残る）。オフの新しい順番で春季キャンプまで
##   7) 作業57：2028年の架空の候補でメジャー志望を表明した選手（FictionalDraft._mark_mlb_intent。表明は年0〜2人で無い年が多いので、
##      無ければ評価 S・A の候補に同じ形で付ける）を2位で指名 → 同じ説得の待ちになり、手帳に説得のページ。
##      ドラフトのあとの状態を覚えておき、①説得して成功 ②説得して失敗 ③説得しないまま次へ（期限切れ）の3通りを確かめる
##
##   godot --headless --path godot --script res://tests/mlb_draftee_check.gd
##
## すべて OK なら "ALL OK"、1つでも NG があれば "FAILED" を出して終了コード 1。

var _failures := 0
var _gs: Node
var _gd: Node
var _ds: GDScript
var _mp: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_ds = load("res://sim/draft.gd")
	_mp = load("res://sim/mlb_persuasion.gd")
	_check_chance()
	_check_oda(false)
	_check_oda(true)
	_check_rintaro()
	await _check_ui(true)
	await _check_ui(false)
	await _check_fictional()
	print("ALL OK" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_chance() -> void:
	print("== 成功率 ==")
	var first := {"round": 1, "ikusei": false}
	var base: float = _mp.chance(first, 0)
	_check(base >= 0.08 and base <= 0.15, "1位の強行指名・約束なし：%d%%" % roundi(base * 100))
	var promised: float = _mp.chance(first, 4)
	_check(promised - base >= 0.25 and promised - base <= 0.35, "4年後のポスティングの約束で +%d%%" % roundi(
		(promised - base) * 100))
	_check(_mp.chance(first, 3) > _mp.chance(first, 6), "短い約束ほど成功しやすい")
	_check(_mp.chance({"round": 9, "ikusei": false}, 0) < base, "下位指名は1位より少し低い")
	_check(_mp.stars(base) <= 2 and _mp.stars(promised) >= 4, "★：約束なし %d・約束あり %d" % [
		_mp.stars(base), _mp.stars(promised)])


## 2026年の織田翔希を巨人で1位指名して説得する。success：約束（3年）ありで成功させる／約束なしで失敗させる
func _check_oda(success: bool) -> void:
	var user := "読売ジャイアンツ"
	print("== 2026年 織田翔希（%s） ==" % ("約束あり・成功" if success else "約束なし・失敗"))
	var d: RefCounted = null
	var oda := ""
	for attempt in 4:
		_gs.new_game(user, 2026)
		_gs.skip_to_phase(_gs.Phase.DRAFT)
		d = _gs.draft()
		if d == null:
			break
		oda = _find(d, "織田 翔希")
		d.user_bid(oda)
		d.run_first_wave()
		if d.first_pick_of(user) == oda:
			break
	_check(d != null and not oda.is_empty() and d.by_id[oda]["mlb_intent"], "織田翔希はメジャー志望の候補")
	if d == null or d.first_pick_of(user) != oda:
		_check(false, "織田翔希を1位で獲得できない（抽選に4回外れた）")
		return
	_check(_mp.deadline_text(d.year, d.by_id[oda]["mlb_overseas"]) == "2027年3月末", "交渉期限は翌年3月末")
	d.auto_complete()
	_gs.draft_sync()
	_check(d.stage == _ds.Stage["DONE"] and not d.resolved and oda in d.pending_talks(),
		"ドラフト会議が終わっても、説得が済むまで入団の処理を待つ")
	d.force_roll = 0.2
	var promise := 3 if success else 0
	var result: Dictionary = d.persuade(oda, promise)
	_check(result["ok"] == success, "説得：%s" % result["text"])
	_check(not d.persuade(oda, 6)["ok"] or success, "説得は1人1回")
	_gs.draft_sync()
	_check(d.resolved, "説得のあとで入団の処理")
	var league: RefCounted = _gs.league
	if not success:
		_check(not league.team_of.has(oda), "失敗：入団しない")
		var logged := false
		for e: Dictionary in league.log:
			if e["kind"] == "mlb_draftee" and e["id"] == oda:
				logged = true
		_check(logged, "失敗：出来事に「メジャーへ挑戦」が残る")
		_to_camp()
		_check(_gs.year == 2027 and not league.team_of.has(oda), "2027年の春季キャンプでも NPB にいない")
		return
	_check(league.team_of.get(oda, "") == user, "成功：巨人に入団")
	_check(int(league.posting_promise.get(oda, 0)) == 2029, "約束：2029年のオフにポスティング")
	var leaving: Array = league.depart_mlb(2029)
	var left := false
	for l: Dictionary in leaving:
		if l["id"] == oda:
			left = true
	_check(left and not league.team_of.has(oda) and league.in_mlb.has(oda), "約束の年のオフにポスティングでメジャーへ")


func _check_rintaro() -> void:
	var user := "横浜DeNAベイスターズ"
	print("== 2025年 佐々木麟太郎（%s） ==" % user)
	var d: RefCounted = null
	var rin := ""
	for attempt in 4:
		_gs.new_game(user, 2025)
		_gs.skip_to_phase(_gs.Phase.DRAFT)
		d = _gs.draft()
		if d == null:
			break
		rin = _find(d, "佐々木 麟太郎")
		d.user_bid(rin)
		d.run_first_wave()
		if d.first_pick_of(user) == rin:
			break
	_check(d != null and not rin.is_empty() and d.by_id[rin]["mlb_intent"], "佐々木麟太郎はメジャー志望の候補")
	if d == null or d.first_pick_of(user) != rin:
		_check(false, "佐々木麟太郎を1位で獲得できない（抽選に4回外れた）")
		return
	_check(_mp.deadline_text(d.year, d.by_id[rin]["mlb_overseas"]) == "2026年7月末",
		"海外の大学に在学：交渉期限は翌年7月末")
	# CPU球団の評価：史実で指名したソフトバンク以外はメジャー志望で評価が下がる
	var c: Dictionary = d.by_id[rin]
	var other := "阪神タイガース"
	var plain := c.duplicate()
	plain["mlb_intent"] = false
	_check(d.evaluate(other, c, true) < d.evaluate(other, plain, true) or d._team_dare[other].has(rin),
		"CPU球団（阪神）はメジャー志望の候補を避ける")
	d.auto_complete()
	_gs.draft_sync()
	d.force_roll = 0.0
	var result: Dictionary = d.persuade(rin, 4)
	_check(result["ok"], "約束ありで説得：%s" % result["text"])
	_gs.draft_sync()
	_check(_gs.league.team_of.get(rin, "") == user, "成功：DeNA に入団")
	_to_camp()
	_check(_gs.year == 2026 and _gs.league.team_of.get(rin, "") == user and not _gd.call("player", rin).is_empty(),
		"2026年の春季キャンプで DeNA にいる（能力値データあり）")


## オフの残りの段階を進めて春季キャンプへ（作業54でドラフトのあとに FA・現役ドラフトが来るようになった）
func _to_camp() -> void:
	var guard := 0
	while _gs.phase != _gs.Phase.CAMP and guard < 10:
		guard += 1
		_gs.advance()


## 作業57：画面（ハブ・ドラフトの手帳）で進める。talk＝「説得する」を押す（false なら押さずに次の段階へ進む）
func _check_ui(talk: bool) -> void:
	var user := "読売ジャイアンツ"
	print("== 画面で進める 2026年 織田翔希（%s） ==" % ("説得する" if talk else "説得しないまま次へ"))
	var d: RefCounted = null
	var oda := ""
	for attempt in 4:
		_gs.new_game(user, 2026)
		_gs.skip_to_phase(_gs.Phase.DRAFT)
		d = _gs.draft()
		oda = _find(d, "織田 翔希")
		d.user_bid(oda)
		d.run_first_wave()
		if d.first_pick_of(user) == oda:
			break
	if d == null or d.first_pick_of(user) != oda:
		_check(false, "織田翔希を1位で獲得できない（抽選に4回外れた）")
		return
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub: Node = current_scene
	hub.call("_open_sub_screen", "draft")
	await _frames(4)
	var view: Node = hub.get("_draft_view")
	view.call("finish_overlays")
	var traits: Array = load("res://sim/scout_notes.gd").traits(d, d.by_id[oda])
	_check(not traits.is_empty() and traits[0]["text"] == "メジャー志望", "手帳の札の先頭に「メジャー志望」（%s）"
		% (traits[0]["text"] if not traits.is_empty() else "なし"))
	view.call("set_filter", "left")
	view.call("_on_complete_pressed")  # 残りをおまかせで終える
	view.call("finish_overlays")
	await _frames(4)
	_check(d.stage == _ds.Stage["DONE"] and not d.resolved and oda in d.pending_talks()
		and not _gs.league.team_of.has(oda), "「残りをおまかせで終える」でも勝手に入団・渡米しない（説得待ち）")
	var nb: Control = view.call("notebook")
	var go: Button = nb.call("go_button")
	_check(view.call("mode") == "book" and view.call("selected_id") == oda and nb.is_visible_in_tree(),
		"絞り込み「未指名」でも手帳に織田のページ（%s）" % d.by_id.get(view.call("selected_id"), {}).get("name", "?"))
	_check(go.text.begins_with("説得する") and not go.disabled, "ページのボタンが「%s」" % go.text)
	_check((view.get("_complete_button") as Button).disabled, "説得が残っている間は「残りをおまかせで終える」は押せない")
	hub.call("_close_sub_screen")
	await _frames(2)
	hub.call("_on_menu_chosen", "advance")  # ハブの可変ボタン
	await _frames(4)
	_check(hub.get("_open_key") == "draft" and not d.resolved and _gs.phase == _gs.Phase.DRAFT,
		"ハブの可変ボタンはドラフト（説得）へ戻る（%s）" % hub.get("_open_key"))
	var league: RefCounted = _gs.league
	if talk:
		d.force_roll = 0.0
		nb.emit_signal("go_pressed")
		await _frames(4)
		_check(d.talks.has(oda) and d.talks[oda]["ok"] and d.resolved and league.team_of.get(oda, "") == user,
			"「説得する」で成功して入団（%s）" % str(d.talks.get(oda, {})))
		_check(nb.get("_state_label").text.contains("成功"), "手帳に説得の結果（%s）" % nb.get("_state_label").text)
	else:
		hub.call("_close_sub_screen")
		_gs.advance()  # 説得しないまま次の段階へ
		_check(d.resolved and d.talks.get(oda, {}).get("expired", false) and not league.team_of.has(oda),
			"説得しないまま次へ進むと期限切れで入団しない（%s）" % str(d.talks.get(oda, {})))
		var logged := ""
		for e: Dictionary in league.log:
			if e["kind"] == "mlb_draftee" and e["id"] == oda:
				logged = str(e.get("text", e))
		_check(logged.contains("期限が切れ"), "出来事に「期限が切れ、メジャーへ挑戦」（%s）" % logged)
	_to_camp()
	_check(_gs.year == 2027 and _gs.phase == _gs.Phase.CAMP and league.team_of.has(oda) == talk,
		"オフの新しい順番で2027年の春季キャンプへ（織田は%s）" % ("巨人" if league.team_of.has(oda) else "NPB にいない"))


## 作業57：2028年の架空の候補のメジャー志望
func _check_fictional() -> void:
	var user := "阪神タイガース"
	print("== 2028年 架空の候補のメジャー志望（%s） ==" % user)
	_gs.new_game(user, 2027)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	_gs.draft_resolve()
	_to_camp()
	_gs.advance()  # 2028年の開幕
	var klass: Array = _gs.draft_class(2028)
	var stated: Array = []
	for p: Dictionary in klass:
		var mi: Variant = p["amateur"].get("mlb_intent")
		if mi is Dictionary and bool(mi.get("stated", false)):
			stated.append(p["name"])
	var marked := false
	if stated.is_empty():
		for p: Dictionary in klass:
			if p["amateur"]["grade"] in ["S", "A"]:
				p["amateur"]["mlb_intent"] = {"stated": true, "note": "%sの%s、高校・大学からのメジャー挑戦を表明" % [
					p["amateur"]["school"], p["name"]]}
				stated.append(p["name"])
				marked = true
				break
	print("  2028年の架空の候補のメジャー志望：%s%s" % [", ".join(stated), "（この年は表明が無いので付けた）" if marked else ""])
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	var d: RefCounted = _gs.draft()
	var target := ""
	for c: Dictionary in d.candidates:
		if c.get("fictional", false) and c.get("mlb_intent", false):
			target = c["id"]
	_check(d != null and d.year == 2028 and not target.is_empty(), "2028年のドラフトの候補に架空のメジャー志望（%s）"
		% d.by_id.get(target, {}).get("name", "なし"))
	if target.is_empty():
		return
	# 1位は別の候補（抽選を避ける）、2位でメジャー志望の候補を指名（CPU はふだん避けるので残っていることが多い）
	var first := ""
	for c: Dictionary in d.candidates:
		if c["id"] != target and not c.get("mlb_intent", false):
			if first.is_empty() or float(c["hyouka"]) > float(d.by_id[first]["hyouka"]):
				first = c["id"]
	d.user_bid(first)
	var guard := 0
	while d.stage == _ds.Stage["FIRST"] and guard < 10:
		guard += 1
		if d.first_pick_of(user).is_empty() and not d.bids.has(user):
			for c: Dictionary in d.remaining():
				if c["id"] != target and not c.get("mlb_intent", false):
					d.user_bid(c["id"])
					break
		d.run_first_wave()
	d.run_until_user()
	var error: String = d.user_pick(target) if str(d.by_id[target]["picked_by"]).is_empty() else "ほかの球団が指名"
	_check(error.is_empty() and d.pick_of(target).get("team", "") == user, "架空のメジャー志望の候補を%sで指名（%s）"
		% [d.pick_of(target).get("label", "-"), error if not error.is_empty() else d.by_id[target]["name"]])
	if not error.is_empty():
		return
	d.auto_complete()
	_gs.draft_sync()
	_check(d.stage == _ds.Stage["DONE"] and not d.resolved and target in d.pending_talks()
		and not _gs.league.team_of.has(target), "ドラフトのあと説得の待ち（勝手に入団・渡米しない）")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_gs.to_save()))
	# 画面：手帳に説得のページ
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub: Node = current_scene
	hub.call("_open_sub_screen", "draft")
	await _frames(4)
	var view: Node = hub.get("_draft_view")
	view.call("finish_overlays")
	await _frames(2)
	var go: Button = (view.call("notebook") as Control).call("go_button")
	_check(view.call("selected_id") == target and go.text.begins_with("説得する") and not go.disabled,
		"手帳に架空の候補の説得のページ（%s）" % go.text)
	hub.call("_close_sub_screen")
	for outcome: String in ["成功", "失敗", "期限切れ"]:
		_gs.load_state(JSON.parse_string(JSON.stringify(saved)))
		var d2: RefCounted = _gs.draft()
		var league: RefCounted = _gs.league
		if outcome == "期限切れ":
			_gs.advance()
		else:
			d2.force_roll = 0.0 if outcome == "成功" else 0.99
			d2.persuade(target, 3)
			_gs.draft_sync()
		var talk: Dictionary = d2.talks.get(target, {})
		var joined: bool = league.team_of.get(target, "") == user
		var ok: bool = d2.resolved and joined == (outcome == "成功") \
			and bool(talk.get("expired", false)) == (outcome == "期限切れ")
		_check(ok, "%s：%s（%s）" % [outcome, "入団" if joined else "入団しない（渡米）", str(talk)])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _find(d: RefCounted, name: String) -> String:
	for c: Dictionary in d.candidates:
		if c["name"] == name:
			return c["id"]
	return ""


func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["OK" if ok else "NG", label])
	if not ok:
		_failures += 1
