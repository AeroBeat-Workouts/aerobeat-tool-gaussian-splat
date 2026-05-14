extends GutTest

func test_readme_mentions_absolute_local_path_support() -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path("res://../README.md"), FileAccess.READ)
	assert_true(file != null, "README should exist")
	var text := file.get_as_text()
	assert_true(text.contains("absolute/local paths"), "README should document absolute/local path loading")
