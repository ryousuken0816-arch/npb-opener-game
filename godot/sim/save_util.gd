class_name SaveUtil
extends RefCounted
## セーブ／ロードの補助（JSON の数値・乱数の状態）。オートロードを参照しない（テストが型として読む Season などからも使う）

## JSON で小数になった整数を int に戻す（入れ子の Array・Dictionary も。小数部のある値はそのまま）
static func ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if f == floorf(f) and absf(f) < 9.0e15:
				return int(f)
			return f
		TYPE_DICTIONARY:
			var d: Dictionary = v
			for key: Variant in d:
				d[key] = ints(d[key])
			return d
		TYPE_ARRAY:
			var a: Array = v
			for i in a.size():
				a[i] = ints(a[i])
			return a
	return v


## 乱数の状態（64ビット）を文字列で（小数にすると桁が落ちるので）
static func rng_state(rng: RandomNumberGenerator) -> String:
	return str(rng.state)


static func set_rng_state(rng: RandomNumberGenerator, state: Variant) -> void:
	var text := str(state)
	if not text.is_empty() and text.is_valid_int():
		rng.state = text.to_int()
