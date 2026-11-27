extends RefCounted
## Edition-separated local references. No reference text is treated as executable logic.
func root() -> String:
	return OS.get_executable_path().get_base_dir().path_join("reference")

func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func status() -> String:
	return "Local master reference available." if FileAccess.file_exists(root().path_join("master_index.json")) else "Master reference not installed. Use the recovery ZIP."

func categories(edition: String) -> Array:
	var result: Array = ["character_options", "creatures"]
	var index = read_json(root().path_join("master_index.json"))
	if index is Dictionary:
		for record in index.get("editions", []):
			if record.get("id") == edition:
				for part in record.get("sections", []):
					result.append(str(part.get("id")))
	return result

func lookup(edition: String, category: String, query: String) -> String:
	if edition not in ["2018", "2024"] or category not in categories(edition):
		return "Invalid edition or category."
	var data = read_json(root().path_join(edition).path_join(category + ".json"))
	var needle = query.strip_edges().to_lower()
	var results = PackedStringArray()
	if category == "character_options" and data is Dictionary:
		return JSON.stringify(data, "  ")
	if category == "creatures" and data is Array:
		for record in data:
			var name = str(record.get("name", ""))
			if needle.is_empty():
				results.append("%s - p. %s" % [name, str(record.get("page"))])
			elif name.to_lower().contains(needle):
				results.append("%s - pages %s to %s\n%s" % [name, str(record.get("start_page")), str(record.get("end_page")), str(record.get("text", ""))])
				if results.size() >= 12:
					break
	elif data is Dictionary:
		for page in data.get("pages", []):
			var body = str(page.get("text", ""))
			if needle.is_empty() or (needle.is_valid_int() and int(needle) == int(page["page"])) or (not needle.is_valid_int() and body.to_lower().contains(needle)):
				results.append("Edition %s | page %d\n%s" % [edition, int(page["page"]), body])
				if results.size() >= 12:
					break
	return "\n\n".join(results) if not results.is_empty() else "No matching local reference. " + status()
