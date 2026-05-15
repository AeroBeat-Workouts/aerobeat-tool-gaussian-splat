extends GutTest

const SAMPLE_PLY := "res://assets/splats/demo.ply"

func test_tool_manager_initializes_and_exposes_supported_formats() -> void:
	var manager := AeroToolManager.new()
	manager._initialize()
	assert_true(manager._is_initialized, "Manager should initialize")
	assert_true(manager.get_supported_extensions().has("ply"), "PLY should be supported")
	assert_true(manager.get_supported_extensions().has("splat"), "Legacy .splat should be supported")
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

	manager.configure_world_environment(world_environment)

	assert_not_null(world_environment.compositor, "World environment should get a compositor")
	assert_eq(world_environment.compositor.compositor_effects.size(), 1, "Gaussian compositor effect should persist on the compositor")
	var effect: CompositorEffect = world_environment.compositor.compositor_effects[0]
	assert_not_null(effect.get_script(), "Configured compositor effect should have the gdgs script attached")
	assert_eq(effect.get_script().resource_path, "res://addons/gdgs/runtime/compositor/gaussian_compositor_effect.gd", "Configured compositor effect should point at the gdgs compositor script")

	manager.configure_world_environment(world_environment)
	assert_eq(world_environment.compositor.compositor_effects.size(), 1, "Configuring the same world environment twice should not duplicate the compositor effect")
	world_environment.free()
	manager.free()
