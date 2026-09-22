extends RefCounted
## Built-in maps. Each character is a 2 m x 2 m block of ground: digits are
## its height level (1-5) and "~" is water, which can't be walked on. Maps
## are point-symmetric: the bottom half is the top half rotated 180 degrees,
## so neither side gets better ground.

const Jobs = preload("res://scripts/core/jobs.gd")

const TILE_SIZE := 2.0

const HIGHLANDS_TOP := [
	"112233211111",
	"112233211111",
	"111222111111",
	"111111111111",
	"122111121111",
	"123111121111",
]

## Blue's starting positions in meters (navigation node centers).
## Red starts at the mirrored positions.
const HIGHLANDS_SPAWNS := [Vector2(2.75, 4.75), Vector2(0.75, 8.75), Vector2(4.75, 6.75), Vector2(2.75, 10.75)]


static func highlands(blue_roster: Array = Jobs.DEFAULT_ROSTER, red_roster: Array = Jobs.DEFAULT_ROSTER) -> Dictionary:
	return _symmetric("Highlands", HIGHLANDS_TOP, HIGHLANDS_SPAWNS, [blue_roster, red_roster])


## Builds a map dictionary:
## {"name", "rows": Array[String], "units": [[job, team, Vector2], ...], "spawn_points": [blue, red]}
static func _symmetric(map_name: String, top: Array, spawns: Array, rosters: Array) -> Dictionary:
	var rows: Array = top.duplicate()
	for i in range(top.size() - 1, -1, -1):
		rows.append((top[i] as String).reverse())
	var size := Vector2((rows[0] as String).length(), rows.size()) * TILE_SIZE
	var units := []
	for team in 2:
		for i in mini(rosters[team].size(), spawns.size()):
			var p: Vector2 = spawns[i]
			units.append([rosters[team][i], team, p if team == 0 else size - p])
	return {
		"name": map_name,
		"rows": rows,
		"units": units,
		"spawn_points": [spawns[0], size - spawns[0]],
	}
