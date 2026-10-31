class_name ContractPage
extends HBoxContainer
## 選手詳細の「契約」タブ：年俸（GameState.league）・前年比・在籍年数・球団内の割合と、ゲーム内の年俸の推移。
## 所属していない選手は状態（外国人市場の提示額・メジャー・引退）。

var _detail: PlayerDetail
var _id := ""
var _team := ""
var _palette: UiTheme.Palette


func setup(detail: PlayerDetail, id: String, team: String, palette: UiTheme.Palette) -> void:
	_detail = detail
	_id = id
	_team = team
	_palette = palette
	_build()


func _build() -> void:
	var row := self
	row.add_theme_constant_override("separation", 12)
	var league := GameState.league
	var card := _detail.card("契約")
	card["panel"].custom_minimum_size = Vector2(660, 0)
	row.add_child(card["panel"])
	var body: VBoxContainer = card["body"]
	body.add_theme_constant_override("separation", 5)
	if league == null:
		body.add_child(_detail.note_label("ゲームを始めると表示されます。"))
		return
	var amount := league.salary_of(_id)
	var history: Array = league.salary_history.get(_id, [])
	var contract_year: int = history[-1]["year"] if not history.is_empty() else GameState.year
	if league.market.has(_id):
		var info: Dictionary = league.market_info[_id]
		var note := "外国人市場の候補（史実は%s）" % GameData.short_name(info["hist_team"])
		if info.get("fictional", false):
			note = "外国人市場の候補（架空の選手）"
		body.add_child(_detail.value_row("提示額", Salary.text(info["asking"]), "", note))
	elif league.team_of.has(_id):
		body.add_child(_detail.value_row("年俸", Salary.text(amount), "", "%d年" % contract_year))
		if history.size() >= 2:
			var diff: int = history[-1]["salary"] - history[-2]["salary"]
			var sign := "+" if diff >= 0 else "−"
			body.add_child(_detail.value_row("前年比", "%s%s" % [sign, Salary.text(absi(diff))], "",
					"%d年 %s" % [history[-2]["year"], Salary.text(history[-2]["salary"])]))
		var years := league.years_in_npb(_id, contract_year)
		body.add_child(_detail.value_row("在籍", "%d年目" % years, "",
				"%d年に入団" % int(league.joined.get(_id, contract_year))))
		var payroll := league.payroll(_team)
		if payroll > 0:
			body.add_child(_detail.value_row("球団内", "%.1f%%" % (100.0 * amount / payroll), "",
					"総額 %s" % Salary.text(payroll)))
	else:
		body.add_child(_detail.value_row("状態", _detail.unattached_text(), "", ""))
	var note := _detail.note_label("年俸は能力値（直近3年の成績）・在籍年数・年齢から計算し、オフの契約更改で今季の成績に応じて上下します。"
			+ "新人はドラフト順位で決まります。")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.clip_text = false
	body.add_child(note)

	var hist_card := _detail.card("年俸の推移")
	hist_card["panel"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hist_card["panel"])
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	hist_card["body"].add_child(grid)
	for title: String in ["年度", "球団", "年俸", "増減"]:
		grid.add_child(UiTheme.small_label(title, 15, _palette.ink, 800))
	var previous := -1
	for h: Dictionary in history:
		grid.add_child(UiTheme.small_label("%d年" % h["year"], 17, UiTheme.TEXT, 700))
		grid.add_child(UiTheme.small_label(GameData.short_name(h["team"]) if h["team"] != "" else "-", 17,
				UiTheme.TEXT, 700))
		grid.add_child(UiTheme.small_label(Salary.text(h["salary"]), 17, UiTheme.TEXT, 700))
		var change := "-"
		if previous >= 0:
			var d: int = h["salary"] - previous
			change = ("+" if d >= 0 else "−") + Salary.text(absi(d))
		grid.add_child(UiTheme.small_label(change, 17, UiTheme.TEXT_SUB, 700))
		previous = h["salary"]
	if history.is_empty():
		hist_card["body"].add_child(_detail.note_label("契約の記録はまだありません。"))
