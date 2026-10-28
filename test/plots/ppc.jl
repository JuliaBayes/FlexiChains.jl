module PPCTests

using Test
using CairoMakie: CairoMakie, Makie
using FlexiChains: FlexiChains as FC, FlexiChain
using StableRNGs: StableRNG

@testset "ppc_plot" begin
    N_iters, N_chains, N_components = 30, 2, 30
    rng = StableRNG(1)
    chn = FlexiChain{Symbol}(randn(rng, N_iters, N_chains, N_components), :y_pred)
    observed = randn(rng, N_components)

    @testset "return types" begin
        @test FC.Makie.ppc_plot(chn, :y_pred) isa Makie.FigureAxisPlot
        @test FC.Makie.ppc_plot(chn, :y_pred; observed=observed) isa Makie.FigureAxisPlot
        fig = Makie.Figure()
        ax = Makie.Axis(fig[1, 1])
        @test FC.Makie.ppc_plot!(ax, chn, :y_pred) isa Makie.AxisPlot
        @test FC.Makie.ppc_plot!(chn, :y_pred) isa Makie.AxisPlot
    end

    @testset "number of curves" begin
        ncurves(fap) = count(p -> p isa Makie.Lines, fap.axis.scene.plots)
        @test ncurves(FC.Makie.ppc_plot(chn, :y_pred; n_draws=7)) == 7
        @test ncurves(FC.Makie.ppc_plot(chn, :y_pred; n_draws=1)) == 1
        @test ncurves(FC.Makie.ppc_plot(chn, :y_pred; n_draws=nothing)) ==
              N_iters * N_chains
        @test ncurves(FC.Makie.ppc_plot(chn, :y_pred; n_draws=61)) == N_iters * N_chains
        @test ncurves(FC.Makie.ppc_plot(chn, :y_pred; n_draws=7, observed=observed)) == 8
    end

    @testset "matrix-valued parameter and observed" begin
        mat_draws = [
            Dict(FC.Parameter(:y_mat) => randn(rng, 2, 3)) for
            _ in 1:N_iters, _ in 1:N_chains
        ]
        mat_chn = FlexiChain{Symbol}(N_iters, N_chains, mat_draws)
        observed_mat = randn(rng, 2, 3)
        @test FC.Makie.ppc_plot(mat_chn, :y_mat; observed=observed_mat) isa
              Makie.FigureAxisPlot
    end

    @testset "rootogram for integer-valued draws" begin
        int_chn =
            FlexiChain{Symbol}(rand(rng, 0:10, N_iters, N_chains, N_components), :y_pred)
        int_observed = rand(rng, 0:12, N_components)
        nplots(fap, T) = count(p -> p isa T, fap.axis.scene.plots)

        fap = FC.Makie.ppc_plot(int_chn, :y_pred; observed=int_observed)
        @test fap isa Makie.FigureAxisPlot
        @test fap.plot isa Makie.Scatter
        @test nplots(fap, Makie.Scatter) == 2
        @test nplots(fap, Makie.Rangebars) == 1
        @test nplots(fap, Makie.Lines) == 0
        @test fap.axis.ylabel[] == "count"

        interval_bars = only(filter(p -> p isa Makie.Rangebars, fap.axis.scene.plots))
        mean_dots = first(filter(p -> p isa Makie.Scatter, fap.axis.scene.plots))
        lower_frequencies = getindex.(interval_bars[1][], 2)
        upper_frequencies = getindex.(interval_bars[1][], 3)
        mean_frequencies = last.(mean_dots[1][])
        @test all(lower_frequencies .<= mean_frequencies .<= upper_frequencies)

        legend = only(filter(c -> c isa Makie.Legend, fap.figure.content))
        legend_entries = only(legend.entrygroups[])[2]
        @test [e.label[] for e in legend_entries] == ["predicted", "observed"]
        @test all(e -> only(e.elements) isa Makie.MarkerElement, legend_entries)

        fap_no_observed = FC.Makie.ppc_plot(int_chn, :y_pred)
        @test nplots(fap_no_observed, Makie.Scatter) == 1
        @test nplots(fap_no_observed, Makie.Rangebars) == 1

        @test_throws "`observed` must contain integers when the draws of `param` are integers; got element type Float64" FC.Makie.ppc_plot(
            int_chn,
            :y_pred;
            observed=float.(int_observed),
        )

        fig = Makie.Figure()
        ax = Makie.Axis(fig[1, 1])
        @test FC.Makie.ppc_plot!(ax, int_chn, :y_pred; observed=int_observed) isa
              Makie.AxisPlot
    end

    @testset "errors" begin
        @test_throws "length of `observed` (29) must match the number of components of `param` (30)" FC.Makie.ppc_plot(
            chn,
            :y_pred;
            observed=observed[1:29],
        )
    end
end

end # module
