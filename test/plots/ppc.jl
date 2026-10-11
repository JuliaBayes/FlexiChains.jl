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
        @test ncurves(FC.Makie.ppc_density(chn, :y_pred; ndraws=7)) == 7
        @test ncurves(FC.Makie.ppc_density(chn, :y_pred; ndraws=1)) == 1
        @test ncurves(FC.Makie.ppc_density(chn, :y_pred; ndraws=nothing)) ==
              N_iters * N_chains
        @test ncurves(FC.Makie.ppc_density(chn, :y_pred; ndraws=7, observed=observed)) == 8
    end

    @testset "errors" begin
        @test_throws "`ndraws` (61) exceeds the number of pooled draws (60)" FC.Makie.ppc_density(
            chn,
            :y_pred;
            ndraws=61,
        )
        @test_throws "length of `observed` (29) must match the number of components of `param` (30)" FC.Makie.ppc_density(
            chn,
            :y_pred;
            observed=observed[1:29],
        )
        int_chn =
            FlexiChain{Symbol}(rand(rng, 1:10, N_iters, N_chains, N_components), :y_pred)
        @test_throws "use `pushforward_hist` for discrete outcomes" FC.Makie.ppc_density(
            int_chn,
            :y_pred,
        )
    end
end

@testset "uniformity test" begin
    PU = FC.PlotUtils

    @testset "pointwise p-values" begin
        # Beta(1, 2) CDF at 0.2 is 1 - 0.8^2 = 0.36; Beta(2, 1) CDF at 0.8 is 0.8^2 = 0.64.
        @test PU.pointwise_pvalues(PU.POT(), [0.2, 0.8]) ≈ [0.72, 0.72]
        # Binomial(2, 0.5): CDF at 2 is 1 and the probability mass at 2 is 0.25.
        @test PU.pointwise_pvalues(PU.PRIT(), [0.5, 0.5]) ≈ [0.25, 0.25]
        @test PU.pointwise_pvalues(PU.PRIT(), [0.25, 0.25, 0.75, 0.75]) ≈
              [0.3125, 0.3125, 0.31640625, 0.31640625]
    end

    @testset "truncated Cauchy combination" begin
        @test PU.truncated_cauchy_combination([0.5, 0.7, 0.8, 0.9]) == 0.5
        pvalues = [0.1, 0.2, 0.3, 0.4, 0.7, 0.8]
        mean_truncated = sum(p -> tan((0.5 - p) * π), pvalues[1:4]) / 6
        @test PU.truncated_cauchy_combination(pvalues) ≈ 0.5 - atan(mean_truncated) / π
    end

    @testset "Shapley contributions" begin
        # p-values of 0.25 and 0.75 transform to 1 and -1.
        @test PU.cauchy_transform(0.25) ≈ 1
        @test PU.cauchy_transform(0.75) ≈ -1
        @test PU.shapley_contributions([0.25, 0.75]) ≈ [1.0, -1.0]
        @test PU.shapley_contributions([0.3]) == [0.0]
        pvalues = [0.05, 0.2, 0.6, 0.9, 0.35]
        @test sum(PU.shapley_contributions(pvalues)) ≈
              sum(PU.cauchy_transform, pvalues) / length(pvalues)
    end

    @testset "invalid PIT values" begin
        @test_throws "PIT values must be sorted" PU.uniformity_test(PU.POT(), [0.4, 0.2])
        @test_throws "PIT values must lie strictly between 0 and 1" PU.uniformity_test(
            PU.POT(),
            [0.0, 0.2],
        )
        @test_throws "PIT values must be non-empty" PU.uniformity_test(PU.POT(), Float64[])
    end
end

@testset "ppc_pit_ecdf" begin
    N_iters, N_chains, N_components = 50, 2, 30
    rng = StableRNG(2)
    # Draws on [0, 1) and observations on [0.25, 0.75): no observation is outside the range
    # of its predictive draws.
    chn = FlexiChain{Symbol}(rand(rng, N_iters, N_chains, N_components), :y_pred)
    observed = 0.25 .+ 0.5 .* rand(rng, N_components)
    int_chn = FlexiChain{Symbol}(rand(rng, 0:5, N_iters, N_chains, N_components), :y_pred)
    int_observed = rand(rng, 0:5, N_components)
    pit = rand(rng, N_components)

    @testset "return types" begin
        @test FC.Makie.ppc_pit_ecdf(chn, :y_pred, observed) isa Makie.FigureAxisPlot
        @test FC.Makie.ppc_pit_ecdf(pit) isa Makie.FigureAxisPlot
        fig = Makie.Figure()
        ax = Makie.Axis(fig[1, 1])
        @test FC.Makie.ppc_pit_ecdf!(ax, chn, :y_pred, observed) isa Makie.AxisPlot
        @test FC.Makie.ppc_pit_ecdf!(chn, :y_pred, observed) isa Makie.AxisPlot
        @test FC.Makie.ppc_pit_ecdf!(ax, pit) isa Makie.AxisPlot
        @test FC.Makie.ppc_pit_ecdf!(pit) isa Makie.AxisPlot
    end

    @testset "choice of uniformity test" begin
        PU = FC.PlotUtils
        @test PU.uniformity_test_for(Float64, Float64) isa PU.POT
        @test PU.uniformity_test_for(Float32, Float64) isa PU.POT
        @test PU.uniformity_test_for(Int, Int) isa PU.PRIT
        @test PU.uniformity_test_for(Int32, Int) isa PU.PRIT
        @test FC.Makie.ppc_pit_ecdf(int_chn, :y_pred, int_observed; rng=StableRNG(1)) isa
              Makie.FigureAxisPlot
    end

    @testset "rng only breaks ties" begin
        check(rng, chn, observed) =
            FC.PlotUtils.pit_ecdf_check(rng, chn, :y_pred, observed, 0.99)
        @test check(StableRNG(1), chn, observed) == check(StableRNG(2), chn, observed)
        @test check(StableRNG(1), int_chn, int_observed) ==
              check(StableRNG(1), int_chn, int_observed)
        @test check(StableRNG(1), int_chn, int_observed) !=
              check(StableRNG(2), int_chn, int_observed)
    end

    @testset "errors" begin
        @test_throws "length of `observed` (29) must match the number of components of `param` (30)" FC.Makie.ppc_pit_ecdf(
            chn,
            :y_pred,
            observed[1:29],
        )
        @test_throws "got element types Float64 and Int64" FC.Makie.ppc_pit_ecdf(
            chn,
            :y_pred,
            int_observed,
        )
        @test_throws "got element types Int64 and Float64" FC.Makie.ppc_pit_ecdf(
            int_chn,
            :y_pred,
            float.(int_observed),
        )

        outside_range = copy(observed)
        outside_range[[3, 7]] = [5.0, -1.0]
        @test_throws "2 observation(s) lie outside the range of all predictive draws (indices [3, 7]); the uniformity test is undefined" FC.Makie.ppc_pit_ecdf(
            chn,
            :y_pred,
            outside_range,
        )
        int_outside_range = copy(int_observed)
        int_outside_range[4] = 9
        @test_throws "1 observation(s) lie outside the range of all predictive draws (indices [4]); the uniformity test is undefined" FC.Makie.ppc_pit_ecdf(
            int_chn,
            :y_pred,
            int_outside_range,
        )
        @test_throws "1 observation(s) lie outside the range of all predictive draws (indices [2]); the uniformity test is undefined" FC.Makie.ppc_pit_ecdf([
            0.3,
            1.0,
            0.6,
        ],)
        @test_throws "1 observation(s) lie outside the range of all predictive draws (indices [1]); the uniformity test is undefined" FC.Makie.ppc_pit_ecdf([
            0.0,
            0.3,
            0.6,
        ],)

        @test_throws "PIT values must lie in [0, 1]; got values outside it at indices [2]" FC.Makie.ppc_pit_ecdf([
            0.3,
            1.2,
            0.6,
        ],)
        @test_throws "PIT values must be non-empty" FC.Makie.ppc_pit_ecdf(Float64[])
        for prob in (0, 1, 1.5)
            @test_throws "`prob` must lie strictly between 0 and 1; got $prob" FC.Makie.ppc_pit_ecdf(
                pit;
                prob=prob,
            )
            @test_throws "`prob` must lie strictly between 0 and 1; got $prob" FC.Makie.ppc_pit_ecdf(
                chn,
                :y_pred,
                observed;
                prob=prob,
            )
        end
    end
end

end # module
