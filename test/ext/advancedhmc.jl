module FlexiChainsAdvancedHMCExtTests

using AdvancedHMC, AbstractMCMC
using DimensionalData: DimArray
using LogDensityProblems
using FlexiChains: FlexiChains, FlexiChain
using Test

@testset "AdvancedHMC extension" begin
    # Set up AD-aware log-density function
    struct LogTargetDensity
        dim::Int
    end
    LogDensityProblems.logdensity(::LogTargetDensity, θ) = -sum(abs2, θ) / 2
    LogDensityProblems.logdensity_and_gradient(::LogTargetDensity, θ) =
        (-sum(abs2, θ) / 2, -θ)
    LogDensityProblems.dimension(p::LogTargetDensity) = p.dim
    function LogDensityProblems.capabilities(::Type{LogTargetDensity})
        return LogDensityProblems.LogDensityOrder{1}()
    end

    nparams = 10
    niters = 20
    chn = AbstractMCMC.sample(
        LogTargetDensity(nparams),
        AdvancedHMC.NUTS(0.8),
        niters;
        n_adapts=10,
        chain_type=FlexiChain{Symbol},
    )
    @test chn isa FlexiChain{Symbol}
    @test size(chn) == (niters, 1)
    @test only(FlexiChains.parameters(chn)) == :params
    @test chn[:params, stack=true] isa DimArray{Float64,3}
    @test size(chn[:params, stack=true]) == (niters, 1, nparams)
end

end # module
