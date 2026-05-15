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
- start a background-threaded load via `begin_load_gaussian_resource_from_path()` or `begin_create_splat_node_from_path()` and emit `background_load_started` / `background_load_progressed` / `background_load_finished`; background loading currently supports only `.ply` and `.compressed.ply`, while `.splat` and `.sog` still use the existing synchronous path
- configure a `WorldEnvironment` with the gdgs compositor effect
- report basic debug metadata such as `point_count`, `aabb`, and detected format

`AeroToolManager` currently mirrors that surface so it can be used as a future
autoload/singleton entry point without changing call sites.

## GodotEnv development flow

From the repo root:

```bash
./scripts/restore-testbed-addons.sh
cd .testbed
godot --headless --path . --import
godot --headless --path . --script addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

## Clean restore flow for GodotEnv-managed addons

If Godot-generated imports make an installed addon look dirty, use the canonical
repo-local restore flow instead of manually deleting folders by hand:

```bash
./scripts/restore-testbed-addons.sh
```

That script clears the generated install targets first:

- `.testbed/addons/*` except `.editorconfig`
- `.testbed/.addons/`

Then it reruns `godotenv addons install` so the wrapper testbed comes back in a
known-clean state.

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

```gdscript
var manager := AeroGaussianSplatManager.new()
manager.background_load_progressed.connect(func(result):
    if result.pending:
        print("%s: %0.1f%%" % [result.status, result.progress * 100.0])
)
manager.background_load_finished.connect(func(result):
    if result.ok:
        add_child(result.node)
)
manager.begin_create_splat_node_from_path("/absolute/path/to/scene.compressed.ply")
```

Background loading is currently limited to `.ply` and `.compressed.ply`. Use the existing synchronous load/create calls for `.splat` and `.sog` assets.

Progress semantics for async loads:

- `background_load_started` returns `pending = true` with `progress = 0.0`.
- `background_load_progressed` is emitted while work is still pending; its `progress` value stays below `1.0` until the load is actually complete.
- `background_load_finished` is the only success payload that reports `pending = false`, `phase = "ready"`, `status = "Ready"`, and `progress = 1.0`.
- Unsupported async formats (`.splat`, `.sog`) should continue to use the synchronous compatibility path in downstream UI.
