extends Node
## Settings for the next battle, chosen in the main menu and Battle Setup.

const Jobs = preload("res://scripts/core/jobs.gd")
const MapData = preload("res://scripts/core/map_data.gd")

## "ai" (vs computer), "hotseat" (two players, one device) or "online".
var mode := "hotseat"
## Team the computer plays in "ai" mode (the human is the other team).
var ai_team := 1
## Computer skill in "ai" mode: "easy", "medium" or "hard" (see AIPlayer.LEVELS).
var ai_difficulty := "medium"
## Team this device plays in "online" mode.
var local_team := 0
## Map to fight on (see MapData.MAPS).
var map_id := MapData.DEFAULT_MAP
## Jobs for each team: [blue 4 job ids, red 4 job ids].
var rosters: Array = [Jobs.DEFAULT_ROSTER.duplicate(), Jobs.DEFAULT_ROSTER.duplicate()]
## When not empty, the next battle is a replay of these recorded commands.
var replay_log: Array = []


func start_online(team: int) -> void:
	mode = "online"
	local_team = team


## The map dictionary for GameState.setup(), from the current settings.
func build_map() -> Dictionary:
	return MapData.build(map_id, rosters[0], rosters[1])
