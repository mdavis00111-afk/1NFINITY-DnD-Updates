extends RefCounted
## Single local audience registry. Provider safety settings are not modified.
const PATH = "user://settings.cfg"
const SECTION = "campaign_maturity"
const KEY = "profiles"
const DEFAULT_ID = "standard"
const IDS = ["family", "standard", "mature"]
# The legacy editor supported 24 custom entries. Built-ins must not consume those slots.
const MAX_LEGACY_PROFILES = 24
const DEFAULTS = [
	{"id":"family","name":"Family friendly","instructions":"Audience: children and families. No graphic violence; conflict is brief or off-screen. Friendship rather than romance. At most a mildly spooky tone."},
	{"id":"standard","name":"Standard","instructions":"Audience: general adult table. Ordinary fantasy violence without lingering gore. Romance may be implied; sexual activity stays off-page."},
	{"id":"mature","name":"Mature","instructions":"Audience: confirmed adult table. Dark themes, horror, profanity, more intense fantasy combat and complex relationships may be appropriate. Intimate scenes remain non-explicit."}
]
# Compatibility for the old editor until specialist 01 replaces it.
const EXAMPLE = '[{"id":"standard","name":"Standard","instructions":"Ordinary fantasy violence; sexual activity off-page."}]'

static func default_profiles() -> Array:
	return DEFAULTS.duplicate(true)

static func validate(value: Variant) -> String:
	if not value is Array:
		return "Profiles must be a JSON array."
	if value.size() > MAX_LEGACY_PROFILES + IDS.size():
		return "Use at most 24 legacy profiles plus the three built-in profiles."
	var seen: Dictionary = {}
	var legacy_count = 0
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
		if not IDS.has(id):
			legacy_count += 1
	if legacy_count > MAX_LEGACY_PROFILES:
		return "Use at most 24 legacy profiles."
	return ""

static func _merge(value: Array) -> Array:
	var result = default_profiles()
	for saved in value:
		var index = IDS.find(saved["id"])
		if index >= 0:
			result[index]["instructions"] = saved["instructions"]
		else:
			# Preserve historical custom IDs for existing campaigns, not new choices.
			result.append(saved.duplicate(true))
	return result

static func load_profiles() -> Array:
	var config = ConfigFile.new()
	if config.load(PATH) != OK:
		return default_profiles()
	var value = config.get_value(SECTION, KEY, [])
	if not validate(value).is_empty():
		return default_profiles()
	return _merge(value)

static func selectable_profiles() -> Array:
	return load_profiles().slice(0, IDS.size())

# Strict lookup for existing creation validation; never silently accept an unknown ID.
static func resolve(id: String) -> Dictionary:
	for profile in load_profiles():
		if profile["id"] == id:
			return profile.duplicate(true)
	return {}

static func resolve_for_narration(id: String) -> Dictionary:
	var profile = resolve(id)
	if profile.is_empty():
		return resolve(DEFAULT_ID)
	return profile

static func needs_adult_confirmation(id: String) -> bool:
	return id == "mature"

static func guidance(id: String) -> String:
	var profile = resolve_for_narration(id)
	var index = IDS.find(profile["id"])
	if index < 0:
		index = IDS.find(DEFAULT_ID)
	# An editable instruction may refine, not weaken the audience baseline.
	return "[CONTENT LEVEL: %s]\nAudience baseline: %s\nEditable guidance: %s" % [profile["name"], DEFAULTS[index]["instructions"], profile["instructions"]]

static func save_profiles(value: Variant) -> String:
	var error = validate(value)
	if not error.is_empty():
		return error
	var config = ConfigFile.new()
	var loaded = config.load(PATH)
	if loaded != OK and loaded != ERR_FILE_NOT_FOUND:
		return "Cannot read settings. Existing file not overwritten."
	var previous = config.get_value(SECTION, KEY, [])
	if not validate(previous).is_empty():
		return "Existing maturity profiles are invalid. Settings not overwritten."
	# Merge changes by ID, retaining other profiles and unrelated settings.
	var combined: Array = previous.duplicate(true)
	for edit in value:
		var replaced = false
		for i in range(combined.size()):
			if combined[i]["id"] == edit["id"]:
				combined[i] = edit.duplicate(true)
				replaced = true
				break
		if not replaced:
			combined.append(edit.duplicate(true))
	var merged = _merge(combined)
	error = validate(merged)
	if not error.is_empty():
		return error
	config.set_value(SECTION, KEY, merged)
	if config.save(PATH) != OK:
		return "Could not save maturity profiles."
	return ""

static func save_guidance(id: String, instructions: String) -> String:
	if not IDS.has(id):
		return "Choose a supported maturity profile."
	var profile = resolve(id)
	profile["instructions"] = instructions.strip_edges()
	return save_profiles([profile])

static func reset_guidance(id: String) -> String:
	var index = IDS.find(id)
	if index < 0:
		return "Choose a supported maturity profile."
	return save_profiles([DEFAULTS[index]])
