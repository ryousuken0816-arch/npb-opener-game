extends Node
## 能力値データ（tools/compute_ratings.py の出力）の読み込みと参照。
##
## 読み込み先は次の順に探す:
##   1. res://data/ratings/<年>_<phase>.json（書き出し時にコピーする想定）
##   2. リポジトリ直下の generated/ratings/（エディタ実行時。コピー不要）

const DATA_DIR := "res://data/ratings"
const GENERATED_DIR := "../generated/ratings"

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

## 守備位置の並び順（一覧のソート用）
const POS_ORDER := ["捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "内野手", "外野手", "指名打者", "投手"]

## 球団カラー（テーマ配色用）。text はボタン等に載せる文字色
const TEAM_COLORS := {
	"読売ジャイアンツ": {"primary": Color("f39800"), "text": Color("202020")},
	"阪神タイガース": {"primary": Color("fff200"), "text": Color("202020")},
	"中日ドラゴンズ": {"primary": Color("0057a8"), "text": Color("ffffff")},
	"横浜ベイスターズ": {"primary": Color("0075c2"), "text": Color("ffffff")},
	"横浜DeNAベイスターズ": {"primary": Color("0075c2"), "text": Color("ffffff")},
	"広島東洋カープ": {"primary": Color("e60039"), "text": Color("ffffff")},
	"東京ヤクルトスワローズ": {"primary": Color("00a960"), "text": Color("ffffff")},
	"埼玉西武ライオンズ": {"primary": Color("003876"), "text": Color("ffffff")},
	"オリックス・バファローズ": {"primary": Color("ffb81c"), "text": Color("202020")},
	"福岡ソフトバンクホークス": {"primary": Color("f5ce00"), "text": Color("202020")},
	"北海道日本ハムファイターズ": {"primary": Color("00a0e9"), "text": Color("202020")},
	"千葉ロッテマリーンズ": {"primary": Color("1b3a6b"), "text": Color("ffffff")},
	"東北楽天ゴールデンイーグルス": {"primary": Color("870038"), "text": Color("ffffff")},
}

const DEFAULT_TEAM_COLOR := {"primary": Color("4a6fa5"), "text": Color("ffffff")}

## 本拠地球場（日程表の表示用。現行の呼称。年代によっては史実と異なる場合がある）
const STADIUM_NAMES := {
	"読売ジャイアンツ": "東京ドーム",
	"阪神タイガース": "阪神甲子園球場",
	"中日ドラゴンズ": "バンテリンドーム ナゴヤ",
	"横浜ベイスターズ": "横浜スタジアム",
	"横浜DeNAベイスターズ": "横浜スタジアム",
	"広島東洋カープ": "MAZDA Zoom-Zoom スタジアム広島",
	"東京ヤクルトスワローズ": "明治神宮野球場",
	"埼玉西武ライオンズ": "ベルーナドーム",
	"オリックス・バファローズ": "京セラドーム大阪",
	"福岡ソフトバンクホークス": "みずほPayPayドーム福岡",
	"北海道日本ハムファイターズ": "エスコンフィールドHOKKAIDO",
	"千葉ロッテマリーンズ": "ZOZOマリンスタジアム",
	"東北楽天ゴールデンイーグルス": "楽天モバイルパーク宮城",
}

const RANK_COLORS := {
	"S": Color("ff5a5a"),
	"A": Color("ff9a3c"),
	"B": Color("ffd23c"),
	"C": Color("8fdc5a"),
	"D": Color("5ac8dc"),
	"E": Color("7a9cff"),
	"F": Color("a0a0a0"),
	"G": Color("707070"),
}

## 現在の能力値ファイルの中身（schema_version 2）
var ratings: Dictionary = {}
var _players_by_team: Dictionary = {}
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


func team_color(team: String) -> Color:
	return TEAM_COLORS.get(team, DEFAULT_TEAM_COLOR)["primary"]


func team_text_color(team: String) -> Color:
	return TEAM_COLORS.get(team, DEFAULT_TEAM_COLOR)["text"]


func stadium_of(team: String) -> String:
	return STADIUM_NAMES.get(team, team)


## その球団が所属するリーグ（"C"/"P"）。能力値未読み込み時は空文字
func league_of(team: String) -> String:
	var players: Array = _players_by_team.get(team, [])
	return players[0]["league"] if not players.is_empty() else ""


func rank_color(rank: String) -> Color:
	return RANK_COLORS.get(rank, Color.WHITE)


func pos_index(pos: Variant) -> int:
	var i := POS_ORDER.find(pos)
	return i if i >= 0 else POS_ORDER.size()


func _index_players() -> void:
	_players_by_team.clear()
	for p: Dictionary in ratings.get("players", []):
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
