extends CanvasLayer

@onready var money_label: Label = $Control/MarginContainer/VBoxContainer/TopBar/MoneyLabel
@onready var back_button: Button = $Control/MarginContainer/VBoxContainer/TopBar/BackButton
@onready var pack_info_label: Label = $Control/MarginContainer/VBoxContainer/PackDisplay/CenterContainer/VBoxContainer/PackInfoLabel
@onready var cards_container: HBoxContainer = $Control/MarginContainer/VBoxContainer/PackDisplay/CenterContainer/VBoxContainer/CardsContainer
@onready var open_pack_button: Button = $Control/MarginContainer/VBoxContainer/BottomBar/VBoxContainer/OpenPackButton
@onready var status_label: Label = $Control/MarginContainer/VBoxContainer/BottomBar/VBoxContainer/StatusLabel

var is_opening: bool = false

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	open_pack_button.pressed.connect(_on_open_pack_pressed)
	
	GameManager.money_changed.connect(_update_money)
	GameManager.pack_opened.connect(_on_pack_opened)
	
	_update_money(GameManager.money)
	_update_button_state()

func _update_money(amount: int) -> void:
	money_label.text = "Money: $" + str(amount)
	_update_button_state()

func _update_button_state() -> void:
	var can_afford := GameManager.can_afford_pack()
	open_pack_button.disabled = not can_afford or is_opening
	
	if not can_afford:
		status_label.text = "Not enough money!"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		status_label.text = ""

func _on_open_pack_pressed() -> void:
	if is_opening or not GameManager.can_afford_pack():
		return
	
	is_opening = true
	open_pack_button.disabled = true
	status_label.text = "Opening pack..."
	status_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	
	# Clear previous cards
	for child in cards_container.get_children():
		child.queue_free()
	
	# Open pack (this triggers the pack_opened signal)
	GameManager.open_pack()

func _on_pack_opened(cards: Array[PlayerCard]) -> void:
	# Animate cards appearing
	for i in range(cards.size()):
		await get_tree().create_timer(0.3).timeout  # Delay between cards
		_add_card_display(cards[i])
	
	status_label.text = "Pack opened! Check your squad."
	status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	
	is_opening = false
	_update_button_state()

func _add_card_display(card: PlayerCard) -> void:
	var card_panel := PanelContainer.new()
	card_panel.custom_minimum_size = Vector2(150, 220)
	
	# Style based on rarity
	var style := StyleBoxFlat.new()
	match card.card_rarity:
		"COMMON":
			style.bg_color = Color(0.3, 0.3, 0.3)
			style.border_color = Color(0.5, 0.5, 0.5)
		"RARE":
			style.bg_color = Color(0.2, 0.3, 0.5)
			style.border_color = Color(0.3, 0.5, 0.8)
		"EPIC":
			style.bg_color = Color(0.4, 0.2, 0.5)
			style.border_color = Color(0.7, 0.3, 0.8)
		"LEGENDARY":
			style.bg_color = Color(0.5, 0.4, 0.1)
			style.border_color = Color(1.0, 0.8, 0.2)
	
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	card_panel.add_theme_stylebox_override("panel", style)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card_panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)
	
	# Overall rating (big)
	var ovr_label := Label.new()
	ovr_label.text = str(card.overall_rating)
	ovr_label.add_theme_font_size_override("font_size", 36)
	ovr_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ovr_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	vbox.add_child(ovr_label)
	
	# Position
	var pos_label := Label.new()
	pos_label.text = card.position
	pos_label.add_theme_font_size_override("font_size", 16)
	pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(pos_label)
	
	# Nationality (flag + name)
	var nat_label := Label.new()
	nat_label.text = GameManager.get_nationality_flag(card.nationality) + " " + GameManager.get_nationality_name(card.nationality)
	nat_label.add_theme_font_size_override("font_size", 12)
	nat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(nat_label)
	
	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)
	
	# Name
	var name_label := Label.new()
	name_label.text = card.player_name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_label)
	
	# Potential
	var pot_label := Label.new()
	pot_label.text = "POT: " + str(card.potential_rating)
	pot_label.add_theme_font_size_override("font_size", 11)
	pot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pot_label.add_theme_color_override("font_color", card.get_potential_color())
	vbox.add_child(pot_label)
	
	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	# Rarity
	var rarity_label := Label.new()
	rarity_label.text = card.card_rarity
	rarity_label.add_theme_font_size_override("font_size", 12)
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(rarity_label)
	
	cards_container.add_child(card_panel)
	
	# Add appear animation
	card_panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(card_panel, "modulate:a", 1.0, 0.3)

func _on_back_pressed() -> void:
	get_parent().show_main_menu()
