# NDTV.jl

*Network Dynamic Temporal Visualization for Julia*

A Julia package for visualizing dynamic networks through animations, timeline plots, filmstrip displays, and layout algorithms for time-varying network data.

## Overview

NDTV.jl provides tools for computing and displaying the evolution of networks over time. It computes smooth layout transitions, generates timeline visualizations, and exports animations in multiple formats. NDTV.jl works with dynamic networks from NetworkDynamic.jl.

NDTV.jl is a port of the R [ndtv](https://github.com/statnet/ndtv) package from the StatNet collection.

### What is Dynamic Network Visualization?

Dynamic networks change over time -- vertices and edges appear and disappear. Visualizing these changes requires:

```text
Time 0        Time 25       Time 50       Time 75       Time 100
  A--B         A--B          A  B           A--B--C       A--B--C
  |            |  |          |              |     |           |
  C            C--D          C--D           D     E       D--E
```

NDTV.jl computes layouts for each time point and provides smooth transitions between them.

### Key Concepts

| Concept | Description |
|---------|-------------|
| **DynamicLayout** | Vertex positions across multiple time points |
| **InterpolatedLayout** | Smooth position interpolation between time points |
| **Layout Algorithm** | Method for positioning vertices (FR, KK, circle, random) |
| **Timeline Plot** | ASCII visualization of vertex and edge activity spells |
| **Filmstrip** | Multiple network snapshots side by side |
| **Animation** | Continuous layout transitions with export support |

### Applications

NDTV.jl is designed for:

- **Epidemiology**: Visualizing disease transmission through a contact network
- **Communication analysis**: Showing how interaction patterns evolve
- **Organizational studies**: Displaying changes in collaboration structures
- **Social media**: Animating the growth and evolution of online networks
- **Ecological studies**: Visualizing animal social network dynamics

## Features

- **Animation rendering**: Compute smooth layout transitions across time
- **Layout algorithms**: Fruchterman-Reingold, Kamada-Kawai, circular, and random layouts
- **Timeline visualization**: ASCII timeline plots showing vertex and edge activity
- **Proximity timeline**: Ego-centric activity views
- **Transmission timeline**: Visualize diffusion and contagion events
- **Filmstrip**: Multiple time-point snapshots
- **Export**: HTML, video (FFmpeg), and GIF (ImageMagick) output

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/Statistical-network-analysis-with-Julia/NDTV.jl")
```

Or for development:

```julia
using Pkg
Pkg.develop(path="/path/to/NDTV.jl")
```

## Quick Start

```julia
using NetworkDynamic
using NDTV

# Create a dynamic network
dnet = DynamicNetwork(10; observation_start=0.0, observation_end=100.0)

# Activate vertices
for i in 1:10
    activate!(dnet, 0.0, 100.0; vertex=i)
end

# Add edge activity spells
activate!(dnet, 0.0, 50.0; edge=(1, 2))
activate!(dnet, 20.0, 80.0; edge=(2, 3))
activate!(dnet, 40.0, 100.0; edge=(3, 4))

# Compute animation layout
layout = render_animation(dnet; n_frames=50)

# Show timeline
timeline_plot(dnet)

# Export to HTML
export_html(layout, "network_animation.html")
```

## Visualization Types

| Type | Function | Description |
|------|----------|-------------|
| Animation | [`render_animation`](@ref) | Smooth layout transitions across time |
| Timeline | [`timeline_plot`](@ref) | ASCII activity timeline |
| Proximity | [`proximity_timeline`](@ref) | Ego-centric activity view |
| Transmission | [`transmissionTimeline`](@ref) | Diffusion event visualization |
| Filmstrip | [`filmstrip`](@ref) | Multiple snapshots at specified times |
| Single snapshot | [`compute_slice_layout`](@ref) | Layout at a single time point |

## Documentation

```@contents
Pages = [
    "getting_started.md",
    "guide/animation.md",
    "guide/layout.md",
    "guide/export.md",
    "api/types.md",
    "api/layout.md",
    "api/export.md",
]
Depth = 2
```

## Theoretical Background

### Force-Directed Layout

The Fruchterman-Reingold algorithm treats the network as a physical system:

- **Repulsive forces** push all vertex pairs apart: $f_r(d) = k^2 / d$
- **Attractive forces** pull connected vertices together: $f_a(d) = d^2 / k$
- **Simulated annealing** gradually reduces the temperature to settle into a stable layout

Where $k = \sqrt{\text{area} / n}$ is the optimal spacing and $d$ is the distance between vertices.

### Dynamic Layout Stability

For dynamic networks, NDTV.jl uses **anchored layouts**: each frame uses the previous frame's positions as starting points. This produces smooth transitions where:

- Persistent vertices maintain stable positions
- New vertices appear near their neighbors
- Layout changes are gradual rather than abrupt

### Interpolation

Between computed layout frames, positions are interpolated:

- **Linear**: $p(t) = p_1 + \alpha \cdot (p_2 - p_1)$
- **Ease**: Smooth acceleration and deceleration using cubic easing

## References

1. Bender-deMoll, S., Morris, M., Moody, J. (2008). Prototype packages for managing and animating longitudinal network data: dynamicnetwork and rSoNIA. *Journal of Statistical Software*, 24(7), 1-36.

2. Fruchterman, T.M.J., Reingold, E.M. (1991). Graph drawing by force-directed placement. *Software: Practice and Experience*, 21(11), 1129-1164.

3. Kamada, T., Kawai, S. (1989). An algorithm for drawing general undirected graphs. *Information Processing Letters*, 31(1), 7-15.

4. Moody, J., McFarland, D., Bender-deMoll, S. (2005). Dynamic network visualization. *American Journal of Sociology*, 110(4), 1206-1241.
