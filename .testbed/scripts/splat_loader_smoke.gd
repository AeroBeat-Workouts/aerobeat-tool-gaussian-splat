extends Node3D

const TOOL_MANAGER_SCRIPT := preload("res://src/AeroGaussianSplatManager.gd")

var _tool_manager: AeroGaussianSplatManager
var _world_environment: WorldEnvironment
var _camera: Camera3D

func _ready() -> void:
	_tool_manager = TOOL_MANAGER_SCRIPT.new()
	add_child(_tool_manager)
	_setup_scene()
	var sample_path := ProjectSettings.globalize_path("res://assets/splats/demo.ply")
	var result := _tool_manager.create_splat_node_from_path(sample_path)
	if result.get("ok", false):
		add_child(result["node"])
	else:
		push_warning(result.get("message", "Unknown splat load failure"))

func _setup_scene() -> void:
	_camera = Camera3D.new()
	_camera.look_at_from_position(Vector3(0.0, 0.0, 4.0), Vector3.ZERO)
	add_child(_camera)

	_world_environment = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.07, 0.09)
	_world_environment.environment = env
	add_child(_world_environment)
	_tool_manager.configure_world_environment(_world_environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	add_child(light)
