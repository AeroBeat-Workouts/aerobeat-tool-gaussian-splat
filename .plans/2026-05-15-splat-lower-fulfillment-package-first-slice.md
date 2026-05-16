# AeroBeat Tool Gaussian Splat

**Date:** 2026-05-15  
**Status:** Complete  
**Agent:** Cookie 🍪

---

## Goal

Implement the first refactor slice that makes Gaussian splat fulfillment dependency-safe: introduce a lower reusable fulfillment package inside `aerobeat-environment-gaussian-splat`, rewire the public wrapper to use it, and validate that standalone wrapper behavior still works.

---

## Overview

The planning pass established that the main conflict is not splat rendering itself, but the current packaging boundary. `aerobeat-environment-gaussian-splat` exposes public global `class_name` symbols such as `AeroToolManager`, which is fine for standalone use but unsafe when a sibling tool repo wants to embed that wrapper into the same Godot runtime.

So this first implementation slice should not touch `aerobeat-environment-loader` yet. Instead, it should focus on `aerobeat-environment-gaussian-splat` alone and create the dependency-safe lower layer that later consumers can use by script path without importing wrapper globals. The current repo root wrapper should remain ergonomic and public, but it should delegate into the lower fulfillment package so we preserve existing behavior while unlocking safer cross-repo composition.

This slice succeeds if we end with:
- a lower installable fulfillment package/subfolder inside the splat repo
- wrapper parity still intact through `src/AeroToolManager.gd`
- repo-local validation proving the wrapper still works
- enough structure that `aerobeat-environment-loader` can later swap from placeholder `.compressed.ply` handling to the new lower boundary with minimal churn

---

## REFERENCES

| ID | Description | Path |
| --- | --- | --- |
| `REF-01` | Current splat core-boundary refactor plan | `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-gaussian-splat/.plans/2026-05-15-splat-core-boundary-refactor.md` |
| `REF-02` | Current splat repo runtime surface | `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-gaussian-splat/src/` |
| `REF-03` | Current hidden splat repo testbed | `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-gaussian-splat/.testbed/` |
| `REF-04` | Environment lane plan that will later consume the safe boundary | `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-loader/.plans/2026-05-15-environment-tool-first-implementation-lane.md` |

---

## Tasks

### Task 1: Inspect current runtime structure and lock the lower-package shape

**Bead ID:** `aerobeat-environment-gaussian-splat-ef6`  
**SubAgent:** `primary` (for `research` workflow role)  
**Role:** `research`  
**References:** `REF-01`, `REF-02`, `REF-03`  
**Prompt:** In repo `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-gaussian-splat`, claim the assigned bead and inspect the current runtime/testbed structure. Lock the first-slice lower-package shape: where the dependency-safe fulfillment package should live, which scripts move into it or delegate through it, what should remain public in `src/`, and how wrapper parity will be preserved.

**Folders Created/Deleted/Modified:**
- `addons/aerobeat-environment-gaussian-splat-fulfillment/` (planned lower package root)

**Files Created/Deleted/Modified:**
- `.plans/2026-05-15-splat-lower-fulfillment-package-first-slice.md`

**Status:** ✅ Complete

**Results:** Inspected the current wrapper/runtime split and locked the first-slice lower-package shape. The new dependency-safe fulfillment boundary will live under `addons/aerobeat-environment-gaussian-splat-fulfillment/` so later GodotEnv consumers can target that exact `subfolder` instead of mounting the repo root. The lower package will expose path-loadable runtime scripts with **no `class_name` declarations**: a primary runtime surface plus the background loader/read-worker helpers it already depends on. The public repo-root wrapper in `src/` will stay in place for standalone ergonomics, but it will be rewritten to delegate into or inherit from those lower scripts rather than owning unique fulfillment logic. Wrapper parity will be preserved by keeping the current method/signal surface stable (`AeroToolManager` -> `AeroGaussianSplatManager`) and validating both wrapper behavior and direct lower-path access in the repo-local testbed/tests.

---

### Task 2: Implement the lower fulfillment package/subfolder

**Bead ID:** `aerobeat-environment-gaussian-splat-q4l`  
**SubAgent:** `primary` (for `coder` workflow role)  
**Role:** `coder`  
**References:** `REF-01`, `REF-02`  
**Prompt:** In repo `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-gaussian-splat`, claim the assigned bead and implement the dependency-safe lower fulfillment package/subfolder. Move or mirror the real reusable splat decode/load/build logic there so it can be consumed later by script path without exposing wrapper-global `class_name` collisions. Avoid unnecessary API churn.

**Folders Created/Deleted/Modified:**
- `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-gaussian-splat/addons/aerobeat-environment-gaussian-splat-fulfillment/`
- `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-gaussian-splat/src/`

**Files Created/Deleted/Modified:**
- `addons/aerobeat-environment-gaussian-splat-fulfillment/README.md`
- `addons/aerobeat-environment-gaussian-splat-fulfillment/runtime/gaussian_splat_runtime.gd`
- `addons/aerobeat-environment-gaussian-splat-fulfillment/runtime/gaussian_splat_background_loader.gd`
- `addons/aerobeat-environment-gaussian-splat-fulfillment/runtime/gaussian_splat_background_read_worker.gd`

**Status:** ✅ Complete

**Results:** Added the lower fulfillment package at `addons/aerobeat-environment-gaussian-splat-fulfillment/` with a stable path-loadable runtime entrypoint and helper scripts, all without `class_name` declarations. The lower runtime now owns the real reusable decode/load/build/background/compositor behavior, while a package-local README documents the intended downstream GodotEnv shape: install this repo with `subfolder: "/addons/aerobeat-environment-gaussian-splat-fulfillment"` and preload `runtime/gaussian_splat_runtime.gd` directly. This preserves the first-slice boundary goal without forcing a broader repo split.

---

### Task 3: Rewire the public wrapper to delegate into the lower layer

**Bead ID:** `aerobeat-environment-gaussian-splat-y59`  
**SubAgent:** `primary` (for `coder` workflow role)  
**Role:** `coder`  
**References:** `REF-02`, `REF-03`  
**Prompt:** In repo `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-gaussian-splat`, claim the assigned bead and update the current public wrapper surface (`src/AeroToolManager.gd` and any related wrapper entrypoints) so it delegates into the new lower fulfillment layer while preserving the existing standalone contract as closely as practical.

**Folders Created/Deleted/Modified:**
- `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-gaussian-splat/src/`
- `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-gaussian-splat/.testbed/`

**Files Created/Deleted/Modified:**
- `src/AeroGaussianSplatManager.gd`
- `src/AeroGaussianSplatBackgroundLoader.gd`
- `src/AeroGaussianSplatBackgroundReadWorker.gd`
- `README.md`
- `.testbed/addons.jsonc`

**Status:** ✅ Complete

**Results:** Rewired the public wrapper layer so `src/AeroGaussianSplatManager.gd` now inherits the lower runtime directly, and the two helper wrapper scripts now inherit their lower helper counterparts. That keeps the standalone/public `class_name` ergonomics intact while moving the real implementation to the lower package. The testbed manifest now installs the lower fulfillment package via a repo-local symlinked addon entry, which proves the exact downstream package shape the environment repo should adopt later. README boundary/runtime docs were updated to describe both wrapper use and lower-package use.

---

### Task 4: Validate wrapper parity and lower-layer safety

**Bead ID:** `aerobeat-environment-gaussian-splat-u4e`  
**SubAgent:** `primary` (for `qa` workflow role)  
**Role:** `qa`  
**References:** `REF-02`, `REF-03`  
**Prompt:** In repo `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-gaussian-splat`, claim the assigned bead and run/add repo-local validation to prove wrapper parity still holds after the refactor. Confirm the hidden testbed still works, current tests still pass or are updated appropriately, and the repo is ready for later downstream consumption by script-path lower-layer dependency.

**Folders Created/Deleted/Modified:**
- `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-gaussian-splat/.testbed/`

**Files Created/Deleted/Modified:**
- `.testbed/addons.jsonc`
- `.testbed/tests/test_AeroToolManager.gd`

**Status:** ✅ Complete

**Results:** Added lower-layer coverage and reran repo-local validation end-to-end. The testbed now installs the lower package exactly like a downstream consumer would, and the updated GUT suite proves both wrapper parity and direct lower-runtime access. Validation passed with: `./scripts/restore-testbed-addons.sh`, `godot --headless --path .testbed --import`, `godot --headless --path .testbed --script addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` (`9/9` passing tests), and `godot --headless --path .testbed --scene res://scenes/splat_loader_smoke.tscn --quit-after 2` (clean exit). One non-blocking Godot shutdown warning about leaked `ObjectDB` instances still appears after the passing GUT run; it did not fail the suite and looks consistent with existing runtime/editor cleanup noise rather than a slice-specific functional break.

---

### Task 5: Audit the slice and record the next handoff to environment

**Bead ID:** `aerobeat-environment-gaussian-splat-21r`  
**SubAgent:** `primary` (for `auditor` workflow role)  
**Role:** `auditor`  
**References:** `REF-01`, `REF-04`  
**Prompt:** In repo `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-gaussian-splat`, claim the assigned bead and audit the slice. Confirm the lower fulfillment boundary now exists, public wrapper ergonomics were preserved, and the plan clearly states the next contained follow-up slice for `aerobeat-environment-loader` to adopt the new boundary.

**Folders Created/Deleted/Modified:**
- `/home/derrick/Documents/projects/aerobeat/aerobeat-environment-gaussian-splat/.plans/`

**Files Created/Deleted/Modified:**
- `.plans/2026-05-15-splat-lower-fulfillment-package-first-slice.md`

**Status:** ✅ Complete

**Results:** Audited the implementation against the plan and repo diff. The lower fulfillment boundary now exists as a real installable subfolder, the public wrapper contract still resolves through `src/` without forcing callers to change usage, and repo-local validation proves both wrapper parity and direct lower-path consumption. Clean handoff for `aerobeat-environment-loader`: install this repo with `subfolder: "/addons/aerobeat-environment-gaussian-splat-fulfillment"` plus the existing `gdgs` dependency, preload `res://addons/aerobeat-environment-gaussian-splat-fulfillment/runtime/gaussian_splat_runtime.gd`, and keep the environment-facing request/result/progress contract unchanged while replacing only the placeholder splat fulfillment internals.

---

## Desired End State For This Slice

After this slice:
- standalone consumers can still use the wrapper as before
- sibling repos do not need to import the wrapper root to reuse the real splat fulfillment logic
- `aerobeat-environment-loader` can later target the lower package directly
- no new repo extraction is required yet

---

## Non-Goals For This Slice

- no `aerobeat-environment-loader` code changes yet
- no `assembly-community` work
- no broad rename pass across AeroBeat
- no new dedicated splat-core repo unless this slice proves the internal lower-package approach is insufficient

---

## Superseded Direction Note

This implementation slice landed successfully as a packaging-boundary improvement, but Derrick has now chosen the **pure AeroBeat architecture** follow-up: move toward a real splat core contract and contract->implementation split as the long-term design, instead of treating the lower fulfillment package as the final boundary.

## Final Results

**Status:** ✅ Complete

**What We Built:** The first lower-boundary refactor slice is now implemented inside `aerobeat-environment-gaussian-splat`. The repo contains a new dependency-safe lower fulfillment package at `addons/aerobeat-environment-gaussian-splat-fulfillment/` with a path-loadable runtime entrypoint and helper scripts that intentionally avoid `class_name` registration. The public wrapper layer in `src/` now delegates to that lower package through inheritance, preserving standalone ergonomics while separating reusable fulfillment from wrapper-global names.

**Reference Check:** `REF-01` satisfied: this slice follows the planned “lower package first” strategy instead of forcing a repo split. `REF-02` satisfied: the current splat runtime surface remains available through `src/` while the real logic moved behind the lower package boundary. `REF-03` satisfied: the hidden testbed now installs and exercises the lower package directly while preserving wrapper tests. `REF-04` satisfied as a handoff note: the next environment slice should depend on the lower package subfolder plus `gdgs`, preload the lower runtime by path, and keep the environment-facing contract stable while swapping out placeholder fulfillment internals.

**Commits:**
- Pending final repo commit.

**Lessons Learned:** The safest first move really was to fix the packaging boundary in the splat repo itself before touching downstream consumers. Installing the lower package in the local testbed the same way a sibling repo would consume it gave us much stronger proof than only refactoring `src/` in place.

---

*Completed on 2026-05-15*
