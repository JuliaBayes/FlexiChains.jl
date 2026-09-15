module FCSummariesTests

using DimensionalData: DimensionalData as DD
using FlexiChains:
    FlexiChains,
    FlexiChain,
    FlexiSummary,
    Parameter,
    ParameterOrExtra,
    Extra,
    VarName,
    @varname,
    summarystats
using Logging: Warn
using MCMCDiagnosticTools: ess, rhat, mcse
using OrderedCollections: OrderedDict
using Random: Random, randn
using Statistics
using StatsBase: geomean, harmmean, mad, iqr
using Test

const ENABLED_SUMMARY_FUNCS = [mean, median, minimum, maximum, std, var, sum, prod]
const WORKS_ON_STRING = [minimum, maximum, prod]

@testset verbose = true "summaries.jl" begin
    @info "Testing summaries.jl"

    N_iters, N_chains = 10, 3
    as = rand(N_iters, N_chains)
    bs = rand(1:100, N_iters, N_chains)
    cs = rand(Bool, N_iters, N_chains)
    ds = fill("hello", N_iters, N_chains)
    chain = FlexiChain{Symbol}(
        N_iters,
        N_chains,
        Dict(
            Parameter(:a) => as,
            Parameter(:b) => bs,
            Extra("c") => cs,
            Extra("actuallyString") => ds,
        );
        iter_indices=FlexiChains._make_lookup(4:4:(4*N_iters)),
        chain_indices=FlexiChains._make_lookup(1:N_chains),
    )

    @testset "collapse" begin
        @testset for func in ENABLED_SUMMARY_FUNCS
            @testset "dims=:iter" begin
                fs = FlexiChains.collapse(chain, [func]; dims=:iter)
                @test fs[:a] isa DD.DimMatrix
                @test parent(parent(DD.dims(fs[:a], :chain))) ==
                      FlexiChains.chain_indices(chain) ==
                      FlexiChains.chain_indices(fs)
                @test isapprox(fs[:a], vec(func(as; dims=1)); nans=true)

                if func in WORKS_ON_STRING
                    # the 1 dim at the end is the stat dim
                    expected = reshape(func(ds; dims=1), N_chains, 1)
                    @test fs[Extra("actuallyString")] == expected
                else
                    # the key "actuallyString" should be skipped
                    @test_logs (:warn, r"\"actuallyString\"") FlexiChains.collapse(
                        chain,
                        [func];
                        dims=:iter,
                        warn=true,
                    )
                end
            end

            @testset "dims=:chain" begin
                fs = FlexiChains.collapse(chain, [func]; dims=:chain)
                @test fs[:a] isa DD.DimMatrix
                @test parent(parent(DD.dims(fs[:a], :iter))) ==
                      FlexiChains.iter_indices(chain) ==
                      FlexiChains.iter_indices(fs)
                @test parent(parent(DD.dims(fs[:a], :stat))) == [Symbol(func)]
                @test isapprox(fs[:a], vec(func(as; dims=2)); nans=true)

                if func in WORKS_ON_STRING
                    # the 1 dim at the end is the stat dim
                    expected = reshape(func(ds; dims=2), N_iters, 1)
                    @test fs[Extra("actuallyString")] == expected
                else
                    # the key "actuallyString" should be skipped
                    @test_logs (:warn, r"\"actuallyString\"") FlexiChains.collapse(
                        chain,
                        [func];
                        dims=:chain,
                        warn=true,
                    )
                end
            end

            @testset "dims=:both" begin
                fs = FlexiChains.collapse(chain, [func]; dims=:both)
                @test fs[:a] isa DD.DimVector
                @test parent(parent(DD.dims(fs[:a], :stat))) == [Symbol(func)]
                @test isapprox(only(fs[:a]), func(as); nans=true)

                if func in WORKS_ON_STRING
                    # the 1 dim at the end is the stat dim
                    expected = func(ds)
                    @test only(fs[Extra("actuallyString")]) == expected
                else
                    # the key "actuallyString" should be skipped
                    @test_logs (:warn, r"\"actuallyString\"") FlexiChains.collapse(
                        chain,
                        [func];
                        dims=:both,
                        warn=true,
                    )
                end
            end
        end
    end

    @testset "other summary functions" begin
        @test geomean(chain) isa FlexiSummary
        @test geomean(chain; dims=:iter) isa FlexiSummary
        @test geomean(chain; dims=:chain) isa FlexiSummary
        @test harmmean(chain) isa FlexiSummary
        @test harmmean(chain; dims=:iter) isa FlexiSummary
        @test harmmean(chain; dims=:chain) isa FlexiSummary
        @test mad(chain) isa FlexiSummary
        @test mad(chain; dims=:iter) isa FlexiSummary
        @test mad(chain; dims=:chain) isa FlexiSummary
        @test iqr(chain) isa FlexiSummary
        @test iqr(chain; dims=:iter) isa FlexiSummary
        @test iqr(chain; dims=:chain) isa FlexiSummary
        @test ess(chain) isa FlexiSummary
        @test ess(chain; dims=:iter) isa FlexiSummary
        @test ess(chain; dims=:chain) isa FlexiSummary
        @test ess(chain; kind=:tail) isa FlexiSummary
        @test ess(chain; dims=:iter, kind=:tail) isa FlexiSummary
        @test ess(chain; dims=:chain, kind=:tail) isa FlexiSummary
        @test rhat(chain) isa FlexiSummary
        @test rhat(chain; dims=:iter) isa FlexiSummary
        @test rhat(chain; dims=:chain) isa FlexiSummary
        @test mcse(chain) isa FlexiSummary
        @test mcse(chain; dims=:iter) isa FlexiSummary
        @test mcse(chain; dims=:chain) isa FlexiSummary
        @test quantile(chain, 0.5) isa FlexiSummary
        @test quantile(chain, 0.5; dims=:iter) isa FlexiSummary
        @test quantile(chain, 0.5; dims=:chain) isa FlexiSummary
        @test quantile(chain, [0.5, 0.9]) isa FlexiSummary
        @test quantile(chain, [0.5, 0.9]; dims=:iter) isa FlexiSummary
        @test quantile(chain, [0.5, 0.9]; dims=:chain) isa FlexiSummary
    end

    @testset "diagnostics respect the chain dimension" begin
        # NOTE: use at least 3 chains. With 2 chains the flattened vector happens to split
        # back into the original two chains, so the bug is invisible.
        rng = Random.MersenneTwister(468)
        niter, nchain = 500, 4
        # Four individually well-mixed chains stuck at two different modes; arranged so
        # that [c1; c2] and [c3; c4] have the same distribution
        raw = randn(rng, niter, nchain) .+ [0.0, 8.0, 0.0, 8.0]'
        as_3d = reshape(raw, niter, nchain, 1)
        chn = FlexiChain{Symbol}(niter, nchain, Dict(Parameter(:x) => raw))

        @test rhat(chn)[:x] ≈ rhat(as_3d)[1]
        @test ess(chn)[:x] ≈ ess(as_3d)[1]
        @test ess(chn; kind=:tail)[:x] ≈ ess(as_3d; kind=:tail)[1]
        @test mcse(chn)[:x] ≈ mcse(as_3d)[1]
        # sanity: this  really is non-converged, i.e., the test can fail
        @test rhat(chn)[:x] > 1.5

        sm = summarystats(chn)
        @test sm[:x, stat=DD.At(:rhat)] ≈ rhat(as_3d)[1]
        @test sm[:x, stat=DD.At(:ess_bulk)] ≈ ess(as_3d; kind=:bulk)[1]
        @test sm[:x, stat=DD.At(:ess_tail)] ≈ ess(as_3d; kind=:tail)[1]
        @test sm[:x, stat=DD.At(:mcse)] ≈ mcse(as_3d)[1]

        # R-hat is a symmetric function of the chains, so should be permutation invariant
        for perm in ([1, 3, 2, 4], [4, 3, 2, 1], [2, 4, 1, 3])
            permuted = FlexiChain{Symbol}(
                niter, nchain, Dict(Parameter(:x) => raw[:, perm])
            )
            @test rhat(permuted)[:x] ≈ rhat(chn)[:x]
        end

        # Statistics that don't care about chain structure are unaffected.
        @test mean(chn)[:x] ≈ mean(raw)
        @test std(chn)[:x] ≈ std(vec(raw))
        @test quantile(chn, 0.5)[:x] ≈ quantile(vec(raw), 0.5)
    end

    @testset "summarystats" begin
        @test summarystats(chain) isa FlexiSummary
        # Not sure what else we want to test here; all the individual functions are
        # well-tested...
    end

    @testset "warn=false" begin
        # Check that no warnings are issued when warn=false
        @test_logs min_level = Warn mean(chain; warn=false)
        @test_logs min_level = Warn FlexiChains.collapse(
            chain,
            [mean];
            dims=:both,
            warn=false,
        )
    end

    @testset "drop_stat_dim=true" begin
        @testset "iter" begin
            fs = FlexiChains.collapse(chain, [mean]; dims=:iter, drop_stat_dim=true)
            @test fs[:a] isa DD.DimVector
            @test parent(parent(DD.dims(fs[:a], :chain))) ==
                  FlexiChains.chain_indices(chain) ==
                  FlexiChains.chain_indices(fs)
            @test isapprox(fs[:a], vec(mean(as; dims=1)))
        end

        @testset "chain" begin
            fs = FlexiChains.collapse(chain, [mean]; dims=:chain, drop_stat_dim=true)
            @test fs[:a] isa DD.DimVector
            @test parent(parent(DD.dims(fs[:a], :iter))) ==
                  FlexiChains.iter_indices(chain) ==
                  FlexiChains.iter_indices(fs)
            @test isapprox(fs[:a], vec(mean(as; dims=2)))
        end

        @testset "both" begin
            fs = FlexiChains.collapse(chain, [mean]; dims=:both, drop_stat_dim=true)
            @test fs[:a] isa Float64
            @test isapprox(fs[:a], mean(as))
        end
    end

    @testset "check that keyword arguments are forwarded" begin
        # We'll use `std` without Bessel correction here.
        N_iters, N_chains = 10, 3
        as = rand(N_iters, N_chains)
        chain = FlexiChain{Symbol}(N_iters, N_chains, Dict(Parameter(:a) => as))

        @testset "iter" begin
            expected = std(as; dims=1, corrected=false)
            result = std(chain; dims=:iter, corrected=false)[:a]
            @test isapprox(result, vec(expected))
        end
        @testset "chain" begin
            expected = std(as; dims=2, corrected=false)
            result = std(chain; dims=:chain, corrected=false)[:a]
            @test isapprox(result, vec(expected))
        end
        @testset "iter + chain" begin
            expected = std(chain[:a]; corrected=false)
            result = std(chain; corrected=false)[:a]
            @test isapprox(only(result), expected)
        end
    end

    @testset "show doesn't error" begin
        ds = [
            Dict(Parameter(:a) => 1, Extra("hello") => 3.0),
            Dict(Parameter(:a) => 1),
            Dict(Extra("hello") => 3.0),
            Dict(),
        ]
        for d in ds
            chain = FlexiChain{Symbol}(10, 3, fill(d, 10, 3))
            display(mean(chain; dims=:iter))
            display(median(chain; dims=:chain))
            display(std(chain; dims=:both))
            display(summarystats(chain))
        end
    end

    @testset "summarystats when some functions fail" begin
        x = randn(2)
        d = Dict(Parameter(:x) => fill(x, 5, 2))
        chain = FlexiChain{Symbol}(5, 2, d)
        # Attempting to perform the summary here will result in some functions failing
        # because they can't handle vector-valued data. For example, ESS will fail.
        # We just want to check that summarystats still works and returns the results for the
        # functions that _do_ work.
        sm = summarystats(chain; split_varnames=false)
        @test haskey(sm, Parameter(:x))
        @test isapprox(sm[:x, stat=DD.At(:mean)], x)
        @test ismissing(sm[:x, stat=DD.At(:ess_bulk)])
    end

    @testset "getindex on summaries" begin
        N_iters, N_chains = 10, 3
        xs = Matrix{Vector{Float64}}(undef, N_iters, N_chains)
        ys = Matrix{Float64}(undef, N_iters, N_chains)
        for i in 1:N_iters, j in 1:N_chains
            xs[i, j] = rand(10)
            ys[i, j] = randn()
        end
        chain = FlexiChain{VarName}(
            N_iters,
            N_chains,
            Dict(Parameter(@varname(x)) => xs, Parameter(@varname(y)) => ys),
        )

        @testset "DimArray name is set to key" begin
            fs = mean(chain; dims=:iter, split_varnames=false)
            @test DD.name(fs[Parameter(@varname(y))]) == string(Parameter(@varname(y)))
            @test DD.name(fs[@varname(y)]) == string(Parameter(@varname(y)))
            @test DD.name(fs[:y]) == string(Parameter(@varname(y)))
        end

        @testset "dims=:iter" begin
            fs = mean(chain; dims=:iter, split_varnames=false)

            @testset "VarName" begin
                @test fs[@varname(x)] isa DD.DimVector
                @test parent(parent(DD.dims(fs[@varname(x)], :chain))) ==
                      FlexiChains.chain_indices(chain) ==
                      FlexiChains.chain_indices(fs)
                @test isapprox(fs[@varname(x)], dropdims(mean(xs; dims=1); dims=1))
            end

            @testset "Symbol" begin
                @test fs[:x] isa DD.DimVector
                @test parent(parent(DD.dims(fs[:x], :chain))) ==
                      FlexiChains.chain_indices(chain) ==
                      FlexiChains.chain_indices(fs)
                @test isapprox(fs[:x], dropdims(mean(xs; dims=1); dims=1))
            end

            @testset "sub-VarName" begin
                @test fs[@varname(x[1])] isa DD.DimVector
                @test parent(parent(DD.dims(fs[@varname(x[1])], :chain))) ==
                      FlexiChains.chain_indices(chain) ==
                      FlexiChains.chain_indices(fs)
                @test isapprox(
                    fs[@varname(x[1])],
                    dropdims(mean(getindex.(xs, 1); dims=1); dims=1),
                )
            end

            @testset "vector of keys" begin
                fs2 = fs[[Parameter(@varname(x)), Parameter(@varname(y))]]
                @test fs2 isa FlexiSummary
                @test FlexiChains.iter_indices(fs2) == FlexiChains.iter_indices(fs)
                @test FlexiChains.chain_indices(fs2) == FlexiChains.chain_indices(fs)
                @test FlexiChains.stat_indices(fs2) == FlexiChains.stat_indices(fs)
                @test fs2[@varname(x[1])] == fs[@varname(x[1])]
                @test fs2[@varname(x[2])] == fs[@varname(x[2])]
                @test fs2[@varname(x)] == fs[@varname(x)]
                @test fs2[@varname(y)] == fs[@varname(y)]
            end

            @testset "nonexistent VarName" begin
                @test_throws KeyError fs[@varname(z)]
                @test_throws Exception fs[@varname(x.a)]
            end
        end

        @testset "dims=:chain" begin
            fs = mean(chain; dims=:chain, split_varnames=false)

            @testset "VarName" begin
                @test fs[@varname(x)] isa DD.DimVector
                @test parent(parent(DD.dims(fs[@varname(x)], :iter))) ==
                      FlexiChains.iter_indices(chain) ==
                      FlexiChains.iter_indices(fs)
                @test isapprox(fs[@varname(x)], dropdims(mean(xs; dims=2); dims=2))
            end

            @testset "Symbol" begin
                @test fs[:x] isa DD.DimVector
                @test parent(parent(DD.dims(fs[:x], :iter))) ==
                      FlexiChains.iter_indices(chain) ==
                      FlexiChains.iter_indices(fs)
                @test isapprox(fs[:x], dropdims(mean(xs; dims=2); dims=2))
            end

            @testset "sub-VarName" begin
                @test fs[@varname(x[1])] isa DD.DimVector
                @test parent(parent(DD.dims(fs[@varname(x[1])], :iter))) ==
                      FlexiChains.iter_indices(chain) ==
                      FlexiChains.iter_indices(fs)
                @test isapprox(
                    fs[@varname(x[1])],
                    dropdims(mean(getindex.(xs, 1); dims=2); dims=2),
                )
            end

            @testset "vector of keys" begin
                fs2 = fs[[Parameter(@varname(x)), Parameter(@varname(y))]]
                @test fs2 isa FlexiSummary
                @test FlexiChains.iter_indices(fs2) == FlexiChains.iter_indices(fs)
                @test FlexiChains.chain_indices(fs2) == FlexiChains.chain_indices(fs)
                @test FlexiChains.stat_indices(fs2) == FlexiChains.stat_indices(fs)
                @test fs2[@varname(x[1])] == fs[@varname(x[1])]
                @test fs2[@varname(x[2])] == fs[@varname(x[2])]
                @test fs2[@varname(x)] == fs[@varname(x)]
                @test fs2[@varname(y)] == fs[@varname(y)]
            end

            @testset "nonexistent VarName" begin
                @test_throws KeyError fs[@varname(z)]
                @test_throws Exception fs[@varname(x.a)]
            end
        end

        @testset "dims=:both" begin
            fs = mean(chain; split_varnames=false)

            @testset "VarName" begin
                @test fs[@varname(x)] isa Vector{Float64}
                @test isapprox(fs[@varname(x)], mean(xs))
            end

            @testset "Symbol" begin
                @test fs[:x] isa Vector{Float64}
                @test isapprox(fs[:x], mean(xs))
            end

            @testset "sub-VarName" begin
                @test fs[@varname(x[1])] isa Float64
                @test isapprox(fs[@varname(x[1])], mean(getindex.(xs, 1)))
            end

            @testset "vector of keys" begin
                fs2 = fs[[Parameter(@varname(x)), Parameter(@varname(y))]]
                @test fs2 isa FlexiSummary
                @test FlexiChains.iter_indices(fs2) == FlexiChains.iter_indices(fs)
                @test FlexiChains.chain_indices(fs2) == FlexiChains.chain_indices(fs)
                @test FlexiChains.stat_indices(fs2) == FlexiChains.stat_indices(fs)
                @test fs2[@varname(x[1])] == fs[@varname(x[1])]
                @test fs2[@varname(x[2])] == fs[@varname(x[2])]
                @test fs2[@varname(x)] == fs[@varname(x)]
                @test fs2[@varname(y)] == fs[@varname(y)]
            end

            @testset "nonexistent VarName" begin
                @test_throws KeyError fs[@varname(z)]
                @test_throws Exception fs[@varname(x.a)]
            end
        end

        @testset "with split_varnames" begin
            fs = mean(chain; dims=:iter)
            for i in 1:10
                @test haskey(fs, @varname(x[i]))
                @test isapprox(
                    fs[@varname(x[i])],
                    dropdims(mean(getindex.(xs, i); dims=1); dims=1),
                )
            end
            @test haskey(fs, @varname(y))
            @test !haskey(fs, @varname(x))
            @test fs[@varname(x[1])] isa DD.DimVector
        end

        @testset "stack keyword" begin
            arr = [1.0, 2.0, 3.0]
            dimarr = DD.DimArray([10.0, 20.0, 30.0], DD.X([:a, :b, :c]))
            Niters, Nchains = 10, 3
            d = Dict(
                Parameter(:arr) => fill(arr, Niters, Nchains),
                Parameter(:dimarr) => fill(dimarr, Niters, Nchains),
                Parameter(:scalar) => rand(Niters, Nchains),
            )
            chain = FlexiChain{Symbol}(Niters, Nchains, d)

            @testset "dims=:both (all collapsed)" begin
                m = mean(chain; split_varnames=false)

                @testset "scalar" begin
                    @test m[:scalar] isa Float64
                    @test m[:scalar, stack=true] isa Float64
                    @test m[:scalar, stack=false] isa Float64
                end

                @testset "Array parameter" begin
                    @test m[:arr, stack=false] == arr
                    @test m[:arr, stack=true] == arr
                    @test m[:arr] == arr
                end

                @testset "DimArray parameter" begin
                    @test m[:dimarr, stack=false] == dimarr
                    @test m[:dimarr, stack=true] == dimarr
                    # no warning because there is no stacking going on
                    @test m[:dimarr] == dimarr
                end
            end

            @testset "dims=:iter" begin
                m = mean(chain; dims=:iter, split_varnames=false)

                @testset "scalar" begin
                    s_default = m[:scalar]
                    s_true = m[:scalar, stack=true]
                    s_false = m[:scalar, stack=false]
                    @test s_default isa DD.DimVector{Float64}
                    @test s_true isa DD.DimVector{Float64}
                    @test s_false isa DD.DimVector{Float64}
                    @test s_default == s_true == s_false
                end

                @testset "Array parameter" begin
                    result = m[:arr, stack=false]
                    @test result isa DD.DimVector{Vector{Float64}}
                    @test size(result) == (Nchains,)
                    @test result[1] == arr

                    result = m[:arr, stack=true]
                    @test result isa DD.DimArray{Float64,2}
                    @test size(result) == (Nchains, 3)
                    @test DD.dims(result) isa Tuple{DD.Dim{:chain},DD.AnonDim}
                    @test result[1, :] == arr

                    result = m[:arr]
                    @test result isa DD.DimVector{Vector{Float64}}
                end

                @testset "DimArray parameter" begin
                    result = m[:dimarr, stack=false]
                    @test result isa DD.DimVector{<:DD.DimArray}
                    @test size(result) == (Nchains,)
                    @test result[1] == dimarr

                    result = m[:dimarr, stack=true]
                    @test result isa DD.DimArray{Float64,2}
                    @test size(result) == (Nchains, 3)
                    @test DD.dims(result) isa Tuple{DD.Dim{:chain},DD.X}
                    @test result[1, :] == parent(dimarr)

                    result =
                        @test_logs((:warn, FlexiChains._STACK_DEPWARN_MSG), m[:dimarr],)
                    @test result isa DD.DimArray{Float64,2}
                    @test size(result) == (Nchains, 3)
                end
            end

            @testset "with multiple statistics" begin
                ms = FlexiChains.collapse(
                    chain,
                    [mean, std];
                    dims=:iter,
                    split_varnames=false,
                )

                @testset "Array parameter" begin
                    result = ms[:arr, stack=true, stat=DD.At(:mean)]
                    @test result isa DD.DimArray{Float64,2}
                    @test size(result) == (Nchains, 3)
                    @test DD.dims(result) isa Tuple{DD.Dim{:chain},DD.AnonDim}
                    @test result[1, :] == arr

                    result = ms[:arr, stack=true]
                    @test result isa DD.DimArray{Float64,3}
                    @test size(result) == (Nchains, 2, 3)
                    @test DD.dims(result) isa Tuple{DD.Dim{:chain},DD.Dim{:stat},DD.AnonDim}

                    result = ms[:arr, stack=false, stat=DD.At(:mean)]
                    @test result isa DD.DimVector{Vector{Float64}}
                end

                @testset "DimArray parameter" begin
                    result = ms[:dimarr, stack=true, stat=DD.At(:mean)]
                    @test result isa DD.DimArray{Float64,2}
                    @test size(result) == (Nchains, 3)
                    @test DD.dims(result) isa Tuple{DD.Dim{:chain},DD.X}

                    result = ms[:dimarr, stack=true]
                    @test result isa DD.DimArray{Float64,3}
                    @test size(result) == (Nchains, 2, 3)
                    @test DD.dims(result) isa Tuple{DD.Dim{:chain},DD.Dim{:stat},DD.X}

                    result = @test_logs(
                        (:warn, FlexiChains._STACK_DEPWARN_MSG),
                        ms[:dimarr, stat=DD.At(:mean)],
                    )
                    @test result isa DD.DimArray{Float64,2}
                    @test size(result) == (Nchains, 3)
                end
            end
        end
    end

    @testset "kwarg handling for getindex" begin
        N_iters, N_chains = 10, 3
        xs = Matrix{Vector{Float64}}(undef, N_iters, N_chains)
        for i in 1:N_iters, j in 1:N_chains
            xs[i, j] = rand(10)
        end
        chain = FlexiChain{VarName}(N_iters, N_chains, Dict(Parameter(@varname(x)) => xs))

        @testset "iter and stat collapsed" begin
            # Test that attempting to index in with either `iter=...` or `stat=...` errors
            fs = mean(chain; dims=:iter, split_varnames=false)
            @test_throws ArgumentError FlexiChains._check_summary_kwargs(
                fs,
                Colon(),
                Colon(),
                Colon(),
            )
            @test_throws ArgumentError fs[Parameter(@varname(x)), iter=:]
            @test_throws ArgumentError FlexiChains._check_summary_kwargs(
                fs,
                FlexiChains._UNSPECIFIED_KWARG,
                Colon(),
                Colon(),
            )
            @test_throws ArgumentError fs[Parameter(@varname(x)), stat=:]
            # And that omitting both works
            @test FlexiChains._check_summary_kwargs(
                fs,
                FlexiChains._UNSPECIFIED_KWARG,
                Colon(),
                FlexiChains._UNSPECIFIED_KWARG,
            ) == (chain=Colon(),)
            @test fs[Parameter(@varname(x))] isa Any
        end

        @testset "iter collapsed only" begin
            # Test that attempting to index in with `iter=...` errors, but `stat=...` works
            fs = FlexiChains.collapse(chain, [mean]; dims=:iter, split_varnames=false)
            @test_throws ArgumentError FlexiChains._check_summary_kwargs(
                fs,
                Colon(),
                Colon(),
                Colon(),
            )
            @test_throws ArgumentError fs[Parameter(@varname(x)), iter=:]
            @test FlexiChains._check_summary_kwargs(
                fs,
                FlexiChains._UNSPECIFIED_KWARG,
                Colon(),
                Colon(),
            ) isa Any
            @test fs[Parameter(@varname(x)), stat=:] isa Any
            @test FlexiChains._check_summary_kwargs(
                fs,
                FlexiChains._UNSPECIFIED_KWARG,
                Colon(),
                FlexiChains._UNSPECIFIED_KWARG,
            ) == (chain=Colon(), stat=Colon())
            # check that we can use DD lookups and Symbol shorthand for the stat dimension
            @test fs[Parameter(@varname(x)), stat=DD.At(:mean)] isa Any
            @test fs[Parameter(@varname(x)), stat=:mean] ==
                  fs[Parameter(@varname(x)), stat=DD.At(:mean)]
            @test fs[@varname(x[1]), stat=:mean] == fs[@varname(x[1]), stat=DD.At(:mean)]
            @test fs[:x, stat=:mean] == fs[:x, stat=DD.At(:mean)]
            @test fs[stat=:mean] == fs[stat=DD.At(:mean)]
            @test FlexiChains._check_summary_kwargs(
                fs,
                FlexiChains._UNSPECIFIED_KWARG,
                Colon(),
                DD.At(:mean),
            ) == (chain=Colon(), stat=DD.At(:mean))
            @test FlexiChains._check_summary_kwargs(
                fs,
                FlexiChains._UNSPECIFIED_KWARG,
                Colon(),
                :mean,
            ) == (chain=Colon(), stat=DD.At(:mean))
            # check sub-varname too
            @test isapprox(
                fs[Parameter(@varname(x[1])), stat=DD.At(:mean)],
                vec(mean(getindex.(xs, 1); dims=1)),
            )
            # check with no kwargs too
            @test fs[Parameter(@varname(x))] isa Any
        end
    end

    @testset "map_keys" begin
        dicts = fill(
            OrderedDict(
                Parameter(:a) => randn(10, 3),
                Parameter(:b) => randn(10, 3),
                Extra("hello") => randn(10, 3),
            ),
            10,
            3,
        )
        chain = FlexiChain{Symbol}(10, 3, dicts)
        smy = FlexiChains.summarystats(chain; split_varnames=false)

        @testset "trivial identity mapping" begin
            idsmy = FlexiChains.map_keys(identity, smy)
            @test idsmy isa FlexiSummary{Symbol}
            @test isequal(smy, idsmy)
            @test collect(keys(idsmy)) == collect(keys(smy))
        end

        @testset "a working mapping" begin
            g(s::Parameter{Symbol}) = Parameter(String(s.name))
            g(e::Extra) = Extra(Symbol(e.name))
            gsmy = FlexiChains.map_keys(g, smy)
            @test gsmy isa FlexiSummary{String}
            # this checks that the order of keys is preserved
            @test collect(keys(gsmy)) == [Parameter("a"), Parameter("b"), Extra(:hello)]
            @test isequal(gsmy[Parameter("a")], smy[Parameter(:a)])
            @test isequal(gsmy[Parameter("b")], smy[Parameter(:b)])
            @test isequal(gsmy[Extra(:hello)], smy[Extra("hello")])
        end

        @testset "bad function output" begin
            # Doesn't return a valid key
            h(::Any) = 1
            @test_throws ArgumentError FlexiChains.map_keys(h, smy)
            # Returns duplicate keys
            j(::Any) = Parameter(:hello)
            @test_throws ArgumentError FlexiChains.map_keys(j, smy)
        end
    end

    @testset "map_parameters" begin
        dicts = fill(
            OrderedDict(
                Parameter(:a) => randn(10, 3),
                Parameter(:b) => randn(10, 3),
                Extra("hello") => randn(10, 3),
            ),
            10,
            3,
        )
        chain = FlexiChain{Symbol}(10, 3, dicts)
        smy = FlexiChains.summarystats(chain; split_varnames=false)

        @testset "trivial identity mapping" begin
            idsmy = FlexiChains.map_parameters(identity, smy)
            @test idsmy isa FlexiSummary{Symbol}
            @test isequal(smy, idsmy)
            @test collect(keys(idsmy)) == collect(keys(smy))
        end

        @testset "a working mapping" begin
            gsmy = FlexiChains.map_parameters(String, smy)
            @test gsmy isa FlexiSummary{String}
            # this checks that the order of keys is preserved
            @test collect(keys(gsmy)) == [Parameter("a"), Parameter("b"), Extra("hello")]
            @test isequal(gsmy[Parameter("a")], smy[Parameter(:a)])
            @test isequal(gsmy[Parameter("b")], smy[Parameter(:b)])
            @test isequal(gsmy[Extra("hello")], smy[Extra("hello")])
        end

        @testset "bad function output" begin
            # Returns duplicate keys
            j(::Any) = 1
            @test_throws ArgumentError FlexiChains.map_parameters(j, smy)
        end
    end

    @testset "merge FlexiSummary" begin
        N_iters, N_chains = 10, 3
        as = rand(N_iters, N_chains)
        bs = rand(N_iters, N_chains)
        cs = rand(N_iters, N_chains)
        chain_ab = FlexiChain{Symbol}(
            N_iters,
            N_chains,
            Dict(Parameter(:a) => as, Parameter(:b) => bs);
            iter_indices=2:2:(2*N_iters),
            chain_indices=[1, 2, 3],
        )
        chain_bc = FlexiChain{Symbol}(
            N_iters,
            N_chains,
            Dict(Parameter(:b) => bs, Extra("c") => cs);
            iter_indices=2:2:(2*N_iters),
            chain_indices=[1, 2, 3],
        )

        @testset "same keys, same stats: s2 takes priority" begin
            s1 = FlexiChains.collapse(chain_ab, [mean, std]; dims=:both)
            s2 = FlexiChains.collapse(chain_ab, [mean, std]; dims=:both)
            merged = merge(s1, s2)
            @test merged isa FlexiSummary{Symbol}
            for k in keys(s2)
                @test isequal(merged[k], s2[k])
            end
        end

        @testset "disjoint keys, same stats" begin
            s1 = mean(chain_ab)
            s2 = mean(chain_bc)
            merged = merge(s1, s2)
            @test merged isa FlexiSummary{Symbol}
            # :a only in s1
            @test isapprox(merged[:a], s1[:a])
            # Extra("c") only in s2
            @test isapprox(merged[Extra("c")], s2[Extra("c")])
            # :b in both — s2 wins
            @test isapprox(merged[:b], s2[:b])
        end

        @testset "same keys, disjoint stats" begin
            s_mean = mean(chain_ab)
            s_std = std(chain_ab)
            merged = merge(s_mean, s_std)
            @test merged isa FlexiSummary{Symbol}
            # Both stat names should be present
            @test FlexiChains.stat_indices(merged) == [:mean, :std]
            # Values should match the originals
            @test isapprox(merged[:a, stat=DD.At(:mean)], s_mean[:a])
            @test isapprox(merged[:a, stat=DD.At(:std)], s_std[:a])
        end

        @testset "disjoint keys and disjoint stats" begin
            s1 = mean(chain_ab)
            s2 = std(chain_bc)
            merged = merge(s1, s2)
            @test merged isa FlexiSummary{Symbol}
            @test FlexiChains.stat_indices(merged) == [:mean, :std]
            # :a only has mean (from s1), std should be missing
            @test isapprox(merged[:a, stat=DD.At(:mean)], s1[:a])
            @test ismissing(merged[:a, stat=DD.At(:std)])
            # Extra("c") only has std (from s2), mean should be missing
            @test isapprox(merged[Extra("c"), stat=DD.At(:std)], s2[Extra("c")])
            @test ismissing(merged[Extra("c"), stat=DD.At(:mean)])
            # :b has mean from s1 and std from s2
            @test isapprox(merged[:b, stat=DD.At(:mean)], s1[:b])
            @test isapprox(merged[:b, stat=DD.At(:std)], s2[:b])
        end

        @testset "overlapping stats: s2 values take priority" begin
            s1 = FlexiChains.collapse(chain_ab, [mean, std]; dims=:both)
            chain_ab2 = FlexiChain{Symbol}(
                N_iters,
                N_chains,
                Dict(Parameter(:a) => as .+ 1, Parameter(:b) => bs .+ 1);
                iter_indices=2:2:(2*N_iters),
                chain_indices=[1, 2, 3],
            )
            s2 = mean(chain_ab2)
            merged = merge(s1, s2)
            # mean should come from s2 (the shifted data)
            @test isapprox(merged[:a, stat=DD.At(:mean)], s2[:a])
            # std should come from s1 (s2 didn't have std)
            @test isapprox(merged[:a, stat=DD.At(:std)], s1[:a, stat=DD.At(:std)])
        end

        @testset "uncollapsed and mismatched iteration or chain indices" begin
            chain_diff_iter = FlexiChain{Symbol}(
                N_iters,
                N_chains,
                Dict(Parameter(:a) => as);
                iter_indices=100:100:(100*N_iters),
                chain_indices=[1, 2, 3],
            )
            s1 = mean(chain_ab; dims=:chain)
            s2 = mean(chain_diff_iter; dims=:chain)
            @test_throws DimensionMismatch merge(s1, s2)

            chain_diff_chain = FlexiChain{Symbol}(
                N_iters,
                N_chains,
                Dict(Parameter(:a) => as);
                iter_indices=2:2:(2*N_iters),
                chain_indices=[10, 20, 30],
            )
            s1 = mean(chain_ab, dims=:iter)
            s2 = mean(chain_diff_chain, dims=:iter)
            @test_throws DimensionMismatch merge(s1, s2)
        end

        @testset "collapsed iter dimension (dims=:iter)" begin
            s1 = mean(chain_ab; dims=:iter)
            s2 = std(chain_bc; dims=:iter)
            merged = merge(s1, s2)
            @test merged isa FlexiSummary{Symbol}
            @test FlexiChains.iter_indices(merged) === nothing
            @test FlexiChains.chain_indices(merged) == FlexiChains.chain_indices(s1)
        end

        @testset "collapsed chain dimension (dims=:chain)" begin
            s1 = mean(chain_ab; dims=:chain)
            s2 = std(chain_bc; dims=:chain)
            merged = merge(s1, s2)
            @test merged isa FlexiSummary{Symbol}
            @test FlexiChains.iter_indices(merged) == FlexiChains.iter_indices(s1)
            @test FlexiChains.chain_indices(merged) === nothing
        end

        @testset "dropped stat dim in merge result" begin
            @testset "when it should be dropped" begin
                s1 = mean(chain_ab)
                s2 = mean(chain_bc)
                @test FlexiChains.stat_indices(s1) === nothing
                @test FlexiChains.stat_indices(s2) === nothing
                merged = merge(s1, s2)
                @test FlexiChains.stat_indices(merged) === nothing
            end
            @testset "when it shouldn't be dropped" begin
                s1 = mean(chain_ab)
                s2 = std(chain_ab)
                @test FlexiChains.stat_indices(s1) === nothing
                @test FlexiChains.stat_indices(s2) === nothing
                merged = merge(s1, s2)
                @test FlexiChains.stat_indices(merged) == [:mean, :std]
            end
        end

        @testset "key type promotion" begin
            chain_str = FlexiChain{String}(
                N_iters,
                N_chains,
                Dict(Parameter("x") => rand(N_iters, N_chains));
                iter_indices=2:2:(2*N_iters),
                chain_indices=[1, 2, 3],
            )
            s1 = mean(chain_ab)
            s2 = mean(chain_str)
            @test_logs (:warn, r"different key types") merge(s1, s2)
            merged = merge(s1, s2)
            @test merged isa FlexiSummary{Any}
            @test haskey(merged, Parameter(:a))
            @test haskey(merged, Parameter("x"))
        end

        @testset "three or more summaries" begin
            chain_d = FlexiChain{Symbol}(
                N_iters,
                N_chains,
                Dict(Parameter(:d) => rand(N_iters, N_chains));
                iter_indices=2:2:(2*N_iters),
                chain_indices=[1, 2, 3],
            )
            s1 = mean(chain_ab)
            s2 = mean(chain_bc)
            s3 = mean(chain_d)
            merged = merge(s1, s2, s3)
            @test merged isa FlexiSummary{Symbol}
            @test haskey(merged, Parameter(:a))
            @test haskey(merged, Parameter(:b))
            @test haskey(merged, Extra("c"))
            @test haskey(merged, Parameter(:d))
        end
    end

    @testset "subset_parameters on summary" begin
        chain_mixed = FlexiChain{Symbol}(
            N_iters,
            N_chains,
            Dict(Parameter(:a) => as, Extra("c") => cs);
            iter_indices=2:2:(2*N_iters),
            chain_indices=[1, 2, 3],
        )
        s = mean(chain_mixed)
        sp = FlexiChains.subset_parameters(s)
        @test sp isa FlexiSummary{Symbol}
        @test haskey(sp, Parameter(:a))
        @test !haskey(sp, Extra("c"))
    end

    @testset "subset_extras on summary" begin
        chain_mixed = FlexiChain{Symbol}(
            N_iters,
            N_chains,
            Dict(Parameter(:a) => as, Extra("c") => cs);
            iter_indices=2:2:(2*N_iters),
            chain_indices=[1, 2, 3],
        )
        s = mean(chain_mixed)
        se = FlexiChains.subset_extras(s)
        @test se isa FlexiSummary{Symbol}
        @test !haskey(se, Parameter(:a))
        @test haskey(se, Extra("c"))
    end
end

end # module
