# NDTV.jl


[![Network Analysis](https://img.shields.io/badge/Network-Analysis-orange.svg)](https://github.com/statistical-network-analysis-with-Julia/NDTV.jl)
[![Build Status](https://github.com/statistical-network-analysis-with-Julia/NDTV.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/statistical-network-analysis-with-Julia/NDTV.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://statistical-network-analysis-with-Julia.github.io/NDTV.jl/dev/)
[![Julia](https://img.shields.io/badge/Julia-1.12+-purple.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

<p align="center">
  <img src="docs/src/assets/logo.svg" alt="NDTV.jl icon" width="160">
</p>

Network Dynamic Temporal Visualization for Julia.

## Overview

NDTV.jl provides tools for visualizing dynamic networks including animations, timeline plots, filmstrip displays, and layout algorithms for time-varying network data.

This package is a Julia port of the R `ndtv` package from the StatNet collection.

## Installation

Requires Julia 1.12+. NDTV.jl depends on the unregistered
[NetworkCore.jl](https://github.com/statistical-network-analysis-with-Julia/NetworkCore.jl) and [DynamicNetworks.jl](https://github.com/statistical-network-analysis-with-Julia/DynamicNetworks.jl) packages, which must be added first (in this order):

```julia
using Pkg
Pkg.add(url="https://github.com/statistical-network-analysis-with-Julia/NetworkCore.jl")
Pkg.add(url="https://github.com/statistical-network-analysis-with-Julia/DynamicNetworks.jl")
Pkg.add(url="https://github.com/statistical-network-analysis-with-Julia/NDTV.jl")
```

For development, clone the repositories side by side (`NDTV.jl` next to
`DynamicNetworks.jl` and `NetworkCore.jl`) and `Pkg.develop` them into one
environment; the organisation site's `tools/prepare_workspace.jl` builds such
a workspace with every package and the extras the examples use. The examples
use `DynamicNetworks` (and `NetworkCore` for `nv`/`ne`) beside `NDTV`.
`export_movie` needs `ffmpeg`; `export_gif` needs ImageMagick with librsvg.

## Features

- **Animation**: Compute layouts for smooth network animations
- **Timeline plots**: Visualize activity over time
- **Filmstrip**: Multiple snapshots side-by-side
- **Layout algorithms**: Fruchterman-Reingold, circular, random
- **Export**: HTML, video, and GIF output (with external tools)

Public functions use snake_case names (the Julia convention); R ndtv-style
camelCase aliases are kept where the R name is the migration target
(e.g. `transmission_timeline`).

## Quick Start

```julia
using DynamicNetworks
using NDTV

# Create dynamic network
dnet = DynamicNetwork(10; observation_start=0.0, observation_end=100.0)
# ... add activity spells ...

# Compute animation layout
layout = render_animation(dnet; n_frames=50)

# Create timeline plot
timeline_plot(dnet)

# Generate filmstrip
frames = filmstrip(dnet, [0.0, 25.0, 50.0, 75.0, 100.0])
```

## Semantics

- **The animation window** is the observation period of the dynamic network,
  cut into `n_frames` equal, contiguous half-open slices. When no window was
  set it is the *closed* range `[first, last]` of the change times, as ndtv's
  default `slice.par`: the last frame starts at the last change time, so a tie
  that forms then is drawn. `onset`/`terminus` override either end. A network
  with neither a window nor a finite spell bound raises an `ArgumentError`
  asking for one (ndtv would animate the placeholder `(0, 1)`). By default
  each frame shows what was active during its slice (R ndtv's aggregated
  slices); `slice=:instant` takes snapshots.
- **Integer and calendar time axes.** `n_frames` defaults to 100 on a
  floating-point axis. On a discrete axis (integer, `Date`, `DateTime`) it
  defaults to 100 or one frame per step, whichever is fewer, so a panel built
  with an integer `start` gets one frame per wave (ndtv's `interval = 1`).
  Slice bounds there are whole steps; when the range does not divide evenly
  they are rounded, and the slices stay contiguous.
- **Vertices and edges with no spells are active** (R's `active.default`).
- **FR and MDS lay out only the vertices active in each frame**; an inactive
  vertex keeps its last (or first) position and is not drawn. Directed
  networks are symmetrised for FR, and MDS lays out each component separately.
- Timelines clamp open-ended (`±Inf`) spells to the window edge; without a
  window they span the range of the change times.

## Layout Computation

### Animation Layout

<!-- skip-check -->
```julia
# Compute layouts for animation
layout = render_animation(dnet;
    algorithm=FRLayout(),
    n_frames=100,
    interpolation=:linear
)

# Access frame data
layout[i]        # Positions at frame i
layout.times     # Time points
layout.bounds    # (xmin, xmax, ymin, ymax)
```

### Layout Algorithms

```julia
# Fruchterman-Reingold (force-directed)
FRLayout(; iterations=100, cooling=0.95, k=1.0)

# Circular layout
CircleLayout(; radius=1.0, start_angle=0.0)

# Random layout
RandomLayout(; xmin=0.0, xmax=1.0, ymin=0.0, ymax=1.0)

# Classical MDS of geodesic distances (deterministic, non-iterative).
# This is NOT Kamada-Kawai: no spring-energy minimization is performed.
MDSLayout()
```

### Single Snapshot Layout

<!-- skip-check -->
```julia
# Layout at specific time
positions = compute_slice_layout(dnet, time; algorithm=FRLayout())
# Returns Dict{vertex => (x, y)}
```

### Layout Sequence

```julia
# Layouts at multiple time points with anchoring
times = collect(0.0:10.0:100.0)
layout = layout_sequence(dnet, times;
    algorithm=FRLayout(),
    anchor=true  # Use previous layout as starting point
)
```

## DynamicLayout Type

<!-- skip-check -->
```julia
struct DynamicLayout{T, Time}
    positions::Vector{Dict{T, Tuple{Float64, Float64}}}  # every vertex, every frame
    times::Vector{Time}                                   # frame (slice) onsets
    bounds::Tuple{Float64, Float64, Float64, Float64}
    frame_edges::Vector{Vector{Tuple{T, T}}}              # active edges per frame
    frame_active::Vector{Vector{T}}                       # active vertices per frame
end

length(layout)   # Number of frames
layout[i]        # Positions at frame i
```

## Interpolated Layout

<!-- skip-check -->
```julia
# Smooth interpolation between computed frames
interp = InterpolatedLayout(base_layout; interpolation=:linear)
interp = InterpolatedLayout(base_layout; interpolation=:ease)

# Get position at any time
pos = get_position(interp, vertex, time)
```

## Timeline Visualization

### Timeline Plot

```julia
# ASCII timeline showing activity
timeline_plot(dnet; width=60)

# Output:
# Timeline: 0.0 to 100.0
# ============================================================
# Vertices:
# V1: |────────────                                          |
# V2: |    ────────────────                                  |
# Edges:
# 1→2: |      ══════════                                      |
```

### Ego Timeline

<!-- skip-check -->
```julia
# Ego-centric timeline
ego_timeline(dnet, vertex; width=60)
```

### Transmission Timeline

<!-- skip-check -->
```julia
# For epidemic/diffusion visualization
transmissions = [(from, to, time), ...]
transmission_timeline(dnet, transmissions)
```

### Timeline Data

```julia
# Extract data for custom plotting
data = timeline_data(dnet)
data.vertices  # (vertex, onset, terminus) tuples
data.edges     # (source, target, onset, terminus) tuples
```

## Filmstrip

```julia
# Multiple snapshots
times = [0.0, 25.0, 50.0, 75.0, 100.0]
frames = filmstrip(dnet, times; algorithm=FRLayout())

# Each frame contains:
# (time, positions, active, edges, n_vertices, n_edges)

# Five contiguous slices of [0, 100); each frame aggregates its slice
frames = slice_layout(dnet, 0.0, 100.0; n_slices=5)
```

## Export

### HTML (Interactive)

```julia
export_html(layout, "animation.html";
    config=HTMLConfig(width=800, height=600, controls=true)
)
```

### Video

```julia
# Requires FFmpeg (built with librsvg, as distribution builds are)
export_movie(layout, "animation.mp4";
    config=VideoConfig(fps=30, width=800, height=600)
)
```

### GIF

```julia
# Requires ImageMagick with its librsvg SVG delegate
# (apt: imagemagick librsvg2-bin; brew: imagemagick librsvg)
export_gif(layout, "animation.gif";
    config=GIFConfig(fps=10, width=400, height=400)
)
```

## Example: Visualizing Network Evolution

```julia
using DynamicNetworks
using NDTV

# Create dynamic network
dnet = DynamicNetwork(20; observation_start=0.0, observation_end=100.0)

# Add some dynamics
for i in 1:20
    activate!(dnet, 0.0, 100.0; vertex=i)
end

# Edges appear and disappear
activate!(dnet, 0.0, 30.0; edge=(1, 2))
activate!(dnet, 20.0, 60.0; edge=(2, 3))
activate!(dnet, 40.0, 80.0; edge=(3, 4))

# Create animation
layout = render_animation(dnet; n_frames=100)

# Show timeline
timeline_plot(dnet)

# Export
export_html(layout, "network_evolution.html")
```

## Example: Epidemic Spread

```julia
# Visualize disease transmission
transmissions = [
    (1, 2, 5.0),   # Person 1 infects 2 at t=5
    (2, 3, 12.0),  # Person 2 infects 3 at t=12
    (2, 4, 15.0),  # Person 2 infects 4 at t=15
]

transmission_timeline(dnet, transmissions)
```

## Coming from R ndtv

| R ndtv | NDTV.jl | Note |
|---|---|---|
| `compute.animation` | `render_animation` / `compute_animation_layout` | `n_frames` equal slices instead of `slice.par` (without a window, over the same closed range of the change times); returns positions |
| `render.animation`, `render.d3movie` | `export_html`, `export_frames`, `export_movie`, `export_gif` | SVG/HTML rendering; no styling arguments |
| `filmstrip` | `filmstrip`, `slice_layout` | frame data, not a plot |
| `timeline` | `timeline_plot`, `timeline_data` | ASCII |
| `proximity.timeline` | not ported (`ego_timeline` is a different display: an ego's tie spells) | **different display**: not MDS positions over time |
| `transmissionTimeline` | `transmission_timeline` | marks events on a text timeline; no transmission tree |
| `network.layout.animate.MDSJ` | `MDSLayout` | classical MDS in Julia |
| `network.layout.fruchtermanreingold` | `FRLayout` | |

The full table, with a rename table for names of earlier development versions
(`KKLayout`, `proximity_timeline`, `transmissionTimeline`, all removed), is in
the documentation ("Coming from R ndtv").

## Not implemented

- Kamada–Kawai layout (`network.layout.animate.kamadakawai`); `MDSLayout`
  is classical MDS.
- Graphviz and attribute-driven layouts (`network.layout.animate.Graphviz`,
  `useAttribute`), `timePrism`, `ndtvAnimationWidget`, and ndtv's
  `layout.*` helpers.
- R's `proximity.timeline` display and the transmission *tree* of
  `transmissionTimeline` (`ego_timeline` and `transmission_timeline` are text
  summaries).
- Vertex and edge styling (colour, size, labels) in exported frames.
- Video and GIF encoding without external tools: `export_movie` needs
  `ffmpeg` (with SVG input), `export_gif` needs ImageMagick with librsvg;
  a missing binary raises `MissingToolError`.

## Documentation

For more detailed documentation, see:

- [Documentation](https://statistical-network-analysis-with-Julia.github.io/NDTV.jl/dev/)

## References

1. Bender-deMoll, S. (2023). ndtv: Network Dynamic Temporal Visualizations. R package. [https://cran.r-project.org/package=ndtv](https://cran.r-project.org/package=ndtv)

2. Bender-deMoll, S., & McFarland, D.A. (2006). The Art and Science of Dynamic Network Visualization. *Journal of Social Structure*, 7(2), 1-38.

## Citation

If you use NDTV.jl in your work, please cite it using the entry in
[`CITATION.bib`](CITATION.bib):

```biblatex
@misc{SNWJNDTVJL,
  author = {Santoni, Simone},
  title = {NDTV.jl: Network Dynamic Temporal Visualization for Julia},
  year = {2026},
  url = {https://github.com/statistical-network-analysis-with-Julia/NDTV.jl},
  note = {Homepage: https://statistical-network-analysis-with-Julia.github.io/NDTV.jl; GitHub: https://github.com/statistical-network-analysis-with-Julia}
}
```

NDTV.jl ports the displays of the R package `ndtv`.
**Please also cite the R package and the methods paper** — Bender-deMoll
(`citation("ndtv")` in R gives the current entry) and Bender-deMoll and
McFarland (2006); the per-package list is at
<https://statistical-network-analysis-with-julia.github.io/citing/>.

## License

MIT License - see [LICENSE](LICENSE) for details.
