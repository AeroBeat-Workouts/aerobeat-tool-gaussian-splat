# AeroBeat Tool Gaussian Splat

**Date:** 2026-05-15  
**Status:** Complete  
**Agent:** Cookie 🍪

---

## Goal

Plan a refactor that makes Gaussian splat loading contract-safe for cross-repo reuse, so `aerobeat-environment-loader` can consume splat functionality through a core-style boundary instead of embedding a sibling repo’s public wrapper and colliding on Godot global class names.

---

## Overview

We just hit the exact design pressure that AeroBeat’s core/contract strategy is meant to solve. `aerobeat-environment-loader` successfully locked its request/result/progress contract, but its real `.compressed.ply` rendering path was blocked because directly embedding `aerobeat-environment-gaussian-splat` brought public Godot `class_name` globals such as `AeroToolManager` into the same runtime surface. Since GDScript has no namespaces, stacking sibling repo wrappers this way is brittle.

So the fix should not be “rename everything randomly” or “give up on reuse.” The right move is to apply the same architecture used elsewhere in AeroBeat: define the safe contract/core boundary, make the splat repo fulfill it, and have higher-level consumers depend on that contract-safe layer rather than the sibling repo’s public wrapper entrypoint.

This refactor likely touches at least `aerobeat-environment-gaussian-splat` and `aerobeat-environment-loader`, and Derrick has now chosen the pure AeroBeat architecture version: a real core contract boundary rather than relying on the subfolder-only fulfillment-package shortcut. The main job of this plan is therefore to document the migration path toward a contract->implementation split and break the work into implementation slices without regressing the already-landed environment and settings lanes.

---

## REFERENCES

| ID | Description | Path |
| --- | --- | --- |
| `REF-01` | Repo owning current Gaussian splat tool implementation | `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-gaussian-splat` |
| `REF-02` | Repo that needs to consume splat functionality safely | `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-loader` |
| `REF-03` | Parallel coordination plan showing the landed environment lane and shared contracts | `/home/derrick/Documents/projects/aerobeat/aerobeat-assembly-community/.plans/2026-05-15-parallel-lego-piece-implementation-coordination.md` |
| `REF-04` | Higher-level fallback/tool roadmap | `/home/derrick/Documents/projects/aerobeat/aerobeat-assembly-community/.plans/2026-05-15-default-environment-fallback-ladder.md` |
| `REF-05` | Environment lane plan documenting the current placeholder splat path | `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-loader/.plans/2026-05-15-environment-tool-first-implementation-lane.md` |
| `REF-06` | Existing content-core repo as an example of AeroBeat core-contract thinking | `/home/derrick/Documents/projects/aerobeat/aerobeat-content-core` |
| `REF-07` | Existing input-core repo as another example of AeroBeat core-contract thinking | `/home/derrick/Documents/projects/aerobeat/aerobeat-input-core` |

---

## Tasks

### Task 1: Inspect current splat repo structure and identify the exact unsafe boundary

**Bead ID:** `aerobeat-environment-gaussian-splat-63r`  
**SubAgent:** `primary` (for `research` workflow role)  
**Role:** `research`  
**References:** `REF-01`, `REF-02`, `REF-05`  
**Prompt:** Inspect `aerobeat-environment-gaussian-splat` and `aerobeat-environment-loader` to document the exact public wrapper classes, lower-level runtime classes, and addon/testbed loading paths that create the current cross-repo conflict. Identify which classes are safe lower-level dependencies already, which ones are public wrapper surfaces, and where the collision risk actually enters the runtime.

**Folders Created/Deleted/Modified:**
- Planning/docs only expected

**Files Created/Deleted/Modified:**
- Analysis notes only

**Status:** ✅ Complete

**Results:** Inspected both repos’ actual current surfaces. In `aerobeat-environment-gaussian-splat`, the published root currently exports four global `class_name` scripts from `src/`: `AeroToolManager`, `AeroGaussianSplatManager`, `AeroGaussianSplatBackgroundLoader`, and `AeroGaussianSplatBackgroundReadWorker`. The real rendering/decoding logic lives below that wrapper layer and depends on vendor GDGS scripts via `res://addons/gdgs/...`, while the wrapper `AeroToolManager` mostly forwards to `AeroGaussianSplatManager`. In `aerobeat-environment-loader`, the current `.compressed.ply` lane is still a structured placeholder inside its own wrapper `src/AeroToolManager.gd`, with progress semantics intentionally aligned to the splat repo. The exact unsafe boundary is therefore the splat repo’s **published wrapper package root**, not the lower-level decode/build logic: if a downstream repo installs that whole wrapper root to reuse real splat fulfillment, Godot registers the flat global script classes from that package into the same runtime namespace as the consumer’s own wrapper classes. Because GDScript has no namespaces, the collision risk enters at addon/package load time through the global script-class registry, with `AeroToolManager` being the clearest conflicting wrapper name and the extra helper globals (`AeroGaussianSplatManager`, `AeroGaussianSplatBackgroundLoader`, `AeroGaussianSplatBackgroundReadWorker`) also leaking more surface than downstream consumers actually need. Key finding: the reusable fulfillment logic already mostly exists, but it is currently shipped only behind a public wrapper boundary that is too broad and too global for sibling-repo composition.

---

### Task 2: Record the chosen pure core-contract refactor shape

**Bead ID:** `aerobeat-environment-gaussian-splat-2x5`  
**SubAgent:** `primary` (for `research` workflow role)  
**Role:** `research`  
**References:** `REF-01`, `REF-06`, `REF-07`  
**Prompt:** Record the chosen refactor shape for contract-safe splat reuse. The decision is now to use the pure AeroBeat architecture approach: define a real splat core contract boundary and have the gaussian-splat repo fulfill it, rather than relying on the subfolder-only fulfillment-package shortcut as the long-term answer. Update the plan to reflect why this fits AeroBeat’s existing core strategy best.

**Folders Created/Deleted/Modified:**
- Planning/docs only expected

**Files Created/Deleted/Modified:**
- Architecture notes only

**Status:** ✅ Complete

**Results:** Compared three shapes against AeroBeat’s existing core pattern. **Option A — create an explicit dependency-safe lower layer inside `aerobeat-environment-gaussian-splat` and keep the current repo root as the standalone wrapper package — is the recommended first move.** It is the smallest safe refactor because the reusable logic already exists in this repo; the problem is packaging/boundary exposure, not missing domain knowledge. The safe layer should be installable through its own package/subfolder entry so downstream repos can depend on real splat fulfillment without loading the wrapper repo’s global `AeroToolManager` surface. Option B — extracting a new dedicated `aerobeat-splat-core` repo now — would be cleaner only if multiple sibling repos were already blocked on the same fulfillment contract or if the lower layer were broad enough to merit independent versioning immediately. Right now that would add repo churn, release overhead, and migration risk before proving the boundary. Option C — ad-hoc renaming or keeping reuse at the wrapper level — does not fit AeroBeat’s architecture because it treats the symptom instead of isolating the contract/fulfillment seam. Why Option A best matches AeroBeat’s core strategy: it still applies the same core/contract thinking as `aerobeat-content-core` and `aerobeat-input-core`, but does so proportionally. First carve out the stable lower-level contract-safe fulfillment boundary where the code already lives; then, only if multiple consumers and release cadence justify it, extract that boundary into a dedicated core repo later. In short: **core-style boundary now, repo split later only if it earns its keep.**

---

### Task 3: Define the migration plan for `aerobeat-environment-gaussian-splat`

**Bead ID:** `aerobeat-environment-gaussian-splat-daw`  
**SubAgent:** `primary` (for `coder` workflow role)  
**Role:** `coder`  
**References:** `REF-01`  
**Prompt:** Based on the chosen refactor shape, define what needs to change in `aerobeat-environment-gaussian-splat`: which runtime classes stay public, which become dependency-safe lower-level fulfillment classes, what contract-facing APIs must be exposed, and how to preserve current standalone repo/testbed usefulness while enabling safer downstream consumption.

**Folders Created/Deleted/Modified:**
- Planning/docs only expected

**Files Created/Deleted/Modified:**
- Migration notes only

**Status:** ✅ Complete

**Results:** Recommended gaussian-splat migration shape: keep the **repo root** as the public standalone wrapper package, but add a **separate dependency-safe subpackage** inside the same repo for real fulfillment. Concretely, the public root keeps `src/AeroToolManager.gd` as the ergonomic wrapper entrypoint and may keep `AeroGaussianSplatManager` only if it truly serves standalone callers; however, the lower fulfillment layer should move to scripts that are loaded by path and **do not declare `class_name`**. That lower layer should own the existing real work: format detection, synchronous `.ply`/`.compressed.ply`/`.splat`/`.sog` decode-to-resource flow, background `.ply`/`.compressed.ply` flow, splat-node creation, and compositor configuration. The lower package should expose a narrow path-based API that is effectively today’s useful runtime surface — load resource, create node, begin background load/create, query progress, configure world environment — but without publishing wrapper-global names into downstream runtimes. The current wrapper should then become a thin adapter over that lower package rather than the only place where the fulfillment can be consumed. Packaging recommendation: give the safe layer its own installable subfolder/package root (for example under a dedicated `packages/` or `addons/` subtree) so GodotEnv consumers can target that subfolder directly instead of mounting the repo root. This matches other GodotEnv patterns in AeroBeat where the consumed `subfolder` is the truthful package boundary. Validation expectation for this repo later: existing standalone tests/scenes should keep passing through the wrapper path, and new repo-local coverage should prove that the wrapper is just delegating into the lower package rather than owning unique fulfillment behavior.

---

### Task 4: Define the migration plan for `aerobeat-environment-loader`

**Bead ID:** `aerobeat-environment-gaussian-splat-nj5`  
**SubAgent:** `primary` (for `coder` workflow role)  
**Role:** `coder`  
**References:** `REF-02`, `REF-05`  
**Prompt:** Define how `aerobeat-environment-loader` should switch from its current structured placeholder `.compressed.ply` path to the contract-safe splat fulfillment path. Capture what should remain unchanged in the environment request/result/progress contract, what dependency boundary should be adopted, and how to migrate the hidden testbed without breaking the already-landed environment lane.

**Folders Created/Deleted/Modified:**
- Planning/docs only expected

**Files Created/Deleted/Modified:**
- Migration notes only

**Status:** ✅ Complete

**Results:** Recommended environment migration: keep the current environment-facing contract exactly where possible — same `load_environment(request)` API, same request/result/error shapes, same `.compressed.ply` official format rule, and same progress/status vocabulary (`resolving`, `loading`, `decoding`, `instantiating`, `applying_config`, `ready`). Only the internal splat fulfillment should change. Instead of the current placeholder path in `src/AeroToolManager.gd`, the repo should install the new gaussian-splat **lower subpackage** plus its pinned `gdgs` dependency into `.testbed/addons.jsonc`, preload the lower runtime by explicit addon path, and translate its real background-load status into the existing environment progress contract. The environment wrapper should remain the owner of environment-specific concerns: request normalization, official format gating, sidecar config discovery/application, world-root attachment, and result metadata. The splat runtime should become an implementation detail used only inside `_load_splat(...)`. That means `_load_splat(...)` should: resolve/validate path, create or reuse the lower runtime instance, start real node/resource creation for `.compressed.ply`, bridge runtime progress into environment progress, attach the returned splat node to `_world_root`, apply the environment sidecar transform, and keep result payload fields stable. The hidden `.testbed` should then swap from proving a placeholder node to proving an actual rendered splat path while preserving the same UI/test surface. Important migration constraint: do not make `aerobeat-environment-loader` depend on the gaussian-splat repo root package or its `AeroToolManager`; depend only on the new safe lower package so the environment lane stays generic-first and collision-free.

---

### Task 5: Produce the implementation roadmap for the refactor

**Bead ID:** `aerobeat-environment-gaussian-splat-2lu`  
**SubAgent:** `primary` (for `auditor` workflow role)  
**Role:** `auditor`  
**References:** `REF-01`, `REF-02`, `REF-03`, `REF-04`  
**Prompt:** Turn the research into a practical implementation roadmap: repo order, validation order, risk points, and the smallest first coding slice that will unlock real splat rendering in `aerobeat-environment-loader` without destabilizing the already-landed lanes. Include explicit notes on how to keep public wrapper ergonomics while moving reuse to a core-safe boundary.

**Folders Created/Deleted/Modified:**
- Planning/docs only expected

**Files Created/Deleted/Modified:**
- Final plan updates only

**Status:** ✅ Complete

**Results:** Recommended implementation roadmap:
1. **Gaussian-splat repo first:** carve out the new lower package inside `aerobeat-environment-gaussian-splat`, move the reusable fulfillment logic behind path-based scripts with no `class_name`, and rewire the repo-root wrapper to delegate to that layer without changing its public API.
2. **Validate gaussian-splat in isolation:** rerun its existing import smoke/GUT coverage and add focused coverage that proves wrapper delegation, supported format behavior, background progress semantics, and compositor configuration still work through the wrapper.
3. **Environment repo second:** add the new gaussian-splat lower package entry plus `gdgs` to `.testbed/addons.jsonc`, replace the placeholder `_load_splat(...)` branch with real runtime consumption, and keep the environment-facing contract unchanged.
4. **Validate environment in isolation:** rerun the existing `.testbed` import + GUT suite and manually confirm the hidden environment testbed now renders a real `.compressed.ply` scene while preserving sidecar transforms and progress/status messaging.
5. **Only after that, consider wider assembly integration:** not part of this slice unless a separate plan later says to do it.

Smallest safe first coding slice: **in `aerobeat-environment-gaussian-splat`, introduce the lower installable fulfillment package and convert the current repo-root wrapper to use it without changing wrapper callers yet.** That single slice proves the new boundary while keeping blast radius inside one repo. Once that lands, the follow-up slice in `aerobeat-environment-loader` is a relatively contained placeholder swap rather than a simultaneous architectural rewrite. Main risk points to watch later: ensuring the lower package exposes a stable path layout for GodotEnv `subfolder` installs, keeping wrapper and lower-layer progress semantics aligned so environment translation stays simple, preserving vendor `gdgs` path expectations, and avoiding accidental reintroduction of global `class_name` declarations inside the reusable layer.

---


## Direction Update

Derrick approved the **pure AeroBeat architecture** version for splats:

- prefer a real contract/core boundary
- keep contract and implementation roles explicit
- avoid depending on sibling tool public wrappers as the long-term composition answer
- treat the subfolder fulfillment-package idea as a useful tactical trick, but not the final architectural destination

This means the next planning/execution should pivot from "internal lower package only" toward "core contract + gaussian-splat fulfillment + downstream consumer adoption".

## Design Direction To Evaluate

What we already know:
- GDScript has no namespaces.
- Repeated public `class_name AeroToolManager` wrappers are fine for standalone repos but hazardous when sibling repos embed each other directly.
- AeroBeat already solves similar composition problems through core/contract boundaries in other areas.

So the likely winning pattern is:
- preserve public wrapper ergonomics for standalone use
- move reusable fulfillment behind a dependency-safe contract/core layer
- have sibling repos consume that lower-level contract-safe layer rather than another repo’s wrapper root

Chosen architectural direction:
- create a real splat core contract boundary in AeroBeat style
- have `aerobeat-environment-gaussian-splat` fulfill that contract
- have downstream consumers such as `aerobeat-environment-loader` consume the contract/implementation path rather than the sibling wrapper root

The remaining design question is narrower now: whether the new core contract should live in a dedicated new splat-core repo or in an existing appropriate core repo boundary.

---

## Non-Goals For This Plan

- no code changes yet
- no renaming spree just to dodge the symptom
- no `assembly-community` integration work
- no changes to the already-landed tool-settings or camera-gesture-control lanes unless strictly needed later
- do not treat the previously landed subfolder fulfillment package as the final architecture; it may remain a temporary implementation aid, but the target design is the contract->implementation split

---

## Final Results

**Status:** ✅ Complete

**What We Built:** A completed refactor plan for making Gaussian splat fulfillment contract-safe for sibling reuse without breaking standalone wrapper ergonomics. The plan identifies the exact unsafe boundary, recommends the smallest safe architecture, defines repo-specific migration steps for both gaussian-splat and environment, and sequences the work into a practical implementation roadmap.

**Reference Check:** `REF-01` and `REF-02` were inspected directly at code/package level. `REF-05` confirmed the environment repo’s current placeholder `.compressed.ply` path and aligned progress semantics. `REF-06` and `REF-07` confirmed the broader AeroBeat pattern: shared/core boundaries should own reusable contracts while higher-level wrappers stay focused and ergonomic. Deliberate recommendation: apply that strategy proportionally by first creating the safe lower package *inside* `aerobeat-environment-gaussian-splat`, not by forcing an immediate new repo split.

**Commits:**
- Pending repo commit for this planning update.

**Lessons Learned:** The problem is not splat decoding itself; it is package-boundary leakage. AeroBeat’s core strategy still fits best here, but the first winning move is an internal lower package boundary rather than a premature repo explosion.

---

*Completed on 2026-05-15*
