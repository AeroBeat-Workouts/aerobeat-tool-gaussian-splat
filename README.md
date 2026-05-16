# AeroBeat Environment - Gaussian Splat

`aerobeat-environment-gaussian-splat` is the AeroBeat-facing Gaussian splat fulfillment repo.
Its repo-root wrapper now adapts into the shared `aerobeat-environment-core` contract while the
real reusable decode/load/build/background/compositor runtime stays in the lower fulfillment
package.

## Boundary

- This repo exposes the stable AeroBeat wrapper API from `src/` for standalone use.
- The repo-root wrapper now also exposes a contract-facing fulfillment adapter that depends on `aerobeat-environment-core` for request/result/error/config vocabulary.
- The real reusable fulfillment runtime still lives in the dependency-safe lower package at `addons/aerobeat-environment-gaussian-splat-fulfillment/`.
- It depends on the pinned vendor payload in `aerobeat-vendor-gdgs`.
- Downstream product/testbed repos should depend on this repo for splat-specific fulfillment instead of loading the third-party decoders directly.
- Sibling repos that need the real splat fulfillment logic **without** wrapper-global `class_name` collisions should depend on the lower package subfolder rather than the repo root wrapper package.
- Consumer projects that use the contract-facing adapter must also install `aerobeat-environment-core` at `res://addons/aerobeat-environment-core`.

## Current runtime surface

`AeroGaussianSplatManager` can:

- detect supported splat formats by extension
- load `.ply`, `.compressed.ply`, `.splat`, and `.sog` files from **absolute/local paths**
- create a `GaussianSplatNode` with an in-memory `GaussianResource`
- start a background-threaded load via `begin_load_gaussian_resource_from_path()` or `begin_create_splat_node_from_path()` and emit `background_load_started` / `background_load_progressed` / `background_load_finished`; background loading currently supports only `.ply` and `.compressed.ply`, while `.splat` and `.sog` still use the existing synchronous path
- report renderer-path support truth via `get_renderer_support_status()` so downstream UI can avoid overclaiming visible render support
- configure a `WorldEnvironment` with the gdgs compositor effect only when the current renderer exposes the required `RenderingDevice` path
- report basic debug metadata such as `point_count`, `aabb`, and detected format

`AeroToolManager` currently mirrors that surface so it can be used as a future
autoload/singleton entry point without changing call sites.

`AeroGaussianSplatEnvironmentFulfillment` / `AeroToolManager.fulfill_environment_request()` can:

- accept either a `Dictionary` request or a typed `AeroEnvironmentRequest`
- validate against the shared `aerobeat-environment-core` `.compressed.ply` contract
- return a typed `AeroEnvironmentResult` on success or `AeroEnvironmentError` on failure
- keep the loaded `node`, `resource`, `point_count`, and config payload in `result.details`
- optionally apply JSON sidecar config and configure a provided `WorldEnvironment`

`AeroGaussianSplatEnvironmentFulfillment.begin_fulfill()` / `AeroToolManager.begin_fulfill()` now add the async contract path on top of that sync surface:

- they keep the existing sync `fulfill()` behavior intact for compatibility
- they wrap lower-runtime `background_load_started` / `background_load_progressed` / `background_load_finished` dictionaries into typed operation progress/result/error updates
- they use shared contract `status` values for cross-kind stages while preserving splat-specific detail in `phase`
- they perform config application and optional `WorldEnvironment` compositor wiring after the background decode/build step completes
- they do **not** overclaim the known renderer/compositor bug as solved; async plumbing is complete even though stable visible render validation is still partially blocked

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

Standalone/public wrapper path:

```gdscript
var manager := AeroGaussianSplatManager.new()
var result := manager.create_splat_node_from_path("/absolute/path/to/scene.ply")
if result.ok:
    add_child(result.node)
```

Contract-facing fulfillment adapter path:

```gdscript
const AeroEnvironmentRequest := preload("res://addons/aerobeat-environment-core/src/contracts/data_types/environment_request.gd")

var fulfillment := AeroGaussianSplatEnvironmentFulfillment.new()
var result = fulfillment.fulfill(AeroEnvironmentRequest.new({
    "request_id": "req-1",
    "kind": "splat",
    "asset_path": "/absolute/path/to/scene.compressed.ply"
}))
if result is AeroEnvironmentResult and result.ok:
    add_child(result.details["node"])
```

Async contract-facing adapter path:

```gdscript
var operation = fulfillment.begin_fulfill(AeroEnvironmentRequest.new({
    "request_id": "req-async-1",
    "kind": "splat",
    "asset_path": "/absolute/path/to/scene.compressed.ply"
}))
operation.progressed.connect(func(progress):
    var snapshot := progress.to_dict()
    print("%s / %s: %0.1f%%" % [snapshot.get("status", ""), snapshot.get("phase", ""), float(snapshot.get("progress", 0.0)) * 100.0])
)
operation.finished.connect(func(_op):
    if operation.result != null and operation.result.ok:
        add_child(operation.result.details["node"])
)
```

Dependency-safe lower-package path for sibling consumers:

```gdscript
const GaussianSplatRuntime := preload("res://addons/aerobeat-environment-gaussian-splat-fulfillment/runtime/gaussian_splat_runtime.gd")

var runtime = GaussianSplatRuntime.new()
var result := runtime.create_splat_node_from_path("/absolute/path/to/scene.ply")
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

Renderer-path truth:

- `get_renderer_support_status()` is the stable way to ask whether the current renderer path can even attempt visible splat output.
- Renderer paths without a `RenderingDevice` backend should be treated as **unsupported for visible splat rendering**; the wrapper will not attach the gdgs compositor there.
- Renderer paths with a `RenderingDevice` are still currently reported as **experimental** until the visible render path is validated end-to-end on that backend/hardware combination.
- In the current validation slice, Forward+ / Vulkan has reproduced compositor-side crashes after successful load, so downstream UI should avoid claiming stable visible output there yet.

Progress semantics for async loads:

- `background_load_started` returns `pending = true` with `progress = 0.0`.
- `background_load_progressed` is emitted while work is still pending; its `progress` value stays below `1.0` until the load is actually complete.
- `background_load_finished` is the only success payload that reports `pending = false`, `phase = "ready"`, `status = "Ready"`, and `progress = 1.0`.
- Unsupported async formats (`.splat`, `.sog`) should continue to use the synchronous compatibility path in downstream UI.
