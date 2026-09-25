# gdlint: disable=max-public-methods
extends Node
## ゲーム進行状態（年・日付・フェーズ・自球団）とその年のペナント（Season）。
##
## シーズンは日単位で進む（`day` は「今日」＝まだ試合をしていない日の通し日数）。
## - 日程表の「1日進める」「1週間進める」「この日まで早送り」は start_fast_forward() で、
##   _process() が一定間隔で1日ずつ進める（途中で stop_fast_forward() で止められる）
## - ハブの可変ボタン「試合へ」は advance() で、その月の残り日程をまとめて行い翌月1日へ進む（近道）
## - 月が替わると month_started を出す。docs/SPEC.md の「月ごとの粒度」（故障・トレードイベント、
##   育成コマンド）はこのタイミングで挟む
## - 最終日を終えるとシーズン終了（表彰）へ進む。オフはフェーズ単位で advance() する

signal changed
## 月が替わった（月替わりのイベントを挟むタイミング）
signal month_started(new_month: int)

enum Phase {
	SEASON,        ## レギュラーシーズン（日単位で進行）
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
## 日程データ（data/<年>/schedule.json）が無い年のシーズン期間（月日）
const DEFAULT_SEASON_START := "04-01"
const DEFAULT_SEASON_END := "10-31"
const ACTIVE_DRAFT_START_YEAR := 2022
## 早送りで1日進める間隔（秒）。将来はシステム設定の「早送り速度」で変える
const FAST_FORWARD_INTERVAL := 0.18

var year: int = START_YEAR
## 今日（まだ試合をしていない日）の通し日数（Season.day_number）。シーズン中のみ意味を持つ
var day: int = 0
## 今日の月
var month: int:
	get:
		return Season.month_of(day)
var phase: Phase = Phase.SEASON
var team: String = ""
## その年のペナント（日程・試合結果・個人成績）。日程データが無い年は null
var season: Season = null

# 自球団の成績（season の集計を写したもの）
var wins: int = 0
var losses: int = 0
var draws: int = 0

## 自球団の采配方針（SimTeam.tactics と同じ形。年をまたいでも引き継ぐ）
var tactics := {"bunt": 0, "steal": 0, "relief": 0}

## 早送りの目標日（この日の試合が終わるまで進める）。早送りしていなければ -1
var fast_forward_target: int = -1
var _fast_forward_time := 0.0


func new_game(team_name: String, start_year: int = START_YEAR) -> void:
	stop_fast_forward()
	team = team_name
	year = start_year
	tactics = {"bunt": 0, "steal": 0, "relief": 0}
	phase = Phase.SEASON
	GameData.load_ratings(year, "pre")
	_start_season()
	changed.emit()


func _process(delta: float) -> void:
	if fast_forward_target < 0:
		return
	_fast_forward_time += delta
	if _fast_forward_time < FAST_FORWARD_INTERVAL:
		return
	_fast_forward_time = 0.0
	_advance_one_day()
	if phase != Phase.SEASON or day > fast_forward_target:
		fast_forward_target = -1
	changed.emit()


## 可変ボタンを押したときの処理。シーズン中はその月の残り日程を行って翌月1日へ（最終月ならシーズン終了へ）、
## オフは次のフェーズへ。
func advance() -> void:
	stop_fast_forward()
	if phase == Phase.SEASON:
		advance_through(_month_end_day(day))
		changed.emit()
		return
	_enter(next_phase())


## target_day（通し日数）の試合が終わるまで一気に進める（最終日を越えるとシーズン終了へ）
func advance_through(target_day: int) -> void:
	while phase == Phase.SEASON and day <= target_day:
		_advance_one_day()


## target_day の試合が終わるまで1日ずつ早送りする（日程表から）。今日より前の日なら何もしない
func start_fast_forward(target_day: int) -> void:
	if phase != Phase.SEASON or target_day < day:
		return
	fast_forward_target = mini(target_day, season_last_day())
	# 最初の1日はすぐに進める
	_fast_forward_time = FAST_FORWARD_INTERVAL
	changed.emit()


func stop_fast_forward() -> void:
	if fast_forward_target < 0:
		return
	fast_forward_target = -1
	changed.emit()


## 自球団の編成（その年のペナントの SimTeam）。日程データが無い年は null
func my_team() -> SimTeam:
	return season.teams.get(team) if season != null else null


## 自球団の采配方針を変える（今季の SimTeam にもすぐ反映）
func set_tactic(key: String, level: int) -> void:
	tactics[key] = clampi(level, SimTeam.TACTIC_MIN, SimTeam.TACTIC_MAX)
	var mine := my_team()
	if mine != null:
		mine.set_tactic(key, tactics[key])


## 采配画面で編成を変えられるか（シーズン中のみ。オフは前年の編成を見るだけ）
func can_edit_roster() -> bool:
	return phase == Phase.SEASON and my_team() != null


func is_fast_forwarding() -> bool:
	return fast_forward_target >= 0


## 今日の試合を行い、翌日へ進む。月が替われば month_started、最終日を終えればシーズン終了へ
func _advance_one_day() -> void:
	if season != null:
		season.sim_until_day(day + 1)
		_sync_record()
	var old_month := month
	day += 1
	if day > season_last_day():
		_enter(next_phase())
		return
	if month != old_month:
		# 月替わりのイベント（故障・トレード、育成コマンド）はここに挟む（未実装）
		month_started.emit(month)


## シーズンの初日（開幕日）・最終日の通し日数。日程データが無い年は既定の期間
func _season_first_day() -> int:
	if season != null and not season.games.is_empty():
		return season.first_day()
	return Season.day_number("%d-%s" % [year, DEFAULT_SEASON_START])


func season_last_day() -> int:
	if season != null and not season.games.is_empty():
		return season.last_day()
	return Season.day_number("%d-%s" % [year, DEFAULT_SEASON_END])


## シーズンの月（開幕日の月〜最終日の月。2008年なら3〜10月）
func season_months() -> Array[int]:
	var result: Array[int] = []
	for m in range(Season.month_of(_season_first_day()), Season.month_of(season_last_day()) + 1):
		result.append(m)
	return result


## some_day を含む月の最終日（シーズン最終日を越えない）
func _month_end_day(some_day: int) -> int:
	var date := Season.date_of_day(some_day)
	var y := int(date.substr(0, 4))
	var m := int(date.substr(5, 2))
	var first_of_next := "%04d-%02d-01" % [y + (1 if m == 12 else 0), 1 if m == 12 else m + 1]
	return mini(Season.day_number(first_of_next) - 1, season_last_day())


## 今月の残り日程（今日以降）で行う試合の数（全球団）
func games_left_in_month() -> int:
	if season == null:
		return 0
	var last := _month_end_day(day)
	var n := 0
	for i in range(season.next_index, season.games.size()):
		var g: Dictionary = season.games[i]
		if g["day"] > last:
			break
		if g["day"] >= day and g["status"] == "played":
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


## ヘッダー表示用の日付（例: "2008年 5月3日" / "2008年 オフ"）
func date_text() -> String:
	match phase:
		Phase.SEASON:
			return "%d年 %d月%d日" % [year, month, _day_of_month()]
		Phase.CAMP:
			return "%d年 2月" % year
		_:
			return "%d年 オフ" % year


## ハブ画面の日付表示: 年
func year_text() -> String:
	return str(year)


## ハブ画面の日付表示: 月日（オフは「オフ」）
func month_text() -> String:
	match phase:
		Phase.SEASON:
			return "%d月%d日" % [month, _day_of_month()]
		Phase.CAMP:
			return "2月"
		_:
			return "オフ"


func _day_of_month() -> int:
	return int(Season.date_of_day(day).substr(8, 2))


## ハブ画面上部のイベント名
func event_text() -> String:
	if phase != Phase.SEASON:
		return phase_name()
	if day == _season_first_day():
		return "開幕戦"
	if month == season_months()[-1]:
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
		season = Season.new(year, GameData.ratings, schedule, randi() + 1,
				GameData.load_debut_years(year))
		var mine: SimTeam = season.teams.get(team)
		if mine != null:
			for key: String in tactics:
				mine.set_tactic(key, tactics[key])
	day = _season_first_day()
	_sync_record()


func _sync_record() -> void:
	var rec: Dictionary = season.record_of(team) if season != null else {}
	wins = rec.get("w", 0)
	losses = rec.get("l", 0)
	draws = rec.get("d", 0)
