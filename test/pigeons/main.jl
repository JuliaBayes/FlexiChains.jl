module FlexiChainsPigeonsExtTests

using FlexiChains: FlexiChains, SymChain, Extra
using BridgeStan
using Pigeons
using DynamicPPL
using Distributions
using Random
using Test

@testset "PigeonsExt" begin
    @testset "Callable struct" begin
        struct MyLogPotential
            n_trials::Int
            n_successes::Int
        end
        function (log_potential::MyLogPotential)(x)
            p1, p2 = x
            if !(0 < p1 < 1) || !(0 < p2 < 1)
                return -Inf
            end
            return logpdf(
                Binomial(log_potential.n_trials, p1 * p2),
                log_potential.n_successes,
            )
        end
        Pigeons.initialization(::MyLogPotential, ::Random.AbstractRNG, ::Int) = [0.5, 0.5]
        pt = pigeons(;
            target=MyLogPotential(100, 50),
            reference=MyLogPotential(0, 0),
            record=[traces],
        )

        chn = FlexiChains.from_pigeons(pt)
        @test chn isa SymChain
        # Should be a single parameter which is a length-2 vector
        @test only(FlexiChains.parameters(chn)) == :param
        @test size(first(chn[:param])) == (2,)
        # log density should be recorded as an extra
        @test only(FlexiChains.extras(chn)) == Extra(:log_density)
        @test eltype(chn[:log_density]) == Float64
    end

    @testset "With Turing model" begin
        @model function f(n_trials, n_successes)
            p1 ~ filldist(Uniform(0, 1), 1, 2)
            n_successes ~ Binomial(n_trials, prod(p1))
            return n_successes
        end
        my_turing_target = TuringLogPotential(f(100, 50))
        pt = pigeons(; target=my_turing_target, record=[traces])

        chn = FlexiChains.from_pigeons(pt)
        @test chn isa FlexiChains.FlexiChain{DynamicPPL.VarName}
        @test only(FlexiChains.parameters(chn)) == @varname(p1)
        sample = first(chn[@varname(p1)])
        @test size(sample) == (1, 2)
        for lp in (:logprior, :loglikelihood, :logjoint)
            @test Extra(lp) in keys(chn)
            @test eltype(chn[lp]) == Float64
        end
    end

    @testset "Discrete parameters" begin
        @model function g()
            x ~ Normal()
            y ~ Poisson(1.0)
            1.0 ~ Normal(x + y)
        end
        pt = pigeons(; target=TuringLogPotential(g()), record=[traces])

        # Check that discrete variables are correctly handled (this essentially tests the
        # `_faithful_sample_array` function). If we used `Pigeons.sample_array` then `y`
        # would be converted to `Float64`.
        chn = FlexiChains.from_pigeons(pt)
        @test chn isa FlexiChains.FlexiChain{DynamicPPL.VarName}
        @test eltype(chn[@varname(x)]) == Float64
        @test eltype(chn[@varname(y)]) == Int
        for lp in (:logprior, :loglikelihood, :logjoint)
            @test Extra(lp) in keys(chn)
            @test eltype(chn[lp]) == Float64
        end
    end

    @testset "Stan model" begin
        struct StanUnidentifiableExample end

        function stan_unid(n_trials, n_successes)
            stan_file = joinpath(@__DIR__, "unid.stan")
            stan_data = Pigeons.json(; n_trials, n_successes)
            return StanLogPotential(stan_file, stan_data, StanUnidentifiableExample())
        end

        pt = pigeons(target=stan_unid(100, 50), reference=stan_unid(0, 0), record=[traces])
        chn = FlexiChains.from_pigeons(pt)

        @test chn isa SymChain
        @test FlexiChains.parameters(chn) == [:p1, :p2]
        @test eltype(chn[:p1]) == Float64
        @test eltype(chn[:p2]) == Float64
        @test only(FlexiChains.extras(chn)) == Extra(:log_density)
        @test eltype(chn[:log_density]) == Float64
    end
end

end # module
