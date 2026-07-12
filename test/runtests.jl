using NDTV
using NetworkDynamic
using Network
using Dates
using Random
using Test

# Dynamic network with CHANGING vertex membership: vertex 4 activates
# late, vertex 1 deactivates early — the case that used to scramble
# identities.
function dynamic_fixture()
    dnet = DynamicNetwork(4; observation_start=0.0, observation_end=10.0)
    activate!(dnet, 0.0, 5.0; vertex=1)
    activate!(dnet, 0.0, 10.0; vertex=2)
    activate!(dnet, 0.0, 10.0; vertex=3)
    activate!(dnet, 5.0, 10.0; vertex=4)
    activate!(dnet, 0.0, 5.0; edge=(1, 2))
    activate!(dnet, 0.0, 10.0; edge=(2, 3))
    activate!(dnet, 5.0, 10.0; edge=(3, 4))
    return dnet
end

@testset "NDTV.jl" begin
    @testset "Static layouts (all algorithms)" begin
        net = network(6)
        add_edge!(net, 1, 2)
        add_edge!(net, 2, 3)
        add_edge!(net, 4, 5)

        rng = Random.Xoshiro(1)
        for alg in (FRLayout(), CircleLayout(), RandomLayout(), KKLayout())
            pos = compute_layout(net, alg; rng=rng)
            @test length(pos) == 6
            @test all(haskey(pos, v) for v in 1:6)
            @test all(all(isfinite, p) for p in values(pos))
        end

        # KK: connected vertices closer than the far component
        kk = compute_layout(net, KKLayout())
        d12 = hypot(kk[1][1] - kk[2][1], kk[1][2] - kk[2][2])
        d14 = hypot(kk[1][1] - kk[4][1], kk[1][2] - kk[4][2])
        @test d12 < d14

        # Reproducible with the same rng seed
        p1 = compute_layout(net, FRLayout(); rng=Random.Xoshiro(9))
        p2 = compute_layout(net, FRLayout(); rng=Random.Xoshiro(9))
        @test p1 == p2
    end

    @testset "Stable vertex identity across slices" begin
        dnet = dynamic_fixture()
        rng = Random.Xoshiro(3)

        layout = layout_sequence(dnet, [2.0, 7.0]; rng=rng)

        # Positions keyed by the persistent IDs 1:4 in every frame,
        # regardless of which vertices are active
        @test length(layout) == 2
        @test all(haskey(layout[1], v) for v in 1:4)
        @test all(haskey(layout[2], v) for v in 1:4)

        # Active sets and edges tracked with real identities
        @test sort(layout.frame_active[1]) == [1, 2, 3]
        @test sort(layout.frame_active[2]) == [2, 3, 4]
        @test (2, 3) in layout.frame_edges[1]
        @test (3, 4) in layout.frame_edges[2]
        @test !((1, 2) in layout.frame_edges[2])
    end

    @testset "Anchoring moves persistent vertices smoothly" begin
        dnet = dynamic_fixture()
        rng = Random.Xoshiro(5)

        anchored = layout_sequence(dnet, collect(0.0:1.0:9.0); anchor=true, rng=rng)

        # Vertex 2 is active throughout; its frame-to-frame displacement
        # under anchoring should be modest (anchored refinement, not a
        # fresh random layout each frame)
        moves = [hypot(anchored[i][2][1] - anchored[i-1][2][1],
                       anchored[i][2][2] - anchored[i-1][2][2])
                 for i in 2:length(anchored)]
        @test maximum(moves) < 1.5

        # Non-FR algorithms are anchored without MethodError (this threw
        # before)
        for alg in (CircleLayout(), RandomLayout(), KKLayout())
            l = layout_sequence(dnet, [2.0, 7.0]; algorithm=alg, anchor=true, rng=rng)
            @test length(l) == 2
        end

        # Deterministic circle layout: identical coordinates every frame
        lc = layout_sequence(dnet, [2.0, 7.0]; algorithm=CircleLayout(), rng=rng)
        @test lc[1] == lc[2]

        # Anchored RandomLayout keeps previous positions
        lr = layout_sequence(dnet, [2.0, 7.0]; algorithm=RandomLayout(),
                             anchor=true, rng=rng)
        @test lr[1] == lr[2]
    end

    @testset "Interpolation" begin
        positions = [Dict(1 => (0.0, 0.0)), Dict(1 => (1.0, 2.0))]
        base = DynamicLayout(positions, [0.0, 1.0])
        il = InterpolatedLayout(base)

        @test get_position(il, 1, 0.0) == (0.0, 0.0)
        @test get_position(il, 1, 1.0) == (1.0, 2.0)
        @test get_position(il, 1, 0.5) == (0.5, 1.0)   # exact midpoint
        @test get_position(il, 1, -1.0) == (0.0, 0.0)  # clamped below
        @test get_position(il, 1, 5.0) == (1.0, 2.0)   # clamped above

        # Easing hits the same endpoints, differs in the middle
        ile = InterpolatedLayout(base; interpolation=:ease)
        @test get_position(ile, 1, 0.0) == (0.0, 0.0)
        @test get_position(ile, 1, 0.25)[1] < 0.25
    end

    @testset "DateTime time axis" begin
        dnet = DynamicNetwork{Int, DateTime}(3)
        t0 = DateTime(2024, 1, 1)
        t1 = DateTime(2024, 1, 11)
        set_observation_period!(dnet, t0, t1)
        activate!(dnet, t0, t1; vertex=1)
        activate!(dnet, t0, t1; vertex=2)
        activate!(dnet, t0, t1; edge=(1, 2))

        # This used to throw on Float64.(times)
        layout = render_animation(dnet; n_frames=5, rng=Random.Xoshiro(2))
        @test layout isa DynamicLayout
        @test length(layout) == 5
        @test layout.times[1] == t0

        il = InterpolatedLayout(layout)
        mid = t0 + Day(5)
        p = get_position(il, 1, mid)
        @test all(isfinite, p)
    end

    @testset "render_animation and filmstrip" begin
        dnet = dynamic_fixture()
        rng = Random.Xoshiro(7)

        layout = render_animation(dnet; n_frames=8, rng=rng)
        @test layout isa DynamicLayout
        @test length(layout) == 8

        eased = render_animation(dnet; n_frames=8, interpolation=:ease, rng=rng)
        @test eased isa InterpolatedLayout

        frames = filmstrip(dnet, [1.0, 6.0]; rng=rng)
        @test length(frames) == 2
        @test frames[1].n_vertices == 3
        @test frames[2].n_vertices == 3
        @test frames[2].n_edges == 2   # (2,3) and (3,4) active at 6.0

        slices = slice_layout(dnet, 0.0, 10.0; n_slices=4, rng=rng)
        @test length(slices) == 4
    end

    @testset "Timelines" begin
        dnet = dynamic_fixture()
        io = IOBuffer()
        timeline_plot(dnet; width=40, io=io)
        out = String(take!(io))
        @test occursin("Timeline: 0.0 to 10.0", out)
        @test occursin("V1:", out)
        @test occursin("2→3:", out)

        proximity_timeline(dnet, 2; width=40, io=io)
        out = String(take!(io))
        @test occursin("vertex 2", out)

        transmissionTimeline(dnet, [(1, 2, 3.0)]; width=40, io=io)
        out = String(take!(io))
        @test occursin("1→2", out)

        # snake_case primary name with R-style camelCase alias
        @test transmissionTimeline === transmission_timeline
        transmission_timeline(dnet, [(1, 2, 3.0)]; width=40, io=io)
        @test occursin("1→2", String(take!(io)))

        td = timeline_data(dnet)
        @test length(td.vertices) == 4
        @test length(td.edges) == 3

        # Degenerate observation window must not divide by zero
        dz = DynamicNetwork(2; observation_start=1.0, observation_end=1.0)
        activate!(dz, 1.0, 1.0; vertex=1)
        timeline_plot(dz; width=20, io=IOBuffer())
        @test true
    end

    @testset "Exports" begin
        dnet = dynamic_fixture()
        layout = render_animation(dnet; n_frames=4, rng=Random.Xoshiro(11))

        mktempdir() do dir
            # SVG frame rendering (the pure-Julia backend)
            paths = export_frames(layout, joinpath(dir, "frames"))
            @test length(paths) == 4
            svg = read(paths[1], String)
            @test occursin("<svg", svg)
            @test occursin("<circle", svg)   # active vertices drawn

            # Self-contained HTML player with embedded data
            html_path = joinpath(dir, "anim.html")
            result = export_html(layout, html_path)
            @test result.n_frames == 4
            html = read(html_path, String)
            @test occursin("const frames", html)   # data embedded
            @test occursin("canvas", html)
            @test occursin("getContext", html)     # real drawing code
            @test occursin("nodes:[", html)

            # Movie/GIF export either succeeds (tool installed) or throws
            # an informative error — never a silent stub
            if isnothing(Sys.which("ffmpeg"))
                @test_throws ErrorException export_movie(layout,
                                                         joinpath(dir, "a.mp4"))
            end
        end
    end
end
