extends SceneTree
## 契約更改の確認（ヘッドレス可。ウィンドウ付きで出力先を渡すとスクショも保存）。
## 1) 2008年から2012年のオフまで（2013年の開幕まで）進め、毎年のオフの契約更改で次を調べる：
##    - 全球団の選手の年俸が今季のゲーム内成績で上下する（活躍した選手は上がり、不振の選手は下がる）
##    - 上げ幅・下げ幅の上限（減額制限 1億円超40%・以下25%、上げ幅3倍・+1.5億円）が守られる
##    - 複数年契約中の選手は据え置き
##    - 自球団の提示額を調整でき（範囲外は範囲に丸める）、調整した値が翌年の年俸になる。締めたあとは変えられない
##    - 予算上限：FAの自球団の提示上限が予算の残りを超えない
##    - 毎年の開幕の年俸の分布（平均・中央値・1億円以上・最高）が相場の範囲に収まり、年を追ってインフレしない
##    - オフ→翌年の開幕で年・日付の表示が進む
## 2) 2012年オフ、ハブ → 可変ボタン → 契約更改の画面をキーボード・マウスで操作（タブ・札の選択・◀▶・選手詳細・
##    「契約更改を終える」）し、ハブの日付が2013年の開幕に追従する
##
##   godot --headless --path godot --script res://tests/contract_check.gd -- [出力先]

const USER_TEAM := "読売ジャイアンツ"
const LAST_OFF := 2012
## 年俸の分布の許容範囲（HANDOFF 4.13：平均 約3,100〜3,300万円・中央値 約1,500万円・1億円以上 約45〜63人・
## 最高 3.5〜5.8億円）から極端に外れないこと
const MEAN_RANGE := [2500, 4300]
const MEDIAN_RANGE := [1000, 2300]
const OVER_100M_RANGE := [30, 90]
const MAX_RANGE := [30000, 70000]
## 最初の年からの平均の伸びの上限（インフレしない）
const INFLATION_MAX := 1.3

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node
## ContractRenewal（autoload に依存するので実行時に読み込む）
var _budget: GDScript


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	_budget = load("res://sim/contract_renewal.gd")
	await _check_years()
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_years() -> void:
	print("== 2008〜%d年のオフの契約更改（自球団：%s） ==" % [LAST_OFF, USER_TEAM])
	_gs.new_game(USER_TEAM)
	var league: Variant = _gs.league
	var means: Array[int] = []
	means.append(_distribution(_gs.year))
	while true:
		var y: int = _gs.year
		_gs.advance_through(_gs.season_last_day())
		_check(_gs.phase == _gs.Phase.AWARDS and _gs.date_text() == "%d年 オフ" % y, "%d年 シーズン終了（%s）" % [
			y, _gs.date_text()])
		var season: Variant = _gs.season
		while _gs.phase != _gs.Phase.FA_TRADE:
			_gs.advance()
		_check_fa_budget(y)
		_gs.fa_resolve()
		_check(_gs.button_text() == "契約更改へ", "%d年オフ：FAを締めると次は契約更改" % y)
		var before := {}
		for id: String in league.team_of:
			before[id] = league.salary_of(id)
		var fixed_before := {}
		for id: String in league.contract_until:
			if int(league.contract_until[id]) >= y + 1:
				fixed_before[id] = league.salary_of(id)
		if y == LAST_OFF:
			await _check_ui(y)
			means.append(_after_off(y))
			break
		_gs.advance()
		_check(_gs.phase == _gs.Phase.CONTRACT and _gs.contract_open() and _gs.button_text() == "契約更改",
				"%d年オフ：契約更改の段階（ボタン=%s）" % [y, _gs.button_text()])
		_check_renewals(y, season, before, fixed_before)
		var expected := _adjust_user(y)
		_gs.contract_resolve()
		_check(not _gs.contract_open() and _gs.button_text() == "戦力外・引退へ",
				"%d年オフ：締めると次は戦力外・引退（%s）" % [y, _gs.button_text()])
		var any: String = expected.keys()[0] if not expected.is_empty() else ""
		if not any.is_empty():
			_check(not _gs.contract_set(any, 1000).is_empty(), "締めたあとは提示額を変えられない")
		while _gs.phase != _gs.Phase.SEASON:
			_gs.advance()
		_check(_gs.year == y + 1 and _gs.date_text().begins_with("%d年 " % (y + 1)) and _gs.month_text() != "オフ",
				"%d年の開幕へ（%s）" % [y + 1, _gs.date_text()])
		for id: String in expected:
			if not league.team_of.has(id):
				continue
			_check(league.salary_of(id) == expected[id], "%d年：%sの年俸は調整した %s（%s）" % [y + 1,
				league.names[id], Salary.text(expected[id]), Salary.text(league.salary_of(id))])
		means.append(_distribution(_gs.year))
	_check(means[-1] <= means[0] * INFLATION_MAX, "年俸の平均がインフレしない（%s → %s）" % [
		Salary.text(means[0]), Salary.text(means[-1])])


## 全球団の更改：成績との関係・上限・据え置き
func _check_renewals(y: int, season: Variant, before: Dictionary, fixed_before: Dictionary) -> void:
	var league: Variant = _gs.league
	var good_up := 0
	var good := 0
	var bad_down := 0
	var bad := 0
	var over_limit: Array[String] = []
	var fixed_changed := 0
	var good_names: Array[String] = []
	var bad_names: Array[String] = []
	for id: String in before:
		if not league.team_of.has(id) or id in league.plan_retirements():
			continue
		var prev: int = before[id]
		var now: int = league.salary_of(id)
		if fixed_before.has(id):
			if now != fixed_before[id]:
				fixed_changed += 1
			continue
		var history: Array = league.salary_history.get(id, [])
		if history.is_empty() or history[-1]["year"] != y + 1:
			continue
		var cut := Salary.CUT_LIMIT_HIGH if prev > Salary.CUT_LIMIT_BORDER else Salary.CUT_LIMIT_LOW
		var upper := maxf(prev, minf(prev * Salary.RAISE_MAX, prev + Salary.RAISE_MAX_AMOUNT))
		if now < prev * (1.0 - cut) - 10 or now > upper + 10:
			over_limit.append("%s %s→%s" % [league.names[id], Salary.text(prev), Salary.text(now)])
		var p: Dictionary = _gd.player(id)
		var stats: Dictionary = (season.pitching if p.get("is_pitcher", false) else season.batting).get(id, {})
		var s := Salary.season_ability(p, stats)
		# 活躍：今季の実力 z が高く出場も多い／不振：年俸5000万円以上で出場が多いのに成績が悪い
		# （年俸の安い若手は出場が増えれば成績が悪くても上がるので除く）
		if float(s[0]) >= 0.8 and float(s[1]) >= 0.6:
			good += 1
			if now > prev:
				good_up += 1
			elif good_names.size() < 3:
				good_names.append("%s %s→%s" % [league.names[id], Salary.text(prev), Salary.text(now)])
		elif float(s[0]) <= -0.5 and float(s[1]) >= 0.4 and prev >= 5000:
			bad += 1
			if now < prev:
				bad_down += 1
			elif bad_names.size() < 3:
				bad_names.append("%s %s→%s" % [league.names[id], Salary.text(prev), Salary.text(now)])
	print("  活躍 %d人中 %d人アップ（上がらなかった例：%s）、不振 %d人中 %d人ダウン（下がらなかった例：%s）" % [
		good, good_up, "、".join(good_names), bad, bad_down, "、".join(bad_names)])
	_check(good >= 5 and good_up >= good * 0.8, "%d年オフ：活躍した選手は上がる（%d/%d）" % [y, good_up, good])
	_check(bad >= 3 and bad_down >= bad * 0.8, "%d年オフ：不振の選手は下がる（%d/%d）" % [y, bad_down, bad])
	_check(over_limit.is_empty(), "%d年オフ：上げ幅・下げ幅の上限を守る %s" % [y, str(over_limit.slice(0, 3))])
	_check(fixed_changed == 0, "%d年オフ：複数年契約中の選手は据え置き（%d人）" % [y, fixed_before.size()])


## 自球団の提示額を調整する（上限・下限・中間）。{選手ID: 期待する来季の年俸}
func _adjust_user(y: int) -> Dictionary:
	var c: Variant = _gs.contracts()
	var league: Variant = _gs.league
	var expected := {}
	var adjustable: Array[String] = []
	var fixed := ""
	for id in c.order:
		if c.can_adjust(id):
			adjustable.append(id)
		elif fixed.is_empty():
			fixed = id
	_check(adjustable.size() >= 20, "%d年オフ：自球団の更改の対象 %d人" % [y, adjustable.size()])
	for id: String in c.rows:
		_check(league.salary_of(id) == c.rows[id]["amount"], "提示額＝来季の年俸（%s）" % league.names[id])
		break
	if adjustable.size() < 3:
		return expected
	# 上限まで上げるのは年俸の安い選手（高額の選手を毎年上げると分布の確認がゆがむ）
	var hi := adjustable[-1]
	var lo := adjustable[0]
	var mid := adjustable[adjustable.size() / 2]
	var row_hi: Dictionary = c.rows[hi]
	_check(_gs.contract_set(hi, int(row_hi["high"]) + 100000).is_empty() and row_hi["amount"] == row_hi["high"],
			"%sの提示を上限 %s に（範囲外は丸める）" % [league.names[hi], Salary.text(row_hi["high"])])
	expected[hi] = row_hi["high"]
	var row_lo: Dictionary = c.rows[lo]
	_gs.contract_set(lo, 0)
	_check(row_lo["amount"] == row_lo["low"] and row_lo["low"] >= int(row_lo["prev"]) * 0.6 - 10,
			"%sの提示を下限 %s に（今季 %s）" % [league.names[lo], Salary.text(row_lo["low"]), Salary.text(row_lo["prev"])])
	expected[lo] = row_lo["low"]
	var row_mid: Dictionary = c.rows[mid]
	var target := Salary.round_amount((int(row_mid["low"]) + int(row_mid["high"])) / 2.0)
	_gs.contract_set(mid, target)
	expected[mid] = row_mid["amount"]
	_check(row_mid["amount"] == target, "%sの提示を %s に" % [league.names[mid], Salary.text(target)])
	if not fixed.is_empty():
		_check(not _gs.contract_set(fixed, 99999).is_empty(), "据え置き（%s）の選手は変えられない" % c.rows[fixed]["fixed"])
	return expected


## FAの自球団の提示上限が予算の残りを超えない（残りが下限より少なければ下限）
func _check_fa_budget(y: int) -> void:
	var f: Variant = _gs.fa()
	for id in f.declared:
		if f.info[id]["from"] == USER_TEAM:
			continue
		var r: Array = f.bid_range(id)
		var base: Array = f.base_range(id)
		var room: int = f.budget_room(id)
		_check(r[1] <= maxi(r[0], room) and r[1] <= base[1], "%d年オフ：FAの提示上限 %s は予算の残り %s 以内" % [
			y, Salary.text(r[1]), Salary.text(maxi(room, 0))])
		return


## 開幕時点の年俸の分布を表示して範囲を調べる。平均を返す
func _distribution(y: int) -> int:
	var league: Variant = _gs.league
	var amounts: Array[int] = []
	for id: String in league.team_of:
		amounts.append(league.salary_of(id))
	amounts.sort()
	var total := 0
	for a in amounts:
		total += a
	var mean := total / amounts.size()
	var median := amounts[amounts.size() / 2]
	var over := amounts.filter(func(a: int) -> bool: return a >= 10000).size()
	print("%d年開幕 年俸：平均 %s・中央値 %s・1億円以上 %d人・最高 %s（%d人）" % [y, Salary.text(mean),
		Salary.text(median), over, Salary.text(amounts[-1]), amounts.size()])
	var parts: Array[String] = []
	for t: String in _gd.teams():
		parts.append("%s %s/%s" % [_gd.short_name(t), _oku(league.payroll(t)), _oku(_budget.budget(t))])
	print("  球団の総額/予算：", "　".join(parts))
	var ids: Array = league.team_of.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return league.salary_of(a) > league.salary_of(b))
	var top: Array[String] = []
	for id: String in ids.slice(0, 5):
		top.append("%s(%s)%s%s" % [league.names[id], _gd.short_name(league.team_of[id]),
			Salary.text(league.salary_of(id)), "・%d年まで" % int(league.contract_until[id]) 				if int(league.contract_until.get(id, 0)) >= y else ""])
	print("  上位：", "、".join(top))
	_check(mean >= MEAN_RANGE[0] and mean <= MEAN_RANGE[1], "%d年：平均 %s が相場の範囲" % [y, Salary.text(mean)])
	_check(median >= MEDIAN_RANGE[0] and median <= MEDIAN_RANGE[1], "%d年：中央値 %s が相場の範囲" % [y, Salary.text(median)])
	_check(over >= OVER_100M_RANGE[0] and over <= OVER_100M_RANGE[1], "%d年：1億円以上 %d人が相場の範囲" % [y, over])
	_check(amounts[-1] >= MAX_RANGE[0] and amounts[-1] <= MAX_RANGE[1], "%d年：最高 %s が相場の範囲" % [
		y, Salary.text(amounts[-1])])
	return mean


static func _oku(amount: int) -> String:
	return "%.1f億" % (amount / 10000.0)


# --- 2) 画面の操作 -------------------------------------------------------------------------

func _check_ui(y: int) -> void:
	print("\n== %d年オフ：契約更改の画面 ==" % y)
	var league: Variant = _gs.league
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub := current_scene
	_check(hub.get("_year_label").text == str(y) and hub.get("_month_label").text == "オフ", "ハブ：%d年 オフ" % y)
	_check(_focus_key() == "advance", "ハブ：可変ボタンにフォーカス（%s）" % _focus_key())
	await _key(KEY_ENTER)
	_check(_gs.phase == _gs.Phase.CONTRACT and hub.get("_open_key") == "contract",
			"可変ボタン「契約更改へ」で契約更改の画面（%s / %s）" % [_gs.phase_name(), hub.get("_open_key")])
	_check(str(hub.get("_sub_title_label").text).contains("%d年オフ" % y), "見出しが %d年オフ" % y)
	var view: Node = hub.get("_contract_view")
	var c: Variant = _gs.contracts()
	_check(view.get("_tab") == "p" and view.list_ids().size() > 0, "投手タブに自球団の投手（%d人）" % view.list_ids().size())
	var first: String = view.list_ids()[0]
	_check(_focused() == view.get("_tags").get(first), "先頭の札にフォーカス")
	await _shot("c1_list")
	await _key(KEY_ENTER)
	_check(view.selected_id() == first, "Enter で札を選ぶ")
	await _key(KEY_ENTER)
	_check(_detail() != null, "もう一度 Enter で選手詳細")
	await _key(KEY_ESCAPE)
	_check(_detail() == null and view.selected_id() == first, "Esc で選手詳細を閉じる")
	# 調整できる選手を選んで ◀▶（マウス）
	await _key(KEY_E)
	_check(view.get("_tab") == "b", "E（RB）で野手タブ")
	var target := ""
	for id: String in view.list_ids():
		if c.can_adjust(id) and int(c.rows[id]["high"]) > int(c.rows[id]["amount"]):
			target = id
			break
	_check(not target.is_empty(), "調整できる野手がいる")
	if target.is_empty():
		return
	await _click(view.get("_tags").get(target))
	_check(view.selected_id() == target, "クリックで札を選ぶ（%s）" % league.names[target])
	var before: int = c.rows[target]["amount"]
	var plus: Button = view.get("_step_buttons")[1]
	await _click(plus)
	await _click(plus)
	var after: int = c.rows[target]["amount"]
	_check(after > before and league.salary_of(target) == after, "▶を2回クリックで %s → %s" % [
		Salary.text(before), Salary.text(after)])
	_check(str(view.get("_new_label").text) == Salary.text(after), "提示額の表示が追従（%s）" % view.get("_new_label").text)
	await _shot("c2_adjust")
	await _key(KEY_E)
	_check(view.get("_tab") == "teams" and view.get("_grid").get_child_count() == 12, "E で球団別（12球団）")
	await _shot("c3_teams")
	await _key(KEY_ESCAPE)
	_check(hub.get("_open_key") == "" and _gs.button_text() == "契約更改", "Esc でハブへ（ボタン=%s）" % _gs.button_text())
	await _key(KEY_ENTER)
	_check(hub.get("_open_key") == "contract" and _gs.phase == _gs.Phase.CONTRACT, "可変ボタンで契約更改の画面に戻る")
	await _click(view.get("_close_button"))
	_check(c.resolved and view.get("_tab") == "teams", "「契約更改を終える」で締める")
	await _key(KEY_ESCAPE)
	_check(_gs.button_text() == "戦力外・引退へ", "締めると可変ボタンは「戦力外・引退へ」")
	while _gs.phase != _gs.Phase.SEASON:
		_gs.advance()
	await _frames(3)
	_check(hub.get("_year_label").text == str(y + 1) and hub.get("_month_label").text != "オフ",
			"ハブの日付が%d年の開幕に追従（%s %s）" % [y + 1, hub.get("_year_label").text, hub.get("_month_label").text])
	if league.team_of.has(target):
		_check(league.salary_of(target) == after, "%d年：画面で調整した年俸 %s" % [y + 1, Salary.text(league.salary_of(target))])


## 最後のオフのあと（画面のテストで2013年の開幕まで進めた）
func _after_off(_y: int) -> int:
	return _distribution(_gs.year)


# --- 共通 --------------------------------------------------------------------------------

func _focus_key() -> String:
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
