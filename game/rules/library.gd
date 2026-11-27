extends RefCounted
const ROOT = "user://rules/2018"
const SECTIONS = {"front_matter":[1,2],"introduction":[3,7],"character_creation":[8,12],"races":[13,21],"classes":[22,34],"backgrounds":[35,44],"equipment":[45,57],"customization":[58,59],"ability_checks":[60,65],"adventuring":[66,71],"combat":[72,81],"spellcasting":[82,85],"spells":[86,109],"monsters":[110,161],"npcs":[162,164],"encounters":[165,167],"magic_items":[168,170],"conditions":[171,171],"gods":[172,173],"factions":[174,176],"character_sheets":[177,179],"next_steps":[180,180]}

func status() -> String:
	var count = 0
	for id in SECTIONS:
		if FileAccess.file_exists(ROOT.path_join(id + ".json")):
			count += 1
	return "Local rules sections: %d / %d" % [count, SECTIONS.size()]

func import_archive(path: String) -> String:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("edition") != "D&D Basic Rules 2018 v1.0":
		return "Invalid edition or archive."
	var sections = data.get("sections", [])
	if not sections is Array or sections.size() != SECTIONS.size():
		return "Invalid section list."
	var seen = {}
	for section in sections:
		if not section is Dictionary:
			return "Invalid section."
		var id = str(section.get("id", ""))
		if not SECTIONS.has(id) or seen.has(id):
			return "Invalid or duplicate section."
		seen[id] = true
		var limits = SECTIONS[id]
		var pages = section.get("pages", [])
		if not pages is Array or pages.size() != limits[1] - limits[0] + 1:
			return "Incomplete section: " + id
		for i in range(pages.size()):
			if not pages[i] is Dictionary or int(pages[i].get("page", 0)) != limits[0] + i or not pages[i].get("text") is String:
				return "Invalid page in " + id
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT)) != OK:
		return "Cannot create local rules directory."
	for section in sections:
		var out = FileAccess.open(ROOT.path_join(str(section["id"]) + ".json"), FileAccess.WRITE)
		if out == null:
			return "Could not write rules section."
		out.store_string(JSON.stringify(section))
		out.close()
	return status()

func search(needle: String) -> String:
	var term = needle.strip_edges().to_lower()
	if term.is_empty():
		return "Enter a rule or term."
	var matches = PackedStringArray()
	for id in SECTIONS:
		var path = ROOT.path_join(id + ".json")
		if not FileAccess.file_exists(path):
			continue
		var section = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not section is Dictionary:
			continue
		for page in section.get("pages", []):
			var body = str(page.get("text", ""))
			if body.to_lower().contains(term):
				matches.append("%s / page %d\n%s" % [id, int(page["page"]), body])
				if matches.size() >= 12:
					return "\n\n".join(matches)
	return "\n\n".join(matches) if not matches.is_empty() else "No matching imported rule pages."
