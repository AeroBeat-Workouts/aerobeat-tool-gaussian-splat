class_name AeroGaussianSplatEnvironmentFulfillment
extends "res://addons/aerobeat-environment-core/src/contracts/interfaces/environment_kind_handler.gd"

const AeroEnvironmentRequest = preload("res://addons/aerobeat-environment-core/src/contracts/data_types/environment_request.gd")
const AeroEnvironmentResult = preload("res://addons/aerobeat-environment-core/src/contracts/data_types/environment_result.gd")
const AeroEnvironmentError = preload("res://addons/aerobeat-environment-core/src/contracts/data_types/environment_error.gd")
const AeroEnvironmentRequestValidator = preload("res://addons/aerobeat-environment-core/src/contracts/validators/environment_request_validator.gd")
const AeroEnvironmentConfigHelper = preload("res://addons/aerobeat-environment-core/src/contracts/validators/environment_config_helper.gd")
const GaussianSplatManagerScript = preload("AeroGaussianSplatManager.gd")

var _gaussian_manager: AeroGaussianSplatManager

func _init(gaussian_manager: AeroGaussianSplatManager = null) -> void:
	supported_kind = AeroEnvironmentConstants.KIND_SPLAT
	_gaussian_manager = gaussian_manager

func get_handler_name() -> String:
	return "gaussian_splat"

func set_gaussian_manager(gaussian_manager: AeroGaussianSplatManager) -> AeroGaussianSplatEnvironmentFulfillment:
	_gaussian_manager = gaussian_manager
	return self

func get_gaussian_manager() -> AeroGaussianSplatManager:
	return _ensure_gaussian_manager()

func fulfill(request: Variant) -> Variant:
	var normalized_result := _normalize_request(request)
	if not normalized_result.get("ok", false):
		return normalized_result.get("error")

	var normalized_request: AeroEnvironmentRequest = normalized_result["request"]
	var absolute_path := AeroEnvironmentRequestValidator.to_absolute_path(normalized_request.asset_path)
	if absolute_path.is_empty() or not FileAccess.file_exists(absolute_path):
		return _build_error(
			normalized_request,
			AeroEnvironmentConstants.ERROR_FILE_MISSING,
			"Splat file does not exist: %s" % normalized_request.asset_path,
			{"absolute_path": absolute_path}
		)

	var gaussian_manager := _ensure_gaussian_manager()
	var load_result: Dictionary = gaussian_manager.create_splat_node_from_path(absolute_path)
	if not load_result.get("ok", false):
		return _build_error(
			normalized_request,
			AeroEnvironmentConstants.ERROR_LOADER_FAILED,
			String(load_result.get("message", "Gaussian splat fulfillment failed.")),
			load_result
		)

	var node: Variant = load_result.get("node", null)
	var config_result := _apply_config_if_present(normalized_request, node)
	if not config_result.get("ok", false):
		if node != null and is_instance_valid(node):
			node.queue_free()
		return _build_error(
			normalized_request,
			AeroEnvironmentConstants.ERROR_INVALID_CONFIG,
			String(config_result.get("message", "Gaussian splat config could not be applied.")),
			config_result
		)

	var context: Dictionary = normalized_request.context
	var world_environment = context.get("world_environment", null)
	var world_environment_configured := false
	if world_environment is WorldEnvironment:
		gaussian_manager.configure_world_environment(world_environment)
		world_environment_configured = world_environment.compositor != null and world_environment.compositor.compositor_effects.size() > 0

	var details := {
		"node": node,
		"resource": load_result.get("resource", null),
		"point_count": int(load_result.get("point_count", 0)),
		"aabb": load_result.get("aabb", AABB()),
		"config": config_result.get("config", {}),
		"world_environment_configured": world_environment_configured,
	}
	return AeroEnvironmentResult.new({
		"ok": true,
		"request_id": normalized_request.request_id,
		"kind": normalized_request.kind,
		"asset_path": normalized_request.asset_path,
		"config_path": String(config_result.get("config_path", normalized_request.config_path)),
		"format": AeroEnvironmentConstants.required_format_for_kind(normalized_request.kind),
		"config_applied": bool(config_result.get("config_applied", false)),
		"metadata": normalized_request.metadata,
		"details": details,
	})

func fulfill_to_dict(request: Variant) -> Dictionary:
	var fulfillment_result = fulfill(request)
	if fulfillment_result == null:
		return {}
	if fulfillment_result.has_method("to_dict"):
		return fulfillment_result.to_dict()
	if fulfillment_result is Dictionary:
		return fulfillment_result
	return {"value": fulfillment_result}

func _normalize_request(request: Variant) -> Dictionary:
	var request_dict := {}
	if request is Dictionary:
		request_dict = request
	elif request is AeroEnvironmentRequest:
		request_dict = request.to_dict()
	else:
		var fallback_request := AeroEnvironmentRequest.new()
		var error := _build_error(
			fallback_request,
			AeroEnvironmentConstants.ERROR_INVALID_REQUEST,
			"Gaussian splat fulfillment requires a Dictionary or AeroEnvironmentRequest.",
			{"received_type": typeof(request)}
		)
		return {
			"ok": false,
			"error": error,
		}

	var normalized_result: Dictionary = AeroEnvironmentRequestValidator.normalize_request_dict(request_dict, true)
	if not normalized_result.get("ok", false):
		return {
			"ok": false,
			"error": normalized_result.get("error"),
		}
	return {
		"ok": true,
		"request": normalized_result["request"],
	}

func _apply_config_if_present(request: AeroEnvironmentRequest, target: Variant) -> Dictionary:
	if not (target is Node):
		return {
			"ok": false,
			"message": "Gaussian splat fulfillment did not return a node that could receive config.",
		}
	var config_path := request.config_path
	if config_path.is_empty():
		return {
			"ok": true,
			"config_applied": false,
			"config_path": "",
			"config": {},
		}
	var absolute_path := AeroEnvironmentRequestValidator.to_absolute_path(config_path)
	if absolute_path.is_empty() or not FileAccess.file_exists(absolute_path):
		return {
			"ok": true,
			"config_applied": false,
			"config_path": config_path,
			"config": {},
		}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(absolute_path))
	if not (parsed is Dictionary):
		return {
			"ok": false,
			"message": "Environment config is not a JSON object: %s" % config_path,
		}
	var config_dict: Dictionary = parsed
	var apply_result: Dictionary = AeroEnvironmentConfigHelper.apply_config_dict(config_dict, target as Node)
	if not apply_result.get("ok", false):
		return apply_result
	return {
		"ok": true,
		"config_applied": true,
		"config_path": config_path,
		"config": config_dict,
	}

func _ensure_gaussian_manager() -> AeroGaussianSplatManager:
	if _gaussian_manager == null:
		_gaussian_manager = GaussianSplatManagerScript.new()
	return _gaussian_manager

func _build_error(request: AeroEnvironmentRequest, error_code: String, message: String, details: Dictionary = {}) -> AeroEnvironmentError:
	return AeroEnvironmentError.new({
		"request_id": request.request_id,
		"kind": request.kind,
		"asset_path": request.asset_path,
		"error_code": error_code,
		"message": message,
		"recoverable": true,
		"metadata": request.metadata,
		"details": details,
	})
