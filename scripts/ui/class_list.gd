extends RefCounted
## Picking classes out of the 100-odd the game knows, the same way everywhere:
## the Unit Guide's table and Battle Setup's class picker both ask here, so a
## search or a role filter means the same thing in both.

const Jobs = preload("res://scripts/core/jobs.gd")

## The ways a list can be ordered: id, and what the picker calls it.
const SORTS := [["name", "Name (A-Z)"], ["role", "Role, then name"], ["hp", "HP"], ["speed", "Speed (fastest first)"]]


## Class ids that match a search (part of a name, case doesn't matter) and a
## role ("" for every role), in the order `sort` asks for.
static func listed_ids(search: String, role_filter: String, sort: String) -> Array:
	var ids := []
	for id in Jobs.all_jobs():
		var job: Dictionary = Jobs.job(id)
		if search != "" and not String(job.name).to_lower().contains(search):
			continue
		if role_filter != "" and not Jobs.roles_of(id).has(role_filter):
			continue
		ids.append(id)
	var order := Jobs.ROLES.keys()
	var by_name := func(a, b): return String(Jobs.job(a).name).naturalnocasecmp_to(Jobs.job(b).name) < 0
	match sort:
		"role":
			var by_role := func(a, b):
				var ra: int = order.find(Jobs.roles_of(a)[0])
				var rb: int = order.find(Jobs.roles_of(b)[0])
				if ra != rb:
					return ra < rb
				return by_name.call(a, b)
			ids.sort_custom(by_role)
		"hp":
			ids.sort_custom(func(a, b): return Jobs.job(a).hp > Jobs.job(b).hp)
		"speed":
			ids.sort_custom(func(a, b): return Jobs.job(a).speed > Jobs.job(b).speed)
		_:
			ids.sort_custom(by_name)
	return ids


## A class's role icons side by side, as one control.
static func role_icons(id: String, size := 16) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.tooltip_text = "%s: %s" % [Jobs.job(id).name, Jobs.role_name(id)]
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	for role in Jobs.roles_of(id):
		var icon := TextureRect.new()
		icon.texture = load(Jobs.ROLES[role].icon)
		icon.custom_minimum_size = Vector2(size, size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
	return box


## A team of four that makes sense to field: a tank, two damage dealers and
## someone to keep them alive, picked at random from the classes of each role.
static func sensible_team(rng: RandomNumberGenerator) -> Array:
	var wanted := ["tank", "damage", "damage", "support"]
	var out := []
	for role in wanted:
		var choices := listed_ids("", role, "name")
		# Prefer a class that isn't already on the team, so it isn't four of a kind.
		var fresh := []
		for id in choices:
			if not out.has(id):
				fresh.append(id)
		if fresh.is_empty():
			fresh = choices
		if fresh.is_empty():
			fresh = Jobs.all_jobs().keys()
		out.append(fresh[rng.randi_range(0, fresh.size() - 1)])
	return out
