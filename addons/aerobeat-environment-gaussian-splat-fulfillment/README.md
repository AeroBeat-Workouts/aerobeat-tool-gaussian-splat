# AeroBeat Gaussian Splat Fulfillment Package

This subfolder is the dependency-safe lower runtime package for `aerobeat-environment-gaussian-splat`.

## Why it exists

The repo root publishes standalone wrapper globals from `src/` such as `AeroToolManager`.
Those are ergonomic for direct use, but sibling repos should not import that wrapper package
just to reuse the real splat fulfillment logic because GDScript global `class_name` symbols are
flat and can collide.

This lower package keeps the reusable runtime path-loadable instead:

- no `class_name` declarations
- stable script-path entrypoint
- same real decode/load/build/background/compositor behavior as the wrapper layer

## Intended GodotEnv consumption

Point downstream consumers at this repo's subfolder:

- `subfolder: "/addons/aerobeat-environment-gaussian-splat-fulfillment"`

Then preload the runtime by path:

```gdscript
const GaussianSplatRuntime := preload("res://addons/aerobeat-environment-gaussian-splat-fulfillment/runtime/gaussian_splat_runtime.gd")
```
