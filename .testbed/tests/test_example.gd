extends GutTest

func test_readme_mentions_absolute_local_path_support() -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path("res://../README.md"), FileAccess.READ)
	assert_true(file != null, "README should exist")
	var text := file.get_as_text()
	assert_true(text.contains("absolute/local paths"), "README should document absolute/local path loading")
	assert_true(text.contains("get_renderer_support_status()"), "README should document renderer support status introspection")
	assert_true(text.contains("Forward+ / Vulkan has reproduced compositor-side crashes"), "README should truth-lock the current Forward+ / Vulkan status")
