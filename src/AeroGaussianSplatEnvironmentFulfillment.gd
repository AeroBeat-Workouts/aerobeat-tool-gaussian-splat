class_name AeroGaussianSplatEnvironmentFulfillment
extends "res://addons/aerobeat-environment-core/src/contracts/interfaces/environment_kind_handler.gd"

const AeroEnvironmentProgress = preload("res://addons/aerobeat-environment-core/src/contracts/data_types/environment_progress.gd")
const AeroEnvironmentRequestValidator = preload("res://addons/aerobeat-environment-core/src/contracts/validators/environment_request_validator.gd")
const AeroEnvironmentConfigHelper = preload("res://addons/aerobeat-environment-core/src/contracts/validators/environment_config_helper.gd")
const GaussianSplatManagerScript = preload("AeroGaussianSplatManager.gd")

var _gaussian_manager: AeroGaussianSplatManager
var _active_operations: Dictionary = {}

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
	var normalized_result = _normalize_request(request)
	if not normalized_result.get("ok", false):
		return normalized_result.get("error")

	var normalized_request: AeroEnvironmentRequest = normalized_result["request"]
	var absolute_path = AeroEnvironmentRequestValidator.to_absolute_path(normalized_request.asset_path)
	if absolute_path.is_empty() or not FileAccess.file_exists(absolute_path):
		return _build_error(
			normalized_request,
			AeroEnvironmentConstants.ERROR_FILE_MISSING,
			"Splat file does not exist: %s" % normalized_request.asset_path,
			{"absolute_path": absolute_path}
		)

	var gaussian_manager = _ensure_gaussian_manager()
	var load_result: Dictionary = gaussian_manager.create_splat_node_from_path(absolute_path)
	if not load_result.get("ok", false):
		return _build_error(
			normalized_request,
			AeroEnvironmentConstants.ERROR_LOADER_FAILED,
			String(load_result.get("message", "Gaussian splat fulfillment failed.")),
			load_result
		)

	var node: Variant = load_result.get("node", null)
	var config_result = _apply_config_if_present(normalized_request, node)
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
	var world_environment_configured = false
	if world_environment is WorldEnvironment:
		gaussian_manager.configure_world_environment(world_environment)
		world_environment_configured = world_environment.compositor != null and world_environment.compositor.compositor_effects.size() > 0

	var details = {
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

func begin_fulfill(request: Variant) -> AeroEnvironmentOperation:
	var normalized_result = _normalize_request(request)
	if not normalized_result.get("ok", false):
		return _wrap_sync_terminal_error(normalized_result.get("error"))

	var normalized_request: AeroEnvironmentRequest = normalized_result["request"]
	var absolute_path = AeroEnvironmentRequestValidator.to_absolute_path(normalized_request.asset_path)
	if absolute_path.is_empty() or not FileAccess.file_exists(absolute_path):
		return _wrap_sync_terminal_error(_build_error(
			normalized_request,
			AeroEnvironmentConstants.ERROR_FILE_MISSING,
			"Splat file does not exist: %s" % normalized_request.asset_path,
			{"absolute_path": absolute_path}
		))

	var operation: AeroEnvironmentOperation = AeroEnvironmentOperation.new(normalized_request)
	var queued_progress: AeroEnvironmentProgress = _build_contract_progress(normalized_request, {
		"pending": true,
		"phase": "reading",
		"status": "Queued",
		"progress": 0.0,
	}, 0, AeroEnvironmentConstants.STATE_PENDING, AeroEnvironmentConstants.STATUS_QUEUED)
	_operation_mark_started(operation, queued_progress)

	var gaussian_manager = _ensure_gaussian_manager()
	var start_result: Dictionary = gaussian_manager.begin_create_splat_node_from_path(absolute_path)
	if not start_result.get("ok", false):
		var start_error = _build_error(
			normalized_request,
			AeroEnvironmentConstants.ERROR_LOADER_FAILED,
			String(start_result.get("message", "Gaussian splat fulfillment failed to start.")),
			start_result
		)
		var failed_progress = _build_contract_progress(normalized_request, start_result, 1, AeroEnvironmentConstants.STATE_FAILED, AeroEnvironmentConstants.STATUS_FAILED)
		_operation_fail(operation, start_error, failed_progress)
		return operation

	var operation_id: String = _get_operation_key(operation)
	var started_callable: Callable = Callable(self, "_on_background_load_started").bind(operation_id)
	var progressed_callable: Callable = Callable(self, "_on_background_load_progressed").bind(operation_id)
	var finished_callable: Callable = Callable(self, "_on_background_load_finished").bind(operation_id)
	_active_operations[operation_id] = {
		"operation": operation,
		"request": normalized_request,
		"absolute_path": absolute_path,
		"sequence": 1,
		"started_callable": started_callable,
		"progressed_callable": progressed_callable,
		"finished_callable": finished_callable,
	}
	gaussian_manager.background_load_started.connect(started_callable)
	gaussian_manager.background_load_progressed.connect(progressed_callable)
	gaussian_manager.background_load_finished.connect(finished_callable)
	return operation

func supports_async() -> bool:
	return true

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
	var request_dict = {}
	if request is Dictionary:
		request_dict = request
	elif request is AeroEnvironmentRequest:
		request_dict = request.to_dict()
	else:
		var fallback_request = AeroEnvironmentRequest.new()
		var error = _build_error(
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

func _on_background_load_started(result: Dictionary, operation_id: String) -> void:
	var context: Dictionary = _active_operations.get(operation_id, {})
	if context.is_empty():
		return
	var progress: AeroEnvironmentProgress = _build_contract_progress(context["request"], result, _next_operation_sequence(operation_id), AeroEnvironmentConstants.STATE_RUNNING)
	_operation_push_progress(context["operation"], progress)

func _on_background_load_progressed(result: Dictionary, operation_id: String) -> void:
	var context: Dictionary = _active_operations.get(operation_id, {})
	if context.is_empty():
		return
	var progress: AeroEnvironmentProgress = _build_contract_progress(context["request"], result, _next_operation_sequence(operation_id), AeroEnvironmentConstants.STATE_RUNNING)
	_operation_push_progress(context["operation"], progress)

func _on_background_load_finished(result: Dictionary, operation_id: String) -> void:
	var context: Dictionary = _active_operations.get(operation_id, {})
	if context.is_empty():
		return

	var request: AeroEnvironmentRequest = context["request"]
	var operation: AeroEnvironmentOperation = context["operation"]
	_disconnect_operation_signals(context)

	if not result.get("ok", false):
		var error = _build_error(
			request,
			AeroEnvironmentConstants.ERROR_LOADER_FAILED,
			String(result.get("message", "Gaussian splat fulfillment failed.")),
			result
		)
		var failed_progress = _build_contract_progress(request, result, _next_operation_sequence(operation_id), AeroEnvironmentConstants.STATE_FAILED, AeroEnvironmentConstants.STATUS_FAILED)
		_operation_fail(operation, error, failed_progress)
		_active_operations.erase(operation_id)
		return

	var node: Variant = result.get("node", null)
	var config_progress: AeroEnvironmentProgress = _build_contract_progress(request, {
		"pending": true,
		"phase": "applying_config",
		"status": "Applying config",
		"progress": maxf(float(result.get("progress", 0.0)), 0.95),
	}, _next_operation_sequence(operation_id), AeroEnvironmentConstants.STATE_RUNNING, AeroEnvironmentConstants.STATUS_APPLYING_CONFIG)
	_operation_push_progress(operation, config_progress)

	var config_result = _apply_config_if_present(request, node)
	if not config_result.get("ok", false):
		if node != null and is_instance_valid(node):
			node.queue_free()
		var config_error = _build_error(
			request,
			AeroEnvironmentConstants.ERROR_INVALID_CONFIG,
			String(config_result.get("message", "Gaussian splat config could not be applied.")),
			config_result
		)
		var config_failed_progress: AeroEnvironmentProgress = _build_contract_progress(request, {
			"pending": false,
			"phase": "applying_config",
			"status": String(config_result.get("message", "Applying config failed")),
			"progress": maxf(float(result.get("progress", 0.0)), 0.95),
		}, _next_operation_sequence(operation_id), AeroEnvironmentConstants.STATE_FAILED, AeroEnvironmentConstants.STATUS_FAILED)
		_operation_fail(operation, config_error, config_failed_progress)
		_active_operations.erase(operation_id)
		return

	var gaussian_manager = _ensure_gaussian_manager()
	var request_context: Dictionary = request.context
	var world_environment = request_context.get("world_environment", null)
	var world_environment_configured = false
	if world_environment is WorldEnvironment:
		gaussian_manager.configure_world_environment(world_environment)
		world_environment_configured = world_environment.compositor != null and world_environment.compositor.compositor_effects.size() > 0

	var details = {
		"node": node,
		"resource": result.get("resource", null),
		"point_count": int(result.get("point_count", 0)),
		"aabb": result.get("aabb", AABB()),
		"config": config_result.get("config", {}),
		"world_environment_configured": world_environment_configured,
	}
	var success_result = AeroEnvironmentResult.new({
		"ok": true,
		"request_id": request.request_id,
		"kind": request.kind,
		"asset_path": request.asset_path,
		"config_path": String(config_result.get("config_path", request.config_path)),
		"format": AeroEnvironmentConstants.required_format_for_kind(request.kind),
		"config_applied": bool(config_result.get("config_applied", false)),
		"metadata": request.metadata,
		"details": details,
	})
	var ready_progress: AeroEnvironmentProgress = _build_contract_progress(request, {
		"pending": false,
		"phase": "ready",
		"status": "Ready",
		"progress": 1.0,
	}, _next_operation_sequence(operation_id), AeroEnvironmentConstants.STATE_SUCCEEDED, AeroEnvironmentConstants.STATUS_READY)
	_operation_succeed(operation, success_result, ready_progress)
	_active_operations.erase(operation_id)

func _build_contract_progress(request: AeroEnvironmentRequest, runtime_result: Dictionary, sequence: int, state_override: String = "", status_override: String = "") -> AeroEnvironmentProgress:
	var phase = String(runtime_result.get("phase", "")).strip_edges().to_lower()
	var status = status_override if not status_override.is_empty() else _map_runtime_phase_to_contract_status(phase)
	if status.is_empty():
		status = AeroEnvironmentConstants.STATUS_LOADING
	var progress_data = {
		"request_id": request.request_id,
		"kind": request.kind,
		"asset_path": request.asset_path,
		"state": state_override if not state_override.is_empty() else (AeroEnvironmentConstants.STATE_RUNNING if bool(runtime_result.get("pending", true)) else AeroEnvironmentConstants.STATE_SUCCEEDED),
		"status": status,
		"phase": phase,
		"progress": clampf(float(runtime_result.get("progress", 0.0)), 0.0, 1.0),
		"message": String(runtime_result.get("status", "")).strip_edges(),
		"sequence": sequence,
		"indeterminate": false,
		"metadata": {
			"runtime": runtime_result.duplicate(true),
		},
	}
	return _new_progress(progress_data)

func _map_runtime_phase_to_contract_status(phase: String) -> String:
	match phase:
		"reading":
			return AeroEnvironmentConstants.STATUS_LOADING
		"decoding":
			return AeroEnvironmentConstants.STATUS_DECODING
		"building":
			return AeroEnvironmentConstants.STATUS_INSTANTIATING
		"applying_config":
			return AeroEnvironmentConstants.STATUS_APPLYING_CONFIG
		"ready":
			return AeroEnvironmentConstants.STATUS_READY
		_:
			return AeroEnvironmentConstants.STATUS_LOADING if phase.is_empty() else phase

func _new_progress(data: Dictionary) -> AeroEnvironmentProgress:
	return AeroEnvironmentProgress.new(data)

func _wrap_sync_terminal_error(error: AeroEnvironmentError) -> AeroEnvironmentOperation:
	var request: AeroEnvironmentRequest = AeroEnvironmentRequest.new({
		"request_id": error.request_id,
		"kind": error.kind,
		"asset_path": error.asset_path,
		"metadata": error.metadata,
	})
	var operation: AeroEnvironmentOperation = AeroEnvironmentOperation.new(request)
	var progress: AeroEnvironmentProgress = _build_contract_progress(request, {
		"pending": false,
		"phase": "resolving",
		"status": error.message,
		"progress": 0.0,
	}, 0, AeroEnvironmentConstants.STATE_FAILED, AeroEnvironmentConstants.STATUS_FAILED)
	_operation_fail(operation, error, progress)
	return operation

func _operation_mark_started(operation: AeroEnvironmentOperation, progress: AeroEnvironmentProgress) -> void:
	operation.mark_started(progress)

func _operation_push_progress(operation: AeroEnvironmentOperation, progress: AeroEnvironmentProgress) -> void:
	operation.push_progress(progress)

func _operation_succeed(operation: AeroEnvironmentOperation, result: AeroEnvironmentResult, progress: AeroEnvironmentProgress) -> void:
	operation.succeed(result, progress)

func _operation_fail(operation: AeroEnvironmentOperation, error: AeroEnvironmentError, progress: AeroEnvironmentProgress) -> void:
	operation.fail(error, progress)

func _get_operation_key(operation: AeroEnvironmentOperation) -> String:
	return str(operation.get_instance_id())

func _next_operation_sequence(operation_id: String) -> int:
	var context: Dictionary = _active_operations.get(operation_id, {})
	var next_sequence = int(context.get("sequence", 0))
	context["sequence"] = next_sequence + 1
	_active_operations[operation_id] = context
	return next_sequence

func _disconnect_operation_signals(context: Dictionary) -> void:
	var gaussian_manager = _ensure_gaussian_manager()
	var started_callable: Callable = context.get("started_callable", Callable())
	var progressed_callable: Callable = context.get("progressed_callable", Callable())
	var finished_callable: Callable = context.get("finished_callable", Callable())
	if started_callable.is_valid() and gaussian_manager.background_load_started.is_connected(started_callable):
		gaussian_manager.background_load_started.disconnect(started_callable)
	if progressed_callable.is_valid() and gaussian_manager.background_load_progressed.is_connected(progressed_callable):
		gaussian_manager.background_load_progressed.disconnect(progressed_callable)
	if finished_callable.is_valid() and gaussian_manager.background_load_finished.is_connected(finished_callable):
		gaussian_manager.background_load_finished.disconnect(finished_callable)

func _apply_config_if_present(request: AeroEnvironmentRequest, target: Variant) -> Dictionary:
	if not (target is Node):
		return {
			"ok": false,
			"message": "Gaussian splat fulfillment did not return a node that could receive config.",
		}
	var config_path = request.config_path
	if config_path.is_empty():
		return {
			"ok": true,
			"config_applied": false,
			"config_path": "",
			"config": {},
		}
	var absolute_path = AeroEnvironmentRequestValidator.to_absolute_path(config_path)
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
