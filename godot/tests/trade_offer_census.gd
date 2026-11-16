extends SceneTree
## トレードの打診の集計（作業87。ヘッドレス、数年分で数分〜十数分。full には入らない：名前が *_check ではない）。
## 開始年から years 年分を流し、自球団への打診を「全部受ける」として：
## - 年ごとの打診の件数・形（優勝争い／若手の獲得／主力どうし）・時期（シーズン中／オフ）
## - 動いた選手の水準（今の能力ランク・将来性ランク・年齢。レギュラー級か伸びしろの大きい若手が両側にいるか）
## - 自球団の損得（需要を掛けない価値：出した選手＋金銭 と 受け取った選手。受けた時点と、翌年の開幕時点）
## - 2026年以降の CPU球団どうしのトレードの件数と水準
##
##   godot --headless --path godot -s res://tests/trade_offer_census.gd -- <球団> <開始年> <年数> [accept|decline]

var _gs: Node
var _gd: Node
var _team := "阪神タイガース"
var _start := 2008
var _years := 3
var _accept := true
var _offers: Array[Dictionary] = []
var _cpu: Array[Dictionary] = []
var _seen_cpu := {}
var _rows := {}
## クラス名はテストのスクリプトから直接使えない（自動読み込みより先に読まれる）ので実行時に読む
var _depth: GDScript
var _to: GDScript
var _fa: GDScript


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_team = args[0]
	if args.size() > 1:
		_start = int(args[1])
	if args.size() > 2:
		_years = int(args[2])
	if args.size() > 3:
		_accept = args[3] != "decline"
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_depth = load("res://sim/depth.gd")
	_to = load("res://sim/trade_offers.gd")
	_fa = load("res://sim/free_agency.gd")
	var t0 := Time.get_ticks_msec()
	_gs.new_game(_team, _start)
	var end_year := _start + _years
	while _gs.year < end_year:
		var y: int = _gs.year
		if _gs.phase == _gs.Phase.SEASON:
			if _gs.day > _gs.season_last_day():
				_gs.advance_through(_gs.day)
			else:
				_gs.advance_through(_gs.day)
		else:
			_gs.advance()
		_take_offers()
		_take_cpu()
		if _gs.year != y:
			print("… %d年が終わった（%.0f秒）" % [y, (Time.get_ticks_msec() - t0) / 1000.0])
	_report()
	quit(0)


func _take_offers() -> void:
	for o: Dictionary in _gs.trade_offers_pending():
		var rec := _describe(o, _gs.team)
		rec["when"] = "シーズン中" if _gs.phase == _gs.Phase.SEASON else _gs.phase_name()
		rec["date"] = _gs.date_text()
		if _accept:
			var r: Dictionary = _gs.trade_offer_accept(int(o["id"]))
			rec["accepted"] = r["ok"]
		else:
			_gs.trade_offer_decline(int(o["id"]))
			rec["accepted"] = false
		_offers.append(rec)
		print("打診 %s %s：%s ⇔ %s（%s）%s　[%s ⇔ %s] 価値 出%.0f／受%.0f 相手の比%.2f" % [rec["year"], rec["date"],
			o["give_text"], o["get_text"], o["kind"], "受けた" if rec["accepted"] else "断った",
			" ".join(rec["give"]), " ".join(rec["get"]), rec["value_give"], rec["value_get"], rec["ratio"]])


## CPU球団どうし（ニュースの「トレードが成立」で自球団が関わらないもの）
func _take_cpu() -> void:
	if _gs.news == null:
		return
	for a: Dictionary in _gs.news.articles:
		if a["kind"] != "trade" or _seen_cpu.has(a["id"]) or _gs.team in a["teams"] \
				or not str(a["headline"]).contains("成立"):
			continue
		_seen_cpu[a["id"]] = true
		var levels: Array[String] = []
		for id: Variant in a["players"]:
			levels.append(_level(str(id)))
		_cpu.append({"year": _gs.year, "headline": a["headline"], "body": a["body"], "levels": levels})
		print("CPU %d：%s %s [%s]" % [_gs.year, a["headline"], a["body"], " ".join(levels)])


func _describe(o: Dictionary, _t: String) -> Dictionary:
	var give_l: Array[String] = []
	var get_l: Array[String] = []
	var give_key := false
	var get_key := false
	for id: String in o["give"]:
		give_l.append(_level(id))
		give_key = give_key or _is_key(id)
	for id: String in o["get"]:
		get_l.append(_level(id))
		get_key = get_key or _is_key(id)
	return {"year": _gs.year, "kind": o["kind"], "give": give_l, "get": get_l, "money": int(o["money"]),
		"both_key": give_key and get_key, "ratio": float(o["ratio"]), "neutral": float(o["neutral"]),
		"value_give": float(o["value_give"]) + int(o["money"]), "value_get": float(o["value_get"]),
		"give_ids": o["give"].duplicate(), "get_ids": o["get"].duplicate()}


func _is_key(id: String) -> bool:
	var p: Dictionary = _gd.player(id)
	var now: float = _depth.now_score(p)
	var fut: float = _gs.trade_future(id)
	var age: int = _fa.age_of(p, _gs.year)
	return now >= _to.REGULAR_SCORE or (age > 0 and age <= _to.PROSPECT_AGE
		and fut >= _to.PROSPECT_FUTURE and fut - now >= _to.PROSPECT_RISE)


## 「今B/将A 24歳 投」
func _level(id: String) -> String:
	var p: Dictionary = _gd.player(id)
	if p.is_empty():
		return "?"
	var now: float = _depth.now_score(p)
	var fut: float = _gs.trade_future(id)
	return "今%s/将%s %d歳%s" % [_depth.rank_of(now), _depth.rank_of(fut), _fa.age_of(p, _gs.year),
		"投" if p.get("is_pitcher", false) else "野"]


func _report() -> void:
	print("\n== 自球団への打診（%s・%d〜%d年・%s） ==" % [_team, _start, _start + _years - 1,
		"全部受ける" if _accept else "全部断る"])
	var by_year := {}
	for r: Dictionary in _offers:
		by_year[r["year"]] = int(by_year.get(r["year"], 0)) + 1
	for y in range(_start, _start + _years + 1):
		print("%d年：%d件" % [y, int(by_year.get(y, 0))])
	var kinds := {}
	var when := {}
	var weak := 0
	var give_v := 0.0
	var get_v := 0.0
	for r: Dictionary in _offers:
		kinds[r["kind"]] = int(kinds.get(r["kind"], 0)) + 1
		when[r["when"]] = int(when.get(r["when"], 0)) + 1
		if not r["both_key"]:
			weak += 1
		if r.get("accepted", false):
			give_v += float(r["value_give"])
			get_v += float(r["value_get"])
	print("形：%s　時期：%s" % [kinds, when])
	print("両側にレギュラー級か有望な若手がいない話：%d件" % weak)
	print("受けた話の価値の合計（需要を掛けない目）：出した %.0f万円（金銭こみ）／受け取った %.0f万円（比 %.2f）" % [
		give_v, get_v, get_v / maxf(give_v, 1.0)])
	print("\n== CPU球団どうし ==")
	var cby := {}
	for r: Dictionary in _cpu:
		cby[r["year"]] = int(cby.get(r["year"], 0)) + 1
	print("年ごと：%s（計%d件）" % [cby, _cpu.size()])
