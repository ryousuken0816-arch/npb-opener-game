class_name RosterRules
extends RefCounted
## 出場選手登録（1軍登録）の史実のルール。
##
## - 1軍の登録人数の上限：2008〜2018年 28人、2019年以降 29人、2020・2021年は特例で 31人
## - 外国人枠：1軍に登録できる外国人は 4人まで（2020・2021年の特例は 5人）。
##   投手だけ・野手だけで枠を使い切ることはできない（4人枠なら投手・野手それぞれ3人まで）
## - 登録を抹消された選手は、抹消から10日間は再登録できない
## - 外国人でも日本の球団に8シーズン以上在籍した（国内FA権を取った）選手は「日本人扱い」で枠の対象外
##
## 外国人かどうかはデータに項目が無いので、ドラフト指名歴が無く（draft が空）経歴（career）がある選手を
## 外国人とみなす（韓国・台湾などから来た選手を含む。日本の学校からドラフトで入った陽岱鋼・林威助らは日本人扱い）。
## 在籍年数は 1軍初出場の年（rosters.json の debut_year）から数える（近似）。

const REREGISTER_DAYS := 10
const FOREIGN_EXEMPT_SEASONS := 8
## 1軍に最低限必要な人数（スタメンを組めなくなる・投手がいなくなる抹消はできない）
const MIN_FIELDERS := 9
const MIN_PITCHERS := 1


## その年の1軍登録の上限人数
static func roster_limit(year: int) -> int:
	if year in [2020, 2021]:
		return 31
	if year >= 2019:
		return 29
	return 28


## その年の1軍に登録できる外国人の人数
static func foreign_limit(year: int) -> int:
	return 5 if year in [2020, 2021] else 4


## 投手・野手それぞれに登録できる外国人の上限（片方だけで枠を使い切れない）
static func foreign_type_limit(year: int) -> int:
	return foreign_limit(year) - 1


## 能力値データの選手が、その年の外国人枠の対象か。debut_year は1軍初出場の年（不明なら null）
static func is_foreign(p: Dictionary, year: int, debut_year: Variant) -> bool:
	if p.get("provisional_id", false):
		return false
	var draft: Variant = p.get("draft")
	var career: Variant = p.get("career")
	if (draft is String and not draft.is_empty()) or not (career is String) or career.is_empty():
		return false
	if debut_year != null and year - int(debut_year) >= FOREIGN_EXEMPT_SEASONS:
		return false
	return true
