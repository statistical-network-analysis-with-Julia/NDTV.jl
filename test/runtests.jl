using NDTV
using Test

@testset "NDTV.jl" begin
    @testset "Module loading" begin
        @test @isdefined(NDTV)
    end

    @testset "Layout algorithm types" begin
        @testset "FRLayout" begin
            fr = FRLayout()
            @test fr isa FRLayout
            @test fr.iterations == 100
            @test fr.cooling == 0.95
            @test fr.k == 1.0

            fr2 = FRLayout(; iterations=50, cooling=0.9, k=2.0)
            @test fr2.iterations == 50
        end

        @testset "CircleLayout" begin
            cl = CircleLayout()
            @test cl isa CircleLayout
            @test cl.radius == 1.0
        end

        @testset "RandomLayout" begin
            rl = RandomLayout()
            @test rl isa RandomLayout
        end

        @testset "KKLayout" begin
            kk = KKLayout()
            @test kk isa KKLayout
            @test kk.iterations == 100
        end
    end

    @testset "DynamicLayout construction" begin
        positions = [Dict(1 => (0.0, 0.0), 2 => (1.0, 1.0))]
        times = [0.0]
        dl = DynamicLayout(positions, times)
        @test dl isa DynamicLayout{Int}
        @test length(dl) == 1
    end

    @testset "InterpolatedLayout construction" begin
        positions = [
            Dict(1 => (0.0, 0.0)),
            Dict(1 => (1.0, 1.0)),
        ]
        times = [0.0, 1.0]
        dl = DynamicLayout(positions, times)
        il = InterpolatedLayout(dl)
        @test il isa InterpolatedLayout{Int}

        pos = get_position(il, 1, 0.5)
        @test pos isa Tuple{Float64, Float64}
    end

    @testset "Export config types" begin
        @test VideoConfig() isa VideoConfig
        @test GIFConfig() isa GIFConfig
        @test HTMLConfig() isa HTMLConfig

        vc = VideoConfig(; fps=60, width=1920, height=1080)
        @test vc.fps == 60
        @test vc.width == 1920
    end

    @testset "Animation API" begin
        @test isdefined(NDTV, :render_animation)
        @test isdefined(NDTV, :compute_animation_layout)
    end

    @testset "Timeline API" begin
        @test isdefined(NDTV, :timeline_plot)
        @test isdefined(NDTV, :proximity_timeline)
        @test isdefined(NDTV, :transmissionTimeline)
        @test isdefined(NDTV, :timeline_data)
    end

    @testset "Filmstrip API" begin
        @test isdefined(NDTV, :filmstrip)
        @test isdefined(NDTV, :slice_layout)
    end

    @testset "Export API" begin
        @test isdefined(NDTV, :export_movie)
        @test isdefined(NDTV, :export_gif)
        @test isdefined(NDTV, :export_html)
    end
end
