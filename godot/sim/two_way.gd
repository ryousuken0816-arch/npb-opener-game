class_name TwoWay
extends RefCounted
## 二刀流（docs/AUTORUN.md 作業86）：投打の両方で試合に出る選手。
##
## - 架空の選手：能力値の two_way {active, type}（sim/fictional_talent.gd。A＝本格二刀流・B＝投手本職＋打撃・C＝野手本職＋投手・D＝素材）。
##   成長で専念すると active が false になり、ふつうの選手になる（sim/growth.gd）
## - 実在の選手：前年までの1軍の打席・アウトがどちらも多い選手（大谷 翔平 2014〜2017年だけ）。型は「実」
## - 起用（SimTeam.two_way_modes）：二刀流（投打の両方）／投手に専念／野手に専念。自球団は起用設定で選ぶ。CPU 球団は二刀流のまま

const MODE_BOTH := "二刀流"
const MODE_PITCH := "投手"
const MODE_BAT := "野手"
const MODES := [MODE_BOTH, MODE_PITCH, MODE_BAT]
const MODE_LABELS := {"二刀流": "二刀流", "投手": "投手に専念", "野手": "野手に専念"}
## 実在の選手を二刀流とみなす前年までの1軍の加重打席・アウト（ふつうの先発投手の打席は多くて150）
const REAL_MIN_PA := 180.0
const REAL_MIN_OUTS := 150.0
## 実在の選手の型
const TYPE_REAL := "実"
## 速報にする投打の節目 [勝, 本塁打, 見出し]（同じ年に両方を越えたとき）
const FEATS := [[10, 10, "二桁勝利・二桁本塁打"], [10, 20, "10勝・20本塁打"], [15, 30, "15勝・30本塁打"]]


## 二刀流の型（"A"〜"D"、実在の選手は "実"）。二刀流でなければ ""
static func type_of(p: Dictionary) -> String:
	var tw: Variant = p.get("two_way")
	if tw is Dictionary:
		if bool(tw.get("active", false)):
			var t := str(tw.get("type", ""))
			return t if not t.is_empty() else "A"
		if tw.has("focus"):
			return ""  # 専念した
	var batting: Variant = p.get("batting")
	var pitching: Variant = p.get("pitching")
	if not (batting is Dictionary and pitching is Dictionary):
		return ""
	var pa := float(batting.get("sample", {}).get("pa_1", 0.0))
	var outs := float(pitching.get("sample", {}).get("outs_1", 0.0))
	if pa >= REAL_MIN_PA and outs >= REAL_MIN_OUTS and batting.get("ratings") is Dictionary \
			and pitching.get("ratings") is Dictionary:
		return TYPE_REAL
	return ""


static func is_two_way(p: Dictionary) -> bool:
	return not type_of(p).is_empty()


## 本格二刀流（型 A・実在）：本職が野手でも、二刀流で起用するときは投手として登録し先発ローテーションに入れる
static func is_full(type: String) -> bool:
	return type == "A" or type == TYPE_REAL


## 起用の名前（表示用）
static func mode_label(mode: String) -> String:
	return str(MODE_LABELS.get(mode, mode))


## 今季の投打の成績で越えた節目（越えた中でいちばん上の見出し。無ければ ""）。before は今日の試合の前の [勝, 本塁打]
static func feat_crossed(before_w: int, before_hr: int, w: int, hr: int) -> String:
	var result := ""
	for f: Array in FEATS:
		var need_w := int(f[0])
		var need_hr := int(f[1])
		if w >= need_w and hr >= need_hr and (before_w < need_w or before_hr < need_hr):
			result = str(f[2])
	return result
