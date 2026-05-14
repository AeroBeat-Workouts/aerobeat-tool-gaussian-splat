class_name AeroGaussianSplatManager
extends Node

const VERSION: String = "0.0.1"
const COMPOSITOR_EFFECT_SCRIPT := preload("res://addons/gdgs/runtime/compositor/gaussian_compositor_effect.gd")
const GAUSSIAN_SPLAT_NODE_SCRIPT := preload("res://addons/gdgs/runtime/nodes/gaussian_splat_node.gd")
const STANDARD_PLY_DECODER := preload("res://addons/gdgs/importers/decoders/standard_ply_decoder.gd")
const COMPRESSED_PLY_DECODER := preload("res://addons/gdgs/importers/decoders/compressed_ply_decoder.gd")
const SPLAT_DECODER := preload("res://addons/gdgs/importers/decoders/splat_decoder.gd")
const SOG_DECODER := preload("res://addons/gdgs/importers/decoders/sog_decoder.gd")
const GAUSSIAN_RESOURCE_BUILDER := preload("res://addons/gdgs/importers/builders/gaussian_resource_builder.gd")

const SUPPORTED_EXTENSIONS := ["ply", "compressed.ply", "splat", "sog"]

func get_supported_extensions() -> PackedStringArray:
	return PackedStringArray(SUPPORTED_EXTENSIONS)

func configure_world_environment(world_environment: WorldEnvironment) -> void:
	if world_environment == null:
		return
	if world_environment.compositor == null:
		world_environment.compositor = Compositor.new()
	for effect in world_environment.compositor.compositor_effects:
		if effect != null and effect.get_script() == COMPOSITOR_EFFECT_SCRIPT:
			return
	var effect := CompositorEffect.new()
	effect.effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	effect.access_resolved_color = true
	effect.access_resolved_depth = true
	effect.needs_motion_vectors = false
	effect.set_script(COMPOSITOR_EFFECT_SCRIPT)
	world_environment.compositor.compositor_effects.append(effect)

func load_gaussian_resource_from_path(asset_path: String) -> Dictionary:
	var normalized_path := asset_path.strip_edges()
	if normalized_path.is_empty():
		return _error(ERR_INVALID_PARAMETER, "No splat path was provided")
	if not FileAccess.file_exists(normalized_path):
		return _error(ERR_FILE_NOT_FOUND, "Splat file does not exist: %s" % normalized_path)

	var decoder_result := _decode_to_canonical(normalized_path)
	if not decoder_result.get("ok", false):
		return decoder_result

	var build_result: Dictionary = GAUSSIAN_RESOURCE_BUILDER.build(decoder_result["canonical"])
	if not build_result.get("ok", false):
		return build_result

	var resource = build_result["resource"]
	return {
		"ok": true,
		"path": normalized_path,
		"format": _detect_format(normalized_path),
		"resource": resource,
		"point_count": resource.point_count,
		"aabb": resource.aabb
	}

func create_splat_node_from_path(asset_path: String) -> Dictionary:
	var load_result := load_gaussian_resource_from_path(asset_path)
	if not load_result.get("ok", false):
		return load_result
	var node = GAUSSIAN_SPLAT_NODE_SCRIPT.new()
	node.gaussian = load_result["resource"]
	load_result["node"] = node
	return load_result

func _decode_to_canonical(asset_path: String) -> Dictionary:
	var format := _detect_format(asset_path)
	match format:
		"compressed.ply":
			return COMPRESSED_PLY_DECODER.decode(asset_path)
		"ply":
			return STANDARD_PLY_DECODER.decode(asset_path)
		"splat":
			return SPLAT_DECODER.decode(asset_path)
		"sog":
			return SOG_DECODER.decode(asset_path)
		_:
			return _error(ERR_FILE_UNRECOGNIZED, "Unsupported splat format for path: %s" % asset_path)

func _detect_format(asset_path: String) -> String:
	var lower := asset_path.to_lower()
	if lower.ends_with(".compressed.ply"):
		return "compressed.ply"
	return lower.get_extension()

func _error(code: int, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": code,
		"message": message
	}
