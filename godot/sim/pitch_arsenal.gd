class_name PitchArsenal
extends RefCounted
## 投手の持ち球（docs/AUTORUN.md 作業79。HANDOFF 4.79）。
## ユーザーの声（2026-11-09）：「変化球量の能力追加したり」「単純に奪三振と置き換えるじゃつまんない」「低い評価でも球速速い人いておかしいと思った」。
## 投手の見せる能力は 球速・制球・スタミナ・持ち球（2〜5種。球種ごとに曲がる向きと変化量 1〜7）。
## 奪三振（k9）・被弾抑制（hr9）は画面に出さず、球速と持ち球から計算した値（derive）としてデータに残す
## （総合・年俸・ドラフトの評価・成長の式・試合の基準はこの値を使う）。
## - 実在の選手：能力値ファイルの k9・hr9 に合うように、選手IDで決まる乱数で持ち球の候補を CANDIDATES 通り作り、いちばん合うものを選ぶ（fit）。
##   合わせきれない分（球速が速いのに三振が少ない、など）は計算した値を k9・hr9 に書き戻す（球速が速いだけの投手も少しは意味がある）
## - 持ち球は pitching.pitches（[{name, move}]）、合わせたときの値は pitching.arsenal（{k, h, kmh}）。k9・hr9・球速が変わったら（成長・シーズン中の寄せ）、
##   球種はそのままに変化量だけ合わせ直す（ensure）
## 向き：左＝シュート側（利き腕の側）、右＝スライダー側、下＝落ちる球（右投げ・左投げとも同じ見せ方）

## 球種：dir 向き、k 空振り（三振）、h 被弾の抑え、gb ゴロ、plat 左右の得意（same＝同じ利き腕の打者に強い、opp＝反対の打者に強い）、
## slow 遅い球（速い球との緩急）、w 選ばれやすさ（実在の選手・ふつうの投手）
const TYPES := {
	"スライダー": {"dir": "右", "k": 1.25, "h": 0.30, "gb": 0.0, "plat": "same", "slow": false, "w": 3.0},
	"カットボール": {"dir": "右", "k": 0.70, "h": 0.85, "gb": 0.3, "plat": "same", "slow": false, "w": 1.3},
	"カーブ": {"dir": "右", "k": 0.85, "h": 0.45, "gb": 0.2, "plat": "", "slow": true, "w": 1.6},
	"シュート": {"dir": "左", "k": 0.35, "h": 0.95, "gb": 1.0, "plat": "same", "slow": false, "w": 0.9},
	"ツーシーム": {"dir": "左", "k": 0.30, "h": 1.10, "gb": 1.2, "plat": "", "slow": false, "w": 1.0},
	"シンカー": {"dir": "左", "k": 0.80, "h": 0.85, "gb": 1.0, "plat": "opp", "slow": false, "w": 0.6},
	"フォーク": {"dir": "下", "k": 1.45, "h": 0.55, "gb": 0.6, "plat": "", "slow": false, "w": 1.6},
	"スプリット": {"dir": "下", "k": 1.15, "h": 0.75, "gb": 0.8, "plat": "", "slow": false, "w": 1.0},
	"チェンジアップ": {"dir": "下", "k": 1.00, "h": 0.60, "gb": 0.6, "plat": "opp", "slow": true, "w": 1.0},
}
## 見せる順（横の球は右・左、落ちる球は下）
const ORDER := ["スライダー", "カットボール", "カーブ", "シュート", "ツーシーム", "シンカー", "フォーク", "スプリット", "チェンジアップ"]
## 同時に持たない組み合わせ
const EXCLUSIVE := [["フォーク", "スプリット"]]
## 効く順の重み（持ち球が多いほど少しずつ上がる）
const WEIGHTS := [1.0, 0.7, 0.45, 0.3, 0.2]
## 変化量1あたりの能力値（球種の k・h を掛ける）
const UNIT := 3.0
const K_BASE := 30.0
const H_BASE := 35.0
## 球速1km/h あたりの奪三振・被弾抑制（その年のリーグの平均との差。実在の投手の球速と K/9 の能力値の傾き 約1.5）
const K_VELO := 1.3
const H_VELO := 0.35
## 縦（落ちる球）と横の変化がそろう（どちらも変化量 COMBO_MOVE 以上）と奪三振に足す
const COMBO_K := 2.0
const COMBO_MOVE := 3
## 緩急：遅い球（変化量 COMBO_MOVE 以上）があると、球速（平均 − SLOW_FROM km/h から）1km/h あたり SLOW_K（SLOW_MAX km/h まで）
const SLOW_K := 0.25
const SLOW_FROM := 4.0
const SLOW_MAX := 8.0
const MOVE_MIN := 1
const MOVE_MAX := 7
## 持ち球の候補を何通り作って、いちばん合うものを選ぶか
const CANDIDATES := 8
## 2つ目からの候補に足す罰（ずれの2乗の和）と、これ以下なら次の候補を作らない値
const CANDIDATE_PENALTY := 4.0
const GOOD_FIT := 6.0
## 変化量を4の近くに寄せる重み（合わせるときの罰の項）
const MOVE_PULL := 0.02
## 持ち球の数（先発・救援）の選ばれやすさ [2種, 3種, 4種, 5種]
const COUNT_STARTER := [10, 35, 35, 20]
const COUNT_RELIEF := [35, 45, 17, 3]
## その年のリーグの球速の平均（km/h。generated/ratings/<年>_pre.json の投手）。無い年はいちばん近い年
const VELO_REF := {2008: 144.8, 2009: 144.9, 2010: 144.9, 2011: 145.9, 2012: 146.3, 2013: 146.5, 2014: 146.5,
	2015: 146.8, 2016: 147.2, 2017: 147.9, 2018: 148.4, 2019: 148.8, 2020: 149.3, 2021: 149.6, 2022: 150.0,
	2023: 150.2, 2024: 150.5, 2025: 150.6, 2026: 150.7}
## 架空の候補の型（FictionalTypes）ごとの球種の選ばれやすさの倍率
const TYPE_HINT := {
	"本格派の剛腕": {"フォーク": 2.0, "スライダー": 1.5},
	"技巧派": {"カットボール": 2.0, "ツーシーム": 1.8, "チェンジアップ": 1.6, "カーブ": 1.5},
	"制球職人": {"カットボール": 1.8, "ツーシーム": 1.8, "シュート": 1.5},
	"荒れ球の豪腕": {"フォーク": 1.8, "スライダー": 1.6},
	"サイドスロー": {"シュート": 3.0, "シンカー": 2.0, "スライダー": 1.5, "フォーク": 0.3},
	"アンダースロー": {"シンカー": 4.0, "シュート": 2.0, "カーブ": 1.5, "フォーク": 0.2},
	"リリーフ専任": {"フォーク": 1.8, "スライダー": 1.5},
	"左のワンポイント": {"スライダー": 2.5, "カーブ": 1.5},
	"未完の大器（投手）": {"フォーク": 1.5, "スライダー": 1.3},
}


static func velo_ref(year: int) -> float:
	if VELO_REF.has(year):
		return float(VELO_REF[year])
	return float(VELO_REF[2008 if year < 2008 else 2026])


## 持ち球（[{name, move}]）と球速から [奪三振, 被弾抑制]（能力値の物差し）
static func derive(pitches: Array, kmh: float, ref: float) -> Array:
	var kc: Array = []
	var hc: Array = []
	var has_down := false
	var has_side := false
	var slow := false
	for x: Dictionary in pitches:
		var t: Dictionary = TYPES.get(str(x["name"]), {})
		if t.is_empty():
			continue
		var m := float(x["move"])
		kc.append(float(t["k"]) * m)
		hc.append(float(t["h"]) * m)
		if int(x["move"]) >= COMBO_MOVE:
			has_down = has_down or t["dir"] == "下"
			has_side = has_side or t["dir"] != "下"
			slow = slow or bool(t["slow"])
	kc.sort()
	kc.reverse()
	hc.sort()
	hc.reverse()
	var k := K_BASE + K_VELO * (kmh - ref)
	var h := H_BASE + H_VELO * (kmh - ref)
	for i in mini(kc.size(), WEIGHTS.size()):
		k += UNIT * float(WEIGHTS[i]) * float(kc[i])
		h += UNIT * float(WEIGHTS[i]) * float(hc[i])
	if has_down and has_side:
		k += COMBO_K
	if slow:
		k += SLOW_K * clampf(kmh - ref + SLOW_FROM, 0.0, SLOW_MAX)
	return [k, h]


## 球種 names に合う変化量を探す（start があればそこから）。目標 k・h との差の2乗 + 変化量を4に寄せる罰が最小になるように1ずつ動かす
static func fit(names: Array, kmh: float, ref: float, k: float, h: float, start: Array = []) -> Array:
	var info := _info(names)
	var mv: Array = []
	for i in names.size():
		mv.append(clampi(int(start[i]), MOVE_MIN, MOVE_MAX) if i < start.size() else 3)
	var e := _err(info, mv, kmh, ref, k, h)
	for _round in 80:
		var best := e
		var bi := -1
		var bd := 0
		for i in mv.size():
			for d: int in [-1, 1]:
				var m := int(mv[i]) + d
				if m < MOVE_MIN or m > MOVE_MAX:
					continue
				mv[i] = m
				var e2 := _err(info, mv, kmh, ref, k, h)
				mv[i] = m - d
				if e2 < best - 1e-6:
					best = e2
					bi = i
					bd = d
		if bi < 0:
			break
		e = best
		mv[bi] = int(mv[bi]) + bd
	var out: Array = []
	for i in names.size():
		out.append({"name": names[i], "move": int(mv[i])})
	return out


## 球種ごとの [k, h, 落ちる球か, 遅い球か]（fit の中で何度も引かないように）
static func _info(names: Array) -> Array:
	var out: Array = []
	for n: Variant in names:
		var t: Dictionary = TYPES.get(str(n), {})
		out.append([float(t.get("k", 0.0)), float(t.get("h", 0.0)), t.get("dir", "") == "下", bool(t.get("slow", false))])
	return out


static func _err(info: Array, mv: Array, kmh: float, ref: float, k: float, h: float) -> float:
	var kc: Array[float] = []
	var hc: Array[float] = []
	var down := false
	var side := false
	var slow := false
	var pull := 0.0
	for i in info.size():
		var m := float(mv[i])
		var t: Array = info[i]
		kc.append(float(t[0]) * m)
		hc.append(float(t[1]) * m)
		if int(mv[i]) >= COMBO_MOVE:
			down = down or bool(t[2])
			side = side or not bool(t[2])
			slow = slow or bool(t[3])
		pull += (m - 4.0) * (m - 4.0)
	kc.sort()
	hc.sort()
	var dk := K_BASE + K_VELO * (kmh - ref) - k
	var dh := H_BASE + H_VELO * (kmh - ref) - h
	var n := kc.size()
	for i in mini(n, WEIGHTS.size()):
		dk += UNIT * float(WEIGHTS[i]) * kc[n - 1 - i]
		dh += UNIT * float(WEIGHTS[i]) * hc[n - 1 - i]
	if down and side:
		dk += COMBO_K
	if slow:
		dk += SLOW_K * clampf(kmh - ref + SLOW_FROM, 0.0, SLOW_MAX)
	return dk * dk + dh * dh + MOVE_PULL * pull


## 持ち球の球種を選ぶ（乱数は呼び出し元）
static func pick_names(rng: RandomNumberGenerator, throws: String, starter: bool, hint := "") -> Array:
	var counts: Array = COUNT_STARTER if starter else COUNT_RELIEF
	var n := 2 + _pick_index(rng, counts)
	# 三振型・ゴロ型の向きは選び方に入れない（年ごとの k・h のゆれで球種が変わらないように）。候補を何通りか作って合うものを選ぶ（ensure）
	var w := {}
	for name: String in TYPES:
		w[name] = float(TYPES[name]["w"])
	if throws == "左":
		w["チェンジアップ"] += 0.8
		w["シュート"] *= 0.6
	var mult: Dictionary = TYPE_HINT.get(hint, {})
	for name: String in mult:
		w[name] = float(w[name]) * float(mult[name])
	var out: Array = []
	for _try in 30:
		if out.size() >= n:
			break
		var pool: Array = []
		var ws: Array = []
		for name: String in ORDER:
			if name in out or _excluded(name, out):
				continue
			pool.append(name)
			ws.append(float(w[name]))
		if pool.is_empty():
			break
		out.append(pool[_pick_index(rng, ws)])
	return out


static func _excluded(name: String, have: Array) -> bool:
	for pair: Array in EXCLUSIVE:
		if name in pair:
			for other: String in pair:
				if other != name and other in have:
					return true
	return false


static func _pick_index(rng: RandomNumberGenerator, weights: Array) -> int:
	var total := 0.0
	for x: Variant in weights:
		total += float(x)
	var r := rng.randf() * total
	for i in weights.size():
		r -= float(weights[i])
		if r <= 0.0:
			return i
	return weights.size() - 1


static func _rv(r: Dictionary, k: String) -> Variant:
	var x: Variant = r.get(k)
	return float(x["value"]) if x is Dictionary and x.get("value") != null else null


## 持ち球が無い・今の k9・hr9・球速と合わないときに作る／合わせ直す。k9・hr9 は計算した値に書き戻す（総合も同じだけ動かす）。
## year：その年（球速の基準。−1 なら球速の基準は 2026年）。hint：架空の候補の型の名前。作り直したら true
static func ensure(p: Dictionary, year := -1, hint := "") -> bool:
	var pit: Variant = p.get("pitching")
	if not pit is Dictionary or not pit.get("ratings") is Dictionary:
		return false
	var r: Dictionary = pit["ratings"]
	var k0: Variant = _rv(r, "k9")
	var h0: Variant = _rv(r, "hr9")
	if k0 == null or h0 == null:
		return false
	var sig: Variant = pit.get("arsenal")
	var ref := velo_ref(year if year > 0 else 2026)
	if year <= 0 and sig is Dictionary and sig.get("ref") != null:
		ref = float(sig["ref"])  # 年の分からない呼び出し（試合・画面）は、前に合わせたときの基準のまま
	var v: Variant = pit.get("velocity")
	var kmh := float(v["kmh"]) if v is Dictionary and v.get("kmh") != null else ref
	var have: Array = pit.get("pitches", []) if pit.get("pitches") is Array else []
	if not have.is_empty() and sig is Dictionary and float(sig.get("k", -1)) == float(k0) \
			and float(sig.get("h", -1)) == float(h0) and float(sig.get("kmh", -1)) == kmh:
		return false
	var pitches: Array
	if not have.is_empty():
		var names: Array = []
		var start: Array = []
		for x: Dictionary in have:
			names.append(str(x["name"]))
			start.append(int(x["move"]))
		pitches = fit(names, kmh, ref, float(k0), float(h0), start)
	else:
		var rng := RandomNumberGenerator.new()
		var best_e := INF
		var starter := str(pit.get("role", "")) == "先発"
		var throws := str(p.get("throws", "右")) if p.get("throws") != null else "右"
		for c in CANDIDATES:
			rng.seed = ("%s#%d" % [str(p.get("id", p.get("name", ""))), c]).hash()
			var names := pick_names(rng, throws, starter, hint)
			var cand := fit(names, kmh, ref, float(k0), float(h0))
			var d := derive(cand, kmh, ref)
			# あとの候補ほど罰を足す（同じ選手は年が変わっても最初の候補の球種になりやすい）。よく合えばそこで止める
			var e := pow(float(d[0]) - float(k0), 2.0) + pow(float(d[1]) - float(h0), 2.0) + CANDIDATE_PENALTY * c
			if e < best_e:
				best_e = e
				pitches = cand
			if best_e <= GOOD_FIT:
				break
	pitches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return ORDER.find(a["name"]) < ORDER.find(b["name"]))
	pit["pitches"] = pitches
	var d := derive(pitches, kmh, ref)
	var k1 := clampi(roundi(float(d[0])), 1, 100)
	var h1 := clampi(roundi(float(d[1])), 1, 100)
	var shift := (float(k1) - float(k0) + float(h1) - float(h0)) / 3.0
	_write(r, "k9", k1)
	_write(r, "hr9", h1)
	if absf(shift) >= 0.5 and _rv(r, "overall") != null:
		_write(r, "overall", clampi(roundi(float(_rv(r, "overall")) + shift), 1, 100))
	pit["arsenal"] = {"k": float(k1), "h": float(h1), "kmh": kmh, "ref": ref}
	return true


static func _write(r: Dictionary, k: String, v: int) -> void:
	var old: Variant = r.get(k)
	var e: Dictionary = old.duplicate() if old is Dictionary else {}
	e["value"] = v
	e["rank"] = Growth.rank_of(float(v))
	r[k] = e


## 選手の一覧（能力値ファイルの players など）の投手すべて
static func ensure_all(players: Array, year := -1) -> int:
	var n := 0
	for p: Dictionary in players:
		if p.get("pitching") is Dictionary:
			var hint := ""
			if p.get("amateur") is Dictionary:
				hint = str(p["amateur"].get("type_key", ""))
			n += 1 if ensure(p, year, hint) else 0
	return n


## 決め球：奪三振にいちばん効く球（空振り × 変化量）。持ち球が無ければ {}
static func best_pitch(p: Dictionary) -> Dictionary:
	var pit: Variant = p.get("pitching")
	if not pit is Dictionary or not pit.get("pitches") is Array:
		return {}
	var best := {}
	var best_v := -1.0
	for x: Dictionary in pit["pitches"]:
		var v := float(TYPES.get(str(x["name"]), {}).get("k", 0.0)) * float(x["move"])
		if v > best_v:
			best_v = v
			best = x
	return best


## 持ち球の短い書き方（例「スライダー5・フォーク6★」）
static func summary(p: Dictionary) -> String:
	var pit: Variant = p.get("pitching")
	if not pit is Dictionary or not pit.get("pitches") is Array:
		return ""
	var best := best_pitch(p)
	var parts: Array = []
	for x: Dictionary in pit["pitches"]:
		parts.append("%s%d%s" % [x["name"], int(x["move"]), "★" if x == best else ""])
	return "・".join(parts)


## 試合の効き方（作業79）：左右の打者による奪三振の上下（z。[同じ利き腕の打者, 反対の打者]）。
## 同じ利き腕に強い球（スライダー・カット・シュート）と反対に強い球（チェンジアップ・シンカー）の奪三振の分の PLATOON 倍を、
## 打者の左右の割合（SAME_SHARE）でならすと0になるように上下に分ける（投手の平均の奪三振は k9 のまま）
const PLATOON := 0.35
## 投げる手ごとの、同じ利き腕の打者の割合（両打ちは反対の打席に立つ）
const SAME_SHARE := {"右": 0.6, "左": 0.4}
## ゴロの多さ：持ち球のゴロ（効く順の重み）の、実在の投手（2026年）の平均と標準偏差
const GB_MEAN := 6.2
const GB_SD := 3.4


static func platoon(pitches: Array, throws: String) -> Array:
	var s := float(SAME_SHARE.get(throws, 0.6))
	var kc: Array = []
	for x: Dictionary in pitches:
		var t: Dictionary = TYPES.get(str(x["name"]), {})
		kc.append([float(t.get("k", 0.0)) * float(x["move"]), str(t.get("plat", ""))])
	kc.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var same := 0.0
	var opp := 0.0
	for i in mini(kc.size(), WEIGHTS.size()):
		var c := PLATOON * UNIT * float(WEIGHTS[i]) * float(kc[i][0]) / 17.0
		if kc[i][1] == "same":
			same += c
			opp -= c * s / (1.0 - s)
		elif kc[i][1] == "opp":
			opp += c
			same -= c * (1.0 - s) / s
	return [same, opp]


## ゴロの多さ（z。0 が実在の投手の平均）
static func groundball(pitches: Array) -> float:
	var g: Array = []
	for x: Dictionary in pitches:
		g.append(float(TYPES.get(str(x["name"]), {}).get("gb", 0.0)) * float(x["move"]))
	g.sort()
	g.reverse()
	var raw := 0.0
	for i in mini(g.size(), WEIGHTS.size()):
		raw += float(WEIGHTS[i]) * float(g[i])
	return (raw - GB_MEAN) / GB_SD


static func groundball_raw(pitches: Array) -> float:
	return groundball(pitches) * GB_SD + GB_MEAN


## 一覧の短い書き方の決め球（例「フォーク6」。持ち球が無ければ "-"）
static func best_label(p: Dictionary) -> String:
	ensure(p)
	var b := best_pitch(p)
	return "%s%d" % [b["name"], int(b["move"])] if not b.is_empty() else "-"
