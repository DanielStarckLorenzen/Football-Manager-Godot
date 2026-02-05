extends Node

# Player's squad
var player_squad: Array[PlayerCard] = []
var starting_11: Array = []  # Indices into player_squad
var substitutes: Array = []

# Resources
var money: int = 500
var season: int = 1

# Team info
var team_name: String = "My Club"
var team_rating: int = 50

var nationalities: Array = []
var nationality_weights: Array[float] = []

var first_names: Array = []
var last_names: Array = []

const PACK_COST: int = 100
const CARDS_PER_PACK: int = 5

signal squad_updated
signal money_changed(new_amount: int)
signal pack_opened(cards: Array[PlayerCard])

func _ready() -> void:
	_load_static_data()
	
	if not load_game():
		print("No save found, starting new game")
		_generate_starter_squad()


func _load_static_data() -> void:
	# Load nationalities
	if FileAccess.file_exists("res://data/players/nationalities.json"):
		var file := FileAccess.open("res://data/players/nationalities.json", FileAccess.READ)
		var json := JSON.new()
		json.parse(file.get_as_text())
		var data: Dictionary = json.data
		nationalities = data.get("nationalities", [])
		
		# Build weights array for weighted random selection
		nationality_weights.clear()
		for nat in nationalities:
			var weight_value = nat.get("weight", 1)
			# FIXED: explicitly convert to float
			if weight_value is int:
				nationality_weights.append(float(weight_value))
			elif weight_value is float:
				nationality_weights.append(weight_value)
			else:
				nationality_weights.append(1.0)  # fallback
		
		file.close()
	
	# Load first names
	if FileAccess.file_exists("res://data/players/first_names.json"):
		var file := FileAccess.open("res://data/players/first_names.json", FileAccess.READ)
		var json := JSON.new()
		json.parse(file.get_as_text())
		first_names = json.data
		file.close()
	
	# Load last names
	if FileAccess.file_exists("res://data/players/last_names.json"):
		var file := FileAccess.open("res://data/players/last_names.json", FileAccess.READ)
		var json := JSON.new()
		json.parse(file.get_as_text())
		last_names = json.data
		file.close()


func _generate_starter_squad() -> void:
	# Start with 15 low-rated players
	var positions: Array[String] = [
		"GK",  # 1 GK
		"DEF", "DEF", "DEF", "DEF",  # 4 DEF
		"MID", "MID", "MID", "MID",  # 4 MID
		"FWD", "FWD",  # 2 FWD
		# Subs
		"GK", "DEF", "MID", "FWD"
	]
	
	for i in range(positions.size()):
		var card := PlayerCard.new()
		card.position = positions[i]
		card.player_name = _generate_random_name()
		_randomize_low_stats(card)
		card.calculate_overall()
		player_squad.append(card)
	
	# Set default starting 11 (first 11 players)
	starting_11 = range(11)
	substitutes = range(11, 15)
	
	_update_team_rating()
	squad_updated.emit()

func _generate_random_name() -> String:
	var first_names := ["James", "John", "Robert", "Michael", "David", "Alex", "Chris", "Tom", "Luke", "Ryan"]
	var last_names := ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Wilson", "Moore"]
	return first_names[randi() % first_names.size()] + " " + last_names[randi() % last_names.size()]

func _randomize_low_stats(card: PlayerCard) -> void:
	# Low-rated starters (35-55 range)
	if card.position == "GK":
		card.diving = randf_range(0.35, 0.55)
		card.handling = randf_range(0.35, 0.55)
		card.positioning = randf_range(0.35, 0.55)
		card.reflexes = randf_range(0.35, 0.55)
	else:
		card.pace = randf_range(0.35, 0.55)
		card.shooting = randf_range(0.35, 0.55)
		card.passing = randf_range(0.35, 0.55)
		card.dribbling = randf_range(0.35, 0.55)
		card.defending = randf_range(0.35, 0.55)
		card.physical = randf_range(0.35, 0.55)
	
	# Adjust stats based on position
	match card.position:
		"DEF":
			card.defending += randf_range(0.1, 0.2)
			card.physical += randf_range(0.05, 0.15)
		"MID":
			card.passing += randf_range(0.1, 0.2)
			card.dribbling += randf_range(0.05, 0.15)
		"FWD":
			card.shooting += randf_range(0.1, 0.2)
			card.pace += randf_range(0.05, 0.15)
	
	# Clamp all stats
	card.pace = clamp(card.pace, 0.1, 1.0)
	card.shooting = clamp(card.shooting, 0.1, 1.0)
	card.passing = clamp(card.passing, 0.1, 1.0)
	card.dribbling = clamp(card.dribbling, 0.1, 1.0)
	card.defending = clamp(card.defending, 0.1, 1.0)
	card.physical = clamp(card.physical, 0.1, 1.0)
	
	# Starter squad has varied potential (some diamonds in the rough!)
	var potential_roll := randf()
	if potential_roll < 0.7:  # 70% low potential
		card.max_level = randi_range(3, 5)
		card.potential_rating = randi_range(50, 65)
		card.upgrade_cost_base = 100
	elif potential_roll < 0.95:  # 25% medium potential
		card.max_level = randi_range(5, 7)
		card.potential_rating = randi_range(65, 78)
		card.upgrade_cost_base = 150
	else:  # 5% hidden gem!
		card.max_level = randi_range(7, 10)
		card.potential_rating = randi_range(75, 88)
		card.upgrade_cost_base = 200
		card.card_rarity = "RARE"  # Upgrade rarity for hidden gem

func _update_team_rating() -> void:
	if starting_11.is_empty():
		team_rating = 50
		return
	
	var total: int = 0
	for idx in starting_11:
		if idx < player_squad.size():
			total += player_squad[idx].overall_rating
	
	team_rating = total / starting_11.size()

func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)

func spend_money(amount: int) -> bool:
	if money >= amount:
		money -= amount
		money_changed.emit(money)
		return true
	return false

func get_starting_11_as_match_data() -> Array:
	# Convert starting 11 to format match engine expects
	var team_data: Array = []
	for idx in starting_11:
		if idx < player_squad.size():
			team_data.append(player_squad[idx].to_match_player())
	return team_data


func can_afford_pack() -> bool:
	return money >= PACK_COST

func open_pack() -> Array[PlayerCard]:
	if not can_afford_pack():
		return []
	
	spend_money(PACK_COST)
	
	var new_cards: Array[PlayerCard] = []
	for i in range(CARDS_PER_PACK):
		var card := _generate_random_player()
		new_cards.append(card)
		player_squad.append(card)  # Add to squad
	
	squad_updated.emit()
	pack_opened.emit(new_cards)
	
	return new_cards

func _generate_random_player() -> PlayerCard:
	var card := PlayerCard.new()
	
	# Random position
	var positions := ["GK", "DEF", "DEF", "MID", "MID", "MID", "FWD", "FWD"]
	card.position = positions[randi() % positions.size()]
	
	card.nationality = _get_random_nationality()
	
	card.player_name = _generate_random_name()
	
	# Determine rarity (affects stat ranges)
	var rarity_roll := randf()
	if rarity_roll < 0.60:  # 60% common
		card.card_rarity = "COMMON"
		_randomize_stats(card, 0.30, 0.60)  # 30-60 range
		card.max_level = randi_range(3, 5)
		card.potential_rating = randi_range(55, 70)
		card.upgrade_cost_base = 100
	elif rarity_roll < 0.85:  # 25% rare
		card.card_rarity = "RARE"
		_randomize_stats(card, 0.50, 0.75)  # 50-75 range
		card.max_level = randi_range(5, 7)
		card.potential_rating = randi_range(70, 82)
		card.upgrade_cost_base = 150
	elif rarity_roll < 0.96:  # 11% epic
		card.card_rarity = "EPIC"
		_randomize_stats(card, 0.65, 0.85)  # 65-85 range
		card.max_level = randi_range(7, 10)
		card.potential_rating = randi_range(80, 92)
		card.upgrade_cost_base = 250
	else:  # 4% legendary
		card.card_rarity = "LEGENDARY"
		_randomize_stats(card, 0.80, 0.95)  # 80-95 range
		card.max_level = randi_range(8, 10)
		card.potential_rating = randi_range(88, 99)
		card.upgrade_cost_base = 400
	
	_randomize_personality(card)
	
	card.calculate_overall()
	var potential_bonus: int = (card.potential_rating - card.overall_rating) * 10
	card.market_value = card.overall_rating * 50 + potential_bonus + randi_range(-200, 200)
	card.wages = card.overall_rating * 2 + randi_range(-10, 10)
	
	return card


func _randomize_stats(card: PlayerCard, min_val: float, max_val: float) -> void:
	if card.position == "GK":
		card.diving = randf_range(min_val, max_val)
		card.handling = randf_range(min_val, max_val)
		card.positioning = randf_range(min_val, max_val)
		card.reflexes = randf_range(min_val, max_val)
	else:
		card.pace = randf_range(min_val, max_val)
		card.shooting = randf_range(min_val, max_val)
		card.passing = randf_range(min_val, max_val)
		card.dribbling = randf_range(min_val, max_val)
		card.defending = randf_range(min_val, max_val)
		card.physical = randf_range(min_val, max_val)
	
	# Position-based adjustments (ADDED - was missing)
	match card.position:
		"DEF":
			card.defending += randf_range(0.1, 0.2)
			card.physical += randf_range(0.05, 0.15)
		"MID":
			card.passing += randf_range(0.1, 0.2)
			card.dribbling += randf_range(0.05, 0.15)
		"FWD":
			card.shooting += randf_range(0.1, 0.2)
			card.pace += randf_range(0.05, 0.15)
	
	# Clamp all stats (ADDED - was missing)
	card.pace = clamp(card.pace, 0.1, 1.0)
	card.shooting = clamp(card.shooting, 0.1, 1.0)
	card.passing = clamp(card.passing, 0.1, 1.0)
	card.dribbling = clamp(card.dribbling, 0.1, 1.0)
	card.defending = clamp(card.defending, 0.1, 1.0)
	card.physical = clamp(card.physical, 0.1, 1.0)


func _randomize_personality(card: PlayerCard) -> void:
	# Generate personality traits (0.3 - 0.9 range for variety)
	card.leadership = randf_range(0.3, 0.9)
	card.work_rate = randf_range(0.3, 0.9)
	card.creativity = randf_range(0.3, 0.9)
	card.aggression = randf_range(0.3, 0.9)
	card.composure = randf_range(0.3, 0.9)
	card.teamwork = randf_range(0.3, 0.9)
	
	# Position-based personality tendencies
	match card.position:
		"GK":
			card.composure += randf_range(0.1, 0.2)  # GKs need composure
			card.leadership += randf_range(0.05, 0.15)  # Often captains
		"DEF":
			card.aggression += randf_range(0.05, 0.15)  # Defenders are tougher
			card.work_rate += randf_range(0.05, 0.15)
			card.leadership += randf_range(0.05, 0.10)
		"MID":
			card.creativity += randf_range(0.1, 0.2)  # Mids are creative
			card.teamwork += randf_range(0.1, 0.15)  # Need to link play
			card.work_rate += randf_range(0.05, 0.15)
		"FWD":
			card.composure += randf_range(0.05, 0.15)  # Finishing under pressure
			card.creativity += randf_range(0.05, 0.10)
	
	# Clamp all personality traits
	card.leadership = clamp(card.leadership, 0.0, 1.0)
	card.work_rate = clamp(card.work_rate, 0.0, 1.0)
	card.creativity = clamp(card.creativity, 0.0, 1.0)
	card.aggression = clamp(card.aggression, 0.0, 1.0)
	card.composure = clamp(card.composure, 0.0, 1.0)
	card.teamwork = clamp(card.teamwork, 0.0, 1.0)


func _get_random_nationality() -> String:
	if nationalities.is_empty():
		return "ENG"  # Fallback
	
	# Weighted random selection
	var total_weight := 0.0
	for weight in nationality_weights:
		total_weight += weight
	
	var rand_val := randf() * total_weight
	var cumulative := 0.0
	
	for i in range(nationalities.size()):
		cumulative += nationality_weights[i]
		if rand_val <= cumulative:
			return nationalities[i]["code"]
	
	return nationalities[0]["code"]  # Fallback to first


func get_nationality_name(code: String) -> String:
	for nat in nationalities:
		if nat["code"] == code:
			return nat["name"]
	return code

func get_nationality_flag(code: String) -> String:
	for nat in nationalities:
		if nat["code"] == code:
			return nat.get("flag", "")
	return ""


func upgrade_player(squad_index: int) -> bool:
	if squad_index < 0 or squad_index >= player_squad.size():
		return false
	
	var card: PlayerCard = player_squad[squad_index]
	
	if not card.can_upgrade():
		return false
	
	var cost: int = card.get_upgrade_cost()
	if not spend_money(cost):
		return false
	
	card.upgrade()
	squad_updated.emit()
	return true


# Save/Load
func save_game() -> void:
	var save_data := {
		"squad": [],
		"starting_11": starting_11,
		"substitutes": substitutes,
		"money": money,
		"season": season,
		"team_name": team_name
	}
	
	# Serialize player cards
	for card in player_squad:
		save_data["squad"].append({
			"name": card.player_name,
			"position": card.position,
			"nationality": card.nationality,
			"level": card.level,
			"max_level": card.max_level,
			"potential": card.potential_rating,
			"upgrade_cost": card.upgrade_cost_base,
			"pace": card.pace,
			"shooting": card.shooting,
			"passing": card.passing,
			"dribbling": card.dribbling,
			"defending": card.defending,
			"physical": card.physical,
			"diving": card.diving,
			"handling": card.handling,
			"positioning_stat": card.positioning,
			"reflexes": card.reflexes,
			"leadership": card.leadership,
			"work_rate": card.work_rate,
			"creativity": card.creativity,
			"aggression": card.aggression,
			"composure": card.composure,
			"teamwork": card.teamwork,
			"rarity": card.card_rarity,
			"overall": card.overall_rating,
			"form": card.current_form,
			"morale": card.morale,
			"games": card.games_played,
			"goals": card.goals_scored,
			"assists": card.assists,
			"clean_sheets": card.clean_sheets,
			"value": card.market_value,
			"wages": card.wages
		})
	
	var file := FileAccess.open("user://savegame.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	print("Game saved!")

func load_game() -> bool:
	if not FileAccess.file_exists("user://savegame.json"):
		return false
	
	var file := FileAccess.open("user://savegame.json", FileAccess.READ)
	var json_string := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var parse_result := json.parse(json_string)
	if parse_result != OK:
		return false
	
	var save_data: Dictionary = json.data
	
	# Load data
	money = save_data.get("money", 1000)
	season = save_data.get("season", 1)
	team_name = save_data.get("team_name", "My Club")
	starting_11 = save_data.get("starting_11", [])
	substitutes = save_data.get("substitutes", [])
	
	# Deserialize player cards
	player_squad.clear()
	for card_data in save_data.get("squad", []):
		var card := PlayerCard.new()
		card.player_name = card_data.get("name", "Unknown")
		card.position = card_data.get("position", "MID")
		card.nationality = card_data.get("nationality", "ENG")
		card.level = card_data.get("level", 1)
		card.max_level = card_data.get("max_level", 5)
		card.potential_rating = card_data.get("potential", 75)
		card.upgrade_cost_base = card_data.get("upgrade_cost", 200)
		card.pace = card_data.get("pace", 0.5)
		card.shooting = card_data.get("shooting", 0.5)
		card.passing = card_data.get("passing", 0.5)
		card.dribbling = card_data.get("dribbling", 0.5)
		card.defending = card_data.get("defending", 0.5)
		card.physical = card_data.get("physical", 0.5)
		card.diving = card_data.get("diving", 0.5)
		card.handling = card_data.get("handling", 0.5)
		card.positioning = card_data.get("positioning_stat", 0.5)
		card.reflexes = card_data.get("reflexes", 0.5)
		card.leadership = card_data.get("leadership", 0.5)
		card.work_rate = card_data.get("work_rate", 0.5)
		card.creativity = card_data.get("creativity", 0.5)
		card.aggression = card_data.get("aggression", 0.5)
		card.composure = card_data.get("composure", 0.5)
		card.teamwork = card_data.get("teamwork", 0.5)
		card.card_rarity = card_data.get("rarity", "COMMON")
		card.overall_rating = card_data.get("overall", 50)
		card.current_form = card_data.get("form", 0.5)
		card.morale = card_data.get("morale", 0.7)
		card.games_played = card_data.get("games", 0)
		card.goals_scored = card_data.get("goals", 0)
		card.assists = card_data.get("assists", 0)
		card.clean_sheets = card_data.get("clean_sheets", 0)
		card.market_value = card_data.get("value", 1000)
		card.wages = card_data.get("wages", 100)
		player_squad.append(card)
	
	_update_team_rating()
	squad_updated.emit()
	money_changed.emit(money)
	
	print("Game loaded!")
	return true
