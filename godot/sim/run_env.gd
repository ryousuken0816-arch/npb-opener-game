class_name RunEnv
extends RefCounted
## 年ごとの点の入りやすさ（作業70）。
##
## 能力値は「その年までの5年の中での位置」（z）なので、年ごとの水準（飛ばないボール・投高打低）は能力値に残らない。
## 試合の基準の確率（GameSim の BASE_K・BASE_BB・BASE_HR・BASE_SHARP。2008年に合わせた値）に、その年のずれ（ロジット）を足して
## リーグの成績を史実に合わせる。ずれは generated/run_env.json（tools/fit_run_env.py が godot/tests/run_env_fit.gd で
## 各年を回して合わせる）。表に無い先の年（2027年〜）は future（直近3年の平均）、表より前の年はいちばん古い年。
## league は史実のリーグの OPS・防御率（年俸の査定 Salary.season_ability が年ごとの水準で比べるのに使う）

const FILE := "run_env.json"
const KEYS := ["k", "bb", "hr", "sharp"]
const REFERENCE_YEAR := 2008

static var _data: Dictionary = {}
static var _loaded := false


## その年のずれ {k, bb, hr, sharp}（ロジット。無ければ空 → ずれ 0）
static func for_year(year: int) -> Dictionary:
	return _lookup("years", "future", year)


## その年の史実のリーグ成績 {ops, era}（年俸の査定の基準を年ごとの水準に合わせる。無ければ空）
static func league(year: int) -> Dictionary:
	return _lookup("league", "league_future", year)


## 2008年（試合の計算・年俸の査定の基準を合わせた年）のリーグ成績
static func reference_league() -> Dictionary:
	return data().get("league", {}).get(str(REFERENCE_YEAR), {})


static func _lookup(section: String, future_key: String, year: int) -> Dictionary:
	var d := data()
	var years: Dictionary = d.get(section, {})
	if years.is_empty():
		return {}
	var key := str(year)
	if years.has(key):
		return years[key]
	var nums: Array = years.keys().map(func(k: String) -> int: return int(k))
	nums.sort()
	if year > int(nums[-1]):
		return d.get(future_key, years[str(nums[-1])])
	return years[str(nums[0])]


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = _load()
	return _data


static func _load() -> Dictionary:
	var bundled := "res://data/generated".path_join(FILE)
	var path := bundled
	if not FileAccess.file_exists(bundled):
		path = ProjectSettings.globalize_path("res://").path_join("../generated").path_join(FILE).simplify_path()
		if not FileAccess.file_exists(path):
			return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
