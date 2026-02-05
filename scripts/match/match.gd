extends Node2D

const TEAM_A: int = 0
const TEAM_B: int = 1
const BALL_OFFSET_MAGNITUDE: float = 6.0

var match_controller: Node = null

@onready var sim: Node = $MatchSim
var player_dot_scene: PackedScene = preload("res://scenes/match/player_dot.tscn")

@export var base_player_speed: float = 160.0
@export var pace_multiplier: float = 80.0  # How much pace stat affects speed
@export var tick_rate: float = 30.0
var _accum: float = 0.0

@export var base_pass_interval: float = 2.0
@export var min_pass_interval: float = 0.8  # Under pressure, pass faster
var pass_timer: float = 0.0

@onready var ball_dot: Sprite2D = $Ball

var all_players: Array[Node2D] = []
var team_a_players: Array[Node2D] = []
var team_b_players: Array[Node2D] = []

# Velocity tracking for smooth movement
var team_a_velocities: Array[Vector2] = []
var team_b_velocities: Array[Vector2] = []

var ball_owner: Node2D = null
var pending_receiver: Node2D = null  # Player who should receive the pass
var ball_owner_team: int = TEAM_A
var ball_owner_index: int = 0
var pending_receiver_team: int = TEAM_A
var pending_receiver_index: int = -1

var ball_in_flight: bool = false
var ball_start: Vector2 = Vector2.ZERO
var ball_end: Vector2 = Vector2.ZERO
var ball_t: float = 0.0
var ball_travel_time: float = 0.6
var ball_action: String = "PASS" # PASS or SHOT
var gk_saving: bool = false  # Is goalkeeper attempting a save
var gk_save_target: Vector2 = Vector2.ZERO  # Where goalkeeper is trying to save

var score_a: int = 0
var score_b: int = 0

@export var shot_chance: float = 0.22
@export var 	shot_min_x_frac: float = 0.72
@export var shot_max_y_from_center: float = 140.0
@export var goal_half_height: float = 55.0
@export var shot_speed_divisor: float = 1200.0

@export var shot_goal_prob: float = 0.35
@export var shot_on_target_prob: float = 0.75
@export var keeper_save_prob: float = 0.55

@export var min_ball_time: float = 0.25
@export var max_ball_time: float = 0.90

@export var pass_candidate_count: int = 7
@export var pass_max_distance: float = 420.0
@export var weight_openness: float = 0.9
@export var weight_forward: float = 0.85
@export var weight_distance: float = 0.006
@export var creative_pass_chance: float = 0.22
@export var through_ball_chance: float = 0.25  # Chance to attempt through ball when opportunity exists
@export var through_ball_lead_distance: float = 80.0  # How far ahead to pass

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var dribble_active: bool = false
var dribble_target: Vector2 = Vector2.ZERO
var dribble_timer: float = 0.0

@export var dribble_duration: float = 0.8
@export var dribble_speed: float = 220.0
@export var dribble_chance: float = 0.35

@export var tackle_radius: float = 18.0
@export var tackle_chance_per_sec: float = 0.9

@export var intercept_radius: float = 16.0
@export var intercept_chance_per_sec: float = 0.6

var ball_free: bool = false
var ball_velocity: Vector2 = Vector2.ZERO

@export var pass_miss_chance: float = 0.10      # Base miss chance (10% of passes go loose)
@export var pass_scatter: float = 55.0          # Base scatter amount
@export var pass_distance_accuracy_factor: float = 0.0015  # How much distance affects accuracy (higher = less accurate at distance)
@export var min_pass_distance: float = 30.0  # Minimum distance for a valid pass
@export var loose_ball_friction: float = 2.5
@export var loose_pickup_radius: float = 22.0
@export var loose_ball_chase_distance: float = 200.0  # How far players will chase loose ball
@export var loose_ball_override_target_distance: float = 50.0  # Override normal targets when this close

@export var touchline_margin: float = 10.0  # Margin for touchlines (sides)
@export var goal_line_margin: float = 10.0  # Margin for goal lines (ends)

@export var ball_receive_radius: float = 25.0  # How close player needs to be to receive pass
@export var receiver_move_toward_ball: bool = true  # Should receiver move toward ball during pass

var ball_end_velocity: Vector2 = Vector2.ZERO # Velocity when the ball lands
var ball_last_touched_by: int = TEAM_A

@export var ball_acceleration_time: float = 0.15 # Time to reach full speed
@export var ball_deceleration_time: float = 0.2 # Time to slow down at end
@export var ball_arc_height: float = 15.0 # How high the ball "bounces" during flight

var ball_trail_positions: Array[Vector2] = []
@export var ball_trail_length: int = 5
@export var ball_trail_enabled: bool = true

var throw_in_active: bool = false
var throw_in_taker_team: int = TEAM_A
var throw_in_taker_index: int = 0
var throw_in_position: Vector2 = Vector2.ZERO
var throw_in_timer: float = 0.0

@export var throw_in_setup_time: float = 1.2  # Time to pick up ball and prepare
@export var throw_in_max_distance: float = 180.0  # How far throw-ins can go

const TEAM_A_COLOR := Color(0.2, 0.6, 1.0)
const TEAM_B_COLOR := Color(1.0, 0.3, 0.3)

func _ready() -> void:
	_spawn_teams()
	rng.randomize()

func _get_ball_offset(team_id: int) -> Vector2:
	# Team A attacks right (ball to the right), Team B attacks left (ball to the left)
	if team_id == TEAM_A:
		return Vector2(BALL_OFFSET_MAGNITUDE, 0.0)
	else:
		return Vector2(-BALL_OFFSET_MAGNITUDE, 0.0)

func _spawn_teams() -> void:
	"""
	Spawn both teams with proper player data.
	"""
	# Get player squad data from GameManager
	var player_team_data: Array = GameManager.get_starting_11_as_match_data()
	
	# Spawn Team A (player's team)
	for i in range(sim.team_a_positions.size()):
		var dot: Node2D = player_dot_scene.instantiate()
		add_child(dot)
		
		# Get player data (either from GameManager or default)
		var p_data: Dictionary = player_team_data[i] if i < player_team_data.size() else _default_player_data()
		
		# Initialize the player dot
		dot.initialize(TEAM_A, p_data, sim.team_a_positions[i], TEAM_A_COLOR)
		
		# Set name for player's team
		if i < GameManager.starting_11.size():
			var player_index: int = GameManager.starting_11[i]
			if player_index < GameManager.player_squad.size():
				var player_card: PlayerCard = GameManager.player_squad[player_index]
				dot.set_player_name(player_card.player_name, true)
		
		team_a_players.append(dot)
		all_players.append(dot)
	
	# Spawn Team B (opponent)
	var opponent_data: Array = _generate_opponent_team()
	for i in range(sim.team_b_positions.size()):
		var dot: Node2D = player_dot_scene.instantiate()
		add_child(dot)
		
		var p_data: Dictionary = opponent_data[i]
		dot.initialize(TEAM_B, p_data, sim.team_b_positions[i], TEAM_B_COLOR)
		dot.hide_name()  # No names for opponents
		
		team_b_players.append(dot)
		all_players.append(dot)
	
	# Give ball to Team A striker (index 9)
	if team_a_players.size() > 9:
		ball_owner = team_a_players[9]
		ball_owner_team = TEAM_A
		ball_owner_index = 9

func _default_player_data() -> Dictionary:
	return {
		"id": randi(),
		"role": "MID",
		"pace": 0.5,
		"tackle": 0.5,
		"pass": 0.5,
		"dribble": 0.5,
		"mark_target": -1
	}

func _generate_opponent_team() -> Array:
	"""
	Generate opponent team with random stats.
	"""
	var opponent: Array = []
	var positions: Array[String] = ["GK", "DEF", "DEF", "DEF", "DEF", "MID", "MID", "MID", "MID", "FWD", "FWD"]
	
	for i in range(11):
		var role: String = positions[i]
		opponent.append({
			"id": i,
			"role": role,
			"pace": randf_range(0.4, 0.6),
			"tackle": randf_range(0.4, 0.6),
			"pass": randf_range(0.4, 0.6),
			"dribble": randf_range(0.4, 0.6),
			"mark_target": -1
		})
	
	return opponent

func _process(delta: float) -> void:
	_accum += delta
	var tick_dt: float = 1.0 / tick_rate

	while _accum >= tick_dt:
		_accum -= tick_dt
		_fixed_tick(tick_dt)

	_render_ball()
	
	# Draw ball trail
	if ball_trail_enabled and ball_in_flight:
		queue_redraw()

func _draw() -> void:
	if not ball_trail_enabled or not ball_in_flight:
		return
	
	# Draw trail as fading circles
	for i in range(ball_trail_positions.size()):
		var pos: Vector2 = ball_trail_positions[i]
		var alpha: float = 1.0 - (float(i) / float(ball_trail_length))
		var radius: float = 4.0 * alpha
		var color: Color = Color(1.0, 1.0, 1.0, alpha * 0.5)
		draw_circle(pos, radius, color)
	
	if throw_in_active:
		var thrower_nodes: Array[Node2D] = team_a_players if throw_in_taker_team == TEAM_A else team_b_players
		var thrower: Node2D = thrower_nodes[throw_in_taker_index]
		
		# Draw circle around thrower
		var color: Color = TEAM_A_COLOR if throw_in_taker_team == TEAM_A else TEAM_B_COLOR
		draw_circle(thrower.position, 25.0, Color(color.r, color.g, color.b, 0.3))
		draw_arc(thrower.position, 25.0, 0, TAU, 32, color, 2.0)


func _fixed_tick(dt: float) -> void:
	if match_controller and match_controller.is_paused:
		return
	
	# Handle throw-in setup
	if throw_in_active:
		_tick_throw_in(dt)
		return  # Don't process normal game logic during throw-in
	
	# Push latest ball state into the sim BEFORE sim.tick
	_sync_sim_state()
	sim.tick(dt)

	_apply_targets(dt)
	_move_receiver_toward_ball(dt)
	_move_goalkeeper_to_save(dt)
	_tick_passing(dt)
	_tick_ball(dt)
	_tick_loose_ball(dt)


func _sync_sim_state() -> void:
	sim.ball_pos = ball_dot.position
	
	if ball_owner:
		sim.ball_owner_team = ball_owner.team_id
		sim.ball_owner_index = _get_player_index(ball_owner)
	else:
		sim.ball_owner_team = TEAM_A
		sim.ball_owner_index = 0
	
	sim.ball_in_flight = ball_in_flight
	
	if ball_in_flight and pending_receiver:
		sim.ball_team = pending_receiver.team_id
	elif ball_owner:
		sim.ball_team = ball_owner.team_id
	else:
		sim.ball_team = TEAM_A
	
	# Update sim with current player positions
	for i in range(team_a_players.size()):
		if i < sim.team_a_positions.size():
			sim.team_a_positions[i] = team_a_players[i].position
	
	for i in range(team_b_players.size()):
		if i < sim.team_b_positions.size():
			sim.team_b_positions[i] = team_b_players[i].position

func _get_player_index(player: Node2D) -> int:
	"""
	Get the index of a player in their team array.
	"""
	if player.team_id == TEAM_A:
		return team_a_players.find(player)
	else:
		return team_b_players.find(player)

func _move_receiver_toward_ball(dt: float) -> void:
	if not ball_in_flight or ball_action != "PASS" or not pending_receiver:
		return
	
	var alpha: float = clamp(ball_t / ball_travel_time, 0.0, 1.0)
	var ball_arrival_pos: Vector2 = ball_start.lerp(ball_end, alpha)
	
	var to_ball: Vector2 = ball_arrival_pos - pending_receiver.position
	var distance_to_ball: float = to_ball.length()
	
	# Only move if ball is reasonably close and not too far
	if distance_to_ball < 150.0 and distance_to_ball > 10.0:
		var max_speed: float = pending_receiver.get_speed()  # Uses player's own pace stat!
		var desired_velocity: Vector2 = to_ball.normalized() * max_speed * 0.6
		
		var acceleration: float = 800.0
		var accel_vec: Vector2 = (desired_velocity - pending_receiver.velocity) * acceleration * dt
		pending_receiver.velocity += accel_vec
		
		if pending_receiver.velocity.length() > max_speed * 0.8:
			pending_receiver.velocity = pending_receiver.velocity.normalized() * max_speed * 0.8

func _handle_pass_arrival() -> void:
	# Check if receiver reached the ball
	if not pending_receiver:
		# No valid receiver - loose ball
		ball_dot.position = ball_end
		ball_velocity = ball_end_velocity
		_start_loose_ball()
		return
	
	var ball_arrival_pos: Vector2 = ball_end
	var distance: float = pending_receiver.position.distance_to(ball_arrival_pos)
	
	if distance <= ball_receive_radius:
		# Receiver can control it
		if distance < 8:
			# Very close - clean reception
			ball_owner = pending_receiver
			ball_owner_team = pending_receiver.team_id
			ball_owner_index = _get_player_index(pending_receiver)
			if distance > 2.0:
				pending_receiver.position = pending_receiver.position.move_toward(ball_arrival_pos, distance * 0.5)
			_set_anchor_for_owner(pending_receiver.position)
		else:
			# Slightly far - ball rolls and receiver chases
			ball_dot.position = ball_arrival_pos
			ball_velocity = ball_end_velocity * 0.6
			_start_loose_ball()
	else:
		# Receiver didn't reach the ball - loose ball
		ball_dot.position = ball_arrival_pos
		ball_velocity = ball_end_velocity
		_start_loose_ball()

func _apply_targets(dt: float) -> void:
	# Apply loose ball target overrides first
	if ball_free:
		_apply_loose_ball_target_overrides()
	
	_sync_targets_from_sim()
	
	# Move all players toward their targets
	for player in all_players:
		_move_player_to_target(player, dt)
	
	# Apply dribble override
	_apply_dribble_override(dt)

func _sync_targets_from_sim() -> void:
	"""
	Read target positions from match_sim and apply them to player dots.
	"""
	for i in range(team_a_players.size()):
		if i < sim.team_a_targets.size():
			team_a_players[i].target_position = sim.team_a_targets[i]
	
	for i in range(team_b_players.size()):
		if i < sim.team_b_targets.size():
			team_b_players[i].target_position = sim.team_b_targets[i]

func _move_player_to_target(player: Node2D, dt: float) -> void:
	"""
	Move a single player toward their target position.
	Uses their own stats and velocity.
	"""
	var current: Vector2 = player.position
	var target: Vector2 = player.target_position
	var max_speed: float = player.get_speed()  # Uses player's pace stat!
	
	var to_target: Vector2 = target - current
	var distance: float = to_target.length()
	
	var acceleration: float = 600.0
	var damping: float = 12.0
	var dead_zone: float = 15.0
	var approach_zone: float = 40.0
	
	# Dead zone - very close, just stop
	if distance < dead_zone:
		player.velocity = player.velocity.move_toward(Vector2.ZERO, damping * max_speed * dt * 3.0)
	
	# Approach zone - slow down
	elif distance < approach_zone:
		var slow_factor: float = distance / approach_zone
		var desired_velocity: Vector2 = to_target.normalized() * max_speed * slow_factor
		var accel_vec: Vector2 = (desired_velocity - player.velocity) * acceleration * dt
		player.velocity += accel_vec
		player.velocity = player.velocity.move_toward(desired_velocity, damping * max_speed * dt)
		if player.velocity.length() > max_speed * slow_factor:
			player.velocity = player.velocity.normalized() * max_speed * slow_factor
	
	# Normal movement - full speed
	elif distance > 0.1:
		var desired_velocity: Vector2 = to_target.normalized() * max_speed
		var accel_vec: Vector2 = (desired_velocity - player.velocity) * acceleration * dt
		player.velocity += accel_vec
		player.velocity = player.velocity.move_toward(desired_velocity, damping * max_speed * dt)
		if player.velocity.length() > max_speed:
			player.velocity = player.velocity.normalized() * max_speed
	
	# Apply friction when very close
	else:
		player.velocity = player.velocity.move_toward(Vector2.ZERO, damping * max_speed * dt)
	
	# Update position
	player.position += player.velocity * dt

func _get_player_speed(team_id: int, player_index: int) -> float:
	var data: Array = sim.team_a if team_id == TEAM_A else sim.team_b
	if player_index >= data.size():
		return base_player_speed
	var pace: float = float(data[player_index].get("pace", 0.5))
	return base_player_speed + (pace - 0.5) * pace_multiplier


func _apply_dribble_override(dt: float) -> void:
	if not dribble_active:
		return
	if ball_in_flight:
		dribble_active = false
		return

	var owner: Node2D = _get_owner_node()
	var dribble_speed_mod: float = _get_dribble_speed()
	owner.position = owner.position.move_toward(dribble_target, dribble_speed_mod * dt)

	dribble_timer += dt
	var reached: bool = owner.position.distance_to(dribble_target) < 3.0
	if reached or dribble_timer >= dribble_duration:
		dribble_active = false
		_set_anchor_for_owner(owner.position)

	_try_tackle_dribbler(dt)

func _get_dribble_speed() -> float:
	var data: Array = sim.team_a if ball_owner_team == TEAM_A else sim.team_b
	if ball_owner_index >= data.size():
		return dribble_speed
	var dribble_stat: float = float(data[ball_owner_index].get("dribble", 0.5))
	return dribble_speed * (0.7 + dribble_stat * 0.6)  # 70-130% of base speed


func _tick_ball(dt: float) -> void:
	if not ball_in_flight:
		return

	# Intercept only apply for passes for now
	if ball_action == "PASS":
		# PASS arrival
		if pending_receiver_index == -1:
			_start_loose_ball()
			return
		if _try_intercept_pass(dt):
			return

	ball_t += dt
	
	# Check if ball goes out of bounds during flight
	if _check_ball_out_of_bounds():
		_handle_ball_out_of_bounds()
		ball_in_flight = false
		return
	
	# Check if goalkeeper saves during flight (for shots)
	if ball_action == "SHOT" and gk_saving:
		_check_goalkeeper_save_during_flight()
	
	if ball_t >= ball_travel_time:
		ball_in_flight = false
		
		if ball_action == "SHOT":
			_resolve_shot()
		else:
			# PASS arrival - check if receiver reached the ball
			_handle_pass_arrival()


func _render_ball() -> void:
	if throw_in_active:
		# During throw-in setup, ball is at throw-in position or in thrower's hands
		if throw_in_timer < throw_in_setup_time * 0.8:
			# Ball on ground at throw-in spot
			ball_dot.position = throw_in_position
		else:
			# Player picked up the ball (show it above their head)
			var thrower_nodes: Array[Node2D] = team_a_players if throw_in_taker_team == TEAM_A else team_b_players
			var thrower: Node2D = thrower_nodes[throw_in_taker_index]
			ball_dot.position = thrower.position + Vector2(0, -15)  # Above head
		return
	
	if ball_in_flight:
		var alpha: float = clamp(ball_t / ball_travel_time, 0.0, 1.0)
		var eased_alpha: float = _ease_ball_flight(alpha)
		var interpolated_pos := ball_start.lerp(ball_end, eased_alpha)
		
		var arc_progress: float = sin(alpha * PI)
		var height_offset: float = ball_arc_height * arc_progress
		var pass_distance: float = ball_start.distance_to(ball_end)
		var distance_factor: float = clamp(pass_distance / 200.0, 0.3, 2.0)
		height_offset *= distance_factor
		
		if ball_action == "SHOT":
			height_offset *= 0.4
		
		var visual_offset := Vector2(0, -height_offset)
		ball_dot.position = interpolated_pos + visual_offset
		
		# Update trail
		if ball_trail_enabled:
			ball_trail_positions.push_front(ball_dot.position)
			if ball_trail_positions.size() > ball_trail_length:
				ball_trail_positions.pop_back()
		
		# Check bounds...
		if interpolated_pos.x < goal_line_margin or interpolated_pos.x > sim.pitch_width - goal_line_margin or \
		   interpolated_pos.y < touchline_margin or interpolated_pos.y > sim.pitch_height - touchline_margin:
			ball_dot.position = interpolated_pos
			if _check_ball_out_of_bounds():
				_handle_ball_out_of_bounds()
				ball_in_flight = false
	elif ball_free:
		# Clear trail when ball is loose
		ball_trail_positions.clear()
	else:
		# Clear trail when ball is possessed
		ball_trail_positions.clear()
		var owner: Node2D = _get_owner_node()
		ball_dot.position = owner.position + _get_ball_offset(ball_owner_team)


func _ease_ball_flight(t: float) -> float:
	# Custom easing: slow start (acceleration), fast middle, slow end (deceleration)
	var accel_duration: float = ball_acceleration_time / ball_travel_time
	var decel_start: float = 1.0 - (ball_deceleration_time / ball_travel_time)
	
	if t < accel_duration:
		# Acceleration phase (ease in quadratic)
		var local_t: float = t / accel_duration
		return accel_duration * local_t * local_t
	elif t > decel_start:
		# Deceleration phase (ease out quadratic)
		var local_t: float = (t - decel_start) / (1.0 - decel_start)
		var eased: float = 1.0 - (1.0 - local_t) * (1.0 - local_t)
		return decel_start + (1.0 - decel_start) * eased
	else:
		# Constant speed phase (linear)
		return t


func _get_owner_node() -> Node2D:
	return team_a_players[ball_owner_index] if ball_owner_team == TEAM_A else team_b_players[ball_owner_index]

func _get_receiver_node() -> Node2D:
	if pending_receiver_index == -1:
		return null
	return team_a_players[pending_receiver_index] if pending_receiver_team == TEAM_A else team_b_players[pending_receiver_index]

func _set_ball_owner(team: int, index: int) -> void:
	ball_owner_team = team
	ball_owner_index = index
	ball_owner = _get_owner_node()


func _tick_passing(dt: float) -> void:
	if ball_in_flight or dribble_active or throw_in_active:
		return

	var interval: float = _get_pass_interval()
	pass_timer += dt
	if pass_timer < interval:
		return

	pass_timer = 0.0
	
	# SHOOT decision
	var owner: Node2D = _get_owner_node()
	if _is_in_shooting_zone(ball_owner_team, owner.position):
		var shoot_probability: float = _get_shoot_probability(ball_owner_team, owner.position)
		if rng.randf() < shoot_probability:
			_start_shot()
			return
	
	# Otherwise dribble or pass (weighted by player stats)
	var dribble_prob: float = _get_dribble_probability()
	if rng.randf() < dribble_prob:
		_start_dribble()
	else:
		_make_animated_pass()

func _get_pass_interval() -> float:
	var pressure: float = _calculate_pressure()
	var interval: float = base_pass_interval * (1.0 - pressure * 0.6)  # Reduce interval under pressure
	return max(interval, min_pass_interval)

func _calculate_pressure() -> float:
	# Calculate how much pressure the ball carrier is under
	var owner: Node2D = _get_owner_node()
	var opponents: Array[Node2D] = team_b_players if ball_owner_team == TEAM_A else team_a_players
	
	var nearest_dist: float = 999999.0
	for opp in opponents:
		var dist: float = owner.position.distance_to(opp.position)
		if dist < nearest_dist:
			nearest_dist = dist
	
	# Pressure is high when opponents are close (within 60 units)
	var pressure: float = 1.0 - clamp(nearest_dist / 60.0, 0.0, 1.0)
	return pressure

func _get_dribble_probability() -> float:
	var data: Array = sim.team_a if ball_owner_team == TEAM_A else sim.team_b
	if ball_owner_index >= data.size():
		return dribble_chance
	
	var dribble_stat: float = float(data[ball_owner_index].get("dribble", 0.5))
	var pressure: float = _calculate_pressure()
	
	# Check space ahead for dribble
	var owner: Node2D = _get_owner_node()
	var attack_dir: Vector2 = Vector2(1.0, 0.0) if ball_owner_team == TEAM_A else Vector2(-1.0, 0.0)
	var space_ahead: float = _check_space_in_direction(owner.position, attack_dir, 60.0)
	
	# Don't dribble if no space or under heavy pressure
	if space_ahead < 30.0 or pressure > 0.7:
		return dribble_chance * 0.2
	
	var base_prob: float = dribble_chance * (0.5 + dribble_stat)
	var pressure_mod: float = 1.0 - pressure * 0.6  # Stronger pressure reduction
	
	return base_prob * pressure_mod

func _check_space_in_direction(from_pos: Vector2, direction: Vector2, check_distance: float) -> float:
	# Check how much space is available in given direction
	var opponents: Array[Node2D] = team_b_players if ball_owner_team == TEAM_A else team_a_players
	var min_dist: float = check_distance
	
	for opp in opponents:
		var to_opp: Vector2 = opp.position - from_pos
		var forward_component: float = to_opp.dot(direction)
		
		# Only check opponents ahead
		if forward_component > 0 and forward_component < check_distance:
			var lateral_dist: float = abs(to_opp.cross(direction))
			# If opponent is in the way (within 40 units laterally)
			if lateral_dist < 40.0:
				min_dist = min(min_dist, forward_component)
	
	return min_dist


func _make_animated_pass() -> void:
	var teammates: Array[Node2D] = team_a_players if ball_owner_team == TEAM_A else team_b_players
	var opponents: Array[Node2D] = team_b_players if ball_owner_team == TEAM_A else team_a_players
	var attack_dir: Vector2 = Vector2(1.0, 0.0) if ball_owner_team == TEAM_A else Vector2(-1.0, 0.0)

	var from_index: int = ball_owner_index
	var to_index: int = _choose_pass_target_index(teammates, opponents, from_index, attack_dir)

	# Only pass if we found a valid target
	if to_index == -1:
		# No valid pass target - try to find ANY teammate within reasonable distance
		var fallback_target: int = _find_fallback_pass_target(teammates, from_index)
		if fallback_target == -1:
			# No teammates close enough - dribble instead
			_start_dribble()
			return
		to_index = fallback_target

	var from_node: Node2D = teammates[from_index]
	var to_node: Node2D = teammates[to_index]

	_start_pass(from_node, to_node, ball_owner_team, to_index)


func _start_dribble() -> void:
	dribble_active = true
	dribble_timer = 0.0

	var owner: Node2D = _get_owner_node()
	var start: Vector2 = owner.position

	var direction: Vector2 = Vector2(1.0, 0.0) if ball_owner_team == TEAM_A else Vector2(-1.0, 0.0)

	var forward_distance: float = rng.randf_range(70.0, 180.0)
	var side_distance: float = rng.randf_range(-18.0, 18.0)

	var raw_target: Vector2 = start + direction * forward_distance + Vector2(0.0, side_distance)

	var margin: float = 30.0
	var x: float = clamp(raw_target.x, margin, sim.pitch_width - margin)
	var y: float = clamp(raw_target.y, margin, sim.pitch_height - margin)
	dribble_target = Vector2(x, y)


func _start_pass(from_node: Node2D, to_node: Node2D, receiver_team: int, receiver_index: int) -> void:
	ball_in_flight = true
	ball_t = 0.0
	ball_start = from_node.position + _get_ball_offset(ball_owner_team)
	
	# Check if this should be a through ball (pass ahead of receiver)
	var attack_dir: Vector2 = Vector2(1.0, 0.0) if ball_owner_team == TEAM_A else Vector2(-1.0, 0.0)
	var from_pos: Vector2 = from_node.position
	var to_pos: Vector2 = to_node.position
	var forward: float = (to_pos - from_pos).dot(attack_dir)
	
	# If receiver is moving forward and there's space, lead the pass
	if forward > 30.0:
		var receiver_data: Array = sim.team_a if receiver_team == TEAM_A else sim.team_b
		if receiver_index < receiver_data.size():
			var role: String = receiver_data[receiver_index].get("role", "MID")
			# Forwards and attacking mids get through balls
			if role == "FWD" or (role == "MID" and forward > 60.0):
				ball_end = to_pos + attack_dir * through_ball_lead_distance
				# Clamp to pitch
				ball_end.x = clamp(ball_end.x, goal_line_margin, sim.pitch_width - goal_line_margin)
				ball_end.y = clamp(ball_end.y, touchline_margin, sim.pitch_height - touchline_margin)
			else:
				ball_end = to_pos + _get_ball_offset(receiver_team)
		else:
			ball_end = to_pos + _get_ball_offset(receiver_team)
	else:
		ball_end = to_pos + _get_ball_offset(receiver_team)
	
	ball_action = "PASS"
	
	# Calculate pass distance for accuracy calculation
	var pass_distance: float = ball_start.distance_to(ball_end)
	
	# Pass accuracy based on player pass stat AND distance
	var miss_chance: float = _get_pass_miss_chance(pass_distance)
	
	# Calculate pass power based on distance
	var pass_power: float = clamp(pass_distance / 300.0, 0.3, 1.5)
	
	# Always add some scatter based on distance (even successful passes aren't perfect)
	var base_scatter: float = pass_scatter * (2.0 - _get_pass_stat())  # Better passers scatter less
	var distance_scatter_multiplier: float = 1.0 + (pass_distance / 200.0)  # Longer passes scatter more
	var scatter_amount: float = base_scatter * distance_scatter_multiplier
	
	if rng.randf() < miss_chance:
		# Complete miss: aim near receiver but not at them
		var scatter := Vector2(rng.randf_range(-scatter_amount, scatter_amount), rng.randf_range(-scatter_amount, scatter_amount))
		ball_end += scatter
		# We will treat it as a loose ball when it arrives
		pending_receiver_index = -1
		pending_receiver = null
		
		ball_end_velocity = (ball_end - ball_start).normalized() * (150.0 * pass_power)
	else:
		# Successful pass, but still add small scatter based on distance
		var small_scatter: float = scatter_amount * 0.3  # 30% of full scatter for successful passes
		var scatter := Vector2(rng.randf_range(-small_scatter, small_scatter), rng.randf_range(-small_scatter, small_scatter))
		ball_end += scatter
		
		ball_end_velocity = (ball_end - ball_start).normalized() * (80.0 * pass_power)

	var dist: float = ball_start.distance_to(ball_end)
	
	# Different speeds for different pass distances
	var base_speed: float = 600.0  # Reduced from 900.0
	if dist < 100.0:
		# Short passes are slower
		base_speed = 450.0
	elif dist > 300.0:
		# Long passes are faster
		base_speed = 750.0
	
	var seconds: float = dist / base_speed
	ball_travel_time = clamp(seconds, min_ball_time, max_ball_time)

	pending_receiver_team = receiver_team
	pending_receiver_index = receiver_index
	pending_receiver = _get_receiver_node()
	ball_last_touched_by = ball_owner_team

func _get_pass_stat() -> float:
	var data: Array = sim.team_a if ball_owner_team == TEAM_A else sim.team_b
	if ball_owner_index >= data.size():
		return 0.5
	return float(data[ball_owner_index].get("pass", 0.5))

func _get_pass_miss_chance(pass_distance: float = 0.0) -> float:
	var pass_stat: float = _get_pass_stat()
	# Better passers miss less often
	var base_miss: float = pass_miss_chance * (1.5 - pass_stat)
	
	# Longer passes are less accurate
	if pass_distance > 0.0:
		var distance_factor: float = pass_distance * pass_distance_accuracy_factor
		# At 200 units: +30% miss chance, at 400 units: +60% miss chance
		base_miss += distance_factor
	
	return clamp(base_miss, 0.0, 0.95)  # Cap at 95% miss chance


func _choose_pass_target_index(
	teammates: Array[Node2D],
	opponents: Array[Node2D],
	from_index: int,
	attack_direction: Vector2
) -> int:
	var from_pos: Vector2 = teammates[from_index].position

	# Check for through ball opportunity first
	if rng.randf() < through_ball_chance:
		var through_target: int = _find_through_ball_target(teammates, opponents, from_index, attack_direction)
		if through_target != -1:
			return through_target

	var candidates: Array = []
	var pressure: float = _calculate_pressure()
	
	# Reduce minimum distance when under pressure
	var effective_min_distance: float = min_pass_distance
	if pressure > 0.6:
		effective_min_distance = min_pass_distance * 0.6  # Allow shorter passes under pressure
	
	for i in range(teammates.size()):
		if i == from_index:
			continue

		var to_pos: Vector2 = teammates[i].position
		var dist: float = from_pos.distance_to(to_pos)
		
		# Use adjusted minimum distance
		if dist > pass_max_distance or dist < effective_min_distance:
			continue

		candidates.append({"i": i, "d": dist})

	if candidates.is_empty():
		# Still no candidates? Try emergency fallback with even shorter passes
		return _find_emergency_pass_target(teammates, from_index, effective_min_distance * 0.5)

	candidates.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))

	var best_index: int = -1
	var best_score: float = -999999.0

	var count: int = min(pass_candidate_count, candidates.size())
	for k in range(count):
		var i: int = int(candidates[k]["i"])
		var dist: float = float(candidates[k]["d"])
		var to_pos: Vector2 = teammates[i].position

		var openness: float = _openness_at_point(opponents, to_pos)
		var forward: float = (to_pos - from_pos).dot(attack_direction)

		# Realism improvements:
		# 1. Prefer passes to players in space (higher openness bonus)
		# 2. Bonus for passes that break lines (forward passes with good openness)
		# 3. Penalty for risky backward passes
		var score: float = (openness * weight_openness) + (forward * weight_forward) - (dist * weight_distance)
		
		# Bonus for forward passes into space
		if forward > 20.0 and openness > 50.0:
			score += 30.0
		
		# Penalty for backward passes
		if forward < -10.0:
			score -= 80.0
		elif forward < 5.0:
			score -= 20.0
		
		# Prefer passes to forwards when in attacking positions
		var ball_progress: float = 0.0
		if ball_owner_team == TEAM_A:
			ball_progress = (from_pos.x - sim.pitch_width * 0.5) / (sim.pitch_width * 0.5)
		else:
			ball_progress = (sim.pitch_width * 0.5 - from_pos.x) / (sim.pitch_width * 0.5)
		
		if ball_progress > 0.4:  # In attacking third
			var receiver_data: Array = sim.team_a if ball_owner_team == TEAM_A else sim.team_b
			if i < receiver_data.size():
				var role: String = receiver_data[i].get("role", "MID")
				if role == "FWD":
					score += 25.0  # Prefer forwards when attacking

		if score > best_score:
			best_score = score
			best_index = i

	return best_index


func _find_emergency_pass_target(teammates: Array[Node2D], from_index: int, _min_dist: float) -> int:
	# Last resort: find ANY teammate, even very close ones
	var from_pos: Vector2 = teammates[from_index].position
	var best_index: int = -1
	var best_score: float = -999999.0
	
	var attack_dir: Vector2 = Vector2(1.0, 0.0) if ball_owner_team == TEAM_A else Vector2(-1.0, 0.0)
	
	for i in range(teammates.size()):
		if i == from_index:
			continue
		
		var to_pos: Vector2 = teammates[i].position
		var dist: float = from_pos.distance_to(to_pos)
		
		# Must be at least a tiny bit away (5 units)
		if dist < 5.0:
			continue
		
		# Strongly prefer forward passes even in emergency
		var forward: float = (to_pos - from_pos).dot(attack_dir)
		var score: float = forward * 2.0 - dist * 0.5
		
		if score > best_score:
			best_score = score
			best_index = i
	
	return best_index


func _find_fallback_pass_target(teammates: Array[Node2D], from_index: int) -> int:
	# Fallback: find ANY teammate within reasonable distance (closer than max, but allow shorter)
	var from_pos: Vector2 = teammates[from_index].position
	var best_index: int = -1
	var best_dist: float = pass_max_distance * 1.5  # Allow slightly longer for fallback
	
	for i in range(teammates.size()):
		if i == from_index:
			continue
		
		var to_pos: Vector2 = teammates[i].position
		var dist: float = from_pos.distance_to(to_pos)
		
		# Must be at least minimum distance away
		if dist < min_pass_distance:
			continue
		
		# Prefer closer teammates for fallback
		if dist < best_dist:
			best_dist = dist
			best_index = i
	
	return best_index

func _find_through_ball_target(
	teammates: Array[Node2D],
	opponents: Array[Node2D],
	from_index: int,
	attack_direction: Vector2
) -> int:
	# Look for teammates making forward runs who have space behind defenders
	var from_pos: Vector2 = teammates[from_index].position
	var best_target: int = -1
	var best_score: float = 0.0
	
	for i in range(teammates.size()):
		if i == from_index:
			continue
		
		var teammate_pos: Vector2 = teammates[i].position
		var forward: float = (teammate_pos - from_pos).dot(attack_direction)
		
		# Only consider forward runs
		if forward < 30.0:
			continue
		
		# Calculate where teammate will be (project forward)
		var projected_pos: Vector2 = teammate_pos + attack_direction * through_ball_lead_distance
		
		# Check if there's space behind defenders
		var space_behind: float = _space_behind_defenders(opponents, projected_pos, attack_direction)
		
		# Check if pass is within range and minimum distance
		var dist: float = from_pos.distance_to(projected_pos)
		if dist > pass_max_distance * 1.2 or dist < min_pass_distance:  # Through balls can be slightly longer
			continue
		
		# Score based on space and forwardness
		var score: float = space_behind * 2.0 + forward * 0.5
		
		# Prefer forwards for through balls
		var receiver_data: Array = sim.team_a if ball_owner_team == TEAM_A else sim.team_b
		if i < receiver_data.size():
			var role: String = receiver_data[i].get("role", "MID")
			if role == "FWD":
				score += 40.0
			elif role == "MID":
				score += 20.0
		
		if score > best_score:
			best_score = score
			best_target = i
	
	# Only return if we found a good opportunity
	if best_score > 50.0:
		return best_target
	
	return -1

func _space_behind_defenders(opponents: Array[Node2D], target_pos: Vector2, attack_direction: Vector2) -> float:
	# Find the nearest defender ahead of the target position
	var nearest_defender_dist: float = 999999.0
	
	for opp in opponents:
		var to_defender: Vector2 = opp.position - target_pos
		var forward_to_defender: float = to_defender.dot(attack_direction)
		
		# Only consider defenders ahead of target
		if forward_to_defender > 0:
			var dist: float = to_defender.length()
			if dist < nearest_defender_dist:
				nearest_defender_dist = dist
	
	# More space = higher score (clamp to reasonable range)
	return clamp(nearest_defender_dist, 0.0, 150.0)


func _openness_at_point(opponents: Array[Node2D], point: Vector2) -> float:
	var nearest: float = 999999.0
	for o in opponents:
		var d: float = o.position.distance_to(point)
		if d < nearest:
			nearest = d
	return clamp(nearest, 0.0, 220.0)


func _set_anchor_for_owner(pos: Vector2) -> void:
	if ball_owner_team == TEAM_A:
		sim.team_a_positions[ball_owner_index] = pos
	else:
		sim.team_b_positions[ball_owner_index] = pos


func _try_tackle_dribbler(dt: float) -> void:
	if not dribble_active:
		return

	var defenders: Array[Node2D] = team_b_players if ball_owner_team == TEAM_A else team_a_players
	var defender_data: Array = sim.team_b if ball_owner_team == TEAM_A else sim.team_a
	var owner: Node2D = _get_owner_node()
	var owner_pos: Vector2 = owner.position
	var owner_data: Array = sim.team_a if ball_owner_team == TEAM_A else sim.team_b
	var owner_dribble: float = float(owner_data[ball_owner_index].get("dribble", 0.5))

	for i in range(defenders.size()):
		var d: Node2D = defenders[i]
		var dist: float = d.position.distance_to(owner_pos)
		if dist <= tackle_radius:
			var defender_tackle: float = float(defender_data[i].get("tackle", 0.5))
			# Tackle success based on defender's tackle stat vs attacker's dribble stat
			var base_chance: float = tackle_chance_per_sec * dt
			var stat_modifier: float = (defender_tackle - owner_dribble + 1.0) * 0.5  # 0.25 to 1.0 multiplier
			var chance: float = base_chance * stat_modifier
			
			if rng.randf() < chance:
				dribble_active = false
				_set_ball_owner(TEAM_B if ball_owner_team == TEAM_A else TEAM_A, i)
				ball_last_touched_by = ball_owner_team
				_set_anchor_for_owner(d.position)
				return


func _try_intercept_pass(dt: float) -> bool:
	var defenders: Array[Node2D] = team_b_players if pending_receiver_team == TEAM_A else team_a_players
	var defender_data: Array = sim.team_b if pending_receiver_team == TEAM_A else sim.team_a
	
	# Calculate pass direction for awareness check
	var pass_direction: Vector2 = (ball_end - ball_start).normalized()
	
	for i in range(defenders.size()):
		var d: Node2D = defenders[i]
		var p: Vector2 = d.position
		var closest: Vector2 = _closest_point_on_segment(ball_start, ball_end, p)
		var dist: float = p.distance_to(closest)

		if dist <= intercept_radius:
			# Check if defender is actually between passer and receiver
			var defender_to_ball: Vector2 = (closest - p).normalized()
			var facing_pass: float = defender_to_ball.dot(pass_direction)
			
			# Only intercept if defender is somewhat facing the pass
			if facing_pass < -0.3:  # Behind the pass
				continue
			
			var defender_tackle: float = float(defender_data[i].get("tackle", 0.5))
			var passer_pass_stat: float = _get_pass_stat()
			
			var base_chance: float = intercept_chance_per_sec * dt
			# Boost chance if well-positioned (facing the pass)
			var position_bonus: float = max(0.0, -facing_pass) * 0.3
			var stat_modifier: float = (defender_tackle - passer_pass_stat + 1.0) * 0.5
			var chance: float = (base_chance + position_bonus) * stat_modifier
			
			if rng.randf() < chance:
				ball_in_flight = false
				_set_ball_owner(TEAM_B if pending_receiver_team == TEAM_A else TEAM_A, i)
				ball_last_touched_by = ball_owner_team
				_set_anchor_for_owner(d.position)
				return true

	return false


func _resolve_shot() -> void:
	# Ball has arrived at target - check if goalkeeper saved it
	var defending_team = (TEAM_B if ball_owner_team == TEAM_A else TEAM_A)
	var gk_node: Node2D = team_a_players[0] if defending_team == TEAM_A else team_b_players[0]
	var ball_arrival_pos: Vector2 = ball_end
	var gk_distance: float = gk_node.position.distance_to(ball_arrival_pos)
	
	# First check: is it on target?
	var on_target: bool = rng.randf() < shot_on_target_prob
	if not on_target:
		# Miss -> goal kick to defending team
		gk_saving = false
		_goal_kick_to_defending_gk()
		return
	
	# Shot is on target - now check goalkeeper save
	# Get shooter stats for better accuracy
	var shooter_data: Array = sim.team_a if ball_owner_team == TEAM_A else sim.team_b
	var shooter_skill: float = 0.5
	if ball_owner_index < shooter_data.size():
		# Use a combination of pass (accuracy) and dribble (technique) for shooting
		var pass_stat: float = float(shooter_data[ball_owner_index].get("pass", 0.5))
		var dribble_stat: float = float(shooter_data[ball_owner_index].get("dribble", 0.5))
		shooter_skill = (pass_stat + dribble_stat) / 2.0
	
	# Calculate shot quality based on distance and angle
	var shot_distance: float = ball_start.distance_to(ball_end)
	var goal_center: Vector2 = _goal_center_for_team(defending_team)
	var attack_dir: Vector2 = Vector2(1.0, 0.0) if ball_owner_team == TEAM_A else Vector2(-1.0, 0.0)
	var to_goal: Vector2 = (goal_center - ball_start).normalized()
	var angle_quality: float = max(0.0, to_goal.dot(attack_dir))
	
	# Shot quality affects goal probability
	var distance_factor: float = clamp(1.0 - (shot_distance / 250.0), 0.3, 1.0)  # Closer = better
	var angle_factor: float = clamp(angle_quality, 0.5, 1.0)  # Better angle = better chance
	var skill_factor: float = 0.7 + (shooter_skill * 0.6)  # 0.7 to 1.3 multiplier
	
	var goal_probability: float = shot_goal_prob * distance_factor * angle_factor * skill_factor
	goal_probability = clamp(goal_probability, 0.05, 0.85)  # Between 5% and 85%
	
	# Check if goalkeeper can reach the shot
	var save_radius: float = 45.0  # How close GK needs to be
	var gk_reached_ball: bool = gk_distance <= save_radius
	
	if gk_reached_ball:
		# Goalkeeper is in position - can they save it?
		# Get GK stats
		var gk_data: Array = sim.team_a if defending_team == TEAM_A else sim.team_b
		var gk_skill: float = float(gk_data[0].get("tackle", 0.5))  # Using tackle as GK skill
		
		# Save probability depends on GK skill vs shot quality
		var base_save_chance: float = keeper_save_prob
		var skill_difference: float = gk_skill - shooter_skill
		var adjusted_save_chance: float = base_save_chance + (skill_difference * 0.3)
		adjusted_save_chance = clamp(adjusted_save_chance, 0.2, 0.9)
		
		var saved: bool = rng.randf() < adjusted_save_chance
		if saved:
			# Successful save
			_gk_save_successful(defending_team, ball_arrival_pos)
			gk_saving = false
			return
		else:
			# GK reached but couldn't save - likely a goal or rebound
			if rng.randf() < 0.7:  # 70% chance it's a goal if GK fails
				_register_goal_for(ball_owner_team)
				var conceded_team = (TEAM_B if ball_owner_team == TEAM_A else TEAM_A)
				_kickoff_after_goal(conceded_team)
				gk_saving = false
				return
			else:
				# Rebound - loose ball
				ball_dot.position = ball_arrival_pos
				_start_loose_ball()
				gk_saving = false
				return
	
	# Goalkeeper didn't reach the shot - check if it's a goal
	var goal_happens: bool = rng.randf() < goal_probability
	if goal_happens:
		_register_goal_for(ball_owner_team)
		var conceded_team = (TEAM_B if ball_owner_team == TEAM_A else TEAM_A)
		_kickoff_after_goal(conceded_team)
		gk_saving = false
	else:
		# On target but somehow missed (hit post, bar, etc.)
		# 50/50 - either goal kick or corner
		if rng.randf() < 0.5:
			_goal_kick_to_defending_gk()
		else:
			# Ball deflected out for corner
			ball_dot.position = ball_arrival_pos
			_start_loose_ball()
		gk_saving = false


func _start_shot() -> void:
	var defending_team: int = TEAM_B if ball_owner_team == TEAM_A else TEAM_A
	var goal_center: Vector2 = _goal_center_for_team(defending_team)
	
	var aim_y: float = goal_center.y + rng.randf_range(-goal_half_height, goal_half_height)
	var target: Vector2 = Vector2(goal_center.x, aim_y)
	
	var shooter: Node2D = _get_owner_node()
	
	ball_action = "SHOT"
	ball_in_flight = true
	ball_t = 0.0
	ball_start = shooter.position + _get_ball_offset(ball_owner_team)
	ball_end = target
	
	var dist: float = ball_start.distance_to(ball_end)
	var shot_speed: float = 1400.0  # Increased from shot_speed_divisor
	var seconds: float = dist / shot_speed
	ball_travel_time = clamp(seconds, 0.2, 0.6)
	
	# Start goalkeeper save attempt
	gk_saving = true
	gk_save_target = target  # Goalkeeper will move toward shot target
	
	pending_receiver_team = defending_team
	pending_receiver_index = 0
	pending_receiver = _get_receiver_node()


func _closest_point_on_segment(a: Vector2, b: Vector2, p: Vector2) -> Vector2:
	var ab: Vector2 = b - a
	var ab_len2: float = ab.length_squared()
	if ab_len2 <= 0.0:
		return a
	var t: float = clamp((p - a).dot(ab) / ab_len2, 0.0, 1.0)
	return a + ab * t


func _goal_center_for_team(defending_team: int) -> Vector2:
	if defending_team == TEAM_A:
		return Vector2(20.0, sim.pitch_height * 0.5)
	else:
		return Vector2(sim.pitch_width - 20.0, sim.pitch_height * 0.5)


func _is_in_shooting_zone(attacking_team: int, pos: Vector2) -> bool:
	var center_y: float = sim.pitch_height * 0.5
	if abs(pos.y - center_y) > shot_max_y_from_center:
		return false
	
	if attacking_team == TEAM_A:
		return pos.x >= sim.pitch_width * shot_min_x_frac
	else:
		return pos.x <= sim.pitch_width * (1.0 - shot_min_x_frac)

func _get_shoot_probability(attacking_team: int, pos: Vector2) -> float:
	var probability: float = shot_chance
	
	var goal_center: Vector2 = _goal_center_for_team(TEAM_B if attacking_team == TEAM_A else TEAM_A)
	var distance_to_goal: float = pos.distance_to(goal_center)
	
	# Less likely to shoot from far
	if distance_to_goal > 250.0:
		return probability * 0.3
	elif distance_to_goal > 180.0:
		return probability * 0.6
	
	# Much more likely when close and central
	if distance_to_goal < 100.0:
		probability = 0.85
	
	# Check angle to goal - don't shoot from tight angles
	var to_goal: Vector2 = goal_center - pos
	var attack_dir: Vector2 = Vector2(1.0, 0.0) if attacking_team == TEAM_A else Vector2(-1.0, 0.0)
	var angle_quality: float = to_goal.normalized().dot(attack_dir)
	
	# From tight angles (side of goal), much less likely
	if angle_quality < 0.3:
		probability *= 0.2
	
	return clamp(probability, 0.05, 0.95)


func _register_goal_for(scoring_team: int) -> void:
	if scoring_team == TEAM_A:
		score_a += 1
	else:
		score_b += 1
	print("GOAL! A %d - %d B" % [score_a, score_b])


func _move_goalkeeper_to_save(dt: float) -> void:
	if not gk_saving or not ball_in_flight or ball_action != "SHOT":
		return
	
	var defending_team = (TEAM_B if ball_owner_team == TEAM_A else TEAM_A)
	var gk_nodes: Array[Node2D] = team_a_players if defending_team == TEAM_A else team_b_players
	var gk_velocities: Array[Vector2] = team_a_velocities if defending_team == TEAM_A else team_b_velocities
	
	if gk_nodes.is_empty() or gk_velocities.is_empty():
		return
	
	var gk: Node2D = gk_nodes[0]  # Goalkeeper is always index 0
	
	# Calculate where ball will be (interpolate along flight path)
	var alpha: float = clamp(ball_t / ball_travel_time, 0.0, 1.0)
	var ball_current_pos: Vector2 = ball_start.lerp(ball_end, alpha)
	
	# Move goalkeeper toward ball's current position (they react to the shot)
	var to_ball: Vector2 = ball_current_pos - gk.position
	var distance: float = to_ball.length()
	
	if distance > 2.0:
		var max_speed: float = _get_player_speed(defending_team, 0)
		var desired_velocity: Vector2 = to_ball.normalized() * max_speed * 1.2  # GK moves faster for saves
		
		# Apply acceleration toward ball
		var acceleration: float = 1500.0  # Strong acceleration for saves
		var accel_vec: Vector2 = (desired_velocity - gk_velocities[0]) * acceleration * dt
		gk_velocities[0] += accel_vec
		
		# Clamp velocity
		if gk_velocities[0].length() > max_speed * 1.2:
			gk_velocities[0] = gk_velocities[0].normalized() * max_speed * 1.2

func _check_goalkeeper_save_during_flight() -> void:
	# Check if goalkeeper reaches ball during flight (early save)
	var defending_team = (TEAM_B if ball_owner_team == TEAM_A else TEAM_A)
	var gk_node: Node2D = team_a_players[0] if defending_team == TEAM_A else team_b_players[0]
	
	# Calculate ball's current position
	var alpha: float = clamp(ball_t / ball_travel_time, 0.0, 1.0)
	var ball_current_pos: Vector2 = ball_start.lerp(ball_end, alpha)
	
	var gk_distance: float = gk_node.position.distance_to(ball_current_pos)
	var save_radius: float = 30.0  # Slightly smaller for in-flight saves
	
	if gk_distance <= save_radius:
		# Goalkeeper saved it during flight
		var saved: bool = rng.randf() < keeper_save_prob
		if saved:
			ball_in_flight = false
			gk_saving = false
			_gk_save_successful(defending_team, ball_current_pos)
		# If not saved, ball continues (could be deflection)

func _gk_save_successful(defending_team: int, save_position: Vector2) -> void:
	# Goalkeeper successfully saved - give them possession at save location
	ball_action = "PASS"
	dribble_active = false
	ball_in_flight = false
	ball_free = false
	
	_set_ball_owner(defending_team, 0)
	
	# Move goalkeeper to save position and give them the ball
	var gk_node: Node2D = _get_owner_node()
	gk_node.position = save_position
	ball_dot.position = save_position + _get_ball_offset(defending_team)
	_set_anchor_for_owner(save_position)

func _gk_possession(defending_team: int) -> void:
	ball_action = "PASS"
	dribble_active = false
	ball_in_flight = false
	gk_saving = false
	
	_set_ball_owner(defending_team, 0)
	
	var gk_node: Node2D = _get_owner_node()
	_set_anchor_for_owner(gk_node.position)


func _goal_kick_to_defending_gk() -> void:
	var defending_team = (TEAM_B if ball_owner_team == TEAM_A else TEAM_A)
	_gk_possession(defending_team)


func _kickoff_after_goal(conceded_team: int) -> void:
	if sim.has_method("reset_to_home"):
		sim.reset_to_home()
	
	ball_action = "PASS"
	dribble_active = false
	ball_in_flight = false
	
	var kickoff_index: int = 9
	if conceded_team == TEAM_A and team_a_players.size() > 9:
		kickoff_index = 9
	elif conceded_team == TEAM_B and team_b_players.size() > 9:
		kickoff_index = 9
	_set_ball_owner(conceded_team, kickoff_index)
	
	var center: Vector2 = Vector2(sim.pitch_width * 0.5, sim.pitch_height * 0.5)
	var owner: Node2D = _get_owner_node()
	owner.position = center
	_set_anchor_for_owner(owner.position)


func _start_loose_ball() -> void:
	ball_in_flight = false
	ball_free = true
	
	# If ball_velocity is already set (from pass arrival), keep it
	# Otherwise generate random velocity
	if ball_velocity.length() < 10.0:
		if ball_action == "PASS":
			var dir := (ball_end - ball_start).normalized()
			ball_velocity = dir * rng.randf_range(60.0, 120.0)
		else:
			ball_velocity = Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-40.0, 40.0))


func _tick_loose_ball(dt: float) -> void:
	if not ball_free:
		return

	# Update ball physics
	_apply_ball_physics(dt)
	
	# Check for pickup (check ALL players, not just nearest at one moment)
	_check_ball_pickup()

func _apply_ball_physics(dt: float) -> void:
	# Apply velocity with smoother deceleration
	var new_pos: Vector2 = ball_dot.position + ball_velocity * dt
	
	# Apply friction with non-linear decay (feels more natural)
	var current_speed: float = ball_velocity.length()
	if current_speed > 0.1:
		# Faster decay at higher speeds
		var friction_amount: float = loose_ball_friction * (1.0 + current_speed / 100.0)
		ball_velocity = ball_velocity.move_toward(Vector2.ZERO, friction_amount * 100.0 * dt)
	else:
		ball_velocity = Vector2.ZERO
	
	# Check for out of bounds BEFORE moving
	if _check_position_out_of_bounds(new_pos):
		_handle_ball_out_of_bounds()
		return
	
	# Update position
	ball_dot.position = new_pos
	
	# Bounce off walls with energy loss
	if ball_dot.position.x <= goal_line_margin or ball_dot.position.x >= sim.pitch_width - goal_line_margin:
		ball_velocity.x *= -0.5  # More energy loss on bounce
		ball_dot.position.x = clamp(ball_dot.position.x, goal_line_margin, sim.pitch_width - goal_line_margin)
	
	if ball_dot.position.y <= touchline_margin or ball_dot.position.y >= sim.pitch_height - touchline_margin:
		ball_velocity.y *= -0.5
		ball_dot.position.y = clamp(ball_dot.position.y, touchline_margin, sim.pitch_height - touchline_margin)

func _check_position_out_of_bounds(pos: Vector2) -> bool:
	return pos.x < goal_line_margin or pos.x > sim.pitch_width - goal_line_margin or \
		   pos.y < touchline_margin or pos.y > sim.pitch_height - touchline_margin

func _apply_loose_ball_target_overrides() -> void:
	# Find the nearest player from each team to chase the ball
	var nearest_a := _nearest_player_from_team_to_point(TEAM_A, ball_dot.position)
	var nearest_b := _nearest_player_from_team_to_point(TEAM_B, ball_dot.position)
	
	# Make one player from each team chase the ball if within chase distance
	if nearest_a["dist"] < loose_ball_chase_distance:
		var chase_index_a: int = nearest_a["index"]
		if chase_index_a < sim.team_a_targets.size():
			# Override their target to be the ball position (they'll chase it)
			sim.team_a_targets[chase_index_a] = ball_dot.position
	
	if nearest_b["dist"] < loose_ball_chase_distance:
		var chase_index_b: int = nearest_b["index"]
		if chase_index_b < sim.team_b_targets.size():
			# Override their target to be the ball position (they'll chase it)
			sim.team_b_targets[chase_index_b] = ball_dot.position
	
	# Also override targets for players very close to ball (prevents semi-circle running)
	# This ensures smooth pickup when they get close
	for i in range(team_a_players.size()):
		var dist: float = team_a_players[i].position.distance_to(ball_dot.position)
		if dist < loose_ball_override_target_distance:
			if i < sim.team_a_targets.size():
				sim.team_a_targets[i] = ball_dot.position
	
	for i in range(team_b_players.size()):
		var dist: float = team_b_players[i].position.distance_to(ball_dot.position)
		if dist < loose_ball_override_target_distance:
			if i < sim.team_b_targets.size():
				sim.team_b_targets[i] = ball_dot.position

func _check_ball_pickup() -> void:
	# Check ALL players to find the actual nearest one
	var best_team := TEAM_A
	var best_index := 0
	var best_dist := 999999.0
	
	# Check Team A
	for i in range(team_a_players.size()):
		var dist: float = team_a_players[i].position.distance_to(ball_dot.position)
		if dist < best_dist:
			best_dist = dist
			best_team = TEAM_A
			best_index = i
	
	# Check Team B
	for i in range(team_b_players.size()):
		var dist: float = team_b_players[i].position.distance_to(ball_dot.position)
		if dist < best_dist:
			best_dist = dist
			best_team = TEAM_B
			best_index = i
	
	# If nearest player is within pickup radius, give them the ball
	if best_dist <= loose_pickup_radius:
		ball_free = false
		_set_ball_owner(best_team, best_index)
		
		# Move player slightly toward ball if not exactly on it
		var owner: Node2D = _get_owner_node()
		if best_dist > 2.0:
			owner.position = owner.position.move_toward(ball_dot.position, best_dist * 0.5)
		
		ball_last_touched_by = ball_owner_team
		_set_anchor_for_owner(owner.position)

func _check_ball_out_of_bounds() -> bool:
	var pos := ball_dot.position
	return pos.x < goal_line_margin or pos.x > sim.pitch_width - goal_line_margin or \
		   pos.y < touchline_margin or pos.y > sim.pitch_height - touchline_margin

func _handle_ball_out_of_bounds() -> void:
	var pos := ball_dot.position
	var was_touchline: bool = (pos.y < touchline_margin or pos.y > sim.pitch_height - touchline_margin)
	var was_goal_line: bool = (pos.x < goal_line_margin or pos.x > sim.pitch_width - goal_line_margin)
	
	# Stop the ball completely
	ball_free = false
	ball_in_flight = false  # Make sure ball is not in flight
	ball_velocity = Vector2.ZERO
	
	if was_touchline:
		# THROW-IN
		_award_throw_in(pos)
	elif was_goal_line:
		# Goal kick or corner kick
		var left_side: bool = pos.x < sim.pitch_width * 0.5
		if left_side:
			# Left side - Team A's goal area
			_gk_possession(TEAM_A)
		else:
			# Right side - Team B's goal area
			_gk_possession(TEAM_B)

func _award_throw_in(out_position: Vector2) -> void:
	"""
	Award a throw-in to the team that didn't touch it last.
	Position the player INSIDE the pitch with the ball.
	"""
	print("Throw-in awarded!")
	
	# Determine which team gets the throw
	var throwing_team: int = TEAM_B if ball_last_touched_by == TEAM_A else TEAM_A
	
	# Calculate a safe position INSIDE the pitch for the throw-in
	# Add a buffer (30 pixels) from the edge to ensure we're clearly inside
	var throw_in_pos: Vector2 = out_position
	
	# Clamp to safe boundaries (well inside the pitch)
	var safe_margin: float = 30.0  # Must be larger than touchline_margin!
	throw_in_pos.x = clamp(throw_in_pos.x, safe_margin, sim.pitch_width - safe_margin)
	throw_in_pos.y = clamp(throw_in_pos.y, safe_margin, sim.pitch_height - safe_margin)
	
	# Find nearest player from throwing team
	var nearest := _nearest_player_from_team_to_point(throwing_team, throw_in_pos)
	
	# Give that player the ball
	_set_ball_owner(throwing_team, nearest["index"])
	
	# Move the player to the throw-in position
	var thrower: Node2D = _get_owner_node()
	thrower.position = throw_in_pos
	
	# Position the ball with the player (using ball offset)
	ball_dot.position = throw_in_pos + _get_ball_offset(ball_owner_team)
	
	# Update their anchor so they don't get pulled away by formations
	_set_anchor_for_owner(throw_in_pos)
	
	# Reset any lingering states
	dribble_active = false
	throw_in_active = false  # If you added this variable
	
	print("Throw-in to Team %s at position %v" % ["A" if throwing_team == TEAM_A else "B", throw_in_pos])

func _award_corner_kick(attacking_team: int, bottom_corner: bool) -> void:
	# Determine corner position
	var corner_x: float = sim.pitch_width - 30.0 if attacking_team == TEAM_A else 30.0
	var corner_y: float = sim.pitch_height - 30.0 if bottom_corner else 30.0
	var corner_pos := Vector2(corner_x, corner_y)
	
	# Find nearest player to take corner
	var nearest := _nearest_player_from_team_to_point(attacking_team, corner_pos)
	_set_ball_owner(attacking_team, nearest["index"])
	
	var taker: Node2D = _get_owner_node()
	taker.position = corner_pos
	ball_dot.position = corner_pos
	_set_anchor_for_owner(corner_pos)
	
	print("Corner kick to Team %s" % ["A" if attacking_team == TEAM_A else "B"])

func _award_goal_kick(defending_team: int) -> void:
	print("Goal kick to Team %s" % ["A" if defending_team == TEAM_A else "B"])
	_gk_possession(defending_team)

func _nearest_player_from_team(team_id: int) -> Dictionary:
	var nodes: Array[Node2D] = team_a_players if team_id == TEAM_A else team_b_players
	var best_index := 0
	var best_dist := 999999.0
	
	for i in range(nodes.size()):
		var dist := nodes[i].position.distance_to(ball_dot.position)
		if dist < best_dist:
			best_dist = dist
			best_index = i
	
	return {"index": best_index, "dist": best_dist}


func _nearest_player_to_ball() -> Dictionary:
	return _nearest_player_to_point(ball_dot.position)

func _nearest_player_to_point(point: Vector2) -> Dictionary:
	var best_team := TEAM_A
	var best_index := 0
	var best_dist := 999999.0

	for i in range(team_a_players.size()):
		var d := team_a_players[i].position.distance_to(point)
		if d < best_dist:
			best_dist = d; best_team = TEAM_A; best_index = i

	for i in range(team_b_players.size()):
		var d := team_b_players[i].position.distance_to(point)
		if d < best_dist:
			best_dist = d; best_team = TEAM_B; best_index = i

	return {"team": best_team, "index": best_index, "dist": best_dist}

func _nearest_player_from_team_to_point(team_id: int, point: Vector2) -> Dictionary:
	var nodes: Array[Node2D] = team_a_players if team_id == TEAM_A else team_b_players
	var best_index := 0
	var best_dist := 999999.0

	for i in range(nodes.size()):
		var d := nodes[i].position.distance_to(point)
		if d < best_dist:
			best_dist = d
			best_index = i

	return {"index": best_index, "dist": best_dist}


func _tick_throw_in(dt: float) -> void:
	throw_in_timer += dt
	
	# Move thrower to throw-in position
	var thrower_nodes: Array[Node2D] = team_a_players if throw_in_taker_team == TEAM_A else team_b_players
	var thrower: Node2D = thrower_nodes[throw_in_taker_index]
	
	# Setup phase - player runs to ball
	if throw_in_timer < throw_in_setup_time:
		# Move player toward throw-in position
		thrower.position = thrower.position.move_toward(throw_in_position, 200.0 * dt)
		ball_dot.position = throw_in_position
		
		# Also update their anchor so they don't get pulled away
		_set_anchor_for_owner(thrower.position)
	else:
		# Execute the throw-in
		_execute_throw_in()


func _execute_throw_in() -> void:
	throw_in_active = false
	
	var thrower_nodes: Array[Node2D] = team_a_players if throw_in_taker_team == TEAM_A else team_b_players
	var opponent_nodes: Array[Node2D] = team_b_players if throw_in_taker_team == TEAM_A else team_a_players
	var thrower: Node2D = thrower_nodes[throw_in_taker_index]
	
	# Find best teammate to throw to
	var attack_dir: Vector2 = Vector2(1.0, 0.0) if throw_in_taker_team == TEAM_A else Vector2(-1.0, 0.0)
	var best_target: int = -1
	var best_score: float = -999999.0
	
	for i in range(thrower_nodes.size()):
		if i == throw_in_taker_index:
			continue
		
		var teammate_pos: Vector2 = thrower_nodes[i].position
		var throw_dist: float = thrower.position.distance_to(teammate_pos)
		
		# Throw-ins have limited range
		if throw_dist > throw_in_max_distance or throw_dist < 30.0:
			continue
		
		# Calculate openness (not near opponents)
		var openness: float = _openness_at_point(opponent_nodes, teammate_pos)
		
		# Calculate forward progress
		var forward: float = (teammate_pos - thrower.position).dot(attack_dir)
		
		# Score = prefer open players, slightly favor forward throws
		var score: float = openness * 0.8 + forward * 0.4 - throw_dist * 0.2
		
		if score > best_score:
			best_score = score
			best_target = i
	
	# If no good target found, throw to nearest teammate
	if best_target == -1:
		var nearest_dist: float = 999999.0
		for i in range(thrower_nodes.size()):
			if i == throw_in_taker_index:
				continue
			var teammate_dist: float = thrower.position.distance_to(thrower_nodes[i].position)
			if teammate_dist < nearest_dist and teammate_dist < throw_in_max_distance:
				nearest_dist = teammate_dist
				best_target = i
	
	# Still no target? Just give them the ball and let them dribble
	if best_target == -1:
		_set_ball_owner(throw_in_taker_team, throw_in_taker_index)
		_set_anchor_for_owner(thrower.position)
		return
	
	# Execute the throw as a pass
	var target_node: Node2D = thrower_nodes[best_target]
	
	# Use a modified pass function (throw-ins are slower and more accurate)
	ball_in_flight = true
	ball_t = 0.0
	ball_start = thrower.position
	ball_end = target_node.position
	ball_action = "PASS"
	
	# Throw-ins are more accurate (less scatter)
	var dist: float = ball_start.distance_to(ball_end)
	var small_scatter: float = 15.0  # Much less scatter than normal passes
	var scatter := Vector2(rng.randf_range(-small_scatter, small_scatter), rng.randf_range(-small_scatter, small_scatter))
	ball_end += scatter
	
	# Throw-ins are slower than normal passes
	var seconds: float = dist / 400.0  # Slower than normal passes
	ball_travel_time = clamp(seconds, 0.3, 1.0)
	
	pending_receiver_team = throw_in_taker_team
	pending_receiver_index = best_target
	pending_receiver = _get_receiver_node()
	
	# Calculate throw velocity for when it lands
	ball_end_velocity = (ball_end - ball_start).normalized() * 60.0  # Gentle throw

func switch_sides() -> void:
	"""
	Switch teams to opposite sides of the pitch.
	Much simpler now - just tell each player to switch!
	"""
	print("Switching sides...")
	
	# Stop all ball states
	ball_in_flight = false
	ball_free = false
	dribble_active = false
	ball_velocity = Vector2.ZERO
	
	var pitch_center_x: float = sim.pitch_width * 0.5
	
	# Each player handles their own side switch
	for player in all_players:
		player.switch_side(pitch_center_x)
	
	# Teams swap colors (visual indicator)
	for player in team_a_players:
		player.set_visual(TEAM_B_COLOR, 12.0)
	
	for player in team_b_players:
		player.set_visual(TEAM_A_COLOR, 12.0)
	
	# Reset ball to center
	ball_dot.position = Vector2(pitch_center_x, sim.pitch_height * 0.5)
	
	# Team B gets kickoff
	if team_b_players.size() > 9:
		ball_owner = team_b_players[9]
		ball_owner_team = TEAM_B
		ball_owner_index = 9
		ball_owner.position = ball_dot.position
	
	print("Sides switched!")
