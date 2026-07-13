"""
    NDTV.jl - Network Dynamic Temporal Visualization

Provides tools for visualizing dynamic networks including animations,
timeline plots, filmstrip displays, and layout algorithms.

Vertex identity is stable across time: snapshots are extracted with
`retain_all_vertices=true`, so every layout, anchor, and interpolation is
keyed by the network's persistent vertex IDs even when vertices activate
and deactivate over time.

Port of the R ndtv package from the StatNet collection.
"""
module NDTV

using Dates
using Graphs
using LinearAlgebra
using Networks
using NetworkDynamic
using Random

# Animation
export render_animation, compute_animation_layout
export export_movie, export_gif, export_html, export_frames

# Timeline visualization
export timeline_plot, proximity_timeline
export transmission_timeline, transmissionTimeline, timeline_data

# Filmstrip
export filmstrip, slice_layout

# Layout algorithms
export DynamicLayout, InterpolatedLayout
export compute_slice_layout, layout_sequence, compute_layout
export FRLayout, MDSLayout, CircleLayout, RandomLayout
# Deprecated alias: this layout is classical MDS of geodesic distances, not
# the iterative Kamada-Kawai energy minimization the old name implied.
export KKLayout
export get_position

# Export formats
export ExportConfig, VideoConfig, GIFConfig, HTMLConfig

# =============================================================================
# Layout Types
# =============================================================================

"""
    DynamicLayout{T, Time}

Layout positions for dynamic network visualization across time. All
dictionaries are keyed by **stable vertex IDs** (the dynamic network's own
IDs), never by per-slice indices.

# Fields
- `positions::Vector{Dict{T, Tuple{Float64, Float64}}}`: Positions per frame
- `times::Vector{Time}`: Frame time points (any NetworkDynamic time type)
- `bounds::Tuple{Float64, Float64, Float64, Float64}`: (xmin, xmax, ymin, ymax)
- `frame_edges::Vector{Vector{Tuple{T, T}}}`: Active edges per frame
- `frame_active::Vector{Vector{T}}`: Active vertices per frame
"""
struct DynamicLayout{T, Time}
    positions::Vector{Dict{T, Tuple{Float64, Float64}}}
    times::Vector{Time}
    bounds::Tuple{Float64, Float64, Float64, Float64}
    frame_edges::Vector{Vector{Tuple{T, T}}}
    frame_active::Vector{Vector{T}}

    function DynamicLayout(positions::Vector{Dict{T, Tuple{Float64, Float64}}},
                           times::Vector{Time};
                           frame_edges::Vector{Vector{Tuple{T, T}}}=
                               [Tuple{T, T}[] for _ in times],
                           frame_active::Vector{Vector{T}}=
                               [T[] for _ in times]) where {T, Time}
        length(positions) == length(times) ||
            throw(ArgumentError("positions and times must have same length"))
        length(frame_edges) == length(times) ||
            throw(ArgumentError("frame_edges and times must have same length"))
        length(frame_active) == length(times) ||
            throw(ArgumentError("frame_active and times must have same length"))

        all_x = Float64[]
        all_y = Float64[]
        for pos_dict in positions
            for (x, y) in values(pos_dict)
                push!(all_x, x)
                push!(all_y, y)
            end
        end

        bounds = if isempty(all_x)
            (0.0, 1.0, 0.0, 1.0)
        else
            (minimum(all_x), maximum(all_x), minimum(all_y), maximum(all_y))
        end

        new{T, Time}(positions, times, bounds, frame_edges, frame_active)
    end
end

Base.length(dl::DynamicLayout) = length(dl.times)
Base.getindex(dl::DynamicLayout, i::Int) = dl.positions[i]

"""
    InterpolatedLayout{T, Time}

Layout with smooth interpolation between time points (`:linear` or
`:ease`).
"""
struct InterpolatedLayout{T, Time}
    base_layout::DynamicLayout{T, Time}
    interpolation::Symbol

    InterpolatedLayout(base::DynamicLayout{T, Time};
                       interpolation::Symbol=:linear) where {T, Time} =
        new{T, Time}(base, interpolation)
end

"""
    get_position(layout::InterpolatedLayout, vertex, time) -> Tuple{Float64, Float64}

Interpolated position of a (stable-ID) vertex at any time point. Works
for any time type supporting subtraction with `/` (numbers, `DateTime`).
"""
function get_position(layout::InterpolatedLayout{T, Time}, vertex::T, time) where {T, Time}
    times = layout.base_layout.times
    positions = layout.base_layout.positions

    idx = searchsortedlast(times, time)

    if idx == 0
        return get(positions[1], vertex, (0.0, 0.0))
    elseif idx == length(times)
        return get(positions[end], vertex, (0.0, 0.0))
    else
        t1, t2 = times[idx], times[idx + 1]
        pos1 = get(positions[idx], vertex, (0.0, 0.0))
        pos2 = get(positions[idx + 1], vertex, (0.0, 0.0))

        alpha = t2 == t1 ? 0.0 : (time - t1) / (t2 - t1)

        if layout.interpolation == :ease
            alpha = alpha < 0.5 ? 2 * alpha^2 : 1 - (-2 * alpha + 2)^2 / 2
        end

        x = pos1[1] + alpha * (pos2[1] - pos1[1])
        y = pos1[2] + alpha * (pos2[2] - pos1[2])

        return (x, y)
    end
end

# =============================================================================
# Layout Algorithms
# =============================================================================

"""
    FRLayout(; iterations=100, cooling=0.95, k=1.0)

Fruchterman-Reingold force-directed layout parameters.
"""
struct FRLayout
    iterations::Int
    cooling::Float64
    k::Float64

    FRLayout(; iterations::Int=100, cooling::Float64=0.95, k::Float64=1.0) =
        new(iterations, cooling, k)
end

"""
    CircleLayout(; radius=1.0, start_angle=0.0)

Vertices evenly spaced on a circle (deterministic).
"""
struct CircleLayout
    radius::Float64
    start_angle::Float64

    CircleLayout(; radius::Float64=1.0, start_angle::Float64=0.0) = new(radius, start_angle)
end

"""
    RandomLayout(; xmin=0.0, xmax=1.0, ymin=0.0, ymax=1.0)

Uniform random positions within the given bounds.
"""
struct RandomLayout
    bounds::Tuple{Float64, Float64, Float64, Float64}

    RandomLayout(; xmin::Float64=0.0, xmax::Float64=1.0,
                   ymin::Float64=0.0, ymax::Float64=1.0) =
        new((xmin, xmax, ymin, ymax))
end

"""
    MDSLayout()

**Classical multidimensional scaling (Torgerson scaling) of the geodesic
distance matrix.** The squared-distance matrix is double-centred and the
top two eigenvectors of the resulting Gram matrix give the coordinates, so
Euclidean distances in the plane approximate graph distances. Deterministic
and non-iterative (a single eigendecomposition, no random start, no `rng`
dependence); unreachable pairs are assigned the maximum finite distance
plus one.

!!! note "This is not Kamada-Kawai"
    This layout was previously called `KKLayout` and documented as
    "Kamada-Kawai-style". That name was misleading: the true Kamada–Kawai
    algorithm (Kamada & Kawai 1989) *iteratively minimizes a spring energy*
    ``\\sum_{i<j} \\tfrac{1}{2} k_{ij}(\\|p_i - p_j\\| - d_{ij})^2`` by
    Newton–Raphson on vertex positions. Nothing of the sort happens here —
    classical MDS solves an eigenproblem in closed form and optimizes a
    different (strain, not stress) criterion. The two give similar pictures
    on small well-connected graphs but are different algorithms with
    different fixed points. [`KKLayout`](@ref) remains as a deprecated
    alias; use `MDSLayout`.
"""
struct MDSLayout end

"""
    KKLayout()

!!! warning "Deprecated — renamed to [`MDSLayout`](@ref)"
    This name implied the iterative Kamada–Kawai energy minimization, which
    this package does not implement: the layout is, and always was,
    classical MDS of the geodesic distance matrix. It has been renamed to
    [`MDSLayout`](@ref) to say what it actually computes. `KKLayout` is an
    alias for `MDSLayout` and will be removed in a future release.
"""
const KKLayout = MDSLayout

# The FR core, shared by fresh and anchored variants
function _fr_iterate!(pos_x, pos_y, net, alg::FRLayout, iterations::Int, temp0::Float64)
    n = length(pos_x)
    n == 0 && return
    area = 4.0
    k = alg.k * sqrt(area / n)
    temp = temp0

    for _ in 1:iterations
        disp_x = zeros(n)
        disp_y = zeros(n)

        for i in 1:n, j in (i+1):n
            dx = pos_x[i] - pos_x[j]
            dy = pos_y[i] - pos_y[j]
            dist = sqrt(dx^2 + dy^2) + 0.01

            force = k^2 / dist
            disp_x[i] += dx / dist * force
            disp_y[i] += dy / dist * force
            disp_x[j] -= dx / dist * force
            disp_y[j] -= dy / dist * force
        end

        for e in edges(net)
            i, j = src(e), dst(e)
            dx = pos_x[i] - pos_x[j]
            dy = pos_y[i] - pos_y[j]
            dist = sqrt(dx^2 + dy^2) + 0.01

            force = dist^2 / k
            disp_x[i] -= dx / dist * force
            disp_y[i] -= dy / dist * force
            disp_x[j] += dx / dist * force
            disp_y[j] += dy / dist * force
        end

        for i in 1:n
            disp_len = sqrt(disp_x[i]^2 + disp_y[i]^2) + 0.01
            pos_x[i] += disp_x[i] / disp_len * min(temp, disp_len)
            pos_y[i] += disp_y[i] / disp_len * min(temp, disp_len)
            pos_x[i] = clamp(pos_x[i], -1, 1)
            pos_y[i] = clamp(pos_y[i], -1, 1)
        end

        temp *= alg.cooling
    end
end

"""
    compute_layout(net::Network, algorithm; rng=Random.default_rng())
        -> Dict{T, Tuple{Float64, Float64}}

Compute a static layout keyed by the network's vertex IDs.
"""
function compute_layout(net::Network{T}, alg::FRLayout;
                        rng::Random.AbstractRNG=Random.default_rng()) where T
    n = Int(nv(net))
    n == 0 && return Dict{T, Tuple{Float64, Float64}}()

    pos_x = rand(rng, n) .* 2 .- 1
    pos_y = rand(rng, n) .* 2 .- 1
    _fr_iterate!(pos_x, pos_y, net, alg, alg.iterations, 1.0)

    return Dict(T(i) => (pos_x[i], pos_y[i]) for i in 1:n)
end

function compute_layout(net::Network{T}, alg::CircleLayout;
                        rng::Random.AbstractRNG=Random.default_rng()) where T
    n = Int(nv(net))
    n == 0 && return Dict{T, Tuple{Float64, Float64}}()

    positions = Dict{T, Tuple{Float64, Float64}}()
    for i in 1:n
        angle = alg.start_angle + 2π * (i - 1) / n
        positions[T(i)] = (alg.radius * cos(angle), alg.radius * sin(angle))
    end

    return positions
end

function compute_layout(net::Network{T}, alg::RandomLayout;
                        rng::Random.AbstractRNG=Random.default_rng()) where T
    n = Int(nv(net))
    xmin, xmax, ymin, ymax = alg.bounds

    positions = Dict{T, Tuple{Float64, Float64}}()
    for i in 1:n
        x = xmin + rand(rng) * (xmax - xmin)
        y = ymin + rand(rng) * (ymax - ymin)
        positions[T(i)] = (x, y)
    end

    return positions
end

function compute_layout(net::Network{T}, ::MDSLayout;
                        rng::Random.AbstractRNG=Random.default_rng()) where T
    n = Int(nv(net))
    n == 0 && return Dict{T, Tuple{Float64, Float64}}()
    n == 1 && return Dict(T(1) => (0.0, 0.0))

    # Geodesic distances, symmetrized; unreachable pairs capped
    D = fill(Inf, n, n)
    for i in 1:n
        dist = Graphs.gdistances(net.graph, i)
        for j in 1:n
            dist[j] < typemax(Int) && (D[i, j] = Float64(dist[j]))
        end
    end
    D = min.(D, transpose(D))
    finite = filter(isfinite, D)
    cap = isempty(finite) ? 1.0 : maximum(finite) + 1.0
    D = map(d -> isfinite(d) ? d : cap, D)

    # Classical MDS
    D2 = D .^ 2
    J = Matrix{Float64}(I, n, n) .- 1.0 / n
    B = -0.5 .* (J * D2 * J)
    B = (B + transpose(B)) ./ 2

    ev = eigen(Symmetric(B))
    order = sortperm(ev.values; rev=true)
    coords = Matrix{Float64}(undef, n, 2)
    for (c, idx) in enumerate(order[1:2])
        λ = max(ev.values[idx], 0.0)
        coords[:, c] = ev.vectors[:, idx] .* sqrt(λ)
    end

    # Normalize into [-1, 1]
    m = maximum(abs.(coords))
    m > 0 && (coords ./= m)

    return Dict(T(i) => (coords[i, 1], coords[i, 2]) for i in 1:n)
end

# --- Anchored variants: seed positions from the previous frame so motion
# --- is smooth. Deterministic layouts simply recompute.

"""
    compute_layout_anchored(net, algorithm, prev_positions; rng=...)

Layout seeded from the previous frame's positions (matched by stable
vertex ID) so consecutive frames move smoothly. Deterministic layouts
(`CircleLayout`, `MDSLayout`) recompute their fixed coordinates; for
`RandomLayout` existing vertices keep their previous position.
"""
function compute_layout_anchored(net::Network{T}, alg::FRLayout,
                                 prev_positions::Dict{T, Tuple{Float64, Float64}};
                                 rng::Random.AbstractRNG=Random.default_rng()) where T
    n = Int(nv(net))
    n == 0 && return Dict{T, Tuple{Float64, Float64}}()

    pos_x = zeros(n)
    pos_y = zeros(n)
    for i in 1:n
        if haskey(prev_positions, T(i))
            pos_x[i], pos_y[i] = prev_positions[T(i)]
        else
            pos_x[i] = rand(rng) * 2 - 1
            pos_y[i] = rand(rng) * 2 - 1
        end
    end

    # Fewer iterations at lower temperature: refine, don't re-solve
    _fr_iterate!(pos_x, pos_y, net, alg, max(alg.iterations ÷ 2, 1), 0.5)

    return Dict(T(i) => (pos_x[i], pos_y[i]) for i in 1:n)
end

function compute_layout_anchored(net::Network{T}, alg::RandomLayout,
                                 prev_positions::Dict{T, Tuple{Float64, Float64}};
                                 rng::Random.AbstractRNG=Random.default_rng()) where T
    positions = compute_layout(net, alg; rng=rng)
    for (v, p) in prev_positions
        haskey(positions, v) && (positions[v] = p)
    end
    return positions
end

# Deterministic algorithms: anchoring is a no-op recomputation
compute_layout_anchored(net::Network, alg::Union{CircleLayout, MDSLayout},
                        prev_positions;
                        rng::Random.AbstractRNG=Random.default_rng()) =
    compute_layout(net, alg; rng=rng)

# Evenly spaced frame times for any supported time type
_lerp_time(t0, t1, frac::Float64) = t0 + (t1 - t0) * frac
_lerp_time(t0::DateTime, t1::DateTime, frac::Float64) =
    t0 + Millisecond(round(Int, Dates.value(Millisecond(t1 - t0)) * frac))
_lerp_time(t0::Date, t1::Date, frac::Float64) =
    t0 + Day(round(Int, Dates.value(Day(t1 - t0)) * frac))

function _frame_times(start_time, end_time, n::Int)
    n >= 1 || throw(ArgumentError("need at least one frame"))
    n == 1 && return [start_time]
    return [_lerp_time(start_time, end_time, (i - 1) / (n - 1)) for i in 1:n]
end

# =============================================================================
# Dynamic Layout Computation
# =============================================================================

# Snapshot with stable vertex IDs: every base vertex is retained, so
# position dictionaries are keyed by persistent identity
_snapshot(dnet, t) = network_extract(dnet, t; retain_all_vertices=true)

"""
    compute_slice_layout(dnet::DynamicNetwork, time; algorithm=FRLayout(),
                         rng=...) -> Dict

Layout for the network snapshot at one time point, keyed by the dynamic
network's stable vertex IDs (all vertices are retained; inactive ones are
placed as isolates).
"""
function compute_slice_layout(dnet::DynamicNetwork{T, Time}, time;
                              algorithm=FRLayout(),
                              rng::Random.AbstractRNG=Random.default_rng()) where {T, Time}
    return compute_layout(_snapshot(dnet, time), algorithm; rng=rng)
end

"""
    layout_sequence(dnet::DynamicNetwork, times; algorithm=FRLayout(),
                    anchor=true, rng=...) -> DynamicLayout

Layouts for a sequence of time points. With `anchor=true` (default) each
frame is seeded from the previous frame's positions — matched by stable
vertex ID — so vertices move smoothly. Per-frame active vertices and
edges are recorded for rendering.
"""
function layout_sequence(dnet::DynamicNetwork{T, Time}, times::AbstractVector;
                         algorithm=FRLayout(), anchor::Bool=true,
                         rng::Random.AbstractRNG=Random.default_rng()) where {T, Time}
    positions = Dict{T, Tuple{Float64, Float64}}[]
    frame_edges = Vector{Tuple{T, T}}[]
    frame_active = Vector{T}[]
    prev_positions = nothing

    for t in times
        snapshot = _snapshot(dnet, t)

        pos = if anchor && !isnothing(prev_positions)
            compute_layout_anchored(snapshot, algorithm, prev_positions; rng=rng)
        else
            compute_layout(snapshot, algorithm; rng=rng)
        end

        push!(positions, pos)
        push!(frame_edges, [(T(src(e)), T(dst(e))) for e in edges(snapshot)])
        push!(frame_active, T.(active_vertices(dnet, t)))
        prev_positions = pos
    end

    return DynamicLayout(positions, collect(times);
                         frame_edges=frame_edges, frame_active=frame_active)
end

# =============================================================================
# Animation Rendering
# =============================================================================

"""
    render_animation(dnet::DynamicNetwork; algorithm=FRLayout(),
                     n_frames=100, interpolation=:linear, rng=...)

Compute layout positions for animating a dynamic network over its
observation period. Works for any NetworkDynamic time type (including
`DateTime`). Returns a [`DynamicLayout`](@ref) (`interpolation = :linear`
or `:none`) or an [`InterpolatedLayout`](@ref) (`interpolation = :ease`).
"""
function render_animation(dnet::DynamicNetwork{T, Time};
                          algorithm=FRLayout(),
                          n_frames::Int=100,
                          interpolation::Symbol=:linear,
                          rng::Random.AbstractRNG=Random.default_rng()) where {T, Time}
    start_time, end_time = dnet.observation_period
    times = _frame_times(start_time, end_time, n_frames)

    base_layout = layout_sequence(dnet, times; algorithm=algorithm, rng=rng)

    if interpolation == :linear || interpolation == :none
        return base_layout
    else
        return InterpolatedLayout(base_layout; interpolation=interpolation)
    end
end

const compute_animation_layout = render_animation

# =============================================================================
# Timeline Visualization
# =============================================================================

# Fraction of the observation window elapsed at time t (0 when degenerate)
function _time_frac(t, start_time, end_time)
    end_time == start_time && return 0.0
    return (t - start_time) / (end_time - start_time)
end

_time_pos(t, start_time, end_time, width) =
    round(Int, _time_frac(t, start_time, end_time) * (width - 1)) + 1

"""
    timeline_data(dnet::DynamicNetwork) -> NamedTuple

Extract raw vertex/edge spell data for visualization.
"""
function timeline_data(dnet::DynamicNetwork{T, Time}) where {T, Time}
    vertex_data = NamedTuple{(:vertex, :onset, :terminus), Tuple{T, Time, Time}}[]
    edge_data = NamedTuple{(:source, :target, :onset, :terminus), Tuple{T, T, Time, Time}}[]

    for (v, spells) in dnet.vertex_spells
        for spell in spells
            push!(vertex_data, (vertex=v, onset=spell.onset, terminus=spell.terminus))
        end
    end

    for ((i, j), spells) in dnet.edge_spells
        for spell in spells
            push!(edge_data, (source=i, target=j, onset=spell.onset, terminus=spell.terminus))
        end
    end

    return (vertices=vertex_data, edges=edge_data)
end

"""
    timeline_plot(dnet::DynamicNetwork; width=60, io=stdout)

ASCII timeline of vertex and edge activity spells.
"""
function timeline_plot(dnet::DynamicNetwork{T, Time}; width::Int=60,
                       io::IO=stdout) where {T, Time}
    start_time, end_time = dnet.observation_period

    println(io, "Timeline: $start_time to $end_time")
    println(io, "=" ^ width)

    println(io, "\nVertices:")
    for v in 1:nv(dnet)
        spells = get(dnet.vertex_spells, T(v), Spell{Time}[])
        line = fill(' ', width)

        for spell in spells
            start_pos = _time_pos(spell.onset, start_time, end_time, width)
            end_pos = _time_pos(spell.terminus, start_time, end_time, width)
            for p in start_pos:end_pos
                1 <= p <= width && (line[p] = '─')
            end
        end

        println(io, "V$v: |$(String(line))|")
    end

    println(io, "\nEdges:")
    for ((i, j), spells) in dnet.edge_spells
        line = fill(' ', width)

        for spell in spells
            start_pos = _time_pos(spell.onset, start_time, end_time, width)
            end_pos = _time_pos(spell.terminus, start_time, end_time, width)
            for p in start_pos:end_pos
                1 <= p <= width && (line[p] = '═')
            end
        end

        println(io, "$i→$j: |$(String(line))|")
    end

    return nothing
end

"""
    proximity_timeline(dnet::DynamicNetwork, vertex; width=60, io=stdout)

Ego-centric ASCII timeline: activity spells of all edges incident to
`vertex`.
"""
function proximity_timeline(dnet::DynamicNetwork{T, Time}, vertex::T;
                            width::Int=60, io::IO=stdout) where {T, Time}
    start_time, end_time = dnet.observation_period

    println(io, "Proximity timeline for vertex $vertex")
    println(io, "=" ^ width)

    for ((i, j), spells) in dnet.edge_spells
        (i == vertex || j == vertex) || continue
        other = i == vertex ? j : i
        direction = i == vertex ? "→" : "←"

        line = fill(' ', width)
        for spell in spells
            start_pos = _time_pos(spell.onset, start_time, end_time, width)
            end_pos = _time_pos(spell.terminus, start_time, end_time, width)
            for p in start_pos:end_pos
                1 <= p <= width && (line[p] = '═')
            end
        end

        println(io, "$direction V$other: |$(String(line))|")
    end

    return nothing
end

"""
    transmission_timeline(dnet::DynamicNetwork, transmissions; width=60, io=stdout)

ASCII timeline marking transmission events `(from, to, time)`.

Also available under the R-style alias `transmissionTimeline` (matching
`ndtv::transmissionTimeline`).
"""
function transmission_timeline(dnet::DynamicNetwork{T, Time},
                               transmissions::Vector{Tuple{T, T, Time}};
                               width::Int=60, io::IO=stdout) where {T, Time}
    start_time, end_time = dnet.observation_period

    println(io, "Transmission Timeline")
    println(io, "=" ^ width)

    for (from, to, time) in transmissions
        pos = _time_pos(time, start_time, end_time, width)
        line = fill(' ', width)
        1 <= pos <= width && (line[pos] = '*')
        println(io, "$from→$to: |$(String(line))| t=$time")
    end

    return nothing
end

"""
    transmissionTimeline

R-style alias for [`transmission_timeline`](@ref).
"""
const transmissionTimeline = transmission_timeline

# =============================================================================
# Filmstrip Visualization
# =============================================================================

"""
    filmstrip(dnet::DynamicNetwork, times; algorithm=FRLayout(), rng=...)

Layout frames at the given times for filmstrip (small-multiples) display.
Each frame records positions (stable IDs), the active vertex set, active
edges, and their counts.
"""
function filmstrip(dnet::DynamicNetwork{T, Time}, times::AbstractVector;
                   algorithm=FRLayout(),
                   rng::Random.AbstractRNG=Random.default_rng()) where {T, Time}
    layout = layout_sequence(dnet, times; algorithm=algorithm, rng=rng)

    frames = NamedTuple[]
    for (i, t) in enumerate(times)
        push!(frames, (
            time=t,
            positions=layout[i],
            active=layout.frame_active[i],
            edges=layout.frame_edges[i],
            n_vertices=length(layout.frame_active[i]),
            n_edges=length(layout.frame_edges[i])
        ))
    end

    return frames
end

"""
    slice_layout(dnet::DynamicNetwork, onset, terminus; n_slices=5,
                 algorithm=FRLayout(), rng=...)

Filmstrip frames over `n_slices` evenly spaced times in
`[onset, terminus]`.
"""
function slice_layout(dnet::DynamicNetwork{T, Time}, onset, terminus;
                      n_slices::Int=5, algorithm=FRLayout(),
                      rng::Random.AbstractRNG=Random.default_rng()) where {T, Time}
    times = _frame_times(onset, terminus, n_slices)
    return filmstrip(dnet, times; algorithm=algorithm, rng=rng)
end

# =============================================================================
# Export Functions
# =============================================================================

"""
    ExportConfig

Abstract base type for all export configuration types.
Subtypes: [`VideoConfig`](@ref), [`GIFConfig`](@ref), [`HTMLConfig`](@ref).
"""
abstract type ExportConfig end

"""
    VideoConfig(; fps=30, width=800, height=600, codec="h264")

Configuration for video (MP4) export. Requires the `ffmpeg` binary.
"""
struct VideoConfig <: ExportConfig
    fps::Int
    width::Int
    height::Int
    codec::String

    VideoConfig(; fps::Int=30, width::Int=800, height::Int=600, codec::String="h264") =
        new(fps, width, height, codec)
end

"""
    GIFConfig(; fps=10, width=400, height=400, loop=0)

Configuration for GIF export. Requires the ImageMagick `magick`/`convert`
binary.
"""
struct GIFConfig <: ExportConfig
    fps::Int
    width::Int
    height::Int
    loop::Int

    GIFConfig(; fps::Int=10, width::Int=400, height::Int=400, loop::Int=0) =
        new(fps, width, height, loop)
end

"""
    HTMLConfig(; width=800, height=600, controls=true)

Configuration for HTML export (self-contained; no external dependencies).
"""
struct HTMLConfig <: ExportConfig
    width::Int
    height::Int
    controls::Bool

    HTMLConfig(; width::Int=800, height::Int=600, controls::Bool=true) =
        new(width, height, controls)
end

# Map layout coordinates into pixel space
function _to_pixels(pos::Tuple{Float64, Float64}, bounds, width, height; pad=20)
    xmin, xmax, ymin, ymax = bounds
    xr = xmax - xmin
    yr = ymax - ymin
    xr == 0 && (xr = 1.0)
    yr == 0 && (yr = 1.0)
    px = pad + (pos[1] - xmin) / xr * (width - 2pad)
    py = pad + (pos[2] - ymin) / yr * (height - 2pad)
    return (px, py)
end

# One SVG frame: active edges as lines, active vertices as circles
function _svg_frame(layout::DynamicLayout, frame::Int, width::Int, height::Int)
    pos = layout.positions[frame]
    active = Set(layout.frame_active[frame])
    parts = String[]
    push!(parts, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" " *
                 "height=\"$height\" viewBox=\"0 0 $width $height\">")
    push!(parts, "<rect width=\"$width\" height=\"$height\" fill=\"white\"/>")
    for (a, b) in layout.frame_edges[frame]
        (haskey(pos, a) && haskey(pos, b)) || continue
        pa = _to_pixels(pos[a], layout.bounds, width, height)
        pb = _to_pixels(pos[b], layout.bounds, width, height)
        push!(parts, "<line x1=\"$(round(pa[1], digits=2))\" y1=\"$(round(pa[2], digits=2))\" " *
                     "x2=\"$(round(pb[1], digits=2))\" y2=\"$(round(pb[2], digits=2))\" " *
                     "stroke=\"#7f8c8d\" stroke-width=\"1.5\"/>")
    end
    for (v, p) in pos
        v in active || continue
        pp = _to_pixels(p, layout.bounds, width, height)
        push!(parts, "<circle cx=\"$(round(pp[1], digits=2))\" cy=\"$(round(pp[2], digits=2))\" " *
                     "r=\"6\" fill=\"#2980b9\" stroke=\"#1a5276\"/>")
    end
    push!(parts, "</svg>")
    return join(parts, "\n")
end

"""
    export_frames(layout::DynamicLayout, dir::String;
                  width=800, height=600) -> Vector{String}

Render every frame of the animation to numbered SVG files in `dir`
(created if needed). Returns the file paths. This is the pure-Julia
rendering backend used by `export_movie`/`export_gif`.
"""
function export_frames(layout::DynamicLayout, dir::String;
                       width::Int=800, height::Int=600)
    mkpath(dir)
    paths = String[]
    for f in 1:length(layout)
        path = joinpath(dir, "frame_$(lpad(f, 5, '0')).svg")
        open(path, "w") do io
            write(io, _svg_frame(layout, f, width, height))
        end
        push!(paths, path)
    end
    return paths
end

"""
    export_movie(layout::DynamicLayout, filepath::String; config=VideoConfig())

Render the animation frames to SVG and encode a video with the `ffmpeg`
binary. Throws an informative error (leaving the rendered frames on disk)
when `ffmpeg` is not installed.
"""
function export_movie(layout::DynamicLayout, filepath::String;
                      config::VideoConfig=VideoConfig())
    dir = mktempdir()
    export_frames(layout, dir; width=config.width, height=config.height)

    ffmpeg = Sys.which("ffmpeg")
    isnothing(ffmpeg) && error(
        "export_movie requires the `ffmpeg` binary, which was not found on " *
        "PATH. The rendered SVG frames are in $dir")

    run(`$ffmpeg -y -framerate $(config.fps) -i $(joinpath(dir, "frame_%05d.svg"))
         -c:v $(config.codec) -pix_fmt yuv420p $filepath`)
    return (filepath=filepath, n_frames=length(layout), fps=config.fps)
end

"""
    export_gif(layout::DynamicLayout, filepath::String; config=GIFConfig())

Render the animation frames to SVG and assemble an animated GIF with
ImageMagick. Throws an informative error (leaving the rendered frames on
disk) when ImageMagick is not installed.
"""
function export_gif(layout::DynamicLayout, filepath::String;
                    config::GIFConfig=GIFConfig())
    dir = mktempdir()
    frames = export_frames(layout, dir; width=config.width, height=config.height)

    magick = something(Sys.which("magick"), Sys.which("convert"), Some(nothing))
    isnothing(magick) && error(
        "export_gif requires ImageMagick (`magick` or `convert`), which was " *
        "not found on PATH. The rendered SVG frames are in $dir")

    delay = max(round(Int, 100 / config.fps), 1)
    run(`$magick -delay $delay -loop $(config.loop) $frames $filepath`)
    return (filepath=filepath, n_frames=length(layout), fps=config.fps)
end

"""
    export_html(layout::DynamicLayout, filepath::String; config=HTMLConfig())

Export a **self-contained** HTML animation: positions, edges, and active
vertex sets for every frame are embedded as data, and a small JavaScript
player draws them on a canvas with play/pause and a frame slider (when
`config.controls`). Open the file in any browser — no dependencies.
"""
function export_html(layout::DynamicLayout{T}, filepath::String;
                     config::HTMLConfig=HTMLConfig()) where T
    w, h = config.width, config.height

    # Embed frame data as JS arrays (pixel coordinates)
    frame_js = String[]
    for f in 1:length(layout)
        pos = layout.positions[f]
        active = Set(layout.frame_active[f])
        nodes = String[]
        for (v, p) in pos
            v in active || continue
            pp = _to_pixels(p, layout.bounds, w, h)
            push!(nodes, "[$(round(pp[1], digits=2)),$(round(pp[2], digits=2)),$(v)]")
        end
        links = String[]
        for (a, b) in layout.frame_edges[f]
            (haskey(pos, a) && haskey(pos, b)) || continue
            pa = _to_pixels(pos[a], layout.bounds, w, h)
            pb = _to_pixels(pos[b], layout.bounds, w, h)
            push!(links, "[$(round(pa[1], digits=2)),$(round(pa[2], digits=2))," *
                         "$(round(pb[1], digits=2)),$(round(pb[2], digits=2))]")
        end
        push!(frame_js, "{t:\"$(layout.times[f])\",nodes:[$(join(nodes, ","))]," *
                        "edges:[$(join(links, ","))]}")
    end

    controls_html = config.controls ? """
        <div>
          <button id="play">Play</button>
          <input id="slider" type="range" min="0" max="$(length(layout) - 1)" value="0" style="width:$(w - 120)px">
          <span id="label"></span>
        </div>""" : ""

    html = """
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"><title>Dynamic Network Animation</title></head>
    <body>
      <h3>Dynamic Network Animation ($(length(layout)) frames)</h3>
      <canvas id="canvas" width="$w" height="$h" style="border:1px solid #ccc"></canvas>
      $controls_html
      <script>
      const frames = [$(join(frame_js, ",\n"))];
      const canvas = document.getElementById("canvas");
      const ctx = canvas.getContext("2d");
      let frame = 0, playing = false;

      function draw(f) {
        ctx.clearRect(0, 0, $w, $h);
        const fr = frames[f];
        ctx.strokeStyle = "#7f8c8d"; ctx.lineWidth = 1.5;
        for (const e of fr.edges) {
          ctx.beginPath(); ctx.moveTo(e[0], e[1]); ctx.lineTo(e[2], e[3]); ctx.stroke();
        }
        ctx.fillStyle = "#2980b9"; ctx.strokeStyle = "#1a5276";
        for (const n of fr.nodes) {
          ctx.beginPath(); ctx.arc(n[0], n[1], 6, 0, 2 * Math.PI);
          ctx.fill(); ctx.stroke();
        }
        const label = document.getElementById("label");
        if (label) label.textContent = "t = " + fr.t;
        const slider = document.getElementById("slider");
        if (slider) slider.value = f;
      }

      function tick() {
        if (!playing) return;
        frame = (frame + 1) % frames.length;
        draw(frame);
        setTimeout(tick, 100);
      }

      const playBtn = document.getElementById("play");
      if (playBtn) playBtn.onclick = () => {
        playing = !playing;
        playBtn.textContent = playing ? "Pause" : "Play";
        if (playing) tick();
      };
      const slider = document.getElementById("slider");
      if (slider) slider.oninput = (e) => { frame = +e.target.value; draw(frame); };

      draw(0);
      </script>
    </body>
    </html>
    """

    open(filepath, "w") do f
        write(f, html)
    end

    return (filepath=filepath, n_frames=length(layout))
end

end # module
