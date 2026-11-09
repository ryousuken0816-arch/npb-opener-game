class_name DraftIntent
extends RefCounted
## ドラフトの意中の球団・入団拒否（docs/AUTORUN.md 作業77）。
##
## - 架空のドラフト候補（2028年〜）の一部が「意中の球団」を持つ（GameState.draft_class で、候補を作った直後に
##   assign。amateur.team_intent に {team, hard, alt, note}）。年に3人前後、評価が高いほど・怪物ほど多い
##   - 意中（hard=false）：「〇〇が第一志望」。ほかの球団でも入団することが多い
##   - 「〇〇以外なら〇〇」（hard=true）：大学進学・社会人・会社に残留など。ほかの球団の指名は拒否しやすい
## - 意中ではない球団が指名すると入団の交渉（Draft の talks。メジャー志望の説得と同じ流れ）。自球団は誠意（年俸の
##   上乗せ）を選んで説得できる。説得しないまま進めたときは「通常の交渉」で決まる（メジャー志望と違い、期限切れにはしない）
## - 拒否した選手は入団せず、alt の進路へ。高校→大学は4年後、高校→社会人は3年後、大学・専門→社会人は2年後、
##   社会人・独立の残留は翌年に、また候補に戻る（LeagueRoster.draft_returns → GameState.draft_class で make_return）。
##   指名した球団は何も得ない（史実どおり）
## - CPU 球団は意中ではない候補をふだん避け（AVOID）、たまにあえて強行する（DARE）。意中の球団は少し上乗せ（FAVORITE_BONUS）

## 当時の評価ごとの、意中の球団を持つ確率（怪物は MONSTER_RATE）。育成枠の候補は持たない
const RATE := {"S": 0.25, "A": 0.12, "B": 0.04, "C": 0.015, "D": 0.0}
const MONSTER_RATE := 0.40
## 「〇〇以外なら〇〇」の強い表明になる割合
const HARD_SHARE := 0.35
## 意中に選ばれやすい球団（名前の一部 → 重み。ほかは 1）
const TEAM_WEIGHT := {"読売": 3.0, "阪神": 2.0, "ソフトバンク": 1.5}

## 意中ではない球団が指名したときの入団拒否の確率（誠意なし）
const REFUSE := {false: 0.30, true: 0.75}
const FIRST_ROUND := -0.08
const LOW_ROUND := 0.08  ## 4位以下
const IKUSEI := 0.20
const REFUSE_MIN := 0.03
const REFUSE_MAX := 0.95
## 誠意（自球団が選ぶ）：値 → {label, 上乗せの年俸（万円）, 成功率に足す値}
const OFFERS := [
	{"value": 0, "label": "通常の交渉", "bonus_man": 0, "plus": 0.0},
	{"value": 1, "label": "監督があいさつ・年俸を上乗せ（+1000万円）", "bonus_man": 1000, "plus": 0.12},
	{"value": 2, "label": "最大限の誠意（+3000万円）", "bonus_man": 3000, "plus": 0.22},
]
## CPU 球団：避ける強さ（評価から引く値）・あえて強行する確率・意中の球団の上乗せ
const AVOID := {false: 0.5, true: 1.6}
const DARE := {false: 0.35, true: 0.10}
const FAVORITE_BONUS := 0.4

## 拒否したあとの進路 → 候補に戻るまでの年数・戻るときの区分
const RETURN_YEARS := {"大学": 4, "社会人": 3, "社会人（大卒）": 2, "残留": 1}

const SOFT_NOTES := ["{school}の{name}は「{team}が第一志望」と公言している",
	"幼いころからの{team}ファン。{school}の{name}は意中の球団に{team}を挙げる",
	"{school}の{name}、{team}入りを熱望。ほかの球団の指名にどう応えるか"]
const HARD_NOTES := ["{school}の{name}は「{team}以外なら{alt}」と明言",
	"{school}の{name}、{team}一本の構え。ほかの球団なら{alt}へ進む意向",
	"「{team}でなければ{alt}」――{school}の{name}が進路の条件を口にした"]
const ALT_WORDS := {"大学": "大学進学", "社会人": "社会人", "社会人（大卒）": "社会人", "残留": "会社に残留"}


## 候補（GameState.draft_class の選手）に意中の球団を付ける。メジャー志望・育成枠の候補には付けない
static func assign(players: Array, teams: Array, rng: RandomNumberGenerator) -> void:
	if teams.is_empty():
		return
	for p: Dictionary in players:
		var am: Dictionary = p.get("amateur", {})
		if am.has("team_intent") or bool(am.get("as_ikusei", false)):
			continue
		var mi: Variant = am.get("mlb_intent")
		if mi is Dictionary and bool(mi.get("stated", false)):
			continue
		var rate: float = MONSTER_RATE if bool(p.get("is_monster", false)) else float(RATE.get(str(am.get("grade", "")), 0.0))
		if rng.randf() >= rate:
			continue
		am["team_intent"] = make_intent(p, _pick_team(teams, rng), rng.randf() < HARD_SHARE, rng)


static func make_intent(p: Dictionary, team: String, hard: bool, rng: RandomNumberGenerator) -> Dictionary:
	var am: Dictionary = p.get("amateur", {})
	var alt := alt_of(str(am.get("category", "")), rng)
	var notes: Array = HARD_NOTES if hard else SOFT_NOTES
	var note := str(notes[rng.randi_range(0, notes.size() - 1)]).format({"school": am.get("school", ""),
		"name": p.get("name", ""), "team": GameData.short_name(team), "alt": ALT_WORDS.get(alt, alt)})
	return {"team": team, "hard": hard, "alt": alt, "note": note}


## 拒否したときの進路（区分から）
static func alt_of(category: String, rng: RandomNumberGenerator) -> String:
	match category:
		"高校":
			return "大学" if rng.randf() < 0.5 else "社会人"
		"大学", "専門":
			return "社会人（大卒）"
	return "残留"


static func _pick_team(teams: Array, rng: RandomNumberGenerator) -> String:
	var weights: Array[float] = []
	var total := 0.0
	for t: String in teams:
		var w := 1.0
		for part: String in TEAM_WEIGHT:
			if part in t:
				w = float(TEAM_WEIGHT[part])
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	for i in teams.size():
		roll -= weights[i]
		if roll <= 0.0:
			return teams[i]
	return teams[-1]


## 意中の球団を持つ候補（Draft の候補 c）で、team が意中ではない（＝入団の交渉が要る）か
static func needs_talk(c: Dictionary, team: String) -> bool:
	var it: Variant = c.get("intent")
	return it is Dictionary and not it.is_empty() and str(it.get("team", "")) != team


## 入団拒否の確率。rec：指名の記録（round・ikusei）、offer：誠意（OFFERS の value）
static func refuse_chance(intent: Dictionary, rec: Dictionary, offer: int) -> float:
	var r := float(REFUSE[bool(intent.get("hard", false))])
	if bool(rec.get("ikusei", false)):
		r += IKUSEI
	elif int(rec.get("round", 0)) == 1:
		r += FIRST_ROUND
	elif int(rec.get("round", 0)) >= 4:
		r += LOW_ROUND
	r -= float(offer_of(offer)["plus"])
	return clampf(r, REFUSE_MIN, REFUSE_MAX)


## 説得の成功率（＝入団する確率）
static func chance(intent: Dictionary, rec: Dictionary, offer: int) -> float:
	return 1.0 - refuse_chance(intent, rec, offer)


static func offer_of(value: int) -> Dictionary:
	for o: Dictionary in OFFERS:
		if int(o["value"]) == value:
			return o
	return OFFERS[0]


## 候補の短い説明（「巨人志望」「巨人以外なら大学進学」）
static func short_text(intent: Dictionary) -> String:
	var team := GameData.short_name(str(intent.get("team", "")))
	if bool(intent.get("hard", false)):
		var alt := str(intent.get("alt", ""))
		return "%s以外なら%s" % [team, ALT_WORDS.get(alt, alt)]
	return "%s志望" % team


## 拒否した選手が候補に戻る年（ドラフトの年）
static func return_year(intent: Dictionary, draft_year: int) -> int:
	return draft_year + int(RETURN_YEARS.get(str(intent.get("alt", "")), 1))


# --- 候補に戻る ------------------------------------------------------------------------------

## 拒否した選手 entry（LeagueRoster.draft_returns の1件：{due, draft_year, team, label, intent, player}）を、
## draft_year 年の候補に作り直す。能力は戻るまでの年数ぶん growth で伸ばす。当時の評価（grade・as_round・bids）は
## その年の候補 cls（支配下の枠）のうち、入団時の能力がいちばん近い候補に合わせる。school：新しい所属
static func make_return(entry: Dictionary, draft_year: int, cls: Array, school: String, growth: Growth,
		rng: RandomNumberGenerator) -> Dictionary:
	var p: Dictionary = (entry["player"] as Dictionary).duplicate(true)
	var from_year := int(entry["draft_year"])
	if growth != null and growth.is_ready():
		for y in range(from_year + 2, draft_year + 2):
			p = growth.grow(p, y, rng)
	var intent: Dictionary = entry.get("intent", {})
	var alt := str(intent.get("alt", "残留"))
	var am: Dictionary = p["amateur"]
	var old_school := str(am.get("school", ""))
	var category := "大学" if alt == "大学" else "社会人"
	if alt == "残留" and str(am.get("category", "")) == "独立":
		category = "独立"
	am["draft_year"] = draft_year
	am["category"] = category
	if alt != "残留":
		am["school"] = school
	var years := draft_year - from_year
	var old_n := maxi(1, str(am.get("grade_text", "")).to_int())
	if category == "大学":
		am["grade_text"] = "大学4年"
	elif alt == "残留":
		am["grade_text"] = ("%d年目" if category == "独立" else "入社%d年目") % (old_n + years)
	else:
		am["grade_text"] = "入社%d年目" % years
	am["entry_age"] = Growth.age_at(p, draft_year + 1)
	p["draft"] = "%d年ドラフト候補" % draft_year
	p["career"] = am["school"]
	p["id"] = "fic:%d:r%s" % [draft_year, str(entry["player"].get("id", "")).replace(":", "-")]
	# 当時の評価：入団時の能力がいちばん近い候補に合わせる
	var level := FictionalDraft.entry_level(p)
	var best: Dictionary = {}
	var best_d := INF
	for q: Dictionary in cls:
		var qa: Dictionary = q.get("amateur", {})
		if bool(qa.get("as_ikusei", false)):
			continue
		var dist := absf(FictionalDraft.entry_level(q) - level)
		if dist < best_d:
			best_d = dist
			best = qa
	for k: String in ["band", "grade", "as_round", "projected"]:
		if best.has(k):
			am[k] = best[k]
	am["as_ikusei"] = false
	am["bids"] = int(best.get("bids", 1)) if str(am.get("grade", "")) == "S" else 1
	am.erase("team_intent")
	am.erase("mlb_intent")
	# 物語：何年に、どこの指名を拒否したか
	var story := "%d年秋、%sの%s指名を拒否して%s" % [from_year, GameData.short_name(str(entry["team"])),
		str(entry.get("label", "")), "%sへ進んだ" % am["school"] if alt != "残留" else "%sに残った" % old_school]
	am["story"] = story
	am["refused"] = {"year": from_year, "team": str(entry["team"]), "label": str(entry.get("label", ""))}
	am["intro"] = FictionalDraft.intro_of(p)
	# 意中の球団は、半分くらいは今も同じ（強い表明は弱まる）
	if rng.randf() < 0.5:
		var again := make_intent(p, str(intent.get("team", "")), false, rng)
		am["team_intent"] = again
	return p
