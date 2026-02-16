## UV and rect helpers for Sprite3D baking.
## Computes source rects, frame rects, and UV coordinates from Sprite3D properties.
class_name SpriteMeshBakerUV


## Retrieve the texture size reliably (works for all Texture2D subtypes in editor).
static func get_tex_size(tex: Texture2D) -> Vector2:
	if tex == null:
		return Vector2.ZERO

	var s: Vector2 = tex.get_size()
	if s.x > 0.0 and s.y > 0.0:
		return s

	# Fallback: reload from resource_path (fixes @tool proxy issue)
	if tex.resource_path != "":
		var reloaded: Texture2D = load(tex.resource_path) as Texture2D
		if reloaded != null:
			s = reloaded.get_size()
			if s.x > 0.0 and s.y > 0.0:
				return s

	# Fallback: try get_image
	var img: Image = tex.get_image()
	if img != null:
		return Vector2(img.get_width(), img.get_height())

	push_warning("[SpriteMeshBaker] Could not determine size for texture '%s'" % tex.resource_path)
	return Vector2.ZERO


## Compute the source rectangle in pixels within the texture.
## Takes into account region_enabled, region_rect, hframes, vframes, and frame.
static func get_frame_rect(sprite: Sprite3D) -> Rect2:
	var tex: Texture2D = sprite.texture
	if tex == null:
		return Rect2()

	var tex_size: Vector2 = get_tex_size(tex)
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return Rect2()

	# Base rect: region or full texture
	var base_rect: Rect2
	if sprite.region_enabled and sprite.region_rect.size.x > 0.0 and sprite.region_rect.size.y > 0.0:
		base_rect = sprite.region_rect
	else:
		base_rect = Rect2(Vector2.ZERO, tex_size)

	# Sub-divide by hframes/vframes if applicable
	var hf: int = sprite.hframes
	var vf: int = sprite.vframes
	if hf > 1 or vf > 1:
		var frame_w: float = base_rect.size.x / float(hf)
		var frame_h: float = base_rect.size.y / float(vf)
		var fi: int = sprite.frame
		var col: int = fi % hf
		var row: int = fi / hf
		base_rect = Rect2(
			base_rect.position.x + col * frame_w,
			base_rect.position.y + row * frame_h,
			frame_w,
			frame_h
		)

	return base_rect


## Compute UV coordinates (u0, v0, u1, v1) from a frame rect and texture size.
static func get_uvs(frame_rect: Rect2, tex_size: Vector2, flip_h: bool, flip_v: bool) -> Dictionary:
	var u0: float = frame_rect.position.x / tex_size.x
	var v0: float = frame_rect.position.y / tex_size.y
	var u1: float = (frame_rect.position.x + frame_rect.size.x) / tex_size.x
	var v1: float = (frame_rect.position.y + frame_rect.size.y) / tex_size.y

	if flip_h:
		var tmp: float = u0
		u0 = u1
		u1 = tmp

	if flip_v:
		var tmp: float = v0
		v0 = v1
		v1 = tmp

	return { "u0": u0, "v0": v0, "u1": u1, "v1": v1 }
