# gdlint: disable=max-public-methods
extends Node
## 能力値データ（tools/compute_ratings.py の出力）の読み込みと参照。
##
## 読み込み先は次の順に探す:
##   1. res://data/ratings/<年>_<phase>.json（書き出し時にコピーする想定）
##   2. リポジトリ直下の generated/ratings/（エディタ実行時。コピー不要）

const DATA_DIR := "res://data/ratings"
const GENERATED_DIR := "../generated/ratings"
## 史実の日程（npb_collector/schedule.py の出力）。書き出し時は res://data/schedule/<年>.json にコピーする想定
const SCHEDULE_DIR := "res://data/schedule"
const REPO_DATA_DIR := "../data"

const LEAGUE_NAMES := {"C": "セ・リーグ", "P": "パ・リーグ"}
## この年より後で日程・名簿のファイルが無い年は、前の年のものを写す（load_schedule・load_debut_years）
const SCHEDULE_COPY_FROM := 2026

## 表示順（ここにない球団名は末尾に名前順で並ぶ）
const TEAM_ORDER := [
	"読売ジャイアンツ", "阪神タイガース", "中日ドラゴンズ",
	"横浜ベイスターズ", "横浜DeNAベイスターズ", "広島東洋カープ", "東京ヤクルトスワローズ",
	"埼玉西武ライオンズ", "オリックス・バファローズ", "福岡ソフトバンクホークス",
	"北海道日本ハムファイターズ", "千葉ロッテマリーンズ", "東北楽天ゴールデンイーグルス",
]

const TEAM_SHORT := {
	"読売ジャイアンツ": "巨人",
	"阪神タイガース": "阪神",
	"中日ドラゴンズ": "中日",
	"横浜ベイスターズ": "横浜",
	"横浜DeNAベイスターズ": "DeNA",
	"広島東洋カープ": "広島",
	"東京ヤクルトスワローズ": "ヤクルト",
	"埼玉西武ライオンズ": "西武",
	"オリックス・バファローズ": "オリックス",
	"福岡ソフトバンクホークス": "ソフトバンク",
	"北海道日本ハムファイターズ": "日本ハム",
	"千葉ロッテマリーンズ": "ロッテ",
	"東北楽天ゴールデンイーグルス": "楽天",
}

## 球団カラー [メイン, サブ]。画面のテーマ色に使う（UiTheme.team_palette）
const TEAM_COLORS := {
	"読売ジャイアンツ": ["f97709", "1a1a1a"],
	"阪神タイガース": ["ffd800", "1a1a1a"],
	"中日ドラゴンズ": ["00338d", "8ec6ec"],
	"横浜ベイスターズ": ["0b4fa8", "9fd6f2"],
	"横浜DeNAベイスターズ": ["0055a5", "00a0e9"],
	"広島東洋カープ": ["e60012", "1a2a5a"],
	"東京ヤクルトスワローズ": ["2e9b48", "0b2c6b"],
	"埼玉西武ライオンズ": ["102961", "3fa9f5"],
	"オリックス・バファローズ": ["0e2350", "b5975a"],
	"福岡ソフトバンクホークス": ["f9c800", "1a1a1a"],
	"北海道日本ハムファイターズ": ["0065b3", "b59b5a"],
	"千葉ロッテマリーンズ": ["1a1a1a", "a7a9ac"],
	"東北楽天ゴールデンイーグルス": ["86001b", "c8a14b"],
}
const DEFAULT_TEAM_COLORS := ["1f5fae", "f2b705"]

## 守備位置の並び順（一覧のソート用）
const POS_ORDER := ["捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "内野手", "外野手", "指名打者", "投手"]

## ランクの文字色（明るい背景用）
const RANK_COLORS := {
	"S": Color("d81b60"),
	"A": Color("e53935"),
	"B": Color("f4511e"),
	"C": Color("ef8a00"),
	"D": Color("c49a00"),
	"E": Color("43a047"),
	"F": Color("1e88e5"),
	"G": Color("8a9199"),
}

## 球団の略称（史実のデータ：trades.json・mlb_moves.json の表記）→ 正式名。
## 「横浜」は2012年から DeNA（resolve_team で年を見て切り替える）
const TEAM_ALIASES := {
	"読売": "読売ジャイアンツ", "巨人": "読売ジャイアンツ", "阪神": "阪神タイガース", "中日": "中日ドラゴンズ",
	"横浜DeNA": "横浜DeNAベイスターズ", "DeNA": "横浜DeNAベイスターズ", "広島東洋": "広島東洋カープ",
	"広島": "広島東洋カープ", "東京ヤクルト": "東京ヤクルトスワローズ", "ヤクルト": "東京ヤクルトスワローズ",
	"埼玉西武": "埼玉西武ライオンズ", "西武": "埼玉西武ライオンズ", "オリックス": "オリックス・バファローズ",
	"福岡ソフトバンク": "福岡ソフトバンクホークス", "ソフトバンク": "福岡ソフトバンクホークス",
	"北海道日本ハム": "北海道日本ハムファイターズ", "日本ハム": "北海道日本ハムファイターズ",
	"千葉ロッテ": "千葉ロッテマリーンズ", "ロッテ": "千葉ロッテマリーンズ",
	"東北楽天": "東北楽天ゴールデンイーグルス", "楽天": "東北楽天ゴールデンイーグルス",
}
const DENA_FROM_YEAR := 2012

## 現在の能力値ファイルの中身（schema_version 4）。
## 各選手の team / league は、ゲーム内の所属（GameState.league）を apply_roster() で書き込んだもの。
## 史実（能力値ファイル）の球団は hist_team に残す。所属していない選手（外国人市場の候補など）は team が空
var ratings: Dictionary = {}
## 史実の能力値ファイルが無い年（Growth.FIRST_YEAR〜）に、オフに成長させて作った来季の能力値（年 → ファイルと同じ形）。
## その年の pre・post の両方として使い、ファイルより優先する。GameState がセーブに残す（docs/AUTORUN.md 作業27）
var synthetic: Dictionary = {}
## 史実の無い年の架空のドラフト候補（ドラフトの年 → 選手の配列。GameState.draft_class が作り、セーブに残す。作業22・32）。
## ドラフトの前でも選手詳細を開けるよう player() で引ける
var draft_classes: Dictionary = {}
var _prospects: Dictionary = {}
## 名簿（data/<年>/rosters.json）の無い年の1軍初出場の年に足す 選手ID → 年（ゲーム内で入った選手。LeagueRoster.joined）
var debut_extra: Dictionary = {}
var _players_by_team: Dictionary = {}
var _players_by_id: Dictionary = {}
## 来季の能力値ファイルの選手（オフに加わった新人・復帰選手・外国人市場の候補を、年が変わる前から引けるように）
var _supplement: Dictionary = {}
## メジャーにいる選手の能力値（能力値ファイルの mlb_players。引き留めたときに使う）
var _mlb_by_id: Dictionary = {}
## 引き留めたメジャー移籍の選手（今のファイルの players にいない）として _players_by_id に足した選手ID
var _kept_ids: Array[String] = []
## 能力値ファイルにいない選手（ドラフトの仮の新人など）として _players_by_id に足した選手ID
var _extra_ids: Array[String] = []
var _team_league: Dictionary = {}
var _parsed_cache: Dictionary = {}
var _drafts_cache: Dictionary = {}
var _loaded_file := ""
var _pages_year := -1
var _pages := {}
var _roster_cache := {}


## <年>_<phase>.json を読み込む。見つからなければ false を返し、現在のデータを保持する。
func load_ratings(year: int, phase: String) -> bool:
	var path := find_ratings_path(year, phase)
	if not path.is_empty() and path == _loaded_file and (not synthetic.has(year) or is_same(ratings, synthetic[year])):
		return true
	if path.is_empty():
		push_warning("能力値ファイルがありません: %d_%s.json" % [year, phase])
		return false
	var parsed: Dictionary = synthetic[year] if synthetic.has(year) else _parse_ratings(path)
	if parsed.is_empty():
		return false
	ratings = parsed
	_parsed_cache.erase(path)
	_loaded_file = path
	_supplement.clear()
	_index_players()
	return true


## 能力値ファイルを今のデータを変えずに読む（来季の準備用。読んだものは load_ratings() でそのまま使う）
func peek_ratings(year: int, phase: String) -> Dictionary:
	var path := find_ratings_path(year, phase)
	if path.is_empty():
		return {}
	if path == _loaded_file:
		return ratings
	if synthetic.has(year):
		var syn: Dictionary = synthetic[year]
		for p: Dictionary in syn.get("players", []):
			if not p.has("hist_team"):
				p["hist_team"] = p["team"]
		return syn
	if not _parsed_cache.has(path):
		var parsed := _parse_ratings(path)
		if parsed.is_empty():
			return {}
		for p: Dictionary in parsed.get("players", []):
			p["hist_team"] = p["team"]
		_parsed_cache[path] = parsed
	return _parsed_cache[path]


func _parse_ratings(path: String) -> Dictionary:
	if _parsed_cache.has(path):
		return _parsed_cache[path]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("能力値ファイルを読めません: " + path)
		return {}
	return parsed


## 来季の能力値ファイルの選手を、今のファイルに無い選手の能力値として引けるようにする
func set_supplement(next_ratings: Dictionary) -> void:
	_supplement.clear()
	for p: Dictionary in next_ratings.get("players", []):
		if not _players_by_id.has(p["id"]):
			_supplement[p["id"]] = p
			var team: String = p.get("hist_team", p["team"])
			if not _team_league.has(team) and p.get("league") != null:
				_team_league[team] = p["league"]


## 引き留めたメジャー移籍の選手（選手ID → 直前のNPBの能力値）を、今のファイルの players にいなければ
## 選手として引けるようにする。能力値は今のファイルの mlb_players（メジャーにいた年の換算）、無ければ直前のNPBの値
func set_kept_players(fallbacks: Dictionary) -> void:
	for id in _kept_ids:
		_players_by_id.erase(id)
	_kept_ids.clear()
	for id: String in fallbacks:
		if _players_by_id.has(id):
			continue
		var src: Dictionary = _mlb_by_id.get(id, fallbacks[id])
		var p: Dictionary = src.duplicate(true)
		p["hist_team"] = ""
		p["team"] = ""
		p["kept_from_mlb"] = "mlb" if _mlb_by_id.has(id) else "npb"
		_players_by_id[id] = p
		_kept_ids.append(id)


## 能力値ファイルにいない選手（選手ID → 選手データ。LeagueRoster.extra_players）を引けるようにする。
## 今のファイルか来季のファイルにいれば（本来の選手として出てきたら）そちらを使う
func set_extra_players(extra: Dictionary) -> void:
	for id in _extra_ids:
		_players_by_id.erase(id)
	_extra_ids.clear()
	for id: String in extra:
		if _players_by_id.has(id) or _supplement.has(id):
			continue
		_players_by_id[id] = extra[id]
		_extra_ids.append(id)


## ゲーム内の所属（選手ID → 球団）を能力値データに書き込み、球団別の一覧を作り直す
func apply_roster(team_of: Dictionary) -> void:
	_players_by_team.clear()
	for p: Dictionary in ratings.get("players", []):
		if not team_of.has(p["id"]):
			p["team"] = ""
	for id in _kept_ids:
		if not team_of.has(id):
			_players_by_id[id]["team"] = ""
	for id in _extra_ids:
		if not team_of.has(id):
			_players_by_id[id]["team"] = ""
	for p: Dictionary in _supplement.values():
		if not team_of.has(p["id"]):
			p["team"] = ""
	for id: String in team_of:
		var p := player(id)
		if p.is_empty():
			continue
		var team: String = team_of[id]
		p["team"] = team
		p["league"] = _team_league.get(team, p.get("league"))
		if not _players_by_team.has(team):
			_players_by_team[team] = []
		_players_by_team[team].append(p)


## 所属している全選手（Season を作るときに渡す）
func rostered_players() -> Array:
	var result: Array = []
	for team: String in teams():
		result.append_array(_players_by_team[team])
	return result


## メジャーにいる選手の能力値（その年のファイルの mlb_players。無ければ空）
func mlb_player(id: String) -> Dictionary:
	return _mlb_by_id.get(id, {})


## 史実のデータの球団の略称 → 正式名（その年の名前。「横浜」は2012年から DeNA）
func resolve_team(short: String, year: int) -> String:
	if short.is_empty():
		return ""
	if short == "横浜":
		return "横浜DeNAベイスターズ" if year >= DENA_FROM_YEAR else "横浜ベイスターズ"
	if TEAM_ALIASES.has(short):
		return TEAM_ALIASES[short]
	for team: String in TEAM_ORDER:
		if team.begins_with(short):
			return team
	return short


## data/ 直下の JSON（trades.json・mlb_moves.json など）。無ければ null
func read_data(file_name: String) -> Variant:
	return _read_repo_json(file_name)


## その年のドラフト会議で指名された選手（名前で探す）。{round, school, ikusei, ...}。見つからなければ空。
## data/<年+1>/drafts.json に「前年秋＋当年秋」の2回分がある（2007年以前は data/drafts_2001-2007.json）
func draft_entry(name: String, draft_year: int) -> Dictionary:
	if not _drafts_cache.has(draft_year):
		var by_name := {}
		var parsed: Variant = _read_repo_json("%d/drafts.json" % (draft_year + 1))
		if not parsed is Array and draft_year > Draft.LAST_HISTORY_YEAR:
			parsed = Draft.amateur_rows(draft_year)  # 史実の無い年のドラフト候補（data/amateur/<年>.json）
		elif not parsed is Array:
			parsed = _read_repo_json("drafts_2001-2007.json")
		if parsed is Array:
			for d: Dictionary in parsed:
				if int(d.get("draft_year", 0)) == draft_year:
					by_name[LeagueRoster.norm_name(d["name"])] = d
		_drafts_cache[draft_year] = by_name
	return _drafts_cache[draft_year].get(LeagueRoster.norm_name(name), {})


## 選手（能力値ファイルの行）のドラフト会議の一覧の行。名前で見つからなければ（登録名「雄星」・異体字など）、選手ページの
## 「<年>年ドラフト<n>位」と順位・育成が同じ行のうち、名前の一部が重なるか出身校が経歴にある行が1つだけならそれ
func draft_entry_for(p: Dictionary, draft_year: int) -> Dictionary:
	var player_name := str(p.get("name", ""))
	var entry := draft_entry(player_name, draft_year)
	if not entry.is_empty():
		return entry
	var text: String = p.get("draft") if p.get("draft") is String else ""
	if not text.begins_with("%d年" % draft_year):
		return {}
	var ikusei := "育成" in text
	var k := text.find("ドラフト")
	var rnd := _first_digits(text.substr(k + 4) if k >= 0 else "")
	var key := LeagueRoster.norm_name(player_name)
	var career := str(p.get("career", ""))
	# 名前の一部が重なる・出身校が経歴にある（末尾の「高」は省いて比べる）の合計点が最も高い行が1つだけならそれ
	var best: Array[Dictionary] = []
	var best_score := 0
	for d: Dictionary in _drafts_cache.get(draft_year, {}).values():
		if bool(d.get("ikusei", false)) != ikusei:
			continue
		if not rnd.is_empty() and _first_digits(str(d.get("round", ""))) != rnd:
			continue
		var dn := LeagueRoster.norm_name(str(d["name"]))
		var school := str(d.get("school", "")).trim_suffix("高")
		var score := 0
		if key.length() >= 2 and (dn.contains(key) or key.contains(dn)):
			score += 1
		if not school.is_empty() and career.contains(school):
			score += 1
		if score > best_score:
			best_score = score
			best = [d]
		elif score == best_score and score > 0:
			best.append(d)
	return best[0] if best.size() == 1 else {}


static func _first_digits(text: String) -> String:
	var digits := ""
	for ch in text:
		if ch.is_valid_int():
			digits += ch
		elif not digits.is_empty():
			break
	return digits


func find_ratings_path(year: int, phase: String) -> String:
	if synthetic.has(year):
		return "synthetic:%d" % year
	var file_name := "%d_%s.json" % [year, phase]
	# res:// の外（リポジトリの generated/）はエディタ実行時のみ参照できる
	var generated_dir := ProjectSettings.globalize_path("res://").path_join(GENERATED_DIR)
	var candidates := [
		DATA_DIR.path_join(file_name),
		generated_dir.path_join(file_name).simplify_path(),
	]
	for path: String in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


## リポジトリ直下の generated/ の JSON（draft_future.json など）。無ければ null
func read_generated(file_name: String) -> Variant:
	var path := ProjectSettings.globalize_path("res://").path_join("../generated").path_join(file_name).simplify_path()
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## data/<年>/schedule.json の中身（試合の配列）。無ければ空配列。
## 史実の無い年（SCHEDULE_COPY_FROM より後）でファイルが無ければ、いちばん近い前の年の日程を同じ曜日のまま
## 何年か後へずらして写す（作業17の2027年と同じ考え方。作業27で10年ほど進めるため）
func load_schedule(year: int) -> Array:
	var own := _schedule_file(year)
	if not own.is_empty() or year <= SCHEDULE_COPY_FROM:
		return own
	for src in range(year - 1, SCHEDULE_COPY_FROM - 1, -1):
		var base := _schedule_file(src)
		if not base.is_empty():
			return copy_schedule(base, year - src)
	return []


## 日程を years 年後へ写す（日付を7日の倍数だけずらし、曜日を保つ。ずらす日数は years 年にいちばん近い週数）
static func copy_schedule(base: Array, years: int) -> Array:
	var shift := roundi(365.2425 * years / 7.0) * 7 * 86400
	var out: Array = []
	for g: Dictionary in base:
		var c := g.duplicate()
		var t := Time.get_unix_time_from_datetime_string(str(g["date"]) + "T00:00:00") + shift
		c["date"] = Time.get_date_string_from_unix_time(t)
		c["status"] = "played"
		for key in ["home_score", "away_score"]:
			c.erase(key)
		out.append(c)
	return out


func _schedule_file(year: int) -> Array:
	var repo_path := ProjectSettings.globalize_path("res://").path_join(REPO_DATA_DIR)
	var candidates := [
		SCHEDULE_DIR.path_join("%d.json" % year),
		repo_path.path_join("%d/schedule.json" % year).simplify_path(),
	]
	for path: String in candidates:
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Array:
			return parsed
		push_error("日程ファイルを読めません: " + path)
	return []


## data/<年>/rosters.json から 選手ID → 1軍初出場の年（debut_year）。外国人枠の「日本人扱い」の判定に使う。
## 名簿の無い年は、いちばん近い前の年の名簿に debut_extra（ゲーム内で入った選手）を足したもの
func load_debut_years(year: int) -> Dictionary:
	var own := _roster_field(year, "debut_year")
	if not own.is_empty() or year <= SCHEDULE_COPY_FROM:
		return own
	var result := {}
	for src in range(year - 1, SCHEDULE_COPY_FROM - 1, -1):
		result = _roster_field(src, "debut_year").duplicate()
		if not result.is_empty():
			break
	for id: String in debut_extra:
		if not result.has(id):
			result[id] = debut_extra[id]
	return result


## data/<年>/rosters.json から 選手ID → 背番号（文字列）。背番号は 2026年の名簿にしか無い（無ければ空）
func uniform_numbers(year: int) -> Dictionary:
	return _roster_field(year, "number")


func _roster_field(year: int, key: String) -> Dictionary:
	var cache_key := "%d|%s" % [year, key]
	if _roster_cache.has(cache_key):
		return _roster_cache[cache_key]
	var result := {}
	var parsed: Variant = _read_repo_json("%d/rosters.json" % year)
	if parsed is Array:
		for r: Dictionary in parsed:
			if r.get("player_id") != null and r.get(key) != null:
				result[r["player_id"]] = r[key]
	_roster_cache[cache_key] = result
	return result


## 選手ページ（data/<年>/players.json）の中身：bio（経歴・ドラフト）と batting/pitching（1軍の年度別成績）。
## **npb.jp の今の選手ページなので <年> より後の成績も入っている**（表示する側で年度を絞る）。
## 5MB 前後あるので、選手詳細を初めて開いたときに1年分だけ読んで持っておく。無ければ空
func player_page(year: int, id: String) -> Dictionary:
	if _pages_year != year:
		_pages_year = year
		var parsed: Variant = _read_repo_json("%d/players.json" % year)
		_pages = parsed if parsed is Dictionary else {}
	return _pages.get(id, {})


## その年の選手ページ全部（選手ID → player_page と同じ中身）。player_page と同じ1年分の持ち方を使う
func all_player_pages(year: int) -> Dictionary:
	player_page(year, "")
	return _pages


func _read_repo_json(relative: String) -> Variant:
	var repo_path := ProjectSettings.globalize_path("res://").path_join(REPO_DATA_DIR)
	var path := repo_path.path_join(relative).simplify_path()
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## 選手IDから能力値ファイルの選手データを引く（今のファイルに無ければ来季のファイル。無ければ空）
func player(id: String) -> Dictionary:
	var p: Dictionary = _players_by_id.get(id, _supplement.get(id, _prospects.get(id, {})))
	if p.is_empty():
		return _mlb_by_id.get(id, {})
	return p


## 架空のドラフト候補を置く（draft_year 年の分。空の配列なら消す）。ドラフト会議の一覧のキャッシュも作り直す
func set_draft_class(draft_year: int, players: Array) -> void:
	if players.is_empty():
		draft_classes.erase(draft_year)
	else:
		draft_classes[draft_year] = players
	_drafts_cache.erase(draft_year)
	_prospects.clear()
	for y: int in draft_classes:
		for p: Dictionary in draft_classes[y]:
			_prospects[p["id"]] = p


func clear_draft_classes() -> void:
	draft_classes.clear()
	_prospects.clear()
	_drafts_cache.clear()


func has_ratings() -> bool:
	return not ratings.is_empty()


## 球団名の一覧（表示順）。league を指定するとそのリーグのみ。
func teams(league: String = "") -> Array[String]:
	var result: Array[String] = []
	for team: String in _players_by_team:
		var players: Array = _players_by_team[team]
		if league.is_empty() or players[0]["league"] == league:
			result.append(team)
	result.sort_custom(_team_before)
	return result


func players_of(team: String) -> Array:
	return _players_by_team.get(team, [])


func short_name(team: String) -> String:
	return TEAM_SHORT.get(team, team)


## [メイン, サブ] の Color
func team_colors(team: String) -> Array[Color]:
	var hex: Array = TEAM_COLORS.get(team, DEFAULT_TEAM_COLORS)
	return [Color(hex[0]), Color(hex[1])]


## "C"（セ）/"P"（パ）。不明なら空文字
func league_of(team: String) -> String:
	var players := players_of(team)
	return players[0]["league"] if not players.is_empty() else ""


func rank_color(rank: String) -> Color:
	return RANK_COLORS.get(rank, Color.WHITE)


func pos_index(pos: Variant) -> int:
	var i := POS_ORDER.find(pos)
	return i if i >= 0 else POS_ORDER.size()


## 読み込んだ直後は史実（能力値ファイル）の球団で分ける（apply_roster() でゲーム内の所属に置き換える）
func _index_players() -> void:
	_players_by_team.clear()
	_players_by_id.clear()
	_kept_ids.clear()
	_extra_ids.clear()
	_mlb_by_id.clear()
	_team_league.clear()
	for p: Dictionary in ratings.get("mlb_players", []):
		_mlb_by_id[p["id"]] = p
	for p: Dictionary in ratings.get("players", []):
		_players_by_id[p["id"]] = p
		if not p.has("hist_team"):
			p["hist_team"] = p["team"]
		if not _team_league.has(p["hist_team"]) and p.get("league") != null:
			_team_league[p["hist_team"]] = p["league"]
		p["team"] = p["hist_team"]
		var team: String = p["team"]
		if team.is_empty():
			continue  # 史実の無い年のドラフト候補（tools/amateur_ratings.py。指名されるまで球団なし）
		if not _players_by_team.has(team):
			_players_by_team[team] = []
		_players_by_team[team].append(p)


func _team_before(a: String, b: String) -> bool:
	var ia := TEAM_ORDER.find(a)
	var ib := TEAM_ORDER.find(b)
	if ia < 0:
		ia = TEAM_ORDER.size()
	if ib < 0:
		ib = TEAM_ORDER.size()
	return ia < ib if ia != ib else a < b
