extends Node

# References to different screens (we'll add these as we build them)
@onready var main_menu: CanvasLayer = $MainMenu
@onready var squad_screen: CanvasLayer = $SquadScreen
@onready var pack_opening: CanvasLayer = $PackOpening

var match_view: Node2D = null
var match_controller: Node = null
var match_ui_overlay: CanvasLayer = null

var match_scene: PackedScene = preload("res://scenes/match/match.tscn")
var match_ui_scene: PackedScene = preload("res://scenes/ui/match_ui_overlay.tscn")

enum Screen {
	MAIN_MENU,
	SQUAD,
	MATCH,
	PACK_OPENING
}

var current_screen: Screen = Screen.MAIN_MENU

func _ready() -> void:
	# Try to load save game
	if not GameManager.load_game():
		print("No save found, starting new game")
	
	match_controller = Node.new()
	match_controller.set_script(load("res://scripts/match/match_controller.gd"))
	add_child(match_controller)
	
	match_controller.match_ended.connect(_on_match_ended)
	
	_show_screen(Screen.MAIN_MENU)

func _show_screen(screen: Screen) -> void:
	current_screen = screen
	
	# Hide all screens
	if main_menu:
		main_menu.visible = false
	if squad_screen:
		squad_screen.visible = false
	if pack_opening:
		pack_opening.visible = false
	
	# Destroy match view and UI if it exists and we're not showing match
	if match_view and screen != Screen.MATCH:
		match_view.queue_free()
		match_view = null
	
	if match_ui_overlay and screen != Screen.MATCH:  # NEW
		match_ui_overlay.queue_free()
		match_ui_overlay = null
	
	# Show requested screen
	match screen:
		Screen.MAIN_MENU:
			if main_menu:
				main_menu.visible = true
		Screen.SQUAD:
			if squad_screen:
				squad_screen.visible = true
		Screen.PACK_OPENING:
			if pack_opening:
				pack_opening.visible = true
		Screen.MATCH:
			_start_match()

func show_main_menu() -> void:
	_show_screen(Screen.MAIN_MENU)

func show_squad_screen() -> void:
	_show_screen(Screen.SQUAD)

func show_match() -> void:
	_show_screen(Screen.MATCH)

func show_pack_opening() -> void:
	_show_screen(Screen.PACK_OPENING)

func _start_match() -> void:
	"""
	Instance the match scene and start the match.
	This is called when switching to the MATCH screen.
	"""
	match_view = match_scene.instantiate()
	add_child(match_view)
	
	# Instance the match UI overlay
	match_ui_overlay = match_ui_scene.instantiate()
	add_child(match_ui_overlay)
	
	# Wait one frame for everything to be ready
	await get_tree().process_frame
	
	if match_view:
		match_view.match_controller = match_controller
	
	# Connect the UI overlay to the match controller
	if match_ui_overlay and match_ui_overlay.has_method("setup"):
		match_ui_overlay.setup(match_controller)
	
	# Start the match through the controller
	match_controller.start_match(match_view)

func _on_match_ended(team_a_score: int, team_b_score: int) -> void:
	"""
	Called when match controller signals that match has ended.
	Show a simple result message then return to main menu.
	"""
	print("Match ended! Score: %d - %d" % [team_a_score, team_b_score])
	
	# Wait a moment so player can see final score
	await get_tree().create_timer(3.0).timeout
	
	# Return to main menu
	show_main_menu()
