extends SceneTree
## メジャー志望の選手の指名と説得（docs/AUTORUN.md 作業26。ヘッドレスで数分）：
##   1) 成功率：強行指名の基本は10%前後、約束（3〜6年）で +30%前後、★の段階
##   2) 2026年（巨人）：織田翔希を1位で指名 → ドラフト会議が終わっても説得が済むまで入団の処理を待つ →
##      約束なしで失敗 → 入団せずメジャーへ（ゲームの NPB にいない・出来事に残る）
##   3) 2026年（巨人）：約束（3年）ありで成功 → 入団し、約束の年のオフにポスティングでメジャーへ
##   4) 2025年（DeNA）：佐々木麟太郎（海外の大学。期限は翌年7月末）も同じ交渉になり、成功すると入団する
##   5) CPU球団は史実で強行指名した球団以外はふだん避ける（メジャー志望の候補の評価が下がる）
##
##   godot --headless --path godot --script res://tests/mlb_draftee_check.gd
##
## すべて OK なら "ALL OK"、1つでも NG があれば "FAILED" を出して終了コード 1。

var _failures := 0
var _gs: Node
var _gd: Node
var _ds: GDScript
var _mp: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_ds = load("res://sim/draft.gd")
	_mp = load("res://sim/mlb_persuasion.gd")
	_check_chance()
	_check_oda(false)
	_check_oda(true)
	_check_rintaro()
	print("ALL OK" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_chance() -> void:
	print("== 成功率 ==")
	var first := {"round": 1, "ikusei": false}
	var base: float = _mp.chance(first, 0)
	_check(base >= 0.08 and base <= 0.15, "1位の強行指名・約束なし：%d%%" % roundi(base * 100))
	var promised: float = _mp.chance(first, 4)
	_check(promised - base >= 0.25 and promised - base <= 0.35, "4年後のポスティングの約束で +%d%%" % roundi(
		(promised - base) * 100))
	_check(_mp.chance(first, 3) > _mp.chance(first, 6), "短い約束ほど成功しやすい")
	_check(_mp.chance({"round": 9, "ikusei": false}, 0) < base, "下位指名は1位より少し低い")
	_check(_mp.stars(base) <= 2 and _mp.stars(promised) >= 4, "★：約束なし %d・約束あり %d" % [
		_mp.stars(base), _mp.stars(promised)])


## 2026年の織田翔希を巨人で1位指名して説得する。success：約束（3年）ありで成功させる／約束なしで失敗させる
func _check_oda(success: bool) -> void:
	var user := "読売ジャイアンツ"
	print("== 2026年 織田翔希（%s） ==" % ("約束あり・成功" if success else "約束なし・失敗"))
	var d: RefCounted = null
	var oda := ""
	for attempt in 4:
		_gs.new_game(user, 2026)
		_gs.skip_to_phase(_gs.Phase.DRAFT)
		d = _gs.draft()
		if d == null:
			break
		oda = _find(d, "織田 翔希")
		d.user_bid(oda)
		d.run_first_wave()
		if d.first_pick_of(user) == oda:
			break
	_check(d != null and not oda.is_empty() and d.by_id[oda]["mlb_intent"], "織田翔希はメジャー志望の候補")
	if d == null or d.first_pick_of(user) != oda:
		_check(false, "織田翔希を1位で獲得できない（抽選に4回外れた）")
		return
	_check(_mp.deadline_text(d.year, d.by_id[oda]["mlb_overseas"]) == "2027年3月末", "交渉期限は翌年3月末")
	d.auto_complete()
	_gs.draft_sync()
	_check(d.stage == _ds.Stage["DONE"] and not d.resolved and oda in d.pending_talks(),
		"ドラフト会議が終わっても、説得が済むまで入団の処理を待つ")
	d.force_roll = 0.2
	var promise := 3 if success else 0
	var result: Dictionary = d.persuade(oda, promise)
	_check(result["ok"] == success, "説得：%s" % result["text"])
	_check(not d.persuade(oda, 6)["ok"] or success, "説得は1人1回")
	_gs.draft_sync()
	_check(d.resolved, "説得のあとで入団の処理")
	var league: RefCounted = _gs.league
	if not success:
		_check(not league.team_of.has(oda), "失敗：入団しない")
		var logged := false
		for e: Dictionary in league.log:
			if e["kind"] == "mlb_draftee" and e["id"] == oda:
				logged = true
		_check(logged, "失敗：出来事に「メジャーへ挑戦」が残る")
		_gs.advance()
		_check(_gs.year == 2027 and not league.team_of.has(oda), "2027年の春季キャンプでも NPB にいない")
		return
	_check(league.team_of.get(oda, "") == user, "成功：巨人に入団")
	_check(int(league.posting_promise.get(oda, 0)) == 2029, "約束：2029年のオフにポスティング")
	var leaving: Array = league.depart_mlb(2029)
	var left := false
	for l: Dictionary in leaving:
		if l["id"] == oda:
			left = true
	_check(left and not league.team_of.has(oda) and league.in_mlb.has(oda), "約束の年のオフにポスティングでメジャーへ")


func _check_rintaro() -> void:
	var user := "横浜DeNAベイスターズ"
	print("== 2025年 佐々木麟太郎（%s） ==" % user)
	var d: RefCounted = null
	var rin := ""
	for attempt in 4:
		_gs.new_game(user, 2025)
		_gs.skip_to_phase(_gs.Phase.DRAFT)
		d = _gs.draft()
		if d == null:
			break
		rin = _find(d, "佐々木 麟太郎")
		d.user_bid(rin)
		d.run_first_wave()
		if d.first_pick_of(user) == rin:
			break
	_check(d != null and not rin.is_empty() and d.by_id[rin]["mlb_intent"], "佐々木麟太郎はメジャー志望の候補")
	if d == null or d.first_pick_of(user) != rin:
		_check(false, "佐々木麟太郎を1位で獲得できない（抽選に4回外れた）")
		return
	_check(_mp.deadline_text(d.year, d.by_id[rin]["mlb_overseas"]) == "2026年7月末",
		"海外の大学に在学：交渉期限は翌年7月末")
	# CPU球団の評価：史実で指名したソフトバンク以外はメジャー志望で評価が下がる
	var c: Dictionary = d.by_id[rin]
	var other := "阪神タイガース"
	var plain := c.duplicate()
	plain["mlb_intent"] = false
	_check(d.evaluate(other, c, true) < d.evaluate(other, plain, true) or d._team_dare[other].has(rin),
		"CPU球団（阪神）はメジャー志望の候補を避ける")
	d.auto_complete()
	_gs.draft_sync()
	d.force_roll = 0.0
	var result: Dictionary = d.persuade(rin, 4)
	_check(result["ok"], "約束ありで説得：%s" % result["text"])
	_gs.draft_sync()
	_check(_gs.league.team_of.get(rin, "") == user, "成功：DeNA に入団")
	_gs.advance()
	_check(_gs.year == 2026 and _gs.league.team_of.get(rin, "") == user and not _gd.call("player", rin).is_empty(),
		"2026年の春季キャンプで DeNA にいる（能力値データあり）")


func _find(d: RefCounted, name: String) -> String:
	for c: Dictionary in d.candidates:
		if c["name"] == name:
			return c["id"]
	return ""


func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["OK" if ok else "NG", label])
	if not ok:
		_failures += 1
