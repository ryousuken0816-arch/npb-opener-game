# gdlint: disable=max-file-lines
class_name RecordsView
extends VBoxContainer
## 記録室（ハブの「記録室」）。docs/SPEC.md「記録室」、docs/AUTORUN.md 作業10。
##
## タブ（LB/RB＝Q/E でも）：
## - 打撃成績／投手成績：個人成績のランキング（年度別・通算、規定到達者のみ／全員、セ・パ・両リーグ）。列の見出しで並び替え。
##   セイバー指標（wOBA・wRC+・OPS+・ISO・BB%・K%・BABIP／FIP・WHIP・K/9・BB/9・K-BB%、守備得点、簡易 WAR）は Records で計算。
##   打撃成績の2段目で守備位置を選ぶと、その位置の守備ランキング（守備イニング・範囲・失策・肩・守備得点。捕手は盗塁阻止・
##   暴投捕逸。年度別のみ）
## - チームのデプス：守備位置ごとにスタメン（正選手）と控え（2軍も）を並べ、現在の能力と将来性のランク（Depth）・年齢。
##   若手の有望株（将来性が現在より2段以上高い25歳以下）は緑の枠と「有望」。並び替え（現在の能力／将来性／年齢）、層の厚さ
## - 位置別の戦力（作業34）：球団×位置の得失点（TeamValue。リーグ平均＝0）を、球団ごとの棒グラフ（◀▶で球団）と
##   12球団の一覧（数字と色の濃さ、見出しは固定、並び替え）で。今季／昨季（試合が少ないうちは昨季が初期表示。昨季がゲームより前の
##   年なら能力から見込んだ値）。「能力ランク」で今までの12球団×守備位置のランク（現在→将来性。球団名でデプスへ）
## - チーム成績の推移：年ごとの順位と勝敗
## - 表彰の歴代：AwardsView を年を選んで表示
## - 達成記録：ノーヒットノーラン・サイクル安打と通算記録の節目
## - 歴代メンバー（作業48）：年×球団の主なスタメン・控え／先発ローテ・中継ぎ・抑え（RecordsHistory）
## - 歴代ドラフト（作業49）：年×球団の指名と、今の球団・評価・通算成績・現役の印（RecordsHistory）
## 名前札は Ⓐ／クリックで選手詳細。Ⓑ はハブへ戻る

signal message_changed(text: String)

const TABS := [["bat", "打撃成績"], ["pit", "投手成績"], ["depth", "デプス"], ["pos_rank", "位置別の戦力"],
	["teams", "順位の推移"], ["awards", "表彰の歴代"], ["history", "達成記録"], ["members", "歴代メンバー"],
	["drafts", "歴代ドラフト"]]
## タブのボタンの幅（9つと LB/RB の案内が広げたサブ画面の幅に入る）
const TAB_WIDTH := 114
## ランキングに出す人数（多いと重いので上位だけ）
const RANKING_ROWS := 50
## 通算の規定（打席・アウト）
const CAREER_MIN_PA := 1000
const CAREER_MIN_OUTS := 900
const ROW_HEIGHT := 30
## ランキングの表の幅（サブ画面の中の幅からスクロールバーの分を引いたもの）
const RANKING_WIDTH := 1150.0
const PROSPECT_COLOR := Color("2e7d32")
const MINE_TINT := Color(1.0, 0.84, 0.31, 0.55)
## 守備位置ランクの表の列の幅（球団名・各位置）。10列＋スクロールバーが広げたサブ画面（1280x720 で幅約1180）に収まる幅
const POS_RANK_TEAM_WIDTH := 120
const POS_RANK_CELL_WIDTH := 100
## 日本一の球団の文字色（チーム成績の推移）
const CHAMPION_COLOR := Color("b8860b")
## チーム成績の推移の各球団の列の幅（年＋12球団。縦のスクロールバーが出ても広げたサブ画面に収まる幅）
const TEAM_CELL_WIDTH := 84
const DEPTH_SORTS := [["now", "現在の能力順"], ["future", "将来性順"], ["age", "年齢順"]]
## 守備ランキングの守備位置（打撃成績の2段目）と、規定（チームの試合数×この回数の守備イニング）
const FIELD_POSITIONS := ["捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "左翼手", "中堅手", "右翼手"]
const FIELD_MIN_INNINGS_PER_GAME := 4.0
## 守備ランキングの列：[キー, 見出し, 種類（Records.format）, 小さいほど良いか]
const FLD_COLUMNS_IF := [
	["g", "試合", "int", false], ["outs", "守備回", "ip", false], ["ch", "打球", "int", false],
	["e", "失策", "int", true], ["rng", "範囲", "runs", false], ["err", "失策点", "runs", false],
	["total", "守備得点", "runs", false], ["per1000", "/1000回", "runs", false],
]
const FLD_COLUMNS_OF := [
	["g", "試合", "int", false], ["outs", "守備回", "ip", false], ["ch", "打球", "int", false],
	["e", "失策", "int", true], ["kills", "補殺", "int", false], ["rng", "範囲", "runs", false],
	["err", "失策点", "runs", false], ["arm", "肩", "runs", false], ["total", "守備得点", "runs", false],
	["per1000", "/1000回", "runs", false],
]
## 位置別の戦力：表示の切り替え、今季の試合がこれより少ないうちは昨季を初期表示（1球団あたりの試合数）
const PV_MODES := [["chart", "球団ごとの棒グラフ"], ["list", "12球団の一覧"], ["ability", "能力ランク（現在→将来）"]]
const PV_MIN_GAMES := 20
## 12球団の一覧の列の幅（球団・各位置）と、色が一番濃くなる点
const PV_TEAM_WIDTH := 110
const PV_CELL_WIDTH := 75
const PV_FULL_COLOR_RUNS := 25.0
const PV_PLUS := Color("e53935")
const PV_MINUS := Color("1e63c9")
const FLD_COLUMNS_C := [
	["g", "試合", "int", false], ["outs", "守備回", "ip", false], ["sba", "企図", "int", false],
	["cs_n", "盗塁刺", "int", false], ["cs_pct", "阻止率", "pct", false], ["wp_n", "暴投捕逸", "int", true],
	["cs", "阻止", "runs", false], ["wp", "暴投捕逸点", "runs", false], ["total", "守備得点", "runs", false],
	["per1000", "/1000回", "runs", false],
]

var _palette: UiTheme.Palette
var _tab := "bat"
var _year := 0
## 表彰の歴代で見ている年（ほかのタブの年とは別）
var _awards_year := 0
var _career := false
var _qualified := true
var _league := ""
var _sort := {"bat": ["avg", true], "pit": ["era", false], "fld": ["total", true], "pv": ["total", true]}
## 打撃成績で見ている守備ランキングの守備位置（空なら打撃のランキング）
var _fld_pos := ""
## 位置別の戦力：表示（PV_MODES）、昨季か、棒グラフの球団、年 → TeamValue の結果
var _pv_mode := "chart"
var _pv_last := false
var _pv_team := ""
var _pv_cache := {}
var _team := ""
var _depth_sort := "now"
## 歴代メンバー：年（0＝いちばん新しい年）・球団・投手を見ているか。歴代ドラフト：年・球団
var _mem_year := 0
var _mem_team := ""
var _mem_pitch := false
var _dr_year := 0
var _dr_team := ""
var _tab_buttons := {}
var _options: HBoxContainer
var _sub_options: HBoxContainer
## スクロールしても見える表の見出し（位置別の戦力の一覧・能力ランク）
var _fixed: VBoxContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _awards_view: AwardsView
var _ids: Array = []
## 年 → リーグ → 係数（Records.coefficients）
var _coef_cache := {}


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	add_theme_constant_override("separation", 6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(UiTheme.small_label("◀ LB", 16, UiTheme.TEXT, 800))
	for t: Array in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(TAB_WIDTH, 38)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_font_override("font", UiTheme.font(800))
		UiTheme.style_toggle(b, p.ink)
		var key: String = t[0]
		b.pressed.connect(func() -> void: set_tab(key))
		row.add_child(b)
		_tab_buttons[key] = b
	row.add_child(UiTheme.small_label("RB ▶", 16, UiTheme.TEXT, 800))
	add_child(row)
	_options = HBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	add_child(_options)
	_sub_options = HBoxContainer.new()
	_sub_options.add_theme_constant_override("separation", 6)
	add_child(_sub_options)
	_fixed = VBoxContainer.new()
	_fixed.add_theme_constant_override("separation", 2)
	add_child(_fixed)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 2)
	_scroll.add_child(_body)
	_awards_view = AwardsView.new()
	_awards_view.setup(p)
	_awards_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_awards_view.visible = false
	add_child(_awards_view)


# --- 外から ------------------------------------------------------------------------------

func open() -> void:
	_coef_cache.clear()
	_pv_cache.clear()
	_pv_last = _pv_default_last()
	var years := GameState.records_years()
	_year = years[-1] if not years.is_empty() else GameState.year
	_team = GameState.team
	_mem_year = 0
	_mem_team = GameState.team
	_dr_year = 0
	_dr_team = GameState.team
	if _tab.is_empty():
		_tab = "bat"
	refresh()
	focus_first()


func back() -> bool:
	return false


func switch_tab(delta: int) -> void:
	var i := 0
	for j in TABS.size():
		if TABS[j][0] == _tab:
			i = j
	set_tab(TABS[posmod(i + delta, TABS.size())][0])


func set_tab(key: String) -> void:
	_tab = key
	refresh()
	focus_first()


## テスト用
func current_tab() -> String:
	return _tab


func shown_year() -> int:
	return _year


## テスト用：ランキングの行（選手ID の並び）
func list_ids() -> Array:
	return _ids


func set_team(team_name: String) -> void:
	_team = team_name
	set_tab("depth")


func focus_first() -> void:
	if _tab == "awards":
		_awards_view.focus_first()
		return
	for c in UiInput.focusables(_body):
		if UiInput.grab(c):
			return
	for c in UiInput.focusables(_options) + UiInput.focusables(_sub_options):
		if UiInput.grab(c):
			return
	UiInput.grab(_tab_buttons[_tab])


func refresh() -> void:
	for key: String in _tab_buttons:
		_tab_buttons[key].set_pressed_no_signal(key == _tab)
	_clear(_options)
	_clear(_sub_options)
	_clear(_fixed)
	_clear(_body)
	_ids = []
	_scroll.visible = _tab != "awards"
	_awards_view.visible = _tab == "awards"
	_scroll.scroll_vertical = 0
	match _tab:
		"bat", "pit":
			_build_ranking(_tab == "pit")
		"depth":
			_build_depth()
		"pos_rank":
			_build_position_value()
		"teams":
			_build_teams()
		"awards":
			_build_awards()
		"history":
			_build_history()
		"members":
			RecordsHistory.build_members(self)
		"drafts":
			RecordsHistory.build_drafts(self)
	_sub_options.visible = _sub_options.get_child_count() > 0
	_fixed.visible = _fixed.get_child_count() > 0


static func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# --- 共通の部品 ------------------------------------------------------------------------------

func _option_button(text: String, pressed: bool, action: Callable, width := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = pressed
	b.custom_minimum_size = Vector2(width, 34)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_font_override("font", UiTheme.font(800))
	UiTheme.style_toggle(b, _palette.ink, 8)
	b.pressed.connect(func() -> void:
		action.call()
		refresh()
		UiInput.grab(_find_option(text)))
	return b


func _find_option(text: String) -> Control:
	for c in _options.get_children() + _sub_options.get_children():
		if c is Button and (c as Button).text == text:
			return c
	return _tab_buttons[_tab]


## 年を選ぶ ◀ 2008年 ▶
func _year_stepper() -> void:
	var years := GameState.records_years()
	if years.is_empty():
		return
	var i := years.find(_year)
	if i < 0:
		i = years.size() - 1
		_year = years[i]
	for d: int in [-1, 1]:
		var b := _option_button("◀" if d < 0 else "▶", false, func() -> void:
			var j := clampi(years.find(_year) + d, 0, years.size() - 1)
			_year = years[j], 40)
		b.toggle_mode = false
		b.disabled = (d < 0 and i == 0) or (d > 0 and i == years.size() - 1)
		if d > 0:
			var label := UiTheme.small_label("%d年" % _year, 18, UiTheme.TEXT, 800)
			label.custom_minimum_size = Vector2(80, 0)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_options.add_child(label)
		_options.add_child(b)


func _cell(text: String, width: float, color := UiTheme.TEXT, align := HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var label := UiTheme.small_label(text, 15, color, 700)
	label.custom_minimum_size = Vector2(width, ROW_HEIGHT)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	return label


func _tag(id: String, text: String, width := 120.0) -> NameTag:
	var tag := NameTag.new()
	tag.custom_minimum_size = Vector2(width, 28)
	tag.font_size = 15
	var p := GameData.player(id)
	if p.is_empty():
		tag.setup_plain(NameTag.family_name(text), NameTag.COLOR_UNKNOWN)
		tag.disabled = true
	else:
		tag.setup_player(p, NameTag.family_name(text))
	tag.tooltip_text = "%s（Ⓐ／クリックで選手詳細）" % text
	_ids.append(id)
	var ids := _ids
	tag.pressed.connect(func() -> void: PlayerDetail.open(tag, id, ids))
	return tag


func _rank(rank: String, size := 18) -> Label:
	var label := UiTheme.rank_label({"rank": rank, "value": Draft.RANK_LETTERS.find(rank)}, size)
	label.tooltip_text = ""
	label.custom_minimum_size = Vector2(22, 0)
	return label


func _row_panel(tint: Color) -> HBoxContainer:
	var panel := PanelContainer.new()
	var style := UiTheme.box(tint, 6)
	style.content_margin_left = 4
	style.content_margin_right = 4
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	_body.add_child(panel)
	return row


func _section(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	UiTheme.heading(label, 20, color, Color.WHITE, 6)
	_body.add_child(label)


# --- 打撃・投手のランキング --------------------------------------------------------------------

func _build_ranking(pitching: bool) -> void:
	var tab := "pit" if pitching else "bat"
	_options.add_child(_option_button("年度別", not _career, func() -> void: _career = false))
	_options.add_child(_option_button("通算", _career, func() -> void:
		_career = true
		_fld_pos = ""))
	if not _career:
		_year_stepper()
	_options.add_child(_option_button("規定到達", _qualified, func() -> void: _qualified = true))
	_options.add_child(_option_button("全員", not _qualified, func() -> void: _qualified = false))
	for lg: Array in [["", "両リーグ"], ["C", "セ"], ["P", "パ"]]:
		var key: String = lg[0]
		_options.add_child(_option_button(lg[1], _league == key, func() -> void: _league = key))
	if not pitching:
		# 2段目：打撃のランキング／守備位置ごとの守備ランキング
		_sub_options.add_child(UiTheme.small_label("守備ランキング：", 15, UiTheme.TEXT_SUB, 800))
		_sub_options.add_child(_option_button("打撃", _fld_pos.is_empty(), func() -> void: _fld_pos = "", 64))
		for pos: String in FIELD_POSITIONS:
			_sub_options.add_child(_option_button(pos.left(2), _fld_pos == pos, func() -> void:
				_fld_pos = pos
				_career = false, 64))
		if not _fld_pos.is_empty():
			_build_fielding()
			return
	var rows := _ranking_rows(pitching)
	var columns: Array = Records.PIT_COLUMNS if pitching else Records.BAT_COLUMNS
	_ranking_table(tab, columns, rows, false)
	var scope := "通算" if _career else "%d年" % _year
	message_changed.emit("%s・%s・%s：%d人（上位%d人まで表示）。列の見出しで並び替え。%s" % [
		scope, "規定到達" if _qualified else "全員", {"": "両リーグ", "C": "セ・リーグ", "P": "パ・リーグ"}[_league],
		rows.size(), RANKING_ROWS,
		"通算はゲーム開始前の史実の1軍成績を含む（規定は%d打席・%d投球回）" % [CAREER_MIN_PA, CAREER_MIN_OUTS / 3]
			if _career else "規定は試合数×3.1打席・×1.0投球回"])


## ランキングの表（見出しで並び替え）。rows は [{id, name, team, row, rank?}]、with_rank なら守備の能力のランクの列
func _ranking_table(tab: String, columns: Array, rows: Array, with_rank: bool) -> void:
	var sort: Array = _sort[tab]
	var key: String = sort[0]
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var va: float = float(a["row"].get(key, 0))
		var vb: float = float(b["row"].get(key, 0))
		if va == vb:
			return str(a["id"]) < str(b["id"])
		return va > vb if sort[1] else va < vb)
	# 列の幅：画面の中の幅（RANKING_WIDTH）から #・選手・球団（・能力）と間隔を引いて等分
	var fixed := 30.0 + 124.0 + 60.0 + (40.0 if with_rank else 0.0)
	var n_fixed := 4 if with_rank else 3
	var width := (RANKING_WIDTH - fixed - 4.0 * (columns.size() + n_fixed)) / columns.size()
	# 見出し（押すと並び替え。もう一度押すと逆順）
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header.add_child(_cell("#", 30, UiTheme.TEXT_SUB))
	header.add_child(_cell("選手", 124, UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_CENTER))
	header.add_child(_cell("球団", 60, UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_LEFT))
	if with_rank:
		header.add_child(_cell("能力", 40, UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_CENTER))
	for col: Array in columns:
		var b := Button.new()
		var ck: String = col[0]
		b.text = str(col[1]) + ("▼" if ck == key and sort[1] else "▲" if ck == key else "")
		b.custom_minimum_size = Vector2(width, 28)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		UiTheme.style_button(b, _palette.main if ck == key else Color("e3e8ee"), Color.TRANSPARENT, 6, 3)
		b.pressed.connect(func() -> void:
			var desc: bool = not col[3]
			if _sort[tab][0] == ck:
				desc = not _sort[tab][1]
			_sort[tab] = [ck, desc]
			refresh()
			for c in UiInput.focusables(_options.get_parent()):
				if c is Button and (c as Button).text.begins_with(str(col[1])):
					UiInput.grab(c))
		header.add_child(b)
	_body.add_child(header)
	if rows.is_empty():
		_body.add_child(UiTheme.small_label("成績がありません（シーズンが始まると表示されます）", 16, UiTheme.TEXT, 700))
	for i in mini(rows.size(), RANKING_ROWS):
		var r: Dictionary = rows[i]
		var row := _row_panel(MINE_TINT if r["team"] == GameState.team else Color(1, 1, 1, 0.5 if i % 2 == 0 else 0.25))
		row.add_child(_cell(str(i + 1), 26, UiTheme.TEXT_SUB))
		row.add_child(_tag(r["id"], r["name"]))
		row.add_child(_cell(GameData.short_name(r["team"]), 60, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT))
		if with_rank:
			var rank_box := CenterContainer.new()
			rank_box.custom_minimum_size = Vector2(40, 0)
			rank_box.add_child(_rank(r["rank"]) if not str(r["rank"]).is_empty() else _cell("-", 22))
			row.add_child(rank_box)
		for col: Array in columns:
			row.add_child(_cell(Records.format(col[2], r["row"].get(col[0], 0)), width,
				_palette.ink if col[0] == key else UiTheme.TEXT))


## 守備ランキング（_fld_pos の守備位置、年度別）
func _build_fielding() -> void:
	var columns: Array = FLD_COLUMNS_C if _fld_pos == "捕手" \
		else FLD_COLUMNS_OF if _fld_pos in Records.OUTFIELD else FLD_COLUMNS_IF
	var has_key := false
	for col: Array in columns:
		has_key = has_key or col[0] == _sort["fld"][0]
	if not has_key:
		_sort["fld"] = ["total", true]
	var rows := fielding_rows(_fld_pos)
	_ranking_table("fld", columns, rows, true)
	message_changed.emit("%d年・%s・%s・%s：%d人（上位%d人まで表示）。守備得点は同じ守備位置のリーグ平均との差（点）、能力は守備力のランク。%s" % [
		_year, _fld_pos, "規定到達" if _qualified else "全員",
		{"": "両リーグ", "C": "セ・リーグ", "P": "パ・リーグ"}[_league], rows.size(), RANKING_ROWS,
		"規定は試合数×%d回の守備イニング" % int(FIELD_MIN_INNINGS_PER_GAME)])


## 守備ランキングの行 [{id, name, team, rank, row}]（テストからも使う）
func fielding_rows(pos: String) -> Array:
	var result: Array = []
	var st := GameState.season_stats(_year)
	var c := _coef(_year, "")
	if st.is_empty() or c.is_empty():
		return result
	for id: String in st["batting"]:
		var b: Dictionary = st["batting"][id]
		var fld: Dictionary = b.get("fld", {})
		if not fld.has(pos):
			continue
		var team: String = st["players"].get(id, {}).get("team", "")
		if not _league.is_empty() and st["leagues"].get(team, "") != _league:
			continue
		var line: Dictionary = fld[pos]
		var outs := int(line.get("outs", 0))
		var rec: Dictionary = st["records"].get(team, {})
		var games := int(rec.get("w", 0)) + int(rec.get("l", 0)) + int(rec.get("d", 0))
		if outs <= 0 or (_qualified and outs < games * FIELD_MIN_INNINGS_PER_GAME * 3.0):
			continue
		var fr: Dictionary = Records.fielding_runs({"fld": {pos: line}}, c["fielding"])["pos"][pos]
		var row := fr.duplicate()
		row["g"] = int(b.get("pos_g", {}).get(pos, 0))
		row["ch"] = int(line.get("gb", 0)) + int(line.get("ln", 0))
		row["e"] = int(line.get("gbe", 0)) + int(line.get("lne", 0))
		row["kills"] = int(line.get("ahk", 0)) + int(line.get("a3k", 0))
		row["sba"] = int(line.get("sba", 0))
		row["cs_n"] = int(line.get("cs", 0))
		row["cs_pct"] = float(row["cs_n"]) / row["sba"] if row["sba"] > 0 else 0.0
		row["wp_n"] = int(line.get("wp", 0))
		row["per1000"] = float(fr["total"]) / (outs / 3.0) * 1000.0
		result.append({"id": id, "name": st["players"].get(id, {}).get("name", _name_of(id)), "team": team,
			"rank": defense_rank(id, pos), "row": row})
	return result


## 守備の能力（今の能力値の守備力）のランク。その位置の能力値が無ければ空
static func defense_rank(id: String, pos: String) -> String:
	var fielding: Variant = GameData.player(id).get("fielding")
	if not fielding is Dictionary:
		return ""
	var f: Variant = fielding.get(SimTeam.field_key(pos))
	if not f is Dictionary or not f.get("defense") is Dictionary:
		return ""
	return str(f["defense"].get("rank", ""))


## ランキングの行 [{id, name, team, row}]
func _ranking_rows(pitching: bool) -> Array:
	var kind := "pitching" if pitching else "batting"
	var result: Array = []
	if _career:
		var totals := _career_totals(kind)
		var last_year: int = GameState.records_years()[-1] if not GameState.records_years().is_empty() else _year
		for id: String in totals:
			var s: Dictionary = totals[id]
			var team := _team_of(id)
			var lg := GameData.league_of(team) if not team.is_empty() else "C"
			if not _league.is_empty() and lg != _league:
				continue
			if _qualified and (int(s.get("outs", 0)) < CAREER_MIN_OUTS if pitching else int(s.get("pa", 0)) < CAREER_MIN_PA):
				continue
			if int(s.get("outs", 0) if pitching else s.get("pa", 0)) <= 0:
				continue
			var c := _coef(last_year, lg)
			if c.is_empty():
				continue
			result.append({"id": id, "name": _name_of(id), "team": team,
				"row": Records.pitching_row(s, c) if pitching else Records.batting_row(s, c)})
		return result
	var st := GameState.season_stats(_year)
	if st.is_empty():
		return result
	var src: Dictionary = st[kind]
	for id: String in src:
		var s: Dictionary = src[id]
		var team: String = st["players"].get(id, {}).get("team", "")
		var lg: String = st["leagues"].get(team, "")
		if not _league.is_empty() and lg != _league:
			continue
		var rec: Dictionary = st["records"].get(team, {})
		var games := int(rec.get("w", 0)) + int(rec.get("l", 0)) + int(rec.get("d", 0))
		if _qualified:
			if pitching and int(s.get("outs", 0)) < games * 3:
				continue
			if not pitching and float(s.get("pa", 0)) < games * 3.1:
				continue
		if int(s.get("outs", 0) if pitching else s.get("pa", 0)) <= 0:
			continue
		var c := _coef(_year, lg)
		result.append({"id": id, "name": st["players"].get(id, {}).get("name", _name_of(id)), "team": team,
			"row": Records.pitching_row(s, c) if pitching else Records.batting_row(s, c)})
	return result


## その年・リーグの係数（Records.coefficients）
func _coef(y: int, lg: String) -> Dictionary:
	var key := "%d/%s" % [y, lg]
	if _coef_cache.has(key):
		return _coef_cache[key]
	var st := GameState.season_stats(y)
	if st.is_empty():
		return {}
	var league_of := func(id: String) -> String:
		return st["leagues"].get(st["players"].get(id, {}).get("team", ""), "")
	var c := Records.coefficients(st["batting"], st["pitching"], league_of, lg)
	_coef_cache[key] = c
	return c


## 通算（ゲーム開始前の史実＋ゲーム内の各年）
func _career_totals(kind: String) -> Dictionary:
	var totals := {}
	var base: Dictionary = GameState.career_base()[kind]
	for id: String in base:
		Records.add_into(totals.get_or_add(id, {}), base[id])
	for y in GameState.records_years():
		var st := GameState.season_stats(y)
		for id: String in st[kind]:
			Records.add_into(totals.get_or_add(id, {}), st[kind][id])
	return totals


func _team_of(id: String) -> String:
	var league: LeagueRoster = GameState.league
	if league != null and league.team_of.has(id):
		return league.team_of[id]
	var years := GameState.records_years()
	for i in range(years.size() - 1, -1, -1):
		var st := GameState.season_stats(years[i])
		if st["players"].has(id):
			return st["players"][id].get("team", "")
	return ""


func _name_of(id: String) -> String:
	var league: LeagueRoster = GameState.league
	if league != null and league.names.has(id):
		return league.names[id]
	var p := GameData.player(id)
	if not p.is_empty():
		return str(p.get("name", ""))
	return str(GameData.all_player_pages(GameState.first_year).get(id, {}).get("name", id))


# --- デプス ------------------------------------------------------------------------------------

func _build_depth() -> void:
	var teams := GameData.teams()
	var i := maxi(teams.find(_team), 0)
	_team = teams[i]
	for d: int in [-1, 1]:
		var b := _option_button("◀" if d < 0 else "▶", false, func() -> void:
			_team = teams[posmod(teams.find(_team) + d, teams.size())], 40)
		b.toggle_mode = false
		if d > 0:
			var label := UiTheme.small_label(GameData.short_name(_team), 18, UiTheme.TEXT, 800)
			label.custom_minimum_size = Vector2(110, 0)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_options.add_child(label)
		_options.add_child(b)
	for s: Array in DEPTH_SORTS:
		var key: String = s[0]
		_options.add_child(_option_button(s[1], _depth_sort == key, func() -> void: _depth_sort = key))
	var legend := UiTheme.small_label("札の右：現在の能力 → 将来性・年齢　緑の枠＝若手の有望株", 14, UiTheme.TEXT_SUB, 700)
	legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_options.add_child(legend)
	var depth := GameState.depth_of(_team)
	var ranks := Depth.team_ranks(depth)
	for pos: String in Depth.POSITIONS:
		var list: Array = depth[pos]
		Depth.sort_entries(list, _depth_sort)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var head := VBoxContainer.new()
		head.custom_minimum_size = Vector2(150, 0)
		var name_label := Label.new()
		name_label.text = pos
		UiTheme.heading(name_label, 19, _palette.ink, Color.WHITE, 5)
		head.add_child(name_label)
		var rr := HBoxContainer.new()
		rr.add_child(UiTheme.small_label("チーム", 13, UiTheme.TEXT_SUB, 700))
		rr.add_child(_rank(ranks[pos]["now_rank"], 20))
		rr.add_child(UiTheme.small_label("→", 14, UiTheme.TEXT_SUB, 800))
		rr.add_child(_rank(ranks[pos]["future_rank"], 20))
		head.add_child(rr)
		head.add_child(UiTheme.small_label("%s以上 %d人／%d人" % [Depth.THICK_RANK, int(ranks[pos]["thick"]),
			int(ranks[pos]["count"])], 13, UiTheme.TEXT, 700))
		row.add_child(head)
		var flow := HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 4)
		for e: Dictionary in list:
			flow.add_child(_depth_card(e))
		if list.is_empty():
			flow.add_child(UiTheme.small_label("（いない）", 15, UiTheme.TEXT_SUB, 700))
		row.add_child(flow)
		var panel := PanelContainer.new()
		var style := UiTheme.box(Color(1, 1, 1, 0.55), 8)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", style)
		panel.add_child(row)
		_body.add_child(panel)
	message_changed.emit("%sのデプス：守備位置ごとに正選手（先）と控え（2軍を含む）。現在の能力と将来性（ドラフトと同じ見立て・ノイズ入り）。" % GameData.short_name(_team))


func _depth_card(e: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var prospect: bool = e["prospect"]
	var base := Color("fff8e1") if e.get("regular", false) else Color("f4f6f8")
	var style := UiTheme.box(base, 6, PROSPECT_COLOR if prospect else Color("cfd6dd"))
	style.border_width_left = 3 if prospect else 1
	style.border_width_right = style.border_width_left
	style.border_width_top = style.border_width_left
	style.border_width_bottom = style.border_width_left
	style.content_margin_left = 3
	style.content_margin_right = 5
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	panel.add_child(row)
	row.add_child(_tag(e["id"], e["name"], 104.0))
	row.add_child(_rank(e["now_rank"]))
	row.add_child(UiTheme.small_label("→", 12, UiTheme.TEXT_SUB, 800))
	row.add_child(_rank(e["future_rank"]))
	var age_text := "%d歳" % int(e["age"]) if int(e["age"]) > 0 else "-"
	var info := UiTheme.small_label(age_text + ("" if e["active"] else " 2軍"), 13,
		PROSPECT_COLOR if prospect else UiTheme.TEXT, 800)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	if prospect:
		row.add_child(UiTheme.small_label("有望", 13, PROSPECT_COLOR, 800))
	return panel


# --- 守備位置ランク ------------------------------------------------------------------------------

func _build_pos_rank() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header.add_child(_cell("球団", POS_RANK_TEAM_WIDTH, UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_CENTER))
	for pos: String in Depth.POSITIONS:
		header.add_child(_cell(pos, POS_RANK_CELL_WIDTH, UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_CENTER))
	_fixed.add_child(_header_panel(header))
	for lg: String in ["C", "P"]:
		_section(GameData.LEAGUE_NAMES.get(lg, lg), Color("1e88e5") if lg == "C" else Color("43a047"))
		for team: String in GameData.teams(lg):
			var ranks := Depth.team_ranks(GameState.depth_of(team))
			var row := _row_panel(MINE_TINT if team == GameState.team else Color(1, 1, 1, 0.5))
			var b := Button.new()
			b.text = GameData.short_name(team)
			b.custom_minimum_size = Vector2(POS_RANK_TEAM_WIDTH, 30)
			b.clip_text = true
			b.add_theme_font_size_override("font_size", 15)
			var colors := GameData.team_colors(team)
			UiTheme.style_button(b, colors[0], Color.TRANSPARENT, 6, 4)
			b.tooltip_text = "%sのデプスを見る" % team
			b.pressed.connect(func() -> void: set_team(team))
			row.add_child(b)
			for pos: String in Depth.POSITIONS:
				var cell := HBoxContainer.new()
				cell.custom_minimum_size = Vector2(POS_RANK_CELL_WIDTH, 0)
				cell.alignment = BoxContainer.ALIGNMENT_CENTER
				cell.add_child(_rank(ranks[pos]["now_rank"], 20))
				cell.add_child(UiTheme.small_label("→", 12, UiTheme.TEXT_SUB, 800))
				cell.add_child(_rank(ranks[pos]["future_rank"], 20))
				cell.tooltip_text = "%s %s：現在 %s → 将来性 %s（%s以上 %d人）" % [GameData.short_name(team), pos,
					ranks[pos]["now_rank"], ranks[pos]["future_rank"], Depth.THICK_RANK, int(ranks[pos]["thick"])]
				cell.mouse_filter = Control.MOUSE_FILTER_PASS
				row.add_child(cell)
	message_changed.emit("12球団の守備位置ごとのチームランク（現在 → 将来性）。正選手を重く、控え・2軍を軽く数えます。球団名でデプスへ。")


# --- 位置別の戦力（作業34） ------------------------------------------------------------------------

func _build_position_value() -> void:
	for m: Array in PV_MODES:
		var key: String = m[0]
		_options.add_child(_option_button(m[1], _pv_mode == key, func() -> void: _pv_mode = key))
	if _pv_mode == "ability":
		_build_pos_rank()
		return
	var cur := pv_current_year()
	_options.add_child(_option_button("今季（%d年）" % cur, not _pv_last, func() -> void: _pv_last = false))
	_options.add_child(_option_button("昨季（%d年）" % (cur - 1), _pv_last, func() -> void: _pv_last = true))
	var values := position_values()
	if _pv_team.is_empty() or not values.has(_pv_team):
		_pv_team = GameState.team if values.has(GameState.team) else ""
	if values.is_empty():
		_body.add_child(UiTheme.small_label("%d年の成績がまだありません（試合が始まると表示されます）" % shown_pv_year(),
			16, UiTheme.TEXT, 700))
		message_changed.emit("位置別の戦力：%d年の成績がまだありません" % shown_pv_year())
		return
	var note := "（能力から見込んだ値）" if pv_estimated() else ""
	if _pv_mode == "chart":
		_build_pv_chart(values, note)
	else:
		_build_pv_list(values, note)


## 位置別の戦力で見せている年（今季か昨季）
func shown_pv_year() -> int:
	return pv_current_year() - (1 if _pv_last else 0)


## 今季の年（シーズン中・オフの表彰までは Season の年）
func pv_current_year() -> int:
	return GameState.season.year if GameState.season != null else GameState.year


## 昨季がゲームより前の年で、能力から見込んだ値を出しているか
func pv_estimated() -> bool:
	var y := shown_pv_year()
	return y < GameState.first_year and GameState.season_stats(y).is_empty()


## 見せている年の TeamValue の結果（テストからも使う）
func position_values() -> Dictionary:
	var y := shown_pv_year()
	var key := "%d/%s" % [y, pv_estimated()]
	if _pv_cache.has(key):
		return _pv_cache[key]
	var result := {}
	if pv_estimated():
		var ranks := {}
		for team: String in GameData.teams():
			ranks[team] = Depth.team_ranks(GameState.depth_of(team))
		result = TeamValue.estimate(ranks)
	else:
		var st := GameState.season_stats(y)
		if not st.is_empty():
			result = TeamValue.from_stats(st, func(id: String) -> String:
				var pos: Variant = GameData.player(id).get("primary_pos")
				return str(pos) if pos != null else "")
	_pv_cache[key] = result
	return result


## 今季の試合が少ないうちは昨季を初期表示にする（記録室を開いたとき）
func _pv_default_last() -> bool:
	var season: Season = GameState.season
	if season == null:
		return false
	var games := 0
	for team: String in season.records:
		var rec: Dictionary = season.records[team]
		games += int(rec["w"]) + int(rec["l"]) + int(rec["d"])
	return games < PV_MIN_GAMES * maxi(season.records.size(), 1)


func _build_pv_chart(values: Dictionary, note: String) -> void:
	var teams := _pv_team_order()
	var i := maxi(teams.find(_pv_team), 0)
	for d: int in [-1, 1]:
		var b := _option_button("◀" if d < 0 else "▶", false, func() -> void:
			_pv_team = teams[posmod(teams.find(_pv_team) + d, teams.size())], 40)
		b.toggle_mode = false
		if d > 0:
			var label := UiTheme.small_label(GameData.short_name(teams[i]), 18, UiTheme.TEXT, 800)
			label.custom_minimum_size = Vector2(110, 0)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_options.add_child(label)
		_options.add_child(b)
	var team: String = teams[i]
	var v: Dictionary = values[team]
	var colors := GameData.team_colors(team)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	# 球団名の札（一覧の球団名と同じ球団カラーのボタンの見た目。押しても何もしない）
	var badge := Button.new()
	badge.text = team
	badge.focus_mode = Control.FOCUS_NONE
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size = Vector2(260, 36)
	badge.add_theme_font_size_override("font_size", 19)
	UiTheme.style_button(badge, colors[0], Color.TRANSPARENT, 8, 4)
	head.add_child(badge)
	var summary := UiTheme.small_label("合計 %s点　12球団中 %d位　%d年%s" % [Records.format("runs", v["total"]),
		int(v["rank"]), shown_pv_year(), note], 22, UiTheme.TEXT, 800)
	summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(summary)
	_body.add_child(head)
	var chart := TeamValueChart.new()
	chart.name = "TeamValueChart"
	chart.custom_minimum_size = Vector2(RANKING_WIDTH - 20.0, 320)
	chart.set_data(v, colors[0])
	_body.add_child(chart)
	# 内訳（打撃・走塁／守備／投球）
	var parts: Array[String] = []
	for col: String in TeamValue.COLUMNS:
		var c: Dictionary = v[col]
		if col in ["先発", "救援"]:
			parts.append("%s %s" % [TeamValue.SHORT[col], Records.format("runs", c["pit"])])
		else:
			parts.append("%s 打%s・守%s" % [TeamValue.SHORT[col], Records.format("runs", c["bat"]),
				Records.format("runs", c["fld"])])
	var detail := UiTheme.small_label("内訳：" + "　".join(parts), 14, UiTheme.TEXT_SUB, 700)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(RANKING_WIDTH - 20.0, 0)
	_body.add_child(detail)
	message_changed.emit("%d年%s・%s：位置ごとの得失点（リーグ平均＝0、点）。野手は打撃・走塁（wRAA）＋守備得点、投手は FIP からの失点の少なさ。◀▶で球団" % [
		shown_pv_year(), note, GameData.short_name(team)])


## 棒グラフで送る球団の並び（セ・パの順）
func _pv_team_order() -> Array:
	var teams: Array = []
	for lg: String in ["C", "P"]:
		for t: String in GameData.teams(lg):
			teams.append(t)
	if not _pv_team in teams:
		_pv_team = GameState.team if GameState.team in teams else teams[0]
	return teams


func _build_pv_list(values: Dictionary, note: String) -> void:
	var sort: Array = _sort["pv"]
	var key: String = sort[0]
	var teams: Array = values.keys()
	var value_of := func(team: String) -> float:
		match key:
			"total":
				return float(values[team]["total"])
			"rank":
				return float(values[team]["rank"])
		return float(values[team][key]["total"])
	teams.sort_custom(func(a: String, b: String) -> bool:
		var va: float = value_of.call(a)
		var vb: float = value_of.call(b)
		if va == vb:
			return a < b
		return va > vb if sort[1] else va < vb)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header.add_child(_cell("球団", PV_TEAM_WIDTH, UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_CENTER))
	var columns: Array = TeamValue.COLUMNS + ["total", "rank"]
	for col: String in columns:
		var title: String = TeamValue.SHORT.get(col, "合計" if col == "total" else "順位")
		var b := Button.new()
		b.text = title + ("▼" if col == key and sort[1] else "▲" if col == key else "")
		b.custom_minimum_size = Vector2(PV_CELL_WIDTH, 28)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 14)
		UiTheme.style_button(b, _palette.main if col == key else Color("e3e8ee"), Color.TRANSPARENT, 6, 3)
		b.pressed.connect(func() -> void:
			var desc := col != "rank"
			if _sort["pv"][0] == col:
				desc = not _sort["pv"][1]
			_sort["pv"] = [col, desc]
			refresh()
			for c in UiInput.focusables(_fixed):
				if c is Button and (c as Button).text.begins_with(title):
					UiInput.grab(c))
		header.add_child(b)
	_fixed.add_child(_header_panel(header))
	for i in teams.size():
		var team: String = teams[i]
		var v: Dictionary = values[team]
		var row := _row_panel(MINE_TINT if team == GameState.team else Color(1, 1, 1, 0.5 if i % 2 == 0 else 0.25))
		var b := Button.new()
		b.text = GameData.short_name(team)
		b.custom_minimum_size = Vector2(PV_TEAM_WIDTH, 30)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 15)
		UiTheme.style_button(b, GameData.team_colors(team)[0], Color.TRANSPARENT, 6, 4)
		b.tooltip_text = "%sの棒グラフを見る" % team
		b.pressed.connect(func() -> void:
			_pv_team = team
			_pv_mode = "chart"
			refresh()
			focus_first())
		row.add_child(b)
		for col: String in TeamValue.COLUMNS:
			var c: Dictionary = v[col]
			var cell := _pv_cell(float(c["total"]), PV_FULL_COLOR_RUNS)
			cell.tooltip_text = "%s %s：%s点（打撃・走塁 %s・守備 %s・投球 %s）" % [GameData.short_name(team), col,
				Records.format("runs", c["total"]), Records.format("runs", c["bat"]), Records.format("runs", c["fld"]),
				Records.format("runs", c["pit"])]
			row.add_child(cell)
		row.add_child(_pv_cell(float(v["total"]), PV_FULL_COLOR_RUNS * 3.0))
		row.add_child(_cell("%d位" % int(v["rank"]), PV_CELL_WIDTH, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	message_changed.emit("%d年%s：12球団×位置の得失点（リーグ平均＝0、点）。赤はプラス・青はマイナス、濃いほど大きい。見出しで並び替え、球団名で棒グラフへ" % [
		shown_pv_year(), note])


## 得失点の数字のマス（プラスは赤・マイナスは青、full 点で一番濃い）
func _pv_cell(value: float, full: float) -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.box((PV_PLUS if value >= 0.0 else PV_MINUS) * Color(1, 1, 1, clampf(absf(value) / full, 0.0, 1.0) * 0.8), 4)
	style.content_margin_left = 2
	style.content_margin_right = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(PV_CELL_WIDTH, ROW_HEIGHT)
	var strong := absf(value) / full > 0.55
	var label := _cell(Records.format("runs", value), PV_CELL_WIDTH - 8, Color.WHITE if strong else UiTheme.TEXT)
	panel.add_child(label)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	return panel


## スクロールの外に置く見出しの行（スクロールバーの分だけ右を空ける）
func _header_panel(header: HBoxContainer) -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.box(Color(1, 1, 1, 0.85), 6)
	style.content_margin_left = 4
	style.content_margin_right = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(header)
	return panel


# --- チーム成績の推移 ------------------------------------------------------------------------------

func _build_teams() -> void:
	var years := GameState.records_years()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header.add_child(_cell("年", 70, UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_CENTER))
	var columns: Array[String] = []
	for lg: String in ["C", "P"]:
		for team: String in GameData.teams(lg):
			columns.append(team)
			header.add_child(_cell(GameData.short_name(team), TEAM_CELL_WIDTH, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_body.add_child(header)
	if years.is_empty():
		_body.add_child(UiTheme.small_label("まだ記録がありません", 16, UiTheme.TEXT, 700))
	for y in years:
		var st := GameState.season_stats(y)
		var order := _ranks_of(st)
		var row := _row_panel(Color(1, 1, 1, 0.5))
		row.add_child(_cell("%d" % y, 70, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		for team in columns:
			var key := _team_key(st, team)
			var rec: Dictionary = st["records"].get(key, {})
			var text := "-"
			var color := UiTheme.TEXT
			if not rec.is_empty():
				var rank := int(order.get(key, 0))
				text = "%d位 %d-%d" % [rank, int(rec["w"]), int(rec["l"])]
				color = Color("d84315") if rank == 1 else UiTheme.TEXT
				if _champion_of(y) == key:
					color = CHAMPION_COLOR
			var cell := _cell(text, TEAM_CELL_WIDTH, color, HORIZONTAL_ALIGNMENT_CENTER)
			if team == GameState.team:
				cell.add_theme_color_override("font_outline_color", MINE_TINT)
				cell.add_theme_constant_override("outline_size", 6)
			row.add_child(cell)
	_build_postseason_history()
	_build_owner_history()
	message_changed.emit("年ごとの順位と勝敗（ゲーム内のペナント）。赤字はリーグ優勝、金色は日本一。下に歴代の優勝・日本一と、オーナーの評価の歴代。")


## その年の日本一（ポストシーズンの記録が無ければ空）
static func _champion_of(y: int) -> String:
	return str(GameState.postseason_history.get(str(y), {}).get("champion", ""))


## 歴代の優勝・日本一（GameState.postseason_history。CS・日本シリーズの勝ち上がり）
func _build_postseason_history() -> void:
	_section("歴代の優勝・日本一", _palette.ink)
	var keys: Array = GameState.postseason_history.keys()
	keys.sort()
	if keys.is_empty():
		_body.add_child(UiTheme.small_label("まだ日本シリーズを行っていません", 16, UiTheme.TEXT_SUB, 700))
	for key: String in keys:
		var h: Dictionary = GameState.postseason_history[key]
		var row := _row_panel(MINE_TINT if h.get("champion", "") == GameState.team else Color(1, 1, 1, 0.5))
		row.add_child(_cell("%s年" % key, 70, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		for lg: String in ["C", "P"]:
			var won := GameData.short_name(str(h.get("pennant", {}).get(lg, "")))
			row.add_child(_cell("%s優勝 %s" % ["セ" if lg == "C" else "パ", won], 170, UiTheme.TEXT,
				HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(_cell("日本一 %s" % GameData.short_name(str(h.get("champion", ""))), 170, CHAMPION_COLOR,
			HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(_cell("%s %s %s" % [h.get("js_score", ""), "対", GameData.short_name(str(h.get("runner_up", "")))],
			200, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT))
		var mvp := ""
		for sr: Dictionary in h.get("series", []):
			if sr.get("key", "") == "JS" and not str(sr.get("mvp", "")).is_empty():
				mvp = "MVP " + str(GameData.player(sr["mvp"]).get("name", ""))
		row.add_child(_cell(mvp, 220, UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_LEFT))


## オーナーの評価の歴代（作業46。OwnerGoals.evals）：年・球団・評価・点・目標ごとの○×・予算の増減・講評
func _build_owner_history() -> void:
	_section("オーナーの評価の歴代", _palette.ink)
	var og: OwnerGoals = GameState.owner_goals
	var years: Array[int] = og.eval_years() if og != null else []
	if years.is_empty():
		_body.add_child(UiTheme.small_label("まだ評価がありません（シーズンの表彰のあとに出ます）", 16, UiTheme.TEXT_SUB, 700))
		return
	years.reverse()
	for y in years:
		var e: Dictionary = og.eval_of(y)
		var row := _row_panel(Color(1, 1, 1, 0.5))
		row.add_child(_cell("%d年" % y, 70, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		row.add_child(_cell(GameData.short_name(str(e.get("team", ""))), 90, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		var grade := _cell(str(e["grade"]), 40, HubStatusCard.GRADE_COLORS.get(e["grade"], UiTheme.TEXT),
			HORIZONTAL_ALIGNMENT_CENTER)
		grade.add_theme_font_size_override("font_size", 22)
		grade.tooltip_text = "%.2f点" % float(e.get("score", 0.0))
		grade.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(grade)
		var goals: Array[String] = []
		for r: Dictionary in e.get("results", []):
			goals.append("%s%s（%s）" % ["○" if r["done"] else "×", r["text"], r["actual"]])
		var goal_cell := _cell("　".join(goals), 520, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		goal_cell.tooltip_text = "
".join(goals)
		goal_cell.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(goal_cell)
		var delta := int(e.get("budget_delta", 0))
		row.add_child(_cell("予算 %s" % ("±0" if delta == 0 else "%s%s" % ["+" if delta > 0 else "−",
			OwnerGoals.money_text(absi(delta))]), 110, UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_LEFT))
		var comment := _cell("「%s」" % e.get("comment", ""), 260, UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_LEFT)
		comment.tooltip_text = str(e.get("comment", ""))
		comment.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(comment)


## 球団名の年による違い（横浜→DeNA）を吸収して、その年の記録の球団名を返す
static func _team_key(st: Dictionary, team: String) -> String:
	if st["records"].has(team):
		return team
	var short := GameData.short_name(team)
	for key: String in st["records"]:
		if GameData.league_of(key) == GameData.league_of(team) and (short in ["DeNA", "横浜"]) \
				and (key.begins_with("横浜") or key.contains("DeNA")):
			return key
	return team


static func _ranks_of(st: Dictionary) -> Dictionary:
	var result := {}
	for lg: String in ["C", "P"]:
		var rows: Array = []
		for team: String in st["records"]:
			if st["leagues"].get(team, "") != lg:
				continue
			var rec: Dictionary = st["records"][team]
			var dec := int(rec["w"]) + int(rec["l"])
			rows.append([team, float(rec["w"]) / dec if dec > 0 else 0.0])
		rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
		for i in rows.size():
			result[rows[i][0]] = i + 1
	return result


# --- 表彰の歴代 ------------------------------------------------------------------------------------

func _build_awards() -> void:
	var years: Array[int] = []
	for key: String in GameState.awards_history:
		years.append(int(key))
	years.sort()
	if years.is_empty():
		_awards_view.open_year(0)
		message_changed.emit("表彰はシーズン終了後に記録されます。")
		return
	if _awards_year not in years:
		_awards_year = years[-1]
	var i := years.find(_awards_year)
	for d: int in [-1, 1]:
		var b := _option_button("◀" if d < 0 else "▶", false, func() -> void:
			_awards_year = years[clampi(years.find(_awards_year) + d, 0, years.size() - 1)], 40)
		b.toggle_mode = false
		b.disabled = (d < 0 and i == 0) or (d > 0 and i == years.size() - 1)
		if d > 0:
			var label := UiTheme.small_label("%d年" % _awards_year, 18, UiTheme.TEXT, 800)
			label.custom_minimum_size = Vector2(80, 0)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_options.add_child(label)
		_options.add_child(b)
	_awards_view.open_year(_awards_year)


# --- 達成記録 -------------------------------------------------------------------------------

func _build_history() -> void:
	var years := GameState.records_years()
	if years.is_empty():
		_body.add_child(UiTheme.small_label("まだ記録がありません", 16, UiTheme.TEXT, 700))
		return
	if _year not in years:
		_year = years[-1]
	var i := years.find(_year)
	for d: int in [-1, 1]:
		var b := _option_button("◀" if d < 0 else "▶", false, func() -> void:
			_year = years[clampi(years.find(_year) + d, 0, years.size() - 1)], 40)
		b.toggle_mode = false
		b.disabled = (d < 0 and i == 0) or (d > 0 and i == years.size() - 1)
		if d > 0:
			var label := UiTheme.small_label("%d年" % _year, 18, UiTheme.TEXT, 800)
			label.custom_minimum_size = Vector2(80, 0)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_options.add_child(label)
		_options.add_child(b)
	_section("達成記録（ノーヒットノーラン・サイクル安打）", _palette.ink)
	var st := GameState.season_stats(_year)
	var feats: Array = st.get("feats", [])
	if feats.is_empty():
		_body.add_child(UiTheme.small_label("なし", 16, UiTheme.TEXT_SUB, 700))
	for f: Dictionary in feats:
		var row := _row_panel(MINE_TINT if f.get("team", "") == GameState.team else Color(1, 1, 1, 0.5))
		var date: String = f["date"]
		row.add_child(_cell("%d月%d日" % [int(date.substr(5, 2)), int(date.substr(8, 2))], 90, UiTheme.TEXT,
			HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(_cell(f["kind"], 170, Color("d84315"), HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(_tag(f["id"], f["name"]))
		row.add_child(_cell(GameData.short_name(f["team"]), 80, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(_cell("%s" % GameData.short_name(str(f["text"]).trim_suffix("戦")) + "戦", 160, UiTheme.TEXT,
			HORIZONTAL_ALIGNMENT_LEFT))
	_section("通算記録の節目（ニュースの速報から）", _palette.ink)
	var marks: Array = []
	if GameState.news != null:
		for a: Dictionary in GameState.news.of_kind("milestone", _year):
			if a["flash"]:
				marks.append(a)
	if marks.is_empty():
		_body.add_child(UiTheme.small_label("なし", 16, UiTheme.TEXT_SUB, 700))
	for a: Dictionary in marks:
		var mark_row := _row_panel(MINE_TINT if a["mine"] else Color(1, 1, 1, 0.5))
		mark_row.add_child(_cell(News.date_label(a["date"]), 90, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT))
		mark_row.add_child(_cell(a["headline"], 760, Color("d84315"), HORIZONTAL_ALIGNMENT_LEFT))
	message_changed.emit("%d年の達成記録（ノーヒットノーラン・サイクル安打・通算記録の節目）。ドラフトは「歴代ドラフト」へ。" % _year)
