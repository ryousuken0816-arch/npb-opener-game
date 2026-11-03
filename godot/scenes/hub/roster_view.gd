class_name RosterView
extends TabContainer
## 球団の選手一覧（野手・投手タブ）。一覧はランク表示（docs/SPEC.md「共通ルール」）。
## 行をクリック（コントローラーは Ⓐ・キーボードは Enter）で選手詳細。十字キーの前後はその一覧の並び。
## 能力のマスは「B 74」（ランクと数値、ランクの色。作業64）。見出しをクリックすると数値の高い順に並び替え（もう一度で逆順）。

## 並びは選手詳細と同じ（作業72）。投手の "velocity" は球速（km/h）の列
const BATTER_COLUMNS := [
	["meet", "ミート"], ["power", "パワー"], ["speed", "走力"],
	["arm", "肩力"], ["defense", "守備力"], ["eye", "選球眼"],
]
const PITCHER_COLUMNS := [
	["overall", "総合"], ["velocity", "球速"], ["bb9", "制球"], ["stamina", "スタミナ"],
	["k9", "奪三振"], ["hr9", "被弾抑制"],
]
const RANK_COLUMN_WIDTH := 80
const SALARY_COLUMN_WIDTH := 120
const VELOCITY_COLUMN_WIDTH := 72
const ABILITY_COLUMN_WIDTH := 72
## 今季の成績タブ（GameState.season）の列 [見出し, 幅]
const BATTING_STAT_COLUMNS := [
	["試合", 48], ["打席", 52], ["打率", 56], ["本塁打", 60], ["打点", 48],
	["盗塁", 48], ["四球", 48], ["三振", 48], ["出塁率", 60],
]
const PITCHING_STAT_COLUMNS := [
	["登板", 48], ["先発", 48], ["勝", 40], ["敗", 40], ["S", 40], ["H", 40],
	["投球回", 76], ["防御率", 60], ["奪三振", 60],
]

var _shown_key := ""


## 表示中と同じ球団・能力値なら作り直さない
func show_team(team: String) -> void:
	var season := GameState.season
	var key := "%s|%s|%s|%d|%d" % [team, GameData.ratings.get("year"), GameData.ratings.get("phase"),
		season.played_count() if season != null else -1, GameState.roster_version]
	var tab := current_tab
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
	if season != null:
		_add_tab("打撃成績", _make_batting_stats_tree(batters + pitchers, season))
		_add_tab("投手成績", _make_pitching_stats_tree(pitchers, season))
	current_tab = clampi(tab, 0, get_tab_count() - 1)


## LB/RB：タブの切り替え（一覧にフォーカスを移す）
func switch_tab(delta: int) -> void:
	if get_tab_count() == 0:
		return
	current_tab = posmod(current_tab + delta, get_tab_count())
	focus_content()
	UiFx.fade_in(get_current_tab_control())


## 表示中のタブの一覧にフォーカス（十字キーの上下で行を選べる）
func focus_content() -> void:
	var tree := get_current_tab_control() as Tree
	if tree == null:
		return
	tree.grab_focus()
	var root := tree.get_root()
	if tree.get_selected() == null and root != null and root.get_first_child() != null:
		tree.set_selected(root.get_first_child(), 0)


func _add_tab(title: String, content: Control) -> void:
	var tree := content as Tree
	if tree != null:
		tree.item_activated.connect(_open_detail.bind(tree))
		tree.item_mouse_selected.connect(func(_pos: Vector2, button: int) -> void:
			if button == MOUSE_BUTTON_LEFT:
				_open_detail(tree))
	add_child(content)
	set_tab_title(get_tab_count() - 1, title)


## 選んでいる行の選手の詳細を開く（前後の選手はこの一覧の並び）
func _open_detail(tree: Tree) -> void:
	var item := tree.get_selected()
	if item == null or item.get_metadata(0) == null:
		return
	var ids: Array[String] = []
	var row := tree.get_root().get_first_child()
	while row != null:
		ids.append(str(row.get_metadata(0)))
		row = row.get_next()
	PlayerDetail.open(tree, str(item.get_metadata(0)), ids)


func _make_batter_tree(players: Array) -> Tree:
	var tree := _make_tree(["名前", "守備位置", "投打"], BATTER_COLUMNS, ["年俸"])
	for p: Dictionary in players:
		var item := tree.create_item()
		item.set_text(0, p["name"])
		item.set_text(1, _str(p["primary_pos"]))
		item.set_text(2, _throws_bats(p))
		_set_ranks(item, 3, p["batting"]["ratings"], BATTER_COLUMNS)
		_set_salary(item, 3 + BATTER_COLUMNS.size(), p["id"])
		item.set_metadata(0, p["id"])
	return tree


func _make_pitcher_tree(players: Array) -> Tree:
	var tree := _make_tree(["名前", "役割", "投"], PITCHER_COLUMNS, ["特能", "年俸"])
	for p: Dictionary in players:
		var pitching: Dictionary = p["pitching"] if p["pitching"] else {}
		var item := tree.create_item()
		item.set_text(0, p["name"])
		item.set_text(1, _str(pitching.get("role")))
		item.set_text(2, "%s投" % p["throws"] if p["throws"] != null else "-")  # 投手は投げる手だけ（表を横にはみ出させない）
		var ratings: Variant = pitching.get("ratings")
		_set_ranks(item, 3, ratings if ratings is Dictionary else {}, PITCHER_COLUMNS)
		_set_velocity(item, 3 + PITCHER_COLUMNS.find(["velocity", "球速"]), pitching)
		var abilities := PackedStringArray(pitching.get("abilities", []))
		item.set_text(3 + PITCHER_COLUMNS.size(), " ".join(abilities))
		item.set_tooltip_text(3 + PITCHER_COLUMNS.size(), " ".join(abilities))
		_set_salary(item, 4 + PITCHER_COLUMNS.size(), p["id"])
		item.set_metadata(0, p["id"])
	return tree


## 今季の打撃成績（出場した選手のみ、打席の多い順）
func _make_batting_stats_tree(players: Array, season: Season) -> Tree:
	var rows: Array = []
	for p: Dictionary in players:
		var b: Dictionary = season.batting.get(p["id"], {})
		if not b.is_empty():
			rows.append([p, b])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return x[1]["pa"] > y[1]["pa"])
	var tree := _make_stats_tree(BATTING_STAT_COLUMNS)
	for row: Array in rows:
		var p: Dictionary = row[0]
		var b: Dictionary = row[1]
		var obp_den: int = b["ab"] + b["bb"] + b["hbp"] + b["sf"]
		var obp := float(b["h"] + b["bb"] + b["hbp"]) / obp_den if obp_den > 0 else 0.0
		var item := tree.create_item()
		item.set_text(0, p["name"])
		item.set_metadata(0, p["id"])
		_set_stat_texts(item, [
			b["g"], b["pa"], _rate(Season.batting_avg(b)) if b["ab"] > 0 else "-", b["hr"],
			b["rbi"], b["sb"], b["bb"], b["so"], _rate(obp) if obp_den > 0 else "-",
		])
	return tree


## 今季の投手成績（登板した投手のみ、投球回の多い順）
func _make_pitching_stats_tree(players: Array, season: Season) -> Tree:
	var rows: Array = []
	for p: Dictionary in players:
		var s: Dictionary = season.pitching.get(p["id"], {})
		if not s.is_empty():
			rows.append([p, s])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return x[1]["outs"] > y[1]["outs"])
	var tree := _make_stats_tree(PITCHING_STAT_COLUMNS)
	for row: Array in rows:
		var p: Dictionary = row[0]
		var s: Dictionary = row[1]
		var outs: int = s["outs"]
		var item := tree.create_item()
		item.set_text(0, p["name"])
		item.set_metadata(0, p["id"])
		_set_stat_texts(item, [
			s["g"], s["gs"], s["w"], s["l"], s["sv"], s["hld"],
			"%d %d/3" % [outs / 3, outs % 3] if outs % 3 != 0 else str(outs / 3),
			"%.2f" % Season.era(s) if outs > 0 else "-", s["so"],
		])
	return tree


func _make_stats_tree(columns: Array) -> Tree:
	var tree := Tree.new()
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.column_titles_visible = true
	tree.columns = 1 + columns.size()
	tree.set_column_title(0, "名前")
	tree.set_column_expand(0, true)
	for i in columns.size():
		tree.set_column_title(i + 1, columns[i][0])
		tree.set_column_expand(i + 1, false)
		tree.set_column_custom_minimum_width(i + 1, columns[i][1])
	tree.create_item()  # 非表示のルート
	return tree


## 見出しのクリックで並び替え：並びの値（各マスのメタデータ）の高い順。同じ列をもう一度で逆順
func _on_title_clicked(column: int, _mouse_button: int, tree: Tree) -> void:
	var root := tree.get_root()
	if root == null or root.get_first_child() == null or not root.get_first_child().get_metadata(column) is float:
		return
	var descending: bool = tree.get_meta("sort_column", -1) != column or not tree.get_meta("sort_desc", true)
	tree.set_meta("sort_column", column)
	tree.set_meta("sort_desc", descending)
	var items: Array[TreeItem] = []
	var row := root.get_first_child()
	while row != null:
		items.append(row)
		row = row.get_next()
	items.sort_custom(func(a: TreeItem, b: TreeItem) -> bool:
		var ma: Variant = a.get_metadata(column)
		var mb: Variant = b.get_metadata(column)
		var va: float = ma if ma is float else -1.0
		var vb: float = mb if mb is float else -1.0
		return va > vb if descending else va < vb)
	for i in range(items.size() - 1, -1, -1):
		items[i].move_before(root.get_first_child())


func _set_stat_texts(item: TreeItem, values: Array) -> void:
	for i in values.size():
		item.set_text(i + 1, str(values[i]))
		item.set_text_alignment(i + 1, HORIZONTAL_ALIGNMENT_RIGHT)
		item.set_custom_font(i + 1, UiTheme.font(700))


## 打率などの表示（".312"）
func _rate(value: float) -> String:
	return ("%.3f" % value).trim_prefix("0")


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
			tree.set_column_custom_minimum_width(col, 64 if header in ["役割", "投"] else 96)
		col += 1
	for rank_column: Array in rank_columns:
		tree.set_column_title(col, rank_column[1])
		tree.set_column_expand(col, false)
		tree.set_column_custom_minimum_width(col, VELOCITY_COLUMN_WIDTH if rank_column[0] == "velocity"
			else RANK_COLUMN_WIDTH)
		col += 1
	for header: String in trailing_headers:
		tree.set_column_title(col, header)
		tree.set_column_expand(col, header != "年俸" and header != "球速" and header != "特能")
		if header == "年俸":
			tree.set_column_custom_minimum_width(col, SALARY_COLUMN_WIDTH)
		elif header == "球速":
			tree.set_column_custom_minimum_width(col, VELOCITY_COLUMN_WIDTH)
		elif header == "特能":
			# 特殊能力は長いと表が横にはみ出すので幅を決めて切る（全部はツールチップ）
			tree.set_column_custom_minimum_width(col, ABILITY_COLUMN_WIDTH)
			tree.set_column_clip_content(col, true)
		col += 1
	tree.create_item()  # 非表示のルート
	tree.column_title_clicked.connect(_on_title_clicked.bind(tree))
	return tree


func _set_ranks(item: TreeItem, first_col: int, ratings: Dictionary, columns: Array) -> void:
	for i in columns.size():
		var col := first_col + i
		if columns[i][0] == "velocity":
			continue  # 球速は _set_velocity
		item.set_text_alignment(col, HORIZONTAL_ALIGNMENT_CENTER)
		var rating: Variant = ratings.get(columns[i][0])
		if rating == null:
			item.set_text(col, "-")
			continue
		item.set_text(col, "%s %d" % [rating["rank"], int(rating["value"])])
		item.set_metadata(col, float(rating["value"]))
		_paint_rank(item, col, rating["rank"])
		item.set_custom_font(col, UiTheme.font(800))
		item.set_custom_font_size(col, 20)
		item.set_tooltip_text(col, "%s %d" % [rating["rank"], int(rating["value"])])


## ランクの色：文字は濃い色、マスの背景は薄い同じ色（作業64。色の決まりは UiTheme.RANK_COLORS）
static func _paint_rank(item: TreeItem, col: int, rank: String) -> void:
	item.set_custom_color(col, UiTheme.rank_color(rank).darkened(0.08))
	item.set_custom_bg_color(col, UiTheme.rank_bg(rank))


## 球速（km/h）：目安のランク（UiTheme.velocity_rank）の色を付ける
func _set_velocity(item: TreeItem, col: int, pitching: Dictionary) -> void:
	item.set_text_alignment(col, HORIZONTAL_ALIGNMENT_CENTER)
	var v: Variant = pitching.get("velocity")
	var kmh := float(v.get("kmh", 0.0)) if v is Dictionary and v.get("kmh") != null else 0.0
	if kmh <= 0.0:
		item.set_text(col, "-")
		return
	item.set_text(col, str(roundi(kmh)))
	item.set_metadata(col, kmh)
	item.set_tooltip_text(col, "%dkm/h" % roundi(kmh))
	_paint_rank(item, col, UiTheme.velocity_rank(kmh))
	item.set_custom_font(col, UiTheme.font(800))


## 年俸（GameState.league）
func _set_salary(item: TreeItem, col: int, id: String) -> void:
	item.set_text_alignment(col, HORIZONTAL_ALIGNMENT_RIGHT)
	var league := GameState.league
	item.set_text(col, Salary.text(league.salary_of(id)) if league != null else "-")


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
	var ra := _role(a)
	var rb := _role(b)
	if ra != rb:
		return ra == "先発"
	return _overall(a) > _overall(b)


## 先発/救援。登板実績のない投手（role が null）は空文字
func _role(p: Dictionary) -> String:
	if not p["pitching"] or p["pitching"]["role"] == null:
		return ""
	return p["pitching"]["role"]


func _overall(p: Dictionary) -> int:
	if not p["pitching"] or not p["pitching"]["ratings"]:
		return 0
	return int(p["pitching"]["ratings"]["overall"]["value"])
