class_name CareerPage
extends HBoxContainer
## 選手詳細の「経歴」タブ：プロフィール（生年月日・ドラフト年と順位・1軍初出場・出身校〜経歴）と所属球団の推移。
## 所属球団の推移は史実の年度別成績（選手ページ）の「所属球団」から作る（1軍に出場した年のみ）＋今季の球団。

## 受賞歴の札を出す最大の数（新しい順）
const AWARDS_SHOWN := 8

var player_id := ""

var _detail: PlayerDetail
var _data: Dictionary
var _page: Dictionary
var _palette: UiTheme.Palette
var _team_name := ""


func setup(detail: PlayerDetail, data: Dictionary, page: Dictionary,
		palette: UiTheme.Palette) -> void:
	_detail = detail
	_data = data
	_page = page
	_palette = palette
	player_id = str(data.get("id", ""))
	_team_name = str(data.get("team", ""))
	_build()



func _build() -> void:
	add_theme_constant_override("separation", 12)
	var profile := UiTheme.titled_panel(_palette, "プロフィール")
	profile["panel"].custom_minimum_size = Vector2(620, 0)
	add_child(profile["panel"])
	# 受賞歴が増えると縦に伸びるので、プロフィールの中身は縦のスクロールの中へ（選手詳細の枠からはみ出さない。作業11）
	var pscroll := ScrollContainer.new()
	pscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	profile["body"].add_child(pscroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", profile["body"].get_theme_constant("separation"))
	pscroll.add_child(body)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	var draft := _draft_parts()
	for pair: Array in [
		["生年月日", _birth_text()],
		["身長／体重", _detail.body_text()],
		["投打", _detail.throws_bats()],
		["ドラフト", draft[0]],
		["指名順位", draft[1]],
		["1軍初出場", _debut_text()],
	]:
		grid.add_child(PlayerDetail.pill(pair[0], 120))
		var value := UiTheme.small_label(pair[1], 19, UiTheme.TEXT, 700)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.custom_minimum_size = Vector2(440, 0)
		grid.add_child(value)
	body.add_child(UiTheme.small_label("出身校〜経歴", 16, _palette.ink, 800))
	body.add_child(_career_chain())
	body.add_child(UiTheme.small_label("受賞歴（ゲーム内の表彰）", 16, _palette.ink, 800))
	body.add_child(_awards_flow())

	var teams := UiTheme.titled_panel(_palette, "所属球団の推移")
	teams["panel"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(teams["panel"])
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	teams["body"].add_child(scroll)
	_detail.use_scroll(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for period: Dictionary in _team_periods():
		list.add_child(_period_row(period))
	teams["body"].add_child(UiTheme.small_label("前年までは1軍に出場した年から。2軍だけの年は含みません。", 13))


func _birth_text() -> String:
	var birth: Variant = _data.get("birth")
	if birth == null or str(birth).length() < 10:
		return "-"
	var b := str(birth)
	var text := "%d年%d月%d日" % [int(b.substr(0, 4)), int(b.substr(5, 2)), int(b.substr(8, 2))]
	var age := _detail.age()
	return text + ("（%d歳）" % age if age >= 0 else "")


## ドラフト [年, 順位]。例: "2000年ドラフト1位" → ["2000年", "ドラフト1位"]。指名歴が無ければ ["-", "-"]
func _draft_parts() -> Array[String]:
	var draft := str(_data.get("draft", "")) if _data.get("draft") != null else ""
	if draft.is_empty():
		var sim := _detail.sim_team()
		var foreign := sim != null and sim.by_id.has(player_id) \
			and (sim.by_id[player_id] as SimPlayer).is_foreign
		return ["指名なし（外国人・自由契約などで入団）" if foreign else "指名なし", "-"]
	var re := RegEx.create_from_string("^(\\d{4})年(.+)$")
	var m := re.search(draft)
	if m == null:
		return [draft, "-"]
	return [m.get_string(1) + "年", m.get_string(2)]


func _debut_text() -> String:
	var debut: Variant = GameData.load_debut_years(_detail.data_year()).get(player_id)
	if debut != null:
		return "%d年" % int(debut)
	var first := 9999
	for kind in ["batting", "pitching"]:
		for h: Variant in _page.get(kind, []):
			if h is Dictionary and int(h.get("年度", 9999)) < GameState.year:
				first = mini(first, int(h["年度"]))
	return "%d年" % first if first < 9999 else "まだ出場なし"


## 経歴（"安田学園高 - 中央大"）を矢印でつないだ札の列。最後に今の球団
func _career_chain() -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	var steps: Array[String] = []
	var career: Variant = _data.get("career")
	if career != null:
		for s: String in str(career).split(" - ", false):
			steps.append(s.strip_edges())
	if steps.is_empty():
		steps.append("（経歴のデータなし）")
	for i in steps.size():
		flow.add_child(_chip(steps[i], Color("eef2f6"), UiTheme.TEXT))
		flow.add_child(UiTheme.small_label("→", 18, UiTheme.TEXT_SUB, 800))
	flow.add_child(_chip(GameData.short_name(_team_name), _palette.main, _palette.on_main))
	return flow


## ゲーム内の受賞歴（GameState.player_awards）を「2008 MVP」の札で。無ければ「なし」
func _awards_flow() -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	var awards := GameState.player_awards(player_id)
	if awards.is_empty():
		flow.add_child(UiTheme.small_label("なし", 16, UiTheme.TEXT_SUB, 700))
	# 多いと枠からはみ出すので新しいほうから AWARDS_SHOWN 件（全部は記録室で）
	var shown := awards.slice(maxi(awards.size() - AWARDS_SHOWN, 0))
	if shown.size() < awards.size():
		flow.add_child(_chip("ほか%d件" % (awards.size() - shown.size()), Color("eef2f6"), UiTheme.TEXT_SUB))
	for a: Dictionary in shown:
		flow.add_child(_chip("%d %s" % [int(a["year"]), a["name"]], Color("ffd54f"), UiTheme.TEXT))
	return flow


func _chip(text: String, color: Color, fg: Color) -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.gloss(color, 8, 1, 2)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.shadow_size = 1
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(UiTheme.small_label(text, 16, fg, 800))
	return panel


## 所属球団の推移 [{from, to, team, current}]。史実の年度別成績の「所属球団」が続く年をまとめ、最後に今季
func _team_periods() -> Array:
	var by_year := {}
	for kind in ["batting", "pitching"]:
		for h: Variant in _page.get(kind, []):
			if not h is Dictionary or int(h.get("年度", 0)) >= GameState.year:
				continue
			var year := int(h["年度"])
			var teams: Array = by_year.get(year, [])
			var team := str(h.get("所属球団", ""))
			if not teams.has(team):
				teams.append(team)
			by_year[year] = teams
	var years := by_year.keys()
	years.sort()
	var periods: Array = []
	for year: int in years:
		for team: String in by_year[year]:
			var last: Dictionary = periods[-1] if not periods.is_empty() else {}
			if not last.is_empty() and last["team"] == team:
				last["to"] = year
			else:
				periods.append({"from": year, "to": year, "team": team, "current": false})
	var current_short := GameData.short_name(_team_name)
	var last_period: Dictionary = periods[-1] if not periods.is_empty() else {}
	if not last_period.is_empty() and _same_team(str(last_period["team"]), _team_name):
		last_period["to"] = GameState.year
		last_period["current"] = true
		last_period["team"] = current_short
	else:
		periods.append({"from": GameState.year, "to": GameState.year, "team": current_short,
			"current": true})
	return periods


## 選手ページの球団名（"読売" "広島東洋" など）が正式名の球団か
func _same_team(short: String, full: String) -> bool:
	return not short.is_empty() and (full.begins_with(short) or GameData.short_name(full) == short)


func _period_row(period: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var years := "%d年" % period["from"]
	if period["current"]:
		years = "%d年〜" % period["from"] if period["from"] != period["to"] else "%d年" % period["from"]
	elif period["to"] != period["from"]:
		years = "%d〜%d年" % [period["from"], period["to"]]
	var year_label := UiTheme.small_label(years, 18, UiTheme.TEXT, 800)
	year_label.custom_minimum_size = Vector2(130, 0)
	row.add_child(year_label)
	var full := _full_team_name(str(period["team"]))
	var colors: Array = [Color("9aa3ad"), Color("5f6670")]  # 今は無い球団
	if not full.is_empty():
		colors = GameData.team_colors(full)
	var chip := _chip(str(period["team"]), colors[0], UiTheme.text_on(colors[0]))
	chip.custom_minimum_size = Vector2(160, 0)
	row.add_child(chip)
	if period["current"]:
		row.add_child(UiTheme.small_label("現在", 16, Color("d84315"), 800))
	return row


## 選手ページの球団名 → 正式名（色を付けるため。見つからなければ空＝今は無い球団）
func _full_team_name(short: String) -> String:
	for full: String in GameData.TEAM_COLORS:
		if _same_team(short, full) or full.contains(short):
			return full
	return ""
