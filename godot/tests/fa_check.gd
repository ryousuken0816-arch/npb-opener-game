extends SceneTree
## FA・ポスティングの確認（ヘッドレス可。ウィンドウ付きで出力先を渡すとスクショも保存）。
## 1) 2008年から2012年のオフまで（2013年の開幕まで）進め、毎年のオフに次を調べる：
##    - FA宣言が起き、締め切りで移籍（CPU球団どうしを含む）・残留が決まる。移籍した選手は翌年の開幕で新しい球団の編成にいる
##    - 自球団の入札（上限の額・5年）で他球団の選手を獲得できる
##    - 自球団の選手のFA宣言（無ければ資格のある選手に宣言させる）を引き留められる。決まった年俸は契約年数のあいだ据え置き
##    - オフの日付表示（「YYYY年 オフ」）と、翌年の開幕で年・日付が進む
##    - 選手の好み（作業36）：1〜2個で、ひとことが出る。出身校の地域。好み（リーグ・地元）を満たす球団が同じ条件なら選ばれる
## 2) 2011年オフ、日本ハムを自球団にしてダルビッシュ（ポスティング）を引き留める操作を、ハブ → 可変ボタン →
##    FA・ポスティングの画面（作業36：(1) 選手×球団の表で LB/RB のセ・パ、マスの「交」「残」「✕」「米」、Ⓐで印、名前札で
##    選手詳細、「OK」で (2) 交渉の部屋、「変更する」→ 年俸の札で ◀▶、「引き留める」、Ⓑで表へ）でキーボード・マウスで行う。
##    成功（乱数を固定）：日本ハムに残り、2012年はメジャーにいた年の能力値（mlb_players）で編成に入る。史実の復帰・引退が
##    二重に起きず、2013年の開幕にも日本ハムにいる。失敗：メジャーへ行き、2012年の開幕にはいない
##
##   godot --headless --path godot --script res://tests/fa_check.gd -- [出力先]

const DARVISH := "61965110"
const NIPPON_HAM := "北海道日本ハムファイターズ"
const USER_TEAM := "読売ジャイアンツ"
const LAST_OFF := 2012

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node
var _pref_target := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_check_offseasons()
	await _check_darvish(true)
	await _check_darvish(false)
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


# --- 1) 2008〜2012年のオフ ---------------------------------------------------------------

func _check_offseasons() -> void:
	print("== 2008〜%d年のオフ（自球団：%s） ==" % [LAST_OFF, USER_TEAM])
	# 毎年上限の額で獲得するので、ここでは予算上限を外す（予算の効き方は tests/contract_check.gd で確かめる）
	var contract_renewal: GDScript = load("res://sim/contract_renewal.gd")
	contract_renewal.set_budget_override(USER_TEAM, 10000000)
	_gs.new_game(USER_TEAM)
	var league: Variant = _gs.league
	var total_declared := 0
	var cpu_moves := 0
	var bought := 0
	var kept := 0
	while true:
		var y: int = _gs.year
		_gs.advance_through(_gs.season_last_day())
		_check(_gs.phase == _gs.Phase.AWARDS and _gs.date_text() == "%d年 オフ" % y,
				"%d年 シーズン終了で日付は「%s」" % [y, _gs.date_text()])
		_gs.advance()
		_check(_gs.phase == _gs.Phase.FA_TRADE, "%d年オフ：FA・トレード・ポスティングへ" % y)
		var f: Variant = _gs.fa()
		_check(f != null and _gs.fa_open() and _gs.button_text() == "FA・移籍交渉",
				"%d年オフ：FAの交渉中（ボタン=%s）" % [y, _gs.button_text()])
		total_declared += f.declared.size()
		var names: Array[String] = []
		for id: String in f.declared:
			names.append("%s(%s)" % [league.names.get(id, id), _gd.short_name(f.info[id]["from"])])
		print("%d年オフ FA宣言 %d人：%s" % [y, f.declared.size(), "、".join(names)])
		_check_prefs(f, league, y)
		# 自球団の入札：他球団の宣言選手のうち一番能力の高い選手に上限の額・5年
		var target := _best_other(f, league)
		if not target.is_empty():
			var r: Array = f.bid_range(target)
			_check(_gs.fa_offer(target, r[1], 5).is_empty(), "%d年オフ：%sに提示できる" % [y, league.names[target]])
			_check(f.stars(league, target, r[1], 5) >= 4, "%d年オフ：上限の提示の成功率は高い（★%d）" % [
				y, f.stars(league, target, r[1], 5)])
		# 自球団の選手の引き留め（宣言が無ければ資格のある選手に宣言させる）
		var own := _own_declared(f)
		if own.is_empty():
			own = _force_own_declare(f, league)
		if not own.is_empty():
			var r: Array = f.bid_range(own)
			_check(_gs.fa_offer(own, r[1], 3).is_empty(), "%d年オフ：自球団の%sを引き留める提示" % [y, league.names[own]])
		_check(not _gs.fa_offer("00000000", 1000, 1).is_empty(), "宣言していない選手には提示できない")
		_gs.fa_resolve()
		# 自球団が関わるFAの補償（作業18、tests/fa_comp_check.gd）はおまかせで決める
		if _gs.comp_open():
			_check(_gs.button_text() == "FAの補償", "%d年オフ：自球団が関わる補償があれば可変ボタンは「FAの補償」" % y)
			_gs.comp_resolve()
		_check(f.resolved and not _gs.fa_open() and _gs.button_text() == "契約更改へ",
				"%d年オフ：締め切ると次は契約更改（%s）" % [y, _gs.button_text()])
		_check(not _gs.fa_offer(target if not target.is_empty() else own, 1000, 1).is_empty(),
				"締め切ったあとは提示できない")
		if not _pref_target.is_empty():
			_check(league.team_of.get(_pref_target, "") == "阪神タイガース",
					"同じ条件なら好みを満たす阪神を選ぶ（%s）" % _gd.short_name(league.team_of.get(_pref_target, "")))
			_pref_target = ""
		var moved_to := {}
		for res: Dictionary in f.results:
			print("  %s：%s → %s %s・%d年（入札%d球団%s）" % [league.names[res["id"]], _gd.short_name(res["from"]),
				_gd.short_name(res["to"]), Salary.text(res["amount"]), res["years"], res["bidders"],
				"、自球団も" if res["user_bid"] else ""])
			_check(league.team_of.get(res["id"], "") == res["to"], "%sの所属が結果どおり" % league.names[res["id"]])
			_check(league.salary_of(res["id"]) == res["amount"], "%sの来季の年俸が結果どおり" % league.names[res["id"]])
			if res["to"] != res["from"]:
				moved_to[res["id"]] = res
				if res["to"] != USER_TEAM and res["from"] != USER_TEAM:
					cpu_moves += 1
		if not target.is_empty():
			var ok: bool = league.team_of.get(target, "") == USER_TEAM
			_check(ok, "%d年オフ：入札で%sを獲得" % [y, league.names[target]])
			if ok:
				bought += 1
		if not own.is_empty():
			var ok: bool = league.team_of.get(own, "") == USER_TEAM
			_check(ok, "%d年オフ：%sを引き留めた" % [y, league.names[own]])
			if ok:
				kept += 1
		var contract := {}
		for id: String in moved_to:
			contract[id] = league.salary_of(id)
		while _gs.phase != _gs.Phase.SEASON:
			_gs.advance()
		_check(_gs.year == y + 1 and _gs.date_text().begins_with("%d年 " % (y + 1)) and _gs.month_text() != "オフ",
				"%d年の開幕へ（%s）" % [y + 1, _gs.date_text()])
		for id: String in moved_to:
			var res: Dictionary = moved_to[id]
			if not league.team_of.has(id):
				continue  # その後に引退など
			var sim: SimTeam = _gs.season.teams.get(league.team_of[id])
			_check(sim != null and sim.by_id.has(id), "%d年開幕：%sが%sの編成にいる" % [
				y + 1, league.names[id], _gd.short_name(league.team_of[id])])
			if int(league.contract_until.get(id, 0)) >= y + 1:
				_check(league.salary_of(id) == contract[id], "%sの年俸は契約年数のあいだ据え置き" % league.names[id])
		if y >= LAST_OFF:
			break
	contract_renewal.set_budget_override(USER_TEAM, -1)
	print("FA宣言 計%d人、CPU球団どうしの移籍 %d人、自球団の獲得 %d人、引き留め %d人" % [
		total_declared, cpu_moves, bought, kept])
	_check(total_declared >= 10, "5年でFA宣言が10人以上（%d人）" % total_declared)
	_check(cpu_moves >= 1, "CPU球団どうしのFA移籍が起きる（%d人）" % cpu_moves)
	_check(bought >= 3, "自球団の入札で獲得できる（%d人）" % bought)
	_check(kept >= 3, "自球団の選手を引き留められる（%d人）" % kept)
	var fa_logs := 0
	for e: Dictionary in league.log:
		if e["kind"] in ["fa_move", "fa_stay", "fa_declare"]:
			fa_logs += 1
	_check(fa_logs > 0, "FAの出来事が記録される（%d件）" % fa_logs)


## 選手の好み（作業36）：全員1〜2個・ひとことが出る。好み（セ・リーグ＋地元の関西）を持たせた選手に阪神と楽天が
## 同じ条件で入札すると阪神を選ぶ（好み2つで +16%、相性の揺れは最大 +10%）
func _check_prefs(f: Variant, league: Variant, y: int) -> void:
	var ok := true
	var kinds := {}
	for id: String in f.declared:
		var prefs: Array = f.prefs_of(id)
		var words: Array = f.pref_words(id)
		if prefs.size() < 1 or prefs.size() > 2 or words.size() != prefs.size():
			ok = false
		for pref: Dictionary in prefs:
			kinds[pref["kind"]] = int(kinds.get(pref["kind"], 0)) + 1
		if f.want_years_of(id) < 1 or f.want_years_of(id) > 4:
			ok = false
	_check(ok, "%d年オフ：宣言した選手の好みは1〜2個でひとことが出る（%s）" % [y, str(kinds)])
	if y != 2008:
		return
	_check(f.region_of_career("智弁和歌山高") == "関西" and f.region_of_career("東北高 - 東北福祉大") == "東北"
			and f.region_of_career("横浜高 - 明治大") == "関東" and f.region_of_career("仙台育英高") == "東北"
			and f.region_of_career("PL学園高") == "関西" and f.region_of_career("安田学園高 - 中央大") == "",
			"出身校の地域（分からなければ空）")
	var hanshin := "阪神タイガース"
	var rakuten := "東北楽天ゴールデンイーグルス"
	var target := ""
	for id: String in f.declared:
		if f.info[id]["from"] not in [hanshin, rakuten, USER_TEAM] and id != _best_other(f, league):
			target = id
			break
	if target.is_empty():
		_check(false, "好みの確認に使う選手がいる")
		return
	var amount: int = f.info[target]["asking"]
	f.info[target]["prefs"] = [{"kind": "league", "value": "C"}, {"kind": "home", "value": "関西"}]
	f.cpu_bids[target] = [{"team": rakuten, "amount": amount, "years": 2, "need": 0.5},
		{"team": hanshin, "amount": amount, "years": 2, "need": 0.5}]
	_check(f.wants(league, target, hanshin) and not f.wants(league, target, rakuten),
			"%s：好み（セ・リーグ・地元の関西）で行きたい球団は阪神、楽天ではない" % league.names[target])
	_check(f.pref_words(target) == ["セ・リーグでプレーしたい", "地元（関西）に近い球団がいい"], "好みのひとこと（%s）" % str(f.pref_words(target)))
	_pref_target = target


func _best_other(f: Variant, league: Variant) -> String:
	var best := ""
	var best_z := -INF
	for id: String in f.declared:
		if f.info[id]["from"] == USER_TEAM:
			continue
		var z := float(Salary.ability(_gd.player(id))[0])
		if z > best_z:
			best_z = z
			best = id
	return best


func _own_declared(f: Variant) -> String:
	for id: String in f.declared:
		if f.info[id]["from"] == USER_TEAM:
			return id
	return ""


func _force_own_declare(f: Variant, league: Variant) -> String:
	var debut: Dictionary = _gd.load_debut_years(_gs.year)
	for id: String in league.players_of(USER_TEAM):
		if id in league.plan_retirements():
			continue
		if f.eligible(league, id, debut):
			f.declare(league, id)
			print("  （%sに宣言させた）" % league.names[id])
			return id
	return ""


# --- 2) ダルビッシュの引き留め ------------------------------------------------------------

func _check_darvish(success: bool) -> void:
	var label := "成功" if success else "失敗"
	print("\n== 2011年オフ：日本ハムでダルビッシュを引き留める（%s） ==" % label)
	_gs.new_game(NIPPON_HAM, 2011)
	var league: Variant = _gs.league
	_check(league.team_of.get(DARVISH, "") == NIPPON_HAM, "2011年開幕：ダルビッシュは日本ハム")
	_gs.advance_through(_gs.season_last_day())
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub := current_scene
	_check(hub.get("_year_label").text == "2011" and hub.get("_month_label").text == "オフ",
			"ハブ：2011年 オフ（%s %s）" % [hub.get("_year_label").text, hub.get("_month_label").text])
	# 可変ボタンは最初「表彰式」（表彰の画面）→ Esc でハブへ → 2回目（「FA/トレードへ」）で FA・ポスティングの画面が開く
	_check(_focus_key(hub) == "advance", "ハブ：可変ボタンにフォーカス")
	await _key(KEY_ENTER)
	_check(hub.get("_open_key") == "awards", "可変ボタンでまず表彰の画面（%s）" % hub.get("_open_key"))
	await _key(KEY_ESCAPE)
	_check(_focus_key(hub) == "advance", "表彰の画面から戻ると可変ボタンにフォーカス")
	await _key(KEY_ENTER)
	_check(_gs.phase == _gs.Phase.FA_TRADE and hub.get("_open_key") == "fa",
			"可変ボタンで FA・ポスティングの画面（%s / %s）" % [_gs.phase_name(), hub.get("_open_key")])
	var view: Node = hub.get("_fa_view")
	var f: Variant = _gs.fa()
	_check(DARVISH in f.mlb and f.mlb_info[DARVISH]["from"] == NIPPON_HAM and not league.team_of.has(DARVISH),
			"ダルビッシュはメジャー移籍の一覧にいる（いったん退団）")
	# (1) 選手×球団の表：最初は自球団のリーグ（パ）。行＝FA宣言した選手のあとにメジャー移籍の選手
	_check(view.get("_league") == "P" and not view.in_room(), "表は自球団のリーグ（パ・リーグ）の列から")
	var ids: Array = view.list_ids()
	_check(DARVISH in ids and ids.find(DARVISH) >= f.declared.size(),
			"ダルビッシュはFA宣言の選手のあとの行（%d行目）" % (ids.find(DARVISH) + 1))
	_check(view.cell(DARVISH, NIPPON_HAM) != null and view.cell(DARVISH, NIPPON_HAM).text == "米", "ダルビッシュの日本ハムのマスは「米」")
	var bad := []
	for id: String in f.declared:
		for team: String in _gd.teams("P"):
			var text: String = view.cell(id, team).text
			var bid: bool = team in f.bidder_teams(id)
			var want := ""
			if team == f.info[id]["from"]:
				want = "残" if bid or (team == NIPPON_HAM and f.user_bids.has(id)) else "✕"
			elif team == NIPPON_HAM:
				want = "交" if f.user_bids.has(id) else ""
			else:
				want = "交" if bid else "✕"
			if text != want:
				bad.append("%s/%s=%s（%s）" % [league.names[id], _gd.short_name(team), text, want])
	_check(bad.is_empty(), "表のマスが入札・残留交渉どおり（%d人×6球団）%s" % [f.declared.size(), str(bad.slice(0, 4))])
	if success and not f.declared.is_empty():
		var first: String = ids[0]
		_check(_focused() == view.cell(first, NIPPON_HAM), "先頭の行の自球団のマスにフォーカス")
		await _key(KEY_E)
		_check(view.get("_league") == "C" and view.cell(first, "読売ジャイアンツ") != null, "E（RB）でセ・リーグの列")
		await _key(KEY_Q)
		_check(view.get("_league") == "P" and view.cell(first, NIPPON_HAM) != null, "Q（LB）でパ・リーグに戻る")
		UiInput_grab(view.cell(first, NIPPON_HAM))
		await _key(KEY_ENTER)
		_check(first in view.marked_ids(), "マスでEnter：%sに印" % league.names[first])
		await _key(KEY_ENTER)
		_check(first not in view.marked_ids(), "もう一度Enterで印を外す")
	var own_cell: Button = view.cell(DARVISH, NIPPON_HAM)
	UiInput_grab(own_cell)
	await _frames(3)  # 表のスクロールがフォーカスに追従してからクリックする
	if success:
		await _key(KEY_ENTER)
	else:
		await _click(own_cell)
	_check(DARVISH in view.marked_ids() and view.selected_id() == DARVISH,
			"ダルビッシュのマスで印（%s）" % ("Enter" if success else "クリック"))
	# 名前札で選手詳細（Esc で閉じる）
	var tag: Control = view.get("_tags").get(DARVISH)
	if success:
		UiInput_grab(tag)
		await _key(KEY_ENTER)
	else:
		await _click(tag)
	_check(_detail() != null, "名前札で選手詳細が開く")
	await _key(KEY_ESCAPE)
	_check(_detail() == null and not view.in_room() and hub.get("_open_key") == "fa", "Esc で選手詳細を閉じる（表のまま）")
	if success:
		# 他球団の選手のマス（メジャー移籍）に印は付けられない
		for id: String in f.mlb:
			if f.mlb_info[id]["from"] != NIPPON_HAM:
				view.toggle_mark(id)
				_check(id not in view.marked_ids(), "他球団のメジャー移籍の選手には印を付けられない")
				break
		await _shot("fa1_list")
	# OK で交渉の部屋へ
	if success:
		UiInput_grab(view.get("_ok_button"))
		await _key(KEY_ENTER)
	else:
		await _click(view.get("_ok_button"))
	_check(view.in_room() and view.room_id() == DARVISH, "「OK」で交渉の部屋（%s）" % view.room_id())
	var change: Button = view.get("_change_button")
	var bar: Button = view.get("_amount_bar")
	if success:
		_check(_focused() == change, "交渉の部屋では「変更する」にフォーカス")
		await _key(KEY_ENTER)
		_check(_focused() == bar, "「変更する」で年俸の札へ")
		var before: int = view.get("_amount")
		await _key(KEY_RIGHT)
		_check(view.get("_amount") > before and _focused() == bar, "→で年俸が上がる（%s）" % Salary.text(view.get("_amount")))
		await _key(KEY_LEFT)
		_check(view.get("_amount") == before, "←で年俸が戻る")
	else:
		var before: int = view.get("_amount")
		var plus: Button = bar.get_parent().get_child(3)
		await _click(plus)
		_check(view.get("_amount") > before, "▶のクリックで年俸が上がる")
	# 年俸を上限まで上げて、年数5年
	var r: Array = f.bid_range(DARVISH)
	var star_low: String = view.get("_stars_label").text
	for i in 80:
		view.call("_step_amount", 1)
	for i in 5:
		view.call("_step_years", 1)
	_check(view.get("_amount") == r[1] and view.get("_years") == 5, "◀▶で年俸を上限（%s）・5年に" % Salary.text(r[1]))
	var chance: float = f.keep_chance(DARVISH, r[1], 5)
	_check(chance >= 0.05 and chance <= 0.2, "成功率は5〜20%%（%d%%）" % roundi(chance * 100))
	_check(view.get("_stars_label").text != star_low
			and view.get("_odds_label").text == "成功率：%d%%" % roundi(chance * 100),
			"提示を変えると★と成功率が変わる（%s → %s）" % [star_low, view.get("_stars_label").text])
	if success:
		await _shot("fa2_room")
	f.force_roll = 0.0 if success else 0.999
	var button: Button = view.get("_action_button")
	_check(button.text == "引き留める" and not button.disabled, "「引き留める」を押せる")
	UiInput_grab(button)
	await _key(KEY_ENTER)
	var status: String = f.mlb_info[DARVISH]["status"]
	_check(status == ("kept" if success else "failed"), "引き留めの結果：%s" % status)
	if success:
		_check(league.team_of.get(DARVISH, "") == NIPPON_HAM and not league.in_mlb.has(DARVISH)
				and league.kept_mlb.has(DARVISH), "成功：日本ハムに残留（メジャーにいない）")
		_check(league.salary_of(DARVISH) == r[1] and int(league.contract_until[DARVISH]) == 2016,
				"成功：年俸 %s・2016年まで" % Salary.text(league.salary_of(DARVISH)))
	else:
		_check(not league.team_of.has(DARVISH) and league.in_mlb.has(DARVISH), "失敗：メジャーへ")
	_check(button.disabled, "引き留めは1回だけ（ボタンが押せない）")
	var again: Dictionary = _gs.mlb_keep(DARVISH, r[1], 5)
	_check(not again["ok"], "2回目の引き留めはできない")
	# Esc で表へ（マスは「残」／「米」） → ハブへ。可変ボタンはまだ FA の交渉（締め切っていない）
	await _key(KEY_ESCAPE)
	_check(not view.in_room() and hub.get("_open_key") == "fa", "Esc で交渉の部屋から表へ")
	var after: String = view.cell(DARVISH, NIPPON_HAM).text
	_check(after == ("残" if success else "米"), "表のマスが引き留めの結果（%s）" % after)
	await _key(KEY_ESCAPE)
	_check(hub.get("_open_key") == "" and _gs.button_text() == "FA・移籍交渉", "Esc でハブへ（ボタン=%s）" % _gs.button_text())
	await _key(KEY_ENTER)
	_check(hub.get("_open_key") == "fa" and _gs.phase == _gs.Phase.FA_TRADE, "可変ボタンで FA の画面に戻る（段階は進まない）")
	UiInput_grab(view.get("_close_button"))
	await _key(KEY_ENTER)
	_check(f.resolved and not view.in_room(), "「締め切る」で結果を表に出す")
	var wrong := []
	for res: Dictionary in f.results:
		var text: String = view.call("_cell_state", f, res["id"], res["to"])[0]
		if text != ("残" if res["to"] == res["from"] else "決"):
			wrong.append(league.names[res["id"]])
	_check(wrong.is_empty(), "締め切ったあとは移籍先のマスが「決」（残留は「残」）%s" % str(wrong))
	_check(view.get("_close_button").disabled and view.get("_mark_button").disabled, "締め切ったあとは印・締め切りはできない")
	await _key(KEY_ESCAPE)
	if _gs.comp_open():
		_gs.comp_resolve()  # 自球団が関わるFAの補償はおまかせ（作業18）
	_check(hub.get("_open_key") == "" and _gs.button_text() == "契約更改へ", "締め切ると可変ボタンは「契約更改へ」")
	# 2012年の開幕へ
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	await _frames(3)
	_check(hub.get("_year_label").text == "2012" and hub.get("_month_label").text != "オフ",
			"ハブの日付が2012年の開幕に追従（%s %s）" % [hub.get("_year_label").text, hub.get("_month_label").text])
	var p: Dictionary = _gd.player(DARVISH)
	if success:
		_check(league.team_of.get(DARVISH, "") == NIPPON_HAM, "2012年開幕：ダルビッシュは日本ハム")
		_check(p.get("kept_from_mlb") == "mlb" and p.get("team") == NIPPON_HAM,
				"2012年：能力値はメジャーにいた年の換算（%s）" % str(p.get("kept_from_mlb")))
		var sim: SimTeam = _gs.season.teams.get(NIPPON_HAM)
		_check(sim != null and sim.by_id.has(DARVISH), "2012年：日本ハムの編成にいる")
		_gs.advance_through(Season.day_number("2012-06-30"))
		var stats: Dictionary = _gs.season.pitching.get(DARVISH, {})
		_check(int(stats.get("outs", 0)) > 0, "2012年：試合に投げている（%d回）" % (int(stats.get("outs", 0)) / 3))
		_gs.advance_through(_gs.season_last_day())
		while _gs.phase != _gs.Phase.SEASON:
			_gs.advance()
		_check(league.team_of.get(DARVISH, "") == NIPPON_HAM and not league.retired.has(DARVISH),
				"2013年開幕：まだ日本ハム（引退・復帰の処理が二重に起きない）")
		var counts := {}
		for e: Dictionary in league.log:
			if e["id"] == DARVISH:
				counts[e["kind"]] = counts.get(e["kind"], 0) + 1
		_check(counts.get("mlb_leave", 0) == 1 and counts.get("mlb_return", 0) == 0 and counts.get("retire", 0) == 0
				and counts.get("mlb_keep", 0) == 1, "ダルビッシュの出来事：%s" % str(counts))
		_check(league.salary_of(DARVISH) == r[1], "2013年も契約どおりの年俸（%s）" % Salary.text(league.salary_of(DARVISH)))
	else:
		_check(not league.team_of.has(DARVISH) and league.in_mlb.has(DARVISH), "2012年開幕：ダルビッシュはメジャー")
		var sim: SimTeam = _gs.season.teams.get(NIPPON_HAM)
		_check(sim != null and not sim.by_id.has(DARVISH), "2012年：日本ハムの編成にいない")


# --- 共通 --------------------------------------------------------------------------------

func UiInput_grab(c: Control) -> void:
	root.get_node("UiInput").grab(c)


func _focus_key(hub: Node) -> String:
	var c := _focused()
	if c != null and c.get_parent() != null and c.get_parent().has_signal("chosen"):
		return str(c.get_parent().get("key"))
	return ""


func _detail() -> Node:
	var scene := current_scene
	for layer in scene.get_children():
		if layer is CanvasLayer:
			for c in layer.get_children():
				if c.has_method("_show_player"):
					return c
	return null


func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["OK" if ok else "NG", label])
	if not ok:
		_failures += 1


func _focused() -> Control:
	return root.gui_get_focus_owner()


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		Input.parse_input_event(e)
		await _frames(2)


## マウスのクリック（ヘッドレスでは Input.parse_input_event のマウスが GUI に届かないので、ビューポートへ直接送る）
func _click(c: Control) -> void:
	# 画面の引き伸ばし（ヘッドレスはウィンドウが基準の解像度と違う）を考えてウィンドウの座標にする
	var pos := root.get_final_transform() * c.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = pos
	move.global_position = pos
	root.push_input(move)
	await _frames(1)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		e.position = pos
		e.global_position = pos
		e.pressed = pressed
		root.push_input(e)
		await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, wait := 0.35) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("  スクショ: %s.png" % name)
