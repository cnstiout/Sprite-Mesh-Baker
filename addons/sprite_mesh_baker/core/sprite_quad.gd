## Quad generation helpers for Sprite3D baking.
## Converts a Sprite3D into 4 corner positions (in root-local space),
## UV coordinates, normal, and color.
class_name SpriteMeshBakerQuad


## Result of converting a single Sprite3D into quad data.
## All positions are in root-local space.
class QuadData:
	var corners: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var normal: Vector3 = Vector3.FORWARD
	var color: Color = Color.WHITE
	var double_sided: bool = true
	var texture: Texture2D = null


## Build a QuadData from a Sprite3D, transforming positions into root-local space.
static func build_quad(sprite: Sprite3D, root: Node3D) -> QuadData:
	var tex: Texture2D = sprite.texture
	if tex == null:
		return null

	var frame_rect: Rect2 = SpriteMeshBakerUV.get_frame_rect(sprite)
	if frame_rect.size.x <= 0.0 or frame_rect.size.y <= 0.0:
		return null

	var ps: float = sprite.pixel_size

	# Quad size in 3D units
	var w: float = frame_rect.size.x * ps
	var h: float = frame_rect.size.y * ps

	# Quad origin in 2D (before axis mapping)
	var x0: float
	var x1: float
	var y0: float
	var y1: float

	if sprite.centered:
		x0 = -w * 0.5
		x1 = w * 0.5
		y0 = -h * 0.5
		y1 = h * 0.5
	else:
		x0 = 0.0
		x1 = w
		y0 = 0.0
		y1 = h

	# Apply offset (pixels -> 3D units)
	var ox: float = sprite.offset.x * ps
	var oy: float = sprite.offset.y * ps
	x0 += ox
	x1 += ox
	y0 += oy
	y1 += oy

	# Axis directions in sprite-local space
	var u_dir: Vector3
	var v_dir: Vector3
	var normal_dir: Vector3

	match sprite.axis:
		Vector3.AXIS_Z:
			u_dir = Vector3(1, 0, 0)
			v_dir = Vector3(0, 1, 0)
			normal_dir = Vector3(0, 0, 1)
		Vector3.AXIS_X:
			u_dir = Vector3(0, 0, -1)
			v_dir = Vector3(0, 1, 0)
			normal_dir = Vector3(1, 0, 0)
		Vector3.AXIS_Y:
			u_dir = Vector3(1, 0, 0)
			v_dir = Vector3(0, 0, -1)
			normal_dir = Vector3(0, 1, 0)
		_:
			u_dir = Vector3(1, 0, 0)
			v_dir = Vector3(0, 1, 0)
			normal_dir = Vector3(0, 0, 1)

	# Build 4 corners in sprite-local space
	# p(x, y) = x * u_dir + (-y) * v_dir  (y inverted for UV consistency)
	var p00_local: Vector3 = x0 * u_dir + (-y0) * v_dir
	var p10_local: Vector3 = x1 * u_dir + (-y0) * v_dir
	var p11_local: Vector3 = x1 * u_dir + (-y1) * v_dir
	var p01_local: Vector3 = x0 * u_dir + (-y1) * v_dir

	# Transform to world, then to root-local
	var sprite_xform: Transform3D = sprite.global_transform
	var p00: Vector3 = root.to_local(sprite_xform * p00_local)
	var p10: Vector3 = root.to_local(sprite_xform * p10_local)
	var p11: Vector3 = root.to_local(sprite_xform * p11_local)
	var p01: Vector3 = root.to_local(sprite_xform * p01_local)

	# Normal in root-local space
	var n_global: Vector3 = sprite_xform.basis * normal_dir
	var n_root: Vector3 = root.global_transform.basis.inverse() * n_global
	n_root = n_root.normalized()

	# UVs
	var tex_size: Vector2 = SpriteMeshBakerUV.get_tex_size(tex)
	var uv_dict: Dictionary = SpriteMeshBakerUV.get_uvs(frame_rect, tex_size, sprite.flip_h, sprite.flip_v)
	var u0: float = uv_dict["u0"]
	var v0: float = uv_dict["v0"]
	var u1: float = uv_dict["u1"]
	var v1: float = uv_dict["v1"]

	# Build result
	var qd := QuadData.new()
	qd.corners = [p00, p10, p11, p01] as Array[Vector3]
	qd.uvs = [
		Vector2(u0, v0),
		Vector2(u1, v0),
		Vector2(u1, v1),
		Vector2(u0, v1)
	] as Array[Vector2]
	qd.normal = n_root
	qd.color = sprite.modulate
	qd.texture = tex

	# Double-sided: read via get() to avoid crash if property name varies
	qd.double_sided = sprite.get("double_sided") if sprite.get("double_sided") != null else true

	return qd
