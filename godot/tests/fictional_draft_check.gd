extends SceneTree
## アマ球界のニュース・架空のドラフト候補・転生選手の確認（docs/AUTORUN.md 作業21・22・32。ヘッドレスで数分）：
##   1) FictionalDraft だけで30年分：1年の人数・区分と順位の割合・将来性 S の人数（史実どおり／夢多め）・無名校の掘り出し物・
##      学校が実在の一覧から・名前が重ならない・転生選手（名前は元の選手と同じ、ピークが元の全盛期に近い）
##      作業50：当時の評価 S は年2〜4人・A は4〜10人、怪物は年0〜2人、高校生は入団時 C〜D 中心（化け物は数年に1人）、
##      S・A の投手の多くは先発型（スタミナ C 以上）、名前に実在のスターの名前を使わない、所属の区分（独立・専門学校・今の社名）
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
var _draft: GDScript
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
	_draft = load("res://sim/draft.gd")
	_check_generator()
	_check_balance()
	_check_types()
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
	_to_season(2028)
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
	# REINCARNATION_ODDS の期待値は年0.47人（20年で約9人）。前の基準（10〜32）は期待値より上の下限で、乱数しだいで半分ほど落ちていた
	_check(rei_total >= 4 and rei_total <= 20, "転生選手は年に0〜2人（20年で %d人）" % rei_total)
	_check(close == rei_total, "転生選手は元の名前・全盛期に近いピーク・高い当時の評価（%d/%d人）" % [close, rei_total])


## 作業50：当時の評価・怪物・高校生の完成度・上位投手のスタミナ・名前・所属の区分（ドラフトの時点で見える情報だけを集計）
func _check_balance() -> void:
	print("== 作業50・62：架空の候補の手直し・入団時の水準（30年分） ==")
	var fd: RefCounted = _fd.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2050
	var years := 30
	var s_bad := 0
	var a_bad := 0
	var mon_bad := 0
	var s_total := 0
	var a_total := 0
	var mon_total := 0
	var hs_phenom := 0
	var hs_strong := 0
	var hs_reg := 0
	var hs_cd := 0
	var top_p := 0
	var top_p_starter := 0
	var star_names := 0
	var tops: Array = []
	var ready1: Array = []
	var hs_top := 0
	var hs_top_weak := 0
	var strong_not_monster := 0
	var mon_cat := {}
	var mon_weak := 0
	var mon_weak_list: Array = []
	var sa_bat := 0
	var sa_all := 0
	var legends := {}
	for l: Dictionary in fd.data.get("legends", []):
		legends[str(l["name"]).replace(" ", "")] = true
	for y in range(2028, 2028 + years):
		var s := 0
		var a := 0
		var mon := 0
		var top := 0.0
		for p: Dictionary in fd.generate_year(y, rng):
			var am: Dictionary = p["amateur"]
			# 作業62：入団時の水準（投手は総合、野手は換算。FictionalDraft.entry_level）
			var lv: float = _fd.entry_level(p)
			var reg := not bool(am["as_ikusei"]) and not p.has("reincarnation")
			if reg:
				top = maxf(top, lv)
			if bool(p.get("is_monster", false)):
				mon_cat[am["category"]] = int(mon_cat.get(am["category"], 0)) + 1
				var w := int(p["pitching"]["ratings"]["k9"]["value"]) if p["is_pitcher"] else maxi(
					int(p["batting"]["ratings"]["power"]["value"]), maxi(int(p["batting"]["ratings"]["speed"]["value"]),
					int(p["batting"]["ratings"]["arm"]["value"])))
				if (am["category"] == "高校" and w < 84) or (am["category"] != "高校" and lv < 79.5):
					mon_weak += 1
					mon_weak_list.append("%s %s %s 武器%d 総合%.1f" % [p["name"], am["category"], am.get("type", ""), w, lv])
			elif reg and not p.has("dream") and lv >= 79.6:
				strong_not_monster += 1
			if str(am.get("band", "")) == "1" and am["category"] != "高校" and not bool(p.get("is_monster", false)):
				ready1.append(lv)
			if am["grade"] in ["S", "A"]:
				sa_all += 1
				sa_bat += 0 if p["is_pitcher"] else 1
				if am["category"] == "高校" and not bool(p.get("is_monster", false)):
					hs_top += 1
					var best := int(p["pitching"]["ratings"]["k9"]["value"]) if p["is_pitcher"] else maxi(
						int(p["batting"]["ratings"]["power"]["value"]), maxi(int(p["batting"]["ratings"]["speed"]["value"]),
						int(p["batting"]["ratings"]["arm"]["value"])))
					hs_top_weak += 1 if best < 70 else 0
			s += 1 if am["grade"] == "S" else 0
			a += 1 if am["grade"] == "A" else 0
			var monster := bool(p.get("is_monster", false))
			mon += 1 if monster else 0
			if str(p["name"]).get_slice(" ", 1) in ["大谷", "宗佑磨", "朗希", "輝明", "翔平", "由伸", "宗隆"] \
					or legends.has(str(p["name"]).replace(" ", "")):
				star_names += 1
			if am["category"] == "高校" and not bool(am["as_ikusei"]):
				hs_reg += 1
				hs_cd += 1 if lv >= 40 and lv < 70 else 0
				if monster:
					hs_phenom += 1
				elif lv >= 70:
					hs_strong += 1
			if p["is_pitcher"] and am["grade"] in ["S", "A"]:
				top_p += 1
				if int(p["pitching"]["ratings"]["stamina"]["value"]) >= 60 and str(p["pitching"]["role"]) == "先発":
					top_p_starter += 1
		tops.append(roundi(top))
		s_total += s
		a_total += a
		mon_total += mon
		s_bad += 1 if s < 2 or s > 4 else 0
		a_bad += 1 if a < 4 or a > 10 else 0
		mon_bad += 1 if mon > 2 else 0
	print("  1年あたり S %.1f人・A %.1f人・怪物 %.2f人、高校生の化け物 %d人／%d年、高校生（本指名）の入団時 C〜D %.0f%%・それ以外で B 以上 %d人、S・A の投手 %d人のうち先発型 %.0f%%"
		% [float(s_total) / years, float(a_total) / years, float(mon_total) / years, hs_phenom, years,
		100.0 * hs_cd / maxf(1, hs_reg), hs_strong, top_p, 100.0 * top_p_starter / maxf(1, top_p)])
	_check(s_bad == 0, "当時の評価 S は毎年2〜4人（外れた年 %d）" % s_bad)
	_check(a_bad == 0, "当時の評価 A は毎年4〜10人（外れた年 %d）" % a_bad)
	_check(mon_bad == 0 and mon_total <= years, "怪物は年に0〜2人（多すぎた年 %d、30年で %d人）" % [mon_bad, mon_total])
	_check(hs_phenom >= 3 and hs_phenom <= 18, "高校生の化け物は数年に1人（30年で %d人）" % hs_phenom)
	_check(hs_strong <= years / 3, "化け物以外の高校生は入団時 B 以上がまれ（30年で %d人）" % hs_strong)
	_check(float(hs_cd) / maxf(1, hs_reg) >= 0.45, "高校生（本指名）の入団時は C〜D が中心（%.0f%%）" % (100.0 * hs_cd / maxf(1, hs_reg)))
	_check(float(top_p_starter) / maxf(1, top_p) >= 0.7, "当時の評価 S・A の投手の多くは先発型・スタミナ C 以上（%.0f%%）"
		% (100.0 * top_p_starter / maxf(1, top_p)))
	_check(star_names == 0, "名前に実在のスターの名前（大谷・朗希など、名選手と同じ姓名）を使わない（%d人）" % star_names)
	# 作業62：2025〜2027年の実在の新人と同じ物差し
	var ready_avg := 0.0
	for v: float in ready1:
		ready_avg += v / maxf(1, ready1.size())
	var tops_bad := tops.filter(func(t: int) -> bool: return t < 76 or t > 84)
	print("  その年の一番上 %s、1位の帯の大学・社会人など 平均 %.1f、怪物 %s、S・A の野手 %.0f%%"
		% [tops, ready_avg, mon_cat, 100.0 * sa_bat / maxf(1, sa_all)])
	_check(tops_bad.is_empty(), "その年の一番上は入団時の総合 78 前後〜82（怪物の年は 84 まで。外れた年 %s）" % [tops_bad])
	_check(ready_avg >= 68 and ready_avg <= 76, "大卒・社会人などの1位の帯は B 前後（平均 %.1f）" % ready_avg)
	_check(hs_top_weak == 0 and hs_top > 0, "高卒の S・A は武器（奪三振・パワー・走力・肩）を1つ B 以上（武器なし %d／%d人）" % [hs_top_weak, hs_top])
	_check(strong_not_monster == 0, "入団時の総合 A（80以上）は怪物だけ（怪物以外 %d人）" % strong_not_monster)
	_check(int(mon_cat.get("大学", 0)) + int(mon_cat.get("社会人", 0)) + int(mon_cat.get("独立", 0)) >= 2 and mon_weak == 0,
		"大学・社会人・独立からも怪物が出て、入団時から飛び抜けている（怪物 %s、足りない %d人 %s）" % [mon_cat, mon_weak, mon_weak_list])
	_check(float(sa_bat) / maxf(1, sa_all) >= 0.25, "S・A の野手もそれなりにいる（%.0f%%）" % (100.0 * sa_bat / maxf(1, sa_all)))
	# 所属の区分：独立リーグ・くふうハヤテは「独立」、専門学校は「専門」、古い社名は無い
	var bad_cat: Array = []
	var has_vocational := false
	for sc: Dictionary in fd.data.get("schools", []):
		var name := str(sc["name"])
		var cat := str(sc["category"])
		has_vocational = has_vocational or cat == "専門"
		if (("IL" in name or "BC" in name or "ハヤテ" in name or "インディゴ" in name) and cat != "独立") \
				or ("専門学校" in name and cat != "専門") or name in ["JX-ENEOS", "新日鐵住金鹿島", "三菱日立パワーシステムズ"] \
				or "分校" in name or "準硬式" in name:
			bad_cat.append("%s（%s）" % [name, cat])
	_check(bad_cat.is_empty() and has_vocational, "所属の区分（独立・専門学校）と今の社名、分校・準硬式は使わない（誤り %s）" % [bad_cat])
	# ドラフト画面の経歴：独立・専門学校の区分がそのまま出る
	_check(_draft.CATEGORY_CAREER.get("独立", "") == "独立" and _draft.career_of_row({"category": "専門", "school": "x専門学校"}) == "専門学校"
		and _draft.career_of_row({"school": "明治大"}) == "大学生", "ドラフト画面の経歴は架空の候補の区分から（独立・専門学校）")


## オフの段階を順に進めて year 年の開幕まで（作業54でドラフトのあとに FA・現役ドラフトなどが入った）
func _to_season(year: int) -> void:
	var guard := 0
	while not (_gs.year == year and _gs.phase == _gs.Phase.SEASON) and guard < 12:
		guard += 1
		_gs.advance()


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
	_to_season(2028)  # 2027年のドラフトはおまかせ → オフ（作業54：ドラフトのあとに FA など）→ 2028年の開幕
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
	# 作業67：その年の色はセンバツ号のはじめに出る（例年並みの年は出ない）
	var theme := str(cls[0]["amateur"].get("year_theme", ""))
	var theme_art := spring.filter(func(a: Dictionary) -> bool: return ("今年は" + theme) in str(a["headline"]))
	_check(not theme.is_empty() and (theme_art.size() == 1 or theme == "例年並み"),
		"2028年の色「%s」がセンバツ号に出る（%d本）" % [theme, theme_art.size()])
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
	# 作業69：ドラフトの時点で、候補の選手データ（選手詳細が読む）に弾道1〜4と具体的な守備位置
	var no_traj: Array = []
	for c: Dictionary in d.candidates:
		var cp: Dictionary = _gd.call("player", str(c["id"]))
		if cp.is_empty() or bool(cp.get("is_pitcher", false)):
			continue
		var tj: Variant = cp.get("batting", {}).get("trajectory")
		if tj == null or int(tj) < 1 or int(tj) > 4 or not str(cp.get("primary_pos", "")) in SimPlayer.POSITIONS:
			no_traj.append("%s（%s・%s）" % [cp["name"], str(tj), cp.get("primary_pos", "")])
	_check(no_traj.is_empty(), "ドラフトの候補（野手）は弾道と具体的な守備位置を持つ（無い %s）" % [no_traj.slice(0, 4)])
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
	var guard := 0
	while not (_gs.year == 2029 and _gs.phase == _gs.Phase.CAMP) and guard < 12:  # 作業54：ドラフトのあとに FA など
		guard += 1
		_gs.advance()
	_check(_gs.year == 2029 and _gs.phase == _gs.Phase.CAMP, "2029年の春季キャンプ（%s）" % _gs.date_text())
	var present := 0
	for rec: Dictionary in mine:
		if _gs.league.team_of.get(rec["id"], "") == USER and not _gd.call("player", rec["id"]).is_empty():
			present += 1
	_check(present == mine.size(), "指名した架空の選手 %d/%d人が自球団に所属" % [present, mine.size()])
	# 作業69：入団した架空の選手（自球団・CPU 球団とも）は弾道1〜4・具体的な守備位置と守備適性を持つ
	var joined := 0
	var bad_join: Array = []
	for rec: Dictionary in d.picks:
		var jp: Dictionary = _gd.call("player", str(rec["id"]))
		if jp.is_empty() or bool(jp.get("is_pitcher", false)):
			continue
		joined += 1
		var traj: Variant = jp.get("batting", {}).get("trajectory")
		var pos := str(jp.get("primary_pos", ""))
		var fld: Dictionary = jp.get("fielding", {})
		var keys_ok := not fld.is_empty()
		for k: String in fld:
			keys_ok = keys_ok and k in SimPlayer.POSITIONS
		if traj == null or int(traj) < 1 or int(traj) > 4 or not pos in SimPlayer.POSITIONS or not keys_ok \
				or not SimPlayer.from_rating(jp).can_play(pos):
			bad_join.append("%s（弾道 %s・%s・%s）" % [jp["name"], str(traj), pos, fld.keys()])
	_check(joined >= 20 and bad_join.is_empty(), "入団した架空の野手 %d人が弾道と具体的な守備位置を持つ（%s）" % [joined, bad_join.slice(0, 4)])
	# 作業69：作業66より前の形（守備位置「内野手」・弾道なし）の選手は、読み込むときに今の形になる
	var old := {"id": "fic:2028:999", "name": "古い 選手", "is_pitcher": false, "primary_pos": "内野手",
		"amateur": {"fictional": true, "category": "大学", "grade": "B"},
		"batting": {"ratings": {"meet": {"value": 72, "rank": "B"}, "power": {"value": 68, "rank": "C"},
			"eye": {"value": 55, "rank": "D"}, "speed": {"value": 60, "rank": "C"}}, "sample": {"pa_1": 0.0, "pa_2": 0.0}},
		"fielding": {"内野手": {"games": 0, "defense": {"value": 79, "rank": "B"}, "arm": {"value": 62, "rank": "C"}}}}
	_check(_fd.upgrade_old(old) and old["primary_pos"] == "遊撃手" and old["fielding"].has("二塁手")
		and int(old["batting"]["trajectory"]) in [1, 2, 3, 4] and int(old["batting"]["ratings"]["defense"]["value"]) == 79,
		"古い形の架空の選手（内野手 B79・弾道なし）→ 遊撃手（二塁手も）・弾道 %s" % str(old["batting"].get("trajectory")))
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


## 作業67：型・能力の散らばり・年の色・物語（30年分。入団時の能力だけを見る）
func _check_types() -> void:
	print("== 作業67：架空の候補の型・年の色・物語（30年分） ==")
	var fd: RefCounted = _fd.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2067
	var years := 30
	var bat_keys := ["meet", "power", "eye", "speed", "defense", "arm"]
	var types := {}
	var themes := {}
	var stories := 0
	var convert_weak := 0
	var of_shapes := {}
	var of_n := 0
	var bat_n := 0
	var bat_strong := 0
	var bat_weak := 0
	var by_grade := {}
	var named := 0
	var all_n := 0
	var same3 := 0
	var no_c := 0
	for y in range(2028, 2028 + years):
		var cls: Array = fd.generate_year(y, rng)
		themes[str(cls[0]["amateur"].get("year_theme", ""))] = int(themes.get(str(cls[0]["amateur"].get("year_theme", "")), 0)) + 1
		for p: Dictionary in cls:
			var am: Dictionary = p["amateur"]
			var group := FictionalTypes.pos_group(p)
			if not types.has(group):
				types[group] = {}
			types[group][str(am.get("type", ""))] = true
			all_n += 1
			named += 1 if str(am.get("type", "")) in str(am.get("intro", "")) else 0
			if not str(am.get("story", "")).is_empty():
				stories += 1
				if am.get("story_key") == "convert_bat" and int(p["batting"]["ratings"]["arm"]["value"]) < 70:
					convert_weak += 1
			var r: Dictionary = p["pitching"]["ratings"] if p["is_pitcher"] else p["batting"]["ratings"]
			var keys: Array = ["k9", "bb9", "hr9", "stamina"] if p["is_pitcher"] else bat_keys
			var hi := 0
			var lo := 0
			var shape := ""
			var seen := {}
			var has_c := false
			for k: String in keys:
				var v := int(r[k]["value"])
				# 長所は 66 以上・短所は 55 以下（作業73。ほかの能力は 50〜65）
				hi += 1 if v >= FictionalTypes.STRENGTH_MIN else 0
				lo += 1 if v < 50 else 0
				shape += "B" if v >= FictionalTypes.STRENGTH_MIN else ("e" if v < 50 else ".")
				seen[v] = int(seen.get(v, 0)) + 1
				has_c = has_c or (v >= 60 and v < 70)
			same3 += 1 if seen.values().max() >= 3 else 0
			var g := str(am["grade"])
			if not by_grade.has(g):
				by_grade[g] = [0, 0]
			by_grade[g][0] += 1
			by_grade[g][1] += hi
			if not p["is_pitcher"] and not p.has("reincarnation"):
				bat_n += 1
				bat_strong += 1 if hi >= 1 else 0
				bat_weak += 1 if lo >= 1 else 0
				no_c += 0 if has_c else 1
				if group == "外野手":
					of_n += 1
					of_shapes[shape] = int(of_shapes.get(shape, 0)) + 1
	var avg := func(g: String) -> float:
		return float(by_grade.get(g, [0, 0])[1]) / maxf(1, by_grade.get(g, [1, 0])[0])
	var top_shape := 0
	for k: String in of_shapes:
		top_shape = maxi(top_shape, int(of_shapes[k]))
	var counts := {}
	for g: String in types:
		counts[g] = types[g].size()
	print("  型の数 %s、年の色 %s、物語 %d人" % [counts, themes, stories])
	print("  長所（66 以上）の数の平均 S %.1f・A %.1f・B %.1f・C %.1f・D %.1f" % [avg.call("S"), avg.call("A"), avg.call("B"), avg.call("C"), avg.call("D")])
	_check(int(counts.get("投手", 0)) >= 9 and int(counts.get("捕手", 0)) >= 6 and int(counts.get("内野手", 0)) >= 8
		and int(counts.get("外野手", 0)) >= 8, "型は守備位置ごとに10前後（%s）" % counts)
	_check(float(named) / maxf(1, all_n) >= 0.9, "紹介文（手帳の札・作戦会議・ニュース）に型の名前（%d／%d人）" % [named, all_n])
	_check(float(top_shape) / maxf(1, of_n) <= 0.25,
		"外野手の能力の形がばらける（いちばん多い形 %d／%d人）" % [top_shape, of_n])
	_check(float(bat_strong) / maxf(1, bat_n) >= 0.95 and float(bat_weak) / maxf(1, bat_n) >= 0.7,
		"野手は長所（66 以上）を持ち、短所（50 未満）も多い（長所 %d・短所 %d／%d人）" % [bat_strong, bat_weak, bat_n])
	_check(avg.call("S") >= 2.0 and avg.call("A") >= 2.0 and avg.call("B") > avg.call("D") + 0.5,
		"評価の高い選手ほど長所が多い（S %.1f・A %.1f・B %.1f・D %.1f）" % [avg.call("S"), avg.call("A"), avg.call("B"), avg.call("D")])
	_check(themes.size() >= 6 and int(themes.get("例年並み", 0)) <= years / 2,
		"年の色は年ごとに変わる（%s）" % themes)
	# 作業73（ユーザー：「まだちょとDB BDみたいなの多いな」）：同じ選手の中に同じ数字が3つ以上並ばない・C の能力も出る
	_check(float(same3) / maxf(1, all_n) <= 0.02 and float(no_c) / maxf(1, bat_n) <= 0.42,
		"同じ数字が3つ以上並ぶ選手はまれ（%d／%d人）、C の無い野手は少なめ（%d／%d人）" % [same3, all_n, no_c, bat_n])
	_check(stories >= years * 4 and stories <= years * 12 and convert_weak == 0,
		"物語は年に数人、元投手の野手は肩が強い（%d人、肩の弱い元投手 %d人）" % [stories, convert_weak])
