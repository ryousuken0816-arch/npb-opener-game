class_name StatTable
extends RefCounted
## 選手詳細の成績表（史実の年度別1軍成績＋今季＋通算）と、打率・投球回などの表示の共通処理。
## 行は今季の成績（Season の batting/pitching）と同じキーの Dictionary にそろえる。

## 年度別成績の列 [見出し, 幅, キー]。キーは今季の成績（Season）と同じ名前にそろえる
const BATTING_COLUMNS := [
	["年度", 50, "year"], ["球団", 100, "team"], ["試合", 42, "g"], ["打席", 46, "pa"], ["打数", 46, "ab"],
	["得点", 42, "r"], ["安打", 42, "h"], ["二塁打", 48, "d"], ["三塁打", 48, "t"], ["本塁打", 48, "hr"],
	["打点", 42, "rbi"], ["盗塁", 42, "sb"], ["犠打", 40, "sh"], ["四球", 42, "bb"], ["死球", 40, "hbp"],
	["三振", 42, "so"], ["併殺", 40, "gdp"], ["打率", 52, "avg"], ["出塁率", 52, "obp"],
	["長打率", 52, "slg"], ["OPS", 52, "ops"],
]
const PITCHING_COLUMNS := [
	["年度", 50, "year"], ["球団", 100, "team"], ["登板", 42, "g"], ["勝利", 42, "w"], ["敗北", 42, "l"],
	["セーブ", 46, "sv"], ["ホールド", 56, "hld"], ["完投", 40, "cg"], ["完封", 40, "sho"],
	["勝率", 50, "wpct"], ["投球回", 62, "ip"], ["打者", 46, "bf"], ["被安打", 50, "h"],
	["被本塁打", 58, "hr"], ["与四球", 50, "bb"], ["与死球", 50, "hbp"], ["奪三振", 50, "so"],
	["失点", 42, "r"], ["自責点", 50, "er"], ["防御率", 54, "era"],
]
## 選手ページ（npb.jp）の列名 → 今季の成績のキー
const BATTING_KEYS := {
	"試合": "g", "打席": "pa", "打数": "ab", "得点": "r", "安打": "h", "二塁打": "d", "三塁打": "t",
	"本塁打": "hr", "打点": "rbi", "盗塁": "sb", "盗塁刺": "cs", "犠打": "sh", "犠飛": "sf", "四球": "bb",
	"死球": "hbp", "三振": "so", "併殺打": "gdp",
}
const PITCHING_KEYS := {
	"登板": "g", "勝利": "w", "敗北": "l", "セーブ": "sv", "H": "hld", "完投": "cg", "完封勝": "sho",
	"打者": "bf", "outs": "outs", "安打": "h", "本塁打": "hr", "四球": "bb", "死球": "hbp", "三振": "so",
	"失点": "r", "自責点": "er",
}


## 年度別の行（史実の今の年より前＋今季）。各行は今季の成績と同じキーの Dictionary（year, team, current を足す）
static func history_rows(history: Array, keys: Dictionary, season_line: Dictionary,
		team_short: String) -> Array:
	var rows: Array = []
	for h: Variant in history:
		if not h is Dictionary or int(h.get("年度", 0)) >= GameState.year:
			continue
		var row := {"year": int(h["年度"]), "team": str(h.get("所属球団", ""))}
		for jp: String in keys:
			if h.get(jp) != null:
				row[keys[jp]] = int(h[jp])
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["year"] < b["year"])
	if GameState.season != null:
		var row := season_line.duplicate()
		row["year"] = GameState.year
		row["team"] = team_short
		row["current"] = true
		rows.append(row)
	return rows


static func total(rows: Array, key: String) -> int:
	var sum := 0
	for row: Dictionary in rows:
		sum += int(row.get(key, 0))
	return sum


## ゲーム内の年度別の WAR・守備得点の列 [見出し, 幅, キー]
const WAR_BATTING_COLUMNS := [
	["年度", 50, "year"], ["球団", 100, "team"], ["打席", 46, "pa"], ["wRC+", 50, "wrc_plus"],
	["主な守備", 70, "pos"], ["守備回", 62, "inn"], ["守備得点", 66, "fld"], ["WAR", 50, "war"],
]
const WAR_PITCHING_COLUMNS := [
	["年度", 50, "year"], ["球団", 100, "team"], ["投球回", 62, "ip"], ["FIP", 50, "fip"], ["WAR", 50, "war"],
]
## 年度別の WAR の表で一度に見える行数（それより多いとスクロール）
const WAR_VISIBLE_ROWS := 4


## ゲーム内の各年（記録室の年）の WAR・守備得点 [{year, team, pa, wrc_plus, pos, inn, fld, war}]（数は表示用の文字）。
## 係数はその年・その選手のリーグ（Records.coefficients）
static func war_rows(id: String, is_pitcher: bool) -> Array:
	var rows: Array = []
	for y: int in GameState.records_years():
		var st := GameState.season_stats(y)
		var kind := "pitching" if is_pitcher else "batting"
		var s: Dictionary = st.get(kind, {}).get(id, {})
		if int(s.get("outs" if is_pitcher else "pa", 0)) <= 0:
			continue
		var team: String = st["players"].get(id, {}).get("team", "")
		var league_of := func(pid: String) -> String:
			return st["leagues"].get(st["players"].get(pid, {}).get("team", ""), "")
		var c := Records.coefficients(st["batting"], st["pitching"], league_of, st["leagues"].get(team, ""))
		var row := {"year": y, "team": GameData.short_name(team)}
		if is_pitcher:
			var r := Records.pitching_row(s, c)
			row.merge({"ip": ip_text(int(s.get("outs", 0))), "fip": Records.format("rate2", r["fip"]),
				"war_value": float(r["war"]), "outs": int(s.get("outs", 0))})
		else:
			var r := Records.batting_row(s, c)
			var fr := Records.fielding_runs(s, c["fielding"])
			var main_pos := ""
			for pos: String in fr["pos"]:
				if main_pos.is_empty() or int(fr["pos"][pos]["outs"]) > int(fr["pos"][main_pos]["outs"]):
					main_pos = pos
			row.merge({"pa": int(s.get("pa", 0)), "wrc_plus": Records.format("plus", r["wrc_plus"]),
				"pos": main_pos if not main_pos.is_empty() else "指名打者", "inn": ip_text(int(fr["outs"])),
				"outs": int(fr["outs"]), "fld_value": float(r["fld"]), "war_value": float(r["war"])})
			row["fld"] = Records.format("runs", r["fld"])
		row["war"] = Records.format("war", row["war_value"])
		rows.append(row)
	return rows


## 年度別の WAR の表（見出し・各年（多ければスクロール）・通算）
static func build_war(rows: Array, is_pitcher: bool, palette: UiTheme.Palette) -> Control:
	var columns: Array = WAR_PITCHING_COLUMNS if is_pitcher else WAR_BATTING_COLUMNS
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 1)
	var header: Array = []
	for col: Array in columns:
		header.append(col[0])
	table.add_child(_row(columns, header, palette.main, palette.on_main, true))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.name = "WarHistory"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 23 * mini(rows.size(), WAR_VISIBLE_ROWS))
	scroll.add_child(box)
	table.add_child(scroll)
	var sum := {"year": "通算", "team": "%d年" % rows.size(), "pa": 0, "outs": 0, "fld_value": 0.0, "war_value": 0.0}
	for i in rows.size():
		var row: Dictionary = rows[i]
		var current: bool = row["year"] == GameState.year
		var bg := Color("fff4c2") if current else Color.WHITE if i % 2 == 0 else Color("f3f6f9")
		box.add_child(_row(columns, _cells(columns, row), bg, UiTheme.TEXT, false))
		for key: String in ["pa", "outs", "fld_value", "war_value"]:
			sum[key] += row.get(key, 0)
	sum["ip"] = ip_text(int(sum["outs"]))
	sum["inn"] = sum["ip"]
	sum["fld"] = Records.format("runs", sum["fld_value"])
	sum["war"] = Records.format("war", sum["war_value"])
	table.add_child(_row(columns, _cells(columns, sum), palette.main.lerp(Color.WHITE, 0.75), UiTheme.TEXT, true))
	if rows.size() > WAR_VISIBLE_ROWS:
		_scroll_war_to_end(scroll)
	return table


static func _scroll_war_to_end(scroll: ScrollContainer) -> void:
	if not scroll.is_inside_tree():
		await scroll.tree_entered
	for i in 2:
		if not is_instance_valid(scroll) or not scroll.is_inside_tree():
			return
		await scroll.get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


## 成績表。見出し・今季・通算の行は固定し、史実の年度別の行（with_history）はその間でスクロールする
## （スクロールは "History" という名前の ScrollContainer）
static func build(columns: Array, rows: Array, with_history: bool,
		palette: UiTheme.Palette) -> Control:
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 1)
	var header: Array = []
	for col: Array in columns:
		header.append(col[0])
	table.add_child(_row(columns, header, palette.main, palette.on_main, true))
	var history_box := VBoxContainer.new()
	history_box.add_theme_constant_override("separation", 1)
	history_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if with_history:
		var scroll := ScrollContainer.new()
		scroll.name = "History"
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.add_child(history_box)
		table.add_child(scroll)
	var sum := {}
	var played_years := {}
	var shown := 0
	for row: Dictionary in rows:
		for key: String in row:
			if row[key] is int and key != "year":
				sum[key] = int(sum.get(key, 0)) + row[key]
		if int(row.get("g", 0)) > 0:
			played_years[row["year"]] = true
		if row.get("current", false):
			table.add_child(_row(columns, _cells(columns, _with_zeros(columns, row)), Color("fff4c2"),
				UiTheme.TEXT, false))
		elif with_history:
			var bg := Color.WHITE if shown % 2 == 0 else Color("f3f6f9")
			history_box.add_child(_row(columns, _cells(columns, row), bg, UiTheme.TEXT, false))
			shown += 1
	if with_history and shown == 0:
		history_box.add_child(UiTheme.small_label("（%d年より前の1軍の出場記録はありません）" % GameState.year, 15))
	sum["year"] = "通算"
	sum["team"] = "%d年" % played_years.size()
	table.add_child(_row(columns, _cells(columns, _with_zeros(columns, sum)),
		palette.main.lerp(Color.WHITE, 0.75), UiTheme.TEXT, true))
	return table


## 今季・通算の行で記録の無い数（まだ出場していない等）は 0 と出す（今季に記録していない完投・完封は「-」）
static func _with_zeros(columns: Array, row: Dictionary) -> Dictionary:
	var result := row.duplicate()
	for col: Array in columns:
		var key: String = col[2]
		var counted := BATTING_KEYS.values().has(key) or PITCHING_KEYS.values().has(key)
		if counted and not result.has(key) and not key in ["cg", "sho"]:
			result[key] = 0
	return result


static func _row(columns: Array, cells: Array, bg: Color, fg: Color, bold: bool) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", style)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	for i in columns.size():
		var label := UiTheme.small_label(str(cells[i]), 14, fg, 800 if bold else 500)
		label.custom_minimum_size = Vector2(columns[i][1], 0)
		label.clip_text = true
		match i:
			0:
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			1:
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			_:
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(label)
	return panel


static func _cells(columns: Array, row: Dictionary) -> Array:
	var cells: Array = []
	for col: Array in columns:
		cells.append(_cell(col[2], row))
	return cells


static func _cell(key: String, row: Dictionary) -> String:
	match key:
		"year", "team":
			return str(row.get(key, ""))
		"avg":
			return rate_text(avg(row), int(row.get("ab", 0)) > 0)
		"obp":
			return rate_text(obp(row), obp_den(row) > 0)
		"slg":
			return rate_text(slg(row), int(row.get("ab", 0)) > 0)
		"ops":
			return rate_text(obp(row) + slg(row), int(row.get("ab", 0)) > 0)
		"ip":
			return ip_text(int(row.get("outs", 0)))
		"era":
			return era_text(row)
		"wpct":
			var decisions := int(row.get("w", 0)) + int(row.get("l", 0))
			return rate_text(float(row.get("w", 0)) / decisions, decisions > 0)
	return str(row[key]) if row.get(key) != null else "-"


static func avg(b: Dictionary) -> float:
	return float(b.get("h", 0)) / int(b["ab"]) if int(b.get("ab", 0)) > 0 else 0.0


static func obp_den(b: Dictionary) -> int:
	return int(b.get("ab", 0)) + int(b.get("bb", 0)) + int(b.get("hbp", 0)) + int(b.get("sf", 0))


static func obp(b: Dictionary) -> float:
	var den := obp_den(b)
	if den <= 0:
		return 0.0
	return float(int(b.get("h", 0)) + int(b.get("bb", 0)) + int(b.get("hbp", 0))) / den


static func slg(b: Dictionary) -> float:
	var ab := int(b.get("ab", 0))
	if ab <= 0:
		return 0.0
	var singles := int(b.get("h", 0)) - int(b.get("d", 0)) - int(b.get("t", 0)) - int(b.get("hr", 0))
	var bases := singles + 2 * int(b.get("d", 0)) + 3 * int(b.get("t", 0)) + 4 * int(b.get("hr", 0))
	return float(bases) / ab


## 打率などの表示（".312"、1以上は "1.050"）
static func rate_text(value: float, valid: bool) -> String:
	if not valid:
		return "-"
	var s := "%.3f" % value
	return s.trim_prefix("0") if value < 1.0 else s


static func ip_text(outs: int) -> String:
	return "%d %d/3" % [outs / 3, outs % 3] if outs % 3 != 0 else str(outs / 3)


static func era_text(s: Dictionary) -> String:
	var outs := int(s.get("outs", 0))
	return "%.2f" % (int(s.get("er", 0)) * 27.0 / outs) if outs > 0 else "-"
