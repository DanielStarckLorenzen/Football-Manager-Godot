extends Node

# This script controls a single match from start to finish
# It connects GameManager's squad data to the match engine

var match_scene: Node2D

# Match states
var match_time: float = 0.0
var match_speed: float = 1.0 # 1.0 = 90 game minutes in 90 real life seconds
var half_time: float = 45.0
var full_time: float = 90.0
var is_match_active: bool = false
var is_paused: bool = false
var half_time_processed: bool = false

# Signals for UI to listen to
signal match_started
signal half_time_reached
signal match_ended(team_a_score: int, team_b_score: int)
signal time_updated(current_time: float)
signal match_paused
signal match_resumed

func _ready() -> void:
	pass

func start_match(match_node: Node2D) -> void:
	"""
	Called when we want to start a match.
	match_node is the actual match.tscn instance with the engine.
	"""
	match_scene = match_node
	match_time = 0.0
	is_match_active = true
	
	var player_team_data: Array = GameManager.get_starting_11_as_match_data()
	
	# For now, create a simple opponent team (AI) TODO
	var opponent_team_data: Array = _generate_opponent_team()
	
	# Load teams into match_sim
	# match_sim is a child of match_node
	var sim = match_scene.get_node("MatchSim")
	if sim:
		sim.team_a = player_team_data
		sim.team_b = opponent_team_data
		
		if sim.has_method("reset_to_home"):
			sim.reset_to_home()
	
	match_started.emit()
	print("Match Started!")

func _process(delta: float) -> void:
	if not is_match_active or is_paused:
		return
	
	match_time += delta * match_speed
	
	time_updated.emit(match_time)
	
	# Check for half time
	if match_time >= half_time and not half_time_processed:
		_handle_half_time()
		half_time_processed = true
	
	# Check for full time
	if match_time >= full_time:
		_handle_full_time()

func _handle_half_time() -> void:
	"""
	Called when we reach 45 minutes.
	Teams should switch sides (handled by match engine).
	"""
	print("HALF TIME!")
	
	is_paused = true
	match_paused.emit()
	
	if match_scene and match_scene.has_method("switch_sides"):
		match_scene.switch_sides()
	
	half_time_reached.emit()
	
	await get_tree().create_timer(3.0).timeout
	
	is_paused = false
	match_resumed.emit()
	print("SECONDS HALF STARTING")

func _handle_full_time() -> void:
	"""
	Called when we reach 90 minutes.
	Match is over, show results.
	"""
	is_match_active = false
	
	# Get final score from match engine
	var team_a_score: int = 0
	var team_b_score: int = 0
	
	if match_scene:
		team_a_score = match_scene.score_a
		team_b_score = match_scene.score_b
	
	print("FULL TIME! Final Score: %d : %d" % [team_a_score, team_b_score])
	
	_award_match_rewards(team_a_score, team_b_score)
	
	match_ended.emit(team_a_score, team_b_score)

func _award_match_rewards(team_a_score: int, team_b_score: int) -> void:
	"""
	Give player money based on match result.
	Win = $300, Draw = $150, Loss = $50
	"""
	var reward: int = 50
	
	if team_a_score > team_b_score:
		reward = 300
		print("VICTORY! You earned $300")
	elif team_a_score == team_b_score:
		reward = 150
		print("DRAW! You earned $150")
	else:
		print("DEFEAT! You earned $50")
	
	GameManager.add_money(reward)

func _generate_opponent_team() -> Array:
	"""
	Creates a simple AI opponent team.
	For now, we'll generate 11 players with random stats (similar to your starter squad).
	Later you can make this more sophisticated (opponent clubs, difficulty levels, etc.)
	"""
	var opponent: Array = []
	
	# Formation 4-4-2
	var positions: Array[String] = [
		"GK",
		"DEF", "DEF", "DEF", "DEF",
		"MID", "MID", "MID", "MID",
		"FWD", "FWD"
	]
	
	for i in range(11):
		# Create a player with slightly randomized stats
		# Average around 50 overall (similar to starter squad)
		var player_dict := {
			"id": i,
			"role": _position_to_role(positions[i]),
			"pace": randf_range(0.4, 0.6),
			"tackle": randf_range(0.4, 0.6),
			"pass": randf_range(0.4, 0.6),
			"dribble": randf_range(0.4, 0.6),
			"mark_target": -1
		}
		
		match positions[i]:
			"DEF":
				player_dict.tackle += 0.15
			"MID":
				player_dict.pass += 0.15
			"FWD":
				player_dict.dribble += 0.15
		
		opponent.append(player_dict)
	
	return opponent

func _position_to_role(position: String) -> String:
	"""
	Converts position string to role for match engine.
	"""
	match position:
		"GK": return "GK"
		"DEF": return "DEF"
		"MID": return "MID"
		"FWD": return "FWD"
		_: return "MID"

func get_current_minute() -> int:
	"""
	Returns current match time as an integer minute (0-90).
	Useful for UI display.
	"""
	return int(match_time)

func get_score() -> Dictionary:
	"""
	Returns current score.
	Useful for UI to display score during match.
	"""
	if match_scene:
		return {
			"team_a": match_scene.score_a,
			"team_b": match_scene.score_b
		}
	return {"team_a": 0, "team_b": 0}
