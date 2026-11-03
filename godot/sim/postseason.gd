# gdlint: disable=max-public-methods
class_name Postseason
extends RefCounted
## ポストシーズン（クライマックスシリーズ・日本シリーズ。docs/AUTORUN.md 作業23）。
##
## 公式戦の最終日のあと、表彰の前に行う。試合は Season の各球団の SimTeam をそのまま使い（先発の登板間隔も
## 引き継ぐ）、GameSim で1試合ずつ行う。個人成績は公式戦（Season.batting/pitching）に足さず、ここで別に持つ。
##
## 形式（史実の年ごとのルール）：
## - ファーストステージ：2位と3位、2位の本拠地で最大3試合・2勝で勝ち抜け
## - ファイナルステージ：1位とファーストの勝者、1位の本拠地で最大6試合・4勝で勝ち抜け（1位に1勝のアドバンテージ）
## - 勝ち数が並んだまま試合が尽きたら（引き分けがあったとき）上位の球団が勝ち抜け
## - 2020年：セはCSなし（優勝球団がそのまま日本シリーズ）、パは1位と2位の4試合・3勝（1位に1勝のアドバンテージ）
## - 日本シリーズ：7試合・4勝。偶数年はセ、奇数年はパの球団が第1・2・6・7戦を主催。引き分けで決まらなければ第8戦以降
## 日程は公式戦の最終日から（史実の日付に近い間隔）：ファーストは最終日の3日後から3日間、ファイナルはその4日後から、
## 日本シリーズはファイナルの初戦の12日後から（第1・2戦→移動日→第3〜5戦→移動日→第6・7戦）。
##
## オートロードは参照しない（球団の並び・リーグは呼び出し側が渡す）

## [キー, 名前, 最大試合数, 勝ち抜けに要る勝ち数, 上位の球団のアドバンテージ]
const STAGES := {
	"first": ["CSファーストステージ", 3, 2, 0],
	"final": ["CSファイナルステージ", 6, 4, 1],
	"final2020": ["クライマックスシリーズ", 4, 3, 1],
	"js": ["日本シリーズ", 7, 4, 0],
}
## 公式戦の最終日から各段階の初戦までの日数
const FIRST_OFFSET := 3
const FINAL_OFFSET := 7
const JS_OFFSET := 19
## 日本シリーズの第n戦の初戦からの日数（第8戦以降は前の試合の翌日）
const JS_DAYS := [0, 1, 3, 4, 5, 7, 8]
## CSの無い年（リーグ → true）
const NO_CS := {2020: {"C": true}}
## 1位と2位だけの短いCS（2020年のパ）
const SHORT_CS := {2020: {"P": true}}

var year: int
## [{key, stage, league, name, round, high, low, adv, need, max_games, games: [...], wins: {球団: n}, winner, loser}]
## games の各試合は {no, day, date, home, away, venue, result}（result は GameSim.play() の結果。未試合は空）
var series: Array[Dictionary] = []
## リーグ → 順位どおりの球団（公式戦の最終順位）
var order := {}
## 個人成績（ポストシーズン全体の合計。公式戦とは別）
var batting := {}
var pitching := {}
## 日本一の球団（決まるまで空）
var champion := ""

var _rng := RandomNumberGenerator.new()
var _venues := {}


## season: 終わった公式戦、standings: リーグ → 順位どおりの球団名（GameState.standings の並び）
func setup(season: Season, season_year: int, standings: Dictionary, seed_value: int) -> void:
	year = season_year
	_rng.seed = seed_value
	order = standings.duplicate(true)
	_venues = home_venues(season)
	var base := season.last_day()
	var js_first := base + JS_OFFSET
	var reps := {}
	for lg: String in ["C", "P"]:
		var teams: Array = order.get(lg, [])
		if teams.is_empty():
			continue
		if NO_CS.get(year, {}).get(lg, false) or teams.size() < 3:
			reps[lg] = teams[0]
			continue
		if SHORT_CS.get(year, {}).get(lg, false):
			_add_series(lg + "2", "final2020", lg, 2, teams[0], teams[1], base + FINAL_OFFSET)
			continue
		_add_series(lg + "1", "first", lg, 1, teams[1], teams[2], base + FIRST_OFFSET)
		_add_series(lg + "2", "final", lg, 2, teams[0], "", base + FINAL_OFFSET)
	# 日本シリーズ（主催：偶数年はセ、奇数年はパの球団が第1戦）
	_add_series("JS", "js", "", 3, reps.get("C", ""), reps.get("P", ""), js_first)
	_assign_js_homes()


func _add_series(key: String, stage: String, lg: String, round_no: int, high: String, low: String,
		first_day: int) -> void:
	var st: Array = STAGES[stage]
	var s := {
		"key": key, "stage": stage, "league": lg, "name": st[0], "round": round_no,
		"high": high, "low": low, "adv": st[3], "need": st[2], "max_games": st[1],
		"games": [], "wins": {}, "draws": 0, "winner": "", "loser": "",
	}
	for i in st[1]:
		var d: int = first_day + (JS_DAYS[i] if stage == "js" else i)
		s["games"].append({"no": i + 1, "day": d, "date": Season.date_of_day(d), "home": "", "away": "",
			"venue": "", "result": {}})
	series.append(s)
	_assign_homes(s)


## 球団の本拠地：その年の公式戦で主催した試合が最も多い球場
static func home_venues(season: Season) -> Dictionary:
	var counts := {}
	for g: Dictionary in season.games:
		var home: String = g["home"]
		var v: String = g.get("venue", "")
		if v.is_empty():
			continue
		var c: Dictionary = counts.get_or_add(home, {})
		c[v] = int(c.get(v, 0)) + 1
	var result := {}
	for team: String in counts:
		var best := ""
		for v: String in counts[team]:
			if best.is_empty() or counts[team][v] > counts[team][best]:
				best = v
		result[team] = best
	return result


## CS：ファーストは2位、ファイナルは1位の本拠地で全試合
func _assign_homes(s: Dictionary) -> void:
	if s["stage"] == "js":
		return
	for g: Dictionary in s["games"]:
		g["home"] = s["high"]
		g["away"] = s["low"]
		g["venue"] = _venues.get(s["high"], "")


## 日本シリーズ：第1・2・6・7戦（と第8戦以降）は A、第3〜5戦は B の主催
func _assign_js_homes() -> void:
	var s := get_series("JS")
	if s.is_empty():
		return
	var central: String = s["high"]
	var pacific: String = s["low"]
	var a := central if year % 2 == 0 else pacific
	var b := pacific if year % 2 == 0 else central
	for g: Dictionary in s["games"]:
		var host := b if g["no"] in [3, 4, 5] else a
		var guest := a if host == b else b
		g["home"] = host
		g["away"] = guest
		g["venue"] = _venues.get(host, "") if not host.is_empty() else ""


func get_series(key: String) -> Dictionary:
	for s in series:
		if s["key"] == key:
			return s
	return {}


## 試合を行う段階が残っていない（日本一が決まった）
func is_finished() -> bool:
	return not champion.is_empty()


func first_day() -> int:
	var d := 1 << 30
	for s in series:
		for g: Dictionary in s["games"]:
			d = mini(d, g["day"])
	return d


## 最後に試合をする予定の日（決まったシリーズの残りは消してある）
func last_day() -> int:
	var d := 0
	for s in series:
		for g: Dictionary in s["games"]:
			d = maxi(d, g["day"])
	return d


## from_day 以降で次に試合がある日（無ければ from_day）
func next_game_day(from_day: int) -> int:
	var best := -1
	for s in series:
		if not s["winner"].is_empty():
			continue
		for g: Dictionary in s["games"]:
			if g["result"].is_empty() and g["day"] >= from_day and (best < 0 or g["day"] < best):
				best = g["day"]
	return best if best >= 0 else from_day


## 今の段階（まだ決まっていないシリーズの中で最も早い回）。全部決まれば 0
func current_round() -> int:
	var r := 0
	for s in series:
		if s["winner"].is_empty() and (r == 0 or s["round"] < r):
			r = s["round"]
	return r


## その回の最後の試合の予定日
func round_last_day(round_no: int) -> int:
	var d := 0
	for s in series:
		if s["round"] == round_no:
			for g: Dictionary in s["games"]:
				d = maxi(d, g["day"])
	return d


## team がまだ勝ち残っていて、これから試合があるか
func team_alive(team: String) -> bool:
	for s in series:
		if s["winner"].is_empty() and team in [s["high"], s["low"]]:
			return true
		if s["winner"].is_empty() and s["low"].is_empty() and _feeds(team, s):
			return true
	return false


## team がまだ決まっていない枠（ファイナルの相手・日本シリーズ）に入る可能性があるか
func _feeds(team: String, target: Dictionary) -> bool:
	for s in series:
		if s["round"] < target["round"] and s["winner"].is_empty() and team in [s["high"], s["low"]] \
				and (target["league"].is_empty() or s["league"] == target["league"]):
			return true
	return false


## その日の試合を行う。行った試合 [{series, game}]（決着で消えた試合は行わない）
func play_day(day: int, teams: Dictionary) -> Array[Dictionary]:
	var played: Array[Dictionary] = []
	for s in series:
		if not s["winner"].is_empty() or s["high"].is_empty() or s["low"].is_empty():
			continue
		for g: Dictionary in s["games"]:
			if g["day"] != day or not g["result"].is_empty():
				continue
			if not teams.has(g["home"]) or not teams.has(g["away"]):
				continue
			_play(s, g, teams)
			played.append({"series": s, "game": g})
	return played


func _play(s: Dictionary, g: Dictionary, teams: Dictionary) -> void:
	var home: SimTeam = teams[g["home"]]
	var away: SimTeam = teams[g["away"]]
	var dh: bool = home.league == "P"
	var game := GameSim.new(away, home, g["day"], dh, _rng)
	game.set_env(RunEnv.for_year(year))
	var result := game.play()
	result.erase("fielding")  # 守備得点は公式戦だけ
	g["result"] = result
	for side in 2:
		for line: Dictionary in result["batting"][side]:
			Season._add_line(batting, line, ["pos", "order"])
		for line: Dictionary in result["pitching"][side]:
			Season._add_line(pitching, line, [])
	Season.compact_result(result)
	var hs: int = result["home_score"]
	var aws: int = result["away_score"]
	if hs == aws:
		s["draws"] += 1
	else:
		var w: String = g["home"] if hs > aws else g["away"]
		s["wins"][w] = int(s["wins"].get(w, 0)) + 1
	_check_decided(s, g)


## 勝ち抜けが決まったら勝者を決め、残りの試合を消して次の回の枠に入れる。
## 日本シリーズが引き分けで決まらないまま試合が尽きたら、翌日に第8戦以降を足す
func _check_decided(s: Dictionary, last: Dictionary) -> void:
	var hw := wins_of(s, s["high"])
	var lw := wins_of(s, s["low"])
	var need: int = s["need"]
	var winner := ""
	if hw >= need:
		winner = s["high"]
	elif lw >= need:
		winner = s["low"]
	else:
		var left := 0
		for g: Dictionary in s["games"]:
			if g["result"].is_empty():
				left += 1
		if left == 0:
			if s["stage"] == "js":
				var d: int = last["day"] + 1
				s["games"].append({"no": s["games"].size() + 1, "day": d, "date": Season.date_of_day(d),
					"home": last["home"], "away": last["away"], "venue": last["venue"], "result": {}})
				return
			winner = s["high"] if hw >= lw else s["low"]
	if winner.is_empty():
		return
	s["winner"] = winner
	s["loser"] = s["low"] if winner == s["high"] else s["high"]
	var kept: Array = []
	for g: Dictionary in s["games"]:
		if not g["result"].is_empty():
			kept.append(g)
	s["games"] = kept
	_advance_winner(s)


func _advance_winner(s: Dictionary) -> void:
	if s["stage"] == "js":
		champion = s["winner"]
		return
	if s["stage"] == "first":
		var fin := get_series(s["league"] + "2")
		if not fin.is_empty():
			fin["low"] = s["winner"]
			_assign_homes(fin)
		return
	var js := get_series("JS")
	js["high" if s["league"] == "C" else "low"] = s["winner"]
	_assign_js_homes()


## シリーズの勝ち数（アドバンテージを含む）
static func wins_of(s: Dictionary, team: String) -> int:
	if team.is_empty():
		return 0
	return int(s["wins"].get(team, 0)) + (int(s["adv"]) if team == s["high"] else 0)


## 例：「4勝2敗」「4勝1敗1分」（アドバンテージを含む勝ち数。winner 側から見る）
static func score_text(s: Dictionary, team: String = "") -> String:
	var t: String = team if not team.is_empty() else (s["winner"] if not s["winner"].is_empty() else s["high"])
	var other: String = s["low"] if t == s["high"] else s["high"]
	var text := "%d勝%d敗" % [wins_of(s, t), wins_of(s, other)]
	if int(s["draws"]) > 0:
		text += "%d分" % s["draws"]
	return text


## 今日（day）の行事の名前（ハブの上の見出し）
func stage_name(day: int) -> String:
	if is_finished():
		return "日本一決定"
	var r := current_round()
	for s in series:
		if s["round"] == r:
			return "日本シリーズ" if s["stage"] == "js" else "クライマックスシリーズ"
	return "ポストシーズン"


## その日に予定された試合 [{series, game}]
func games_on(day: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for s in series:
		for g: Dictionary in s["games"]:
			if g["day"] == day:
				result.append({"series": s, "game": g})
	return result


## シリーズの最優秀選手（勝った球団の選手で、そのシリーズの打撃・投球の得点換算が最も高い選手）。{id, text} か空
static func series_mvp(s: Dictionary) -> Dictionary:
	if s["winner"].is_empty():
		return {}
	var bat := {}
	var pit := {}
	for g: Dictionary in s["games"]:
		var res: Dictionary = g["result"]
		if res.is_empty():
			continue
		var side := 1 if g["home"] == s["winner"] else 0
		for line: Dictionary in res["batting"][side]:
			Season._add_line(bat, line, ["pos", "order"])
		for line: Dictionary in res["pitching"][side]:
			Season._add_line(pit, line, [])
	var best := ""
	var best_v := -1e9
	var text := ""
	for id: String in bat:
		var b: Dictionary = bat[id]
		var tb: int = int(b["h"]) + int(b["d"]) + 2 * int(b["t"]) + 3 * int(b["hr"])
		var v := tb + int(b["bb"]) + int(b["hbp"]) + int(b["rbi"]) + int(b["r"]) * 0.5 + int(b["hr"]) * 1.5 \
				- (int(b["ab"]) - int(b["h"])) * 0.4
		if v > best_v:
			best_v = v
			best = id
			text = "%d打数%d安打 %d本塁打 %d打点" % [b["ab"], b["h"], b["hr"], b["rbi"]]
	for id: String in pit:
		var p: Dictionary = pit[id]
		var v := int(p["outs"]) / 3.0 * 0.9 - int(p["er"]) * 2.0 + int(p.get("w", 0)) * 3.0 \
				+ int(p.get("sv", 0)) * 2.0 + int(p["so"]) * 0.3
		if v > best_v:
			best_v = v
			best = id
			text = "%d登板 %d勝 %d回%s 自責点%d" % [p["g"], p.get("w", 0), int(p["outs"]) / 3,
				"" if int(p["outs"]) % 3 == 0 else " %d/3" % (int(p["outs"]) % 3), p["er"]]
	return {"id": best, "text": text} if not best.is_empty() else {}


## 年の記録用の要約：{year, pennant: {C, P}, cs: {C, P}, champion, runner_up, js_score, series: [{key, name, winner, loser, score}]}
func summary() -> Dictionary:
	var result := {"year": year, "pennant": {}, "cs": {}, "champion": champion, "runner_up": "", "js_score": "",
		"series": []}
	for lg: String in order:
		if not order[lg].is_empty():
			result["pennant"][lg] = order[lg][0]
	var js := get_series("JS")
	if not js.is_empty():
		result["cs"]["C"] = js["high"]
		result["cs"]["P"] = js["low"]
		result["runner_up"] = js["loser"]
		if not js["winner"].is_empty():
			result["js_score"] = score_text(js)
	for s in series:
		var mvp := series_mvp(s)
		result["series"].append({"key": s["key"], "name": s["name"], "league": s["league"],
			"winner": s["winner"], "loser": s["loser"], "score": score_text(s) if not s["winner"].is_empty() else "",
			"mvp": mvp.get("id", ""), "mvp_text": mvp.get("text", "")})
	return result


# --- 優勝争い（公式戦） ------------------------------------------------------------------------

## リーグの優勝争い：{leader, magic, clinched}。magic は首位の球団があと何勝すれば（他球団が全勝しても）
## 優勝が決まるか（残り試合で届かなければ -1）。clinched は優勝が決まった（magic 0）。
## 残り試合は日程の未消化の試合（中止を除く）から数える。直接対決の分は考えない
static func pennant_race(season: Season, teams: Array, records_of: Callable) -> Dictionary:
	if teams.is_empty():
		return {}
	var remaining := {}
	for t: String in teams:
		remaining[t] = 0
	for i in range(season.next_index, season.games.size()):
		var g: Dictionary = season.games[i]
		if g["status"] != "played" or not g["result"].is_empty():
			continue
		for key: String in ["home", "away"]:
			if remaining.has(g[key]):
				remaining[g[key]] += 1
	var leader: String = teams[0]
	var lr: Dictionary = records_of.call(leader)
	var l_rem: int = remaining[leader]
	var l_total := int(lr["w"]) + int(lr["l"]) + l_rem
	var magic := -1
	for k in l_rem + 1:
		var l_pct := float(int(lr["w"]) + k) / l_total if l_total > 0 else 0.0
		var ok := true
		for t: String in teams:
			if t == leader:
				continue
			var r: Dictionary = records_of.call(t)
			var x_total := int(r["w"]) + int(r["l"]) + int(remaining[t])
			var x_pct := float(int(r["w"]) + int(remaining[t])) / x_total if x_total > 0 else 0.0
			if x_pct >= l_pct:
				ok = false
				break
		if ok:
			magic = k
			break
	# 全日程を終えたら首位が優勝（同率は表示順の上位）
	if season.is_finished() or l_rem == 0 and _all_done(remaining):
		magic = 0
	return {"leader": leader, "magic": magic, "clinched": magic == 0}


static func _all_done(remaining: Dictionary) -> bool:
	for t: String in remaining:
		if int(remaining[t]) > 0:
			return false
	return true


# --- セーブ／ロード ----------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"year": year, "series": series, "order": order, "batting": batting, "pitching": pitching,
		"champion": champion, "venues": _venues, "rng": SaveUtil.rng_state(_rng)}


## d は SaveUtil.ints() で整数を戻したもの
static func from_save(d: Dictionary) -> Postseason:
	var p := Postseason.new()
	p.year = int(d["year"])
	p.series.assign(d.get("series", []))
	p.order = d.get("order", {})
	p.batting = d.get("batting", {})
	p.pitching = d.get("pitching", {})
	p.champion = str(d.get("champion", ""))
	p._venues = d.get("venues", {})
	SaveUtil.set_rng_state(p._rng, d.get("rng", ""))
	return p
