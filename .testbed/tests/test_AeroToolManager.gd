extends GutTest

const SAMPLE_PLY := "res://assets/splats/demo.ply"
const LOWER_RUNTIME_SCRIPT := preload("res://addons/aerobeat-tool-gaussian-splat-fulfillment/runtime/gaussian_splat_runtime.gd")

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
