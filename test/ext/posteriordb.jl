module FCPosteriorDBExtTests

using PosteriorDB
using DimensionalData: DimensionalData as DD
using FlexiChains: FlexiChains, FlexiChain, VarName, @vn, summarystats
using Test

@testset verbose = true "FlexiChainsPosteriorDBExt" begin
    @info "Testing ext/posteriordb.jl"

    pdb = PosteriorDB.database()

    @testset "check that all PDB refs load fine" begin
        for n in PosteriorDB.posterior_names(pdb)
            post = PosteriorDB.posterior(pdb, n)
            ref = PosteriorDB.reference_posterior(post)
            # not all posteriors have references
            if !isnothing(ref)
                chn = FlexiChains.from_posteriordb(ref)
                @test chn isa FlexiChain{VarName}
                # Check that splitting the VarNames back up gives the same number of
                # parameters as are stored in PosteriorDB, i.e., that no data was lost or
                # duplicated when recombining arrays.
                @test length(FlexiChains.parameters(FlexiChains._split_varnames(chn)[1])) ==
                      length(keys(PosteriorDB.load(ref)[1]))
            end
        end
    end

    @testset "check that the data are correct" begin
        post = PosteriorDB.posterior(pdb, "eight_schools-eight_schools_centered")
        ref = PosteriorDB.reference_posterior(post)
        raw = PosteriorDB.load(ref)

        chn = FlexiChains.from_posteriordb(ref)
        @test chn isa FlexiChain{VarName}
        @test collect(FlexiChains.parameters(chn)) == [@vn(theta), @vn(mu), @vn(tau)]
        @test size(chn) == (1000, 10)
        @test DD.parent(FlexiChains.iter_indices(chn)) == 10010:10:20000
        @test chn[@vn(theta), iter=1, chain=1] isa Vector{Float64}
        @test length(chn[@vn(theta), iter=1, chain=1]) == 8
        for c in 1:10, i in (1, 1000)
            @test chn[@vn(theta[3]), iter=i, chain=c] == raw[c]["theta[3]"][i]
            @test chn[@vn(mu), iter=i, chain=c] == raw[c]["mu"][i]
        end
        @test summarystats(chn) isa FlexiChains.FlexiSummary
    end

    @testset "name parsing and vector recombination" begin
        ext = Base.get_extension(FlexiChains, :FlexiChainsPosteriorDBExt)
        @test ext._parse_stan_name("mu") == (:mu, nothing)
        @test ext._parse_stan_name("theta[3]") == (:theta, 3)
        @test ext._parse_stan_name("not a stan name") ==
              (Symbol("not a stan name"), nothing)
        @test_throws ErrorException ext._parse_stan_name("Sigma[2,1]")
        m = zeros(1, 1)
        @test ext._vector_length(:x, [1 => m, 2 => m, 3 => m]) == 3
        @test ext._vector_length(:x, [nothing => m]) === nothing
        # incomplete, duplicated, zero-based, or mixed scalar/indexed entries error
        @test_throws ErrorException ext._vector_length(:x, [1 => m, 3 => m])
        @test_throws ErrorException ext._vector_length(:x, [2 => m, 2 => m])
        @test_throws ErrorException ext._vector_length(:x, [0 => m, 1 => m])
        @test_throws ErrorException ext._vector_length(:x, [nothing => m, 1 => m])
    end
end

end # module
