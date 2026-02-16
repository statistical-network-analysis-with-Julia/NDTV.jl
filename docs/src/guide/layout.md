# Layout Algorithms

This guide covers the layout algorithms available in NDTV.jl for positioning vertices in dynamic network visualizations.

## Overview

Layout algorithms compute vertex positions -- $(x, y)$ coordinates -- for network visualizations. NDTV.jl provides four algorithms, each suited to different use cases:

| Algorithm | Type | Complexity | Best For |
|-----------|------|------------|----------|
| [`FRLayout`](@ref) | Force-directed | $O(n^2 \cdot \text{iters})$ | General networks |
| [`KKLayout`](@ref) | Energy-based | $O(n^2 \cdot \text{iters})$ | Small networks |
| [`CircleLayout`](@ref) | Geometric | $O(n)$ | Fixed-structure comparisons |
| [`RandomLayout`](@ref) | Random | $O(n)$ | Initial exploration |

## Fruchterman-Reingold Layout

The Fruchterman-Reingold (FR) algorithm is the default layout method and the most commonly used for network visualization. It treats the graph as a physical system of charged particles connected by springs.

### Algorithm

The FR algorithm works by simulating forces between vertices:

1. **Repulsive forces** push all vertex pairs apart (like charged particles):

```math
f_r(d) = \frac{k^2}{d}
```

2. **Attractive forces** pull connected vertices together (like springs):

```math
f_a(d) = \frac{d^2}{k}
```

where $d$ is the distance between two vertices and $k = \sqrt{\text{area} / n}$ is the optimal vertex spacing.

3. **Simulated annealing** gradually reduces a temperature parameter that limits vertex movement, allowing the layout to settle into a stable configuration.

### Usage

```julia
# Default parameters
layout = compute_slice_layout(dnet, 50.0; algorithm=FRLayout())

# Custom parameters
fr = FRLayout(
    iterations=200,   # More iterations for better convergence
    cooling=0.98,     # Slower cooling for more exploration
    k=1.5             # Larger spacing between vertices
)
layout = compute_slice_layout(dnet, 50.0; algorithm=fr)
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `iterations` | `Int` | `100` | Number of simulation steps |
| `cooling` | `Float64` | `0.95` | Temperature reduction factor per iteration |
| `k` | `Float64` | `1.0` | Scaling factor for optimal vertex spacing |

### How Parameters Affect Layout

**Iterations**: Controls convergence quality. Too few iterations produce messy layouts; too many waste computation.

```julia
# Quick but rough
FRLayout(iterations=30)

# Standard quality
FRLayout(iterations=100)

# High quality (slow)
FRLayout(iterations=300)
```

**Cooling**: Controls how quickly the system "freezes." Higher values (closer to 1.0) allow more exploration but slower convergence.

```julia
# Fast convergence, may get stuck in local minima
FRLayout(cooling=0.85)

# Balanced (default)
FRLayout(cooling=0.95)

# Slow convergence, better global structure
FRLayout(cooling=0.99)
```

**k (spacing)**: Scales the optimal distance between vertices. Larger values spread the layout out.

```julia
# Compact layout
FRLayout(k=0.5)

# Standard spacing
FRLayout(k=1.0)

# Spread out
FRLayout(k=2.0)
```

### Implementation Details

The NDTV.jl implementation:

- Initializes vertex positions randomly in $[-1, 1] \times [-1, 1]$
- Computes all pairwise repulsive forces: $O(n^2)$ per iteration
- Computes attractive forces for each edge: $O(m)$ per iteration
- Limits displacement by the current temperature: $\text{disp}_{\text{max}} = \text{temp}$
- Clamps positions to $[-1, 1]$ bounds
- Reduces temperature by the cooling factor each iteration

For anchored layouts (used in animation sequences), the algorithm:
- Starts from previous frame positions (not random)
- Uses half the temperature ($0.5$ instead of $1.0$)
- Runs half the iterations
- This preserves layout stability while allowing gradual adaptation

## Kamada-Kawai Layout

The Kamada-Kawai (KK) algorithm minimizes an energy function based on graph-theoretic distances. It tries to make the Euclidean distance between any two vertices proportional to their shortest-path distance in the graph.

### Algorithm

KK minimizes the stress energy:

```math
E = \sum_{i<j} k_{ij} \left( \|p_i - p_j\| - d_{ij} \right)^2
```

where:
- $d_{ij}$ is the graph-theoretic distance (shortest path length) between vertices $i$ and $j$
- $k_{ij} = 1/d_{ij}^2$ is the spring constant (closer vertices are more strongly constrained)
- $\|p_i - p_j\|$ is the Euclidean distance between vertex positions

### Usage

```julia
kk = KKLayout(
    iterations=100,
    epsilon=1e-4
)

layout = compute_slice_layout(dnet, 50.0; algorithm=kk)
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `iterations` | `Int` | `100` | Maximum number of optimization steps |
| `epsilon` | `Float64` | `1e-4` | Convergence threshold |

### When to Use KK

KK produces high-quality layouts that respect graph distances, but it is more expensive than FR for large networks. Use KK when:

- The network has fewer than ~50 vertices
- You want distances in the layout to reflect graph-theoretic distances
- The network has a clear hierarchical or tree-like structure
- You need reproducible, stable layouts

```julia
# Small network with clear structure
kk = KKLayout(iterations=200, epsilon=1e-5)
layout = render_animation(dnet; algorithm=kk, n_frames=50)
```

## Circle Layout

The circle layout places all vertices evenly around a circle. This ignores network structure entirely but provides a stable reference layout.

### Usage

```julia
# Default circle
circle = CircleLayout()

# Custom radius and starting angle
circle = CircleLayout(
    radius=2.0,        # Larger circle
    start_angle=π/4    # Start from 45 degrees
)

layout = compute_slice_layout(dnet, 50.0; algorithm=circle)
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `radius` | `Float64` | `1.0` | Circle radius |
| `start_angle` | `Float64` | `0.0` | Angle (radians) for the first vertex |

### Vertex Placement

Vertex $i$ is placed at:

```math
x_i = r \cos\left(\theta_0 + \frac{2\pi(i-1)}{n}\right), \quad
y_i = r \sin\left(\theta_0 + \frac{2\pi(i-1)}{n}\right)
```

where $r$ is the radius, $\theta_0$ is the start angle, and $n$ is the number of vertices.

### When to Use Circle Layout

- **Comparing networks**: Same vertex positions across different time points
- **Adjacency visualization**: Focus on edge patterns rather than spatial structure
- **Reference layout**: A baseline for comparing with force-directed results
- **Animation stability**: Perfectly stable positions (no layout drift)

```julia
# Compare network structure at two time points using identical vertex positions
pos_early = compute_slice_layout(dnet, 10.0; algorithm=CircleLayout())
pos_late = compute_slice_layout(dnet, 90.0; algorithm=CircleLayout())
# Only edges differ -- vertices are in the same positions
```

## Random Layout

The random layout places vertices uniformly at random within specified bounds. This is the fastest layout but provides no structural information.

### Usage

```julia
# Default bounds [0, 1] x [0, 1]
random = RandomLayout()

# Custom bounds
random = RandomLayout(
    xmin=-2.0, xmax=2.0,
    ymin=-2.0, ymax=2.0
)

layout = compute_slice_layout(dnet, 50.0; algorithm=random)
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `xmin` | `Float64` | `0.0` | Minimum x coordinate |
| `xmax` | `Float64` | `1.0` | Maximum x coordinate |
| `ymin` | `Float64` | `0.0` | Minimum y coordinate |
| `ymax` | `Float64` | `1.0` | Maximum y coordinate |

### When to Use Random Layout

- **Quick exploration**: Get an immediate (if uninformative) view
- **Stress testing**: Verify that visualization code handles arbitrary positions
- **Starting point**: Initialize positions before applying a force-directed refinement
- **Baseline comparison**: Measure how much structure a force-directed layout reveals

## Choosing an Algorithm

### Decision Guide

```text
Is your network small (<50 vertices)?
├── Yes: Do you care about graph distances?
│   ├── Yes → KKLayout
│   └── No → FRLayout
└── No: Is speed critical?
    ├── Yes → CircleLayout or RandomLayout
    └── No → FRLayout (with reduced iterations if needed)
```

### Visual Comparison

Consider a network with community structure:

| Algorithm | Reveals Structure? | Stable? | Speed |
|-----------|-------------------|---------|-------|
| FR | Yes -- communities cluster | With anchoring | Medium |
| KK | Yes -- distances are meaningful | High | Slow |
| Circle | No -- all vertices equidistant | Perfect | Fast |
| Random | No -- positions are meaningless | None | Fast |

### Combining Algorithms

You can use different algorithms at different stages:

```julia
# Use circle layout for the first frame (stable starting point)
# Then switch to FR for the rest
first_pos = compute_slice_layout(dnet, 0.0; algorithm=CircleLayout())

# Use FR with anchoring for subsequent frames
times = collect(10.0:10.0:100.0)
positions = [first_pos]
for t in times
    snapshot = network_extract(dnet, t)
    pos = compute_layout_anchored(snapshot, FRLayout(), positions[end])
    push!(positions, pos)
end
```

## Layout for Dynamic Networks

### Anchored Layout Computation

When computing layouts for animation, NDTV.jl uses the previous frame's positions as starting points. This is the key to smooth animation:

```julia
# Automatically uses anchoring
layout = layout_sequence(dnet, times; anchor=true)
```

The anchored computation:
1. Copies positions from the previous frame
2. New vertices get random positions
3. Runs the layout algorithm with reduced temperature
4. Positions gradually adapt to structural changes

### Handling Vertex Appearance and Disappearance

When a vertex appears in a new frame:
- It receives a random initial position
- The layout algorithm positions it near its neighbors
- Over subsequent frames, it settles into a stable position

When a vertex disappears:
- Its position is simply dropped from the frame
- Remaining vertices may shift slightly to fill the gap

When a vertex reappears after a gap:
- It gets a new random position (its old position is not remembered)
- It settles near its current neighbors, which may differ from before

## Advanced Topics

### Reproducible Layouts

Force-directed layouts use random initialization. For reproducible results, seed the random number generator:

```julia
using Random
Random.seed!(42)

layout = render_animation(dnet; n_frames=100, algorithm=FRLayout())
```

### Layout Bounds

Every `DynamicLayout` has a `bounds` field computed from all vertex positions across all frames:

```julia
layout = render_animation(dnet; n_frames=100)
xmin, xmax, ymin, ymax = layout.bounds

# Use for consistent scaling across frames
width = xmax - xmin
height = ymax - ymin
```

### Custom Layout Functions

You can use `compute_layout` directly on a static `Network`:

```julia
using Network

# Create a static network
net = Network(5; directed=false)
add_edge!(net, 1, 2)
add_edge!(net, 2, 3)
add_edge!(net, 3, 4)

# Compute layout
positions = compute_layout(net, FRLayout(iterations=200))
```
