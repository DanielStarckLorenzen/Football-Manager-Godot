extends Node2D

@export var radius: float = 12.0
@export var color: Color = Color.WHITE

@onready var name_label: Label = $NameLabel

var player_name: String = ""
var show_name: bool = false
var team_id: int = 0

var player_data: Dictionary = {
	"id": 0,
	"role": "MID",
	"pace": 0.5,
	"tackle": 0.5,
	"pass": 0.5,
	"dribble": 0.5,
	"mark_traget": -1,
}

var velocity: Vector2 = Vector2.ZERO
var home_position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	if name_label:
		name_label.visible = show_name
		if show_name:
			name_label.text = player_name

func initialize(p_team_id: int, p_player_data: Dictionary, p_home_pos: Vector2, p_color: Color) -> void:
	"""
	Set up this player dot with all its data.
	Called once when the match starts.
	"""
	team_id = p_team_id
	player_data = p_player_data
	home_position = p_home_pos
	target_position = p_home_pos
	position = p_home_pos
	
	set_visual(p_color, 12.0)

func set_player_name(new_name: String, visible: bool = true) -> void:
	player_name = new_name
	show_name = visible
	
	if name_label:
		name_label.text = player_name
		name_label.visible = show_name

func hide_name() -> void:
	show_name = false
	
	if name_label:
		name_label.visible = false

func show_name_label() -> void:
	show_name = true
	
	if name_label:
		name_label.visible = true

func get_stat(stat_name: String) -> float:
	"""
	Get a player stat (pace, tackle, pass, dribble).
	"""
	return player_data.get(stat_name, 0.5)

func get_role() -> String:
	"""
	Get player role (GK, DEF, MID, FWD).
	"""
	return player_data.get("role", "MID")

func get_speed() -> float:
	"""
	Calculate this player's movement speed based on pace stat.
	"""
	var base_speed: float = 160.0
	var pace_multiplier: float = 80.0
	var pace: float = get_stat("pace")
	return base_speed + (pace - 0.5) * pace_multiplier

func switch_side(pitch_center_x: float) -> void:
	"""
	Mirror this player to the opposite side of the pitch.
	Called at half-time.
	"""
	# Mirror current position
	var mirrored_x: float = pitch_center_x + (pitch_center_x - position.x)
	position.x = mirrored_x
	
	# Mirror home position (formation anchor)
	var mirrored_home_x: float = pitch_center_x + (pitch_center_x - home_position.x)
	home_position.x = mirrored_home_x
	
	# Update target to new home
	target_position = home_position
	
	# Reset velocity
	velocity = Vector2.ZERO

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)

func set_visual(p_color: Color, p_radius: float = 6.0) -> void:
	color = p_color
	radius = p_radius
	queue_redraw()
