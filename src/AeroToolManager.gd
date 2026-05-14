class_name AeroToolManager
extends Node

signal initialized

const VERSION: String = "0.0.1"
const GaussianManagerScript = preload("AeroGaussianSplatManager.gd")

@export var is_active: bool = true

var _is_initialized: bool = false
var _gaussian_manager: AeroGaussianSplatManager

func _ready() -> void:
	_initialize()

func _initialize() -> void:
	if _is_initialized:
		return
	_gaussian_manager = GaussianManagerScript.new()
	add_child(_gaussian_manager)
	_is_initialized = true
	initialized.emit()

func get_supported_extensions() -> PackedStringArray:
	_initialize()
	return _gaussian_manager.get_supported_extensions()

func load_gaussian_resource_from_path(asset_path: String) -> Dictionary:
	_initialize()
	return _gaussian_manager.load_gaussian_resource_from_path(asset_path)

func create_splat_node_from_path(asset_path: String) -> Dictionary:
	_initialize()
	return _gaussian_manager.create_splat_node_from_path(asset_path)

func configure_world_environment(world_environment: WorldEnvironment) -> void:
	_initialize()
	_gaussian_manager.configure_world_environment(world_environment)
