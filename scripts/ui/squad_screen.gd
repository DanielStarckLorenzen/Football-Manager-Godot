extends CanvasLayer

# Reference the manually built nodes
@onready var starting_list: VBoxContainer = $Control/MarginContainer/VBoxContainer/ContentArea/VBoxContainer/ScrollContainer/StartingList
@onready var subs_list: VBoxContainer = $Control/MarginContainer/VBoxContainer/ContentArea/VBoxContainer2/ScrollContainer/SubsList
@onready var money_label: Label = $Control/MarginContainer/VBoxContainer/TopBar/MoneyLabel
@onready var back_button: Button = $Control/MarginContainer/VBoxContainer/TopBar/BackButton
@onready var save_button: Button = $Control/MarginContainer/VBoxContainer/SaveButton
@onready var play_match_button: Button = $Control/MarginContainer/VBoxContainer/PlayMatchButton

func _ready() -> void:
	# Connect button signals
	back_button.pressed.connect(_on_back_pressed)
	save_button.pressed.connect(_on_save_pressed)
	play_match_button.pressed.connect(_on_play_match_pressed)
	
	# Connect to GameManager signals
	GameManager.squad_updated.connect(_refresh_squad)
	GameManager.money_changed.connect(_update_money)
	
	# Initial display
	_refresh_squad()
	_update_money(GameManager.money)
		

func _refresh_squad() -> void:
	# Clear existing player cards
	for child in starting_list.get_children():
		child.queue_free()
	for child in subs_list.get_children():
		child.queue_free()
	
	# Add starting 11
	for idx in GameManager.starting_11:
		if idx < GameManager.player_squad.size():
			var card: PlayerCard = GameManager.player_squad[idx]
			var card_ui := _create_player_card_ui(card)
			starting_list.add_child(card_ui)
	
	# Add substitutes
	for idx in GameManager.substitutes:
		if idx < GameManager.player_squad.size():
			var card: PlayerCard = GameManager.player_squad[idx]
			var card_ui := _create_player_card_ui(card)
			subs_list.add_child(card_ui)

func _create_player_card_ui(card: PlayerCard) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 80)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	
	var hbox := HBoxContainer.new()
	margin.add_child(hbox)
	
	# Left side - name, position, nationality, level
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left_vbox)
	
	# Name + Flag
	var name_hbox := HBoxContainer.new()
	left_vbox.add_child(name_hbox)
	
	var name_label := Label.new()
	name_label.text = card.player_name
	name_label.add_theme_font_size_override("font_size", 16)
	name_hbox.add_child(name_label)
	
	var flag_label := Label.new()
	flag_label.text = " " + GameManager.get_nationality_flag(card.nationality)
	flag_label.add_theme_font_size_override("font_size", 16)
	name_hbox.add_child(flag_label)
	
	# Position + Overall + Potential
	var info_hbox := HBoxContainer.new()
	left_vbox.add_child(info_hbox)
	
	var pos_label := Label.new()
	pos_label.text = card.position + " - OVR: " + str(card.overall_rating)
	pos_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info_hbox.add_child(pos_label)
	
	var ovr_label := Label.new()
	ovr_label.text = "OVR: " + str(card.overall_rating) + " "
	ovr_label.add_theme_color_override("font_color", card.get_rating_color())
	info_hbox.add_child(ovr_label)
	
	var pot_label := Label.new()
	pot_label.text = "POT: " + str(card.potential_rating)
	pot_label.add_theme_font_size_override("font_size", 11)
	pot_label.add_theme_color_override("font_color", card.get_potential_color())
	info_hbox.add_child(pot_label)
	
	var level_label := Label.new()
	level_label.text = card.get_level_stars()
	level_label.add_theme_font_size_override("font_size", 14)
	level_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	left_vbox.add_child(level_label)
	
	var personality_label := Label.new()
	personality_label.text = "(" + card.get_personality_type() + ")"
	personality_label.add_theme_font_size_override("font_size", 11)
	personality_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	left_vbox.add_child(personality_label)
	
	# Right side - stats
	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 10)
	stats_grid.add_theme_constant_override("v_separation", 2)
	hbox.add_child(stats_grid)
	
	if card.position == "GK":
		_add_stat_label(stats_grid, "DIV", card.diving)
		_add_stat_label(stats_grid, "HAN", card.handling)
		_add_stat_label(stats_grid, "POS", card.positioning)
		_add_stat_label(stats_grid, "REF", card.reflexes)
	else:
		_add_stat_label(stats_grid, "PAC", card.pace)
		_add_stat_label(stats_grid, "SHO", card.shooting)
		_add_stat_label(stats_grid, "PAS", card.passing)
		_add_stat_label(stats_grid, "DRI", card.dribbling)
		_add_stat_label(stats_grid, "DEF", card.defending)
		_add_stat_label(stats_grid, "PHY", card.physical)
	
	return panel

func _add_stat_label(container: GridContainer, stat_name: String, value: float) -> void:
	var name_lbl := Label.new()
	name_lbl.text = stat_name + ":"
	name_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(name_lbl)
	
	var stat_value := int(value * 99)
	var val_lbl := Label.new()
	val_lbl.text = str(stat_value)
	val_lbl.add_theme_font_size_override("font_size", 12)
	
	var stat_color := Color.WHITE
	if stat_value >= 70:
		stat_color = Color(0.3, 0.9, 0.3)  # Green
	elif stat_value >= 50:
		stat_color = Color(0.9, 0.9, 0.3)  # Yellow
	else:
		stat_color = Color(0.9, 0.3, 0.3)  # Red
	
	val_lbl.add_theme_color_override("font_color", stat_color)
	container.add_child(val_lbl)

func _update_money(amount: int) -> void:
	if money_label:
		money_label.text = "Money: $" + str(amount)

func _on_back_pressed() -> void:
	get_parent().show_main_menu()

func _on_save_pressed() -> void:
	GameManager.save_game()
	get_parent().show_main_menu()

func _on_play_match_pressed() -> void:
	if GameManager.starting_11.size() < 11:
		print("Error: Need 11 players to start match!")
		return
	
	get_parent().show_match()
