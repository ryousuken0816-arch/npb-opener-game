extends SceneTree
## 架空のドラフト候補のメジャー志望の人数（docs/AUTORUN.md 作業78。ヘッドレスで数十秒）：
##   2028〜2040年（と種を変えたもう1巡）の候補を作り、年ごとのメジャー志望の人数を数える。
##   - 年平均 約1人（0人の年も2人以上の年もある）
##   - 目玉（評価 S・A）だけでなく、ときどき中位（B・C の大学生・社会人・独立）も表明する
##   - 育成枠の候補・意中の球団（作業77）とは重ならない
##
##   godot --headless --path godot --script res://tests/mlb_intent_count_check.gd
##
## すべて OK なら "ALL OK"、1つでも NG があれば "FAILED" を出して終了コード 1。

const TEAMS := ["読売ジャイアンツ", "阪神タイガース", "中日ドラゴンズ", "横浜DeNAベイスターズ", "広島東洋カープ",
	"東京ヤクルトスワローズ", "福岡ソフトバンクホークス", "北海道日本ハムファイターズ", "千葉ロッテマリーンズ",
	"東北楽天ゴールデンイーグルス", "埼玉西武ライオンズ", "オリックス・バファローズ"]

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fd_script: GDScript = load("res://sim/fictional_draft.gd")
	# 意中の球団（作業77）があれば重ならないかも見る
	var di: GDScript = load("res://sim/draft_intent.gd") if ResourceLoader.exists("res://sim/draft_intent.gd") else null
	var fd: RefCounted = fd_script.new()
	var total := 0
	var years := 0
	var zero := 0
	var multi := 0
	var mid := 0
	var by_grade := {}
	var overlap := 0
	var ikusei := 0
	for round_i in 2:
		var line: Array[String] = []
		for y in range(2028, 2041):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("mlb-count:%d:%d" % [round_i, y])
			var cls: Array = fd.generate_year(y, rng)
			var irng := RandomNumberGenerator.new()
			irng.seed = hash("intent:%d:%d" % [round_i, y])
			if di != null:
				di.assign(cls, TEAMS, irng)
			var n := 0
			for p: Dictionary in cls:
				var am: Dictionary = p["amateur"]
				var mi: Variant = am.get("mlb_intent")
				if not (mi is Dictionary and bool(mi.get("stated", false))):
					continue
				n += 1
				by_grade[am["grade"]] = int(by_grade.get(am["grade"], 0)) + 1
				if am["grade"] in ["B", "C"]:
					mid += 1
				if am.has("team_intent"):
					overlap += 1
				if bool(am.get("as_ikusei", false)):
					ikusei += 1
				if round_i == 0:
					print("  %d年 %s（%s・%s・評価%s）：%s" % [y, p["name"], am["school"], am["category"], am["grade"],
						mi["note"]])
			total += n
			years += 1
			zero += 1 if n == 0 else 0
			multi += 1 if n >= 2 else 0
			line.append("%d:%d" % [y, n])
		print("  " + " ".join(line))
	var avg := float(total) / years
	print("  %d年分で%d人（年平均%.2f人、0人の年%d・2人以上の年%d）　評価ごと：%s" % [years, total, avg, zero, multi,
		str(by_grade)])
	_check(avg >= 0.7 and avg <= 1.4, "年平均 約1人（%.2f人）" % avg)
	_check(zero >= 2 and multi >= 2, "0人の年も2人以上の年もある（0人%d年・2人以上%d年）" % [zero, multi])
	_check(mid >= 2 and mid < total, "ときどき中位（B・C）の候補も表明する（%d人）" % mid)
	_check(overlap == 0 and ikusei == 0, "育成枠・意中の球団の候補とは重ならない")
	print("ALL OK" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["OK" if ok else "NG", label])
	if not ok:
		_failures += 1
