class_name PlayerNames
## What players are called: a random silly name to start with (see
## Players.join), which they can change in the lobby. The name is also
## their health bar in a match (NameTag), so names are kept short.
##
## The last name typed on this machine is remembered (saved()), so the
## person at the keyboard doesn't have to type it in every time.

const MAX_LENGTH := 12
const PROFILE_PATH := "user://profile.cfg"

const RANDOM: Array[String] = [
	"Bonk", "Grub", "Noodle", "Sir Wobble", "Pip", "Gristle", "Mumbo", "Boop",
	"Turnip", "Gobbo", "Crumpet", "Snort", "Biscuit", "Dingus", "Lumpy", "Fizz",
	"Gloop", "Wiggles", "Sprout", "Chonk", "Bramble", "Nugget", "Pickle", "Rumble",
	"Scoot", "Toadie", "Waffle", "Zonk", "Bungle", "Mopsy", "Clank", "Tater",
	"Grumbo", "Squee", "Kevin", "Plonk", "Muffin", "Doodle", "Bork", "Yeet",
]


## A random name nobody in `taken` has (one of them anyway if all are).
static func random(taken: Array = []) -> String:
	var free: Array = RANDOM.filter(func(n: String) -> bool: return not taken.has(n))
	return str(free.pick_random() if not free.is_empty() else RANDOM.pick_random())


## `text` made fit to show: no spaces at the ends, at most MAX_LENGTH long.
static func clean(text: String) -> String:
	return text.strip_edges().left(MAX_LENGTH).strip_edges()


## The name last typed on this machine, or "" if none has been.
static func saved() -> String:
	var profile := ConfigFile.new()
	if profile.load(PROFILE_PATH) != OK:
		return ""
	return clean(str(profile.get_value("player", "name", "")))


static func save(text: String) -> void:
	var profile := ConfigFile.new()
	profile.load(PROFILE_PATH)  # Keep anything else in it
	profile.set_value("player", "name", clean(text))
	profile.save(PROFILE_PATH)
