module FCVarNameTests

using FlexiChains:
    FlexiChains, FlexiChain, FlexiSummary, Parameter, Extra, VarName, @varname, Prefixed
using VarNames: Iden, @opticof
using DimensionalData: DimensionalData as DD
using OrderedCollections: OrderedDict
using Statistics: mean
using Test

@testset verbose = true "varname.jl" begin
    @info "Testing varname.jl"

    @testset "basic VarName getindex" begin
        N_iters = 10
        d = Dict(
            Parameter(@varname(a)) => 1.0,
            Parameter(@varname(b)) => [2.0, 3.0],
            Parameter(@varname(c)) => (x=4.0, y=5.0),
        )
        chain = FlexiChain{VarName}(N_iters, 1, fill(d, N_iters))

        @testset "ordinary VarName" begin
            @test chain[@varname(a)] == fill(1.0, N_iters, 1)
            @test chain[@varname(b)] == fill([2.0, 3.0], N_iters, 1)
            @test chain[@varname(c)] == fill((x=4.0, y=5.0), N_iters, 1)
            @test_throws KeyError chain[@varname(d)]
            @test chain[@varname(b[1])] == fill(2.0, N_iters, 1)
            @test chain[@varname(b[2])] == fill(3.0, N_iters, 1)
            @test_throws KeyError chain[@varname(b[3])]
            @test chain[@varname(c.x)] == fill(4.0, N_iters, 1)
            @test chain[@varname(c.y)] == fill(5.0, N_iters, 1)
            @test_throws KeyError chain[@varname(c.z)]
        end

        @testset "using Symbol" begin
            @test chain[:a] == fill(1.0, N_iters, 1)
            @test chain[:b] == fill([2.0, 3.0], N_iters, 1)
            @test chain[:c] == fill((x=4.0, y=5.0), N_iters, 1)
            @test_throws KeyError chain[:d]
            # If you want to do fancy sub-indexing you had better use VarNames
            @test_throws KeyError chain[Symbol("b[1]")]
        end

        @testset "multiple keys" begin
            cs = chain[[@varname(a), @varname(b[1]), @varname(c.x)]]
            @test cs isa FlexiChain{VarName}
        end

        @testset "ragged data e.g. vectors of different lengths" begin
            # The first sample of `a` has `a[1]` only, but the second has
            # both `a[1]` and `a[2]`
            d = Dict(Parameter(@varname(a)) => [[1.0], [2.0, 3.0]])
            chn = FlexiChain{VarName}(2, 1, d; iter_indices=[6, 7])
            @test chn[@varname(a)] == reshape([[1.0], [2.0, 3.0]], 2, 1)
            @test chn[@varname(a[1])] == reshape([1.0, 2.0], 2, 1)
            # when indexing into `a[2]` we should get a `missing` for the first sample
            @test isequal(chn[@varname(a[2])], reshape([missing, 3.0], 2, 1))
            # and if we try to get `a[3]` we should get an error
            @test_throws KeyError chn[@varname(a[3])]

            # For good measure we'll throw in some iter subsetting too
            @test chn[@varname(a), iter=2] == [[2.0, 3.0]]
            @test chn[@varname(a[1]), iter=2] == [2.0]
            @test isequal(chn[@varname(a[2]), iter=1], [missing])
            @test chn[@varname(a[2]), iter=2] == [3.0]
            @test_throws KeyError chn[@varname(a[3]), iter=2]
            @test chn[@varname(a), iter=DD.At(7)] == [[2.0, 3.0]]
            @test chn[@varname(a[1]), iter=DD.At(7)] == [2.0]
            @test isequal(chn[@varname(a[2]), iter=1], [missing])
            @test chn[@varname(a[2]), iter=DD.At(7)] == [3.0]
            @test_throws KeyError chn[@varname(a[3]), iter=DD.At(7)]
            # and chain
            @test chn[@varname(a), chain=1] == [[1.0], [2.0, 3.0]]
            @test chn[@varname(a[1]), chain=1] == [1.0, 2.0]
            @test isequal(chn[@varname(a[2]), chain=1], [missing, 3.0])
            @test_throws KeyError chn[@varname(a[3]), chain=1]
        end
    end

    @testset "split_varnames" begin
        @testset "TKey = VarName" begin
            N_iters = 10
            # use OrderedDict so that we can also test order
            d = OrderedDict(
                Parameter(@varname(a)) => 1.0,
                Parameter(@varname(c)) => (x=4.0, y=5.0),
                Parameter(@varname(b)) => [2.0, 3.0],
                Extra("hello") => 3.0,
            )
            chain = FlexiChain{VarName}(N_iters, 1, fill(d, N_iters))
            chain2, _ = FlexiChains._split_varnames(chain)
            @test collect(keys(chain2)) == ([
                Parameter(@varname(a)),
                Parameter(@varname(c.x)),
                Parameter(@varname(c.y)),
                Parameter(@varname(b[1])),
                Parameter(@varname(b[2])),
                Extra("hello"),
            ])
        end

        @testset "TKey = Symbol" begin
            N_iters = 10
            # use OrderedDict so that we can also test order
            d = OrderedDict(
                Parameter(:a) => 1.0,
                Parameter(:c) => (x=4.0, y=5.0),
                Parameter(:b) => [2.0, 3.0],
                Extra("hello") => 3.0,
            )
            chain = FlexiChain{Symbol}(N_iters, 1, fill(d, N_iters))
            chain2, _ = FlexiChains._split_varnames(chain)
            @test collect(keys(chain2)) == ([
                Parameter(:a),
                Parameter(Symbol("c.x")),
                Parameter(Symbol("c.y")),
                Parameter(Symbol("b[1]")),
                Parameter(Symbol("b[2]")),
                Extra("hello"),
            ])
        end

        @testset "TKey = String" begin
            N_iters = 10
            # use OrderedDict so that we can also test order
            d = OrderedDict(
                Parameter("a") => 1.0,
                Parameter("c") => (x=4.0, y=5.0),
                Parameter("b") => [2.0, 3.0],
                Extra("hello") => 3.0,
            )
            chain = FlexiChain{String}(N_iters, 1, fill(d, N_iters))
            chain2, _ = FlexiChains._split_varnames(chain)
            @test collect(keys(chain2)) == ([
                Parameter("a"),
                Parameter("c.x"),
                Parameter("c.y"),
                Parameter("b[1]"),
                Parameter("b[2]"),
                Extra("hello"),
            ])
        end

        @testset "other unsupported keys" begin
            N_iters = 10
            # just a dummy wrapper
            struct K
                k::Symbol
            end

            @testset "if everything is already scalar" begin
                # Should be a no-op
                d = OrderedDict(
                    Parameter(K(:a)) => 1.0,
                    Parameter(K(:b)) => 2.0,
                    Extra("hello") => 3.0,
                )
                chain = FlexiChain{K}(N_iters, 1, fill(d, N_iters))
                split_chain, _ = FlexiChains._split_varnames(chain)
                @test isequal(split_chain, chain)
                # check order of keys are unchanged
                @test collect(keys(split_chain)) == collect(keys(chain))
            end

            @testset "if there are non-scalar values" begin
                d = OrderedDict(Parameter(K(:b)) => [2.0, 3.0])
                chain = FlexiChain{K}(N_iters, 1, fill(d, N_iters))
                @test_throws ArgumentError FlexiChains._split_varnames(chain)
            end
        end
    end


    @testset "Prefixed" begin
        @testset "construction" begin
            for vn in (@varname(x), @varname(x[1]), @varname(x.a))
                p = Prefixed(vn)
                @test p.target_vn == vn
            end
            # construction from Symbol
            @test Prefixed(:y) == Prefixed(@varname(y))
        end

        @testset "show" begin
            @test sprint(show, Prefixed(@varname(x))) == "Prefixed(x)"
            @test sprint(show, Prefixed(:y)) == "Prefixed(y)"
            @test sprint(show, Prefixed(@varname(x[1]))) == "Prefixed(x[1])"
            @test sprint(show, Prefixed(@varname(x.a))) == "Prefixed(x.a)"
        end

        @testset "shares_tail" begin
            st = FlexiChains.shares_tail

            @testset "exact match (no prefix)" begin
                @test st(@varname(x), @varname(x))
                @test !st(@varname(x), @varname(y))
            end

            @testset "single prefix" begin
                @test st(@varname(a.x), @varname(x))
                @test !st(@varname(a.x), @varname(y))
            end

            @testset "multiple prefixes" begin
                @test st(@varname(a.b.c), @varname(c))
                @test st(@varname(a.b.c), @varname(b.c))
                @test st(@varname(a.b.c), @varname(a.b.c))
                @test !st(@varname(a.b.c), @varname(d))
            end

            @testset "target longer than vn" begin
                @test !st(@varname(x), @varname(a.x))
                @test !st(@varname(b.c), @varname(a.b.c))
            end

            @testset "with indexing optics" begin
                @test st(@varname(a.x[1]), @varname(x[1]))
                @test !st(@varname(a.x[1]), @varname(x))
                @test !st(@varname(a.x[1]), @varname(x[2]))
            end
        end

        @testset "prefixed_get_key_and_optic" begin
            pgko = FlexiChains.prefixed_get_key_and_optic

            @testset "simple match with prefix" begin
                vns = Set([@varname(a.x), @varname(a.y), @varname(b)])
                k, o = pgko(vns, Prefixed(@varname(x)))
                @test k == @varname(a.x)
                @test o == Iden()
            end

            @testset "exact match (no prefix)" begin
                vns = Set([@varname(a.x), @varname(b)])
                k, o = pgko(vns, Prefixed(@varname(b)))
                @test k == @varname(b)
                @test o == Iden()
            end

            @testset "no match throws KeyError" begin
                vns = Set([@varname(a.x), @varname(b)])
                @test_throws KeyError pgko(vns, Prefixed(@varname(z)))
            end

            @testset "multiple matches throws ArgumentError" begin
                vns = Set([@varname(a.x), @varname(b.x)])
                @test_throws ArgumentError pgko(vns, Prefixed(@varname(x)))
            end

            @testset "optic stripping" begin
                # Prefixed(@varname(x.b)) with chain containing @varname(a.x)
                # should find @varname(a.x) with .b optic
                vns = Set([@varname(a.x)])
                k, o = pgko(vns, Prefixed(@varname(x.b)))
                @test k == @varname(a.x)
                @test o == @opticof(_.b)

                k, o = pgko(vns, Prefixed(@varname(x[1])))
                @test k == @varname(a.x)
                @test o == @opticof(_[1])
            end

            @testset "optic stripping, no match after full strip" begin
                vns = Set([@varname(a.y)])
                @test_throws KeyError pgko(vns, Prefixed(@varname(x.b)))
            end
        end

        @testset "getindex with Prefixed" begin
            N_iters, N_chains = 5, 2

            @testset "FlexiChain" begin
                d = Dict(
                    Parameter(@varname(a.x)) => 1.0,
                    Parameter(@varname(a.y)) => [2.0, 3.0],
                    Parameter(@varname(b)) => 10.0,
                    Parameter(@varname(m.p)) => (; q=20.0),
                )
                chain = FlexiChain{VarName}(N_iters, N_chains, fill(d, N_iters, N_chains))

                @testset "simple prefix match" begin
                    result = chain[Prefixed(:x)]
                    @test result isa DD.DimMatrix
                    @test all(==(1.0), result)
                    @test size(result) == (N_iters, N_chains)
                end

                @testset "no prefix needed" begin
                    result = chain[Prefixed(:b)]
                    @test result isa DD.DimMatrix
                    @test all(==(10.0), result)
                end

                @testset "array-valued parameter" begin
                    result = chain[Prefixed(:y)]
                    @test result isa DD.DimMatrix
                    @test all(==([2.0, 3.0]), result)
                end

                @testset "with suboptic" begin
                    @testset "indexing" begin
                        result = chain[Prefixed(@varname(y[1]))]
                        @test result isa DD.DimMatrix
                        @test all(==(2.0), result)
                    end

                    @testset "field access" begin
                        result = chain[Prefixed(@varname(p.q))]
                        @test result isa DD.DimMatrix
                        @test all(==(20.0), result)
                    end
                end

                @testset "with iter/chain kwargs" begin
                    result = chain[Prefixed(:x), iter=1:2]
                    @test size(result) == (2, N_chains)
                    result2 = chain[Prefixed(:x), chain=1]
                    @test size(result2) == (N_iters,)
                end

                @testset "no match" begin
                    @test_throws KeyError chain[Prefixed(:z)]
                end

                @testset "multiple matches" begin
                    d2 = Dict(
                        Parameter(@varname(a.x)) => 1.0,
                        Parameter(@varname(b.x)) => 2.0,
                    )
                    chain2 = FlexiChain{VarName}(N_iters, 1, fill(d2, N_iters))
                    @test_throws ArgumentError chain2[Prefixed(:x)]
                end
            end

            @testset "FlexiSummary" begin
                d = Dict(
                    Parameter(@varname(a.x)) => 1.0,
                    Parameter(@varname(a.y)) => 2.0,
                    Parameter(@varname(b)) => 10.0,
                )
                chain = FlexiChain{VarName}(N_iters, N_chains, fill(d, N_iters, N_chains))
                fs = mean(chain; dims=:iter)

                @testset "simple prefix match" begin
                    result = fs[Prefixed(:x)]
                    @test all(==(1.0), result)
                end

                @testset "no prefix needed" begin
                    result = fs[Prefixed(:b)]
                    @test all(==(10.0), result)
                end

                @testset "no match" begin
                    @test_throws KeyError fs[Prefixed(:z)]
                end
            end
        end
    end
end

end # module
