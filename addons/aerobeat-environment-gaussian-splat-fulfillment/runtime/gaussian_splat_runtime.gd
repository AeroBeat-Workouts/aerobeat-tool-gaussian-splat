extends Node

signal background_load_started(result)
signal background_load_progressed(result)
signal background_load_finished(result)

const VERSION: String = "0.0.1"
const COMPOSITOR_EFFECT_SCRIPT := preload("res://addons/gdgs/runtime/compositor/gaussian_compositor_effect.gd")
const GAUSSIAN_SPLAT_NODE_SCRIPT := preload("res://addons/gdgs/runtime/nodes/gaussian_splat_node.gd")
const GAUSSIAN_RESOURCE_SCRIPT := preload("res://addons/gdgs/runtime/resources/gaussian_resource.gd")
const BINARY_PLY_READER := preload("res://addons/gdgs/importers/parsers/binary_ply_reader.gd")
const GAUSSIAN_RESOURCE_BUILDER := preload("res://addons/gdgs/importers/builders/gaussian_resource_builder.gd")
const BACKGROUND_LOADER_SCRIPT := preload("res://addons/aerobeat-environment-gaussian-splat-fulfillment/runtime/gaussian_splat_background_loader.gd")
const BACKGROUND_READ_WORKER_SCRIPT := preload("res://addons/aerobeat-environment-gaussian-splat-fulfillment/runtime/gaussian_splat_background_read_worker.gd")

const SUPPORTED_EXTENSIONS := ["ply", "compressed.ply", "splat", "sog"]
const REQUEST_KIND_RESOURCE := "resource"
const REQUEST_KIND_NODE := "node"
const ASYNC_BATCH_SIZE := 4096
const STRUCT_SIZE := 60
const SH_FLOAT_COUNT := 48
const SH_C0 := 0.28209479177387814
const SQRT2 := 1.4142135623730951
const PHASE_IDLE := "idle"
const PHASE_READING := "reading"
const PHASE_DECODING := "decoding"
const PHASE_BUILDING := "building"
const PHASE_READY := "ready"
const STATUS_IDLE := "Idle"
const STATUS_READING := "Reading splat file"
const STATUS_READY := "Ready"
const RENDER_SUPPORT_SUPPORTED := "supported"
const RENDER_SUPPORT_EXPERIMENTAL := "experimental"
const RENDER_SUPPORT_UNSUPPORTED := "unsupported"

var _background_load_thread: Thread
var _background_read_worker: RefCounted
var _background_request: Dictionary = {}
var _background_status: Dictionary = {
	"pending": false,
	"progress": 0.0,
	"phase": PHASE_IDLE,
	"status": STATUS_IDLE
}
var _background_total_units: int = 0
var _background_completed_units: int = 0

func get_supported_extensions() -> PackedStringArray:
	return PackedStringArray(SUPPORTED_EXTENSIONS)

func get_renderer_support_status() -> Dictionary:
	var renderer_name := "unknown"
	if RenderingServer.has_method("get_current_rendering_method"):
		renderer_name = String(RenderingServer.get_current_rendering_method())
	var rendering_device = RenderingServer.get_rendering_device()
	var has_rendering_device := rendering_device != null
	if not has_rendering_device:
		return {
			"ok": false,
			"renderer_name": renderer_name,
			"support_level": RENDER_SUPPORT_UNSUPPORTED,
			"has_rendering_device": false,
			"can_attempt_render": false,
			"can_configure_compositor": false,
			"message": "Gaussian splat rendering is unavailable in the current renderer path because GDGS requires a RenderingDevice-backed compositor. Switch to a RenderingDevice renderer before expecting visible splat output."
		}

	var message := "Gaussian splat loading is available, but visible rendering is still treated as experimental on the current renderer path. On the current validation slice, Forward+ / Vulkan has reproduced compositor-side crashes after successful load."
	if renderer_name == "mobile":
		message = "Gaussian splat loading is available on the current RenderingDevice renderer, but visible rendering should still be treated as experimental until this path is validated end-to-end."
	return {
		"ok": true,
		"renderer_name": renderer_name,
		"support_level": RENDER_SUPPORT_EXPERIMENTAL,
		"has_rendering_device": true,
		"can_attempt_render": true,
		"can_configure_compositor": true,
		"message": message
	}

func configure_world_environment(world_environment: WorldEnvironment) -> void:
	if world_environment == null:
		return
	var support := get_renderer_support_status()
	if not support.get("can_configure_compositor", false):
		return
	if world_environment.compositor == null:
		world_environment.compositor = Compositor.new()
	var compositor := world_environment.compositor
	var compositor_effects := compositor.compositor_effects
	for existing_effect in compositor_effects:
		if existing_effect != null and existing_effect.get_script() == COMPOSITOR_EFFECT_SCRIPT:
			return
	var effect := CompositorEffect.new()
	effect.effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	effect.access_resolved_color = true
	effect.access_resolved_depth = true
	effect.needs_motion_vectors = false
	effect.set_script(COMPOSITOR_EFFECT_SCRIPT)
	compositor_effects.append(effect)
	compositor.compositor_effects = compositor_effects

func load_gaussian_resource_from_path(asset_path: String) -> Dictionary:
	var prepared_result := _prepare_load(asset_path)
	if not prepared_result.get("ok", false):
		return prepared_result
	return _load_gaussian_resource_prepared(prepared_result)

func create_splat_node_from_path(asset_path: String) -> Dictionary:
	var load_result := load_gaussian_resource_from_path(asset_path)
	if not load_result.get("ok", false):
		return load_result
	return _with_splat_node(load_result)

func begin_load_gaussian_resource_from_path(asset_path: String) -> Dictionary:
	return _begin_background_load(asset_path, REQUEST_KIND_RESOURCE)

func begin_create_splat_node_from_path(asset_path: String) -> Dictionary:
	return _begin_background_load(asset_path, REQUEST_KIND_NODE)

func is_background_load_in_progress() -> bool:
	return not _background_request.is_empty()

func get_background_load_status() -> Dictionary:
	return _background_status.duplicate(true)

func _exit_tree() -> void:
	if _background_load_thread != null:
		var thread := _background_load_thread
		_background_load_thread = null
		thread.wait_to_finish()
	_background_read_worker = null
	_background_request = {}
	_reset_background_status()

func _begin_background_load(asset_path: String, request_kind: String) -> Dictionary:
	if is_background_load_in_progress():
		return _error(ERR_BUSY, "A background splat load is already in progress")

	var prepared_result := _prepare_load(asset_path)
	if not prepared_result.get("ok", false):
		return prepared_result
	if prepared_result["format"] != "ply" and prepared_result["format"] != "compressed.ply":
		return _error(ERR_UNAVAILABLE, "Background loading currently supports .ply and .compressed.ply")

	var request := {
		"path": prepared_result["path"],
		"format": prepared_result["format"],
		"request_kind": request_kind
	}
	var thread := Thread.new()
	_background_read_worker = BACKGROUND_READ_WORKER_SCRIPT.new()
	var error := thread.start(Callable(_background_read_worker, "read_ply").bind(request))
	if error != OK:
		_background_read_worker = null
		return _error(error, "Failed to start background splat load for %s" % request["path"])

	_background_load_thread = thread
	_background_request = request
	_background_total_units = 0
	_background_completed_units = 0
	_set_background_status(PHASE_READING, STATUS_READING, {
		"ok": true,
		"path": request["path"],
		"format": request["format"],
		"request_kind": request_kind,
		"pending": true,
		"progress": 0.0
	}, false)
	call_deferred("_watch_background_load")

	var started_result := _background_status.duplicate(true)
	started_result["pending"] = true
	background_load_started.emit(started_result)
	return started_result

func _watch_background_load() -> void:
	while _background_load_thread != null and _background_load_thread.is_alive():
		await get_tree().process_frame
	if _background_load_thread == null:
		return
	var thread := _background_load_thread
	_background_load_thread = null
	var read_result = thread.wait_to_finish()
	_background_read_worker = null
	if read_result is not Dictionary:
		_finalize_background_load(_error(ERR_BUG, "Background splat load returned an unexpected result"))
		return
	var result = await _continue_background_load(read_result)
	_finalize_background_load(result)

func _continue_background_load(read_result: Dictionary) -> Dictionary:
	if not read_result.get("ok", false):
		return read_result
	match String(read_result.get("format", "")):
		"ply":
			return await _decode_standard_ply_async(read_result)
		"compressed.ply":
			return await _decode_compressed_ply_async(read_result)
		_:
			return _error(ERR_UNAVAILABLE, "Background loading currently supports .ply and .compressed.ply")

func _finalize_background_load(result: Dictionary) -> void:
	var request := _background_request
	_background_request = {}

	if result.get("ok", false) and request.get("request_kind", "") == REQUEST_KIND_NODE:
		result = _with_splat_node(result)

	var final_result := result.duplicate(true)
	final_result["pending"] = false
	final_result["request_kind"] = request.get("request_kind", final_result.get("request_kind", REQUEST_KIND_RESOURCE))
	if final_result.get("ok", false):
		_background_total_units = max(_background_total_units, 1)
		_background_completed_units = _background_total_units
		final_result["phase"] = PHASE_READY
		final_result["status"] = STATUS_READY
		final_result["progress"] = 1.0
	else:
		final_result["phase"] = _background_status.get("phase", PHASE_READING)
		final_result["status"] = final_result.get("message", _background_status.get("status", "Background load failed"))
		final_result["progress"] = clampf(float(_background_status.get("progress", 0.0)), 0.0, 1.0)
	_background_status = final_result.duplicate(true)
	background_load_finished.emit(final_result)

func _prepare_load(asset_path: String) -> Dictionary:
	var normalized_path := asset_path.strip_edges()
	if normalized_path.is_empty():
		return _error(ERR_INVALID_PARAMETER, "No splat path was provided")
	if not FileAccess.file_exists(normalized_path):
		return _error(ERR_FILE_NOT_FOUND, "Splat file does not exist: %s" % normalized_path)
	return {
		"ok": true,
		"path": normalized_path,
		"format": _detect_format(normalized_path)
	}

func _load_gaussian_resource_prepared(prepared_result: Dictionary) -> Dictionary:
	var loader = BACKGROUND_LOADER_SCRIPT.new()
	return loader.load_gaussian_resource(prepared_result["path"], prepared_result["format"])

func _with_splat_node(load_result: Dictionary) -> Dictionary:
	var result := load_result.duplicate()
	var node = GAUSSIAN_SPLAT_NODE_SCRIPT.new()
	node.gaussian = result["resource"]
	result["node"] = node
	return result

func _decode_standard_ply_async(read_result: Dictionary) -> Dictionary:
	var ply: Dictionary = read_result.get("ply", {})
	var vertex := _get_element(ply, "vertex")
	if vertex.is_empty():
		return _error(ERR_INVALID_DATA, "PLY file does not contain a vertex element")

	var property_map: Dictionary = vertex.get("property_map", {})
	var required := [
		"x", "y", "z",
		"f_dc_0", "f_dc_1", "f_dc_2",
		"opacity",
		"scale_0", "scale_1",
		"rot_0", "rot_1", "rot_2", "rot_3"
	]
	for name in required:
		if not property_map.has(name):
			return _error(ERR_INVALID_DATA, "PLY file is missing required property '%s'" % name)

	var count := int(vertex.get("count", 0))
	_begin_background_progress(1 + count + count + count)
	_set_background_status(PHASE_DECODING, "Decoding vertices (0/%d)" % count)

	var stride := int(vertex.get("stride", 0))
	var data: PackedByteArray = vertex.get("data", PackedByteArray())
	var canonical := GAUSSIAN_RESOURCE_BUILDER.create_canonical(count)
	var positions: PackedVector3Array = canonical["positions"]
	var scales_linear: PackedVector3Array = canonical["scales_linear"]
	var rotations: Array = canonical["rotations"]
	var opacities: PackedFloat32Array = canonical["opacities"]
	var sh_coeffs: PackedFloat32Array = canonical["sh_coeffs"]
	var reported_vertices := 0

	for i in range(count):
		var base := i * stride
		positions[i] = Vector3(
			float(_read_property(data, base, property_map, "x", 0.0)),
			float(_read_property(data, base, property_map, "y", 0.0)),
			float(_read_property(data, base, property_map, "z", 0.0))
		)

		var scale_2 := float(_read_property(data, base, property_map, "scale_2", log(1e-6)))
		scales_linear[i] = Vector3(
			exp(float(_read_property(data, base, property_map, "scale_0", 0.0))),
			exp(float(_read_property(data, base, property_map, "scale_1", 0.0))),
			exp(scale_2)
		)

		rotations[i] = Quaternion(
			float(_read_property(data, base, property_map, "rot_1", 0.0)),
			float(_read_property(data, base, property_map, "rot_2", 0.0)),
			float(_read_property(data, base, property_map, "rot_3", 0.0)),
			float(_read_property(data, base, property_map, "rot_0", 1.0))
		).normalized()

		opacities[i] = _sigmoid(float(_read_property(data, base, property_map, "opacity", 0.0)))

		var sh_offset := i * SH_FLOAT_COUNT
		sh_coeffs[sh_offset + 0] = float(_read_property(data, base, property_map, "f_dc_0", 0.0))
		sh_coeffs[sh_offset + 1] = float(_read_property(data, base, property_map, "f_dc_1", 0.0))
		sh_coeffs[sh_offset + 2] = float(_read_property(data, base, property_map, "f_dc_2", 0.0))

		for coeff_idx in range(15):
			var coeff_offset := sh_offset + 3 + coeff_idx * 3
			sh_coeffs[coeff_offset + 0] = float(_read_property(data, base, property_map, "f_rest_%d" % coeff_idx, 0.0))
			sh_coeffs[coeff_offset + 1] = float(_read_property(data, base, property_map, "f_rest_%d" % (coeff_idx + 15), 0.0))
			sh_coeffs[coeff_offset + 2] = float(_read_property(data, base, property_map, "f_rest_%d" % (coeff_idx + 30), 0.0))

		if _should_yield(i, count):
			var processed_vertices := i + 1
			_advance_background_progress(processed_vertices - reported_vertices, PHASE_DECODING, "Decoding vertices (%d/%d)" % [processed_vertices, count])
			reported_vertices = processed_vertices
			await get_tree().process_frame

	return await _build_resource_async(read_result["path"], read_result["format"], canonical)

func _decode_compressed_ply_async(read_result: Dictionary) -> Dictionary:
	var ply: Dictionary = read_result.get("ply", {})
	var chunk_element := _get_element(ply, "chunk")
	var vertex_element := _get_element(ply, "vertex")
	if chunk_element.is_empty() or vertex_element.is_empty():
		return _error(ERR_INVALID_DATA, "Compressed PLY must contain 'chunk' and 'vertex' elements")

	var vertex_map: Dictionary = vertex_element.get("property_map", {})
	for property_name in ["packed_position", "packed_rotation", "packed_scale", "packed_color"]:
		if not vertex_map.has(property_name):
			return _error(ERR_INVALID_DATA, "Compressed PLY is missing '%s'" % property_name)

	var chunk_map: Dictionary = chunk_element.get("property_map", {})
	var chunk_required := [
		"min_x", "min_y", "min_z",
		"max_x", "max_y", "max_z",
		"min_scale_x", "min_scale_y", "min_scale_z",
		"max_scale_x", "max_scale_y", "max_scale_z",
		"min_r", "min_g", "min_b",
		"max_r", "max_g", "max_b"
	]
	for property_name in chunk_required:
		if not chunk_map.has(property_name):
			return _error(ERR_INVALID_DATA, "Compressed PLY chunk metadata is missing '%s'" % property_name)

	var count := int(vertex_element.get("count", 0))
	var chunk_count := int(chunk_element.get("count", 0))
	_begin_background_progress(1 + chunk_count + count + count + count)
	_set_background_status(PHASE_DECODING, "Decoding compressed chunks (0/%d)" % chunk_count)

	var expected_chunks := int(ceili(count / 256.0))
	if chunk_count < expected_chunks:
		return _error(ERR_INVALID_DATA, "Compressed PLY does not contain enough chunk records")

	var chunk_stride := int(chunk_element.get("stride", 0))
	var chunk_data: PackedByteArray = chunk_element.get("data", PackedByteArray())
	var chunks: Array = []
	chunks.resize(chunk_count)
	var reported_chunks := 0
	for i in range(chunks.size()):
		var base := i * chunk_stride
		chunks[i] = {
			"min_x": float(_read_required_property(chunk_data, base, chunk_map, "min_x")),
			"min_y": float(_read_required_property(chunk_data, base, chunk_map, "min_y")),
			"min_z": float(_read_required_property(chunk_data, base, chunk_map, "min_z")),
			"max_x": float(_read_required_property(chunk_data, base, chunk_map, "max_x")),
			"max_y": float(_read_required_property(chunk_data, base, chunk_map, "max_y")),
			"max_z": float(_read_required_property(chunk_data, base, chunk_map, "max_z")),
			"min_scale_x": float(_read_required_property(chunk_data, base, chunk_map, "min_scale_x")),
			"min_scale_y": float(_read_required_property(chunk_data, base, chunk_map, "min_scale_y")),
			"min_scale_z": float(_read_required_property(chunk_data, base, chunk_map, "min_scale_z")),
			"max_scale_x": float(_read_required_property(chunk_data, base, chunk_map, "max_scale_x")),
			"max_scale_y": float(_read_required_property(chunk_data, base, chunk_map, "max_scale_y")),
			"max_scale_z": float(_read_required_property(chunk_data, base, chunk_map, "max_scale_z")),
			"min_r": float(_read_required_property(chunk_data, base, chunk_map, "min_r")),
			"min_g": float(_read_required_property(chunk_data, base, chunk_map, "min_g")),
			"min_b": float(_read_required_property(chunk_data, base, chunk_map, "min_b")),
			"max_r": float(_read_required_property(chunk_data, base, chunk_map, "max_r")),
			"max_g": float(_read_required_property(chunk_data, base, chunk_map, "max_g")),
			"max_b": float(_read_required_property(chunk_data, base, chunk_map, "max_b"))
		}
		if _should_yield(i, chunks.size()):
			var processed_chunks := i + 1
			_advance_background_progress(processed_chunks - reported_chunks, PHASE_DECODING, "Decoding compressed chunks (%d/%d)" % [processed_chunks, chunk_count])
			reported_chunks = processed_chunks
			await get_tree().process_frame

	var sh_element := _get_element(ply, "sh")
	var sh_stride := 0
	var sh_coeffs_per_channel := 0
	var sh_data := PackedByteArray()
	if not sh_element.is_empty():
		var sh_map: Dictionary = sh_element.get("property_map", {})
		sh_coeffs_per_channel = int(sh_map.size() / 3)
		sh_stride = int(sh_element.get("stride", 0))
		sh_data = sh_element.get("data", PackedByteArray())
		if int(sh_element.get("count", 0)) != count:
			return _error(ERR_INVALID_DATA, "Compressed PLY SH element count does not match vertex count")
		if sh_coeffs_per_channel < 0 or sh_coeffs_per_channel > 15:
			return _error(ERR_INVALID_DATA, "Compressed PLY SH payload has an unsupported size")

	var canonical := GAUSSIAN_RESOURCE_BUILDER.create_canonical(count)
	var positions: PackedVector3Array = canonical["positions"]
	var scales_linear: PackedVector3Array = canonical["scales_linear"]
	var rotations: Array = canonical["rotations"]
	var opacities: PackedFloat32Array = canonical["opacities"]
	var sh_coeffs: PackedFloat32Array = canonical["sh_coeffs"]

	var vertex_stride := int(vertex_element.get("stride", 0))
	var vertex_data: PackedByteArray = vertex_element.get("data", PackedByteArray())
	var reported_vertices := 0
	_set_background_status(PHASE_DECODING, "Decoding vertices (0/%d)" % count)

	for i in range(count):
		var base := i * vertex_stride
		var chunk: Dictionary = chunks[int(i / 256)]

		var packed_position := int(_read_required_property(vertex_data, base, vertex_map, "packed_position"))
		var packed_rotation := int(_read_required_property(vertex_data, base, vertex_map, "packed_rotation"))
		var packed_scale := int(_read_required_property(vertex_data, base, vertex_map, "packed_scale"))
		var packed_color := int(_read_required_property(vertex_data, base, vertex_map, "packed_color"))

		var position_norm := _unpack_111011(packed_position)
		positions[i] = Vector3(
			_lerp_range(chunk["min_x"], chunk["max_x"], position_norm.x),
			_lerp_range(chunk["min_y"], chunk["max_y"], position_norm.y),
			_lerp_range(chunk["min_z"], chunk["max_z"], position_norm.z)
		)

		var log_scale_norm := _unpack_111011(packed_scale)
		scales_linear[i] = Vector3(
			exp(_lerp_range(chunk["min_scale_x"], chunk["max_scale_x"], log_scale_norm.x)),
			exp(_lerp_range(chunk["min_scale_y"], chunk["max_scale_y"], log_scale_norm.y)),
			exp(_lerp_range(chunk["min_scale_z"], chunk["max_scale_z"], log_scale_norm.z))
		)

		rotations[i] = _unpack_packed_rotation(packed_rotation)

		var packed_rgba := _unpack_8888(packed_color)
		var dc_r := _lerp_range(chunk["min_r"], chunk["max_r"], packed_rgba.x)
		var dc_g := _lerp_range(chunk["min_g"], chunk["max_g"], packed_rgba.y)
		var dc_b := _lerp_range(chunk["min_b"], chunk["max_b"], packed_rgba.z)

		var sh_offset := i * SH_FLOAT_COUNT
		sh_coeffs[sh_offset + 0] = (dc_r - 0.5) / SH_C0
		sh_coeffs[sh_offset + 1] = (dc_g - 0.5) / SH_C0
		sh_coeffs[sh_offset + 2] = (dc_b - 0.5) / SH_C0
		opacities[i] = packed_rgba.w

		if not sh_element.is_empty():
			var sh_base := i * sh_stride
			for coeff_idx in range(sh_coeffs_per_channel):
				var dst := sh_offset + 3 + coeff_idx * 3
				sh_coeffs[dst + 0] = _decode_quantized_sh(sh_data[sh_base + coeff_idx])
				sh_coeffs[dst + 1] = _decode_quantized_sh(sh_data[sh_base + coeff_idx + sh_coeffs_per_channel])
				sh_coeffs[dst + 2] = _decode_quantized_sh(sh_data[sh_base + coeff_idx + sh_coeffs_per_channel * 2])

		if _should_yield(i, count):
			var processed_vertices := i + 1
			_advance_background_progress(processed_vertices - reported_vertices, PHASE_DECODING, "Decoding vertices (%d/%d)" % [processed_vertices, count])
			reported_vertices = processed_vertices
			await get_tree().process_frame

	return await _build_resource_async(read_result["path"], read_result["format"], canonical)

func _build_resource_async(asset_path: String, format: String, canonical: Dictionary) -> Dictionary:
	var count := int(canonical.get("count", 0))
	var positions: PackedVector3Array = canonical.get("positions", PackedVector3Array())
	var scales_linear: PackedVector3Array = canonical.get("scales_linear", PackedVector3Array())
	var rotations: Array = canonical.get("rotations", [])
	var opacities: PackedFloat32Array = canonical.get("opacities", PackedFloat32Array())
	var sh_coeffs: PackedFloat32Array = canonical.get("sh_coeffs", PackedFloat32Array())

	if count < 0:
		return _error(ERR_INVALID_DATA, "Canonical gaussian count is invalid")
	if positions.size() != count or scales_linear.size() != count or rotations.size() != count or opacities.size() != count:
		return _error(ERR_INVALID_DATA, "Canonical gaussian arrays are inconsistent")
	if sh_coeffs.size() != count * SH_FLOAT_COUNT:
		return _error(ERR_INVALID_DATA, "Canonical SH coefficient buffer has an unexpected size")

	var center := Vector3.ZERO
	var reported_center := 0
	_set_background_status(PHASE_BUILDING, "Computing center (0/%d)" % count)
	if count > 0:
		for i in range(count):
			center += positions[i]
			if _should_yield(i, count):
				var processed_center := i + 1
				_advance_background_progress(processed_center - reported_center, PHASE_BUILDING, "Computing center (%d/%d)" % [processed_center, count])
				reported_center = processed_center
				await get_tree().process_frame
		center /= float(count)

	var points := PackedFloat32Array()
	points.resize(count * STRUCT_SIZE)
	var xyz := PackedVector3Array()
	xyz.resize(count)
	var aabb_min_v := Vector3(INF, INF, INF)
	var aabb_max_v := Vector3(-INF, -INF, -INF)
	var reported_points := 0
	_set_background_status(PHASE_BUILDING, "Packing resource data (0/%d)" % count)

	for i in range(count):
		var pos: Vector3 = positions[i] - center
		var scale_linear: Vector3 = scales_linear[i]
		var rotation_value = rotations[i]
		var rotation := Quaternion(0.0, 0.0, 0.0, 1.0)
		if rotation_value is Quaternion:
			rotation = rotation_value.normalized()

		scale_linear = Vector3(
			maxf(scale_linear.x, 1e-6),
			maxf(scale_linear.y, 1e-6),
			maxf(scale_linear.z, 1e-6)
		)

		xyz[i] = pos
		aabb_min_v = aabb_min_v.min(pos)
		aabb_max_v = aabb_max_v.max(pos)

		var base := i * STRUCT_SIZE
		points[base + 0] = pos.x
		points[base + 1] = pos.y
		points[base + 2] = pos.z
		points[base + 3] = 0.0

		var scale_mat := Basis.from_scale(scale_linear)
		var rot_mat := Basis(rotation).transposed()
		var cov_3d := (scale_mat * rot_mat).transposed() * (scale_mat * rot_mat)

		points[base + 4] = cov_3d.x[0]
		points[base + 5] = cov_3d.y[0]
		points[base + 6] = cov_3d.z[0]
		points[base + 7] = cov_3d.y[1]
		points[base + 8] = cov_3d.z[1]
		points[base + 9] = cov_3d.z[2]

		points[base + 10] = clampf(opacities[i], 0.0, 1.0)
		points[base + 11] = 0.0

		var sh_offset := i * SH_FLOAT_COUNT
		for j in range(SH_FLOAT_COUNT):
			points[base + 12 + j] = sh_coeffs[sh_offset + j]

		if _should_yield(i, count):
			var processed_points := i + 1
			_advance_background_progress(processed_points - reported_points, PHASE_BUILDING, "Packing resource data (%d/%d)" % [processed_points, count])
			reported_points = processed_points
			await get_tree().process_frame

	var resource = GAUSSIAN_RESOURCE_SCRIPT.new()
	resource.point_count = count
	resource.point_data_float = points
	resource.point_data_byte = points.to_byte_array()
	resource.xyz = xyz
	resource.aabb = AABB(aabb_min_v, aabb_max_v - aabb_min_v) if count > 0 else AABB()

	return {
		"ok": true,
		"path": asset_path,
		"format": format,
		"resource": resource,
		"point_count": resource.point_count,
		"aabb": resource.aabb
	}

func _get_element(ply: Dictionary, name: String) -> Dictionary:
	var elements: Array = ply.get("elements", [])
	for element in elements:
		if element.get("name", "") == name:
			return element
	return {}

func _read_property(data: PackedByteArray, base: int, property_map: Dictionary, property_name: String, default_value: Variant) -> Variant:
	var prop: Dictionary = property_map.get(property_name, {})
	if prop.is_empty():
		return default_value
	return BINARY_PLY_READER.decode_scalar(data, base + int(prop["offset"]), String(prop["type"]))

func _read_required_property(data: PackedByteArray, base: int, property_map: Dictionary, property_name: String) -> Variant:
	var prop: Dictionary = property_map[property_name]
	return BINARY_PLY_READER.decode_scalar(data, base + int(prop["offset"]), String(prop["type"]))

func _should_yield(index: int, count: int) -> bool:
	return count > 0 and ((index + 1) % ASYNC_BATCH_SIZE == 0 or index + 1 == count)

func _unpack_111011(value: int) -> Vector3:
	return Vector3(
		float((value >> 21) & 0x7FF) / 2047.0,
		float((value >> 11) & 0x3FF) / 1023.0,
		float(value & 0x7FF) / 2047.0
	)

func _unpack_8888(value: int) -> Vector4:
	return Vector4(
		float((value >> 24) & 0xFF) / 255.0,
		float((value >> 16) & 0xFF) / 255.0,
		float((value >> 8) & 0xFF) / 255.0,
		float(value & 0xFF) / 255.0
	)

func _unpack_packed_rotation(value: int) -> Quaternion:
	var largest := (value >> 30) & 0x3
	var packed := [
		(value >> 20) & 0x3FF,
		(value >> 10) & 0x3FF,
		value & 0x3FF
	]
	var components := [0.0, 0.0, 0.0, 0.0]
	var packed_idx := 0
	var sum_sq := 0.0
	for component_idx in range(4):
		if component_idx == largest:
			continue
		var decoded := ((float(packed[packed_idx]) / 1023.0) - 0.5) * SQRT2
		components[component_idx] = decoded
		sum_sq += decoded * decoded
		packed_idx += 1
	components[largest] = sqrt(maxf(0.0, 1.0 - sum_sq))
	return Quaternion(components[1], components[2], components[3], components[0]).normalized()

func _decode_quantized_sh(value: int) -> float:
	return (((float(value) + 0.5) / 256.0) - 0.5) * 8.0

func _lerp_range(min_value: float, max_value: float, normalized: float) -> float:
	return min_value + (max_value - min_value) * normalized

func _sigmoid(value: float) -> float:
	return 1.0 / (1.0 + exp(-value))

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

func _begin_background_progress(total_units: int) -> void:
	# Reserve one final completion unit so pending progress never reaches 1.0.
	_background_total_units = max(total_units + 1, 2)
	_background_completed_units = 1
	_set_background_status(PHASE_DECODING, _background_status.get("status", STATUS_READING))

func _advance_background_progress(delta_units: int, phase: String, status_text: String) -> void:
	if delta_units > 0:
		_background_completed_units = min(_background_total_units, _background_completed_units + delta_units)
	_set_background_status(phase, status_text)

func _set_background_status(phase: String, status_text: String, extra: Dictionary = {}, emit_signal: bool = true) -> void:
	var status := _background_request.duplicate(true)
	for key in extra.keys():
		status[key] = extra[key]
	status["pending"] = status.get("pending", is_background_load_in_progress())
	status["phase"] = phase
	status["status"] = status_text
	status["progress"] = clampf(_compute_background_progress(), 0.0, 1.0) if not extra.has("progress") else clampf(float(extra["progress"]), 0.0, 1.0)
	_background_status = status
	if emit_signal:
		background_load_progressed.emit(status.duplicate(true))

func _compute_background_progress() -> float:
	if _background_total_units <= 0:
		return 0.0
	return float(_background_completed_units) / float(_background_total_units)

func _reset_background_status() -> void:
	_background_total_units = 0
	_background_completed_units = 0
	_background_status = {
		"pending": false,
		"progress": 0.0,
		"phase": PHASE_IDLE,
		"status": STATUS_IDLE
	}
