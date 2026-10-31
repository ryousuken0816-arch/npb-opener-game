# gdlint: disable=max-file-lines
class_name RecordsView
extends VBoxContainer
## 記録室（ハブの「記録室」）。docs/SPEC.md「記録室」、docs/AUTORUN.md 作業10。
##
## タブ（LB/RB＝Q/E でも）：
## - 打撃成績／投手成績：個人成績のランキング（年度別・通算、規定到達者のみ／全員、セ・パ・両リーグ）。列の見出しで並び替え。
##   セイバー指標（wOBA・wRC+・OPS+・ISO・BB%・K%・BABIP／FIP・WHIP・K/9・BB/9・K-BB%、簡易 WAR）は Records で計算
## - チームのデプス：守備位置ごとにスタメン（正選手）と控え（2軍も）を並べ、現在の能力と将来性のランク（Depth）・年齢。
##   若手の有望株（将来性が現在より2段以上高い25歳以下）は緑の枠と「有望」。並び替え（現在の能力／将来性／年齢）、層の厚さ
## - 守備位置ランク：12球団×守備位置のチームとしてのランク（現在→将来性）。球団名でその球団のデプスへ
## - チーム成績の推移：年ごとの順位と勝敗
## - 表彰の歴代：AwardsView を年を選んで表示
## - ドラフト・達成記録：ゲーム内のドラフトの指名結果と、ノーヒットノーラン・サイクル安打
## 名前札は Ⓐ／クリックで選手詳細。Ⓑ はハブへ戻る

signal message_changed(text: String)

const TABS := [["bat", "打撃成績"], ["pit", "投手成績"], ["depth", "チームのデプス"], ["pos_rank", "守備位置ランク"],
	["teams", "チーム成績の推移"], ["awards", "表彰の歴代"], ["history", "ドラフト・達成記録"]]
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
const DEPTH_SORTS := [["now", "現在の能力順"], ["future", "将来性順"], ["age", "年齢順"]]

var _palette: UiTheme.Palette
var _tab := "bat"
var _year := 0
## 表彰の歴代で見ている年（ほかのタブの年とは別）
var _awards_year := 0
var _career := false
var _qualified := true
var _league := ""
var _sort := {"bat": ["avg", true], "pit": ["era", false]}
var _team := ""
var _depth_sort := "now"
var _tab_buttons := {}
var _options: HBoxContainer
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
	row.add_theme_constant_override("separation", 6)
	row.add_child(UiTheme.small_label("◀ LB", 16, UiTheme.TEXT, 800))
	for t: Array in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(140, 38)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 16)
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
	var years := GameState.records_years()
	_year = years[-1] if not years.is_empty() else GameState.year
	_team = GameState.team
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
	for c in UiInput.focusables(_options):
		if UiInput.grab(c):
			return
	UiInput.grab(_tab_buttons[_tab])


func refresh() -> void:
	for key: String in _tab_buttons:
		_tab_buttons[key].set_pressed_no_signal(key == _tab)
	_clear(_options)
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
			_build_pos_rank()
		"teams":
			_build_teams()
		"awards":
			_build_awards()
		"history":
			_build_history()


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
	for c in _options.get_children():
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
	_options.add_child(_option_button("通算", _career, func() -> void: _career = true))
	if not _career:
		_year_stepper()
	_options.add_child(_option_button("規定到達", _qualified, func() -> void: _qualified = true))
	_options.add_child(_option_button("全員", not _qualified, func() -> void: _qualified = false))
	for lg: Array in [["", "両リーグ"], ["C", "セ"], ["P", "パ"]]:
		var key: String = lg[0]
		_options.add_child(_option_button(lg[1], _league == key, func() -> void: _league = key))
	var rows := _ranking_rows(pitching)
	var columns: Array = Records.PIT_COLUMNS if pitching else Records.BAT_COLUMNS
	var sort: Array = _sort[tab]
	var key: String = sort[0]
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var va: float = float(a["row"].get(key, 0))
		var vb: float = float(b["row"].get(key, 0))
		if va == vb:
			return str(a["id"]) < str(b["id"])
		return va > vb if sort[1] else va < vb)
	# 列の幅：画面の中の幅（RANKING_WIDTH）から #・選手・球団と間隔を引いて等分
	var width := (RANKING_WIDTH - 30.0 - 124.0 - 60.0 - 4.0 * (columns.size() + 3)) / columns.size()
	# 見出し（押すと並び替え。もう一度押すと逆順）
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header.add_child(_cell("#", 30, UiTheme.TEXT_SUB))
	header.add_child(_cell("選手", 124, UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_CENTER))
	header.add_child(_cell("球団", 60, UiTheme.TEXT_SUB, HORIZONTAL_ALIGNMENT_LEFT))
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
		for col: Array in columns:
			row.add_child(_cell(Records.format(col[2], r["row"].get(col[0], 0)), width,
				_palette.ink if col[0] == key else UiTheme.TEXT))
	var scope := "通算" if _career else "%d年" % _year
	message_changed.emit("%s・%s・%s：%d人（上位%d人まで表示）。列の見出しで並び替え。%s" % [
		scope, "規定到達" if _qualified else "全員", {"": "両リーグ", "C": "セ・リーグ", "P": "パ・リーグ"}[_league],
		rows.size(), RANKING_ROWS,
		"通算はゲーム開始前の史実の1軍成績を含む（規定は%d打席・%d投球回）" % [CAREER_MIN_PA, CAREER_MIN_OUTS / 3]
			if _career else "規定は試合数×3.1打席・×1.0投球回"])


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
	_body.add_child(header)
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
			header.add_child(_cell(GameData.short_name(team), 88, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
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
			var cell := _cell(text, 88, color, HORIZONTAL_ALIGNMENT_CENTER)
			if team == GameState.team:
				cell.add_theme_color_override("font_outline_color", MINE_TINT)
				cell.add_theme_constant_override("outline_size", 6)
			row.add_child(cell)
	message_changed.emit("年ごとの順位と勝敗（ゲーム内のペナント）。赤字は優勝。")


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


# --- ドラフト・達成記録 -------------------------------------------------------------------------------

func _build_history() -> void:
	var years := GameState.records_years()
	var league: LeagueRoster = GameState.league
	if league != null:
		for id: String in league.drafted:
			var y := int(league.drafted[id]["year"])
			if y not in years:
				years.append(y)
	years.sort()
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
	_section("ドラフト（%d年秋・ゲーム内の指名）" % _year, _palette.ink)
	var by_team := {}
	if league != null:
		for id: String in league.drafted:
			var rec: Dictionary = league.drafted[id]
			if int(rec["year"]) == _year:
				by_team.get_or_add(rec["team"], []).append([id, rec])
	if by_team.is_empty():
		_body.add_child(UiTheme.small_label("この年のドラフトはまだ行っていません", 16, UiTheme.TEXT_SUB, 700))
	for team: String in GameData.teams():
		if not by_team.has(team):
			continue
		var picks: Array = by_team[team]
		picks.sort_custom(func(a: Array, b: Array) -> bool:
			var ia := 1 if a[1]["ikusei"] else 0
			var ib := 1 if b[1]["ikusei"] else 0
			return ia < ib if ia != ib else int(a[1]["round"]) < int(b[1]["round"]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var team_label := _cell(GameData.short_name(team), 90, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		team_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(team_label)
		var flow := HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 4)
		for pick: Array in picks:
			var rec: Dictionary = pick[1]
			var box := HBoxContainer.new()
			box.add_theme_constant_override("separation", 2)
			var label := "育成%d" % int(rec["round"]) if rec["ikusei"] else "%d位" % int(rec["round"])
			box.add_child(UiTheme.small_label(label, 13, UiTheme.TEXT_SUB, 800))
			box.add_child(_tag(pick[0], _name_of(pick[0]), 104.0))
			flow.add_child(box)
		row.add_child(flow)
		var panel := PanelContainer.new()
		var style := UiTheme.box(MINE_TINT if team == GameState.team else Color(1, 1, 1, 0.5), 6)
		style.content_margin_left = 4
		style.content_margin_right = 4
		panel.add_theme_stylebox_override("panel", style)
		panel.add_child(row)
		_body.add_child(panel)
	message_changed.emit("%d年の達成記録と、%d年秋のドラフトの指名結果（ゲーム内）。" % [_year, _year])
