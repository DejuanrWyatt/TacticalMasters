extends Node
## Settings for the next battle, chosen in the main menu and Battle Setup.

const Jobs = preload("res://scripts/core/jobs.gd")
const MapData = preload("res://scripts/core/map_data.gd")
const GameState = preload("res://scripts/core/game_state.gd")
const AstraImport = preload("res://scripts/core/astra_import.gd")
const TUNING_PATH := "user://tuning.cfg"

## "ai" (vs computer), "cpu" (computer vs computer, to watch), "hotseat"
## (two players, one device) or "online".
var mode := "hotseat"
## Team the computer plays in "ai" mode (the human is the other team).
var ai_team := 1
## Computer skill in "ai" mode: "easy", "medium" or "hard" (see AIPlayer.LEVELS).
var ai_difficulty := "medium"
## "cpu" mode: Blue's computer skill (Red uses ai_difficulty).
var ai_difficulty_blue := "medium"
## Team this device plays in "online" mode.
var local_team := 0
## Map to fight on (see MapData.MAPS).
var map_id := MapData.DEFAULT_MAP
## Jobs for each team: [blue 4 job ids, red 4 job ids].
var rosters: Array = [Jobs.DEFAULT_ROSTER.duplicate(), Jobs.DEFAULT_ROSTER.duplicate()]
## When not empty, the next battle is a replay of these recorded commands.
var replay_log: Array = []
## Rule numbers at the start of the battle being replayed.
var replay_tuning := {}
## Developer Tools rule numbers (only the changed ones), saved between runs.
var tuning := {}
## Online: the host's rule numbers for this match.
var online_tuning := {}
## Messages from loading imported classes (shown in Developer Tools).
var class_messages: Array[String] = []


func _ready() -> void:
	_load_tuning()
	class_messages = AstraImport.load_all()
	for m in class_messages:
		print(m)


## Rule numbers the next battle starts with.
func battle_tuning() -> Dictionary:
	if not replay_log.is_empty():
		return replay_tuning
	if mode == "online":
		return online_tuning
	return tuning


## Changes one rule number (Developer Tools) and saves it.
func set_tuning(key: String, value: float) -> void:
	if is_equal_approx(value, GameState.TUNING[key][0]):
		tuning.erase(key)
	else:
		tuning[key] = value
	save_tuning()


func reset_tuning() -> void:
	tuning.clear()
	save_tuning()


func save_tuning() -> void:
	var cfg := ConfigFile.new()
	for key in tuning:
		cfg.set_value("tuning", key, tuning[key])
	cfg.save(TUNING_PATH)


func _load_tuning() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(TUNING_PATH) != OK or not cfg.has_section("tuning"):
		return
	var values := {}
	for key in cfg.get_section_keys("tuning"):
		values[key] = cfg.get_value("tuning", key)
	tuning = GameState.clean_tuning(values)


## Teams the computer plays in the current mode.
func ai_teams() -> Array:
	match mode:
		"ai":
			return [ai_team]
		"cpu":
			return [0, 1]
	return []


## Computer skill for a team.
func difficulty_for(team: int) -> String:
	return ai_difficulty_blue if mode == "cpu" and team == 0 else ai_difficulty


func start_online(team: int) -> void:
	mode = "online"
	local_team = team


## The map dictionary for GameState.setup(), from the current settings.
func build_map() -> Dictionary:
	return MapData.build(map_id, rosters[0], rosters[1])
