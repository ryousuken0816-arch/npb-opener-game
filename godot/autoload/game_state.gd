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

## 所属・年俸・年越しの史実の出来事（誰がどの球団にいるか。年が変わっても引き継ぐ）
var league: LeagueRoster = null

## 自球団の采配方針（SimTeam.tactics と同じ形。年をまたいでも引き継ぐ）
var tactics := {"bunt": 0, "steal": 0, "relief": 0}

## 早送りの目標日（この日の試合が終わるまで進める）。早送りしていなければ -1
var fast_forward_target: int = -1
var _fast_forward_time := 0.0
## オフの編成（所属が変わるたびに作り直す。球団名 → SimTeam）
var _offseason_teams := {}


func new_game(team_name: String, start_year: int = START_YEAR) -> void:
	stop_fast_forward()
	team = team_name
	year = start_year
	tactics = {"bunt": 0, "steal": 0, "relief": 0}
	phase = Phase.SEASON
	GameData.load_ratings(year, "pre")
	league = LeagueRoster.new()
	league.start(year, GameData.ratings, _opening_date(), team, randi() + 1)
	_sync_roster()
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


## 自球団の編成（シーズン中はその年のペナントの SimTeam、オフは今の所属で自動編成したもの）。
## シーズン中で日程データが無い年は null
func my_team() -> SimTeam:
	return sim_team_of(team)


## 球団の編成（my_team() と同じ。オフは所属が変わるたびに作り直す）
func sim_team_of(team_name: String) -> SimTeam:
	if phase == Phase.SEASON:
		return season.teams.get(team_name) if season != null else null
	if not _offseason_teams.has(team_name):
		var members := GameData.players_of(team_name)
		if members.is_empty():
			return null
		_offseason_teams[team_name] = SimTeam.new(team_name, GameData.league_of(team_name), members, year,
				GameData.load_debut_years(year))
	return _offseason_teams[team_name]


## 外国人市場の選手を自球団で獲得する（オフのみ）。失敗したら理由の文を返す
func sign_foreign(id: String) -> String:
	if phase == Phase.SEASON:
		return "シーズン中は獲得できません"
	var error := league.sign_foreign(id, team)
	if error.is_empty():
		_sync_roster()
		changed.emit()
	return error


## 外国人市場が開いているか（FA・トレード・ポスティング〜春季キャンプ）
func market_open() -> bool:
	return phase != Phase.SEASON and phase != Phase.AWARDS and league != null and not league.market.is_empty()


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
	# 今日までの史実のトレード（CPU球団どうし）
	_apply_trades(Season.date_of_day(day))
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


## フェーズに入ったときの処理。年越しの史実の出来事（LeagueRoster）はここで起こす：
## FA・トレード・ポスティング＝メジャー移籍・年内のトレード・来季の準備（復帰・外国人市場）、契約更改＝年俸、
## 戦力外・引退＝引退、ドラフト＝新人（史実の球団へ）、春季キャンプ＝新しい年。CPU球団は外国人市場から少しずつ獲得する
func _enter(new_phase: Phase) -> void:
	phase = new_phase
	match new_phase:
		Phase.AWARDS:
			# シーズン後の能力値に更新（当年までの成績で再計算したもの）
			GameData.load_ratings(year, "post")
		Phase.FA_TRADE:
			league.depart_mlb(year)
			_apply_trades("%d-12-31" % year)
			var next := GameData.peek_ratings(year + 1, "pre")
			if not next.is_empty():
				GameData.set_supplement(next)
				league.prepare_next_year(year, next)
				league.apply_returns()
		Phase.CONTRACT:
			league.renew_contracts(year, season)
			league.cpu_market_round()
		Phase.RELEASE:
			league.apply_retirements()
			league.cpu_market_round()
		Phase.DRAFT:
			league.apply_newcomers()
			league.cpu_market_round()
		Phase.CAMP:
			year += 1
			GameData.load_ratings(year, "pre")
			league.begin_year(year, GameData.ratings)
			team = league.user_team
			league.cpu_market_round(-1)
			_apply_trades("%d-01-31" % year)
		Phase.SEASON:
			_start_season()
	_sync_roster()
	changed.emit()


## 所属が変わった・能力値ファイルを読み替えたとき：能力値データに所属を書き込み、オフの編成を作り直す
func _sync_roster() -> void:
	if league != null:
		GameData.apply_roster(league.team_of)
	_offseason_teams.clear()


## date までの史実のトレードを起こす（シーズン中はペナントの編成にもすぐ反映）
func _apply_trades(date: String) -> void:
	if league == null:
		return
	var moves := league.apply_trades_until(date)
	if moves.is_empty():
		return
	_sync_roster()
	if phase == Phase.SEASON and season != null:
		for mv in moves:
			season.transfer(GameData.player(mv["pid"]), mv["to"])


## 開幕日（"YYYY-MM-DD"）。日程データが無い年は既定の開始日
func _opening_date() -> String:
	var first := ""
	for g: Dictionary in GameData.load_schedule(year):
		if first.is_empty() or g["date"] < first:
			first = g["date"]
	return first if not first.is_empty() else "%d-%s" % [year, DEFAULT_SEASON_START]


## その年の日程を読み込み、開幕前の状態にする（能力値は開幕時点の pre を使う）。
## 開幕前日までの史実のトレードを起こし、外国人市場を閉じてから、今の所属で各球団を編成する
func _start_season() -> void:
	season = null
	if league != null:
		var opening := Season.day_number(_opening_date())
		_apply_trades(Season.date_of_day(opening - 1))
		league.close_market()
		_sync_roster()
	var schedule := GameData.load_schedule(year)
	if not schedule.is_empty() and GameData.has_ratings():
		var roster := {"players": GameData.rostered_players()} if league != null else GameData.ratings
		season = Season.new(year, roster, schedule, randi() + 1,
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
