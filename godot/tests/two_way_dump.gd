extends SceneTree
## 二刀流の候補（docs/AUTORUN.md 作業86）の出る頻度と、本格二刀流（型 A）の入団時・ピークを並べる（表示だけ。ヘッドレスで数十秒）。
##
##   godot --headless --path godot -s res://tests/two_way_dump.gd -- [年数] [種の数]

var _years := 120
var _seeds := 2


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_years = int(args[0])
	if args.size() > 1:
		_seeds = int(args[1])
	_run.call_deferred()


func _run() -> void:
	var fd_script: GDScript = load("res://sim/fictional_draft.gd")
	var counts := {"A": 0, "B": 0, "C": 0, "D": 0}
	var aces: Array = []
	for s in _seeds:
		var fd: RefCounted = fd_script.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 8600 + s
		for y in range(2028, 2028 + _years):
			for p: Dictionary in fd.generate_year(y, rng):
				var tw: Dictionary = p.get("two_way", {})
				if not bool(tw.get("active", false)):
					continue
				counts[str(tw["type"])] += 1
				if str(tw["type"]) == "A":
					PitchArsenal.ensure(p, y + 1)  # ゲームと同じ（GameData.set_draft_class）
					p["_year"] = y
					aces.append(p)
	var n := float(_years * _seeds)
	print("== 二刀流の候補（%d年 × %d通り） ==" % [_years, _seeds])
	for t: String in counts:
		print("  型 %s：%d人（1年あたり %.3f人＝%.1f年に1人）" % [t, counts[t], counts[t] / n, n / maxf(1.0, counts[t])])
	print("\n== 型 A %d人（入団時 → ピーク） ==" % aces.size())
	var sums := {}
	for p: Dictionary in aces:
		var pr: Dictionary = p["pitching"]["ratings"]
		var br: Dictionary = p["batting"]["ratings"]
		var pk: Dictionary = p["growth"]["peak"]
		var best := PitchArsenal.best_pitch(p)
		var am: Dictionary = p["amateur"]
		print("  %d %s %s（%s・評価%s・%s・%d球団） 投：%dkm 総合%d 奪三振%d→%d 制球%d 被弾%d スタミナ%d 決め球%s%d ／ 打：ミート%d→%d パワー%d→%d 選球眼%d 走力%d 肩%d 守備%d 弾道%s" % [
			p["_year"], p["name"], am["category"], am.get("type", ""), am["grade"], am.get("projected", ""), int(am.get("bids", 1)),
			int(p["pitching"]["velocity"]["kmh"]), _v(pr, "overall"), _v(pr, "k9"), int(pk.get("k9", 0)), _v(pr, "bb9"), _v(pr, "hr9"),
			_v(pr, "stamina"), best.get("name", "-"), int(best.get("move", 0)),
			_v(br, "meet"), int(pk.get("meet", 0)), _v(br, "power"), int(pk.get("power", 0)), _v(br, "eye"), _v(br, "speed"),
			_v(br, "arm"), _v(br, "defense"), str(p["batting"].get("trajectory", "-"))])
		for k: String in ["velo", "k9", "bb9", "hr9", "stamina", "meet", "power", "batmax", "best"]:
			var v := 0.0
			match k:
				"velo": v = float(p["pitching"]["velocity"]["kmh"])
				"batmax": v = maxf(_v(br, "meet"), _v(br, "power"))
				"best": v = float(best.get("move", 0))
				"meet", "power": v = _v(br, k)
				_: v = _v(pr, k)
			sums[k] = float(sums.get(k, 0.0)) + v
	if not aces.is_empty():
		var parts := []
		for k: String in sums:
			parts.append("%s %.1f" % [k, sums[k] / aces.size()])
		print("  平均：", ", ".join(parts))
	quit(0)


static func _v(r: Dictionary, k: String) -> int:
	var x: Variant = r.get(k)
	return int(x["value"]) if x is Dictionary and x.get("value") != null else 0
