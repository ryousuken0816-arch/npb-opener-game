extends SceneTree
## ドラフトの意中の球団・入団拒否（docs/AUTORUN.md 作業77。ヘッドレスで数分）：
##   1) 確率：意中（弱い）・「〇〇以外なら〇〇」（強い）の入団拒否の確率、誠意（年俸の上乗せ）で下がる、順位で上下
##   2) 人数：2028〜2040年の架空の候補で、意中の球団を持つ候補が年に数人（怪物・評価の高い候補ほど多い）
##   3) 2028年（阪神）：「巨人以外なら会社に残留」の候補を2位で強行指名 → ドラフト会議のあと交渉の待ち。
##      CPU 球団の評価は意中ではない球団で下がり、意中の球団で上がる。セーブしておき
##      ①誠意で説得して成功（年俸の上乗せ） ②説得して失敗（入団拒否・出来事・戻る予定）
##      ③説得しないまま次へ（通常の交渉で決まる。期限切れにはしない）
##   4) ②の続き：セーブ・ロードで戻る予定が残り、翌2029年の候補に戻る（指名拒否の物語・寸評・ドラフトの候補）
##   5) 拒否した選手が戻る年数（高校→大学4年・社会人3年、大学→社会人2年、残留1年）と、戻るときの能力の伸び
##   6) ニュース（ドラフト直前号）・有識者の予想・スカウトの噂と札に意中の球団が出る
##
##   godot --headless --path godot --script res://tests/draft_intent_check.gd
##
## すべて OK なら "ALL OK"、1つでも NG があれば "FAILED" を出して終了コード 1。

const USER := "阪神タイガース"
const FAVORITE := "読売ジャイアンツ"

var _failures := 0
var _gs: Node
var _gd: Node
var _ds: GDScript
var _di: GDScript
var _sn: GDScript
var _de: GDScript
var _fd: GDScript
var _gr: GDScript
var _lr: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_ds = load("res://sim/draft.gd")
	_ds.lottery_seed = 1
	_di = load("res://sim/draft_intent.gd")
	_sn = load("res://sim/scout_notes.gd")
	_de = load("res://sim/draft_experts.gd")
	_fd = load("res://sim/fictional_draft.gd")
	_gr = load("res://sim/growth.gd")
	_lr = load("res://sim/league_roster.gd")
	_check_chance()
	_check_counts()
	_check_return_years()
	await _check_game()
	print("ALL OK" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_chance() -> void:
	print("== 入団拒否の確率 ==")
	var soft := {"team": FAVORITE, "hard": false, "alt": "大学"}
	var hard := {"team": FAVORITE, "hard": true, "alt": "大学"}
	var r1 := {"round": 1, "ikusei": false}
	var r2 := {"round": 2, "ikusei": false}
	var r5 := {"round": 5, "ikusei": false}
	var ik := {"round": 1, "ikusei": true}
	var s0: float = _di.refuse_chance(soft, r2, 0)
	var h0: float = _di.refuse_chance(hard, r2, 0)
	print("  意中：%d%%　「以外なら」：%d%%（2位・誠意なし）" % [roundi(s0 * 100), roundi(h0 * 100)])
	_check(s0 >= 0.2 and s0 <= 0.4 and h0 >= 0.6 and h0 <= 0.9, "意中は2〜4割、「以外なら」は6〜9割が拒否")
	_check(_di.refuse_chance(hard, r1, 0) < h0 and _di.refuse_chance(hard, r5, 0) > h0
		and _di.refuse_chance(hard, ik, 0) > h0, "1位は下がり、下位・育成は上がる")
	_check(_di.refuse_chance(hard, r2, 2) < _di.refuse_chance(hard, r2, 1)
		and _di.refuse_chance(hard, r2, 1) < h0, "誠意（年俸の上乗せ）が大きいほど拒否が減る")
	_check(_di.needs_talk({"intent": soft}, USER) and not _di.needs_talk({"intent": soft}, FAVORITE)
		and not _di.needs_talk({}, USER), "意中の球団の指名は交渉が要らない")


## 2028〜2040年の架空の候補で、意中の球団を持つ候補の人数
func _check_counts() -> void:
	print("== 意中の球団を持つ候補の人数（2028〜2040年） ==")
	var fd: RefCounted = _fd.new()
	var teams: Array = ["読売ジャイアンツ", "阪神タイガース", "中日ドラゴンズ", "横浜DeNAベイスターズ", "広島東洋カープ",
		"東京ヤクルトスワローズ", "福岡ソフトバンクホークス", "北海道日本ハムファイターズ", "千葉ロッテマリーンズ",
		"東北楽天ゴールデンイーグルス", "埼玉西武ライオンズ", "オリックス・バファローズ"]
	var total := 0
	var hard_n := 0
	var by_grade := {}
	var monsters := [0, 0]
	var years := 0
	var max_n := 0
	var line: Array[String] = []
	for y in range(2028, 2041):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("intent-count:%d" % y)
		var cls: Array = fd.generate_year(y, rng)
		var irng := RandomNumberGenerator.new()
		irng.seed = hash("intent:%d" % y)
		_di.assign(cls, teams, irng)
		var n := 0
		for p: Dictionary in cls:
			var am: Dictionary = p["amateur"]
			if bool(p.get("is_monster", false)):
				monsters[0] += 1
			if not am.has("team_intent"):
				continue
			n += 1
			hard_n += 1 if bool(am["team_intent"]["hard"]) else 0
			by_grade[am["grade"]] = int(by_grade.get(am["grade"], 0)) + 1
			if bool(p.get("is_monster", false)):
				monsters[1] += 1
			_check(not bool(am.get("as_ikusei", false)), "育成枠の候補には付けない")
			_check(not (am.get("mlb_intent") is Dictionary), "メジャー志望の候補には付けない")
		total += n
		years += 1
		max_n = maxi(max_n, n)
		line.append("%d:%d" % [y, n])
	print("  " + " ".join(line))
	print("  合計%d人（年平均%.1f人、うち「以外なら」%d人）　評価ごと：%s　怪物 %d人中 %d人" % [total, float(total) / years,
		hard_n, str(by_grade), monsters[0], monsters[1]])
	var avg := float(total) / years
	_check(avg >= 1.5 and avg <= 5.0 and max_n <= 9, "年に数人（年平均%.1f人・最大%d人）" % [avg, max_n])
	_check(hard_n >= 1 and hard_n < total, "「以外なら」の強い表明も混ざる（%d人）" % hard_n)
	_check(int(by_grade.get("S", 0)) + int(by_grade.get("A", 0)) >= 3, "評価の高い候補にもいる")


## 拒否したあと候補に戻る年数・戻るときの選手
func _check_return_years() -> void:
	print("== 候補に戻る年数 ==")
	_check(_di.return_year({"alt": "大学"}, 2030) == 2034 and _di.return_year({"alt": "社会人"}, 2030) == 2033
		and _di.return_year({"alt": "社会人（大卒）"}, 2030) == 2032 and _di.return_year({"alt": "残留"}, 2030) == 2031,
		"高校→大学4年・社会人3年、大学→社会人2年、残留1年")
	var fd: RefCounted = _fd.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var cls: Array = fd.generate_year(2030, rng)
	var hs: Dictionary = {}
	for p: Dictionary in cls:
		if p["amateur"]["category"] == "高校" and p["amateur"]["grade"] in ["S", "A"]:
			hs = p
			break
	if hs.is_empty():
		_check(false, "2030年の高校生の目玉が見つからない")
		return
	var entry := {"due": 2034, "draft_year": 2030, "team": "中日ドラゴンズ", "label": "1位",
		"intent": {"team": FAVORITE, "hard": true, "alt": "大学"}, "player": hs}
	var cls2: Array = fd.generate_year(2034, rng)
	var back: Dictionary = _di.make_return(entry, 2034, cls2, "東都大学", _gr.new(), rng)
	var am: Dictionary = back["amateur"]
	var before: float = _fd.entry_level(hs)
	var after: float = _fd.entry_level(back)
	print("  %s：%s %s → %s %s、能力 %.1f → %.1f、評価 %s、%s" % [back["name"], hs["amateur"]["school"],
		hs["amateur"]["grade_text"], am["school"], am["grade_text"], before, after, am["grade"], am["story"]])
	_check(am["category"] == "大学" and am["school"] == "東都大学" and am["draft_year"] == 2034
		and str(back["draft"]).begins_with("2034年") and back["id"] != hs["id"], "大学4年として2034年の候補に戻る")
	_check(after > before, "4年間で能力が伸びる")
	_check(str(am["story"]).contains("2030年秋") and str(am["story"]).contains("中日") and am["refused"]["year"] == 2030,
		"物語に「2030年秋、中日の1位指名を拒否」")
	_check(int(_gr.age_at(back, 2035)) == int(_gr.age_at(hs, 2031)) + 4, "年齢も4つ上")


func _check_game() -> void:
	print("== 2028年 意中の候補を強行指名（%s） ==" % USER)
	_gs.new_game(USER, 2027)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	_gs.draft_resolve()
	_to_camp()
	_gs.advance()  # 2028年の開幕
	var klass: Array = _gs.draft_class(2028)
	var natural := 0
	for p: Dictionary in klass:
		if p["amateur"].has("team_intent"):
			natural += 1
			print("  %s（%s・%s）：%s" % [p["name"], p["amateur"]["school"], p["amateur"]["grade"],
				p["amateur"]["team_intent"]["note"]])
	print("  2028年の意中の候補：%d人" % natural)
	# 2位で残っていそうな評価 B の社会人（無ければ B の誰か）に「巨人以外なら会社に残留」を付ける
	var target_p: Dictionary = {}
	for p: Dictionary in klass:
		var am: Dictionary = p["amateur"]
		if am["grade"] == "B" and not bool(am.get("as_ikusei", false)) and not (am.get("mlb_intent") is Dictionary):
			if target_p.is_empty() or am["category"] == "社会人":
				target_p = p
			if am["category"] == "社会人":
				break
	var tam: Dictionary = target_p["amateur"]
	tam["team_intent"] = {"team": FAVORITE, "hard": true, "alt": "残留",
		"note": "%sの%sは「巨人以外なら会社に残留」と明言" % [tam["school"], target_p["name"]]}
	var tname: String = target_p["name"]
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	var d: RefCounted = _gs.draft()
	var target := _find(d, tname)
	_check(d != null and d.year == 2028 and not target.is_empty() and not d.by_id[target].get("intent", {}).is_empty(),
		"2028年のドラフトの候補に意中の球団（%s）" % tname)
	if target.is_empty():
		return
	# ニュース・予想・噂
	var news_found := false
	for a: Dictionary in _gs.news.articles:
		if str(a.get("headline", "")).contains(tname) and str(a.get("headline", "")).contains("以外なら"):
			news_found = true
	_check(news_found, "ドラフト直前号に「%s、巨人以外なら会社に残留」の記事" % tname)
	var c: Dictionary = d.by_id[target]
	var rumor: String = _sn.rumor_text(d, c)
	_check(rumor.contains("以外なら"), "スカウトの噂：%s" % rumor)
	var tags: Array = _sn.traits(d, c)
	_check(not tags.is_empty() and str(tags[0]["text"]).contains("巨人以外なら"), "特徴の札：%s" % str(tags[0] if not tags.is_empty() else {}))
	var pred: Dictionary = _de.predict(2028, "2028-10-08", {}, _gd.teams())
	var key: String = _lr.norm_name(tname)
	_check(pred["intents"].has(key), "有識者の予想の材料に意中の球団")
	# CPU 球団の評価：意中ではない球団（強行しない）で下がり、意中の球団で上がる
	var plain: Dictionary = c.duplicate()
	plain.erase("intent")
	var other := ""
	for t: String in d.teams:
		if t != FAVORITE and t != USER and not d._team_dare.get(t, {}).has(target):
			other = t
			break
	var diff_other: float = d.evaluate(other, c, false) - d.evaluate(other, plain, false)
	var diff_fav: float = d.evaluate(FAVORITE, c, false) - d.evaluate(FAVORITE, plain, false)
	_check(diff_other < -1.0 and diff_fav > 0.0, "CPU の評価：%s %.2f、%s +%.2f" % [_gd.short_name(other), diff_other,
		_gd.short_name(FAVORITE), diff_fav])
	# 1位は別の候補、2位で強行指名
	var guard := 0
	while d.stage == _ds.Stage["FIRST"] and guard < 10:
		guard += 1
		if d.first_pick_of(USER).is_empty() and not d.bids.has(USER):
			var best := ""
			for cc: Dictionary in d.remaining():
				if cc["id"] != target and not cc.get("mlb_intent", false) and cc.get("intent", {}).is_empty():
					if best.is_empty() or float(cc["hyouka"]) > float(d.by_id[best]["hyouka"]):
						best = cc["id"]
			d.user_bid(best)
		d.run_first_wave()
	d.run_until_user()
	if not str(d.by_id[target]["picked_by"]).is_empty():
		print("  %sは%sが先に指名（あえて強行）。残りの候補に付け直す" % [tname, d.by_id[target]["picked_by"]])
		var it: Dictionary = d.by_id[target]["intent"]
		target = ""
		for cc: Dictionary in d.remaining():
			if cc.get("fictional", false) and cc.get("intent", {}).is_empty() and not cc.get("mlb_intent", false):
				target = cc["id"]
				break
		d.by_id[target]["intent"] = it
		tname = d.by_id[target]["name"]
		for p: Dictionary in klass:
			if p["name"] == tname:
				p["amateur"]["team_intent"] = it
	var error: String = d.user_pick(target)
	_check(error.is_empty() and d.pick_of(target).get("team", "") == USER, "%sを%sで強行指名" % [tname,
		d.pick_of(target).get("label", "-")])
	if not error.is_empty():
		return
	d.auto_complete()
	_gs.draft_sync()
	_check(d.stage == _ds.Stage["DONE"] and not d.resolved and target in d.pending_talks()
		and not _gs.league.team_of.has(target), "ドラフトのあと交渉の待ち（勝手に入団・拒否しない）")
	var opts: Array = d.talk_options(target)
	_check(opts.size() == 3 and float(opts[2]["chance"]) > float(opts[0]["chance"]), "誠意の選び方：%s" % str(opts))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_gs.to_save()))
	# 画面：手帳に説得（誠意）のページ・上の帯に入団交渉の案内
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub: Node = current_scene
	hub.call("_open_sub_screen", "draft")
	await _frames(4)
	var view: Node = hub.get("_draft_view")
	view.call("finish_overlays")
	await _frames(2)
	var go: Button = (view.call("notebook") as Control).call("go_button")
	var notice: String = view.call("talk_notice", d, d.pending_talks())
	_check(view.call("selected_id") == target and go.text.begins_with("説得する") and not go.disabled,
		"手帳に入団交渉のページ（%s）" % go.text)
	_check(notice.contains("意中の球団が別の%s" % tname) and notice.contains("通常の交渉"), "案内：%s" % notice)
	hub.call("_close_sub_screen")
	for outcome: String in ["成功", "失敗", "交渉しない"]:
		_gs.load_state(JSON.parse_string(JSON.stringify(saved)))
		var d2: RefCounted = _gs.draft()
		var league: RefCounted = _gs.league
		var res := {}
		if outcome == "交渉しない":
			d2.force_roll = 0.99
			_gs.advance()
		else:
			d2.force_roll = 0.0 if outcome == "成功" else 0.99
			res = d2.persuade(target, 2 if outcome == "成功" else 1)
			_gs.draft_sync()
		var talk: Dictionary = d2.talks.get(target, {})
		var joined: bool = league.team_of.get(target, "") == USER
		print("  %s：%s %s" % [outcome, str(res.get("text", "")), str(talk)])
		_check(d2.resolved and joined == (outcome == "成功") and not bool(talk.get("expired", false))
			and str(talk.get("kind", "")) == "intent" and int(talk.get("promise", -1)) == 0,
			"%s：%s" % [outcome, "入団" if joined else "入団拒否"])
		if outcome == "成功":
			print("  年俸：%s" % str(league.salary.get(target)))
			_check(int(talk.get("bonus_man", 0)) == 3000 and not league.posting_promise.has(target),
				"最大限の誠意：年俸 +3000万円（ポスティングの約束は付かない）")
			continue
		var logged := ""
		for e: Dictionary in league.log:
			if e["kind"] == "draft_refused" and e["id"] == target:
				logged = str(e["text"])
		_check(not logged.is_empty(), "出来事：%s" % logged)
		var mine: Dictionary = {}
		for r: Dictionary in league.draft_returns:
			print("    拒否：%s（%s %s、%s）→ %d年に戻る" % [r["player"]["name"], _gd.short_name(r["team"]), r["label"],
				_di.short_text(r["intent"]), int(r["due"])])
			if r["player"]["name"] == tname:
				mine = r
		_check(not mine.is_empty() and int(mine["due"]) == 2029, "翌2029年に候補へ戻る予定")
		if outcome == "失敗":
			_check_comeback(tname)


## 拒否した選手が翌年の候補に戻る（セーブ・ロードをはさむ）
func _check_comeback(tname: String) -> void:
	_to_camp()
	var again: Dictionary = JSON.parse_string(JSON.stringify(_gs.to_save()))
	_gs.load_state(again)
	var kept := false
	for r: Dictionary in _gs.league.draft_returns:
		kept = kept or r["player"]["name"] == tname
	_check(kept, "セーブ・ロードのあとも戻る予定が残る")
	_gs.advance()  # 2029年の開幕
	var cls: Array = _gs.draft_class(2029)
	var back: Dictionary = {}
	for p: Dictionary in cls:
		if p["name"] == tname:
			back = p
	var left := false
	for r: Dictionary in _gs.league.draft_returns:
		left = left or int(r["due"]) <= 2029
	_check(not back.is_empty() and not left, "2029年の候補に%sが戻る（戻した予定は消える）" % tname)
	if back.is_empty():
		return
	var am: Dictionary = back["amateur"]
	print("  %s：%s %s・評価%s　%s" % [tname, am["school"], am["grade_text"], am["grade"], am["intro"]])
	_check(am["refused"]["year"] == 2028 and str(am["story"]).contains("2028年秋") and str(am["intro"]).contains("拒否"),
		"紹介文に「2028年秋、阪神の2位指名を拒否」")
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	var d: RefCounted = _gs.draft()
	var id := _find(d, tname)
	_check(d != null and d.year == 2029 and not id.is_empty() and not d.by_id[id].get("refused", {}).is_empty(),
		"2029年のドラフトの候補に%s（指名拒否の経緯つき）" % tname)
	if not id.is_empty():
		var tags: Array = _sn.traits(d, d.by_id[id])
		var has := false
		for t: Dictionary in tags:
			has = has or str(t["text"]).contains("指名拒否")
		_check(has, "特徴の札に「2028年 指名拒否」")
	var news_found := false
	for a: Dictionary in _gs.news.articles:
		if str(a.get("headline", "")).contains(tname) and str(a.get("headline", "")).contains("再びドラフト候補"):
			news_found = true
	_check(news_found, "ドラフト直前号に「%s、再びドラフト候補に」" % tname)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _to_camp() -> void:
	var guard := 0
	while _gs.phase != _gs.Phase.CAMP and guard < 10:
		guard += 1
		_gs.advance()


func _find(d: RefCounted, name: String) -> String:
	for c: Dictionary in d.candidates:
		if c["name"] == name:
			return c["id"]
	return ""


func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["OK" if ok else "NG", label])
	if not ok:
		_failures += 1
