extends Node
## Settings for the next battle, chosen in the main menu and Battle Setup.

const Jobs = preload("res://scripts/core/jobs.gd")
const MapData = preload("res://scripts/core/map_data.gd")
const GameState = preload("res://scripts/core/game_state.gd")
const AstraImport = preload("res://scripts/core/astra_import.gd")
const TUNING_PATH := "user://tuning.cfg"
const STATS_PATH := "user://class_stats.cfg"

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
## Class stats changed in the Unit Guide ({job id: {stat: value}}), saved.
var stat_overrides := {}
## The number evasion and criticals are rolled from (online: the host's; a
## replay: the one its battle used).
var online_seed := 0
var replay_seed := 0
## Online: the host's changed stats for this match.
var online_overrides := {}
## Changed stats at the start of the battle being replayed.
var replay_overrides := {}
## Messages from loading imported classes (shown in Developer Tools).
var class_messages: Array[String] = []


func _ready() -> void:
	_load_tuning()
	class_messages = AstraImport.load_all()
	for m in class_messages:
		print(m)
	_load_stats()


## The random seed the next battle uses.
func battle_seed() -> int:
	if not replay_log.is_empty():
		return replay_seed
	if mode == "online":
		return online_seed
	return randi()


## Changed class stats the next battle uses (and makes active).
func battle_overrides() -> Dictionary:
	if not replay_log.is_empty():
		return replay_overrides
	if mode == "online":
		return online_overrides
	return stat_overrides


## Changes one class stat (Unit Guide), saves it and makes it active.
## The class's own value clears the change.
func set_stat(job_id: String, stat: String, value: int) -> void:
	var changes: Dictionary = stat_overrides.duplicate(true)
	if not changes.has(job_id):
		changes[job_id] = {}
	changes[job_id][stat] = value
	stat_overrides = Jobs.clean_overrides(changes)
	_save_stats()


## Puts a class's stats (or every class's, with "") back to their own.
func reset_stats(job_id := "") -> void:
	if job_id == "":
		stat_overrides = {}
	else:
		stat_overrides.erase(job_id)
	_save_stats()


func _save_stats() -> void:
	Jobs.set_overrides(stat_overrides)
	var cfg := ConfigFile.new()
	for id in stat_overrides:
		for stat in stat_overrides[id]:
			cfg.set_value(id, stat, stat_overrides[id][stat])
	cfg.save(STATS_PATH)


func _load_stats() -> void:
	var cfg := ConfigFile.new()
	var changes := {}
	if cfg.load(STATS_PATH) == OK:
		for id in cfg.get_sections():
			changes[id] = {}
			for stat in cfg.get_section_keys(id):
				changes[id][stat] = cfg.get_value(id, stat)
	stat_overrides = Jobs.clean_overrides(changes)
	Jobs.set_overrides(stat_overrides)


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
