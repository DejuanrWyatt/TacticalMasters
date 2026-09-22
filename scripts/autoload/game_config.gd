extends Node
## Settings for the next battle, chosen in the main menu.

## "ai" (vs computer), "hotseat" (two players, one device) or "online".
var mode := "hotseat"
## Team the computer plays in "ai" mode (the human is the other team).
var ai_team := 1
## Computer skill in "ai" mode: "easy", "medium" or "hard" (see AIPlayer.LEVELS).
var ai_difficulty := "medium"
## Team this device plays in "online" mode.
var local_team := 0


func start_online(team: int) -> void:
	mode = "online"
	local_team = team
