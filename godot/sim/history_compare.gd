class_name HistoryCompare
extends RefCounted
## 史実との比較（docs/AUTORUN.md 作業24）：ゲームが史実と違う道に進んだことを記事（News）にし、年の終わりに「史実との比較」の号を出す。
## GameState が1つ持つ（state に GameState を渡す）。
##
## 史実の材料：
## - 優勝・日本一：HIST_CHAMPIONS（2008〜2025年。球団は略称）
## - 順位：data/<年>/schedule.json の実際のスコアから勝敗を数える（hist_standings）
## - タイトル：data/<年>/players.json のその年の1軍成績を Season の形にして、ゲームと同じ Awards の計算で出す（hist_titles）
## - 移籍：能力値ファイルの hist_team（その年の開幕時点の史実の球団）とゲームの所属
## - ドラフト：Draft の候補の hist_team・hist_round（史実の指名）とゲームの指名。史実で入団しなかった指名は HIST_UNSIGNED
## 記事を出す時：リーグ優勝の決定（史実と違えば速報）、日本一（日本シリーズ号）、表彰（タイトルの違い）、
## ドラフトのあと（ドラフトの違い）、春季キャンプ（移籍の違いと「史実との比較」の号）

## 史実の優勝（C・P）と日本一（js）
const HIST_CHAMPIONS := {
	2008: {"C": "巨人", "P": "西武", "js": "西武"}, 2009: {"C": "巨人", "P": "日本ハム", "js": "巨人"},
	2010: {"C": "中日", "P": "ソフトバンク", "js": "ロッテ"}, 2011: {"C": "中日", "P": "ソフトバンク", "js": "ソフトバンク"},
	2012: {"C": "巨人", "P": "日本ハム", "js": "巨人"}, 2013: {"C": "巨人", "P": "楽天", "js": "楽天"},
	2014: {"C": "巨人", "P": "ソフトバンク", "js": "ソフトバンク"}, 2015: {"C": "ヤクルト", "P": "ソフトバンク", "js": "ソフトバンク"},
	2016: {"C": "広島", "P": "日本ハム", "js": "日本ハム"}, 2017: {"C": "広島", "P": "ソフトバンク", "js": "ソフトバンク"},
	2018: {"C": "広島", "P": "西武", "js": "ソフトバンク"}, 2019: {"C": "巨人", "P": "西武", "js": "ソフトバンク"},
	2020: {"C": "巨人", "P": "ソフトバンク", "js": "ソフトバンク"}, 2021: {"C": "ヤクルト", "P": "オリックス", "js": "ヤクルト"},
	2022: {"C": "ヤクルト", "P": "オリックス", "js": "オリックス"}, 2023: {"C": "阪神", "P": "オリックス", "js": "阪神"},
	2024: {"C": "巨人", "P": "ソフトバンク", "js": "DeNA"}, 2025: {"C": "阪神", "P": "ソフトバンク", "js": "ソフトバンク"},
}
## 史実で指名されたが入団しなかった選手（ドラフトの年 → [名前]。ゲームで指名して入団したら記事にする）
const HIST_UNSIGNED := {
	2008: ["長野 久義"], 2011: ["菅野 智之"], 2025: ["佐々木 麟太郎"],
}
const CENTRAL_SHORT := ["巨人", "阪神", "中日", "横浜", "DeNA", "広島", "ヤクルト"]
## 移籍の違いの記事に出す人数（自球団以外は能力の高い順）
const TRANSFER_LINES := 8

var gs: Node
var _standings_cache := {}


func _init(state: Node) -> void:
	gs = state


static func hist_champion(year: int, key: String) -> String:
	var short: String = HIST_CHAMPIONS.get(year, {}).get(key, "")
	return GameData.resolve_team(short, year) if not short.is_empty() else ""


static func league_of_name(team: String) -> String:
	return "C" if GameData.short_name(team) in CENTRAL_SHORT else "P"


## 史実の順位（日程の実際のスコアから）：リーグ → [{team, w, l, d}]（勝率順）
func hist_standings(year: int) -> Dictionary:
	if _standings_cache.has(year):
		return _standings_cache[year]
	var rec := {}
	for g: Dictionary in GameData.load_schedule(year):
		if g.get("status", "") != "played" or g.get("home_score") == null or g.get("away_score") == null:
			continue
		var home := GameData.resolve_team(g["home"], year)
		var away := GameData.resolve_team(g["away"], year)
		var hs := int(g["home_score"])
		var aws := int(g["away_score"])
		for t: String in [home, away]:
			rec.get_or_add(t, {"team": t, "w": 0, "l": 0, "d": 0})
		if hs > aws:
			rec[home]["w"] += 1
			rec[away]["l"] += 1
		elif hs < aws:
			rec[home]["l"] += 1
			rec[away]["w"] += 1
		else:
			rec[home]["d"] += 1
			rec[away]["d"] += 1
	var result := {"C": [], "P": []}
	for t: String in rec:
		result[league_of_name(t)].append(rec[t])
	for lg: String in result:
		result[lg].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _pct(a) > _pct(b))
	_standings_cache[year] = result
	return result


static func _pct(r: Dictionary) -> float:
	var dec := int(r["w"]) + int(r["l"])
	return float(r["w"]) / dec if dec > 0 else 0.0


## 史実のタイトル（リーグ → Awards の titles と同じ形）。その年の選手ページが無ければ空
func hist_titles(year: int) -> Dictionary:
	var pages: Dictionary = GameData.all_player_pages(year)
	if pages.is_empty():
		return {}
	var s := Season.new(year, {"players": []}, [], 1)
	for id: String in pages:
		var page: Dictionary = pages[id]
		var team := ""
		for kind: String in ["batting", "pitching"]:
			for row: Variant in page.get(kind, []):
				if not (row is Dictionary) or int(row.get("年度", 0)) != year:
					continue
				var line := Records.from_page_batting(row) if kind == "batting" else Records.from_page_pitching(row)
				Records.add_into((s.batting if kind == "batting" else s.pitching).get_or_add(id, {}), line)
				team = GameData.resolve_team(str(row.get("所属球団", "")), year)
		if not team.is_empty():
			s.players[id] = {"name": str(page.get("name", id)), "team": team}
	for lg: String in ["C", "P"]:
		for r: Dictionary in hist_standings(year)[lg]:
			s.records[r["team"]] = {"w": r["w"], "l": r["l"], "d": r["d"], "rs": 0, "ra": 0}
			s.leagues[r["team"]] = lg
	# 所属の分からない成績（球団名が引けない）は除く
	for kind_dict: Dictionary in [s.batting, s.pitching]:
		for id: String in kind_dict.keys():
			if not s.players.has(id):
				kind_dict.erase(id)
	var a := Awards.new()
	a._season = s
	a._player_of = GameData.player
	for team: String in s.records:
		var rec: Dictionary = s.records[team]
		a._team_games[team] = int(rec["w"]) + int(rec["l"]) + int(rec["d"])
	return {"C": a._titles("C"), "P": a._titles("P")}


# --- その場の記事 ---------------------------------------------------------------------------

## リーグ優勝が決まったとき：史実と違えば速報
func pennant_decided(lg: String, team: String, date: String) -> void:
	var hist := hist_champion(gs.year, lg)
	if hist.is_empty() or hist == team:
		return
	gs.post_news(News.article(date, "divergence", "史実ではこの年%sが優勝　ゲームでは%s" % [GameData.short_name(hist),
		GameData.short_name(team)], "%d年の%s、史実の優勝は%s。ゲームでは%sが優勝した。" % [gs.year,
			GameData.LEAGUE_NAMES.get(lg, ""), hist, team], [], [team, hist]), "", true)


## 日本一が決まったとき（日本シリーズ号に載せる）
func postseason_decided(ps: Postseason, key: String, date: String) -> void:
	var hist := hist_champion(ps.year, "js")
	if hist.is_empty():
		return
	var lines: Array[String] = []
	for lg: String in ["C", "P"]:
		var h := hist_champion(ps.year, lg)
		var g: String = ps.order.get(lg, [""])[0]
		lines.append("%s優勝：ゲーム %s／史実 %s%s" % ["セ" if lg == "C" else "パ", GameData.short_name(g),
			GameData.short_name(h), "" if g == h else "（違い）"])
	lines.append("日本一：ゲーム %s／史実 %s%s" % [GameData.short_name(ps.champion), GameData.short_name(hist),
		"" if ps.champion == hist else "（違い）"])
	var same := ps.champion == hist
	var headline := "史実どおり%sが日本一" % GameData.short_name(hist) if same else \
		"史実の日本一は%s　ゲームでは%sが頂点に" % [GameData.short_name(hist), GameData.short_name(ps.champion)]
	gs.post_news(News.article(date, "divergence", headline, "\n".join(lines), [], [ps.champion, hist]), key)


## 表彰のあと：タイトルの違い（号に載せる）
func titles_decided(year: int, key: String, date: String) -> void:
	var game: Dictionary = gs.awards_of(year)
	if game.is_empty():
		return
	var hist := hist_titles(year)
	if hist.is_empty():
		return
	var lines: Array[String] = []
	var ids: Array = []
	var same := 0
	for lg: String in ["C", "P"]:
		var game_titles: Array = game.get("leagues", {}).get(lg, {}).get("titles", [])
		var hist_titles_lg: Array = hist.get(lg, [])
		for i in mini(game_titles.size(), hist_titles_lg.size()):
			var gt: Dictionary = game_titles[i]
			var ht: Dictionary = hist_titles_lg[i]
			var g_names := _winner_names(gt)
			var h_names := _winner_names(ht)
			if g_names == h_names:
				same += 1
				continue
			lines.append("%s %s：ゲーム %s（%s）／史実 %s（%s）" % ["セ" if lg == "C" else "パ", gt["name"], g_names,
				gt.get("value_text", ""), h_names, ht.get("value_text", "")])
			for w: Dictionary in gt.get("winners", []):
				ids.append(w["id"])
	var headline := "タイトルは%d部門で史実と違う顔ぶれ" % lines.size() if not lines.is_empty() else "タイトルはすべて史実どおり"
	if same > 0 and not lines.is_empty():
		headline += "（史実どおり%d部門）" % same
	gs.post_news(News.article(date, "divergence", headline, "\n".join(lines), ids, []), key)


static func _winner_names(t: Dictionary) -> String:
	var names: Array[String] = []
	for w: Dictionary in t.get("winners", []):
		names.append(str(w.get("name", "")).replace(" ", "").replace("　", ""))
	return "・".join(names) if not names.is_empty() else "該当なし"


## ドラフトのあと：自球団の指名と史実、各球団の1位の違い、史実で入団しなかった選手の指名
func draft_decided(draft: Draft, key: String, date: String) -> void:
	if draft == null:
		return
	var mine: String = gs.team
	var lines: Array[String] = []
	var ids: Array = []
	for p: Dictionary in draft.picks:
		if p["team"] != mine:
			continue
		var c: Dictionary = draft.by_id.get(p["id"], {})
		var hist_text := _hist_pick_text(c)
		var same: bool = c.get("hist_team", "") == mine and int(c.get("hist_round", 0)) == int(p["round"]) \
			and bool(c.get("hist_ikusei", false)) == bool(p["ikusei"])
		lines.append("%s %s（史実：%s）%s" % [p["label"], c.get("name", p["name"]), hist_text, "" if same else "★"])
		ids.append(p["id"])
	if not lines.is_empty():
		gs.post_news(News.article(date, "divergence", "%sのドラフト　史実との違い" % GameData.short_name(mine),
			"\n".join(lines) + "\n★＝史実と違う指名", ids, [mine]), key)
	# 各球団の1位
	var firsts: Array[String] = []
	var first_ids: Array = []
	for team: String in draft.teams:
		var game_first: String = draft.first_pick_of(team)
		var hist_first := ""
		for c: Dictionary in draft.candidates:
			if c.get("hist_team", "") == team and int(c.get("hist_round", 0)) == 1 and not c.get("hist_ikusei", false):
				hist_first = c["id"]
				break
		if game_first.is_empty() or game_first == hist_first:
			continue
		var gc: Dictionary = draft.by_id.get(game_first, {})
		var hc: Dictionary = draft.by_id.get(hist_first, {})
		firsts.append("%s：ゲーム %s／史実 %s" % [GameData.short_name(team), gc.get("name", "-"), hc.get("name", "-")])
		first_ids.append(game_first)
	if not firsts.is_empty():
		gs.post_news(News.article(date, "divergence", "ドラフト1位、%d球団が史実と違う選手を指名" % firsts.size(),
			"\n".join(firsts), first_ids, []), key)
	# 史実で入団しなかった指名選手
	for name: String in HIST_UNSIGNED.get(draft.year, []):
		for c: Dictionary in draft.candidates:
			if LeagueRoster.norm_name(c["name"]) != LeagueRoster.norm_name(name) or str(c.get("picked_by", "")).is_empty():
				continue
			var team: String = c["picked_by"]
			gs.post_news(News.article(date, "divergence", "史実では入団しなかった%sを%sが%sで指名" % [
				c["name"].replace(" ", ""), GameData.short_name(team), c.get("pick_label", "")],
				"史実：%s（入団せず）。ゲームでは%sが%sで指名した。" % [_hist_pick_text(c), team, c.get("pick_label", "")],
				[c["id"]], [team]), key)


static func _hist_pick_text(c: Dictionary) -> String:
	var team: String = c.get("hist_team", "")
	if team.is_empty():
		return "指名なし"
	return "%s%s" % [GameData.short_name(team), c.get("hist_label", "")]


## 新しい年の能力値を読んだあと（春季キャンプ）：史実の球団と今の所属が違う選手の記事の行。
## {mine_kept: [...], mine_lost: [...], others: [...], ids: [...]}（行は文字列）
func transfer_lines() -> Dictionary:
	var mine: String = gs.team
	var kept: Array[String] = []
	var lost: Array[String] = []
	var others: Array = []
	var ids: Array = []
	for p: Dictionary in GameData.ratings.get("players", []):
		var hist: String = str(p.get("hist_team", ""))
		var team: String = str(p.get("team", ""))
		if hist.is_empty() or team.is_empty() or GameData.short_name(hist) == GameData.short_name(team):
			continue
		var line := "%s：史実 %s／ゲーム %s" % [p["name"], GameData.short_name(hist), GameData.short_name(team)]
		if team == mine:
			kept.append(line)
			ids.append(p["id"])
		elif GameData.short_name(hist) == GameData.short_name(mine):
			lost.append(line)
			ids.append(p["id"])
		else:
			var ab := Salary.ability(p)
			others.append([float(ab[0]) + float(ab[1]), line, p["id"]])
	others.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var top: Array[String] = []
	for i in mini(TRANSFER_LINES, others.size()):
		top.append(others[i][1])
		ids.append(others[i][2])
	return {"mine_kept": kept, "mine_lost": lost, "others": top, "others_total": others.size(), "ids": ids}


# --- 年の終わりの「史実との比較」 ------------------------------------------------------------

## 春季キャンプに入ったとき（year はいま終わった年）：史実との比較の号。号のキー
func year_summary(year: int, draft: Draft) -> String:
	var key := "%d-history" % year
	var date := "%d-02-01" % (year + 1)
	gs.news.open_issue(key, "%d年 史実との比較" % year, date, year)
	var body: Array[String] = []
	var diffs := 0
	# 順位
	var st: Dictionary = gs.season_stats(year)
	var hist := hist_standings(year)
	for lg: String in ["C", "P"]:
		var game_order := _game_order(st, lg)
		var hist_order: Array[String] = []
		for r: Dictionary in hist.get(lg, []):
			hist_order.append(GameData.short_name(r["team"]))
		if game_order.is_empty() or hist_order.is_empty():
			continue
		body.append("【%s順位】ゲーム %s" % [GameData.LEAGUE_NAMES.get(lg, ""), " ".join(game_order)])
		body.append("　　　　　史実 %s" % " ".join(hist_order))
		for i in mini(game_order.size(), hist_order.size()):
			if game_order[i] != hist_order[i]:
				diffs += 1
	# 優勝・日本一
	var ph: Dictionary = gs.postseason_history.get(str(year), {})
	if HIST_CHAMPIONS.has(year):
		for k: String in ["C", "P", "js"]:
			var g := str(ph.get("champion", "")) if k == "js" else str(ph.get("pennant", {}).get(k, ""))
			var h := hist_champion(year, k)
			var label := "日本一" if k == "js" else "%s優勝" % ("セ" if k == "C" else "パ")
			body.append("【%s】ゲーム %s／史実 %s%s" % [label, GameData.short_name(g), GameData.short_name(h),
				"" if g == h else "　★"])
	# 移籍
	var tl := transfer_lines()
	body.append("【移籍の違い】史実と所属が違う選手 %d人（自球団に残った%d人・自球団から出た%d人を含む）" % [
		tl["others_total"] + tl["mine_kept"].size() + tl["mine_lost"].size(), tl["mine_kept"].size(),
		tl["mine_lost"].size()])
	# ドラフト1位
	if draft != null:
		var n := 0
		for team: String in draft.teams:
			var gf: String = draft.first_pick_of(team)
			for c: Dictionary in draft.candidates:
				if c.get("hist_team", "") == team and int(c.get("hist_round", 0)) == 1 and not c.get("hist_ikusei", false):
					if c["id"] != gf:
						n += 1
					break
		body.append("【ドラフト1位】史実と違う球団 %d" % n)
	var headline := "%d年は史実と%s" % [year, "違う一年に" if diffs > 0 or _champion_differs(year, ph) else "ほぼ同じ一年"]
	if _champion_differs(year, ph):
		headline = "%d年、日本一は史実の%sではなく%s" % [year, GameData.short_name(hist_champion(year, "js")),
			GameData.short_name(str(ph.get("champion", "")))]
	gs.post_news(News.article(date, "history", headline, "\n".join(body), [], []), key)
	if not tl["mine_kept"].is_empty() or not tl["mine_lost"].is_empty():
		var lines: Array[String] = []
		for l: String in tl["mine_kept"]:
			lines.append("残留・加入　" + l)
		for l: String in tl["mine_lost"]:
			lines.append("流出　" + l)
		gs.post_news(News.article(date, "divergence", "史実と違う%sの顔ぶれ（%d人）" % [GameData.short_name(gs.team),
			lines.size()], "\n".join(lines), tl["ids"], [gs.team]), key)
	if not tl["others"].is_empty():
		gs.post_news(News.article(date, "divergence", "主な移籍の違い　史実と違う球団でプレーする選手",
			"\n".join(tl["others"]), tl["ids"], []), key)
	return key


static func _champion_differs(year: int, ph: Dictionary) -> bool:
	if ph.is_empty() or not HIST_CHAMPIONS.has(year):
		return false
	return str(ph.get("champion", "")) != hist_champion(year, "js")


## ゲームの順位（略称、勝率順）
static func _game_order(st: Dictionary, lg: String) -> Array[String]:
	var rows: Array = []
	var records: Dictionary = st.get("records", {})
	for team: String in records:
		if st.get("leagues", {}).get(team, "") == lg:
			rows.append({"team": team, "w": records[team]["w"], "l": records[team]["l"]})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _pct(a) > _pct(b))
	var result: Array[String] = []
	for r: Dictionary in rows:
		result.append(GameData.short_name(r["team"]))
	return result
