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
var _players_by_team: Dictionary = {}
var _players_by_id: Dictionary = {}
## 来季の能力値ファイルの選手（オフに加わった新人・復帰選手・外国人市場の候補を、年が変わる前から引けるように）
var _supplement: Dictionary = {}
## メジャーにいる選手の能力値（能力値ファイルの mlb_players。引き留めたときに使う）
var _mlb_by_id: Dictionary = {}
## 引き留めたメジャー移籍の選手（今のファイルの players にいない）として _players_by_id に足した選手ID
var _kept_ids: Array[String] = []
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
	if not path.is_empty() and path == _loaded_file:
		return true
	if path.is_empty():
		push_warning("能力値ファイルがありません: %d_%s.json" % [year, phase])
		return false
	var parsed := _parse_ratings(path)
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


## ゲーム内の所属（選手ID → 球団）を能力値データに書き込み、球団別の一覧を作り直す
func apply_roster(team_of: Dictionary) -> void:
	_players_by_team.clear()
	for p: Dictionary in ratings.get("players", []):
		if not team_of.has(p["id"]):
			p["team"] = ""
	for id in _kept_ids:
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
		if not parsed is Array:
			parsed = _read_repo_json("drafts_2001-2007.json")
		if parsed is Array:
			for d: Dictionary in parsed:
				if int(d.get("draft_year", 0)) == draft_year:
					by_name[LeagueRoster.norm_name(d["name"])] = d
		_drafts_cache[draft_year] = by_name
	return _drafts_cache[draft_year].get(LeagueRoster.norm_name(name), {})


func find_ratings_path(year: int, phase: String) -> String:
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


## data/<年>/schedule.json の中身（試合の配列）。無ければ空配列
func load_schedule(year: int) -> Array:
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


## data/<年>/rosters.json から 選手ID → 1軍初出場の年（debut_year）。外国人枠の「日本人扱い」の判定に使う
func load_debut_years(year: int) -> Dictionary:
	return _roster_field(year, "debut_year")


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


func _read_repo_json(relative: String) -> Variant:
	var repo_path := ProjectSettings.globalize_path("res://").path_join(REPO_DATA_DIR)
	var path := repo_path.path_join(relative).simplify_path()
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## 選手IDから能力値ファイルの選手データを引く（今のファイルに無ければ来季のファイル。無ければ空）
func player(id: String) -> Dictionary:
	return _players_by_id.get(id, _supplement.get(id, {}))


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
