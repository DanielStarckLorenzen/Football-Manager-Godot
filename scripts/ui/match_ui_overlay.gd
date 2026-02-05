extends CanvasLayer

# This script displays the match time and score during gameplay
# It listens to the match_controller for updates

@onready var time_label: Label = $Control/MarginContainer/MainContainer/TopBar/MarginContainer/HBoxContainer/TimeLabel
@onready var score_label: Label = $Control/MarginContainer/MainContainer/TopBar/MarginContainer/HBoxContainer/ScoreLabel
@onready var team_label: Label = $Control/MarginContainer/MainContainer/TopBar/MarginContainer/HBoxContainer/TeamLabel
@onready var half_time_container: CenterContainer = $Control/MarginContainer/MainContainer/HalfTimeContainer
@onready var half_time_label: Label = $Control/MarginContainer/MainContainer/HalfTimeContainer/PanelContainer/MarginContainer/HalfTimeLabel

var match_controller: Node = null

# States
var is_half_time_shown: bool = false
var half_time_duration: float = 3.0  # Show "HALF TIME" for 3 seconds
var half_time_timer: float = 0.0

func _ready() -> void:
	half_time_container.visible = false
	
	team_label.text = GameManager.team_name

func setup(controller: Node) -> void:
	"""
	Called by game_container to connect this UI to the match controller.
	This is how we know which match to display info for.
	"""
	match_controller = controller
	
	# Conenct to controller signals
	if match_controller:
		match_controller.time_updated.connect(_on_time_updated)
		match_controller.half_time_reached.connect(_on_half_time_reached)
		match_controller.match_started.connect(_on_match_started)

func _on_match_started() -> void:
	"""
	Called when match starts - reset everything.
	"""
	is_half_time_shown = false
	half_time_container.visible = false
	_update_display()

func _on_time_updated(current_time: float) -> void:
	"""
	Called every frame with current match time.
	Updates the time display.
	"""
	_update_display()

func _on_half_time_reached() -> void:
	"""
	Called at 45 minutes - show half-time message.
	"""
	is_half_time_shown = true
	half_time_timer = 0.0
	half_time_container.visible = true

func _process(delta: float) -> void:
	# Handle half-time message display timer
	if is_half_time_shown:
		half_time_timer += delta
		
		# Hide after duration
		if half_time_timer >= half_time_duration:
			half_time_container.visible = false
			is_half_time_shown = false

func _update_display() -> void:
	"""
	Updates the UI with current match state.
	"""
	if not match_controller:
		return
	
	# Update time
	var current_minute: int = match_controller.get_current_minute()
	time_label.text = str(current_minute) + "'"
	
	# Update score
	var score: Dictionary = match_controller.get_score()
	score_label.text = str(score.team_a) + " - " + str(score.team_b)
	
	# Visual feedback based on score
	# Green if winning, white if drawing, red if losing
	if score.team_a > score.team_b:
		score_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))  # Green
	elif score.team_a < score.team_b:
		score_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))  # Red
	else:
		score_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))  # White
