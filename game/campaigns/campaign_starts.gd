extends RefCounted
## Pre-generated circumstances, never predetermined plots or mechanical outcomes.
const ART = {
	"tavern":"res://art/hall.jpg",
	"court":"res://art/hall.jpg",
	"woods":"res://art/forest.svg",
	"sea":"res://art/valley.svg",
	"market":"res://art/castle.jpg",
	"road":"res://art/valley.svg"
}
const STARTS = [
	{"id":"tavern","name":"Seedy Tavern","kind":"tavern","description":"You begin in a modest, rough-edged tavern. Locals and travellers have their own business. You may talk, rest, investigate or leave."},
	{"id":"court","name":"Royal Court","kind":"court","description":"You begin at a royal court where petitioners, visitors and officials gather. You are free to observe, seek an audience or depart."},
	{"id":"woods","name":"Deep in the Woods","kind":"wilderness","description":"You begin among woodland paths, away from a settlement. The forest offers routes to explore and ordinary wilderness challenges."},
	{"id":"sea","name":"Out at Sea","kind":"ship","description":"You begin aboard a vessel travelling across open water. Crew and passengers attend to their affairs."},
	{"id":"market","name":"Market Town","kind":"settlement","description":"You begin in a busy market town, where traders, residents and travellers go about their day."},
	{"id":"road","name":"Along the Road","kind":"road","description":"You begin on a road through unfamiliar countryside. Other travellers and places may lie ahead."}
]

static func find_start(id: String) -> Dictionary:
	for start in STARTS:
		if start["id"] == id:
			return start.duplicate(true)
	return {}

static func texture_for(id: String) -> Texture2D:
	var path = str(ART.get(id,ART["road"]))
	var texture = load(path) as Texture2D
	if id=="market":
		var crop = AtlasTexture.new()
		crop.atlas=texture
		crop.region=Rect2(900,14,760,570)
		return crop
	return texture

static func valid_art(id: String) -> bool:
	return ART.has(id)
