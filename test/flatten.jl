module FCFlattenTests

using FlexiChains:
    FlexiChains,
    FlexiChain,
    FlexiSummary,
    Parameter,
    Extra,
    Wide,
    Long,
    VarName,
    @varname,
    iter_indices,
    chain_indices,
    stat_indices,
    summarystats
using DataFrames: DataFrame, names, nrow, ncol
using DimensionalData: DimensionalData as DD, val, At
using OrderedCollections: OrderedDict
using Statistics: mean, std
using Test
using FlexiChains: Tables

@testset verbose = true "flatten.jl" begin
    @info "Testing flatten.jl"

    @testset "Array conversion" begin
        @testset "basic test case" begin
            N_iters, N_chains = 10, 2
            d = OrderedDict(Parameter(:a) => 1.0, Parameter(:b) => 2.0, Extra(:lp) => -3.0)
            chain = FlexiChain{Symbol}(N_iters, N_chains, fill(d, N_iters, N_chains))

            @testset "parameters_only=true (default)" begin
                da = DD.DimArray(chain; warn=false)
                @test da isa DD.DimArray{Float64,3}
                @test size(da) == (N_iters, N_chains, 2)
                @test val(DD.dims(da, :iter)) == val(iter_indices(chain))
                @test val(DD.dims(da, :chain)) == val(chain_indices(chain))
                @test all(x -> x == 1.0, da[:, :, At(:a)])
                @test all(x -> x == 2.0, da[:, :, At(:b)])
                param_keys = collect(val(DD.dims(da, :param)))
                @test param_keys == [:a, :b]
            end

            @testset "parameters_only=false" begin
                da_all = DD.DimArray(chain; parameters_only=false, warn=false)
                @test da_all isa DD.DimArray{Float64,3}
                @test size(da_all) == (N_iters, N_chains, 3)
                @test val(DD.dims(da_all, :iter)) == val(iter_indices(chain))
                @test val(DD.dims(da_all, :chain)) == val(chain_indices(chain))
                @test all(x -> x == 1.0, da_all[:, :, At(Parameter(:a))])
                @test all(x -> x == 2.0, da_all[:, :, At(Parameter(:b))])
                @test all(x -> x == -3.0, da_all[:, :, At(Extra(:lp))])
                param_keys = collect(val(DD.dims(da_all, :param)))
                @test param_keys == [Parameter(:a), Parameter(:b), Extra(:lp)]
            end

            @testset "Base.Array instead of DimArray" begin
                arr = Array(chain; warn=false)
                @test arr isa Array{Float64,3}
                @test size(arr) == (N_iters, N_chains, 2)
                @test all(x -> x == 1.0, arr[:, :, 1])
                @test all(x -> x == 2.0, arr[:, :, 2])
            end
        end

        @testset "avoid over-concretisation of eltype" begin
            N_iters, N_chains = 10, 2
            d = OrderedDict(Parameter(:a) => 1.0, Parameter(:b) => false)
            chain = FlexiChain{Symbol}(N_iters, N_chains, fill(d, N_iters, N_chains))
            da = DD.DimArray(chain; warn=false)
            @test eltype(da) == Real
            @test eltype(map(identity, da[param=1])) == Float64
            @test eltype(map(identity, da[param=2])) == Bool
        end

        @testset "VarName-keyed chain with array-valued param" begin
            N_iters, N_chains = 8, 1
            d = OrderedDict(
                Parameter(@varname(a)) => 1.0,
                Parameter(@varname(b)) => [2.0, 3.0],
            )
            chain = FlexiChain{VarName}(N_iters, N_chains, fill(d, N_iters))
            da = DD.DimArray(chain; warn=false)
            @test size(da) == (N_iters, N_chains, 3)
            param_keys = collect(val(DD.dims(da, :param)))
            @test param_keys == [@varname(a), @varname(b[1]), @varname(b[2])]

            @testset "split_varnames=false" begin
                da2 = DD.DimArray(chain; split_varnames=false, warn=false)
                @test size(da2) == (N_iters, N_chains, 2)
                param_keys2 = collect(val(DD.dims(da2, :param)))
                @test param_keys2 == [@varname(a), @varname(b)]
                @test all(x -> x == 1.0, da2[:, :, At(@varname(a))])
                @test all(x -> x == [2.0, 3.0], da2[:, :, At(@varname(b))])
            end
        end

        @testset "eltype_filter" begin
            N_iters = 5
            d = OrderedDict(
                Parameter(:a) => 1.0,
                Parameter(:b) => "hello",
                Extra(:lp) => -1.0,
            )
            chain = FlexiChain{Symbol}(N_iters, 1, fill(d, N_iters))
            da = DD.DimArray(chain; eltype_filter=Float64, warn=false)
            param_keys = collect(val(DD.dims(da, :param)))
            @test param_keys == [:a]
        end

        @testset "warns about skipped keys" begin
            N_iters = 5
            d = OrderedDict(Parameter(:a) => 1.0, Parameter(:b) => "hello")
            chain = FlexiChain{Symbol}(N_iters, 1, fill(d, N_iters))
            @test_logs (:warn, r"skipping.*b") DD.DimArray(chain; eltype_filter=Float64)
        end

        @testset "warn=false suppresses warnings" begin
            N_iters = 5
            d = OrderedDict(Parameter(:a) => 1.0, Parameter(:b) => "hello")
            chain = FlexiChain{Symbol}(N_iters, 1, fill(d, N_iters))
            @test_logs DD.DimArray(chain; eltype_filter=Float64, warn=false)
        end

        @testset "empty DimArray when no keys match" begin
            N_iters = 5
            d = OrderedDict(Parameter(:a) => "hello")
            chain = FlexiChain{Symbol}(N_iters, 1, fill(d, N_iters))
            da = @test_logs (:warn,) (:warn, r"no keys") DD.DimArray(
                chain;
                eltype_filter=Float64,
            )
            @test da isa DD.DimArray{Float64,3}
            @test size(da) == (N_iters, 1, 0)
        end

        @testset "String-keyed chain" begin
            N_iters = 5
            d = OrderedDict(Parameter("a") => 1.0, Parameter("b") => [2.0, 3.0])
            chain = FlexiChain{String}(N_iters, 1, fill(d, N_iters))
            da = DD.DimArray(chain; warn=false)
            @test size(da) == (N_iters, 1, 3)
            param_keys = collect(val(DD.dims(da, :param)))
            @test param_keys == ["a", "b[1]", "b[2]"]
        end
    end

    @testset "Summary Array conversion" begin
        N_iters, N_chains = 10, 2
        as = rand(N_iters, N_chains)
        bs = rand(1:100, N_iters, N_chains)
        d = OrderedDict(
            Parameter(:a) => as,
            Parameter(:b) => bs,
            Extra(:lp) => -rand(N_iters, N_chains),
        )
        chain = FlexiChain{Symbol}(N_iters, N_chains, d)

        @testset "basic interface" begin
            fs = FlexiChains.collapse(chain, [mean, std]; dims=:both)
            da = DD.DimArray(fs; warn=false)
            @test da isa DD.DimMatrix
            @test collect(val(DD.dims(da, :param))) == [:a, :b]
            arr = Array(fs; warn=false)
            @test arr isa Matrix
            @test size(arr) == size(da)

            @testset "parameters_only=false" begin
                da_all = DD.DimArray(fs; parameters_only=false, warn=false)
                @test collect(val(DD.dims(da_all, :param))) ==
                      [Parameter(:a), Parameter(:b), Extra(:lp)]
            end

            @testset "warn kwarg" begin
                d2 = OrderedDict(
                    Parameter(:a) => rand(5, 1),
                    Parameter(:b) => fill("hello", 5, 1),
                )
                c2 = FlexiChain{Symbol}(5, 1, d2)
                fs2 = minimum(c2)
                da2 = DD.DimArray(fs2; eltype_filter=Float64, warn=false)
                @test collect(val(DD.dims(da2, :param))) == [:a]
                @test_logs (:warn, r"skipping.*b") DD.DimArray(fs2; eltype_filter=Float64)
                @test_logs DD.DimArray(fs2; eltype_filter=Float64, warn=false)
            end
        end

        @testset "VarName-keyed summary with array-valued param" begin
            d = OrderedDict(
                Parameter(@varname(a)) => 1.0,
                Parameter(@varname(b)) => [2.0, 3.0],
            )
            vn_chain = FlexiChain{VarName}(8, 1, fill(d, 8))
            vn_summary = mean(vn_chain; split_varnames=false)

            da = DD.DimArray(vn_summary; warn=false)
            @test size(da) == (3,)  # stat only
            param_keys = collect(val(DD.dims(da, :param)))
            @test param_keys == [@varname(a), @varname(b[1]), @varname(b[2])]

            @testset "split_varnames=false" begin
                da2 = DD.DimArray(vn_summary; split_varnames=false, warn=false)
                @test size(da2) == (2,) # stat only
                param_keys2 = collect(val(DD.dims(da2, :param)))
                @test param_keys2 == [@varname(a), @varname(b)]
                @test da2[At(@varname(a))] ≈ 1.0
                @test da2[At(@varname(b))] ≈ [2.0, 3.0]
            end
        end

        @testset "dims=:both" begin
            fs = FlexiChains.collapse(chain, [mean, std]; dims=:both)
            da = DD.DimArray(fs; warn=false)
            @test size(da) == (2, 2)  # (stat, param)
            @test val(DD.dims(da, :stat)) == [:mean, :std]
            @test da[At(:mean), At(:a)] ≈ mean(as)
            @test da[At(:std), At(:a)] ≈ std(as[:])
        end

        @testset ":param only" begin
            fs = mean(chain)
            da = DD.DimArray(fs)
            @test da isa DD.DimVector
            @test DD.name(DD.dims(da)) == (FlexiChains.PARAM_DIM_NAME,)
            @test size(da) == (2,)
            @test da[At(:a)] ≈ mean(as)
            @test da[At(:b)] ≈ mean(bs)

            a = Array(fs)
            @test a isa Vector
            @test size(a) == (2,)
            @test a[1] ≈ mean(as)
            @test a[2] ≈ mean(bs)
        end

        @testset ":chain, :stat, :param" begin
            fs = FlexiChains.collapse(chain, [mean, std]; dims=:iter)
            da = DD.DimArray(fs)
            @test DD.name(DD.dims(da)) == (
                FlexiChains.CHAIN_DIM_NAME,
                FlexiChains.STAT_DIM_NAME,
                FlexiChains.PARAM_DIM_NAME,
            )
            @test size(da) == (N_chains, 2, 2)
            @test val(DD.dims(da, :chain)) == val(chain_indices(chain))
            @test val(DD.dims(da, :stat)) == [:mean, :std]
            @test da[:, At(:mean), At(:a)] ≈ vec(mean(as; dims=1))
        end

        @testset ":iter, :stat, :param" begin
            fs = FlexiChains.collapse(chain, [mean, std]; dims=:chain)
            da = DD.DimArray(fs)
            @test DD.name(DD.dims(da)) == (
                FlexiChains.ITER_DIM_NAME,
                FlexiChains.STAT_DIM_NAME,
                FlexiChains.PARAM_DIM_NAME,
            )
            @test size(da) == (N_iters, 2, 2)
            @test val(DD.dims(da, :iter)) == val(iter_indices(chain))
            @test val(DD.dims(da, :stat)) == [:mean, :std]
            @test da[:, At(:mean), At(:a)] ≈ vec(mean(as; dims=2))
        end

        @testset ":chain, :param" begin
            fs = mean(chain; dims=:iter)
            da = DD.DimArray(fs)
            @test DD.name(DD.dims(da)) ==
                  (FlexiChains.CHAIN_DIM_NAME, FlexiChains.PARAM_DIM_NAME)
            @test da isa DD.DimMatrix
            @test size(da) == (N_chains, 2)
            @test val(DD.dims(da, :chain)) == val(chain_indices(chain))
            @test da[:, At(:a)] ≈ vec(mean(as; dims=1))
        end

        @testset ":iter, :param" begin
            fs = mean(chain; dims=:chain)
            da = DD.DimArray(fs)
            @test DD.name(DD.dims(da)) ==
                  (FlexiChains.ITER_DIM_NAME, FlexiChains.PARAM_DIM_NAME)
            @test da isa DD.DimMatrix
            @test size(da) == (N_iters, 2)
            @test val(DD.dims(da, :iter)) == val(iter_indices(chain))
            @test da[:, At(:a)] ≈ vec(mean(as; dims=2))
        end

        @testset "VarName-keyed with array-valued param" begin
            d_vn = OrderedDict(
                Parameter(@varname(a)) => 1.0,
                Parameter(@varname(b)) => [2.0, 3.0],
            )
            vn_chain = FlexiChain{VarName}(8, 1, fill(d_vn, 8))
            fs = mean(vn_chain)
            da = DD.DimArray(fs)
            @test size(da) == (3,)
            @test DD.name(DD.dims(da)) == (FlexiChains.PARAM_DIM_NAME,)
            param_keys = collect(val(DD.dims(da, :param)))
            @test param_keys == [@varname(a), @varname(b[1]), @varname(b[2])]
        end
    end

    @testset "Tables.jl interface" begin
        N_iters, N_chains = 10, 2
        d = OrderedDict(Parameter(:a) => 1.0, Parameter(:b) => false, Extra(:lp) => -3.0)
        chain = FlexiChain{Symbol}(N_iters, N_chains, fill(d, N_iters, N_chains))

        @testset "Wide" begin
            @testset "default (parameters_only=true, split_varnames=true)" begin
                df = DataFrame(Wide(chain))
                @test nrow(df) == N_iters * N_chains
                @test names(df) == ["iter", "chain", "a", "b"]
                @test df.iter == repeat(1:N_iters; outer=N_chains)
                @test df.chain == repeat(1:N_chains; inner=N_iters)
                @test all(df.a .== 1.0)
                @test all(df.b .== false)
            end

            @testset "parameters_only=false" begin
                df = DataFrame(Wide(chain; parameters_only=false))
                @test names(df) == ["iter", "chain", "a", "b", "lp"]
                @test all(df.lp .== -3.0)
            end
        end

        @testset "Long" begin
            @testset "default (parameters_only=true, split_varnames=true)" begin
                df = DataFrame(Long(chain))
                @test nrow(df) == N_iters * N_chains * 2
                @test names(df) == ["iter", "chain", "param", "value"]
                @test df.param == repeat([:a, :b]; inner=N_iters * N_chains)
                @test df.iter == repeat(1:N_iters; outer=N_chains * 2)
                @test df.chain == repeat(1:N_chains; inner=N_iters, outer=2)
                a_rows = df.param .== :a
                b_rows = df.param .== :b
                @test all(df.value[a_rows] .== 1.0)
                @test all(df.value[b_rows] .== 0.0)
            end

            @testset "parameters_only=false" begin
                df = DataFrame(Long(chain; parameters_only=false))
                @test nrow(df) == N_iters * N_chains * 3
                @test Extra(:lp) in df.param
            end
        end

        @testset "FlexiChain directly as table source" begin
            df = DataFrame(chain)
            df_wide = DataFrame(Wide(chain))
            @test names(df) == names(df_wide)
            @test nrow(df) == nrow(df_wide)
            for col in names(df)
                @test df[!, col] == df_wide[!, col]
            end
        end

        @testset "VarName-keyed chain with array-valued param" begin
            d_vn = OrderedDict(
                Parameter(@varname(a)) => 1.0,
                Parameter(@varname(b)) => [2.0, 3.0],
            )
            vn_chain = FlexiChain{VarName}(N_iters, N_chains, fill(d_vn, N_iters, N_chains))

            @testset "Wide" begin
                df = DataFrame(Wide(vn_chain))
                @test names(df) == ["iter", "chain", "a", "b[1]", "b[2]"]
                @test all(df[!, "a"] .== 1.0)
                @test all(df[!, "b[1]"] .== 2.0)
                @test all(df[!, "b[2]"] .== 3.0)
            end

            @testset "split_varnames=false" begin
                df = DataFrame(Wide(vn_chain; split_varnames=false))
                @test names(df) == ["iter", "chain", "a", "b"]
                @test all(df[!, "a"] .== 1.0)
                @test all(x -> x == [2.0, 3.0], df[!, "b"])
            end
        end

        @testset "duplicate column names error" begin
            d_dup = OrderedDict(Parameter("s") => 1.0, Extra(:s) => 2.0)
            dup_chain = FlexiChain{Any}(5, 1, fill(d_dup, 5))
            @test_throws ArgumentError Wide(dup_chain; parameters_only=false)
            # Long preserves original keys, so Parameter("s") and Extra(:s) are distinct
            df = DataFrame(Long(dup_chain; parameters_only=false))
            @test nrow(df) == 5 * 1 * 2
        end

        @testset "Wide summary" begin
            N_iters, N_chains = 10, 2
            as = rand(N_iters, N_chains)
            bs = rand(N_iters, N_chains)
            d_summary = OrderedDict(
                Parameter(:a) => as,
                Parameter(:b) => bs,
                Extra(:lp) => -rand(N_iters, N_chains),
            )
            sc = FlexiChain{Symbol}(N_iters, N_chains, d_summary)

            @testset "mean(chain) — all dims collapsed, single stat" begin
                fs = mean(sc)
                df = DataFrame(Wide(fs))
                @test nrow(df) == 2
                @test names(df) == ["param", "stat"]
                @test df.param == [:a, :b]
                for row in eachrow(df)
                    @test row.stat ≈ fs[row.param]
                end
            end

            @testset "mean(chain; dims=:iter) — chain dim retained, single stat" begin
                fs = mean(sc; dims=:iter)
                df = DataFrame(Wide(fs))
                @test nrow(df) == 2 * N_chains
                @test names(df) == ["param", "chain", "stat"]
                @test df.param == repeat([:a, :b]; inner=N_chains)
                @test df.chain == repeat(1:N_chains; outer=2)
                for row in eachrow(df)
                    @test row.stat ≈ fs[row.param, chain=At(row.chain)]
                end
            end

            @testset "mean(chain; dims=:chain) — iter dim retained, single stat" begin
                fs = mean(sc; dims=:chain)
                df = DataFrame(Wide(fs))
                @test nrow(df) == 2 * N_iters
                @test names(df) == ["param", "iter", "stat"]
                @test df.param == repeat([:a, :b]; inner=N_iters)
                @test df.iter == repeat(1:N_iters; outer=2)
                for row in eachrow(df)
                    @test row.stat ≈ fs[row.param, iter=At(row.iter)]
                end
            end

            @testset "collapse(chain, [mean, std]; dims=:both) — named stat cols" begin
                fs = FlexiChains.collapse(sc, [mean, std]; dims=:both)
                df = DataFrame(Wide(fs))
                @test nrow(df) == 2
                @test names(df) == ["param", "mean", "std"]
                @test df.param == [:a, :b]
                for row in eachrow(df)
                    for stat_name in [:mean, :std]
                        @test row[stat_name] ≈ fs[row.param, stat=At(stat_name)]
                    end
                end
            end

            @testset "collapse(chain, [mean, std]; dims=:iter) — chain + named stats" begin
                fs = FlexiChains.collapse(sc, [mean, std]; dims=:iter)
                df = DataFrame(Wide(fs))
                @test nrow(df) == 2 * N_chains
                @test names(df) == ["param", "chain", "mean", "std"]
                @test df.param == repeat([:a, :b]; inner=N_chains)
                @test df.chain == repeat(1:N_chains; outer=2)
                for row in eachrow(df)
                    for stat_name in [:mean, :std]
                        @test row[stat_name] ≈
                              fs[row.param, stat=At(stat_name), chain=At(row.chain)]
                    end
                end
            end

            @testset "FlexiSummary directly as table source" begin
                fs = FlexiChains.collapse(sc, [mean, std]; dims=:both)
                df = DataFrame(fs)
                df_wide = DataFrame(Wide(fs))
                @test names(df) == names(df_wide)
                @test nrow(df) == nrow(df_wide)
                for col in names(df)
                    @test df[!, col] == df_wide[!, col]
                end
            end

            @testset "parameters_only=false includes extras" begin
                fs = mean(sc)
                df = DataFrame(Wide(fs; parameters_only=false))
                @test nrow(df) == 3
                @test Extra(:lp) in df.param
            end

            @testset "VarName-keyed summary with array-valued param" begin
                d_vn = OrderedDict(
                    Parameter(@varname(a)) => 1.0,
                    Parameter(@varname(b)) => [2.0, 3.0],
                )
                vn_chain =
                    FlexiChain{VarName}(N_iters, N_chains, fill(d_vn, N_iters, N_chains))
                fs = mean(vn_chain; split_varnames=false)

                @testset "split_varnames=true" begin
                    df = DataFrame(Wide(fs; split_varnames=true))
                    @test nrow(df) == 3
                    @test names(df) == ["param", "stat"]
                    for row in eachrow(df)
                        @test row.stat ≈ fs[row.param]
                    end
                end
                @testset "split_varnames=false" begin
                    df = DataFrame(Wide(fs; split_varnames=false))
                    @test nrow(df) == 2
                    @test names(df) == ["param", "stat"]
                    for row in eachrow(df)
                        @test row.stat ≈ fs[row.param]
                    end
                end
            end
        end
    end
end

end # module
