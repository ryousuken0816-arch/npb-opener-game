extends Node
## ゲーム進行状態（年・月・フェーズ・自球団）とその年のペナント（Season）。
## ハブ画面の可変ボタンは advance() を呼び、button_text() の文言を表示する。
## シーズン中は「試合へ」でその月の残り試合（史実の日程）をすべてシミュレーションし、次の月へ進む。

signal changed

enum Phase {
	SEASON,        ## レギュラーシーズン（月単位で進行）
	AWARDS,        ## シーズン終了・表彰
	ACTIVE_DRAFT,  ## 現役ドラフト（2022年オフ以降）
	FA_TRADE,      ## FA・トレード・ポスティング
	CONTRACT,      ## 契約更改
	RELEASE,       ## 戦力外・引退
	DRAFT,         ## ドラフト
	CAMP,          ## 春季キャンプ（翌年）
}

const PHASE_NAMES := {
	Phase.SEASON: "レギュラーシーズン",
	Phase.AWARDS: "シーズン終了・表彰",
	Phase.ACTIVE_DRAFT: "現役ドラフト",
	Phase.FA_TRADE: "FA・トレード・ポスティング",
	Phase.CONTRACT: "契約更改",
	Phase.RELEASE: "戦力外・引退",
	Phase.DRAFT: "ドラフト",
	Phase.CAMP: "春季キャンプ",
}

## 可変ボタンの文言（そのフェーズへ進むとき）
const PHASE_BUTTON := {
	Phase.SEASON: "開幕へ",
	Phase.ACTIVE_DRAFT: "現役ドラフトへ",
	Phase.FA_TRADE: "FA/トレードへ",
	Phase.CONTRACT: "契約更改へ",
	Phase.RELEASE: "戦力外・引退へ",
	Phase.DRAFT: "ドラフトへ",
	Phase.CAMP: "春季キャンプへ",
}

const START_YEAR := 2008
## 日程データ（data/<年>/schedule.json）が無い年に使う月の並び
const DEFAULT_SEASON_MONTHS: Array[int] = [4, 5, 6, 7, 8, 9, 10]
const ACTIVE_DRAFT_START_YEAR := 2022

var year: int = START_YEAR
var month: int = DEFAULT_SEASON_MONTHS[0]
var phase: Phase = Phase.SEASON
var team: String = ""
## その年のペナント（日程・試合結果・個人成績）。日程データが無い年は null
var season: Season = null

# 自球団の成績（season の集計を写したもの）
var wins: int = 0
var losses: int = 0
var draws: int = 0


func new_game(team_name: String, start_year: int = START_YEAR) -> void:
	team = team_name
	year = start_year
	phase = Phase.SEASON
	GameData.load_ratings(year, "pre")
	_start_season()
	changed.emit()


## 可変ボタンを押したときの処理。シーズン中はその月の試合を行って次の月へ、オフは次のフェーズへ。
func advance() -> void:
	if phase == Phase.SEASON:
		if season != null:
			season.sim_month(month)
			_sync_record()
		var months := season_months()
		var i := months.find(month)
		if i + 1 < months.size():
			month = months[i + 1]
			changed.emit()
			return
	_enter(next_phase())


## シーズンの月（日程データがあれば試合のある月。2008年なら3〜10月）
func season_months() -> Array[int]:
	if season != null and not season.games.is_empty():
		return season.months()
	return DEFAULT_SEASON_MONTHS


## その月にまだ行っていない試合の数（全球団）
func games_left_in_month() -> int:
	if season == null:
		return 0
	var n := 0
	for i in range(season.next_index, season.games.size()):
		var g: Dictionary = season.games[i]
		if int(g["date"].substr(5, 2)) == month and g["status"] == "played":
			n += 1
	return n


func next_phase() -> Phase:
	match phase:
		Phase.SEASON:
			return Phase.AWARDS
		Phase.AWARDS:
			return Phase.ACTIVE_DRAFT if year >= ACTIVE_DRAFT_START_YEAR else Phase.FA_TRADE
		Phase.CAMP:
			return Phase.SEASON
		_:
			return (phase + 1) as Phase


func button_text() -> String:
	if phase == Phase.SEASON:
		return "試合へ"
	return PHASE_BUTTON[next_phase()]


func phase_name() -> String:
	return PHASE_NAMES[phase]


## ヘッダー表示用の日付（例: "2008年 5月" / "2008年 オフ"）
func date_text() -> String:
	match phase:
		Phase.SEASON:
			return "%d年 %d月" % [year, month]
		Phase.CAMP:
			return "%d年 2月" % year
		_:
			return "%d年 オフ" % year


## ハブ画面の日付表示: 年
func year_text() -> String:
	return str(year)


## ハブ画面の日付表示: 月（オフは「オフ」）
func month_text() -> String:
	match phase:
		Phase.SEASON:
			return "%d月" % month
		Phase.CAMP:
			return "2月"
		_:
			return "オフ"


## ハブ画面上部のイベント名
func event_text() -> String:
	if phase != Phase.SEASON:
		return phase_name()
	var months := season_months()
	if month == months[0] and games_played() == 0:
		return "開幕戦"
	if month == months[-1]:
		return "シーズン終盤"
	return "ペナントレース"


func games_played() -> int:
	return wins + losses + draws


## リーグの順位表。各行は {team, wins, losses, draws, runs, runs_allowed, rank, games_behind}。
func standings(league: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for t in GameData.teams(league):
		var rec: Dictionary = season.record_of(t) if season != null else {}
		rows.append({
			"team": t,
			"wins": rec.get("w", 0),
			"losses": rec.get("l", 0),
			"draws": rec.get("d", 0),
			"runs": rec.get("rs", 0),
			"runs_allowed": rec.get("ra", 0),
		})
	# 同率は GameData.teams() の表示順を保つ（sort_custom は安定ソートではない）
	for i in rows.size():
		rows[i]["order"] = i
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := win_pct(a)
		var pb := win_pct(b)
		return pa > pb if pa != pb else a["order"] < b["order"])
	for i in rows.size():
		var row := rows[i]
		var top := rows[0]
		row["games_behind"] = ((top["wins"] - top["losses"]) - (row["wins"] - row["losses"])) / 2.0
		var tied := i > 0 and win_pct(row) == win_pct(rows[i - 1])
		row["rank"] = rows[i - 1]["rank"] if tied else i + 1
	return rows


## 勝率（引き分けを除く）。試合がなければ 0
static func win_pct(row: Dictionary) -> float:
	var decided: int = row["wins"] + row["losses"]
	return float(row["wins"]) / decided if decided > 0 else 0.0


func record_text() -> String:
	return "%d勝 %d敗 %d分" % [wins, losses, draws]


func _enter(new_phase: Phase) -> void:
	match new_phase:
		Phase.AWARDS:
			# シーズン後の能力値に更新（当年までの成績で再計算したもの）
			GameData.load_ratings(year, "post")
		Phase.CAMP:
			year += 1
			GameData.load_ratings(year, "pre")
		Phase.SEASON:
			_start_season()
	phase = new_phase
	changed.emit()


## その年の日程を読み込み、開幕前の状態にする（能力値は開幕時点の pre を使う）
func _start_season() -> void:
	var schedule := GameData.load_schedule(year)
	season = null
	if not schedule.is_empty() and GameData.has_ratings():
		season = Season.new(year, GameData.ratings, schedule, randi() + 1)
	month = season_months()[0]
	_sync_record()


func _sync_record() -> void:
	var rec: Dictionary = season.record_of(team) if season != null else {}
	wins = rec.get("w", 0)
	losses = rec.get("l", 0)
	draws = rec.get("d", 0)
