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

## 現在の能力値ファイルの中身（schema_version 3）
var ratings: Dictionary = {}
var _players_by_team: Dictionary = {}
var _players_by_id: Dictionary = {}
var _loaded_file := ""


## <年>_<phase>.json を読み込む。見つからなければ false を返し、現在のデータを保持する。
func load_ratings(year: int, phase: String) -> bool:
	var path := find_ratings_path(year, phase)
	if not path.is_empty() and path == _loaded_file:
		return true
	if path.is_empty():
		push_warning("能力値ファイルがありません: %d_%s.json" % [year, phase])
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("能力値ファイルを読めません: " + path)
		return false
	ratings = parsed
	_loaded_file = path
	_index_players()
	return true


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
	var repo_path := ProjectSettings.globalize_path("res://").path_join(REPO_DATA_DIR)
	var path := repo_path.path_join("%d/rosters.json" % year).simplify_path()
	var result := {}
	if not FileAccess.file_exists(path):
		return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Array:
		for r: Dictionary in parsed:
			if r.get("player_id") != null and r.get("debut_year") != null:
				result[r["player_id"]] = r["debut_year"]
	return result


## 選手IDから能力値ファイルの選手データを引く（無ければ空）
func player(id: String) -> Dictionary:
	return _players_by_id.get(id, {})


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


func _index_players() -> void:
	_players_by_team.clear()
	_players_by_id.clear()
	for p: Dictionary in ratings.get("players", []):
		_players_by_id[p["id"]] = p
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
