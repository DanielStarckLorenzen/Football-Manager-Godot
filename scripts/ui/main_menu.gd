extends CanvasLayer

@onready var squad_button: Button = $Control/MenuContainer/SquadButton
@onready var play_button: Button = $Control/MenuContainer/PlayMatchButton
@onready var pack_button: Button = $Control/MenuContainer/OpenPackButton
@onready var quit_button: Button = $Control/MenuContainer/QuitButton

func _ready() -> void:
	squad_button.pressed.connect(_on_squad_pressed)
	play_button.pressed.connect(_on_play_pressed)
	pack_button.pressed.connect(_on_pack_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_squad_pressed() -> void:
	get_parent().show_squad_screen()

func _on_play_pressed() -> void:
	get_parent().show_match()

func _on_pack_pressed() -> void:
	get_parent().show_pack_opening()

func _on_quit_pressed() -> void:
	get_tree().quit()
