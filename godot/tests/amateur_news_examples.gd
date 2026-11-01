extends SceneTree
## 記事例の書き出し（テストではない）。--headless --path godot -s res://tests/amateur_news_examples.gd -- 出力先.md
var _gs: Node
var _an: GDScript
var _at: GDScript
var _examples: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _add(a: Array, label: String) -> void:
	if _examples.size() >= 10:
		return
	_examples.append("## %d. %s（%s）\n\n%s" % [_examples.size() + 1, a[0], label, str(a[1]).replace("\n", "\n\n")])
	print("記事%d：%s" % [_examples.size(), a[0]])


func _run() -> void:
	_gs = root.get_node("GameState")
	_an = load("res://sim/amateur_news.gd")
	_at = load("res://sim/amateur_tournament.gd")
	var sg: GDScript = load("res://scripts/save_game.gd")
	sg.set("autosave_enabled", false)
	var rng := RandomNumberGenerator.new()
	_gs.new_game("阪神タイガース", 2008)
	var an: RefCounted = _an.new(_gs)
	_add(an.article(an.prospects(2008)[0], _an.STAGES[0], 2008, rng), "2008年・未確認の大会成績は書かない")
	_gs.new_game("阪神タイガース", 2026)
	an = _an.new(_gs)
	for c: Dictionary in an.prospects(2026):
		if c["category"] == "大学":
			_add(an.article(c, _an.STAGES[1], 2026, rng), "2026年・収集済みの実績")
			break
	for c: Dictionary in an.prospects(2026):
		if c["category"] == "独立":
			_add(an.article(c, _an.STAGES[2], 2026, rng), "2026年・独立リーグ")
			break
	_gs.new_game("阪神タイガース", 2018)
	_gs.call("_amateur_news", "2018-10-08")
	var real: Dictionary = _gs.news.of_issue("2018-amateur-summer-result")[0]
	_add([real["headline"], real["body"]], "2018年・史実")
	_gs.new_game("阪神タイガース", 2027)
	_gs.skip_to_phase(_gs.Phase.DRAFT)
	_gs.advance()
	_gs.advance()
	_gs.call("_amateur_news", "2028-10-08")
	an = _an.new(_gs)
	for c: Dictionary in an.prospects(2028):
		if not _at.summary(_gs.amateur_results, 2028, c["name"], c["school"]).is_empty() and _examples.size() < 8:
			_add(an.article(c, _an.STAGES[4], 2028, rng), "2028年・架空選手の秋の紹介")
	for key: String in ["2028-amateur-spring-result", "2028-amateur-summer-result"]:
		var a: Dictionary = _gs.news.of_issue(key)[0]
		_add([a["headline"], a["body"]], "2028年・ゲーム内大会")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0], FileAccess.WRITE)
		if file == null:
			push_error("記事例を書き込めません：" + args[0])
			quit(1)
			return
		file.store_string("# アマ球界の記事例10本\n\n実際の生成処理から採取。架空年の大会はゲーム内の結果。\n\n" + "\n\n".join(_examples))
	quit()
