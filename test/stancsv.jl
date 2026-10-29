module FlexiChainsStanCSVTests

using FlexiChains: FlexiChains, FlexiChain, Parameter, Extra, VarName, @vn
using DimensionalData: DimensionalData as DD
using Test

# Test fixture. See test/stan/README.md for details
const STAN_BASE = joinpath(@__DIR__, "stan", "eight_schools_centred")
const STAN_CSV_PATHS = ["$(STAN_BASE)_$(i).csv" for i in 1:4]

@testset verbose = true "from_stan_csv" begin
    @info "Testing stancsv.jl"

    @testset "with Vector{String}" begin
        chn = FlexiChains.from_stan_csv(STAN_CSV_PATHS)
        @test chn isa FlexiChain{Symbol}
        @test size(chn) == (10, 4)

        # Check parameters (theta.1, ..., theta.8, mu, tau)
        params = Set(FlexiChains.parameters(chn))
        @test length(params) == 11
        @test :muplus1 in params # generated quantity
        @test :mu in params
        @test :tau in params
        for i in 1:8
            @test Symbol("theta.$i") in params
        end

        # Check extras (columns ending in __)
        exts = Set(FlexiChains.extras(chn))
        @test Extra(:lp) in exts
        @test Extra(:accept_stat) in exts
        @test Extra(:stepsize) in exts
        @test Extra(:treedepth) in exts
        @test Extra(:n_leapfrog) in exts
        @test Extra(:divergent) in exts
        @test Extra(:energy) in exts

        # Check iteration indices (save_warmup=false, thin=2, num_warmup=10, num_samples=20)
        @test parent(FlexiChains.iter_indices(chn)) == 11:2:30
        @test parent(FlexiChains.chain_indices(chn)) == 1:4

        # Check sampling time is preserved (total elapsed time per chain)
        st = FlexiChains.sampling_time(chn)
        @test length(st) == 4
        @test !any(ismissing, st)
        @test all(t -> t >= 0, st)
    end

    @testset "with base_path" begin
        chn = FlexiChains.from_stan_csv(STAN_BASE, 4)
        @test chn isa FlexiChain{Symbol}
        @test size(chn) == (10, 4)
    end

    @testset "with subset of chains" begin
        chn = FlexiChains.from_stan_csv(STAN_CSV_PATHS[1:2])
        @test size(chn) == (10, 2)
    end

    @testset "with key_spec" begin
        ks = (
            Extra(:lp),
            Extra(:accept_stat),
            Extra(:stepsize),
            Extra(:treedepth),
            Extra(:n_leapfrog),
            Extra(:divergent),
            Extra(:energy),
            Parameter(@vn(theta)) => (8,),
            Parameter(@vn(mu)),
            Parameter(@vn(tau)),
            Parameter(@vn(muplus1)),
        )
        chn_sym = FlexiChains.from_stan_csv(STAN_CSV_PATHS)
        chn = FlexiChains.from_stan_csv(STAN_CSV_PATHS, ks)
        @test chn isa FlexiChain{VarName}
        @test size(chn) == (10, 4)
        @test collect(FlexiChains.parameters(chn)) ==
              [@vn(theta), @vn(mu), @vn(tau), @vn(muplus1)]
        for i in 1:8
            @test chn[@vn(theta[i])] == chn_sym[Symbol("theta.$i")]
        end
        @test chn[@vn(mu)] == chn_sym[:mu]
        @test chn[Extra(:lp)] == chn_sym[Extra(:lp)]
        # Metadata is preserved
        @test FlexiChains.iter_indices(chn) == FlexiChains.iter_indices(chn_sym)
        @test isequal(FlexiChains.sampling_time(chn), FlexiChains.sampling_time(chn_sym))

        # Also works with base_path
        @test isequal(FlexiChains.from_stan_csv(STAN_BASE, 4, ks), chn)

        # Wrong number of columns
        @test_throws ArgumentError FlexiChains.from_stan_csv(STAN_CSV_PATHS, ks[1:(end-1)])
    end

    @testset "error handling" begin
        @test_throws ArgumentError FlexiChains.from_stan_csv(String[])
        @test_throws ArgumentError FlexiChains.from_stan_csv("nonexistent", 1)
        @test_throws ArgumentError FlexiChains.from_stan_csv(["nonexistent.csv"])
        @test_throws ArgumentError FlexiChains.from_stan_csv("nonexistent", 0)
    end
end

end # module
