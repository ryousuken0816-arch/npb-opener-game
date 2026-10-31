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
## 優勝・日本一の演出を出す（kind: "pennant"＝リーグ優勝 / "champion"＝日本一）。自動処理の途中は出さない
signal celebrate(kind: String, team_name: String, title: String)
## 速報を載せた（ハブの帯に出す）。自動処理の途中は出さない
signal news_posted(article: Dictionary)
## 新聞の号を出した（月ごとの新聞・日本シリーズ号など。ハブが次に開く）
signal issue_published(key: String)

enum Phase {
	SEASON,        ## レギュラーシーズン（日単位で進行）
	AWARDS,        ## シーズン終了・表彰
	ACTIVE_DRAFT,  ## 現役ドラフト（2022年オフ以降）
	FA_TRADE,      ## FA・トレード・ポスティング
	CONTRACT,      ## 契約更改
	RELEASE,       ## 戦力外・引退
	DRAFT,         ## ドラフト
	CAMP,          ## 春季キャンプ（翌年）
	## クライマックスシリーズ・日本シリーズ（公式戦と表彰の間。日単位で進行）。
	## セーブに段階の番号が入るので、途中に挟まず最後に足す（並びは next_phase() で決める）
	POSTSEASON,
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
	Phase.POSTSEASON: "ポストシーズン",
}

## 可変ボタンの文言（そのフェーズへ進むとき）
const PHASE_BUTTON := {
	Phase.SEASON: "開幕へ",
	Phase.POSTSEASON: "CS・日本シリーズへ",
	Phase.AWARDS: "表彰へ",
	Phase.ACTIVE_DRAFT: "現役ドラフトへ",
	Phase.FA_TRADE: "FA/トレードへ",
	Phase.CONTRACT: "契約更改へ",
	Phase.RELEASE: "戦力外・引退へ",
	Phase.DRAFT: "ドラフトへ",
	Phase.CAMP: "春季キャンプへ",
}

const START_YEAR := 2008
## デバッグ用の開始年の範囲（タイトル画面で選べる。どの年も generated/ratings と data/<年>/schedule.json がある。
## 2027年は史実が無く、日程は2026年の写し・能力は2026年シーズン後の引き継ぎ。docs/AUTORUN.md 作業17）
const DEBUG_FIRST_YEAR := 2008
const DEBUG_LAST_YEAR := 2027
## 日程データ（data/<年>/schedule.json）が無い年のシーズン期間（月日）
const DEFAULT_SEASON_START := "04-01"
const DEFAULT_SEASON_END := "10-31"
const ACTIVE_DRAFT_START_YEAR := 2022
## 早送りで1日進める間隔（秒）。将来はシステム設定の「早送り速度」で変える
const FAST_FORWARD_INTERVAL := 0.18
## 育成選手を支配下に登録できる最後の日（月-日。史実のルール）
const IKUSEI_DEADLINE := "07-31"
## CPU球団が育成から支配下に上げる時期（この月に替わったとき）と1回の人数
const CPU_IKUSEI_MONTHS := [5, 6, 7]
const CPU_IKUSEI_PER_MONTH := 1

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

## その年のポストシーズン（CS・日本シリーズ。ポストシーズンの段階に入ったときに作り、翌年の開幕まで残す）
var postseason: Postseason = null
## ポストシーズンの歴代（年の文字列 → Postseason.summary()）。日本一が決まったときに足す
var postseason_history := {}
## 今季の優勝争い（リーグ → {magic: 点灯した最初の値, clinched: 優勝決定の日}）。演出・ニュースを1回だけ出す
var pennant_race := {}
## 新聞・速報（年をまたいで残る。セーブにも入る）
var news: News = null
var _desk: NewsDesk = null
var _history: HistoryCompare = null
## 春季キャンプで「史実との比較」に使う、いま終わったオフのドラフト
var _last_draft: Draft = null

## 表彰の履歴（年の文字列 → Awards.compute() の結果）。シーズン終了・表彰の段階に入ったときに足す
var awards_history := {}
## ゲーム内の過去のシーズンの成績（年の文字列 → {batting, pitching, players, records, leagues}）。
## シーズン終了時に Season から写す（新人王の資格・記録室の通算成績に使う）
var stats_history := {}
## このゲームを始めた年（これより前の成績は史実の1軍成績を使う）
var first_year: int = START_YEAR
## 表彰をまだ画面で見ていない（シーズン終了・表彰の段階で、可変ボタンがまず表彰の画面を開く）
var awards_pending := false

## 早送りの目標日（この日の試合が終わるまで進める）。早送りしていなければ -1
var fast_forward_target: int = -1
## 所属が変わるたびに増える（一覧の作り直しの判定用）
var roster_version := 0
var _fast_forward_time := 0.0
## オフの編成（所属が変わるたびに作り直す。球団名 → SimTeam）
var _offseason_teams := {}
## オートセーブを次のフレームで書く（月替わり・段階の切り替わりで立てる。同じフレームで何度立っても1回）
var _autosave_pending := false
## skip_to_phase などの自動処理の途中（セーブしない）
var _busy := false


func new_game(team_name: String, start_year: int = START_YEAR) -> void:
	stop_fast_forward()
	_autosave_pending = false
	team = team_name
	year = start_year
	first_year = start_year
	_depth = null
	awards_pending = false
	awards_history = {}
	stats_history = {}
	postseason = null
	postseason_history = {}
	news = News.new()
	tactics = {"bunt": 0, "steal": 0, "relief": 0}
	phase = Phase.SEASON
	GameData.load_ratings(year, "pre")
	league = LeagueRoster.new()
	league.start(year, GameData.ratings, _opening_date(), team, randi() + 1)
	_sync_roster()
	_start_season()
	changed.emit()


func _process(delta: float) -> void:
	if _autosave_pending and not _busy:
		_autosave_pending = false
		SaveGame.autosave()
	if fast_forward_target < 0:
		return
	_fast_forward_time += delta
	if _fast_forward_time < FAST_FORWARD_INTERVAL:
		return
	_fast_forward_time = 0.0
	_advance_one_day()
	if not is_daily_phase() or day > fast_forward_target or postseason_done():
		fast_forward_target = -1
	changed.emit()


## 可変ボタンを押したときの処理。シーズン中はその月の残り日程を行って翌月1日へ（最終月ならシーズン終了へ）、
## オフは次のフェーズへ。
func advance() -> void:
	stop_fast_forward()
	if phase == Phase.SEASON:
		advance_through(_month_end_day(day), true)
		changed.emit()
		return
	if phase == Phase.POSTSEASON and not postseason_done():
		postseason_play_round()
		return
	if phase == Phase.FA_TRADE:
		fa_resolve()
		comp_resolve()
	if phase == Phase.CONTRACT:
		contract_resolve()
	if phase == Phase.RELEASE:
		release_resolve()
	if phase == Phase.DRAFT:
		draft_resolve()
	_enter(next_phase())


## デバッグ用：シーズン中ならその年の残り試合をすべてシミュレーションしてシーズン終了まで進め、
## オフを target の段階まで進める（途中の段階の自球団の選択は可変ボタンで進めたときと同じく自動で締める）。
## target がその年のオフに無い・もう過ぎている（現役ドラフトの2021年以前など）ときは春季キャンプの手前で止まる。
## target に着いたら true。将来ドラフトの段階ができても Phase.DRAFT を渡せば同じように直接飛べる
func skip_to_phase(target: Phase) -> bool:
	stop_fast_forward()
	if target == Phase.SEASON:
		return false
	_busy = true
	if phase == Phase.SEASON:
		advance_through(season_last_day())
	while phase != target and phase != Phase.SEASON:
		if phase == Phase.CAMP or (next_phase() == Phase.CAMP and target != Phase.CAMP):
			break
		advance()
	_busy = false
	changed.emit()
	return phase == target


## target_day（通し日数）の試合が終わるまで一気に進める。最終日を越えるとポストシーズンへ入り、
## stop_at_postseason でなければ CS・日本シリーズもすべて行ってシーズン終了・表彰まで進む
## （テスト・「すぐドラフトへ」用。ハブの「試合へ」はポストシーズンの入口で止まる）
func advance_through(target_day: int, stop_at_postseason := false) -> void:
	while phase == Phase.SEASON and day <= target_day:
		_advance_one_day()
	if phase == Phase.POSTSEASON and not stop_at_postseason:
		postseason_play_all()
		_enter(Phase.AWARDS)


## シーズン中・ポストシーズン中（日単位で進む段階）
func is_daily_phase() -> bool:
	return phase == Phase.SEASON or phase == Phase.POSTSEASON


## ポストシーズンの段階で、日本一が決まった
func postseason_done() -> bool:
	return phase == Phase.POSTSEASON and (postseason == null or postseason.is_finished())


## ポストシーズンの今の回（ファースト・ファイナル・日本シリーズ）を最後まで行う。
## 自球団が勝ち残っていなければ日本一が決まるまで行う
func postseason_play_round() -> void:
	if postseason == null:
		return
	stop_fast_forward()
	if not postseason.team_alive(team):
		postseason_play_all()
		return
	# 日本シリーズが引き分けで延びると予定の最終日が後ろへずれるので、毎日計算し直す
	var round_no := postseason.current_round()
	while not postseason_done() and postseason.current_round() == round_no \
			and day <= postseason.round_last_day(round_no):
		_advance_one_day()
	changed.emit()


## 日本一が決まるまで一気に行う
func postseason_play_all() -> void:
	stop_fast_forward()
	while phase == Phase.POSTSEASON and not postseason_done():
		_advance_one_day()
	changed.emit()


## target_day の試合が終わるまで1日ずつ早送りする（日程表から）。今日より前の日なら何もしない
func start_fast_forward(target_day: int) -> void:
	if not is_daily_phase() or target_day < day or postseason_done():
		return
	var last := postseason.last_day() if phase == Phase.POSTSEASON else season_last_day()
	fast_forward_target = mini(target_day, last)
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
	if is_daily_phase():
		return season.teams.get(team_name) if season != null else null
	if not _offseason_teams.has(team_name):
		var members := GameData.players_of(team_name)
		if members.is_empty():
			return null
		_offseason_teams[team_name] = SimTeam.new(team_name, GameData.league_of(team_name), members, year,
				GameData.load_debut_years(year))
		if league != null:
			_offseason_teams[team_name].set_ikusei(league.ikusei_of(team_name))
	return _offseason_teams[team_name]


## トレード交渉ができないときの理由（できるときは空）。シーズン中は7月31日まで、オフは FA・トレード・
## ポスティングの段階から春季キャンプまで（契約更改・戦力外・ドラフトは締めてから）。docs/SPEC.md「決定事項：トレード交渉の時期」
func trade_block_reason() -> String:
	if league == null:
		return "トレード交渉はゲームを始めてから行えます"
	match phase:
		Phase.SEASON:
			if season == null:
				return "この年の日程データが無いので交渉できません"
			if Season.date_of_day(day).substr(5) > Trade.DEADLINE:
				return "8月1日からシーズン終了までは交渉できません（移籍期限は7月31日）"
		Phase.POSTSEASON:
			return "8月1日からシーズン終了までは交渉できません（移籍期限は7月31日）"
		Phase.AWARDS, Phase.ACTIVE_DRAFT:
			return "オフのトレード交渉は「FA・トレード・ポスティング」の段階から行えます"
	if contract_open():
		return "契約更改を締めてから交渉できます"
	if release_open():
		return "戦力外を確定してから交渉できます"
	if draft_open():
		return "ドラフト会議を終えてから交渉できます"
	return ""


## トレードで交渉できない選手（選手ID → 理由）。FA宣言して締め切り前の選手
func trade_excluded() -> Dictionary:
	var result := {}
	var f := fa()
	if f != null and not f.resolved:
		for id: String in f.declared:
			result[id] = "FA宣言中です"
	return result


## 断られたときに同じ球団と交渉できない単位（シーズン中は日付、オフは段階）
func trade_day_key() -> String:
	return Season.date_of_day(day) if phase == Phase.SEASON else "%d-%d" % [year, phase]


## トレードの相手の見立て（Trade.evaluate）
func trade_estimate(partner: String, give: Array, get_ids: Array, money: int) -> Dictionary:
	return Trade.evaluate(league, year, partner, give, get_ids, money)


## トレードを申し込む。{ok, text}。成立したら所属を入れ替え、シーズン中はペナントの編成にもすぐ反映する
func trade_request(partner: String, give: Array, get_ids: Array, money: int) -> Dictionary:
	var error := trade_block_reason()
	if error.is_empty():
		error = Trade.check(league, partner, give, get_ids, money, trade_excluded())
	if error.is_empty() and league.trade_refused.get(partner, "") == trade_day_key():
		error = "%sには今日はもう断られました（%s）" % [GameData.short_name(partner),
			"明日以降にもう一度" if phase == Phase.SEASON else "次の段階でもう一度"]
	if not error.is_empty():
		return {"ok": false, "text": error}
	var est := trade_estimate(partner, give, get_ids, money)
	if randf() >= float(est["chance"]):
		league.trade_refused[partner] = trade_day_key()
		changed.emit()
		return {"ok": false, "refused": true, "text": "%sに断られました（成功率：%s）" % [GameData.short_name(partner),
			Trade.STAR_WORDS[est["stars"]]]}
	var date := Season.date_of_day(day) if phase == Phase.SEASON else ""
	var moves := Trade.execute(league, partner, give, get_ids, money, date)
	_sync_roster()
	if phase == Phase.SEASON and season != null:
		for mv in moves:
			season.transfer(GameData.player(mv["pid"]), mv["to"])
		_mark_ikusei(true)  # 移った育成選手の印を付け直す（1軍に入っていれば組み直す。作業19）
	changed.emit()
	var names: Array[String] = []
	for mv in moves:
		if mv["to"] == team:
			names.append(mv["name"])
	return {"ok": true, "text": "トレード成立！ %sから %s を獲得しました" % [GameData.short_name(partner),
		"・".join(names)]}


## 外国人市場（戦力外の選手を含む）の選手を自球団で獲得する（オフのみ）。失敗したら理由の文を返す。
## 戦力外・引退の段階からは支配下の上限（70人。来季の新人の見込みと、戦力外に選んだ選手を差し引いて数える）を守る
func sign_foreign(id: String) -> String:
	if phase == Phase.SEASON:
		return "シーズン中は獲得できません"
	var info: Dictionary = league.market_info.get(id, {})
	if info.get("released", "") == team:
		return "自球団が戦力外にした選手は獲得できません"
	if league.limit_active and user_room() <= 0:
		return "支配下登録が上限（%d人）です。戦力外で枠を空けてください" % LeagueRoster.ROSTER_LIMIT
	var error := league.sign_foreign(id, team)
	if error.is_empty():
		_sync_roster()
		changed.emit()
	return error


## このオフの FA・ポスティング（FA・トレード・ポスティングの段階のみ。それ以外は null）
func fa() -> FreeAgency:
	if phase != Phase.FA_TRADE or league == null:
		return null
	return league.fa


## FAの交渉が残っている（FA・トレード・ポスティングの段階で、まだ締め切っていない）
func fa_open() -> bool:
	var f := fa()
	return f != null and not f.resolved


## FA宣言した選手に自球団が条件を出す（自球団の選手なら引き留め）。だめなら理由の文
func fa_offer(id: String, amount: int, years: int) -> String:
	var f := fa()
	if f == null:
		return "FAの交渉はオフの「FA・トレード・ポスティング」で行います"
	var error := f.offer(id, amount, years)
	if error.is_empty():
		changed.emit()
	return error


func fa_cancel(id: String) -> void:
	var f := fa()
	if f != null:
		f.cancel_offer(id)
		changed.emit()


## メジャー移籍する自球団の選手を引き留める（1人1回）。{ok, chance, text}
func mlb_keep(id: String, amount: int, years: int) -> Dictionary:
	var f := fa()
	if f == null:
		return {"ok": false, "chance": 0.0, "text": "引き留めはオフの「FA・トレード・ポスティング」で行います"}
	var result := f.keep_mlb(league, id, amount, years)
	if result["ok"]:
		_sync_roster()
	changed.emit()
	return result


## FAの交渉を締め切り、移籍先を決める（可変ボタンで次へ進むときにも自動で行う）
func fa_resolve() -> void:
	var f := fa()
	if f == null or f.resolved:
		return
	f.resolve(league)
	# FA移籍の補償（作業18）：CPU球団どうしはここで決まり、人的補償の選手も移る
	league.compensation = FaCompensation.new()
	league.compensation.open(league, f)
	_sync_roster()
	changed.emit()


## このオフのFAの補償（FAを締め切ったあとの FA・トレード・ポスティングの段階のみ。それ以外は null）
func comp() -> FaCompensation:
	if phase != Phase.FA_TRADE or league == null:
		return null
	return league.compensation


## 自球団が決める補償が残っている（プロテクト・人的補償の選手か金銭か）
func comp_open() -> bool:
	var c := comp()
	return c != null and not c.resolved and not c.pending().is_empty()


## 自球団のプロテクトを決める（index は comp().cases の番号）。だめなら理由の文
func comp_protect(index: int, ids: Array) -> String:
	var c := comp()
	if c == null or index < 0 or index >= c.cases.size():
		return "補償はありません"
	return c.set_protect(league, c.cases[index], ids)


## 自球団のプロテクトを確定する（旧球団が人的補償の選手か金銭かを選ぶ）
func comp_confirm(index: int) -> void:
	var c := comp()
	if c == null or index < 0 or index >= c.cases.size():
		return
	c.confirm_protect(league, c.cases[index])
	_sync_roster()
	changed.emit()


## 自球団が旧球団のとき：人的補償の選手（kind=player）・金銭（money）・指名権（pick）を選ぶ。だめなら理由の文
func comp_choose(index: int, kind: String, id: String = "") -> String:
	var c := comp()
	if c == null or index < 0 or index >= c.cases.size():
		return "補償はありません"
	var error := c.choose(league, c.cases[index], kind, id)
	if error.is_empty():
		_sync_roster()
		changed.emit()
	return error


## 残りの補償をおまかせで決める（可変ボタンで次の段階へ進むときにも自動で行う）
func comp_resolve() -> void:
	var c := comp()
	if c == null or c.resolved:
		return
	c.resolve_all(league)
	_sync_roster()
	changed.emit()


## このオフの契約更改（契約更改の段階のみ。それ以外は null）
func contracts() -> ContractRenewal:
	if phase != Phase.CONTRACT or league == null:
		return null
	return league.contracts


## 契約更改の提示が残っている（契約更改の段階で、まだ締めていない）
func contract_open() -> bool:
	var c := contracts()
	return c != null and not c.resolved


## 自球団の選手の来季の年俸（提示額）を変える。だめなら理由の文
func contract_set(id: String, amount: int) -> String:
	var c := contracts()
	if c == null:
		return "契約更改はオフの「契約更改」の段階で行います"
	var error := c.set_amount(league, id, amount)
	if error.is_empty():
		changed.emit()
	return error


## 契約更改を締める（可変ボタンで次へ進むときにも自動で行う）
func contract_resolve() -> void:
	var c := contracts()
	if c == null or c.resolved:
		return
	c.resolved = true
	changed.emit()


## このオフの戦力外・引退（戦力外・引退の段階のみ。それ以外は null）
func releases() -> Releases:
	if phase != Phase.RELEASE or league == null:
		return null
	return league.releases


## 戦力外の選択が残っている（戦力外・引退の段階で、まだ締めていない）
func release_open() -> bool:
	var r := releases()
	return r != null and not r.resolved


## 自球団の選手の戦力外の印を付ける／外す。だめなら理由の文
func release_toggle(id: String) -> String:
	var r := releases()
	if r == null:
		return "戦力外はオフの「戦力外・引退」の段階で決めます"
	var error := r.toggle(id)
	if error.is_empty():
		changed.emit()
	return error


## 足りない人数をおまかせで選ぶ。選んだ人数
func release_auto() -> int:
	var r := releases()
	if r == null or r.resolved:
		return 0
	var n := r.auto_fill(league)
	changed.emit()
	return n


## 自球団があと何人戦力外にする必要があるか（段階の外は 0）
func release_need() -> int:
	var r := releases()
	return r.need(league) if r != null else 0


## 戦力外を締める（足りなければ自動で選ぶ。可変ボタンで次へ進むときにも自動で行う）
func release_resolve() -> void:
	var r := releases()
	if r == null or r.resolved:
		return
	r.resolve(league)
	_sync_roster()
	changed.emit()


## このオフのドラフト（ドラフトの段階のみ。それ以外は null）
func draft() -> Draft:
	if phase != Phase.DRAFT or league == null:
		return null
	return league.draft


## ドラフトが残っている（ドラフトの段階で、まだ終えていない）
func draft_open() -> bool:
	var d := draft()
	return d != null and not d.resolved


## ドラフトの画面で指名を進めたあとに呼ぶ：終わっていれば入団させる（結果を反映）
func draft_sync() -> void:
	var d := draft()
	if d == null:
		return
	# 自球団が指名したメジャー志望の選手の説得が残っていれば、入団の処理は説得のあと（作業26）
	if d.stage == Draft.Stage.DONE and not d.resolved and d.pending_talks().is_empty():
		league.apply_draft()
		_sync_roster()
	changed.emit()


## ドラフトを終える（残りはおまかせ。可変ボタンで次へ進むときにも自動で行う）
func draft_resolve() -> void:
	var d := draft()
	if d == null or d.resolved:
		return
	d.auto_complete()
	league.apply_draft()
	_sync_roster()
	changed.emit()


## ドラフトの2巡目の指名順（下位から）：交流戦で負け越したリーグの最下位から、セ・パ交互に
func draft_waiver_order() -> Array[String]:
	var first := _interleague_loser()
	var a := standings(first)
	var b := standings("P" if first == "C" else "C")
	a.reverse()
	b.reverse()
	var result: Array[String] = []
	for i in maxi(a.size(), b.size()):
		if i < a.size():
			result.append(a[i]["team"])
		if i < b.size():
			result.append(b[i]["team"])
	return result


## 交流戦で負け越したリーグ（"C"/"P"）。試合結果が無ければ年の偶奇で決める
func _interleague_loser() -> String:
	var wins := {"C": 0, "P": 0}
	if season != null:
		for g: Dictionary in season.games:
			if g.get("kind", "") != "interleague" or not g.has("result"):
				continue
			var r: Dictionary = g["result"]
			var hs := int(r.get("home_score", 0))
			var aws := int(r.get("away_score", 0))
			if hs == aws:
				continue
			var winner: String = g["home"] if hs > aws else g["away"]
			var lg := GameData.league_of(winner)
			if wins.has(lg):
				wins[lg] += 1
	if wins["C"] == wins["P"]:
		return "C" if year % 2 == 0 else "P"
	return "C" if wins["C"] < wins["P"] else "P"


## 自球団の支配下の空き（来季の新人の見込みと、戦力外に選んで締めていない選手を差し引く）
func user_room() -> int:
	if league == null:
		return 0
	var r := releases()
	var marked := r.marked_registered() if r != null and not r.resolved else 0
	return league.room(team) + marked


## 外国人市場が開いているか（FA・トレード・ポスティング〜春季キャンプ）
func market_open() -> bool:
	if phase in [Phase.SEASON, Phase.POSTSEASON, Phase.AWARDS] or league == null:
		return false
	return not league.market.is_empty()


## 自球団の采配方針を変える（今季の SimTeam にもすぐ反映）
func set_tactic(key: String, level: int) -> void:
	tactics[key] = clampi(level, SimTeam.TACTIC_MIN, SimTeam.TACTIC_MAX)
	var mine := my_team()
	if mine != null:
		mine.set_tactic(key, tactics[key])


# --- 育成選手の支配下登録（docs/AUTORUN.md 作業19） ----------------------------------------------

## 支配下に登録できない理由（春季キャンプ〜7月31日だけ登録できる）。登録できるなら空
func ikusei_promote_block() -> String:
	if league == null:
		return "支配下登録はできません"
	if phase == Phase.CAMP:
		return ""
	if phase == Phase.SEASON:
		if day <= Season.day_number("%d-%s" % [year, IKUSEI_DEADLINE]):
			return ""
		return "支配下登録は7月31日までです（来季の春季キャンプから再びできます）"
	return "支配下登録は春季キャンプから7月31日までです"


## 自球団の育成選手を支配下に登録する。だめなら理由
func promote_ikusei(id: String) -> String:
	var block := ikusei_promote_block()
	if not block.is_empty():
		return block
	if league.team_of.get(id, "") != team:
		return "自球団の選手ではありません"
	var date := Season.date_of_day(day) if phase == Phase.SEASON else "%d-02-01" % year
	var error := league.promote_ikusei(id, date)
	if error.is_empty():
		var mine := my_team()
		if mine != null and mine.by_id.has(id):
			mine.by_id[id].is_ikusei = false
		changed.emit()
	return error


## 選手が今の時点で育成か（選手詳細・一覧の表示用）
func is_ikusei(id: String) -> bool:
	return league != null and league.ikusei_now(id)


## 今季の各球団（SimTeam）に育成選手の印を付ける。rebuild なら1軍にいる育成選手を外して組み直す（開幕時）
func _mark_ikusei(rebuild: bool) -> void:
	if season == null or league == null:
		return
	for t: String in season.teams:
		season.teams[t].set_ikusei(league.ikusei_of(t), rebuild)


## CPU球団が育成選手を支配下に上げる（5〜7月の月替わり。LeagueRoster.cpu_promotion_candidates）
func _cpu_promote_ikusei() -> void:
	if season == null or league == null:
		return
	var date := Season.date_of_day(day)
	for t: String in season.teams:
		if t == team:
			continue
		for id: String in league.cpu_promotion_candidates(t, CPU_IKUSEI_PER_MONTH):
			if league.promote_ikusei(id, date).is_empty() and season.teams[t].by_id.has(id):
				season.teams[t].by_id[id].is_ikusei = false


## 采配画面で編成を変えられるか（シーズン中のみ。オフは前年の編成を見るだけ）
func can_edit_roster() -> bool:
	return is_daily_phase() and my_team() != null


func is_fast_forwarding() -> bool:
	return fast_forward_target >= 0


## 今日の試合を行い、翌日へ進む。月が替われば month_started、最終日を終えればシーズン終了へ
func _advance_one_day() -> void:
	if phase == Phase.POSTSEASON:
		_advance_postseason_day()
		return
	if season != null:
		season.sim_until_day(day + 1)
		_sync_record()
		desk().scan_day(Season.date_of_day(day))
		_check_pennant_race()
	# 今日までの史実のトレード（CPU球団どうし）
	_apply_trades(Season.date_of_day(day))
	var old_month := month
	day += 1
	if day > season_last_day():
		_publish(desk().monthly_issue(day, true))
		_enter(next_phase())
		return
	if month != old_month:
		_publish(desk().monthly_issue(day))
		if month in CPU_IKUSEI_MONTHS:
			_cpu_promote_ikusei()
		# 月替わりのイベント（故障・トレード、育成コマンド）はここに挟む（未実装）
		month_started.emit(month)
		_autosave_pending = true


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
			return Phase.POSTSEASON if season != null and not season.games.is_empty() else Phase.AWARDS
		Phase.POSTSEASON:
			return Phase.AWARDS
		Phase.AWARDS:
			return Phase.ACTIVE_DRAFT if year >= ACTIVE_DRAFT_START_YEAR else Phase.FA_TRADE
		Phase.CAMP:
			return Phase.SEASON
		_:
			return (phase + 1) as Phase


func button_text() -> String:
	if phase == Phase.SEASON or phase == Phase.POSTSEASON and not postseason_done():
		return "試合へ"
	if phase == Phase.AWARDS and awards_pending:
		return "表彰式"
	if fa_open():
		return "FA・移籍交渉"
	if comp_open():
		return "FAの補償"
	if contract_open():
		return "契約更改"
	if release_open():
		return "戦力外・引退"
	if draft_open():
		return "ドラフト会議"
	return PHASE_BUTTON[next_phase()]


func phase_name() -> String:
	return PHASE_NAMES[phase]


## ヘッダー表示用の日付（例: "2008年 5月3日" / "2008年 オフ"）
func date_text() -> String:
	match phase:
		Phase.SEASON, Phase.POSTSEASON:
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
		Phase.SEASON, Phase.POSTSEASON:
			return "%d月%d日" % [month, _day_of_month()]
		Phase.CAMP:
			return "2月"
		_:
			return "オフ"


func _day_of_month() -> int:
	return int(Season.date_of_day(day).substr(8, 2))


## ハブ画面上部のイベント名
func event_text() -> String:
	if phase == Phase.POSTSEASON and postseason != null:
		return postseason.stage_name(day)
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
## 戦力外・引退＝引退と戦力外（Releases。CPU球団はここで決め、自球団は画面で選ぶ）、ドラフト＝ドラフト以外の新加入
## （史実の球団へ）とドラフト会議（Draft。新人は指名した球団へ。画面で進めるか、次へ進むときにおまかせで終える）、春季キャンプ＝新しい年。
## CPU球団は外国人市場（戦力外の選手を含む）から少しずつ獲得する
func _enter(new_phase: Phase) -> void:
	phase = new_phase
	match new_phase:
		Phase.POSTSEASON:
			_start_postseason()
		Phase.AWARDS:
			# シーズン後の能力値に更新（当年までの成績で再計算したもの）
			GameData.load_ratings(year, "post")
			_archive_season()
			awards_pending = awards_history.has(str(year))
			desk().awards_article(year, open_off_issue(), "%d-11-01" % year)
			history().titles_decided(year, open_off_issue(), "%d-11-01" % year)
		Phase.FA_TRADE:
			var leaving := league.depart_mlb(year)
			_apply_trades("%d-12-31" % year)
			var next := GameData.peek_ratings(year + 1, "pre")
			if not next.is_empty():
				GameData.set_supplement(next)
				league.prepare_next_year(year, next, GameData.peek_ratings(year + 1, "post"))
				league.apply_returns()
			league.open_fa(year, leaving)
		Phase.CONTRACT:
			league.renew_contracts(year, season)
			league.cpu_market_round()
		Phase.RELEASE:
			league.apply_retirements()
			league.cpu_market_round()
			_sync_roster()
			league.open_releases(year)
		Phase.DRAFT:
			league.apply_newcomers()
			_sync_roster()
			league.draft = null
			if league.draft_available():
				league.open_draft(year, draft_waiver_order(), GameData.teams())
			league.cpu_market_round()
			league.cpu_release_round()
		Phase.CAMP:
			_last_draft = league.draft
			history().draft_decided(_last_draft, open_off_issue(), "%d-11-20" % year)
			year += 1
			GameData.load_ratings(year, "pre")
			league.begin_year(year, GameData.ratings)
			team = league.user_team
			league.cpu_market_round(-1)
			league.cpu_release_round(2)
			_apply_trades("%d-01-31" % year)
		Phase.SEASON:
			_start_season()
	_sync_roster()
	if new_phase == Phase.CAMP:
		# 年の終わり：新しい年の所属（史実の球団 hist_team と比べる）を当ててから「史実との比較」の号
		_publish(history().year_summary(year - 1, _last_draft))
		_last_draft = null
	_autosave_pending = true
	changed.emit()


## 所属が変わった・能力値ファイルを読み替えたとき：能力値データに所属を書き込み、オフの編成を作り直す
func _sync_roster() -> void:
	if league != null:
		GameData.set_kept_players(league.kept_fallbacks())
		GameData.set_extra_players(league.extra_players())
		GameData.apply_roster(league.team_of)
	_offseason_teams.clear()
	roster_version += 1


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
		_mark_ikusei(true)


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
	postseason = null
	pennant_race = {}
	if news != null:
		news.period_from = -1
	if league != null:
		var opening := Season.day_number(_opening_date())
		_apply_trades(Season.date_of_day(opening - 1))
		league.close_market()
		_sync_roster()
		league.trim_to_limit()
		_sync_roster()
	var schedule := GameData.load_schedule(year)
	if not schedule.is_empty() and GameData.has_ratings():
		var roster := {"players": GameData.rostered_players()} if league != null else GameData.ratings
		season = Season.new(year, roster, schedule, randi() + 1,
				GameData.load_debut_years(year))
		_mark_ikusei(true)
		var mine: SimTeam = season.teams.get(team)
		if mine != null:
			for key: String in tactics:
				mine.set_tactic(key, tactics[key])
	day = _season_first_day()
	_sync_record()


# --- ポストシーズン・優勝争い ---------------------------------------------------------------

## 公式戦の最終順位でポストシーズンの組み合わせと日程を作り、初戦の日へ
func _start_postseason() -> void:
	var order := {}
	for lg: String in ["C", "P"]:
		var names: Array = []
		for row: Dictionary in standings(lg):
			names.append(row["team"])
		order[lg] = names
	postseason = Postseason.new()
	postseason.setup(season, year, order, randi() + 1)
	day = postseason.first_day()


## ポストシーズンの今日の試合を行い、翌日へ。日本一が決まったら歴代に残して演出を出す（表彰へは可変ボタンで進む）
func _advance_postseason_day() -> void:
	if postseason == null or postseason.is_finished():
		return
	var date := Season.date_of_day(day)
	var decided := {}
	for s in postseason.series:
		decided[s["key"]] = not s["winner"].is_empty()
	postseason.play_day(day, season.teams)
	for s in postseason.series:
		if not decided[s["key"]] and not s["winner"].is_empty():
			desk().series_decided(s, date)
	day += 1
	if postseason.is_finished():
		var js_key := desk().postseason_issue(postseason, date)
		history().postseason_decided(postseason, js_key, date)
		_publish(js_key)
		postseason_history[str(year)] = postseason.summary()
		stop_fast_forward()
		_celebrate("champion", postseason.champion, "日本一")


## 今季の優勝争い：マジックの点灯と優勝の決定を1回ずつ記録し、自球団の優勝なら演出を出す
func _check_pennant_race() -> void:
	if season == null or season.next_index < season.games.size() / 2:
		return
	for lg: String in ["C", "P"]:
		var st: Dictionary = pennant_race.get_or_add(lg, {})
		if st.has("clinched"):
			continue
		var names: Array = []
		for row: Dictionary in standings(lg):
			names.append(row["team"])
		var race := Postseason.pennant_race(season, names, season.record_of)
		if race.is_empty():
			continue
		if int(race["magic"]) > 0 and not st.has("magic"):
			st["magic"] = race["magic"]
			st["magic_team"] = race["leader"]
			st["magic_date"] = Season.date_of_day(day)
			desk().magic_lit(lg, race["leader"], race["magic"], st["magic_date"])
		if race["clinched"]:
			st["clinched"] = Season.date_of_day(day)
			st["team"] = race["leader"]
			desk().pennant_clinched(lg, race["leader"], st["clinched"])
			history().pennant_decided(lg, race["leader"], st["clinched"])
			if race["leader"] == team:
				stop_fast_forward()
				_celebrate("pennant", team, "%s優勝" % GameData.LEAGUE_NAMES.get(lg, ""))


## 今のマジック（リーグ → {leader, magic, clinched}）。公式戦の後半だけ（それ以外は空）
func pennant_status(lg: String) -> Dictionary:
	if phase != Phase.SEASON or season == null or season.next_index < season.games.size() / 2:
		return {}
	var names: Array = []
	for row: Dictionary in standings(lg):
		names.append(row["team"])
	return Postseason.pennant_race(season, names, season.record_of)


# --- ニュース（作業25） ---------------------------------------------------------------------

## 史実との比較（作業24）
func history() -> HistoryCompare:
	if _history == null:
		_history = HistoryCompare.new(self)
	return _history


## ニュースの記者（NewsDesk）
func desk() -> NewsDesk:
	if _desk == null:
		_desk = NewsDesk.new(self)
	return _desk


## 記事を載せる（News.article で作ったもの）。issue_key の号に載せ、flash なら速報としてハブの帯にも出す。
## 自球団の話題（teams に自球団・players に自球団の選手）なら mine を付ける。載せた記事を返す。
## ほかの作業（アマのニュース・史実との分岐）もこれで載せる
func post_news(a: Dictionary, issue_key := "", flash := false) -> Dictionary:
	if news == null:
		news = News.new()
	a["flash"] = flash
	var mine: bool = team in a.get("teams", [])
	if not mine:
		for id: Variant in a.get("players", []):
			if GameData.player(str(id)).get("team", "") == team:
				mine = true
				break
	a["mine"] = mine
	news.post(a, issue_key)
	if flash and not _busy:
		news_posted.emit(a)
	return a


## その年のオフ号（表彰・史実との違いなど。オフの記事を載せる）のキー。無ければ作る
func open_off_issue() -> String:
	if news == null:
		news = News.new()
	var key := "%d-off" % year
	news.open_issue(key, "%d年 オフ号" % year, "%d-11-01" % year, year)
	return key


func _publish(issue_key: String) -> void:
	if not issue_key.is_empty() and not _busy:
		issue_published.emit(issue_key)


func _celebrate(kind: String, team_name: String, title: String) -> void:
	if not _busy and not team_name.is_empty():
		celebrate.emit(kind, team_name, title)


func _sync_record() -> void:
	var rec: Dictionary = season.record_of(team) if season != null else {}
	wins = rec.get("w", 0)
	losses = rec.get("l", 0)
	draws = rec.get("d", 0)


# --- 表彰・過去の成績 ---------------------------------------------------------------------

## シーズン終了時：今季の成績を履歴に写し、表彰を決める（同じ年を2回通っても上書きするだけ）
func _archive_season() -> void:
	if season == null or season.played_count() == 0:
		return
	var key := str(year)
	stats_history[key] = {
		"batting": season.batting.duplicate(true), "pitching": season.pitching.duplicate(true),
		"players": season.players.duplicate(true), "records": season.records.duplicate(true),
		"leagues": season.leagues.duplicate(),
		"feats": _season_feats(),
	}
	awards_history[key] = Awards.compute(season, GameData.player, is_rookie)


## 今年の表彰（まだ無ければ空）
func awards_of(y: int) -> Dictionary:
	return awards_history.get(str(y), {})


## 選手の受賞歴 [{year, name}]（ゲーム内の表彰のみ）
func player_awards(id: String) -> Array:
	return Awards.history_of(awards_history, id)


## 新人王の資格：外国人でない、入団から5年以内、前年までの1軍が60打席・30投球回以内
func is_rookie(id: String) -> bool:
	if league == null:
		return false
	var p := GameData.player(id)
	if p.is_empty() or RosterRules.is_foreign(p, year, GameData.load_debut_years(year).get(id)):
		return false
	var joined_year := int(league.joined.get(id, year))
	if year - joined_year >= Awards.ROOKIE_YEARS:
		return false
	var prior := prior_play(id)
	return prior["pa"] <= Awards.ROOKIE_MAX_PA and prior["outs"] <= Awards.ROOKIE_MAX_OUTS


## 今年より前の1軍の打席数・アウト数（ゲームを始めた年より前は史実、それ以降はゲーム内の成績）
func prior_play(id: String) -> Dictionary:
	var pa := 0
	var outs := 0
	var page := GameData.player_page(year, id)
	for row: Dictionary in page.get("batting", []):
		if int(row.get("年度", 0)) < first_year:
			pa += Records._n(row.get("打席"))
	for row: Dictionary in page.get("pitching", []):
		if int(row.get("年度", 0)) < first_year:
			outs += Records._n(row.get("outs"))
	for key: String in stats_history:
		if int(key) >= year:
			continue
		var h: Dictionary = stats_history[key]
		pa += int(h["batting"].get(id, {}).get("pa", 0))
		outs += int(h["pitching"].get(id, {}).get("outs", 0))
	return {"pa": pa, "outs": outs}


# --- 記録室 ---------------------------------------------------------------------------------

## 記録室で見られる年（古い順）：履歴にある年と、まだ履歴に入っていない今季（試合をしていれば）
func records_years() -> Array[int]:
	var result: Array[int] = []
	for key: String in stats_history:
		result.append(int(key))
	if season != null and season.played_count() > 0 and not stats_history.has(str(season.year)):
		result.append(season.year)
	result.sort()
	return result


## その年の成績 {batting, pitching, players, records, leagues, feats}（無ければ空）。今季は Season をそのまま
func season_stats(y: int) -> Dictionary:
	if stats_history.has(str(y)):
		return stats_history[str(y)]
	if season != null and season.year == y:
		return {"batting": season.batting, "pitching": season.pitching, "players": season.players,
			"records": season.records, "leagues": season.leagues, "feats": _season_feats()}
	return {}


## 今季のノーヒットノーラン・サイクル安打（Records.feats）
func _season_feats() -> Array:
	var team_of := func(id: String) -> String: return season.players.get(id, {}).get("team", "")
	return Records.feats(season.games, season.player_name, team_of)


var _career_base := {}
var _career_base_year := -1


## ゲームを始めた年より前の史実の1軍成績の通算 {batting: {id: 成績}, pitching: {id: 成績}}（data/<開始年>/players.json）
func career_base() -> Dictionary:
	if _career_base_year == first_year:
		return _career_base
	_career_base_year = first_year
	_career_base = {"batting": {}, "pitching": {}}
	var pages := GameData.all_player_pages(first_year)
	for id: String in pages:
		var page: Dictionary = pages[id]
		for kind: String in ["batting", "pitching"]:
			for row: Variant in page.get(kind, []):
				if not (row is Dictionary) or int(row.get("年度", 9999)) >= first_year:
					continue
				var line := Records.from_page_batting(row) if kind == "batting" else Records.from_page_pitching(row)
				Records.add_into(_career_base[kind].get_or_add(id, {}), line)
	return _career_base


var _depth: Depth = null


## デプスの計算（将来性のノイズはゲームごとに固定）
func depth_tool() -> Depth:
	if _depth == null:
		var data: Variant = GameData.read_generated("player_future.json")
		_depth = Depth.new(data if data is Dictionary else {}, "%d/%s" % [first_year, team],
			Draft.DIFFICULTY_NOISE[Draft.DIFFICULTY])
	return _depth


## 球団のデプス（Depth.team_depth）。今の所属・編成で
func depth_of(team_name: String) -> Dictionary:
	var members := GameData.players_of(team_name)
	var age_year := year if phase in [Phase.SEASON, Phase.CAMP, Phase.AWARDS] else year + 1
	return depth_tool().team_depth(members, sim_team_of(team_name), year,
		func(p: Dictionary) -> int: return FreeAgency.age_of(p, age_year))


# --- セーブ／ロード（SaveGame） -----------------------------------------------------------

## いまセーブできるか（早送り中・自動処理の途中はできない）
func can_save() -> bool:
	return save_block_reason().is_empty()


## セーブできない理由（できるなら空）
func save_block_reason() -> String:
	if team.is_empty() or league == null:
		return "ゲームを始めていません"
	if is_fast_forwarding():
		return "早送り中はセーブできません（早送りを止めてから）"
	if _busy:
		return "自動で進めている途中はセーブできません"
	return ""


## セーブの一覧に出す概要
func save_summary() -> Dictionary:
	var text := "%s　%s　%s" % [date_text(), GameData.short_name(team), record_text()]
	if phase == Phase.SEASON:
		var lg := GameData.league_of(team)
		for row: Dictionary in standings(lg):
			if row["team"] == team:
				text += "（%s %d位）" % [GameData.LEAGUE_NAMES.get(lg, ""), int(row["rank"])]
	else:
		text = "%s（%s）　%s　%s" % [date_text(), phase_name(), GameData.short_name(team), record_text()]
	return {"year": year, "date": date_text(), "phase": phase, "phase_name": phase_name(), "team": team,
		"wins": wins, "losses": losses, "draws": draws, "text": text}


## ゲームの状態（年・日付・段階・自球団・成績・方針、所属（LeagueRoster）、ペナント（Season））
func to_save() -> Dictionary:
	return {
		"year": year, "day": day, "phase": phase, "team": team, "tactics": tactics,
		"wins": wins, "losses": losses, "draws": draws,
		"first_year": first_year, "awards_history": awards_history, "stats_history": stats_history,
		"awards_pending": awards_pending,
		"postseason": postseason.to_save() if postseason != null else null,
		"postseason_history": postseason_history, "pennant_race": pennant_race,
		"news": news.to_save() if news != null else null,
		"league": league.to_save() if league != null else null,
		"season": season.to_save() if season != null else null,
	}


## to_save() の中身で再開する（d は SaveUtil.ints() で整数を戻したもの）。能力値ファイルはその年・段階のものを
## 読み直し（シーズン中・春季キャンプは開幕前、オフはシーズン後）、オフの途中なら来季のファイルも読んでから所属を当てる
func load_state(d: Dictionary) -> void:
	stop_fast_forward()
	_autosave_pending = false
	_busy = false
	year = int(d["year"])
	day = int(d.get("day", 0))
	phase = int(d.get("phase", Phase.SEASON)) as Phase
	team = str(d["team"])
	first_year = int(d.get("first_year", year))
	_depth = null
	awards_pending = bool(d.get("awards_pending", false))
	awards_history = d.get("awards_history", {})
	stats_history = d.get("stats_history", {})
	postseason_history = d.get("postseason_history", {})
	pennant_race = d.get("pennant_race", {})
	postseason = Postseason.from_save(d["postseason"]) if d.get("postseason") is Dictionary else null
	news = News.from_save(d["news"]) if d.get("news") is Dictionary else News.new()
	_desk = null
	_history = null
	tactics = {"bunt": 0, "steal": 0, "relief": 0}
	for key: String in d.get("tactics", {}):
		tactics[key] = int(d["tactics"][key])
	GameData.load_ratings(year, "pre" if phase in [Phase.SEASON, Phase.CAMP, Phase.POSTSEASON] else "post")
	GameData.set_kept_players({})
	GameData.set_extra_players({})
	var next := {}
	if phase in [Phase.FA_TRADE, Phase.CONTRACT, Phase.RELEASE, Phase.DRAFT]:
		next = GameData.peek_ratings(year + 1, "pre")
	GameData.set_supplement(next)
	league = LeagueRoster.new()
	league.from_save(d["league"])
	league.restore_plan()
	_sync_roster()
	season = null
	if d.get("season") is Dictionary:
		var sd: Dictionary = d["season"]
		season = Season.from_save(sd, GameData.load_debut_years(int(sd["year"])), GameData.player)
		_mark_ikusei(false)
	wins = int(d.get("wins", 0))
	losses = int(d.get("losses", 0))
	draws = int(d.get("draws", 0))
	changed.emit()
