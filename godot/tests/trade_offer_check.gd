extends SceneTree
## トレードの打診の確認（docs/AUTORUN.md 作業87。ヘッドレス可、約1分半）。2008年の阪神で：
## - 打診の中身：両側にレギュラー級か伸びしろの大きい若手がいる・相手が損をしない（相手の目の比 1.0〜1.25）・
##   需要を掛けない目でも自球団が得をしすぎない。ニュースに出る・ハブの新戦力に印・返事の期限は数日（7月31日まで）
## - 日送りを止める：「試合へ」（ハブ）と日程表の早送りの途中で打診が届くと、その日で止めて打診の画面が開く
## - 返事：断る（所属は変わらない）・期限が過ぎたら流れる・受ける（所属・ペナントの編成・出来事・ニュース）・
##   条件を変える（案が入ったまま交渉の画面へ。同じ条件なら必ず成立して「条件を変えて成立」）
## - 8月1日からは打診が来ない。オフ（FA・トレード・ポスティング）の打診は段階が変わると流れる
## - セーブに残る（中身と期限）。作業87より前のセーブ（打診の項目が無い）も読める
## - 2008年は CPU球団どうしの打診の予定が無い（2026年から）。作れば両側に主力・有望な若手がいてニュースに出る
## - 年俸の見方：高年俸の主力が安く見えない（年俸の割高な分だけ引く）
## ウィンドウ付きで出力先を渡すと、打診の画面を1枚スクショ。
##
##   godot --headless --path godot -s res://tests/trade_offer_check.gd -- [出力先]

const USER := "阪神タイガース"

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node
var _hub: Node
var _view: Node
var _to: GDScript
var _trade: GDScript
var _save: GDScript


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_to = load("res://sim/trade_offers.gd")
	_trade = load("res://sim/trade.gd")
	_save = load("res://scripts/save_game.gd")
	_gs.new_game(USER, 2008)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	_hub = current_scene
	_view = _hub.get("_trade_view")
	_check_plan()
	_check_value()
	_gs.advance_through(_gs.day + 30)
	await _check_content()
	await _check_hub_stop()
	await _check_schedule_stop()
	await _check_decline()
	await _check_expire()
	await _check_accept()
	await _check_modify()
	await _check_save()
	_check_cpu()
	await _check_deadline()
	await _check_offseason()
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("OK ", label)
	else:
		_failures += 1
		print("NG ", label)


func _check_plan() -> void:
	print("== 予定 ==")
	var slots: Array = _gs.offer_plan.get("slots", [])
	var users := 0
	var cpus := 0
	for s: Dictionary in slots:
		if s["who"] == "user":
			users += 1
		else:
			cpus += 1
	_check(int(_gs.offer_plan.get("year", 0)) == 2008 and users <= 3 and cpus == 0,
		"2008年の予定：自球団への打診 %d件（0〜3件）・CPU球団どうし %d件（2025年度までは史実だけ）" % [users, cpus])
	# 年ごとの件数の分布（予定だけ。30年分）
	var counts := [0, 0, 0, 0]
	var cpu_counts := [0, 0, 0]
	for y in range(2008, 2038):
		var r := RandomNumberGenerator.new()
		r.seed = hash([y, "plan_check"])
		var plan: Dictionary = _to.make_plan(r, y, "%d-03-28" % y)
		var u := 0
		var c := 0
		for s: Dictionary in plan["slots"]:
			if s["who"] == "user":
				u += 1
			else:
				c += 1
		counts[u] += 1
		if y >= 2026:
			cpu_counts[c] += 1
	_check(counts[0] > 0 and counts[0] < 10 and counts[1] + counts[2] + counts[3] >= 20,
		"30年分の予定：自球団への打診 0件の年 %d・1件 %d・2件 %d・3件 %d" % counts)
	_check(cpu_counts[0] == 0 and cpu_counts[1] + cpu_counts[2] == 12,
		"2026年からの12年分：CPU球団どうし 1件の年 %d・2件 %d" % [cpu_counts[1], cpu_counts[2]])


func _check_value() -> void:
	print("== 年俸の見方 ==")
	# 12球団で年俸の高い働き盛り（32歳まで）の選手：前の見方（年俸の半分を引く）より高く、市場価値×年齢の係数の半分以上
	var best := ""
	for id: String in _gs.league.team_of:
		var age: int = load("res://sim/free_agency.gd").age_of(_gd.player(id), _gs.year)
		if age > 0 and age <= 32 and (best.is_empty() or _gs.league.salary_of(id) > _gs.league.salary_of(best)):
			best = id
	var p: Dictionary = _gd.player(best)
	var a: Array = load("res://sim/salary.gd").ability(p)
	var market: float = load("res://sim/salary.gd").market_value(a[0], maxf(a[1], 0.35), a[2])
	var age_f := 1.0
	var age2: int = load("res://sim/free_agency.gd").age_of(p, _gs.year)
	for f: Array in _trade.AGE_FACTORS:
		if age2 <= int(f[0]):
			age_f = float(f[1])
			break
	var v: float = _trade.player_value(p, _gs.year, _gs.league.salary_of(best))
	var old_v := maxf(market * age_f - 0.5 * _gs.league.salary_of(best), market * age_f * 0.15)
	_check(v > old_v and v >= market * age_f * 0.5,
		"年俸の高い働き盛り %s（%d歳・%s）：価値 %.0f万円（市場価値×年齢 %.0f、前の見方なら %.0f）" % [p.get("name"),
			age2, _salary_text(_gs.league.salary_of(best)), v, market * age_f, old_v])


## 打診の中身（強制的に作る）
func _check_content() -> void:
	print("== 打診の中身 ==")
	var o := _make_offer()
	if o.is_empty():
		_check(false, "打診が作れる")
		return
	var m: RefCounted = _gs.call("_offer_maker", "check")
	var give_key := false
	var get_key := false
	for id: String in o["give"]:
		give_key = give_key or m.is_key(id)
	for id: String in o["get"]:
		get_key = get_key or m.is_key(id)
	_check(give_key and get_key, "両側にレギュラー級か有望な若手：出す %s／受け取る %s（%s）" % [o["give_text"],
		o["get_text"], o["kind"]])
	var e: Dictionary = m.measure(o["partner"], USER, o["give"], o["get"], int(o["money"]))
	_check(float(e["ratio"]) >= 1.0 and float(e["ratio"]) <= 1.25,
		"相手が損をしない：相手の目の比 %.2f（1.0〜1.25）" % e["ratio"])
	_check(float(e["neutral"]) >= 0.97, "受けるだけで得をしない：需要を掛けない目の比 %.2f（0.97以上）" % e["neutral"])
	var today: String = _gd_date(_gs.day)
	_check(str(o["deadline"]) > today and str(o["deadline"]) <= _gd_date(_gs.day + 6),
		"返事の期限は数日：%s（今日 %s）" % [o["deadline"], today])
	var news_ok := false
	for a: Dictionary in _gs.news.articles:
		if a["kind"] == "trade" and str(a["headline"]).contains("打診") and a["mine"]:
			news_ok = true
	_check(news_ok, "ニュースに出る（自球団の話題）")
	_hub.call("_refresh")
	_check(str(_hub.call("scout_text")).contains("打診"), "ハブの新戦力に印（%s）" % _hub.call("scout_text"))
	_check(_gs.make_trade_offer().is_empty(), "返事待ちがあるあいだは次の打診は来ない")
	_gs.trade_offer_decline(int(o["id"]))


## 「試合へ」の途中で届くと止まって打診の画面が開く
func _check_hub_stop() -> void:
	print("== 「試合へ」で止まる ==")
	_gs.news_stop_override = 1
	_gs.set_news_stop_preset("none")  # ほかのニュースでは止めない（打診は設定にかかわらず止まる）
	var start: int = _gs.day
	_gs.offer_plan = {"year": _gs.year, "slots": [{"who": "user", "at": _gd_date(start + 2), "tries": 0}]}
	_hub.call("_on_menu_chosen", "advance")
	await _frames(3)
	var o: Dictionary = _pending()
	_check(not o.is_empty() and _gs.day == start + 2, "2日後の朝に打診が届いて止まる（%s。月末まで進まない）" % _gs.date_text())
	_check(_hub.get("_open_key") == "trade" and _view.call("offer_mode") and o.get("seen", false),
		"打診の画面が開く（%s）" % _view.call("offer_text").get_slice("\n", 0))
	await _shot("trade_offer")
	_gs.trade_offer_decline(int(o.get("id", 0)))
	_hub.call("_close_sub_screen")
	_gs.news_stop_override = -1


## 日程表の早送りの途中で届くと止まる
func _check_schedule_stop() -> void:
	print("== 日程表の早送りで止まる ==")
	_gs.news_stop_override = 1
	_hub.call("_open_sub_screen", "schedule")
	await _frames(2)
	var start: int = _gs.day
	_gs.offer_plan = {"year": _gs.year, "slots": [{"who": "user", "at": _gd_date(start + 2), "tries": 0}]}
	_gs.start_fast_forward(start + 10)
	var t := 0
	while _gs.is_fast_forwarding() and t < 100:
		await create_timer(0.05).timeout
		t += 1
	await _frames(3)
	var o: Dictionary = _pending()
	_check(not o.is_empty() and _gs.day == start + 2 and not _gs.is_fast_forwarding(),
		"早送りが2日後で止まる（%s）" % _gs.date_text())
	_check(_hub.get("_open_key") == "trade" and _view.call("offer_mode"), "打診の画面が開く")
	_gs.trade_offer_decline(int(o.get("id", 0)))
	_hub.call("_close_sub_screen")
	_gs.news_stop_override = -1
	_gs.offer_plan = {}


func _check_decline() -> void:
	print("== 断る ==")
	var o := _make_offer()
	if o.is_empty():
		_check(false, "打診が作れる")
		return
	var before: Dictionary = _gs.league.team_of.duplicate()
	await _open_offer()
	_check(_view.call("offer_mode") and _view.call("offer_id") == int(o["id"]), "トレードの画面が打診の画面で開く")
	_view.call("press_decline")
	await _frames(2)
	_check(o["status"] == "declined" and _gs.league.team_of == before and not _view.call("offer_mode")
		and str(_view.call("status_text")).contains("断りました"), "断る：所属は変わらない（%s）" % _view.call("status_text"))
	_hub.call("_close_sub_screen")


func _check_expire() -> void:
	print("== 期限で流れる ==")
	var o := _make_offer()
	if o.is_empty():
		_check(false, "打診が作れる")
		return
	_gs.advance_through(_gs.day + 2)
	_check(o["status"] == "pending", "期限の前（%s）はまだ返事できる" % _gs.date_text())
	while _gd_date(_gs.day) <= str(o["deadline"]):
		_gs.advance_through(_gs.day)
	var news_ok := false
	for a: Dictionary in _gs.news.articles:
		if str(a["headline"]).contains("期限が過ぎて流れました"):
			news_ok = true
	_check(o["status"] == "expired" and news_ok, "期限（%s）が過ぎると流れる（%s）" % [o["deadline"], _gs.date_text()])
	var r: Dictionary = _gs.trade_offer_accept(int(o["id"]))
	_check(not r["ok"], "流れた打診は受けられない（%s）" % r["text"])


func _check_accept() -> void:
	print("== 受ける ==")
	var o := _make_offer()
	if o.is_empty():
		_check(false, "打診が作れる")
		return
	await _open_offer()
	_view.call("press_action")
	await _frames(2)
	var partner: String = o["partner"]
	var ok: bool = o["status"] == "accepted"
	for id: String in o["give"]:
		ok = ok and _gs.league.team_of[id] == partner and _gs.sim_team_of(partner).by_id.has(id)
	for id: String in o["get"]:
		ok = ok and _gs.league.team_of[id] == USER and _gs.my_team().by_id.has(id)
	_check(ok, "受ける：所属とペナントの編成が入れ替わる（%s）" % _view.call("status_text"))
	var logged := 0
	for e: Dictionary in _gs.league.events(_gs.year, "trade"):
		if e["id"] in o["give"] or e["id"] in o["get"]:
			logged += 1
	_check(logged == o["give"].size() + o["get"].size(), "出来事に %d人の移籍が残る" % logged)
	var news_ok := false
	for a: Dictionary in _gs.news.articles:
		if a["kind"] == "trade" and str(a["headline"]).contains("成立") and partner in a["teams"]:
			news_ok = true
	_check(news_ok, "ニュースに成立が出る")
	var before: int = _gs.games_played()
	_gs.advance_through(_gs.day + 3)
	_check(_gs.games_played() > before, "そのまま日付を進めても試合が進む（%s）" % _gs.date_text())
	_hub.call("_close_sub_screen")


func _check_modify() -> void:
	print("== 条件を変える ==")
	var o := _make_offer()
	if o.is_empty():
		_check(false, "打診が作れる")
		return
	await _open_offer()
	_view.call("press_modify")
	await _frames(2)
	var same: bool = ",".join(_view.call("give_ids")) == ",".join(o["give"]) \
		and ",".join(_view.call("get_ids")) == ",".join(o["get"]) and _view.call("partner") == o["partner"]
	_check(not _view.call("offer_mode") and same and o["status"] == "pending",
		"条件を変える：相手の案が入ったまま交渉の画面（%s）" % _view.call("status_text"))
	var est: Dictionary = _gs.trade_estimate(o["partner"], o["give"], o["get"], int(o["money"]))
	_check(float(est["chance"]) >= 0.999, "打診と同じ条件なら成功率 %.2f（必ず成立）" % est["chance"])
	# こちらの出す選手を1人減らすと成功しにくくなる（2人以上出すときだけ）
	if o["give"].size() >= 2:
		var less: Array = o["give"].slice(0, o["give"].size() - 1)
		var est2: Dictionary = _gs.trade_estimate(o["partner"], less, o["get"], int(o["money"]))
		_check(float(est2["chance"]) < 1.0, "出す選手を減らすと成功率が下がる（%.2f）" % est2["chance"])
	_view.call("press_action")
	await _frames(2)
	_check(o["status"] == "countered" and _gs.league.team_of[o["get"][0]] == USER,
		"依頼する：条件を変えて成立（%s）" % _view.call("status_text"))
	_hub.call("_close_sub_screen")


func _check_save() -> void:
	print("== セーブ ==")
	var o := _make_offer()
	if o.is_empty():
		_check(false, "打診が作れる")
		return
	var err: String = _save.save("slot3")
	var load_err: String = _save.load_slot("slot3")
	var back: Dictionary = _gs.trade_offer(int(o["id"]))
	_check(err.is_empty() and load_err.is_empty() and back.get("status", "") == "pending"
		and back.get("deadline", "") == o["deadline"] and ",".join(back.get("give", [])) == ",".join(o["give"]),
		"セーブ・ロードで打診の中身と期限が残る（%s まで）" % back.get("deadline", "?"))
	_check(not _gs.offer_plan.is_empty(), "予定も残る")
	# 作業87より前のセーブ（打診の項目が無い）
	var d: Dictionary = _gs.to_save()
	d.erase("trade_offers")
	d.erase("offer_plan")
	_gs.load_state(_save.ints(JSON.parse_string(JSON.stringify(d))))
	_check(_gs.trade_offers.is_empty() and int(_gs.offer_plan.get("year", 0)) == _gs.year,
		"古いセーブも読める（打診なし・今日からの予定を作る）")
	_save.delete("slot3")
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	_hub = current_scene
	_view = _hub.get("_trade_view")


func _check_cpu() -> void:
	print("== CPU球団どうし ==")
	var before: int = _gs.league.events(_gs.year, "trade").size()
	var deal: Dictionary = _gs.make_cpu_trade()
	if deal.is_empty():
		_check(false, "CPU球団どうしのトレードが作れる")
		return
	var m: RefCounted = _gs.call("_offer_maker", "check2")
	var a_key := false
	var b_key := false
	for id: String in deal["give"]:
		b_key = b_key or m.is_key(id)
	for id: String in deal["get"]:
		a_key = a_key or m.is_key(id)
	var moved := true
	for id: String in deal["give"]:
		moved = moved and _gs.league.team_of[id] == deal["partner"]
	_check(a_key and b_key and moved and deal["partner"] != USER and deal["target"] != USER
		and _gs.league.events(_gs.year, "trade").size() > before,
		"%s⇔%s：%s ⇔ %s（両側に主力・有望な若手、相手の比 %.2f・受ける側の比 %.2f）" % [
			_gd.short_name(deal["target"]), _gd.short_name(deal["partner"]), m.side_text(deal["give"]),
			m.side_text(deal["get"]), deal["ratio"], deal["target_ratio"]])


func _check_deadline() -> void:
	print("== 7月31日まで ==")
	while _gd_date(_gs.day).substr(5) <= "07-31":
		_gs.advance_through(_gs.day)
	_check(_gs.make_trade_offer().is_empty(), "8月1日からは打診が来ない（%s）" % _gs.date_text())
	var late := true
	for o: Dictionary in _gs.trade_offers:
		late = late and (str(o["deadline"]).is_empty() or str(o["deadline"]).substr(5) <= "07-31")
	_check(late, "シーズン中の打診の期限はすべて7月31日まで")


func _check_offseason() -> void:
	print("== オフ ==")
	_gs.advance_through(_gs.season_last_day())
	while _gs.phase != _gs.Phase.FA_TRADE:
		_gs.advance()
	var o := _make_offer()
	_check(not o.is_empty() and str(o["deadline"]).is_empty(), "FA・トレード・ポスティングの段階でも打診が来る（返事は%s）" % (
		_gs.trade_offer_deadline_text(o) if not o.is_empty() else "-"))
	_gs.advance()
	_check(not o.is_empty() and o["status"] == "expired", "次の段階（%s）へ進むと流れる" % _gs.phase_name())


# --- 道具 ------------------------------------------------------------------------------

## 打診を1件作る（相手を順に試す）
func _make_offer() -> Dictionary:
	for o: Dictionary in _gs.trade_offers_pending():
		_gs.trade_offer_decline(int(o["id"]))
	return _gs.make_trade_offer()


func _pending() -> Dictionary:
	var p: Array = _gs.trade_offers_pending()
	return p[0] if not p.is_empty() else {}


func _open_offer() -> void:
	_hub.call("_open_sub_screen", "trade")
	await _frames(2)


func _gd_date(d: int) -> String:
	return load("res://sim/season.gd").date_of_day(d)


func _salary_text(v: int) -> String:
	return load("res://sim/salary.gd").text(v)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("  スクショ: %s.png" % name)
