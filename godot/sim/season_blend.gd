class_name SeasonBlend
extends RefCounted
## シーズン中に能力を史実へ寄せる（docs/AUTORUN.md 作業40）。
##
## 史実のある年（その年の `<年>_post` がその年の成績まで入っている年。2008〜2026年）は、開幕を `<年>_pre` の能力で始め、
## 月替わりごとに、リーグ全体の消化した試合の割合 × `SPEED`（上限1）だけ `<年>_post` の値へ混ぜる
## （値 = pre + (post − pre) × 割合 を丸める）。ブレイク・不振が史実のタイミングで能力に出る。
## 混ぜるのは 打撃（ミート・パワー・選球眼・走力・守備力・肩力・弾道）・守備位置ごとの守備力と肩力（両方のファイルにある位置）・
## 投球（総合・スタミナ・K/9・BB/9・HR/9・球速）。役割・特殊能力・detail（実数値）は開幕のまま。
## シーズン後（AWARDS）は今までどおり `<年>_post` を読み直す。史実の無い年（2027年〜）は混ぜない（作業27の成長の仕組み）。
##
## リーグ全体のずれは差し引く：その年に多く出た野手ほど post で上がる（よく打ったから出た）ため、そのまま混ぜると
## 野手だけ平均が上がり打高になる（2008年で打率 +.007）。試合の係数は開幕の能力に合わせてあるので、能力ごとに
## 「出場量（post の加重打席・加重アウト数）で重みを付けた post − pre の平均」（`league_shift`）を post から引いて混ぜ、
## 選手どうしの差の変化（ブレイク・不振）だけを寄せる。守備位置ごとの守備力・肩力・球速は差し引かない。

## 消化した試合の割合に掛ける速さ（1.0 なら全日程の半分を消化した月初めに pre と post の真ん中）
const SPEED := 1.0

const BAT_KEYS := ["meet", "power", "eye", "speed", "defense", "arm"]
## リーグ全体のずれを差し引く打撃の項目（batting.ratings の守備力・肩力は守備位置の値の写しなので差し引かない）
const SHIFT_BAT_KEYS := ["meet", "power", "eye", "speed"]
const PITCH_KEYS := ["overall", "stamina", "k9", "bb9", "hr9"]
const FIELD_KEYS := ["defense", "arm"]
const VALUE_MIN := 1
const VALUE_MAX := 100


## 消化した試合数・全日程の試合数 → 混ぜる割合（0〜1）
static func fraction(played: int, scheduled: int) -> float:
	if scheduled <= 0:
		return 0.0
	return clampf(float(played) / float(scheduled) * SPEED, 0.0, 1.0)


## pre（開幕時点）と post（シーズン後）のファイルが、その年の成績を混ぜられる組か
static func applies(pre: Dictionary, post: Dictionary) -> bool:
	if pre.is_empty() or post.is_empty() or pre.get("synthetic", false) or post.get("synthetic", false):
		return false
	var pre_through: Variant = pre.get("stats_through")
	var post_through: Variant = post.get("stats_through")
	if pre_through == null or post_through == null:
		return false
	return int(post_through) == int(pre.get("year", -1)) and int(post_through) > int(pre_through)


## 能力ごとのリーグ全体のずれ {"batting": {キー: 平均}, "pitching": {キー: 平均}}。pre_players は開幕時点の選手データ、
## post_by_id は 選手ID → post の選手データ。重みは post の加重打席（野手）・加重アウト数（投手）
static func league_shift(pre_players: Array, post_by_id: Dictionary) -> Dictionary:
	var out := {"batting": {}, "pitching": {}}
	var specs := [["batting", SHIFT_BAT_KEYS, "pa_1"], ["pitching", PITCH_KEYS, "outs_1"]]
	for spec: Array in specs:
		var part: String = spec[0]
		var sums := {}
		var weights := {}
		for p: Dictionary in pre_players:
			var q: Dictionary = post_by_id.get(p["id"], {})
			if q.is_empty() or (part == "batting" and p.get("is_pitcher", false)):
				continue
			var a: Variant = p.get(part)
			var b: Variant = q.get(part)
			if not (a is Dictionary and b is Dictionary):
				continue
			var w := float(b.get("sample", {}).get(spec[2], 0.0))
			if w <= 0.0:
				continue
			for key: String in spec[1]:
				var ra: Variant = a.get("ratings", {}).get(key)
				var rb: Variant = b.get("ratings", {}).get(key)
				if ra is Dictionary and rb is Dictionary and ra.get("value") != null and rb.get("value") != null:
					sums[key] = float(sums.get(key, 0.0)) + w * (float(rb["value"]) - float(ra["value"]))
					weights[key] = float(weights.get(key, 0.0)) + w
		for key: String in sums:
			out[part][key] = sums[key] / weights[key]
	return out


## 混ぜる前の能力の写し（選手データのうち混ぜる部分）
static func snapshot(p: Dictionary) -> Dictionary:
	var snap := {}
	for part in ["batting", "pitching", "fielding"]:
		if p.get(part) is Dictionary:
			snap[part] = (p[part] as Dictionary).duplicate(true)
	return snap


## p（今の能力値データ。その場で書き換える）を、写し base と post の選手データ（から shift＝league_shift を引いたもの）の
## 間で t の割合に混ぜる。t = 0 なら写しのとおりに戻す
static func blend(p: Dictionary, base: Dictionary, post: Dictionary, t: float, shift: Dictionary = {}) -> void:
	_restore(p, base)
	if t <= 0.0 or post.is_empty():
		return
	var bat: Variant = p.get("batting")
	var post_bat: Variant = post.get("batting")
	if bat is Dictionary and post_bat is Dictionary:
		_mix_keys(bat.get("ratings"), post_bat.get("ratings"), BAT_KEYS, t, shift.get("batting", {}))
		if bat.get("trajectory") != null and post_bat.get("trajectory") != null:
			bat["trajectory"] = clampi(roundi(lerpf(float(bat["trajectory"]), float(post_bat["trajectory"]), t)), 1, 4)
	var fld: Variant = p.get("fielding")
	var post_fld: Variant = post.get("fielding")
	if fld is Dictionary and post_fld is Dictionary:
		for pos: String in fld:
			if post_fld.has(pos):
				_mix_keys(fld[pos], post_fld[pos], FIELD_KEYS, t)
	var pit: Variant = p.get("pitching")
	var post_pit: Variant = post.get("pitching")
	if pit is Dictionary and post_pit is Dictionary:
		_mix_keys(pit.get("ratings"), post_pit.get("ratings"), PITCH_KEYS, t, shift.get("pitching", {}))
		var v: Variant = pit.get("velocity")
		var pv: Variant = post_pit.get("velocity")
		if v is Dictionary and pv is Dictionary and v.get("kmh") != null and pv.get("kmh") != null:
			v["kmh"] = roundi(lerpf(float(v["kmh"]), float(pv["kmh"]), t))


static func _restore(p: Dictionary, base: Dictionary) -> void:
	for part: String in base:
		p[part] = (base[part] as Dictionary).duplicate(true)


static func _mix_keys(r: Variant, q: Variant, keys: Array, t: float, shift: Dictionary = {}) -> void:
	if not (r is Dictionary and q is Dictionary):
		return
	for key: String in keys:
		var a: Variant = r.get(key)
		var b: Variant = q.get(key)
		if a is Dictionary and b is Dictionary and a.get("value") != null and b.get("value") != null:
			var goal := float(b["value"]) - float(shift.get(key, 0.0))
			var v := clampi(roundi(lerpf(float(a["value"]), goal, t)), VALUE_MIN, VALUE_MAX)
			a["value"] = v
			a["rank"] = Growth.rank_of(v)
