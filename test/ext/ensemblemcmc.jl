module FlexiChainsEnsembleMCMCExtTests

using EnsembleMCMC
using FlexiChains: FlexiChains, Extra, @varname
using DimensionalData: At
using Random123: Philox4x
using Test

@testset "EnsembleMCMC conversion" begin
    initial = Float32[-1 0 1 0; 0 -1 0 1]
    runs = map((42, 43)) do seed
        state = initialize(Philox4x((seed, 1)), x -> -sum(abs2, x) / 2, initial;
                           walker_ids=[11, 23, 37, 41])
        sample!(state, 3)
    end
    chain = FlexiChains.from_ensemblemcmc(runs...; iter_indices=101:103)
    @test size(chain) == (3, 2)
    @test collect(FlexiChains.iter_indices(chain)) == 101:103
    @test chain[:positions, stack=true][:, 2, :, :] == permutedims(runs[2].positions, (3, 1, 2))
    @test chain[Extra(:move_index), chain=1] == runs[1].move_indices
    @test chain[@varname(positions[2, 3]), chain=2] == runs[2].positions[2, 3, :]

    names = [:alpha, :beta]
    named = FlexiChains.from_ensemblemcmc(runs[1]; param_names=names)
    names[1] = :changed
    @test collect(FlexiChains.parameters(named)) == [@varname(alpha), @varname(beta)]
    @test named[@varname(beta[3]), chain=1] == runs[1].positions[2, 3, :]
    @test named[:beta, stack=true] == permutedims(runs[1].positions[2:2, :, :], (3, 1, 2))
    named[:alpha, stack=false][1, 1][walker=At(23)] = 77
    @test runs[1].positions[1, 2, 1] == 77

    # Array-valued samples share storage; dimension labels do not.
    runs[1].walker_ids[2] = 99
    @test chain[:positions, stack=false][1, 1][walker=At(23)][1] == 77
    for (key, source) in ((:positions, runs[1].positions),
                         (Extra(:log_density), runs[1].logdensities),
                         (Extra(:accepted), runs[1].accepted))
        shared = chain[key, stack=false][1, 1]
        source[1] = iszero(source[1]) ? one(eltype(source)) : zero(eltype(source))
        @test shared[1] == source[1]
        shared[1] = iszero(shared[1]) ? one(eltype(shared)) : zero(eltype(shared))
        @test source[1] == shared[1]
    end
    @test_throws DimensionMismatch FlexiChains.from_ensemblemcmc(runs[2]; param_names=[:alpha])
    @test_throws ArgumentError FlexiChains.from_ensemblemcmc(runs[2]; param_names=[:alpha, :alpha])
end

end
