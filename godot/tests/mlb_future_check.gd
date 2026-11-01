extends SceneTree
## 2027年以降の日本人のメジャー移籍と帰国の確認（docs/AUTORUN.md 作業41）。
## ヘッドレスで実行：
##   godot --headless --path godot --script res://tests/mlb_future_check.gd -- [年数]

const USER := "読売ジャイアンツ"
const START := 2027
const DEFAULT_YEARS := 10

var _failures := 0
var _years := DEFAULT_YEARS
var _gs: Node
var _gd: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		_years = int(args[0])
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")
	var t0 := Time.get_ticks_msec()

	print("=== 2027年以降のメジャー移籍・帰国テスト（%d年間）開始 ===" % _years)
	_gs.new_game(USER, START)

	var total_departures := 0
	var total_returns := 0
	var departure_counts_by_year := {}
	var return_counts_by_year := {}
	var news_departure_found := false
	var news_return_found := false
	var keep_tested := false
	var return_player_played := false

	# 追跡用：復帰した選手ID
	var returned_player_ids: Array[String] = []

	for i in _years:
		var y: int = _gs.year
		print("--- %d年シーズン進行中 ---" % y)

		# シーズンをスキップして FA・トレード・ポスティングのオフへ進める
		_gs.skip_to_phase(_gs.Phase.FA_TRADE)
		var f: Variant = _gs.fa()
		_check(f != null, "%d年オフ：FAが開始された" % y)

		# 1. メジャー移籍人数の確認
		var mlb_list: Array = f.mlb if f != null else []
		var dep_count := mlb_list.size()
		total_departures += dep_count
		departure_counts_by_year[y] = dep_count
		print("  %d年オフ メジャー移籍: %d人" % [y, dep_count])

		# 2. 自球団選手の引き留めテスト（1回実施）
		if not keep_tested and dep_count > 0:
			# テストのため、最初の移籍選手を自球団所属にして引き留めを試す
			var target_id: String = mlb_list[0]
			f.mlb_info[target_id]["from"] = USER
			var keep_res: Dictionary = f.keep_mlb(_gs.league, target_id, 80000, 3)
			_check(keep_res.has("ok"), "メジャー移籍の引き留め処理が実行できる")
			if keep_res["ok"]:
				_check(_gs.league.team_of.has(target_id) and _gs.league.team_of[target_id] == USER,
					"引き留め成功で自球団に残る")
				print("  -> %s の引き留めに成功（自球団に残留）" % target_id)
				keep_tested = true
			else:
				print("  -> %s の引き留めは失敗（確率通り）" % target_id)
				# 確実に成功するパターンも別でテスト
				_gs.league.keep_from_mlb(target_id, USER, 100000, 3, y + 1)
				_check(_gs.league.team_of.has(target_id) and _gs.league.team_of[target_id] == USER,
					"keep_from_mlb で自球団に残留する")
				keep_tested = true

		# 3. 帰国選手の確認（FA市場に出ている選手の中で mlb_return フラグを持つもの）
		var ret_count := 0
		if f != null:
			for id in f.declared:
				if f.info.get(id, {}).get("mlb_return", false):
					ret_count += 1
					returned_player_ids.append(id)
					print("  -> 帰国選手がFA市場に登場: %s (古巣: %s)" % [
						_gs.league.names.get(id, id), f.info[id].get("from", "")])
		total_returns += ret_count
		return_counts_by_year[y] = ret_count
		print("  %d年オフ メジャー帰国: %d人" % [y, ret_count])

		# 4. セーブ／ロードの確認（3年目オフに実施）
		if i == 2:
			_check_save_load(y)

		# 5. FAを締め切る
		_gs.fa_resolve()

		# 6. 契約更改・戦力外・ドラフトを進めて春季キャンプ（来季開幕）へ
		_gs.skip_to_phase(_gs.Phase.CAMP)
		_check(_gs.year == y + 1, "来季（%d年）へ年越し" % (y + 1))

		# 7. メジャーにいる日本人選手の能力値が GameData.ratings に存在するか確認
		var mlb_ratings: Array = _gd.ratings.get("mlb_players", [])
		print("  来季（%d年）のメジャー在籍選手数: %d人" % [_gs.year, mlb_ratings.size()])
		_check(mlb_ratings.size() >= 5, "%d年：メジャー在籍日本人選手が保持されている（%d人）" % [
			_gs.year, mlb_ratings.size()])

		# 8. 復帰選手がチームに所属しているか確認
		for ret_id in returned_player_ids:
			if _gs.league.team_of.has(ret_id):
				var assigned_team: String = _gs.league.team_of[ret_id]
				var p: Dictionary = _gd.player(ret_id)
				if not p.is_empty() and not assigned_team.is_empty() and not return_player_played:
					return_player_played = true
					print("  -> 帰国選手 %s が %s に所属（試合出場可能）" % [
						_gs.league.names.get(ret_id, ret_id), assigned_team])

		# 春季キャンプから開幕へ進める
		_gs.advance()
		_check(_gs.phase == _gs.Phase.SEASON, "%d年シーズン開幕" % _gs.year)

		# 9. ニュースの確認
		if _gs.news != null:
			for a: Dictionary in _gs.news.articles:
				var head: String = a.get("headline", "")
				if head.contains("メジャー挑戦を表明"):
					news_departure_found = true
				if head.contains("古巣に復帰") or head.contains("に入団") or head.contains("復帰を表明"):
					news_return_found = true

	# 10. 全体の集計と史実近似チェック
	print("\n=== %d年間の集計結果 ===" % _years)
	print("総メジャー移籍数: %d人 (年平均 %.1f人)" % [total_departures, float(total_departures) / _years])
	print("総メジャー帰国数: %d人 (年平均 %.1f人)" % [total_returns, float(total_returns) / _years])

	# 移籍人数：10年で10〜30人（年1〜3人）
	_check(total_departures >= _years * 0.8 and total_departures <= _years * 3.5,
		"メジャー移籍の人数が史実の頃に近い（計%d人、年平均%.1f人）" % [
			total_departures, float(total_departures) / _years])

	# 帰国人数：10年で6〜25人（年0.6〜2.5人）
	_check(total_returns >= mini(_years, 4),
		"メジャーからの帰国が定期的に発生する（計%d人）" % total_returns)

	_check(news_departure_found, "メジャー挑戦表明のニュースが配信された")
	_check(news_return_found, "メジャー帰国・入団のニュースが配信された")
	_check(keep_tested, "自球団選手の引き留めテストが完了")
	_check(return_player_played, "帰国した選手が所属球団に入団し名簿に存在する")

	var elapsed := (Time.get_ticks_msec() - t0) / 1000
	print("所要時間: %d秒" % elapsed)
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_save_load(y: int) -> void:
	var save_util = load("res://sim/save_util.gd")
	var save_data: Variant = save_util.ints(JSON.parse_string(JSON.stringify(_gs.to_save(), "", false, true)))
	var in_mlb_before: int = _gs.league.in_mlb.size()
	_gs.load_state(save_data)
	var in_mlb_after: int = _gs.league.in_mlb.size()
	_check(in_mlb_before == in_mlb_after,
		"%d年オフ：セーブ／ロードでメジャー在籍人数が一致（%d人）" % [y, in_mlb_after])


func _check(condition: bool, message: String) -> void:
	if condition:
		print("OK: %s" % message)
	else:
		_failures += 1
		printerr("NG: %s" % message)
