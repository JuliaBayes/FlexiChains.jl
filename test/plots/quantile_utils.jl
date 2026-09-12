module QuantileUtilsTests

using Test
using Statistics: Statistics
using FlexiChains: FlexiChains as FC
using FlexiChains: FlexiChain, Parameter
using OrderedCollections: OrderedDict
using StableRNGs: StableRNG
const PU = FC.PlotUtils

@testset "compute_quantile_bands" begin
    levels = [0.25, 0.5, 0.75]

    @testset "single-chain matrix = direct quantile" begin
        data = reshape(collect(1.0:100.0), :, 1)
        bands = PU.compute_quantile_bands(data, levels)
        @test length(bands) == 3
        @test bands ≈ [25.75, 50.5, 75.25] atol = 1.0e-6
    end

    @testset "identical chains = same as single chain" begin
        col = collect(1.0:100.0)
        data = hcat(col, col)
        bands = PU.compute_quantile_bands(data, levels)
        single = PU.compute_quantile_bands(reshape(col, :, 1), levels)
        @test bands ≈ single atol = 1.0e-9
    end

    @testset "ensemble differs from pooled when chains differ" begin
        # Distinct per-chain distributions + an asymmetric level so the ensemble
        # estimate provably differs from a naive pooled quantile.
        c1 = collect(1.0:100.0)
        c2 = collect(101.0:200.0)
        data = hcat(c1, c2)
        ensemble = PU.compute_quantile_bands(data, [0.25])
        expected =
            (
                PU.compute_quantile_bands(reshape(c1, :, 1), [0.25]) .+
                PU.compute_quantile_bands(reshape(c2, :, 1), [0.25])
            ) ./ 2
        pooled = Statistics.quantile(vec(data), 0.25)
        @test ensemble ≈ expected atol = 1.0e-9
        @test !isapprox(ensemble[1], pooled; atol=1.0e-6)  # guards against pooling regression
    end
end

@testset "level_to_quantile_bounds" begin
    @test all(PU.level_to_quantile_bounds(0.95) .≈ (0.025, 0.975))
    @test PU.level_to_quantile_bounds(0.5) == (0.25, 0.75)

    for bad in (0.0, 1.0, -0.1, 1.1)
        @test_throws "level must be in (0, 1), got $bad" PU.level_to_quantile_bounds(bad)
    end
end

@testset "binning utilities" begin
    @testset "get_bin_edges spans the range" begin
        edges = PU.get_bin_edges([0.0, 10.0, 5.0], 5)
        @test length(edges) == 6
        @test first(edges) == 0.0
        @test last(edges) == 10.0
    end

    @testset "get_bin_edges degenerate + empty" begin
        edges = PU.get_bin_edges([5.0, 5.0], 4)   # constant input
        @test length(edges) == 5
        @test first(edges) == 5.0
        @test last(edges) > 5.0
        @test_throws ArgumentError PU.get_bin_edges(Float64[], 4)
    end

    @testset "histogram_counts interior edge is left-closed" begin
        edges = range(0.0, 10.0; length=6)  # [0,2)[2,4)[4,6)[6,8)[8,10]
        @test PU.histogram_counts([2.0], edges) == [0, 1, 0, 0, 0]
    end

    @testset "histogram_counts" begin
        edges = range(0.0, 10.0; length=6)  # bins: [0,2)[2,4)[4,6)[6,8)[8,10]
        counts = PU.histogram_counts([1.0, 3.0, 3.5, 9.0, 10.0], edges)
        @test counts == [1, 2, 0, 0, 2]   # 10.0 (== last edge) lands in last bin
        @test sum(counts) == 5
    end

    @testset "histogram_counts ignores out-of-range" begin
        edges = range(0.0, 10.0; length=6)
        counts = PU.histogram_counts([-1.0, 11.0, 5.0], edges)
        @test sum(counts) == 1
    end

    @testset "bin_count_matrices returns iter×chain×nbins array" begin
        edges = range(0.0, 10.0; length=6)
        comp1 = fill(1.0, 3, 2)   # all in bin 1
        comp2 = fill(9.0, 3, 2)   # all in bin 5
        counts = PU.bin_count_matrices(stack([comp1, comp2]), edges)
        @test size(counts) == (3, 2, 5)
        @test all(==(1), counts[:, :, 1])
        @test all(==(1), counts[:, :, 5])
        @test all(==(0), counts[:, :, 2])
    end
end

@testset "subset_and_split_chain leaf extraction" begin
    rng = StableRNG(1)
    # array-valued variable `v` stored whole: each draw is a length-3 vector
    dicts = [OrderedDict(Parameter(:v) => randn(rng, 3)) for _ in 1:5, _ in 1:2]
    chn = FlexiChain{Symbol}(5, 2, dicts)

    sub, _ = PU.subset_and_split_chain(chn, :v)   # auto-expand single array variable
    ks = collect(keys(sub))
    @test length(ks) == 3
    data = map(k -> PU._get_raw_data(sub, k), ks)
    @test length(data) == 3
    @test all(d -> size(d) == (5, 2), data)    # each leaf is iter×chain
end

end # module
