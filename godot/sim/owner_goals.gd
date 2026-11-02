class_name OwnerGoals
extends RefCounted
## オーナーの目標と評価（作業46）。GameState が1つ持つ。オートロードは参照しない（事実は GameState が集めて渡す）。
##
## - 春季キャンプ（ゲームの開始時も）に、今年の目標を1〜3個（choose）：順位の目標を必ず1つ（球団の戦力の順位と
##   前年の順位から。優勝・Aクラス・勝率5割・最下位脱出）、強い球団は日本一、弱い球団ほど若手の起用、
##   年俸総額が予算に近い・超えている球団は予算を守る
## - 表彰のあと（オフの次の段階へ進むとき）に採点（evaluate）：目標ごとに 0〜1.3 点、平均で S〜E と短い講評。
##   評価で翌年の予算（ContractRenewal.owner_bonus）が増減する。D・E が続くと「監督の進退」のニュース（GameState）。
##   ゲームオーバーにはしない

const GRADES := ["S", "A", "B", "C", "D", "E"]
## この点以上でその評価（GRADES と同じ並び。最後は残り全部）
const GRADE_MIN := [1.1, 0.95, 0.7, 0.45, 0.2]
## 評価 → 翌年の予算の増減（万円）
const GRADE_BUDGET := {"S": 20000, "A": 10000, "B": 0, "C": 0, "D": -5000, "E": -10000}
## 予算の増減の合計の範囲（万円）
const BONUS_MIN := -30000
const BONUS_MAX := 60000
## 「監督の進退」のニュースを出す、D・E の続いた年数
const BAD_STREAK_NEWS := 2
const GRADE_COMMENT := {
	"S": "期待を大きく上回る一年だった。来季の補強費は上積みする",
	"A": "目標をしっかり果たしてくれた。来季の予算は少し増やそう",
	"B": "おおむね合格だが、もう一歩ほしかった",
	"C": "物足りない一年だった。来季は結果で応えてほしい",
	"D": "期待を裏切る結果だ。来季の予算は削らせてもらう",
	"E": "到底納得できない。来季の予算は大きく削る",
}

## 若手の目標：この年齢（4月1日時点）以下の選手の 打席＋対戦打者
const YOUTH_AGE := 25
const YOUTH_TARGET := {"strong": 1600, "weak": 2400}
## 戦力の見込みの順位（1〜6）がこれ以下（強い）なら若手の目標を出す確率は YOUTH_P_STRONG
const YOUTH_P_STRONG := 0.25
const YOUTH_P_WEAK := 0.7
## 年俸総額が予算のこの割合を超えていれば「予算を守る」を目標に入れる
const BUDGET_GOAL_SHARE := 0.95
## 見込みの順位（戦力の順位を2、前年の順位を1の重み）→ 順位の目標
const RANK_TIERS := [[1.8, "rank", 1], [3.5, "rank", 3], [4.8, "winpct", 500], [99.0, "rank", 5]]

## "年" → [{kind, target}]
var goals := {}
## "年" → {grade, score, comment, results: [{text, score, done, actual}], budget_delta, bonus, team}
var evals := {}
## 予算の増減の合計（万円）
var bonus := 0
## D・E の続いている年数
var bad_streak := 0


## 目標を決める。strength_rank：開幕時の戦力の順位（リーグの6球団中）、prev_rank：前年の順位（無ければ -1）、
## prev_champion：前年の日本一、payroll / budget：年俸総額と予算（万円）
static func choose(strength_rank: int, prev_rank: int, prev_champion: bool, payroll: int, budget: int,
		rng: RandomNumberGenerator) -> Array:
	var expect := float(strength_rank) if prev_rank < 1 else (strength_rank * 2.0 + prev_rank) / 3.0
	var list: Array = []
	for tier: Array in RANK_TIERS:
		if expect <= float(tier[0]):
			list.append({"kind": tier[1], "target": tier[2]})
			break
	var strong := expect <= 3.5
	if expect <= 1.8 and (prev_champion or rng.randf() < 0.4):
		list.append({"kind": "japan", "target": 1})
	if rng.randf() < (YOUTH_P_STRONG if strong else YOUTH_P_WEAK) and list.size() < 3:
		list.append({"kind": "youth", "target": YOUTH_TARGET["strong" if strong else "weak"]})
	if budget > 0 and payroll > budget * BUDGET_GOAL_SHARE and list.size() < 3:
		list.append({"kind": "budget", "target": budget})
	return list


static func goal_text(g: Dictionary) -> String:
	var t := int(g["target"])
	match str(g["kind"]):
		"rank":
			match t:
				1:
					return "リーグ優勝"
				3:
					return "Aクラス入り（3位以内）"
				5:
					return "最下位脱出（5位以内）"
			return "%d位以内" % t
		"winpct":
			return "勝率5割以上"
		"japan":
			return "日本一"
		"youth":
			return "若手の起用（%d歳以下の打席＋対戦打者 %d）" % [YOUTH_AGE, t]
		"budget":
			return "年俸総額を予算（%s）内に" % money_text(t)
	return str(g["kind"])


## 万円 → "32.5億" / "8000万"
static func money_text(amount: int) -> String:
	if absi(amount) >= 10000:
		return "%.1f億" % (amount / 10000.0)
	return "%d万" % amount


## 1つの目標の採点。facts: {rank, win_pct, champion, js（日本シリーズに出た）, youth, payroll, budget, final（年末か）}
## 返す: {score（0〜1.3）, done（達成。途中なら今のペースで）, actual（今の数字のひとこと）}
static func score_goal(g: Dictionary, facts: Dictionary) -> Dictionary:
	var t := int(g["target"])
	var rank := int(facts.get("rank", 6))
	match str(g["kind"]):
		"rank":
			var s := 1.0 + 0.1 * (t - rank) if rank <= t else maxf(0.0, 1.0 - 0.35 * (rank - t))
			return {"score": minf(s, 1.3), "done": rank <= t, "actual": "%d位" % rank}
		"winpct":
			var pct := float(facts.get("win_pct", 0.0))
			var s := 1.0 + (pct - 0.5) * 2.0 if pct >= 0.5 else maxf(0.0, 1.0 - (0.5 - pct) * 8.0)
			return {"score": minf(s, 1.3), "done": pct >= 0.5, "actual": "勝率 %s" % ("%.3f" % pct).trim_prefix("0")}
		"japan":
			var champ := bool(facts.get("champion", false))
			var s := 1.2 if champ else (0.7 if facts.get("js", false) else (0.4 if rank <= 3 else 0.1))
			var actual := "日本一" if champ else ("日本シリーズ" if facts.get("js", false) else "%d位" % rank)
			if not facts.get("final", true) and not champ:
				actual = "%d位" % rank
				return {"score": s, "done": rank == 1, "actual": actual}
			return {"score": s, "done": champ, "actual": actual}
		"youth":
			var n := int(facts.get("youth", 0))
			var ratio := float(n) / maxf(1.0, t)
			var pace := float(facts.get("pace", 1.0))  # 途中：消化した試合の割合
			var s := minf(1.3, ratio) if ratio >= 1.0 else ratio * 0.9
			return {"score": s, "done": ratio >= pace, "actual": "%d／%d" % [n, t]}
		"budget":
			var pay := int(facts.get("payroll", 0))
			var bud := int(facts.get("budget", t))
			var s := 1.0 if pay <= bud else maxf(0.0, 1.0 - (float(pay) / bud - 1.0) * 5.0)
			return {"score": s, "done": pay <= bud, "actual": "%s／%s" % [money_text(pay), money_text(bud)]}
	return {"score": 0.0, "done": false, "actual": ""}


static func grade_of(score: float) -> String:
	for i in GRADE_MIN.size():
		if score >= float(GRADE_MIN[i]):
			return GRADES[i]
	return GRADES[-1]


func set_goals(year: int, list: Array) -> void:
	goals[str(year)] = list.duplicate(true)


func goals_of(year: int) -> Array:
	return goals.get(str(year), [])


func eval_of(year: int) -> Dictionary:
	return evals.get(str(year), {})


## 年末の評価を決めて残す（同じ年を2回通っても上書きするだけで、予算は1回だけ動かす）。返す: 評価
func evaluate(year: int, facts: Dictionary, team_name: String) -> Dictionary:
	var key := str(year)
	var list := goals_of(year)
	if list.is_empty():
		return {}
	var results: Array = []
	var total := 0.0
	for g: Dictionary in list:
		var r := score_goal(g, facts)
		results.append({"text": goal_text(g), "score": r["score"], "done": r["done"], "actual": r["actual"]})
		total += float(r["score"])
	var score := total / list.size()
	var grade := grade_of(score)
	if evals.has(key):
		bonus -= int(evals[key].get("budget_delta", 0))
		if evals[key].get("bad", false):
			bad_streak = maxi(0, bad_streak - 1)
	var before := bonus
	bonus = clampi(bonus + int(GRADE_BUDGET[grade]), BONUS_MIN, BONUS_MAX)
	var bad := grade in ["D", "E"]
	bad_streak = bad_streak + 1 if bad else 0
	var e := {"grade": grade, "score": snappedf(score, 0.01), "comment": GRADE_COMMENT[grade], "results": results,
		"budget_delta": bonus - before, "bonus": bonus, "team": team_name, "bad": bad, "streak": bad_streak}
	evals[key] = e
	return e


## 評価のある年（古い順）
func eval_years() -> Array[int]:
	var result: Array[int] = []
	for key: String in evals:
		result.append(int(key))
	result.sort()
	return result


func to_save() -> Dictionary:
	return {"goals": goals, "evals": evals, "bonus": bonus, "bad_streak": bad_streak}


static func from_save(d: Variant) -> OwnerGoals:
	var o := OwnerGoals.new()
	if not (d is Dictionary):
		return o
	o.goals = d.get("goals", {})
	o.evals = d.get("evals", {})
	o.bonus = int(d.get("bonus", 0))
	o.bad_streak = int(d.get("bad_streak", 0))
	return o
