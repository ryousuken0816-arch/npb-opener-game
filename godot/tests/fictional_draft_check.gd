extends SceneTree
## アマ球界のニュース・架空のドラフト候補・転生選手の確認（docs/AUTORUN.md 作業21・22・32。ヘッドレスで数分）：
##   1) FictionalDraft だけで30年分：1年の人数・区分と順位の割合・将来性 S の人数（史実どおり／夢多め）・無名校の掘り出し物・
##      学校が実在の一覧から・名前が重ならない・転生選手（名前は元の選手と同じ、ピークが元の全盛期に近い）
##   2) 2026年開始：シーズンを進めると春（センバツ）・大学選手権・都市対抗・夏の甲子園・秋の号が日付どおりに出る
##      （実在の候補の名前・メジャー志望の織田翔希）。4月1日の時点では春の号だけ
##   3) 2027年開始 → 2028年：春に架空の候補のニュース → 2028年のドラフトの候補は架空の選手（実在の学校名）・転生の印 →
##      自球団が指名 → 2029年に所属・1軍で試合に出る。転生選手の設定をオフにすると2029年の候補に出ない。セーブ→ロードで候補が残る
##
##   godot --headless --path godot --script res://tests/fictional_draft_check.gd
##
## すべて OK なら "ALL OK"、1つでも NG があれば "FAILED" を出して終了コード 1。

const USER := "阪神タイガース"

var _failures := 0
var _gs: Node
var _gd: Node
## オートロードを参照するクラスは、オートロードの準備ができてから読む（スクリプトの読み込み時に GameData が無いため）
var _fd: GDScript
var _lr: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_fd = load("res://sim/fictional_draft.gd")
	_lr = load("res://sim/league_roster.gd")
	_check_generator()
	_check_amateur_news_2026()
	_check_fictional_flow()
	print("ALL OK" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(1 if _failures > 0 else 0)


# --- 1) 作る仕組みだけ ----------------------------------------------------------------------

func _check_generator() -> void:
	print("== 架空の候補を30年分 ==")
	var fd: RefCounted = _fd.new()
	_check(fd.is_ready(), "ひな形を読める（%d人・転生のもと %d人）" % [fd.data.get("templates", []).size(),
		fd.data.get("legends", []).size()])
	var schools := {}
	for s: Dictionary in fd.data.get("schools", []):
		schools[s["name"]] = true
	var hist_s := _template_share(fd, 1.6)
	for mode: String in ["historical", "dream"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 2028
		var total := 0
		var s_count := 0
		var gems := 0
		var bad_school := 0
		var dup := 0
		var growth_ok := true
		var by_cat := {}
		for y in range(2028, 2058):
			var taken := {}
			var players: Array = fd.generate_year(y, rng, {"hits": mode})
			total += players.size()
			for p: Dictionary in players:
				var am: Dictionary = p["amateur"]
				if float(am["future_score"]) >= 1.6:
					s_count += 1
				if am.get("gem", false):
					gems += 1
				if not schools.has(am["school"]):
					bad_school += 1
				var key: String = _lr.norm_name(p["name"])
				if taken.has(key):
					dup += 1
				taken[key] = true
				by_cat[am["category"]] = int(by_cat.get(am["category"], 0)) + 1
				if not (p.get("growth") is Dictionary and p["growth"].get("peak") is Dictionary
						and str(p["growth"].get("type", "")) in _fd.GROWTH_TYPES):
					growth_ok = false
		var per_year := float(total) / 30.0
		var s_year := float(s_count) / 30.0
		print("  %s：1年 %.1f人・将来性S %.1f人/年（ひな形 %.1f人/年）・掘り出し物 %d人/30年・区分 %s" % [mode, per_year, s_year,
			hist_s * per_year, gems, by_cat])
		_check(per_year >= 95.0 and per_year <= 135.0, "%s：1年の人数が史実の指名の人数ほど（%.1f人）" % [mode, per_year])
		_check(bad_school == 0, "%s：学校・所属はすべて実在の一覧から（一覧に無い %d人）" % [mode, bad_school])
		_check(dup == 0, "%s：同じ年に名前が重ならない（%d件）" % [mode, dup])
		_check(growth_ok, "%s：全員に隠れたピークと育ち方（growth）" % mode)
		_check(gems >= 2 and gems <= 14, "%s：無名校の掘り出し物は5年に1人ほど（30年で %d人）" % [mode, gems])
		if mode == "historical":
			_check(absf(s_year - hist_s * per_year) <= 1.2, "史実どおり：将来性Sの人数がひな形（史実の指名）の割合どおり（%.1f／%.1f）"
				% [s_year, hist_s * per_year])
		else:
			_check(s_year >= hist_s * per_year + 1.5, "夢多め：将来性Sが年に2〜3人増える（%.1f人/年）" % s_year)
	# 転生選手
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	var legends: Array = fd.data.get("legends", [])
	var rei_total := 0
	var close := 0
	for y in range(2028, 2048):
		for p: Dictionary in fd.generate_year(y, rng2, {"legends": legends}):
			var rei: Dictionary = _fd.reincarnation_of(p)
			if rei.is_empty():
				continue
			rei_total += 1
			var src: Dictionary = {}
			for l: Dictionary in legends:
				if l["id"] == rei["id"]:
					src = l
			var gap := 0.0
			var n := 0
			for k: String in src.get("peak", {}):
				if k != "velocity" and p["growth"]["peak"].has(k):
					gap += absf(float(p["growth"]["peak"][k]) - float(src["peak"][k]))
					n += 1
			if p["name"] == src.get("name") and n > 0 and gap / n <= 12.0 and p["amateur"]["grade"] in ["S", "A"]:
				close += 1
	_check(rei_total >= 10 and rei_total <= 32, "転生選手は年に0〜2人（20年で %d人）" % rei_total)
	_check(close == rei_total, "転生選手は元の名前・全盛期に近いピーク・高い当時の評価（%d/%d人）" % [close, rei_total])


## ひな形のうち将来性の点が th 以上の割合（本指名＋育成の全員）
func _template_share(fd: RefCounted, th: float) -> float:
	var all: Array = fd.data.get("templates", [])
	var n := 0
	for t: Dictionary in all:
		if float(t["score"]) >= th:
			n += 1
	return float(n) / maxf(1.0, all.size())


# --- 2) 2026年のアマ球界のニュース --------------------------------------------------------------

func _check_amateur_news_2026() -> void:
	print("== 2026年のアマ球界のニュース ==")
	_gs.new_game(USER, 2026)
	_gs.advance_through(Season.day_number("2026-04-01") - 1)
	var news: News = _gs.news
	_check(news.get_issue("2026-amateur-spring").size() > 0 and news.get_issue("2026-amateur-summer").is_empty(),
		"4月1日（%s）：春のセンバツ号が出て、夏の号はまだ" % _gs.date_text())
	var spring := news.of_issue("2026-amateur-spring")
	_check(spring.size() >= 2, "春の号に高校生の候補の記事 %d本（%s）" % [spring.size(), _heads(spring)])
	_gs.advance_through(Season.day_number("2026-08-24") - 1)
	_check(news.get_issue("2026-amateur-summer").size() > 0 and news.get_issue("2026-amateur-fall").is_empty(),
		"8月24日（%s）：夏の甲子園号が出て、秋の号はまだ" % _gs.date_text())
	_gs.skip_to_phase(_gs.Phase.AWARDS)
	var names := {}
	for a: Dictionary in news.of_kind("amateur", 2026):
		names[a["headline"]] = true
	var keys := ["spring", "college", "shakai", "summer", "fall"]
	var have := 0
	for k: String in keys:
		if not news.get_issue("2026-amateur-%s" % k).is_empty():
			have += 1
	_check(have == keys.size(), "2026年：5つの号がすべて出た（%d/5）" % have)
	var oda := false
	var real := 0
	var ama: Dictionary = _gd.read_data("amateur/2026.json")
	var real_names := {}
	for p: Dictionary in ama["players"]:
		real_names[p["name"]] = true
	for h: String in names:
		if "織田" in h and "メジャー" in h:
			oda = true
		for n: String in real_names:
			if n in h:
				real += 1
				break
	_check(oda, "秋の号に織田翔希のメジャー挑戦の表明")
	_check(real >= 10, "見出しに実在の候補の名前（%d本）" % real)
	_check(_gs.phase == _gs.Phase.AWARDS and _gs.year == 2026, "シーズン後は表彰へ（%s）" % _gs.date_text())


# --- 3) 2028年の架空の候補 → 指名 → 2029年 ------------------------------------------------------

func _check_fictional_flow() -> void:
	print("== 2027年開始 → 2028年の架空の候補 ==")
	_gs.new_game(USER, 2027)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	_gs.advance()  # 2027年のドラフトはおまかせ → 2028年の春季キャンプ
	_gs.advance()  # 開幕
	_check(_gs.year == 2028 and _gs.phase == _gs.Phase.SEASON, "2028年の開幕（%s）" % _gs.date_text())
	_check(_gd.draft_classes.is_empty(), "開幕の時点ではまだ2028年の候補を作っていない")
	_gs.advance_through(Season.day_number("2028-04-02") - 1)
	var cls: Array = _gs.draft_class(2028)
	var spring: Array = _gs.news.of_issue("2028-amateur-spring")
	var fic_named := 0
	for a: Dictionary in spring:
		for p: Dictionary in cls:
			if str(p["name"]) in str(a["headline"]) or str(p["name"]).get_slice(" ", 0) in str(a["headline"]):
				fic_named += 1
				break
	_check(cls.size() >= 95 and spring.size() >= 2 and fic_named >= 2, "2028年の春：架空の候補 %d人・センバツ号に %d本（%s）" % [
		cls.size(), fic_named, _heads(spring)])
	var linked := 0
	for a: Dictionary in spring:
		if not a["players"].is_empty() and not _gd.call("player", str(a["players"][0])).is_empty():
			linked += 1
	_check(linked >= 2, "ニュースの選手から候補の選手詳細を引ける（%d本）" % linked)
	var date_before: String = _gs.date_text()
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	var d: RefCounted = _gs.draft()
	_check(d != null and d.year == 2028, "2028年オフのドラフト（%s → %s）" % [date_before, _gs.date_text()])
	if d == null:
		return
	var fd: RefCounted = _fd.new()
	var schools := {}
	for s: Dictionary in fd.data.get("schools", []):
		schools[s["name"]] = true
	var fictional := 0
	var real_school := 0
	var rei: Array[Dictionary] = []
	var ranks := {}
	for c: Dictionary in d.candidates:
		if c.get("fictional", false):
			fictional += 1
		if schools.has(c["school"]):
			real_school += 1
		if not c.get("reincarnation", {}).is_empty():
			rei.append(c)
		ranks[c["hyouka_rank"]] = int(ranks.get(c["hyouka_rank"], 0)) + 1
	_check(fictional == d.candidates.size() and fictional >= 95, "候補はすべて架空の選手（%d人）" % fictional)
	_check(real_school == d.candidates.size(), "出身校・所属はすべて実在の学校名（%d人）" % real_school)
	_check(ranks.has("S") or ranks.has("A"), "当時の評価に上位の目玉がいる（%s）" % ranks)
	print("  転生選手：%s" % ", ".join(rei.map(func(c: Dictionary) -> String:
		return "%s（%s・元 %d年）" % [c["name"], c["school"], int(c["reincarnation"]["peak_year"])])))
	# 自球団：1位は転生選手（いれば）か当時の評価のいちばん高い候補
	var target: Dictionary = rei[0] if not rei.is_empty() else {}
	if target.is_empty():
		for c: Dictionary in d.candidates:
			if target.is_empty() or float(c["hyouka"]) > float(target["hyouka"]):
				target = c
	d.user_bid(target["id"])
	d.run_first_wave()
	d.auto_complete()
	var mine: Array = d.picks_of(USER)
	_check(mine.size() >= 3, "自球団が架空の候補を指名（%d人）" % mine.size())
	_gs.advance()
	_check(_gs.year == 2029 and _gs.phase == _gs.Phase.CAMP, "2029年の春季キャンプ（%s）" % _gs.date_text())
	var present := 0
	for rec: Dictionary in mine:
		if _gs.league.team_of.get(rec["id"], "") == USER and not _gd.call("player", rec["id"]).is_empty():
			present += 1
	_check(present == mine.size(), "指名した架空の選手 %d/%d人が自球団に所属" % [present, mine.size()])
	if not rei.is_empty():
		var rp: Dictionary = _gd.call("player", rei[0]["id"])
		_check(not _fd.reincarnation_of(rp).is_empty(), "転生選手は入団後も転生の印と元の選手が分かる")

	# 転生選手の設定をオフ → 2029年の候補に出ない。セーブ→ロードで設定と候補が残る
	_gs.set_reincarnation(false)
	_gs.set_fictional_hits("dream")
	_gs.advance()
	_check(_gs.phase == _gs.Phase.SEASON and _gs.year == 2029, "2029年の開幕（%s）" % _gs.date_text())
	_play_rookie(mine)
	var cls29: Array = _gs.draft_class(2029)
	var rei29 := 0
	var dream29 := 0
	for p: Dictionary in cls29:
		if not _fd.reincarnation_of(p).is_empty():
			rei29 += 1
		if p["amateur"].get("dream", false):
			dream29 += 1
	_check(cls29.size() >= 95 and rei29 == 0, "転生選手オフ：2029年の候補 %d人に転生選手なし" % cls29.size())
	_check(dream29 >= 2, "夢多め：2029年の候補にS級の大物 %d人" % dream29)
	var saved: Dictionary = SaveUtil.ints(JSON.parse_string(JSON.stringify(_gs.to_save())))
	_gs.new_game(USER, 2026)
	_gs.load_state(saved)
	_check(not _gs.reincarnation_on and _gs.fictional_hits == "dream" and _gs.draft_class(2029).size() == cls29.size()
		and str(_gs.draft_class(2029)[0]["name"]) == str(cls29[0]["name"]), "セーブ→ロードで設定と2029年の候補が残る")


## 指名した選手を1人1軍に上げ、2週間で試合に出るか
func _play_rookie(mine: Array) -> void:
	var roster: Variant = _gs.season.teams.get(USER)
	var rookie: Variant = null
	for rec: Dictionary in mine:
		var sp: Variant = roster.by_id.get(rec["id"]) if roster != null else null
		if sp != null and not sp.is_ikusei and (rookie == null or (rookie.is_pitcher and not sp.is_pitcher)):
			rookie = sp
	var err := "指名選手なし"
	if rookie != null and roster.is_active(rookie):
		err = ""
	elif rookie != null:
		var out_p: Variant = null
		if rookie.is_pitcher:
			for sp: Variant in roster.active_players(true):
				if roster.pitcher_role(sp)[0] == "rotation":
					out_p = sp
					break
		else:
			var order: Array = roster.lineup(true)
			for i in range(order.size() - 1, -1, -1):
				if order[i][0] != null and order[i][1] != "投手":
					out_p = order[i][0]
					break
		err = "入れ替える選手なし" if out_p == null else str(roster.swap_registration(out_p, rookie, _gs.day))
	_check(err.is_empty(), "架空の新人を1軍に登録できる（%s%s）" % [rookie.name if rookie != null else "", err])
	var before: String = _gs.date_text()
	_gs.advance_through(_gs.day + 14)
	var b: Dictionary = _gs.season.batting.get(rookie.id if rookie != null else "", {})
	var p: Dictionary = _gs.season.pitching.get(rookie.id if rookie != null else "", {})
	_check(int(b.get("pa", 0)) > 0 or int(p.get("outs", 0)) > 0, "2週間で架空の新人が試合に出た（%s → %s、打席 %d・アウト %d）"
		% [before, _gs.date_text(), int(b.get("pa", 0)), int(p.get("outs", 0))])


func _heads(list: Array) -> String:
	var out: Array[String] = []
	for a: Dictionary in list.slice(0, 3):
		out.append(str(a["headline"]))
	return " / ".join(out)


func _check(ok: bool, label: String) -> void:
	print(("  OK  " if ok else "  NG  ") + label)
	if not ok:
		_failures += 1
