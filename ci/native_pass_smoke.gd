extends SceneTree

const WAITING_FOR_INPUT := 2
const BALLS_MOVING := 3

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame

	game.professional_mode = false
	game.moves_per_turn = 3
	game.moves_left = 3
	game._start_new_match()
	for _frame in range(600):
		await physics_frame
		if game.state == WAITING_FOR_INPUT:
			break
	if game.state != WAITING_FOR_INPUT:
		push_error("Turn setup did not settle")
		quit(1)
		return

	var positions := [Vector2(440, 1500), Vector2(540, 1350), Vector2(640, 1500)]
	for i in range(3):
		var ball: RigidBody2D = game.balls[i]
		ball.global_position = positions[i]
		PhysicsServer2D.body_set_state(
			ball.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, ball.global_transform)
		ball.linear_velocity = Vector2.ZERO
		ball.angular_velocity = 0.0
		ball.sleeping = true

	game.active_ball = game.balls[1]
	game._shoot_ball(game.active_ball, Vector2(0, 600))
	for _frame in range(600):
		await physics_frame
		if game.state != BALLS_MOVING:
			break

	if game.shot_collided or game.state != WAITING_FOR_INPUT or game.moves_left != 2:
		var failure := (
			"Pass gap test failed. State %s, moves %s, collided %s; "
			+ "status: %s, crossed: %s, ball: %s"
		) % [game.state, game.moves_left, game.shot_collided,
			game.status_label.text, game.gap_crossed, game.active_ball.global_position]
		push_error(failure)
		quit(1)
		return
	var failures: Array[String] = []
	if game.get_node_or_null("GoalBackstop") == null:
		failures.append("Goal tunnel has no physical backstop")
	game.winning_score = 2
	game.scores[0] = 1
	game._update_hud()
	if game.p1_score_value.text != "۱/۲":
		failures.append("Configurable score target is missing from the scoreboard")
	game._finish_shot(3)
	if game.state != 5:
		failures.append("Match did not end at the configured score target")
	game._handle_back_request()
	if game.state != 0 or not game.menu_overlay.visible:
		failures.append("Back request did not return to the game menu")
	game._set_gate(true, true)
	var goal_probe: RigidBody2D = game.balls[0]
	goal_probe.global_position = Vector2(540, 180)
	PhysicsServer2D.body_set_state(
		goal_probe.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, goal_probe.global_transform)
	goal_probe.linear_velocity = Vector2(0, -600)
	goal_probe.sleeping = false
	for _frame in range(20):
		await physics_frame
	if goal_probe.linear_velocity.y <= 0:
		failures.append("Ball passed through the goal backstop instead of bouncing")
	if not failures.is_empty():
		for failure_message in failures:
			push_error(failure_message)
		quit(1)
		return
	print("Native smoke tests passed: pass, goal bounce, score target, and back navigation.")
	quit(0)
