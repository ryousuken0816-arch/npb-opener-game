class_name NewsDesk
extends RefCounted
## ニュースの記者（docs/AUTORUN.md 作業25）：試合の結果・月替わり・優勝争い・ポストシーズンから記事（News.article）を書き、
## GameState.post_news() で載せる。GameState が1つ持つ（state に GameState を渡す）。
##
## - 速報（その日の試合のあと）：ノーヒットノーラン・完全試合・サイクル安打（Records.feats）、通算記録の節目（MILESTONES。
##   ゲームを始める前の史実の1軍通算＋ゲーム内の過去の年＋今季）、自球団の選手のプロ初本塁打・初勝利、マジック点灯・優勝決定
## - 月ごとの新聞（月替わり）：首位争い（ゲーム差・マジック）、月間MVP（両リーグの野手・投手）、連勝・連敗、今月の記録、自球団の月間成績。
##   その月の試合が少ない（1球団 MIN_TEAM_GAMES 試合未満）ときは翌月の号とまとめる（3・4月号）。公式戦の最後は最終順位の号
## - ポストシーズン：シリーズの勝ち抜けの速報、日本一が決まったら日本シリーズ号

## 通算記録の節目 [成績のキー, 名前, 節目]
const MILESTONES := {
	"b": [["h", "本安打", [1000, 1500, 2000, 2500]], ["hr", "本塁打", [200, 300, 400, 500]],
		["rbi", "打点", [1000, 1500]], ["sb", "盗塁", [200, 300]]],
	"p": [["w", "勝", [100, 150, 200]], ["sv", "セーブ", [100, 200, 250, 300]],
		["so", "奪三振", [1500, 2000, 2500]], ["hld", "ホールド", [100, 200, 300]]],
}
## 月ごとの新聞を出すのに要る1球団あたりの試合数（届かない月は翌月とまとめる）
const MIN_TEAM_GAMES := 8
## 記事にする連勝・連敗
const STREAK_MIN := 6
## 月間MVPの資格（その期間の1球団あたりの試合数 × これ）
const MVP_PA_PER_GAME := 2.7
const MVP_OUTS_PER_GAME := 1.0
## 首位が独走とみなすゲーム差・接戦とみなすゲーム差
const RUNAWAY_GAMES := 8.0
const CLOSE_GAMES := 1.5

var gs: Node
var _career_year := -1
var _career := {}


func _init(state: Node) -> void:
	gs = state


# --- その日の試合 --------------------------------------------------------------------------

## date の試合（終わったもの）から速報を書く
func scan_day(date: String) -> void:
	var season: Season = gs.season
	if season == null:
		return
	var games: Array = []
	for g: Dictionary in season.games_on(date):
		if not g["result"].is_empty():
			games.append(g)
	if games.is_empty():
		return
	var team_of := func(id: String) -> String: return season.players.get(id, {}).get("team", "")
	for f: Dictionary in Records.feats(games, season.player_name, team_of):
		var opp := GameData.short_name(str(f["text"]).trim_suffix("戦"))
		var a := News.article(date, "feat", "%s（%s）が%s達成！" % [f["name"], GameData.short_name(f["team"]),
			f["kind"]], "%s、%s戦で%s。" % [News.date_label(date), opp, f["kind"]], [f["id"]], [f["team"]])
		gs.post_news(a, "", true)
	for g: Dictionary in games:
		var res: Dictionary = g["result"]
		for side in 2:
			var team: String = g["home"] if side == 1 else g["away"]
			var opp: String = g["away"] if side == 1 else g["home"]
			for line: Dictionary in res["batting"][side]:
				_check_line(date, line, "b", season.batting.get(line["id"], {}), team, opp)
			for line: Dictionary in res["pitching"][side]:
				_check_line(date, line, "p", season.pitching.get(line["id"], {}), team, opp)


## 1人の1試合の成績で通算の節目・初記録を越えたか
func _check_line(date: String, line: Dictionary, kind: String, season_total: Dictionary, team: String,
		opp: String) -> void:
	var id: String = line["id"]
	var name: String = gs.season.player_name(id)
	var before_season := career_before(id, kind)
	for m: Array in MILESTONES[kind]:
		var key: String = m[0]
		var today := int(line.get(key, 0))
		if today <= 0:
			continue
		var after := int(before_season.get(key, 0)) + int(season_total.get(key, 0))
		var before := after - today
		for mark: int in m[2]:
			if before < mark and after >= mark:
				var title := "通算%d%s" % [mark, m[1]]
				var body := "%s、%s戦で%s（%s）が%sを達成した。" % [News.date_label(date), GameData.short_name(opp), name,
					GameData.short_name(team), title]
				if key == "h" and mark == 2000:
					body += "名球会入りの条件を満たした。"
				gs.post_news(News.article(date, "milestone", "%s（%s）%s達成" % [name, GameData.short_name(team), title],
					body, [id], [team]), "", true)
		# 自球団の選手のプロ初本塁打・初勝利
		if team == gs.team and before == 0 and key in ["hr", "w"] and int(before_season.get(key, 0)) == 0:
			var what := "プロ初本塁打" if key == "hr" else "プロ初勝利"
			gs.post_news(News.article(date, "team", "%sが%s" % [name, what], "%s、%s戦で%sが%sを記録した。" % [
				News.date_label(date), GameData.short_name(opp), name, what], [id], [team]), "", true)


## 今季より前の1軍の通算（ゲームを始める前は史実、それ以降はゲーム内の成績）。kind は "b"（打撃）/"p"（投手）
func career_before(id: String, kind: String) -> Dictionary:
	if _career_year != gs.year:
		_career_year = gs.year
		_career = {}
	var key := kind + id
	if _career.has(key):
		return _career[key]
	var total := {}
	var base: Dictionary = gs.career_base().get("batting" if kind == "b" else "pitching", {})
	Records.add_into(total, base.get(id, {}))
	for y: String in gs.stats_history:
		if int(y) >= gs.year or int(y) < gs.first_year:
			continue
		var h: Dictionary = gs.stats_history[y]
		Records.add_into(total, h["batting" if kind == "b" else "pitching"].get(id, {}))
	_career[key] = total
	return total


# --- 優勝争い ------------------------------------------------------------------------------

func magic_lit(lg: String, team: String, magic: int, date: String) -> void:
	gs.post_news(News.article(date, "race", "%sにマジック%d点灯" % [GameData.short_name(team), magic],
		"%s、%sの首位%sに優勝へのマジックナンバー%dが点灯した。" % [News.date_label(date),
			GameData.LEAGUE_NAMES.get(lg, ""), GameData.short_name(team), magic], [], [team]), "", true)


func pennant_clinched(lg: String, team: String, date: String) -> void:
	var rec: Dictionary = gs.season.record_of(team)
	gs.post_news(News.article(date, "pennant", "%sが%s優勝！" % [GameData.short_name(team),
		GameData.LEAGUE_NAMES.get(lg, "")], "%s、%sが%sの優勝を決めた（%d勝%d敗%d分）。" % [News.date_label(date),
			team, GameData.LEAGUE_NAMES.get(lg, ""), rec["w"], rec["l"], rec["d"]], [], [team]), "", true)


# --- 月ごとの新聞 ---------------------------------------------------------------------------

## to_day（この日の前日まで）の分の新聞を出す。試合が少なければ出さずに次へまとめる（final は必ず出す）。出した号のキー
func monthly_issue(to_day: int, final := false) -> String:
	var season: Season = gs.season
	var news: News = gs.news
	if season == null or news == null:
		return ""
	var from_day := news.period_from if news.period_from >= 0 else season.first_day()
	var games: Array = []
	for g: Dictionary in season.games:
		if g["day"] >= from_day and g["day"] < to_day and not g["result"].is_empty():
			games.append(g)
	var team_games := games.size() * 2.0 / maxf(1.0, season.teams.size())
	if games.is_empty() or (team_games < MIN_TEAM_GAMES and not final):
		return ""
	news.period_from = to_day
	var months: Array[int] = []
	for g: Dictionary in games:
		var m := int(g["date"].substr(5, 2))
		if m not in months:
			months.append(m)
	var title := "%d年 %s月号" % [gs.year, _months_text(months)]
	if final:
		title = "%d年 ペナントレース最終号" % gs.year
	var key := "%d-%02d" % [gs.year, months[-1]]
	var date := Season.date_of_day(to_day)
	news.open_issue(key, title, date, gs.year)
	var stats := _period_stats(games)
	for lg: String in ["C", "P"]:
		_race_article(key, date, lg, final)
	for lg: String in ["C", "P"]:
		_mvp_article(key, date, lg, stats, team_games, months)
	_streak_article(key, date, from_day, to_day)
	_records_article(key, date, from_day, to_day)
	_my_team_article(key, date, games, stats, months, final)
	return key


## 期間の個人成績 {batting, pitching}（Season._add_line で足す）
static func _period_stats(games: Array) -> Dictionary:
	var bat := {}
	var pit := {}
	for g: Dictionary in games:
		var res: Dictionary = g["result"]
		for side in 2:
			for line: Dictionary in res["batting"][side]:
				Season._add_line(bat, line, ["pos", "order"])
			for line: Dictionary in res["pitching"][side]:
				Season._add_line(pit, line, [])
	return {"batting": bat, "pitching": pit}


func _race_article(key: String, date: String, lg: String, final: bool) -> void:
	var rows: Array[Dictionary] = gs.standings(lg)
	if rows.size() < 2:
		return
	var top: Dictionary = rows[0]
	var second: Dictionary = rows[1]
	var lg_name: String = GameData.LEAGUE_NAMES.get(lg, "")
	var short := GameData.short_name(top["team"])
	var gap: float = second["games_behind"]
	var lines: Array[String] = []
	for r: Dictionary in rows:
		lines.append("%d位 %s　%d勝%d敗%d分　%s" % [r["rank"], GameData.short_name(r["team"]), r["wins"], r["losses"],
			r["draws"], "-" if r["rank"] == 1 else _gb(r["games_behind"])])
	var headline := ""
	var race: Dictionary = gs.pennant_race.get(lg, {})
	if final:
		headline = "%s最終順位　%sが優勝" % [lg_name, short]
	elif race.has("clinched"):
		headline = "%s　%sが優勝を決める" % [lg_name, GameData.short_name(race.get("team", top["team"]))]
	elif gap <= CLOSE_GAMES:
		headline = "%s首位攻防、%sと%sが%sの大接戦" % [lg_name, short, GameData.short_name(second["team"]),
			"ゲーム差なし" if gap == 0.0 else _gb(gap) + "差"]
	elif gap >= RUNAWAY_GAMES:
		headline = "%sが独走、2位%sに%s差" % [short, GameData.short_name(second["team"]), _gb(gap)]
	else:
		headline = "%s首位は%s、2位%sと%s差" % [lg_name, short, GameData.short_name(second["team"]), _gb(gap)]
	var status: Dictionary = gs.pennant_status(lg)
	if not final and not race.has("clinched") and int(status.get("magic", -1)) > 0:
		headline += "　マジック%d" % status["magic"]
	gs.post_news(News.article(date, "standings" if final else "race", headline, "\n".join(lines), [],
		[top["team"], second["team"]]), key)


static func _months_text(months: Array[int]) -> String:
	var parts: Array[String] = []
	for m in months:
		parts.append(str(m))
	return "・".join(parts)


static func _gb(v: float) -> String:
	return ("%.1f" % v) if v != floorf(v) else ("%d.0" % int(v))


## 月間MVP：野手は wOBA の分子からリーグ平均程度を引いた得点換算、投手は防御率4点台との差の失点減＋勝利・セーブ
func _mvp_article(key: String, date: String, lg: String, stats: Dictionary, team_games: float,
		months: Array[int]) -> void:
	var bat := _best_batter(stats["batting"], lg, team_games * MVP_PA_PER_GAME)
	var pit := _best_pitcher(stats["pitching"], lg, team_games * MVP_OUTS_PER_GAME)
	if bat.is_empty() and pit.is_empty():
		return
	var parts: Array[String] = []
	var body: Array[String] = []
	var ids: Array = []
	var teams: Array = []
	for e: Dictionary in [bat, pit]:
		if e.is_empty():
			continue
		parts.append("%s（%s）" % [e["name"], GameData.short_name(e["team"])])
		body.append("%s：%s（%s）　%s" % [e["role"], e["name"], GameData.short_name(e["team"]), e["text"]])
		ids.append(e["id"])
		teams.append(e["team"])
	var month_text := _months_text(months)
	gs.post_news(News.article(date, "mvp", "%s%s月の月間MVPは%s" % [GameData.LEAGUE_NAMES.get(lg, ""), month_text,
		"と".join(parts)], "\n".join(body), ids, teams), key)


func _league_of_player(id: String) -> String:
	var team: String = gs.season.players.get(id, {}).get("team", "")
	return gs.season.leagues.get(team, "")


func _best_batter(bat: Dictionary, lg: String, min_pa: float) -> Dictionary:
	var best := ""
	var best_v := -1e9
	for id: String in bat:
		var b: Dictionary = bat[id]
		if _league_of_player(id) != lg or int(b["pa"]) < min_pa:
			continue
		var v := _bat_value(b)
		if v > best_v:
			best_v = v
			best = id
	if best.is_empty():
		return {}
	var b: Dictionary = bat[best]
	return {"id": best, "name": gs.season.player_name(best), "team": gs.season.players[best]["team"], "role": "野手",
		"text": "打率%s %d本塁打 %d打点%s" % [_avg(b), b["hr"], b["rbi"],
			" %d盗塁" % b["sb"] if int(b["sb"]) >= 5 else ""]}


static func _bat_value(b: Dictionary) -> float:
	var singles := int(b["h"]) - int(b["d"]) - int(b["t"]) - int(b["hr"])
	var num := 0.69 * int(b["bb"]) + 0.72 * int(b["hbp"]) + 0.89 * singles + 1.27 * int(b["d"]) \
		+ 1.62 * int(b["t"]) + 2.10 * int(b["hr"])
	return num - 0.33 * int(b["pa"]) + 0.2 * int(b["sb"])


static func _avg(b: Dictionary) -> String:
	var avg: float = float(b["h"]) / int(b["ab"]) if int(b["ab"]) > 0 else 0.0
	return ("%.3f" % avg).trim_prefix("0")


func _best_pitcher(pit: Dictionary, lg: String, min_outs: float) -> Dictionary:
	var best := ""
	var best_v := -1e9
	for id: String in pit:
		var p: Dictionary = pit[id]
		if _league_of_player(id) != lg:
			continue
		var outs := int(p["outs"])
		var relief := int(p.get("sv", 0)) + int(p.get("hld", 0)) >= 5
		if outs < min_outs and not relief:
			continue
		var v := outs / 27.0 * 4.2 - int(p["er"]) + int(p.get("w", 0)) * 0.6 + int(p.get("sv", 0)) * 0.5 \
			+ int(p["so"]) * 0.03
		if v > best_v:
			best_v = v
			best = id
	if best.is_empty():
		return {}
	var p: Dictionary = pit[best]
	var era := int(p["er"]) * 27.0 / int(p["outs"]) if int(p["outs"]) > 0 else 0.0
	var text := "%d勝%d敗 防御率%.2f %d奪三振" % [p.get("w", 0), p.get("l", 0), era, p["so"]]
	if int(p.get("sv", 0)) >= 3:
		text = "%d登板 %dセーブ 防御率%.2f" % [p["g"], p["sv"], era]
	return {"id": best, "name": gs.season.player_name(best), "team": gs.season.players[best]["team"], "role": "投手",
		"text": text}


## 期間に終わった最も長い連勝・連敗（STREAK_MIN 以上）
func _streak_article(key: String, date: String, from_day: int, to_day: int) -> void:
	var season: Season = gs.season
	var cur := {}
	var best := {}
	for g: Dictionary in season.games:
		if g["day"] >= to_day:
			break
		var res: Dictionary = g["result"]
		if res.is_empty():
			continue
		var hs: int = res["home_score"]
		var aws: int = res["away_score"]
		for side in 2:
			var team: String = g["home"] if side == 1 else g["away"]
			var c: Dictionary = cur.get_or_add(team, {"sign": 0, "n": 0})
			var sign := 0
			if hs != aws:
				sign = 1 if (hs > aws) == (side == 1) else -1
			if sign == 0:
				continue
			if c["sign"] == sign:
				c["n"] += 1
			else:
				c["sign"] = sign
				c["n"] = 1
			if g["day"] >= from_day and int(c["n"]) >= STREAK_MIN and int(c["n"]) > int(best.get("n", 0)):
				best = {"team": team, "n": c["n"], "sign": sign}
	if best.is_empty():
		return
	var short := GameData.short_name(best["team"])
	var headline := "%sが%d連勝" % [short, best["n"]] if best["sign"] > 0 else "%sが泥沼の%d連敗" % [short, best["n"]]
	var still: bool = cur[best["team"]]["sign"] == best["sign"] and cur[best["team"]]["n"] == best["n"]
	gs.post_news(News.article(date, "streak", headline, "%s（%s）" % [headline, "継続中" if still else "ストップ"],
		[], [best["team"]]), key)


## 期間の速報（記録達成・快挙）をまとめた記事
func _records_article(key: String, date: String, from_day: int, to_day: int) -> void:
	var lines: Array[String] = []
	var ids: Array = []
	var news: News = gs.news
	for a in news.between(Season.date_of_day(from_day), Season.date_of_day(to_day)):
		if a["kind"] in ["milestone", "feat"]:
			lines.append("%s　%s" % [News.date_label(a["date"]), a["headline"]])
			ids.append_array(a["players"])
	if lines.is_empty():
		return
	var head := lines[0].get_slice("　", 1) if lines.size() == 1 else "記録ラッシュ　%d件の達成" % lines.size()
	gs.post_news(News.article(date, "milestone", head, "\n".join(lines), ids, []), key)


func _my_team_article(key: String, date: String, games: Array, stats: Dictionary, months: Array[int],
		final: bool) -> void:
	var mine: String = gs.team
	var w := 0
	var l := 0
	var d := 0
	for g: Dictionary in games:
		if mine not in [g["home"], g["away"]]:
			continue
		var res: Dictionary = g["result"]
		var my_score: int = res["home_score"] if g["home"] == mine else res["away_score"]
		var opp_score: int = res["away_score"] if g["home"] == mine else res["home_score"]
		if my_score > opp_score:
			w += 1
		elif my_score < opp_score:
			l += 1
		else:
			d += 1
	if w + l + d == 0:
		return
	var lg := GameData.league_of(mine)
	var rank := 0
	for r: Dictionary in gs.standings(lg):
		if r["team"] == mine:
			rank = r["rank"]
	var mine_bat := {}
	var mine_pit := {}
	for id: String in stats["batting"]:
		if gs.season.players.get(id, {}).get("team", "") == mine:
			mine_bat[id] = stats["batting"][id]
	for id: String in stats["pitching"]:
		if gs.season.players.get(id, {}).get("team", "") == mine:
			mine_pit[id] = stats["pitching"][id]
	var games_n := float(w + l + d)
	var bat := _best_batter(mine_bat, lg, games_n * MVP_PA_PER_GAME * 0.7)
	var pit := _best_pitcher(mine_pit, lg, games_n * MVP_OUTS_PER_GAME * 0.7)
	var month_text := _months_text(months)
	var verdict := "勝ち越し" if w > l else ("負け越し" if w < l else "五分")
	var headline := "%s、%s月は%d勝%d敗%sで%s（%d位）" % [GameData.short_name(mine), month_text, w, l,
		"%d分" % d if d > 0 else "", verdict, rank]
	if final:
		headline = "%s、公式戦を%d位で終える" % [GameData.short_name(mine), rank]
	var body: Array[String] = ["月間成績 %d勝%d敗%d分　順位 %d位　%s" % [w, l, d, rank, gs.record_text()]]
	var ids: Array = []
	for e: Dictionary in [bat, pit]:
		if not e.is_empty():
			body.append("好調：%s　%s" % [e["name"], e["text"]])
			ids.append(e["id"])
	gs.post_news(News.article(date, "team", headline, "\n".join(body), ids, [mine]), key)


# --- ポストシーズン -------------------------------------------------------------------------

## シリーズの勝ち抜けの速報
func series_decided(s: Dictionary, date: String) -> void:
	var winner := GameData.short_name(s["winner"])
	var loser := GameData.short_name(s["loser"])
	var score := Postseason.score_text(s)
	var headline := ""
	match s["stage"]:
		"first":
			headline = "%sがCSファイナルへ　%sを%sで下す" % [winner, loser, score]
		"final", "final2020":
			headline = "%sが日本シリーズ進出　%sを%sで破る" % [winner, loser, score]
		_:
			headline = "%sが日本一！　%sを%sで下す" % [winner, loser, score]
	var mvp := Postseason.series_mvp(s)
	var body := "%s　%s %s %s" % [s["name"], winner, score, loser]
	var ids: Array = []
	if not mvp.is_empty():
		body += "\nMVP：%s　%s" % [gs.season.player_name(mvp["id"]), mvp["text"]]
		ids.append(mvp["id"])
	gs.post_news(News.article(date, "postseason", headline, body, ids, [s["winner"], s["loser"]]), "", true)


## 日本一が決まったら日本シリーズ号（日本一の記事・各シリーズの結果・自球団）
func postseason_issue(ps: Postseason, date: String) -> String:
	var key := "%d-js" % ps.year
	gs.news.open_issue(key, "%d年 日本シリーズ号" % ps.year, date, ps.year)
	var js := ps.get_series("JS")
	var mvp := Postseason.series_mvp(js)
	var champ := GameData.short_name(ps.champion)
	var body: Array[String] = ["日本シリーズ %s %s %s" % [champ, Postseason.score_text(js), GameData.short_name(js["loser"])]]
	for g: Dictionary in js["games"]:
		var r: Dictionary = g["result"]
		body.append("第%d戦（%s・%s）%s %d-%d %s" % [g["no"], News.date_label(g["date"]), g["venue"],
			GameData.short_name(g["away"]), r["away_score"], r["home_score"], GameData.short_name(g["home"])])
	var ids: Array = []
	if not mvp.is_empty():
		body.append("日本シリーズMVP：%s　%s" % [gs.season.player_name(mvp["id"]), mvp["text"]])
		ids.append(mvp["id"])
	gs.post_news(News.article(date, "postseason", "%sが%d年の日本一" % [champ, ps.year], "\n".join(body), ids,
		[ps.champion, js["loser"]]), key)
	var lines: Array[String] = []
	for s in ps.series:
		if s["stage"] == "js" or s["winner"].is_empty():
			continue
		lines.append("%s %s　%s %s %s" % ["セ" if s["league"] == "C" else "パ", s["name"],
			GameData.short_name(s["winner"]), Postseason.score_text(s), GameData.short_name(s["loser"])])
	if not lines.is_empty():
		gs.post_news(News.article(date, "postseason", "クライマックスシリーズの結果", "\n".join(lines), [], []), key)
	var mine: String = gs.team
	var mine_text := ""
	if mine == ps.champion:
		mine_text = "%sが日本一に輝いた。" % GameData.short_name(mine)
	elif mine == js["loser"]:
		mine_text = "%sは日本シリーズで敗れた。" % GameData.short_name(mine)
	else:
		var lg := GameData.league_of(mine)
		var rank: int = ps.order.get(lg, []).find(mine) + 1
		var cs := "CSで敗退" if rank in [1, 2, 3] else "Bクラス"
		mine_text = "%sは公式戦%d位（%s）でシーズンを終えた。" % [GameData.short_name(mine), rank, cs]
	gs.post_news(News.article(date, "team", mine_text.trim_suffix("。"), mine_text, [], [mine]), key)
	return key


# --- オフ ----------------------------------------------------------------------------------

## 表彰（MVP・新人王・沢村賞）の記事（オフ号に載せる）
func awards_article(year: int, key: String, date: String) -> void:
	var aw: Dictionary = gs.awards_of(year)
	if aw.is_empty():
		return
	var lines: Array[String] = []
	var ids: Array = []
	var mvps: Array[String] = []
	for lg: String in ["C", "P"]:
		var l: Dictionary = aw.get("leagues", {}).get(lg, {})
		for k: Array in [["mvp", "MVP"], ["rookie", "新人王"]]:
			var e: Variant = l.get(k[0])
			if e is Dictionary:
				lines.append("%s %s：%s（%s）%s" % ["セ" if lg == "C" else "パ", k[1], e["name"],
					GameData.short_name(e["team"]), e.get("text", "")])
				ids.append(e["id"])
				if k[0] == "mvp":
					mvps.append("%s%s" % ["セ" if lg == "C" else "パ", e["name"]])
	var saw: Variant = aw.get("sawamura")
	if saw is Dictionary:
		lines.append("沢村賞：%s（%s）%s" % [saw["name"], GameData.short_name(saw["team"]), saw.get("text", "")])
		ids.append(saw["id"])
	if lines.is_empty():
		return
	var headline := "%d年のMVPは%s" % [year, "・".join(mvps)] if not mvps.is_empty() else "%d年の表彰" % year
	gs.post_news(News.article(date, "awards", headline, "\n".join(lines), ids, []), key)
