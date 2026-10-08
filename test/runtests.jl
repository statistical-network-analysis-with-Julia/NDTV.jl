using NDTV
using DynamicNetworks
using NetworkCore
using Dates
using Random
using Test
using Aqua

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
        for alg in (FRLayout(), CircleLayout(), RandomLayout(), MDSLayout())
            pos = compute_layout(net, alg; rng=rng)
            @test length(pos) == 6
            @test all(haskey(pos, v) for v in 1:6)
            @test all(all(isfinite, p) for p in values(pos))
        end

        # MDS: connected vertices closer than the far component
        mds = compute_layout(net, MDSLayout())
        d12 = hypot(mds[1][1] - mds[2][1], mds[1][2] - mds[2][2])
        d14 = hypot(mds[1][1] - mds[4][1], mds[1][2] - mds[4][2])
        @test d12 < d14

        # Classical MDS is a closed-form eigenproblem, not an iterative
        # energy minimization: it is deterministic and ignores the rng.
        @test compute_layout(net, MDSLayout(); rng=Random.Xoshiro(3)) ==
              compute_layout(net, MDSLayout(); rng=Random.Xoshiro(4))

        # The layout was once called `KKLayout`, a name that implied
        # Kamada-Kawai energy minimization, which is not what runs. The old
        # name was never released and is gone.
        @test !isdefined(NDTV, :KKLayout)

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
        for alg in (CircleLayout(), RandomLayout(), MDSLayout())
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

        ego_timeline(dnet, 2; width=40, io=io)
        out = String(take!(io))
        @test occursin("vertex 2", out)

        transmission_timeline(dnet, [(1, 2, 3.0)]; width=40, io=io)
        out = String(take!(io))
        @test occursin("1→2", out)

        # R-borrowed names with other meanings are not used (R ndtv's
        # transmissionTimeline draws a tree; proximity.timeline MDS positions);
        # the earlier Julia names were never released and are gone.
        @test !isdefined(NDTV, :transmissionTimeline)
        @test !isdefined(NDTV, :proximity_timeline)
        @test isempty([nm for nm in names(NDTV) if Base.isdeprecated(NDTV, nm)])

        td = timeline_data(dnet)
        @test length(td.vertices) == 4
        @test length(td.edges) == 3

        # Degenerate observation window must not divide by zero
        dz = DynamicNetwork(2; observation_start=1.0, observation_end=1.0)
        activate!(dz, 1.0, 1.0; vertex=1)
        io2 = IOBuffer()
        timeline_plot(dz; width=20, io=io2)
        @test occursin("V1:", String(take!(io2)))
    end

    @testset "Exports" begin
        dnet = dynamic_fixture()
        layout = render_animation(dnet; n_frames=4, rng=Random.Xoshiro(11))

        mktempdir() do dir
            # SVG frame rendering (the pure-Julia backend)
            paths = export_frames(layout, joinpath(dir, "frames"); width=120, height=90)
            @test length(paths) == 4
            svg = read(paths[1], String)
            @test occursin("<svg", svg)
            @test occursin("width=\"120\"", svg)
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
            export_html(layout, joinpath(dir, "nc.html"); config=HTMLConfig(controls=false))
            @test !occursin("id=\"play\"", read(joinpath(dir, "nc.html"), String))

            # A missing binary is a MissingToolError naming the frame
            # directory -- never a silent stub, never a bare ErrorException
            withenv("PATH" => "") do
                err = try
                    export_movie(layout, joinpath(dir, "a.mp4")); nothing
                catch e
                    e
                end
                @test err isa MissingToolError
                @test isdir(err.frames_dir)
                @test length(readdir(err.frames_dir)) == 4
                @test occursin("ffmpeg", sprint(showerror, err))
                @test_throws MissingToolError export_gif(layout, joinpath(dir, "a.gif"))
            end

            # The success paths run wherever the tools are installed. CI's
            # Linux cell installs them and sets NDTV_REQUIRE_EXPORT_TOOLS, so
            # there a missing tool fails the suite instead of skipping.
            require_tools = get(ENV, "NDTV_REQUIRE_EXPORT_TOOLS", "false") == "true"
            if isnothing(Sys.which("ffmpeg"))
                @info "ffmpeg not found: skipping the export_movie success path"
                require_tools ? (@test !isnothing(Sys.which("ffmpeg"))) : (@test_skip false)
            else
                mp4 = joinpath(dir, "anim.mp4")
                r = export_movie(layout, mp4; config=VideoConfig(fps=4, width=160, height=120))
                @test r.filepath == mp4 && r.n_frames == 4 && r.fps == 4
                @test isfile(mp4) && filesize(mp4) > 0
                # An encoder ffmpeg does not have is an informative ArgumentError
                bad = try
                    export_movie(layout, joinpath(dir, "b.mp4");
                                 config=VideoConfig(width=160, height=120, codec="no_such_codec"))
                    nothing
                catch e
                    e
                end
                @test bad isa ArgumentError
                @test occursin("no_such_codec", sprint(showerror, bad))
            end
            if isnothing(Sys.which("magick")) && isnothing(Sys.which("convert"))
                @info "ImageMagick not found: skipping the export_gif success path"
                require_tools ? (@test !isnothing(Sys.which("convert"))) : (@test_skip false)
            else
                gif = joinpath(dir, "anim.gif")
                r = export_gif(layout, gif; config=GIFConfig(fps=4, width=120, height=90))
                @test r.n_frames == 4
                @test isfile(gif) && String(read(gif, 4)) == "GIF8"
            end
        end
    end

    @testset "Configuration types and aliases" begin
        @test VideoConfig() isa ExportConfig && GIFConfig() isa ExportConfig &&
              HTMLConfig() isa ExportConfig
        v = VideoConfig(; fps=12, width=320, height=240, codec="mpeg4")
        @test (v.fps, v.width, v.height, v.codec) == (12, 320, 240, "mpeg4")
        @test (VideoConfig().fps, VideoConfig().codec) == (30, "h264")
        g = GIFConfig(; fps=5, width=100, height=80, loop=2)
        @test (g.fps, g.width, g.height, g.loop) == (5, 100, 80, 2)
        @test (HTMLConfig().width, HTMLConfig().height, HTMLConfig().controls) == (800, 600, true)
        @test compute_animation_layout === render_animation
        dnet = dynamic_fixture()
        a = compute_animation_layout(dnet; n_frames=3, rng=Random.Xoshiro(1))
        b = render_animation(dnet; n_frames=3, rng=Random.Xoshiro(1))
        @test a.positions == b.positions
        @test_throws ArgumentError render_animation(dnet; slice=:bogus)
        @test_throws ArgumentError render_animation(dnet; interpolation=:cubic)
        @test_throws ArgumentError layout_sequence(dnet, [1.0]; rule=:bogus)
        @test_throws ArgumentError layout_sequence(dnet, [1.0, 2.0]; termini=[3.0])
    end

    # =========================================================================
    # R ndtv semantics: activity defaults, frame grid, timelines, layouts
    # =========================================================================

    @testset "Vertices with no spells are active: frames are not empty" begin
        d = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
        activate!(d, 0.0, 10.0; edge=(1, 2)); activate!(d, 0.0, 10.0; edge=(2, 3))
        L = render_animation(d; n_frames=3, rng=Random.Xoshiro(1))
        @test all(==([(1, 2), (2, 3)]), L.frame_edges)       # used to be empty
        @test all(==([1, 2, 3]), L.frame_active)
        @test occursin("<line", NDTV._svg_frame(L, 1, 100, 100))
    end

    @testset "Default window and frame grid" begin
        # No explicit window: the closed range of the change times, as ndtv's
        # default slice.par (never the placeholder (0, 1))
        d = DynamicNetwork(3)
        for v in 1:3; activate!(d, 0.0, 100.0; vertex=v); end
        activate!(d, 10.0, 60.0; edge=(1, 2)); activate!(d, 50.0, 90.0; edge=(2, 3))
        L = render_animation(d; n_frames=5, slice=:instant, rng=Random.Xoshiro(1))
        @test L.times == [0.0, 25.0, 50.0, 75.0, 100.0]    # the last frame is at 100
        @test length.(L.frame_edges) == [0, 1, 2, 1, 0]
        io = IOBuffer(); timeline_plot(d; width=20, io=io)
        @test occursin("Timeline: 0.0 to 100.0", String(take!(io)))
        # Explicit bounds override the window
        Lw = render_animation(d; n_frames=2, onset=50.0, terminus=70.0, rng=Random.Xoshiro(1))
        @test Lw.times == [50.0, 60.0]

        # No frame on the window end, where every half-open spell has ended
        d2 = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
        for v in 1:3; activate!(d2, 0.0, 10.0; vertex=v); end
        activate!(d2, 0.0, 10.0; edge=(1, 2))
        L2 = render_animation(d2; n_frames=3, slice=:instant, rng=Random.Xoshiro(1))
        @test last(L2.times) < 10.0
        @test all(!isempty, L2.frame_edges)                 # the last frame used to be empty

        # Interval slices (the default) keep spells shorter than the frame spacing
        d3 = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
        activate!(d3, 2.0, 4.0; edge=(1, 2)); activate!(d3, 5.0, 5.0; edge=(2, 3))
        inst = render_animation(d3; n_frames=3, slice=:instant, rng=Random.Xoshiro(1))
        intv = render_animation(d3; n_frames=3, rng=Random.Xoshiro(1))
        @test !any(e -> (2, 3) in e, inst.frame_edges)       # the point spell is missed
        @test intv.frame_edges[2] == [(1, 2), (2, 3)]        # slice [3.33, 6.67)
        @test intv.frame_edges[1] == [(1, 2)]
        fs = slice_layout(d3, 0.0, 10.0; n_slices=2, rng=Random.Xoshiro(1))
        @test [f.n_edges for f in fs] == [1, 1]
        fsi = slice_layout(d3, 0.0, 10.0; n_slices=2, slice=:instant, rng=Random.Xoshiro(1))
        @test [f.n_edges for f in fsi] == [0, 1]   # instants 0 and 5 (the point spell)
        @test_throws ArgumentError slice_layout(d3, 0.0, 10.0; slice=:bogus)
    end

    @testset "No observation window: a tie forming at the last change time is drawn" begin
        # A derived half-open window [0, 5) used to leave out the tie that
        # forms at 5 and stays open: no frame ever showed it.
        g = DynamicNetwork(3)
        activate!(g, 0.0, 5.0; edge=(1, 2)); activate!(g, 5.0, Inf; edge=(2, 3))
        L = render_animation(g; n_frames=5, rng=Random.Xoshiro(1))
        @test L.times == [0.0, 1.25, 2.5, 3.75, 5.0]
        @test L.frame_edges == [[(1, 2)], [(1, 2)], [(1, 2)], [(1, 2)], [(2, 3)]]
        L1 = render_animation(g; n_frames=1, rng=Random.Xoshiro(1))
        @test L1.times == [0.0] && sort(L1.frame_edges[1]) == [(1, 2), (2, 3)]
        Li = render_animation(g; n_frames=2, slice=:instant, rng=Random.Xoshiro(1))
        @test Li.frame_edges == [[(1, 2)], [(2, 3)]]
        # An explicit terminus makes the range half-open again
        Lt = render_animation(g; n_frames=2, terminus=4.0, rng=Random.Xoshiro(1))
        @test Lt.times == [0.0, 2.0]
        io = IOBuffer(); timeline_plot(g; width=11, io=io)
        out = String(take!(io))
        @test occursin("Timeline: 0.0 to 5.0", out)
        @test occursin("2→3: |" * " "^10 * "═|", out)
        # Only the window decides the grid once it is set
        set_observation_period!(g, 0.0, 5.0)
        Lw = render_animation(g; n_frames=5, rng=Random.Xoshiro(1))
        @test Lw.times == [0.0, 1.0, 2.0, 3.0, 4.0]
        @test all(e -> !((2, 3) in e), Lw.frame_edges)   # [5, Inf) is after the window

        # DateTime axis, no window: the closed grid lands on the last change
        t0 = DateTime(2024, 1, 1)
        dt = DynamicNetwork{Int, DateTime}(2)
        activate!(dt, t0, t0 + Day(2); edge=(1, 2))
        Ld = render_animation(dt; n_frames=3, slice=:instant, rng=Random.Xoshiro(1))
        @test Ld.times == [t0, t0 + Day(1), t0 + Day(2)]

        # No window and no finite spell bound: no placeholder range, a request
        p = DynamicNetwork(3)
        add_edge!(p.network, 1, 2)
        err = try render_animation(p; n_frames=2); nothing catch e; e end
        @test err isa ArgumentError && occursin("set_observation_period!", err.msg)
        @test_throws ArgumentError timeline_plot(p; io=IOBuffer())
        @test_throws ArgumentError ego_timeline(p, 1; io=IOBuffer())
        @test length(render_animation(p; n_frames=2, onset=0.0, terminus=2.0,
                                      rng=Random.Xoshiro(1))) == 2
        io = IOBuffer(); timeline_plot(p; onset=0.0, terminus=1.0, width=5, io=io)
        @test occursin("1→2: |═════|", String(take!(io)))
        io = IOBuffer(); transmission_timeline(p, [(1, 2, 2.0), (2, 3, 4.0)]; width=11, io=io)
        out = String(take!(io))                          # the range of the events
        @test occursin("1→2: |*" * " "^10 * "| t=2.0", out)
        @test occursin("2→3: |" * " "^10 * "*| t=4.0", out)
    end

    @testset "Integer, Int32 and calendar time axes" begin
        # Frame bounds were interpolated in Float64 and converted back to the
        # axis, so the default call (100 frames) threw an InexactError on any
        # integer axis, including panels built with an integer `start`.
        rng() = Random.Xoshiro(1)
        for (TA, TV) in ((Int, Int), (Int32, Int), (Int, Int32), (Int32, Int32))
            w = DynamicNetwork{TV, TA}(3; observation_start=0, observation_end=10)
            activate!(w, 0, 3; edge=(1, 2)); activate!(w, 3, 7; edge=(2, 3))
            L = render_animation(w; rng=rng())                 # default n_frames
            @test L.times == 0:9 && eltype(L.times) == TA      # one frame per step
            @test L.frame_edges == [fill([(1, 2)], 3); fill([(2, 3)], 4); fill(Tuple{TV,TV}[], 3)]
            L3 = render_animation(w; n_frames=3, rng=rng())    # 10/3 is not whole
            @test L3.times == [0, 3, 7]                        # rounded, contiguous
            @test L3.frame_edges == [[(1, 2)], [(2, 3)], []]
            @test render_animation(w; n_frames=10, rng=rng()).times == 0:9
            err = try render_animation(w; n_frames=11); nothing catch e; e end
            @test err isa ArgumentError && occursin("at most 10 frames", err.msg)
            @test length(slice_layout(w, 0, 10; rng=rng())) == 5
            @test [f.time for f in slice_layout(w, 0, 3; rng=rng())] == [0, 1, 2]
            @test [f.n_edges for f in slice_layout(w, 0, 10; n_slices=3, rng=rng())] == [1, 1, 0]
            @test_throws ArgumentError slice_layout(w, 0, 3; n_slices=4)
            # Without a window: the closed range [0, 7] of the change times
            u = DynamicNetwork{TV, TA}(3)
            activate!(u, 0, 3; edge=(1, 2)); activate!(u, 3, 7; edge=(2, 3))
            Lu = render_animation(u; rng=rng())
            @test Lu.times == 0:7
            @test Lu.frame_edges[4] == [(2, 3)] && isempty(Lu.frame_edges[end])
            @test render_animation(u; n_frames=3, rng=rng()).times == [0, 4, 7]   # 3.5 rounds up
            # Vertex ids of any Integer type in the interpolated layout
            il = InterpolatedLayout(Lu)
            @test get_position(il, 1, 2) == get_position(il, TV(1), 2)
            io = IOBuffer(); timeline_plot(u; width=8, io=io)
            @test occursin("Timeline: 0 to 7", String(take!(io)))
        end

        # An unbounded range is refused (a float window to Inf gave NaN frames;
        # typemax stands for Inf on an integer axis)
        for (TA, hi) in ((Float64, Inf), (Int, typemax(Int)), (DateTime, typemax(DateTime)))
            lo = TA === DateTime ? DateTime(2020) : zero(TA)
            o = DynamicNetwork{Int, TA}(2; observation_start=lo, observation_end=hi)
            err = try render_animation(o; n_frames=3); nothing catch e; e end
            @test err isa ArgumentError && occursin("unbounded time range", err.msg)
            @test_throws ArgumentError slice_layout(o, lo, hi)
        end

        # The panel constructor with an integer start: one frame per wave
        p = [network(4) for _ in 1:3]
        add_edge!(p[1], 1, 2); add_edge!(p[2], 2, 3); add_edge!(p[3], 3, 4)
        for start in (1, Int32(1))
            dp = DynamicNetwork(p; start=start)
            @test get_observation_period(dp) == (1, 4)
            L = render_animation(dp; rng=rng())
            @test L.times == [1, 2, 3]
            @test L.frame_edges == [[(1, 2)], [(2, 3)], [(3, 4)]]
            @test render_animation(dp; n_frames=2, rng=rng()).times == [1, 3]   # 1.5 rounds up
            @test_throws ArgumentError render_animation(dp; n_frames=4)
        end

        # Date axis: whole days (100 frames over five days used to repeat
        # frames, most of them empty instants)
        d0 = Date(2020, 1, 1)
        dd = DynamicNetwork{Int, Date}(3)
        activate!(dd, d0, d0 + Day(3); edge=(1, 2)); activate!(dd, d0 + Day(2), d0 + Day(5); edge=(2, 3))
        Ld = render_animation(dd; rng=rng())
        @test Ld.times == [d0 + Day(k) for k in 0:5]
        @test Ld.frame_edges[3] == [(1, 2), (2, 3)]
        @test render_animation(dd; n_frames=3, rng=rng()).times == [d0, d0 + Day(3), d0 + Day(5)]
        @test_throws ArgumentError render_animation(dd; n_frames=7)

        # DateTime axis: 100 frames, a whole number of milliseconds apart
        t0 = DateTime(2020)
        dt = DynamicNetwork{Int, DateTime}(3; observation_start=t0, observation_end=t0 + Day(3))
        activate!(dt, t0, t0 + Hour(1); edge=(1, 2))
        Lt = render_animation(dt; rng=rng())
        @test length(Lt.times) == 100 && Lt.times[1] == t0
        @test all(==(Millisecond(2_592_000)), diff(Lt.times))     # 3 days / 100
        @test Lt.frame_edges[1:3] == [[(1, 2)], [(1, 2)], []]      # the hour ends in frame 2
        dt7 = DynamicNetwork{Int, DateTime}(2; observation_start=t0, observation_end=t0 + Millisecond(7))
        @test diff(render_animation(dt7; n_frames=3, rng=rng()).times) == Millisecond.([2, 3])
        @test length(render_animation(dt7; rng=rng()).times) == 7

        # Brute force: on random integer networks, every grid has distinct,
        # increasing integer frames, and interval slices lose no spell that
        # overlaps the range (slices are contiguous)
        r = Random.Xoshiro(20261007)
        for _ in 1:150
            n = 4
            g = DynamicNetwork{Int32, Int}(n)
            for _ in 1:rand(r, 1:6)
                i, j = rand(r, 1:n), rand(r, 1:n)
                i == j && continue
                a = rand(r, -5:15)
                activate!(g, a, a + rand(r, 0:6); edge=(i, j))
            end
            isempty(get_change_times(g)) && continue
            lo, hi = extrema(get_change_times(g))
            nf = rand(r, 1:(hi - lo + 1))
            L = render_animation(g; n_frames=nf, algorithm=CircleLayout(), rng=r)
            @test length(L.times) == nf && allunique(L.times) && issorted(L.times)
            @test first(L.times) == lo && (nf == 1 || last(L.times) == hi)
            shown = Set(e for fe in L.frame_edges for e in fe)
            for (key, spells) in g.edge_spells, sp in spells
                # a spell overlapping the closed range [lo, hi] is drawn somewhere
                (sp.onset <= hi && (sp.terminus > lo || sp.onset == sp.terminus >= lo)) &&
                    @test key in shown
            end
        end
    end

    @testset "Open-ended spells in timelines" begin
        d = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
        activate!(d, 0.0, Inf; vertex=1)
        activate!(d, -Inf, 5.0; vertex=2)
        activate!(d, 5.0, Inf; edge=(1, 2))
        io = IOBuffer()
        timeline_plot(d; width=21, io=io)                   # used to throw InexactError
        out = String(take!(io))
        @test occursin("V1: |" * "─"^21 * "|", out)
        @test occursin("V2: |" * "─"^11 * " "^10 * "|", out)
        @test occursin("1→2: |" * " "^10 * "═"^11 * "|", out)
        @test occursin("V3: |" * "─"^21 * "|", out)         # no spells: active throughout
        ego_timeline(d, 1; width=21, io=io)
        @test occursin("→ V2", String(take!(io)))
        transmission_timeline(d, [(1, 2, 20.0)]; width=21, io=io)
        @test occursin("*| t=20.0", String(take!(io)))     # clamped to the window end
        td = timeline_data(d)
        @test (vertex=3, onset=-Inf, terminus=Inf) in td.vertices
        render_animation(d; n_frames=2, rng=Random.Xoshiro(1))   # finite window, no throw
    end

    @testset "Structural layouts use the active vertices only" begin
        # Path 1-2-3 active now; vertices 4-6 only later
        d = DynamicNetwork(6; observation_start=0.0, observation_end=30.0)
        for v in 1:3; activate!(d, 0.0, 10.0; vertex=v); end
        for v in 4:6; activate!(d, 20.0, 30.0; vertex=v); end
        activate!(d, 0.0, 10.0; edge=(1, 2)); activate!(d, 0.0, 10.0; edge=(2, 3))
        activate!(d, 20.0, 30.0; edge=(4, 5))
        path = network(3); add_edge!(path, 1, 2); add_edge!(path, 2, 3)

        mds = compute_slice_layout(d, 1.0; algorithm=MDSLayout())
        @test sort(collect(keys(mds))) == [1, 2, 3]
        @test mds == compute_layout(path, MDSLayout())
        # The path's endpoints are as far apart as possible (they used to
        # collapse towards the inactive vertices' cluster)
        @test hypot((mds[1] .- mds[3])...) ≈ 2.0
        fr = compute_slice_layout(d, 1.0; algorithm=FRLayout(), rng=Random.Xoshiro(4))
        @test fr == compute_layout(path, FRLayout(); rng=Random.Xoshiro(4))
        # Circle/random keep one slot per vertex
        @test length(compute_slice_layout(d, 1.0; algorithm=CircleLayout())) == 6

        # In a sequence every vertex has a position in every frame: inactive
        # vertices hold the position they last had (or will first have)
        L = layout_sequence(d, [1.0, 25.0]; algorithm=MDSLayout())
        @test all(haskey(L[k], v) for k in 1:2, v in 1:6)
        @test L[2][1] == L[1][1] && L[2][3] == L[1][3]       # carried forward
        @test L[1][4] == L[2][4] && L[1][6] == L[2][6]       # back-filled
        @test L.frame_active == [[1, 2, 3], [4, 5, 6]]
    end

    @testset "FR symmetrises directed graphs" begin
        dir = network(3); add_edge!(dir, 1, 2); add_edge!(dir, 2, 1); add_edge!(dir, 2, 3)
        und = network(3; directed=false); add_edge!(und, 1, 2); add_edge!(und, 2, 3)
        one = network(3); add_edge!(one, 1, 2); add_edge!(one, 2, 3)
        # A mutual pair attracts once: same picture as the undirected graph
        @test compute_layout(dir, FRLayout(); rng=Random.Xoshiro(8)) ==
              compute_layout(und, FRLayout(); rng=Random.Xoshiro(8)) ==
              compute_layout(one, FRLayout(); rng=Random.Xoshiro(8))
        @test NDTV._attraction_pairs(dir) == [(1, 2), (2, 3)]
    end

    @testset "MDS lays out each component separately" begin
        net = network(4; directed=false); add_edge!(net, 1, 2); add_edge!(net, 3, 4)
        p = compute_layout(net, MDSLayout())
        @test length(unique(values(p))) == 4                 # nothing collapses
        d(a, b) = hypot((p[a] .- p[b])...)
        @test d(1, 2) ≈ d(3, 4)
        @test d(1, 2) < d(2, 3)
        @test maximum(abs, Iterators.flatten(values(p))) ≈ 1.0
        # Directed graphs use the symmetrised geodesics (1->2<-3 is a path)
        dg = network(3); add_edge!(dg, 1, 2); add_edge!(dg, 3, 2)
        ug = network(3; directed=false); add_edge!(ug, 1, 2); add_edge!(ug, 3, 2)
        @test compute_layout(dg, MDSLayout()) == compute_layout(ug, MDSLayout())
    end

    @testset "Undirected timelines use an undirected connector" begin
        d = DynamicNetwork(3; observation_start=0.0, observation_end=10.0, directed=false)
        activate!(d, 1.0, 5.0; edge=(3, 1))
        io = IOBuffer()
        ego_timeline(d, 3; width=20, io=io)
        out = String(take!(io))
        @test occursin("— V1", out) && !occursin("→", out) && !occursin("←", out)
        timeline_plot(d; width=20, io=io)
        @test occursin("1—3:", String(take!(io)))
    end

    @testset "filmstrip returns a concretely typed vector" begin
        fs = filmstrip(dynamic_fixture(), [1.0, 6.0]; rng=Random.Xoshiro(1))
        @test isconcretetype(eltype(fs))
        @test fs[1].time == 1.0 && fs[1].active == [1, 2, 3]
        fsi = filmstrip(dynamic_fixture(), [1.0]; termini=[6.0], rng=Random.Xoshiro(1))
        @test fsi[1].n_vertices == 4                        # vertex 4 joins at 5
    end

    @testset "Golden fixture: MDSLayout vs R cmdscale of geodesic distances" begin
        fx = NetworkCore.load_golden(joinpath(@__DIR__, "fixtures", "mds_layout.toml"))
        V = fx.values
        tol = fx.tolerance["distance"]
        for g in 1:V["n_cases"]
            c = V["case_$g"]
            n = c["n"]
            net = network(n; directed=c["directed"])
            for (i, j) in c["edges"]
                add_edge!(net, i, j)
            end
            pos = compute_layout(net, MDSLayout())
            # Invariant under rotation, reflection, translation and scale:
            # pairwise distances over their maximum (R's upper.tri order)
            d = [hypot(pos[i][1] - pos[j][1], pos[i][2] - pos[j][2])
                 for j in 2:n for i in 1:(j - 1)]
            @test isapprox(d ./ maximum(d), c["distances"]; atol=tol)
        end
    end

    @testset "Every exported docstring carries a runnable example" begin
        meta = Base.Docs.meta(NDTV)
        documented_elsewhere(b) = any(haskey(Base.Docs.meta(m), b)
                                      for m in (NetworkCore, DynamicNetworks, NetworkCore.Graphs))
        undocumented = String[]; missing_example = String[]
        blocks = Tuple{String,String}[]
        for nm in names(NDTV)
            nm === :NDTV && continue
            # Deprecated bindings without a docstring of their own
            Base.isdeprecated(NDTV, nm) && !haskey(meta, Base.Docs.Binding(NDTV, nm)) && continue
            b = Base.Docs.Binding(NDTV, nm)
            if !haskey(meta, b)
                documented_elsewhere(b) || push!(undocumented, string(nm))
                continue
            end
            has_example = false
            for (_, ds) in meta[b].docs
                txt = ds.text isa AbstractString ? ds.text : join(string.(ds.text), "\n")
                for m in eachmatch(r"```julia\n(.*?)```"s, txt)
                    has_example = true
                    push!(blocks, (string(nm), String(m.captures[1])))
                end
                # Sketches that need external binaries use a ```jl fence
                occursin("```jl\n", txt) && (has_example = true)
            end
            has_example || push!(missing_example, string(nm))
        end
        @test isempty(undocumented)
        @test isempty(missing_example)
        @test length(blocks) >= 25
        for (nm, code) in blocks
            m = Module(Symbol("DocExample_", nm))
            ok = try
                Core.eval(m, :(using NDTV))
                redirect_stdout(devnull) do
                    Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
                        Core.eval(m, Meta.parseall(code; filename="docstring:$nm"))
                    end
                end
                true
            catch err
                println(stderr, "docstring example of $nm failed: ", sprint(showerror, err))
                false
            end
            @test ok
        end
    end

    @testset "Aqua" begin
        Aqua.test_all(NDTV)
        @test isempty(Test.detect_ambiguities(NDTV))
    end
end
