# Getting Started

This tutorial walks through common use cases for NDTV.jl, from basic animation to advanced visualization of dynamic networks.

## Installation

Install NDTV.jl from GitHub:

```julia
using Pkg
Pkg.add(url="https://github.com/Statistical-network-analysis-with-Julia/NDTV.jl")
```

NDTV.jl depends on NetworkDynamic.jl for dynamic network data structures. Install it as well:

```julia
Pkg.add(url="https://github.com/Statistical-network-analysis-with-Julia/NetworkDynamic.jl")
```

## Basic Workflow

The typical NDTV.jl workflow consists of four steps:

1. **Create a dynamic network** -- Define vertices and edges with activity spells
2. **Compute layouts** -- Position vertices at each time point using layout algorithms
3. **Visualize** -- Generate timelines, filmstrips, or animation frames
4. **Export** -- Save results as HTML, video, or GIF

## Step 1: Create a Dynamic Network

Dynamic networks are created using NetworkDynamic.jl. Vertices and edges have activity spells that define when they are present:

```julia
using NetworkDynamic
using NDTV

# Create a dynamic network with 5 vertices observed from t=0 to t=100
dnet = DynamicNetwork(5; observation_start=0.0, observation_end=100.0)

# Activate all vertices for the full observation period
for i in 1:5
    activate!(dnet, 0.0, 100.0; vertex=i)
end

# Add edge activity spells
# Edge (1,2) is active from t=0 to t=40
activate!(dnet, 0.0, 40.0; edge=(1, 2))

# Edge (2,3) is active from t=20 to t=70
activate!(dnet, 20.0, 70.0; edge=(2, 3))

# Edge (3,4) is active from t=40 to t=90
activate!(dnet, 40.0, 90.0; edge=(3, 4))

# Edge (4,5) is active from t=60 to t=100
activate!(dnet, 60.0, 100.0; edge=(4, 5))

# Edge (1,3) appears temporarily from t=10 to t=30
activate!(dnet, 10.0, 30.0; edge=(1, 3))
```

### Understanding Activity Spells

Each vertex and edge can have multiple activity spells -- intervals during which they are active. A vertex or edge can appear, disappear, and reappear:

```julia
# Vertex 1 is active in two intervals
activate!(dnet, 0.0, 50.0; vertex=1)
activate!(dnet, 70.0, 100.0; vertex=1)

# Edge (1,2) also has two spells
activate!(dnet, 0.0, 30.0; edge=(1, 2))
activate!(dnet, 60.0, 90.0; edge=(1, 2))
```

### Network Snapshots

At any time point, you can extract the active subnetwork:

```julia
# Get the network at time t=25
snapshot = network_extract(dnet, 25.0)
println("Vertices at t=25: ", nv(snapshot))
println("Edges at t=25: ", ne(snapshot))
```

## Step 2: Compute Animation Layout

NDTV.jl computes vertex positions for each time point using force-directed or geometric layout algorithms:

```julia
# Compute animation with 50 frames using Fruchterman-Reingold layout
layout = render_animation(dnet;
    algorithm=FRLayout(),
    n_frames=50,
    interpolation=:linear
)

println("Number of frames: ", length(layout))
println("Time range: ", layout.times[1], " to ", layout.times[end])
println("Layout bounds: ", layout.bounds)
```

The result is a [`DynamicLayout`](@ref) containing vertex positions at each frame:

```julia
# Access positions at frame 1
positions_frame1 = layout[1]
# Returns Dict{vertex_id => (x, y)}

# Access the time for each frame
layout.times  # Vector of time points
```

### Anchored Layouts

By default, NDTV.jl uses **anchored layouts**: each frame's layout computation starts from the previous frame's positions. This produces smooth transitions:

```julia
# Compute layout sequence with anchoring (default)
times = collect(0.0:10.0:100.0)
layout = layout_sequence(dnet, times;
    algorithm=FRLayout(),
    anchor=true   # Use previous positions as starting point
)

# Without anchoring -- each frame is computed independently
layout_unanchored = layout_sequence(dnet, times;
    algorithm=FRLayout(),
    anchor=false
)
```

With anchoring enabled:
- Persistent vertices maintain stable positions across frames
- New vertices appear near their connected neighbors
- Layout changes are gradual rather than abrupt

### Choosing a Layout Algorithm

NDTV.jl provides four layout algorithms:

```julia
# Fruchterman-Reingold: Force-directed (best for most networks)
fr = FRLayout(iterations=100, cooling=0.95, k=1.0)

# Kamada-Kawai: Energy-based (good for small networks)
kk = KKLayout(iterations=100, epsilon=1e-4)

# Circle: Uniform circular placement
circle = CircleLayout(radius=1.0, start_angle=0.0)

# Random: Random uniform placement
random = RandomLayout(xmin=0.0, xmax=1.0, ymin=0.0, ymax=1.0)
```

| Algorithm | Best For | Stability | Speed |
|-----------|----------|-----------|-------|
| `FRLayout` | General networks | High (with anchoring) | Medium |
| `KKLayout` | Small networks (<50 vertices) | High | Slow |
| `CircleLayout` | Fixed-structure comparisons | Perfect | Fast |
| `RandomLayout` | Initial exploration | None | Fast |

## Step 3: Visualize the Network

### Timeline Plot

The simplest visualization is an ASCII timeline showing when vertices and edges are active:

```julia
timeline_plot(dnet)
```

This produces output like:

```text
Timeline: 0.0 to 100.0
============================================================

Vertices:
V1: |────────────────────────────────────────────────────────────|
V2: |────────────────────────────────────────────────────────────|
V3: |────────────────────────────────────────────────────────────|
V4: |────────────────────────────────────────────────────────────|
V5: |────────────────────────────────────────────────────────────|

Edges:
1→2: |════════════════════════                                    |
2→3: |            ════════════════════════════════                |
3→4: |                        ════════════════════════════════    |
4→5: |                                    ════════════════════════|
```

You can control the display width:

```julia
timeline_plot(dnet; width=80)
```

### Proximity Timeline

View activity from a single vertex's perspective:

```julia
# Show all edges involving vertex 2
proximity_timeline(dnet, 2)
```

Output:

```text
Proximity timeline for vertex 2
============================================================
→ V1: |════════════════════════                                    |
→ V3: |            ════════════════════════════════                |
```

### Filmstrip

Generate data for multiple snapshots side-by-side:

```julia
# Get network snapshots at 5 time points
times = [0.0, 25.0, 50.0, 75.0, 100.0]
frames = filmstrip(dnet, times; algorithm=FRLayout())

for frame in frames
    println("t=$(frame.time): $(frame.n_vertices) vertices, $(frame.n_edges) edges")
end
```

You can also use `slice_layout` for evenly-spaced slices over an interval:

```julia
frames = slice_layout(dnet, 0.0, 100.0; n_slices=5, algorithm=FRLayout())
```

### Transmission Timeline

For visualizing diffusion or contagion events:

```julia
# Define transmission events: (source, target, time)
transmissions = [
    (1, 2, 5.0),    # Vertex 1 transmits to 2 at t=5
    (2, 3, 15.0),   # Vertex 2 transmits to 3 at t=15
    (2, 4, 20.0),   # Vertex 2 transmits to 4 at t=20
    (3, 5, 30.0),   # Vertex 3 transmits to 5 at t=30
]

transmissionTimeline(dnet, transmissions)
```

Output:

```text
Transmission Timeline
============================================================
1→2: |  *                                                        | t=5.0
2→3: |        *                                                  | t=15.0
2→4: |           *                                               | t=20.0
3→5: |                 *                                         | t=30.0
```

## Step 4: Export the Animation

### HTML Export

The simplest export format creates a self-contained HTML file:

```julia
layout = render_animation(dnet; n_frames=100)

export_html(layout, "my_animation.html";
    config=HTMLConfig(width=800, height=600, controls=true)
)
```

### Video Export

Video export requires FFmpeg to be installed on your system:

```julia
export_movie(layout, "my_animation.mp4";
    config=VideoConfig(fps=30, width=800, height=600, codec="h264")
)
```

### GIF Export

GIF export requires ImageMagick:

```julia
export_gif(layout, "my_animation.gif";
    config=GIFConfig(fps=10, width=400, height=400, loop=0)
)
```

## Interpolated Layout

For smoother animation between computed frames, use interpolated layouts:

```julia
# Compute base layout
base = layout_sequence(dnet, collect(0.0:20.0:100.0);
    algorithm=FRLayout()
)

# Create interpolated layout with linear interpolation
interp_linear = InterpolatedLayout(base; interpolation=:linear)

# Or with ease (smooth acceleration/deceleration)
interp_ease = InterpolatedLayout(base; interpolation=:ease)

# Query any vertex position at any time
pos = get_position(interp_ease, 1, 35.0)
println("Vertex 1 at t=35: x=$(pos[1]), y=$(pos[2])")
```

Interpolation modes:

| Mode | Formula | Effect |
|------|---------|--------|
| `:linear` | $p(t) = p_1 + \alpha(p_2 - p_1)$ | Constant velocity |
| `:ease` | Cubic ease-in-out | Smooth acceleration and deceleration |

## Complete Example: Epidemic Visualization

Here is a complete example combining multiple NDTV.jl features to visualize disease transmission through a contact network:

```julia
using NetworkDynamic
using NDTV

# Create a contact network with 10 individuals
dnet = DynamicNetwork(10; observation_start=0.0, observation_end=50.0)

# Activate all individuals
for i in 1:10
    activate!(dnet, 0.0, 50.0; vertex=i)
end

# Define contact patterns (edges)
contacts = [
    (1, 2, 0.0, 50.0),   # Household contacts
    (1, 3, 0.0, 50.0),
    (2, 4, 5.0, 40.0),   # Workplace contacts
    (3, 5, 5.0, 40.0),
    (4, 6, 10.0, 35.0),
    (5, 7, 10.0, 35.0),
    (6, 8, 15.0, 30.0),
    (7, 9, 15.0, 45.0),
    (8, 10, 20.0, 50.0),
]

for (i, j, t_start, t_end) in contacts
    activate!(dnet, t_start, t_end; edge=(i, j))
end

# Show the full timeline
println("=== Contact Timeline ===")
timeline_plot(dnet)

# Define transmission events
transmissions = [
    (1, 2, 3.0),    # Index case infects household member
    (1, 3, 5.0),
    (2, 4, 12.0),   # Workplace transmission
    (3, 5, 14.0),
    (4, 6, 22.0),   # Second wave
    (5, 7, 25.0),
]

# Show transmission timeline
println("\n=== Transmission Events ===")
transmissionTimeline(dnet, transmissions)

# Show proximity timeline for the index case
println("\n=== Index Case (Vertex 1) Contacts ===")
proximity_timeline(dnet, 1)

# Compute animation layout
layout = render_animation(dnet; n_frames=100, algorithm=FRLayout())

# Generate filmstrip at key time points
frames = filmstrip(dnet, [0.0, 10.0, 20.0, 30.0, 40.0, 50.0])
println("\n=== Network Snapshots ===")
for f in frames
    println("t=$(f.time): $(f.n_vertices) vertices, $(f.n_edges) edges")
end

# Export animation
export_html(layout, "epidemic_animation.html")
```

## Best Practices

1. **Start with timeline plots**: Use `timeline_plot` to understand your data before computing layouts
2. **Use anchored layouts**: Always keep `anchor=true` (default) for smooth animation transitions
3. **Choose frames wisely**: Start with 50 frames and increase only if transitions look choppy
4. **Seed for reproducibility**: Use `Random.seed!()` before layout computation for consistent results
5. **Match FPS to frames**: Total duration = n_frames / fps -- aim for 5-15 second animations
6. **Export to HTML first**: HTML export requires no dependencies and allows interactive exploration

## Next Steps

- Learn about [Animation Layout](@ref) algorithms and configuration
- Explore [Layout Algorithms](@ref) in detail
- Read about [Export](guide/export.md) options and formats
