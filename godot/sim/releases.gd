class_name Releases
extends RefCounted
## 1オフ分の「戦力外・引退」（オフの段階 5。docs/SPEC.md のオフの流れ）。
##
## 段階に入ったとき（LeagueRoster.open_releases）に：
## - 史実の引退（来季の能力値ファイルにいない選手。LeagueRoster.apply_retirements で所属から外したもの）を retired_rows に並べる
## - CPU球団は支配下の上限（LeagueRoster.ROSTER_LIMIT＝70人）から、来季に入る新人（ドラフト＝史実の新人のうち支配下）と
##   外国人市場で獲る予定の人数を見込んで、あふれる人数を能力・年齢・年俸（LeagueRoster.keep_score）の低い順に戦力外にする
## - 自球団は画面で選ぶ（marked）。締める（resolve）ときに足りなければ残りを keep_score の低い順に自動で選ぶ
## 戦力外の選手は、来季の能力値ファイルにいれば（＝史実で来季もプレーする）市場（LeagueRoster.market、外国人市場と同じ
## 一覧）に入り、他球団が獲得できる。いなければ引退扱い。育成選手（LeagueRoster.is_ikusei）は支配下の人数に数えない。

var year: int                       ## このオフのシーズンの年（来季は year + 1）
var team: String                    ## 自球団
## 史実の引退 [{id, name, team, age, pitcher, foreign}]（全球団。自球団が先）
var retired_rows: Array[Dictionary] = []
## CPU球団の戦力外 [{id, name, team, market}]
var cpu_rows: Array[Dictionary] = []
## 締めたときの自球団の戦力外 [{id, name, team, market}]
var user_rows: Array[Dictionary] = []
## 自球団の候補（支配下・育成の全員）。keep_score の低い順（戦力外の候補が先）
var order: Array[String] = []
var scores := {}                    ## 選手ID → keep_score
var ikusei := {}                    ## 自球団の育成選手（支配下の人数に数えない）
var protected := {}                 ## 選手ID → 戦力外にできない理由（複数年契約・今オフに加入）
var marked := {}                    ## 自球団で戦力外に選んだ選手
var resolved := false


func _init(season_year: int, user_team: String) -> void:
	year = season_year
	team = user_team


## 戦力外に選べるか（だめなら理由の文）
func check_mark(id: String) -> String:
	if resolved:
		return "戦力外・引退は締めました"
	if id not in order:
		return "自球団の選手ではありません"
	if protected.has(id):
		return "%sのため戦力外にできません" % protected[id]
	return ""


## 戦力外の印を付ける／外す。だめなら理由の文
func toggle(id: String) -> String:
	if marked.has(id):
		if resolved:
			return "戦力外・引退は締めました"
		marked.erase(id)
		return ""
	var error := check_mark(id)
	if error.is_empty():
		marked[id] = true
	return error


## 選んだ戦力外のうち支配下の人数
func marked_registered() -> int:
	var n := 0
	for id: String in marked:
		if not ikusei.has(id):
			n += 1
	return n


## 来季の支配下の見込み（今の支配下 − 選んだ戦力外 ＋ 新人などの見込み）
func projected(league: LeagueRoster) -> int:
	return league.registered_count(team) - marked_registered() + league.incoming(team)


## あと何人戦力外にする必要があるか
func need(league: LeagueRoster) -> int:
	if resolved:
		return 0
	return maxi(0, projected(league) - LeagueRoster.ROSTER_LIMIT)


## 足りない人数を keep_score の低い順に選ぶ（おまかせ）。選んだ人数
func auto_fill(league: LeagueRoster) -> int:
	var added := 0
	for id in order:
		if need(league) <= 0:
			break
		if marked.has(id) or ikusei.has(id) or protected.has(id):
			continue
		marked[id] = true
		added += 1
	return added


## 締める：足りなければ自動で選び、選んだ選手を戦力外にする
func resolve(league: LeagueRoster) -> void:
	if resolved:
		return
	auto_fill(league)
	var ids: Array = marked.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return order.find(a) < order.find(b))
	for id: String in ids:
		if league.team_of.get(id, "") != team:
			continue
		user_rows.append(league.release_player(id))
	resolved = true
