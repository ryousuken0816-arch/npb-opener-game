# gdlint: disable=max-file-lines
class_name RecordsHistory
extends RefCounted
## 記録室の「歴代メンバー」「歴代ドラフト」（docs/AUTORUN.md 作業48・49）。
## シーズンが速く過ぎて自分のチームの顔ぶれを覚えられない、という声から。ゲームが教えるのではなく、ユーザーが自分で
## 見返して覚えるための一覧（パワプロの「歴代メンバー」「ドラフト選手」のように）。
##
## - 歴代メンバー：年×球団で、主なスタメン（その年いちばん多かった打順と守備位置）と主な控え、先発ローテ・中継ぎ・抑え。
##   ゲームで遊んだ年はゲーム内の成績。打順は試合の打撃の行の順（Season.games の結果の "order"）を数える
##   （batting_orders。オフに stats_history の "orders" に残す）。
##   開始年より前は史実：1軍成績は data/<年>/players.json（選手ページの年度別成績）、守備位置ごとの試合数は
##   generated/ratings/<年>_post.json の fielding。史実には打順も先発の数も無いので、守備位置ごとに試合の多い選手を選んで
##   成績から打順を決め（_order_by_role）、先発は1登板あたりの投球回で見分ける
## - 歴代ドラフト：年×球団で、指名順に 今の球団・守備位置・経歴（高/大/社）・投打・評価（今の能力の総合ランク＝デプスの
##   「現在の能力」）・通算成績・現役の印。ゲームで遊んだ年は LeagueRoster.drafted、開始年より前は史実の指名
##   （data/<年+1>/drafts.json、2007年以前は data/drafts_2001-2007.json）を、能力値ファイルの選手と突き合わせる
##   （GameData.draft_entry_for）。通算成績は開始年より前の史実（選手ページ）＋ゲーム内の全年
## 並べる部品は RecordsView のもの（_cell・_tag・_option_button など）を使う

## 史実の成績を出せる年（選手ページ・能力値ファイルがある年）
const HIST_FIRST_YEAR := 2008
const HIST_LAST_YEAR := 2026
## 歴代ドラフトの最初の年（data/drafts_2001-2007.json）
const DRAFT_FIRST_YEAR := 2001
## 控え：打席がこれ以上の選手を、打席の多い順に何人まで
const BENCH_MIN_PA := 20
const BENCH_MAX := 10
## 先発ローテ：先発の多い順に何人まで。6人目は先発（史実は投球回）がこれ以上のときだけ
const ROTATION_MAX := 6
const ROTATION_MIN := 5
const SIXTH_MIN_GS := 10
const SIXTH_MIN_OUTS := 180
## 先発とみなす：ゲーム内は先発が登板の半分以上かつこの数以上。史実は1登板あたりのアウトがこれ以上
const STARTER_MIN_GS := 5
const HIST_STARTER_OUTS_PER_G := 13.5
const HIST_STARTER_MIN_G := 5
## 抑え：セーブがこれ以上の救援投手（いちばん多い1人）。中継ぎ：登板がこれ以上を、ホールド＋セーブの多い順に何人まで
const CLOSER_MIN_SV := 5
const RELIEF_MIN_G := 15
const RELIEF_MAX := 7
## サブの守備位置とみなす先発出場（史実は守備）の試合数
const SUB_POS_GAMES := 10
## リーグ上位を色で示す順位
const TOP_N := 3
const LEADER_COLOR := Color("d84315")
const TOP_COLOR := Color("ef6c00")
const STAR_COLOR := Color("c79100")
const ACTIVE_COLOR := Color("2e7d32")
const STARTER_TINT := Color("fff8e1")
const ROW_TINT := Color(1, 1, 1, 0.6)
## リーグ上位を色付けする数字 [キー, 打撃 b／投手 p, 小さいほど良いか, 1位のタイトル（史実の年の ☆）]
const LEADER_KEYS := [
	["avg", "b", false, "首位打者"], ["hr", "b", false, "本塁打王"], ["rbi", "b", false, "打点王"],
	["sb", "b", false, "盗塁王"], ["era", "p", true, "最優秀防御率"], ["w", "p", false, "最多勝"],
	["sv", "p", false, "最多セーブ"], ["hld", "p", false, "最多ホールド"], ["so", "p", false, "最多奪三振"],
]
const AWARD_NAMES := {"mvp": "MVP", "rookie": "新人王", "best_nine": "ベストナイン", "gold_glove": "ゴールデングラブ賞"}
const POS_SHORT := {
	"捕手": "捕", "一塁手": "一", "二塁手": "二", "三塁手": "三", "遊撃手": "遊", "左翼手": "左", "中堅手": "中",
	"右翼手": "右", "外野手": "外", "内野手": "内", "指名打者": "指", "投手": "投",
}
const OUTFIELD := ["左翼手", "中堅手", "右翼手", "外野手"]
## 史実のスタメンを選ぶ守備位置（外野は左中右の区別が無いので3人）
const HIST_POSITIONS := {"捕手": 1, "一塁手": 1, "二塁手": 1, "三塁手": 1, "遊撃手": 1, "外野手": 3}
## 列の幅。野手・投手は2列に並べる（1280x720 の広げたサブ画面に2列が入る幅）
const BAT_W := [30, 100, 58, 38, 36, 46, 40, 38, 34, 36, 30]
const BAT_HEAD := ["打順", "名前", "守備", "投打", "試合", "打率", "本塁打", "打点", "盗塁", "年齢", "☆"]
const PIT_W := [28, 96, 38, 36, 52, 30, 30, 44, 46, 40, 36, 30]
const PIT_HEAD := ["役", "名前", "投打", "登板", "勝敗", "S", "H", "防御率", "投球回", "奪三振", "年齢", "☆"]
const DRAFT_W := [78, 104, 84, 30, 30, 140, 38, 30, 76, 54, 84, 72, 56, 50]
const DRAFT_HEAD := ["順位", "名前", "今の球団", "位置", "経歴", "出身", "投打", "評価", "通算成績", "", "", "", "", "現役"]
## 球団のマークのボタンの大きさ
const EMBLEM_SIZE := 40

## 年 → 選手ページから集めたもの（pages_summary）
static var _pages_cache := {}
## "年_phase" → 選手ID → 能力値ファイルの選手
static var _ratings_cache := {}
## 年 → 史実の年の year_data
static var _hist_cache := {}
## 今季の打順の数え（試合が進んだら数え直す）
static var _orders_cache := {}
## "年_phase" → 選手ID → 総合ランク（_rank_of。小さいので全部の年を持つ）
static var _rank_cache := {}
## 年ごとの持ち物は最近使った年だけ持ち、記録室を閉じたら捨てる（clear_caches。作業55：年を切り替えるたびに
## その年の選手ページ・能力値ファイルを持ち続けて、1年あたり約24MB、2020年開始で歴代メンバーを12年見ると
## +285MB になり、iPhone の Web 版でメモリが足りなくなっていた）。
## 選手ページの集計（1年約7MB）は、歴代ドラフトの通算成績で入団の次の年から開始年まで順に探すので多めに持つ
const PAGES_YEARS := 16
## 能力値ファイル（1年約12MB）・史実の年の成績（1年約4MB）
const CACHE_YEARS := 4


# --- 年・球団 ----------------------------------------------------------------------------------

## 同じ球団か（横浜ベイスターズ → 横浜DeNAベイスターズ のように名前が変わっても同じ）
static func same_team(a: String, b: String) -> bool:
	return a == b or (a.contains("ベイスターズ") and b.contains("ベイスターズ"))


static func league_of_team(team: String) -> String:
	for t: String in GameData.teams():
		if same_team(t, team):
			return GameData.league_of(t)
	return ""


## 史実のその年の1球団の試合数（規定打席・規定投球回）
static func season_games(y: int) -> int:
	if y == 2020:
		return 120
	return 144 if y <= 2014 else 143


## 歴代メンバーで見られる年：開始年より前の史実の年＋ゲームで遊んだ年
static func member_years() -> Array[int]:
	var result: Array[int] = []
	for y in range(HIST_FIRST_YEAR, mini(GameState.first_year, HIST_LAST_YEAR + 1)):
		result.append(y)
	for y in GameState.records_years():
		if y not in result:
			result.append(y)
	result.sort()
	return result


## 歴代ドラフトで見られる年：開始年より前の史実のドラフト＋ゲームで行ったドラフト
static func draft_years() -> Array[int]:
	var result: Array[int] = []
	for y in range(DRAFT_FIRST_YEAR, mini(GameState.first_year, Draft.LAST_HISTORY_YEAR + 1)):
		result.append(y)
	var league: LeagueRoster = GameState.league
	if league != null:
		for id: String in league.drafted:
			var y := int(league.drafted[id]["year"])
			if y not in result:
				result.append(y)
	result.sort()
	return result


# --- 史実のデータ ------------------------------------------------------------------------------

## その年の選手ページ（data/<年>/players.json）から：
## season＝選手ID → 球団 → {"b": 打撃, "p": 投手}（その年の1軍成績。途中で移籍した選手は球団ごと）、
## career＝選手ID → {"b", "p"}（ゲームを始めた年より前の1軍の通算）、last＝その中で最後に1軍に出た年、
## names・bio（生年月日・投打）
static func pages_summary(y: int) -> Dictionary:
	var fy := GameState.first_year
	var cached: Dictionary = _pages_cache.get(y, {})
	if not cached.is_empty() and int(cached["first_year"]) == fy:
		_remember(_pages_cache, y, cached, PAGES_YEARS)
		return cached
	var season := {}
	var career := {}
	var names := {}
	var bio := {}
	var last := {}
	var pages := GameData.all_player_pages(y)
	for id: String in pages:
		var page: Dictionary = pages[id]
		names[id] = str(page.get("name", ""))
		bio[id] = {"birth": page.get("birth"), "throws": page.get("throws", ""), "bats": page.get("bats", "")}
		for kind: String in ["batting", "pitching"]:
			var k := "b" if kind == "batting" else "p"
			var rows: Variant = page.get(kind)
			if not rows is Array:
				continue
			for row: Variant in rows:
				if not row is Dictionary:
					continue
				var ry := int((row as Dictionary).get("年度", 0))
				var line := Records.from_page_batting(row) if k == "b" else Records.from_page_pitching(row)
				if ry == y:
					var team := GameData.resolve_team(str((row as Dictionary).get("所属球団", "")), y)
					var by_team: Dictionary = season.get_or_add(id, {})
					var per: Dictionary = by_team.get_or_add(team, {})
					Records.add_into(per.get_or_add(k, {}), line)
				if ry > 0 and ry < fy:
					var c: Dictionary = career.get_or_add(id, {})
					Records.add_into(c.get_or_add(k, {}), line)
					last[id] = maxi(int(last.get(id, 0)), ry)
	cached = {"first_year": fy, "season": season, "career": career, "names": names, "bio": bio, "last": last}
	_remember(_pages_cache, y, cached, PAGES_YEARS)
	return cached


## 能力値ファイルの選手（選手ID → 選手）。その年のファイルが無ければ空
static func ratings_index(y: int, phase := "post") -> Dictionary:
	var key := "%d_%s" % [y, phase]
	if _ratings_cache.has(key):
		var hit: Dictionary = _ratings_cache[key]
		_remember(_ratings_cache, key, hit)
		return hit
	var result := {}
	var data := GameData.peek_ratings(y, phase, false)
	for p: Dictionary in data.get("players", []):
		result[str(p["id"])] = p
	_remember(_ratings_cache, key, result)
	return result


## 記録室を閉じたとき：年ごとの持ち物を捨てる（ランクと今季の打順は小さいので残す）
static func clear_caches() -> void:
	_pages_cache.clear()
	_ratings_cache.clear()
	_hist_cache.clear()


## cache の key を最後（いちばん新しい）に入れ直し、いちばん長く使っていないものから CACHE_YEARS 個を超えた分を捨てる
static func _remember(cache: Dictionary, key: Variant, value: Variant, limit := CACHE_YEARS) -> void:
	cache.erase(key)
	cache[key] = value
	while cache.size() > limit:
		cache.erase(cache.keys()[0])


## 選手の生年月日・投打・守備位置など（今の能力値データ → その年の能力値ファイル）
static func bio_of(id: String, y: int) -> Dictionary:
	var p := GameData.player(id)
	if not p.is_empty():
		return p
	return ratings_index(clampi(y, HIST_FIRST_YEAR, HIST_LAST_YEAR), "post").get(id, {})


# --- 打順（ゲーム内） ----------------------------------------------------------------------------

## 試合の結果から、選手ID → 打順（"1"〜"9"）→ 先発出場の試合数。打撃の行は打席に立った順に作られるので、
## 先発の守備位置の行の "order"（0〜8）が打順。投手・代打は数えない
static func batting_orders(games: Array) -> Dictionary:
	var result := {}
	for g: Dictionary in games:
		var res: Variant = g.get("result")
		if not res is Dictionary:
			continue
		for side: Variant in (res as Dictionary).get("batting", []):
			if not side is Array:
				continue
			for line: Variant in side:
				if not line is Dictionary:
					continue
				var order := int((line as Dictionary).get("order", 99))
				if order >= 9 or not str((line as Dictionary).get("pos", "")) in SimTeam.LINEUP_POSITIONS:
					continue
				var per: Dictionary = result.get_or_add(str(line["id"]), {})
				var k := str(order + 1)
				per[k] = int(per.get(k, 0)) + 1
	return result


## その年の打順の数え（オフに残したもの。今季は試合から）。古いセーブで無ければ空
static func orders_of(y: int) -> Dictionary:
	var h: Dictionary = GameState.stats_history.get(str(y), {})
	if not h.is_empty():
		return h.get("orders", {})
	var s: Season = GameState.season
	if s == null or s.year != y:
		return {}
	var key := "%s/%d/%d/%d" % [GameState.team, GameState.first_year, y, s.played_count()]
	if _orders_cache.get("key", "") != key:
		_orders_cache = {"key": key, "orders": batting_orders(s.games)}
	return _orders_cache["orders"]


# --- 1年分の成績 ------------------------------------------------------------------------------

## その年の全選手の成績：{bat: [entry], pit: [entry], game（ゲーム内の年か）, finished（シーズンが終わったか）,
## games: 球団 → 試合数, leagues: 球団 → C/P}。entry＝{id, name, team, line, pos_g, orders, rank: キー → 順位, stars}
static func year_data(y: int) -> Dictionary:
	var d: Dictionary
	if y in GameState.records_years():
		d = _game_year(y)
	elif _hist_cache.has(y):
		var hit: Dictionary = _hist_cache[y]
		_remember(_hist_cache, y, hit)
		return hit
	else:
		d = _hist_year(y)
		_remember(_hist_cache, y, d)
	_mark_leaders(d)
	return d


static func _game_year(y: int) -> Dictionary:
	var st := GameState.season_stats(y)
	var orders := orders_of(y)
	var players: Dictionary = st.get("players", {})
	var awards := _award_stars(GameState.awards_of(y))
	var bat: Array = []
	var pit: Array = []
	for kind: String in ["batting", "pitching"]:
		var src: Dictionary = st.get(kind, {})
		for id: String in src:
			var line: Dictionary = src[id]
			var info: Dictionary = players.get(id, {})
			var e := {"id": id, "name": str(info.get("name", id)), "team": str(info.get("team", "")), "line": line,
				"pos_g": line.get("pos_g", {}), "orders": orders.get(id, {}), "rank": {},
				"stars": (awards.get(id, []) as Array).duplicate()}
			(bat if kind == "batting" else pit).append(e)
	var games := {}
	var records: Dictionary = st.get("records", {})
	for team: String in records:
		var r: Dictionary = records[team]
		games[team] = int(r.get("w", 0)) + int(r.get("l", 0)) + int(r.get("d", 0))
	return {"bat": bat, "pit": pit, "game": true, "finished": GameState.stats_history.has(str(y)),
		"games": games, "leagues": st.get("leagues", {})}


static func _hist_year(y: int) -> Dictionary:
	var ps := pages_summary(y)
	var rt := ratings_index(y, "post")
	var gg := {}
	var awards: Variant = GameData.read_data("%d/awards.json" % y)
	if awards is Array:
		for a: Dictionary in awards:
			if a.get("player_id") != null:
				gg[str(a["player_id"])] = str(a.get("award", "ゴールデングラブ賞"))
	var bat: Array = []
	var pit: Array = []
	var leagues := {}
	var games := {}
	for id: String in ps["season"]:
		var by_team: Dictionary = ps["season"][id]
		var p: Dictionary = rt.get(id, {})
		var pos_g := {}
		var fielding: Variant = p.get("fielding")
		if fielding is Dictionary:
			for pos: String in fielding:
				var n := int((fielding[pos] as Dictionary).get("games", 0))
				if n > 0:
					pos_g[pos] = n
		var name := str(p.get("name", ps["names"].get(id, id)))
		for team: String in by_team:
			if not leagues.has(team):
				leagues[team] = league_of_team(team)
				games[team] = season_games(y)
			var t: Dictionary = by_team[team]
			var stars: Array = [gg[id]] if gg.has(id) else []
			if t.has("b") and int(t["b"].get("pa", 0)) > 0:
				bat.append({"id": id, "name": name, "team": team, "line": t["b"], "pos_g": pos_g, "orders": {},
					"rank": {}, "stars": stars.duplicate()})
			if t.has("p") and int(t["p"].get("g", 0)) > 0:
				pit.append({"id": id, "name": name, "team": team, "line": t["p"], "pos_g": pos_g, "orders": {},
					"rank": {}, "stars": stars.duplicate()})
	return {"bat": bat, "pit": pit, "game": false, "finished": true, "games": games, "leagues": leagues}


## 表彰（Awards.compute の結果）→ 選手ID → 賞の名前の配列
static func _award_stars(aw: Dictionary) -> Dictionary:
	var result := {}
	var leagues: Dictionary = aw.get("leagues", {})
	for lg: String in leagues:
		var block: Dictionary = leagues[lg]
		for key: String in block:
			if key == "titles":
				for t: Dictionary in block["titles"]:
					for w: Variant in t.get("winners", []):
						_collect_ids(w, str(t.get("name", "")), result)
			else:
				_collect_ids(block[key], str(AWARD_NAMES.get(key, key)), result)
	_collect_ids(aw.get("sawamura"), "沢村賞", result)
	return result


static func _collect_ids(v: Variant, label: String, result: Dictionary) -> void:
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("id"):
			var list: Array = result.get_or_add(str(d["id"]), [])
			if label not in list:
				list.append(label)
			return
		for k: Variant in d:
			_collect_ids(d[k], label, result)
	elif v is Array:
		for x: Variant in v:
			_collect_ids(x, label, result)


## リーグ上位（TOP_N 位まで）の印。史実の年は1位をタイトルとして ☆（ゲーム内の年は表彰の結果で付ける）
static func _mark_leaders(d: Dictionary) -> void:
	for list: Array in [d["bat"], d["pit"]]:
		for e: Dictionary in list:
			e["rank"] = {}
	for spec: Array in LEADER_KEYS:
		var key: String = spec[0]
		var lower: bool = spec[2]
		var list: Array = d["bat"] if spec[1] == "b" else d["pit"]
		for lg: String in ["C", "P"]:
			var vals: Array = []
			for e: Dictionary in list:
				if str(d["leagues"].get(e["team"], "")) != lg:
					continue
				var v: Variant = stat_value(e, key, int(d["games"].get(e["team"], 0)))
				if v != null and (lower or float(v) > 0.0):
					vals.append([float(v), e])
			vals.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] if lower else a[0] > b[0])
			var rank := 0
			for i in vals.size():
				if i == 0 or not is_equal_approx(float(vals[i][0]), float(vals[i - 1][0])):
					rank = i + 1
				if rank > TOP_N:
					break
				var e: Dictionary = vals[i][1]
				e["rank"][key] = rank
				if rank == 1 and not d["game"] and spec[3] not in e["stars"]:
					e["stars"].append(spec[3])


## 成績の数字（打率・防御率は規定に届かなければ null）
static func stat_value(e: Dictionary, key: String, team_games: int) -> Variant:
	var line: Dictionary = e["line"]
	match key:
		"avg":
			if float(line.get("pa", 0)) < 3.1 * team_games or int(line.get("ab", 0)) == 0:
				return null
			return float(line.get("h", 0)) / float(line["ab"])
		"era":
			if int(line.get("outs", 0)) < 3 * team_games or int(line.get("outs", 0)) == 0:
				return null
			return float(line.get("er", 0)) * 27.0 / float(line["outs"])
	return int(line.get(key, 0))


# --- 歴代メンバー -------------------------------------------------------------------------------

## その年・その球団の顔ぶれ：{lineup: [{slot, e, pos}], bench: [{e, pos}], rotation, relief, closer: [entry],
## game, dh, year}
static func members(y: int, team: String) -> Dictionary:
	var d := year_data(y)
	var bats: Array = []
	for e: Dictionary in d["bat"]:
		if same_team(e["team"], team) and not _pitcher_only(e, y):
			bats.append(e)
	var pits: Array = []
	for e: Dictionary in d["pit"]:
		if same_team(e["team"], team):
			pits.append(e)
	var dh := league_of_team(team) == "P"
	var lineup: Array = []
	if d["game"]:
		lineup = _lineup_from_orders(bats, dh)
	if lineup.is_empty():
		lineup = _lineup_by_position(bats, dh)
	var used := {}
	for s: Dictionary in lineup:
		used[s["e"]["id"]] = true
	var bench: Array = []
	for e: Dictionary in bats:
		if not used.has(e["id"]) and int(e["line"].get("pa", 0)) >= BENCH_MIN_PA:
			bench.append(e)
	bench.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["line"].get("pa", 0)) > int(b["line"].get("pa", 0)))
	var bench_rows: Array = []
	for e: Dictionary in bench.slice(0, BENCH_MAX):
		bench_rows.append({"e": e, "pos": main_pos(e, y)})
	var staff := _staff(pits, d["game"])
	staff.merge({"lineup": lineup, "bench": bench_rows, "game": d["game"], "dh": dh, "year": y})
	return staff


## 投手の打撃の行（守備位置が投手だけ）は野手に入れない
static func _pitcher_only(e: Dictionary, y: int) -> bool:
	for pos: String in e["pos_g"]:
		if pos != "投手":
			return false
	if e["pos_g"].has("投手"):
		return true
	return bool(bio_of(e["id"], y).get("is_pitcher", false))


## いちばん多く出た守備位置（投手は除く。無ければ能力値データの主な守備位置）
static func main_pos(e: Dictionary, y: int) -> String:
	var best := ""
	var best_n := 0
	for pos: String in e["pos_g"]:
		var n := int(e["pos_g"][pos])
		if pos != "投手" and n > best_n:
			best = pos
			best_n = n
	if best.is_empty():
		var p := bio_of(e["id"], y)
		best = str(p.get("primary_pos", "")) if not bool(p.get("is_pitcher", false)) else "指名打者"
	return best if not best.is_empty() else "指名打者"


## サブの守備位置（主な位置のほかに SUB_POS_GAMES 試合以上。多い順に）
static func sub_positions(e: Dictionary, main: String) -> Array[String]:
	var list: Array = []
	for pos: String in e["pos_g"]:
		if pos != "投手" and pos != main and int(e["pos_g"][pos]) >= SUB_POS_GAMES:
			list.append([int(e["pos_g"][pos]), pos])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var result: Array[String] = []
	for x: Array in list:
		result.append(x[1])
	return result


## ゲーム内の年：打順ごとに先発の多い選手（多い組から順に決める）。打順の記録が無ければ空
static func _lineup_from_orders(bats: Array, dh: bool) -> Array:
	var n := 9 if dh else 8
	var pairs: Array = []
	for e: Dictionary in bats:
		for k: String in e["orders"]:
			if int(k) <= n:
				pairs.append([int(e["orders"][k]), int(k), e])
	if pairs.is_empty():
		return []
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var by_slot := {}
	var used := {}
	for p: Array in pairs:
		var e: Dictionary = p[2]
		if by_slot.has(p[1]) or used.has(e["id"]):
			continue
		by_slot[p[1]] = e
		used[e["id"]] = true
	var rest := _by_pa(bats.filter(func(e: Dictionary) -> bool: return not used.has(e["id"])))
	var result: Array = []
	for slot in range(1, n + 1):
		if not by_slot.has(slot):
			if rest.is_empty():
				continue
			by_slot[slot] = rest.pop_front()
		var e: Dictionary = by_slot[slot]
		result.append({"slot": slot, "e": e, "pos": main_pos(e, 0)})
	return result


## 史実の年（打順の記録が無い）：守備位置ごとに試合の多い選手を選び（DH制は残りで打席の多い選手）、打順は成績から
static func _lineup_by_position(bats: Array, dh: bool) -> Array:
	var need := HIST_POSITIONS.duplicate()
	var pairs: Array = []
	for e: Dictionary in bats:
		var per := {}
		for pos: String in e["pos_g"]:
			var key := "外野手" if pos in OUTFIELD else pos
			if need.has(key):
				per[key] = int(per.get(key, 0)) + int(e["pos_g"][pos])
		for key: String in per:
			pairs.append([int(per[key]), key, e])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var chosen: Array = []
	var used := {}
	for p: Array in pairs:
		var e: Dictionary = p[2]
		if int(need.get(p[1], 0)) <= 0 or used.has(e["id"]):
			continue
		need[p[1]] = int(need[p[1]]) - 1
		used[e["id"]] = true
		chosen.append({"e": e, "pos": _shown_pos(e, p[1])})
	var rest := _by_pa(bats.filter(func(e: Dictionary) -> bool: return not used.has(e["id"])))
	for key: String in need:
		for i in int(need[key]):
			if rest.is_empty():
				break
			var e: Dictionary = rest.pop_front()
			used[e["id"]] = true
			chosen.append({"e": e, "pos": key})
	if dh and not rest.is_empty():
		var e: Dictionary = rest.pop_front()
		chosen.append({"e": e, "pos": "指名打者"})
	return _order_by_role(chosen)


## 外野は（ゲーム内の年なら）左中右のうちいちばん多い位置で見せる
static func _shown_pos(e: Dictionary, key: String) -> String:
	if key != "外野手":
		return key
	var best := key
	var best_n := 0
	for pos: String in e["pos_g"]:
		if pos in OUTFIELD and int(e["pos_g"][pos]) > best_n:
			best = pos
			best_n = int(e["pos_g"][pos])
	return best


static func _by_pa(list: Array) -> Array:
	var result := list.duplicate()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["line"].get("pa", 0)) > int(b["line"].get("pa", 0)))
	return result


## 打順を成績から：4番＝長打、3番＝OPS、1番＝出塁と足、5番＝長打、2番＝出塁と足、6番から下は OPS の順
static func _order_by_role(chosen: Array) -> Array:
	var pool := chosen.duplicate()
	var by_slot := {}
	for role: Array in [[4, "power"], [3, "ops"], [1, "lead"], [5, "power"], [2, "lead"]]:
		if pool.is_empty():
			break
		var best_i := 0
		for i in pool.size():
			if _role_score(pool[i]["e"], role[1]) > _role_score(pool[best_i]["e"], role[1]):
				best_i = i
		by_slot[role[0]] = pool[best_i]
		pool.remove_at(best_i)
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _role_score(a["e"], "ops") > _role_score(b["e"], "ops"))
	var slot := 6
	for c: Dictionary in pool:
		by_slot[slot] = c
		slot += 1
	var result: Array = []
	for s in range(1, slot):
		if by_slot.has(s):
			result.append({"slot": s, "e": by_slot[s]["e"], "pos": by_slot[s]["pos"]})
	return result


static func _role_score(e: Dictionary, role: String) -> float:
	var b: Dictionary = e["line"]
	var ab := float(b.get("ab", 0))
	var pa := maxf(float(b.get("pa", 0)), 1.0)
	var h := float(b.get("h", 0))
	var on_base := h + float(b.get("bb", 0)) + float(b.get("hbp", 0))
	var obp := on_base / maxf(ab + float(b.get("bb", 0)) + float(b.get("hbp", 0)) + float(b.get("sf", 0)), 1.0)
	var bases := h + float(b.get("d", 0)) + 2.0 * float(b.get("t", 0)) + 3.0 * float(b.get("hr", 0))
	var slg := bases / maxf(ab, 1.0)
	match role:
		"power":
			return slg + 2.0 * float(b.get("hr", 0)) / pa
		"lead":
			return obp + 2.0 * float(b.get("sb", 0)) / pa
	return obp + slg


## 投手陣：先発ローテ・抑え・中継ぎ（勝ちパターン）
static func _staff(pits: Array, game: bool) -> Dictionary:
	var starters: Array = []
	for e: Dictionary in pits:
		var line: Dictionary = e["line"]
		var g := int(line.get("g", 0))
		if game:
			var gs := int(line.get("gs", 0))
			if gs >= STARTER_MIN_GS and gs * 2 >= g:
				starters.append(e)
		elif g >= HIST_STARTER_MIN_G and float(line.get("outs", 0)) / maxf(g, 1.0) >= HIST_STARTER_OUTS_PER_G:
			starters.append(e)
	var key := "gs" if game else "outs"
	starters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["line"].get(key, 0)) > int(b["line"].get(key, 0)))
	var rotation: Array = []
	for e: Dictionary in starters:
		if rotation.size() >= ROTATION_MAX:
			break
		var big := int(e["line"].get("gs", 0)) >= SIXTH_MIN_GS if game \
			else int(e["line"].get("outs", 0)) >= SIXTH_MIN_OUTS
		if rotation.size() >= ROTATION_MIN and not big:
			break
		rotation.append(e)
	var in_rotation := {}
	for e: Dictionary in rotation:
		in_rotation[e["id"]] = true
	var closer: Array = []
	var best_sv := CLOSER_MIN_SV - 1
	for e: Dictionary in pits:
		var sv := int(e["line"].get("sv", 0))
		if not in_rotation.has(e["id"]) and sv > best_sv:
			best_sv = sv
			closer = [e]
	var relief: Array = []
	for e: Dictionary in pits:
		if in_rotation.has(e["id"]) or (not closer.is_empty() and closer[0] == e):
			continue
		if int(e["line"].get("g", 0)) >= RELIEF_MIN_G:
			relief.append(e)
	relief.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var la: Dictionary = a["line"]
		var lb: Dictionary = b["line"]
		var va := int(la.get("hld", 0)) + int(la.get("sv", 0))
		var vb := int(lb.get("hld", 0)) + int(lb.get("sv", 0))
		return va > vb if va != vb else int(la.get("g", 0)) > int(lb.get("g", 0)))
	return {"rotation": rotation, "closer": closer, "relief": relief.slice(0, RELIEF_MAX)}


# --- 歴代ドラフト -------------------------------------------------------------------------------

## その年・その球団の指名：{rows: [行], game}。行＝{id, name, label, round, ikusei, entry（史実の指名の行）,
## pitcher, pos, cat（高/大/社）, school, hand, rank, career: {b, p}, status（active/mlb/retired/left/unknown）, now_team}
static func draft_picks(draft_year: int, team: String) -> Dictionary:
	var game := draft_year >= GameState.first_year
	var rows := _game_picks(draft_year, team) if game else _hist_picks(draft_year, team)
	var ids: Array = []
	for r: Dictionary in rows:
		if not str(r["id"]).is_empty():
			ids.append(r["id"])
	var careers := careers_of(ids, draft_year)
	for r: Dictionary in rows:
		_fill_pick(r, draft_year, careers.get(r["id"], {}))
	return {"rows": rows, "game": game}


static func _game_picks(draft_year: int, team: String) -> Array:
	var rows: Array = []
	var league: LeagueRoster = GameState.league
	if league == null:
		return rows
	for id: String in league.drafted:
		var rec: Dictionary = league.drafted[id]
		if int(rec["year"]) != draft_year or not same_team(str(rec["team"]), team):
			continue
		var ikusei := bool(rec.get("ikusei", false))
		var rnd := int(rec.get("round", 1))
		var name := str(league.names.get(id, GameData.player(id).get("name", id)))
		rows.append({"id": id, "name": name, "round": rnd, "ikusei": ikusei, "order": 0,
			"label": str(rec.get("label", ("育成" if ikusei else "") + "%d位" % rnd)), "entry": {}})
	rows.sort_custom(_pick_before)
	return rows


static func _hist_picks(draft_year: int, team: String) -> Array:
	var ids := _draft_ids(draft_year)
	var rows: Array = []
	for d: Dictionary in hist_draft_rows(draft_year):
		if not same_team(hist_team_of(d, draft_year), team):
			continue
		var key := LeagueRoster.norm_name(str(d["name"]))
		if not ids.has(key):
			ids[key] = _id_by_name(key, team, draft_year)
		var section := str(d.get("section", ""))
		var ikusei := bool(d.get("ikusei", false)) or section.contains("育成")
		var label := str(d.get("round", ""))
		var order := 0
		if section.contains("高校生"):
			label = "高校" + label
		elif section.contains("大学生"):
			label = "大社" + label
			order = 1
		if ikusei and not label.begins_with("育成"):
			label = "育成" + label
		rows.append({"id": str(ids[key]), "name": str(d["name"]),
			"round": Draft.round_number(str(d.get("round", ""))), "ikusei": ikusei, "order": order, "label": label,
			"entry": d})
	rows.sort_custom(_pick_before)
	return rows


static func _pick_before(a: Dictionary, b: Dictionary) -> bool:
	if a["ikusei"] != b["ikusei"]:
		return not a["ikusei"]
	if int(a["order"]) != int(b["order"]):
		return int(a["order"]) < int(b["order"])
	return int(a["round"]) < int(b["round"])


## 史実の指名の一覧（data/<年+1>/drafts.json、2007年以前は data/drafts_2001-2007.json）
static func hist_draft_rows(draft_year: int) -> Array:
	var result: Array = []
	for file_name: String in ["%d/drafts.json" % (draft_year + 1), "drafts_2001-2007.json"]:
		var parsed: Variant = GameData.read_data(file_name)
		if not parsed is Array:
			continue
		for d: Dictionary in parsed:
			if int(d.get("draft_year", 0)) == draft_year and not str(d.get("name", "")).begins_with("("):
				result.append(d)
		if not result.is_empty():
			break
	return result


## 史実の指名の行の球団（その年の名前。オリックス・ブルーウェーブはオリックスに、近鉄は無し）
static func hist_team_of(d: Dictionary, draft_year: int) -> String:
	var team := Draft.hist_team_of(d, draft_year)
	if team.is_empty() and str(d.get("code", "")) == "bw":
		return GameData.resolve_team("オリックス", draft_year)
	return team


## 史実の指名 → 選手ID（正規化した名前 → ID）。入団した年の能力値ファイルと今の能力値データの選手のうち、
## ドラフトの経歴がその年の選手を GameData.draft_entry_for で指名の行と突き合わせる
static func _draft_ids(draft_year: int) -> Dictionary:
	var result := {}
	var prefix := "%d年" % draft_year
	var sources: Array = [GameData.rostered_players(),
		ratings_index(clampi(draft_year + 1, HIST_FIRST_YEAR, HIST_LAST_YEAR), "pre").values()]
	for list: Array in sources:
		for p: Dictionary in list:
			var text: Variant = p.get("draft")
			if not (text is String and (text as String).begins_with(prefix)):
				continue
			var entry := GameData.draft_entry_for(p, draft_year)
			if not entry.is_empty():
				var key := LeagueRoster.norm_name(str(entry["name"]))
				if not result.has(key):
					result[key] = str(p["id"])
	return result


## ドラフトの経歴が無い選手（1軍に出ていない仮IDの選手など）は、入団した年の能力値ファイルで同じ名前・同じ球団の選手
static func _id_by_name(key: String, team: String, draft_year: int) -> String:
	var rt := ratings_index(clampi(draft_year + 1, HIST_FIRST_YEAR, HIST_LAST_YEAR), "pre")
	for id: String in rt:
		var p: Dictionary = rt[id]
		if p.get("draft") == null and LeagueRoster.norm_name(str(p.get("name", ""))) == key 				and same_team(str(p.get("hist_team", p.get("team", ""))), team):
			return id
	return ""


## 通算の1軍成績（選手ID → {"b": 打撃, "p": 投手, "last": 開始年より前に最後に1軍に出た年}）＝ゲームを始めた年より前の
## 史実＋ゲーム内の全年。
## 史実は選手ページ（どの年のページにも全部の年度がある）を、開始年・入団した年から順に探す
static func careers_of(ids: Array, draft_year: int) -> Dictionary:
	var result := {}
	var fy := GameState.first_year
	var years: Array[int] = [clampi(fy, HIST_FIRST_YEAR, HIST_LAST_YEAR)]
	for y in range(maxi(draft_year + 1, HIST_FIRST_YEAR), mini(fy, HIST_LAST_YEAR + 1)):
		if y not in years:
			years.append(y)
	var missing: Array = []
	for id: String in ids:
		if not id.begins_with("tmp:"):
			missing.append(id)
	for y in years:
		if missing.is_empty() or draft_year >= fy:
			break
		var ps := pages_summary(y)
		var still: Array = []
		for id: String in missing:
			if ps["career"].has(id):
				result[id] = (ps["career"][id] as Dictionary).duplicate(true)
				result[id]["last"] = int(ps["last"].get(id, 0))
			elif not ps["names"].has(id):
				still.append(id)
		missing = still
	for y in GameState.records_years():
		var st := GameState.season_stats(y)
		for id: String in ids:
			for kind: Array in [["batting", "b"], ["pitching", "p"]]:
				var line: Variant = (st.get(kind[0], {}) as Dictionary).get(id)
				if line is Dictionary:
					var c: Dictionary = result.get_or_add(id, {})
					Records.add_into(c.get_or_add(kind[1], {}), line)
	return result


static func _fill_pick(r: Dictionary, draft_year: int, career: Dictionary) -> void:
	var id: String = r["id"]
	var entry: Dictionary = r["entry"]
	var p: Dictionary = GameData.player(id) if not id.is_empty() else {}
	if p.is_empty() and not id.is_empty():
		p = ratings_index(clampi(draft_year + 1, HIST_FIRST_YEAR, HIST_LAST_YEAR), "pre").get(id, {})
	if entry.is_empty() and not p.is_empty():
		entry = GameData.draft_entry_for(p, draft_year)
	var pitcher := bool(p.get("is_pitcher", false)) if not p.is_empty() else str(entry.get("pos", "")) == "投手"
	r["pitcher"] = pitcher
	var pos := "投手" if pitcher else str(p.get("primary_pos", entry.get("pos", "")))
	r["pos"] = str(POS_SHORT.get(pos, pos.left(1)))
	var school := str(entry.get("school", ""))
	if school.is_empty():
		var am: Variant = p.get("amateur")
		if am is Dictionary:
			school = str((am as Dictionary).get("school", ""))
	if school.is_empty():
		var parts := str(p.get("career", "")).split(" - ")
		school = parts[-1].strip_edges() if parts.size() > 0 else ""
	r["school"] = school
	r["cat"] = Draft.career_of(school).left(1) if not school.is_empty() else "-"
	r["hand"] = hand_text(p)
	r["career"] = career
	r["pos_color"] = NameTag.pos_color(pos)
	r["rank"] = _rank_of(id, p, int(career.get("last", 0)))
	_status_of(r)


## 今の能力の総合ランク（デプスの「現在の能力」と同じ）。今の能力値データにいない（引退した）選手は、引退した年
## （ゲームを始める前に引退した選手は最後に1軍に出た年）の能力値ファイルで
static func _rank_of(id: String, p: Dictionary, last_year: int) -> String:
	var src := p
	var league: LeagueRoster = GameState.league
	if GameData.player(id).is_empty():
		var ry := last_year
		if league != null and league.retired.has(id):
			ry = int(league.retired[id])
		if ry >= HIST_FIRST_YEAR:
			# 引退した年の能力値ファイルのランク。選手ごとに年が違うので、ファイルを丸ごと持たずランクだけを覚える
			var ranks := _ranks_of(mini(ry, HIST_LAST_YEAR), "post")
			if ranks.has(id):
				return ranks[id]
	if src.is_empty() or (src.get("batting") == null and src.get("pitching") == null):
		return ""
	return Depth.rank_of(Depth.now_score(src))


## その年の能力値ファイルの全選手の総合ランク（選手ID → ランク。ランクの出せない選手はいない）
static func _ranks_of(y: int, phase: String) -> Dictionary:
	var key := "%d_%s" % [y, phase]
	if _rank_cache.has(key):
		return _rank_cache[key]
	var src: Dictionary = _ratings_cache[key] if _ratings_cache.has(key) else {}
	var players: Array = src.values() if not src.is_empty() else GameData.peek_ratings(y, phase, false).get("players", [])
	var ranks := {}
	for p: Dictionary in players:
		if p.get("batting") != null or p.get("pitching") != null:
			ranks[str(p["id"])] = Depth.rank_of(Depth.now_score(p))
	_rank_cache[key] = ranks
	return ranks


static func _status_of(r: Dictionary) -> void:
	var id: String = r["id"]
	var league: LeagueRoster = GameState.league
	r["now_team"] = ""
	if id.is_empty() or league == null:
		r["status"] = "unknown"
	elif league.team_of.has(id):
		r["status"] = "active"
		r["now_team"] = league.team_of[id]
	elif league.in_mlb.has(id):
		r["status"] = "mlb"
	elif league.names.has(id) and not league.retired.has(id):
		r["status"] = "left"
	else:
		r["status"] = "retired"


## 「右投左打」→「右左」
static func hand_text(p: Dictionary) -> String:
	var t: String = p.get("throws") if p.get("throws") is String else ""
	var b: String = p.get("bats") if p.get("bats") is String else ""
	if t.is_empty() and b.is_empty():
		return "-"
	return t.left(1) + b.left(1)


# --- 画面 --------------------------------------------------------------------------------------

static func build_members(v: RecordsView) -> void:
	var years := member_years()
	if years.is_empty():
		v._body.add_child(UiTheme.small_label("まだ記録がありません", 16, UiTheme.TEXT, 700))
		return
	if v._mem_year not in years:
		v._mem_year = years[-1]
	_stepper(v, years, v._mem_year, func(y: int) -> void: v._mem_year = y)
	v._options.add_child(v._option_button("野手", not v._mem_pitch, func() -> void: v._mem_pitch = false, 70))
	v._options.add_child(v._option_button("投手", v._mem_pitch, func() -> void: v._mem_pitch = true, 70))
	var legend := UiTheme.small_label("赤字＝リーグ1位・橙＝3位まで　☆＝タイトル・表彰", 14, UiTheme.TEXT_SUB, 700)
	legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v._options.add_child(legend)
	if v._mem_team.is_empty():
		v._mem_team = GameState.team
	_team_picker(v, v._mem_team, func(t: String) -> void: v._mem_team = t)
	var m := members(v._mem_year, v._mem_team)
	var source := "ゲーム内の成績" if m["game"] else "史実の成績"
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	v._body.add_child(cols)
	var left := _column(cols)
	var right := _column(cols)
	if v._mem_pitch:
		_heading(v, left, "先発ローテーション")
		_pit_header(v, left)
		for e: Dictionary in m["rotation"]:
			_pit_row(v, left, "先", e, true)
		if m["rotation"].is_empty():
			left.add_child(UiTheme.small_label("（記録なし）", 15, UiTheme.TEXT_SUB, 700))
		_heading(v, left, "抑え")
		_pit_header(v, left)
		for e: Dictionary in m["closer"]:
			_pit_row(v, left, "抑", e, true)
		if m["closer"].is_empty():
			left.add_child(UiTheme.small_label("（セーブ%d以上の投手なし）" % CLOSER_MIN_SV, 15, UiTheme.TEXT_SUB, 700))
		_heading(v, right, "中継ぎ（ホールド・セーブの多い順）")
		_pit_header(v, right)
		for e: Dictionary in m["relief"]:
			_pit_row(v, right, "中", e, false)
		v.message_changed.emit("%d年 %sの投手陣（%s）。先発ローテは先発の多い順%s。名前札から選手詳細。" % [
			v._mem_year, GameData.short_name(v._mem_team), source, "" if m["game"] else "（史実は1登板の投球回で先発を見分ける）"])
		return
	_heading(v, left, "主なスタメン（%s）" % ("DH制" if m["dh"] else "9番は投手"))
	_bat_header(v, left)
	for s: Dictionary in m["lineup"]:
		_bat_row(v, left, str(s["slot"]), s["e"], s["pos"], true)
	if not m["dh"]:
		var row := _row(left, ROW_TINT)
		row.add_child(v._cell("9", BAT_W[0], UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		var tag := NameTag.new()
		tag.custom_minimum_size = Vector2(BAT_W[1], 28)
		tag.font_size = 15
		tag.setup_plain("投手", NameTag.COLOR_PITCHER)
		tag.disabled = true
		row.add_child(tag)
	if m["lineup"].is_empty():
		left.add_child(UiTheme.small_label("（記録なし）", 15, UiTheme.TEXT_SUB, 700))
	_heading(v, right, "主な控え（打席の多い順）")
	_bat_header(v, right)
	for s: Dictionary in m["bench"]:
		_bat_row(v, right, "-", s["e"], s["pos"], false)
	var how := "その年いちばん多かった打順と守備位置" if m["game"] else "守備位置ごとに試合の多い選手。打順は成績から（史実に打順の記録が無いため）"
	v.message_changed.emit("%d年 %sの野手（%s）。%s。名前札から選手詳細。" % [v._mem_year,
		GameData.short_name(v._mem_team), source, how])


static func build_drafts(v: RecordsView) -> void:
	var years := draft_years()
	if years.is_empty():
		v._body.add_child(UiTheme.small_label("まだ記録がありません", 16, UiTheme.TEXT, 700))
		return
	if v._dr_year not in years:
		v._dr_year = years[-1]
	_stepper(v, years, v._dr_year, func(y: int) -> void: v._dr_year = y)
	var legend := UiTheme.small_label("評価＝今の能力（引退した選手は最後の年）　通算成績＝1軍", 14, UiTheme.TEXT_SUB, 700)
	legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v._options.add_child(legend)
	if v._dr_team.is_empty():
		v._dr_team = GameState.team
	_team_picker(v, v._dr_team, func(t: String) -> void: v._dr_team = t)
	var picks := draft_picks(v._dr_year, v._dr_team)
	var rows: Array = picks["rows"]
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	for i in DRAFT_HEAD.size():
		header.add_child(_head(DRAFT_HEAD[i], DRAFT_W[i]))
	v._fixed.add_child(v._header_panel(header))
	var shown_ikusei := false
	if rows.is_empty():
		v._body.add_child(UiTheme.small_label("この年の指名の記録がありません", 16, UiTheme.TEXT_SUB, 700))
	for r: Dictionary in rows:
		if r["ikusei"] and not shown_ikusei:
			shown_ikusei = true
			_heading(v, v._body, "育成指名")
		_draft_row(v, r)
	var source := "ゲーム内のドラフト" if picks["game"] else "史実のドラフト"
	v.message_changed.emit("%d年秋 %sの指名（%s）。今の球団・評価・通算成績は今のゲームの状態。名前札から選手詳細。" % [
		v._dr_year, GameData.short_name(v._dr_team), source])


# --- 部品 --------------------------------------------------------------------------------------

## 年を選ぶ ◀ 2008年 ▶
static func _stepper(v: RecordsView, years: Array[int], current: int, set_year: Callable) -> void:
	var i := years.find(current)
	for d: int in [-1, 1]:
		var b := v._option_button("◀" if d < 0 else "▶", false, func() -> void:
			set_year.call(years[clampi(years.find(current) + d, 0, years.size() - 1)]), 40)
		b.toggle_mode = false
		b.disabled = (d < 0 and i == 0) or (d > 0 and i == years.size() - 1)
		if d > 0:
			var label := UiTheme.small_label("%d年" % current, 18, UiTheme.TEXT, 800)
			label.custom_minimum_size = Vector2(80, 0)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			v._options.add_child(label)
		v._options.add_child(b)


## 12球団のマーク（押すとその球団）。選んでいる球団は押した色、横に球団名
static func _team_picker(v: RecordsView, current: String, set_team: Callable) -> void:
	for team: String in GameData.teams():
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = same_team(team, current)
		b.custom_minimum_size = Vector2(EMBLEM_SIZE + 6, EMBLEM_SIZE)
		b.tooltip_text = GameData.short_name(team)
		UiTheme.style_toggle(b, v._palette.ink, 8)
		var emblem := TeamEmblem.new()
		emblem.setup(UiTheme.team_palette(team), GameData.short_name(team).substr(0, 2))
		emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		emblem.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
		b.add_child(emblem)
		b.set_meta("team", team)
		b.pressed.connect(func() -> void:
			set_team.call(team)
			v.refresh()
			for c in v._sub_options.get_children():
				if c.has_meta("team") and c.get_meta("team") == team:
					UiInput.grab(c))
		v._sub_options.add_child(b)
	var label := UiTheme.small_label(GameData.short_name(current), 18, UiTheme.TEXT, 800)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v._sub_options.add_child(label)


static func _column(parent: Control) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	parent.add_child(col)
	return col


static func _heading(v: RecordsView, parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	UiTheme.heading(label, 18, v._palette.ink, Color.WHITE, 6)
	parent.add_child(label)


static func _row(parent: Control, tint: Color) -> HBoxContainer:
	var panel := PanelContainer.new()
	var style := UiTheme.box(tint, 6)
	style.content_margin_left = 4
	style.content_margin_right = 4
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	parent.add_child(panel)
	return row


static func _head(text: String, width: float) -> Label:
	var label := UiTheme.small_label(text, 13, UiTheme.TEXT_SUB, 800)
	label.custom_minimum_size = Vector2(width, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	return label


static func _header_row(parent: Control, heads: Array, widths: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 0)
	row.add_child(pad)
	for i in heads.size():
		row.add_child(_head(heads[i], widths[i]))
	parent.add_child(row)


static func _bat_header(_v: RecordsView, parent: Control) -> void:
	_header_row(parent, BAT_HEAD, BAT_W)


static func _pit_header(_v: RecordsView, parent: Control) -> void:
	_header_row(parent, PIT_HEAD, PIT_W)


## 数字（リーグ上位は色。ツールチップに順位）
static func _num(v: RecordsView, text: String, width: float, rank: int) -> Label:
	var color := UiTheme.TEXT
	if rank == 1:
		color = LEADER_COLOR
	elif rank > 1:
		color = TOP_COLOR
	var label := v._cell(text, width, color)
	if rank > 0:
		label.tooltip_text = "リーグ%d位" % rank
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.add_theme_font_override("font", UiTheme.font(800))
	return label


static func _star(v: RecordsView, stars: Array, width: float) -> Label:
	var text := ""
	if stars.size() == 1:
		text = "☆"
	elif stars.size() > 1:
		text = "☆%d" % stars.size()
	var label := v._cell(text, width, STAR_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	if not stars.is_empty():
		label.tooltip_text = "・".join(PackedStringArray(stars))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label


static func _age_text(id: String, y: int) -> String:
	var age := FreeAgency.age_of(bio_of(id, y), y)
	return "%d" % age if age > 0 else "-"


## 名前札（その年の守備位置の色）
static func _name_tag(v: RecordsView, e: Dictionary, width: float, colors: Array[Color]) -> NameTag:
	var tag := v._tag(e["id"], e["name"], width)
	tag.colors = colors
	tag.queue_redraw()
	return tag


static func _bat_row(v: RecordsView, parent: Control, slot: String, e: Dictionary, pos: String, starter: bool) -> void:
	var y := v._mem_year
	var b: Dictionary = e["line"]
	var rank: Dictionary = e["rank"]
	var subs := sub_positions(e, pos)
	var row := _row(parent, STARTER_TINT if starter else ROW_TINT)
	row.add_child(v._cell(slot, BAT_W[0], UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var colors: Array[Color] = [NameTag.pos_color(pos)]
	if not subs.is_empty() and NameTag.pos_color(subs[0]) != colors[0]:
		colors.append(NameTag.pos_color(subs[0]))
	row.add_child(_name_tag(v, e, BAT_W[1], colors))
	var pos_text := str(POS_SHORT.get(pos, pos.left(1)))
	if not subs.is_empty():
		pos_text += "/" + str(POS_SHORT.get(subs[0], subs[0].left(1)))
	var pos_cell := v._cell(pos_text, BAT_W[2], UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	var pos_tip: Array = []
	for p: String in e["pos_g"]:
		if p != "投手":
			pos_tip.append("%s %d" % [p, int(e["pos_g"][p])])
	pos_cell.tooltip_text = "守備位置の試合数：" + "、".join(PackedStringArray(pos_tip)) if not pos_tip.is_empty() else ""
	pos_cell.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(pos_cell)
	row.add_child(v._cell(hand_text(bio_of(e["id"], y)), BAT_W[3], UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(v._cell(str(int(b.get("g", 0))), BAT_W[4]))
	var ab := int(b.get("ab", 0))
	var avg := float(b.get("h", 0)) / float(ab) if ab > 0 else 0.0
	row.add_child(_num(v, Records.format("rate3", avg) if ab > 0 else "-", BAT_W[5], int(rank.get("avg", 0))))
	row.add_child(_num(v, str(int(b.get("hr", 0))), BAT_W[6], int(rank.get("hr", 0))))
	row.add_child(_num(v, str(int(b.get("rbi", 0))), BAT_W[7], int(rank.get("rbi", 0))))
	row.add_child(_num(v, str(int(b.get("sb", 0))), BAT_W[8], int(rank.get("sb", 0))))
	row.add_child(v._cell(_age_text(e["id"], y), BAT_W[9]))
	row.add_child(_star(v, e["stars"], BAT_W[10]))


static func _pit_row(v: RecordsView, parent: Control, role: String, e: Dictionary, starter: bool) -> void:
	var y := v._mem_year
	var p: Dictionary = e["line"]
	var rank: Dictionary = e["rank"]
	var row := _row(parent, STARTER_TINT if starter else ROW_TINT)
	row.add_child(v._cell(role, PIT_W[0], UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var colors: Array[Color] = [NameTag.COLOR_PITCHER]
	row.add_child(_name_tag(v, e, PIT_W[1], colors))
	row.add_child(v._cell(hand_text(bio_of(e["id"], y)), PIT_W[2], UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(v._cell(str(int(p.get("g", 0))), PIT_W[3]))
	row.add_child(_num(v, "%d-%d" % [int(p.get("w", 0)), int(p.get("l", 0))], PIT_W[4], int(rank.get("w", 0))))
	row.add_child(_num(v, str(int(p.get("sv", 0))), PIT_W[5], int(rank.get("sv", 0))))
	row.add_child(_num(v, str(int(p.get("hld", 0))), PIT_W[6], int(rank.get("hld", 0))))
	var outs := int(p.get("outs", 0))
	var era := float(p.get("er", 0)) * 27.0 / float(outs) if outs > 0 else 99.0
	row.add_child(_num(v, Records.format("rate2", era), PIT_W[7], int(rank.get("era", 0))))
	row.add_child(v._cell(Records.format("ip", outs), PIT_W[8]))
	row.add_child(_num(v, str(int(p.get("so", 0))), PIT_W[9], int(rank.get("so", 0))))
	row.add_child(v._cell(_age_text(e["id"], y), PIT_W[10]))
	row.add_child(_star(v, e["stars"], PIT_W[11]))


static func _draft_row(v: RecordsView, r: Dictionary) -> void:
	var active: bool = r["status"] in ["active", "mlb"]
	var row := v._row_panel(RecordsView.MINE_TINT if r["status"] == "active" and same_team(r["now_team"], v._dr_team)
		else ROW_TINT)
	row.add_child(v._cell(r["label"], DRAFT_W[0], UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var tag := v._tag(r["id"], r["name"], DRAFT_W[1])
	if str(r["id"]).is_empty() or GameData.player(r["id"]).is_empty():
		var colors: Array[Color] = [r["pos_color"]]
		tag.colors = colors
		tag.queue_redraw()
	row.add_child(tag)
	row.add_child(_team_chip(r))
	row.add_child(v._cell(r["pos"], DRAFT_W[3], UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(v._cell(r["cat"], DRAFT_W[4], UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var school := v._cell(r["school"], DRAFT_W[5], UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_LEFT)
	school.tooltip_text = r["school"]
	school.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(school)
	row.add_child(v._cell(r["hand"], DRAFT_W[6], UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var rank_box := CenterContainer.new()
	rank_box.custom_minimum_size = Vector2(DRAFT_W[7], 0)
	rank_box.add_child(v._rank(r["rank"]) if not str(r["rank"]).is_empty() else UiTheme.small_label("-", 15))
	row.add_child(rank_box)
	for cell: Label in _career_cells(v, r):
		row.add_child(cell)
	var mark := v._cell("現役" if active else "", DRAFT_W[13], ACTIVE_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	mark.add_theme_font_override("font", UiTheme.font(800))
	row.add_child(mark)


## 通算成績の5つの欄（野手：試合・打率・本塁打・打点・盗塁、投手：登板・防御率・勝敗・H・S）。出場が無ければ1つにまとめる
static func _career_cells(v: RecordsView, r: Dictionary) -> Array[Label]:
	var cells: Array[Label] = []
	var career: Dictionary = r["career"]
	var total_w := 0.0
	for i in range(8, 13):
		total_w += DRAFT_W[i] + 4
	total_w -= 4
	if str(r["id"]).is_empty():
		cells.append(v._cell("（記録なし）", total_w, UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_CENTER))
		return cells
	if r["pitcher"]:
		var p: Dictionary = career.get("p", {})
		if int(p.get("g", 0)) == 0:
			cells.append(v._cell("一軍登板なし", total_w, UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_CENTER))
			return cells
		var outs := int(p.get("outs", 0))
		var era := float(p.get("er", 0)) * 27.0 / float(outs) if outs > 0 else 99.0
		cells.append(v._cell("%d登板" % int(p["g"]), DRAFT_W[8]))
		cells.append(v._cell(Records.format("rate2", era), DRAFT_W[9]))
		cells.append(v._cell("%d勝%d敗" % [int(p.get("w", 0)), int(p.get("l", 0))], DRAFT_W[10]))
		cells.append(v._cell("%dH" % int(p.get("hld", 0)), DRAFT_W[11]))
		cells.append(v._cell("%dS" % int(p.get("sv", 0)), DRAFT_W[12]))
		return cells
	var b: Dictionary = career.get("b", {})
	if int(b.get("g", 0)) == 0:
		cells.append(v._cell("一軍出場なし", total_w, UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_CENTER))
		return cells
	var ab := int(b.get("ab", 0))
	cells.append(v._cell("%d試合" % int(b["g"]), DRAFT_W[8]))
	cells.append(v._cell(Records.format("rate3", float(b.get("h", 0)) / float(ab)) if ab > 0 else "-", DRAFT_W[9]))
	cells.append(v._cell("%d本" % int(b.get("hr", 0)), DRAFT_W[10]))
	cells.append(v._cell("%d打点" % int(b.get("rbi", 0)), DRAFT_W[11]))
	cells.append(v._cell("%d盗" % int(b.get("sb", 0)), DRAFT_W[12]))
	return cells


## 今の球団（球団カラーの札。引退・メジャー・不明は灰色・紺）
static func _team_chip(r: Dictionary) -> Control:
	var text := "引退"
	var bg := Color("cfd6dd")
	match str(r["status"]):
		"active":
			text = GameData.short_name(r["now_team"])
			bg = GameData.team_colors(r["now_team"])[0]
		"mlb":
			text = "MLB"
			bg = Color("1a237e")
		"left":
			text = "退団"
		"unknown":
			text = "-"
			bg = Color("eceff1")
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(DRAFT_W[2], 26)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", UiTheme.box(bg, 6))
	var label := UiTheme.small_label(text, 14, UiTheme.text_on(bg), 800)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	panel.add_child(label)
	return panel
