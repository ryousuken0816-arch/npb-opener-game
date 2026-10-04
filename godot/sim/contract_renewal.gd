class_name ContractRenewal
extends RefCounted
## 1オフ分の契約更改（オフの「契約更改」の段階。docs/SPEC.md のオフの流れ 4）。
##
## 段階に入ったとき（LeagueRoster.renew_contracts）に全球団の全選手の来季の年俸を今季のゲーム内成績・能力値・
## 在籍年数から査定し（Salary.renew）、すぐ来季の額として反映する。CPU球団はそのまま決まり。
## 自球団の選手は査定額を提示額の初期値として rows に持ち、締めるまで Salary.renew_limits の範囲で調整できる
## （調整した額もすぐ LeagueRoster.salary に入る）。保留（交渉決裂）は無し。
## FAなどで決まった複数年契約中の選手・このオフに加わった選手は据え置き（fixed に理由）。
##
## 予算上限（資金力の差）は球団ごとの定数 BUDGET（万円）。史実の傾向（巨人・ソフトバンク・阪神が高め、
## 広島・ヤクルトが低め）で、2008年開幕の年俸総額より4〜10億円ほど上に置いた。FAの提示では、自球団は提示上限が
## 予算の残りまで（FreeAgency.bid_range）、CPU球団は予算を超える入札をしない（FreeAgency._cpu_bids）。
## 契約更改そのものは予算で抑えない（年俸は成績どおり。超えた球団は画面で赤く表示）

const BUDGET := {
	"読売ジャイアンツ": 420000,
	"福岡ソフトバンクホークス": 420000,
	"阪神タイガース": 340000,
	"中日ドラゴンズ": 320000,
	"千葉ロッテマリーンズ": 280000,
	"オリックス・バファローズ": 280000,
	"埼玉西武ライオンズ": 270000,
	"横浜ベイスターズ": 280000,
	"横浜DeNAベイスターズ": 280000,
	"東北楽天ゴールデンイーグルス": 270000,
	"北海道日本ハムファイターズ": 270000,
	"広島東洋カープ": 240000,
	"東京ヤクルトスワローズ": 240000,
}
const BUDGET_DEFAULT := 260000

var year: int                       ## このオフのシーズンの年（来季は year + 1）
var team: String                    ## 自球団
## 自球団の選手ID → {prev: 今季の年俸, proposed: 査定額, amount: 提示額, low, high, fixed: 据え置きの理由（空なら調整可）}
var rows := {}
var order: Array[String] = []       ## rows の並び（年俸の高い順）
var resolved := false


## テスト用：球団 → 予算上限の差し替え（予算と関係のない仕組みを確かめるテストで、上限を外すのに使う）
static var budget_override := {}


## 球団の予算上限（万円）
static func budget(team_name: String) -> int:
	if budget_override.has(team_name):
		return int(budget_override[team_name])
	return int(BUDGET.get(team_name, BUDGET_DEFAULT))


## テスト用：予算上限を差し替える（amount < 0 で元に戻す）
static func set_budget_override(team_name: String, amount: int) -> void:
	if amount < 0:
		budget_override.erase(team_name)
	else:
		budget_override[team_name] = amount


func _init(season_year: int, user_team: String) -> void:
	year = season_year
	team = user_team


func add_row(id: String, prev: int, proposed: int, fixed: String) -> void:
	var r: Array = Salary.renew_limits(prev, proposed, year + 1) if fixed.is_empty() else [proposed, proposed]
	rows[id] = {"prev": prev, "proposed": proposed, "amount": proposed, "low": r[0], "high": r[1], "fixed": fixed}
	order.append(id)


func sort_rows() -> void:
	order.sort_custom(func(a: String, b: String) -> bool:
		if rows[a]["amount"] != rows[b]["amount"]:
			return rows[a]["amount"] > rows[b]["amount"]
		return a < b)


func can_adjust(id: String) -> bool:
	return rows.has(id) and String(rows[id]["fixed"]).is_empty() and not resolved


## 提示額を変える（範囲に丸める）。だめなら理由の文。決めた額は league の来季の年俸に入る
func set_amount(league: LeagueRoster, id: String, amount: int) -> String:
	if resolved:
		return "契約更改は終わりました"
	if not rows.has(id):
		return "自球団の契約更改の対象ではありません"
	if not String(rows[id]["fixed"]).is_empty():
		return "%sのため据え置きです" % rows[id]["fixed"]
	var row: Dictionary = rows[id]
	row["amount"] = clampi(Salary.round_amount(amount), row["low"], row["high"])
	league.set_next_salary(id, row["amount"], year + 1)
	return ""


## 提示額の合計の前年からの増減
func total_change() -> int:
	var d := 0
	for id: String in rows:
		d += int(rows[id]["amount"]) - int(rows[id]["prev"])
	return d


# --- セーブ／ロード ----------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"year": year, "team": team, "rows": rows, "order": order, "resolved": resolved}


static func from_save(d: Dictionary) -> ContractRenewal:
	var c := ContractRenewal.new(int(d["year"]), str(d["team"]))
	c.rows = d.get("rows", {})
	c.order.assign(d.get("order", []))
	c.resolved = bool(d.get("resolved", false))
	return c
