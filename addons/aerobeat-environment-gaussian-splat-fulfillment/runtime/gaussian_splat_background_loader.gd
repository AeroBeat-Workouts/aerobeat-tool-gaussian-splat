extends RefCounted

const STANDARD_PLY_DECODER := preload("res://addons/gdgs/importers/decoders/standard_ply_decoder.gd")
const COMPRESSED_PLY_DECODER := preload("res://addons/gdgs/importers/decoders/compressed_ply_decoder.gd")
const SPLAT_DECODER := preload("res://addons/gdgs/importers/decoders/splat_decoder.gd")
const SOG_DECODER := preload("res://addons/gdgs/importers/decoders/sog_decoder.gd")
const GAUSSIAN_RESOURCE_BUILDER := preload("res://addons/gdgs/importers/builders/gaussian_resource_builder.gd")

func load_gaussian_resource(asset_path: String, format: String) -> Dictionary:
	var decoder_result := _decode_to_canonical(asset_path, format)
	if not decoder_result.get("ok", false):
		return decoder_result

	var build_result: Dictionary = GAUSSIAN_RESOURCE_BUILDER.build(decoder_result["canonical"])
	if not build_result.get("ok", false):
		return build_result

	var resource = build_result["resource"]
	return {
		"ok": true,
		"path": asset_path,
		"format": format,
		"resource": resource,
		"point_count": resource.point_count,
		"aabb": resource.aabb
	}

func _decode_to_canonical(asset_path: String, format: String) -> Dictionary:
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

func _error(code: int, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": code,
		"message": message
	}
