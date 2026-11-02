extends Node
## スマホ表示（UiLayout.is_mobile）のときだけ、どの画面にも効かせる調整。UiLayout が子に持つ。
## 画面ごとに書かなくても、パソコン用に作った画面がスマホの幅で崩れず、指で押せるようにする。
##
## 1. 押せるもの（ボタン・名前札・入力欄・スライダー）の高さを、指で押しやすい大きさ（UiLayout.touch_units()＝実寸44px）以上にする
## 2. 札・ボタンを並べた GridContainer の列の数を、画面の幅に入るだけに減らす（ラベルの入った Grid＝表はそのまま）
## 3. 縦向きで幅に入らない HBoxContainer を縦並びにする。外側から順に（左右の2枚のパネル→上下に）。
##    表の行（幅を決めた列が並ぶ行）とその中はそのまま：横向きをすすめ、縦では画面ごと横にスクロールして見る
## 4. 縦向きで幅に入らない1行の文言は折り返す。幅を決めたパネルは画面の幅まで縮める
## 5. 中身をアンカーで重ねた入れ物（采配のページの置き場など）は、中身の高さを入れ物の高さにして、外側のスクロールで見られるようにする
## 6. 指でなぞってスクロール（一覧の上のボタンから始めても）。長押し＝右クリック（名前札→選手詳細）。
##    ツールチップのあるものはタップ・長押しで説明を出す
## パソコン表示に戻したら、元の大きさ・列の数・並びに戻す。
## tests/mobile_fit_check.gd が縦（390x844）と横（844x390）で全画面を開いて、はみ出し・小さすぎるボタンが無いか調べる。

## 調整しないもの：set_meta("touch_keep", true)（その中も）
const KEEP_META := "touch_keep"
const ORIG_META := "_touch_orig"
const GROUP := "_touch_adapted"
## 横並びを縦に包んだ入れ物（HBox → 入れ物）と、入れ物の印
const WRAP_META := "_touch_wrap"
const WRAPPER_META := "_touch_wrapper"
## これだけ指が動いたらなぞる（論理ピクセル）
const DRAG_START := 12.0
const LONG_PRESS_SEC := 0.5
## 縦向きの文字の最小の大きさ（論理。iPhone の縦で実寸 約12px）
const MIN_FONT := 15
## コントローラーのタブ切り替えの案内（スマホでは出さない）
const PAD_HINTS := ["◀ LB", "RB ▶"]
## 表の見出しの並べ替えボタンとみなす幅（これより広いボタンはタブなど）
const TABLE_CELL_MAX := 80.0
## タップで出す説明の表示時間（秒）
const TAP_TIP_SEC := 2.5
const REFIT_INTERVAL_MSEC := 100

var _dirty := true
var _next_refit_msec := 0
var _was_mobile := false

var _pressing := false
var _press_pos := Vector2.ZERO
var _press_msec := 0
var _press_target: Control
var _dragging := false
## なぞってスクロールする向きのスクロールバー（一覧＝ScrollContainer か Tree の）
var _drag_h: ScrollBar
var _drag_v: ScrollBar
var _long_fired := false
var _synthetic := false
var _tip_until_msec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	get_viewport().size_changed.connect(mark_dirty)
	UiLayout.layout_changed.connect(func(_p: bool, _m: bool) -> void:
		restore_all()
		mark_dirty())


func mark_dirty() -> void:
	_dirty = true


func _on_node_added(node: Node) -> void:
	if node is Control:
		_dirty = true


func _process(_delta: float) -> void:
	var mobile := UiLayout.is_mobile
	if not mobile:
		if _was_mobile:
			restore_all()
		_was_mobile = false
		_pressing = false
		return
	_was_mobile = true
	if _pressing and not _dragging and not _long_fired \
			and Time.get_ticks_msec() - _press_msec >= int(LONG_PRESS_SEC * 1000.0):
		_on_long_press()
	if _tip_until_msec > 0 and Time.get_ticks_msec() > _tip_until_msec:
		_tip_until_msec = 0
		UiInput.hide_tip()
	# 調べ直しは 0.1秒に1回まで（日程表の早送りなどで画面が毎フレーム作り直されるとき、スマホで重くならないように）
	if _dirty and Time.get_ticks_msec() >= _next_refit_msec:
		_dirty = false
		_next_refit_msec = Time.get_ticks_msec() + REFIT_INTERVAL_MSEC
		refit()


## 今の画面すべてを調べ直す（ハブがサブ画面を開いたときにも呼ぶ。表示を切り替えただけでは node_added が来ないので）
func refit() -> void:
	if not UiLayout.is_mobile:
		return
	var t := UiLayout.touch_units()
	var view_w := get_viewport().get_visible_rect().size.x
	for child in get_tree().root.get_children():
		_walk(child, t, view_w, false)


# --- 大きさ・並び ---------------------------------------------------------------------------

func _walk(node: Node, t: float, view_w: float, in_table: bool) -> void:
	if node is Window:
		return
	if node.has_meta(KEEP_META):
		return
	if node is Control:
		var c := node as Control
		if not in_table and _is_table_row(c):
			in_table = true
		_fit_touch(c, t, in_table)
		if not in_table:
			_fit_font(c)
			_fit_width(c, view_w)
		if c is ScrollContainer and _scrolls_sideways(c as ScrollContainer):
			in_table = true  # 横にスクロールする一覧の中は幅を詰めない
	for child in node.get_children():
		_walk(child, t, view_w, in_table)


func _orig(c: Control) -> Dictionary:
	if not c.has_meta(ORIG_META):
		c.set_meta(ORIG_META, {})
		c.add_to_group(GROUP)
	return c.get_meta(ORIG_META)


## 1. 押せるもの：高さ（と、表の中でなければ幅）を指の大きさ以上に
func _fit_touch(c: Control, t: float, in_table: bool) -> void:
	if c is TabContainer:
		var bar := (c as TabContainer).get_tab_bar()
		var ob := _orig(c)
		if not ob.has("tab_min"):
			ob["tab_min"] = bar.custom_minimum_size
		bar.custom_minimum_size.y = maxf((ob["tab_min"] as Vector2).y, t)
		return
	if not (c is BaseButton or c is LineEdit or c is Slider):
		return
	if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return
	var o := _orig(c)
	# 画面のコードが後から大きさを変えたら、それを元の大きさとして覚え直す
	if not o.has("min") or c.custom_minimum_size != o.get("applied", Vector2(-1, -1)):
		o["min"] = c.custom_minimum_size
	var base: Vector2 = o["min"]
	var want := Vector2(base.x, maxf(base.y, t))
	# 幅：表の中は列の幅をそろえたいので、細すぎる（並べ替えの ▲▼ など）ものだけ広げる
	want.x = maxf(base.x, t * (0.6 if in_table else 0.8))
	if c is Slider:
		want.x = base.x
	o["applied"] = want
	if c.custom_minimum_size != want:
		c.custom_minimum_size = want


## 縦向き：小さな文字（表の中は除く）を MIN_FONT まで大きくする（見出しの label_settings は共有なので触らない）
func _fit_font(c: Control) -> void:
	if not UiLayout.is_portrait or not (c is Label or c is Button):
		return
	if c is Label and (c as Label).label_settings != null:
		return
	var o := _orig(c)
	if o.has("font"):
		return
	var fs := c.get_theme_font_size("font_size")
	if fs <= 0 or fs >= MIN_FONT:
		return
	o["font"] = fs if c.has_theme_font_size_override("font_size") else -1
	c.add_theme_font_size_override("font_size", MIN_FONT)


## 2〜5. 幅に入らないものを詰める
func _fit_width(c: Control, view_w: float) -> void:
	if c is GridContainer:
		_fit_grid(c as GridContainer, view_w)
	elif c is HBoxContainer and UiLayout.is_portrait:
		_fit_hbox(c as HBoxContainer, view_w)
	elif c is Label and UiLayout.is_portrait:
		_fit_label(c as Label, view_w)
	elif c is Button and UiLayout.is_portrait:
		_fit_button(c as Button, view_w)
	if c.get_class() == "Control" and c.get_child_count() > 0:
		_fit_stack(c)
	if c is ScrollContainer or c is Tree:
		_fit_inner_scroll(c)
	if c is Label and (c as Label).text in PAD_HINTS and c.visible:
		_orig(c)["pad_hint"] = true
		c.visible = false
	if UiLayout.is_portrait and c.custom_minimum_size.x > 0.0 and not (c is BaseButton):
		var avail := _avail(c, view_w)
		if c.custom_minimum_size.x > avail + 1.0:
			var o := _orig(c)
			if not o.has("min_w"):
				o["min_w"] = c.custom_minimum_size.x
			c.custom_minimum_size.x = maxf(avail, 40.0)


func _fit_grid(g: GridContainer, view_w: float) -> void:
	if g.has_meta(WRAPPER_META):
		return  # 横並びを折り返した入れ物（列の数は _fit_hbox が決める）
	var cell := 0.0
	var count := 0
	for child in g.get_children():
		if not (child is Control) or not (child as Control).visible:
			continue
		if child is Label or child is RichTextLabel:
			return  # 表（見出し・値のラベルが並ぶ）は列を変えない
		cell = maxf(cell, (child as Control).get_combined_minimum_size().x)
		count += 1
	if count == 0 or cell <= 0.0:
		return
	var o := _orig(g)
	if not o.has("columns"):
		o["columns"] = g.columns
	var orig_cols: int = o["columns"]
	var sep := float(g.get_theme_constant("h_separation"))
	var avail := _avail(g, view_w)
	var cols := clampi(int(floor((avail + sep) / (cell + sep))), 1, orig_cols)
	if g.columns != cols:
		g.columns = cols


## 幅に入らない横並び：中身を、幅に入るだけの列の数の GridContainer（HBox のただ1つの子）へ移して折り返す
## （HBoxContainer は向きを変えられないので）。左右に並べた大きなパネルは1列＝縦並び、ボタンの列は2〜3列ずつになる。
## 画面のコードが後から HBox へ足した子も入れ物へ移す。中身を消して作り直したら、入れ物も消えて次の調べ直しでまた包む
func _fit_hbox(h: HBoxContainer, view_w: float) -> void:
	var avail := _avail(h, view_w)
	if h.has_meta(WRAP_META):
		var wrapper: Variant = h.get_meta(WRAP_META)
		if is_instance_valid(wrapper) and (wrapper as Node).get_parent() == h:
			for child in h.get_children():
				if child != wrapper:
					child.reparent(wrapper as Node, false)
			_flow_columns(wrapper as GridContainer, avail)
			return
		h.remove_meta(WRAP_META)
	if h.get_child_count() == 0:
		return
	if _shrunk_width(h) <= avail + 1.0 and not _tiles_prefer_stack(h, avail):
		return
	var grid := GridContainer.new()
	grid.set_meta(WRAPPER_META, true)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sep := h.get_theme_constant("separation")
	grid.add_theme_constant_override("h_separation", sep)
	grid.add_theme_constant_override("v_separation", maxi(sep, 4))
	var children := h.get_children()
	h.add_child(grid)
	# 持ち主（シーンの %名前 で探せるように）を同じにしてから移す
	if h.owner != null:
		grid.owner = h.owner
	for child in children:
		child.reparent(grid, false)
	h.set_meta(WRAP_META, grid)
	_orig(h)["wrapped"] = true
	_flow_columns(grid, avail)


## HBox の最小の幅。札を並べた Grid は1列まで減らせるので、札1枚の幅で数える
## （采配の一覧の「1軍」の見出しと6列の札：札を2〜3列にすれば横に並んだまま入る）
static func _shrunk_width(h: HBoxContainer) -> float:
	var total := 0.0
	var n := 0
	for child in h.get_children():
		if not (child is Control) or not (child as Control).visible:
			continue
		n += 1
		var c := child as Control
		var w := c.get_combined_minimum_size().x
		if c is GridContainer and not c.has_meta(WRAPPER_META):
			var cell := 0.0
			var tiles := true
			for t in c.get_children():
				if t is Label or t is RichTextLabel:
					tiles = false
					break
				if t is Control and (t as Control).visible:
					cell = maxf(cell, (t as Control).get_combined_minimum_size().x)
			if tiles and cell > 0.0:
				w = maxf(cell, c.custom_minimum_size.x)
		total += w
	return total + float(h.get_theme_constant("separation")) * maxi(n - 1, 0)


## 札を並べた Grid と見出しが横に並ぶ行で、並べたままだと札が3列より少なく、縦に積めば列が増えるなら積む
## （采配の一覧：「1軍」の見出しを上に、札を3列に）
static func _tiles_prefer_stack(h: HBoxContainer, avail: float) -> bool:
	var others := 0.0
	var n := 0
	var cell := 0.0
	for child in h.get_children():
		if not (child is Control) or not (child as Control).visible:
			continue
		n += 1
		var c := child as Control
		if c is GridContainer and cell <= 0.0:
			for t in c.get_children():
				if t is Label or t is RichTextLabel:
					cell = -1.0
					break
				if t is Control and (t as Control).visible:
					cell = maxf(cell, (t as Control).get_combined_minimum_size().x)
			if cell > 0.0:
				continue
		others += c.get_combined_minimum_size().x
	if cell <= 0.0 or n < 2:
		return false
	var sep := float(h.get_theme_constant("separation"))
	var side := int(floor((avail - others - sep * (n - 1) + 6.0) / (cell + 6.0)))
	var stacked := int(floor((avail + 6.0) / (cell + 6.0)))
	return side < 3 and stacked > side


## 折り返しの列の数：各列の幅（その列のいちばん広いもの）の合計が avail に入る最大の数
static func _flow_columns(grid: GridContainer, avail: float) -> void:
	var widths: Array[float] = []
	for child in grid.get_children():
		if child is Control and (child as Control).visible:
			# 札を並べた Grid は1行を使う（列を増やせるように）
			var tiles := child is GridContainer and not child.has_meta(WRAPPER_META) 					and not (child as Control).get_children().any(func(t: Node) -> bool: return t is Label)
			widths.append(avail if tiles else (child as Control).get_combined_minimum_size().x)
	if widths.is_empty():
		return
	var sep := float(grid.get_theme_constant("h_separation"))
	var cols := widths.size()
	while cols > 1:
		var col_w: Array[float] = []
		col_w.resize(cols)
		col_w.fill(0.0)
		for i in widths.size():
			col_w[i % cols] = maxf(col_w[i % cols], widths[i])
		var total := sep * (cols - 1)
		for w in col_w:
			total += w
		if total <= avail + 1.0:
			break
		cols -= 1
	if grid.columns != cols:
		grid.columns = cols


func _fit_label(l: Label, view_w: float) -> void:
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF or l.clip_text or l.text.is_empty():
		return
	var avail := _avail(l, view_w)
	if l.get_combined_minimum_size().x <= avail + 1.0:
		return
	var o := _orig(l)
	o["autowrap"] = l.autowrap_mode
	o["label_min_w"] = l.custom_minimum_size.x
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = maxf(avail, 40.0)


## 幅に入らないボタン：文字を「…」で省き、幅を画面の幅までにする（_fit_touch の覚えた大きさは元のまま）
func _fit_button(b: Button, view_w: float) -> void:
	if b.text.is_empty():
		return
	# 1つで行の幅より広いときだけ（横に並んだ兄弟の分は引かない。並びは _fit_hbox が折り返す）
	var parent := b.get_parent() as Control
	var row := parent is HBoxContainer or (parent != null and parent.has_meta(WRAPPER_META))
	var avail := _avail(parent, view_w) - _inner_pad(parent) if row else _avail(b, view_w)
	if b.get_combined_minimum_size().x <= avail + 1.0:
		return
	var o := _orig(b)
	if not o.has("clip"):
		o["clip"] = [b.clip_text, b.text_overrun_behavior]
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var want := Vector2(minf(b.custom_minimum_size.x, maxf(avail, 40.0)), b.custom_minimum_size.y)
	if o.has("applied"):
		o["applied"] = want
	b.custom_minimum_size = want


## 縦向き：一覧の中の一覧（外側も縦にスクロールする）は中身の高さまで伸ばして、画面ごと1つのスクロールで見る
## （左右に並んでいた一覧を縦に並べると、高さが0近くに潰れて中身が見えなくなるので）。Tree は画面の高さの6割
func _fit_inner_scroll(c: Control) -> void:
	if not UiLayout.is_portrait or c.has_meta("fit_guard"):
		return
	var s := c as ScrollContainer
	if s != null and (s.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED or s.get_child_count() == 0):
		return
	if not _has_vertical_scroll_above(c):
		return
	var o := _orig(c)
	if not o.has("inner_h"):
		o["inner_h"] = c.custom_minimum_size.y
		if s != null and s.get_child(0) is Control:
			(s.get_child(0) as Control).minimum_size_changed.connect(_update_inner.bind(c))
	_update_inner(c)


func _update_inner(c: Control) -> void:
	if not is_instance_valid(c) or not c.has_meta(ORIG_META) or not UiLayout.is_portrait:
		return
	var o: Dictionary = c.get_meta(ORIG_META)
	if not o.has("inner_h"):
		return
	var h: float = o["inner_h"]
	if c is ScrollContainer:
		var child := c.get_child(0) as Control
		if child != null:
			h = maxf(h, child.get_combined_minimum_size().y)
	else:
		h = maxf(h, get_viewport().get_visible_rect().size.y * 0.6)
	if not is_equal_approx(c.custom_minimum_size.y, h):
		c.custom_minimum_size.y = h


static func _has_vertical_scroll_above(c: Node) -> bool:
	var p := c.get_parent()
	while p != null:
		var s := p as ScrollContainer
		if s != null and s.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			return true
		p = p.get_parent()
	return false


## アンカーで重ねた中身の高さを入れ物に写す（中身が縦に伸びたら外側のスクロールで見られる）
func _fit_stack(c: Control) -> void:
	var o := _orig(c)
	if o.has("stack"):
		return
	var anchored := false
	for child in c.get_children():
		if child is Control and is_equal_approx((child as Control).anchor_bottom, 1.0) \
				and is_zero_approx((child as Control).anchor_top):
			anchored = true
			if not (child as Control).minimum_size_changed.is_connected(_update_stack.bind(c)):
				(child as Control).minimum_size_changed.connect(_update_stack.bind(c))
				(child as Control).visibility_changed.connect(_update_stack.bind(c))
	if not anchored:
		return
	o["stack"] = c.custom_minimum_size.y
	_update_stack(c)


func _update_stack(c: Control) -> void:
	if not is_instance_valid(c) or not c.has_meta(ORIG_META):
		return
	var o: Dictionary = c.get_meta(ORIG_META)
	if not o.has("stack"):
		return
	var h: float = o["stack"]
	if UiLayout.is_mobile:
		for child in c.get_children():
			if child is Control and (child as Control).visible \
					and is_equal_approx((child as Control).anchor_bottom, 1.0):
				var cc := child as Control
				h = maxf(h, cc.get_combined_minimum_size().y + cc.offset_top - cc.offset_bottom)
	if not is_equal_approx(c.custom_minimum_size.y, h):
		c.custom_minimum_size.y = h


## 表の行：幅を決めた列（ラベル・見出しのボタン）が4つ以上並ぶ HBox
## 表の行：幅を決めたラベル（値の欄）か細い見出しのボタン（並べ替え）が4つ以上・半分以上並ぶ HBox。
## 幅を決めた大きめのボタンが並ぶだけ（タブの列など）は表ではない（折り返してよい）
static func _is_table_row(c: Control) -> bool:
	if not (c is HBoxContainer):
		return false
	var cols := 0
	var cells := 0
	for child in c.get_children():
		if child is Control and (child as Control).visible:
			cols += 1
			var w := (child as Control).custom_minimum_size.x
			if w > 0.0 and (child is Label or (child is BaseButton and w <= TABLE_CELL_MAX)):
				cells += 1
	return cells >= 4 and cells * 2 >= cols


## 横にスクロールする一覧（画面のルートの包み＝fit_guard は除く）
static func _scrolls_sideways(s: ScrollContainer) -> bool:
	if s.has_meta("fit_guard"):
		return false
	return s.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED


## c が使える最大の幅（画面の幅から、外側の余白・左右に並ぶ兄弟の幅を引いたもの）。位置ではなく最小の大きさから求める
func _avail(c: Control, view_w: float) -> float:
	var chain: Array[Control] = []
	var node: Node = c
	while node != null and node is Control:
		chain.push_front(node as Control)
		if (node as Control).top_level:
			break
		node = node.get_parent()
	var w := view_w
	for i in chain.size():
		var a := chain[i]
		# 自分のアンカー・余白（親が入れ物でないとき）
		if i == 0 or not (chain[i - 1] is Container):
			if is_zero_approx(a.anchor_left) and is_equal_approx(a.anchor_right, 1.0):
				w -= a.offset_left - a.offset_right
			elif is_equal_approx(a.anchor_left, a.anchor_right):
				w = maxf(w - maxf(a.position.x, 0.0), 0.0) if i > 0 else w
		if i == chain.size() - 1:
			break
		var child := chain[i + 1]
		w -= _inner_pad(a)
		if a is BoxContainer and not (a as BoxContainer).vertical:
			var sep := float(a.get_theme_constant("separation"))
			for sib in a.get_children():
				if sib != child and sib is Control and (sib as Control).visible and not (sib as Control).top_level:
					w -= (sib as Control).get_combined_minimum_size().x + sep
		elif a is GridContainer:
			# ほかの列（その列でいちばん広いもの）の幅と、列の間を引く
			var cols := maxi((a as GridContainer).columns, 1)
			var shown: Array[Control] = []
			for sib in a.get_children():
				if sib is Control and (sib as Control).visible:
					shown.append(sib as Control)
			var mine := shown.find(child) % cols if shown.has(child) else 0
			var col_w: Array[float] = []
			col_w.resize(cols)
			col_w.fill(0.0)
			for k in shown.size():
				if k % cols != mine:
					col_w[k % cols] = maxf(col_w[k % cols], shown[k].get_combined_minimum_size().x)
			for cw in col_w:
				w -= cw
			w -= float(a.get_theme_constant("h_separation")) * (cols - 1)
		elif a is ScrollContainer:
			if _scrolls_sideways(a as ScrollContainer):
				return INF
			# 縦のスクロールバーなどの分（最小の幅の差。出ているスクロールバーの幅は少なくとも引く）
			var sc := a as ScrollContainer
			var over := sc.get_combined_minimum_size().x - child.get_combined_minimum_size().x
			if sc.get_v_scroll_bar().visible:
				over = maxf(over, sc.get_v_scroll_bar().size.x)
			w -= maxf(over, 0.0)
	return w


## 入れ物の内側の余白（左右の合計）
static func _inner_pad(a: Control) -> float:
	if a is MarginContainer:
		return float(a.get_theme_constant("margin_left") + a.get_theme_constant("margin_right"))
	var style: StyleBox = null
	if a is PanelContainer or a is ScrollContainer:
		style = a.get_theme_stylebox("panel")
	elif a is Button:
		style = a.get_theme_stylebox("normal")
	if style != null:
		return style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT)
	return 0.0


## パソコン表示（または向きが変わる前）に戻す
func restore_all() -> void:
	for node in get_tree().get_nodes_in_group(GROUP):
		var c := node as Control
		if c == null or not c.has_meta(ORIG_META):
			continue
		var o: Dictionary = c.get_meta(ORIG_META)
		if o.has("min"):
			c.custom_minimum_size = o["min"]
		if o.has("min_w"):
			c.custom_minimum_size.x = o["min_w"]
		if o.has("columns"):
			(c as GridContainer).columns = o["columns"]
		if o.has("wrapped") and c.has_meta(WRAP_META):
			var wrapper: Variant = c.get_meta(WRAP_META)
			if is_instance_valid(wrapper) and (wrapper as Node).get_parent() == c:
				var at := (wrapper as Node).get_index()
				for child in (wrapper as Node).get_children():
					child.reparent(c, false)
					c.move_child(child, at)
					at += 1
				(wrapper as Node).queue_free()
				c.remove_child(wrapper as Node)
			c.remove_meta(WRAP_META)
		if o.has("autowrap"):
			if c is Label:
				(c as Label).autowrap_mode = o["autowrap"]
				c.custom_minimum_size.x = o.get("label_min_w", 0.0)
			elif c is Button:
				(c as Button).autowrap_mode = o["autowrap"]
		if o.has("stack"):
			c.custom_minimum_size.y = o["stack"]
		if o.has("font"):
			if int(o["font"]) < 0:
				c.remove_theme_font_size_override("font_size")
			else:
				c.add_theme_font_size_override("font_size", int(o["font"]))
		if o.has("clip"):
			(c as Button).clip_text = o["clip"][0]
			(c as Button).text_overrun_behavior = o["clip"][1]
		if o.has("inner_h"):
			c.custom_minimum_size.y = o["inner_h"]
		if o.has("pad_hint"):
			c.visible = true
		if o.has("tab_min"):
			(c as TabContainer).get_tab_bar().custom_minimum_size = o["tab_min"]
		c.remove_meta(ORIG_META)
		c.remove_from_group(GROUP)


# --- 指の操作 -----------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _synthetic or not UiLayout.is_mobile:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_pressing = true
			_dragging = false
			_long_fired = false
			_drag_h = null
			_drag_v = null
			_press_pos = mb.position
			_press_msec = Time.get_ticks_msec()
			_press_target = control_at(mb.position)
		else:
			var handled := _dragging or _long_fired
			var was_tap := _pressing and not handled
			_pressing = false
			_dragging = false
			if handled:
				get_viewport().set_input_as_handled()
			elif was_tap:
				_show_tip_at.call_deferred(mb.position)
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _pressing and not _long_fired:
		if not _dragging:
			var moved := mm.position - _press_pos
			if moved.length() < DRAG_START:
				return
			var bars := _scroll_bars_for(_press_target, absf(moved.x) > absf(moved.y))
			if bars.is_empty():
				_pressing = false  # なぞってもスクロールする一覧が無い（ふつうのマウスの動きとして扱う）
				return
			_drag_h = bars[0]
			_drag_v = bars[1]
			_dragging = true
			_cancel_press()
		if _drag_h != null and is_instance_valid(_drag_h):
			_drag_h.value -= mm.relative.x
		if _drag_v != null and is_instance_valid(_drag_v):
			_drag_v.value -= mm.relative.y
		get_viewport().set_input_as_handled()


## 押したボタンを押していないことにする（画面の外で離したことにする）
func _cancel_press() -> void:
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(-10000, -10000)
	up.global_position = up.position
	_push(up)


func _on_long_press() -> void:
	_long_fired = true
	_cancel_press()
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_RIGHT
		e.pressed = pressed
		e.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed else 0
		e.position = _press_pos
		e.global_position = _press_pos
		_push(e)
	_show_tip_at(_press_pos)


func _push(e: InputEvent) -> void:
	_synthetic = true
	get_viewport().push_input(e, true)
	_synthetic = false


## 指の下のもの（またはその親）にツールチップがあれば、しばらく出す
func _show_tip_at(pos: Vector2) -> void:
	var c := control_at(pos)
	while c != null:
		var text := c.get_tooltip(c.get_global_transform().affine_inverse() * pos)
		if not text.is_empty():
			UiInput.show_tip_for(c, text)
			_tip_until_msec = Time.get_ticks_msec() + int(TAP_TIP_SEC * 1000.0)
			return
		var parent := c.get_parent()
		c = parent as Control if parent is Control else null


## c から上へたどって、その向きにスクロールできる一覧（ScrollContainer・Tree）の [横, 縦] のスクロールバー。無ければ []
static func _scroll_bars_for(c: Control, sideways: bool) -> Array:
	var node: Node = c
	var fallback: Array = []
	while node != null:
		var bars: Array = []
		if node is ScrollContainer and (node as ScrollContainer).is_visible_in_tree():
			var s := node as ScrollContainer
			bars = [s.get_h_scroll_bar() if s.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED else null,
				s.get_v_scroll_bar() if s.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED else null]
		elif node is Tree and (node as Tree).is_visible_in_tree():
			bars = [null, null]
			for child in node.get_children(true):
				if child is HScrollBar:
					bars[0] = child
				elif child is VScrollBar:
					bars[1] = child
		if not bars.is_empty():
			var can_h := bars[0] != null and (bars[0] as ScrollBar).max_value > (bars[0] as ScrollBar).page + 1.0
			var can_v := bars[1] != null and (bars[1] as ScrollBar).max_value > (bars[1] as ScrollBar).page + 1.0
			if not can_h:
				bars[0] = null
			if not can_v:
				bars[1] = null
			if (sideways and can_h) or (not sideways and can_v):
				return bars
			if fallback.is_empty() and (can_h or can_v):
				fallback = bars
		node = node.get_parent()
	return fallback


## 画面のその位置でいちばん上にある、マウスを受け取るもの（上の層・後ろに足したものほど上）
func control_at(pos: Vector2) -> Control:
	var layers: Array = []
	var base: Array[Node] = []
	for child in get_tree().root.get_children():
		if child is CanvasLayer:
			layers.append(child)
		else:
			base.append(child)
		_collect_layers(child, layers)
	layers.sort_custom(func(a: CanvasLayer, b: CanvasLayer) -> bool: return a.layer > b.layer)
	for layer: CanvasLayer in layers:
		if not layer.visible:
			continue
		var hit := _hit_children(layer, pos, Rect2(-1e9, -1e9, 2e9, 2e9))
		if hit != null:
			return hit
	for i in range(base.size() - 1, -1, -1):
		var hit := _hit(base[i], pos, Rect2(-1e9, -1e9, 2e9, 2e9))
		if hit != null:
			return hit
	return null


static func _collect_layers(node: Node, layers: Array) -> void:
	for child in node.get_children():
		if child is CanvasLayer:
			layers.append(child)
		if not (child is Window):
			_collect_layers(child, layers)


static func _hit_children(node: Node, pos: Vector2, clip: Rect2) -> Control:
	for i in range(node.get_child_count() - 1, -1, -1):
		var hit := _hit(node.get_child(i), pos, clip)
		if hit != null:
			return hit
	return null


static func _hit(node: Node, pos: Vector2, clip: Rect2) -> Control:
	if node is Window or node is CanvasLayer:
		return null  # 別の層は control_at が順に調べる
	if node is CanvasItem and not (node as CanvasItem).visible:
		return null
	var c := node as Control
	if c != null:
		var r := c.get_global_rect()
		if c.top_level:
			clip = Rect2(-1e9, -1e9, 2e9, 2e9)
		if c.clip_contents:
			clip = clip.intersection(r)
			if not clip.has_point(pos):
				return null
	var hit := _hit_children(node, pos, clip)
	if hit != null:
		return hit
	if c != null and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and clip.has_point(pos) \
			and c.get_global_rect().has_point(pos):
		return c
	return null
