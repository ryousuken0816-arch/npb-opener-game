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

## 守備位置の慣れ（作業44）：能力値の fielding.<位置>.detail の weight（その位置の守備の出場量。少サンプル補正の重みで、
## 正選手は 1.0）× FAMILIAR_SCALE を上限1にしたもの。守備力は「慣れ × 守備力 + (1 − 慣れ) × 不慣れの値」で使う
## （ほとんど守ったことのない位置に、少サンプル補正の C 前後の守備力が付いていても、試合・スタメン選考では低く扱う）
const FAMILIAR_SCALE := 2.5
## 記録のない・慣れていない位置の守備 z 値（一塁は易しいので高め）
const UNFAMILIAR_Z := -2.5
const UNFAMILIAR_Z_FIRST := -1.0
## この慣れ以上なら「守れる位置」（控え捕手を選ぶときなど）
const FAMILIAR_MIN := 0.5

## 外野の守備範囲に混ぜる走力の割合（作業43。範囲 = (1−割合) × 守備力 + 割合 × 走力。中堅は広く走るので大きめ）
const RANGE_SPEED_SHARE := {"中堅手": 0.3, "左翼手": 0.1, "右翼手": 0.1}

var id: String
var name: String
var team: String
var is_pitcher: bool
var bats: String  ## "右" / "左" / "両"
var throws: String
var primary_pos := ""  ## 能力値データの primary_pos（"投手" "捕手" "外野手" など。不明は空）
var is_foreign := false  ## 外国人枠の対象（RosterRules.is_foreign）
var is_ikusei := false  ## 育成選手（支配下登録するまで1軍に登録できない。GameState.mark_ikusei が付ける）
## 調子（-2〜2）と故障（作業45。Health.apply が毎日付ける）。故障中は1軍の試合に出ない
var form := 0
var injured := false
var injury := ""  ## 故障のひとこと（"故障 右肘の炎症（あと12日）" など。出られれば空）

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
var familiarity := {}  ## 位置 → 慣れ（0〜1）

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
	s.primary_pos = p["primary_pos"] if p.get("primary_pos") != null else ""

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
			s.familiarity[pos] = familiarity_of(f)
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


## 能力だけを能力値データから読み直す（シーズン中に能力を史実へ寄せたとき。作業40）。
## 所属・育成・外国人枠・投手の役割・出場量はそのまま
func refresh_from(p: Dictionary) -> void:
	var s := SimPlayer.from_rating(p)
	for key in ["meet", "power", "eye", "speed", "trajectory", "defense", "arm", "familiarity",
			"overall", "k9", "bb9", "hr9", "stamina"]:
		set(key, s.get(key))


## 能力値の守備位置の項目（fielding.<位置>）→ 慣れ（0〜1）。detail の weight（basement の年）か detail.err.weight
## （npb.jp の年）。detail が無い（架空の選手・新人の仮の守備位置など）ときは慣れているとみなす
static func familiarity_of(f: Dictionary) -> float:
	var detail: Variant = f.get("detail")
	if not detail is Dictionary:
		return 1.0
	var w: Variant = detail.get("weight")
	if w == null and detail.get("err") is Dictionary:
		w = detail["err"].get("weight")
	if w == null:
		return 1.0
	return clampf(float(w) * FAMILIAR_SCALE, 0.0, 1.0)


## その位置の守備 z 値。記録のない位置・慣れていない位置は不慣れとして大きく下げる（作業44）
func defense_at(pos: String) -> float:
	var low := UNFAMILIAR_Z_FIRST if pos == "一塁手" else UNFAMILIAR_Z
	if not defense.has(pos):
		return low
	var f: float = familiarity.get(pos, 1.0)
	return f * float(defense[pos]) + (1.0 - f) * low


## その位置を守れるか（慣れが FAMILIAR_MIN 以上）
func can_play(pos: String) -> bool:
	return defense.has(pos) and float(familiarity.get(pos, 1.0)) >= FAMILIAR_MIN


## 守備範囲の z 値（slot はスタメンの位置。中堅手・左翼手・右翼手は守備力に走力を混ぜる。ほかは defense_at と同じ）
func range_at(slot: String) -> float:
	var key := "外野手" if RANGE_SPEED_SHARE.has(slot) else slot
	var d := defense_at(key)
	var share: float = RANGE_SPEED_SHARE.get(slot, 0.0)
	return (1.0 - share) * d + share * speed


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
