extends Node
## Finds and caches images by basename (e.g. "BowlingBall").
##
## SVG files are rasterized at runtime at the size they are displayed, so
## vector art stays crisp at every zoom level. Drop new images into
## res://assets/images and refer to them by name (without extension).

const IMAGE_DIR := "res://assets/images/"

var _paths := {}            # basename -> res path
var _svg_natural := {}      # basename -> Vector2 natural size
var _cache := {}            # "name@bucket" -> Texture2D


func _ready() -> void:
	for f in ResourceLoader.list_directory(IMAGE_DIR):
		_register(f)
	# raw .svg sources are not resources; list them too
	var dir := DirAccess.open(IMAGE_DIR)
	if dir:
		for f in dir.get_files():
			_register(f.trim_suffix(".import"))


func _register(file: String) -> void:
	var ext := file.get_extension().to_lower()
	if ext not in ["svg", "png", "jpg", "jpeg", "webp"]:
		return
	var base := file.get_basename()
	# prefer svg over raster versions with the same name
	if _paths.has(base) and String(_paths[base]).ends_with(".svg"):
		return
	_paths[base] = IMAGE_DIR + file


func has_image(image_name: String) -> bool:
	return _paths.has(image_name)


func all_names() -> Array:
	var names := _paths.keys()
	names.sort()
	return names


## Returns a texture for `image_name`, rasterized so that its largest side is
## at least `max_px` pixels (SVG only). Returns null if not found.
func get_texture(image_name: String, max_px: float = 256.0) -> Texture2D:
	if not _paths.has(image_name):
		return null
	var path: String = _paths[image_name]
	if not path.ends_with(".svg"):
		var key_r := image_name
		if not _cache.has(key_r):
			_cache[key_r] = load(path)
		return _cache[key_r]
	var bucket := 32
	while bucket < max_px and bucket < 2048:
		bucket *= 2
	var key := "%s@%d" % [image_name, bucket]
	if _cache.has(key):
		return _cache[key]
	var tex := _rasterize_svg(image_name, path, bucket)
	_cache[key] = tex
	return tex


func _rasterize_svg(image_name: String, path: String, bucket: int) -> Texture2D:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		# exported game without raw svg files: fall back to the imported texture
		return load(path) if ResourceLoader.exists(path) else null
	if not _svg_natural.has(image_name):
		var probe := Image.new()
		if probe.load_svg_from_buffer(bytes, 1.0) != OK:
			return null
		_svg_natural[image_name] = Vector2(probe.get_size())
	var natural: Vector2 = _svg_natural[image_name]
	var scale: float = clampf(bucket / maxf(1.0, maxf(natural.x, natural.y)), 0.02, 16.0)
	var img := Image.new()
	if img.load_svg_from_buffer(bytes, scale) != OK:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
