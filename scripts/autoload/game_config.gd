extends Node
## Settings for the next battle, chosen in the main menu and Battle Setup.

const Jobs = preload("res://scripts/core/jobs.gd")
const MapData = preload("res://scripts/core/map_data.gd")
const GameState = preload("res://scripts/core/game_state.gd")
const AstraImport = preload("res://scripts/core/astra_import.gd")
const TUNING_PATH := "user://tuning.cfg"
## Names that have changed, old to new. Saved files are read through these so
## a player's own numbers survive a rename instead of being quietly dropped.
const RENAMED_STATS := {"wits": "speed"}
const RENAMED_TUNING := {"wits_multiplier": "speed_multiplier"}
## Teams the player saved in Battle Setup, by the name they gave them.
const TEAMS_PATH := "user://teams.cfg"
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
## Commands of that log to play through before the replay is shown: how the
## replay bar jumps to a point in the battle.
var replay_skip := 0
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
	# After the imported classes are registered: a saved team may name one,
	# and a team naming a class the game doesn't know is dropped.
	_load_teams()
	_load_stats()


## The random seed the next battle uses.
## A seed set in Battle Setup (0 = a new battle every time).
var battle_seed_setting := 0


func battle_seed() -> int:
	if not replay_log.is_empty():
		return replay_seed
	if mode == "online":
		return online_seed
	return battle_seed_setting if battle_seed_setting != 0 else randi()


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
				var name: String = RENAMED_STATS.get(stat, stat)
				if name != stat and cfg.has_section_key(id, name):
					continue  # saved under both names: the one in use now wins
				changes[id][name] = cfg.get_value(id, stat)
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


## Saved teams: {name: [4 class ids]}, newest last.
var teams := {}


## Saves (or replaces) a team under a name, and writes it to disk.
func save_team(team_name: String, roster: Array) -> void:
	var clean := team_name.strip_edges()
	if clean == "" or roster.size() != 4:
		return
	teams[clean] = roster.duplicate()
	_save_teams()


func delete_team(team_name: String) -> void:
	if teams.erase(team_name):
		_save_teams()


func _save_teams() -> void:
	var cfg := ConfigFile.new()
	for key in teams:
		cfg.set_value("teams", key, teams[key])
	cfg.save(TEAMS_PATH)


func _load_teams() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(TEAMS_PATH) != OK:
		return
	for key in cfg.get_section_keys("teams") if cfg.has_section("teams") else []:
		var roster = cfg.get_value("teams", key, [])
		# Only what still looks like a team of four known classes.
		if roster is Array and roster.size() == 4:
			var ok := true
			for id in roster:
				if not (id is String and Jobs.all_jobs().has(id)):
					ok = false
			if ok:
				teams[key] = roster


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
		var name: String = RENAMED_TUNING.get(key, key)
		if name != key and cfg.has_section_key("tuning", name):
			continue  # saved under both names: the one in use now wins
		values[name] = cfg.get_value("tuning", key)
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
