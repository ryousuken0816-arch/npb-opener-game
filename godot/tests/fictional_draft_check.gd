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
var _growth: GDScript
var _fa: GDScript
var _an: GDScript
var _at: GDScript
var _examples: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_fd = load("res://sim/fictional_draft.gd")
	_lr = load("res://sim/league_roster.gd")
	_growth = load("res://sim/growth.gd")
	_fa = load("res://sim/free_agency.gd")
	_an = load("res://sim/amateur_news.gd")
	_at = load("res://sim/amateur_tournament.gd")
	_check_generator()
	_check_news_text()
	_check_tournaments()
	_check_amateur_news_2026()
	_check_fictional_flow()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0], FileAccess.WRITE)
		if file != null:
			file.store_string("# アマ球界の記事例10本\n\n実際の生成処理から採取。架空年の大会はゲーム内の結果。\n\n" + "\n\n".join(_examples))
	print("ALL OK" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(1 if _failures > 0 else 0)


func _example(a: Array, label: String) -> void:
	if _examples.size() < 10:
		_examples.append("## %d. %s（%s）\n\n%s" % [_examples.size() + 1, a[0], label, str(a[1]).replace("\n", "\n\n")])


func _check_news_text() -> void:
	print("== 記事の再現性・史実の扱い ==")
	_gs.new_game(USER, 2008)
	var an: RefCounted = _an.new(_gs)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var historical: Array = an.prospects(2008)
	var a: Array = an.article(historical[0], _an.STAGES[0], 2008, rng)
	rng.seed = 99999
	_check(a == an.article(historical[0], _an.STAGES[0], 2008, rng), "同じ選手・同じ号なら呼び出し元の乱数に左右されず同じ全文")
	var made_up := false
	for c: Dictionary in historical:
		var text: Array = an.article(c, _an.STAGES[3], 2008, rng)
		for word: String in ["完封", "奪三振", "本塁打", "優勝投手", "MVP"]:
			if word in str(text):
				made_up = true
	_check(not made_up, "2008年の紹介に架空の完封・奪三振・本塁打・優勝を足さない")
	_gs.call("_amateur_news", "2008-03-31")
	var spring: Array = _gs.news.of_issue("2008-amateur-spring")
	var lowered := false
	for story: Dictionary in spring:
		if "中位" in story["body"] or "育成" in story["body"]:
			lowered = true
	_check(lowered, "同じ号に中位・育成級にも光を当てる記事")
	_example(a, "2008年・事実未確認の大会成績は書かない")
	_gs.new_game(USER, 2026)
	an = _an.new(_gs)
	for c: Dictionary in an.prospects(2026):
		if c["category"] == "大学" and _examples.size() == 1:
			_example(an.article(c, _an.STAGES[1], 2026, rng), "2026年・収集済みの実績")
		if c["category"] == "独立" and _examples.size() == 2:
			var story: Array = an.article(c, _an.STAGES[2], 2026, rng)
			_check(not "都市対抗で" in str(story), "独立候補を都市対抗出場者にしない")
			_example(story, "2026年・独立リーグ")
	# 区分・守備位置・評価別のすべての経路を通す（事実の追加はしない）。
	var seed_c: Dictionary = an.prospects(2026)[0]
	for pos: String in ["投手", "捕手", "内野手", "外野手"]:
		for grade: String in ["S", "A", "B", "C", "D"]:
			var c := seed_c.duplicate(true)
			c["pos"] = pos
			c["pitcher"] = pos == "投手"
			c["grade"] = grade
			var story: Array = an.article(c, _an.STAGES[4], 2026, rng)
			_check("ある球団のスカウト" in story[1] and not str(story[0]).is_empty(), "守備位置・評価別：%s %s" % [pos, grade])


func _check_tournaments() -> void:
	print("== 史実の出典・大会結果・候補への反映 ==")
	var data: Dictionary = _gd.read_data("amateur/tournaments.json")
	var sourced := true
	var count := 0
	for year: String in data["years"]:
		for event: String in data["years"][year]:
			var r: Dictionary = data["years"][year][event]
			if r.get("cancelled", false):
				continue
			count += 1
			sourced = sourced and str(r["sources"]["winner"]).begins_with("https://") and str(r["sources"]["runner_up"]).begins_with("https://")
			for p: Dictionary in r["players"]:
				sourced = sourced and str(p["source_url"]).begins_with("https://")
	_check(sourced and count >= 85, "史実の大会結果と選手の活躍には出典URL（%d大会）" % count)
	_gs.new_game(USER, 2018)
	_gs.call("_amateur_news", "2018-03-31")
	_check(_gs.amateur_results.is_empty(), "センバツ紹介号の日には未開催の決勝結果を出さない")
	_gs.call("_amateur_news", "2018-10-08")
	var summary: String = _at.summary(_gs.amateur_results, 2018, "根尾 昂", "大阪桐蔭高")
	_check("センバツ優勝投手" in summary and "夏の甲子園優勝メンバー" in summary, "学校名の「高」表記を照合し、根尾の春夏の実績")
	var summer: Array = _gs.news.of_issue("2018-amateur-summer-result")
	_check(summer.size() == 1 and "春夏連覇" in summer[0]["headline"] and "13-2" in summer[0]["body"], "2018大阪桐蔭の春夏連覇・決勝スコアは史実どおり")
	_example([summer[0]["headline"], summer[0]["body"]], "2018年・史実")
	var before: int = _gs.news.articles.size()
	_gs.call("_amateur_news", "2018-10-08")
	_check(_gs.news.articles.size() == before and not _gs.amateur_results.has("2018-jingu"), "同じ結果を二重掲載せず、11月の神宮結果はまだ出さない")
	_gs.new_game(USER, 2020)
	_gs.call("_amateur_news", "2020-10-31")
	_check(_gs.amateur_results.is_empty(), "2020年の中止大会と12月開催の都市対抗の結果は秋に出さない")
	_gs.new_game(USER, 2027)
	_gs.call("_amateur_news", "2027-10-08")
	_check(_gs.amateur_results.is_empty(), "未確認の2027年は史実の結果を捏造しない")
	_gs.new_game(USER, 2027)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	_gs.advance()
	_gs.advance()
	_gs.call("_amateur_news", "2028-10-08")
	var results: Dictionary = _gs.amateur_results.duplicate(true)
	_check(results.size() == 4, "架空年は秋までに4大会の結果を保存、神宮はまだ")
	var all: Array = _an.new(_gs).prospects(2028)
	var champion: Dictionary = results["2028-summer"]
	_check(champion["winner"] != champion["runner_up"] and not champion["players"].is_empty(), "優勝・準優勝が重ならず、活躍選手がいる")
	var seed_value := hash("tournament:%d:%s:%d:%s" % [2028, "summer", _gs.first_year, USER])
	var reproduced: Dictionary = _at.simulate(2028, "summer", all, seed_value)
	reproduced["notes"] = champion["notes"].duplicate(true)
	_check(reproduced == champion, "同じ種なら大会結果も同じ（春夏連覇の注記は掲載時に付く）")
	var entries := {}
	for p: Dictionary in _gs.draft_class(2028):
		entries[p["id"]] = p
	var ds: GDScript = load("res://sim/draft.gd")
	var d: RefCounted = ds.new()
	d.setup(2028, USER, _gd.teams(), entries, {}, _gd.teams(), 123)
	var displayed := 0
	for c: Dictionary in d.candidates:
		var h: String = _at.summary(results, 2028, c["name"], c["school"])
		if not h.is_empty():
			displayed += 1
			_check(h in c["intro"], "作戦会議・ドラフト共通の紹介文に実績：%s" % c["name"])
			var row: Dictionary = {}
			for candidate: Dictionary in ds.fictional_rows(2028):
				if candidate["name"] == c["name"]:
					row = candidate
			var base: float = ds.hyouka_value(int(row["as_round"]), bool(row["as_ikusei"]), maxi(1, int(row["bids"])), false)
			_check(float(c["hyouka"]) > base and float(c["hyouka"]) <= base + 0.24001, "大会実績は当時の評価だけに小さく加算：%s" % c["name"])
	_check(displayed > 0, "大会で活躍した候補を紹介できる")
	for c: Dictionary in all:
		if not _at.summary(results, 2028, c["name"], c["school"]).is_empty() and _examples.size() < 8:
			_example(_an.new(_gs).article(c, _an.STAGES[4], 2028, RandomNumberGenerator.new()), "2028年・架空選手の秋の紹介")
	for key: String in ["2028-amateur-spring-result", "2028-amateur-summer-result"]:
		var story: Dictionary = _gs.news.of_issue(key)[0]
		_example([story["headline"], story["body"]], "2028年・ゲーム内大会")
	var saved: Dictionary = SaveUtil.ints(JSON.parse_string(JSON.stringify(_gs.to_save())))
	_gs.new_game(USER, 2008)
	_gs.load_state(saved)
	_check(_gs.amateur_results == results, "セーブ→ロードで優勝・準優勝・個人賞・数字が同じ")
	before = _gs.news.articles.size()
	_gs.call("_amateur_news", "2028-10-08")
	_check(before == _gs.news.articles.size(), "ロード後も大会の記事は増殖しない")
	var old_save := saved.duplicate(true)
	old_save.erase("amateur_results")
	_gs.load_state(old_save)
	_check(_gs.amateur_results.is_empty(), "大会結果の項目が無い古いセーブも読み込める")
	# 実在校の同じ2校を多数回抽選し、強豪優位と番狂わせの両方を確認する。
	var fixture: Dictionary = all[0].duplicate(true)
	fixture["category"] = "大学"
	fixture["school"] = "明治大"
	var underdog := fixture.duplicate(true)
	underdog["school"] = "未登録の大学（テスト）"
	var strong_wins := 0
	for seed_value2 in 200:
		if _at.simulate(2028, "college", [fixture, underdog], seed_value2)["winner"] == "明治大":
			strong_wins += 1
	_check(strong_wins > 120 and strong_wins < 195, "強豪が勝ちやすく、伏兵も勝てる（強豪 %d/200勝）" % strong_wins)
	_gs.new_game(USER, 2008)
	_check(_gs.amateur_results.is_empty(), "新しいゲームには前の大会結果が残らない")


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
		var age_bad := 0
		var by_cat := {}
		var age_range := {}
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
				# 年齢：入団する年（翌年）の4月1日時点の年齢が、区分と入社の年に合っている。誕生日があって成長の年齢と同じ
				var age: int = _growth.age_at(p, y + 1)
				var limits := _age_limits(str(am["category"]), str(am["grade_text"]))
				if p.get("birth") == null or age != int(am["entry_age"]) or age < limits[0] or age > limits[1] \
						or _growth.age_at(p, y + 2) != age + 1:
					age_bad += 1
				var lohi: Array = age_range.get(str(am["category"]), [99, 0])
				age_range[str(am["category"])] = [mini(lohi[0], age), maxi(lohi[1], age)]
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
		_check(age_bad == 0 and age_range.has("社会人") and age_range.has("独立"),
			"%s：高校・大学・社会人・独立の全員に年齢（誕生日あり・区分と入社の年に合う・成長の年齢と同じ。範囲 %s、不備 %d人）" % [mode, age_range, age_bad])
		_check(gems >= 2 and gems <= 14, "%s：無名校の掘り出し物は5年に1人ほど（30年で %d人）" % [mode, gems])
		if mode == "historical":
			_check(absf(s_year - hist_s * per_year) <= 1.2, "史実どおり：将来性Sの人数がひな形（史実の指名）の割合どおり（%.1f／%.1f）"
				% [s_year, hist_s * per_year])
		else:
			_check(s_year >= hist_s * per_year + 1.2, "夢多め：将来性Sが年に2〜3人増える（%.1f人/年）" % s_year)
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


## 区分と学年・入社の年の表示から、入団する年の4月1日時点の年齢の範囲 [下限, 上限]
func _age_limits(category: String, grade_text: String) -> Array:
	match category:
		"高校":
			return [18, 18]
		"大学":
			return [22, 22]
		"社会人":
			var years := int(grade_text.trim_prefix("入社").trim_suffix("年目"))
			# 高卒（18歳＋入社の年。3〜4年目）か大卒（22歳＋入社の年。2〜4年目）
			return [18 + years if years >= 3 else 22 + years, 22 + years]
	return [19, 25]


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
	_check_ages(d.candidates, mine)
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


## 2028年のドラフトの候補一覧の年齢：全員に出る（社会人・独立も）。指名した選手は入団後の年齢・成長の年齢とも合う
func _check_ages(candidates: Array, mine: Array) -> void:
	var by_career := {}
	var missing := 0
	for c: Dictionary in candidates:
		if int(c["age"]) <= 0 or not c.get("age_known", false):
			missing += 1
		var lohi: Array = by_career.get(c["career"], [99, 0])
		by_career[c["career"]] = [mini(lohi[0], int(c["age"])), maxi(lohi[1], int(c["age"]))]
	print("  候補の年齢（区分ごと）：%s" % by_career)
	_check(missing == 0, "候補一覧：全員に年齢が出る（出ない %d人）" % missing)
	_check(by_career.get("高校生", [18, 18]) == [18, 18] and by_career.get("大学生", [22, 22]) == [22, 22]
		and by_career.has("社会人") and by_career["社会人"][0] >= 19 and by_career["社会人"][1] <= 26,
		"候補一覧：高校生は18歳・大学生は22歳・社会人（独立を含む）は19〜26歳")
	var by_id := {}
	for c: Dictionary in candidates:
		by_id[c["id"]] = c
	var bad := 0
	for rec: Dictionary in mine:
		var p: Dictionary = _gd.call("player", rec["id"])
		var c: Dictionary = by_id.get(rec["id"], {})
		# 入団する2029年の4月1日時点の年齢が候補一覧の年齢。翌年は +1。暦年の差（FA・戦力外の画面の年齢）は 0〜1 歳上
		if p.is_empty() or c.is_empty() or _growth.age_at(p, 2029) != int(c["age"]) or _growth.age_at(p, 2030) != int(c["age"]) + 1 \
				or _fa.age_of(p, 2029) < int(c["age"]) or _fa.age_of(p, 2029) > int(c["age"]) + 1:
			bad += 1
	_check(bad == 0, "指名した選手 %d人：入団後の年齢が候補一覧の年齢と同じ（毎年1歳ずつ）" % mine.size())


## 指名した選手を1人1軍に上げ、3週間で試合に出るか
func _play_rookie(mine: Array) -> void:
	var roster: Variant = _gs.season.teams.get(USER)
	# 野手を優先。もうスタメンにいればその選手、いなければ2軍の選手を上げてスタメンと入れ替える
	# （1軍の控えにいるだけの選手は試合に出ないことがある）
	var starters := {}
	for o: Array in roster.lineup(false):
		if o[0] != null:
			starters[o[0].id] = true
	var rookie: Variant = null
	var rookie_score := -1
	for rec: Dictionary in mine:
		var sp: Variant = roster.by_id.get(rec["id"]) if roster != null else null
		if sp == null or sp.is_ikusei:
			continue
		var score := (2 if not sp.is_pitcher else 0) + (4 if starters.has(sp.id) else (1 if not roster.is_active(sp) else -9))
		if score > rookie_score:
			rookie = sp
			rookie_score = score
	var err := "指名選手なし"
	if rookie != null and (starters.has(rookie.id) or (rookie.is_pitcher and roster.is_active(rookie))):
		err = ""
	elif rookie != null:
		var out_p: Variant = null
		if rookie.is_pitcher:
			for sp: Variant in roster.active_players(true):
				if roster.pitcher_role(sp)[0] == "rotation":
					out_p = sp
					break
		else:
			# 阪神（セ）は DH なしの試合がほとんど。DH なしの打順の選手と入れ替える（draft_check と同じ）
			var order: Array = roster.lineup(false)
			for i in range(order.size() - 1, -1, -1):
				if order[i][0] != null and order[i][1] != "投手":
					out_p = order[i][0]
					break
		err = "入れ替える選手なし" if out_p == null else str(roster.swap_registration(out_p, rookie, _gs.day))
	_check(err.is_empty(), "架空の新人を1軍に登録できる（%s%s）" % [rookie.name if rookie != null else "", err])
	var before: String = _gs.date_text()
	if rookie != null:
		var order_text: Array[String] = []
		for o: Array in roster.lineup(false):
			order_text.append("%s:%s" % [o[0].name if o[0] != null else "-", o[1]])
		print("  新人 %s（%s）1軍=%s 打順=%s 守備=%s" % [rookie.name, rookie.id, roster.is_active(rookie), ", ".join(order_text),
			str(_gd.call("player", rookie.id).get("fielding", {}).keys())])
	_gs.advance_through(_gs.day + 21)
	var b: Dictionary = _gs.season.batting.get(rookie.id if rookie != null else "", {})
	var p: Dictionary = _gs.season.pitching.get(rookie.id if rookie != null else "", {})
	_check(int(b.get("pa", 0)) > 0 or int(p.get("outs", 0)) > 0, "3週間で架空の新人が試合に出た（%s → %s、打席 %d・アウト %d）"
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
