extends Node2D
## سه‌توپ — نسخهٔ آرکید دو‌نفره (Phase 2.4)
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

enum GameState { MENU, TURN_SETUP, WAITING_FOR_INPUT, BALLS_MOVING, TRANSITION, MATCH_OVER }
enum ShotKind { NONE, PASS, OPENER, GOAL, FOUL }

# ---------------------------------------------------------------- پیکربندی
const TABLE_RECT := Rect2(60, 218, 960, 1542)
const WALL_THICKNESS := 24.0
const GOAL_RECT := Rect2(390, 140, 300, 78)
const BALL_RADIUS := 36.0
const MAX_DRAG_DIST := 320.0
const MIN_SHOT_DRAG_DIST := 24.0
const PRO_MIN_SWIPE_SPEED := 120.0
const PRO_MAX_SWIPE_SPEED := 1600.0
const IMPULSE_MULTIPLIER := 10.0
const STOP_SPEED_THRESHOLD := 12.0
const LINEAR_DAMP := 2.0
const WINNING_SCORE := 3
const DEFAULT_MOVES_PER_TURN := 3
const MIN_MOVES_PER_TURN := 1
const MAX_MOVES_PER_TURN := 9
const PROFESSIONAL_MIN_MOVES := 3
const MIX_RATE := 22050.0
## اندازهٔ طراحی صحنه (مستقل از اندازهٔ پنجره)
const DESIGN_SIZE := Vector2(1080, 1920)

## خط هجوم: اگر توپ پس از عبور از این خط متوقف شود، مسیر دروازه آزاد می‌شود.
## تعادل با جستجوی عددی روی ۲۱۶۰ شوت تنظیم شده (نه حدس):
##   حداکثر مسافت یک شوت = 320×10 / 2.0 = ۱۶۰۰px
##   خط روی ۴۶٫۵٪ میز است (نسبت ۰٫۴۶۵)؛ از شروع توپ‌ها حدود ۴۵۶px فاصله دارد.
##   با برد ۱۶۰۰px هنوز می‌توان با یک شوت پاس داد و دروازه را باز کرد.
##   تا دهانهٔ دروازه نیز مسیر شوت طلایی در دسترس می‌ماند.
##   با این تنظیم بخشی از فضای شوت‌های ممکن «طلایی» است؛ در عمل چون بازیکن
##   خط شکاف را می‌بیند، نرخ موفقیت واقعی به‌مراتب بالاتر است.
const ATTACK_LINE_RATIO := 0.465
const USER_SETTINGS_PATH := "user://se_toop_settings.cfg"

# ---------------------------------------------------------------- وضعیت
var state: GameState = GameState.WAITING_FOR_INPUT
var balls: Array[RigidBody2D] = []
var ball_visuals: Array[Node2D] = []
var ball_crease_lines: Array[Line2D] = []
var active_ball: RigidBody2D = null
var other_balls: Array[RigidBody2D] = []
var prev_active_pos := Vector2.ZERO
var shot_origin := Vector2.ZERO

var is_dragging := false
var drag_current_pos := Vector2.ZERO
var drag_start_pos := Vector2.ZERO
var drag_start_usec := 0
var drag_last_pos := Vector2.ZERO
var drag_last_usec := 0
var pro_motion_distance := 0.0
var pro_motion_usec := 0
var drag_ball: RigidBody2D = null

var current_player := 1
var scores: Array[int] = [0, 0]
var moves_per_turn := DEFAULT_MOVES_PER_TURN
var configured_moves := DEFAULT_MOVES_PER_TURN
var moves_left := DEFAULT_MOVES_PER_TURN
var professional_mode := false

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
var shot_collided := false
var pass_line_a := Vector2.ZERO
var pass_line_b := Vector2.ZERO
var pass_line_valid := false
var gate_tween: Tween

var goal_particles: CPUParticles2D
var gate_particles: CPUParticles2D

var hud_root: Control
var top_bar: ColorRect
var menu_overlay: ColorRect
var menu_panel: Panel
var score_card_p1: Panel
var score_card_p2: Panel
var top_info_card: Panel
var menu_kicker: Label
var menu_emblem: Label
var menu_accent: ColorRect
var tutorial_overlay: ColorRect
var tutorial_panel: Panel
var tutorial_title: Label
var tutorial_text: Label
var tutorial_guide_demo: Label
var tutorial_continue_button: Button
var professional_button: Button
var menu_title: Label
var menu_hint: Label
var move_count_label: Label
var moves_down_button: Button
var moves_up_button: Button
var start_game_button: Button
var menu_button: Button
var p1_score_label: Label
var p2_score_label: Label
var p1_score_value: Label
var p2_score_value: Label
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
	call_deferred("_show_main_menu")

## ریشهٔ صحنه حرکت نمی‌کند (لرزش روی دوربین است) تا فیزیک دست‌نخورده بماند.
##
## نکتهٔ مهم: اندازهٔ طراحی همیشه 1080×1920 است، نه اندازهٔ ویوپورت.
## stretch/aspect=expand است؛ در صفحهٔ افقی دوربین صحنه را ۹۰ درجه می‌چرخاند و در
## هر دو جهت با بزرگ‌نمایی مناسب میز کامل داخل پنجره جا می‌گیرد.
func _setup_camera() -> void:
	camera_center = DESIGN_SIZE * 0.5
	main_camera = Camera2D.new()
	main_camera.name = "ShakeCamera"
	main_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	main_camera.position = camera_center
	# اندازه و چرخش دوربین با نسبت واقعی پنجره تنظیم می‌شود.
	add_child(main_camera)
	main_camera.make_current()
	get_viewport().size_changed.connect(_refresh_layout)
	_refresh_layout()

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
	var labels: Array[Label] = [p1_score_label, p2_score_label, p1_score_value,
		p2_score_value, turn_info_label, status_label, banner_label, toast_label,
		menu_kicker, menu_title, menu_hint, menu_emblem, move_count_label,
		tutorial_title, tutorial_text, tutorial_guide_demo]
	for lbl in labels:
		if lbl != null:
			lbl.add_theme_font_override("font", sys_font)
	reset_btn.add_theme_font_override("font", sys_font)
	menu_button.add_theme_font_override("font", sys_font)
	moves_down_button.add_theme_font_override("font", sys_font)
	moves_up_button.add_theme_font_override("font", sys_font)
	start_game_button.add_theme_font_override("font", sys_font)
	professional_button.add_theme_font_override("font", sys_font)
	tutorial_continue_button.add_theme_font_override("font", sys_font)

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

func _build_environment() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.07, 0.06)
	bg.size = Vector2(1080, 1920)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_rect(TABLE_RECT.position + Vector2(16, 20), TABLE_RECT.size, Color(0, 0, 0, 0.40))

	_rect(TABLE_RECT.position - Vector2(14, 14), TABLE_RECT.size + Vector2(28, 28),
		Color(0.33, 0.20, 0.11))
	_rect(TABLE_RECT.position - Vector2(14, 14), Vector2(TABLE_RECT.size.x + 28, 4),
		Color(0.45, 0.29, 0.16))

	_rect(TABLE_RECT.position, TABLE_RECT.size, Color(0.46, 0.30, 0.17))

	for i in range(1, 8):
		_rect(Vector2(TABLE_RECT.position.x + float(i) * 120.0, TABLE_RECT.position.y),
			Vector2(3, TABLE_RECT.size.y), Color(0.40, 0.25, 0.13, 0.45))

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

	attack_line = Line2D.new()
	attack_line.width = 5.0
	attack_line.default_color = Color(1.0, 0.88, 0.30, 0.70)
	attack_line.points = PackedVector2Array([
		Vector2(TABLE_RECT.position.x, attack_y),
		Vector2(TABLE_RECT.end.x, attack_y)
	])
	add_child(attack_line)

	goal_line = Line2D.new()
	goal_line.width = 4.0
	goal_line.default_color = Color(0.35, 1.0, 0.55, 0.55)
	goal_line.points = PackedVector2Array([
		Vector2(GOAL_RECT.position.x, GOAL_RECT.end.y + 6.0),
		Vector2(GOAL_RECT.end.x, GOAL_RECT.end.y + 6.0)
	])
	add_child(goal_line)

	target_gate_line = Line2D.new()
	target_gate_line.width = 6.0
	target_gate_line.default_color = Color(0.25, 0.92, 1.0, 0.60)
	target_gate_line.visible = false
	add_child(target_gate_line)

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

func _build_goal() -> void:
	_rect(GOAL_RECT.position - Vector2(16, 16), GOAL_RECT.size + Vector2(32, 18),
		Color(0.07, 0.24, 0.15))
	_rect(GOAL_RECT.position, GOAL_RECT.size, Color(0.11, 0.50, 0.29))

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
	return p.x - BALL_RADIUS > gap_left and p.x + BALL_RADIUS < gap_right

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

func _panel_style(background: Color, border: Color, radius: int = 20) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 6)
	return style

func _style_button(button: Button, background: Color) -> void:
	button.add_theme_stylebox_override("normal", _panel_style(
		background, Color(1.0, 0.83, 0.48, 0.72), 18))
	button.add_theme_stylebox_override("hover", _panel_style(
		background.lightened(0.12), Color(1.0, 0.91, 0.68), 18))
	button.add_theme_stylebox_override("pressed", _panel_style(
		background.darkened(0.14), Color(1.0, 0.75, 0.32), 18))
	button.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "Hud"
	add_child(hud)

	hud_root = Control.new()
	hud_root.name = "HudRoot"
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hud_root)

	top_bar = ColorRect.new()
	top_bar.color = Color(0.06, 0.05, 0.04, 0.94)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(top_bar)

	score_card_p1 = Panel.new()
	score_card_p1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_card_p1.add_theme_stylebox_override("panel", _panel_style(
		Color(0.035, 0.13, 0.21, 0.96), Color(0.24, 0.67, 0.95, 0.72), 14))
	hud_root.add_child(score_card_p1)
	score_card_p2 = Panel.new()
	score_card_p2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_card_p2.add_theme_stylebox_override("panel", _panel_style(
		Color(0.22, 0.055, 0.075, 0.96), Color(0.96, 0.35, 0.39, 0.72), 14))
	hud_root.add_child(score_card_p2)
	top_info_card = Panel.new()
	top_info_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_info_card.add_theme_stylebox_override("panel", _panel_style(
		Color(0.045, 0.07, 0.085, 0.94), Color(0.50, 0.59, 0.62, 0.38), 14))
	hud_root.add_child(top_info_card)

	p1_score_label = _label(hud_root, Vector2.ZERO, 20, Color(0.72, 0.88, 0.98))
	p1_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p2_score_label = _label(hud_root, Vector2.ZERO, 20, Color(1.0, 0.78, 0.78))
	p2_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p1_score_value = _label(hud_root, Vector2.ZERO, 34, Color.WHITE)
	p1_score_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p2_score_value = _label(hud_root, Vector2.ZERO, 34, Color.WHITE)
	p2_score_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_info_label = _label(hud_root, Vector2.ZERO, 25, Color(0.98, 0.96, 0.90))
	status_label = _label(hud_root, Vector2.ZERO, 22, Color(1.0, 0.90, 0.56))

	goal_meter_bg = ColorRect.new()
	goal_meter_bg.color = Color(1, 1, 1, 0.16)
	goal_meter_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(goal_meter_bg)
	goal_meter = ColorRect.new()
	goal_meter.color = Color(1.0, 0.35, 0.35)
	goal_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(goal_meter)

	reset_btn = _new_button(hud_root, "تعویض نوبت")
	reset_btn.pressed.connect(_on_manual_reset_pressed)
	menu_button = _new_button(hud_root, "منو")
	menu_button.pressed.connect(_on_menu_pressed)

	banner_label = _label(hud_root, Vector2.ZERO, 48, Color.WHITE)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_label.modulate = Color(1, 1, 1, 0)
	toast_label = _label(hud_root, Vector2.ZERO, 20, Color.WHITE)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.modulate = Color(1, 1, 1, 0)

	# منوی شروع و تنظیم تعداد حرکت؛ با چیدمان صریح در هر دو جهت صفحه.
	menu_overlay = ColorRect.new()
	menu_overlay.color = Color(0.025, 0.02, 0.018, 0.88)
	menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(menu_overlay)
	menu_panel = Panel.new()
	menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.07, 0.055, 0.046, 0.98), Color(0.78, 0.57, 0.28, 0.92), 32))
	menu_overlay.add_child(menu_panel)

	menu_kicker = _label(menu_panel, Vector2.ZERO, 16, Color(0.86, 0.68, 0.40))
	menu_kicker.text = "کاغذی • آرکید • دونفره"
	menu_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_title = _label(menu_panel, Vector2.ZERO, 42, Color(1.0, 0.83, 0.48))
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_hint = _label(menu_panel, Vector2.ZERO, 20, Color(0.90, 0.88, 0.82))
	menu_hint.text = "دوئل کاغذی؛ سه توپ، یک قهرمان"
	menu_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_emblem = _label(menu_panel, Vector2.ZERO, 38, Color(0.96, 0.89, 0.72))
	menu_emblem.text = "●   ●   ●"
	menu_emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_accent = ColorRect.new()
	menu_accent.color = Color(0.92, 0.64, 0.28, 0.9)
	menu_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_panel.add_child(menu_accent)
	move_count_label = _label(menu_panel, Vector2.ZERO, 30, Color.WHITE)
	move_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	moves_down_button = _new_button(menu_panel, "−")
	moves_down_button.pressed.connect(_change_configured_moves.bind(-1))
	moves_up_button = _new_button(menu_panel, "+")
	moves_up_button.pressed.connect(_change_configured_moves.bind(1))
	professional_button = _new_button(menu_panel, "حرفه‌ای: خاموش")
	professional_button.toggle_mode = true
	professional_button.toggled.connect(_on_professional_toggled)
	start_game_button = _new_button(menu_panel, "شروع بازی")
	_style_button(start_game_button, Color(0.43, 0.25, 0.10, 1.0))
	_style_button(professional_button, Color(0.16, 0.14, 0.12, 1.0))
	_style_button(moves_down_button, Color(0.16, 0.14, 0.12, 1.0))
	_style_button(moves_up_button, Color(0.16, 0.14, 0.12, 1.0))
	start_game_button.pressed.connect(_on_start_game_pressed)

	tutorial_overlay = ColorRect.new()
	tutorial_overlay.color = Color(0.025, 0.02, 0.018, 0.92)
	tutorial_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	tutorial_overlay.visible = false
	hud_root.add_child(tutorial_overlay)
	tutorial_panel = Panel.new()
	tutorial_panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.07, 0.055, 0.046, 0.99), Color(0.38, 0.72, 0.78, 0.82), 28))
	tutorial_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	tutorial_overlay.add_child(tutorial_panel)
	tutorial_title = _label(tutorial_panel, Vector2.ZERO, 38, Color(1.0, 0.83, 0.48))
	tutorial_title.text = "آموزش کوتاه"
	tutorial_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_text = _label(tutorial_panel, Vector2.ZERO, 22, Color(0.95, 0.92, 0.86))
	tutorial_text.text = "۱) عادی: توپ را خلاف جهت شوت بکشید. " \
		+ "حرفه‌ای: در جهت شوت سریع بکشید؛ سرعت انگشت قدرت را تعیین می‌کند.\n\n" \
		+ "۲) برای پاس، توپ را از شکاف دو توپ عبور دهید؛ برخورد با توپ دیگر خطاست و نوبت می‌سوزد.\n\n" \
		+ "۳) پس از عبور توپ از خط میانی، صبر کنید تا بایستد و مسیر آزاد شود؛ " \
		+ "برای گل باید تمام توپ از خط دروازه رد شود.\n\n" \
		+ "۴) در حالت حرفه‌ای، گل از حرکت سوم به بعد مجاز است؛ تعداد حرکت را از منو تنظیم کنید."
	tutorial_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial_guide_demo = _label(tutorial_panel, Vector2.ZERO, 24, Color(0.40, 0.91, 1.0))
	tutorial_guide_demo.text = "خط راهنمای شوت:  توپ  ─────────▶  مسیر"
	tutorial_guide_demo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_continue_button = _new_button(tutorial_panel, "متوجه شدم؛ شروع بازی")
	_style_button(tutorial_continue_button, Color(0.43, 0.25, 0.10, 1.0))
	tutorial_continue_button.pressed.connect(_on_tutorial_continue_pressed)

	_refresh_layout()

func _label(parent: Control, initial_position: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = initial_position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.62))
	label.add_theme_constant_override("outline_size", 1)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _new_button(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(button)
	return button

func _layout_label(node: Control, rect: Rect2, font_size: int) -> void:
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_size_override("font_size", font_size)

func _refresh_layout() -> void:
	if get_viewport() == null:
		return
	var view_size := get_viewport().get_visible_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return
	var landscape := view_size.x > view_size.y
	var design_fit := minf(view_size.x / DESIGN_SIZE.x, view_size.y / DESIGN_SIZE.y)
	if landscape:
		design_fit = minf(view_size.x / DESIGN_SIZE.y, view_size.y / DESIGN_SIZE.x)
		main_camera.rotation = -PI * 0.5
	else:
		main_camera.rotation = 0.0
	main_camera.zoom = Vector2.ONE * maxf(design_fit, 0.05)
	camera_center = DESIGN_SIZE * 0.5
	main_camera.position = camera_center
	if hud_root != null:
		_layout_hud(view_size, landscape)
		_layout_tutorial(view_size, landscape)
		if p1_score_label != null:
			_update_hud()

func _layout_hud(view_size: Vector2, landscape: bool) -> void:
	var reference := Vector2(1920, 1080) if landscape else DESIGN_SIZE
	var scale_ui := minf(view_size.x / reference.x, view_size.y / reference.y)
	var canvas_size := reference * scale_ui
	var origin := (view_size - canvas_size) * 0.5
	hud_root.position = Vector2.ZERO
	hud_root.size = view_size
	top_bar.position = origin
	top_bar.size = Vector2(canvas_size.x, 112.0 * scale_ui if landscape else 126.0 * scale_ui)

	if landscape:
		score_card_p1.position = origin + Vector2(16, 6) * scale_ui
		score_card_p1.size = Vector2(278, 44) * scale_ui
		score_card_p2.position = origin + Vector2(16, 61) * scale_ui
		score_card_p2.size = Vector2(278, 44) * scale_ui
		_layout_label(p1_score_value, Rect2(origin + Vector2(24, 5) * scale_ui,
			Vector2(48, 42) * scale_ui), roundi(31 * scale_ui))
		_layout_label(p2_score_value, Rect2(origin + Vector2(24, 60) * scale_ui,
			Vector2(48, 42) * scale_ui), roundi(31 * scale_ui))
		_layout_label(p1_score_label, Rect2(origin + Vector2(78, 5) * scale_ui,
			Vector2(205, 42) * scale_ui), roundi(19 * scale_ui))
		_layout_label(p2_score_label, Rect2(origin + Vector2(78, 60) * scale_ui,
			Vector2(205, 42) * scale_ui), roundi(19 * scale_ui))
		top_info_card.position = origin + Vector2(315, 5) * scale_ui
		top_info_card.size = Vector2(650, 102) * scale_ui
		_layout_label(turn_info_label, Rect2(origin + Vector2(335, 7) * scale_ui,
			Vector2(590, 42) * scale_ui), roundi(26 * scale_ui))
		_layout_label(status_label, Rect2(origin + Vector2(335, 50) * scale_ui,
			Vector2(600, 36) * scale_ui), roundi(21 * scale_ui))
		goal_meter_bg.position = origin + Vector2(330, 96) * scale_ui
		goal_meter_bg.size = Vector2(250, 9) * scale_ui
		reset_btn.position = origin + Vector2(1500, 13) * scale_ui
		reset_btn.size = Vector2(240, 78) * scale_ui
		menu_button.position = origin + Vector2(1760, 13) * scale_ui
		menu_button.size = Vector2(135, 78) * scale_ui
		_layout_label(banner_label, Rect2(origin + Vector2(500, 430) * scale_ui,
			Vector2(920, 120) * scale_ui), roundi(48 * scale_ui))
		_layout_label(toast_label, Rect2(origin + Vector2(240, 1010) * scale_ui,
			Vector2(1440, 50) * scale_ui), roundi(20 * scale_ui))
	else:
		score_card_p1.position = origin + Vector2(12, 5) * scale_ui
		score_card_p1.size = Vector2(292, 53) * scale_ui
		score_card_p2.position = origin + Vector2(12, 66) * scale_ui
		score_card_p2.size = Vector2(292, 53) * scale_ui
		_layout_label(p1_score_value, Rect2(origin + Vector2(22, 5) * scale_ui,
			Vector2(58, 51) * scale_ui), roundi(36 * scale_ui))
		_layout_label(p2_score_value, Rect2(origin + Vector2(22, 66) * scale_ui,
			Vector2(58, 51) * scale_ui), roundi(36 * scale_ui))
		_layout_label(p1_score_label, Rect2(origin + Vector2(86, 5) * scale_ui,
			Vector2(207, 51) * scale_ui), roundi(22 * scale_ui))
		_layout_label(p2_score_label, Rect2(origin + Vector2(86, 66) * scale_ui,
			Vector2(207, 51) * scale_ui), roundi(22 * scale_ui))
		top_info_card.position = origin + Vector2(310, 5) * scale_ui
		top_info_card.size = Vector2(435, 92) * scale_ui
		_layout_label(turn_info_label, Rect2(origin + Vector2(326, 8) * scale_ui,
			Vector2(405, 41) * scale_ui), roundi(24 * scale_ui))
		_layout_label(status_label, Rect2(origin + Vector2(326, 49) * scale_ui,
			Vector2(405, 38) * scale_ui), roundi(21 * scale_ui))
		goal_meter_bg.position = origin + Vector2(315, 101) * scale_ui
		goal_meter_bg.size = Vector2(240, 9) * scale_ui
		reset_btn.position = origin + Vector2(752, 18) * scale_ui
		reset_btn.size = Vector2(204, 82) * scale_ui
		menu_button.position = origin + Vector2(968, 18) * scale_ui
		menu_button.size = Vector2(94, 82) * scale_ui
		_layout_label(banner_label, Rect2(origin + Vector2(120, 890) * scale_ui,
			Vector2(840, 120) * scale_ui), roundi(48 * scale_ui))
		_layout_label(toast_label, Rect2(origin + Vector2(60, 1820) * scale_ui,
			Vector2(960, 60) * scale_ui), roundi(20 * scale_ui))
	goal_meter.position = goal_meter_bg.position
	goal_meter.size.y = goal_meter_bg.size.y
	reset_btn.add_theme_font_size_override("font_size", roundi(17 * scale_ui))
	menu_button.add_theme_font_size_override("font_size", roundi(20 * scale_ui))
	_layout_menu(view_size, landscape)

func _layout_menu(view_size: Vector2, landscape: bool) -> void:
	menu_overlay.position = Vector2.ZERO
	menu_overlay.size = view_size
	var panel_ref := Vector2(980, 660) if landscape else Vector2(860, 700)
	var panel_scale := minf((view_size.x - 32) / panel_ref.x,
		(view_size.y - 32) / panel_ref.y)
	panel_scale = maxf(panel_scale, 0.35)
	var panel_size := panel_ref * panel_scale
	menu_panel.position = (view_size - panel_size) * 0.5
	menu_panel.size = panel_size
	_layout_label(menu_kicker, Rect2(Vector2(36, 18) * panel_scale,
		Vector2(panel_ref.x - 72, 30) * panel_scale), roundi(16 * panel_scale))
	_layout_label(menu_title, Rect2(Vector2(36, 48) * panel_scale,
		Vector2(panel_ref.x - 72, 76) * panel_scale), roundi(56 * panel_scale))
	_layout_label(menu_hint, Rect2(Vector2(36, 122) * panel_scale,
		Vector2(panel_ref.x - 72, 42) * panel_scale), roundi(20 * panel_scale))
	_layout_label(menu_emblem, Rect2(Vector2(36, 166) * panel_scale,
		Vector2(panel_ref.x - 72, 56) * panel_scale), roundi(38 * panel_scale))
	menu_accent.position = Vector2(110, 236) * panel_scale
	menu_accent.size = Vector2(panel_ref.x - 220, 3) * panel_scale
	_layout_label(move_count_label, Rect2(Vector2((panel_ref.x - 420) * 0.5, 274) * panel_scale,
		Vector2(420, 68) * panel_scale), roundi(30 * panel_scale))
	moves_down_button.position = Vector2(150, 270) * panel_scale
	moves_down_button.size = Vector2(100, 78) * panel_scale
	moves_up_button.position = Vector2(panel_ref.x - 250, 270) * panel_scale
	moves_up_button.size = Vector2(100, 78) * panel_scale
	moves_down_button.add_theme_font_size_override("font_size", roundi(36 * panel_scale))
	moves_up_button.add_theme_font_size_override("font_size", roundi(36 * panel_scale))
	professional_button.position = Vector2(100, 382) * panel_scale
	professional_button.size = Vector2(panel_ref.x - 200, 64) * panel_scale
	professional_button.add_theme_font_size_override("font_size", roundi(20 * panel_scale))
	professional_button.text = "حرفه‌ای: روشن (سوایپ جلو · گل از حرکت ۳)" \
		if professional_mode else "حرفه‌ای: خاموش"
	start_game_button.position = Vector2(72, panel_ref.y - 124) * panel_scale
	start_game_button.size = Vector2(panel_ref.x - 144, 82) * panel_scale
	start_game_button.add_theme_font_size_override("font_size", roundi(25 * panel_scale))
	menu_title.text = "سه‌توپ"
	_update_move_count_label()

func _layout_tutorial(view_size: Vector2, landscape: bool) -> void:
	if tutorial_overlay == null:
		return
	tutorial_overlay.position = Vector2.ZERO
	tutorial_overlay.size = view_size
	var panel_ref := Vector2(980, 720) if landscape else Vector2(860, 820)
	var panel_scale := minf(minf(view_size.x / panel_ref.x, view_size.y / panel_ref.y), 1.0)
	panel_scale = maxf(panel_scale, 0.35)
	var panel_size := panel_ref * panel_scale
	tutorial_panel.position = (view_size - panel_size) * 0.5
	tutorial_panel.size = panel_size
	tutorial_title.position = Vector2(36, 34) * panel_scale
	tutorial_title.size = Vector2(panel_ref.x - 72, 68) * panel_scale
	tutorial_title.add_theme_font_size_override("font_size", roundi(38 * panel_scale))
	tutorial_text.position = Vector2(54, 118) * panel_scale
	tutorial_text.size = Vector2(panel_ref.x - 108, panel_ref.y - 300) * panel_scale
	tutorial_text.add_theme_font_size_override("font_size", roundi(22 * panel_scale))
	tutorial_guide_demo.position = Vector2(36, panel_ref.y - 160) * panel_scale
	tutorial_guide_demo.size = Vector2(panel_ref.x - 72, 52) * panel_scale
	tutorial_guide_demo.add_theme_font_size_override("font_size", roundi(24 * panel_scale))
	tutorial_continue_button.position = Vector2(72, panel_ref.y - 92) * panel_scale
	tutorial_continue_button.size = Vector2(panel_ref.x - 144, 66) * panel_scale
	tutorial_continue_button.add_theme_font_size_override("font_size", roundi(22 * panel_scale))

func _minimum_configured_moves() -> int:
	return PROFESSIONAL_MIN_MOVES if professional_mode else MIN_MOVES_PER_TURN

func _update_move_count_label() -> void:
	if move_count_label != null:
		move_count_label.text = "تعداد حرکت مجاز: %s" % _fa(configured_moves)
	if moves_down_button != null:
		moves_down_button.disabled = configured_moves <= _minimum_configured_moves()
	if moves_up_button != null:
		moves_up_button.disabled = configured_moves >= MAX_MOVES_PER_TURN

func _change_configured_moves(amount: int) -> void:
	configured_moves = clampi(configured_moves + amount,
		_minimum_configured_moves(), MAX_MOVES_PER_TURN)
	_update_move_count_label()

func _show_main_menu() -> void:
	state = GameState.MENU
	is_dragging = false
	active_ball = null
	drag_ball = null
	for ball in balls:
		ball.linear_velocity = Vector2.ZERO
		ball.angular_velocity = 0.0
		ball.sleeping = true
		ball.visible = false
	menu_overlay.visible = true
	aim_line.visible = false
	aim_tip.visible = false
	target_gate_line.visible = false
	_set_gate(false, true)
	start_game_button.text = "شروع بازی" if scores == [0, 0] else "شروع دوباره"
	_layout_hud(get_viewport().get_visible_rect().size,
		get_viewport().get_visible_rect().size.x > get_viewport().get_visible_rect().size.y)

func _on_menu_pressed() -> void:
	_show_main_menu()

func _on_start_game_pressed() -> void:
	moves_per_turn = configured_moves
	menu_overlay.visible = false
	if not _tutorial_has_been_seen():
		tutorial_overlay.visible = true
		return
	_start_game_now()

func _tutorial_has_been_seen() -> bool:
	var settings := ConfigFile.new()
	if settings.load(USER_SETTINGS_PATH) != OK:
		return false
	return settings.get_value("progress", "tutorial_seen", false) == true

func _on_tutorial_continue_pressed() -> void:
	var settings := ConfigFile.new()
	settings.load(USER_SETTINGS_PATH)
	settings.set_value("progress", "tutorial_seen", true)
	settings.save(USER_SETTINGS_PATH)
	tutorial_overlay.visible = false
	_start_game_now()

func _start_game_now() -> void:
	for ball in balls:
		ball.visible = true
	_start_new_match()

func _on_professional_toggled(enabled: bool) -> void:
	professional_mode = enabled
	if professional_mode:
		configured_moves = maxi(configured_moves, PROFESSIONAL_MIN_MOVES)
	professional_button.text = "حرفه‌ای: روشن (سوایپ جلو · گل از حرکت ۳)" \
		if professional_mode else "حرفه‌ای: خاموش"
	_update_move_count_label()
	goal_meter_bg.visible = not professional_mode
	goal_meter.visible = not professional_mode
	if professional_mode:
		aim_line.visible = false
		aim_tip.visible = false
		target_gate_line.visible = false
		goal_meter.size.x = 0.0

func _show_banner(text: String, color: Color = Color(1, 0.95, 0.3)) -> void:
	banner_label.text = text
	banner_label.modulate = color
	banner_label.scale = Vector2(0.72, 0.72)
	banner_label.pivot_offset = banner_label.size * 0.5
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

		var visual_root := Node2D.new()
		visual_root.name = "PaperVisual"
		ball.add_child(visual_root)

		var pts := PackedVector2Array()
		var blend := randf_range(-2.6, 2.6)
		for v in range(12):
			var ang := float(v) * TAU / 12.0
			var r := BALL_RADIUS * randf_range(0.86, 1.04)
			r *= 1.0 + 0.10 * cos(ang * 2.0 + blend)
			pts.append(Vector2(cos(ang) * r, sin(ang) * r))

		var shadow := Polygon2D.new()
		shadow.polygon = pts
		shadow.color = Color(0, 0, 0, 0.30)
		shadow.position = Vector2(6, 8)
		visual_root.add_child(shadow)

		var body := Polygon2D.new()
		body.polygon = pts
		body.color = Color(0.97, 0.96, 0.91)
		visual_root.add_child(body)

		var outline := Line2D.new()
		outline.width = 2.0
		outline.default_color = Color(0.78, 0.74, 0.64, 0.55)
		var loop := PackedVector2Array(pts)
		loop.append(pts[0])
		outline.points = loop
		visual_root.add_child(outline)

		var crease := Line2D.new()
		crease.width = 2.5
		crease.default_color = Color(0.36, 0.55, 0.85, 0.42)
		crease.points = PackedVector2Array([
			pts[1] * 0.62, Vector2.ZERO, pts[5] * 0.68, pts[8] * 0.58
		])
		visual_root.add_child(crease)
		ball_crease_lines.append(crease)
		ball_visuals.append(visual_root)

		ball.body_entered.connect(_on_ball_body_entered.bind(ball))
		add_child(ball)
		balls.append(ball)


func _start_new_match() -> void:
	scores = [0, 0]
	current_player = 1
	reset_btn.text = "تعویض نوبت"
	_start_turn(1)
	_show_toast("")

func _on_manual_reset_pressed() -> void:
	if state == GameState.MATCH_OVER:
		_start_new_match()
	else:
		_switch_turn()

func _start_turn(player_idx: int) -> void:
	current_player = player_idx
	for crease in ball_crease_lines:
		crease.default_color = Color(0.35, 0.72, 1.0, 0.72) if current_player == 1 \
			else Color(1.0, 0.40, 0.42, 0.72)
	moves_left = moves_per_turn
	state = GameState.TURN_SETUP
	active_ball = null
	other_balls.clear()
	shot_collided = false
	gap_crossed = false
	pass_line_valid = false
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
		var p: Vector2 = base[i] + Vector2(randf_range(-58, 58), randf_range(-46, 46))
		b.sleeping = false
		b.linear_velocity = Vector2.from_angle(randf_range(0.0, TAU)) * randf_range(150.0, 245.0)
		b.angular_velocity = randf_range(-6.0, 6.0)
		b.global_position = p
		PhysicsServer2D.body_set_state(
			b.get_rid(),
			PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(randf_range(0.0, TAU), p)
		)
		var visual := ball_visuals[i]
		visual.position = Vector2(0, -56)
		visual.scale = Vector2(0.82, 0.58)
		var drop_tween := create_tween().set_parallel(true)
		drop_tween.tween_property(visual, "position", Vector2.ZERO, 0.38) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		drop_tween.tween_property(visual, "scale", Vector2.ONE, 0.38) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	status_label.text = "توپ‌ها روی میز پخش می‌شوند"
	_show_banner("نوبت بازیکن %s" % _fa(current_player),
		Color(0.45, 0.80, 1.0) if current_player == 1 else Color(1.0, 0.52, 0.52))
	_update_hud()

func _switch_turn() -> void:
	_start_turn(2 if current_player == 1 else 1)

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
		drag_start_pos = pos
		drag_start_usec = Time.get_ticks_usec()
		drag_last_pos = pos
		drag_last_usec = drag_start_usec
		pro_motion_distance = 0.0
		pro_motion_usec = 0
		if not professional_mode:
			_update_target_gate_preview(best)
		_play_sfx(720.0, 760.0, 0.05, -22.0)

func _track_pro_swipe_motion(pos: Vector2, now_usec: int) -> void:
	var elapsed_usec := now_usec - drag_last_usec
	var step_distance := pos.distance_to(drag_last_pos)
	# Ignore pauses between movement bursts so holding the finger does not dilute power.
	if elapsed_usec > 0 and elapsed_usec <= 150000 and step_distance > 0.0:
		pro_motion_distance += step_distance
		pro_motion_usec += elapsed_usec
	drag_last_pos = pos
	drag_last_usec = now_usec

func _update_drag(pos: Vector2) -> void:
	drag_current_pos = pos
	if professional_mode:
		_track_pro_swipe_motion(pos, Time.get_ticks_usec())
		aim_line.visible = false
		aim_tip.visible = false
		target_gate_line.visible = false
		goal_meter.size.x = 0.0
		return
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
	if professional_mode:
		var now_usec := Time.get_ticks_usec()
		_track_pro_swipe_motion(pos, now_usec)
		var swipe := pos - drag_start_pos
		var elapsed := maxf((now_usec - drag_start_usec) / 1000000.0, 0.05)
		var swipe_speed := swipe.length() / elapsed
		if pro_motion_usec > 0:
			swipe_speed = pro_motion_distance / (float(pro_motion_usec) / 1000000.0)
		if swipe.length() >= MIN_SHOT_DRAG_DIST:
			var power_ratio := clampf(
				(swipe_speed - PRO_MIN_SWIPE_SPEED) / (PRO_MAX_SWIPE_SPEED - PRO_MIN_SWIPE_SPEED),
				0.0, 1.0)
			var equivalent_drag := lerpf(MIN_SHOT_DRAG_DIST, MAX_DRAG_DIST, power_ratio)
			_shoot_ball(drag_ball, swipe.normalized() * equivalent_drag * IMPULSE_MULTIPLIER)
		else:
			active_ball = null
	else:
		var pull := drag_ball.global_position - pos
		if pull.length() > MIN_SHOT_DRAG_DIST:
			_shoot_ball(drag_ball, pull.limit_length(MAX_DRAG_DIST) * IMPULSE_MULTIPLIER)
		else:
			active_ball = null
	drag_ball = null

func _current_turn_move_number() -> int:
	return moves_per_turn - moves_left + 1

func _update_target_gate_preview(selected: RigidBody2D) -> void:
	if professional_mode:
		target_gate_line.visible = false
		return
	var others: Array[Vector2] = []
	for b in balls:
		if b != selected:
			others.append(b.global_position)
	if others.size() == 2:
		target_gate_line.visible = true
		target_gate_line.points = PackedVector2Array([others[0], others[1]])

func _shoot_ball(ball: RigidBody2D, impulse: Vector2) -> void:
	state = GameState.BALLS_MOVING
	prev_active_pos = ball.global_position
	shot_origin = ball.global_position
	gap_crossed = false
	shot_collided = false

	other_balls.clear()
	for b in balls:
		if b != ball:
			other_balls.append(b)
	pass_line_valid = other_balls.size() == 2
	if pass_line_valid:
		pass_line_a = other_balls[0].global_position
		pass_line_b = other_balls[1].global_position

	ball.sleeping = false
	ball.apply_central_impulse(impulse)
	ball.apply_torque_impulse(randf_range(-1400.0, 1400.0))
	_play_sfx(280.0, 150.0, 0.08)
	status_label.text = ""
	_update_hud()

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
	if goal_meter != null and active_ball != null and is_dragging and not professional_mode:
		var target := _attack_line_y()
		var span := maxf(absf(shot_origin.y - target), 1.0)
		var ratio := clampf(1.0 - absf(active_ball.global_position.y - target) / span, 0.0, 1.0)
		goal_meter.size.x = goal_meter_bg.size.x * ratio

func _trigger_shake(amount: float) -> void:
	shake_strength = maxf(shake_strength, amount)

func _physics_process(_delta: float) -> void:
	if state == GameState.TURN_SETUP:
		var setup_stopped := true
		for b in balls:
			if b.linear_velocity.length() > STOP_SPEED_THRESHOLD:
				setup_stopped = false
				break
		if setup_stopped:
			for b in balls:
				b.linear_velocity = Vector2.ZERO
				b.angular_velocity = 0.0
				b.sleeping = true
			state = GameState.WAITING_FOR_INPUT
			status_label.text = ""
			_update_hud()
		return
	if state != GameState.BALLS_MOVING or active_ball == null:
		return

	if shot_collided:
		var collision_stopped := true
		for b in balls:
			if b.linear_velocity.length() > STOP_SPEED_THRESHOLD:
				collision_stopped = false
				break
		if collision_stopped:
			_finish_shot(ShotKind.FOUL, "برخورد با توپ دیگر! نوبت سوخت.")
		return

	var cur := active_ball.global_position

	# ۱) گل فقط وقتی ثبت می‌شود که تمام توپ از خط ورودی دروازه عبور کند.
	if cur.y + BALL_RADIUS <= GOAL_RECT.end.y + 6.0 \
		and cur.x >= GOAL_RECT.position.x + BALL_RADIUS \
		and cur.x <= GOAL_RECT.end.x - BALL_RADIUS \
		and _is_gate_open_for(cur):
		if professional_mode and _current_turn_move_number() < PROFESSIONAL_MIN_MOVES:
			_finish_shot(ShotKind.FOUL, "در حالت حرفه‌ای، گل از حرکت سوم به بعد مجاز است؛ نوبت سوخت.")
		else:
			_finish_shot(ShotKind.GOAL)
		return

	# عبور از خط بین دو توپ در هر فریم ثبت می‌شود؛ این کار پیش از داوری خروج
	# از میز انجام می‌شود تا عبور واقعی از شکاف به‌اشتباه «سوختن نوبت» نشود.
	if not gap_crossed and pass_line_valid:
		if Geometry2D.segment_intersects_segment(
				prev_active_pos, cur, pass_line_a, pass_line_b) != null:
			gap_crossed = true
			_play_sfx(540.0, 780.0, 0.09)

	# ۲) افتادن توپ از زمین (میز + دهانهٔ دروازه) → خطا
	for b in balls:
		if not _is_on_field(b.global_position):
			_finish_shot(ShotKind.FOUL, "خطا! توپ از روی میز بیرون افتاد.")
			return

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
	var goal_tunnel := Rect2(
		GOAL_RECT.position - Vector2(BALL_RADIUS, BALL_RADIUS),
		GOAL_RECT.size + Vector2(BALL_RADIUS * 2.0, BALL_RADIUS)
	)
	return TABLE_RECT.has_point(p) or goal_tunnel.has_point(p)

func _on_ball_body_entered(body: Node, source_ball: RigidBody2D) -> void:
	if state != GameState.BALLS_MOVING or source_ball != active_ball:
		return
	if body is RigidBody2D and balls.has(body) and not shot_collided:
		shot_collided = true
		_trigger_shake(7.0)
		_play_sfx(160.0, 95.0, 0.13)

## ترتیب داوری اصلاح‌شده: ابتدا دستاوردها (گل / عبور از شکاف / باز کردن دروازه)
## ثبت می‌شوند و تنها اگر هیچ‌کدام رخ نداده باشد خطا اعلام می‌شود.
func _judge_shot() -> void:
	if shot_collided:
		_finish_shot(ShotKind.FOUL, "برخورد با توپ دیگر! نوبت سوخت.")
		return
	var crossed := gap_crossed or _passed_between()
	var opened := false
	for b in balls:
		if b.global_position.y < _attack_line_y():
			opened = true
			break
	var reached_goal := active_ball != null and active_ball.global_position.y \
		<= GOAL_RECT.end.y + BALL_RADIUS

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
	if active_ball == null or not pass_line_valid:
		return false
	if gap_crossed:
		return true
	var now_pos := active_ball.global_position
	if Geometry2D.segment_intersects_segment(
			shot_origin, now_pos, pass_line_a, pass_line_b) != null:
		return true
	return Geometry2D.segment_intersects_segment(
			prev_active_pos, now_pos, pass_line_a, pass_line_b) != null

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

	# PASS / OPENER: هر شوت موفق یک حرکت از سهمیه کم می‌کند.
	if kind == ShotKind.PASS:
		_play_sfx(540.0, 780.0, 0.10)
	moves_left -= 1
	if moves_left <= 0:
		state = GameState.TRANSITION
		status_label.text = "حرکت‌های مجاز تمام شد؛ نوبت حریف."
		_show_banner("پایان نوبت", Color(1.0, 0.82, 0.38))
		_update_hud()
		_delayed_turn(1.2)
	else:
		state = GameState.WAITING_FOR_INPUT
		status_label.text = ""
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

func _update_hud() -> void:
	var mark1 := "▶ " if current_player == 1 else "   "
	var mark2 := "▶ " if current_player == 2 else "   "
	p1_score_label.text = "%sبازیکن ۱" % mark1
	p2_score_label.text = "%sبازیکن ۲" % mark2
	p1_score_value.text = _fa(scores[0])
	p2_score_value.text = _fa(scores[1])

	var gate_txt := "آزاد" if gate_open else "مسدود"
	turn_info_label.text = "نوبت %s | حرکت %s/%s | مسیر %s" % [
		_fa(current_player), _fa(moves_left), _fa(moves_per_turn), gate_txt
	]
	if goal_meter != null:
		if gate_open:
			goal_meter.size.x = goal_meter_bg.size.x
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
