class_name SimPlayer
extends RefCounted
## 試合シミュレーション用の選手データ。能力値（1〜100）を z 値に直して持つ。
##
## 能力値は「63 + 17 × z」で正規化されている（tools/README.md「スケール」）ので、
## z = (値 − 63) / 17 に戻すと、平均的なレギュラー（規定打席・投球回クラス）が 0 になる。

const SCALE_MEAN := 63.0
const SCALE_SD := 17.0

## 能力値が無い（1・2軍とも実績がない）ときの仮の値
const UNKNOWN_BATTING := 45.0
const UNKNOWN_PITCHING := 45.0
const UNKNOWN_STAMINA := 40.0

## 投手が打席に立つときの打撃 z 値（npb.jp の能力値は野手母集団で正規化されているため、
## 投手の打撃能力値は使わず、実際の投手の打撃成績（打率1割前後・三振率4割）相当の値にする）
const PITCHER_BAT_MEET := -3.4
const PITCHER_BAT_POWER := -2.4
const PITCHER_BAT_EYE := -1.6
const PITCHER_BAT_SPEED := -1.0

## 守備位置（fielding のキー）
const POSITIONS := ["捕手", "一塁手", "二塁手", "三塁手", "遊撃手", "外野手"]

var id: String
var name: String
var team: String
var is_pitcher: bool
var bats: String  ## "右" / "左" / "両"
var throws: String

# 打撃（z 値）
var meet := 0.0
var power := 0.0
var eye := 0.0
var speed := 0.0
var trajectory := 2
var batting_sample := 0.0  ## 1軍の加重打席数（オーダーの優先度に使う）

# 守備（位置 → z 値）
var defense := {}
var arm := {}

# 投球（z 値）
var has_pitching := false
var overall := 0.0
var k9 := 0.0
var bb9 := 0.0
var hr9 := 0.0
var stamina := 0.0  ## 能力値（1〜100）のまま
var role := ""  ## "先発" / "救援" / ""
var pitching_sample := 0.0


static func z_of(rating: Variant, fallback: float) -> float:
	var value := fallback
	if rating is Dictionary and rating.get("value") != null:
		value = float(rating["value"])
	return (value - SCALE_MEAN) / SCALE_SD


static func from_rating(p: Dictionary) -> SimPlayer:
	var s := SimPlayer.new()
	s.id = p["id"]
	s.name = p["name"]
	s.team = p["team"]
	s.is_pitcher = p["is_pitcher"]
	s.bats = p["bats"] if p["bats"] != null else "右"
	s.throws = p["throws"] if p["throws"] != null else "右"

	var batting: Variant = p.get("batting")
	if batting is Dictionary and batting.get("ratings") is Dictionary:
		var r: Dictionary = batting["ratings"]
		s.meet = z_of(r.get("meet"), UNKNOWN_BATTING)
		s.power = z_of(r.get("power"), UNKNOWN_BATTING)
		s.eye = z_of(r.get("eye"), UNKNOWN_BATTING)
		s.speed = z_of(r.get("speed"), UNKNOWN_BATTING)
		var traj: Variant = batting.get("trajectory")
		s.trajectory = int(traj) if traj != null else 2
		s.batting_sample = float(batting.get("sample", {}).get("pa_1", 0.0))
	else:
		for key in ["meet", "power", "eye", "speed"]:
			s.set(key, z_of(null, UNKNOWN_BATTING))
	if s.is_pitcher:
		s.meet = PITCHER_BAT_MEET
		s.power = PITCHER_BAT_POWER
		s.eye = PITCHER_BAT_EYE
		s.speed = minf(s.speed, PITCHER_BAT_SPEED)
		s.trajectory = 1

	var fielding: Variant = p.get("fielding")
	if fielding is Dictionary:
		for pos: String in fielding:
			var f: Dictionary = fielding[pos]
			s.defense[pos] = z_of(f.get("defense"), UNKNOWN_BATTING)
			if f.get("arm") != null:
				s.arm[pos] = z_of(f["arm"], UNKNOWN_BATTING)

	var pitching: Variant = p.get("pitching")
	if pitching is Dictionary:
		s.has_pitching = true
		var pr: Variant = pitching.get("ratings")
		if pr is Dictionary:
			s.overall = z_of(pr.get("overall"), UNKNOWN_PITCHING)
			s.k9 = z_of(pr.get("k9"), UNKNOWN_PITCHING)
			s.bb9 = z_of(pr.get("bb9"), UNKNOWN_PITCHING)
			s.hr9 = z_of(pr.get("hr9"), UNKNOWN_PITCHING)
			var st: Variant = pr.get("stamina")
			s.stamina = float(st["value"]) if st is Dictionary else UNKNOWN_STAMINA
		else:
			for key in ["overall", "k9", "bb9", "hr9"]:
				s.set(key, z_of(null, UNKNOWN_PITCHING))
			s.stamina = UNKNOWN_STAMINA
		var role_value: Variant = pitching.get("role")
		s.role = role_value if role_value != null else ""
		s.pitching_sample = float(pitching.get("sample", {}).get("outs_1", 0.0))
	return s


## その位置の守備 z 値。記録のない位置は不慣れとして大きく下げる
func defense_at(pos: String) -> float:
	if defense.has(pos):
		return defense[pos]
	if pos == "一塁手":
		return -1.0
	return -2.5


func arm_at(pos: String) -> float:
	return arm.get(pos, defense_at(pos) * 0.5)


## 打撃の総合的な強さ（オーダーの選考・打順に使う）
func batting_value() -> float:
	return meet * 0.45 + power * 0.4 + eye * 0.2 + speed * 0.05


## スタミナ（能力値）→ 交代の目安の球数。
## 能力値は「1登板あたりのアウト数」を正規化したもの（先発で 62→12アウト、85→21アウト、
## 救援 40→3.3アウト）で、ほぼ直線 outs ≈ 0.395 × 値 − 12.3。1アウトあたり約5.5球として換算
func pitch_limit() -> int:
	var outs := maxf(0.395 * stamina - 12.3, 2.0)
	return int(outs * 5.5 + 15.0)
