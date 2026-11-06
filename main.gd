extends Node2D

enum GameState { WAITING_FOR_INPUT, BALLS_MOVING, TURN_OVER }

const TABLE_RECT := Rect2(60, 180, 960, 1560)
const ATTACK_LINE_Y := 700.0
const BALL_RADIUS := 36.0
const MAX_DRAG_DIST := 280.0
const IMPULSE_MULTIPLIER := 5.5
const STOP_SPEED_THRESHOLD := 12.0

var state: GameState = GameState.WAITING_FOR_INPUT
var balls: Array[RigidBody2D] = []
var active_ball: RigidBody2D = null
var other_balls: Array[RigidBody2D] = []
var prev_active_pos: Vector2 = Vector2.ZERO

var is_dragging := false
var drag_current_pos := Vector2.ZERO
var passed_between := false
var hit_other_ball := false
var gate_is_open := false
var goal_scored_this_shot := false

var moves_left: int = 3
var score: int = 0

var aim_line: Line2D
var left_gate_door: StaticBody2D
var right_gate_door: StaticBody2D
var status_label: Label
var info_label: Label

func _ready() -> void:
	_build_table_and_ui()
	_build_smart_goal()
	_spawn_balls()
	_reset_turn()

func _build_table_and_ui() -> void:
	# پس‌زمینه میز چوبی
	var bg := ColorRect.new()
	bg.color = Color(0.18, 0.12, 0.08)
	bg.size = Vector2(1080, 1920)
	add_child(bg)

	var table_surface := ColorRect.new()
	table_surface.color = Color(0.45, 0.29, 0.16)
	table_surface.position = TABLE_RECT.position
	table_surface.size = TABLE_RECT.size
	add_child(table_surface)

	# خط یک‌سوم هجومی (خط باز شدن دروازه)
	var attack_line := Line2D.new()
	attack_line.points = PackedVector2Array([
		Vector2(TABLE_RECT.position.x, ATTACK_LINE_Y),
		Vector2(TABLE_RECT.end.x, ATTACK_LINE_Y)
	])
	attack_line.width = 6.0
	attack_line.default_color = Color(1.0, 0.85, 0.2, 0.6)
	add_child(attack_line)

	# خط نشانگر هدف‌گیری
	aim_line = Line2D.new()
	aim_line.width = 8.0
	aim_line.default_color = Color(0.2, 1.0, 0.4, 0.85)
	aim_line.visible = false
	add_child(aim_line)

	# رابط کاربری (HUD)
	var hud := CanvasLayer.new()
	add_child(hud)

	info_label = Label.new()
	info_label.position = Vector2(60, 40)
	info_label.add_theme_font_size_override("font_size", 36)
	hud.add_child(info_label)

	status_label = Label.new()
	status_label.position = Vector2(60, 100)
	status_label.add_theme_font_size_override("font_size", 40)
	status_label.modulate = Color(1, 0.9, 0.3)
	hud.add_child(status_label)

	var reset_btn := Button.new()
	reset_btn.text = "شروع مجدد نوبت"
	reset_btn.position = Vector2(760, 45)
	reset_btn.size = Vector2(260, 80)
	reset_btn.add_theme_font_size_override("font_size", 30)
	reset_btn.pressed.connect(_reset_turn)
	hud.add_child(reset_btn)

func _build_smart_goal() -> void:
	# چارچوب دروازه در بالای میز
	var goal_visual := ColorRect.new()
	goal_visual.color = Color(0.1, 0.4, 0.2)
	goal_visual.position = Vector2(390, 110)
	goal_visual.size = Vector2(300, 70)
	add_child(goal_visual)

	# دو درِ کشویی برقی جلوی دروازه
	left_gate_door = _create_gate_door(Vector2(390, 165))
	right_gate_door = _create_gate_door(Vector2(540, 165))

func _create_gate_door(pos: Vector2) -> StaticBody2D:
	var door := StaticBody2D.new()
	door.position = pos

	var rect := ColorRect.new()
	rect.size = Vector2(150, 26)
	rect.color = Color(0.85, 0.2, 0.2)
	door.add_child(rect)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(150, 26)
	col.position = Vector2(75, 13)
	col.shape = shape
	door.add_child(col)

	add_child(door)
	return door

func _set_gate_open(open: bool) -> void:
	if gate_is_open == open:
		return
	gate_is_open = open
	var tween := create_tween().set_parallel(true)
	if open:
		tween.tween_property(left_gate_door, "position:x", 230.0, 0.35).set_trans(Tween.TRANS_BACK)
		tween.tween_property(right_gate_door, "position:x", 700.0, 0.35).set_trans(Tween.TRANS_BACK)
	else:
		tween.tween_property(left_gate_door, "position:x", 390.0, 0.25)
		tween.tween_property(right_gate_door, "position:x", 540.0, 0.25)

func _spawn_balls() -> void:
	for i in range(3):
		var ball := RigidBody2D.new()
		ball.gravity_scale = 0.0
		ball.linear_damp = 3.5
		ball.angular_damp = 4.0
		ball.contact_monitor = true
		ball.max_contacts_reported = 4

		var mat := PhysicsMaterial.new()
		mat.bounce = 0.3
		ball.physics_material_override = mat

		var col := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = BALL_RADIUS
		col.shape = circle
		ball.add_child(col)

		# ظاهر چندضلعی شبیه کاغذ مچاله
		var poly := Polygon2D.new()
		var pts := PackedVector2Array()
		for v in range(10):
			var angle := v * TAU / 10.0
			var r := BALL_RADIUS * randf_range(0.82, 1.05)
			pts.append(Vector2(cos(angle) * r, sin(angle) * r))
		poly.polygon = pts
		poly.color = Color(0.95, 0.94, 0.9)
		ball.add_child(poly)

		ball.body_entered.connect(_on_ball_body_entered.bind(ball))
		add_child(ball)
		balls.append(ball)

func _reset_turn() -> void:
	state = GameState.WAITING_FOR_INPUT
	moves_left = 3
	passed_between = false
	hit_other_ball = false
	goal_scored_this_shot = false
	_set_gate_open(false)

	var start_positions := [
		Vector2(380, 1500),
		Vector2(540, 1380),
		Vector2(700, 1500)
	]
	for i in range(3):
		var b := balls[i]
		b.linear_velocity = Vector2.ZERO
		b.angular_velocity = 0.0
		PhysicsServer2D.body_set_state(
			b.get_rid(),
			PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, start_positions[i])
		)

	status_label.text = "یک توپ را بکشید و از بین دو توپ دیگر رد کنید"
	_update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if state != GameState.WAITING_FOR_INPUT:
		return

	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			for b in balls:
				if b.global_position.distance_to(event.position) <= BALL_RADIUS * 1.6:
					active_ball = b
					is_dragging = true
					drag_current_pos = event.position
					break
		elif is_dragging and active_ball:
			is_dragging = false
			aim_line.visible = false
			var drag_vec: Vector2 = active_ball.global_position - event.position
			if drag_vec.length() > 25.0:
				var clamped := drag_vec.limit_length(MAX_DRAG_DIST)
				_shoot_ball(active_ball, clamped * IMPULSE_MULTIPLIER)
			else:
				active_ball = null

	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and is_dragging and active_ball:
		drag_current_pos = event.position
		var pull_vec: Vector2 = (active_ball.global_position - drag_current_pos).limit_length(MAX_DRAG_DIST)
		aim_line.visible = true
		aim_line.points = PackedVector2Array([
			active_ball.global_position,
			active_ball.global_position + pull_vec
		])

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
	status_label.text = "..."

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

	prev_active_pos = cur_pos

	# ۲. بررسی ورود به دروازه (وقتی دروازه باز است)
	if gate_is_open and Rect2(390, 100, 300, 80).has_point(cur_pos):
		goal_scored_this_shot = true
		_evaluate_shot()
		return

	# ۳. بررسی افتادن توپ‌ها از روی میز
	for b in balls:
		if not TABLE_RECT.has_point(b.global_position):
			status_label.text = "خطا! توپ از میز بیرون افتاد."
			state = GameState.TURN_OVER
			_update_hud()
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

func _evaluate_shot() -> void:
	if goal_scored_this_shot:
		score += 1
		state = GameState.TURN_OVER
		status_label.text = "گل! شوت عالی بود!"
		_update_hud()
		return

	if hit_other_ball:
		state = GameState.TURN_OVER
		status_label.text = "خطا! توپ به توپ دیگر برخورد کرد."
		_update_hud()
		return

	if not passed_between:
		state = GameState.TURN_OVER
		status_label.text = "سوختی! توپ از بین دو توپ دیگر رد نشد."
		_update_hud()
		return

	# پاس صحیح انجام شده؛ بررسی عبور از خط یک‌سوم برای باز شدن دروازه برقی
	for b in balls:
		if b.global_position.y < ATTACK_LINE_Y:
			_set_gate_open(true)
			break

	moves_left -= 1
	if moves_left <= 0:
		state = GameState.TURN_OVER
		status_label.text = "۳ حرکت تمام شد! نوبت سوخت."
	else:
		state = GameState.WAITING_FOR_INPUT
		status_label.text = "پاس صحیح! حرکت بعدی را بزنید."

	_update_hud()

func _update_hud() -> void:
	var gate_txt := "باز" if gate_is_open else "قفل"
	info_label.text = "امتیاز: %d   |   حرکت باقی‌مانده: %d   |   دروازه: %s" % [score, moves_left, gate_txt]