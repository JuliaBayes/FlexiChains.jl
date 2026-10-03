module FCInterfaceTests

using ComponentArrays: ComponentArray
using FlexiChains:
    FlexiChains,
    FlexiChain,
    Parameter,
    Extra,
    ParameterOrExtra,
    @varname,
    VarName,
    transform_values,
    DimArray
using DimensionalData: DimensionalData as DD, At, Not
using OrderedCollections: OrderedDict
using AbstractMCMC: AbstractMCMC
using Test
using Random: Xoshiro

@testset verbose = true "interface.jl" begin
    @info "Testing interface.jl"

    @testset "show doesn't error" begin
        ds = [
            Dict(Parameter(:a) => 1, Extra("hello") => 3.0),
            Dict(Parameter(:a) => 1),
            Dict(Extra("hello") => 3.0),
            Dict(),
        ]
        for d in ds
            chain = FlexiChain{Symbol}(10, 1, fill(d, 10))
            display(chain)
        end
    end

    @testset "_show_range" begin
        # Don't really want to test the full `show` output for FlexiChain, so just unit test
        # this function
        @test FlexiChains._show_range(1:10) == "1:10"
        @test FlexiChains._show_range(3:3:30) == "3:3:30"
        @test FlexiChains._show_range(FlexiChains._make_lookup(1:10)) == "1:10"
        @test FlexiChains._show_range(FlexiChains._make_lookup(3:3:30)) == "3:3:30"
        @test FlexiChains._show_range(FlexiChains._make_lookup(1:10)[DD.Not(4)]) ==
              "[1 … 10]"
        @test FlexiChains._show_range([1, 2, 3, 5, 7, 11]) == "[1 … 11]"
        @test FlexiChains._show_range([2, 3, 5, 7, 11]) == "[2, 3, 5, 7, 11]"
    end

    @testset "equality" begin
        d = Dict(Parameter(:a) => 1, Extra("hello") => 3.0)
        chain1 = FlexiChain{Symbol}(
            10,
            1,
            fill(d, 10);
            sampling_time=[2.5],
            last_sampler_state=["finished"],
        )
        chain2 = FlexiChain{Symbol}(
            10,
            1,
            fill(d, 10);
            sampling_time=[2.5],
            last_sampler_state=["finished"],
        )
        @test chain1 == chain2
        @test isequal(chain1, chain2)
        @test FlexiChains.has_same_data(chain1, chain2)
        # Different iter indices should make chains unequal
        chain3 = FlexiChain{Symbol}(
            10,
            1,
            fill(d, 10);
            iter_indices=21:30,
            sampling_time=[2.5],
            last_sampler_state=["finished"],
        )
        @test chain1 != chain3
        @test !isequal(chain1, chain3)
        # But if we compare the data it should be the same
        @test FlexiChains.has_same_data(chain1, chain3)
        @test Set(keys(chain1)) == Set(keys(chain3))
        # Note that == and isequal on DimData also take indices into account
        # (isequal only from v0.30 onwards though)
        @test !any(k -> chain1[k] == chain3[k], keys(chain1))
        @test !any(k -> isequal(chain1[k], chain3[k]), keys(chain1))
        # A final test case with missing
        dmiss = Dict(Parameter(:a) => missing)
        chainmiss1 = FlexiChain{Symbol}(
            10,
            1,
            fill(dmiss, 10);
            sampling_time=[2.5],
            last_sampler_state=["finished"],
        )
        chainmiss2 = FlexiChain{Symbol}(
            10,
            1,
            fill(dmiss, 10);
            sampling_time=[2.5],
            last_sampler_state=["finished"],
        )
        @test ismissing(chainmiss1 == chainmiss2)
        @test isequal(chainmiss1, chainmiss2)
        @test FlexiChains.has_same_data(chainmiss1, chainmiss2)
        @test ismissing(FlexiChains.has_same_data(chainmiss1, chainmiss2; strict=true))
    end

    @testset "dictionary interface" begin
        N_iters, N_chains = 10, 2
        d = OrderedDict(Parameter(:a) => 1, Extra("hello") => 3.0, Parameter(:b) => 2)
        dicts = fill(d, N_iters, N_chains)
        chain = FlexiChain{Symbol}(N_iters, N_chains, dicts)
        # size
        @test chain isa FlexiChain{Symbol}
        @test size(chain) == (N_iters, N_chains)
        @test size(chain, 1) == N_iters
        @test size(chain, 2) == N_chains
        @test FlexiChains.niters(chain) == N_iters
        @test FlexiChains.nchains(chain) == N_chains
        # keys
        @test collect(keys(chain)) == [Parameter(:a), Extra("hello"), Parameter(:b)]
        for k in keys(d)
            @test haskey(chain, k)
        end
        # values
        @test collect(values(chain)) ==
              [chain[Parameter(:a)], chain[Extra("hello")], chain[Parameter(:b)]]
        @test collect(values(chain; parameters_only=true)) ==
              [chain[Parameter(:a)], chain[Parameter(:b)]]
        # pairs
        @test collect(pairs(chain)) == [
            Parameter(:a) => chain[Parameter(:a)],
            Extra("hello") => chain[Extra("hello")],
            Parameter(:b) => chain[Parameter(:b)],
        ]
        @test collect(pairs(chain; parameters_only=true)) ==
              [:a => chain[Parameter(:a)], :b => chain[Parameter(:b)]]
    end

    @testset "get key names" begin
        N_iters = 10
        # use OrderedDict when constructing so that we can also test order
        d = OrderedDict(
            Parameter(:a) => 1,
            Parameter(:b) => 2,
            Extra("hello") => 3.0,
            Extra("world") => 4.0,
            Extra("key") => 5.0,
        )
        chain = FlexiChain{Symbol}(N_iters, 1, fill(d, N_iters))

        @testset "parameters" begin
            @test FlexiChains.parameters(chain) == [:a, :b]
        end
        @testset "extras" begin
            @test FlexiChains.extras(chain) ==
                  [Extra("hello"), Extra("world"), Extra("key")]
        end
    end

    @testset "getindex" begin
        @testset "DimArray is correctly constructed" begin
            N_iters = 10
            dicts = fill(Dict(Parameter(:a) => 1), N_iters)
            # Inject some chaos with non-default iter_indices and chain_indices
            iter_range = 3:3:(N_iters*3)
            chain = FlexiChain{Symbol}(
                N_iters,
                1,
                dicts;
                iter_indices=iter_range,
                chain_indices=[4],
            )

            @testset "without iter/chain indexing" begin
                returned_as = chain[Parameter(:a)]
                @test returned_as isa DD.DimMatrix
                @test size(returned_as) == (N_iters, 1)
                @test DD.dims(returned_as) isa Tuple{DD.Dim{:iter},DD.Dim{:chain}}
                @test parent(DD.val(DD.dims(returned_as), :iter)) == iter_range
                @test parent(DD.val(DD.dims(returned_as), :chain)) == [4]
            end

            @testset "with iter/chain indexing" begin
                returned_as = chain[Parameter(:a), iter=4:5, chain=DD.At([4])]
                @test returned_as isa DD.DimMatrix
                @test size(returned_as) == (2, 1)
                @test DD.dims(returned_as) isa Tuple{DD.Dim{:iter},DD.Dim{:chain}}
                @test parent(DD.val(DD.dims(returned_as), :iter)) == iter_range[4:5]
                @test parent(DD.val(DD.dims(returned_as), :chain)) == [4]
            end

            @testset "indexing into single chain" begin
                returned_as = chain[Parameter(:a), chain=DD.At(4)]
                @test returned_as isa DD.DimVector
                @test length(returned_as) == N_iters
                @test DD.dims(returned_as) isa Tuple{DD.Dim{:iter}}
                @test parent(DD.val(DD.dims(returned_as), :iter)) == iter_range
            end

            @testset "indexing into single iter + single chain" begin
                returned_as = chain[Parameter(:a), iter=DD.At(6), chain=1]
                @test returned_as == 1
            end
        end

        @testset "DimArray name is set to key" begin
            N_iters = 10
            dicts = fill(Dict(Parameter(:a) => 1, Extra("hello") => 3.0), N_iters)
            chain = FlexiChain{Symbol}(N_iters, 1, dicts)

            @testset "by ParameterOrExtra key" begin
                @test DD.name(chain[Parameter(:a)]) == "Parameter(:a)"
                @test DD.name(chain[Extra("hello")]) == "Extra(\"hello\")"
            end
            @testset "by parameter name" begin
                @test DD.name(chain[:a]) == "Parameter(:a)"
            end
            @testset "by Symbol (String TKey)" begin
                str_dicts = fill(Dict(Parameter("a") => 1), N_iters)
                str_chain = FlexiChain{String}(N_iters, 1, str_dicts)
                @test DD.name(str_chain[:a]) == "Parameter(\"a\")"
            end
        end

        @testset "metadata is correctly constructed" begin
            d = Dict(Parameter(:a) => 1, Extra("hello") => 3.0)
            c = FlexiChain{Symbol}(
                10,
                3,
                fill(d, 10, 3);
                sampling_time=randn(3),
                last_sampler_state=randn(3),
            )
            cs = c[chain=2]
            @test cs isa FlexiChain{Symbol}
            @test FlexiChains.sampling_time(cs) == [FlexiChains.sampling_time(c)[2]]
            @test FlexiChains.last_sampler_state(cs) ==
                  [FlexiChains.last_sampler_state(c)[2]]
        end

        @testset "structures are preserved" begin
            Ni, Nc = 10, 2
            d = Dict(Parameter(:a) => 1)
            structs = [(i, j) for i in 1:Ni, j in 1:Nc]
            chn = FlexiChain{Symbol}(Ni, Nc, fill(d, Ni, Nc); structures=structs)
            @test chn[iter=3:5]._structures == structs[3:5, :]
            @test chn[chain=2]._structures == structs[:, 2:2]
            @test chn[iter=1:4, chain=1]._structures == structs[1:4, 1:1]
            @test chn[[Parameter(:a)]]._structures == structs
        end

        @testset "unambiguous: TKey and ParameterOrExtra{TKey}" begin
            struct Shay
                T::String
            end

            N_iters = 10
            dicts = fill(
                Dict(
                    Parameter(Shay("a")) => 1,
                    Parameter(Shay("b")) => 2,
                    Extra("hello") => 3.0,
                ),
                N_iters,
            )
            chain = FlexiChain{Shay}(N_iters, 1, dicts)

            # Note that DimArrays compare equal to regular matrices with `==` if they have
            # the same contents, so these tests don't actually check that the types returned
            # are correct. We assume that that's handled in the DimArray testset above.
            @testset "TKey" begin
                @test chain[Shay("a")] == fill(1, N_iters, 1)
                @test chain[Shay("a")] == fill(1, N_iters, 1)
                @test chain[Shay("b")] == fill(2, N_iters, 1)
                @testset "with iter subsetting" begin
                    @test chain[Shay("a"), iter=4:6] == fill(1, 3, 1)
                    @test chain[Shay("a"), iter=4:6, chain=DD.At(1)] == fill(1, 3)
                end
            end

            @testset "ParameterOrExtra{TKey}" begin
                @test chain[Parameter(Shay("a"))] == fill(1, N_iters, 1)
                @test chain[Parameter(Shay("a"))] == fill(1, N_iters, 1)
                @test chain[Parameter(Shay("b"))] == fill(2, N_iters, 1)
                @test chain[Extra("hello")] == fill(3.0, N_iters, 1)
                @test_throws KeyError chain[Parameter(Shay("c"))]
                @test_throws KeyError chain[Extra("world")]
                @testset "with iter subsetting" begin
                    @test chain[Parameter(Shay("a")), iter=4:6] == fill(1, 3, 1)
                    @test chain[Parameter(Shay("a")), iter=4:6, chain=DD.At(1)] ==
                          fill(1, 3)
                end
            end
        end

        @testset "indexing with Symbol" begin
            @testset "no ambiguity" begin
                N_iters = 10
                dicts = fill(Dict(Parameter("a") => 1, Parameter("b") => 2), N_iters)
                chain = FlexiChain{String}(N_iters, 1, dicts)
                # This relies on there being a unique key that can be converted to the given
                # Symbol
                @test chain[:a] == fill(1, N_iters, 1)
                @test chain[:b] == fill(2, N_iters, 1)

                @testset "with iter subsetting" begin
                    @test chain[:a, iter=4:6] == fill(1, 3, 1)
                    @test chain[:a, iter=4:6, chain=DD.At(1)] == fill(1, 3)
                end
            end

            @testset "with ambiguity" begin
                # What happens if you have multiple keys that convert to the same Symbol?
                struct TurnsToA end
                Base.Symbol(::TurnsToA) = :a

                N_iters = 10
                dicts = fill(Dict(Parameter(TurnsToA()) => 1, Extra("a") => 3.0), N_iters)
                chain = FlexiChain{TurnsToA}(N_iters, 1, dicts)

                # getindex with the full key should be fine
                @test chain[Parameter(TurnsToA())] == fill(1, N_iters, 1)
                @test chain[Extra("a")] == fill(3.0, N_iters, 1)
                # but getindex with the symbol should fail
                @test_throws KeyError chain[:a]
                # ... with the correct error message
                @test_throws "multiple keys" chain[:a]
            end

            @testset "on a chain with TKey=Symbol" begin
                niters, nchains = 10, 3
                d = Dict(
                    Parameter(:a) => zeros(niters, nchains),
                    Parameter(:c) => zeros(niters, nchains),
                    Extra(:b) => zeros(niters, nchains),
                    Extra(:c) => zeros(niters, nchains),
                )
                chain = FlexiChain{Symbol}(niters, nchains, d)
                # Check that the unambiguous ones can be accessed (both parameter and extra
                # -- on old versions of FlexiChains, parameters would work but not extras,
                # due to Julia's rules on method dispatch).
                @test all(iszero, chain[:a])
                @test all(iszero, chain[:b])
                @test_throws "multiple keys" chain[:c]
            end
        end

        @testset "multiple keys: Colon and AbstractVector" begin
            # These methods all return FlexiChain
            N_iters = 10
            hellos = randn(N_iters)
            dicts = Dict(
                Parameter("a") => 1:N_iters,
                Parameter("b") => fill(2, N_iters),
                Extra("hello") => hellos,
            )
            chain = FlexiChain{String}(N_iters, 1, dicts; iter_indices=2:2:(N_iters*2))

            @testset "No argument (should default to colon)" begin
                @test isequal(chain, chain[])
                @testset "with iter subsetting" begin
                    # Ordinary indices
                    c2 = chain[iter=4:6]
                    @test c2 isa FlexiChain{String}
                    @test size(c2) == (3, 1)
                    @test c2[Parameter("a")] == reshape(4:6, 3, 1)
                    # With DimensionalData selectors
                    c3 = chain[iter=DD.At([4, 6, 8])]
                    @test c3 isa FlexiChain{String}
                    @test size(c3) == (3, 1)
                    @test c3[Parameter("a")] == reshape(2:4, 3, 1)
                end
            end
            @testset "Explicit colon" begin
                @test isequal(chain, chain[:])
            end
            @testset "AbstractVector{ParameterOrExtra{TKey}}" begin
                keys = [Parameter("a"), Extra("hello")]
                c = chain[keys]
                @test c isa FlexiChain{String}
                @test size(c) == (N_iters, 1)
                @test c[Parameter("a")] == reshape(1:N_iters, N_iters, 1)
                @test c[Extra("hello")] == reshape(hellos, N_iters, 1)
                @test !haskey(c, Parameter("b"))
                @test_throws KeyError c[Parameter("b")]
            end
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

            @testset "scalar parameter is unaffected by stack" begin
                s_default = chain[:scalar]
                s_true = chain[:scalar, stack=true]
                s_false = chain[:scalar, stack=false]
                @test s_default isa DD.DimMatrix{Float64}
                @test s_true isa DD.DimMatrix{Float64}
                @test s_false isa DD.DimMatrix{Float64}
                @test s_default == s_true == s_false
            end

            @testset "Array parameter" begin
                @testset "stack=false" begin
                    result = chain[:arr, stack=false]
                    @test result isa DD.DimMatrix{Vector{Float64}}
                    @test size(result) == (Niters, Nchains)
                    @test result[1, 1] == arr
                end
                @testset "stack=true" begin
                    result = chain[:arr, stack=true]
                    @test result isa DD.DimArray{Float64,3}
                    @test size(result) == (Niters, Nchains, 3)
                    @test DD.dims(result) isa Tuple{DD.Dim{:iter},DD.Dim{:chain},DD.AnonDim}
                    @test result[1, 1, :] == arr
                end
                @testset "default (no stack kwarg)" begin
                    result = chain[:arr]
                    @test result isa DD.DimMatrix{Vector{Float64}}
                    @test size(result) == (Niters, Nchains)
                    @test result[1, 1] == arr
                end
            end

            @testset "DimArray parameter" begin
                @testset "stack=false" begin
                    result = chain[:dimarr, stack=false]
                    @test result isa DD.DimMatrix{<:DD.DimArray}
                    @test size(result) == (Niters, Nchains)
                    @test result[1, 1] == dimarr
                end
                @testset "stack=true" begin
                    result = chain[:dimarr, stack=true]
                    @test result isa DD.DimArray{Float64,3}
                    @test size(result) == (Niters, Nchains, 3)
                    @test DD.dims(result) isa Tuple{DD.Dim{:iter},DD.Dim{:chain},DD.X}
                    @test DD.lookup(DD.dims(result, DD.X)) ==
                          DD.lookup(DD.dims(dimarr, DD.X))
                    @test result[1, 1, :] == parent(dimarr)
                end
                @testset "default (no stack kwarg) emits deprecation warning" begin
                    result =
                        @test_logs((:warn, FlexiChains._STACK_DEPWARN_MSG), chain[:dimarr],)
                    @test result isa DD.DimArray{Float64,3}
                    @test size(result) == (Niters, Nchains, 3)
                end
            end

            @testset "stack=true with mismatched sizes errors" begin
                arr1 = [1.0, 2.0]
                arr2 = [1.0, 2.0, 3.0]
                mat = hcat(fill([arr1, arr2], 3)...)
                d_bad = Dict(Parameter(:x) => mat)
                bad_chain = FlexiChain{Symbol}(2, 3, d_bad)
                @test_throws DimensionMismatch bad_chain[:x, stack=true]
                result = bad_chain[:x, stack=false]
                @test result isa DD.DimMatrix
                @test result[1, 1] == arr1
                @test result[2, 1] == arr2
            end

            @testset "stack with iter/chain subsetting" begin
                result = chain[:arr, stack=true, iter=1:3, chain=DD.At(1)]
                @test result isa DD.DimArray{Float64,2}
                @test size(result) == (3, 3)
                @test result[1, :] == arr

                result = chain[:dimarr, stack=true, iter=1:3, chain=DD.At(1)]
                @test result isa DD.DimArray{Float64,2}
                @test size(result) == (3, 3)
                @test result[1, :] == parent(dimarr)
            end

            @testset "stack with both dims collapsed" begin
                result = chain[:arr, stack=true, iter=DD.At(1), chain=DD.At(1)]
                @test result == arr

                result = chain[:dimarr, stack=true, iter=DD.At(1), chain=DD.At(1)]
                @test result == dimarr
            end
        end
    end

    @testset "values_at / parameters_at" begin
        Ni, Nc = 10, 3
        c = FlexiChain{Symbol}(
            Ni,
            Nc,
            OrderedDict(Parameter(:a) => rand(Ni, Nc), Extra("c") => rand(Ni, Nc)),
        )

        @testset "values_at" begin
            for i in 1:Ni
                d = FlexiChains.values_at(c; iter=i, chain=1)
                @test d isa OrderedDict
                @test length(d) == 2
                @test d[Parameter(:a)] == c[Parameter(:a)][i]
                @test d[Extra("c")] == c[Extra("c")][i]
                d = FlexiChains.values_at(c, NamedTuple; iter=i, chain=1)
                @test d == (a=c[Parameter(:a)][i], c=c[Extra("c")][i])
                d = FlexiChains.values_at(c, ComponentArray; iter=i, chain=1)
                @test d == ComponentArray(; a=c[Parameter(:a)][i], c=c[Extra("c")][i])
                d = FlexiChains.values_at(c, ComponentArray{Real}; iter=i, chain=1)
                @test d == ComponentArray{Real}(; a=c[Parameter(:a)][i], c=c[Extra("c")][i])
            end

            @testset "default kwargs (all iters/chains)" begin
                d = FlexiChains.values_at(c)
                @test d isa
                      DD.DimMatrix{<:OrderedDict{<:FlexiChains.ParameterOrExtra{<:Symbol}}}
                @test size(d) == (Ni, Nc)
                for i in 1:Ni, j in 1:Nc
                    @test d[i, j] == FlexiChains.values_at(c; iter=i, chain=j)
                end
            end

            @testset "with ranges of indices" begin
                iters = 1:5
                d = FlexiChains.values_at(c; iter=iters, chain=1)
                @test d isa
                      DD.DimVector{<:OrderedDict{<:FlexiChains.ParameterOrExtra{<:Symbol}}}
                for i in iters
                    @test d[i] == FlexiChains.values_at(c; iter=i, chain=1)
                end
                d = FlexiChains.values_at(c; iter=iters, chain=:)
                @test d isa
                      DD.DimMatrix{<:OrderedDict{<:FlexiChains.ParameterOrExtra{<:Symbol}}}
                for i in iters, j in 1:Nc
                    @test d[i, j] == FlexiChains.values_at(c; iter=i, chain=j)
                end
            end

            @testset "with vector indices" begin
                iters = [5, 6]
                d = FlexiChains.values_at(c; iter=iters, chain=1)
                @test d isa
                      DD.DimVector{<:OrderedDict{<:FlexiChains.ParameterOrExtra{<:Symbol}}}
                for i in iters
                    @test d[At(i)] == FlexiChains.values_at(c; iter=i, chain=1)
                end
            end

            @testset "with Not() selector" begin
                d = FlexiChains.values_at(c; iter=Not(3), chain=1)
                @test d isa
                      DD.DimVector{<:OrderedDict{<:FlexiChains.ParameterOrExtra{<:Symbol}}}
                @test size(d, 1) == Ni - 1
                for i in [1, 2, 4, 5, 6, 7, 8, 9, 10]
                    @test d[At(i)] == FlexiChains.values_at(c; iter=i, chain=1)
                end
            end

            @testset "ambiguous keys" begin
                c2 = FlexiChain{Any}(
                    Ni,
                    Nc,
                    OrderedDict(
                        Parameter(:a) => rand(Ni, Nc),
                        Parameter("a") => rand(Ni, Nc),
                    ),
                )
                @test_throws ArgumentError FlexiChains.values_at(
                    c2,
                    NamedTuple;
                    iter=1,
                    chain=1,
                )
                @test_throws ArgumentError FlexiChains.values_at(
                    c2,
                    ComponentArray;
                    iter=1,
                    chain=1,
                )
            end

            @testset "chains with abstract type parameter" begin
                # This doesn't really test `VarName` per se, it's more about testing an
                # abstract type parameter, as this used to error
                cvn = FlexiChain{VarName}(
                    1,
                    1,
                    OrderedDict(Parameter(@varname(a)) => rand(1, 1)),
                )
                vals = FlexiChains.values_at(cvn; iter=1, chain=1)
                @test vals isa OrderedDict{ParameterOrExtra{<:VarName},Any}
            end

            @testset "dispatch on structures" begin
                struct TestValStructure
                    tag::Tuple{Int,Int}
                end
                FlexiChains.reconstruct_values(
                    ::FlexiChain,
                    ::Any,
                    ::Any,
                    s::TestValStructure,
                ) = s
                Ni_s, Nc_s = 4, 2
                structs = [TestValStructure((i, j)) for i in 1:Ni_s, j in 1:Nc_s]
                cs = FlexiChain{Symbol}(
                    Ni_s,
                    Nc_s,
                    OrderedDict(Parameter(:a) => rand(Ni_s, Nc_s));
                    structures=structs,
                )
                for i in 1:Ni_s, j in 1:Nc_s
                    @test FlexiChains.values_at(cs; iter=i, chain=j) === structs[i, j]
                end
                # Explicit type should bypass structures
                @test FlexiChains.values_at(cs, OrderedDict; iter=1, chain=1) isa
                      OrderedDict
            end
        end

        @testset "parameters_at" begin
            for i in 1:Ni
                d = FlexiChains.parameters_at(c; iter=i, chain=1)
                @test length(d) == 1
                @test d[:a] == c[Parameter(:a)][i]
                d = FlexiChains.parameters_at(c, NamedTuple; iter=i, chain=1)
                @test d == (; a=c[Parameter(:a)][i])
                d = FlexiChains.parameters_at(c, ComponentArray; iter=i, chain=1)
                @test d == ComponentArray(; a=c[Parameter(:a)][i])
                d = FlexiChains.parameters_at(c, ComponentArray{Real}; iter=i, chain=1)
                @test d == ComponentArray{Real}(; a=c[Parameter(:a)][i])
            end

            @testset "default kwargs (all iters/chains)" begin
                d = FlexiChains.parameters_at(c)
                @test d isa DD.DimMatrix{<:OrderedDict{Symbol}}
                @test size(d) == (Ni, Nc)
                for i in 1:Ni, j in 1:Nc
                    @test d[i, j] == FlexiChains.parameters_at(c; iter=i, chain=j)
                end
            end

            @testset "with ranges of indices" begin
                iters = 1:5
                d = FlexiChains.parameters_at(c; iter=iters, chain=1)
                @test d isa DD.DimVector{<:OrderedDict{Symbol}}
                for i in iters
                    @test d[i] == FlexiChains.parameters_at(c; iter=i, chain=1)
                end
                d = FlexiChains.parameters_at(c; iter=iters, chain=:)
                @test d isa DD.DimMatrix{<:OrderedDict{Symbol}}
                for i in iters, j in 1:Nc
                    @test d[i, j] == FlexiChains.parameters_at(c; iter=i, chain=j)
                end
            end

            @testset "with vector indices" begin
                iters = [5, 6]
                d = FlexiChains.parameters_at(c; iter=iters, chain=1)
                @test d isa DD.DimVector{<:OrderedDict{Symbol}}
                for i in iters
                    @test d[At(i)] == FlexiChains.parameters_at(c; iter=i, chain=1)
                end
            end

            @testset "with Not() selector" begin
                d = FlexiChains.parameters_at(c; iter=Not(3), chain=1)
                @test d isa DD.DimVector{<:OrderedDict{Symbol}}
                @test size(d, 1) == Ni - 1
                for i in [1, 2, 4, 5, 6, 7, 8, 9, 10]
                    @test d[At(i)] == FlexiChains.parameters_at(c; iter=i, chain=1)
                end
            end

            @testset "ambiguous keys" begin
                c2 = FlexiChain{Any}(
                    Ni,
                    Nc,
                    OrderedDict(
                        Parameter(:a) => rand(Ni, Nc),
                        Parameter("a") => rand(Ni, Nc),
                    ),
                )
                @test_throws ArgumentError FlexiChains.parameters_at(
                    c2,
                    NamedTuple;
                    iter=1,
                    chain=1,
                )
                @test_throws ArgumentError FlexiChains.parameters_at(
                    c2,
                    ComponentArray;
                    iter=1,
                    chain=1,
                )
            end

            @testset "dispatch on structures" begin
                struct TestParamStructure
                    tag::Tuple{Int,Int}
                end
                FlexiChains.reconstruct_parameters(
                    ::FlexiChain,
                    ::Any,
                    ::Any,
                    s::TestParamStructure,
                ) = s
                Ni_s, Nc_s = 4, 2
                structs = [TestParamStructure((i, j)) for i in 1:Ni_s, j in 1:Nc_s]
                cs = FlexiChain{Symbol}(
                    Ni_s,
                    Nc_s,
                    OrderedDict(
                        Parameter(:a) => rand(Ni_s, Nc_s),
                        Extra("c") => rand(Ni_s, Nc_s),
                    );
                    structures=structs,
                )
                for i in 1:Ni_s, j in 1:Nc_s
                    @test FlexiChains.parameters_at(cs; iter=i, chain=j) === structs[i, j]
                end
                # Explicit type should bypass structures
                @test FlexiChains.parameters_at(cs, OrderedDict; iter=1, chain=1) isa
                      OrderedDict
            end
        end

        @testset "positional API removed" begin
            @test_throws MethodError FlexiChains.values_at(c, 1, 1)
            @test_throws MethodError FlexiChains.values_at(c, 1, 1, NamedTuple)
            @test_throws MethodError FlexiChains.parameters_at(c, 1, 1)
            @test_throws MethodError FlexiChains.parameters_at(c, 1, 1, NamedTuple)
        end
    end

    @testset "keys merge: `merge`" begin
        @testset "basic merge" begin
            struct Foo end
            N_iters = 10
            dict1 = Dict(Parameter(:a) => 1, Parameter(:b) => "no", Extra("foo") => 3.0)
            chain1 = FlexiChain{Symbol}(N_iters, 1, fill(dict1, N_iters))

            dict2 = Dict(
                Parameter(:c) => Foo(),
                Parameter(:b) => "yes",
                Extra("bar") => "cheese",
            )
            ii = 3:3:(N_iters*3)
            ci = [4]
            sampling_time = [2.5]
            last_sampler_state = ["finished"]
            chain2 = FlexiChain{Symbol}(
                N_iters,
                1,
                fill(dict2, N_iters);
                iter_indices=ii,
                chain_indices=ci,
                sampling_time=sampling_time,
                last_sampler_state=last_sampler_state,
            )
            chain3 = merge(chain1, chain2)

            @testset "values are taken from second chain" begin
                expected_chain3 = FlexiChain{Symbol}(
                    N_iters,
                    1,
                    fill(merge(dict1, dict2), N_iters);
                    iter_indices=ii,
                    chain_indices=ci,
                    sampling_time=sampling_time,
                    last_sampler_state=last_sampler_state,
                )
                for k in keys(expected_chain3)
                    @test chain3[k] == expected_chain3[k]
                end
                # An explicit test
                @test all(x -> x == "yes", chain3[Parameter(:b)])
            end

            @testset "metadata is taken from second chain" begin
                @test FlexiChains.iter_indices(chain3) == ii
                @test FlexiChains.chain_indices(chain3) == ci
                @test FlexiChains.sampling_time(chain3) == sampling_time
                @test FlexiChains.last_sampler_state(chain3) == last_sampler_state
            end

            @testset "underlying data still has the right types" begin
                # Essentially we want to avoid that the underlying data is converted into
                # Matrix{Any} which would lose type information.
                @test eltype(chain3[Parameter(:a)]) == Int
                @test eltype(chain3[Parameter(:b)]) == String
                @test eltype(chain3[Extra("foo")]) == Float64
                @test eltype(chain3[Extra("bar")]) == String
                @test eltype(chain3[Parameter(:c)]) == Foo
            end
        end

        @testset "size mismatch" begin
            # Sizes are just incompatible
            dict1 = Dict(Parameter(:a) => 1)
            chain1 = FlexiChain{Symbol}(10, 1, fill(dict1, 10))
            dict2 = Dict(Parameter(:b) => 2.0)
            chain2 = FlexiChain{Symbol}(100, 1, fill(dict2, 100))
            @test_throws DimensionMismatch merge(chain1, chain2)

            # This is OK (vector combined with N*1 matrix)
            dict3 = Dict(Parameter(:c) => 3.0)
            chain3 = FlexiChain{Symbol}(10, 1, fill(dict3, 10, 1))
            @test merge(chain1, chain3) isa FlexiChain{Symbol}

            # This is not OK
            dict4 = Dict(Parameter(:d) => 3.0)
            chain4 = FlexiChain{Symbol}(5, 2, fill(dict4, 5, 2))
            @test_throws DimensionMismatch merge(chain1, chain4)
        end

        @testset "key type promotion" begin
            dict1 = Dict(Parameter(:a) => 1)
            chain1 = FlexiChain{Symbol}(10, 1, fill(dict1, 10))
            dict2 = Dict(Parameter("b") => "Hi")
            chain2 = FlexiChain{String}(10, 1, fill(dict2, 10))
            @test_logs (:warn, r"different key types") merge(chain1, chain2)
            ch = merge(chain1, chain2)
            # Not sure why but `Base.promote_type(Symbol, String)` returns Any
            @test ch isa FlexiChain{Any}
            @test ch[Parameter(:a)] isa AbstractMatrix{Int}
            @test ch[Parameter(:a)] == fill(1, 10, 1)
            @test ch[Parameter("b")] isa AbstractMatrix{String}
            @test ch[Parameter("b")] == fill("Hi", 10, 1)
        end

        @testset "structures are preserved" begin
            Ni, Nc = 10, 2
            d1 = Dict(Parameter(:a) => 1)
            d2 = Dict(Parameter(:a) => 2, Parameter(:b) => 3.0)
            nt_structs1 = [(a=i, b=j) for i in 1:Ni, j in 1:Nc]
            nt_structs2 = [(b=100, c=200) for _ in 1:Ni, _ in 1:Nc]
            chn1 = FlexiChain{Symbol}(Ni, Nc, fill(d1, Ni, Nc); structures=nt_structs1)
            chn2 = FlexiChain{Symbol}(Ni, Nc, fill(d2, Ni, Nc); structures=nt_structs2)
            merged = merge(chn1, chn2)
            for i in 1:Ni, j in 1:Nc
                @test merged._structures[i, j] ==
                      merge(nt_structs1[i, j], nt_structs2[i, j])
            end
        end

        @testset "merge_structures with nothing" begin
            @test FlexiChains.merge_structures(nothing, nothing) === nothing
            @test FlexiChains.merge_structures(nothing, :foo) === :foo
            @test FlexiChains.merge_structures(:foo, nothing) === :foo
        end
    end

    @testset "subset parameters and extras" begin
        N_iters = 10
        d = Dict(Parameter(:a) => 1, Extra("c") => 3.0)
        chain = FlexiChain{Symbol}(N_iters, 1, fill(d, N_iters))
        @test isequal(FlexiChains.subset_parameters(chain), chain[[Parameter(:a)]])
        @test isequal(FlexiChains.subset_extras(chain), chain[[Extra("c")]])
    end

    @testset "vcat" begin
        @testset "basic application" begin
            niters1 = 10
            d1 = Dict(Parameter(:a) => 1, Extra("c") => 3.0)
            chain1 = FlexiChain{Symbol}(niters1, 1, fill(d1, niters1))
            niters2 = 20
            d2 = Dict(Parameter(:a) => 2, Extra("c") => "foo")
            chain2 = FlexiChain{Symbol}(niters2, 1, fill(d2, niters2))
            chain12 = vcat(chain1, chain2)
            @test chain12 isa FlexiChain{Symbol}
            @test size(chain12) == (niters1 + niters2, 1)
            @test chain12[Parameter(:a)] == vcat(fill(1, niters1, 1), fill(2, niters2, 1))
            @test chain12[Extra("c")] ==
                  vcat(fill(3.0, niters1, 1), fill("foo", niters2, 1))
        end

        @testset "_smartcat" begin
            @test FlexiChains._smartcat(1:10, 11:20) == 1:20
            @test FlexiChains._smartcat(
                FlexiChains._make_lookup(1:10),
                FlexiChains._make_lookup(11:20),
            ) == FlexiChains._make_lookup(1:20)
            @test FlexiChains._smartcat(2:2:10, 12:2:20) == 2:2:20
            @test FlexiChains._smartcat(
                FlexiChains._make_lookup(2:2:10),
                FlexiChains._make_lookup(12:2:20),
            ) == FlexiChains._make_lookup(2:2:20)
        end

        @testset "handling indices" begin
            N_iters = 10
            d1 = Dict(Parameter(:a) => 1, Extra("c") => 3.0)
            chain1 = FlexiChain{Symbol}(
                N_iters,
                1,
                fill(d1, N_iters);
                iter_indices=1:10,
                chain_indices=[1],
            )
            d2 = Dict(Parameter(:a) => 2, Extra("c") => "foo")
            chain2 = FlexiChain{Symbol}(
                N_iters,
                1,
                fill(d2, N_iters);
                iter_indices=21:30,
                chain_indices=[2],
            )
            chain12 = vcat(chain1, chain2)
            @test FlexiChains.iter_indices(chain12) == vcat(1:10, 31:40)
            @test_logs (:warn, r"different chain indices") vcat(chain1, chain2)
            @test FlexiChains.chain_indices(chain12) == FlexiChains.chain_indices(chain1)
        end

        @testset "metadata" begin
            niters1 = 10
            d1 = Dict(Parameter(:a) => 1, Extra("c") => 3.0)
            chain1 = FlexiChain{Symbol}(
                niters1,
                1,
                fill(d1, niters1);
                sampling_time=[1],
                last_sampler_state=["foo"],
            )
            niters2 = 20
            d2 = Dict(Parameter(:a) => 2, Extra("c") => "foo")
            chain2 = FlexiChain{Symbol}(
                niters2,
                1,
                fill(d2, niters2);
                sampling_time=[2],
                last_sampler_state=["bar"],
            )
            chain12 = vcat(chain1, chain2)

            # Sampling times should be summed
            @test isapprox(FlexiChains.sampling_time(chain12), [3])
            # Last sampler state should be taken from the second chain
            @test FlexiChains.last_sampler_state(chain12) == ["bar"]
        end

        @testset "structures are preserved" begin
            Nc = 2
            d1 = Dict(Parameter(:a) => 1)
            structs1 = [(i, j) for i in 1:10, j in 1:Nc]
            chn1 = FlexiChain{Symbol}(10, Nc, fill(d1, 10, Nc); structures=structs1)
            d2 = Dict(Parameter(:a) => 2)
            structs2 = [(i, j) for i in 11:15, j in 1:Nc]
            chn2 = FlexiChain{Symbol}(5, Nc, fill(d2, 5, Nc); structures=structs2)
            @test vcat(chn1, chn2)._structures == vcat(structs1, structs2)
        end

        @testset "error on different number of chains" begin
            d1 = Dict(Parameter(:a) => 1, Extra("c") => 3.0)
            chain1 = FlexiChain{Symbol}(10, 1, fill(d1, 10, 1))
            d2 = Dict(Parameter(:a) => 2, Extra("c") => "foo")
            chain2 = FlexiChain{Symbol}(10, 2, fill(d2, 10, 2))
            @test_throws DimensionMismatch vcat(chain1, chain2)
        end

        @testset "error on different key type" begin
            d1 = Dict(Parameter(:a) => 1)
            chain1 = FlexiChain{Symbol}(10, 1, fill(d1, 10))
            d2 = Dict(Parameter("a") => 2)
            chain2 = FlexiChain{String}(10, 1, fill(d2, 10))
            @test_throws ArgumentError vcat(chain1, chain2)
        end
    end

    @testset "hcat" begin
        @testset "basic application" begin
            N_iters = 10
            d1 = Dict(Parameter(:a) => 1, Extra("c") => 3.0)
            chain1 = FlexiChain{Symbol}(N_iters, 1, fill(d1, N_iters))
            d2 = Dict(Parameter(:a) => 2, Extra("c") => "foo")
            chain2 = FlexiChain{Symbol}(N_iters, 1, fill(d2, N_iters))
            chain12 = hcat(chain1, chain2)
            @test chain12 isa FlexiChain{Symbol}
            @test size(chain12) == (N_iters, 2)
            @test chain12[Parameter(:a)] == repeat([1 2], N_iters)
            @test chain12[Extra("c")] == repeat([3.0 "foo"], N_iters)
        end

        @testset "handling indices" begin
            N_iters = 10
            d1 = Dict(Parameter(:a) => 1, Extra("c") => 3.0)
            chain1 = FlexiChain{Symbol}(N_iters, 1, fill(d1, N_iters); iter_indices=1:10)
            d2 = Dict(Parameter(:a) => 2, Extra("c") => "foo")
            chain2 = FlexiChain{Symbol}(N_iters, 1, fill(d2, N_iters); iter_indices=21:30)

            @test_logs (:warn, r"different iteration indices") hcat(chain1, chain2)
            chain12 = hcat(chain1, chain2)
            @test FlexiChains.iter_indices(chain12) == FlexiChains.iter_indices(chain1)
            @test FlexiChains.chain_indices(chain12) == [1, 2]
        end

        @testset "combination of metadata" begin
            N_iters = 10
            d1 = Dict(Parameter(:a) => 1)
            chain1 = FlexiChain{Symbol}(
                N_iters,
                1,
                fill(d1, N_iters);
                sampling_time=[1],
                last_sampler_state=["foo"],
            )
            d2 = Dict(Parameter(:a) => 2)
            chain2 = FlexiChain{Symbol}(
                N_iters,
                1,
                fill(d2, N_iters);
                sampling_time=[2],
                last_sampler_state=["bar"],
            )
            chain12 = hcat(chain1, chain2)
            @test chain12 isa FlexiChain{Symbol}
            @test size(chain12) == (N_iters, 2)
            @test chain12[Parameter(:a)] == repeat([1 2], N_iters)
            @test FlexiChains.sampling_time(chain12) == [1, 2]
            @test FlexiChains.last_sampler_state(chain12) == ["foo", "bar"]
        end

        @testset "structures are preserved" begin
            Ni = 10
            d1 = Dict(Parameter(:a) => 1)
            structs1 = [(i, 1) for i in 1:Ni, _ in 1:1]
            chn1 = FlexiChain{Symbol}(Ni, 1, fill(d1, Ni); structures=structs1)
            d2 = Dict(Parameter(:a) => 2)
            structs2 = [(i, 2) for i in 1:Ni, _ in 1:1]
            chn2 = FlexiChain{Symbol}(Ni, 1, fill(d2, Ni); structures=structs2)
            @test hcat(chn1, chn2)._structures == hcat(structs1, structs2)
        end

        @testset "3 or more inputs" begin
            N_iters = 10
            d1 = Dict(Parameter(:a) => 1, Extra("c") => 3.0)
            chain1 = FlexiChain{Symbol}(N_iters, 1, fill(d1, N_iters))
            d2 = Dict(Parameter(:a) => 2, Extra("c") => "foo")
            chain2 = FlexiChain{Symbol}(N_iters, 1, fill(d2, N_iters))
            d3 = Dict(Parameter(:x) => 4, Extra("e") => :y)
            chain3 = FlexiChain{Symbol}(N_iters, 1, fill(d3, N_iters))
            chain123 = hcat(chain1, chain2, chain3)
            @test chain123 isa FlexiChain{Symbol}
            @test size(chain123) == (N_iters, 3)
            # need isequal() rather than `==` to handle the `missing` values
            @test isequal(chain123[Parameter(:a)], repeat([1 2 missing], N_iters))
            @test isequal(chain123[Extra("c")], repeat([3.0 "foo" missing], N_iters))
            @test isequal(chain123[Parameter(:x)], repeat([missing missing 4], N_iters))
            @test isequal(chain123[Extra("e")], repeat([missing missing :y], N_iters))
        end

        @testset "stacking different numbers of chains" begin
            N_iters = 10
            chain1 = FlexiChain{Symbol}(N_iters, 1, fill(Dict(Parameter(:a) => 1), N_iters))
            chain2 =
                FlexiChain{Symbol}(N_iters, 2, fill(Dict(Parameter(:a) => 3), N_iters, 2))
            chain12 = hcat(chain1, chain2)
            @test chain12 isa FlexiChain{Symbol}
            @test size(chain12) == (N_iters, 3)
            @test chain12[Parameter(:a)] == repeat([1 3 3], N_iters)
        end

        @testset "error on different number of iters" begin
            d1 = Dict(Parameter(:a) => 1, Extra("c") => 3.0)
            chain1 = FlexiChain{Symbol}(20, 1, fill(d1, 20))
            d2 = Dict(Parameter(:a) => 2, Extra("c") => "foo")
            chain2 = FlexiChain{Symbol}(10, 1, fill(d2, 10))
            @test_throws DimensionMismatch hcat(chain1, chain2)
        end

        @testset "error on different key type" begin
            d1 = Dict(Parameter(:a) => 1)
            chain1 = FlexiChain{Symbol}(10, 1, fill(d1, 10))
            d2 = Dict(Parameter("a") => 2)
            chain2 = FlexiChain{String}(10, 1, fill(d2, 10))
            @test_throws ArgumentError hcat(chain1, chain2)
        end

        @testset "different parameters in chains" begin
            chain1 = FlexiChain{Symbol}(10, 1, fill(Dict(Parameter(:a) => 1), 10))
            chain2 = FlexiChain{Symbol}(10, 1, fill(Dict(Parameter(:b) => 2), 10))
            chain12 = hcat(chain1, chain2)
            @test chain12 isa FlexiChain{Symbol}
            @test size(chain12) == (10, 2)
            # need isequal() rather than `==` to handle the `missing` values
            @test isequal(chain12[Parameter(:a)], repeat([1 missing], 10))
            @test isequal(chain12[Parameter(:b)], repeat([missing 2], 10))
        end

        @testset "AbstractMCMC.chainscat and chainsstack" begin
            # These methods make use of hcat. We just do a basic test
            N_iters = 10
            d1 = Dict(Parameter(:a) => 1, Extra("c") => 3.0)
            chain1 = FlexiChain{Symbol}(N_iters, 1, fill(d1, N_iters))
            d2 = Dict(Parameter(:a) => 2, Extra("c") => "foo")
            chain2 = FlexiChain{Symbol}(N_iters, 1, fill(d2, N_iters))
            d3 = Dict(Parameter(:x) => 4, Extra("e") => :y)
            chain3 = FlexiChain{Symbol}(N_iters, 1, fill(d3, N_iters))
            chain12 = hcat(chain1, chain2)
            @test isequal(AbstractMCMC.chainscat(chain1, chain2), chain12)
            @test isequal(AbstractMCMC.chainsstack([chain1, chain2]), chain12)
            chain123 = hcat(chain1, chain2, chain3)
            @test isequal(AbstractMCMC.chainscat(chain1, chain2, chain3), chain123)
            @test isequal(AbstractMCMC.chainsstack([chain1, chain2, chain3]), chain123)
        end
    end

    @testset "map_keys" begin
        N_iters = 10
        dicts = fill(
            OrderedDict(Parameter(:a) => 1, Parameter(:b) => 2, Extra("hello") => 3.0),
            N_iters,
        )
        chain = FlexiChain{Symbol}(N_iters, 1, dicts)

        @testset "trivial identity mapping" begin
            idchain = FlexiChains.map_keys(identity, chain)
            @test idchain isa FlexiChain{Symbol}
            @test isequal(chain, idchain)
            @test collect(keys(idchain)) == collect(keys(chain))
        end

        @testset "a working mapping" begin
            g(s::Parameter{Symbol}) = Parameter(String(s.name))
            g(e::Extra) = Extra(Symbol(e.name))
            gchain = FlexiChains.map_keys(g, chain)
            @test gchain isa FlexiChain{String}
            # this checks that the order of keys is preserved
            @test collect(keys(gchain)) == [Parameter("a"), Parameter("b"), Extra(:hello)]
            @test gchain[Parameter("a")] == chain[Parameter(:a)]
            @test gchain[Parameter("b")] == chain[Parameter(:b)]
            @test gchain[Extra(:hello)] == chain[Extra("hello")]
        end

        @testset "bad function output" begin
            # Doesn't return a valid key
            h(::Any) = 1
            @test_throws ArgumentError FlexiChains.map_keys(h, chain)
            # Returns duplicate keys
            j(::Any) = Parameter(:hello)
            @test_throws ArgumentError FlexiChains.map_keys(j, chain)
        end
    end

    @testset "map_parameters" begin
        N_iters = 10
        dicts = fill(
            OrderedDict(Parameter(:a) => 1, Parameter(:b) => 2, Extra("hello") => 3.0),
            N_iters,
        )
        chain = FlexiChain{Symbol}(N_iters, 1, dicts)

        @testset "trivial identity mapping" begin
            idchain = FlexiChains.map_parameters(identity, chain)
            @test idchain isa FlexiChain{Symbol}
            @test isequal(chain, idchain)
            @test collect(keys(idchain)) == collect(keys(chain))
        end

        @testset "a working mapping" begin
            gchain = FlexiChains.map_parameters(String, chain)
            @test gchain isa FlexiChain{String}
            # this checks that the order of keys is preserved
            @test collect(keys(gchain)) == [Parameter("a"), Parameter("b"), Extra("hello")]
            @test gchain[Parameter("a")] == chain[Parameter(:a)]
            @test gchain[Parameter("b")] == chain[Parameter(:b)]
            @test gchain[Extra("hello")] == chain[Extra("hello")]
        end

        @testset "bad function output" begin
            # Doesn't return a valid key
            h(::Any) = 1
            @test_throws ArgumentError FlexiChains.map_keys(h, chain)
            # Returns duplicate keys
            j(::Any) = Parameter(:hello)
            @test_throws ArgumentError FlexiChains.map_keys(j, chain)
        end
    end

    @testset "rand" begin
        N_iters, N_chains = 10, 3
        d = Dict(Parameter(:a) => 1, Parameter(:b) => 2.0, Extra("lp") => -3.0)
        chn = FlexiChain{Symbol}(N_iters, N_chains, fill(d, N_iters, N_chains))
        rng = Xoshiro(468)

        # Test with and without rng
        for args in ((rng,), ())
            @test rand(args..., chn) isa OrderedDict{ParameterOrExtra{<:Symbol}}
            @test rand(args..., chn; parameters_only=true) isa OrderedDict{Symbol}
            @test rand(args..., chn, 5) isa
                  Vector{<:OrderedDict{ParameterOrExtra{<:Symbol}}}
            @test size(rand(args..., chn, 5)) == (5,)
            @test rand(args..., chn, 3, 4) isa
                  Matrix{<:OrderedDict{ParameterOrExtra{<:Symbol}}}
            @test size(rand(args..., chn, 3, 4)) == (3, 4)
        end

        @testset "reproducibility" begin
            @test rand(Xoshiro(468), chn) == rand(Xoshiro(468), chn)
            @test rand(Xoshiro(468), chn, 2) == rand(Xoshiro(468), chn, 2)
        end
    end

    @testset "transform_values" begin
        Ni, Nc = 10, 3
        a_vals = rand(Ni, Nc)
        b_vals = rand(Ni, Nc)
        d = OrderedDict(Parameter(@varname(a)) => a_vals, Parameter(@varname(b)) => b_vals)
        chn = FlexiChain{VarName}(Ni, Nc, d)

        @test FlexiChains.has_same_data(transform_values(chn), chn)
        @test_throws ArgumentError transform_values(chn, :wut)

        incr(x) = x + 1
        dbl(x) = x * 2

        @testset "k => f" begin
            for k in (:a, @varname(a), Parameter(@varname(a)))
                chn2 = transform_values(chn, k => incr)
                @test chn[@varname(a)] == a_vals # Original chain unchanged.
                @test chn2[@varname(a)] == chn[@varname(a)] .+ 1
            end
        end

        @testset "multiple args" begin
            chn2 = transform_values(chn, :a => incr, :b => dbl)
            @test chn2[@varname(a)] == chn[@varname(a)] .+ 1
            @test chn2[@varname(b)] == chn[@varname(b)] .* 2
        end

        @testset "k => f => newk" begin
            for outk in (@varname(aplus1), Parameter(@varname(aplus1)), Extra(:ap1))
                chn2 = transform_values(chn, :a => incr => outk)
                @test chn2[outk] == chn[@varname(a)] .+ 1
                @test chn2[@varname(a)] == chn[@varname(a)]
            end

            # Invalid key
            @test_throws ArgumentError transform_values(chn, :a => incr => 1)
        end

        @testset "functions with arity > 1" begin
            chn2 = transform_values(chn, [:a, :b] => (+) => @varname(sum_ab))
            @test chn2[@varname(sum_ab)] == chn[@varname(a)] .+ chn[@varname(b)]
            @test chn2[@varname(a)] == chn[@varname(a)]
            @test chn2[@varname(b)] == chn[@varname(b)]

            # Must specify output key
            @test_throws ArgumentError transform_values(chn, [:a, :b] => (+))
        end

        @testset "DimVector use case" begin
            Ni, Nc = 10, 3
            cs = [randn(2) for _ in 1:Ni, _ in 1:Nc]
            d = OrderedDict(Parameter(:x) => cs)
            chn = FlexiChain{Symbol}(Ni, Nc, d)

            f(v) = DimArray(v, DD.Dim{:whatever}([:a, :b]))
            chn2 = transform_values(chn, :x => f)
            @test chn2[:x, stack=true] isa DD.DimArray{Float64,3}
            @test DD.name.(DD.dims(chn2[:x, stack=true])) == (:iter, :chain, :whatever)
        end
    end
end

end # module
