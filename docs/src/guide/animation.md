# Animation Layout

This guide covers how NDTV.jl computes smooth layout transitions for animating dynamic networks.

## Overview

Dynamic network animation requires computing vertex positions at many time points so that the network appears to evolve smoothly. NDTV.jl achieves this through:

1. **Network slicing** -- extracting the active subnetwork at each time point
2. **Layout computation** -- positioning vertices using force-directed or geometric algorithms
3. **Anchoring** -- using the previous frame's positions as starting points for stability
4. **Interpolation** -- smoothing transitions between computed frames

## The Animation Pipeline

```text
DynamicNetwork
      │
      ▼
  ┌───────────┐     ┌──────────────┐     ┌────────────────┐
  │ Time slice │────▶│ Layout compute│────▶│ DynamicLayout  │
  │  at t_1    │     │  (anchored)  │     │  positions[1]  │
  └───────────┘     └──────────────┘     └────────────────┘
                          │ anchor
                          ▼
  ┌───────────┐     ┌──────────────┐     ┌────────────────┐
  │ Time slice │────▶│ Layout compute│────▶│ DynamicLayout  │
  │  at t_2    │     │  (anchored)  │     │  positions[2]  │
  └───────────┘     └──────────────┘     └────────────────┘
                          │ anchor
                          ▼
                         ...
                          │
                          ▼
                  ┌────────────────────┐
                  │ InterpolatedLayout │
                  │  (optional smooth) │
                  └────────────────────┘
```

## Computing an Animation

### Using `render_animation`

The simplest way to create an animation is with [`render_animation`](@ref):

```julia
using NetworkDynamic
using NDTV

# Create a dynamic network
dnet = DynamicNetwork(10; observation_start=0.0, observation_end=100.0)
for i in 1:10
    activate!(dnet, 0.0, 100.0; vertex=i)
end
activate!(dnet, 0.0, 50.0; edge=(1, 2))
activate!(dnet, 20.0, 80.0; edge=(2, 3))
activate!(dnet, 40.0, 100.0; edge=(3, 4))

# Compute animation with 100 frames
layout = render_animation(dnet;
    algorithm=FRLayout(),
    n_frames=100,
    interpolation=:linear
)
```

Parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `algorithm` | Layout type | `FRLayout()` | Layout algorithm to use |
| `n_frames` | `Int` | `100` | Number of frames to compute |
| `interpolation` | `Symbol` | `:linear` | Interpolation mode (`:linear`, `:ease`, `:none`) |

### Frame Computation

`render_animation` divides the observation period into evenly-spaced time points and computes a layout at each one:

```julia
# With n_frames=5 over [0, 100]:
# Times: [0.0, 25.0, 50.0, 75.0, 100.0]
# At each time, the active subnetwork is extracted and laid out
```

The observation period is taken from the `DynamicNetwork`'s `observation_period` field:

```julia
start_time, end_time = dnet.observation_period
# Frames are evenly spaced from start_time to end_time
```

## Layout Sequences

For more control over which time points to compute, use [`layout_sequence`](@ref):

```julia
# Compute layouts at specific time points
times = [0.0, 10.0, 25.0, 50.0, 75.0, 100.0]
layout = layout_sequence(dnet, times;
    algorithm=FRLayout(),
    anchor=true
)
```

This is useful when you want:
- Non-uniform time spacing (e.g., more detail during active periods)
- Layouts only at specific events of interest
- Custom time grids that match your data

### Anchored vs. Independent Layouts

The `anchor` parameter controls layout stability:

**Anchored (default, `anchor=true`):**
- Each frame starts from the previous frame's vertex positions
- Uses half the normal iterations (since starting positions are good)
- Produces smooth, stable transitions
- Persistent vertices barely move between frames

**Independent (`anchor=false`):**
- Each frame is computed from scratch with random initial positions
- Full iteration count
- Frames may show dramatically different arrangements
- Useful for comparing structural properties without positional bias

```julia
# Anchored -- smooth transitions
layout_smooth = layout_sequence(dnet, times; anchor=true)

# Independent -- each frame computed fresh
layout_fresh = layout_sequence(dnet, times; anchor=false)
```

### How Anchoring Works

When anchoring is enabled, the algorithm:

1. Checks which vertices existed in the previous frame
2. Copies their positions as starting points
3. New vertices (not in the previous frame) get random initial positions
4. Runs the layout algorithm with reduced temperature/iterations

This means:
- Vertices that persist between frames drift gradually to accommodate new structure
- New vertices settle near their neighbors naturally
- The overall layout remains recognizable across frames

## Single-Frame Layout

For a layout at a single time point, use [`compute_slice_layout`](@ref):

```julia
# Get vertex positions at t=50
positions = compute_slice_layout(dnet, 50.0; algorithm=FRLayout())
# Returns Dict{vertex_id => (x, y)}

for (v, (x, y)) in positions
    println("Vertex $v: ($x, $y)")
end
```

This extracts the active subnetwork at the given time and applies the layout algorithm once.

## Interpolated Layouts

For smoother animation between computed frames, wrap a `DynamicLayout` in an [`InterpolatedLayout`](@ref):

```julia
# Compute base layout at a few time points
base = layout_sequence(dnet, collect(0.0:20.0:100.0);
    algorithm=FRLayout()
)

# Create interpolated layout
interp = InterpolatedLayout(base; interpolation=:ease)

# Query position at any time (not just computed times)
pos = get_position(interp, 1, 35.0)
println("Vertex 1 at t=35: ($(pos[1]), $(pos[2]))")
```

### Interpolation Modes

**Linear interpolation (`:linear`)**

Positions change at constant velocity between frames:

```math
p(t) = p_1 + \alpha \cdot (p_2 - p_1)
```

where $\alpha = (t - t_1) / (t_2 - t_1)$ is the fractional position between frames.

**Ease interpolation (`:ease`)**

Uses cubic ease-in-out for smooth acceleration and deceleration:

```math
\alpha_{\text{ease}} = \begin{cases}
2\alpha^2 & \text{if } \alpha < 0.5 \\
1 - \frac{(-2\alpha + 2)^2}{2} & \text{otherwise}
\end{cases}
```

This produces natural-looking motion where vertices slow down as they approach their target positions.

| Mode | Visual Effect | Use Case |
|------|---------------|----------|
| `:linear` | Constant speed | Technical analysis, precise tracking |
| `:ease` | Smooth start/stop | Presentations, publications |
| `:none` | No interpolation (discrete) | Frame-by-frame inspection |

### Querying Interpolated Positions

The [`get_position`](@ref) function returns a vertex's position at any time:

```julia
interp = InterpolatedLayout(base; interpolation=:ease)

# Get position at exact frame time (no interpolation needed)
pos_exact = get_position(interp, 1, 20.0)

# Get position between frames (interpolated)
pos_between = get_position(interp, 1, 35.0)

# Before first frame -- returns first frame position
pos_before = get_position(interp, 1, -5.0)

# After last frame -- returns last frame position
pos_after = get_position(interp, 1, 200.0)
```

## Working with DynamicLayout

The [`DynamicLayout`](@ref) type stores computed positions:

```julia
layout = render_animation(dnet; n_frames=50)

# Number of frames
length(layout)  # 50

# Access positions at a specific frame
frame_10 = layout[10]  # Dict{T, Tuple{Float64, Float64}}

# Time points
layout.times  # Vector{Float64} of length 50

# Bounding box for all frames
xmin, xmax, ymin, ymax = layout.bounds
```

### Extracting Frame Data

```julia
# Iterate over all frames
for (i, t) in enumerate(layout.times)
    positions = layout[i]
    n_vertices = length(positions)
    println("Frame $i (t=$t): $n_vertices vertices positioned")
end

# Get all positions for a single vertex across time
vertex_trajectory = [(t, layout[i][1]) for (i, t) in enumerate(layout.times)
                     if haskey(layout[i], 1)]
```

## Timeline Visualization

### Timeline Plot

[`timeline_plot`](@ref) creates an ASCII visualization of vertex and edge activity:

```julia
timeline_plot(dnet; width=60)
```

The output uses `─` for vertex activity and `═` for edge activity, scaled to the specified width. This gives an immediate overview of when network elements are active.

### Proximity Timeline

[`proximity_timeline`](@ref) shows the activity of edges connected to a specific vertex:

```julia
# Show all edges involving vertex 3
proximity_timeline(dnet, 3; width=60)
```

This is useful for understanding a vertex's local network dynamics -- when its connections appear and disappear.

### Transmission Timeline

[`transmissionTimeline`](@ref) visualizes discrete transmission events (e.g., disease spread, information diffusion):

```julia
transmissions = [
    (1, 2, 5.0),
    (2, 3, 12.0),
    (2, 4, 15.0),
]

transmissionTimeline(dnet, transmissions; width=60)
```

Each transmission is shown as a `*` at its time position on the timeline.

### Timeline Data

[`timeline_data`](@ref) extracts raw activity data for custom plotting:

```julia
data = timeline_data(dnet)

# Vertex activity spells
for v in data.vertices
    println("Vertex $(v.vertex): active $(v.onset) to $(v.terminus)")
end

# Edge activity spells
for e in data.edges
    println("Edge $(e.source)→$(e.target): active $(e.onset) to $(e.terminus)")
end
```

## Filmstrip

### Basic Filmstrip

[`filmstrip`](@ref) generates layout data for multiple time-point snapshots:

```julia
times = [0.0, 25.0, 50.0, 75.0, 100.0]
frames = filmstrip(dnet, times; algorithm=FRLayout())

for frame in frames
    println("t=$(frame.time): $(frame.n_vertices)v, $(frame.n_edges)e")
    println("  Positions: ", frame.positions)
end
```

### Slice Layout

[`slice_layout`](@ref) generates evenly-spaced slices over an interval:

```julia
# 5 snapshots between t=10 and t=90
frames = slice_layout(dnet, 10.0, 90.0; n_slices=5, algorithm=FRLayout())
# Computes at t = 10.0, 30.0, 50.0, 70.0, 90.0
```

## Performance Considerations

### Number of Frames

More frames produce smoother animation but take longer to compute:

| Frames | Quality | Compute Time (relative) |
|--------|---------|------------------------|
| 25 | Choppy | 1x |
| 50 | Acceptable | 2x |
| 100 | Smooth | 4x |
| 200 | Very smooth | 8x |

For large networks (>100 vertices), start with fewer frames and increase as needed.

### Layout Algorithm Choice

- **FRLayout**: $O(n^2)$ per iteration due to pairwise repulsion. Good for networks up to ~500 vertices.
- **KKLayout**: More expensive per iteration but may converge faster. Best for small networks.
- **CircleLayout**: $O(n)$ -- fast but ignores network structure.
- **RandomLayout**: $O(n)$ -- fastest, but no structural information.

### Reducing Computation

```julia
# Fewer iterations for faster (rougher) layouts
fast_alg = FRLayout(iterations=30, cooling=0.9)

# Compute fewer frames
layout = render_animation(dnet; n_frames=25, algorithm=fast_alg)
```
