class_name ScoutView
extends TabContainer
## 「新戦力」画面（ハブ）。今は外国人市場と、年越しの出来事の一覧だけ（トレード交渉・スカウティングは未実装）。
##
## - 外国人市場：史実で来日した新外国人の候補（GameState.league.market）。オフ（FA・トレード・ポスティング〜
##   春季キャンプ）に「獲得する」で自球団に入る（年俸は提示額）。CPU球団もオフのフェーズごとに獲得していく。
##   「戦力外・引退」の段階からは、戦力外になった選手（来季の成績がある選手）も並ぶ（史実の球団の列に「戦力外（元の球団）」）。
##   戦力外・引退の段階からは支配下の上限（70人）に空きが無いと獲れない
## - 出来事：メジャー移籍・復帰、史実のトレード、引退、新人、外国人の獲得など（LeagueRoster.log の新しい順）
## 行をⒶ（Enter）／クリックで選手詳細。LB/RB でタブ切り替え。

const MARKET_COLUMNS := [["名前", 0], ["投野", 64], ["守備位置", 96], ["主な能力", 170],
	["提示額", 130], ["史実の球団", 120]]
const LOG_KINDS := ["mlb_leave", "mlb_return", "trade", "retire", "rookie", "join", "foreign_sign",
	"foreign_unsigned", "rename", "fa_declare", "fa_move", "fa_stay", "mlb_keep", "mlb_keep_failed", "release",
	"release_sign", "release_unsigned", "release_trim", "mlb_draftee"]
const LOG_LIMIT := 400

var _palette: UiTheme.Palette
var _market_tree: Tree
var _status: Label
var _sign_button: Button
var _log_tree: Tree
var _shown_key := ""


func setup(p: UiTheme.Palette) -> void:
	_palette = p
	var market := VBoxContainer.new()
	market.add_theme_constant_override("separation", 8)
	add_child(market)
	set_tab_title(0, "外国人市場")
	_status = UiTheme.small_label("", 16, UiTheme.TEXT, 700)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	market.add_child(_status)
	_market_tree = _tree(MARKET_COLUMNS)
	market.add_child(_market_tree)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	market.add_child(row)
	_sign_button = Button.new()
	_sign_button.text = "獲得する"
	_sign_button.custom_minimum_size = Vector2(200, 46)
	UiTheme.style_button(_sign_button, Color("00a396"))
	_sign_button.pressed.connect(_sign_selected)
	row.add_child(_sign_button)

	_log_tree = _tree([["年", 70], ["日付", 130], ["出来事", 0]])
	add_child(_log_tree)
	set_tab_title(1, "出来事")


func refresh() -> void:
	var league := GameState.league
	var key := "%d|%d|%d" % [GameState.year, GameState.phase, GameState.roster_version]
	if key == _shown_key or league == null:
		return
	_shown_key = key
	_render_market(league)
	_render_log(league)


func focus_first() -> void:
	var tree := get_current_tab_control() as Tree
	if tree == null:
		tree = _market_tree
	tree.grab_focus()
	var root := tree.get_root()
	if tree.get_selected() == null and root != null and root.get_first_child() != null:
		tree.set_selected(root.get_first_child(), 0)


func switch_tab(delta: int) -> void:
	current_tab = posmod(current_tab + delta, get_tab_count())
	focus_first()


func _render_market(league: LeagueRoster) -> void:
	_market_tree.clear()
	_market_tree.create_item()
	var open := GameState.market_open()
	if GameState.phase in [GameState.Phase.SEASON, GameState.Phase.AWARDS]:
		_status.text = "外国人市場はオフ（FA・トレード・ポスティング〜春季キャンプ）に開きます。" \
			+ "来季に来日する新外国人が候補になり、CPU球団もオフのフェーズごとに獲得していきます。"
	elif league.market.is_empty():
		_status.text = "外国人市場に残っている選手はいません。"
	else:
		var released := league.released_in_market().size()
		_status.text = "来季の新外国人 %d人。「獲得する」で自球団に入ります（年俸は提示額。高いほど評判が良い）。" \
			% (league.market.size() - released) + "CPU球団はフェーズが進むたびに獲得し、開幕までに残った選手は来日しません。"
		if released > 0:
			_status.text += "戦力外の選手も%d人います（開幕までに残ると引退）。" % released
	var ids: Array[String] = league.market.duplicate()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return league.market_info[a]["asking"] > league.market_info[b]["asking"])
	for id in ids:
		var p := GameData.player(id)
		var info: Dictionary = league.market_info[id]
		var item := _market_tree.create_item()
		item.set_text(0, league.names.get(id, id))
		item.set_text(1, "投手" if info["pitcher"] else "野手")
		item.set_text(2, str(p.get("primary_pos")) if p.get("primary_pos") != null else "-")
		item.set_text(3, _ability_text(p, info["pitcher"]))
		item.set_text(4, Salary.text(info["asking"]))
		item.set_text_alignment(4, HORIZONTAL_ALIGNMENT_RIGHT)
		var origin := GameData.short_name(info["hist_team"])
		if info.has("released"):
			origin = "戦力外（%s）" % GameData.short_name(info["released"])
		item.set_text(5, origin)
		item.set_metadata(0, id)
	_sign_button.disabled = not open or ids.is_empty()
	_sign_button.visible = GameState.phase not in [GameState.Phase.SEASON, GameState.Phase.AWARDS]


## 主な能力のランク（投手は総合・スタミナ・奪三振・制球、野手はミート・パワー・走力）
func _ability_text(p: Dictionary, pitcher: bool) -> String:
	var parts: Array[String] = []
	var ratings: Variant = (p.get("pitching") if pitcher else p.get("batting"))
	if not ratings is Dictionary or not ratings.get("ratings") is Dictionary:
		return "-"
	var keys := [["overall", "総"], ["stamina", "ス"], ["k9", "三"], ["bb9", "制"]] if pitcher \
		else [["meet", "ミ"], ["power", "パ"], ["speed", "走"]]
	for k: Array in keys:
		var r: Variant = ratings["ratings"].get(k[0])
		parts.append("%s%s" % [k[1], r["rank"] if r is Dictionary else "-"])
	return " ".join(parts)


func _render_log(league: LeagueRoster) -> void:
	_log_tree.clear()
	_log_tree.create_item()
	var count := 0
	for i in range(league.log.size() - 1, -1, -1):
		var e: Dictionary = league.log[i]
		if e["kind"] not in LOG_KINDS:
			continue
		var item := _log_tree.create_item()
		item.set_text(0, "%d" % e["year"])
		item.set_text(1, e["date"] if not e["date"].is_empty() else "オフ")
		item.set_text(2, e["text"])
		var id: String = e["id"]
		if not id.is_empty() and not id.contains("|") and not GameData.player(id).is_empty():
			item.set_metadata(0, id)
		count += 1
		if count >= LOG_LIMIT:
			break
	if count == 0:
		_log_tree.create_item().set_text(2, "まだ出来事はありません（シーズン中の史実のトレードやオフの移籍がここに出ます）。")


func _sign_selected() -> void:
	var item := _market_tree.get_selected()
	if item == null or item.get_metadata(0) == null:
		_status.text = "獲得する選手を一覧から選んでください。"
		return
	var id := str(item.get_metadata(0))
	var error := GameState.sign_foreign(id)
	if not error.is_empty():
		_status.text = error
		return
	refresh()
	_status.text = "%sを獲得しました（%s）。" % [GameState.league.names.get(id, id),
		Salary.text(GameState.league.salary_of(id))]
	focus_first()


func _tree(columns: Array) -> Tree:
	var tree := Tree.new()
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.column_titles_visible = true
	tree.columns = columns.size()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for i in columns.size():
		tree.set_column_title(i, columns[i][0])
		tree.set_column_expand(i, columns[i][1] == 0)
		if columns[i][1] > 0:
			tree.set_column_custom_minimum_width(i, columns[i][1])
	tree.create_item()
	tree.item_activated.connect(_open_detail.bind(tree))
	return tree


func _open_detail(tree: Tree) -> void:
	var item := tree.get_selected()
	if item == null or item.get_metadata(0) == null:
		return
	var ids: Array[String] = []
	var row := tree.get_root().get_first_child()
	while row != null:
		if row.get_metadata(0) != null:
			ids.append(str(row.get_metadata(0)))
		row = row.get_next()
	PlayerDetail.open(tree, str(item.get_metadata(0)), ids)
