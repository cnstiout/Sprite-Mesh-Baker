## Main bake logic for Sprite Mesh Baker.
## Gathers Sprite3D nodes, converts them to quads, and builds an ArrayMesh.
class_name SpriteMeshBaker


## Options for the bake operation.
class BakeOptions:
	var group_by_texture: bool = true
	var alpha_threshold: float = 0.01
	var disable_originals: bool = false
	var delete_originals: bool = false
	## 0 = Nearest, 1 = Linear (maps to BaseMaterial3D.TextureFilter)
	var texture_filter: int = 0


## Result returned after a bake operation.
class BakeResult:
	var mesh_instance: MeshInstance3D
	var sprite_count: int = 0
	var surface_count: int = 0
	var skipped_billboard: Array[String] = []
	var skipped_no_texture: Array[String] = []
	var valid_sprites: Array[Sprite3D] = []
	var error: String = ""


## Gather all Sprite3D descendants recursively.
static func gather_sprites(node: Node, out: Array[Sprite3D]) -> void:
	for child in node.get_children():
		if child is Sprite3D:
			out.append(child as Sprite3D)
		gather_sprites(child, out)


## Main bake entry point.
## root: the Node3D parent selected by the user.
## options: BakeOptions instance.
## Returns a BakeResult.
static func bake(root: Node3D, options: BakeOptions) -> BakeResult:
	var result := BakeResult.new()

	# 1) Gather all Sprite3D descendants
	var sprites: Array[Sprite3D] = []
	gather_sprites(root, sprites)

	if sprites.is_empty():
		result.error = "No Sprite3D found under '%s'." % root.name
		return result

	# 2) Filter: skip billboard, skip no-texture
	var valid_sprites: Array[Sprite3D] = []
	for s in sprites:
		if s.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
			var path_str: String = str(s.get_path())
			result.skipped_billboard.append(path_str)
			printerr("[SpriteMeshBaker] SKIPPED (billboard): %s" % path_str)
			continue
		if s.texture == null:
			var path_str: String = str(s.get_path())
			result.skipped_no_texture.append(path_str)
			printerr("[SpriteMeshBaker] SKIPPED (no texture): %s" % path_str)
			continue
		valid_sprites.append(s)

	if valid_sprites.is_empty():
		result.error = "All Sprite3D nodes were skipped (billboard or no texture)."
		return result

	# 3) Build quad data for each sprite
	var quads: Array = []  # Array of SpriteMeshBakerQuad.QuadData
	for s in valid_sprites:
		var qd = SpriteMeshBakerQuad.build_quad(s, root)
		if qd != null:
			quads.append(qd)

	if quads.is_empty():
		result.error = "No valid quads generated (all sprites may have zero-size regions)."
		return result

	# 4) Group quads by texture (or single group)
	var groups: Dictionary = {}  # Texture2D -> Array[QuadData]
	var multiple_textures: bool = false
	var first_tex: Texture2D = null

	for qd in quads:
		var tex: Texture2D = qd.texture
		if first_tex == null:
			first_tex = tex
		elif tex != first_tex:
			multiple_textures = true

		if not groups.has(tex):
			groups[tex] = []
		groups[tex].append(qd)

	# If group_by_texture is OFF but multiple textures exist, force ON
	if not options.group_by_texture and multiple_textures:
		push_warning("[SpriteMeshBaker] Multiple textures detected; forcing 'Group by texture' ON.")
		options.group_by_texture = true

	# 5) Build ArrayMesh
	var array_mesh := ArrayMesh.new()

	if options.group_by_texture:
		for tex: Texture2D in groups:
			var group_quads: Array = groups[tex]
			_build_surface(array_mesh, group_quads, tex, options.texture_filter)
	else:
		# Single surface with the one texture
		_build_surface(array_mesh, quads, first_tex, options.texture_filter)

	# 6) Create MeshInstance3D (not yet added to scene — caller handles that)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "%s_baked" % root.name
	mesh_inst.mesh = array_mesh
	mesh_inst.transform = Transform3D.IDENTITY

	# 7) Fill result
	result.mesh_instance = mesh_inst
	result.sprite_count = quads.size()
	result.surface_count = array_mesh.get_surface_count()
	result.valid_sprites = valid_sprites

	print("[SpriteMeshBaker] Baked %d sprites into %d surface(s). Skipped %d billboard, %d no-texture." % [
		result.sprite_count,
		result.surface_count,
		result.skipped_billboard.size(),
		result.skipped_no_texture.size()
	])

	return result


## Build one surface (set of quads) into the ArrayMesh for a given texture.
## tex_filter: 0 = Nearest, 1 = Linear, 2 = Nearest Mipmap, 3 = Linear Mipmap
static func _build_surface(array_mesh: ArrayMesh, quad_list: Array, tex: Texture2D, tex_filter: int = 0) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for qd in quad_list:
		var c: Array[Vector3] = qd.corners
		var uv: Array[Vector2] = qd.uvs
		var n: Vector3 = qd.normal
		var col: Color = qd.color

		# Triangle 1: p00, p10, p11
		_add_vertex(st, c[0], uv[0], n, col)
		_add_vertex(st, c[1], uv[1], n, col)
		_add_vertex(st, c[2], uv[2], n, col)

		# Triangle 2: p11, p01, p00
		_add_vertex(st, c[2], uv[2], n, col)
		_add_vertex(st, c[3], uv[3], n, col)
		_add_vertex(st, c[0], uv[0], n, col)

	# Create material
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Texture filter
	match tex_filter:
		0: mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		1: mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		2: mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		3: mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_: mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	st.set_material(mat)
	st.commit(array_mesh)


## Add a single vertex with normal, UV, and color to the SurfaceTool.
static func _add_vertex(st: SurfaceTool, pos: Vector3, uv: Vector2, normal: Vector3, color: Color) -> void:
	st.set_normal(normal)
	st.set_uv(uv)
	st.set_color(color)
	st.add_vertex(pos)
