extends Node2D

enum GameState { WAITING_FOR_INPUT, BALLS_MOVING, TRANSITION, MATCH_OVER }

const TABLE_RECT := Rect2(60, 220, 960, 1520)
const ATTACK_LINE_Y := 720.0
const GOAL_RECT := Rect2(390, 140, 300, 80)
const BALL_RADIUS := 36.0
const MAX_DRAG_DIST := 300.0
const IMPULSE_MULTIPLIER := 5.8
const STOP_SPEED_THRESHOLD := 14.0
const WINNING_SCORE := 3

var state: GameState = GameState.WAITING_FOR_INPUT
var balls: Array[RigidBody2D] = []
var active_ball: RigidBody2D = null
var last_used_ball: RigidBody2D = null
var other_balls: Array[RigidBody2D] = []
var prev_active_pos: Vector2 = Vector2.ZERO

var is_dragging := false
var drag_current_pos := Vector2.ZERO
var passed_between := false
var hit_other_ball := false
var gate_is_open := false
var goal_scored_this_shot := false

var current_player: int = 1
var scores: Array[int] = [0, 0]
var moves_left: int = 3

var aim_line: Line2D
var target_gate_line: Line2D
var left_gate_door: StaticBody2D
var right_gate_door: StaticBody2D
var gate_led_left: ColorRect
var gate_led_right: ColorRect

var p1_score_label: Label
var p2_score_label: Label
var turn_info_label: Label
var status_label: Label
var center_banner: Label
var goal_particles: CPUParticles2D
var gate_particles: CPUParticles2D

var shake_strength: float = 0.0
var audio_player: AudioStreamPlayer

func _ready() -> void:
	randomize()
	_setup_audio()
	_build_table_and_environment()
	_build_smart_goal()
	_build_particles()
	_build_hud()
	_spawn_balls()
	_start_new_match()

func _setup_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.25
	audio_player.stream = gen
	add_child(audio_player)

func _play_sfx(freq_start: float, freq_end: float, duration: float, volume_db: float = -8.0) -> void:
	audio_player.volume_db = volume_db
	audio_player.play()
	var playback := audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var total_frames := int(22050.0 * duration)
	var phase := 0.0
	for i in range(min(total_frames, playback.get_frames_available())):
		var t := float(i) / float(max(total_frames, 1))
		var freq := lerpf(freq_start, freq_end, t)
		var env := (1.0 - t) * minf(t * 12.0, 1.0)
		phase = fmod(phase + freq / 22050.0, 1.0)
		var sample := sin(phase * TAU) * env * 0.45
		playback.push_frame(Vector2(sample, sample))

func _build_table_and_environment() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.08, 0.06)
	bg.size = Vector2(1080, 1920)
	add_child(bg)

	# سایه میز
	var table_shadow := ColorRect.new()
	table_shadow.color = Color(0.0, 0.0, 0.0, 0.45)
	table_shadow.position = TABLE_RECT.position + Vector2(14, 18)
	table_shadow.size = TABLE_RECT.size
	add_child(table_shadow)

	# حاشیه میز چوبی
	var table_border := ColorRect.new()
	table_border.color = Color(0.32, 0.19, 0.10)
	table_border.position = TABLE_RECT.position - Vector2(12, 12)
	table_border.size = TABLE_RECT.size + Vector2(24, 24)
	add_child(table_border)

	# سطح میز
	var table_surface := ColorRect.new()
	table_surface.color = Color(0.48, 0.31, 0.17)
	table_surface.position = TABLE_RECT.position
	table_surface.size = TABLE_RECT.size
	add_child(table_surface)

	# خطوط بافت چوب نیمکت مدرسه
	for i in range(1, 8):
		var grain := ColorRect.new()
		grain.color = Color(0.42, 0.26, 0.14, 0.45)
		grain.position = Vector2(TABLE_RECT.position.x + i * 120.0, TABLE_RECT.position.y)
		grain.size = Vector2(4, TABLE_RECT.size.y)
		add_child(grain)

	# رنگ‌آمیزی ناحیه یک‌سوم هجومی
	var attack_zone_tint := ColorRect.new()
	attack_zone_tint.color = Color(1.0, 0.85, 0.25, 0.05)
	attack_zone_tint.position = TABLE_RECT.position
	attack_zone_tint.size = Vector2(TABLE_RECT.size.x, ATTACK_LINE_Y - TABLE_RECT.position.y)
	add_child(attack_zone_tint)

	# خط یک‌سوم هجومی (بازکننده دروازه)
	var attack_line := Line2D.new()
	attack_line.points = PackedVector2Array([
		Vector2(TABLE_RECT.position.x, ATTACK_LINE_Y),
		Vector2(TABLE_RECT.end.x, ATTACK_LINE_Y)
	])
	attack_line.width = 5.0
	attack_line.default_color = Color(1.0, 0.88, 0.25, 0.65)
	add_child(attack_line)

	# خط راهنمای بین دو توپ دیگر (نگهدارنده شکاف پاس)
	target_gate_line = Line2D.new()
	target_gate_line.width = 6.0
	target_gate_line.default_color = Color(0.2, 0.9, 1.0, 0.55)
	target_gate_line.visible = false
	add_child(target_gate_line)

	# خط نشانگر کشیدن و قدرت شوت
	aim_line = Line2D.new()
	aim_line.width = 10.0
	aim_line.default_color = Color(0.2, 1.0, 0.4, 0.9)
	aim_line.visible = false
	add_child(aim_line)

func _build_smart_goal() -> void:
	var goal_frame := ColorRect.new()
	goal_frame.color = Color(0.08, 0.25, 0.16)
	goal_frame.position = GOAL_RECT.position - Vector2(14, 14)
	goal_frame.size = GOAL_RECT.size + Vector2(28, 14)
	add_child(goal_frame)

	var goal_net := ColorRect.new()
	goal_net.color = Color(0.12, 0.50, 0.30)
	goal_net.position = GOAL_RECT.position
	goal_net.size = GOAL_RECT.size
	add_child(goal_net)

	# چراغ‌های وضعیت دروازه برقی
	gate_led_left = ColorRect.new()
	gate_led_left.position = Vector2(360, 195)
	gate_led_left.size = Vector2(20, 20)
	add_child(gate_led_left)

	gate_led_right = ColorRect.new()
	gate_led_right.position = Vector2(700, 195)
	gate_led_right.size = Vector2(20, 20)
	add_child(gate_led_right)

	left_gate_door = _create_gate_door(Vector2(390, 204))
	right_gate_door = _create_gate_door(Vector2(540, 204))

func _create_gate_door(pos: Vector2) -> StaticBody2D:
	var door := StaticBody2D.new()
	door.position = pos

	var rect := ColorRect.new()
	rect.size = Vector2(150, 24)
	rect.color = Color(0.85, 0.18, 0.22)
	door.add_child(rect)

	var stripe := ColorRect.new()
	stripe.position = Vector2(10, 9)
	stripe.size = Vector2(130, 6)
	stripe.color = Color(1.0, 0.75, 0.2, 0.9)
	door.add_child(stripe)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(150, 24)
	col.position = Vector2(75, 12)
	col.shape = shape
	door.add_child(col)

	add_child(door)
	return door

func _build_particles() -> void:
	goal_particles = CPUParticles2D.new()
	goal_particles.position = Vector2(540, 180)
	goal_particles.emitting = false
	goal_particles.one_shot = true
	goal_particles.explosiveness = 0.9
	goal_particles.amount = 45
	goal_particles.lifetime = 1.1
	goal_particles.direction = Vector2(0, 1)
	goal_particles.spread = 90.0
	goal_particles.initial_velocity_min = 220.0
	goal_particles.initial_velocity_max = 520.0
	goal_particles.scale_amount_min = 8.0
	goal_particles.scale_amount_max = 16.0
	goal_particles.color = Color(1.0, 0.88, 0.2)
	add_child(goal_particles)

	gate_particles = CPUParticles2D.new()
	gate_particles.position = Vector2(540, 215)
	gate_particles.emitting = false
	gate_particles.one_shot = true
	gate_particles.explosiveness = 0.85
	gate_particles.amount = 24
	gate_particles.lifetime = 0.55
	gate_particles.direction = Vector2(0, 1)
	gate_particles.spread = 120.0
	gate_particles.initial_velocity_min = 120.0
	gate_particles.initial_velocity_max = 280.0
	gate_particles.scale_amount_min = 5.0
	gate_particles.scale_amount_max = 10.0
	gate_particles.color = Color(0.2, 1.0, 0.6)
	add_child(gate_particles)

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)

	var top_bar := ColorRect.new()
	top_bar.color = Color(0.07, 0.05, 0.04, 0.92)
	top_bar.size = Vector2(1080, 125)
	hud.add_child(top_bar)

	p1_score_label = Label.new()
	p1_score_label.position = Vector2(45, 22)
	p1_score_label.add_theme_font_size_override("font_size", 34)
	p1_score_label.modulate = Color(0.4, 0.75, 1.0)
	hud.add_child(p1_score_label)

	p2_score_label = Label.new()
	p2_score_label.position = Vector2(45, 68)
	p2_score_label.add_theme_font_size_override("font_size", 34)
	p2_score_label.modulate = Color(1.0, 0.45, 0.45)
	hud.add_child(p2_score_label)

	turn_info_label = Label.new()
	turn_info_label.position = Vector2(350, 22)
	turn_info_label.add_theme_font_size_override("font_size", 32)
	hud.add_child(turn_info_label)

	status_label = Label.new()
	status_label.position = Vector2(350, 68)
	status_label.add_theme_font_size_override("font_size", 30)
	status_label.modulate = Color(1.0, 0.9, 0.35)
	hud.add_child(status_label)

	var reset_btn := Button.new()
	reset_btn.text = "تعویض نوبت / ریست"
	reset_btn.position = Vector2(800, 25)
	reset_btn.size = Vector2(240, 75)
	reset_btn.add_theme_font_size_override("font_size", 26)
	reset_btn.pressed.connect(_on_manual_reset_pressed)
	hud.add_child(reset_btn)

	center_banner = Label.new()
	center_banner.position = Vector2(140, 880)
	center_banner.size = Vector2(800, 120)
	center_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_banner.add_theme_font_size_override("font_size", 54)
	center_banner.modulate = Color(1, 1, 1, 0)
	hud.add_child(center_banner)

func _show_banner(text: String, color: Color = Color(1, 0.95, 0.3)) -> void:
	center_banner.text = text
	center_banner.modulate = color
	center_banner.scale = Vector2(0.7, 0.7)
	center_banner.pivot_offset = Vector2(400, 60)
	var tw := create_tween()
	tw.tween_property(center_banner, "scale", Vector2(1.05, 1.05), 0.18).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(0.75)
	tw.tween_property(center_banner, "modulate:a", 0.0, 0.3)

func _set_gate_open(open: bool) -> void:
	var changed := (gate_is_open != open)
	gate_is_open = open

	var led_color := Color(0.2, 1.0, 0.4) if open else Color(1.0, 0.15, 0.15)
	gate_led_left.color = led_color
	gate_led_right.color = led_color

	var tween := create_tween().set_parallel(true)
	if open:
		tween.tween_property(left_gate_door, "position:x", 225.0, 0.38).set_trans(Tween.TRANS_BACK)
		tween.tween_property(right_gate_door, "position:x", 705.0, 0.38).set_trans(Tween.TRANS_BACK)
		if changed:
			gate_particles.restart()
			_play_sfx(420.0, 880.0, 0.22)
			_trigger_shake(7.0)
	else:
		tween.tween_property(left_gate_door, "position:x", 390.0, 0.25)
		tween.tween_property(right_gate_door, "position:x", 540.0, 0.25)

func _spawn_balls() -> void:
	for i in range(3):
		var ball := RigidBody2D.new()
		ball.gravity_scale = 0.0
		ball.linear_damp = 3.6
		ball.angular_damp = 4.2
		ball.contact_monitor = true
		ball.max_contacts_reported = 4

		var mat := PhysicsMaterial.new()
		mat.bounce = 0.32
		ball.physics_material_override = mat

		var col := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = BALL_RADIUS
		col.shape = circle
		ball.add_child(col)

		var pts := PackedVector2Array()
		for v in range(12):
			var angle := v * TAU / 12.0
			var r := BALL_RADIUS * randf_range(0.80, 1.06)
			pts.append(Vector2(cos(angle) * r, sin(angle) * r))

		# سایه زیر کاغذ مچاله
		var shadow := Polygon2D.new()
		shadow.polygon = pts
		shadow.color = Color(0.0, 0.0, 0.0, 0.32)
		shadow.position = Vector2(7, 9)
		ball.add_child(shadow)

		# بدنه کاغذ مچاله
		var poly := Polygon2D.new()
		poly.polygon = pts
		poly.color = Color(0.96, 0.95, 0.90)
		ball.add_child(poly)

		# خطوط آبی دفتر مشق و چروک‌های کاغذ
		var crease := Line2D.new()
		crease.width = 2.5
		crease.default_color = Color(0.35, 0.55, 0.85, 0.45)
		crease.points = PackedVector2Array([
			pts[1] * 0.65, Vector2.ZERO, pts[5] * 0.7, pts[9] * 0.6
		])
		ball.add_child(crease)

		ball.body_entered.connect(_on_ball_body_entered.bind(ball))
		add_child(ball)
		balls.append(ball)

func _start_new_match() -> void:
	scores = [0, 0]
	current_player = 1
	_start_turn(1)

func _on_manual_reset_pressed() -> void:
	if state == GameState.MATCH_OVER:
		_start_new_match()
	else:
		var next_p := 2 if current_player == 1 else 1
		_start_turn(next_p)

func _start_turn(player_idx: int) -> void:
	current_player = player_idx
	state = GameState.WAITING_FOR_INPUT
	moves_left = 3
	passed_between = false
	hit_other_ball = false
	goal_scored_this_shot = false
	active_ball = null
	last_used_ball = null
	is_dragging = false
	aim_line.visible = false
	target_gate_line.visible = false
	_set_gate_open(false)

	var start_positions := [
		Vector2(360 + randf_range(-20, 20), 1520 + randf_range(-15, 15)),
		Vector2(540 + randf_range(-20, 20), 1390 + randf_range(-15, 15)),
		Vector2(720 + randf_range(-20, 20), 1520 + randf_range(-15, 15))
	]
	for i in range(3):
		var b := balls[i]
		b.sleeping = false
		b.linear_velocity = Vector2.ZERO
		b.angular_velocity = 0.0
		b.global_position = start_positions[i]
		PhysicsServer2D.body_set_state(
			b.get_rid(),
			PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(randf_range(0.0, TAU), start_positions[i])
		)

	status_label.text = "توپ را بکشید و از خط آبی بین دو توپ رد کنید"
	_show_banner("نوبت بازیکن %d" % current_player, Color(0.4, 0.8, 1.0) if current_player == 1 else Color(1.0, 0.5, 0.5))
	_update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if state != GameState.WAITING_FOR_INPUT:
		return

	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			for b in balls:
				if b.global_position.distance_to(event.position) <= BALL_RADIUS * 1.7:
					active_ball = b
					is_dragging = true
					drag_current_pos = event.position
					_update_target_gate_preview(b)
					break
		elif is_dragging and active_ball:
			is_dragging = false
			aim_line.visible = false
			target_gate_line.visible = false
			var drag_vec: Vector2 = active_ball.global_position - event.position
			if drag_vec.length() > 28.0:
				var clamped := drag_vec.limit_length(MAX_DRAG_DIST)
				_shoot_ball(active_ball, clamped * IMPULSE_MULTIPLIER)
			else:
				active_ball = null

	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and is_dragging and active_ball:
		drag_current_pos = event.position
		var pull_vec: Vector2 = (active_ball.global_position - drag_current_pos).limit_length(MAX_DRAG_DIST)
		var power_ratio := pull_vec.length() / MAX_DRAG_DIST
		aim_line.visible = true
		aim_line.default_color = Color(0.2, 1.0, 0.4, 0.9).lerp(Color(1.0, 0.25, 0.2, 0.95), power_ratio)
		aim_line.points = PackedVector2Array([
			active_ball.global_position,
			active_ball.global_position + pull_vec
		])
		_update_target_gate_preview(active_ball)

func _update_target_gate_preview(selected_ball: RigidBody2D) -> void:
	var others: Array[Vector2] = []
	for b in balls:
		if b != selected_ball:
			others.append(b.global_position)
	if others.size() == 2:
		target_gate_line.visible = true
		target_gate_line.points = PackedVector2Array([others[0], others[1]])

func _shoot_ball(ball: RigidBody2D, impulse: Vector2) -> void:
	state = GameState.BALLS_MOVING
	passed_between = false
	hit_other_ball = false
	goal_scored_this_shot = false
	prev_active_pos = ball.global_position

	other_balls.clear()
	for b in balls:
		if b != ball:
			other_balls.append(b)

	ball.apply_central_impulse(impulse)
	ball.apply_torque_impulse(randf_range(-1600.0, 1600.0))
	_play_sfx(260.0, 140.0, 0.09)
	status_label.text = "در حال حرکت..."

func _process(delta: float) -> void:
	if shake_strength > 0.1:
		shake_strength = lerpf(shake_strength, 0.0, 12.0 * delta)
		position = Vector2(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength)
		)
	else:
		position = Vector2.ZERO

func _trigger_shake(amount: float) -> void:
	shake_strength = amount

func _physics_process(_delta: float) -> void:
	if state != GameState.BALLS_MOVING or active_ball == null:
		return

	var cur_pos := active_ball.global_position

	# ۱. بررسی عبور از بین دو توپ دیگر
	if not passed_between and other_balls.size() == 2:
		var intersect = Geometry2D.segment_intersects_segment(
			prev_active_pos, cur_pos,
			other_balls[0].global_position, other_balls[1].global_position
		)
		if intersect != null:
			passed_between = true
			_play_sfx(520.0, 740.0, 0.12)

	prev_active_pos = cur_pos

	# ۲. بررسی گل شدن (وقتی دروازه باز است)
	if gate_is_open and GOAL_RECT.has_point(cur_pos):
		goal_scored_this_shot = true
		_evaluate_shot()
		return

	# ۳. بررسی افتادن هر یک از توپ‌ها از روی میز
	for b in balls:
		if not TABLE_RECT.has_point(b.global_position):
			_handle_foul("خطا! توپ از روی میز بیرون افتاد.")
			return

	# ۴. بررسی توقف کامل توپ‌ها
	var all_stopped := true
	for b in balls:
		if b.linear_velocity.length() > STOP_SPEED_THRESHOLD:
			all_stopped = false
			break

	if all_stopped:
		_evaluate_shot()

func _on_ball_body_entered(body: Node, source_ball: RigidBody2D) -> void:
	if state == GameState.BALLS_MOVING and source_ball == active_ball:
		if body in other_balls:
			hit_other_ball = true
			_trigger_shake(9.0)
			_play_sfx(150.0, 90.0, 0.15)

func _evaluate_shot() -> void:
	if goal_scored_this_shot:
		scores[current_player - 1] += 1
		goal_particles.restart()
		_trigger_shake(16.0)
		_play_sfx(440.0, 880.0, 0.25)
		_update_hud()

		if scores[current_player - 1] >= WINNING_SCORE:
			state = GameState.MATCH_OVER
			status_label.text = "بازیکن %d برنده مسابقه شد! (روی دکمه کلیک کنید)" % current_player
			_show_banner("قهرمان: بازیکن %d 🏆" % current_player, Color(0.2, 1.0, 0.4))
		else:
			state = GameState.TRANSITION
			status_label.text = "گل برای بازیکن %d!" % current_player
			_show_banner("گلللل! ⚽", Color(0.2, 1.0, 0.4))
			_switch_turn_after_delay(1.8)
		return

	if hit_other_ball:
		_handle_foul("خطا! توپ به توپ دیگر برخورد کرد.")
		return

	if not passed_between:
		_handle_foul("سوختی! توپ از بین دو توپ دیگر رد نشد.")
		return

	# پاس صحیح انجام شده؛ بررسی باز شدن دروازه برقی
	var was_open := gate_is_open
	for b in balls:
		if b.global_position.y < ATTACK_LINE_Y:
			_set_gate_open(true)
			break

	last_used_ball = active_ball
	moves_left -= 1

	if moves_left <= 0:
		_handle_foul("۳ حرکت تمام شد! نوبت به حریف رسید.")
	else:
		state = GameState.WAITING_FOR_INPUT
		if not was_open and gate_is_open:
			status_label.text = "دروازه باز شد! حالا شوت بزنید!"
			_show_banner("دروازه باز شد! ⚡", Color(0.2, 1.0, 0.6))
		else:
			status_label.text = "پاس صحیح! حرکت بعدی را بزنید."
			_show_banner("پاس صحیح ✓", Color(0.4, 0.95, 1.0))

	_update_hud()

func _handle_foul(reason: String) -> void:
	state = GameState.TRANSITION
	status_label.text = reason
	_trigger_shake(8.0)
	_play_sfx(210.0, 110.0, 0.22)
	_show_banner("نوبت سوخت! ✖", Color(1.0, 0.35, 0.35))
	_update_hud()
	_switch_turn_after_delay(1.5)

func _switch_turn_after_delay(delay_sec: float) -> void:
	await get_tree().create_timer(delay_sec).timeout
	if state == GameState.TRANSITION:
		var next_p := 2 if current_player == 1 else 1
		_start_turn(next_p)

func _update_hud() -> void:
	var p1_mark := "▶ " if current_player == 1 else "   "
	var p2_mark := "▶ " if current_player == 2 else "   "
	p1_score_label.text = "%sبازیکن ۱: %d گل" % [p1_mark, scores[0]]
	p2_score_label.text = "%sبازیکن ۲: %d گل" % [p2_mark, scores[1]]

	var gate_txt := "باز 🟢" if gate_is_open else "قفل 🔴"
	turn_info_label.text = "نوبت: بازیکن %d  |  حرکت: %d/3  |  دروازه: %s" % [current_player, moves_left, gate_txt]
