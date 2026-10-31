class_name DraftVoice
extends Node
## ドラフトの指名発表の読み上げ（docs/AUTORUN.md 作業28）。声は設定（GameSettings の [voice]）で差し替えられる：
## - os：OS の音声合成（DisplayServer.tts_speak。Windows の日本語の声）。初期値
## - voicevox：自分の PC で動かす VOICEVOX 互換の HTTP API（/audio_query → /synthesis）。URL と話者は設定。
##   つながらない・失敗したときは os に戻る（その起動の間は os のまま）
## - wav：録音のフォルダ（wav_dir）。部品ごとに <キー>.wav があればつないで再生し、無い部分だけ os で読む
## 部品＝{key, text}。キーは round_<N>・ikusei_round_<N>・team_<略称>・name_<名前>・pos_<守備位置>・school_<出身>
## （PickAnnounce.voice_parts が作る。差し込み方は godot/README.md「ドラフトの読み上げ」）。
## 実在のアナウンサーの声をまねることはしない。声のデータ・モデルはリポジトリに入れない（.gitignore）。
## テスト（-s）・ヘッドレスでは音を出さない（muted）。どこから読むかの段取り（last_plan）は同じように作る

const PAUSE_SEC := 0.15
const HTTP_TIMEOUT := 4.0
## OS の音声合成が話し始めるまでの猶予（その間は「話していない」と返ることがある）
const TTS_START_GRACE := 0.4
const SAMPLE_RATE := 22050

## 音を出さない（テスト・ヘッドレス）
var muted := false
## 直前に読んだ段取り [{src: wav/tts, path/text, engine}]（テスト用）
var last_plan: Array[Dictionary] = []
## voicevox に失敗したら true（その起動の間は os で読む）
var voicevox_down := false

static var _chime: AudioStreamWAV

var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _elapsed := 0.0
var _player: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _http: HTTPRequest
var _http_stage := ""
var _os_voice := ""


func _ready() -> void:
	muted = DisplayServer.get_name() == "headless" or GameSettings._under_test()
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)
	_http = HTTPRequest.new()
	_http.timeout = HTTP_TIMEOUT
	_http.request_completed.connect(_on_http_done)
	add_child(_http)


func _process(delta: float) -> void:
	if _current.is_empty():
		return
	_elapsed += delta
	match str(_current.get("src", "")):
		"pause":
			if _elapsed >= PAUSE_SEC:
				_next()
		"wav", "voicevox_play":
			if not _player.playing:
				_next()
		"tts":
			if muted or (_elapsed >= TTS_START_GRACE and not DisplayServer.tts_is_speaking()):
				_next()
		"voicevox":
			pass  # HTTP の返事を待つ


## 部品を読み上げる（前の読み上げは止める）。設定で読み上げがオフなら何もしない
func speak(parts: Array) -> void:
	stop()
	if not bool(GameSettings.get_value("voice", "enabled")):
		last_plan = []
		return
	last_plan = plan(parts, str(GameSettings.get_value("voice", "backend")))
	if muted:
		return
	_queue = last_plan.duplicate()
	_next()


## 読み上げ中か
func is_busy() -> bool:
	return not _current.is_empty()


func stop() -> void:
	_queue.clear()
	_current = {}
	if muted:
		return
	if _player != null:
		_player.stop()
	if _http != null:
		_http.cancel_request()
	if DisplayServer.tts_is_speaking():
		DisplayServer.tts_stop()


## 自球団の指名の効果音（短いチャイム）
func chime() -> void:
	if muted or _sfx == null:
		return
	_sfx.stream = _chime_stream()
	_sfx.volume_db = _volume_db()
	_sfx.play()


## どこから読むかの段取り。wav はファイルがある部品だけ録音、続く無い部品はまとめて音声合成。
## os・voicevox は全体を「、」でつないで一度に読む
func plan(parts: Array, backend: String) -> Array[Dictionary]:
	var engine := "voicevox" if backend == "voicevox" and not voicevox_down else "os"
	var out: Array[Dictionary] = []
	if backend != "wav":
		out.append({"src": engine if engine == "voicevox" else "tts", "text": _join(parts), "engine": engine})
		return out
	var dir := str(GameSettings.get_value("voice", "wav_dir"))
	var pending: Array = []
	for part: Dictionary in parts:
		var path := dir.path_join(str(part["key"]) + ".wav")
		if FileAccess.file_exists(path):
			if not pending.is_empty():
				out.append({"src": "tts", "text": _join(pending), "engine": "os"})
				pending.clear()
			if not out.is_empty():
				out.append({"src": "pause"})
			out.append({"src": "wav", "path": path})
		else:
			pending.append(part)
	if not pending.is_empty():
		out.append({"src": "tts", "text": _join(pending), "engine": "os"})
	return out


func _join(parts: Array) -> String:
	var texts: Array[String] = []
	for part: Dictionary in parts:
		texts.append(str(part["text"]))
	return "、".join(texts)


func _next() -> void:
	_elapsed = 0.0
	if _queue.is_empty():
		_current = {}
		return
	_current = _queue.pop_front()
	match str(_current["src"]):
		"wav":
			var stream := AudioStreamWAV.load_from_file(str(_current["path"]))
			if stream == null:
				_next()
				return
			_play(stream)
		"tts":
			_speak_os(str(_current["text"]))
		"voicevox":
			_voicevox_query(str(_current["text"]))


func _play(stream: AudioStream) -> void:
	_player.stream = stream
	_player.volume_db = _volume_db()
	_player.play()


func _speak_os(text: String) -> void:
	if _os_voice.is_empty():
		var voices := DisplayServer.tts_get_voices_for_language("ja")
		if voices.is_empty():
			push_warning("日本語の音声合成の声が見つかりません（読み上げなし）")
			_current = {}
			_queue.clear()
			return
		_os_voice = voices[0]
	DisplayServer.tts_speak(text, _os_voice, int(GameSettings.get_value("voice", "volume")), 1.0,
		float(GameSettings.get_value("voice", "rate")))


# --- VOICEVOX 互換の HTTP API ---------------------------------------------------------------

func _voicevox_query(text: String) -> void:
	var url := "%s/audio_query?speaker=%d&text=%s" % [_voicevox_url(), _speaker(), text.uri_encode()]
	_http_stage = "query"
	_current["text"] = text
	if _http.request(url, [], HTTPClient.METHOD_POST, "") != OK:
		_voicevox_failed()


func _on_http_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _current.get("src", "") != "voicevox":
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_voicevox_failed()
		return
	if _http_stage == "query":
		var query: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not query is Dictionary:
			_voicevox_failed()
			return
		query["speedScale"] = float(GameSettings.get_value("voice", "rate"))
		_http_stage = "synthesis"
		var url := "%s/synthesis?speaker=%d" % [_voicevox_url(), _speaker()]
		if _http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST,
				JSON.stringify(query)) != OK:
			_voicevox_failed()
		return
	var stream := AudioStreamWAV.load_from_buffer(body)
	if stream == null:
		_voicevox_failed()
		return
	_current["src"] = "voicevox_play"
	_elapsed = 0.0
	_play(stream)


## つながらない・失敗：この起動の間は OS の音声合成で読む
func _voicevox_failed() -> void:
	voicevox_down = true
	push_warning("VOICEVOX 互換のエンジン（%s）につながらないので、OS の音声合成で読みます" % _voicevox_url())
	var text := str(_current.get("text", ""))
	_current = {"src": "tts", "text": text, "engine": "os"}
	for item in last_plan:
		if item.get("engine", "") == "voicevox":
			item["engine"] = "os"
	_elapsed = 0.0
	if not muted:
		_speak_os(text)


func _voicevox_url() -> String:
	return str(GameSettings.get_value("voice", "voicevox_url")).trim_suffix("/")


func _speaker() -> int:
	return int(GameSettings.get_value("voice", "voicevox_speaker"))


## テスト用：音を出さずに VOICEVOX 互換のエンジンへつなげるか試す（つながらなければ voicevox_down）
func probe_voicevox() -> void:
	_current = {"src": "voicevox", "text": "テスト"}
	_voicevox_query("テスト")


func _volume_db() -> float:
	return linear_to_db(maxf(0.001, float(GameSettings.get_value("voice", "volume")) / 100.0))


static func _chime_stream() -> AudioStreamWAV:
	if _chime != null:
		return _chime
	# ピンポン（2音、減衰する正弦波）
	var notes := [[880.0, 0.0], [660.0, 0.22]]
	var n := int(SAMPLE_RATE * 0.9)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var v := 0.0
		for note: Array in notes:
			var dt: float = t - float(note[1])
			if dt >= 0.0:
				v += sin(TAU * float(note[0]) * dt) * exp(-dt * 5.0) * 0.4
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	_chime = AudioStreamWAV.new()
	_chime.format = AudioStreamWAV.FORMAT_16_BITS
	_chime.mix_rate = SAMPLE_RATE
	_chime.data = data
	return _chime
