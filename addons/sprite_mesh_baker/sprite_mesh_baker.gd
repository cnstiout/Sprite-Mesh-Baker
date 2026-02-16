## EditorPlugin for Sprite Mesh Baker.
## Adds a Tools menu item and manages the bake dialog.
@tool
extends EditorPlugin

const MENU_LABEL := "Bake Sprite3D Group to MeshInstance3D..."

var _dialog: AcceptDialog
var _bake_root: Node3D

# Dialog controls
var _group_by_texture_cb: CheckBox
var _disable_originals_cb: CheckBox
var _delete_originals_cb: CheckBox
var _alpha_threshold_spin: SpinBox
var _texture_filter_option: OptionButton
var _result_label: Label
var _bake_button: Button


func _enter_tree() -> void:
	add_tool_menu_item(MENU_LABEL, _on_tool_menu_pressed)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_LABEL)
	if _dialog and is_instance_valid(_dialog):
		_dialog.queue_free()
		_dialog = null


func _on_tool_menu_pressed() -> void:
	var selection: EditorSelection = get_editor_interface().get_selection()
	var selected: Array[Node] = selection.get_selected_nodes()

	if selected.size() != 1 or not (selected[0] is Node3D):
		_show_alert("Please select exactly one Node3D as the bake root.")
		return

	var root: Node3D = selected[0] as Node3D

	var sprites: Array[Sprite3D] = []
	SpriteMeshBaker.gather_sprites(root, sprites)
	if sprites.is_empty():
		_show_alert("No Sprite3D found under '%s'." % root.name)
		return

	_bake_root = root
	_ensure_dialog()
	_result_label.text = "Root: '%s' — %d Sprite3D found. Click Bake." % [root.name, sprites.size()]
	_dialog.popup_centered()


func _ensure_dialog() -> void:
	if _dialog and is_instance_valid(_dialog):
		return

	_dialog = AcceptDialog.new()
	_dialog.title = "Bake Sprite3D Group to MeshInstance3D"
	_dialog.min_size = Vector2i(440, 340)
	# Hide the default OK button — we add our own Bake button
	_dialog.get_ok_button().visible = false

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_dialog.add_child(vbox)

	# Group by texture
	_group_by_texture_cb = CheckBox.new()
	_group_by_texture_cb.text = "Group by texture (1 surface per texture)"
	_group_by_texture_cb.button_pressed = true
	vbox.add_child(_group_by_texture_cb)

	# Alpha threshold
	var hbox_alpha := HBoxContainer.new()
	hbox_alpha.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox_alpha)

	var alpha_label := Label.new()
	alpha_label.text = "Alpha threshold:"
	hbox_alpha.add_child(alpha_label)

	_alpha_threshold_spin = SpinBox.new()
	_alpha_threshold_spin.min_value = 0.0
	_alpha_threshold_spin.max_value = 1.0
	_alpha_threshold_spin.step = 0.01
	_alpha_threshold_spin.value = 0.01
	hbox_alpha.add_child(_alpha_threshold_spin)

	# Texture filter
	var hbox_filter := HBoxContainer.new()
	hbox_filter.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox_filter)

	var filter_label := Label.new()
	filter_label.text = "Texture filter:"
	hbox_filter.add_child(filter_label)

	_texture_filter_option = OptionButton.new()
	_texture_filter_option.add_item("Nearest (pixel art)", 0)
	_texture_filter_option.add_item("Linear (smooth)", 1)
	_texture_filter_option.add_item("Nearest + Mipmaps", 2)
	_texture_filter_option.add_item("Linear + Mipmaps", 3)
	_texture_filter_option.selected = 0
	hbox_filter.add_child(_texture_filter_option)

	# Separator
	vbox.add_child(HSeparator.new())

	# Disable originals
	_disable_originals_cb = CheckBox.new()
	_disable_originals_cb.text = "Disable originals after bake (visible = false)"
	_disable_originals_cb.button_pressed = false
	vbox.add_child(_disable_originals_cb)

	# Delete originals
	_delete_originals_cb = CheckBox.new()
	_delete_originals_cb.text = "Delete originals after bake"
	_delete_originals_cb.button_pressed = false
	vbox.add_child(_delete_originals_cb)
	_delete_originals_cb.toggled.connect(_on_delete_toggled)

	# Separator
	vbox.add_child(HSeparator.new())

	# Result label
	_result_label = Label.new()
	_result_label.text = ""
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.custom_minimum_size = Vector2(400, 60)
	_result_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_result_label)

	# Buttons
	var hbox_buttons := HBoxContainer.new()
	hbox_buttons.add_theme_constant_override("separation", 8)
	hbox_buttons.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(hbox_buttons)

	_bake_button = Button.new()
	_bake_button.text = "Bake"
	_bake_button.custom_minimum_size = Vector2(100, 0)
	_bake_button.pressed.connect(_on_bake_pressed)
	hbox_buttons.add_child(_bake_button)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(80, 0)
	close_button.pressed.connect(func(): _dialog.hide())
	hbox_buttons.add_child(close_button)

	get_editor_interface().get_base_control().add_child(_dialog)


func _on_delete_toggled(pressed: bool) -> void:
	if pressed:
		_disable_originals_cb.button_pressed = false
		_disable_originals_cb.disabled = true
	else:
		_disable_originals_cb.disabled = false


func _on_bake_pressed() -> void:
	if _bake_root == null or not is_instance_valid(_bake_root):
		_result_label.text = "ERROR: Root node is no longer valid. Close and retry."
		return

	var opts := SpriteMeshBaker.BakeOptions.new()
	opts.group_by_texture = _group_by_texture_cb.button_pressed
	opts.alpha_threshold = _alpha_threshold_spin.value
	opts.disable_originals = _disable_originals_cb.button_pressed
	opts.delete_originals = _delete_originals_cb.button_pressed
	opts.texture_filter = _texture_filter_option.get_selected_id()

	var result: SpriteMeshBaker.BakeResult = SpriteMeshBaker.bake(_bake_root, opts)

	if result.error != "":
		_show_result(result)
		return

	# UndoRedo: use the scene owner as context for correct history
	var scene_root: Node = _bake_root.owner if _bake_root.owner else _bake_root
	var ur: EditorUndoRedoManager = get_undo_redo()
	ur.create_action("Bake Sprites to Mesh", UndoRedo.MERGE_DISABLE, scene_root)

	ur.add_do_reference(result.mesh_instance)
	ur.add_do_method(self, "_do_bake", _bake_root, result.mesh_instance, scene_root)
	ur.add_undo_method(self, "_undo_bake", _bake_root, result.mesh_instance)

	# Handle originals
	if opts.disable_originals:
		for s in result.valid_sprites:
			ur.add_do_method(self, "_set_visible", s, false)
			ur.add_undo_method(self, "_set_visible", s, true)
	elif opts.delete_originals:
		for s in result.valid_sprites:
			var parent: Node = s.get_parent()
			var idx: int = s.get_index()
			ur.add_do_method(self, "_remove_node", parent, s)
			ur.add_undo_method(self, "_restore_node", parent, s, idx, scene_root)
			ur.add_undo_reference(s)

	ur.commit_action()
	_show_result(result)


## UndoRedo helper: add the baked mesh to root.
func _do_bake(root: Node3D, mesh_inst: MeshInstance3D, owner: Node) -> void:
	root.add_child(mesh_inst)
	mesh_inst.owner = owner


## UndoRedo helper: remove the baked mesh from root.
func _undo_bake(root: Node3D, mesh_inst: MeshInstance3D) -> void:
	if mesh_inst.get_parent() == root:
		root.remove_child(mesh_inst)


## UndoRedo helper: set node visibility.
func _set_visible(node: Node3D, vis: bool) -> void:
	node.visible = vis


## UndoRedo helper: remove a node from its parent.
func _remove_node(parent: Node, child: Node) -> void:
	if child.get_parent() == parent:
		parent.remove_child(child)


## UndoRedo helper: restore a node to its parent.
func _restore_node(parent: Node, child: Node, idx: int, owner: Node) -> void:
	parent.add_child(child)
	parent.move_child(child, idx)
	child.owner = owner


func _show_result(result: SpriteMeshBaker.BakeResult) -> void:
	if result.error != "":
		_result_label.text = "ERROR: %s" % result.error
		return

	var lines: PackedStringArray = PackedStringArray()
	lines.append("OK! Baked %d sprite(s) into %d surface(s)." % [result.sprite_count, result.surface_count])

	if not result.skipped_billboard.is_empty():
		lines.append("Skipped (billboard): %d" % result.skipped_billboard.size())
		for p in result.skipped_billboard:
			lines.append("  - %s" % p)

	if not result.skipped_no_texture.is_empty():
		lines.append("Skipped (no texture): %d" % result.skipped_no_texture.size())

	_result_label.text = "\n".join(lines)


func _show_alert(message: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.dialog_text = message
	dlg.title = "Sprite Mesh Baker"
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	get_editor_interface().get_base_control().add_child(dlg)
	dlg.popup_centered()
