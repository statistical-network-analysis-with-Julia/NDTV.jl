"""
    NDTV.jl - Network Dynamic Temporal Visualization

Provides tools for visualizing dynamic networks including animations,
timeline plots, filmstrip displays, and layout algorithms.

Vertex identity is stable across time: position dictionaries are keyed by
the network's persistent vertex IDs even when vertices activate and
deactivate. Structural layouts (`FRLayout`, `MDSLayout`) are computed on the
vertices active in each slice only; an inactive vertex keeps the position it
last had (or will first have), so it never distorts the active picture.

Port of the R ndtv package from the StatNet collection.
"""
module NDTV

using Dates
using Graphs
using LinearAlgebra
using NetworkCore
using DynamicNetworks
using Random
using PrecompileTools: @setup_workload, @compile_workload

# Animation
export render_animation, compute_animation_layout
export export_movie, export_gif, export_html, export_frames
export MissingToolError

# Timeline visualization
export timeline_plot, ego_timeline
export transmission_timeline, timeline_data

# Filmstrip
export filmstrip, slice_layout

# Layout algorithms
export DynamicLayout, InterpolatedLayout
export compute_slice_layout, layout_sequence, compute_layout
export FRLayout, MDSLayout, CircleLayout, RandomLayout
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
IDs), never by per-slice indices; every frame holds a position for every
vertex (inactive vertices keep a carried position and are not drawn).

# Fields
- `positions::Vector{Dict{T, Tuple{Float64, Float64}}}`: Positions per frame
- `times::Vector{Time}`: Frame time points (the slice onsets for interval slices)
- `bounds::Tuple{Float64, Float64, Float64, Float64}`: (xmin, xmax, ymin, ymax)
- `frame_edges::Vector{Vector{Tuple{T, T}}}`: Active edges per frame
- `frame_active::Vector{Vector{T}}`: Active vertices per frame

# Example
```julia
using NDTV
dl = DynamicLayout([Dict(1 => (0.0, 0.0)), Dict(1 => (1.0, 1.0))], [0.0, 1.0])
length(dl), dl.bounds          # (2, (0.0, 1.0, 0.0, 1.0))
```
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
`:ease`); query it with [`get_position`](@ref).

# Example
```julia
using NDTV
base = DynamicLayout([Dict(1 => (0.0, 0.0)), Dict(1 => (1.0, 2.0))], [0.0, 1.0])
il = InterpolatedLayout(base; interpolation=:ease)
il.interpolation               # :ease
```
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
Times before the first frame (after the last) return the first (last)
frame's position.

# Example
```julia
using NDTV
base = DynamicLayout([Dict(1 => (0.0, 0.0)), Dict(1 => (1.0, 2.0))], [0.0, 1.0])
get_position(InterpolatedLayout(base), 1, 0.5)   # (0.5, 1.0)
```
"""
function get_position(layout::InterpolatedLayout{T, Time}, vertex::Integer, time) where {T, Time}
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

Fruchterman-Reingold force-directed layout parameters. Directed networks
are laid out on their symmetrised graph (a mutual pair attracts once), as R's
`network.layout.fruchtermanreingold` does.

# Example
```julia
using NDTV, NetworkCore, Random
net = network(4); add_edge!(net, 1, 2); add_edge!(net, 2, 3)
pos = compute_layout(net, FRLayout(; iterations=50); rng=Xoshiro(1))
length(pos)                    # 4
```
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

Vertices evenly spaced on a circle (deterministic). In a dynamic layout every
vertex keeps its slot on the circle across frames.

# Example
```julia
using NDTV, NetworkCore
compute_layout(network(4), CircleLayout(; radius=2.0))[1]   # (2.0, 0.0)
```
"""
struct CircleLayout
    radius::Float64
    start_angle::Float64

    CircleLayout(; radius::Float64=1.0, start_angle::Float64=0.0) = new(radius, start_angle)
end

"""
    RandomLayout(; xmin=0.0, xmax=1.0, ymin=0.0, ymax=1.0)

Uniform random positions within the given bounds (drawn from the `rng`
passed to [`compute_layout`](@ref)).

# Example
```julia
using NDTV, NetworkCore, Random
pos = compute_layout(network(3), RandomLayout(; xmax=10.0); rng=Xoshiro(2))
all(0 <= p[1] <= 10 for p in values(pos))   # true
```
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
distance matrix** (of the symmetrised graph on directed networks). The squared-distance matrix is double-centred and the
top two eigenvectors of the resulting Gram matrix give the coordinates, so
Euclidean distances in the plane approximate graph distances. Deterministic
and non-iterative (a single eigendecomposition, no random start, no `rng`
dependence). Each connected component is scaled on its own and the
components are packed side by side (largest first), so disconnected parts
neither collapse onto each other nor need an invented "unreachable" distance.

!!! note "This is not Kamada-Kawai"
    The true Kamada–Kawai algorithm (Kamada & Kawai 1989) *iteratively
    minimizes a spring energy*
    ``\\sum_{i<j} \\tfrac{1}{2} k_{ij}(\\|p_i - p_j\\| - d_{ij})^2`` by
    Newton–Raphson on vertex positions. Classical MDS solves an eigenproblem
    in closed form and optimizes a different (strain, not stress) criterion.
    The two give similar pictures on small well-connected graphs but are
    different algorithms with different fixed points. Kamada–Kawai is not
    implemented here.

# Example
```julia
using NDTV, NetworkCore
net = network(3; directed=false); add_edge!(net, 1, 2); add_edge!(net, 2, 3)
pos = compute_layout(net, MDSLayout())
pos[2]                         # the middle of the path sits at the centre
```
"""
struct MDSLayout end

# Undirected attraction pairs: a directed network is symmetrised so that a
# mutual pair attracts once (R network.layout.fruchtermanreingold); loops
# exert no force and are skipped.
function _attraction_pairs(net::Network)
    pairs = Tuple{Int, Int}[]
    seen = Set{Tuple{Int, Int}}()
    for e in edges(net)
        i, j = Int(src(e)), Int(dst(e))
        i == j && continue
        key = (min(i, j), max(i, j))
        key in seen && continue
        push!(seen, key)
        push!(pairs, key)
    end
    return pairs
end

# The FR core, shared by fresh and anchored variants
function _fr_iterate!(pos_x, pos_y, net, alg::FRLayout, iterations::Int, temp0::Float64)
    n = length(pos_x)
    n == 0 && return
    area = 4.0
    k = alg.k * sqrt(area / n)
    temp = temp0
    pairs = _attraction_pairs(net)

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

        for (i, j) in pairs
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

Compute a static layout of every vertex of `net`, keyed by its vertex IDs.
`algorithm` is an [`FRLayout`](@ref), [`MDSLayout`](@ref),
[`CircleLayout`](@ref) or [`RandomLayout`](@ref); randomness comes only from
`rng`.

# Example
```julia
using NDTV, NetworkCore, Random
net = network(5); add_edge!(net, 1, 2); add_edge!(net, 2, 3)
pos = compute_layout(net, FRLayout(); rng=Xoshiro(3))
sort(collect(keys(pos)))       # [1, 2, 3, 4, 5]
```
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

# Classical MDS of one connected component (vertex indices `comp`), with
# coordinates scaled so that one unit is one geodesic step.
function _mds_component(g, comp::Vector{Int})
    m = length(comp)
    m == 1 && return zeros(1, 2)
    D = zeros(m, m)
    for (a, v) in enumerate(comp)
        dist = Graphs.gdistances(g, v)
        for (b, w) in enumerate(comp)
            D[a, b] = Float64(dist[w])     # connected: always finite
        end
    end
    D2 = D .^ 2
    J = Matrix{Float64}(I, m, m) .- 1.0 / m
    B = -0.5 .* (J * D2 * J)
    B = (B + transpose(B)) ./ 2
    ev = eigen(Symmetric(B))
    order = sortperm(ev.values; rev=true)
    coords = zeros(m, 2)
    for (c, idx) in enumerate(order[1:min(2, m)])
        λ = max(ev.values[idx], 0.0)
        coords[:, c] = ev.vectors[:, idx] .* sqrt(λ)
    end
    # Deterministic orientation: the first vertex's coordinates non-negative
    for c in 1:2
        s = findfirst(x -> abs(x) > 1e-12, coords[:, c])
        !isnothing(s) && coords[s, c] < 0 && (coords[:, c] .*= -1)
    end
    return coords
end

function compute_layout(net::Network{T}, ::MDSLayout;
                        rng::Random.AbstractRNG=Random.default_rng()) where T
    n = Int(nv(net))
    n == 0 && return Dict{T, Tuple{Float64, Float64}}()
    n == 1 && return Dict(T(1) => (0.0, 0.0))

    # Geodesics on the symmetrised graph (direction ignored, as for FR);
    # each connected component is scaled separately and packed
    ug = SimpleGraph(net.graph)
    comps = [sort(Int.(c)) for c in Graphs.connected_components(ug)]
    sort!(comps; by=c -> (-length(c), first(c)))

    coords = zeros(n, 2)
    x_offset = 0.0
    for comp in comps
        c = _mds_component(ug, comp)
        xmin, xmax = extrema(c[:, 1])
        ymid = sum(extrema(c[:, 2])) / 2
        for (a, v) in enumerate(comp)
            coords[v, 1] = c[a, 1] - xmin + x_offset
            coords[v, 2] = c[a, 2] - ymid
        end
        x_offset += (xmax - xmin) + 1.0          # one geodesic step of gap
    end

    # Normalize into [-1, 1], centred
    coords[:, 1] .-= (minimum(coords[:, 1]) + maximum(coords[:, 1])) / 2
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

# Structural layouts use the edges, so inactive vertices would distort them:
# they are laid out on the active subgraph. Circle/random placements ignore
# the edges and keep one stable slot per vertex.
_uses_structure(::Union{FRLayout, MDSLayout}) = true
_uses_structure(::Any) = false

# Time axes. On a continuous axis (floating point) a frame may start
# anywhere. A discrete axis has a smallest step, its unit: 1 on an integer
# axis, a day on a `Date` axis, a millisecond on a `DateTime` axis. Frame
# bounds on a discrete axis are whole units from the start of the range, as
# ndtv's slice.par (interval = 1) gives them for integer data.
_axis_unit(::Type{<:Integer}) = 1
_axis_unit(::Type{Date}) = Day(1)
_axis_unit(::Type{DateTime}) = Millisecond(1)
_axis_unit(::Type) = nothing

# The number of units in [t0, t1] on a discrete axis, widened so that a range
# reaching the axis extremes does not overflow.
_n_units(t0::Integer, t1::Integer) = widen(t1) - widen(t0)
_n_units(t0::Union{Date, DateTime}, t1::Union{Date, DateTime}) =
    widen(Dates.value(t1)) - widen(Dates.value(t0))

# Number of frames of a grid that a discrete axis can hold one unit apart or
# more (`typemax(Int)` on a continuous axis).
function _max_frames(start_time::Time, end_time::Time; closed::Bool) where Time
    isnothing(_axis_unit(Time)) && return typemax(Int)
    units = _n_units(start_time, end_time)
    return Int(min(closed ? units + 1 : max(units, 1), typemax(Int)))
end

# The default number of frames: `n` on a continuous axis; on a discrete axis
# at most `n`, and no more than one per unit (ndtv's interval = 1 on integer
# panels: one frame per wave).
_default_frames(start_time, end_time, n::Int; closed::Bool) =
    min(n, _max_frames(start_time, end_time; closed=closed))

# The time `num/den` of the way from t0 to t1 (num, den > 0 integers, or a
# Float64 fraction on a continuous axis). On a discrete axis the offset is
# rounded to the nearest whole unit, in exact integer arithmetic.
function _grid_time(t0::Time, t1::Time, num::Integer, den::Integer) where Time
    unit = _axis_unit(Time)
    isnothing(unit) && return t0 + (t1 - t0) * (num / den)
    units = _n_units(t0, t1)
    offset = div(2 * num * units + den, 2 * den)          # round half up
    return _shift(t0, offset)
end
_shift(t0::T, offset::Integer) where T<:Integer =
    T(clamp(widen(t0) + offset, typemin(T), typemax(T)))
_shift(t0::Date, offset::Integer) = t0 + Day(Int64(offset))
_shift(t0::DateTime, offset::Integer) = t0 + Millisecond(Int64(offset))

# Frame grid of n slices: their onsets and termini.
# - Half-open over [start, stop) (an observation window, or explicit bounds):
#   frame k covers [start + (k-1)Δ, start + kΔ) with Δ = (stop - start)/n, so
#   no frame sits on the window end, where every half-open spell has ended.
# - Closed over [start, stop] (no window: the range of the change times, as
#   ndtv's default slice.par takes it): Δ = (stop - start)/(n - 1), so the last
#   frame starts at `stop` and shows what begins at the last change time
#   (ndtv's slice onsets seq(start, end, by = interval)).
# On a discrete axis every bound is rounded to a whole unit. The slices stay
# contiguous (each terminus is the next onset), so no activity falls between
# frames; their lengths differ by at most one unit when Δ is not whole. A grid
# that would put two frames less than one unit apart is refused.
function _frame_grid(start_time::Time, end_time::Time, n::Integer;
                     closed::Bool=false) where Time
    n >= 1 || throw(ArgumentError("need at least one frame"))
    end_time >= start_time || throw(ArgumentError("the time window must have start <= end"))
    # An unbounded end (±Inf, or the axis extreme on integer and calendar axes,
    # as DynamicNetworks.unbounded_spell gives it) cannot be cut into frames.
    u = DynamicNetworks.unbounded_spell(Time)
    (start_time == u.onset || end_time == u.terminus ||
     (start_time isa Real && !(isfinite(start_time) && isfinite(end_time)))) &&
        throw(ArgumentError("cannot cut the unbounded time range [$start_time, $end_time] " *
                            "into frames; pass a finite onset= and terminus="))
    m = _max_frames(start_time, end_time; closed=closed)
    n <= m || throw(ArgumentError(
        "$n frames do not fit the $Time time range [$start_time, $end_time" *
        (closed ? "]" : ")") * ": a $Time axis has a smallest step of " *
        "$(_axis_unit(Time)), so at most $m frames can start one step apart. " *
        "Pass at most $m frames, or leave the number of frames at its default"))
    # Fractions of the range as i/denom (a division, so that equal spacing
    # stays exact); one closed frame spans twice the range, to hold its end.
    num_scale, denom = closed ? (n == 1 ? (2, 1) : (1, n - 1)) : (1, n)
    onsets = [_grid_time(start_time, end_time, (i - 1) * num_scale, denom) for i in 1:n]
    termini = [_grid_time(start_time, end_time, i * num_scale, denom) for i in 1:n]
    return onsets, termini
end

# The time range of a display, and whether it is closed: explicit bounds win;
# then the observation window (half-open); then, with no window, the range
# [first, last] of the change times (closed at the end unless `terminus` was
# given), together with `extra` instants the display must show. With none of
# these there is no range to draw, and the caller is asked for one: R ndtv
# would fall back to the placeholder (0, 1).
function _display_range(dnet::DynamicNetwork{T, Time}, onset, terminus,
                        context::AbstractString; extra=Time[]) where {T, Time}
    window = get_observation_period(dnet)
    if !isnothing(window)
        start = isnothing(onset) ? window[1] : convert(Time, onset)
        stop = isnothing(terminus) ? window[2] : convert(Time, terminus)
        return start, stop, false
    end
    if isnothing(onset) || isnothing(terminus)
        times = vcat(get_change_times(dnet), Time[convert(Time, t) for t in extra])
        isempty(times) && throw(ArgumentError(
            "$context: this network has no observation window and no finite spell " *
            "bound to take a time range from; pass onset= and terminus=, or set a " *
            "window with set_observation_period!(dnet, start, stop)"))
        start = isnothing(onset) ? minimum(times) : convert(Time, onset)
        stop = isnothing(terminus) ? maximum(times) : convert(Time, terminus)
        return start, stop, isnothing(terminus)
    end
    return convert(Time, onset), convert(Time, terminus), false
end

# =============================================================================
# Dynamic Layout Computation
# =============================================================================

# One slice: the snapshot (all vertex IDs retained, so edges carry stable
# IDs) and the vertices active in it. `tend === nothing` is an instant;
# otherwise the slice is the interval [t, tend) under `rule`.
function _slice(dnet::DynamicNetwork{T}, t, tend, rule::Symbol) where T
    if isnothing(tend)
        snap = network_extract(dnet, t; retain_all_vertices=true)
        active = T.(active_vertices(dnet, t))
    else
        snap = network_extract(dnet, t, tend; rule=rule, retain_all_vertices=true)
        active = T[T(v) for v in 1:nv(dnet)
                   if is_active(dnet, t, tend; vertex=T(v), rule=rule)]
    end
    return snap, active
end

# The subgraph of `snap` induced by `active`, renumbered 1:k (directedness kept).
function _active_subgraph(snap::Network{T, D}, active::Vector{T}) where {T, D}
    local_of = Dict(v => T(i) for (i, v) in enumerate(active))
    sub = Network{T, D}(; n=length(active), loops=snap.loops)
    for e in edges(snap)
        a, b = T(src(e)), T(dst(e))
        (haskey(local_of, a) && haskey(local_of, b)) || continue
        add_edge!(sub, local_of[a], local_of[b])
    end
    return sub
end

# Positions of the active vertices only (structural layouts), or of every
# vertex (circle/random), keyed by stable IDs.
function _layout_slice(snap::Network{T}, active::Vector{T}, alg, prev; rng) where T
    if !_uses_structure(alg)
        return isnothing(prev) ? compute_layout(snap, alg; rng=rng) :
                                 compute_layout_anchored(snap, alg, prev; rng=rng)
    end
    sub = _active_subgraph(snap, active)
    sub_pos = if isnothing(prev)
        compute_layout(sub, alg; rng=rng)
    else
        prev_sub = Dict{T, Tuple{Float64, Float64}}()
        for (i, v) in enumerate(active)
            haskey(prev, v) && (prev_sub[T(i)] = prev[v])
        end
        compute_layout_anchored(sub, alg, prev_sub; rng=rng)
    end
    return Dict{T, Tuple{Float64, Float64}}(active[Int(i)] => p for (i, p) in sub_pos)
end

"""
    compute_slice_layout(dnet::DynamicNetwork, time; algorithm=FRLayout(),
                         rng=...) -> Dict

Layout of the network active at `time`, keyed by the dynamic network's
stable vertex IDs. Structural layouts ([`FRLayout`](@ref),
[`MDSLayout`](@ref)) place only the vertices active at `time` (inactive
vertices are not laid out and have no entry); [`CircleLayout`](@ref) and
[`RandomLayout`](@ref) place every vertex. Vertices with no spells are
active (DynamicNetworks' `active_default`).

# Example
```julia
using NDTV, DynamicNetworks, Random
dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
activate!(dnet, 0.0, 5.0; vertex=3)
activate!(dnet, 0.0, 10.0; edge=(1, 2))
sort(collect(keys(compute_slice_layout(dnet, 7.0; rng=Xoshiro(1)))))   # [1, 2]
```
"""
function compute_slice_layout(dnet::DynamicNetwork{T, Time}, time;
                              algorithm=FRLayout(),
                              rng::Random.AbstractRNG=Random.default_rng()) where {T, Time}
    snap, active = _slice(dnet, time, nothing, :any)
    return _layout_slice(snap, active, algorithm, nothing; rng=rng)
end

"""
    layout_sequence(dnet::DynamicNetwork, times; termini=nothing, rule=:any,
                    algorithm=FRLayout(), anchor=true, rng=...) -> DynamicLayout

Layouts for a sequence of slices. Slice `k` is the instant `times[k]`, or,
when `termini` is given, the interval `[times[k], termini[k])` under `rule`
(`:any` — R ndtv's aggregated slices — or `:all`).

Structural layouts ([`FRLayout`](@ref), [`MDSLayout`](@ref)) are computed on
the vertices active in the slice only, so an inactive vertex never pulls the
active ones around. Every frame still holds a position for every vertex: an
inactive vertex keeps its last position (or, before it first appears, its
first one) and is not drawn. With `anchor=true` (default) each frame is
seeded from the previous frame's positions — matched by stable vertex ID —
so vertices move smoothly. Per-frame active vertices and edges are recorded
for rendering.

# Example
```julia
using NDTV, DynamicNetworks, Random
dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
activate!(dnet, 0.0, 5.0; edge=(1, 2))
activate!(dnet, 5.0, 10.0; edge=(2, 3))
dl = layout_sequence(dnet, [1.0, 6.0]; rng=Xoshiro(1))
dl.frame_edges                 # [[(1, 2)], [(2, 3)]]
```
"""
function layout_sequence(dnet::DynamicNetwork{T, Time}, times::AbstractVector;
                         termini::Union{Nothing, AbstractVector}=nothing,
                         rule::Symbol=:any,
                         algorithm=FRLayout(), anchor::Bool=true,
                         rng::Random.AbstractRNG=Random.default_rng()) where {T, Time}
    rule in (:any, :all) || throw(ArgumentError("rule must be :any or :all"))
    isnothing(termini) || length(termini) == length(times) ||
        throw(ArgumentError("times and termini must have the same length"))
    n = nv(dnet)
    raw = Dict{T, Tuple{Float64, Float64}}[]
    frame_edges = Vector{Tuple{T, T}}[]
    frame_active = Vector{T}[]
    carried = nothing    # positions of every vertex seen so far

    for (k, t) in enumerate(times)
        snap, active = _slice(dnet, t, isnothing(termini) ? nothing : termini[k], rule)
        pos = _layout_slice(snap, active, algorithm, anchor ? carried : nothing; rng=rng)
        push!(raw, pos)
        push!(frame_edges, [(T(src(e)), T(dst(e))) for e in edges(snap)])
        push!(frame_active, active)
        carried = isnothing(carried) ? copy(pos) : merge(carried, pos)
    end

    # Fill every frame with a position for every vertex: carry the last known
    # position forward, and back-fill a vertex's first position into the
    # frames before it appears. A vertex never laid out sits at the origin.
    positions = [copy(p) for p in raw]
    last = Dict{T, Tuple{Float64, Float64}}()
    for p in positions
        for (v, xy) in last
            haskey(p, v) || (p[v] = xy)
        end
        merge!(last, p)
    end
    for v in T.(1:n)
        first_k = findfirst(p -> haskey(p, v), raw)
        xy = isnothing(first_k) ? (0.0, 0.0) : raw[first_k][v]
        for p in positions
            haskey(p, v) || (p[v] = xy)
        end
    end

    return DynamicLayout(positions, collect(times);
                         frame_edges=frame_edges, frame_active=frame_active)
end

# =============================================================================
# Animation Rendering
# =============================================================================

"""
    render_animation(dnet::DynamicNetwork; algorithm=FRLayout(), n_frames=nothing,
                     onset=nothing, terminus=nothing, slice=:interval, rule=:any,
                     interpolation=:linear, rng=...)

Compute layout positions for animating a dynamic network (R ndtv's
`compute.animation`). The frames cover `n_frames` equal, contiguous slices of
a time range; with `slice=:interval` (default, as R's `aggregate.dur` equal to
the interval) frame `k` shows everything active during its slice under
`rule`, so spells shorter than the frame spacing are not lost;
`slice=:instant` shows the network at each slice onset.

- With an observation window (DynamicNetworks' `get_observation_period`), or
  with explicit `onset` and `terminus`, the range is `[onset, terminus)`, cut
  into half-open slices; no frame sits on its end, where every half-open spell
  has ended.
- **Without a window**, the range is the closed range `[first, last]` of the
  change times (`get_change_times`), as ndtv's default `slice.par` takes it:
  the slices are spaced `(last - first)/(n_frames - 1)` apart and the last one
  starts at the last change time, so a tie that forms then is drawn. Either end
  can be overridden with `onset`/`terminus`. A network with neither a window nor
  a finite spell bound raises an `ArgumentError` asking for one (ndtv would
  animate the placeholder range (0, 1)).

**Number of frames.** `n_frames` defaults to 100 on a floating-point time
axis. A discrete axis (integer, `Date`, `DateTime`) has a smallest step (1, a
day, a millisecond); there the default is 100 frames or one per step,
whichever is fewer, so a panel built with an integer `start` gets one frame per
wave, as ndtv's `interval = 1` gives. On a discrete axis every slice bound is
a whole number of steps from the start: when the range does not divide into
`n_frames` equal slices, the bounds are rounded and the slices differ in length
by one step at most, staying contiguous so that no activity falls between two
frames. Asking for more frames than the range has steps raises an
`ArgumentError`.

Works for any DynamicNetworks time type (including `Int`, `Date` and
`DateTime`). Returns a [`DynamicLayout`](@ref) (`interpolation = :linear` or
`:none`) or an [`InterpolatedLayout`](@ref) (`interpolation = :ease`).

# Example
```julia
using NDTV, DynamicNetworks, NetworkCore, Random
dnet = DynamicNetwork(3)                         # no explicit window
activate!(dnet, 0.0, 4.0; edge=(1, 2))
activate!(dnet, 4.0, Inf; edge=(2, 3))           # forms at the last change time
dl = render_animation(dnet; n_frames=3, rng=Xoshiro(1))
dl.times                                         # [0.0, 2.0, 4.0]: closed range
dl.frame_edges[end]                              # [(2, 3)]

panel = [network(3) for _ in 1:3]                # three waves on an integer axis
add_edge!(panel[1], 1, 2); add_edge!(panel[3], 2, 3)
waves = DynamicNetwork(panel; start=1)           # waves at [1,2), [2,3), [3,4)
render_animation(waves; rng=Xoshiro(1)).times    # [1, 2, 3]: one frame per wave
```
"""
function render_animation(dnet::DynamicNetwork{T, Time};
                          algorithm=FRLayout(),
                          n_frames::Union{Nothing, Integer}=nothing,
                          onset=nothing, terminus=nothing,
                          slice::Symbol=:interval, rule::Symbol=:any,
                          interpolation::Symbol=:linear,
                          rng::Random.AbstractRNG=Random.default_rng()) where {T, Time}
    slice in (:interval, :instant) ||
        throw(ArgumentError("slice must be :interval or :instant"))
    interpolation in (:linear, :none, :ease) ||
        throw(ArgumentError("interpolation must be :linear, :none or :ease"))
    start_time, end_time, closed = _display_range(dnet, onset, terminus, "render_animation")
    n = isnothing(n_frames) ? _default_frames(start_time, end_time, 100; closed=closed) : n_frames
    times, ends = _frame_grid(start_time, end_time, n; closed=closed)
    slice == :interval && start_time == end_time && (ends = nothing)

    base_layout = layout_sequence(dnet, times; termini=slice == :interval ? ends : nothing,
                                  rule=rule, algorithm=algorithm, rng=rng)

    if interpolation == :linear || interpolation == :none
        return base_layout
    else
        return InterpolatedLayout(base_layout; interpolation=interpolation)
    end
end

"""
    compute_animation_layout(dnet; kwargs...)

Alias of [`render_animation`](@ref), after R ndtv's `compute.animation`.

# Example
```julia
using NDTV, DynamicNetworks, Random
dnet = DynamicNetwork(2; observation_start=0.0, observation_end=2.0)
activate!(dnet, 0.0, 2.0; edge=(1, 2))
length(compute_animation_layout(dnet; n_frames=2, rng=Xoshiro(1)))   # 2
```
"""
const compute_animation_layout = render_animation

# =============================================================================
# Timeline Visualization
# =============================================================================

# Fraction of the window elapsed at time t, clamped to [0, 1] so that
# open-ended spells (±Inf) and spells outside the window are drawn to the
# window edge instead of crashing; 0 for a degenerate window.
function _time_frac(t, start_time, end_time)
    end_time == start_time && return 0.0
    t <= start_time && return 0.0
    t >= end_time && return 1.0
    return Float64((t - start_time) / (end_time - start_time))
end

_time_pos(t, start_time, end_time, width) =
    round(Int, _time_frac(t, start_time, end_time) * (width - 1)) + 1

# Base edges in a deterministic order, as stored keys
function _sorted_edges(dnet::DynamicNetwork{T}) where T
    ks = Tuple{T, T}[]
    for e in edges(dnet.network)
        i, j = T(src(e)), T(dst(e))
        push!(ks, is_directed(dnet) ? (i, j) : (min(i, j), max(i, j)))
    end
    return sort!(unique!(ks))
end

_arrow(dnet) = is_directed(dnet) ? "→" : "—"

"""
    timeline_data(dnet::DynamicNetwork) -> NamedTuple

Vertex and edge activity spells as two vectors of named tuples
(`(vertex, onset, terminus)` and `(source, target, onset, terminus)`),
sorted by element. Elements with no spells are reported as active over
`(-Inf, Inf)` (DynamicNetworks' `get_vertex_activity`/`get_edge_activity`).

# Example
```julia
using NDTV, DynamicNetworks
dnet = DynamicNetwork(2; observation_start=0.0, observation_end=10.0)
activate!(dnet, 1.0, 3.0; edge=(1, 2))
td = timeline_data(dnet)
td.edges[1]                    # (source = 1, target = 2, onset = 1.0, terminus = 3.0)
```
"""
function timeline_data(dnet::DynamicNetwork{T, Time}) where {T, Time}
    vertex_data = NamedTuple{(:vertex, :onset, :terminus), Tuple{T, Time, Time}}[]
    edge_data = NamedTuple{(:source, :target, :onset, :terminus), Tuple{T, T, Time, Time}}[]

    for v in T.(1:nv(dnet))
        for spell in get_vertex_activity(dnet, v)
            push!(vertex_data, (vertex=v, onset=spell.onset, terminus=spell.terminus))
        end
    end

    for (i, j) in _sorted_edges(dnet)
        for spell in get_edge_activity(dnet, i, j)
            push!(edge_data, (source=i, target=j, onset=spell.onset, terminus=spell.terminus))
        end
    end

    return (vertices=vertex_data, edges=edge_data)
end

function _bar(spells, start_time, end_time, width, ch)
    line = fill(' ', width)
    for spell in spells
        spell.terminus < start_time && continue
        spell.onset > end_time && continue
        start_pos = _time_pos(spell.onset, start_time, end_time, width)
        end_pos = _time_pos(spell.terminus, start_time, end_time, width)
        for p in start_pos:end_pos
            1 <= p <= width && (line[p] = ch)
        end
    end
    return String(line)
end

"""
    timeline_plot(dnet::DynamicNetwork; width=60, onset=nothing, terminus=nothing, io=stdout)

ASCII timeline of vertex and edge activity spells over the window
`[onset, terminus]`: by default the observation window or, when none is set,
the range of the change times (`get_change_times`); a network with neither
raises an `ArgumentError` unless both bounds are given. Open-ended spells run
to the window edge; elements with no spells are active throughout. Edges are
labelled `i→j` on directed networks and `i—j` on undirected ones.

# Example
```julia
using NDTV, DynamicNetworks
dnet = DynamicNetwork(2; observation_start=0.0, observation_end=10.0)
activate!(dnet, 0.0, 5.0; edge=(1, 2))
timeline_plot(dnet; width=20)
```
"""
function timeline_plot(dnet::DynamicNetwork{T, Time}; width::Int=60,
                       onset=nothing, terminus=nothing,
                       io::IO=stdout) where {T, Time}
    start_time, end_time, _ = _display_range(dnet, onset, terminus, "timeline_plot")

    println(io, "Timeline: $start_time to $end_time")
    println(io, "=" ^ width)

    println(io, "\nVertices:")
    for v in 1:nv(dnet)
        bar = _bar(get_vertex_activity(dnet, T(v)), start_time, end_time, width, '─')
        println(io, "V$v: |$bar|")
    end

    println(io, "\nEdges:")
    arrow = _arrow(dnet)
    for (i, j) in _sorted_edges(dnet)
        bar = _bar(get_edge_activity(dnet, i, j), start_time, end_time, width, '═')
        println(io, "$i$arrow$j: |$bar|")
    end

    return nothing
end

"""
    ego_timeline(dnet::DynamicNetwork, vertex; width=60, io=stdout)

Ego-centric ASCII timeline: activity spells of all edges incident to
`vertex`, marked `→`/`←` (out/in) on directed networks and `—` on undirected
ones, over the range [`timeline_plot`](@ref) uses.

Not R ndtv's `proximity.timeline`, a different display (vertex positions from
an MDS of geodesic distances drawn as lines over time), which is not ported.

# Example
```julia
using NDTV, DynamicNetworks
dnet = DynamicNetwork(3; directed=false, observation_start=0.0, observation_end=10.0)
activate!(dnet, 0.0, 5.0; edge=(1, 2))
ego_timeline(dnet, 1; width=20)
```
"""
function ego_timeline(dnet::DynamicNetwork{T, Time}, vertex::Integer;
                            width::Int=60, io::IO=stdout) where {T, Time}
    start_time, end_time, _ = _display_range(dnet, nothing, nothing, "ego_timeline")
    vertex = T(vertex)

    println(io, "Ego timeline for vertex $vertex")
    println(io, "=" ^ width)

    for (i, j) in _sorted_edges(dnet)
        (i == vertex || j == vertex) || continue
        other = i == vertex ? j : i
        direction = is_directed(dnet) ? (i == vertex ? "→" : "←") : "—"
        bar = _bar(get_edge_activity(dnet, i, j), start_time, end_time, width, '═')
        println(io, "$direction V$other: |$bar|")
    end

    return nothing
end

"""
    transmission_timeline(dnet::DynamicNetwork, transmissions; width=60, io=stdout)

ASCII timeline marking transmission events `(from, to, time)` over the
observation window or, when none is set, over the range of the change times
and the transmission times.

Not R ndtv's `transmissionTimeline`, which draws a transmission *tree*
(generation against time) from a `tEdgeList`; this text display only marks
when each transmission happened.

# Example
```julia
using NDTV, DynamicNetworks
dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
transmission_timeline(dnet, [(1, 2, 2.0), (2, 3, 6.0)]; width=20)
```
"""
function transmission_timeline(dnet::DynamicNetwork{T, Time},
                               transmissions::AbstractVector{<:Tuple{Integer, Integer, Any}};
                               width::Int=60, io::IO=stdout) where {T, Time}
    start_time, end_time, _ = _display_range(dnet, nothing, nothing, "transmission_timeline";
                                             extra=[t for (_, _, t) in transmissions])

    println(io, "Transmission Timeline")
    println(io, "=" ^ width)

    arrow = _arrow(dnet)
    for (from, to, time) in transmissions
        pos = _time_pos(convert(Time, time), start_time, end_time, width)
        line = fill(' ', width)
        1 <= pos <= width && (line[pos] = '*')
        println(io, "$from$arrow$to: |$(String(line))| t=$time")
    end

    return nothing
end


# =============================================================================
# Filmstrip Visualization
# =============================================================================

"""
    filmstrip(dnet::DynamicNetwork, times; termini=nothing, rule=:any,
              algorithm=FRLayout(), rng=...) -> Vector{NamedTuple}

Layout frames at the given times (or slices `[times[k], termini[k])`) for
filmstrip (small-multiples) display, after R ndtv's `filmstrip`. Each frame
is a named tuple `(time, positions, active, edges, n_vertices, n_edges)`:
positions keyed by stable ID, the active vertex set, the active edges, and
their counts. The vector is concretely typed.

# Example
```julia
using NDTV, DynamicNetworks, Random
dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
activate!(dnet, 0.0, 5.0; edge=(1, 2))
fs = filmstrip(dnet, [1.0, 6.0]; rng=Xoshiro(1))
[f.n_edges for f in fs]        # [1, 0]
```
"""
function filmstrip(dnet::DynamicNetwork{T, Time}, times::AbstractVector;
                   termini::Union{Nothing, AbstractVector}=nothing, rule::Symbol=:any,
                   algorithm=FRLayout(),
                   rng::Random.AbstractRNG=Random.default_rng()) where {T, Time}
    layout = layout_sequence(dnet, times; termini=termini, rule=rule,
                             algorithm=algorithm, rng=rng)

    return [(time=t,
             positions=layout[i],
             active=layout.frame_active[i],
             edges=layout.frame_edges[i],
             n_vertices=length(layout.frame_active[i]),
             n_edges=length(layout.frame_edges[i])) for (i, t) in enumerate(layout.times)]
end

"""
    slice_layout(dnet::DynamicNetwork, onset, terminus; n_slices=nothing, slice=:interval,
                 rule=:any, algorithm=FRLayout(), rng=...)

Filmstrip frames for `n_slices` equal, contiguous slices of
`[onset, terminus)`; with `slice=:interval` (default) each frame shows what
was active during its slice under `rule`, with `slice=:instant` the network
at each slice onset.

`n_slices` defaults to 5, or, on a discrete time axis (integer, `Date`,
`DateTime`), to one slice per step when the range has fewer than 5 steps. On
a discrete axis the slice bounds are rounded to whole steps, as described
under [`render_animation`](@ref).

# Example
```julia
using NDTV, DynamicNetworks, Random
dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
activate!(dnet, 0.0, 5.0; edge=(1, 2))
fs = slice_layout(dnet, 0.0, 10.0; n_slices=2, rng=Xoshiro(1))
[f.time for f in fs], [f.n_edges for f in fs]   # ([0.0, 5.0], [1, 0])
```
"""
function slice_layout(dnet::DynamicNetwork{T, Time}, onset, terminus;
                      n_slices::Union{Nothing, Integer}=nothing,
                      slice::Symbol=:interval, rule::Symbol=:any,
                      algorithm=FRLayout(),
                      rng::Random.AbstractRNG=Random.default_rng()) where {T, Time}
    slice in (:interval, :instant) ||
        throw(ArgumentError("slice must be :interval or :instant"))
    t0, t1 = convert(Time, onset), convert(Time, terminus)
    n = isnothing(n_slices) ? _default_frames(t0, t1, 5; closed=false) : n_slices
    times, ends = _frame_grid(t0, t1, n)
    return filmstrip(dnet, times; termini=slice == :interval ? ends : nothing,
                     rule=rule, algorithm=algorithm, rng=rng)
end

# =============================================================================
# Export Functions
# =============================================================================

"""
    MissingToolError(tool, purpose, frames_dir)

Thrown by [`export_movie`](@ref) and [`export_gif`](@ref) when the external
program they need (`ffmpeg`, ImageMagick) is not on `PATH`. The SVG frames
already rendered are left in `frames_dir`, so they can be encoded by hand.

# Example
```julia
using NDTV
err = MissingToolError("ffmpeg", "export_movie", "/tmp/frames")
sprint(showerror, err)
```
"""
struct MissingToolError <: Exception
    tool::String
    purpose::String
    frames_dir::String
end

function Base.showerror(io::IO, e::MissingToolError)
    print(io, "MissingToolError: ", e.purpose, " requires ", e.tool,
          ", which was not found on PATH. The rendered SVG frames are in ",
          e.frames_dir)
end

"""
    ExportConfig

Abstract base type for all export configuration types.
Subtypes: [`VideoConfig`](@ref), [`GIFConfig`](@ref), [`HTMLConfig`](@ref).

# Example
```julia
using NDTV
GIFConfig() isa ExportConfig   # true
```
"""
abstract type ExportConfig end

"""
    VideoConfig(; fps=30, width=800, height=600, codec="h264")

Configuration for video export with [`export_movie`](@ref). Requires the
`ffmpeg` binary, built with SVG input support (`--enable-librsvg`, as in the
usual distribution builds); `codec` is passed to `ffmpeg -c:v`.

# Example
```julia
using NDTV
cfg = VideoConfig(; fps=12, codec="mpeg4")
cfg.fps, cfg.codec             # (12, "mpeg4")
```
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

Configuration for GIF export with [`export_gif`](@ref). Requires
ImageMagick (`magick` or `convert`) with an SVG delegate (librsvg:
`librsvg2-bin` on Debian/Ubuntu, `librsvg2-tools` on Fedora,
`brew install librsvg` on macOS). `loop=0` loops forever.

# Example
```julia
using NDTV
GIFConfig(; fps=5).fps         # 5
```
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

Configuration for [`export_html`](@ref) (self-contained; no external
dependencies).

# Example
```julia
using NDTV
HTMLConfig(; controls=false).controls   # false
```
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
    for (v, p) in sort!(collect(pos); by=first)
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
(created if needed): active edges as lines, active vertices as circles.
Returns the file paths. This is the pure-Julia rendering backend used by
[`export_movie`](@ref)/[`export_gif`](@ref).

# Example
```julia
using NDTV, DynamicNetworks, Random
dnet = DynamicNetwork(2; observation_start=0.0, observation_end=2.0)
activate!(dnet, 0.0, 2.0; edge=(1, 2))
dl = render_animation(dnet; n_frames=2, rng=Xoshiro(1))
paths = export_frames(dl, mktempdir(); width=100, height=100)
length(paths)                  # 2
```
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
binary (R ndtv's `saveVideo`). Throws a [`MissingToolError`](@ref) (leaving
the rendered frames on disk) when `ffmpeg` is not installed. Returns
`(filepath, n_frames, fps)`.

# Example
```jl
export_movie(layout, "animation.mp4"; config=VideoConfig(fps=10))
```
"""
function export_movie(layout::DynamicLayout, filepath::String;
                      config::VideoConfig=VideoConfig())
    dir = mktempdir()
    export_frames(layout, dir; width=config.width, height=config.height)

    ffmpeg = Sys.which("ffmpeg")
    isnothing(ffmpeg) && throw(MissingToolError("the `ffmpeg` binary", "export_movie", dir))

    cmd = `$ffmpeg -y -loglevel error -framerate $(config.fps)
           -i $(joinpath(dir, "frame_%05d.svg")) -c:v $(config.codec)
           -pix_fmt yuv420p $filepath`
    errbuf = IOBuffer()
    try
        run(pipeline(cmd; stderr=errbuf))
    catch err
        err isa ProcessFailedException || rethrow()
        throw(ArgumentError("ffmpeg failed to encode the frames in $dir " *
                            "(codec $(repr(config.codec)); ffmpeg needs SVG input " *
                            "support, i.e. a build with librsvg). ffmpeg said: " *
                            strip(String(take!(errbuf)))))
    end
    return (filepath=filepath, n_frames=length(layout), fps=config.fps)
end

"""
    export_gif(layout::DynamicLayout, filepath::String; config=GIFConfig())

Render the animation frames to SVG and assemble an animated GIF with
ImageMagick (`magick`, or the older `convert`), which needs an SVG delegate
(librsvg). Throws a [`MissingToolError`](@ref) (leaving the rendered frames
on disk) when ImageMagick is not installed. Returns `(filepath, n_frames,
fps)`.

# Example
```jl
export_gif(layout, "animation.gif"; config=GIFConfig(fps=5))
```
"""
function export_gif(layout::DynamicLayout, filepath::String;
                    config::GIFConfig=GIFConfig())
    dir = mktempdir()
    frames = export_frames(layout, dir; width=config.width, height=config.height)

    magick = something(Sys.which("magick"), Sys.which("convert"), Some(nothing))
    isnothing(magick) && throw(MissingToolError(
        "ImageMagick (`magick` or `convert`)", "export_gif", dir))

    delay = max(round(Int, 100 / config.fps), 1)
    errbuf = IOBuffer()
    try
        run(pipeline(`$magick -delay $delay -loop $(config.loop) $frames $filepath`;
                     stderr=errbuf))
    catch err
        err isa ProcessFailedException || rethrow()
        throw(ArgumentError("ImageMagick failed to assemble the frames in $dir; " *
                            "it needs an SVG delegate (librsvg: `librsvg2-bin` on " *
                            "Debian/Ubuntu, `brew install librsvg` on macOS). " *
                            "ImageMagick said: " * strip(String(take!(errbuf)))))
    end
    return (filepath=filepath, n_frames=length(layout), fps=config.fps)
end

"""
    export_html(layout::DynamicLayout, filepath::String; config=HTMLConfig())

Export a **self-contained** HTML animation: positions, edges, and active
vertex sets for every frame are embedded as data, and a small JavaScript
player draws them on a canvas with play/pause and a frame slider (when
`config.controls`). Open the file in any browser — no dependencies.

# Example
```julia
using NDTV, DynamicNetworks, Random
dnet = DynamicNetwork(2; observation_start=0.0, observation_end=2.0)
activate!(dnet, 0.0, 2.0; edge=(1, 2))
dl = render_animation(dnet; n_frames=2, rng=Xoshiro(1))
export_html(dl, joinpath(mktempdir(), "anim.html")).n_frames   # 2
```
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
        for (v, p) in sort!(collect(pos); by=first)
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

# Time-to-first-animation: compile the README path (slice layouts, the
# animation, the text timelines and the SVG/HTML writers) under a fixed rng.
@setup_workload begin
    @compile_workload begin
        for directed in (true, false)
            d = DynamicNetwork(4; directed=directed, observation_start=0.0,
                               observation_end=10.0)
            activate!(d, 0.0, 5.0; edge=(1, 2))
            activate!(d, 2.0, 8.0; edge=(2, 3))
            activate!(d, 4.0, 4.0; edge=(3, 4))
            for alg in (FRLayout(; iterations=5), MDSLayout(), CircleLayout())
                anim = render_animation(d; algorithm=alg, n_frames=3,
                                        rng=Random.Xoshiro(1))
                if alg isa FRLayout
                    dir = mktempdir()
                    export_frames(anim, dir)
                    export_html(anim, joinpath(dir, "a.html"))
                end
            end
            timeline_plot(d; io=devnull)
            ego_timeline(d, 2; io=devnull)
            transmission_timeline(d, [(1, 2, 1.0)]; io=devnull)
        end
    end
end

end # module
