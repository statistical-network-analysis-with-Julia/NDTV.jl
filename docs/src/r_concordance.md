# Coming from R ndtv

NDTV.jl ports the layout-and-frame core of R's
[ndtv](https://cran.r-project.org/package=ndtv) to Julia. The rendering
side is different by design: NDTV.jl writes SVG frames, a self-contained HTML
player, and (through external binaries) videos and GIFs, instead of drawing
with R graphics and the `animation`/`htmlwidgets` packages. **Validation.** The deterministic layout, `MDSLayout`, is checked against R:
a golden fixture (`test/fixtures/mds_layout.toml`, 40 random connected graphs)
requires its inter-vertex distances to equal those of
`stats::cmdscale(sna::geodist(g)$gdist, k = 2)` to 1e-8, up to the rotation,
reflection and scale a layout leaves free. Activity, slices and windows are
DynamicNetworks.jl's, which are checked against R networkDynamic by its own
fixture. The Fruchterman–Reingold layout is random and iterative and is
tested for its properties (reproducibility from `rng`, symmetrisation,
active-vertex-only layout), not against ndtv's output; ndtv's own animation
layouts come from Java (MDSJ) and Graphviz back ends and are not compared.

## Concordance

| R ndtv | NDTV.jl | Differences |
|---|---|---|
| `compute.animation(net, slice.par = list(start, end, interval, aggregate.dur, rule))` | [`render_animation`](@ref)`(dnet; n_frames, onset, terminus, slice, rule)` (alias [`compute_animation_layout`](@ref)) | The window is cut into `n_frames` equal, contiguous slices (R: an `interval` and an `aggregate.dur`). `slice=:interval` is R's default `aggregate.dur = interval`; `slice=:instant` takes snapshots. The default window is the observation period, cut into half-open slices. Without one it is the closed range `[first, last]` of the change times, the last slice starting at the last change time, as R's default `slice.par` (`net.obs.period`, else the change times, with slice onsets `seq(start, end, by = interval)`). With neither, R uses `(0, 1)`; NDTV.jl raises an `ArgumentError`. On an integer, `Date` or `DateTime` axis the default `n_frames` is at most one frame per step (R's default `interval = 1`), and slice bounds are whole steps. Returns positions instead of storing them as TEAs on the network. |
| `render.animation`, `render.d3movie`, `ani.replay` | [`export_html`](@ref), [`export_frames`](@ref), [`export_movie`](@ref), [`export_gif`](@ref) | Self-contained HTML canvas player and SVG frames; video/GIF need `ffmpeg` / ImageMagick + librsvg. No vertex/edge styling arguments (colour, size, labels). |
| `saveVideo`, `saveGIF` (via the `animation` package) | [`export_movie`](@ref), [`export_gif`](@ref) | A missing binary raises [`MissingToolError`](@ref). |
| `filmstrip(net, slice.par = ...)` | [`filmstrip`](@ref)`(dnet, times; termini)`, [`slice_layout`](@ref)`(dnet, onset, terminus; n_slices)` | Returns frame data (positions, active sets, counts); does not draw. |
| `timeline(net)` | [`timeline_plot`](@ref) | ASCII bars (R draws a plot); [`timeline_data`](@ref) returns the spells for custom plotting. |
| `timeline(net)` range | the window, else the range of the change times | Without either, [`timeline_plot`](@ref) and [`ego_timeline`](@ref) need `onset`/`terminus` (an `ArgumentError` says so); [`transmission_timeline`](@ref) also spans the transmission times. |
| `proximity.timeline(net)` | not ported; [`ego_timeline`](@ref) is a different display | R draws vertex positions from MDS of geodesic distances as lines over time; NDTV.jl prints an ego's tie spells. |
| `transmissionTimeline(net, ...)` | [`transmission_timeline`](@ref) | R draws a transmission tree (generation against time) from a `tEdgeList`; NDTV.jl marks each `(from, to, time)` on a text timeline. |
| `network.layout.animate.kamadakawai` | — | Not ported. [`MDSLayout`](@ref) is classical MDS, **not** Kamada–Kawai. |
| `network.layout.animate.MDSJ` | [`MDSLayout`](@ref) | Classical MDS computed in Julia (R calls the MDSJ Java library); components laid out separately. |
| `network.layout.fruchtermanreingold` (network) | [`FRLayout`](@ref) | Same symmetrisation of directed graphs; own force constants, positions clamped to `[-1, 1]`. |
| `network.layout.circle` | [`CircleLayout`](@ref) | — |
| `network.layout.animate.Graphviz`, `network.layout.animate.useAttribute` | — | Not ported. |
| `timePrism`, `ndtvAnimationWidget`, `layout.center`, `layout.distance`, `layout.normalize`, `install.ffmpeg`, `install.graphviz` | — | Not ported. |

## Semantics shared with networkDynamic

NDTV.jl takes activity from DynamicNetworks.jl, which follows R's
networkDynamic: spells are half-open `[onset, terminus)`, a point spell is
active exactly at its instant, and **vertices and edges with no spells are
active** (`active.default = TRUE`). Structural layouts (FR, MDS) are computed
on the vertices active in each slice only, as ndtv does; an inactive vertex
keeps its last (or first) position and is not drawn.

## Renamed functions

Earlier development versions used three names that are gone. None was
released.

| Earlier name | NDTV.jl name | Why |
|:--|:--|:--|
| `KKLayout` | [`MDSLayout`](@ref) | The layout is classical MDS, not Kamada–Kawai. |
| `proximity_timeline` | [`ego_timeline`](@ref) | R's `proximity.timeline` is a different display. |
| `transmissionTimeline` | [`transmission_timeline`](@ref) | R's `transmissionTimeline` draws a transmission tree. |
