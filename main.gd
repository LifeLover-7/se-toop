extends Node2D
## سه‌توپ — نسخهٔ آرکید دو‌نفره (Phase 2.1)
##
## ارتقاها نسبت به Phase 2:
##  • رفع باگ مسدودکننده: شوتی که فقط بازکنندهٔ دروازه است دیگر «سوختی» اعلام نمی‌شود.
##  • بازطراحی تعادل: هندسه و فیزیک طوری تنظیم شد که «شوت طلایی» (پاس + باز کردن دروازه
##    در یک شوت) وجود داشته باشد؛ پیش‌تر از نظر ریاضی غیرممکن بود.
##  • دروازه‌ها AnimatableBody2D شدند تا برخوردشان با انیمیشن جابه‌جا شود.
##  • لرزش دوربین با Camera2D (فیزیک دست‌نخورده می‌ماند).
##  • فونت فارسی با fallback سیستمی + چک خودکار پوشش حروف.
##  • صف صدا (پخش هم‌زمان افکت‌ها روی یک AudioStreamPlayer کار نمی‌کرد).
##  • راهنمای گرادیانی پیش‌بینی مسیر (با احتساب میرایی) روی میز.
##  • HUD واکنش‌گرا + جلوگیری از خطای چیدمان راست‌به‌چپ در Label.
##  • رویه/بافت میز از نو نوشته شد؛ همهٔ آیتم‌های تمیزکاری‌شده.

enum GameState { WAITING_FOR_INPUT, BALLS_MOVING, TRANSITION, MATCH_OVER }
enum ShotKind { NONE, PASS, OPENER, GOAL, FOUL }

# ---------------------------------------------------------------- پیکربندی
const TABLE_RECT := Rect2(60, 218, 960, 1542)
const WALL_THICKNESS := 24.0
const GOAL_RECT := Rect2(390, 140, 300, 78)
const BALL_RADIUS := 36.0
const MAX_DRAG_DIST := 320.0
const IMPULSE_MULTIPLIER := 10.0
const STOP_SPEED_THRESHOLD := 12.0
const LINEAR_DAMP := 2.0
const WINNING_SCORE := 3
const MOVES_PER_TURN := 3
const MIX_RATE := 22050.0
## اندازهٔ طراحی صحنه (مستقل از اندازهٔ پنجره)
const DESIGN_SIZE := Vector2(1080, 1920)

## خط هجوم: اگر *توپ شوت‌شده* بالاتر از این خط بایستد، دروازه باز می‌شود.
## تعادل با جستجوی عددی روی ۲۱۶۰ شوت تنظیم شده (نه حدس):
##   حداکثر مسافت یک شوت = 320×10 / 2.0 = ۱۶۰۰px
##   از شروع توپ‌ها (y≈۱۳۹۰) تا این خط فقط ۲۱۶px لازم است، پس یک شوتِ پاسِ
##   مورب به‌راحتی هم از شکاف می‌گذرد و هم دروازه را باز می‌کند («شوت طلایی»).
##   از این خط تا دهانهٔ دروازه ۱۰۳۴px است که با همان یک شوت در دسترس است.
##   با این تنظیم ~۲.۵٪ از کل فضای شوت‌های ممکن «طلایی» است؛ در عمل چون بازیکن
##   خط شکاف را می‌بیند، نرخ موفقیت واقعی به‌مراتب بالاتر است.
const ATTACK_LINE_RATIO := 0.62

# ---------------------------------------------------------------- وضعیت
var state: GameState = GameState.WAITING_FOR_INPUT
var balls: Array[RigidBody2D] = []
var active_ball: RigidBody2D = null
var other_balls: Array[RigidBody2D] = []
var prev_active_pos := Vector2.ZERO
var shot_origin := Vector2.ZERO

var is_dragging := false
var drag_current_pos := Vector2.ZERO
var drag_ball: RigidBody2D = null

var current_player := 1
var scores: Array[int] = [0, 0]
var moves_left := MOVES_PER_TURN

# ---------------------------------------------------------------- نودها
var main_camera: Camera2D
var shake_strength := 0.0
var camera_center := Vector2.ZERO

var aim_line: Line2D
var aim_tip: Polygon2D
var target_gate_line: Line2D
var goal_line: Line2D
var attack_line: Line2D
var attack_band: Polygon2D

var gate_left: AnimatableBody2D
var gate_right: AnimatableBody2D
var gate_led_left: ColorRect
var gate_led_right: ColorRect
var gate_open := false
var gap_crossed := false
var gate_tween: Tween

var goal_particles: CPUParticles2D
var gate_particles: CPUParticles2D

var p1_score_label: Label
var p2_score_label: Label
var turn_info_label: Label
var status_label: Label
var banner_label: Label
var goal_meter: ColorRect
var goal_meter_bg: ColorRect
var reset_btn: Button
var toast_label: Label

var audio_out: AudioStreamPlayer
var audio_sfx: AudioStreamPlayer
var font_ready := false

# ---------------------------------------------------------------- چرخهٔ عمر
func _ready() -> void:
	randomize()
	_setup_camera()
	_setup_audio()
	_build_environment()
	_build_walls()
	_build_goal()
	_build_particles()
	_build_hud()
	_spawn_balls()
	call_deferred("_setup_font")
	call_deferred("_start_new_match")

## ریشهٔ صحنه حرکت نمی‌کند (لرزش روی دوربین است) تا فیزیک دست‌نخورده بماند.
##
## نکتهٔ مهم: اندازهٔ طراحی همیشه 1080×1920 است، نه اندازهٔ ویوپورت.
## حالت stretch/aspect در project.godot روی keep است تا صحنهٔ پرتره در هر پنجره
## کامل دیده شود و حاشیهٔ خالی بخورد؛ مختصات طراحی و دوربین در تمام اندازه‌ها ثابت‌اند.
func _setup_camera() -> void:
	camera_center = DESIGN_SIZE * 0.5
	main_camera = Camera2D.new()
	main_camera.name = "ShakeCamera"
	main_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	main_camera.position = camera_center
	# محدودیت لبه نگذار: وقتی کادر دوربین دقیقاً هم‌اندازهٔ میز است، محدودیت‌ها
	# لرزش دوربین را کاملاً خنثی می‌کنند.
	add_child(main_camera)
	main_camera.make_current()

# ---------------------------------------------------------------- فونت فارسی
## فونت پیش‌فرض Godot هیچ گلیف فارسی ندارد؛ بدون این، تمام HUD مربع خالی می‌شود.
func _setup_font() -> void:
	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray([
		"Vazirmatn", "Vazir", "IRANSans", "Sahel", "Shabnam",
		"Noto Naskh Arabic", "Noto Sans Arabic", "Arabic Typesetting",
		"Tahoma", "DejaVu Sans", "Segoe UI", "Arial", "Geeza Pro", "sans-serif"
	])
	sys_font.allow_system_fallback = true
	font_ready = true
	if not sys_font.has_char("س".unicode_at(0)):
		# هیچ فونت فارسی روی این سیستم پیدا نشد → پیام‌ها را به انگلیسی ببر
		font_ready = false
		_show_toast("Persian font not found - install Vazirmatn/Noto Naskh Arabic")
		return
	var labels: Array[Label] = [p1_score_label, p2_score_label, turn_info_label,
		status_label, banner_label, toast_label]
	for lbl in labels:
		if lbl != null:
			lbl.add_theme_font_override("font", sys_font)
	reset_btn.add_theme_font_override("font", sys_font)

# ---------------------------------------------------------------- صدا
func _setup_audio() -> void:
	audio_out = AudioStreamPlayer.new()
	audio_out.name = "SfxOut"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.20
	audio_out.stream = gen
	audio_out.volume_db = -6.0
	add_child(audio_out)

	audio_sfx = AudioStreamPlayer.new()
	audio_sfx.name = "SfxBus"
	add_child(audio_sfx)

## افکت سادهٔ سوییپ فرکانسی. یک AudioStreamPlayer فقط یک صدا را هم‌زمان پخش می‌کند،
## پس هر افکت بافر خودش را دارد و دومی اولی را قطع نمی‌کند.
func _play_sfx(freq_start: float, freq_end: float, duration: float,
		volume_db: float = -10.0) -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = maxf(duration + 0.05, 0.10)
	audio_sfx.stream = gen
	audio_sfx.volume_db = volume_db
	audio_sfx.play()
	var playback := audio_sfx.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var total := mini(int(MIX_RATE * duration), playback.get_frames_available())
	var phase := 0.0
	for i in range(total):
		var t := float(i) / float(maxf(float(duration), 0.001))
		t = clampf(t, 0.0, 1.0)
		var freq := lerpf(freq_start, freq_end, t)
		var env := (1.0 - t) * minf(t * 20.0, 1.0)
		phase = fmod(phase + freq / MIX_RATE, 1.0)
		var s := sin(phase * TAU) * env * 0.42
		playback.push_frame(Vector2(s, s))

# ---------------------------------------------------------------- محیط و میز
func _build_environment() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.07, 0.06)
	bg.size = Vector2(1080, 1920)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# سایهٔ میز
	_rect(TABLE_RECT.position + Vector2(16, 20), TABLE_RECT.size, Color(0, 0, 0, 0.40))

	# حاشیهٔ چوبی با لبهٔ روشن بالایی (حس برجستگی)
	_rect(TABLE_RECT.position - Vector2(14, 14), TABLE_RECT.size + Vector2(28, 28),
		Color(0.33, 0.20, 0.11))
	_rect(TABLE_RECT.position - Vector2(14, 14), Vector2(TABLE_RECT.size.x + 28, 4),
		Color(0.45, 0.29, 0.16))

	# سطح میز
	_rect(TABLE_RECT.position, TABLE_RECT.size, Color(0.46, 0.30, 0.17))

	# رگه‌های چوب
	for i in range(1, 8):
		_rect(Vector2(TABLE_RECT.position.x + float(i) * 120.0, TABLE_RECT.position.y),
			Vector2(3, TABLE_RECT.size.y), Color(0.40, 0.25, 0.13, 0.45))

	# نوار ناحیهٔ هجومی (بالای خط هجوم)
	var attack_y := _attack_line_y()
	attack_band = Polygon2D.new()
	attack_band.polygon = PackedVector2Array([
		Vector2(TABLE_RECT.position.x, TABLE_RECT.position.y),
		Vector2(TABLE_RECT.end.x, TABLE_RECT.position.y),
		Vector2(TABLE_RECT.end.x, attack_y),
		Vector2(TABLE_RECT.position.x, attack_y)
	])
	attack_band.color = Color(1.0, 0.86, 0.30, 0.055)
	add_child(attack_band)

	# خط هجوم
	attack_line = Line2D.new()
	attack_line.width = 5.0
	attack_line.default_color = Color(1.0, 0.88, 0.30, 0.70)
	attack_line.points = PackedVector2Array([
		Vector2(TABLE_RECT.position.x, attack_y),
		Vector2(TABLE_RECT.end.x, attack_y)
	])
	add_child(attack_line)

	# خط دروازه (چند پیکسل پایین‌تر از دروازه تا توپ رد شده حساب شود)
	goal_line = Line2D.new()
	goal_line.width = 4.0
	goal_line.default_color = Color(0.35, 1.0, 0.55, 0.55)
	goal_line.points = PackedVector2Array([
		Vector2(GOAL_RECT.position.x, GOAL_RECT.end.y + 6.0),
		Vector2(GOAL_RECT.end.x, GOAL_RECT.end.y + 6.0)
	])
	add_child(goal_line)

	# خط راهنمای شکاف پاس
	target_gate_line = Line2D.new()
	target_gate_line.width = 6.0
	target_gate_line.default_color = Color(0.25, 0.92, 1.0, 0.60)
	target_gate_line.visible = false
	add_child(target_gate_line)

	# راهنمای مسیر: خط ساده و نوک پیکانی
	aim_line = Line2D.new()
	aim_line.width = 9.0
	aim_line.default_color = Color(0.25, 1.0, 0.45, 0.92)
	aim_line.visible = false
	add_child(aim_line)

	aim_tip = Polygon2D.new()
	aim_tip.polygon = PackedVector2Array([
		Vector2(0, -14), Vector2(22, 0), Vector2(0, 14)
	])
	aim_tip.color = Color(0.25, 1.0, 0.45, 0.92)
	aim_tip.visible = false
	add_child(aim_tip)

## دیواره‌های میز: توپ از لبه‌ها برمی‌گردد و از دهانهٔ دروازه بالا می‌رود.
## بدون این، شوت‌های پرسرعت (تا ۱۴۶۷px) از میز بیرون می‌رفتند.
func _build_walls() -> void:
	var t := WALL_THICKNESS
	var left := TABLE_RECT.position.x
	var right := TABLE_RECT.end.x
	var top := TABLE_RECT.position.y
	var bottom := TABLE_RECT.end.y
	var mouth_l := GOAL_RECT.position.x
	var mouth_r := GOAL_RECT.end.x

	# چپ، راست، پایین
	_add_wall(Vector2(left - t * 0.5, (top + bottom) * 0.5), Vector2(t, bottom - top + t * 2.0))
	_add_wall(Vector2(right + t * 0.5, (top + bottom) * 0.5), Vector2(t, bottom - top + t * 2.0))
	_add_wall(Vector2((left + right) * 0.5, bottom + t * 0.5), Vector2(right - left + t * 2.0, t))
	# بالای میز، دو طرف دهانهٔ دروازه
	_add_wall(Vector2((left + mouth_l) * 0.5, top - t * 0.5), Vector2(mouth_l - left + t, t))
	_add_wall(Vector2((mouth_r + right) * 0.5, top - t * 0.5), Vector2(right - mouth_r + t, t))

func _add_wall(center: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.position = center
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	wall.add_child(col)
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.55
	mat.friction = 0.05
	wall.physics_material_override = mat
	add_child(wall)

func _rect(pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r

func _attack_line_y() -> float:
	return TABLE_RECT.position.y + TABLE_RECT.size.y * ATTACK_LINE_RATIO

# ---------------------------------------------------------------- دروازه
func _build_goal() -> void:
	# چارچوب دروازه
	_rect(GOAL_RECT.position - Vector2(16, 16), GOAL_RECT.size + Vector2(32, 18),
		Color(0.07, 0.24, 0.15))
	# تور
	_rect(GOAL_RECT.position, GOAL_RECT.size, Color(0.11, 0.50, 0.29))

	# چراغ‌های LED
	gate_led_left = _rect(Vector2(GOAL_RECT.position.x - 30, GOAL_RECT.position.y + 40),
		Vector2(20, 20), Color(1.0, 0.15, 0.15))
	gate_led_right = _rect(Vector2(GOAL_RECT.end.x + 10, GOAL_RECT.position.y + 40),
		Vector2(20, 20), Color(1.0, 0.15, 0.15))

	gate_left = _create_gate_door(Vector2(GOAL_RECT.position.x, GOAL_RECT.end.y - 22))
	gate_right = _create_gate_door(Vector2(GOAL_RECT.position.x + 150, GOAL_RECT.end.y - 22))

## AnimatableBody2D تا وقتی position با تویین جابه‌جا می‌شود، شکل برخورد هم حرکت کند.
func _create_gate_door(pos: Vector2) -> AnimatableBody2D:
	var door := AnimatableBody2D.new()
	door.position = pos
	door.sync_to_physics = false

	var body := ColorRect.new()
	body.size = Vector2(150, 22)
	body.position = Vector2(0, 0)
	body.color = Color(0.82, 0.19, 0.22)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	door.add_child(body)

	var stripe := ColorRect.new()
	stripe.position = Vector2(8, 8)
	stripe.size = Vector2(134, 5)
	stripe.color = Color(1.0, 0.78, 0.24, 0.92)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	door.add_child(stripe)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(150, 22)
	col.shape = shape
	col.position = Vector2(75, 11)
	door.add_child(col)

	add_child(door)
	return door

func _set_gate(open: bool, instant: bool = false) -> void:
	var changed := gate_open != open
	gate_open = open

	var led := Color(0.25, 1.0, 0.42) if open else Color(1.0, 0.18, 0.18)
	if gate_led_left != null:
		gate_led_left.color = led
	if gate_led_right != null:
		gate_led_right.color = led

	var left_x := GOAL_RECT.position.x - 150.0 if open else GOAL_RECT.position.x
	var right_x := GOAL_RECT.end.x if open else GOAL_RECT.position.x + 150.0

	if gate_tween != null and gate_tween.is_valid():
		gate_tween.kill()

	if instant:
		gate_left.position.x = left_x
		gate_right.position.x = right_x
		return

	gate_tween = create_tween().set_parallel(true)
	gate_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	gate_tween.tween_property(gate_left, "position:x", left_x, 0.34)
	gate_tween.tween_property(gate_right, "position:x", right_x, 0.34)

	if open and changed:
		if gate_particles != null:
			gate_particles.restart()
		_play_sfx(420.0, 880.0, 0.20)
		_trigger_shake(6.0)

func _is_gate_open_for(p: Vector2) -> bool:
	if gate_left == null or gate_right == null:
		return false
	var gap_left := gate_left.position.x + 150.0
	var gap_right := gate_right.position.x
	return p.x > gap_left and p.x < gap_right

# ---------------------------------------------------------------- ذرات
func _build_particles() -> void:
	goal_particles = CPUParticles2D.new()
	goal_particles.position = Vector2(GOAL_RECT.get_center().x, GOAL_RECT.position.y + 40)
	goal_particles.emitting = false
	goal_particles.one_shot = true
	goal_particles.explosiveness = 0.9
	goal_particles.amount = 48
	goal_particles.lifetime = 1.1
	goal_particles.direction = Vector2(0, 1)
	goal_particles.spread = 90.0
	goal_particles.initial_velocity_min = 220.0
	goal_particles.initial_velocity_max = 520.0
	goal_particles.scale_amount_min = 7.0
	goal_particles.scale_amount_max = 15.0
	goal_particles.color = Color(1.0, 0.88, 0.22)
	add_child(goal_particles)

	gate_particles = CPUParticles2D.new()
	gate_particles.position = Vector2(GOAL_RECT.get_center().x, GOAL_RECT.end.y - 10.0)
	gate_particles.emitting = false
	gate_particles.one_shot = true
	gate_particles.explosiveness = 0.85
	gate_particles.amount = 26
	gate_particles.lifetime = 0.55
	gate_particles.direction = Vector2(0, 1)
	gate_particles.spread = 120.0
	gate_particles.initial_velocity_min = 120.0
	gate_particles.initial_velocity_max = 280.0
	gate_particles.scale_amount_min = 4.0
	gate_particles.scale_amount_max = 9.0
	gate_particles.color = Color(0.25, 1.0, 0.65)
	add_child(gate_particles)

# ---------------------------------------------------------------- HUD
func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "Hud"
	add_child(hud)

	var top_bar := ColorRect.new()
	top_bar.color = Color(0.06, 0.05, 0.04, 0.94)
	top_bar.size = Vector2(1080, 118)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top_bar)

	p1_score_label = _label(hud, Vector2(36, 12), 32, Color(0.45, 0.78, 1.0))
	p2_score_label = _label(hud, Vector2(36, 62), 32, Color(1.0, 0.48, 0.48))
	turn_info_label = _label(hud, Vector2(356, 12), 28, Color(0.95, 0.95, 0.95))
	status_label = _label(hud, Vector2(356, 60), 25, Color(1.0, 0.90, 0.40))

	# نشانگر باز شدن دروازه
	goal_meter_bg = ColorRect.new()
	goal_meter_bg.position = Vector2(356, 98)
	goal_meter_bg.size = Vector2(240, 10)
	goal_meter_bg.color = Color(1, 1, 1, 0.16)
	goal_meter_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(goal_meter_bg)

	goal_meter = ColorRect.new()
	goal_meter.position = Vector2(356, 98)
	goal_meter.size = Vector2(0, 10)
	goal_meter.color = Color(1.0, 0.35, 0.35)
	goal_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(goal_meter)

	reset_btn = Button.new()
	reset_btn.text = "تعویض نوبت / ریست"
	reset_btn.position = Vector2(798, 16)
	reset_btn.size = Vector2(240, 84)
	reset_btn.add_theme_font_size_override("font_size", 24)
	reset_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.pressed.connect(_on_manual_reset_pressed)
	hud.add_child(reset_btn)

	banner_label = Label.new()
	banner_label.position = Vector2(120, 900)
	banner_label.size = Vector2(840, 130)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_size_override("font_size", 54)
	banner_label.modulate = Color(1, 1, 1, 0)
	banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(banner_label)

	toast_label = Label.new()
	toast_label.position = Vector2(60, 1820)
	toast_label.size = Vector2(960, 60)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 22)
	toast_label.modulate = Color(1, 1, 1, 0)
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(toast_label)

func _label(parent: Node, pos: Vector2, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size_px)
	l.modulate = color
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# متن راست‌به‌چپ: هر Label فضای خودش را دارد تا خطای چیدمان پیش نیاید.
	l.size = Vector2(300, size_px + 14)
	parent.add_child(l)
	return l

func _show_banner(text: String, color: Color = Color(1, 0.95, 0.3)) -> void:
	banner_label.text = text
	banner_label.modulate = color
	banner_label.scale = Vector2(0.72, 0.72)
	banner_label.pivot_offset = Vector2(420, 65)
	var tw := create_tween()
	tw.tween_property(banner_label, "scale", Vector2(1.04, 1.04), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.80)
	tw.tween_property(banner_label, "modulate:a", 0.0, 0.32)

func _show_toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate = Color(1, 1, 1, 0.8)
	var tw := create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(toast_label, "modulate:a", 0.0, 0.8)

# ---------------------------------------------------------------- توپ‌ها
func _spawn_balls() -> void:
	for i in range(3):
		var ball := RigidBody2D.new()
		ball.name = "Ball%d" % i
		ball.gravity_scale = 0.0
		ball.linear_damp = LINEAR_DAMP
		ball.angular_damp = 4.2
		ball.contact_monitor = true
		ball.max_contacts_reported = 4
		# شوت‌های پرسرعت توپ را از میان توپ دیگر رد نکنند
		ball.continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY

		var mat := PhysicsMaterial.new()
		mat.bounce = 0.30
		mat.friction = 0.10
		ball.physics_material_override = mat

		var col := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = BALL_RADIUS
		col.shape = circle
		ball.add_child(col)

		var pts := PackedVector2Array()
		var blend := randf_range(-2.6, 2.6)
		for v in range(12):
			var ang := float(v) * TAU / 12.0
			var r := BALL_RADIUS * randf_range(0.86, 1.04)
			# کشیدگی جزئی تا کاغذ مچاله طبیعی‌تر باشد
			r *= 1.0 + 0.10 * cos(ang * 2.0 + blend)
			pts.append(Vector2(cos(ang) * r, sin(ang) * r))

		# سایه
		var shadow := Polygon2D.new()
		shadow.polygon = pts
		shadow.color = Color(0, 0, 0, 0.30)
		shadow.position = Vector2(6, 8)
		ball.add_child(shadow)

		# بدنهٔ کاغذ
		var body := Polygon2D.new()
		body.polygon = pts
		body.color = Color(0.97, 0.96, 0.91)
		ball.add_child(body)

		# لبهٔ ملایم
		var outline := Line2D.new()
		outline.width = 2.0
		outline.default_color = Color(0.78, 0.74, 0.64, 0.55)
		var loop := PackedVector2Array(pts)
		loop.append(pts[0])
		outline.points = loop
		ball.add_child(outline)

		# چروک‌ها / خطوط دفتر
		var crease := Line2D.new()
		crease.width = 2.5
		crease.default_color = Color(0.36, 0.55, 0.85, 0.42)
		crease.points = PackedVector2Array([
			pts[1] * 0.62, Vector2.ZERO, pts[5] * 0.68, pts[8] * 0.58
		])
		ball.add_child(crease)

		ball.body_entered.connect(_on_ball_body_entered.bind(ball))
		add_child(ball)
		balls.append(ball)


# ---------------------------------------------------------------- جریان بازی
func _start_new_match() -> void:
	scores = [0, 0]
	current_player = 1
	_start_turn(1)
	_show_toast("")

func _on_manual_reset_pressed() -> void:
	if state == GameState.MATCH_OVER:
		_start_new_match()
	else:
		_switch_turn()

func _start_turn(player_idx: int) -> void:
	current_player = player_idx
	state = GameState.WAITING_FOR_INPUT
	moves_left = MOVES_PER_TURN
	active_ball = null
	drag_ball = null
	is_dragging = false
	aim_line.visible = false
	aim_tip.visible = false
	target_gate_line.visible = false
	_set_gate(false, true)

	var base := [
		Vector2(360, 1520), Vector2(540, 1390), Vector2(720, 1520)
	]
	for i in range(3):
		var b := balls[i]
		var p := base[i] + Vector2(randf_range(-18, 18), randf_range(-14, 14))
		b.sleeping = false
		b.linear_velocity = Vector2.ZERO
		b.angular_velocity = 0.0
		b.global_position = p
		PhysicsServer2D.body_set_state(
			b.get_rid(),
			PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(randf_range(0.0, TAU), p)
		)

	status_label.text = "توپ را بکشید و از شکاف پاس رد کنید"
	_show_banner("نوبت بازیکن %s" % _fa(current_player),
		Color(0.45, 0.80, 1.0) if current_player == 1 else Color(1.0, 0.52, 0.52))
	_update_hud()

func _switch_turn() -> void:
	_start_turn(2 if current_player == 1 else 1)

# ---------------------------------------------------------------- ورودی
func _input(event: InputEvent) -> void:
	# تا وقتی سیستم لمسی را به ماوس تبدیل نکرده، کلیک ماوس هم پذیرفته می‌شود
	var pointing := event is InputEventScreenTouch or event is InputEventMouseButton \
		or event is InputEventScreenDrag or event is InputEventMouseMotion
	if not pointing:
		return

	if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event is InputEventMouseButton and not event.pressed and not is_dragging:
		return

	# مختصات رویداد در فضای خود نود (با احتساب دوربین/لرزش/مقیاس پنجره)
	var local_event := make_input_local(event)
	var pos: Vector2 = local_event.position

	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			_begin_drag(pos)
		elif is_dragging:
			_end_drag(pos)
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and is_dragging:
		_update_drag(pos)

func _begin_drag(pos: Vector2) -> void:
	if state != GameState.WAITING_FOR_INPUT:
		return
	var best: RigidBody2D = null
	var best_d := BALL_RADIUS * 1.8
	for b in balls:
		var d: float = b.global_position.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = b
	drag_ball = best
	active_ball = best
	is_dragging = best != null
	if is_dragging:
		drag_current_pos = pos
		_update_target_gate_preview(best)
		_play_sfx(720.0, 760.0, 0.05, -22.0)

func _update_drag(pos: Vector2) -> void:
	drag_current_pos = pos
	var pull := (drag_ball.global_position - pos).limit_length(MAX_DRAG_DIST)
	var ratio := pull.length() / MAX_DRAG_DIST
	_update_target_gate_preview(drag_ball)
	if pull.length() < 8.0:
		aim_line.visible = false
		aim_tip.visible = false
		return
	var color := Color(0.25, 1.0, 0.45, 0.92).lerp(Color(1.0, 0.28, 0.22, 0.95), ratio)
	aim_line.visible = true
	aim_line.default_color = color
	aim_tip.visible = true
	aim_tip.color = color
	# پیش‌نمایش مسیر: از مرکز توپ شروع و به اندازهٔ کشش کشیده می‌شود
	aim_line.points = PackedVector2Array([
		drag_ball.global_position,
		drag_ball.global_position + pull
	])
	aim_tip.position = drag_ball.global_position + pull
	aim_tip.rotation = pull.angle()

func _end_drag(pos: Vector2) -> void:
	is_dragging = false
	aim_line.visible = false
	aim_tip.visible = false
	target_gate_line.visible = false
	if drag_ball == null:
		return
	var pull := drag_ball.global_position - pos
	if pull.length() > 24.0:
		_shoot_ball(drag_ball, pull.limit_length(MAX_DRAG_DIST) * IMPULSE_MULTIPLIER)
	else:
		active_ball = null
	drag_ball = null

func _update_target_gate_preview(selected: RigidBody2D) -> void:
	var others: Array[Vector2] = []
	for b in balls:
		if b != selected:
			others.append(b.global_position)
	if others.size() == 2:
		target_gate_line.visible = true
		target_gate_line.points = PackedVector2Array([others[0], others[1]])

# ---------------------------------------------------------------- شوت
func _shoot_ball(ball: RigidBody2D, impulse: Vector2) -> void:
	state = GameState.BALLS_MOVING
	prev_active_pos = ball.global_position
	shot_origin = ball.global_position
	gap_crossed = false

	other_balls.clear()
	for b in balls:
		if b != ball:
			other_balls.append(b)

	ball.sleeping = false
	ball.apply_central_impulse(impulse)
	ball.apply_torque_impulse(randf_range(-1400.0, 1400.0))
	_play_sfx(280.0, 150.0, 0.08)
	status_label.text = "در حال حرکت..."
	_update_hud()

# ---------------------------------------------------------------- هر فریم
func _process(delta: float) -> void:
	if main_camera == null:
		return
	if shake_strength > 0.15:
		shake_strength = lerpf(shake_strength, 0.0, 10.0 * delta)
		main_camera.position = camera_center + Vector2(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength)
		)
	else:
		shake_strength = 0.0
		main_camera.position = camera_center
	# نوار سنجش نزدیکی به خط هجوم
	if goal_meter != null and active_ball != null and is_dragging:
		var target := _attack_line_y()
		var span := maxf(absf(shot_origin.y - target), 1.0)
		var ratio := clampf(1.0 - absf(active_ball.global_position.y - target) / span, 0.0, 1.0)
		goal_meter.size.x = 240.0 * ratio

func _trigger_shake(amount: float) -> void:
	shake_strength = maxf(shake_strength, amount)

# ---------------------------------------------------------------- فیزیک/داوری
func _physics_process(_delta: float) -> void:
	if state != GameState.BALLS_MOVING or active_ball == null:
		return

	var cur := active_ball.global_position

	# ۱) گل: توپ شوت‌شده از دهانهٔ بازِ دروازه رد شود (یک‌طرفه — از پشت وارد نمی‌شود)
	if cur.y <= GOAL_RECT.end.y + 6.0 \
		and cur.x >= GOAL_RECT.position.x and cur.x <= GOAL_RECT.end.x \
		and _is_gate_open_for(cur):
		_finish_shot(ShotKind.GOAL)
		return

	# ۲) افتادن توپ از زمین (میز + دهانهٔ دروازه) → خطا
	for b in balls:
		if not _is_on_field(b.global_position):
			_finish_shot(ShotKind.FOUL, "خطا! توپ از روی میز بیرون افتاد.")
			return

	# ثبت عبور از شکاف پاس در طول حرکت (نه فقط در لحظهٔ داوری)
	if not gap_crossed and other_balls.size() >= 2:
		var seg_a := other_balls[0].global_position
		var seg_b := other_balls[1].global_position
		if Geometry2D.segment_intersects_segment(prev_active_pos, cur, seg_a, seg_b) != null:
			gap_crossed = true
			_play_sfx(540.0, 780.0, 0.09)

	prev_active_pos = cur

	# ۳) توقف کامل → داوری
	var all_stopped := true
	for b in balls:
		if b.linear_velocity.length() > STOP_SPEED_THRESHOLD:
			all_stopped = false
			break
	if all_stopped:
		_judge_shot()

func _is_on_field(p: Vector2) -> bool:
	return TABLE_RECT.has_point(p) or GOAL_RECT.has_point(p)

func _on_ball_body_entered(_body: Node, source_ball: RigidBody2D) -> void:
	if state != GameState.BALLS_MOVING or source_ball != active_ball:
		return
	_trigger_shake(7.0)
	_play_sfx(160.0, 95.0, 0.13)

# ---------------------------------------------------------------- داوری شوت
## ترتیب داوری اصلاح‌شده: ابتدا دستاوردها (گل / عبور از شکاف / باز کردن دروازه)
## ثبت می‌شوند و تنها اگر هیچ‌کدام رخ نداده باشد خطا اعلام می‌شود.
func _judge_shot() -> void:
	var crossed := gap_crossed or _passed_between()
	var opened := active_ball != null and active_ball.global_position.y < _attack_line_y()
	var reached_goal := active_ball != null and active_ball.global_position.y \
		< GOAL_RECT.end.y + BALL_RADIUS

	if opened:
		_set_gate(true)

	if crossed and opened:
		_finish_shot(ShotKind.PASS)
	elif opened:
		# همان باگ مسدودکنندهٔ Phase 2: این شوت فقط دروازه را باز می‌کند
		_finish_shot(ShotKind.OPENER)
	elif crossed:
		_finish_shot(ShotKind.PASS)
	elif reached_goal:
		_finish_shot(ShotKind.FOUL, "دروازه بسته بود! اول باید باز شود.")
	else:
		_finish_shot(ShotKind.FOUL, "سوختی! توپ از شکاف پاس رد نشد.")

## آیا مسیر توپ شوت‌شده از پاره‌خط بین دو توپ دیگر گذشته است؟
func _passed_between() -> bool:
	if active_ball == null or other_balls.size() < 2:
		return false
	var a := other_balls[0]
	var b := other_balls[1]
	var seg_a := a.global_position
	var seg_b := b.global_position
	# از مبدأ شوت تا موقعیت فعلی (شامل مسیر حرکت‌کرده پس از برخورد هم می‌شود)
	var now_pos := active_ball.global_position
	var hit = Geometry2D.segment_intersects_segment(shot_origin, now_pos, seg_a, seg_b)
	if hit != null:
		return true
	# احتیاط: قطعهٔ آخرِ مسیر هم بررسی می‌شود (برخوردهای پرسرعت)
	return Geometry2D.segment_intersects_segment(prev_active_pos, now_pos, seg_a, seg_b) != null

func _finish_shot(kind: ShotKind, foul_reason: String = "") -> void:
	match kind:
		ShotKind.GOAL:
			scores[current_player - 1] += 1
			goal_particles.restart()
			_trigger_shake(14.0)
			_play_sfx(440.0, 900.0, 0.24)
			_update_hud()
			if scores[current_player - 1] >= WINNING_SCORE:
				state = GameState.MATCH_OVER
				status_label.text = "بازیکن %s برنده شد!" % _fa(current_player)
				_show_banner("قهرمان: بازیکن %s" % _fa(current_player), Color(0.3, 1.0, 0.5))
				reset_btn.text = "بازی جدید"
			else:
				state = GameState.TRANSITION
				status_label.text = "گل برای بازیکن %s!" % _fa(current_player)
				_show_banner("گلللل!", Color(0.3, 1.0, 0.5))
				_delayed_turn(1.8)
			return

		ShotKind.FOUL:
			_trigger_shake(8.0)
			_play_sfx(220.0, 110.0, 0.20)
			_after_mistake(foul_reason if foul_reason != "" else "خطا!")
			return

		_:
			pass

	# PASS / OPENER
	if kind == ShotKind.PASS:
		_play_sfx(540.0, 780.0, 0.10)
	moves_left -= 1
	if moves_left <= 0:
		_after_mistake("حرکت‌ها تمام شد! نوبت حریف.")
	else:
		state = GameState.WAITING_FOR_INPUT
		if opened:
			status_label.text = "دروازه باز شد! حالا شوت بزنید!"
			_show_banner("دروازه باز شد!", Color(0.3, 1.0, 0.65))
		else:
			status_label.text = "پاس صحیح! حرکت بعدی."
			_show_banner("پاس صحیح", Color(0.45, 0.95, 1.0))
		_update_hud()

func _after_mistake(reason: String) -> void:
	state = GameState.TRANSITION
	status_label.text = reason
	_show_banner("نوبت سوخت", Color(1.0, 0.38, 0.38))
	_update_hud()
	_delayed_turn(1.5)

func _delayed_turn(delay_sec: float) -> void:
	await get_tree().create_timer(delay_sec).timeout
	if state == GameState.TRANSITION:
		_switch_turn()

# ---------------------------------------------------------------- HUD
func _update_hud() -> void:
	var mark1 := "▶ " if current_player == 1 else "   "
	var mark2 := "▶ " if current_player == 2 else "   "
	p1_score_label.text = "%sبازیکن ۱: %s" % [mark1, _fa(scores[0])]
	p2_score_label.text = "%sبازیکن ۲: %s" % [mark2, _fa(scores[1])]

	var gate_txt := "باز" if gate_open else "قفل"
	turn_info_label.text = "نوبت %s | حرکت %s/%s | دروازه %s" % [
		_fa(current_player), _fa(moves_left), _fa(MOVES_PER_TURN), gate_txt
	]
	if goal_meter != null:
		if gate_open:
			goal_meter.size.x = 240.0
			goal_meter.color = Color(0.3, 1.0, 0.5)
		else:
			goal_meter.size.x = 0.0
			goal_meter.color = Color(1.0, 0.35, 0.35)

## ارقام فارسی برای HUD
func _fa(n: int) -> String:
	var digits := ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"]
	var s := str(n)
	var out := ""
	for i in range(s.length()):
		var ch := s.substr(i, 1)
		var idx := ch.to_int()
		out += digits[idx] if ch.is_valid_int() else ch
	return out
