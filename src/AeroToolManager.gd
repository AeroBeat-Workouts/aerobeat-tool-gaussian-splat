class_name AeroToolManager
extends Node

signal initialized
signal background_load_started(result)
signal background_load_progressed(result)
signal background_load_finished(result)

const VERSION: String = "0.0.1"
const GaussianManagerScript = preload("AeroGaussianSplatManager.gd")
const GaussianFulfillmentScript = preload("AeroGaussianSplatEnvironmentFulfillment.gd")

@export var is_active: bool = true

var _is_initialized: bool = false
var _gaussian_manager: AeroGaussianSplatManager
var _gaussian_fulfillment: AeroGaussianSplatEnvironmentFulfillment

func _ready() -> void:
	_initialize()

func _initialize() -> void:
	if _is_initialized:
		return
	_gaussian_manager = GaussianManagerScript.new()
	add_child(_gaussian_manager)
	_gaussian_fulfillment = GaussianFulfillmentScript.new(_gaussian_manager)
	_gaussian_manager.background_load_started.connect(func(result): background_load_started.emit(result))
	_gaussian_manager.background_load_progressed.connect(func(result): background_load_progressed.emit(result))
	_gaussian_manager.background_load_finished.connect(func(result): background_load_finished.emit(result))
	_is_initialized = true
	initialized.emit()

func get_supported_extensions() -> PackedStringArray:
	_initialize()
	return _gaussian_manager.get_supported_extensions()

func get_renderer_support_status() -> Dictionary:
	_initialize()
	return _gaussian_manager.get_renderer_support_status()

func load_gaussian_resource_from_path(asset_path: String) -> Dictionary:
	_initialize()
	return _gaussian_manager.load_gaussian_resource_from_path(asset_path)

func create_splat_node_from_path(asset_path: String) -> Dictionary:
	_initialize()
	return _gaussian_manager.create_splat_node_from_path(asset_path)

func begin_load_gaussian_resource_from_path(asset_path: String) -> Dictionary:
	_initialize()
	return _gaussian_manager.begin_load_gaussian_resource_from_path(asset_path)

func begin_create_splat_node_from_path(asset_path: String) -> Dictionary:
	_initialize()
	return _gaussian_manager.begin_create_splat_node_from_path(asset_path)

func is_background_load_in_progress() -> bool:
	_initialize()
	return _gaussian_manager.is_background_load_in_progress()

func get_background_load_status() -> Dictionary:
	_initialize()
	return _gaussian_manager.get_background_load_status()

func configure_world_environment(world_environment: WorldEnvironment) -> void:
	_initialize()
	_gaussian_manager.configure_world_environment(world_environment)

func get_environment_fulfillment() -> AeroGaussianSplatEnvironmentFulfillment:
	_initialize()
	return _gaussian_fulfillment

func supports_environment_kind(kind: String) -> bool:
	_initialize()
	return _gaussian_fulfillment.supports_kind(kind)

func fulfill_environment_request(request: Variant) -> Variant:
	_initialize()
	return _gaussian_fulfillment.fulfill(request)

func begin_fulfill_environment_request(request: Variant) -> Variant:
	_initialize()
	return _gaussian_fulfillment.begin_fulfill(request)

func begin_fulfill(request: Variant) -> Variant:
	return begin_fulfill_environment_request(request)

func supports_async() -> bool:
	_initialize()
	return _gaussian_fulfillment.supports_async()

func fulfill(request: Variant) -> Variant:
	return fulfill_environment_request(request)
