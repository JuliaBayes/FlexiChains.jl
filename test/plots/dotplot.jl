module DotplotTests

using Test
using CairoMakie: Makie
using SwarmMakie: SwarmMakie
using FlexiChains: FlexiChains as FC, FlexiChain, Parameter
using StableRNGs: StableRNG

const SwarmExt = Base.get_extension(FC, :FlexiChainsSwarmMakieExt)

"Tallest stack `WilkinsonBeeswarm` itself produces over `values` with `nbins` bins."
function reference_tallest_stack(values, nbins)
    positions = Makie.Point2f.(0.0, values)
    buffer = similar(positions)
    binwidth = (maximum(values) - minimum(values)) / nbins
    SwarmMakie.wilkinson_kernel!(buffer, positions, binwidth, :right)
    stacks = last.(buffer)
    return maximum(count(==(y), stacks) for y in unique(stacks))
end

@testset "dotplot" begin
    @testset "_tallest_stack mirrors WilkinsonBeeswarm" begin
        rng = StableRNG(11)
        for values in ([0.0, 0.1, 0.2, 1.0, 1.05], collect(0.0:0.5:10.0), randn(rng, 200))
            for nbins in (3, 12, 25)
                @test SwarmExt._tallest_stack(values, nbins) ==
                      reference_tallest_stack(values, nbins)
            end
        end
    end

    @testset "constant parameters are rejected" begin
        chn = FlexiChain{Symbol}(fill(1.0, 10, 2, 1), :z)
        @test_throws "all of its values are 1.0" FC.Makie.dotplot(chn)
    end
end

end # module
