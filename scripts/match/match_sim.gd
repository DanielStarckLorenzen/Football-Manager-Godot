extends Node

@export var pitch_width := 1000.0
@export var pitch_height := 600.0
@export var tick_rate := 10.0

const TEAM_A_COLOR := Color(0.2, 0.6, 1.0)
const TEAM_B_COLOR := Color(1.0, 0.3, 0.3)

var team_a: Array = []
var team_b: Array = []

var team_a_positions: Array[Vector2] = []
var team_b_positions: Array[Vector2] = []

var accum := 0.0

var team_a_targets: Array[Vector2] = []
var team_b_targets: Array[Vector2] = []

var _t := 0.0

var team_a_home: Array[Vector2] = []
var team_b_home: Array[Vector2] = []

var ball_pos: Vector2 = Vector2.ZERO
var ball_team: int = 0

@export var shape_slide_x := 0.22
@export var shape_slide_y := 0.14
@export var return_to_home := 0.02

@export var mark_strength := 0.30
@export var support_strength := 0.22
@export var forward_run_strength := 0.28

var ball_owner_team: int = 0
var ball_owner_index: int = 0
var ball_in_flight: bool = false

@export var press_strength: float = 0.75 # How hard pressers chase the ball
@export var second_press_strength: float = 0.45
@export var support_distance: float = 55.0
@export var support_ahead: float = 25.0

@export var defensive_line_coordination: float = 0.65  # How much defenders align to defensive line (0-1)
@export var offside_trap_chance: float = 0.25  # Chance to attempt offside trap
@export var offside_trap_distance: float = 50.0  # How far forward to move for offside trap
@export var defensive_line_spacing: float = 180.0  # Ideal spacing between defenders

var runner_team: int = -1
var runner_index: int = -1
var runner_target: Vector2 = Vector2.ZERO

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

@export var gk_base_position_offset: float = 80.0
@export var gk_max_advance: float = 150.0

func _ready() -> void:
	rng.randomize()
	team_a_positions = _make_basic_positions(true)
	team_b_positions = _make_basic_positions(false)
	
	team_a_home = team_a_positions.duplicate()
	team_b_home = team_b_positions.duplicate()
	
	team_a = _make_team_data(true)
	team_b = _make_team_data(false)
	
	# Initialize targets
	team_a_targets = _compute_team_targets(0)
	team_b_targets = _compute_team_targets(1)

func _make_team_data(_left_side: bool) -> Array:
	var players: Array = []
	
	# Index meaning (based on the formation builder):
	# 0 GK, 1-4 DEF, 5-8 MID, 9-10 FWD
	for i in range(11):
		var role := "MID"
		if i == 0: role = "GK"
		elif i <= 4: role = "DEF"
		elif i <= 8: role = "MID"
		else: role = "FWD"
		
		# Placeholder stats (later these come from the roster system)
		# For now, add some variation based on role
		var base_pace: float = 0.5
		var base_tackle: float = 0.5
		var base_pass: float = 0.5
		var base_dribble: float = 0.5
		
		# Role-based stat adjustments
		if role == "GK":
			base_pace = 0.4
			base_tackle = 0.6
			base_pass = 0.45
			base_dribble = 0.3
		elif role == "DEF":
			base_pace = 0.45
			base_tackle = 0.65
			base_pass = 0.55
			base_dribble = 0.4
		elif role == "MID":
			base_pace = 0.55
			base_tackle = 0.5
			base_pass = 0.65
			base_dribble = 0.6
		elif role == "FWD":
			base_pace = 0.65
			base_tackle = 0.4
			base_pass = 0.5
			base_dribble = 0.7
		
		# Add some random variation (±0.15)
		var p := {
			"id": i,
			"role": role,
			"pace":  clamp(base_pace + rng.randf_range(-0.15, 0.15), 0.1, 1.0),
			"tackle": clamp(base_tackle + rng.randf_range(-0.15, 0.15), 0.1, 1.0),
			"pass":  clamp(base_pass + rng.randf_range(-0.15, 0.15), 0.1, 1.0),
			"dribble": clamp(base_dribble + rng.randf_range(-0.15, 0.15), 0.1, 1.0),
			"mark_target": -1, # index of opponent being marked
		}
		players.append(p)
		
	return players

func assign_marking() -> void:
	# Team B marks Team A
	_assign_team_marking(team_b, team_b_positions, team_a_positions)
	# Team A marks Team B
	_assign_team_marking(team_a, team_a_positions, team_b_positions)

func _assign_team_marking(defenders: Array, def_pos: Array[Vector2], att_pos: Array[Vector2]) -> void:
	for i in range(defenders.size()):
		var role: String = defenders[i]["role"]
		if role == "GK":
			defenders[i]["mark_target"] = -1
			continue
		
		# DEF/MID mark closest opponent (can be refined by zones later)
		var best := -1
		var best_distance := INF
		for j in range(att_pos.size()):
			var distance := def_pos[i].distance_to(att_pos[j])
			if distance < best_distance:
				best_distance = distance
				best = j
		
		defenders[i]["mark_target"] = best

func _make_basic_positions(left_side: bool) -> Array[Vector2]:
	var positions: Array[Vector2] = []

	var x_min := 100.0
	var x_max := pitch_width - 100.0

	var left_x: float = float(lerp(x_min, x_max, 0.25))
	var right_x: float = float(lerp(x_min, x_max, 0.75))
	var base_x: float = left_x if left_side else right_x


	var gk_x: float
	var back_x: float
	var mid_x: float
	var fwd_x: float

	if left_side:
		gk_x = base_x - 250.0
		back_x = base_x - 150.0
		mid_x = base_x
		fwd_x = base_x + 180.0
	else:
		gk_x = base_x + 250.0
		back_x = base_x + 150.0
		mid_x = base_x
		fwd_x = base_x - 180.0

	var y_lanes := [80.0, 180.0, 300.0, 420.0, 520.0]

	# GK
	positions.append(Vector2(gk_x, pitch_height / 2.0))

	# Back 4
	for i in range(4):
		positions.append(Vector2(back_x, y_lanes[i]))

	# Mid 4
	for i in range(4):
		positions.append(Vector2(mid_x, y_lanes[i]))

	# Front 2
	positions.append(Vector2(fwd_x, pitch_height / 2.0 - 70.0))
	positions.append(Vector2(fwd_x, pitch_height / 2.0 + 70.0))

	return positions

# Smooth target updates to reduce jitter
var _target_update_timer: float = 0.0
var _target_update_interval: float = 0.05  # Update targets 20 times per second instead of every tick

func tick(delta: float) -> void:
	_t += delta
	assign_marking()
	_update_team_anchors_toward_home()

	# NEW: choose a depth runner for the team in possession (only when ball not in flight)
	runner_team = -1
	runner_index = -1
	if (not ball_in_flight):
		_pick_runner_for_team(ball_owner_team)

	# Update targets less frequently to reduce jitter
	_target_update_timer += delta
	if _target_update_timer >= _target_update_interval:
		_target_update_timer = 0.0
		team_a_targets = _compute_team_targets(0)
		team_b_targets = _compute_team_targets(1)


func _update_team_anchors_toward_home() -> void:
	var a_rate: float = return_to_home * 0.5
	var b_rate: float = return_to_home * 0.5
	
	if ball_owner_team == 0:
		a_rate *= 0.08
		b_rate *= 0.85
	else:
		b_rate *= 0.08
		a_rate *= 0.85
	
	# Gentle pull back toward original formation over time
	for i in range(team_a_positions.size()):
		team_a_positions[i] = team_a_positions[i].lerp(team_a_home[i], a_rate)
	
	for i in range(team_b_positions.size()):
		team_b_positions[i] = team_b_positions[i].lerp(team_b_home[i], b_rate)

func _compute_team_targets(team_id: int) -> Array[Vector2]:
	var anchors: Array[Vector2] = team_a_positions if team_id == 0 else team_b_positions
	var opp_anchors: Array[Vector2] = team_b_positions if team_id == 0 else team_a_positions
	var data: Array = team_a if team_id == 0 else team_b
	var defending: bool = (ball_owner_team != team_id)
	
	var context := _build_team_context(team_id, anchors, data, defending)
	
	var targets: Array[Vector2] = []
	for i in range(anchors.size()):
		var desired := _compute_player_target(i, team_id, anchors, opp_anchors, data, context)
		targets.append(desired)
	
	return targets

func _build_team_context(team_id: int, anchors: Array[Vector2], data: Array, defending: bool) -> Dictionary:
	var context := {}
	context.defending = defending
	context.attack_direction = Vector2(1, 0) if team_id == 0 else Vector2(-1, 0)
	
	# Ball position relative to center for shape sliding
	var center := Vector2(pitch_width * 0.5, pitch_height * 0.5)
	var rel := (ball_pos - center)
	context.rel_x = rel.x / pitch_width
	context.rel_y = rel.y / pitch_height
	
	# Shape slide amounts
	context.slide_x = shape_slide_x
	context.slide_y = shape_slide_y
	if ball_owner_team == team_id:
		context.slide_x *= 0.35
		context.slide_y *= 0.25
	
	# Pressing setup
	context.presser_indices = []
	if defending:
		var allowed_press: Array[String] = _allowed_press_roles(team_id)
		context.presser_indices = _closest_players_to_point_filtered(anchors, ball_pos, 2, data, allowed_press, -1)
	
	# Support setup - get more supporters for better involvement
	context.supporter_indices = []
	context.support_spots = []
	if (not defending) and (not ball_in_flight):
		var carrier_pos: Vector2 = anchors[ball_owner_index]
		var allowed_support = _allowed_support_roles(team_id)
		# Get 4 supporters instead of 2 for better team involvement
		context.supporter_indices = _closest_players_to_point_filtered(anchors, carrier_pos, 4, data, allowed_support, ball_owner_index)
		context.support_spots = _support_spots(team_id, carrier_pos)
	
	# Defensive line coordination setup
	if defending:
		context["defensive_line_x"] = _calculate_defensive_line_x(anchors, data)
		context["offside_trap_active"] = _should_attempt_offside_trap(team_id, anchors, data)
	else:
		context["defensive_line_x"] = 0.0
		context["offside_trap_active"] = false
	
	return context

func _compute_player_target(
	player_index: int,
	team_id: int,
	anchors: Array[Vector2],
	opp_anchors: Array[Vector2],
	data: Array,
	context: Dictionary
) -> Vector2:
	var role: String = data[player_index]["role"]
	var desired := anchors[player_index]
	
	# Special GK positioning when defending
	if role == "GK" and context.defending:
		desired = _get_goalkeeper_position(team_id, anchors[player_index])
	
	# Apply shape sliding based on ball position
	if role != "GK":  # Don't slide GK
		desired = _apply_shape_slide(desired, context)
	
	# Apply shape sliding based on ball position
	desired = _apply_shape_slide(desired, context)
	
	# Apply role-based behavior (attacking or defending)
	if ball_owner_team == team_id:
		desired += _attack_offset(role, player_index, anchors, context.attack_direction)
	else:
		desired += _defend_offset(role, player_index, data, opp_anchors)
		# Apply defensive line coordination for defenders
		if role == "DEF":
			desired = _apply_defensive_line_coordination(desired, player_index, anchors, data, context)
	
	# Apply depth run override
	desired = _apply_depth_run(desired, player_index, team_id)
	
	# Apply pressing behavior
	desired = _apply_pressing(desired, player_index, context)
	
	# Apply support behavior
	desired = _apply_support(desired, player_index, context)
	
	# Apply separation to avoid clustering
	desired += _seperation_offset(player_index, anchors, 22.0, 18.0)
	
	# Apply role-based boundary constraints
	desired = _apply_role_boundaries(desired, role, team_id)
	
	return desired

func _apply_role_boundaries(position: Vector2, role: String, team_id: int) -> Vector2:
	var constrained := position
	
	# Define boundaries based on role and team
	var min_x: float = 20.0
	var max_x: float = pitch_width - 20.0
	var min_y: float = 20.0
	var max_y: float = pitch_height - 20.0
	
	# Role-based X constraints (prevent players from going to wrong areas)
	if role == "GK":
		# Goalkeeper stays in defensive third
		if team_id == 0:  # Team A (left side)
			max_x = pitch_width * 0.35
		else:  # Team B (right side)
			min_x = pitch_width * 0.65
	elif role == "DEF":
		# Defenders shouldn't go too far forward (stay in defensive half mostly)
		if team_id == 0:
			max_x = pitch_width * 0.65  # Can push forward but not too much
		else:
			min_x = pitch_width * 0.35
	elif role == "MID":
		# Midfielders have more freedom but shouldn't go to goalkeeper line
		if team_id == 0:
			min_x = pitch_width * 0.15  # Don't go back to GK line
			max_x = pitch_width * 0.90
		else:
			min_x = pitch_width * 0.10
			max_x = pitch_width * 0.85
	elif role == "FWD":
		# Forwards shouldn't go back to defensive line
		if team_id == 0:
			min_x = pitch_width * 0.25  # Don't go back too far
		else:
			max_x = pitch_width * 0.75
	
	# Apply constraints
	constrained.x = clamp(constrained.x, min_x, max_x)
	constrained.y = clamp(constrained.y, min_y, max_y)
	
	return constrained

func _apply_shape_slide(position: Vector2, context: Dictionary) -> Vector2:
	var adjusted := position
	adjusted.x += context.rel_x * pitch_width * context.slide_x
	adjusted.y += context.rel_y * pitch_height * context.slide_y
	return adjusted

func _apply_depth_run(position: Vector2, player_index: int, team_id: int) -> Vector2:
	if (ball_owner_team == team_id) and (runner_team == team_id) and (player_index == runner_index):
		return position.lerp(runner_target, 0.9)
	return position

func _apply_pressing(position: Vector2, player_index: int, context: Dictionary) -> Vector2:
	if not context.defending:
		return position
	
	var pressers: Array[int] = context.presser_indices
	if pressers.is_empty():
		return position
	
	if player_index == pressers[0]:
		return position.lerp(ball_pos, press_strength)
	elif pressers.size() > 1 and player_index == pressers[1]:
		return position.lerp(ball_pos, second_press_strength)
	
	return position

func _apply_support(position: Vector2, player_index: int, context: Dictionary) -> Vector2:
	if context.defending or ball_in_flight:
		return position
	
	var supporters: Array[int] = context.supporter_indices
	var spots: Array[Vector2] = context.support_spots
	
	if supporters.is_empty():
		return position
	
	# Apply support to multiple players with varying strength
	var support_lerp: float = 0.0
	var target_spot: Vector2 = Vector2.ZERO
	
	if player_index == supporters[0] and spots.size() > 0:
		support_lerp = 0.85
		target_spot = spots[0]
	elif supporters.size() > 1 and player_index == supporters[1] and spots.size() > 1:
		support_lerp = 0.75
		target_spot = spots[1]
	elif supporters.size() > 2 and player_index == supporters[2]:
		# Third supporter - create additional spot or use existing
		if spots.size() > 0:
			var carrier_pos: Vector2 = team_a_positions[ball_owner_index] if ball_owner_team == 0 else team_b_positions[ball_owner_index]
			var attack_dir: Vector2 = context.attack_direction
			target_spot = carrier_pos + attack_dir * support_ahead * 0.5 + Vector2(0, (player_index % 2 - 0.5) * support_distance * 1.5)
			support_lerp = 0.65
	elif supporters.size() > 3 and player_index == supporters[3]:
		var carrier_pos: Vector2 = team_a_positions[ball_owner_index] if ball_owner_team == 0 else team_b_positions[ball_owner_index]
		var attack_dir: Vector2 = context.attack_direction
		target_spot = carrier_pos + attack_dir * support_ahead * 0.3 + Vector2(0, (player_index % 2 - 0.5) * support_distance * 2.0)
		support_lerp = 0.55
	
	if support_lerp > 0.0:
		return position.lerp(target_spot, support_lerp)
	
	return position

func _attack_offset(role: String, i: int, anchors: Array[Vector2], attack_direction: Vector2) -> Vector2:
	var off := Vector2.ZERO
	
	# Base forward movement by role
	if role == "DEF":
		off += attack_direction * 30.0  # Slightly more forward
	elif role == "MID":
		off += attack_direction * 80.0  # Much more aggressive forward movement
	elif role == "FWD":
		off += attack_direction * 90.0
	
	# Midfielders actively move toward ball and forward
	if role == "MID":
		var to_ball: Vector2 = ball_pos - anchors[i]
		var forward_component: float = to_ball.dot(attack_direction)
		# Move forward more when ball is ahead, less when behind
		if forward_component > 0:
			off += attack_direction * forward_component * 0.25
		# Also move toward ball laterally
		off += to_ball * support_strength * 0.20
	
	# Forwards make stronger forward runs when ball is central
	var center_y := pitch_height * 0.5
	var ball_centrality: float = 1.0 - min(abs(ball_pos.y - center_y) / center_y, 1.0)
	if role == "FWD":
		off += attack_direction * (forward_run_strength * 100.0 * ball_centrality)
	
	# Defenders can push forward more when ball is deep in opponent half
	var ball_progress: float = 0.0
	if ball_owner_team == 0:  # Team A attacking right
		ball_progress = (ball_pos.x - pitch_width * 0.5) / (pitch_width * 0.5)
	else:  # Team B attacking left
		ball_progress = (pitch_width * 0.5 - ball_pos.x) / (pitch_width * 0.5)
	
	# In _attack_offset, be more conservative with defenders
	if role == "DEF":
		# Only push forward if ball is very deep in opponent half
		if ball_progress > 0.5:
			off += attack_direction * ball_progress * 25.0  # Reduced from 40.0
		else:
			off += attack_direction * 15.0  # Reduced from 30.0

	return off

func _defend_offset(role: String, i: int, data: Array, opp_anchors: Array[Vector2]) -> Vector2:
	var off := Vector2.ZERO

	# When defending: drop lines
	var drop := 0.0
	if role == "DEF":
		drop = 10.0
	elif role == "MID":
		drop = 30.0
	elif role == "FWD":
		drop = 15.0

	# Team A defends left, Team B defends right
	var defend_dir := Vector2(-1, 0) if (data == team_a) else Vector2(1, 0)
	off += defend_dir * drop

	# Marking pull: lean toward marked opponent
	var mark_i: int = int(data[i]["mark_target"])
	if mark_i != -1 and mark_i < opp_anchors.size():
		var opp_pos := opp_anchors[mark_i]
		off += (opp_pos - (team_a_positions[i] if data == team_a else team_b_positions[i])) * mark_strength * 0.25

	# Compact around ball a bit
	off += (ball_pos - (team_a_positions[i] if data == team_a else team_b_positions[i])) * 0.05

	return off

func _calculate_defensive_line_x(anchors: Array[Vector2], data: Array) -> float:
	# Calculate average X position of defenders (indices 1-4)
	var def_count: int = 0
	var sum_x: float = 0.0
	
	for i in range(anchors.size()):
		if i < data.size() and String(data[i]["role"]) == "DEF":
			sum_x += anchors[i].x
			def_count += 1
	
	if def_count > 0:
		return sum_x / float(def_count)
	
	# Fallback: return average of first 4 outfield players
	if anchors.size() > 4:
		for i in range(1, 5):
			sum_x += anchors[i].x
		return sum_x / 4.0
	
	return anchors[0].x if anchors.size() > 0 else pitch_width * 0.5

func _should_attempt_offside_trap(team_id: int, anchors: Array[Vector2], data: Array) -> bool:
	# Only attempt offside trap in certain conditions
	# 1. Ball is in opponent's half (we're defending deep)
	# 2. Random chance
	# 3. Opponents are making forward runs
	
	var ball_in_opponent_half: bool = false
	if team_id == 0:  # Team A defending
		ball_in_opponent_half = ball_pos.x > pitch_width * 0.5
	else:  # Team B defending
		ball_in_opponent_half = ball_pos.x < pitch_width * 0.5
	
	if not ball_in_opponent_half:
		return false
	
	# Check if opponents are making forward runs
	var opp_anchors: Array[Vector2] = team_b_positions if team_id == 0 else team_a_positions
	var opp_data: Array = team_b if team_id == 0 else team_a
	
	var forward_runs_detected: bool = false
	
	for i in range(opp_anchors.size()):
		if i < opp_data.size():
			var role: String = String(opp_data[i]["role"])
			if role == "FWD" or role == "MID":
				# Check if opponent is ahead of our defensive line
				var def_line_x: float = _calculate_defensive_line_x(anchors, data)
				var opp_x: float = opp_anchors[i].x
				
				if team_id == 0:  # Team A defending (opponents attack left toward A's goal)
					if opp_x < def_line_x - 20.0:  # Opponent ahead of line (closer to A's goal)
						forward_runs_detected = true
						break
				else:  # Team B defending (opponents attack right toward B's goal)
					if opp_x > def_line_x + 20.0:  # Opponent ahead of line (closer to B's goal)
						forward_runs_detected = true
						break
	
	if not forward_runs_detected:
		return false
	
	# Random chance to attempt trap
	return rng.randf() < offside_trap_chance

func _apply_defensive_line_coordination(
	position: Vector2,
	player_index: int,
	anchors: Array[Vector2],
	data: Array,
	context: Dictionary
) -> Vector2:
	var coordinated := position
	
	# Safely get defensive line X (with fallback)
	var def_line_x: float = context.get("defensive_line_x", anchors[player_index].x)
	var offside_trap: bool = context.get("offside_trap_active", false)
	
	# Align defender's X to defensive line (with coordination strength)
	var current_x: float = anchors[player_index].x
	var line_alignment: float = (def_line_x - current_x) * defensive_line_coordination
	coordinated.x += line_alignment
	
	# Offside trap: move line forward together (toward center/halfway line)
	if offside_trap:
		# Move defensive line away from own goal (toward center)
		# Team A defends left side, so move right (toward center)
		# Team B defends right side, so move left (toward center)
		var trap_dir: Vector2 = Vector2(1, 0) if (data == team_a) else Vector2(-1, 0)
		var trap_move: float = offside_trap_distance * (1.0 - defensive_line_coordination * 0.5)
		coordinated += trap_dir * trap_move
	
	# Maintain defensive shape: keep proper spacing between defenders
	coordinated = _maintain_defensive_spacing(coordinated, player_index, anchors, data)
	
	return coordinated

func _maintain_defensive_spacing(
	position: Vector2,
	player_index: int,
	anchors: Array[Vector2],
	data: Array
) -> Vector2:
	var adjusted := position
	var min_spacing: float = defensive_line_spacing * 0.8  # Minimum spacing
	var ideal_spacing: float = defensive_line_spacing
	
	# Only adjust spacing with other defenders
	for i in range(anchors.size()):
		if i == player_index:
			continue
		
		if i < data.size() and String(data[i]["role"]) == "DEF":
			var other_pos: Vector2 = anchors[i]
			var to_other: Vector2 = position - other_pos
			var distance: float = to_other.length()
			
			# If too close, push away; if too far, pull slightly closer
			if distance > 0.1 and distance < ideal_spacing * 1.5:
				if distance < min_spacing:
					# Too close - push away
					var push_strength: float = (min_spacing - distance) / min_spacing * 15.0
					adjusted += to_other.normalized() * push_strength
				elif distance > ideal_spacing * 1.2:
					# Too far - pull slightly closer (weaker effect)
					var pull_strength: float = (distance - ideal_spacing * 1.2) / ideal_spacing * 5.0
					adjusted -= to_other.normalized() * pull_strength
	
	return adjusted

func _closest_players_to_point_filtered(
	anchors: Array[Vector2], 
	point: Vector2, 
	count: int, 
	data: Array, 
	allowed_roles: Array[String], 
	exclude_index: int = -1
) -> Array[int]:
	var list: Array = []
	for i in range(anchors.size()):
		if i == exclude_index:
			continue
		
		var role: String = String(data[i]["role"])
		if allowed_roles.find(role) == -1:
			continue
		
		var d: float = anchors[i].distance_to(point)
		list.append({"i": i, "d": d})
	
	list.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	
	var result: Array[int] = []
	var n: int = min(count, list.size())
	for k in range(n):
		result.append(int(list[k]["i"]))
	return result

func _support_spots(team_id: int, carrier_pos: Vector2) -> Array[Vector2]:
	var attack_dir: Vector2 = Vector2(1.0, 0.0) if team_id == 0 else Vector2(-1.0, 0.0)
	
	# Two classic triangle spots
	var ahead: Vector2 = attack_dir * support_ahead
	
	var flip: float = sign(ball_pos.y - pitch_height * 0.5) # -1 or 1
	
	return [
		carrier_pos + ahead + Vector2(0, -support_distance * (0.8 + 0.3 * flip)),
		carrier_pos + ahead + Vector2(0,  support_distance * (1.1 - 0.2 * flip)),
	]

func _seperation_offset(i: int, anchors: Array[Vector2], min_dist: float, strength: float) -> Vector2:
	var off := Vector2.ZERO
	var p: Vector2 = anchors[i]
	
	# Improved separation: only push away from very close players
	# This prevents constant micro-adjustments
	for j in range(anchors.size()):
		if j == i:
			continue
		var to: Vector2 = p - anchors[j]
		var d: float = to.length()
		# Only apply separation if very close (within 80% of min_dist)
		if d > 0.001 and d < min_dist * 0.8:
			var push_strength: float = ((min_dist * 0.8 - d) / (min_dist * 0.8)) * strength
			off += to.normalized() * push_strength
	
	return off

func _ball_is_in_team_defensive_third(team_id: int) -> bool:
	if team_id == 0:
		return ball_pos.x < pitch_width * 0.33
	else:
		return ball_pos.x > pitch_width * 0.67

func _allowed_support_roles(team_id: int) -> Array[String]:
	# Default: mids + forwards support
	# Allow defenders to support only if ball is deep
	if _ball_is_in_team_defensive_third(team_id):
		return ["DEF", "MID", "FWD"]
	return ["MID", "FWD"]

func _allowed_press_roles(team_id: int) -> Array[String]:
	# Default: forwards + mids press
	# Allow defenders to press only if ball is deep
	if _ball_is_in_team_defensive_third(team_id):
		return ["DEF","MID", "FWD"]
	return ["MID", "FWD"]


func reset_to_home() -> void:
	team_a_positions = team_a_home.duplicate()
	team_b_positions = team_b_home.duplicate()


func _pick_runner_for_team(team_id: int) -> void:
	runner_team = team_id
	runner_index = -1

	var data := team_a if team_id == 0 else team_b
	var anchors := team_a_positions if team_id == 0 else team_b_positions

	var fwds: Array[int] = []
	for i in range(data.size()):
		if String(data[i]["role"]) == "FWD":
			fwds.append(i)

	if fwds.is_empty():
		return

	# alternate between them based on time (keeps it deterministic)
	var idx: int = int(floor(_t)) % fwds.size()
	runner_index = fwds[idx]


	var p := anchors[runner_index]
	
	var backline_x: float = _opponent_backline_x(team_id)

	# Team A attacks right, Team B attacks left:
	var target_x: float
	if team_id == 0:
		target_x = backline_x + 70.0
	else:
		target_x = backline_x - 70.0

	var lateral: float = clamp((ball_pos.y - pitch_height * 0.5) * 0.35, -90.0, 90.0)

	runner_target = Vector2(target_x, p.y + lateral)
	runner_target.x = clamp(runner_target.x, 20.0, pitch_width - 20.0)
	runner_target.y = clamp(runner_target.y, 20.0, pitch_height - 20.0)



func _opponent_backline_x(team_id: int) -> float:
	# returns average x of opponent defenders (indices 1..4)
	var opp := team_b_positions if team_id == 0 else team_a_positions
	var sum: float = 0.0
	for i in range(1, 5):
		sum += opp[i].x
	return sum / 4.0


func _get_goalkeeper_position(team_id: int, current_pos: Vector2) -> Vector2:
	var goal_center_x: float = 50.0 if team_id == 0 else pitch_width - 50.0
	var goal_center: Vector2 = Vector2(goal_center_x, pitch_height * 0.5)
	
	var ball_to_goal: Vector2 = goal_center - ball_pos
	var distance_to_ball: float = ball_pos.distance_to(goal_center)
	
	# How far from goal to position (advance when ball is close)
	var base_offset: float = 80.0
	var max_advance: float = 150.0
	var advance: float = clamp(
		max_advance * (1.0 - distance_to_ball / (pitch_width * 0.7)),
		base_offset,
		max_advance
	)
	
	# Position along line from goal to ball
	var gk_pos: Vector2 = goal_center + ball_to_goal.normalized() * advance
	
	# Limit lateral movement
	var max_lateral: float = 80.0
	gk_pos.y = clamp(gk_pos.y, goal_center.y - max_lateral, goal_center.y + max_lateral)
	
	# Smooth transition from current position
	return current_pos.lerp(gk_pos, 0.3)

func switch_sides() -> void:
	"""
	Mirror all formations and positions for half-time side switch
	"""
	var pitch_center_x: float = pitch_width * 0.5
	
	for i in range(team_a_positions.size()):
		var mirrored_x: float = pitch_center_x + (pitch_center_x - team_a_positions[i].x)
		team_a_positions[i].x = mirrored_x
	
	for i in range(team_b_positions.size()):
		var mirrored_x: float = pitch_center_x + (pitch_center_x - team_b_positions[i].x)
		team_b_positions[i].x = mirrored_x
	
	for i in range(team_a_targets.size()):
		var mirrored_x: float = pitch_center_x + (pitch_center_x - team_a_targets[i].x)
		team_a_targets[i].x = mirrored_x
	
	for i in range(team_b_targets.size()):
		var mirrored_x: float = pitch_center_x + (pitch_center_x - team_b_targets[i].x)
		team_b_targets[i].x = mirrored_x
	
	print("Match sim sides switched")
