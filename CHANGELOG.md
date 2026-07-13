# Changelog

All notable changes to NDTV.jl are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
package adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - Unreleased

Release driven by the 2026-07 expert-panel review: stable vertex identity
across animation frames, reproducible layouts, a real classical-MDS layout
algorithm (honestly named), and export backends that actually render (SVG
frames, ffmpeg movies, interactive HTML).

### Breaking

- **Layouts are keyed by stable vertex IDs.** `compute_slice_layout`,
  `layout_sequence`, `slice_layout`, and `filmstrip` snapshot with
  `retain_all_vertices=true`, so positions cover *all* vertex IDs (inactive
  vertices placed as isolates) instead of densely renumbered active-only
  vertices. This fixes vertex-identity drift between frames. *Migration:*
  index positions by original vertex ID, not `1:k`.
- **`KKLayout` renamed to `MDSLayout`; `KKLayout` is now a deprecated
  alias.** The algorithm is classical multidimensional scaling (Torgerson
  scaling) of the geodesic-distance matrix: double-centre the squared
  distances, take the top two eigenvectors. It is *not* Kamada–Kawai, which
  iteratively minimizes a spring energy by Newton–Raphson — no such
  iteration exists in this package, and none was ever implemented. The name
  implied an algorithm the code does not run, so it was changed to say what
  it actually computes; the docs no longer print the KK stress-energy
  formula as if it were being minimized. True Kamada–Kawai remains
  unimplemented. *Migration:* use `MDSLayout()`; `KKLayout()` still works
  (`const KKLayout = MDSLayout`) but will be removed in a future release.
- **`MDSLayout()` is fieldless** — being a closed-form eigenproblem it needs
  no iteration or convergence settings, so the old `iterations`/`epsilon`
  keywords are gone, and it ignores any `rng` passed to `compute_layout`.
  *Migration:* drop those keywords.
- **`DynamicLayout` gained a `Time` type parameter and
  `frame_edges`/`frame_active` fields;** `times` is `Vector{Time}` rather
  than `Vector{Float64}`. *Migration:* construct via the keyword
  constructor; do not assume `Float64` times.
- **`export_movie`/`export_gif` can throw** when `ffmpeg`/ImageMagick are
  missing (they now actually encode; previously they only warned and did
  nothing, leaving no output). Rendered frames are left on disk on failure.
  *Migration:* install the binaries or catch the error.
- **Minimum Julia raised to 1.12**; package UUID regenerated. *Migration:*
  upgrade Julia and re-resolve environments pinning the old UUID.

### Added

- `export_frames(layout, dir; width, height)` — pure-Julia SVG rendering
  backend (one numbered SVG per frame), used by `export_movie` and
  `export_gif`.
- `export_html` emits a self-contained interactive animation (embedded
  frame data, canvas player with play/pause and a time slider) instead of a
  static stub.
- `transmission_timeline` snake_case primary (camelCase
  `transmissionTimeline` kept as an exported alias);
  `compute_animation_layout` is a proper `const` alias of
  `render_animation`.
- `rng::AbstractRNG` keywords on `compute_layout` and the anchored variants
  for reproducible layouts.
- Non-numeric time axes (`Date`/`DateTime`) supported throughout
  `layout_sequence`/`render_animation`/`filmstrip`/`slice_layout`; timeline
  functions gain an `io::IO` keyword.

### Changed

- Anchored Fruchterman–Reingold refines from the previous frame at lower
  temperature and half the iterations, giving temporally smoother layouts.
- `filmstrip` frames report active vertices/edges derived from the layout
  instead of re-extracting snapshots.

### Performance

- `DynamicLayout` carries per-frame active vertex/edge lists so renderers
  and `filmstrip` no longer re-extract network snapshots per frame.

## [0.1.0] - 2026-02-09

Initial release: dynamic layout computation, animation rendering, filmstrip
and timeline visualizations for NetworkDynamic.jl networks.
