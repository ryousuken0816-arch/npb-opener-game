extends SceneTree
## 投手の持ち球（PitchArsenal。docs/AUTORUN.md 作業79・HANDOFF 4.79）の確認。ヘッドレスで約1分。
## - 実在の投手（2012年・2026年の開幕前の能力値）に持ち球を作ると、計算した奪三振・被弾抑制が元の値に近い（合わせきれない人は少ない）
## - 持ち球は2〜5種、変化量は1〜7で真ん中もよく出る（端に張り付かない）、球種がばらける、決め球がある
## - 作業83の分布：多くの球は2〜4、決め球の平均は4くらい、奪三振の上位1割の決め球は5〜6、7を持つ投手はリーグに数人
## - 同じ選手は年が変わってもほぼ同じ球種（2025年と2026年）。作ったあと ensure をもう一度呼んでも変わらない
## - 球速が速いだけ（持ち球が弱い）の投手も、遅い投手より奪三振が少し高い
## - 成長などで k9 が変わったら、球種はそのままで変化量が合わせ直される
##
##   godot --headless --path godot -s res://tests/pitch_arsenal_check.gd

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var by_year := {}
	for y: int in [2012, 2025, 2026]:
		by_year[y] = _check_year(y)
	_check_stable(by_year[2025], by_year[2026])
	_check_velocity()
	_check_refit(by_year[2026])
	_check_learn(by_year[2026])
	print("（%d秒）" % ((Time.get_ticks_msec() - t0) / 1000))
	print("ALL OK" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(1 if _failures > 0 else 0)


func _load(y: int) -> Array:
	var gd: Node = root.get_node("GameData")
	var d: Variant = gd.peek_ratings(y, "pre", false)
	if not d is Dictionary or d.is_empty():
		_check(false, "能力値ファイルを読める（%d_pre）" % y)
		return []
	var out: Array = []
	for p: Dictionary in d.get("players", []):
		var pit: Variant = p.get("pitching")
		if bool(p.get("is_pitcher", false)) and pit is Dictionary and pit.get("ratings") is Dictionary 				and pit["ratings"].get("k9") is Dictionary:
			out.append(p)
	return out


func _check_year(y: int) -> Dictionary:
	print("== %d年の開幕前の投手 ==" % y)
	var players := _load(y)
	var before := {}
	for p: Dictionary in players:
		before[p["id"]] = [float(p["pitching"]["ratings"]["k9"]["value"]), float(p["pitching"]["ratings"]["hr9"]["value"])]
	var t0 := Time.get_ticks_msec()
	PitchArsenal.ensure_all(players, y)
	var ms := Time.get_ticks_msec() - t0
	var ek: Array = []
	var eh: Array = []
	var moves := {}
	var counts := {}
	var names := {}
	var best := {}
	var big := 0
	var sevens := 0
	var best_moves: Array = []
	var by_k: Array = []
	for p: Dictionary in players:
		var r: Dictionary = p["pitching"]["ratings"]
		var b: Array = before[p["id"]]
		var dk := float(r["k9"]["value"]) - float(b[0])
		var dh := float(r["hr9"]["value"]) - float(b[1])
		ek.append(dk)
		eh.append(dh)
		big += 1 if absf(dk) > 5.0 or absf(dh) > 5.0 else 0
		var ps: Array = p["pitching"]["pitches"]
		counts[ps.size()] = int(counts.get(ps.size(), 0)) + 1
		for x: Dictionary in ps:
			moves[int(x["move"])] = int(moves.get(int(x["move"]), 0)) + 1
			names[x["name"]] = int(names.get(x["name"], 0)) + 1
		var bp := PitchArsenal.best_pitch(p)
		best[bp.get("name", "")] = int(best.get(bp.get("name", ""), 0)) + 1
		best_moves.append(int(bp.get("move", 0)))
		var mx := 0
		var total := 0
		for x: Dictionary in ps:
			mx = maxi(mx, int(x["move"]))
			total += int(x["move"])
		sevens += 1 if mx >= PitchArsenal.MOVE_MAX else 0
		by_k.append([float(r["k9"]["value"]), int(bp.get("move", 0)), total])
	var gbs: Array = []
	var plat_mean: Array = []
	for p: Dictionary in players:
		gbs.append(PitchArsenal.groundball_raw(p["pitching"]["pitches"]))
		var pl: Array = PitchArsenal.platoon(p["pitching"]["pitches"], str(p.get("throws", "右")))
		var sh := float(PitchArsenal.SAME_SHARE.get(str(p.get("throws", "右")), 0.6))
		plat_mean.append(sh * float(pl[0]) + (1.0 - sh) * float(pl[1]))
	print("  ゴロ（元の値）%s、左右の上下をならした値 %s" % [_stat(gbs), _stat(plat_mean)])
	var n := maxf(1, players.size())
	print("  %d人（%dミリ秒）。奪三振のずれ %s、被弾抑制のずれ %s、5を超えてずれた人 %d" % [players.size(), ms, _stat(ek), _stat(eh), big])
	print("  持ち球の数 %s、変化量 %s" % [counts, _sorted(moves)])
	print("  球種 %s" % names)
	print("  決め球 %s" % best)
	print("  例：%s" % _examples(players))
	by_k.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var top: Array = by_k.slice(0, maxi(1, by_k.size() / 10))
	var top_best := _mean(top.map(func(x: Array) -> int: return x[1]))
	var top_sum := _mean(top.map(func(x: Array) -> int: return x[2]))
	var mid := float(int(moves.get(2, 0)) + int(moves.get(3, 0)) + int(moves.get(4, 0)))
	print("  決め球の変化量 平均 %.2f、奪三振の上位1割 決め球 %.2f・合計 %.1f、7を持つ投手 %d人" % [_mean(best_moves), top_best, top_sum, sevens])
	var edge := float(int(moves.get(1, 0)) + int(moves.get(7, 0)))
	var all_moves := 0.0
	for m: int in moves:
		all_moves += moves[m]
	_check(absf(_mean(ek)) < 1.0 and absf(_mean(eh)) < 1.0, "%d年：計算した奪三振・被弾抑制は元の値と平均でずれない（%.2f・%.2f）" % [y, _mean(ek), _mean(eh)])
	_check(_sd(ek) < 3.0 and _sd(eh) < 4.0, "%d年：一人ずつのずれも小さい（標準偏差 %.1f・%.1f）" % [y, _sd(ek), _sd(eh)])
	_check(big / n < 0.08, "%d年：5を超えてずれる人は少ない（%d人）" % [y, big])
	_check(edge / maxf(1, all_moves) < 0.35, "%d年：変化量が1か7に張り付く球は少ない（%.0f%%）" % [y, 100.0 * edge / maxf(1, all_moves)])
	_check(sevens <= maxi(3, players.size() / 50), "%d年：変化量7を持つ投手はリーグに数人（%d人）" % [y, sevens])
	_check(_mean(best_moves) >= 3.2 and _mean(best_moves) <= 4.4, "%d年：決め球の変化量の平均は4くらい（%.2f）" % [y, _mean(best_moves)])
	_check(top_best >= 4.5 and top_best <= 6.0, "%d年：奪三振の上位1割の決め球は5〜6（%.2f）" % [y, top_best])
	_check(mid / maxf(1, all_moves) >= 0.6, "%d年：多くの球は変化量2〜4（%.0f%%）" % [y, 100.0 * mid / maxf(1, all_moves)])
	_check(names.size() >= 8 and best.size() >= 6, "%d年：球種・決め球がばらける（%d種・決め球 %d種）" % [y, names.size(), best.size()])
	for c: int in counts:
		_check(c >= 2 and c <= 5, "%d年：持ち球は2〜5種（%d種）" % [y, c])
	var out := {}
	for p: Dictionary in players:
		out[p["id"]] = p
	return out


func _check_stable(a: Dictionary, b: Dictionary) -> void:
	var same := 0
	var n := 0
	for id: String in a:
		if not b.has(id):
			continue
		n += 1
		var na: Array = a[id]["pitching"]["pitches"].map(func(x: Dictionary) -> String: return x["name"])
		var nb: Array = b[id]["pitching"]["pitches"].map(func(x: Dictionary) -> String: return x["name"])
		same += 1 if na == nb else 0
	print("== 2025年と2026年で同じ球種の投手 %d／%d人 ==" % [same, n])
	_check(float(same) / maxf(1, n) >= 0.6, "同じ選手は年が変わってもほぼ同じ球種（%d／%d人）" % [same, n])


func _check_velocity() -> void:
	print("== 球速だけ速い投手 ==")
	var weak := [{"name": "スライダー", "move": 1}, {"name": "カーブ", "move": 1}]
	var slow: Array = PitchArsenal.derive(weak, 140.0, 150.0)
	var fast: Array = PitchArsenal.derive(weak, 160.0, 150.0)
	var good: Array = PitchArsenal.derive([{"name": "スライダー", "move": 5}, {"name": "フォーク", "move": 6}], 148.0, 150.0)
	print("  持ち球が弱い 140km 奪三振 %.0f・160km %.0f、148km でスライダー5・フォーク6 %.0f" % [slow[0], fast[0], good[0]])
	_check(float(fast[0]) - float(slow[0]) >= 15.0, "球速が速いと奪三振が上がる（140km %.0f → 160km %.0f）" % [slow[0], fast[0]])
	_check(float(fast[0]) < float(good[0]), "球速が速いだけの投手は、変化球の良い投手ほどは三振を取れない（%.0f < %.0f）" % [fast[0], good[0]])


func _check_refit(players: Dictionary) -> void:
	print("== 合わせ直し ==")
	# 変化量に伸びしろのある投手（どの球も4以下）
	var p: Dictionary = players.values()[0].duplicate(true)
	for q: Dictionary in players.values():
		if q["pitching"]["pitches"].all(func(x: Dictionary) -> bool: return int(x["move"]) <= 4):
			p = q.duplicate(true)
			break
	var names: Array = p["pitching"]["pitches"].map(func(x: Dictionary) -> String: return x["name"])
	_check(not PitchArsenal.ensure(p, 2026), "作ったあとにもう一度呼んでも変わらない")
	var r: Dictionary = p["pitching"]["ratings"]
	var k0 := int(r["k9"]["value"])
	var before := PitchArsenal.summary(p)
	var before_sum := _move_sum(p)
	r["k9"] = {"value": mini(100, k0 + 10), "rank": "B"}
	PitchArsenal.ensure(p, 2026)
	var names2: Array = p["pitching"]["pitches"].map(func(x: Dictionary) -> String: return x["name"])
	print("  %s：奪三振 %d → %d（%s → %s）" % [p["name"], k0, int(r["k9"]["value"]), before, PitchArsenal.summary(p)])
	_check(names == names2 and int(r["k9"]["value"]) >= k0 + 4 and _move_sum(p) > before_sum, "k9 が上がると球種はそのままで変化量が上がる")


static func _move_sum(p: Dictionary) -> int:
	var n := 0
	for x: Dictionary in p["pitching"]["pitches"]:
		n += int(x["move"])
	return n


func _examples(players: Array) -> String:
	var parts: Array = []
	for p: Dictionary in players.slice(0, 4):
		parts.append("%s %dkm（%s）" % [p["name"], int(p["pitching"].get("velocity", {}).get("kmh", 0)), PitchArsenal.summary(p)])
	return "　".join(parts)


static func _mean(a: Array) -> float:
	var s := 0.0
	for x: Variant in a:
		s += float(x)
	return s / maxf(1, a.size())


static func _sd(a: Array) -> float:
	var m := _mean(a)
	var s := 0.0
	for x: Variant in a:
		s += pow(float(x) - m, 2.0)
	return sqrt(s / maxf(1, a.size()))


static func _stat(a: Array) -> String:
	return "平均 %.2f・標準偏差 %.2f" % [_mean(a), _sd(a)]


static func _sorted(d: Dictionary) -> String:
	var ks: Array = d.keys()
	ks.sort()
	return ", ".join(ks.map(func(k: Variant) -> String: return "%s:%d" % [k, d[k]]))


func _check(ok: bool, message: String) -> void:
	print("  %s  %s" % ["OK" if ok else "NG", message])
	if not ok:
		_failures += 1


## 新しい球種（maybe_learn）：若い投手ほど覚えやすい・覚えると球種が1つ増えて奪三振か被弾抑制が上がる・合わせ直しても消えない
func _check_learn(players: Dictionary) -> void:
	print("== 新しい球種 ==")
	var rng := RandomNumberGenerator.new()
	rng.seed = 79
	var young := [0, 0]
	var old := [0, 0]
	var ok := 0
	var tried := 0
	var example := ""
	for p0: Dictionary in players.values():
		var p: Dictionary = p0.duplicate(true)
		var age := Growth.age_at(p, 2026)
		var n0: int = p["pitching"]["pitches"].size()
		var r: Dictionary = p["pitching"]["ratings"]
		var before := int(r["k9"]["value"]) + int(r["hr9"]["value"])
		var name := PitchArsenal.maybe_learn(p, age, 2026, rng)
		var bucket: Array = young if age <= 23 else old
		bucket[0] += 1
		if name.is_empty():
			continue
		bucket[1] += 1
		tried += 1
		var after := int(r["k9"]["value"]) + int(r["hr9"]["value"])
		PitchArsenal.ensure(p, 2026)
		var names: Array = p["pitching"]["pitches"].map(func(x: Dictionary) -> String: return x["name"])
		if p["pitching"]["pitches"].size() == n0 + 1 and name in names and after > before:
			ok += 1
			if example.is_empty():
				example = "%s %d歳：%s を覚えた（%s）" % [p["name"], age, name, PitchArsenal.summary(p)]
	print("  23歳以下 %d／%d人、24歳以上 %d／%d人が覚えた。例：%s" % [young[1], young[0], old[1], old[0], example])
	_check(tried > 0 and ok == tried, "覚えると球種が1つ増え、奪三振か被弾抑制が上がり、合わせ直しても残る（%d／%d人）" % [ok, tried])
	_check(float(young[1]) / maxf(1, young[0]) > float(old[1]) / maxf(1, old[0]), "若い投手ほど覚えやすい")
