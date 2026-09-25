class_name RosterView
extends TabContainer
## 球団の選手一覧（野手・投手タブ）。一覧はランク表示（docs/SPEC.md「共通ルール」）。

const BATTER_COLUMNS := [
	["meet", "ミート"], ["power", "パワー"], ["eye", "選球眼"],
	["speed", "走力"], ["defense", "守備力"], ["arm", "肩力"],
]
const PITCHER_COLUMNS := [
	["overall", "総合"], ["stamina", "スタミナ"], ["k9", "奪三振"],
	["bb9", "制球"], ["hr9", "被弾抑制"],
]
const RANK_COLUMN_WIDTH := 72

var _shown_key := ""


## 表示中と同じ球団・能力値なら作り直さない
func show_team(team: String) -> void:
	var key := "%s|%s|%s" % [team, GameData.ratings.get("year"), GameData.ratings.get("phase")]
	if key == _shown_key:
		return
	_shown_key = key
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var batters: Array = []
	var pitchers: Array = []
	for p: Dictionary in GameData.players_of(team):
		(pitchers if p["is_pitcher"] else batters).append(p)
	batters.sort_custom(_batter_before)
	pitchers.sort_custom(_pitcher_before)

	_add_tab("野手 (%d)" % batters.size(), _make_batter_tree(batters))
	_add_tab("投手 (%d)" % pitchers.size(), _make_pitcher_tree(pitchers))


func _add_tab(title: String, content: Control) -> void:
	add_child(content)
	set_tab_title(get_tab_count() - 1, title)


func _make_batter_tree(players: Array) -> Tree:
	var tree := _make_tree(["名前", "守備位置", "投打"], BATTER_COLUMNS)
	for p: Dictionary in players:
		var item := tree.create_item()
		item.set_text(0, p["name"])
		item.set_text(1, _str(p["primary_pos"]))
		item.set_text(2, _throws_bats(p))
		_set_ranks(item, 3, p["batting"]["ratings"], BATTER_COLUMNS)
		item.set_metadata(0, p["id"])
	return tree


func _make_pitcher_tree(players: Array) -> Tree:
	var tree := _make_tree(["名前", "役割", "投打"], PITCHER_COLUMNS, ["特殊能力"])
	for p: Dictionary in players:
		var pitching: Dictionary = p["pitching"] if p["pitching"] else {}
		var item := tree.create_item()
		item.set_text(0, p["name"])
		item.set_text(1, _str(pitching.get("role")))
		item.set_text(2, _throws_bats(p))
		_set_ranks(item, 3, pitching.get("ratings", {}), PITCHER_COLUMNS)
		var abilities := PackedStringArray(pitching.get("abilities", []))
		item.set_text(3 + PITCHER_COLUMNS.size(), " ".join(abilities))
		item.set_metadata(0, p["id"])
	return tree


func _make_tree(text_headers: Array, rank_columns: Array, trailing_headers: Array = []) -> Tree:
	var tree := Tree.new()
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.column_titles_visible = true
	tree.columns = text_headers.size() + rank_columns.size() + trailing_headers.size()
	var col := 0
	for header: String in text_headers:
		tree.set_column_title(col, header)
		tree.set_column_expand(col, col == 0)
		if col > 0:
			tree.set_column_custom_minimum_width(col, 96)
		col += 1
	for rank_column: Array in rank_columns:
		tree.set_column_title(col, rank_column[1])
		tree.set_column_expand(col, false)
		tree.set_column_custom_minimum_width(col, RANK_COLUMN_WIDTH)
		col += 1
	for header: String in trailing_headers:
		tree.set_column_title(col, header)
		tree.set_column_expand(col, true)
		col += 1
	tree.create_item()  # 非表示のルート
	return tree


func _set_ranks(item: TreeItem, first_col: int, ratings: Dictionary, columns: Array) -> void:
	for i in columns.size():
		var col := first_col + i
		item.set_text_alignment(col, HORIZONTAL_ALIGNMENT_CENTER)
		var rating: Variant = ratings.get(columns[i][0])
		if rating == null:
			item.set_text(col, "-")
			continue
		item.set_text(col, rating["rank"])
		item.set_custom_color(col, GameData.rank_color(rating["rank"]))
		item.set_custom_font(col, UiTheme.font(800))
		item.set_custom_font_size(col, 22)
		item.set_tooltip_text(col, str(int(rating["value"])))


func _throws_bats(p: Dictionary) -> String:
	if p["throws"] == null or p["bats"] == null:
		return "-"
	return "%s投%s打" % [p["throws"], p["bats"]]


func _str(value: Variant) -> String:
	return "-" if value == null else str(value)


func _batter_before(a: Dictionary, b: Dictionary) -> bool:
	var pa := GameData.pos_index(a["primary_pos"])
	var pb := GameData.pos_index(b["primary_pos"])
	if pa != pb:
		return pa < pb
	return a["name"] < b["name"]


func _pitcher_before(a: Dictionary, b: Dictionary) -> bool:
	var ra: String = a["pitching"]["role"] if a["pitching"] else ""
	var rb: String = b["pitching"]["role"] if b["pitching"] else ""
	if ra != rb:
		return ra == "先発"
	return _overall(a) > _overall(b)


func _overall(p: Dictionary) -> int:
	return int(p["pitching"]["ratings"]["overall"]["value"]) if p["pitching"] else 0
