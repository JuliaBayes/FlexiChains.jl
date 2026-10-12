module PPCTests

using Test
using CairoMakie: CairoMakie, Makie
using FlexiChains: FlexiChains as FC, FlexiChain
using StableRNGs: StableRNG

@testset "ppc_density" begin
    N_iters, N_chains, N_components = 30, 2, 30
    rng = StableRNG(1)
    chn = FlexiChain{Symbol}(randn(rng, N_iters, N_chains, N_components), :y_pred)
    observed = randn(rng, N_components)

    @testset "return types" begin
        @test FC.Makie.ppc_density(chn, :y_pred) isa Makie.FigureAxisPlot
        @test FC.Makie.ppc_density(chn, :y_pred; observed=observed) isa Makie.FigureAxisPlot
        fig = Makie.Figure()
        ax = Makie.Axis(fig[1, 1])
        @test FC.Makie.ppc_density!(ax, chn, :y_pred) isa Makie.AxisPlot
        @test FC.Makie.ppc_density!(chn, :y_pred) isa Makie.AxisPlot
    end

    @testset "number of curves" begin
        ncurves(fap) = count(p -> p isa Makie.Lines, fap.axis.scene.plots)
        @test ncurves(FC.Makie.ppc_density(chn, :y_pred; n_draws=7)) == 7
        @test ncurves(FC.Makie.ppc_density(chn, :y_pred; n_draws=1)) == 1
        @test ncurves(FC.Makie.ppc_density(chn, :y_pred; n_draws=nothing)) ==
              N_iters * N_chains
        @test ncurves(FC.Makie.ppc_density(chn, :y_pred; n_draws=61)) == N_iters * N_chains
        @test ncurves(FC.Makie.ppc_density(chn, :y_pred; n_draws=7, observed=observed)) == 8
    end

    @testset "errors" begin
        @test_throws "length of `observed` (29) must match the number of components of `param` (30)" FC.Makie.ppc_density(
            chn,
            :y_pred;
            observed=observed[1:29],
        )
        int_chn =
            FlexiChain{Symbol}(rand(rng, 1:10, N_iters, N_chains, N_components), :y_pred)
        @test_throws "`ppc_density` does not support integer-valued draws, use `pushforward_hist`" FC.Makie.ppc_density(
            int_chn,
            :y_pred,
        )
    end
end

end # module
