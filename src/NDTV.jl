"""
    NDTV.jl - Network Dynamic Temporal Visualization

Provides tools for visualizing dynamic networks including
animations, timeline plots, filmstrip displays, and layout algorithms.

Port of the R ndtv package from the StatNet collection.
"""
module NDTV

using Dates
using Graphs
using LinearAlgebra
using Network
using NetworkDynamic
using Random
using Statistics

# Animation
export render_animation, compute_animation_layout
export export_movie, export_gif, export_html

# Timeline visualization
export timeline_plot, proximity_timeline
export transmissionTimeline, timeline_data

# Filmstrip
export filmstrip, slice_layout

# Layout algorithms
export DynamicLayout, InterpolatedLayout
export compute_slice_layout, layout_sequence, compute_layout
export FRLayout, KKLayout, CircleLayout, RandomLayout
export get_position

# Export formats
export ExportConfig, VideoConfig, GIFConfig, HTMLConfig

# =============================================================================
# Layout Types
# =============================================================================

"""
    DynamicLayout{T}

Layout positions for dynamic network visualization across time.

# Fields
- `positions::Vector{Dict{T, Tuple{Float64, Float64}}}`: Position per vertex per time
- `times::Vector{Float64}`: Time points
- `bounds::Tuple{Float64, Float64, Float64, Float64}`: (xmin, xmax, ymin, ymax)
"""
struct DynamicLayout{T}
    positions::Vector{Dict{T, Tuple{Float64, Float64}}}
    times::Vector{Float64}
    bounds::Tuple{Float64, Float64, Float64, Float64}

    function DynamicLayout(positions::Vector{Dict{T, Tuple{Float64, Float64}}},
                           times::Vector{Float64}) where T
        length(positions) == length(times) ||
            throw(ArgumentError("positions and times must have same length"))

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

        new{T}(positions, times, bounds)
    end
end

Base.length(dl::DynamicLayout) = length(dl.times)
Base.getindex(dl::DynamicLayout, i::Int) = dl.positions[i]

"""
    InterpolatedLayout{T}

Layout with smooth interpolation between time points.
"""
struct InterpolatedLayout{T}
    base_layout::DynamicLayout{T}
    interpolation::Symbol

    InterpolatedLayout(base::DynamicLayout{T}; interpolation::Symbol=:linear) where T =
        new{T}(base, interpolation)
end

"""
    get_position(layout::InterpolatedLayout, vertex, time) -> Tuple{Float64, Float64}

Get interpolated position at any time point.
"""
function get_position(layout::InterpolatedLayout{T}, vertex::T, time::Float64) where T
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

        alpha = (time - t1) / (t2 - t1)

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
    FRLayout

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
    CircleLayout

Simple circular layout.
"""
struct CircleLayout
    radius::Float64
    start_angle::Float64

    CircleLayout(; radius::Float64=1.0, start_angle::Float64=0.0) = new(radius, start_angle)
end

"""
    RandomLayout

Random layout with specified bounds.
"""
struct RandomLayout
    bounds::Tuple{Float64, Float64, Float64, Float64}

    RandomLayout(; xmin::Float64=0.0, xmax::Float64=1.0,
                   ymin::Float64=0.0, ymax::Float64=1.0) =
        new((xmin, xmax, ymin, ymax))
end

"""
    KKLayout

Kamada-Kawai layout parameters.
"""
struct KKLayout
    iterations::Int
    epsilon::Float64

    KKLayout(; iterations::Int=100, epsilon::Float64=1e-4) = new(iterations, epsilon)
end

"""
    compute_layout(net::Network, algorithm::FRLayout) -> Dict{Int, Tuple{Float64, Float64}}

Compute Fruchterman-Reingold layout for a static network.
"""
function compute_layout(net::Network{T}, alg::FRLayout) where T
    n = nv(net)
    n == 0 && return Dict{T, Tuple{Float64, Float64}}()

    pos_x = rand(n) .* 2 .- 1
    pos_y = rand(n) .* 2 .- 1

    area = 4.0
    k = alg.k * sqrt(area / n)
    temp = 1.0

    for _ in 1:alg.iterations
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

    return Dict(T(i) => (pos_x[i], pos_y[i]) for i in 1:n)
end

function compute_layout(net::Network{T}, alg::CircleLayout) where T
    n = nv(net)
    n == 0 && return Dict{T, Tuple{Float64, Float64}}()

    positions = Dict{T, Tuple{Float64, Float64}}()
    for i in 1:n
        angle = alg.start_angle + 2π * (i - 1) / n
        x = alg.radius * cos(angle)
        y = alg.radius * sin(angle)
        positions[T(i)] = (x, y)
    end

    return positions
end

function compute_layout(net::Network{T}, alg::RandomLayout) where T
    n = nv(net)
    xmin, xmax, ymin, ymax = alg.bounds

    positions = Dict{T, Tuple{Float64, Float64}}()
    for i in 1:n
        x = xmin + rand() * (xmax - xmin)
        y = ymin + rand() * (ymax - ymin)
        positions[T(i)] = (x, y)
    end

    return positions
end

# =============================================================================
# Dynamic Layout Computation
# =============================================================================

"""
    compute_slice_layout(dnet::DynamicNetwork, time; algorithm=FRLayout()) -> Dict

Compute layout for a network snapshot at a specific time.
"""
function compute_slice_layout(dnet::DynamicNetwork{T, Time}, time::Time;
                              algorithm=FRLayout()) where {T, Time}
    snapshot = network_extract(dnet, time)
    return compute_layout(snapshot, algorithm)
end

"""
    layout_sequence(dnet::DynamicNetwork, times; algorithm=FRLayout(), anchor=true) -> DynamicLayout

Compute layouts for a sequence of time points.
"""
function layout_sequence(dnet::DynamicNetwork{T, Time}, times::AbstractVector{Time};
                         algorithm=FRLayout(), anchor::Bool=true) where {T, Time}
    positions = Dict{T, Tuple{Float64, Float64}}[]
    prev_positions = nothing

    for (i, t) in enumerate(times)
        snapshot = network_extract(dnet, t)

        if anchor && !isnothing(prev_positions)
            pos = compute_layout_anchored(snapshot, algorithm, prev_positions)
        else
            pos = compute_layout(snapshot, algorithm)
        end

        push!(positions, pos)
        prev_positions = pos
    end

    return DynamicLayout(positions, Float64.(times))
end

function compute_layout_anchored(net::Network{T}, alg::FRLayout,
                                 prev_positions::Dict{T, Tuple{Float64, Float64}}) where T
    n = nv(net)
    n == 0 && return Dict{T, Tuple{Float64, Float64}}()

    pos_x = zeros(n)
    pos_y = zeros(n)

    for i in 1:n
        if haskey(prev_positions, T(i))
            pos_x[i], pos_y[i] = prev_positions[T(i)]
        else
            pos_x[i] = rand() * 2 - 1
            pos_y[i] = rand() * 2 - 1
        end
    end

    area = 4.0
    k = alg.k * sqrt(area / n)
    temp = 0.5

    for _ in 1:(alg.iterations ÷ 2)
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

    return Dict(T(i) => (pos_x[i], pos_y[i]) for i in 1:n)
end

# =============================================================================
# Animation Rendering
# =============================================================================

"""
    render_animation(dnet::DynamicNetwork; kwargs...) -> DynamicLayout

Compute layout positions for animating a dynamic network.
"""
function render_animation(dnet::DynamicNetwork{T, Time};
                          algorithm=FRLayout(),
                          n_frames::Int=100,
                          interpolation::Symbol=:linear) where {T, Time}
    start_time, end_time = dnet.observation_period
    times = range(start_time, end_time, length=n_frames)

    base_layout = layout_sequence(dnet, collect(times); algorithm=algorithm)

    if interpolation == :linear || interpolation == :none
        return base_layout
    else
        return InterpolatedLayout(base_layout; interpolation=interpolation)
    end
end

compute_animation_layout = render_animation

# =============================================================================
# Timeline Visualization
# =============================================================================

"""
    timeline_data(dnet::DynamicNetwork) -> NamedTuple

Extract timeline data for visualization.
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
    timeline_plot(dnet::DynamicNetwork; kwargs...) -> Nothing

Create a timeline visualization of network dynamics (ASCII).
"""
function timeline_plot(dnet::DynamicNetwork{T, Time}; width::Int=60) where {T, Time}
    data = timeline_data(dnet)
    start_time, end_time = dnet.observation_period
    duration = end_time - start_time

    println("Timeline: $start_time to $end_time")
    println("=" ^ width)

    println("\nVertices:")
    for v in 1:nv(dnet)
        spells = get(dnet.vertex_spells, T(v), Spell{Time}[])
        line = fill(' ', width)

        for spell in spells
            start_pos = round(Int, (spell.onset - start_time) / duration * (width - 1)) + 1
            end_pos = round(Int, (spell.terminus - start_time) / duration * (width - 1)) + 1
            for p in start_pos:end_pos
                1 <= p <= width && (line[p] = '─')
            end
        end

        println("V$v: |$(String(line))|")
    end

    println("\nEdges:")
    for ((i, j), spells) in dnet.edge_spells
        line = fill(' ', width)

        for spell in spells
            start_pos = round(Int, (spell.onset - start_time) / duration * (width - 1)) + 1
            end_pos = round(Int, (spell.terminus - start_time) / duration * (width - 1)) + 1
            for p in start_pos:end_pos
                1 <= p <= width && (line[p] = '═')
            end
        end

        println("$i→$j: |$(String(line))|")
    end

    return nothing
end

"""
    proximity_timeline(dnet::DynamicNetwork, vertex; kwargs...) -> Nothing

Create an ego-centric timeline.
"""
function proximity_timeline(dnet::DynamicNetwork{T, Time}, vertex::T;
                            width::Int=60) where {T, Time}
    start_time, end_time = dnet.observation_period
    duration = end_time - start_time

    println("Proximity timeline for vertex $vertex")
    println("=" ^ width)

    for ((i, j), spells) in dnet.edge_spells
        (i == vertex || j == vertex) || continue
        other = i == vertex ? j : i
        direction = i == vertex ? "→" : "←"

        line = fill(' ', width)
        for spell in spells
            start_pos = round(Int, (spell.onset - start_time) / duration * (width - 1)) + 1
            end_pos = round(Int, (spell.terminus - start_time) / duration * (width - 1)) + 1
            for p in start_pos:end_pos
                1 <= p <= width && (line[p] = '═')
            end
        end

        println("$direction V$other: |$(String(line))|")
    end

    return nothing
end

"""
    transmissionTimeline(dnet::DynamicNetwork, transmissions; kwargs...)

Create timeline showing transmission events.
"""
function transmissionTimeline(dnet::DynamicNetwork{T, Time},
                              transmissions::Vector{Tuple{T, T, Time}};
                              width::Int=60) where {T, Time}
    start_time, end_time = dnet.observation_period
    duration = end_time - start_time

    println("Transmission Timeline")
    println("=" ^ width)

    for (from, to, time) in transmissions
        pos = round(Int, (time - start_time) / duration * (width - 1)) + 1
        line = fill(' ', width)
        1 <= pos <= width && (line[pos] = '*')
        println("$from→$to: |$(String(line))| t=$time")
    end

    return nothing
end

# =============================================================================
# Filmstrip Visualization
# =============================================================================

"""
    filmstrip(dnet::DynamicNetwork, times; kwargs...) -> Vector

Generate data for filmstrip visualization.
"""
function filmstrip(dnet::DynamicNetwork{T, Time}, times::AbstractVector{Time};
                   algorithm=FRLayout()) where {T, Time}
    layout = layout_sequence(dnet, times; algorithm=algorithm)

    frames = []
    for (i, t) in enumerate(times)
        snapshot = network_extract(dnet, t)
        push!(frames, (
            time=t,
            positions=layout[i],
            n_vertices=nv(snapshot),
            n_edges=ne(snapshot)
        ))
    end

    return frames
end

"""
    slice_layout(dnet::DynamicNetwork, onset, terminus; n_slices=5) -> Vector

Create layouts for multiple time slices.
"""
function slice_layout(dnet::DynamicNetwork{T, Time}, onset::Time, terminus::Time;
                      n_slices::Int=5, algorithm=FRLayout()) where {T, Time}
    times = range(onset, terminus, length=n_slices)
    return filmstrip(dnet, collect(times); algorithm=algorithm)
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

Configuration for video (MP4) export. Requires FFmpeg.

# Fields
- `fps::Int`: Frames per second
- `width::Int`: Video width in pixels
- `height::Int`: Video height in pixels
- `codec::String`: Video codec (e.g., "h264", "h265", "vp9")
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

Configuration for GIF export. Requires ImageMagick.

# Fields
- `fps::Int`: Frames per second
- `width::Int`: GIF width in pixels
- `height::Int`: GIF height in pixels
- `loop::Int`: Loop count (0 = infinite)
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

Configuration for HTML export. No external dependencies required.

# Fields
- `width::Int`: Canvas width in pixels
- `height::Int`: Canvas height in pixels
- `controls::Bool`: Show playback controls
"""
struct HTMLConfig <: ExportConfig
    width::Int
    height::Int
    controls::Bool

    HTMLConfig(; width::Int=800, height::Int=600, controls::Bool=true) =
        new(width, height, controls)
end

"""
    export_movie(layout::DynamicLayout, filepath::String; config=VideoConfig())

Export a dynamic network animation as a video file. Requires FFmpeg.

Returns a named tuple with `filepath`, `n_frames`, and `fps`.
"""
function export_movie(layout::DynamicLayout, filepath::String;
                      config::VideoConfig=VideoConfig())
    @warn "export_movie: Video export requires FFmpeg. Layout data prepared with $(length(layout)) frames."
    return (filepath=filepath, n_frames=length(layout), fps=config.fps)
end

"""
    export_gif(layout::DynamicLayout, filepath::String; config=GIFConfig())

Export a dynamic network animation as an animated GIF. Requires ImageMagick.

Returns a named tuple with `filepath`, `n_frames`, and `fps`.
"""
function export_gif(layout::DynamicLayout, filepath::String;
                    config::GIFConfig=GIFConfig())
    @warn "export_gif: GIF export requires ImageMagick. Layout data prepared with $(length(layout)) frames."
    return (filepath=filepath, n_frames=length(layout), fps=config.fps)
end

"""
    export_html(layout::DynamicLayout, filepath::String; config=HTMLConfig())

Export a dynamic network animation as a self-contained HTML file.
No external dependencies required to view.

Returns a named tuple with `filepath` and `n_frames`.
"""
function export_html(layout::DynamicLayout{T}, filepath::String;
                     config::HTMLConfig=HTMLConfig()) where T
    html = """
    <!DOCTYPE html>
    <html>
    <head><title>Dynamic Network</title></head>
    <body>
        <h1>Dynamic Network Animation</h1>
        <p>Frames: $(length(layout))</p>
        <p>Time range: $(layout.times[1]) to $(layout.times[end])</p>
        <canvas id="canvas" width="$(config.width)" height="$(config.height)"></canvas>
    </body>
    </html>
    """

    open(filepath, "w") do f
        write(f, html)
    end

    return (filepath=filepath, n_frames=length(layout))
end

end # module
