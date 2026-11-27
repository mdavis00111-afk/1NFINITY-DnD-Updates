extends RefCounted
## Owner-supplied content/maturity definitions; no invented defaults.
const PATH = "user://settings.cfg"
const SECTION = "campaign_maturity"
const KEY = "profiles"
const EXAMPLE = '[{"id":"your-profile","name":"Your profile","instructions":"Your approved maturity instructions"}]'

static func validate(value: Variant) -> String:
	if not value is Array:
		return "Profiles must be a JSON array."
	if value.size() > 24:
		return "Use at most 24 profiles."
	var seen: Dictionary = {}
	var regex = RegEx.new()
	regex.compile("^[a-z0-9][a-z0-9_-]{0,47}$")
	for profile in value:
		if not profile is Dictionary:
			return "Each profile must be an object."
		for key in ["id","name","instructions"]:
			if not profile.get(key) is String or str(profile[key]).strip_edges().is_empty():
				return "Each profile needs nonempty id, name and instructions."
		var id = str(profile["id"])
		if regex.search(id) == null or seen.has(id):
			return "Profile IDs must be unique lowercase identifiers."
		if str(profile["name"]).length()>80 or str(profile["instructions"]).length()>12000:
			return "Profile name or instructions exceed the supported length."
		seen[id]=true
	return ""

static func load_profiles() -> Array:
	var config = ConfigFile.new()
	if config.load(PATH) != OK:
		return []
	var value = config.get_value(SECTION,KEY,[])
	if not validate(value).is_empty():
		return []
	return value.duplicate(true)

static func resolve(id: String) -> Dictionary:
	for profile in load_profiles():
		if profile["id"] == id:
			return profile.duplicate(true)
	return {}

static func save_profiles(value: Variant) -> String:
	var error = validate(value)
	if not error.is_empty():
		return error
	var config = ConfigFile.new()
	var loaded = config.load(PATH)
	if loaded != OK and loaded != ERR_FILE_NOT_FOUND:
		return "Cannot read settings. Existing file not overwritten."
	config.set_value(SECTION,KEY,value.duplicate(true))
	if config.save(PATH) != OK:
		return "Could not save maturity profiles."
	return ""
