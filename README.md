# AeroBeat Tool - Gaussian Splat

`aerobeat-tool-gaussian-splat` is the AeroBeat-facing runtime/tool wrapper for Gaussian
splat loading.

## Boundary

- This repo exposes the stable AeroBeat API from `src/`.
- It depends on the pinned vendor payload in `aerobeat-vendor-gdgs`.
- Downstream product/testbed repos should talk to this repo instead of loading the
  third-party decoders directly.

## Current runtime surface

`AeroGaussianSplatManager` can:

- detect supported splat formats by extension
- load `.ply`, `.compressed.ply`, `.splat`, and `.sog` files from **absolute/local paths**
- create a `GaussianSplatNode` with an in-memory `GaussianResource`
- configure a `WorldEnvironment` with the gdgs compositor effect
- report basic debug metadata such as `point_count`, `aabb`, and detected format

`AeroToolManager` currently mirrors that surface so it can be used as a future
autoload/singleton entry point without changing call sites.

## GodotEnv development flow

From the repo root:

```bash
cd .testbed
godotenv addons install
godot --headless --path . --import
godot --headless --path . --script addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

## `.testbed` contents

- `assets/splats/` - local sample splat payloads for loader validation
- `scenes/splat_loader_smoke.tscn` - direct runtime smoke scene
- `scripts/splat_loader_smoke.gd` - test scene logic
- `tests/` - repo-local unit tests

## Runtime use

```gdscript
var manager := AeroGaussianSplatManager.new()
var result := manager.create_splat_node_from_path("/absolute/path/to/scene.ply")
if result.ok:
    add_child(result.node)
```
