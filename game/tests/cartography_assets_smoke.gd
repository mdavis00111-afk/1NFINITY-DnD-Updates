extends SceneTree
## Read-only cartography asset import / SVG decode and metadata smoke suite.
const CATALOG = "res://cartography/art/catalog.json"
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func blob_sha(bytes: PackedByteArray) -> String:
	var header = ("blob "+str(bytes.size())).to_utf8_buffer()
	header.append(0)
	var hash = HashingContext.new()
	hash.start(HashingContext.HASH_SHA1)
	hash.update(header)
	hash.update(bytes)
	return hash.finish().hex_encode()

func run() -> void:
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if not catalog is Dictionary or not catalog.get("assets") is Array:
		push_error("Cartography catalog missing or invalid.")
		quit(1)
		return
	var assets: Array = catalog["assets"]
	expect(assets.size()==250,"Asset count outside specification")
	var ids: Dictionary = {}
	var paths: Dictionary = {}
	var hashes: Dictionary = {}
	for asset in assets:
		if not asset is Dictionary:
			expect(false,"Invalid registry row")
			continue
		var id = str(asset.get("id",""))
		var path = str(asset.get("path",""))
		expect(not id.is_empty() and not ids.has(id),"Duplicate or empty ID: "+id)
		ids[id]=true
		expect(not id.ends_with(".vintage") and asset.get("provenance",{}).get("type")!="open_license_reference_crop","Uncleared art in registry: "+id)
		if not path.begins_with("res://cartography/art/") or not path.ends_with(".svg") or path.contains(".."):
			expect(false,"Unsafe asset path: "+id)
			continue
		expect(not paths.has(path),"Duplicate path: "+id)
		paths[path]=true
		var bytes = FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			expect(false,"Missing source SVG: "+id)
			continue
		var sha = blob_sha(bytes)
		expect(bytes.size()==int(asset.get("byte_size",-1)) and sha==str(asset.get("git_blob_sha1","")),"Asset bytes changed: "+id)
		expect(not hashes.has(sha),"Byte-identical illustration: "+id)
		hashes[sha]=true
		var image = Image.new()
		var err = image.load_svg_from_string(bytes.get_string_from_utf8())
		if err!=OK or image.is_empty():
			expect(false,"SVG decode failed: "+id)
			continue
		expect(image.get_width()==int(asset.get("width",-1)) and image.get_height()==int(asset.get("height",-1)),"SVG dimensions mismatch: "+id)
		image.convert(Image.FORMAT_RGBA8)
		var rgba = image.get_data()
		var has_ink = false
		var has_clear = false
		var has_nonopaque = false
		for i in range(3,rgba.size(),4):
			var alpha = rgba[i]
			if alpha>0: has_ink=true
			if alpha==0: has_clear=true
			if alpha<255: has_nonopaque=true
			if has_ink and has_clear and has_nonopaque:
				break
		expect(has_ink,"Blank illustration: "+id)
		if asset.get("transparent",false):
			expect(has_clear,"No transparent background: "+id)
		else:
			expect(str(asset.get("kind",""))=="parchment" and not has_nonopaque,"Unexpected opaque asset or transparent parchment: "+id)
		var texture = ResourceLoader.load(path,"Texture2D")
		expect(texture is Texture2D,"Godot texture import unavailable: "+id)
		if texture is Texture2D:
			expect(texture.get_width()==int(asset.get("width",-1)) and texture.get_height()==int(asset.get("height",-1)),"Imported texture dimensions mismatch: "+id)
		var anchor = asset.get("anchor",[])
		expect(anchor is Array and anchor.size()==2,"Missing anchor: "+id)
		expect(asset.get("provenance") is Dictionary and asset.get("scale") is Dictionary,"Missing metadata: "+id)
	for failure in failures:
		push_error(failure)
	print("Cartography assets: ",assets.size()," checked; ",failures.size()," failures.")
	quit(0 if failures.is_empty() else 1)
