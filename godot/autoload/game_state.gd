extends Node
## ゲーム進行状態（年・月・フェーズ・自球団）。
## ハブ画面の可変ボタンは advance() を呼び、button_text() の文言を表示する。

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
const SEASON_MONTHS := [4, 5, 6, 7, 8, 9, 10]
const ACTIVE_DRAFT_START_YEAR := 2022

var year: int = START_YEAR
var month: int = SEASON_MONTHS[0]
var phase: Phase = Phase.SEASON
var team: String = ""

# 自球団の成績（試合シミュレーション実装までは 0 のまま）
var wins: int = 0
var losses: int = 0
var draws: int = 0


func new_game(team_name: String, start_year: int = START_YEAR) -> void:
	team = team_name
	year = start_year
	month = SEASON_MONTHS[0]
	phase = Phase.SEASON
	wins = 0
	losses = 0
	draws = 0
	GameData.load_ratings(year, "pre")
	changed.emit()


## 可変ボタンを押したときの処理。シーズン中は1か月進め、オフは次のフェーズへ。
func advance() -> void:
	if phase == Phase.SEASON:
		# TODO: その月の全試合をシミュレーションする
		var i := SEASON_MONTHS.find(month)
		if i + 1 < SEASON_MONTHS.size():
			month = SEASON_MONTHS[i + 1]
			changed.emit()
			return
	_enter(next_phase())


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
			month = SEASON_MONTHS[0]
			wins = 0
			losses = 0
			draws = 0
	phase = new_phase
	changed.emit()
