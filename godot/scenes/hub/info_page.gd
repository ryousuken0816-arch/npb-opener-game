class_name InfoPage
extends HBoxContainer
## 采配 → 情報：12球団の年俸総額（人数・平均・最高額）と、自球団の年俸の高い順の一覧。
## 年俸は GameState.league（LeagueRoster）。一覧の行をⒶ（Enter）／クリックで選手詳細。

var _palette: UiTheme.Palette
var _shown_key := ""
var _trees: Array[Tree] = []


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	add_theme_constant_override("separation", 12)


func refresh() -> void:
	var key := "%d|%d|%d" % [GameState.year, GameState.phase, GameState.roster_version]
	if key == _shown_key:
		return
	_shown_key = key
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_trees.clear()
	var league := GameState.league
	if league == null:
		return
	var left := UiTheme.titled_panel(_palette, "12球団の年俸総額")
	left["panel"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left["panel"].size_flags_stretch_ratio = 1.4
	add_child(left["panel"])
	var teams := _team_tree(league)
	left["body"].add_child(teams)
	var note := UiTheme.small_label("年俸は%s。総額にカーソルを合わせると平均。" % _contract_label(), 14)
	left["body"].add_child(note)

	var right := UiTheme.titled_panel(_palette, "%sの年俸（高い順）" % GameData.short_name(GameState.team))
	right["panel"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right["panel"])
	right["body"].add_child(_player_tree(league))


func focus_first() -> void:
	if not _trees.is_empty():
		_trees[0].grab_focus()


## 契約更改（CONTRACT）〜ドラフトの間は来季の額になっている
func _contract_label() -> String:
	if GameState.phase in [GameState.Phase.CONTRACT, GameState.Phase.RELEASE, GameState.Phase.DRAFT]:
		return "%d年の契約（更改済み）" % (GameState.year + 1)
	return "%d年の契約" % GameState.year


func _team_tree(league: LeagueRoster) -> Tree:
	var tree := _tree(["順位", "球団", "人数", "総額", "最高額"], [52, 120, 64, 150, 0])
	var rows: Array = []
	for team: String in GameData.teams():
		var ids := league.players_of(team)
		var top := ""
		var top_amount := -1
		for id in ids:
			if league.salary_of(id) > top_amount:
				top_amount = league.salary_of(id)
				top = id
		rows.append({"team": team, "count": ids.size(), "total": league.payroll(team), "top": top,
			"top_amount": top_amount})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["total"] > b["total"])
	for i in rows.size():
		var r: Dictionary = rows[i]
		var item := tree.create_item()
		item.set_text(0, str(i + 1))
		item.set_text(1, GameData.short_name(r["team"]))
		item.set_tooltip_text(1, r["team"])
		item.set_text(2, "%d人" % r["count"])
		item.set_text(3, Salary.text(r["total"]))
		item.set_tooltip_text(3, "平均 %s" % Salary.text(
				Salary.round_amount(float(r["total"]) / maxi(1, r["count"]))))
		var top_name: String = league.names.get(r["top"], "")
		item.set_text(4, "%s %s" % [top_name.get_slice(" ", 0), Salary.text(r["top_amount"])])
		item.set_tooltip_text(4, top_name)
		for col in [0, 2, 3]:
			item.set_text_alignment(col, HORIZONTAL_ALIGNMENT_RIGHT)
		if r["team"] == GameState.team:
			for col in 5:
				item.set_custom_bg_color(col, _palette.main.lerp(Color.WHITE, 0.75))
		item.set_metadata(0, r["top"])
	return tree


func _player_tree(league: LeagueRoster) -> Tree:
	var tree := _tree(["名前", "守備", "在籍", "年俸"], [0, 76, 64, 124])
	var ids := league.players_of(GameState.team)
	ids.sort_custom(func(a: String, b: String) -> bool:
		return league.salary_of(a) > league.salary_of(b))
	var year := GameState.year
	for id in ids:
		var p := GameData.player(id)
		var item := tree.create_item()
		item.set_text(0, league.names.get(id, id))
		var pos: Variant = p.get("primary_pos")
		item.set_text(1, str(pos).trim_suffix("手") if pos != null else "-")
		item.set_text(2, "%d年目" % league.years_in_npb(id, year))
		item.set_text(3, Salary.text(league.salary_of(id)))
		item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
		item.set_text_alignment(3, HORIZONTAL_ALIGNMENT_RIGHT)
		item.set_metadata(0, id)
	return tree


func _tree(titles: Array, widths: Array) -> Tree:
	var tree := Tree.new()
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.column_titles_visible = true
	tree.columns = titles.size()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for i in titles.size():
		tree.set_column_title(i, titles[i])
		tree.set_column_expand(i, widths[i] == 0)
		if widths[i] > 0:
			tree.set_column_custom_minimum_width(i, widths[i])
	tree.create_item()
	_trees.append(tree)
	tree.item_activated.connect(_open_detail.bind(tree))
	tree.item_mouse_selected.connect(func(_pos: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT:
			_open_detail(tree))
	return tree


func _open_detail(tree: Tree) -> void:
	var item := tree.get_selected()
	if item == null or item.get_metadata(0) == null or str(item.get_metadata(0)).is_empty():
		return
	var ids: Array[String] = []
	var row := tree.get_root().get_first_child()
	while row != null:
		if row.get_metadata(0) != null and not str(row.get_metadata(0)).is_empty():
			ids.append(str(row.get_metadata(0)))
		row = row.get_next()
	PlayerDetail.open(tree, str(item.get_metadata(0)), ids)
