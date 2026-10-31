class_name MlbPersuasion
extends RefCounted
## メジャー志望の選手をドラフトで指名したときの説得の交渉（docs/AUTORUN.md 作業26）。
##
## - メジャー志望の選手：史実で表明した選手（data/mlb_intent.json）と、史実の無い年の候補の
##   data/amateur/<年>.json の mlb_intent.stated
## - 成功率：強行指名の基本 BASE_CHANCE、「何年後にポスティングを認める」約束で PROMISE_BONUS（年数が短いほど
##   大きい）、1位指名・育成指名で少し上下。★は成功率の目安（FA の引き留めと同じ5段階）
## - 説得は1人1回（自球団はドラフト会議の結果の画面で。しなければ約束なしの扱い）。CPU球団は半々で約束する
## - 失敗した選手は渡米してゲームの NPB には出てこない。約束した選手は約束の年のオフにポスティングでメジャーへ
## - 交渉期限（高校生などは翌年3月末、海外の学校に在学する選手は翌年7月末）は表示だけ。結果はドラフト会議の
##   あと（オフ）にすぐ決まる

const BASE_CHANCE := 0.10
## 約束の年数 → 成功率に足す値（ユーザー決定：約束で +30% 前後。短い約束ほど選手には魅力）
const PROMISE_BONUS := {3: 0.34, 4: 0.30, 5: 0.27, 6: 0.24}
const PROMISE_YEARS := [3, 4, 5, 6]
const FIRST_ROUND_BONUS := 0.03
const IKUSEI_PENALTY := -0.05
const CHANCE_MIN := 0.02
const CHANCE_MAX := 0.60
## ★の境目（成功率がこれ以上で ★2・★3・★4・★5）
const STAR_STEPS := [0.10, 0.25, 0.38, 0.50]
## CPU球団が約束を付ける確率と、そのときの年数
const CPU_PROMISE_RATE := 0.5
const CPU_PROMISE_YEARS := 4
## CPU球団はふだんメジャー志望の候補を避ける（評価から引く値）。DARE_RATE の確率でその候補を気にしない
## （たまの強行指名）。史実で強行指名した球団は避けない
const CPU_AVOID := 1.6
const CPU_DARE_RATE := 0.12


## 成功率。promise：約束の年数（0＝約束なし）
static func chance(rec: Dictionary, promise: int) -> float:
	var c := BASE_CHANCE + float(PROMISE_BONUS.get(promise, 0.0))
	if bool(rec.get("ikusei", false)):
		c += IKUSEI_PENALTY
	elif int(rec.get("round", 0)) == 1:
		c += FIRST_ROUND_BONUS
	return clampf(c, CHANCE_MIN, CHANCE_MAX)


static func stars(value: float) -> int:
	var n := 1
	for step: float in STAR_STEPS:
		if value >= step:
			n += 1
	return n


static func star_text(value: float) -> String:
	var n := stars(value)
	return "★".repeat(n) + "☆".repeat(5 - n)


## 交渉期限の文（draft_year の翌年）
static func deadline_text(draft_year: int, overseas: bool) -> String:
	return "%d年%s" % [draft_year + 1, "7月末" if overseas else "3月末"]


## その年のメジャー志望の候補（正規化した名前 → {overseas, hist_team, hist_result, note}）
static func intents(draft_year: int) -> Dictionary:
	var result := {}
	var hist: Variant = GameData.read_data("mlb_intent.json")
	if hist is Array:
		for m: Dictionary in hist:
			if int(m.get("draft_year", 0)) == draft_year:
				result[LeagueRoster.norm_name(str(m["name"]))] = m
	var ama: Variant = GameData.read_data("amateur/%d.json" % draft_year)
	if ama is Dictionary and draft_year > Draft.LAST_HISTORY_YEAR:
		for a: Dictionary in ama.get("players", []):
			var mi: Variant = a.get("mlb_intent")
			if mi is Dictionary and bool(mi.get("stated", false)):
				result[LeagueRoster.norm_name(str(a["name"]))] = {"overseas": a.get("category") == "その他",
					"hist_team": "", "hist_result": null, "note": str(mi.get("note", ""))}
	return result
