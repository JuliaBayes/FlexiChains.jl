module FCChainTests

using FlexiChains: FlexiChains, FlexiChain, Parameter, Extra
using FlexiChains: @varname, VarName
using DimensionalData: val, At
using OffsetArrays: OffsetArray
using OrderedCollections: OrderedDict
using Test

@testset verbose = true "chain.jl" begin
    @info "Testing chain.jl"

    @testset "constructors" begin
        @testset "from array-of-dicts" begin
            @testset "vector of dict" begin
                N_iters = 10
                dicts = fill(
                    Dict(Parameter(:a) => 1, Parameter(:b) => 2, Extra("hello") => 3.0),
                    N_iters,
                )
                chain = FlexiChain{Symbol}(N_iters, 1, dicts)
                @test size(chain) == (N_iters, 1)

                @testset "with metadata" begin
                    chain2 = FlexiChain{Symbol}(
                        N_iters,
                        1,
                        dicts;
                        iter_indices=3:3:(3*N_iters),
                        chain_indices=[2],
                        sampling_time=[1],
                        last_sampler_state=["foo"],
                    )
                    @test size(chain2) == (N_iters, 1)
                    @test val(FlexiChains.iter_indices(chain2)) == 3:3:(3*N_iters)
                    @test val(FlexiChains.chain_indices(chain2)) == [2]
                    @test FlexiChains.sampling_time(chain2) == [1]
                    @test FlexiChains.last_sampler_state(chain2) == ["foo"]
                end
            end

            @testset "matrix of dict" begin
                N_iters, N_chains = 10, 2
                dicts = fill(
                    Dict(Parameter(:a) => 1, Parameter(:b) => 2, Extra("hello") => 3.0),
                    N_iters,
                    N_chains,
                )
                chain = FlexiChain{Symbol}(N_iters, N_chains, dicts)
                @test size(chain) == (N_iters, N_chains)

                @testset "wrong size of data" begin
                    N_iters, N_chains = 10, 2
                    dicts = fill(Dict(Parameter(:a) => 1), N_iters, N_chains)
                    @test_throws DimensionMismatch FlexiChain{Symbol}(
                        N_iters + 1,
                        N_chains + 1,
                        dicts,
                    )
                end

                @testset "wrong indices length" begin
                    @test_throws DimensionMismatch FlexiChain{Symbol}(
                        N_iters,
                        N_chains,
                        dicts;
                        iter_indices=1:(2*N_iters),
                    )
                    @test_throws DimensionMismatch FlexiChain{Symbol}(
                        N_iters,
                        N_chains,
                        dicts;
                        chain_indices=1:(2*N_chains),
                    )
                end

                @testset "with metadata" begin
                    chain2 = FlexiChain{Symbol}(
                        N_iters,
                        N_chains,
                        dicts;
                        iter_indices=3:3:(3*N_iters),
                        chain_indices=[2, 1],
                        sampling_time=[1, 2],
                        last_sampler_state=["foo", "bar"],
                    )
                    @test size(chain2) == (N_iters, N_chains)
                    @test val(FlexiChains.iter_indices(chain2)) == 3:3:(3*N_iters)
                    @test val(FlexiChains.chain_indices(chain2)) == [2, 1]
                    @test FlexiChains.sampling_time(chain2) == [1, 2]
                    @test FlexiChains.last_sampler_state(chain2) == ["foo", "bar"]
                end

                @testset "wrong metadata size" begin
                    @test_throws DimensionMismatch FlexiChain{Symbol}(
                        N_iters,
                        N_chains,
                        dicts;
                        sampling_time=[1],
                    )
                    @test_throws DimensionMismatch FlexiChain{Symbol}(
                        N_iters,
                        N_chains,
                        dicts;
                        sampling_time=1:3,
                    )
                    @test_throws DimensionMismatch FlexiChain{Symbol}(
                        N_iters,
                        N_chains,
                        dicts;
                        last_sampler_state=["foo"],
                    )
                    @test_throws DimensionMismatch FlexiChain{Symbol}(
                        N_iters,
                        N_chains,
                        dicts;
                        last_sampler_state=["foo", "bar", "baz"],
                    )
                end
            end
        end

        @testset "from dict-of-arrays" begin
            @testset "dict of vectors" begin
                N_iters = 10
                arrays = Dict(
                    Parameter(:a) => rand(N_iters),
                    Parameter(:b) => rand(N_iters),
                    Extra("hello") => rand(N_iters),
                )
                chain = FlexiChain{Symbol}(N_iters, 1, arrays)
                @test size(chain) == (N_iters, 1)

                @testset "with metadata" begin
                    chain2 = FlexiChain{Symbol}(
                        N_iters,
                        1,
                        arrays;
                        iter_indices=3:3:(3*N_iters),
                        chain_indices=[2],
                        sampling_time=[1],
                        last_sampler_state=["foo"],
                    )
                    @test size(chain2) == (N_iters, 1)
                    @test val(FlexiChains.iter_indices(chain2)) == 3:3:(3*N_iters)
                    @test val(FlexiChains.chain_indices(chain2)) == [2]
                    @test FlexiChains.sampling_time(chain2) == [1]
                    @test FlexiChains.last_sampler_state(chain2) == ["foo"]
                end
            end

            @testset "dict of matrices" begin
                N_iters, N_chains = 10, 2
                arrays = Dict(
                    Parameter(:a) => rand(N_iters, N_chains),
                    Parameter(:b) => rand(N_iters, N_chains),
                    Extra("hello") => rand(N_iters, N_chains),
                )
                chain = FlexiChain{Symbol}(N_iters, N_chains, arrays)
                @test size(chain) == (N_iters, N_chains)

                @testset "wrong size of data" begin
                    N_iters, N_chains = 10, 2
                    arrays = Dict(Parameter(:a) => rand(N_iters, N_chains))
                    @test_throws DimensionMismatch FlexiChain{Symbol}(
                        N_iters + 1,
                        N_chains + 1,
                        arrays,
                    )
                end

                @testset "wrong indices length" begin
                    @test_throws DimensionMismatch FlexiChain{Symbol}(
                        N_iters,
                        N_chains,
                        arrays;
                        iter_indices=1:(2*N_iters),
                    )
                    @test_throws DimensionMismatch FlexiChain{Symbol}(
                        N_iters,
                        N_chains,
                        arrays;
                        chain_indices=1:(2*N_chains),
                    )
                end

                @testset "with metadata" begin
                    chain2 = FlexiChain{Symbol}(
                        N_iters,
                        N_chains,
                        arrays;
                        iter_indices=3:3:(3*N_iters),
                        chain_indices=[2, 1],
                        sampling_time=[1, 2],
                        last_sampler_state=["foo", "bar"],
                    )
                    @test size(chain2) == (N_iters, N_chains)
                    @test val(FlexiChains.iter_indices(chain2)) == 3:3:(3*N_iters)
                    @test val(FlexiChains.chain_indices(chain2)) == [2, 1]
                    @test FlexiChains.sampling_time(chain2) == [1, 2]
                    @test FlexiChains.last_sampler_state(chain2) == ["foo", "bar"]
                end

                @testset "wrong metadata size" begin
                    @test_throws DimensionMismatch FlexiChain{Symbol}(
                        N_iters,
                        N_chains,
                        arrays;
                        sampling_time=[1],
                    )
                    @test_throws DimensionMismatch FlexiChain{Symbol}(
                        N_iters,
                        N_chains,
                        arrays;
                        sampling_time=1:3,
                    )
                    @test_throws DimensionMismatch FlexiChain{Symbol}(
                        N_iters,
                        N_chains,
                        arrays;
                        last_sampler_state=["foo"],
                    )
                    @test_throws DimensionMismatch FlexiChain{Symbol}(
                        N_iters,
                        N_chains,
                        arrays;
                        last_sampler_state=["foo", "bar", "baz"],
                    )
                end
            end
        end

        @testset "from 3D array" begin
            arr = rand(3, 2, 5)
            niters, nchains, _ = size(arr)

            @testset "all scalar keys" begin
                chain = FlexiChain{Symbol}(
                    arr,
                    (
                        Parameter(:a),
                        Parameter(:b),
                        Parameter(:c),
                        Parameter(:d),
                        Parameter(:e),
                    ),
                )
                @test chain isa FlexiChain{Symbol}
                @test size(chain) == (niters, nchains)
                @test collect(keys(chain)) == Parameter.([:a, :b, :c, :d, :e])
                for i in 1:niters, j in 1:nchains
                    @test chain[:a, iter=i, chain=j] == arr[i, j, 1]
                    @test chain[:b, iter=i, chain=j] == arr[i, j, 2]
                    @test chain[:c, iter=i, chain=j] == arr[i, j, 3]
                    @test chain[:d, iter=i, chain=j] == arr[i, j, 4]
                    @test chain[:e, iter=i, chain=j] == arr[i, j, 5]
                end
            end

            @testset "single vector key" begin
                for ks in (:x, (Parameter(:x) => (5,),))
                    chain = FlexiChain{Symbol}(arr, ks)
                    @test chain isa FlexiChain{Symbol}
                    @test size(chain) == (niters, nchains)
                    @test only(keys(chain)) == Parameter(:x)
                    for i in 1:niters, j in 1:nchains
                        @test chain[:x, iter=i, chain=j] == arr[i, j, :]
                    end
                end
            end

            @testset "mix of scalar and vector keys" begin
                chain = FlexiChain{Symbol}(
                    arr,
                    (Parameter(:μ), Parameter(:σ), Parameter(:β) => (3,)),
                )
                @test chain isa FlexiChain{Symbol}
                @test collect(keys(chain)) == [Parameter(:μ), Parameter(:σ), Parameter(:β)]
                for i in 1:niters, j in 1:nchains
                    @test chain[:μ, iter=i, chain=j] == arr[i, j, 1]
                    @test chain[:σ, iter=i, chain=j] == arr[i, j, 2]
                    @test chain[:β, iter=i, chain=j] == arr[i, j, 3:5]
                end
            end

            @testset "VarName keys" begin
                chain = FlexiChain{VarName}(
                    arr,
                    (Parameter(@varname(a)), Parameter(@varname(b)) => (4,)),
                )
                @test chain isa FlexiChain{<:VarName}
                for i in 1:niters, j in 1:nchains
                    @test chain[@varname(a), iter=i, chain=j] == arr[i, j, 1]
                    @test chain[@varname(b[1]), iter=i, chain=j] == arr[i, j, 2]
                    @test chain[@varname(b[2]), iter=i, chain=j] == arr[i, j, 3]
                    @test chain[@varname(b[3]), iter=i, chain=j] == arr[i, j, 4]
                    @test chain[@varname(b[4]), iter=i, chain=j] == arr[i, j, 5]
                end
            end

            @testset "mix of Parameter and Extra" begin
                chain = FlexiChain{Symbol}(
                    arr,
                    (Parameter(:μ), Parameter(:σ), Parameter(:β) => (2,), Extra(:lp)),
                )
                @test chain isa FlexiChain{Symbol}
                @test collect(keys(chain)) ==
                      [Parameter(:μ), Parameter(:σ), Parameter(:β), Extra(:lp)]
                for i in 1:niters, j in 1:nchains
                    @test chain[:μ, iter=i, chain=j] == arr[i, j, 1]
                    @test chain[:σ, iter=i, chain=j] == arr[i, j, 2]
                    @test chain[:β, iter=i, chain=j] == arr[i, j, 3:4]
                    @test chain[Extra(:lp), iter=i, chain=j] == arr[i, j, 5]
                end
            end

            @testset "matrix-valued key" begin
                arr6 = rand(3, 2, 6)
                chain = FlexiChain{Symbol}(arr6, (Parameter(:M) => (2, 3),))
                @test chain isa FlexiChain{Symbol}
                for i in 1:3, j in 1:2
                    @test chain[:M, iter=i, chain=j] == reshape(arr6[i, j, :], 2, 3)
                end
            end

            @testset "custom iter_indices and chain_indices" begin
                chain = FlexiChain{Symbol}(
                    arr,
                    (Parameter(:a), Parameter(:b) => (4,));
                    iter_indices=10:10:30,
                    chain_indices=[5, 10],
                )
                @test size(chain) == (niters, nchains)
                @test chain[:a, iter=At(10), chain=At(5)] == arr[1, 1, 1]
            end

            @testset "OffsetArray input" begin
                oarr = OffsetArray(arr, 0:2, 10:11, -2:2)
                chain = FlexiChain{Symbol}(
                    oarr,
                    (Parameter(:μ), Parameter(:σ), Parameter(:β) => (3,)),
                )
                @test chain isa FlexiChain{Symbol}
                @test size(chain) == (niters, nchains)
                for i in 1:niters, j in 1:nchains
                    @test chain[:μ, iter=i, chain=j] == arr[i, j, 1]
                    @test chain[:σ, iter=i, chain=j] == arr[i, j, 2]
                    @test chain[:β, iter=i, chain=j] == arr[i, j, 3:5]
                end
            end

            @testset "column count validation" begin
                @test_throws ArgumentError FlexiChain{Symbol}(
                    arr,
                    (Parameter(:a), Parameter(:b)),
                )
                @test_throws ArgumentError FlexiChain{Symbol}(arr, (Parameter(:a) => (6,),))
            end

            @testset "round-trip" begin
                arr = rand(3, 2, 4)
                for ks in (
                    :a,
                    (Parameter(:a), Parameter(:b), Parameter(:c), Parameter(:d)),
                    (Parameter(:a), Parameter(:b), Parameter(:c), Extra(:lp)),
                    (Parameter(:a), Parameter(:b), Parameter(:c) => (2,)),
                )
                    chain = FlexiChain{Symbol}(arr, ks)
                    arr2 = Array(chain; parameters_only=false)
                    @test arr == arr2
                end
            end
        end
    end

    @testset "key ordering of internal data" begin
        # note that the ordering returned by keys(), parameters(), etc. is tested elsewhere
        @testset "array-of-dict" begin
            N_iters, N_chains = 10, 2
            dicts = fill(
                OrderedDict(Parameter(:b) => 1, Extra("hello") => 3, Parameter(:a) => 2),
                N_iters,
                N_chains,
            )
            chain = FlexiChain{Symbol}(N_iters, N_chains, dicts)
            @test collect(keys(chain._data)) ==
                  [Parameter(:b), Extra("hello"), Parameter(:a)]
        end
        @testset "dict-of-array" begin
            N_iters, N_chains = 10, 2
            dicts = OrderedDict(
                Parameter(:b) => fill(1, N_iters, N_chains),
                Extra("hello") => fill(3, N_iters, N_chains),
                Parameter(:a) => fill(2, N_iters, N_chains),
            )
            chain = FlexiChain{Symbol}(N_iters, N_chains, dicts)
            @test collect(keys(chain._data)) ==
                  [Parameter(:b), Extra("hello"), Parameter(:a)]
        end
    end

    @testset "renumber_iters and renumber_chains" begin
        N_iters, N_chains = 10, 2
        dicts = fill(Dict(Parameter(:a) => 1), N_iters, N_chains)
        chain = FlexiChain{Symbol}(N_iters, N_chains, dicts)
        @testset "renumber_iters" begin
            new_iters = 3:3:(3*N_iters)
            chain2 = @inferred FlexiChains.renumber_iters(chain, new_iters)
            @test val(FlexiChains.iter_indices(chain2)) == new_iters
            @test_throws DimensionMismatch FlexiChains.renumber_iters(chain, 1:(2*N_iters))
        end
        @testset "renumber_chains" begin
            new_chains = [2, 1]
            chain2 = @inferred FlexiChains.renumber_chains(chain, new_chains)
            @test val(FlexiChains.chain_indices(chain2)) == new_chains
            @test_throws DimensionMismatch FlexiChains.renumber_chains(
                chain,
                1:(2*N_chains),
            )
        end
    end
end

end # module
