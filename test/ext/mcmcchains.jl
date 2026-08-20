module FlexiChainsMCMCChainsExtTests

using AbstractMCMC: AbstractMCMC
using DimensionalData: DimArray, Dim
using Distributions
using DynamicPPL: DynamicPPL
using FlexiChains:
    FlexiChains, FlexiChain, Parameter, Extra, ParameterOrExtra, _make_prior_chain, @varname
using LinearAlgebra: I
using MCMCChains: MCMCChains
using Random: Xoshiro
using Test

"""
Build an `MCMCChains.Chains` from a DynamicPPL model, mimicking what Turing's
`bundle_samples` does but without depending on Turing.

cf. https://github.com/TuringLang/DynamicPPL.jl/blob/d7e84ce28c004f17e05711ccfd90e6225b2169b8/ext/DynamicPPLMCMCChainsExt.jl#L173-L185
"""
function _make_mcmcchains(rng, model, n_iters, n_chains; discard_initial=0, thinning=1)
    samples = _make_prior_chain(rng, model, n_iters, n_chains; make_chain=false)
    bare_chain = AbstractMCMC.from_samples(MCMCChains.Chains, samples)
    start_time = rand(rng, n_chains)
    stop_time = start_time .+ rand(rng, n_chains)
    info = merge(
        bare_chain.info,
        (
            start_time=start_time,
            stop_time=stop_time,
            samplerstate=_make_sampler_state(n_chains),
        ),
    )
    return MCMCChains.Chains(
        bare_chain.value.data,
        names(bare_chain),
        bare_chain.name_map;
        info=info,
        start=discard_initial + 1,
        thin=thinning,
    )
end

_make_sampler_state(n_chains) = [(; x="state_$i") for i in 1:n_chains]

@testset "FlexiChainsMCMCChainsExt" begin
    @testset "FlexiChain{VarName} -> MCMCChains" begin
        @model function f()
            x ~ Normal()
            y ~ MvNormal(zeros(3), I)
            return z ~ LKJCholesky(3, 2.0)
        end
        flexic = _make_prior_chain(Xoshiro(468), f(), 20, 1)
        new_mcmcc = MCMCChains.Chains(flexic)

        @testset "iteration indices" begin
            @test FlexiChains.iter_indices(flexic) == range(new_mcmcc)
        end

        @testset "sampling time is preserved" begin
            flexic_with_time = VNChain(20, 1, flexic._data; sampling_time=[3.14])
            mc = MCMCChains.Chains(flexic_with_time)
            @test hasproperty(mc.info, :start_time)
            @test hasproperty(mc.info, :stop_time)
            durations = mc.info.stop_time .- mc.info.start_time
            @test durations ≈ FlexiChains.sampling_time(flexic_with_time)
        end

        @testset "sampler state is preserved" begin
            flexic_with_state =
                VNChain(20, 1, flexic._data; last_sampler_state=["some_state"])
            mc = MCMCChains.Chains(flexic_with_state)
            @test hasproperty(mc.info, :samplerstate)
            @test mc.info.samplerstate == FlexiChains.last_sampler_state(flexic_with_state)
        end
    end

    @testset "FlexiChain{Symbol} -> MCMCChains" begin
        # Mostly to test that it works; the VarName test above is responsible for checking
        # all the other fields.
        niters, nchains, nparams = 10, 3, 5
        rand_da() = DimArray(rand(nparams), Dim{:param}(1:nparams))
        dict_of_arrays = Dict{ParameterOrExtra{Symbol},Matrix}(
            Parameter(:params) => [rand_da() for _ in 1:niters, _ in 1:nchains],
            Extra(:lp) => rand(niters, nchains),
        )
        chn = FlexiChain{Symbol}(niters, nchains, dict_of_arrays)
        @test size(chn[:params]) == (niters, nchains, nparams)

        mc = MCMCChains.Chains(chn)
        mc_params = MCMCChains.get_sections(mc, :parameters)
        @test :lp in keys(mc)
        for i in 1:nparams
            @test Symbol("params[$i]") in keys(mc_params)
        end
        # MCMCChains is niters x nparams x nchains
        @test permutedims(mc_params.value.data, (1, 3, 2)) == chn[:params]
        @test mc[:lp] == chn[:lp]
    end

    @testset "MCMCChains -> FlexiChain (from_mcmcchains)" begin
        @model function g()
            m ~ Normal(0, 1.0)
            s ~ InverseGamma(2, 3)
            return 1.5 ~ Normal(m, sqrt(s))
        end

        @testset "single chain (no key_spec)" begin
            chn = _make_mcmcchains(Xoshiro(123), g(), 100, 1)
            fc = FlexiChains.from_mcmcchains(chn)

            @test fc isa FlexiChain{Symbol}
            @test size(fc) == (size(chn, 1), size(chn, 3))

            # Key names & grouping (order matters)
            @test collect(FlexiChains.parameters(fc)) == collect(names(chn, :parameters))
            @test collect(FlexiChains.extras(fc)) ==
                  [Extra(n) for n in names(chn, :internals)]
            # Data
            for name in names(chn)
                k = name in names(chn, :parameters) ? Parameter(name) : Extra(name)
                @test fc[k] == chn[:, name, :].data
            end
            # Iteration indices
            @test collect(FlexiChains.iter_indices(fc)) == collect(range(chn))
            # Sampling time
            expected_time = chn.info.stop_time .- chn.info.start_time
            @test collect(FlexiChains.sampling_time(fc)) ≈ expected_time
            # Sampler state
            @test collect(FlexiChains.last_sampler_state(fc)) == _make_sampler_state(1)
        end

        @testset "multiple chains (no key_spec)" begin
            ni, nc = 100, 3
            chn = _make_mcmcchains(Xoshiro(456), g(), ni, nc)
            fc = FlexiChains.from_mcmcchains(chn)
            @test size(fc) == (ni, nc)
            for name in names(chn, :parameters)
                @test fc[Parameter(name)] == chn[:, name, :].data
            end
            expected_time = chn.info.stop_time .- chn.info.start_time
            @test collect(FlexiChains.sampling_time(fc)) ≈ expected_time
            # Sampler state
            @test collect(FlexiChains.last_sampler_state(fc)) == _make_sampler_state(nc)
        end

        @testset "iteration indices with discard and thinning" begin
            chn =
                _make_mcmcchains(Xoshiro(111), g(), 50, 1; discard_initial=100, thinning=3)
            fc = FlexiChains.from_mcmcchains(chn)
            ii = collect(FlexiChains.iter_indices(fc))
            @test collect(ii) == collect(range(chn)) == 101:3:250
        end

        @testset "with custom key_spec" begin
            chn = _make_mcmcchains(Xoshiro(321), g(), 100, 1)
            nparams = length(names(chn))
            ks = tuple((Parameter(Symbol("p$i")) for i in 1:nparams)...)
            fc = FlexiChains.from_mcmcchains(chn, ks)
            @test fc isa FlexiChain{Symbol}
            @test size(fc) == (size(chn, 1), size(chn, 3))
            @test collect(FlexiChains.parameters(fc)) == [Symbol("p$i") for i in 1:nparams]
        end

        @testset "with upconversion to VarName" begin
            chn = _make_mcmcchains(Xoshiro(321), g(), 100, 1)
            nparams = length(names(chn))
            ks = (
                Parameter(@varname(x)),
                Parameter(@varname(y)) => (nparams - 2,),
                Parameter(@varname(z)),
            )
            fc = FlexiChains.from_mcmcchains(chn, ks)
            @test fc isa VNChain
            @test size(fc) == (size(chn, 1), size(chn, 3))
            @test collect(FlexiChains.parameters(fc)) ==
                  [@varname(x), @varname(y), @varname(z)]
            @test eltype(fc[@varname(x)]) == Float64
            @test eltype(fc[@varname(y)]) == Vector{Float64}
            @test eltype(fc[@varname(z)]) == Float64
            # This used to error prior to v0.6.31 because `fc` would be a
            # `FlexiChain{VarName{sym,Iden} where sym}`.
            @test FlexiChains._split_varnames(fc) isa Any
        end

        @testset "deprecated constructor still works" begin
            chn = _make_mcmcchains(Xoshiro(654), g(), 50, 1)
            fc = @test_deprecated FlexiChain{Symbol}(chn)
            @test fc isa FlexiChain{Symbol}
            @test size(fc) == (size(chn, 1), size(chn, 3))
        end
    end
end

end # module FlexiChainsMCMCChainsExtTests
