class_name Tex
extends RefCounted
## Small greyscale textures painted in code, multiplied over the vertex
## colours. Sampled without filtering and projected in world or object space,
## so they read as chunky texels on low-poly shapes, the way late-90s console
## games looked.

static var _cache := {}
static var _materials := {}
static var _lock := Mutex.new()   ## The next mountain is built on a thread.

static func _make(key: String, size: int, paint: Callable) -> ImageTexture:
	_lock.lock()
	var tex := _make_locked(key, size, paint)
	_lock.unlock()
	return tex

static func _make_locked(key: String, size: int, paint: Callable) -> ImageTexture:
	if _cache.has(key): return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for y in size:
		for x in size:
			var v: float = paint.call(x, y, rng)
			img.set_pixel(x, y, Color(v, v, v))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Dirt, grass and rock: speckles and the odd pebble.
static func grit() -> ImageTexture:
	return _make("grit", 32, func(x, y, rng):
		var v: float = rng.randf_range(0.8, 1.0)
		if rng.randf() < 0.07: v = rng.randf_range(0.55, 0.7)
		if rng.randf() < 0.03: v = 1.12
		return v)

## Denim twill.
static func denim() -> ImageTexture:
	return _make("denim", 16, func(x, y, rng):
		return (0.72 if (x + y) % 4 < 2 else 0.95) * rng.randf_range(0.92, 1.0))

## Flannel check: two bands crossing, darker where they meet.
static func plaid() -> ImageTexture:
	return _make("plaid", 16, func(x, y, rng):
		var a := 1 if x % 8 < 3 else 0
		var b := 1 if y % 8 < 3 else 0
		var v := 1.0 - 0.3 * (a + b)
		if x % 8 == 5 or y % 8 == 5: v = 1.1
		return v)

## Racing stripes across a jersey.
static func stripes() -> ImageTexture:
	return _make("stripes", 16, func(x, y, rng):
		return 1.08 if y % 8 < 2 else (0.62 if y % 8 == 4 else 0.95))

## Plain cotton with a little weave.
static func cotton() -> ImageTexture:
	return _make("cotton", 8, func(x, y, rng):
		return rng.randf_range(0.88, 1.0))

## Wavy highlights for the stream.
static func ripples() -> ImageTexture:
	return _make("ripples", 32, func(x, y, rng):
		var w := sin((x + sin(y * 0.4) * 3.0) * 0.6)
		return 1.2 if w > 0.9 else (0.85 + rng.randf() * 0.1))

## A vertex-coloured material with one of the textures above projected on it.
static func material(tex: ImageTexture, scale: float, world: bool) -> StandardMaterial3D:
	_lock.lock()
	var m := _material_locked(tex, scale, world)
	_lock.unlock()
	return m

static func _material_locked(tex: ImageTexture, scale: float, world: bool) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [tex.get_instance_id(), scale, world]
	if _materials.has(key): return _materials[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = 1.0
	m.metallic_specular = 0.15
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = m
	return m
