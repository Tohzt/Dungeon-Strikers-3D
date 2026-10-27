class_name MatchStats extends RefCounted
## Each player's tally over a match, for the end-of-match screen
## (MatchStatsScreen): kills, deaths, goals, damage dealt to the other teams'
## players and to bosses, and bosses slain. Only kept where the match is
## decided (Net.decides()); Game3D sends everyone the finished rows with
## the result.

const FIELDS: Array[StringName] = [&"kills", &"deaths", &"goals", &"damage", &"boss_damage", &"boss_kills"]

## Player node name -> field -> running total.
var _tally: Dictionary[String, Dictionary] = {}


func add(player: PlayerClass3D, field: StringName, amount: float = 1.0) -> void:
	if not player:
		return
	var row: Dictionary = _tally.get_or_add(String(player.name), {})
	row[field] = row.get(field, 0.0) + amount


## One Dictionary per player, ready to send over the network: who they are
## (node name, label, team, character, bot) and a whole number for each of
## FIELDS.
func rows(players: Array[PlayerClass3D]) -> Array:
	var found: Array = []
	for player: PlayerClass3D in players:
		if not is_instance_valid(player) or not player.slot:
			continue
		var tally: Dictionary = _tally.get(String(player.name), {})
		var row: Dictionary = {
			"name": String(player.name),
			"label": player.slot.label(),
			"team": player.slot.team,
			"character": player.slot.character,
			"bot": player.slot.is_bot,
		}
		for field: StringName in FIELDS:
			row[String(field)] = roundi(tally.get(field, 0.0))
		found.append(row)
	return found
