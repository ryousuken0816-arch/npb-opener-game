# gdlint: disable=max-public-methods,max-file-lines
class_name Draft
extends RefCounted
## 1回分のドラフト会議（オフの「ドラフト」の段階。docs/AUTORUN.md 作業5、docs/SPEC.md「ドラフト・編成」）。
##
## 候補はその年の史実のドラフト指名選手全員（data/<年+1>/drafts.json の当年秋の分。本指名と育成）。能力は来季の
## 開幕時点の能力値ファイル（新人の初期能力。1軍出場の無い選手は仮IDの選手）。ファイルにいない候補は似た候補の
## 能力を写した仮の選手（synthetic）を作る。指名されなかった候補は入団しない。
## 史実の無い年（LAST_HISTORY_YEAR より後。2027年〜）は data/amateur/<年>.json の実在のアマ選手が候補（作業17）。
## 当時の評価は報道での格付け（GRADE_AS_PICK）、CPU球団の指名人数は AMATEUR_QUOTA、能力は tools/amateur_ratings.py
##
## 進行（stage）：
## - FIRST：1位入札。全球団が同時に入札し（自球団は user_bid、CPU球団は _cpu_first_bid）、run_first_wave() で
##   重複した候補は抽選。外れた球団は次の入札（外れ1位）へ。全球団の1位が決まるまでくり返す
## - WAIVER：2位以降。前年の順位でウェーバー（偶数巡は順位の逆＝下位から、奇数巡は上位から）。自球団の番は
##   user_pick／user_finish、CPU球団は cpu_step()。CPU球団は史実でその球団が指名した人数（quota）まで指名する
## - IKUSEI：育成選手の指名。順番は WAIVER と同じ。CPU球団は史実の育成指名の人数まで
## - DONE：終了（GameState が LeagueRoster.apply_draft で入団させる）
##
## 2つのランク（S〜G）：
## - 当時の評価（hyouka）：史実の指名順位＋1巡目の競合数（data/draft_first_round.json）
## - 将来性（future）：入団後の史実の能力値のピーク（generated/draft_future.json、tools/draft_future.py）に
##   ノイズ（難易度の定数 DIFFICULTY_NOISE）を足したもの。CPU球団の指名判断も同じノイズ入りの値を使う。
##   指名から日が浅い年（2023年以降）は史実の成績が少ないので当時の評価で補う（2025年はほぼ当時の評価そのまま）

enum Stage { FIRST, WAIVER, IKUSEI, DONE }

## 難易度ごとの将来性のノイズ（z）。システム設定の「難易度」ができたら切り替える
const DIFFICULTY_NOISE := {"easy": 0.2, "normal": 0.35, "hard": 0.6}
const DIFFICULTY := "normal"
## CPU球団ごとの見立ての違い（同じ候補でも球団によって評価が少しずつ違う）
const TEAM_NOISE := 0.3
## CPU球団の評価：1位入札（当時の評価を重く）
const FIRST_FUTURE_WEIGHT := 0.6
const FIRST_HYOUKA_WEIGHT := 0.9
## 2位以降：当時の評価と将来性（ノイズ入り）をそれぞれ候補全体の z にして、この割合で混ぜる（作業7）。
## 難易度ごと：やさしい＝当時の評価寄り（史実で下位指名のお宝が下位まで残る）、むずかしい＝将来性寄り
const CPU_HYOUKA_SHARE := {"easy": 0.8, "normal": 0.7, "hard": 0.55}
## 目玉：各CPU球団が上位で強く狙う候補（1〜TARGET_COUNT_MAX 人）。その球団の見立て（将来性＋見立ての違い）の
## 上位から選び、1位入札と TARGET_ROUNDS 位までの指名で評価に TARGET_BONUS を足す。
## 本当の大物は多くの球団の目玉になって上位で消え、中くらいのお宝は目玉にならず下位まで残る
const TARGET_COUNT_MAX := 2
const TARGET_BONUS := 1.5
const TARGET_ROUNDS := 2
## 1位入札：先に入札した球団1つごとに評価から引く値（競合を嫌う）と、入札ごとの迷い
const COMPETE_PENALTY := 0.4
const FIRST_BID_NOISE := 0.15
## 守備位置の不足をどれだけ評価に足すか（最大・最小）
const NEED_WEIGHT := 0.8
const NEED_MAX := 0.5
const NEED_MIN := -0.3
## 支配下＋育成のうち、守備位置ごとの目安の割合（投手・捕手・内野・外野）
const NEED_SHARE := {"投手": 0.5, "捕手": 0.1, "内野手": 0.22, "外野手": 0.18}
## 自球団が指名できる最大人数（本指名・育成）
const USER_MAX_REG := 10
const USER_MAX_IKUSEI := 10
## 1位入札をくり返す上限（候補が尽きたときの保険）
const MAX_WAVES := 8

## 当時の評価の値：1位（1回目の入札）＝ FIRST_BASE ＋ FIRST_PER_BID × (競合数−1)、外れ1位、2位以降、育成
const FIRST_BASE := 3.0
const FIRST_PER_BID := 0.6
const REBID_BASE := 2.5
const REBID_PER_BID := 0.2
const ROUND_VALUE := {2: 2.0, 3: 1.5, 4: 1.1, 5: 0.8, 6: 0.55, 7: 0.35}
const LATE_ROUND_VALUE := 0.2
const IKUSEI_VALUE := {1: 0.0, 2: -0.2}
const LATE_IKUSEI_VALUE := -0.4
## ランクのしきい値 [S, A, B, C, D, E, F]（これ未満は G）
const HYOUKA_RANKS := [4.0, 2.9, 1.9, 1.0, 0.5, 0.15, -0.1]
const FUTURE_RANKS := [1.6, 1.1, 0.65, 0.25, -0.1, -0.45, -0.8]
const RANK_LETTERS := ["S", "A", "B", "C", "D", "E", "F", "G"]
## 一度も能力値ファイルに出てこなかった（1軍・2軍に在籍しなかった）選手の将来性
const FUTURE_NONE := -1.2
## 当時の評価を将来性の目盛りに直す（史実の成績が少ない年の補い）：FUTURE_FROM_HYOUKA[0] + [1] × 評価
const FUTURE_FROM_HYOUKA := [-0.9, 0.55]
## 史実の成績がこの年数そろえば将来性は史実だけで決める（それより少なければ当時の評価で補う）
const FUTURE_FULL_YEARS := 3.0

## 経歴の並び順
## 1年目の能力（作業13）：投手の項目と、野手の総合（打撃・走塁・守備の加重平均。Salary.ability と同じ重み）
const FIRST_PITCH_KEYS := ["overall", "stamina", "k9", "bb9"]
const FIRST_BAT_WEIGHTS := {"meet": 0.35, "power": 0.35, "eye": 0.1, "speed": 0.1, "defense": 0.1}
## 史実（npb.jp）のシーズン・ドラフトがある最後の年。これより後の年に入団した新人の1年目は「未来」（表示しない）
const LAST_HISTORY_YEAR := 2026
## この年の能力値ファイルはシーズン途中のデータ。この年に入団した新人の1年目は途中（今は無し。2026年は最終成績）
const IN_PROGRESS_YEAR := 0
## 史実の指名が無い年（アマ選手の候補）に CPU球団が指名する人数
const AMATEUR_QUOTA := {"reg": 6, "ikusei": 2}
## アマ選手の報道での格付け（S〜D）→ 当時の評価を作る [順位, 競合数]。D は育成1位相当
const GRADE_AS_PICK := {"S": [1, 3], "A": [1, 1], "B": [2, 0], "C": [4, 0], "D": [1, -1]}
## 史実の指名がある年でも data/amateur/<年>.json に有識者の格付けがあれば、当時の評価にこの割合で混ぜる
## （ユーザー指示 2026-11-01：当時の評価も有識者の評価を総合して決める）
const SCOUT_HYOUKA_WEIGHT := 0.5
const CAREER_ORDER := ["高校生", "大学生", "専門学校", "社会人", "独立"]
## 架空の候補の区分（amateur.category）→ 経歴の表示（作業50）
const CATEGORY_CAREER := {"高校": "高校生", "大学": "大学生", "専門": "専門学校", "社会人": "社会人", "独立": "独立"}
const POS_GROUPS := ["投手", "捕手", "内野手", "外野手"]

## drafts.json の球団コード → 球団の略称（GameData.resolve_team へ）
const TEAM_CODES := {
	"g": "読売", "t": "阪神", "d": "中日", "yb": "横浜", "db": "横浜DeNA", "c": "広島東洋", "s": "東京ヤクルト",
	"l": "埼玉西武", "bs": "オリックス", "b": "オリックス", "h": "福岡ソフトバンク", "f": "北海道日本ハム",
	"m": "千葉ロッテ", "e": "東北楽天",
}

var year: int
var user_team := ""
var stage: Stage = Stage.FIRST
var teams: Array[String] = []
var candidates: Array[Dictionary] = []
var by_id := {}
## 球団 → {"reg": 本指名の人数, "ikusei": 育成の人数}（史実）
var quota := {}
## 指名の記録 [{team, id, round, ikusei, label, wave}]（指名順）
var picks: Array[Dictionary] = []
## 1位の入札の回（1＝最初の入札、2以降＝外れ1位）
var wave := 1
## 今の回の入札（球団 → 候補ID）。自球団は user_bid で入れる
var bids := {}
## 抽選の記録 [{wave, id, teams: [球団], winner}]
var lotteries: Array[Dictionary] = []
## 直前の入札の結果 [{team, id, won: bool, lottery: bool, rivals: int}]
var last_wave: Array[Dictionary] = []
## ウェーバーの順番（2巡目の順。下位から）
var order: Array[String] = []
## 今の巡（本指名は2〜、育成は1〜）と、いま指名する球団
var round := 2
var _turn_team := ""
## いまの番の、その巡の並び（_base_order）の中の位置（指名権が移ると同じ球団が1つの巡に2回出るので位置で持つ）
var _turn_index := 0
## FAの補償で移った指名権 [{round, from, to}]（本指名のその巡で from の番が to の番になる。作業18）
var pick_moves: Array = []
## 指名を終えた球団（本指名・育成）
var done_reg := {}
var done_ikusei := {}
## 自球団が自分で選んだか（false ならおまかせ）
var user_auto := false
## 自球団の支配下の空き（本指名の上限。GameState から渡す。-1 は制限なし）
var user_room := -1
var resolved := false
## 将来性の元データの最終年（generated/draft_future.json の data_through）
var data_through := 0
## メジャー志望の選手の説得（作業26、MlbPersuasion）：候補ID → {team, promise, chance, ok}
var talks := {}
## テスト用：0以上なら説得の乱数の代わりに使う
var force_roll := -1.0

var _rng := RandomNumberGenerator.new()
var _team_noise := {}
## 球団 → {候補ID: true}：メジャー志望の候補を避けない（たまの強行指名・史実で強行指名した球団）
var _team_dare := {}
var _need := {}  ## 球団 → {守備位置: 今の人数}
## CPU球団 → [目玉の候補ID]（setup で決める。セーブに入る）
var cpu_targets := {}
## 当時の評価・将来性（ノイズ入り）の候補全体の平均と標準偏差（2位以降の評価の z。setup・ロードで計算）
var _scale := {}
## 自球団の作戦会議の印（作業37、DraftBoard.apply_to）：候補ID → 印（◎○△☆✕）と、本命（◎）の順 [候補ID]。
## 自球団のおまかせ・おすすめ（user_recommend）だけに使う。CPU球団の指名は変わらない
var user_marks := {}
var user_favorites: Array = []


## 候補を作る。league: 所属（守備位置の不足の計算に使う）、entries: 来季の開幕時点の能力値ファイルの選手
## （選手ID → 選手。LeagueRoster._plan.entries）、taken: すでにどこかに所属している選手ID（候補にしない）
func setup(season_year: int, user: String, team_names: Array[String], entries: Dictionary,
		taken: Dictionary, waiver_order: Array[String], seed_value: int) -> void:
	year = season_year
	user_team = user
	teams = team_names.duplicate()
	order = waiver_order.duplicate()
	_rng.seed = seed_value
	var rows := draft_rows(year)
	var first := _first_round_info(year)
	var future := _load_future()
	var mlb := MlbPersuasion.intents(year)
	var scout_grades := {}
	if not rows.is_empty() and not bool(rows[0].get("amateur", false)):
		for a in amateur_rows(year):
			scout_grades[LeagueRoster.norm_name(a["name"])] = a["grade"]
	var by_name := {}
	for id: String in entries:
		if not taken.has(id):
			# 登録名（雄星など）の選手はドラフト会議の一覧の名前（菊池 雄星）で引けるようにする
			var row := GameData.draft_entry_for(entries[id], year)
			by_name[LeagueRoster.norm_name(str(row.get("name", entries[id]["name"])))] = id
	for t in teams:
		quota[t] = {"reg": 0, "ikusei": 0}
	var missing: Array[Dictionary] = []
	for d: Dictionary in rows:
		var key := LeagueRoster.norm_name(d["name"])
		var hist := hist_team_of(d, year)
		var amateur: bool = d.get("amateur", false)
		var c := {
			"name": d["name"], "pos": d.get("pos", ""), "pitcher": d.get("pos", "") == "投手",
			"school": d.get("school", ""), "career": career_of_row(d),
			"hist_team": hist, "hist_ikusei": bool(d.get("ikusei", false)),
			"hist_round": round_number(d.get("round", "")), "picked_by": "", "pick_label": "",
			"amateur": amateur, "grade": str(d.get("grade", "")), "fictional": bool(d.get("fictional", false)),
		}
		c["hist_label"] = ("育成" if c["hist_ikusei"] else "") + "%d位" % c["hist_round"]
		var fr: Dictionary = first.get(key, {})
		c["bids"] = int(fr.get("bids", 1)) if c["hist_round"] == 1 and not c["hist_ikusei"] else 0
		c["rebid"] = int(fr.get("wave", 1)) >= 2
		c["hyouka"] = hyouka_value(c["hist_round"], c["hist_ikusei"], c["bids"], c["rebid"])
		if amateur:
			c["hist_label"] = ""
			c["hist_round"] = 0
			c["bids"] = 0
			c["hyouka"] = grade_value(c["grade"])
			if d.has("as_round"):
				# 架空の候補（作業22）：ひな形の史実の指名順位・競合数が当時の評価
				c["bids"] = int(d["bids"]) if int(d["as_round"]) == 1 and not bool(d["as_ikusei"]) else 0
				c["hyouka"] = hyouka_value(int(d["as_round"]), bool(d["as_ikusei"]), maxi(1, int(d["bids"])), false)
			c["reincarnation"] = d.get("reincarnation", {})
		elif scout_grades.has(key):
			c["grade"] = str(scout_grades[key])
			c["hyouka"] = lerpf(c["hyouka"], grade_value(c["grade"]), SCOUT_HYOUKA_WEIGHT)
		c["hyouka"] += AmateurTournament.bonus(GameState.amateur_results, year, c["name"], c["school"])
		c["hyouka_rank"] = rank_of(c["hyouka"], HYOUKA_RANKS)
		c["mlb_intent"] = mlb.has(key)
		if c["mlb_intent"]:
			c["mlb_overseas"] = bool(mlb[key].get("overseas", false))
			c["mlb_note"] = str(mlb[key].get("note", ""))
		c["future"] = _future_value(future.get(key, {}), c["hyouka"])
		if d.has("future_score"):
			c["future"] = float(d["future_score"])  # 架空の候補：隠れたピーク（難易度のノイズは下で足す）
		c["future_seen"] = c["future"] + _rng.randfn(0.0, DIFFICULTY_NOISE[DIFFICULTY])
		c["future_rank"] = rank_of(c["future_seen"], FUTURE_RANKS)
		if quota.has(hist):
			quota[hist]["ikusei" if c["hist_ikusei"] else "reg"] += 1
		if by_name.has(key):
			c["id"] = by_name[key]
			c["synthetic"] = false
			by_name.erase(key)
		else:
			c["id"] = "tmp:draft%d:%s" % [year, key]
			c["synthetic"] = true
			missing.append(c)
		if by_id.has(c["id"]):
			continue
		candidates.append(c)
		by_id[c["id"]] = c
	if not rows.is_empty() and bool(rows[0].get("amateur", false)):
		for t in teams:
			quota[t] = AMATEUR_QUOTA.duplicate()
	for c in candidates:
		_fill_profile(c, entries.get(c["id"], {}))
	for c in missing:
		c["player"] = _synthetic_player(c, entries)
		_fill_profile(c, c["player"])
	_fill_first_years()
	for t in teams:
		_team_noise[t] = {}
		_team_dare[t] = {}
		for c in candidates:
			_team_noise[t][c["id"]] = _rng.randfn(0.0, TEAM_NOISE)
	for c in candidates:
		if not c["mlb_intent"]:
			continue
		for t in teams:
			if t == c["hist_team"] or _rng.randf() < MlbPersuasion.CPU_DARE_RATE:
				_team_dare[t][c["id"]] = true
	_compute_scale()
	_choose_targets()


## 2位以降の評価に使う、当時の評価・将来性（ノイズ入り）の平均と標準偏差
func _compute_scale() -> void:
	for key: String in ["hyouka", "future_seen"]:
		var sum := 0.0
		var sq := 0.0
		for c in candidates:
			sum += float(c[key])
			sq += float(c[key]) * float(c[key])
		var n := maxf(float(candidates.size()), 1.0)
		var mean := sum / n
		_scale[key] = [mean, maxf(sqrt(maxf(sq / n - mean * mean, 0.0)), 0.01)]


## CPU球団ごとの目玉（1〜TARGET_COUNT_MAX 人）：本指名級の候補から、その球団の見立ての将来性が高い順
func _choose_targets() -> void:
	cpu_targets = {}
	for t in teams:
		if t == user_team:
			continue
		var view: Array = []
		for c in candidates:
			if not c["hist_ikusei"]:
				view.append([c["id"], float(c["future_seen"]) + float(_team_noise[t].get(c["id"], 0.0))])
		view.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] if a[1] == b[1] else a[1] > b[1])
		var ids: Array = []
		for i in mini(_rng.randi_range(1, TARGET_COUNT_MAX), view.size()):
			ids.append(view[i][0])
		cpu_targets[t] = ids


## 仮の選手（能力値ファイルにいない候補）[{id, player}]。GameData に足して画面・試合で引けるようにする
func synthetic_players() -> Dictionary:
	var result := {}
	for c in candidates:
		if c["synthetic"]:
			result[c["id"]] = c["player"]
	return result


## 守備位置の不足の計算用：球団の今の人数（守備位置の4区分）
func set_team_counts(counts: Dictionary) -> void:
	_need = counts


# --- 1位入札 ---------------------------------------------------------------------------

## 1位が決まっていない球団
func teams_without_first() -> Array[String]:
	var result: Array[String] = []
	for t in teams:
		if first_pick_of(t).is_empty():
			result.append(t)
	return result


func first_pick_of(team: String) -> String:
	for p in picks:
		if p["team"] == team and p["round"] == 1:
			return p["id"]
	return ""


## 自球団の1位入札（FIRST の段階で、まだ1位が決まっていないとき）。だめなら理由の文
func user_bid(id: String) -> String:
	if stage != Stage.FIRST:
		return "1位の入札は終わりました"
	if not first_pick_of(user_team).is_empty():
		return "1位は決まっています"
	if not by_id.has(id):
		return "候補にいない選手です"
	if not str(by_id[id]["picked_by"]).is_empty():
		return "%sが交渉権を獲得済みです" % GameData.short_name(by_id[id]["picked_by"])
	bids[user_team] = id
	return ""


## CPU球団の1位入札（まだ入れていない球団すべて）。テストや画面で入札先を見るために外からも呼べる
func cpu_first_bids() -> Dictionary:
	# 球団ごとに順に決める（順番はランダム）。先に入札した球団が多い候補ほど競合を嫌って評価を下げる
	# （自球団の入札は CPU球団には見えない）
	var order_now: Array[String] = []
	for t in teams_without_first():
		if t != user_team and not bids.has(t):
			order_now.append(t)
	for i in range(order_now.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := order_now[i]
		order_now[i] = order_now[j]
		order_now[j] = tmp
	var rivals := {}
	for t: String in bids:
		if t != user_team:
			rivals[bids[t]] = int(rivals.get(bids[t], 0)) + 1
	for t in order_now:
		var best := ""
		var best_value := -INF
		for c in _remaining():
			var v := evaluate(t, c, true) - COMPETE_PENALTY * int(rivals.get(c["id"], 0)) 				+ _rng.randfn(0.0, FIRST_BID_NOISE)
			if v > best_value:
				best_value = v
				best = c["id"]
		bids[t] = best
		rivals[best] = int(rivals.get(best, 0)) + 1
	return bids


## 入札を締めて交渉権を決める（重複は抽選）。自球団が入札していなければおまかせで入札する。
## 結果は last_wave。全球団の1位が決まったらウェーバーへ
func run_first_wave() -> Array[Dictionary]:
	if stage != Stage.FIRST:
		return []
	if not bids.has(user_team) and first_pick_of(user_team).is_empty():
		bids[user_team] = _best_for(user_team, true, false)
		user_auto = true
	cpu_first_bids()
	var by_cand := {}
	for t: String in bids:
		var id: String = bids[t]
		if id.is_empty():
			continue
		if not by_cand.has(id):
			by_cand[id] = []
		by_cand[id].append(t)
	last_wave.clear()
	var ids: Array = by_cand.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return by_id[a]["hyouka"] > by_id[b]["hyouka"])
	for id: String in ids:
		var bidders: Array = by_cand[id]
		bidders.sort_custom(func(a: String, b: String) -> bool: return teams.find(a) < teams.find(b))
		var winner: String = bidders[0]
		if bidders.size() > 1:
			winner = bidders[_rng.randi_range(0, bidders.size() - 1)]
			lotteries.append({"wave": wave, "id": id, "teams": bidders.duplicate(), "winner": winner})
		_record_pick(winner, id, 1, false)
		for t: String in bidders:
			last_wave.append({"team": t, "id": id, "won": t == winner, "lottery": bidders.size() > 1,
				"rivals": bidders.size()})
	bids.clear()
	wave += 1
	if teams_without_first().is_empty() or wave > MAX_WAVES or _remaining().is_empty():
		_start_waiver()
	return last_wave


## 直前の入札で抽選になった候補 [{wave, id, teams, winner}]
func last_lotteries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for lot in lotteries:
		if lot["wave"] == wave - 1:
			result.append(lot)
	return result


# --- ウェーバー・育成 --------------------------------------------------------------------

## いま指名する球団（WAIVER・IKUSEI のとき。終わっていれば空）
func current_team() -> String:
	if stage != Stage.WAIVER and stage != Stage.IKUSEI:
		return ""
	return _turn_team


func is_user_turn() -> bool:
	return current_team() == user_team and not current_team().is_empty()


## CPU球団の番なら1人指名して次へ進める。指名した記録（指名しなかった・自球団の番なら空）
func cpu_step() -> Dictionary:
	var team := current_team()
	if team.is_empty() or team == user_team:
		return {}
	var ikusei := stage == Stage.IKUSEI
	var id := ""
	if _cpu_wants_more(team, ikusei):
		id = _best_for(team, false, ikusei)
	var rec := {}
	if id.is_empty():
		_mark_done(team, ikusei)
	else:
		rec = _record_pick(team, id, round, ikusei)
		if not _cpu_wants_more(team, ikusei):
			_mark_done(team, ikusei)
	_next_turn()
	return rec


## 自球団の指名。だめなら理由の文
func user_pick(id: String) -> String:
	if not is_user_turn():
		return "自球団の指名の番ではありません"
	if not by_id.has(id):
		return "候補にいない選手です"
	if not str(by_id[id]["picked_by"]).is_empty():
		return "%sが指名済みです" % GameData.short_name(by_id[id]["picked_by"])
	var ikusei := stage == Stage.IKUSEI
	if not ikusei and user_room >= 0 and user_reg_count() >= user_room:
		return "支配下登録の上限（%d人）を超えるため本指名できません。育成で指名するか選択終了してください" % \
			LeagueRoster.ROSTER_LIMIT
	_record_pick(user_team, id, round, ikusei)
	if user_count(ikusei) >= (USER_MAX_IKUSEI if ikusei else USER_MAX_REG):
		_mark_done(user_team, ikusei)
	_next_turn()
	return ""


## 自球団の選択終了（今の段階＝本指名か育成の指名を終える）
func user_finish() -> void:
	if not is_user_turn():
		return
	_mark_done(user_team, stage == Stage.IKUSEI)
	_next_turn()


## 自球団の番のおまかせ指名（CPU球団と同じ考え方。史実の人数に達していれば選択終了）
func user_auto_pick() -> Dictionary:
	if not is_user_turn():
		return {}
	var ikusei := stage == Stage.IKUSEI
	var room_ok := ikusei or user_room < 0 or user_reg_count() < user_room
	if not room_ok or not _cpu_wants_more(user_team, ikusei):
		user_finish()
		return {}
	var id := _best_for(user_team, false, ikusei)
	if id.is_empty():
		user_finish()
		return {}
	user_pick(id)
	return picks[-1]


## 自球団の番か終わりになるまで CPU球団の指名を進める。進めた指名 [記録]
func run_until_user() -> Array[Dictionary]:
	var done: Array[Dictionary] = []
	var guard := 0
	while stage != Stage.DONE and not is_user_turn() and guard < 5000:
		guard += 1
		var rec := cpu_step()
		if not rec.is_empty():
			done.append(rec)
	return done


## 残りをすべて進める（自球団の番はおまかせ）。1位入札が残っていればそこから
func auto_complete() -> void:
	var guard := 0
	while stage == Stage.FIRST and guard < MAX_WAVES + 2:
		guard += 1
		run_first_wave()
	guard = 0
	while stage != Stage.DONE and guard < 5000:
		guard += 1
		if is_user_turn():
			user_auto = true
			user_auto_pick()
		else:
			cpu_step()


# --- 参照 -----------------------------------------------------------------------------

## 球団の指名（本指名・育成） [記録]
func picks_of(team: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for p in picks:
		if p["team"] == team:
			result.append(p)
	return result


func user_count(ikusei: bool) -> int:
	var n := 0
	for p in picks:
		if p["team"] == user_team and p["ikusei"] == ikusei:
			n += 1
	return n


func user_reg_count() -> int:
	return user_count(false)


## 指名されていない候補
func remaining() -> Array[Dictionary]:
	return _remaining()


## 段階の名前（画面の見出し）
func stage_text() -> String:
	match stage:
		Stage.FIRST:
			return "第1巡選択希望選手" if wave == 1 else "第1巡 外れ1位の入札（%d回目）" % wave
		Stage.WAIVER:
			return "第%d巡選択" % round
		Stage.IKUSEI:
			return "育成選手 第%d巡選択" % round
	return "ドラフト会議 終了"


## 並び替えの値（大きいほど上にしたいものは大きい値。名前・出身校は文字列）。key は DraftView.SORT_KEYS
static func sort_value(c: Dictionary, key: String) -> Variant:
	match key:
		"pos":
			return POS_GROUPS.find(c["pos"]) * 100 + GameData.pos_index(c.get("primary_pos"))
		"career":
			return CAREER_ORDER.find(c["career"])
		"age":
			return int(c.get("age", 0))
		"hyouka":
			return float(c["hyouka"])
		"future":
			return float(c["future_seen"])
		"school":
			return str(c["school"])
		"name":
			return str(c["name"])
		"velocity":
			return int(c.get("velocity", 0))
		"first":
			return int(c.get("first", {}).get("overall", -1))
		"yosou":
			# 有識者の予想順位（作業38。1位が上、予想に入っていない候補は下）
			return 100 - int(c["yosou"]) if int(c.get("yosou", 0)) > 0 else -1
	return int(c.get("ratings", {}).get(key, -1))


# --- 内部 ----------------------------------------------------------------------------

## 巡ごとの順番（偶数巡は order＝下位から、奇数巡はその逆）
func _base_order(at_round: int) -> Array[String]:
	var base: Array[String] = order.duplicate()
	if at_round % 2 == 1:
		base.reverse()
	if stage == Stage.WAIVER:
		for m: Dictionary in pick_moves:
			var i := base.find(m["from"]) if int(m["round"]) == at_round else -1
			if i >= 0:
				base[i] = m["to"]
	return base


## FAの補償で移った指名権を入れる（LeagueRoster.open_draft から）。旧球団（to）の本指名は1人増え、獲得球団は1人減る
func set_pick_moves(moves: Array) -> void:
	pick_moves = moves.duplicate(true)
	for m: Dictionary in pick_moves:
		if quota.has(m["to"]):
			quota[m["to"]]["reg"] += 1
		if quota.has(m["from"]):
			quota[m["from"]]["reg"] = maxi(0, int(quota[m["from"]]["reg"]) - 1)


func _done_set() -> Dictionary:
	return done_ikusei if stage == Stage.IKUSEI else done_reg


## 今の巡の index 番目以降で、まだ指名を終えていない最初の球団を今の番にする（巡の最後まで無ければ次の巡）
func _seek(index: int) -> void:
	var done := _done_set()
	if done.size() >= teams.size():
		_turn_team = ""
		return
	var base := _base_order(round)
	var guard := 0
	while guard < 1000:
		guard += 1
		if index >= base.size():
			round += 1
			base = _base_order(round)
			index = 0
		if not done.has(base[index]):
			_turn_team = base[index]
			_turn_index = index
			return
		index += 1


func _start_waiver() -> void:
	stage = Stage.WAIVER
	round = 2
	for t in teams:
		if t != user_team and not _cpu_wants_more(t, false):
			done_reg[t] = true
	if _remaining().is_empty() or done_reg.size() >= teams.size():
		_start_ikusei()
		return
	_seek(0)


func _start_ikusei() -> void:
	stage = Stage.IKUSEI
	round = 1
	for t in teams:
		if t != user_team and not _cpu_wants_more(t, true):
			done_ikusei[t] = true
	if _remaining().is_empty():
		for t in teams:
			done_ikusei[t] = true
	if done_ikusei.size() >= teams.size():
		stage = Stage.DONE
		_turn_team = ""
		return
	_seek(0)


## 次の球団へ（巡の最後なら次の巡。全球団が終えたら次の段階）
func _next_turn() -> void:
	var done := _done_set()
	if _remaining().is_empty():
		for t in teams:
			done[t] = true
	if done.size() >= teams.size():
		if stage == Stage.WAIVER:
			_start_ikusei()
		else:
			stage = Stage.DONE
			_turn_team = ""
		return
	_seek(_turn_index + 1)


func _mark_done(team: String, ikusei: bool) -> void:
	if ikusei:
		done_ikusei[team] = true
	else:
		done_reg[team] = true


func _record_pick(team: String, id: String, at_round: int, ikusei: bool) -> Dictionary:
	var c: Dictionary = by_id[id]
	c["picked_by"] = team
	c["pick_label"] = ("育成" if ikusei else "") + "%d位" % at_round
	var rec := {"team": team, "id": id, "round": at_round, "ikusei": ikusei, "label": c["pick_label"],
		"wave": wave if at_round == 1 and not ikusei else 0, "name": c["name"]}
	picks.append(rec)
	var group: String = c["pos"]
	if not _need.has(team):
		_need[team] = {}
	_need[team][group] = int(_need[team].get(group, 0)) + 1
	return rec


## CPU球団（とおまかせの自球団）がまだ指名するか：史実の人数まで
func _cpu_wants_more(team: String, ikusei: bool) -> bool:
	var q: Dictionary = quota.get(team, {"reg": 0, "ikusei": 0})
	var n := 0
	for p in picks:
		if p["team"] == team and p["ikusei"] == ikusei:
			n += 1
	return n < int(q["ikusei" if ikusei else "reg"]) and not _remaining().is_empty()


func _remaining() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for c in candidates:
		if str(c["picked_by"]).is_empty():
			result.append(c)
	return result


## 球団が一番ほしい候補。first: 1位入札（当時の評価を重く）。自球団は作戦会議の印を優先し、✕（回避）は選ばない
func _best_for(team: String, first: bool, ikusei: bool) -> String:
	if team == user_team:
		var recommended := user_recommend()
		if not recommended.is_empty():
			return recommended
	var best := ""
	var best_value := -INF
	for c in _remaining():
		if team == user_team and user_marks.get(c["id"], "") == "✕":
			continue
		var v := evaluate(team, c, first)
		if ikusei and not c["hist_ikusei"]:
			# 育成では本指名級の候補ほど入団しにくいので少し下げる（残っていれば指名はする）
			v -= 0.2
		if v > best_value:
			best_value = v
			best = c["id"]
	return best


## 作戦会議の印（DraftBoard.apply_to から）
func set_user_board(marks_by_id: Dictionary, favorite_ids: Array) -> void:
	user_marks = marks_by_id.duplicate()
	user_favorites = favorite_ids.duplicate()


## 自球団のおすすめ（作業37）：残っている候補のうち、本命（◎）の順番 → ○ → ☆ → △（同じ印の中は CPU球団と同じ
## 考え方の評価の順）。印の付いた候補が残っていなければ空
func user_recommend() -> String:
	var left := {}
	for c in _remaining():
		left[c["id"]] = c
	for id: Variant in user_favorites:
		if left.has(str(id)):
			return str(id)
	for mark: String in ["○", "☆", "△"]:
		var best := ""
		var best_value := -INF
		for id: String in left:
			if user_marks.get(id, "") != mark:
				continue
			var v := evaluate(user_team, left[id], stage == Stage.FIRST)
			if v > best_value:
				best_value = v
				best = id
		if not best.is_empty():
			return best
	return ""


## CPU球団の評価：球団ごとの見立ての違い＋当時の評価と将来性（ノイズ入り）＋守備位置の不足＋目玉の上乗せ
func evaluate(team: String, c: Dictionary, first: bool) -> float:
	var v: float = float(_team_noise.get(team, {}).get(c["id"], 0.0))
	if first:
		var hyouka_z := (float(c["hyouka"]) - 1.5) / 1.2
		v += FIRST_FUTURE_WEIGHT * float(c["future_seen"]) + FIRST_HYOUKA_WEIGHT * hyouka_z
	else:
		if _scale.is_empty():
			_compute_scale()
		var share: float = CPU_HYOUKA_SHARE[DIFFICULTY]
		v += share * _z(c, "hyouka") + (1.0 - share) * _z(c, "future_seen")
	if (first or round <= TARGET_ROUNDS) and c["id"] in cpu_targets.get(team, []):
		v += TARGET_BONUS
	if c.get("mlb_intent", false) and (team == user_team or not _team_dare.get(team, {}).has(c["id"])):
		v -= MlbPersuasion.CPU_AVOID  # メジャー志望はふだん避ける（自球団のおまかせも）
	if c.get("two_way", {}).get("active", false):
		var tw_type: String = str(c.get("two_way", {}).get("type", ""))
		match tw_type:
			"A": v += 0.45
			"B", "C": v += 0.20
			"D": v += 0.15
	return v + _need_bonus(team, c["pos"])


func _z(c: Dictionary, key: String) -> float:
	var s: Array = _scale[key]
	return (float(c[key]) - float(s[0])) / float(s[1])


func _need_bonus(team: String, group: String) -> float:
	var counts: Dictionary = _need.get(team, {})
	var total := 0
	for g: String in counts:
		total += int(counts[g])
	if total <= 0:
		return 0.0
	var target: float = total * float(NEED_SHARE.get(group, 0.2))
	if target <= 0.0:
		return 0.0
	var gap: float = (target - float(counts.get(group, 0))) / target
	return clampf(gap * NEED_WEIGHT, NEED_MIN, NEED_MAX)


## 候補の表示用の項目（年齢・能力・紹介文）
func _fill_profile(c: Dictionary, p: Dictionary) -> void:
	if p.is_empty():
		p = GameData.player(c["id"])
	c["primary_pos"] = p.get("primary_pos", c["pos"]) if p.get("primary_pos") != null else c["pos"]
	var age := FreeAgency.age_of(p, year)
	c["age_known"] = age > 0
	var ama0: Variant = p.get("amateur")
	if ama0 is Dictionary and ama0.get("fictional", false):
		# 架空の候補は入団する年（翌年）の4月1日時点の年齢（高校18・大学22・社会人は入社の年に合わせた21〜26、独立19〜25）
		age = Growth.age_at(p, year + 1)
		c["age_known"] = age > 0
	elif age <= 0:
		age = 18 if c["career"] == "高校生" else (22 if c["career"] == "大学生" else 0)
	c["age"] = age
	var ratings := {}
	var bat: Variant = p.get("batting")
	if bat is Dictionary and bat.get("ratings") is Dictionary:
		for k: String in ["meet", "power", "eye", "speed", "arm", "defense"]:
			var r: Variant = bat["ratings"].get(k)
			if r is Dictionary and r.get("value") != null:
				ratings[k] = int(r["value"])
	var pit: Variant = p.get("pitching")
	c["velocity"] = 0
	if pit is Dictionary:
		if pit.get("ratings") is Dictionary:
			for k: String in ["overall", "stamina", "k9", "bb9"]:
				var r: Variant = pit["ratings"].get(k)
				if r is Dictionary and r.get("value") != null:
					ratings[k] = int(r["value"])
		if pit.get("velocity") is Dictionary:
			c["velocity"] = int(pit["velocity"].get("kmh", 0))
	c["ratings"] = ratings
	var ama: Variant = p.get("amateur")
	c["two_way"] = ama.get("two_way", {}) if ama is Dictionary and ama.get("two_way") is Dictionary else p.get("two_way", {})
	if bool(c["two_way"].get("active", false)):
		if c["pitcher"]:
			var sub_bat: Variant = p.get("batting")
			if sub_bat is Dictionary and sub_bat.get("ratings") is Dictionary:
				var b_rat := {}
				for k: String in ["meet", "power", "eye", "speed", "defense", "arm"]:
					var r: Variant = sub_bat["ratings"].get(k)
					if r is Dictionary and r.get("value") != null:
						b_rat[k] = int(r["value"])
				c["two_way_bat"] = b_rat
		else:
			var sub_pit: Variant = p.get("pitching")
			if sub_pit is Dictionary:
				var p_rat := {}
				if sub_pit.get("ratings") is Dictionary:
					for k: String in ["overall", "stamina", "k9", "bb9"]:
						var r: Variant = sub_pit["ratings"].get(k)
						if r is Dictionary and r.get("value") != null:
							p_rat[k] = int(r["value"])
				if sub_pit.get("velocity") is Dictionary:
					p_rat["velocity"] = int(sub_pit["velocity"].get("kmh", 140))
				c["two_way_pit"] = p_rat
	c["intro"] = str(ama["intro"]) if ama is Dictionary and ama.get("intro") is String else intro_text(c)
	var honors := AmateurTournament.summary(GameState.amateur_results, year, c["name"], c["school"])
	if not honors.is_empty():
		c["intro"] += "\n" + honors


## 1年目の能力（入団1年目のシーズン後＝generated/ratings/<入団年>_post.json の値。ノイズなし。作業13）を
## c["first"] に入れる：{status（"1軍"・"2軍"＝2軍の成績だけで動いた・"なし"＝出場なし／データなし）, overall,
## ratings（キー → 値）, velocity, partial（入団年がシーズン途中のデータ）}
func _fill_first_years() -> void:
	var path := GameData.find_ratings_path(year + 1, "post")
	# 史実の無い年（成長で作った能力値 "synthetic:<年>"）は1年目の答えが無い（下で「未来」にする）
	var readable := not path.is_empty() and not path.begins_with("synthetic:") and year + 1 <= LAST_HISTORY_YEAR
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if readable else null
	var by_id_post := {}
	var by_name_post := {}
	if parsed is Dictionary:
		for p: Dictionary in parsed.get("players", []):
			by_id_post[p["id"]] = p
			by_name_post[LeagueRoster.norm_name(str(p.get("name", "")))] = p
	for c in candidates:
		if year + 1 > LAST_HISTORY_YEAR:
			c["first"] = {"status": "未来", "overall": -1, "ratings": {}, "velocity": 0, "partial": false}
			continue
		var p: Dictionary = by_id_post.get(c["id"], {})
		if p.is_empty() and c["synthetic"]:
			p = by_name_post.get(LeagueRoster.norm_name(c["name"]), {})
			if not str(p.get("draft", "")).begins_with("%d年" % year):
				p = {}
		c["first"] = first_year_of(p, c["pitcher"], year + 1 == IN_PROGRESS_YEAR)


## 能力値ファイルの選手から1年目の能力（_fill_first_years の形）
static func first_year_of(p: Dictionary, pitcher: bool, partial: bool) -> Dictionary:
	var result := {"status": "なし", "overall": -1, "ratings": {}, "velocity": 0, "partial": partial}
	var part: Variant = p.get("pitching" if pitcher else "batting")
	if not part is Dictionary or not part.get("ratings") is Dictionary:
		return result
	var sample: Dictionary = part.get("sample", {}) if part.get("sample") is Dictionary else {}
	var first_team := float(sample.get("outs_1" if pitcher else "pa_1", 0.0))
	var farm := float(sample.get("outs_2" if pitcher else "pa_2", 0.0))
	if first_team <= 0.0 and farm <= 0.0:
		return result
	result["status"] = "1軍" if first_team > 0.0 else "2軍"
	var keys: Array = FIRST_PITCH_KEYS if pitcher else FIRST_BAT_WEIGHTS.keys() + ["arm"]
	for k: String in keys:
		var r: Variant = part["ratings"].get(k)
		if r is Dictionary and r.get("value") != null:
			result["ratings"][k] = int(r["value"])
	if pitcher:
		result["overall"] = int(result["ratings"].get("overall", -1))
		if part.get("velocity") is Dictionary:
			result["velocity"] = int(part["velocity"].get("kmh", 0))
	else:
		var total := 0.0
		for k: String in FIRST_BAT_WEIGHTS:
			total += FIRST_BAT_WEIGHTS[k] * int(result["ratings"].get(k, 45))
		result["overall"] = roundi(total)
	return result


## 簡単な紹介文（アマ時代のニュースのデータが無いので、出身・守備位置・球速程度）
static func intro_text(c: Dictionary) -> String:
	var school: String = c["school"]
	if c["pitcher"]:
		if int(c.get("velocity", 0)) > 0:
			return "%sの投手、最速%dkm" % [school, int(c["velocity"])]
		return "%sの投手" % school
	return "%sの%s" % [school, c["pos"]]


## 能力値ファイルにいない候補の仮の選手：同じ守備位置の区分で当時の評価が近い候補の能力を写す
func _synthetic_player(c: Dictionary, entries: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_gap := INF
	for o in candidates:
		if o["synthetic"] or o["pos"] != c["pos"] or not entries.has(o["id"]):
			continue
		var gap: float = absf(float(o["hyouka"]) - float(c["hyouka"])) + (0.5 if o["career"] != c["career"] else 0.0)
		if gap < best_gap:
			best_gap = gap
			best = entries[o["id"]]
	var p: Dictionary = best.duplicate(true) if not best.is_empty() else _blank_player(c)
	p["id"] = c["id"]
	p["provisional_id"] = true
	p["name"] = c["name"]
	p["team"] = c["hist_team"]
	p["hist_team"] = c["hist_team"]
	p["team_id"] = null
	p["birth"] = null
	p["draft"] = "%d年ドラフト%s" % [year, c["hist_label"]]
	p["career"] = c["school"]
	p["synthetic_draft"] = true
	if p.get("pitching") is Dictionary and p["pitching"].get("sample") is Dictionary:
		p["pitching"]["sample"] = {"outs_1": 0.0, "outs_2": 0.0}
	if p.get("batting") is Dictionary and p["batting"].get("sample") is Dictionary:
		p["batting"]["sample"] = {"pa_1": 0.0, "pa_2": 0.0}
	return p


static func _blank_player(c: Dictionary) -> Dictionary:
	var r := {"value": 50, "rank": "D"}
	var p := {"is_pitcher": c["pitcher"], "primary_pos": c["pos"], "throws": null, "bats": null,
		"height": null, "weight": null, "league": null,
		"batting": {"ratings": {"meet": r.duplicate(), "power": r.duplicate(), "eye": r.duplicate(),
			"speed": r.duplicate(), "defense": r.duplicate()}, "detail": {}, "sample": {"pa_1": 0.0, "pa_2": 0.0},
			"trajectory": 2},
		"pitching": null, "fielding": {}}
	if c["pitcher"]:
		p["pitching"] = {"ratings": {"overall": r.duplicate(), "stamina": r.duplicate(), "k9": r.duplicate(),
			"bb9": r.duplicate(), "hr9": r.duplicate()}, "abilities": [], "role": "救援", "detail": {},
			"velocity": {"kmh": 140, "source": "provisional"}, "sample": {"outs_1": 0.0, "outs_2": 0.0}}
	return p


func _future_value(entry: Dictionary, hyouka: float) -> float:
	var hist := float(entry.get("score", FUTURE_NONE)) if not entry.is_empty() else FUTURE_NONE
	var years := float(data_through - year - 1)
	var w := clampf(years / FUTURE_FULL_YEARS, 0.0, 1.0)
	var guess: float = FUTURE_FROM_HYOUKA[0] + FUTURE_FROM_HYOUKA[1] * hyouka
	if not entry.is_empty() and w < 1.0:
		# 少ない年数でも史実の成績が当時の評価の見込みより良ければそちらを使う
		return maxf(lerpf(guess, hist, w), hist)
	return lerpf(guess, hist, w)


func _load_future() -> Dictionary:
	var parsed: Variant = GameData.read_generated("draft_future.json")
	if not parsed is Dictionary:
		data_through = year + 1
		return {}
	data_through = int(parsed.get("data_through", year + 1))
	return parsed.get("years", {}).get(str(year), {})


# --- メジャー志望の説得（作業26） ---------------------------------------------------------

## 指名の記録（その候補の）。無ければ空
func pick_of(id: String) -> Dictionary:
	for rec in picks:
		if rec["id"] == id:
			return rec
	return {}


## 自球団が指名したメジャー志望の選手で、まだ説得していない（できる）か
func can_persuade(id: String) -> bool:
	var rec := pick_of(id)
	return stage == Stage.DONE and not resolved and not rec.is_empty() and rec["team"] == user_team 		and bool(by_id[id].get("mlb_intent", false)) and not talks.has(id)


## 自球団が指名して、まだ説得していないメジャー志望の選手（ドラフト会議が終わっても、これが残っていれば入団の
## 処理を待つ。可変ボタンで次へ進むと約束なしの扱いで決まる）
func pending_talks() -> Array[String]:
	var result: Array[String] = []
	for rec in picks:
		if can_persuade(rec["id"]):
			result.append(rec["id"])
	return result


## 自球団の説得（1人1回）。promise：ポスティングを認める年数（0＝約束なし）。{ok, chance, text}
func persuade(id: String, promise: int) -> Dictionary:
	if not can_persuade(id):
		return {"ok": false, "chance": 0.0, "text": "説得できる選手ではありません"}
	var t := _talk(id, user_team, promise)
	var name: String = by_id[id]["name"]
	if t["ok"]:
		var cond := "（%d年後のポスティングを約束）" % promise if promise > 0 else ""
		return {"ok": true, "chance": t["chance"], "text": "%sの説得に成功！入団します%s" % [name, cond]}
	return {"ok": false, "chance": t["chance"], "text": "%sの説得は失敗しました。メジャーへ挑戦します。" % name}


## まだ決まっていない交渉をすべて決める（ドラフト会議の結果で入団させる前に LeagueRoster.apply_draft から）。
## 自球団で説得しなかった選手は約束なし、CPU球団は CPU_PROMISE_RATE の確率で約束を付ける
func resolve_talks() -> void:
	for rec in picks:
		var id: String = rec["id"]
		if talks.has(id) or not bool(by_id[id].get("mlb_intent", false)):
			continue
		var promise := 0
		if rec["team"] != user_team and _rng.randf() < MlbPersuasion.CPU_PROMISE_RATE:
			promise = MlbPersuasion.CPU_PROMISE_YEARS
		_talk(id, rec["team"], promise)


func _talk(id: String, team: String, promise: int) -> Dictionary:
	var chance := MlbPersuasion.chance(pick_of(id), promise)
	var roll := force_roll if force_roll >= 0.0 else _rng.randf()
	var t := {"team": team, "promise": promise, "chance": chance, "ok": roll < chance}
	talks[id] = t
	return t


# --- 静的 ----------------------------------------------------------------------------

## その年のドラフト会議の指名一覧（drafts.json の当年秋の分。本指名が先、球団・順位順）。史実の無い年は
## アマ選手の候補（amateur_rows）
static func draft_rows(draft_year: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var parsed: Variant = GameData.read_data("%d/drafts.json" % (draft_year + 1))
	if not parsed is Array:
		return amateur_rows(draft_year) if draft_year > LAST_HISTORY_YEAR else result
	for d: Dictionary in parsed:
		if int(d.get("draft_year", 0)) == draft_year and not str(d.get("name", "")).begins_with("("):
			result.append(d)
	return result


## 史実の無い年のドラフト候補（data/amateur/<年>.json）を drafts.json の行の形にしたもの。
## 球団（code）・順位は無く、amateur: true・grade（報道での格付け）・fictional（架空の選手）が付く
static func amateur_rows(draft_year: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var parsed: Variant = GameData.read_data("amateur/%d.json" % draft_year)
	if not parsed is Dictionary:
		return fictional_rows(draft_year)
	for a: Dictionary in parsed.get("players", []):
		var scout: Dictionary = a.get("scout", {}) if a.get("scout") is Dictionary else {}
		result.append({"draft_year": draft_year, "name": a["name"], "pos": a.get("pos", ""),
			"school": a.get("school", ""), "code": "", "round": "", "ikusei": false, "amateur": true,
			"grade": str(scout.get("grade", a.get("eval_rank", "C"))), "fictional": bool(a.get("fictional", false))})
	return result


## 架空のドラフト候補（作業22・32。GameData.draft_classes の選手）を drafts.json の行の形にしたもの。
## amateur_rows の形に、as_round・as_ikusei・bids（当時の評価の順位・競合数）・future_score（将来性の点）・
## reincarnation（転生のもと）が付く
static func fictional_rows(draft_year: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for p: Dictionary in GameData.draft_classes.get(draft_year, []):
		var am: Dictionary = p["amateur"]
		result.append({"draft_year": draft_year, "name": p["name"], "pos": _pos_of(p), "school": am["school"],
			"code": "", "round": "", "ikusei": false, "amateur": true, "grade": str(am["grade"]), "fictional": true,
			"as_round": int(am["as_round"]), "as_ikusei": bool(am["as_ikusei"]), "bids": int(am.get("bids", 1)),
			"future_score": float(am["future_score"]), "reincarnation": am.get("reincarnation", {}),
			"category": str(am.get("category", "")),
			"two_way": am.get("two_way", p.get("two_way", {}))})
	return result


static func _pos_of(p: Dictionary) -> String:
	if p.get("is_pitcher", false):
		return "投手"
	var pos := str(p.get("primary_pos", ""))
	if pos == "捕手":
		return "捕手"
	return "外野手" if pos.contains("外野") or pos in ["左翼手", "中堅手", "右翼手"] else "内野手"


## 1巡目の競合数（名前 → {bids, wave}）
static func _first_round_info(draft_year: int) -> Dictionary:
	var result := {}
	var parsed: Variant = GameData.read_data("draft_first_round.json")
	if parsed is Array:
		for d: Dictionary in parsed:
			if int(d.get("draft_year", 0)) == draft_year:
				result[LeagueRoster.norm_name(str(d.get("name", "")))] = d
	return result


static func hist_team_of(d: Dictionary, draft_year: int) -> String:
	var short: String = TEAM_CODES.get(str(d.get("code", "")), "")
	return GameData.resolve_team(short, draft_year) if not short.is_empty() else ""


## 候補の行の経歴。架空の候補は区分（独立・専門学校も分ける）、ほかは出身校の名前から
static func career_of_row(d: Dictionary) -> String:
	if CATEGORY_CAREER.has(str(d.get("category", ""))):
		return CATEGORY_CAREER[d["category"]]
	return career_of(str(d.get("school", "")))


static func career_of(school: String) -> String:
	if school.ends_with("高") or "高校" in school or "高等学校" in school:
		return "高校生"
	if "大学" in school or school.ends_with("大"):
		return "大学生"
	return "社会人"


static func round_number(text: String) -> int:
	var digits := ""
	for ch in text:
		if ch.is_valid_int():
			digits += ch
		elif not digits.is_empty():
			break
	return int(digits) if not digits.is_empty() else 1


static func hyouka_value(r: int, ikusei: bool, bid_count: int, rebid: bool) -> float:
	if ikusei:
		return float(IKUSEI_VALUE.get(r, LATE_IKUSEI_VALUE))
	if r == 1:
		if rebid:
			return REBID_BASE + REBID_PER_BID * maxi(0, bid_count - 1)
		return FIRST_BASE + FIRST_PER_BID * maxi(0, bid_count - 1)
	return float(ROUND_VALUE.get(r, LATE_ROUND_VALUE))


## 有識者の格付け（S〜D）を当時の評価の値に（GRADE_AS_PICK の順位・競合数として）
static func grade_value(grade: String) -> float:
	var as_pick: Array = GRADE_AS_PICK.get(grade, GRADE_AS_PICK["C"])
	return hyouka_value(as_pick[0], as_pick[1] < 0, maxi(as_pick[1], 1), false)


static func rank_of(value: float, thresholds: Array) -> String:
	for i in thresholds.size():
		if value >= float(thresholds[i]):
			return RANK_LETTERS[i]
	return RANK_LETTERS[-1]


# --- セーブ／ロード ----------------------------------------------------------------------

## 途中経過（候補・指名・入札・抽選・順番・乱数）をすべて持つ。仮の候補の選手データ（candidates[].player）も含む
func to_save() -> Dictionary:
	return {
		"year": year, "user_team": user_team, "stage": stage, "teams": teams, "candidates": candidates,
		"quota": quota, "picks": picks, "wave": wave, "bids": bids, "lotteries": lotteries,
		"last_wave": last_wave, "order": order, "round": round, "turn_team": _turn_team, "turn_index": _turn_index, "pick_moves": pick_moves,
		"done_reg": done_reg, "done_ikusei": done_ikusei, "user_auto": user_auto, "user_room": user_room,
		"resolved": resolved, "data_through": data_through, "rng": SaveUtil.rng_state(_rng),
		"team_noise": _team_noise, "need": _need, "cpu_targets": cpu_targets, "talks": talks,
		"team_dare": _team_dare, "user_marks": user_marks, "user_favorites": user_favorites,
	}


static func from_save(d: Dictionary) -> Draft:
	var dr := Draft.new()
	dr.year = int(d["year"])
	dr.user_team = str(d["user_team"])
	dr.stage = int(d.get("stage", Stage.DONE)) as Stage
	dr.teams.assign(d.get("teams", []))
	dr.candidates.assign(d.get("candidates", []))
	for c in dr.candidates:
		dr.by_id[c["id"]] = c
	dr.quota = d.get("quota", {})
	dr.picks.assign(d.get("picks", []))
	dr.wave = int(d.get("wave", 1))
	dr.bids = d.get("bids", {})
	dr.lotteries.assign(d.get("lotteries", []))
	dr.last_wave.assign(d.get("last_wave", []))
	dr.order.assign(d.get("order", []))
	dr.round = int(d.get("round", 2))
	dr._turn_team = str(d.get("turn_team", ""))
	dr.pick_moves = d.get("pick_moves", [])
	dr._turn_index = int(d.get("turn_index", maxi(0, dr._base_order(dr.round).find(dr._turn_team))))
	dr.done_reg = d.get("done_reg", {})
	dr.done_ikusei = d.get("done_ikusei", {})
	dr.user_auto = bool(d.get("user_auto", false))
	dr.user_room = int(d.get("user_room", -1))
	dr.resolved = bool(d.get("resolved", false))
	dr.data_through = int(d.get("data_through", 0))
	SaveUtil.set_rng_state(dr._rng, d.get("rng", ""))
	dr._team_noise = d.get("team_noise", {})
	dr._need = d.get("need", {})
	dr.talks = d.get("talks", {})
	dr._team_dare = d.get("team_dare", {})
	dr.cpu_targets = d.get("cpu_targets", {})
	dr.user_marks = d.get("user_marks", {})
	dr.user_favorites = d.get("user_favorites", [])
	dr._compute_scale()
	return dr
