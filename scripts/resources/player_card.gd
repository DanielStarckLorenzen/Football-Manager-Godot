extends Resource
class_name PlayerCard

@export var player_name: String = ""
@export var position: String = "ST"  # GK, DEF, MID, FWD
@export var overall_rating: int = 50  # 1-99
@export var nationality: String = "ENG"

# Outfield player stats (0.0 - 1.0)
@export var pace: float = 0.5
@export var shooting: float = 0.5
@export var passing: float = 0.5
@export var dribbling: float = 0.5
@export var defending: float = 0.5
@export var physical: float = 0.5

# GK specific stats (only used if position == "GK")
@export var diving: float = 0.5
@export var handling: float = 0.5
@export var positioning: float = 0.5
@export var reflexes: float = 0.5

@export var card_rarity: String = "COMMON"  # COMMON, RARE, EPIC, LEGENDARY
@export var player_id: int = 0  # Unique ID

# Upgrade and potential system
@export var level: int = 1 # Current upgrade level (1-10)
@export var max_level: int = 5 # How many times this card can be upgraded
@export var upgrade_cost_base: int = 200 # Base cost to upgrade
@export var potential_rating: int = 60 # Max overall this card can reach

# Personality traits (0.0 - 1.0, affects chemistry and morale)
@export var leadership: float = 0.5
@export var work_rate: float = 0.5
@export var creativity: float = 0.5
@export var aggression: float = 0.5
@export var composure: float = 0.5
@export var teamwork: float = 0.5

# Carrer stats
@export var games_played: int = 0
@export var goals_scored: int = 0
@export var assists: int = 0
@export var clean_sheets: int = 0 # Only for GK and DEFs

# Form and performence
@export var current_form: float = 0.5 # Recent performences (0.0-1.0)
@export var morale: float = 0.7 # Happiness

# Contract/value TODO
@export var market_value: int = 1000 # For transfer system
@export var wages: int = 100 # Weekly cost

func _init() -> void:
	player_id = Time.get_ticks_msec() + randi()

func calculate_overall() -> int:
	if position == "GK":
		var avg: float = (diving + handling + positioning + reflexes) / 4.0
		overall_rating = int(avg * 99.0)
	else:
		var avg: float = (pace + shooting + passing + dribbling + defending + physical) / 6.0
		overall_rating = int(avg * 99.0)
	
	# Level bonus
	if level > 1:
		var level_bonus: int = (level -1) * 2 # +2 rating per level
		overall_rating += level_bonus
	
	# Form affects current performence slightly
	var form_bonus: int = int((current_form - 0.5) * 0.5) # -2 to +2 rating
	overall_rating = clamp(overall_rating + form_bonus, 1, 99)
	
	# Can't exceed potential
	overall_rating = min(overall_rating, potential_rating)
	
	return overall_rating


func can_upgrade() -> bool:
	return level < max_level and overall_rating < potential_rating


func get_upgrade_cost() -> int:
	return upgrade_cost_base * level


func upgrade() -> bool:
	if not can_upgrade():
		return false
	
	level += 1
	
	var growth_amount: float = 0.05 # 5% growth per level
	
	if position == "GK":
		diving = min(diving + growth_amount, 1.0)
		handling = min(handling + growth_amount, 1.0)
		positioning = min(positioning + growth_amount, 1.0)
		reflexes = min(reflexes + growth_amount, 1.0)
	else:
		pace = min(pace + growth_amount, 1.0)
		shooting = min(shooting + growth_amount, 1.0)
		passing = min(passing + growth_amount, 1.0)
		dribbling = min(dribbling + growth_amount, 1.0)
		defending = min(defending + growth_amount, 1.0)
		physical = min(physical + growth_amount, 1.0)
	
	calculate_overall()
	market_value = overall_rating * 50 + randi_range(-200, 200)
	
	return true


func get_effective_overall() -> int:
	var base := float(overall_rating)
	var morale_modifier := (morale - 0.5) * 0.1
	var form_modifier := (current_form - 0.5) * 0.15
	
	var effective := base * (1.0 + morale_modifier + form_modifier)
	return int(clamp(effective, 1, 99))


func get_potential_color() -> Color:
	var potential_gap: int = potential_rating - overall_rating
	
	if potential_gap >= 20:
		return Color(0.3, 1.0, 0.3)  # High potential - bright green
	elif potential_gap >= 10:
		return Color(0.7, 1.0, 0.3)  # Good potential - yellow-green
	elif potential_gap >= 5:
		return Color(1.0, 1.0, 0.3)  # Some potential - yellow
	else:
		return Color(0.6, 0.6, 0.6)  # Low potential - gray


# Convert to match sim format
func to_match_player() -> Dictionary:
	var effective_overall := get_effective_overall()
	var stat_modifier := float(effective_overall) / float(overall_rating) if overall_rating > 0 else 1.0
	
	return {
		"id": player_id,
		"role": _get_role(),
		"pace": pace * stat_modifier,
		"tackle": defending * stat_modifier,
		"pass": passing * stat_modifier,
		"dribble": dribbling * stat_modifier,
		"mark_target": -1
	}

func _get_role() -> String:
	match position:
		"GK": return "GK"
		"DEF", "LB", "CB", "RB": return "DEF"
		"MID", "CDM", "CM", "CAM", "LM", "RM": return "MID"
		"FWD", "ST", "LW", "RW": return "FWD"
		_: return "MID"


func get_personality_type() -> String:
	var traits := {
		"Leader": leadership,
		"Workhorse": work_rate,
		"Playmaker": creativity,
		"Enforcer": aggression,
		"Professional": composure,
		"Team Player": teamwork
	}
	
	var max_trait := ""
	var max_value := 0.0
	for personality_trait in traits:
		if traits[personality_trait] > max_value:
			max_value = traits[personality_trait]
			max_trait = personality_trait
	
	return max_trait


func calculate_chemistry(other: PlayerCard) -> float:
	var chemistry := 0.5
	
	if nationality == other.nationality:
		chemistry += 0.15
	
	var my_type := get_personality_type()
	var their_type := other.get_personality_type()
	
	var compatible := {
		"Leader": ["Team Player", "Workhorse"],
		"Workhorse": ["Leader", "Professional"],
		"Playmaker": ["Team Player", "Professional"],
		"Enforcer": ["Workhorse", "Leader"],
		"Professional": ["Playmaker", "Workhorse"],
		"Team Player": ["Leader", "Playmaker"]
	}
	
	if their_type in compatible.get(my_type, []):
		chemistry += 0.20
	
	chemistry += (teamwork + other.teamwork) * 0.1
	
	return clamp(chemistry, 0.0, 1.0)


func update_form(performance: float) -> void:
	current_form = lerp(current_form, performance, 0.3)
	current_form = clamp(current_form, 0.0, 1.0)


func update_morale(change: float) -> void:
	morale += change
	morale = clamp(morale, 0.0, 1.0)


func get_rating_color() -> Color:
	if overall_rating >= 80:
		return Color(1.0, 0.84, 0.0)  # Gold
	elif overall_rating >= 70:
		return Color(0.75, 0.75, 0.75)  # Silver
	elif overall_rating >= 60:
		return Color(0.8, 0.5, 0.2)  # Bronze
	else:
		return Color(0.6, 0.6, 0.6)  # Gray


func get_level_stars() -> String:
	var stars := ""
	for i in range(max_level):
		if i < level:
			stars += "★"
		else:
			stars += "☆"
	return stars
