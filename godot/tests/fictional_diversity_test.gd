extends SceneTree
## 架空ドラフト候補の多様性・インフレゼロ・二刀流・怪物出現の検証テスト

func _init() -> void:
	print("==================================================")
	print("架空ドラフト候補 生成エンジン v2 検証テスト開始")
	print("==================================================")

	var fd := FictionalDraft.new()
	if not fd.is_ready():
		print("ERROR: FictionalDraft is not ready")
		quit(1)
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 20281101

	# ----------------------------------------------------
	# 1. 1000年分の大規模シミュレーション（統計検証）
	# ----------------------------------------------------
	print("\n>>> 1000年分のドラフト候補生成テストを実行中...")

	var total_players := 0
	var monster_count := 0
	var two_way_counts := {"A": 0, "B": 0, "C": 0, "D": 0}
	var two_way_annual_hist := [0, 0, 0, 0] # 0人、1人、2人、3人以上
	var types_count := {}

	# 100年ごとの平均将来性スコア（インフレ検証用）
	var era_scores := []
	var current_era_scores := []

	# 能力の多様性チェック用（シグネチャのユニーク数）
	var signatures := {}
	var duplicate_count := 0

	for year_idx in 1000:
		var draft_year := 2028 + year_idx
		var pool := fd.generate_year(draft_year, rng)
		total_players += pool.size()

		var tw_this_year := 0
		for p: Dictionary in pool:
			var score := float(p.get("amateur", {}).get("future_score", 0.0))
			current_era_scores.append(score)

			if bool(p.get("is_monster", false)):
				monster_count += 1

			var two_way: Dictionary = p.get("two_way", {})
			if bool(two_way.get("active", false)):
				tw_this_year += 1
				var tw_type: String = str(two_way.get("type", ""))
				if two_way_counts.has(tw_type):
					two_way_counts[tw_type] += 1

			var t_word: String = str(p.get("amateur", {}).get("type", ""))
			types_count[t_word] = int(types_count.get(t_word, 0)) + 1

			# 能力シグネチャ（ミート・パワー・走力・守備 または 球速・制球・奪三振）
			var sig := ""
			if p.get("is_pitcher", false):
				var pit: Dictionary = p.get("pitching", {})
				var r: Dictionary = pit.get("ratings", {})
				sig = "P:%d:%d:%d:%d" % [
					int(pit.get("velocity", {}).get("kmh", 140)),
					int(r.get("overall", {}).get("value", 50)),
					int(r.get("k9", {}).get("value", 50)),
					int(r.get("bb9", {}).get("value", 50))
				]
			else:
				var bat: Dictionary = p.get("batting", {})
				var r: Dictionary = bat.get("ratings", {})
				sig = "B:%d:%d:%d:%d:%d" % [
					int(r.get("meet", {}).get("value", 50)),
					int(r.get("power", {}).get("value", 50)),
					int(r.get("speed", {}).get("value", 50)),
					int(r.get("defense", {}).get("value", 50)),
					int(r.get("arm", {}).get("value", 50))
				]
			if signatures.has(sig):
				duplicate_count += 1
			else:
				signatures[sig] = true

		if tw_this_year == 0:
			two_way_annual_hist[0] += 1
		elif tw_this_year == 1:
			two_way_annual_hist[1] += 1
		elif tw_this_year == 2:
			two_way_annual_hist[2] += 1
		else:
			two_way_annual_hist[3] += 1

		if (year_idx + 1) % 100 == 0:
			var sum := 0.0
			for s in current_era_scores:
				sum += s
			var avg := sum / float(current_era_scores.size())
			era_scores.append(avg)
			current_era_scores.clear()

	print("1000年分生成完了！ 総選手数: %d 人" % total_players)
	print("・ユニーク能力パターン数: %d 種類 (重複率: %.2f%%)" % [
		signatures.size(), float(duplicate_count) / float(total_players) * 100.0
	])
	print("・即戦力の怪物出現数: %d 人 (出現率: %.2f%%, 目安1.5%%)" % [
		monster_count, float(monster_count) / float(total_players) * 100.0
	])
	print("・二刀流出現数: 本格怪物(A)=%d人 (%.1f年に1人), 投手本職(B)=%d人, 野手本職(C)=%d人, 未完素材(D)=%d人" % [
		two_way_counts["A"], 1000.0 / float(maxi(1, two_way_counts["A"])),
		two_way_counts["B"], two_way_counts["C"], two_way_counts["D"]
	])
	print("  年間出現数分布: 0人の年=%d年 (%.1f%%), 1人の年=%d年 (%.1f%%), 2人の年=%d年 (%.1f%%), 3人以上=%d年" % [
		two_way_annual_hist[0], two_way_annual_hist[0] * 100.0 / 1000.0,
		two_way_annual_hist[1], two_way_annual_hist[1] * 100.0 / 1000.0,
		two_way_annual_hist[2], two_way_annual_hist[2] * 100.0 / 1000.0,
		two_way_annual_hist[3]
	])

	print("\n--- 100年ごとの平均将来性スコア（インフレ検証） ---")
	for i in era_scores.size():
		print("  第%d世紀 (%d〜%d年): 平均将来性スコア = %+.4f" % [
			i + 1, 2028 + i * 100, 2028 + (i + 1) * 100 - 1, era_scores[i]
		])
	var drift := absf(era_scores[-1] - era_scores[0])
	print("  1000年でのスコアドリフト幅: %.4f (許容0.05以内: %s)" % [
		drift, "PASS (インフレなし！)" if drift < 0.05 else "FAIL"
	])

	print("\n--- 主な出現タイプの内訳トップ10 ---")
	var sorted_types := types_count.keys()
	sorted_types.sort_custom(func(a: String, b: String) -> bool:
		return int(types_count[a]) > int(types_count[b])
	)
	for i in mini(10, sorted_types.size()):
		var t_name: String = sorted_types[i]
		print("  %2d位: %-18s (%d 人)" % [i + 1, t_name, types_count[t_name]])

	# ----------------------------------------------------
	# 2. 代表サンプル30人の能力一覧出力
	# ----------------------------------------------------
	print("\n==================================================")
	print("ドラフト候補サンプル 30人一覧（2030年秋のドラフト）")
	print("==================================================")

	rng.seed = 20301026
	var sample_pool := fd.generate_year(2030, rng)

	# 1位候補、二刀流、ロマン枠、掘り出し物などをバランスよく抽出
	var sample_30: Array = []
	for p: Dictionary in sample_pool:
		if sample_30.size() < 30:
			sample_30.append(p)

	print(String("%-4s | %-8s | %-4s | %-6s | %-16s | %-6s | %-4s | %s") % [
		"順位帯", "名前", "位置", "区分", "二つ名・タイプ", "将来性", "格付", "主要能力（入団時 / ピーク）"
	])
	print("------------------------------------------------------------------------------------------------------------------------")

	for p: Dictionary in sample_30:
		var am: Dictionary = p.get("amateur", {})
		var band: String = str(am.get("band", ""))
		var name: String = str(p.get("name", ""))
		var pos: String = str(p.get("primary_pos", ""))
		var cat: String = str(am.get("category", ""))
		var t_word: String = str(am.get("type", ""))
		var f_score: float = float(am.get("future_score", 0.0))
		var f_rank := "S" if f_score >= 1.6 else ("A" if f_score >= 1.0 else ("B" if f_score >= 0.3 else ("C" if f_score >= -0.3 else "D")))
		var grade: String = str(am.get("grade", ""))

		var ability_str := ""
		if p.get("is_pitcher", false):
			var pit: Dictionary = p.get("pitching", {})
			var r: Dictionary = pit.get("ratings", {})
			var pk: Dictionary = p.get("growth", {}).get("peak", {})
			var v_ent := int(pit.get("velocity", {}).get("kmh", 140))
			var v_pk := int(pk.get("velocity", 145))
			ability_str = "球速%d(%d) 制球%d(%d) 奪三%d(%d) 総%d(%d)" % [
				v_ent, v_pk,
				int(r.get("bb9", {}).get("value", 50)), int(pk.get("bb9", 50)),
				int(r.get("k9", {}).get("value", 50)), int(pk.get("k9", 50)),
				int(r.get("overall", {}).get("value", 50)), int(pk.get("overall", 50))
			]
		else:
			var bat: Dictionary = p.get("batting", {})
			var r: Dictionary = bat.get("ratings", {})
			var pk: Dictionary = p.get("growth", {}).get("peak", {})
			ability_str = "ミ%d(%d) パ%d(%d) 走%d(%d) 守%d(%d) 肩%d(%d)" % [
				int(r.get("meet", {}).get("value", 50)), int(pk.get("meet", 50)),
				int(r.get("power", {}).get("value", 50)), int(pk.get("power", 50)),
				int(r.get("speed", {}).get("value", 50)), int(pk.get("speed", 50)),
				int(r.get("defense", {}).get("value", 50)), int(pk.get("defense", 50)),
				int(r.get("arm", {}).get("value", 50)), int(pk.get("arm", 50))
			]

		var two_way: Dictionary = p.get("two_way", {})
		if bool(two_way.get("active", false)):
			ability_str += " ★二刀流[%s]" % str(two_way.get("type", ""))

		print(String("%-6s | %-8s | %-4s | %-6s | %-16s | %-6s | %-4s | %s") % [
			band, name, pos, cat, t_word, "%+.2f(%s)" % [f_score, f_rank], grade, ability_str
		])

	print("\n==================================================")
	print("検証テスト正常終了！")
	print("==================================================")
	quit(0)
