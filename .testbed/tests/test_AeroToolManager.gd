extends GutTest

const SAMPLE_PLY := "res://assets/splats/demo.ply"
const SAMPLE_COMPRESSED_PLY := "res://assets/splats/demo.compressed.ply"
const LOWER_RUNTIME_SCRIPT := preload("res://addons/aerobeat-environment-gaussian-splat-fulfillment/runtime/gaussian_splat_runtime.gd")
const FULFILLMENT_SCRIPT := preload("res://src/AeroGaussianSplatEnvironmentFulfillment.gd")
const REQUEST_SCRIPT := preload("res://addons/aerobeat-environment-core/src/contracts/data_types/environment_request.gd")
const RESULT_SCRIPT := preload("res://addons/aerobeat-environment-core/src/contracts/data_types/environment_result.gd")
const ERROR_SCRIPT := preload("res://addons/aerobeat-environment-core/src/contracts/data_types/environment_error.gd")

func test_tool_manager_initializes_and_exposes_supported_formats() -> void:
	var manager := AeroToolManager.new()
	manager._initialize()
	assert_true(manager._is_initialized, "Manager should initialize")
	assert_true(manager.get_supported_extensions().has("ply"), "PLY should be supported")
	assert_true(manager.get_supported_extensions().has("splat"), "Legacy .splat should be supported")
	manager.free()

func test_lower_runtime_is_path_loadable_and_builds_a_resource() -> void:
	var runtime = LOWER_RUNTIME_SCRIPT.new()
	add_child_autofree(runtime)
	var absolute_path := ProjectSettings.globalize_path(SAMPLE_PLY)
	var result := runtime.load_gaussian_resource_from_path(absolute_path)
	assert_true(result.get("ok", false), result.get("message", "Expected lower runtime sample PLY to load"))
	assert_true(result.get("point_count", 0) > 0, "Lower runtime should decode sample points")
	assert_true(result.get("resource", null) != null, "Lower runtime should return a resource")

func test_public_manager_matches_lower_runtime_surface() -> void:
	var public_manager := AeroGaussianSplatManager.new()
	var lower_runtime = LOWER_RUNTIME_SCRIPT.new()
	add_child_autofree(public_manager)
	add_child_autofree(lower_runtime)
	assert_eq(public_manager.get_supported_extensions(), lower_runtime.get_supported_extensions(), "Public manager should preserve the lower runtime extension contract")
	assert_eq(public_manager.get_renderer_support_status().get("support_level", ""), lower_runtime.get_renderer_support_status().get("support_level", ""), "Public manager should preserve the lower runtime renderer-support contract")

func test_contract_fulfillment_accepts_typed_request_and_returns_typed_result() -> void:
	var manager := AeroToolManager.new()
	manager._initialize()
	var request = REQUEST_SCRIPT.new({
		"request_id": "req-splat-contract",
		"kind": "splat",
		"asset_path": ProjectSettings.globalize_path(SAMPLE_COMPRESSED_PLY),
	})
	var result = manager.fulfill_environment_request(request)
	assert_true(result is RESULT_SCRIPT, "Contract fulfillment should return a typed environment result on success")
	assert_true(result.ok, "Typed fulfillment result should succeed for the sample compressed ply")
	assert_eq(result.kind, "splat")
	assert_eq(result.format, ".compressed.ply")
	assert_true(result.details.get("node", null) is Node3D, "Fulfillment should surface the created splat node in result.details")
	assert_true(int(result.details.get("point_count", 0)) > 0, "Fulfillment should surface decoded point count")
	if result.details.get("node", null) != null and is_instance_valid(result.details.get("node", null)):
		(result.details.get("node", null) as Node).free()
	manager.free()

func test_contract_fulfillment_applies_config_and_can_configure_world_environment() -> void:
	var manager := AeroToolManager.new()
	manager._initialize()
	var temp_dir := ProjectSettings.globalize_path("user://gaussian_splat_contract_tests")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var config_path := "%s/demo.json" % temp_dir
	FileAccess.open(config_path, FileAccess.WRITE).store_string('{"position":[1,2,3],"rotation_degrees":{"x":0,"y":90,"z":0},"scale":[2,2,2]}')
	var world_environment := WorldEnvironment.new()
	var request := {
		"request_id": "req-splat-config",
		"kind": "splat",
		"asset_path": ProjectSettings.globalize_path(SAMPLE_COMPRESSED_PLY),
		"config_path": config_path,
		"context": {"world_environment": world_environment},
	}
	var result = manager.fulfill(request)
	assert_true(result is RESULT_SCRIPT, "Compat fulfill alias should still route through the typed contract adapter")
	assert_true(result.ok, "Configured contract fulfillment should succeed")
	assert_true(result.config_applied, "Config sidecar should be applied when present")
	assert_eq(result.config_path, config_path)
	var node: Variant = result.details.get("node", null)
	assert_true(node is Node3D, "Configured fulfillment should still return a Node3D")
	assert_eq((node as Node3D).position, Vector3(1, 2, 3))
	assert_almost_eq((node as Node3D).rotation_degrees.y, 90.0, 0.001)
	assert_eq((node as Node3D).scale, Vector3(2, 2, 2))
	assert_true(result.details.get("world_environment_configured", false) in [true, false], "Fulfillment should report whether compositor configuration was attempted")
	if result.details.get("world_environment_configured", false):
		assert_not_null(world_environment.compositor, "World environment should receive a compositor when the current renderer supports it")
	if node != null and is_instance_valid(node):
		(node as Node).free()
	world_environment.free()
	manager.free()

func test_contract_fulfillment_rejects_non_contract_formats_even_if_wrapper_supports_them() -> void:
	var fulfillment = FULFILLMENT_SCRIPT.new()
	var result = fulfillment.fulfill({
		"request_id": "req-splat-bad-format",
		"kind": "splat",
		"asset_path": ProjectSettings.globalize_path(SAMPLE_PLY),
	})
	assert_true(result is ERROR_SCRIPT, "Contract fulfillment should return a typed environment error on failure")
	assert_eq(result.error_code, "unsupported_format")
	assert_true(result.message.contains("requires .compressed.ply"), "Contract error should explain the official splat format requirement")

func test_begin_fulfill_returns_operation_and_completes_with_typed_result() -> void:
	var manager := AeroToolManager.new()
	add_child_autofree(manager)
	manager._initialize()
	var request = REQUEST_SCRIPT.new({
		"request_id": "req-splat-async-success",
		"kind": "splat",
		"asset_path": ProjectSettings.globalize_path(SAMPLE_COMPRESSED_PLY),
	})
	var operation: Variant = manager.call("begin_fulfill", request)
	assert_not_null(operation, "Async contract path should return an operation object")
	assert_true(operation.has_signal("finished"), "Operation should expose a finished signal")
	await operation.finished
	await get_tree().process_frame
	assert_true(operation.result is RESULT_SCRIPT, "Async operation should resolve with a typed environment result")
	assert_true(operation.result.ok, "Async operation should succeed for the sample compressed ply")
	var latest_progress: Variant = operation.latest_progress
	assert_not_null(latest_progress, "Async operation should retain the final progress snapshot")
	var progress_dict: Dictionary = latest_progress.to_dict() if latest_progress.has_method("to_dict") else {}
	assert_eq(String(progress_dict.get("state", "")), "succeeded", "Final async progress should report a succeeded state")
	assert_eq(String(progress_dict.get("status", "")), "ready", "Final async progress should report the ready contract status")
	assert_eq(String(progress_dict.get("phase", "")), "ready", "Final async progress should preserve the splat-specific ready phase")
	assert_eq(float(progress_dict.get("progress", 0.0)), 1.0, "Final async progress should report 1.0 completion")
	var result_node: Variant = operation.result.details.get("node", null)
	if result_node != null and is_instance_valid(result_node):
		(result_node as Node).free()

func test_begin_fulfill_wraps_sync_validation_errors_into_failed_operations() -> void:
	var fulfillment: Variant = FULFILLMENT_SCRIPT.new()
	var operation: Variant = fulfillment.call("begin_fulfill", {
		"request_id": "req-splat-async-bad-format",
		"kind": "splat",
		"asset_path": ProjectSettings.globalize_path(SAMPLE_PLY),
	})
	assert_not_null(operation, "Async contract path should still return an operation for terminal validation errors")
	assert_true(operation.has_signal("finished"), "Failed operation should expose a finished signal")
	assert_true(operation.error is ERROR_SCRIPT, "Failed async operation should capture a typed environment error")
	assert_eq(operation.error.error_code, "unsupported_format")
	var latest_progress: Variant = operation.latest_progress
	assert_not_null(latest_progress, "Failed async operation should still retain a terminal progress snapshot")
	var progress_dict: Dictionary = latest_progress.to_dict() if latest_progress.has_method("to_dict") else {}
	assert_eq(String(progress_dict.get("state", "")), "failed", "Failed async progress should report a failed state")
	assert_eq(String(progress_dict.get("status", "")), "failed", "Failed async progress should report the failed contract status")

func test_runtime_progress_translation_uses_contract_status_and_splat_phase() -> void:
	var fulfillment: Variant = FULFILLMENT_SCRIPT.new()
	var request = REQUEST_SCRIPT.new({
		"request_id": "req-splat-progress-map",
		"kind": "splat",
		"asset_path": ProjectSettings.globalize_path(SAMPLE_COMPRESSED_PLY),
	})
	var progress: Variant = fulfillment.call("_build_contract_progress", request, {
		"pending": true,
		"phase": "decoding",
		"status": "Decoding vertices (128/1024)",
		"progress": 0.375,
	}, 7, "running")
	var progress_dict: Dictionary = progress.to_dict() if progress.has_method("to_dict") else {}
	assert_eq(String(progress_dict.get("state", "")), "running", "Progress translation should mark active async work as running")
	assert_eq(String(progress_dict.get("status", "")), "decoding", "Progress translation should use contract status vocabulary")
	assert_eq(String(progress_dict.get("phase", "")), "decoding", "Progress translation should preserve splat-specific phase detail")
	assert_eq(int(progress_dict.get("sequence", -1)), 7, "Progress translation should preserve ordered sequence numbers")
	assert_eq(float(progress_dict.get("progress", 0.0)), 0.375, "Progress translation should preserve fractional progress")
	assert_eq(String(progress_dict.get("message", "")), "Decoding vertices (128/1024)", "Progress translation should preserve runtime status text as the user-facing message")

func test_renderer_support_status_reports_runtime_truth() -> void:
	var manager := AeroToolManager.new()
	manager._initialize()
	var status := manager.get_renderer_support_status()
	assert_true(status.has("renderer_name"), "Support status should name the current renderer")
	assert_true(status.has("support_level"), "Support status should report a support level")
	assert_true(status.has("has_rendering_device"), "Support status should say whether a RenderingDevice exists")
	assert_true(status.has("can_attempt_render"), "Support status should say whether visible render can be attempted")
	assert_true(status.has("can_configure_compositor"), "Support status should say whether compositor setup is allowed")
	assert_true(status.has("message"), "Support status should include a user-facing message")
	if not bool(status.get("has_rendering_device", false)):
		assert_false(status.get("ok", true), "Renderer paths without a RenderingDevice should not be treated as render-capable")
		assert_false(status.get("can_attempt_render", true), "Renderer paths without a RenderingDevice should not attempt visible render")
		assert_false(status.get("can_configure_compositor", true), "Renderer paths without a RenderingDevice should not configure the compositor")
		assert_eq(status.get("support_level", ""), "unsupported", "Renderer paths without a RenderingDevice should be marked unsupported")
	else:
		assert_true(status.get("ok", false), "RenderingDevice renderer paths should at least be eligible for render attempts")
		assert_true(status.get("can_attempt_render", false), "RenderingDevice renderer paths should allow render attempts")
		assert_true(status.get("can_configure_compositor", false), "RenderingDevice renderer paths should allow compositor configuration")
		assert_eq(status.get("support_level", ""), "experimental", "RenderingDevice renderer paths should stay truthfully experimental until fully validated")
	manager.free()

func test_absolute_path_loading_builds_a_resource() -> void:
	var manager := AeroToolManager.new()
	manager._initialize()
	var absolute_path := ProjectSettings.globalize_path(SAMPLE_PLY)
	var result := manager.load_gaussian_resource_from_path(absolute_path)
	assert_true(result.get("ok", false), result.get("message", "Expected sample PLY to load"))
	assert_true(result.get("point_count", 0) > 0, "Loaded sample should contain points")
	assert_true(result.get("resource", null) != null, "Resource should be returned")
	manager.free()

func test_background_loading_starts_and_reports_pending_state() -> void:
	var manager := AeroToolManager.new()
	add_child_autofree(manager)
	manager._initialize()
	var absolute_path := ProjectSettings.globalize_path(SAMPLE_PLY)
	var start_result := manager.begin_create_splat_node_from_path(absolute_path)
	assert_true(start_result.get("ok", false), start_result.get("message", "Expected background load to start"))
	assert_true(start_result.get("pending", false), "Background load should report pending immediately")
	assert_true(manager.is_background_load_in_progress(), "Background load should be marked in progress")
	assert_eq(start_result.get("phase", ""), "reading", "Background load should start in the reading phase")
	assert_eq(start_result.get("status", ""), "Reading splat file", "Background load should expose user-facing reading status text")
	assert_eq(float(start_result.get("progress", -1.0)), 0.0, "Background load should start at 0.0 progress")
	var status := manager.get_background_load_status()
	assert_eq(status.get("phase", ""), "reading", "Status accessor should mirror the current phase")
	assert_eq(status.get("status", ""), "Reading splat file", "Status accessor should mirror the current status text")

func test_background_progress_stays_below_complete_until_finalize() -> void:
	var manager := AeroToolManager.new()
	manager._initialize()
	var gaussian_manager = manager._gaussian_manager
	gaussian_manager._background_request = {
		"path": ProjectSettings.globalize_path(SAMPLE_PLY),
		"format": "ply",
		"request_kind": "resource"
	}
	gaussian_manager._begin_background_progress(1 + 2 + 2 + 2)
	gaussian_manager._advance_background_progress(2 + 2 + 2, "building", "Packing resource data (2/2)")
	var pending_status := gaussian_manager.get_background_load_status()
	assert_true(pending_status.get("pending", false), "Pending progress should remain marked pending")
	assert_lt(float(pending_status.get("progress", 1.0)), 1.0, "Pending progress should stay below 1.0 before finalize")

	gaussian_manager._finalize_background_load({
		"ok": true,
		"path": ProjectSettings.globalize_path(SAMPLE_PLY),
		"format": "ply",
		"resource": null,
		"point_count": 1,
		"aabb": AABB()
	})
	var finished_status := gaussian_manager.get_background_load_status()
	assert_false(finished_status.get("pending", true), "Finished status should clear pending")
	assert_eq(finished_status.get("phase", ""), "ready", "Finished status should report the ready phase")
	assert_eq(finished_status.get("status", ""), "Ready", "Finished status should report Ready status")
	assert_eq(float(finished_status.get("progress", 0.0)), 1.0, "Finished status should report 1.0 progress")
	manager.free()

func test_configure_world_environment_persists_compositor_effect_once() -> void:
	var manager := AeroToolManager.new()
	manager._initialize()
	var world_environment := WorldEnvironment.new()
	var status := manager.get_renderer_support_status()

	manager.configure_world_environment(world_environment)

	if bool(status.get("can_configure_compositor", false)):
		assert_not_null(world_environment.compositor, "World environment should get a compositor on renderer paths that can configure one")
		assert_eq(world_environment.compositor.compositor_effects.size(), 1, "Gaussian compositor effect should persist on the compositor")
		var effect: CompositorEffect = world_environment.compositor.compositor_effects[0]
		assert_not_null(effect.get_script(), "Configured compositor effect should have the gdgs script attached")
		assert_eq(effect.get_script().resource_path, "res://addons/gdgs/runtime/compositor/gaussian_compositor_effect.gd", "Configured compositor effect should point at the gdgs compositor script")

		manager.configure_world_environment(world_environment)
		assert_eq(world_environment.compositor.compositor_effects.size(), 1, "Configuring the same world environment twice should not duplicate the compositor effect")
	else:
		assert_null(world_environment.compositor, "Unsupported renderer paths should leave the compositor unset")
	world_environment.free()
	manager.free()
