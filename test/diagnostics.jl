module FCDiagnosticsTests

using FlexiChains:
    FlexiChains, FlexiChain, FlexiSummary, Parameter, Extra, VarName, @varname, changerate
import DimensionalData as DD
using MCMCDiagnosticTools:
    MCMCDiagnosticTools, gelmandiag, gelmandiag_multivariate, discretediag, bfmi, rstar
using MLJBase: MLJBase, Pipeline, predict_mode
using MLJDecisionTreeInterface: DecisionTreeClassifier
using StableRNGs: StableRNG
using Statistics: mean
using Test

@testset verbose = true "diagnostics.jl" begin
    @info "Testing diagnostics.jl"

    @testset "changerate" begin
        chain = FlexiChain{Symbol}(
            4,
            3,
            Dict(
                Parameter(:x) => [0 1 0; 0 2 0; 0 1 1; 0 2 1],
                Parameter(:label) =>
                    ["a" "b" "c"; "a" "c" "c"; "a" "b" "d"; "a" "c" "d"],
            );
            chain_indices=[2, 4, 6],
        )
        @testset "dims=:iter is per chain" begin
            rates = changerate(chain; dims=:iter)
            @test rates[:x] == [0, 1, 1 / 3]
            @test rates[:label] == [0, 1, 1 / 3]
            @test DD.lookup(rates[:x], :chain) == [2, 4, 6]
        end

        @testset "dims=:both averages over chains" begin
            rates = changerate(chain)
            @test rates[:x] ≈ (0 + 1 + 1 / 3) / 3
            @test rates[:label] ≈ (0 + 1 + 1 / 3) / 3
        end

        @testset "dims=:chain unsupported" begin
            @test_throws ArgumentError changerate(chain; dims=:chain)
        end

        for n in 0:1
            short = FlexiChain{Symbol}(n, 1, Dict(Parameter(:x) => zeros(Int, n, 1)))
            @test isnan(changerate(short; split_varnames=(n > 0))[:x])
            @test isnan(only(changerate(short; dims=:iter, split_varnames=(n > 0))[:x]))
        end

        arrays = FlexiChain{VarName}(
            3,
            1,
            Dict(Parameter(@varname(x)) => reshape([[0, 0], [0, 1], [0, 0]], 3, 1)),
        )
        @test changerate(arrays)[@varname(x[1])] == 0
        @test changerate(arrays)[@varname(x[2])] == 1
        @test changerate(arrays; split_varnames=false)[@varname(x)] == 1
    end

    @testset "gelmandiag" begin
        N_iters, N_chains = 100, 3
        as = randn(N_iters, N_chains)
        bs = randn(N_iters, N_chains)

        @testset "Symbol chain, scalar params" begin
            chain = FlexiChain{Symbol}(
                N_iters,
                N_chains,
                Dict(Parameter(:a) => as, Parameter(:b) => bs),
            )
            gd = gelmandiag(chain)
            @test gd isa FlexiSummary{Symbol}
            @test haskey(gd, Parameter(:a))
            @test haskey(gd, Parameter(:b))
            @test length(gd[:a]) == 2  # psrf and psrfci
            @test all(gd[:a] .> 0)

            # Round-trip: values should match calling MCMCDiagnosticTools directly
            raw = stack([as, bs]; dims=3)
            ref = MCMCDiagnosticTools.gelmandiag(raw)
            @test gd[:a] == [ref.psrf[1], ref.psrfci[1]]
            @test gd[:b] == [ref.psrf[2], ref.psrfci[2]]
        end

        @testset "Symbol chain, array-valued params" begin
            xs = [randn(3) for _ in 1:N_iters, _ in 1:N_chains]
            chain = FlexiChain{Symbol}(
                N_iters,
                N_chains,
                Dict(Parameter(:x) => xs, Parameter(:y) => as),
            )
            gd = gelmandiag(chain)
            @test gd isa FlexiSummary{Symbol}
            @test haskey(gd, Parameter(Symbol("x[1]")))
            @test haskey(gd, Parameter(Symbol("x[2]")))
            @test haskey(gd, Parameter(Symbol("x[3]")))
            @test haskey(gd, Parameter(:y))
        end

        @testset "VarName chain" begin
            xs = [randn(2) for _ in 1:N_iters, _ in 1:N_chains]
            chain = FlexiChain{VarName}(
                N_iters,
                N_chains,
                Dict(Parameter(@varname(x)) => xs, Parameter(@varname(y)) => as),
            )
            gd = gelmandiag(chain)
            @test gd isa FlexiSummary{VarName}
            @test haskey(gd, @varname(x[1]))
            @test haskey(gd, @varname(x[2]))
            @test haskey(gd, @varname(y))
        end

        @testset "non-Real params skipped with warning" begin
            chain = FlexiChain{Symbol}(
                N_iters,
                N_chains,
                Dict(
                    Parameter(:a) => as,
                    Parameter(:str) => fill("hello", N_iters, N_chains),
                ),
            )
            gd = @test_logs (:warn, r"str.*Real") gelmandiag(chain)
            @test haskey(gd, Parameter(:a))
            @test !haskey(gd, Parameter(:str))
            @test_logs gelmandiag(chain; warn=false)
        end

        @testset "errors with single chain" begin
            chain = FlexiChain{Symbol}(N_iters, 1, Dict(Parameter(:a) => randn(N_iters, 1)))
            @test_throws ErrorException gelmandiag(chain)
        end
    end

    @testset "gelmandiag_multivariate" begin
        N_iters, N_chains = 100, 3
        as = randn(N_iters, N_chains)
        bs = randn(N_iters, N_chains)
        chain = FlexiChain{Symbol}(
            N_iters,
            N_chains,
            Dict(Parameter(:a) => as, Parameter(:b) => bs),
        )

        @testset "returns NamedTuple with summary and psrf_multivariate" begin
            gdm = gelmandiag_multivariate(chain)
            @test gdm.summary isa FlexiSummary{Symbol}
            @test gdm.psrf_multivariate isa Float64
            @test gdm.psrf_multivariate > 0
            # per-parameter stats should match gelmandiag
            gd = gelmandiag(chain)
            @test gd[:a] == gdm.summary[:a]
            @test gd[:b] == gdm.summary[:b]
        end

        @testset "errors with single parameter" begin
            chain1 = FlexiChain{Symbol}(N_iters, N_chains, Dict(Parameter(:a) => as))
            @test_throws ErrorException gelmandiag_multivariate(chain1)
        end
    end

    @testset "discretediag" begin
        N_iters, N_chains = 100, 3
        as = rand(1:5, N_iters, N_chains)
        bs = rand(1:3, N_iters, N_chains)

        @testset "Symbol chain, scalar params" begin
            chain = FlexiChain{Symbol}(
                N_iters,
                N_chains,
                Dict(Parameter(:a) => as, Parameter(:b) => bs),
            )
            result = discretediag(chain)
            @test result.between isa FlexiSummary{Symbol}
            @test result.within isa FlexiSummary{Symbol}
            # Between-chain: per-parameter stats
            @test haskey(result.between, Parameter(:a))
            @test haskey(result.between, Parameter(:b))
            @test length(result.between[:a]) == 3  # stat, df, pvalue
            # Within-chain: per-parameter-per-chain stats
            @test haskey(result.within, Parameter(:a))
            @test haskey(result.within, Parameter(:b))
            @test size(result.within[:a]) == (N_chains, 3)

            # Round-trip: values should match calling MCMCDiagnosticTools directly
            raw = stack([as, bs]; dims=3)
            ref_between, ref_within = MCMCDiagnosticTools.discretediag(raw)
            @test result.between[:a] ==
                  [ref_between.stat[1], ref_between.df[1], ref_between.pvalue[1]]
            @test result.between[:b] ==
                  [ref_between.stat[2], ref_between.df[2], ref_between.pvalue[2]]
            @test result.within[:a] ==
                  hcat(ref_within.stat[1, :], ref_within.df[1, :], ref_within.pvalue[1, :])
        end

        @testset "Symbol chain, array-valued params" begin
            xs = [rand(1:4, 2) for _ in 1:N_iters, _ in 1:N_chains]
            chain = FlexiChain{Symbol}(
                N_iters,
                N_chains,
                Dict(Parameter(:x) => xs, Parameter(:y) => as),
            )
            result = discretediag(chain)
            @test result.between isa FlexiSummary{Symbol}
            @test haskey(result.between, Parameter(Symbol("x[1]")))
            @test haskey(result.between, Parameter(Symbol("x[2]")))
            @test haskey(result.between, Parameter(:y))
        end

        @testset "VarName chain" begin
            xs = [rand(1:4, 2) for _ in 1:N_iters, _ in 1:N_chains]
            chain = FlexiChain{VarName}(
                N_iters,
                N_chains,
                Dict(Parameter(@varname(x)) => xs, Parameter(@varname(y)) => as),
            )
            result = discretediag(chain)
            @test result.between isa FlexiSummary{VarName}
            @test result.within isa FlexiSummary{VarName}
            @test haskey(result.between, @varname(x[1]))
            @test haskey(result.between, @varname(x[2]))
            @test haskey(result.between, @varname(y))
        end

        @testset "non-Integer params skipped with warning" begin
            chain = FlexiChain{Symbol}(
                N_iters,
                N_chains,
                Dict(
                    Parameter(:a) => as,
                    Parameter(:f) => randn(N_iters, N_chains),
                    Extra(:str) => fill("hello", N_iters, N_chains),
                ),
            )
            result = @test_logs (:warn, r"not subtype Integer") discretediag(chain)
            @test haskey(result.between, Parameter(:a))
            @test !haskey(result.between, Parameter(:f))
            @test !haskey(result.between, Extra(:str))
            @test_logs discretediag(chain; warn=false)
        end

        @testset "method kwarg forwarded" begin
            chain = FlexiChain{Symbol}(N_iters, N_chains, Dict(Parameter(:a) => as))
            result = discretediag(chain; method=:hangartner)
            @test result.between isa FlexiSummary{Symbol}
        end

        @testset "errors with single chain" begin
            chain =
                FlexiChain{Symbol}(N_iters, 1, Dict(Parameter(:a) => rand(1:5, N_iters, 1)))
            @test_throws Exception discretediag(chain)
        end

        @testset "within-chain has correct chain indices" begin
            chain = FlexiChain{Symbol}(
                N_iters,
                N_chains,
                Dict(Parameter(:a) => as);
                chain_indices=FlexiChains._make_lookup(2:2:6),
            )
            result = discretediag(chain)
            @test FlexiChains.chain_indices(result.within) ==
                  FlexiChains.chain_indices(chain)
        end
    end

    @testset "bfmi" begin
        N_iters, N_chains = 100, 3
        energy = randn(N_iters, N_chains)
        chain = FlexiChain{Symbol}(
            N_iters,
            N_chains,
            Dict(
                Parameter(:a) => randn(N_iters, N_chains),
                Extra(:hamiltonian_energy) => energy,
            ),
        )

        @testset "matches MCMCDiagnosticTools on raw values" begin
            result = bfmi(chain, Extra(:hamiltonian_energy))
            @test result isa DD.DimVector
            ref = MCMCDiagnosticTools.bfmi(energy)
            @test parent(result) == ref
        end

        @testset "Symbol shorthand gives same result" begin
            @test bfmi(chain, :hamiltonian_energy) ==
                  bfmi(chain, Extra(:hamiltonian_energy))
        end
    end

    @testset "rstar" begin
        N_iters, N_chains = 100, 3
        # Fix the classifier's seed so that results only depend on the rng passed to rstar
        prob_clf = DecisionTreeClassifier(; rng=123)
        det_clf = Pipeline(DecisionTreeClassifier(; rng=123); operation=predict_mode)

        @testset "converged chains give R* ≈ 1" begin
            # Identical, constant draws: the classifier cannot distinguish chains
            chain = FlexiChain{Symbol}(
                N_iters,
                N_chains,
                Dict(
                    Parameter(:a) => fill(4.0, N_iters, N_chains),
                    Parameter(:b) => fill(-1.0, N_iters, N_chains),
                ),
            )
            dist = rstar(StableRNG(1), prob_clf, chain)
            @test dist isa MCMCDiagnosticTools.Distributions.Distribution
            @test isapprox(mean(dist), 1; atol=0.1)
            val = rstar(StableRNG(1), det_clf, chain)
            @test val isa Real
            @test isapprox(val, 1; atol=0.2)
        end

        @testset "non-converged chains give R* > 1" begin
            # Each chain is centred at a very different location
            as = randn(StableRNG(2), N_iters, N_chains) .+ [0.0 100.0 -100.0]
            chain = FlexiChain{Symbol}(N_iters, N_chains, Dict(Parameter(:a) => as))
            val = rstar(StableRNG(1), det_clf, chain)
            @test val > 1.5
            dist = rstar(StableRNG(1), prob_clf, chain)
            @test mean(dist) > 1.5
        end

        @testset "matches MCMCDiagnosticTools on the raw array" begin
            as = randn(StableRNG(3), N_iters, N_chains)
            bs = randn(StableRNG(4), N_iters, N_chains)
            chain = FlexiChain{Symbol}(
                N_iters,
                N_chains,
                Dict(Parameter(:a) => as, Parameter(:b) => bs),
            )
            raw = Array(chain)
            @test rstar(StableRNG(5), det_clf, chain) ==
                  MCMCDiagnosticTools.rstar(StableRNG(5), det_clf, raw)
        end

        @testset "rng argument is optional" begin
            chain = FlexiChain{Symbol}(
                N_iters,
                N_chains,
                Dict(Parameter(:a) => fill(4.0, N_iters, N_chains)),
            )
            val = rstar(det_clf, chain)
            @test val isa Real
            @test isapprox(val, 1; atol=0.2)
        end

        @testset "array-valued params and VarName chain" begin
            xs = [randn(2) for _ in 1:N_iters, _ in 1:N_chains]
            ys = randn(N_iters, N_chains)
            chain = FlexiChain{VarName}(
                N_iters,
                N_chains,
                Dict(Parameter(@varname(x)) => xs, Parameter(@varname(y)) => ys),
            )
            val = rstar(StableRNG(1), det_clf, chain)
            @test val isa Real
            # Should be the same as calling on the flattened array (3 columns)
            raw = Array(chain)
            @test size(raw) == (N_iters, N_chains, 3)
            @test val == MCMCDiagnosticTools.rstar(StableRNG(1), det_clf, raw)
        end

        @testset "non-Real params skipped with warning" begin
            chain = FlexiChain{Symbol}(
                N_iters,
                N_chains,
                Dict(
                    Parameter(:a) => randn(N_iters, N_chains),
                    Parameter(:str) => fill("hello", N_iters, N_chains),
                    Extra(:energy) => randn(N_iters, N_chains),
                ),
            )
            val = @test_logs (:warn, r"str.*Real") rstar(StableRNG(1), det_clf, chain)
            @test val isa Real
            @test_logs rstar(StableRNG(1), det_clf, chain; warn=false)
            # Extras are not used as features
            chain_a =
                FlexiChain{Symbol}(N_iters, N_chains, Dict(Parameter(:a) => chain[:a]))
            @test rstar(StableRNG(1), det_clf, chain; warn=false) ==
                  rstar(StableRNG(1), det_clf, chain_a)
        end

        @testset "keyword arguments are forwarded" begin
            as = randn(StableRNG(6), N_iters, N_chains)
            chain = FlexiChain{Symbol}(N_iters, N_chains, Dict(Parameter(:a) => as))
            raw = Array(chain)
            @test rstar(StableRNG(1), det_clf, chain; subset=0.5, split_chains=1) ==
                  MCMCDiagnosticTools.rstar(
                StableRNG(1),
                det_clf,
                raw;
                subset=0.5,
                split_chains=1,
            )
            @test_throws ArgumentError rstar(StableRNG(1), det_clf, chain; subset=1.5)
        end
    end
end

end # module
