class_name DraftVoice
extends Node
## ドラフトの指名発表の読み上げ（docs/AUTORUN.md 作業28）。声は設定（GameSettings の [voice]）で差し替えられる：
## - os：OS の音声合成（DisplayServer.tts_speak。Windows の日本語の声）。初期値
## - voicevox：自分の PC で動かす VOICEVOX 互換の HTTP API（/audio_query → /synthesis）。URL と話者は設定。
##   つながらない・失敗したときは os に戻る（その起動の間は os のまま）
## - wav：録音のフォルダ（wav_dir）。部品ごとに <キー>.wav があればつないで再生し、無い部分だけ os で読む
## Web 版は設定によらず、ページを出しているサーバーが voice/ で録音の部品を渡していれば（tools/serve_web.py の
## --voice-dir）、部品ごとに取り寄せて wav と同じようにつなぐ（無い部品・取れない部品だけ os で読む）。
## 録音はゲームにも GitHub Pages にも入れず、自分の PC から同じ Wi-Fi のスマホへ渡すため
## 部品＝{key, text}。キーは round_<N>・ikusei_round_<N>・team_<略称>・name_<名前>・pos_<守備位置>・school_<出身>
## （PickAnnounce.voice_parts が作る。差し込み方は godot/README.md「ドラフトの読み上げ」）。
## 実在のアナウンサーの声をまねることはしない。声のデータ・モデルはリポジトリに入れない（.gitignore）。
## テスト（-s）・ヘッドレスでは音を出さない（muted）。どこから読むかの段取り（last_plan）は同じように作る
##
## OS の音声合成は終わり際に止めない（作業42）。Godot 4.7 の Windows（OneCore）は、読み終えた瞬間に別のスレッドで
## MediaPlayer を閉じる。同じときに tts_stop() でメインのスレッドからも閉じると、ゲームごと固まる
## （発表の最後の部品を OS の声で読み終えたところで「次へ」を押すとフリーズした）。
## そこで、残りが短いと見込まれるときは止めずに自然に終わらせ、終わるまで次の OS の読み上げを始めない。
## テストでは tts_sim で OS の音声合成のまねをする（音を出さない。終わりの合図が来る・来ないを作れる）
## Web 版（ブラウザの speechSynthesis）では終わり際の待ちはしない（いつでもすぐ止める）。発表も読み上げの終わりを待たない（作業63）

const PAUSE_SEC := 0.15
const HTTP_TIMEOUT := 4.0
## OS の音声合成が話し始めるまでの猶予（その間は「話していない」と返ることがある）
const TTS_START_GRACE := 0.4
const SAMPLE_RATE := 22050
## OS の音声合成の長さの見込み（1文字あたりの秒。短めに見込むほど、終わり際に止めない側に倒れる）
const TTS_SEC_PER_CHAR := 0.08
## 見込みの残りがこれより短ければ止めない（秒）
const TTS_CUT_MARGIN := 0.8
## 前の OS の読み上げが終わるのを待つ上限（終わりの合図が来ないとき。過ぎたらその部品は読まない）
const TTS_BUSY_WAIT := 5.0
## Web 版の録音の部品の置き場（ページからの相対）と、置き場があるかを調べる URL（置き場からの相対）
const WEB_VOICE_DIR := "voice/"
const WEB_VOICE_PING := "ping"

## 音を出さない（テスト・ヘッドレス）
var muted := false
## 直前に読んだ段取り [{src: wav/tts, path/text, engine}]（テスト用）
var last_plan: Array[Dictionary] = []
## voicevox に失敗したら true（その起動の間は os で読む）
var voicevox_down := false
## テスト用：OS の音声合成のまね {sec_per_char（実際の速さ）, never_end（終わりの合図が来ない）}。空なら本物
var tts_sim: Dictionary = {}
## テスト用：OS の音声合成への呼び出しの記録 [{op: speak/stop/hold, left（そのときの本当の残り秒。まねのときだけ）}]
var tts_log: Array[Dictionary] = []
## Web 版の録音の部品の置き場（末尾は /）。空なら無い（調べる前・サーバーが渡していない・Web 版でない）。テストでは直接入れる
var web_voice_url := ""
## Web 版の部品の取り寄せ {キー: {done: 取り寄せ終わったか, stream: 録音（取れなければ null）, http: 取り寄せ中の HTTPRequest}}
var web_fetched: Dictionary = {}

static var _chime: AudioStreamWAV

var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _elapsed := 0.0
var _player: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _http: HTTPRequest
var _http_stage := ""
var _os_voice := ""
## いまの OS の読み上げを始めてからの秒と、長さの見込み（秒）。読み上げていなければ -1
var _tts_elapsed := -1.0
var _tts_estimate := 0.0
## まね：残りの秒（never_end なら止めるまで終わらない）
var _sim_left := 0.0


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
	if OS.has_feature("web") and not muted:
		_probe_web_voice()


func _process(delta: float) -> void:
	_tick_tts(delta)
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
		"web_wav":
			# 取り寄せが終わるのを待って鳴らす。取れない・待ちすぎたら OS の音声合成で読む
			var got: Dictionary = web_fetched.get(_current["key"], {})
			if got.get("done", false) and got.get("stream") != null:
				_current["src"] = "wav"
				_play(got["stream"])
			elif got.get("done", false) or _elapsed >= HTTP_TIMEOUT:
				_current = {"src": "tts", "text": _current["text"], "engine": "os", "started": false}
				_elapsed = 0.0
		"tts":
			if muted:
				_next()
			elif not _current.get("started", false):
				# 前の読み上げ（終わり際で止めなかったもの）が終わるのを待ってから読む
				if not _tts_speaking():
					_current["started"] = true
					_elapsed = 0.0
					_speak_os(str(_current["text"]))
				elif _elapsed >= TTS_BUSY_WAIT:
					_next()
			elif _elapsed >= TTS_START_GRACE and not _tts_speaking():
				_next()
		"voicevox":
			pass  # HTTP の返事を待つ


## 部品を読み上げる（前の読み上げは止める）。設定で読み上げがオフなら何もしない
func speak(parts: Array) -> void:
	stop()
	if not bool(GameSettings.get_value("voice", "enabled")):
		last_plan = []
		return
	var backend := str(GameSettings.get_value("voice", "backend"))
	var web := not web_voice_url.is_empty() and backend != "voicevox"
	last_plan = plan_web(parts) if web else plan(parts, backend)
	if muted:
		return
	if web:
		fetch_web(parts)
	_queue = last_plan.duplicate()
	_next()


## Web 版か（Web 版の動きをまねるテストでは環境変数 NPB_SIM_WEB=1。作業63）
static func web_like() -> bool:
	return OS.has_feature("web") or OS.get_environment("NPB_SIM_WEB") == "1"


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
	_cancel_web_fetch()
	if _tts_elapsed >= 0.0 or _tts_speaking():
		if tts_cuttable():
			_tts_stop()
		else:
			tts_log.append({"op": "hold", "left": _sim_left if not tts_sim.is_empty() else -1.0})


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
		var path := wav_path(dir, str(part["key"]))
		if not path.is_empty():
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


## Web 版の段取り：部品ごとにサーバーから取り寄せた録音を、間を置いてつなぐ（取れなかった部品は鳴らすときに OS の声へ）
func plan_web(parts: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for part: Dictionary in parts:
		if not out.is_empty():
			out.append({"src": "pause"})
		out.append({"src": "web_wav", "key": str(part["key"]), "text": str(part["text"]),
			"url": web_part_url(str(part["key"]))})
	return out


## Web 版の部品の URL（キーは日本語を含むので % でくるむ）
func web_part_url(key: String) -> String:
	return web_voice_url + key.uri_encode() + ".wav"


## 部品の録音を一度に取り寄せ始める（鳴らす順を待たずに。届いたものから web_fetched に入る）
func fetch_web(parts: Array) -> void:
	_cancel_web_fetch()
	for part: Dictionary in parts:
		var key := str(part["key"])
		if web_fetched.has(key):
			continue
		var http := HTTPRequest.new()
		http.timeout = HTTP_TIMEOUT
		add_child(http)
		web_fetched[key] = {"done": false, "stream": null, "http": http}
		http.request_completed.connect(_on_web_part_done.bind(key, http))
		if http.request(web_part_url(key)) != OK:
			_on_web_part_done(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), key, http)


func _on_web_part_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		key: String, http: HTTPRequest) -> void:
	var stream: AudioStreamWAV = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		stream = AudioStreamWAV.load_from_buffer(body)
	if web_fetched.get(key, {}).get("http") == http:
		web_fetched[key] = {"done": true, "stream": stream}
	http.queue_free()


## 取り寄せ中のものはやめ、取り寄せた録音も捨てる（指名ごとに部品が変わるので持ち越さない）
func _cancel_web_fetch() -> void:
	for got: Dictionary in web_fetched.values():
		var http: Variant = got.get("http")
		if http is HTTPRequest and is_instance_valid(http):
			http.cancel_request()
			http.queue_free()
	web_fetched.clear()


## Web 版：ページを出しているサーバーに録音の部品の置き場があるか調べる（あれば web_voice_url を入れる）
func _probe_web_voice() -> void:
	var base := str(JavaScriptBridge.eval("new URL('%s', location.href).href" % WEB_VOICE_DIR, true))
	if not base.begins_with("http"):
		return
	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			web_voice_url = base
		http.queue_free())
	if http.request(base + WEB_VOICE_PING) != OK:
		http.queue_free()


## 部品の録音のファイル（無ければ空）。出身は「〜大学」の録音が無ければ「〜大」も探す（録音は「法政大」のように略す。
## OS の声で読む部品が減れば、OS の音声合成を止める場面も減る）
static func wav_path(dir: String, key: String) -> String:
	var keys: Array[String] = [key]
	if key.begins_with("school_") and key.ends_with("大学"):
		keys.append(key.trim_suffix("学"))
	for k in keys:
		var path := dir.path_join(k + ".wav")
		if FileAccess.file_exists(path):
			return path
	return ""


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
			_current["started"] = false  # _process で前の読み上げが終わってから読む
		"voicevox":
			_voicevox_query(str(_current["text"]))
		"web_wav":
			pass  # _process で取り寄せが終わるのを待つ


func _play(stream: AudioStream) -> void:
	_player.stream = stream
	_player.volume_db = _volume_db()
	_player.play()


func _speak_os(text: String) -> void:
	if not tts_sim.is_empty():
		_tts_begin(text)
		_sim_left = INF if tts_sim.get("never_end", false) else text.length() * float(tts_sim.get("sec_per_char", 0.12))
		tts_log.append({"op": "speak", "left": _sim_left})
		return
	if _os_voice.is_empty():
		var voices := DisplayServer.tts_get_voices_for_language("ja")
		if voices.is_empty():
			push_warning("日本語の音声合成の声が見つかりません（読み上げなし）")
			_current = {}
			_queue.clear()
			return
		_os_voice = voices[0]
	_tts_begin(text)
	DisplayServer.tts_speak(text, _os_voice, int(GameSettings.get_value("voice", "volume")), 1.0,
		float(GameSettings.get_value("voice", "rate")))


# --- OS の音声合成（終わり際に止めない。作業42） ---------------------------------------------

## 止めてよいか：読み始めてからの秒が長さの見込みより TTS_CUT_MARGIN 以上手前か、まだ話し始めていない（頼んだ直後）とき
func tts_cuttable() -> bool:
	if web_like():
		return _tts_elapsed >= 0.0 or _tts_speaking()  # ブラウザの speechSynthesis はいつ止めても固まらない
	if _tts_elapsed < 0.0:
		return false
	return _tts_elapsed < _tts_estimate - TTS_CUT_MARGIN 		or (_tts_elapsed < TTS_START_GRACE and not _tts_speaking())


func _tts_begin(text: String) -> void:
	_tts_elapsed = 0.0
	_tts_estimate = text.length() * TTS_SEC_PER_CHAR / maxf(0.5, float(GameSettings.get_value("voice", "rate")))


func _tick_tts(delta: float) -> void:
	if _tts_elapsed < 0.0:
		return
	_tts_elapsed += delta
	if not tts_sim.is_empty():
		_sim_left -= delta
	if _tts_elapsed >= TTS_START_GRACE and not _tts_speaking():
		_tts_elapsed = -1.0


func _tts_speaking() -> bool:
	if not tts_sim.is_empty():
		return _tts_elapsed >= 0.0 and _sim_left > 0.0
	return DisplayServer.tts_is_speaking()


func _tts_stop() -> void:
	tts_log.append({"op": "stop", "left": _sim_left if not tts_sim.is_empty() else -1.0})
	_tts_elapsed = -1.0
	if not tts_sim.is_empty():
		_sim_left = 0.0
		return
	DisplayServer.tts_stop()


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
	_current = {"src": "tts", "text": text, "engine": "os", "started": false}
	for item in last_plan:
		if item.get("engine", "") == "voicevox":
			item["engine"] = "os"
	_elapsed = 0.0


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
