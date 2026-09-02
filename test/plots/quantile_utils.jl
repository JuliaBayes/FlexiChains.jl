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

@testset "dot plot utilities" begin
    @testset "quantile_dots sits at equal-probability midpoints" begin
        values = collect(1.0:100.0)
        dots = PU.quantile_dots(values, 4)
        @test length(dots) == 4
        @test dots ≈ Statistics.quantile(values, [0.125, 0.375, 0.625, 0.875])
        @test issorted(dots)
    end

    @testset "quantile_dots pools a matrix and rejects non-positive counts" begin
        data = hcat(collect(1.0:10.0), collect(11.0:20.0))
        @test PU.quantile_dots(data, 3) ≈ PU.quantile_dots(vec(data), 3)
        @test_throws ArgumentError PU.quantile_dots(data, 0)
    end

    @testset "quantile_dots keeps integer samples on the support" begin
        # The continuous method interpolates between order statistics, which for integer
        # samples yields values the parameter cannot take.
        @test PU.quantile_dots([1.0, 2.0], 2) == [1.25, 1.75]
        @test PU.quantile_dots([1, 2], 2) == [1, 2]

        values = [1, 1, 4, 9]
        dots = PU.quantile_dots(values, 4)
        @test eltype(dots) <: Integer
        @test all(in(values), dots)
        @test issorted(dots)
    end

    @testset "quantile_dots on integers is the inverse empirical CDF" begin
        # Each dot is the smallest observation whose empirical cumulative probability
        # reaches that dot's probability.
        values = [3, 1, 1, 1]
        @test PU.quantile_dots(values, 4) == [1, 1, 1, 3]
        @test PU.quantile_dots(reshape(values, 2, 2), 4) == PU.quantile_dots(values, 4)
        @test_throws ArgumentError PU.quantile_dots(values, 0)
    end

    @testset "default_binwidth" begin
        values = collect(0.0:1.0:9.0)
        @test PU.default_binwidth(values) ≈ 9.0 / sqrt(2 * pi * 10)
        @test PU.default_binwidth(fill(3.0, 5)) == 1.0   # single stack
    end

    @testset "wilkinson_stacks groups and centres each stack" begin
        values = [0.0, 0.1, 0.2, 1.0, 1.05]
        locations, counts = PU.wilkinson_stacks(values, 0.5)
        @test counts == [3, 2]
        @test locations ≈ [0.1, 1.025]
        @test sum(counts) == length(values)
    end

    @testset "wilkinson_stacks stack width is left-closed" begin
        # 1.0 is exactly `binwidth` above the stack's first value, so it opens a new stack.
        locations, counts = PU.wilkinson_stacks([0.0, 0.999, 1.0], 1.0)
        @test counts == [2, 1]
        @test locations ≈ [0.4995, 1.0]
    end

    @testset "wilkinson_stacks rejects unsorted values and non-positive widths" begin
        @test_throws ArgumentError PU.wilkinson_stacks([1.0, 0.0], 1.0)
        @test_throws ArgumentError PU.wilkinson_stacks([0.0, 1.0], 0.0)
    end

    @testset "dot_coordinates places one dot per value" begin
        values = [0.0, 0.1, 0.2, 1.0, 1.05]
        locations, levels = PU.dot_coordinates(values, 0.5)
        @test length(locations) == length(values)
        @test levels == [1, 2, 3, 1, 2]
        @test locations ≈ [0.1, 0.1, 0.1, 1.025, 1.025]
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
