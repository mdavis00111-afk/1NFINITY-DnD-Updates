extends RefCounted
## Shared, presentation-only portrait fallback, cropped from the approved sheet art.
const SAMPLE = preload("res://art/sheet_reference.jpg")
static var default_texture: Texture2D

static func texture_for(path: String = "") -> Texture2D:
	if not path.is_empty() and FileAccess.file_exists(path):
		var image = Image.load_from_file(path)
		if not image.is_empty():
			return ImageTexture.create_from_image(image)
	if default_texture == null:
		var source = SAMPLE.get_image()
		# Coordinates are normalized against the inspected 1088 x 1406 sample artwork.
		var extent = source.get_size()
		var region = Rect2i(roundi(extent.x * 30.0/1088.0),roundi(extent.y * 102.0/1406.0),roundi(extent.x * 232.0/1088.0),roundi(extent.y * 374.0/1406.0))
		default_texture = ImageTexture.create_from_image(source.get_region(region))
	return default_texture
