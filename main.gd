extends Node2D
## سه‌توپ — بازی آرکید دونفره با Godot 4.7

enum GameState { MENU, TURN_SETUP, WAITING_FOR_INPUT, BALLS_MOVING, TRANSITION, MATCH_OVER }
enum ShotKind { NONE, PASS, GOAL, FOUL }

# ---------------------------------------------------------------- پیکربندی
const TABLE_RECT := Rect2(60, 218, 960, 1542)
const WALL_THICKNESS := 24.0
const GOAL_RECT := Rect2(390, 140, 300, 78)
const BALL_RADIUS := 36.0
const MAX_DRAG_DIST := 320.0
const MIN_SHOT_DRAG_DIST := 24.0
const IMPULSE_MULTIPLIER := 10.0
const STOP_SPEED_THRESHOLD := 12.0
const LINEAR_DAMP := 2.0
const DEFAULT_WINNING_SCORE := 3
const MIN_WINNING_SCORE := 1
const MAX_WINNING_SCORE := 15
const DEFAULT_MOVES_PER_TURN := 3
const MIN_MOVES_PER_TURN := 2
const MAX_MOVES_PER_TURN := 9
const PROFESSIONAL_MIN_MOVES := 3
const SURFACE_IDS := ["grass", "indoor", "asphalt", "table", "glass", "rug", "carpet"]
const SURFACE_NAMES := ["چمن", "سالن", "آسفالت", "میز چوبی", "شیشه", "فرش", "موکت"]
const SURFACE_DAMPING := [2.55, 1.75, 2.05, 2.0, 1.35, 3.25, 2.85]
const NATIONAL_TEAMS := ["ایران", "ژاپن", "برزیل", "آرژانتین", "مراکش", "فرانسه", "اسپانیا", "آلمان"]
const CLUB_TEAMS := ["پرسپولیس", "استقلال", "بارسلونا", "رئال مادرید", "لیورپول", "منچسترسیتی", "بایرن مونیخ", "الهلال"]
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
var pro_touch_pressure_min := 1.0
var pro_touch_pressure_max := 0.0
var pro_touch_pressure_samples := 0
var pro_peak_flick_speed := 0.0
var pro_last_sample_pos := Vector2.ZERO
var pro_last_sample_time_usec := 0
var drag_ball: RigidBody2D = null

var current_player := 1
var scores: Array[int] = [0, 0]
var moves_per_turn := DEFAULT_MOVES_PER_TURN
var configured_moves := DEFAULT_MOVES_PER_TURN
var moves_left := DEFAULT_MOVES_PER_TURN
var winning_score := DEFAULT_WINNING_SCORE
var professional_mode := false
var selected_surface := 3
var tournament_kind := 0
var tournament_team_indices := [0, 1]
var tournament_mode := false
var tournament_wins := [0, 0]
var tournament_match := 1

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
var shot_physics_frames := 0
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
var menu_row_panels: Array[Panel] = []
var surface_pattern_nodes: Array[ColorRect] = []
var table_surface: ColorRect
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
var victory_overlay: ColorRect
var victory_panel: Panel
var victory_cup: Label
var victory_title: Label
var victory_summary: Label
var victory_replay_button: Button
var victory_menu_button: Button
var professional_button: Button
var surface_cycle_button: Button
var tournament_kind_button: Button
var tournament_team1_button: Button
var tournament_team2_button: Button
var tournament_start_button: Button
var menu_title: Label
var menu_hint: Label
var move_count_label: Label
var moves_down_button: Button
var moves_up_button: Button
var score_target_label: Label
var score_down_button: Button
var score_up_button: Button
var exit_confirmation: ConfirmationDialog
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
var toast_label: Label

var audio_out: AudioStreamPlayer
var audio_sfx: AudioStreamPlayer
var font_ready := false

# ---------------------------------------------------------------- چرخهٔ عمر
func _ready() -> void:
	randomize()
	_load_winning_score()
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
		score_target_label, tutorial_title, tutorial_text, tutorial_guide_demo,
		victory_cup, victory_title, victory_summary]
	for lbl in labels:
		if lbl != null:
			lbl.add_theme_font_override("font", sys_font)
	menu_button.add_theme_font_override("font", sys_font)
	moves_down_button.add_theme_font_override("font", sys_font)
	moves_up_button.add_theme_font_override("font", sys_font)
	start_game_button.add_theme_font_override("font", sys_font)
	professional_button.add_theme_font_override("font", sys_font)
	surface_cycle_button.add_theme_font_override("font", sys_font)
	tournament_kind_button.add_theme_font_override("font", sys_font)
	tournament_team1_button.add_theme_font_override("font", sys_font)
	tournament_team2_button.add_theme_font_override("font", sys_font)
	tournament_start_button.add_theme_font_override("font", sys_font)
	score_down_button.add_theme_font_override("font", sys_font)
	score_up_button.add_theme_font_override("font", sys_font)
	exit_confirmation.add_theme_font_override("font", sys_font)
	tutorial_continue_button.add_theme_font_override("font", sys_font)
	victory_replay_button.add_theme_font_override("font", sys_font)
	victory_menu_button.add_theme_font_override("font", sys_font)

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

	table_surface = _rect(TABLE_RECT.position, TABLE_RECT.size, Color(0.46, 0.30, 0.17))
	for _pattern_index in range(100):
		var pattern := _rect(Vector2.ZERO, Vector2.ZERO, Color.TRANSPARENT)
		pattern.visible = false
		surface_pattern_nodes.append(pattern)
	_update_surface_visuals()

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
func _set_surface_pattern(index: int, pos: Vector2, size: Vector2,
		color: Color, rotation: float = 0.0) -> void:
	if index < 0 or index >= surface_pattern_nodes.size():
		return
	var pattern := surface_pattern_nodes[index]
	pattern.position = pos
	pattern.size = size
	pattern.color = color
	pattern.rotation = rotation
	pattern.visible = true

func _update_surface_visuals() -> void:
	if table_surface == null:
		return
	for pattern in surface_pattern_nodes:
		pattern.visible = false
	var x := TABLE_RECT.position.x
	var y := TABLE_RECT.position.y
	var w := TABLE_RECT.size.x
	var h := TABLE_RECT.size.y
	match selected_surface:
		0:
			table_surface.color = Color("#276a3e")
			for i in range(8):
				_set_surface_pattern(i, Vector2(x + i * 120.0, y), Vector2(120, h),
					Color(0.78, 1.0, 0.72, 0.07 if i % 2 == 0 else 0.015))
			_set_surface_pattern(8, Vector2(x + 28, y + 28), Vector2(w - 56, 3), Color(0.82, 1.0, 0.78, 0.24))
			_set_surface_pattern(9, Vector2(x + 28, y + h - 31), Vector2(w - 56, 3), Color(0.82, 1.0, 0.78, 0.24))
			for i in range(10):
				_set_surface_pattern(10 + i, Vector2(x, y + 150.0 + i * 128.0), Vector2(w, 2),
					Color(0.86, 1.0, 0.83, 0.065))
		1:
			table_surface.color = Color("#b27a48")
			for i in range(12):
				_set_surface_pattern(i, Vector2(x + i * 80.0, y), Vector2(3, h), Color(0.30, 0.15, 0.08, 0.27))
			for i in range(9):
				_set_surface_pattern(12 + i, Vector2(x, y + i * 180.0), Vector2(w, 2), Color(1.0, 0.78, 0.48, 0.12))
		2:
			table_surface.color = Color("#41474b")
			for i in range(80):
				var px := x + fposmod(i * 137.0, w - 8.0)
				var py := y + fposmod(i * 271.0, h - 8.0)
				_set_surface_pattern(i, Vector2(px, py), Vector2(3 + i % 3, 2 + i % 2), Color(0.85, 0.88, 0.85, 0.14))
			for i in range(12):
				_set_surface_pattern(80 + i, Vector2(x + 35 + i * 75.0, y + 86), Vector2(38, 4), Color(0.9, 0.84, 0.66, 0.34))
		3:
			table_surface.color = Color("#764d2b")
			for i in range(1, 9):
				_set_surface_pattern(i - 1, Vector2(x + i * 120.0, y), Vector2(3, h), Color(0.31, 0.18, 0.09, 0.45))
			for i in range(20):
				_set_surface_pattern(8 + i, Vector2(x, y + i * 78.0), Vector2(w, 2), Color(0.93, 0.66, 0.36, 0.055))
		4:
			table_surface.color = Color("#174b59")
			for i in range(6):
				_set_surface_pattern(i, Vector2(x + 52 + i * 166.0, y), Vector2(9, h), Color(0.75, 0.96, 1.0, 0.13))
			for i in range(6):
				_set_surface_pattern(6 + i, Vector2(x + i * 150.0, y + 90), Vector2(24, h - 180), Color(0.48, 0.85, 0.95, 0.06), -0.10)
		5:
			table_surface.color = Color("#762e3c")
			_set_surface_pattern(0, Vector2(x + 24, y + 24), Vector2(w - 48, 5), Color("#e0b66d"))
			_set_surface_pattern(1, Vector2(x + 24, y + h - 29), Vector2(w - 48, 5), Color("#e0b66d"))
			_set_surface_pattern(2, Vector2(x + 24, y + 24), Vector2(5, h - 48), Color("#e0b66d"))
			_set_surface_pattern(3, Vector2(x + w - 29, y + 24), Vector2(5, h - 48), Color("#e0b66d"))
			for i in range(72):
				var px := x + 78 + fposmod(i * 83.0, w - 140)
				var py := y + 80 + fposmod(i * 127.0, h - 150)
				_set_surface_pattern(4 + i, Vector2(px, py), Vector2(8, 8), Color(1.0, 0.79, 0.43, 0.37), PI * 0.25)
		6:
			table_surface.color = Color("#35474c")
			for i in range(90):
				var px := x + fposmod(i * 19.0, w - 4.0)
				var py := y + fposmod(i * 103.0, h - 2.0)
				_set_surface_pattern(i, Vector2(px, py), Vector2(2, 20), Color(0.88, 0.93, 0.87, 0.095))

func _build_walls() -> void:
	var t := WALL_THICKNESS
	var left := TABLE_RECT.position.x
	var right := TABLE_RECT.end.x
	var top := TABLE_RECT.position.y
	var bottom := TABLE_RECT.end.y
	var mouth_l := GOAL_RECT.position.x
	var mouth_r := GOAL_RECT.end.x

	_add_wall(Vector2(left - t * 0.5, (top + bottom) * 0.5), Vector2(t, bottom - top + t * 2.0))
	_add_wall(Vector2(right + t * 0.5, (top + bottom) * 0.5), Vector2(t, bottom - top + t * 2.0))
	_add_wall(Vector2((left + right) * 0.5, bottom + t * 0.5), Vector2(right - left + t * 2.0, t))
	_add_wall(Vector2((left + mouth_l) * 0.5, top - t * 0.5), Vector2(mouth_l - left + t, t))
	_add_wall(Vector2((mouth_r + right) * 0.5, top - t * 0.5), Vector2(right - mouth_r + t, t))
	# دیوارهٔ پشتی تور؛ توپ بعد از گل از قاب دروازه خارج نمی‌شود.
	_add_wall(Vector2(GOAL_RECT.get_center().x, GOAL_RECT.position.y - t * 0.5),
		Vector2(GOAL_RECT.size.x, t), "GoalBackstop", 0.12)

func _add_wall(
		center: Vector2, size: Vector2, node_name: String = "", bounce: float = 0.55
) -> void:
	var wall := StaticBody2D.new()
	if node_name != "":
		wall.name = node_name
	wall.position = center
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	wall.add_child(col)
	var mat := PhysicsMaterial.new()
	mat.bounce = bounce
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
	_rect(Vector2(GOAL_RECT.position.x, GOAL_RECT.position.y - WALL_THICKNESS),
		Vector2(GOAL_RECT.size.x, WALL_THICKNESS), Color(0.13, 0.34, 0.23))

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
	p1_score_label.clip_text = true
	p2_score_label = _label(hud_root, Vector2.ZERO, 20, Color(1.0, 0.78, 0.78))
	p2_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p2_score_label.clip_text = true
	p1_score_value = _label(hud_root, Vector2.ZERO, 34, Color.WHITE)
	p1_score_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p2_score_value = _label(hud_root, Vector2.ZERO, 34, Color.WHITE)
	p2_score_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_info_label = _label(hud_root, Vector2.ZERO, 25, Color(0.98, 0.96, 0.90))
	turn_info_label.clip_text = true
	status_label = _label(hud_root, Vector2.ZERO, 22, Color(1.0, 0.90, 0.56))
	status_label.clip_text = true

	goal_meter_bg = ColorRect.new()
	goal_meter_bg.color = Color(1, 1, 1, 0.16)
	goal_meter_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(goal_meter_bg)
	goal_meter = ColorRect.new()
	goal_meter.color = Color(1.0, 0.35, 0.35)
	goal_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(goal_meter)

	menu_button = _new_button(hud_root, "منو  ☰")
	_style_button(menu_button, Color(0.30, 0.22, 0.13, 1.0))
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
	var glow_gradient := Gradient.new()
	glow_gradient.colors = PackedColorArray([
		Color(0.58, 0.34, 0.13, 0.42), Color(0.10, 0.07, 0.05, 0.0)
	])
	var glow_texture := GradientTexture2D.new()
	glow_texture.gradient = glow_gradient
	glow_texture.width = 512
	glow_texture.height = 512
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.42)
	glow_texture.fill_to = Vector2(0.95, 0.95)
	var glow_rect := TextureRect.new()
	glow_rect.texture = glow_texture
	glow_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow_rect.stretch_mode = TextureRect.STRETCH_SCALE
	glow_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_overlay.add_child(glow_rect)
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
	menu_emblem.text = "●  ─  ●  ─  ●"
	menu_emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_row_panels.clear()
	for _row_index in range(2):
		var row_panel := Panel.new()
		row_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_panel.add_theme_stylebox_override("panel", _panel_style(
			Color(0.035, 0.045, 0.055, 0.72), Color(0.88, 0.70, 0.40, 0.20), 20))
		menu_panel.add_child(row_panel)
		menu_row_panels.append(row_panel)
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
	score_target_label = _label(menu_panel, Vector2.ZERO, 26, Color(1.0, 0.88, 0.62))
	score_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_down_button = _new_button(menu_panel, "−")
	score_down_button.pressed.connect(_change_winning_score.bind(-1))
	score_up_button = _new_button(menu_panel, "+")
	score_up_button.pressed.connect(_change_winning_score.bind(1))
	professional_button = _new_button(menu_panel, "✦ بازی حرفه‌ای · فلیک + فشار لمس")
	professional_button.tooltip_text = "در دستگاه‌های پشتیبان، فشار انگشت قدرت را تعیین می‌کند؛ در غیر این صورت فلیک سریع."
	professional_button.pressed.connect(_on_professional_mode_pressed)
	surface_cycle_button = _new_button(menu_panel, "🏟 زمین: میز چوبی · لمس برای تغییر")
	surface_cycle_button.pressed.connect(_cycle_surface)
	tournament_kind_button = _new_button(menu_panel, "جام ملت‌ها · لمس برای انتخاب جام باشگاه‌ها")
	tournament_kind_button.pressed.connect(_cycle_tournament_kind)
	tournament_team1_button = _new_button(menu_panel, "آبی · ایران")
	tournament_team1_button.pressed.connect(_cycle_tournament_team.bind(0))
	tournament_team2_button = _new_button(menu_panel, "قرمز · ژاپن")
	tournament_team2_button.pressed.connect(_cycle_tournament_team.bind(1))
	tournament_start_button = _new_button(menu_panel, "🏆 شروع جام حذفی دونفره · بهترین از ۳ بازی")
	tournament_start_button.pressed.connect(_on_tournament_start_pressed)
	start_game_button = _new_button(menu_panel, "شروع بازی")
	_style_button(start_game_button, Color(0.43, 0.25, 0.10, 1.0))
	_style_button(professional_button, Color(0.48, 0.30, 0.11, 1.0))
	_style_button(surface_cycle_button, Color(0.14, 0.18, 0.18, 1.0))
	_style_button(tournament_kind_button, Color(0.10, 0.20, 0.27, 1.0))
	_style_button(tournament_team1_button, Color(0.07, 0.17, 0.27, 1.0))
	_style_button(tournament_team2_button, Color(0.28, 0.10, 0.13, 1.0))
	_style_button(tournament_start_button, Color(0.10, 0.32, 0.40, 1.0))
	_style_button(moves_down_button, Color(0.16, 0.14, 0.12, 1.0))
	_style_button(moves_up_button, Color(0.16, 0.14, 0.12, 1.0))
	_style_button(score_down_button, Color(0.16, 0.14, 0.12, 1.0))
	_style_button(score_up_button, Color(0.16, 0.14, 0.12, 1.0))
	start_game_button.pressed.connect(_on_start_game_pressed)

	exit_confirmation = ConfirmationDialog.new()
	exit_confirmation.title = "خروج از بازی؟"
	exit_confirmation.dialog_text = "می‌خواهید از سه‌توپ خارج شوید؟"
	exit_confirmation.ok_button_text = "خروج"
	exit_confirmation.confirmed.connect(_on_exit_confirmed)
	add_child(exit_confirmation)
	exit_confirmation.get_cancel_button().text = "ماندن"

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
		+ "حرفه‌ای: یک فلیک رو به جلو بزنید؛ فشار لمس قدرت را می‌سازد، نه نگه‌داشتن انگشت.\n\n" \
		+ "۲) هر شوت باید از شکاف دو توپ دیگر رد شود؛ برخورد با توپ یا نرسیدن به شکاف خطاست.\n\n" \
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
	_build_victory_overlay()

	_refresh_layout()

func _build_victory_overlay() -> void:
	victory_overlay = ColorRect.new()
	victory_overlay.color = Color(0.015, 0.02, 0.025, 0.84)
	victory_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	victory_overlay.visible = false
	hud_root.add_child(victory_overlay)
	victory_panel = Panel.new()
	victory_panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.075, 0.085, 0.095, 0.99), Color(0.95, 0.72, 0.32, 0.88), 30))
	victory_overlay.add_child(victory_panel)
	victory_cup = _label(victory_panel, Vector2.ZERO, 54, Color(1.0, 0.82, 0.40))
	victory_cup.text = "🏆"
	victory_cup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_title = _label(victory_panel, Vector2.ZERO, 40, Color(1.0, 0.85, 0.52))
	victory_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_summary = _label(victory_panel, Vector2.ZERO, 24, Color(0.95, 0.91, 0.84))
	victory_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_replay_button = _new_button(victory_panel, "بازی دوباره")
	victory_menu_button = _new_button(victory_panel, "بازگشت به منو")
	_style_button(victory_replay_button, Color(0.44, 0.29, 0.12, 1.0))
	_style_button(victory_menu_button, Color(0.16, 0.18, 0.20, 1.0))
	victory_replay_button.pressed.connect(_on_victory_replay_pressed)
	victory_menu_button.pressed.connect(_show_main_menu)

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
		_layout_label(p1_score_value, Rect2(origin + Vector2(22, 5) * scale_ui,
			Vector2(76, 42) * scale_ui), roundi(26 * scale_ui))
		_layout_label(p2_score_value, Rect2(origin + Vector2(22, 60) * scale_ui,
			Vector2(76, 42) * scale_ui), roundi(26 * scale_ui))
		_layout_label(p1_score_label, Rect2(origin + Vector2(102, 5) * scale_ui,
			Vector2(181, 42) * scale_ui), roundi(19 * scale_ui))
		_layout_label(p2_score_label, Rect2(origin + Vector2(102, 60) * scale_ui,
			Vector2(181, 42) * scale_ui), roundi(19 * scale_ui))
		top_info_card.position = origin + Vector2(315, 5) * scale_ui
		top_info_card.size = Vector2(650, 102) * scale_ui
		_layout_label(turn_info_label, Rect2(origin + Vector2(335, 7) * scale_ui,
			Vector2(590, 42) * scale_ui), roundi(22 * scale_ui))
		_layout_label(status_label, Rect2(origin + Vector2(335, 50) * scale_ui,
			Vector2(600, 36) * scale_ui), roundi(18 * scale_ui))
		goal_meter_bg.position = origin + Vector2(330, 96) * scale_ui
		goal_meter_bg.size = Vector2(250, 9) * scale_ui
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
		_layout_label(p1_score_value, Rect2(origin + Vector2(20, 5) * scale_ui,
			Vector2(82, 51) * scale_ui), roundi(27 * scale_ui))
		_layout_label(p2_score_value, Rect2(origin + Vector2(20, 66) * scale_ui,
			Vector2(82, 51) * scale_ui), roundi(27 * scale_ui))
		_layout_label(p1_score_label, Rect2(origin + Vector2(108, 5) * scale_ui,
			Vector2(184, 51) * scale_ui), roundi(20 * scale_ui))
		_layout_label(p2_score_label, Rect2(origin + Vector2(108, 66) * scale_ui,
			Vector2(184, 51) * scale_ui), roundi(20 * scale_ui))
		top_info_card.position = origin + Vector2(310, 5) * scale_ui
		top_info_card.size = Vector2(435, 92) * scale_ui
		_layout_label(turn_info_label, Rect2(origin + Vector2(326, 8) * scale_ui,
			Vector2(405, 41) * scale_ui), roundi(20 * scale_ui))
		_layout_label(status_label, Rect2(origin + Vector2(326, 49) * scale_ui,
			Vector2(405, 38) * scale_ui), roundi(17 * scale_ui))
		goal_meter_bg.position = origin + Vector2(315, 101) * scale_ui
		goal_meter_bg.size = Vector2(240, 9) * scale_ui
		menu_button.position = origin + Vector2(968, 18) * scale_ui
		menu_button.size = Vector2(94, 82) * scale_ui
		_layout_label(banner_label, Rect2(origin + Vector2(120, 890) * scale_ui,
			Vector2(840, 120) * scale_ui), roundi(48 * scale_ui))
		_layout_label(toast_label, Rect2(origin + Vector2(60, 1820) * scale_ui,
			Vector2(960, 60) * scale_ui), roundi(20 * scale_ui))
	goal_meter.position = goal_meter_bg.position
	goal_meter.size.y = goal_meter_bg.size.y
	menu_button.add_theme_font_size_override("font_size", roundi(20 * scale_ui))
	_layout_menu(view_size, landscape)
	_layout_victory(view_size)

func _layout_victory(view_size: Vector2) -> void:
	if victory_overlay == null:
		return
	victory_overlay.position = Vector2.ZERO
	victory_overlay.size = view_size
	var ui_scale := minf(minf(view_size.x / 720.0, view_size.y / 500.0), 1.0)
	ui_scale = maxf(ui_scale, 0.48)
	var panel_size := Vector2(680, 460) * ui_scale
	victory_panel.position = (view_size - panel_size) * 0.5
	victory_panel.size = panel_size
	victory_cup.position = Vector2(30, 24) * ui_scale
	victory_cup.size = Vector2(620, 72) * ui_scale
	victory_cup.add_theme_font_size_override("font_size", roundi(52 * ui_scale))
	victory_title.position = Vector2(28, 100) * ui_scale
	victory_title.size = Vector2(624, 76) * ui_scale
	victory_title.add_theme_font_size_override("font_size", roundi(38 * ui_scale))
	victory_summary.position = Vector2(34, 190) * ui_scale
	victory_summary.size = Vector2(612, 70) * ui_scale
	victory_summary.add_theme_font_size_override("font_size", roundi(22 * ui_scale))
	victory_replay_button.position = Vector2(45, 320) * ui_scale
	victory_replay_button.size = Vector2(280, 72) * ui_scale
	victory_menu_button.position = Vector2(355, 320) * ui_scale
	victory_menu_button.size = Vector2(280, 72) * ui_scale
	victory_replay_button.add_theme_font_size_override("font_size", roundi(22 * ui_scale))
	victory_menu_button.add_theme_font_size_override("font_size", roundi(22 * ui_scale))

func _layout_menu(view_size: Vector2, landscape: bool) -> void:
	menu_overlay.position = Vector2.ZERO
	menu_overlay.size = view_size
	var panel_ref := Vector2(980, 1010) if landscape else Vector2(860, 1020)
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
	menu_row_panels[0].position = Vector2(80, 258) * panel_scale
	menu_row_panels[0].size = Vector2(panel_ref.x - 160, 94) * panel_scale
	menu_row_panels[1].position = Vector2(80, 358) * panel_scale
	menu_row_panels[1].size = Vector2(panel_ref.x - 160, 82) * panel_scale
	_layout_label(move_count_label, Rect2(Vector2((panel_ref.x - 420) * 0.5, 274) * panel_scale,
		Vector2(420, 68) * panel_scale), roundi(30 * panel_scale))
	moves_down_button.position = Vector2(150, 270) * panel_scale
	moves_down_button.size = Vector2(100, 78) * panel_scale
	moves_up_button.position = Vector2(panel_ref.x - 250, 270) * panel_scale
	moves_up_button.size = Vector2(100, 78) * panel_scale
	moves_down_button.add_theme_font_size_override("font_size", roundi(36 * panel_scale))
	moves_up_button.add_theme_font_size_override("font_size", roundi(36 * panel_scale))
	var score_row_y := 366.0
	score_target_label.position = Vector2((panel_ref.x - 360) * 0.5, score_row_y) * panel_scale
	score_target_label.size = Vector2(360, 64) * panel_scale
	score_target_label.add_theme_font_size_override("font_size", roundi(25 * panel_scale))
	score_down_button.position = Vector2((panel_ref.x - 560) * 0.5, score_row_y - 2) * panel_scale
	score_down_button.size = Vector2(100, 68) * panel_scale
	score_up_button.position = Vector2(panel_ref.x - (panel_ref.x - 560) * 0.5 - 100,
		score_row_y - 2) * panel_scale
	score_up_button.size = Vector2(100, 68) * panel_scale
	score_down_button.add_theme_font_size_override("font_size", roundi(32 * panel_scale))
	score_up_button.add_theme_font_size_override("font_size", roundi(32 * panel_scale))
	professional_button.position = Vector2(100, 464) * panel_scale
	professional_button.size = Vector2(panel_ref.x - 200, 64) * panel_scale
	professional_button.add_theme_font_size_override("font_size", roundi(18 * panel_scale))
	surface_cycle_button.position = Vector2(100, 540) * panel_scale
	surface_cycle_button.size = Vector2(panel_ref.x - 200, 54) * panel_scale
	surface_cycle_button.add_theme_font_size_override("font_size", roundi(17 * panel_scale))
	tournament_kind_button.position = Vector2(100, 602) * panel_scale
	tournament_kind_button.size = Vector2(panel_ref.x - 200, 54) * panel_scale
	tournament_kind_button.add_theme_font_size_override("font_size", roundi(17 * panel_scale))
	tournament_team1_button.position = Vector2(100, 664) * panel_scale
	tournament_team1_button.size = Vector2((panel_ref.x - 220) * 0.5, 50) * panel_scale
	tournament_team2_button.position = Vector2(120 + (panel_ref.x - 220) * 0.5, 664) * panel_scale
	tournament_team2_button.size = tournament_team1_button.size
	tournament_team1_button.add_theme_font_size_override("font_size", roundi(16 * panel_scale))
	tournament_team2_button.add_theme_font_size_override("font_size", roundi(16 * panel_scale))
	tournament_start_button.position = Vector2(100, 722) * panel_scale
	tournament_start_button.size = Vector2(panel_ref.x - 200, 62) * panel_scale
	tournament_start_button.add_theme_font_size_override("font_size", roundi(16 * panel_scale))
	start_game_button.position = Vector2(72, panel_ref.y - 96) * panel_scale
	start_game_button.size = Vector2(panel_ref.x - 144, 70) * panel_scale
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

func _load_winning_score() -> void:
	var settings := ConfigFile.new()
	if settings.load(USER_SETTINGS_PATH) == OK:
		winning_score = clampi(settings.get_value("game", "winning_score", DEFAULT_WINNING_SCORE),
			MIN_WINNING_SCORE, MAX_WINNING_SCORE)
		selected_surface = clampi(settings.get_value("game", "surface", 3), 0, SURFACE_IDS.size() - 1)
		tournament_kind = clampi(settings.get_value("game", "tournament_kind", 0), 0, 1)
		var saved_teams: Array = settings.get_value("game", "teams", [0, 1])
		if saved_teams.size() >= 2:
			tournament_team_indices = [clampi(saved_teams[0], 0, 7), clampi(saved_teams[1], 0, 7)]

func _save_winning_score() -> void:
	var settings := ConfigFile.new()
	settings.load(USER_SETTINGS_PATH)
	settings.set_value("game", "winning_score", winning_score)
	settings.set_value("game", "surface", selected_surface)
	settings.set_value("game", "tournament_kind", tournament_kind)
	settings.set_value("game", "teams", tournament_team_indices)
	settings.save(USER_SETTINGS_PATH)

func _tournament_team_pool() -> Array:
	return CLUB_TEAMS if tournament_kind == 1 else NATIONAL_TEAMS

func _player_display_name(player_idx: int) -> String:
	if tournament_mode:
		var pool := _tournament_team_pool()
		return str(pool[tournament_team_indices[player_idx - 1]])
	return "بازیکن %s" % _fa(player_idx)

func _refresh_tournament_menu() -> void:
	if surface_cycle_button == null:
		return
	surface_cycle_button.text = "🏟 جنس زمین: %s  ·  لمس برای تغییر" % SURFACE_NAMES[selected_surface]
	tournament_kind_button.text = "جام باشگاه‌ها · تغییر به جام ملت‌ها" if tournament_kind == 1 \
		else "جام ملت‌ها · تغییر به جام باشگاه‌ها"
	var teams := _tournament_team_pool()
	tournament_team1_button.text = "آبی · %s" % teams[tournament_team_indices[0]]
	tournament_team2_button.text = "قرمز · %s" % teams[tournament_team_indices[1]]

func _cycle_surface() -> void:
	selected_surface = (selected_surface + 1) % SURFACE_IDS.size()
	_update_surface_visuals()
	_save_winning_score()
	_refresh_tournament_menu()

func _cycle_tournament_kind() -> void:
	tournament_kind = 1 - tournament_kind
	tournament_team_indices = [0, 1]
	_save_winning_score()
	_refresh_tournament_menu()

func _cycle_tournament_team(player_idx: int) -> void:
	var teams := _tournament_team_pool()
	tournament_team_indices[player_idx] = (tournament_team_indices[player_idx] + 1) % teams.size()
	if tournament_team_indices[0] == tournament_team_indices[1]:
		tournament_team_indices[player_idx] = (tournament_team_indices[player_idx] + 1) % teams.size()
	_save_winning_score()
	_refresh_tournament_menu()

func _on_tournament_start_pressed() -> void:
	professional_mode = false
	tournament_mode = true
	tournament_wins = [0, 0]
	tournament_match = 1
	_launch_configured_game()

func _update_move_count_label() -> void:
	if move_count_label != null:
		move_count_label.text = "تعداد حرکت مجاز: %s" % _fa(configured_moves)
	if score_target_label != null:
		score_target_label.text = "هدف قهرمانی: %s گل" % _fa(winning_score)
	if moves_down_button != null:
		moves_down_button.disabled = configured_moves <= _minimum_configured_moves()
	if moves_up_button != null:
		moves_up_button.disabled = configured_moves >= MAX_MOVES_PER_TURN
	if score_down_button != null:
		score_down_button.disabled = winning_score <= MIN_WINNING_SCORE
	if score_up_button != null:
		score_up_button.disabled = winning_score >= MAX_WINNING_SCORE
	if surface_cycle_button != null:
		_refresh_tournament_menu()

func _change_configured_moves(amount: int) -> void:
	configured_moves = clampi(configured_moves + amount,
		_minimum_configured_moves(), MAX_MOVES_PER_TURN)
	_update_move_count_label()

func _change_winning_score(amount: int) -> void:
	winning_score = clampi(winning_score + amount, MIN_WINNING_SCORE, MAX_WINNING_SCORE)
	_save_winning_score()
	_update_move_count_label()

func _show_main_menu() -> void:
	state = GameState.MENU
	tournament_mode = false
	if victory_overlay != null:
		victory_overlay.visible = false
	professional_mode = false
	goal_meter_bg.visible = true
	goal_meter.visible = true
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
	tournament_mode = false
	professional_mode = false
	_launch_configured_game()

func _on_professional_mode_pressed() -> void:
	tournament_mode = false
	professional_mode = true
	configured_moves = maxi(configured_moves, PROFESSIONAL_MIN_MOVES)
	_update_move_count_label()
	_launch_configured_game()

func _launch_configured_game() -> void:
	moves_per_turn = configured_moves
	goal_meter_bg.visible = not professional_mode
	goal_meter.visible = not professional_mode
	if professional_mode:
		aim_line.visible = false
		aim_tip.visible = false
		target_gate_line.visible = false
		goal_meter.size.x = 0.0
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

func _show_victory_screen() -> void:
	victory_title.text = ("قهرمان جام: %s" if tournament_mode else "قهرمان: %s") \
		% _player_display_name(current_player)
	if tournament_mode:
		victory_summary.text = "نتیجهٔ سری حذفی: %s — %s" % [
			_fa(tournament_wins[current_player - 1]), _fa(tournament_wins[1 if current_player == 1 else 0])
		]
	else:
		victory_summary.text = "نتیجهٔ نهایی  %s  —  %s گل" % [
			_fa(scores[current_player - 1]), _fa(winning_score)
		]
	victory_overlay.visible = true
	_spawn_paper_confetti()

func _on_victory_replay_pressed() -> void:
	victory_overlay.visible = false
	if tournament_mode:
		tournament_wins = [0, 0]
		tournament_match = 1
	_start_new_match()

func _spawn_paper_confetti() -> void:
	var palette := [Color(1.0, 0.85, 0.48), Color(0.40, 0.78, 1.0),
		Color(1.0, 0.42, 0.44), Color(0.38, 0.91, 0.63), Color(0.83, 0.62, 1.0)]
	var view_size := get_viewport().get_visible_rect().size
	for i in range(110):
		var piece := ColorRect.new()
		piece.color = palette[i % palette.size()]
		piece.size = Vector2(randf_range(7.0, 15.0), randf_range(4.0, 9.0))
		piece.position = Vector2(randf_range(0.0, view_size.x), randf_range(-120.0, 150.0))
		piece.rotation = randf_range(-PI, PI)
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_root.add_child(piece)
		var duration := randf_range(1.8, 3.0)
		var target := piece.position + Vector2(randf_range(-240.0, 240.0), randf_range(480.0, 1100.0))
		var tw := create_tween().set_parallel(true)
		tw.tween_property(piece, "position", target, duration).set_trans(Tween.TRANS_SINE)
		tw.tween_property(piece, "rotation", piece.rotation + randf_range(-12.0, 12.0), duration)
		tw.tween_property(piece, "modulate:a", 0.0, duration * 0.5).set_delay(duration * 0.5)
		get_tree().create_timer(duration).timeout.connect(piece.queue_free)

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
		ball.linear_damp = SURFACE_DAMPING[selected_surface]
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
	_start_turn(2 if tournament_mode and tournament_match % 2 == 0 else 1)
	_show_toast("")

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
	_show_banner("نوبت %s" % _player_display_name(current_player),
		Color(0.45, 0.80, 1.0) if current_player == 1 else Color(1.0, 0.52, 0.52))
	_update_hud()

func _switch_turn() -> void:
	_start_turn(2 if current_player == 1 else 1)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_request()

func _handle_back_request() -> void:
	if exit_confirmation != null and exit_confirmation.visible:
		return
	if tutorial_overlay != null and tutorial_overlay.visible:
		tutorial_overlay.visible = false
		menu_overlay.visible = true
		state = GameState.MENU
	elif state != GameState.MENU:
		_show_main_menu()
	elif exit_confirmation != null:
		exit_confirmation.popup_centered()

func _on_exit_confirmed() -> void:
	get_tree().quit()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_action_pressed("ui_cancel"):
		_handle_back_request()
		get_viewport().set_input_as_handled()
		return
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
			_begin_drag(pos, event)
		elif is_dragging:
			_end_drag(pos, event)
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and is_dragging:
		_update_drag(pos, event)

func _begin_drag(pos: Vector2, event: InputEvent) -> void:
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
		pro_touch_pressure_min = 1.0
		pro_touch_pressure_max = 0.0
		pro_touch_pressure_samples = 0
		pro_peak_flick_speed = 0.0
		pro_last_sample_pos = pos
		pro_last_sample_time_usec = Time.get_ticks_usec()
		_sample_professional_input(pos, event)
		if not professional_mode:
			_update_target_gate_preview(best)
		_play_sfx(720.0, 760.0, 0.05, -22.0)

func _update_drag(pos: Vector2, event: InputEvent) -> void:
	_sample_professional_input(pos, event)
	drag_current_pos = pos
	if professional_mode:
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
	aim_line.points = PackedVector2Array([
		drag_ball.global_position,
		drag_ball.global_position + pull
	])
	aim_tip.position = drag_ball.global_position + pull
	aim_tip.rotation = pull.angle()

func _sample_professional_input(pos: Vector2, event: InputEvent) -> void:
	var now_usec := Time.get_ticks_usec()
	var elapsed := maxf(float(now_usec - pro_last_sample_time_usec) / 1000000.0, 0.004)
	pro_peak_flick_speed = maxf(pro_peak_flick_speed,
		pos.distance_to(pro_last_sample_pos) / elapsed)
	var pressure := 0.0
	if event is InputEventScreenTouch:
		pressure = event.pressure
	elif event is InputEventScreenDrag:
		pressure = event.pressure
	if pressure > 0.01:
		pro_touch_pressure_min = minf(pro_touch_pressure_min, pressure)
		pro_touch_pressure_max = maxf(pro_touch_pressure_max, pressure)
		pro_touch_pressure_samples += 1
	pro_last_sample_pos = pos
	pro_last_sample_time_usec = now_usec

func _professional_shot_power(has_pressure: bool, pressure: float, peak_speed: float) -> float:
	var intensity := clampf(peak_speed / 1500.0, 0.0, 1.0)
	if has_pressure:
		intensity = clampf((pressure - 0.04) / 0.96, 0.0, 1.0)
	return lerpf(220.0, MAX_DRAG_DIST * IMPULSE_MULTIPLIER,
		pow(intensity, 1.15))

func _professional_shot_impulse(swipe: Vector2, has_pressure: bool = false,
		pressure: float = 0.0, peak_speed: float = 0.0) -> Vector2:
	if swipe.length_squared() < 0.001:
		return Vector2.ZERO
	return swipe.normalized() * _professional_shot_power(has_pressure, pressure, peak_speed)

func _end_drag(pos: Vector2, event: InputEvent) -> void:
	_sample_professional_input(pos, event)
	is_dragging = false
	aim_line.visible = false
	aim_tip.visible = false
	target_gate_line.visible = false
	if drag_ball == null:
		return
	if professional_mode:
		var swipe := pos - drag_start_pos
		if swipe.length() > MIN_SHOT_DRAG_DIST:
			var pressure_range := pro_touch_pressure_max - pro_touch_pressure_min
			var pressure_supported := pro_touch_pressure_samples >= 2 \
				and (pressure_range >= 0.04 or pro_touch_pressure_max < 0.43 \
				or pro_touch_pressure_max > 0.57)
			_shoot_ball(drag_ball, _professional_shot_impulse(swipe,
				pressure_supported, pro_touch_pressure_max, pro_peak_flick_speed))
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
	shot_physics_frames = 0

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
			for b in balls:
				b.sleeping = true
			state = GameState.WAITING_FOR_INPUT
			status_label.text = ""
			_update_hud()
		return
	if state != GameState.BALLS_MOVING or active_ball == null:
		return

	# apply_central_impulse is integrated after this frame's script callbacks.
	# Ignore the pre-integration zero velocities so every shot is not judged
	# as a stationary foul before the physics server applies its impulse.
	shot_physics_frames += 1
	if shot_physics_frames == 1:
		prev_active_pos = active_ball.global_position
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

	# عبور از شکاف را پیش از داوری گل/خروج ثبت می‌کنیم.
	if not gap_crossed and pass_line_valid:
		if Geometry2D.segment_intersects_segment(
				prev_active_pos, cur, pass_line_a, pass_line_b) != null:
			gap_crossed = true
			_play_sfx(540.0, 780.0, 0.09)

	# گل هم فقط با پاس معتبر و عبور کامل توپ از خط دروازه ثبت می‌شود.
	if cur.y + BALL_RADIUS <= GOAL_RECT.end.y + 6.0 \
		and cur.x >= GOAL_RECT.position.x + BALL_RADIUS \
		and cur.x <= GOAL_RECT.end.x - BALL_RADIUS \
		and _is_gate_open_for(cur):
		if not gap_crossed:
			_finish_shot(ShotKind.FOUL, "توپ باید از شکاف بین دو توپ عبور کند؛ نوبت سوخت.")
		elif professional_mode and _current_turn_move_number() < PROFESSIONAL_MIN_MOVES:
			_finish_shot(ShotKind.FOUL, _professional_early_goal_message())
		else:
			_finish_shot(ShotKind.GOAL)
		return
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
	if not gap_crossed:
		_finish_shot(ShotKind.FOUL, "توپ باید از شکاف بین دو توپ عبور کند؛ نوبت سوخت.")
		return
	var opened := false
	for b in balls:
		if b.global_position.y < _attack_line_y():
			opened = true
			break
	if opened:
		_set_gate(true)
	_finish_shot(ShotKind.PASS)

func _professional_early_goal_message() -> String:
	var messages := [
		"عجله نکن، مرد! گل از حرکت سوم حساب می‌شود؛ نوبت سوخت.",
		"یواش قهرمان! هنوز حرکت سوم نرسیده؛ گل قبول نیست!",
		"چه عجله‌ای! اول سه حرکت، بعد جشن گل؛ نوبت سوخت."
	]
	return messages.pick_random()

func _finish_shot(kind: ShotKind, foul_reason: String = "") -> void:
	match kind:
		ShotKind.GOAL:
			scores[current_player - 1] += 1
			goal_particles.restart()
			_trigger_shake(14.0)
			_play_sfx(440.0, 900.0, 0.24)
			_update_hud()
			if scores[current_player - 1] >= winning_score and tournament_mode:
				_finish_tournament_match()
			elif scores[current_player - 1] >= winning_score:
				state = GameState.MATCH_OVER
				status_label.text = "%s برنده شد!" % _player_display_name(current_player)
				_show_banner("قهرمان: %s" % _player_display_name(current_player), Color(0.3, 1.0, 0.5))
				_show_victory_screen()
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

	# هر پاس موفق یک حرکت از سهمیه کم می‌کند.
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

func _finish_tournament_match() -> void:
	tournament_wins[current_player - 1] += 1
	_update_hud()
	if tournament_wins[current_player - 1] >= 2:
		state = GameState.MATCH_OVER
		status_label.text = "%s قهرمان جام شد!" % _player_display_name(current_player)
		_show_banner("قهرمان جام: %s" % _player_display_name(current_player), Color(0.3, 1.0, 0.5))
		_show_victory_screen()
		return
	state = GameState.TRANSITION
	status_label.text = "%s این بازی را برد؛ یک برد تا جام!" % _player_display_name(current_player)
	_show_banner("یک برد تا جام!", Color(1.0, 0.82, 0.38))
	_delayed_tournament_match(2.0)

func _delayed_tournament_match(delay_sec: float) -> void:
	await get_tree().create_timer(delay_sec).timeout
	if state == GameState.TRANSITION and tournament_mode:
		tournament_match += 1
		_start_new_match()

func _after_mistake(reason: String) -> void:
	state = GameState.TRANSITION
	status_label.text = reason
	if reason.begins_with("عجله") or reason.begins_with("یواش") \
			or reason.begins_with("چه عجله‌ای"):
		_show_banner("عجله نکن، مرد!", Color(1.0, 0.75, 0.26))
	else:
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
	p1_score_label.text = "%s%s" % [mark1, _player_display_name(1)]
	p2_score_label.text = "%s%s" % [mark2, _player_display_name(2)]
	p1_score_value.text = "%s/%s" % [_fa(scores[0]), _fa(winning_score)]
	p2_score_value.text = "%s/%s" % [_fa(scores[1]), _fa(winning_score)]

	var gate_txt := "آزاد" if gate_open else "مسدود"
	var cup_score := " | جام %s–%s" % [_fa(tournament_wins[0]), _fa(tournament_wins[1])] \
		if tournament_mode else ""
	turn_info_label.text = "نوبت %s | حرکت %s/%s | مسیر %s%s" % [
		_player_display_name(current_player), _fa(moves_left), _fa(moves_per_turn), gate_txt, cup_score
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
