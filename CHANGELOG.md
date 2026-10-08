# Changelog

All notable changes to NDTV.jl are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
package adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - Unreleased

**Dependencies renamed:** the foundation package is now `NetworkCore` (developed as `Networks`) and the dynamic-network package is now `DynamicNetworks` (developed as `NetworkDynamic`); update `using` lines accordingly. Types and functions keep their names.

### Changed

- **Activity follows R networkDynamic.** Vertices and edges with no spells are
  active (DynamicNetworks.jl's `active_default`), so a network built from edge
  spells alone no longer animates as empty frames.
- **Names borrowed from R mean what they mean in R.** `proximity_timeline` is
  renamed `ego_timeline` (R's `proximity.timeline` draws MDS positions over
  time, which is not ported), the camelCase `transmissionTimeline` is renamed
  `transmission_timeline` (R's draws a transmission tree), and `KKLayout` is
  renamed `MDSLayout`. The old names were never released and are removed, with
  no deprecated bindings; the "Coming from R ndtv" page has a rename table.
- **Default animation window.** `render_animation`, `timeline_plot`,
  `ego_timeline` and `transmission_timeline` use the observation window when
  one is set, instead of the `(0, 1)` placeholder of a network built without
  one. **Without a window**, the animation covers the *closed* range
  `[first, last]` of the change times, as ndtv's default `slice.par` does:
  the last frame starts at the last change time, so a tie that forms then
  and stays open is drawn (a half-open range never showed it). The timelines
  span the same range (`transmission_timeline` with the transmission times).
  A network with neither a window nor a finite spell bound raises an
  `ArgumentError` asking for `onset`/`terminus` or `set_observation_period!`.
  `onset`/`terminus` override either end.
- **Frames are slices.** `render_animation` and `slice_layout` cut the window
  into equal, contiguous half-open slices; by default (`slice=:interval`) each
  frame shows what was active during its slice under `rule`, as R ndtv's
  aggregated slices do, so short spells are no longer lost between frames and
  the last frame no longer sits on the window end (where every spell has
  ended). `slice=:instant` takes snapshots at the slice onsets.
  `layout_sequence` and `filmstrip` accept `termini=` and `rule=` for
  interval slices.
- **Layouts use the active vertices only.** `FRLayout` and `MDSLayout` lay out
  the vertices active in each slice; inactive vertices keep their last (or
  first) position and are not drawn. `compute_slice_layout` with these
  algorithms returns positions for the active vertices only.
- `FRLayout` symmetrises directed networks (a mutual pair attracts once), as R's
  `network.layout.fruchtermanreingold`.
- `MDSLayout` lays out each connected component separately (on the
  symmetrised graph) and packs them side by side, instead of capping
  unreachable distances, which collapsed components onto each other.
- Timelines clamp open-ended (`±Inf`) spells to the window edge instead of
  throwing `InexactError`; vertices and edges are listed in a fixed order, and
  undirected ties are drawn as `i—j`/`— V` instead of with arrows.
- `filmstrip` returns a concretely typed vector of named tuples.
- `export_movie`/`export_gif` throw the new `MissingToolError` (naming the tool
  and the directory of rendered frames) when `ffmpeg`/ImageMagick is missing,
  and an `ArgumentError` naming the likely cause when encoding fails.
- `MDSLayout` replaces `KKLayout`: the algorithm is classical MDS of geodesic
  distances, not Kamada–Kawai.
- The `export_movie`/`export_gif` success paths run in CI: the Linux job
  installs ffmpeg, ImageMagick and librsvg, and the test suite requires them
  there (`NDTV_REQUIRE_EXPORT_TOOLS=true`) instead of skipping.

### Fixed

- **Integer and calendar time axes.** `render_animation` and `slice_layout`
  interpolated frame bounds in floating point and converted them back to the
  axis, so the default call threw an `InexactError` on any integer axis,
  including panels built with an integer `start`; on a `Date` axis the 100
  default frames repeated the same few days. Frame bounds on a discrete axis
  (integer, `Date`, `DateTime`) are now whole steps from the start of the
  range, rounded when the range does not divide evenly, with contiguous
  slices. The default `n_frames` (and `n_slices`) is at most one frame per
  step, so an integer panel animates one frame per wave, as ndtv's
  `interval = 1` does; asking for more frames than the range has steps raises
  an `ArgumentError`. An unbounded range is refused instead of producing
  `NaN` frames.
- `get_position` takes a vertex id of any `Integer` type (a literal id threw a
  `MethodError` on an `Int32` layout).

### Added

- A PrecompileTools workload: the time to the first result drops from
  about 3.7 s to 1.0 s.
- Layout algorithms `FRLayout`, `MDSLayout`, `CircleLayout`, `RandomLayout`
  with an `rng` keyword; layouts keyed by stable vertex IDs and anchored
  between frames.
- `export_frames` (SVG frames), a self-contained interactive `export_html`
  player, `export_movie` (ffmpeg) and `export_gif` (ImageMagick + librsvg).
- `DateTime`/`Date` time axes throughout; `io=` keywords on the timelines.
- A "Coming from R ndtv" concordance page.

### Known limitations

- Not implemented: Kamada–Kawai, Graphviz and attribute-driven layouts;
  `timePrism`, `ndtvAnimationWidget`, ndtv's `layout.*` helpers; R's
  `proximity.timeline` display and the transmission tree of
  `transmissionTimeline` (`ego_timeline` and `transmission_timeline` are text
  summaries); vertex and
  edge styling in exported frames.
- Video and GIF export need external binaries (`ffmpeg` with SVG input;
  ImageMagick with librsvg).
- `MDSLayout` is checked against R's `cmdscale` of geodesic distances by a
  golden fixture; `FRLayout` (random, iterative) is tested for its properties
  only, and no layout is compared with ndtv's MDSJ/Graphviz output.

## [0.1.0] - 2026-02-09

Development version, never released: dynamic layout computation, animation
rendering, filmstrip and timeline visualizations for DynamicNetworks.jl
networks.
