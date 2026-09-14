# NDTV.jl

Turn observed network activity into animations, timelines, and filmstrips. NDTV.jl takes NetworkDynamic.jl data, computes layouts over time, and exports visual artifacts for inspecting and communicating changing relationships.

| First analysis | Learn the model or data | Reference and detail |
|:--|:--|:--|
| [Export a first animation](getting_started.md) | [Choose a layout](guide/layout.md) | [Compare export formats](guide/export.md) |

!!! note "Supported scope"

    Layouts encode graph structure, not physical positions or an inferred movement process. Interpolation is a visual transition between frames. HTML and SVG exports are self-contained outputs; video and GIF export require the external tools documented in the [export guide](guide/export.md).

## Installation

```@raw html
<p>Use Julia <strong>1.12 or newer</strong> and the <a href="/getting-started/">shared workspace installation guide</a>. These development packages are not yet registered; the guide prepares the required sibling checkouts and a Julia environment for the examples.</p>
```

## Quick Start

Create a small contact sequence and export an HTML animation with a deterministic circular layout:

```julia
using NetworkDynamic, NDTV

dnet = DynamicNetwork(4; observation_start=0.0, observation_end=10.0)
activate_vertices!(dnet, collect(1:4), 0.0, 10.0)
activate!(dnet, 0.0, 5.0; edge=(1, 2))
activate!(dnet, 3.0, 9.0; edge=(2, 3))
layout = render_animation(dnet; algorithm=CircleLayout(), n_frames=6)
export_html(layout, "network.html")
```

```@raw html
<p>Open <code>network.html</code> in a browser to inspect the selected frames. Increase the frame count when short spells would otherwise be missed. For quantitative reachability or duration analysis, continue with <a href="/TSNA.jl/dev/">TSNA.jl</a>.</p>
```

## Visualization Types

| Type | Function | Description |
|------|----------|-------------|
| Animation | [`render_animation`](@ref) | Smooth layout transitions across time |
| Timeline | [`timeline_plot`](@ref) | ASCII activity timeline |
| Proximity | [`proximity_timeline`](@ref) | Ego-centric activity view |
| Transmission | [`transmission_timeline`](@ref) | Diffusion event visualization |
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

With `FRLayout()` and anchoring enabled, a frame starts from the previous
frame's coordinates before applying the force-directed updates. This can
reduce visual jumps, but does not constrain actors to fixed positions.
`CircleLayout()` and `MDSLayout()` recompute their deterministic layouts;
anchoring does not change those algorithms. New or changing contacts can
still lead to substantial movement in the drawing.

### Interpolation

Between computed layout frames, positions are interpolated:

- **Linear**: $p(t) = p_1 + \alpha \cdot (p_2 - p_1)$
- **Ease**: Smooth acceleration and deceleration using cubic easing

## References

1. Bender-deMoll, S., Morris, M., Moody, J. (2008). Prototype packages for managing and animating longitudinal network data: dynamicnetwork and rSoNIA. *Journal of Statistical Software*, 24(7), 1-36.

2. Fruchterman, T.M.J., Reingold, E.M. (1991). Graph drawing by force-directed placement. *Software: Practice and Experience*, 21(11), 1129-1164.

3. Torgerson, W.S. (1952). Multidimensional scaling: I. Theory and method. *Psychometrika*, 17(4), 401-419. — the classical (strain) MDS that [`MDSLayout`](@ref) implements.

   Note: Kamada, T., Kawai, S. (1989), "An algorithm for drawing general undirected graphs" (*Information Processing Letters*, 31(1), 7-15), is cited here only for contrast. Its iterative spring-energy minimization is **not** implemented in NDTV.jl; the layout formerly named `KKLayout` is classical MDS.

4. Moody, J., McFarland, D., Bender-deMoll, S. (2005). Dynamic network visualization. *American Journal of Sociology*, 110(4), 1206-1241.


## Citation

If you use NDTV.jl in your work, please cite it using the entry in
[`CITATION.bib`](https://github.com/statistical-network-analysis-with-Julia/NDTV.jl/blob/main/CITATION.bib):

```biblatex
@misc{SNWJNDTVJL,
  author = {{Statistical Network Analysis with Julia}},
  title = {NDTV.jl: Network Dynamic Temporal Visualization for Julia},
  year = {2026},
  url = {https://github.com/statistical-network-analysis-with-Julia/NDTV.jl},
  note = {Homepage: https://statistical-network-analysis-with-Julia.github.io/NDTV.jl; GitHub: https://github.com/statistical-network-analysis-with-Julia}
}
```

## Module

```@docs
NDTV
```
