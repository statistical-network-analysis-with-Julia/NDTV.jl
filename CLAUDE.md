# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NDTV.jl is a Julia port of the R `ndtv` package (from the StatNet suite) that provides tools for visualizing dynamic (time-varying) networks through animations, timeline plots, filmstrip displays, and layout algorithms. It operates on `DynamicNetwork` objects from the sibling `NetworkDynamic.jl` package.

## Development Commands

- **Run tests:** `julia --project -e 'using Pkg; Pkg.test()'`
- **Load package:** `julia --project -e 'using NDTV'`
- **Build docs:** `julia --project=docs docs/make.jl`
- **Activate environment:** `julia --project` (uses local `Project.toml`)

Note: This package depends on local sibling packages `Network` and `NetworkDynamic` via relative path sources (`../Network`, `../NetworkDynamic`). These must be present alongside this repo.

## Architecture

The entire package lives in a single file: `src/NDTV.jl`. It is organized into these sections (in order):

1. **Layout Types** — `DynamicLayout{T, Time}` (positions + times + bounds + per-frame active vertices/edges; generic over NetworkDynamic time types incl. DateTime) and `InterpolatedLayout{T, Time}` (linear/ease interpolation). ALL position dictionaries are keyed by STABLE vertex IDs: snapshots are taken with `network_extract(...; retain_all_vertices=true)`, so anchoring/interpolation match real identities even when membership changes.
2. **Layout Algorithms** — `FRLayout` (force-directed, shared `_fr_iterate!` core), `KKLayout` (classical MDS on geodesic distances, deterministic), `CircleLayout`, `RandomLayout`; dispatched via `compute_layout(net, algorithm; rng=...)`. `compute_layout_anchored` has methods for every algorithm (FR refines from previous positions; RandomLayout keeps previous positions; deterministic layouts recompute).
3. **Dynamic Layout Computation** — `compute_slice_layout`, `layout_sequence` (with anchoring support), `compute_layout_anchored`
4. **Animation Rendering** — `render_animation` (generates evenly-spaced time frames and delegates to `layout_sequence`)
5. **Timeline Visualization** — `timeline_plot`, `proximity_timeline`, `transmissionTimeline` (ASCII output); `timeline_data` extracts raw spell data
6. **Filmstrip** — `filmstrip`, `slice_layout` (multiple network snapshots at specified times)
7. **Export** — `export_frames` (pure-Julia SVG rendering backend), `export_html` (self-contained HTML player: embedded frame data + canvas JS with play/slider controls), `export_movie`/`export_gif` (render SVG frames, then invoke `ffmpeg`/ImageMagick binaries; informative error listing the frame directory when the binary is missing — never a silent stub)

The package is parameterized on vertex type `T` and time type `Time` throughout, following the conventions of `NetworkDynamic.jl`.

## Key Dependencies

- **NetworkDynamic.jl** (local) — provides `DynamicNetwork`, activity spells, `network_extract`, `activate!`
- **Network.jl** (local) — static network type used for snapshots; provides `nv`, `ne`, `edges`, `src`, `dst`
- **Graphs.jl** — graph algorithms
- **LinearAlgebra, Random, Dates** — stdlib packages for layouts (KK eigen-decomposition), seeded RNG threading, and DateTime frame times (`_frame_times`/`_lerp_time`)

## Conventions

- Single-module, single-file package structure (`src/NDTV.jl`)
- Layout algorithms are structs with keyword-argument inner constructors (e.g., `FRLayout(; iterations=100, cooling=0.95, k=1.0)`)
- Layout dispatch uses multiple dispatch on algorithm type: `compute_layout(net, alg::FRLayout)`
- Functions use `where {T, Time}` parametric typing matching `DynamicNetwork{T, Time}`
- R-style naming preserved for ported functions (e.g., `transmissionTimeline` uses camelCase to match R's `ndtv`)
- Other functions use Julia snake_case (e.g., `timeline_plot`, `render_animation`)
- All public API is exported at the top of the module
- Docstrings use Julia triple-quote style with `@ref` cross-references
- Julia 1.12+ compatibility required
