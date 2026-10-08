# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NDTV.jl is a Julia port of the R `ndtv` package (from the StatNet suite) that provides tools for visualizing dynamic (time-varying) networks through animations, timeline plots, filmstrip displays, and layout algorithms. It operates on `DynamicNetwork` objects from the sibling `DynamicNetworks.jl` package.

## Development Commands

- **Run tests:** `julia --project -e 'using Pkg; Pkg.test()'`
- **Load package:** `julia --project -e 'using NDTV'`
- **Build docs:** `julia --project=docs docs/make.jl`
- **Activate environment:** `julia --project` (uses local `Project.toml`)

Note: This package depends on local sibling packages `NetworkCore` and `DynamicNetworks` via relative path sources (`../NetworkCore.jl`, `../DynamicNetworks.jl`). These must be present alongside this repo. The package is `NetworkCore` and exports the type `Network`: `using NetworkCore` + `Network(5)`.

## Architecture

The entire package lives in a single file: `src/NDTV.jl`. It is organized into these sections (in order):

1. **Layout Types** — `DynamicLayout{T, Time}` (positions + times + bounds + per-frame active vertices/edges; generic over DynamicNetworks time types incl. DateTime) and `InterpolatedLayout{T, Time}` (linear/ease interpolation). ALL position dictionaries are keyed by STABLE vertex IDs and every frame holds a position for every vertex (see 3).
2. **Layout Algorithms** — `FRLayout` (force-directed, shared `_fr_iterate!` core; attraction runs over `_attraction_pairs`, the SYMMETRISED edge set, so a mutual pair attracts once, as R's `network.layout.fruchtermanreingold`), `MDSLayout` (classical MDS on geodesic distances of the symmetrised graph, PER CONNECTED COMPONENT (`_mds_component`), components packed side by side largest first; deterministic, non-iterative, ignores `rng`), `CircleLayout`, `RandomLayout`; dispatched via `compute_layout(net, algorithm; rng=...)`. `compute_layout_anchored` has methods for every algorithm (FR refines from previous positions; RandomLayout keeps previous positions; deterministic layouts recompute).

   **Naming discipline:** `MDSLayout` was called `KKLayout` in development and documented as Kamada–Kawai. It never implemented the KK spring-energy minimization. A name may not imply an algorithm the code does not implement. The old name was never released and is removed (no deprecated binding; a test pins `!isdefined(NDTV, :KKLayout)`). Do not describe true Kamada–Kawai as implemented.
3. **Dynamic Layout Computation** — `_slice(dnet, t, tend, rule)` returns the snapshot (`network_extract(...; retain_all_vertices=true)`, instant or interval `[t, tend)` under `rule`) and the active vertex list. `_layout_slice`: structural layouts (`_uses_structure`: FR, MDS) are computed on `_active_subgraph` (active vertices renumbered 1:k, anchored to the carried positions by stable ID) — inactive vertices must never influence active ones; Circle/Random keep one slot per vertex on the full snapshot. `layout_sequence(dnet, times; termini, rule, algorithm, anchor, rng)` then fills every frame: last position carried forward, first position back-filled, a never-active vertex at the origin. `compute_slice_layout` returns only the active vertices for FR/MDS.
4. **Animation Rendering** — `render_animation(dnet; n_frames, onset, terminus, slice=:interval, rule=:any, ...)`: the range is `_display_range(dnet, onset, terminus, context)` → `(start, stop, closed)`: explicit bounds win; then the observation window (`get_observation_period`, half-open); with NO window, the range `[first, last]` of `get_change_times` (closed unless `terminus` is given; ndtv's default `slice.par`); with none of these an `ArgumentError` asking for a window (never the `(0,1)` placeholder). `_frame_grid(start, stop, n; closed)` cuts it into `n_frames` equal slices: half-open with Δ = range/n (no frame on the window end), or closed with Δ = range/(n−1) so the last slice starts at `stop` and shows a tie forming at the last change time. **Discrete axes** (`_axis_unit`: integer → 1, `Date` → `Day(1)`, `DateTime` → `Millisecond(1)`; floats are continuous) get whole-unit bounds from `_grid_time` (exact integer arithmetic, rounded half up, so slices stay contiguous and differ by ≤ 1 unit); `_max_frames` caps `n` at one frame per unit (an `ArgumentError` beyond it), and `n_frames=nothing`/`n_slices=nothing` default to `_default_frames` = min(100 or 5, that cap) — an integer panel gets one frame per wave (ndtv's `interval = 1`). Never interpolate in Float64 and `convert` back to an integer axis (that was an `InexactError` on every default call). An unbounded end (`±Inf`, or `DynamicNetworks.unbounded_spell`'s axis extremes) is refused. `slice=:interval` (default, R ndtv's `aggregate.dur = interval`) aggregates each slice; `:instant` snapshots the onsets. `compute_animation_layout` is a `const` alias.
5. **Timeline Visualization** — `timeline_plot`, `ego_timeline` (development name `proximity_timeline`, removed), `transmission_timeline` (ASCII output; the development name `transmissionTimeline` was removed because R's function of that name draws a transmission tree); `timeline_data`. Their range is `_display_range` too (`transmission_timeline` adds the transmission times via `extra=`). They read activity through `get_vertex_activity`/`get_edge_activity` (no-spell elements = `(-Inf, Inf)`), list base edges in sorted order (`_sorted_edges`), clamp time fractions to [0,1] (`_time_frac`; ±Inf spells reach the window edge, never `InexactError`), and use `—` instead of arrows on undirected networks. `ego_timeline`/`transmission_timeline` are text summaries, NOT R's displays of those names (documented in the concordance page).
6. **Filmstrip** — `filmstrip(dnet, times; termini, rule)` (concretely typed vector of named tuples), `slice_layout(dnet, onset, terminus; n_slices, slice)`.
7. **Export** — `export_frames` (pure-Julia SVG rendering backend), `export_html` (self-contained HTML player), `export_movie`/`export_gif` (render SVG frames, then invoke `ffmpeg`/ImageMagick; a missing binary throws the exported `MissingToolError(tool, purpose, frames_dir)`, a failed encode an `ArgumentError` naming the cause — ffmpeg needs librsvg SVG input, ImageMagick the librsvg delegate).

The package is parameterized on vertex type `T` and time type `Time` throughout, following the conventions of `DynamicNetworks.jl`.

## Conversion invariants

NDTV does not author a conversion — it *consumes* `DynamicNetworks.network_extract`
(`_slice` extracts with `retain_all_vertices=true`, instant or interval) and
inherits its row of the ecosystem invariant table
(`NetworkCore.jl/docs/src/guide/conversion_invariants.md`). Vertex IDs are stable
across frames, and activity follows DynamicNetworks (R's `active.default`:
elements with no spells are active). NDTV returns layouts and rendered frames,
never a network, so it has no conversion contract of its own.

## Key Dependencies

- **PrecompileTools.jl** -- the `@compile_workload` at the end of the module (README path, both directedness flavours); keep it in step with the README examples.

- **DynamicNetworks.jl** (local) — provides `DynamicNetwork`, activity spells, `network_extract`, `activate!`
- **NetworkCore.jl** (local) — static network type used for snapshots; provides `nv`, `ne`, `edges`, `src`, `dst`
- **Graphs.jl** — graph algorithms
- **LinearAlgebra, Random, Dates** — stdlib packages for layouts (the `MDSLayout` eigendecomposition), seeded RNG threading, and Date/DateTime frame times (`_grid_time`, `_axis_unit`)

## Golden fixture

`test/fixtures/mds_layout.toml` (regenerate with `Rscript test/fixtures/r/mds_layout.R > test/fixtures/mds_layout.toml`; needs R with sna) pins `MDSLayout` against `stats::cmdscale` of the symmetrised geodesic distances on 40 random connected graphs, comparing max-normalised pairwise distances at 1e-8 (the quantity invariant under rotation, reflection, translation and scale).

## Conventions

- Single-module, single-file package structure (`src/NDTV.jl`)
- Layout algorithms are structs with keyword-argument inner constructors (e.g., `FRLayout(; iterations=100, cooling=0.95, k=1.0)`)
- Layout dispatch uses multiple dispatch on algorithm type: `compute_layout(net, alg::FRLayout)`
- Functions use `where {T, Time}` parametric typing matching `DynamicNetwork{T, Time}`
- A name borrowed from R must mean what it means in R: `proximity_timeline` and `transmissionTimeline` were renamed (`ego_timeline`, `transmission_timeline`) because R's functions of those names are different displays; `KKLayout` → `MDSLayout` likewise. The old names are gone (never released); the docs' concordance has a rename table. Do not add deprecated bindings for unreleased names.
- Other functions use Julia snake_case (e.g., `timeline_plot`, `render_animation`)
- All public API is exported at the top of the module
- Docstrings use Julia triple-quote style with `@ref` cross-references
- Julia 1.12+ compatibility required
- Tests: `test/runtests.jl` pins each R-semantics fix in a testset named after the behaviour, runs every docstring ```` ```julia ```` example in a fresh module (sketches needing ffmpeg/ImageMagick use ```` ```jl ````), runs Aqua + `detect_ambiguities`, and exercises the `export_movie`/`export_gif` success paths when the binaries are on PATH (`@test_skip` otherwise, unless `NDTV_REQUIRE_EXPORT_TOOLS=true`, which CI's Linux cell sets after `apt-get install ffmpeg imagemagick librsvg2-bin` — a step outside the generated layout block of `.github/workflows/CI.yml`; the missing-tool path is tested with `PATH=""`).
- R ndtv concordance: `docs/src/r_concordance.md`; keep it, the README "Coming from R ndtv"/"Not implemented" sections and the CHANGELOG "Known limitations" in sync.
