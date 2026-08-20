module FlexiChains

using AbstractMCMC: AbstractMCMC
using DimensionalData: DimensionalData as DD
using DimensionalData.Dimensions.Lookups: Lookups as DDL
using OrderedCollections: OrderedDict, OrderedSet
using DocStringExtensions: TYPEDFIELDS
using PrecompileTools: @setup_workload, @compile_workload

# For use when marking the public API.
# On 1.11+ it just uses the `public` keyword, otherwise it does nothing.
macro public(ex)
    # https://discourse.julialang.org/t/is-compat-jl-worth-it-for-the-public-keyword/119041/22
    return if VERSION >= v"1.11.0-DEV.469"
        args = if ex isa Symbol
            (ex,)
        elseif Base.isexpr(ex, :tuple)
            ex.args
        else
            error("unexpected expression in @public")
        end
        esc(Expr(:public, args...))
    else
        nothing
    end
end

include("chain.jl")
include("summary.jl")
include("diagnostics.jl")
include("getindex.jl")
include("interface/equal.jl")
include("interface/size.jl")
include("interface/dict.jl")
include("interface/show.jl")
include("interface/cat.jl")
include("interface/mergesubset.jl")
include("interface/samples.jl")
include("interface/rand.jl")
include("interface/transform.jl")
include("varname.jl")
include("flatten.jl")
include("conversions.jl")
include("stancsv.jl")

# These denote the 'special' keys that we use for Turing.jl return values
const _LOGJOINT_KEY = Extra(:logjoint)
const _LOGPRIOR_KEY = Extra(:logprior)
const _LOGLIKELIHOOD_KEY = Extra(:loglikelihood)

# Extended in PosteriorDB extension (but not exported)
function from_posteriordb_ref end
@public from_posteriordb_ref
include("plots/utils.jl")
include("plots/plots.jl")
include("plots/makie.jl")
include("plots/shims.jl")

# Extended in AbstractPPL extension and used in MCMCChains extension
_internal_to_varname(sym::Symbol) = VarName{sym}()
_maybe_promote_key(::Type{Tnew}) where {Tnew} = Tnew
_maybe_promote_key(::Type{<:VarName}) = VarName

# Extended in MCMCChains extension
function from_mcmcchains end
@public from_mcmcchains

# Extended in Pigeons extension
function from_pigeons end
@public from_pigeons
function _internal_from_pigeons end
function _faithful_sample_array end

# Convenience re-exports.
export Wide, Long
using DimensionalData: At, Near, Contains, (..), Touches, Where, Not, DimArray, Begin, End
export At, Near, Contains, (..), Touches, Where, Not, DimArray, Begin, End
using Statistics: mean, median, std, var, quantile
export mean, median, std, var, quantile
using StatsBase: summarystats, mad
export summarystats, mad
using MCMCDiagnosticTools:
    ess, rhat, mcse, gelmandiag, gelmandiag_multivariate, discretediag, bfmi
export ess, rhat, mcse, gelmandiag, gelmandiag_multivariate, discretediag, bfmi

"""
    VNChain

Alias for `FlexiChain{VarName}`.
"""
const VNChain = FlexiChain{VarName}

"""
    SymChain

Alias for `FlexiChain{Symbol}`.
"""
const SymChain = FlexiChain{Symbol}

export VarName, @vn, @varname, VNChain, SymChain

# Test utils, overloaded in DynamicPPLExt.
function _make_prior_chain end
function _make_posterior_chain end

# Attempt to precompile _some_ stuff, especially for VarName. This cuts the TTFX by about
# 2-3x.
@setup_workload begin
    d = Dict{ParameterOrExtra{<:VarName},Any}()
    d[Parameter(@varname(a))] = 1
    ds = fill(d, 10, 2)
    @compile_workload begin
        fc = VNChain(10, 2, ds)
        summarystats(fc)
    end
end

function __init__()
    Base.Experimental.register_error_hint(MethodError) do io, exc, argtypes, kwargs
        if exc.f === FlexiChains.PlotUtils.get_hdi_intervals
            printstyled(
                io,
                "\n\n    To use interval=:hdi, please load PosteriorStats.jl first.\n";
                color=:cyan,
            )
        end
    end
    Base.Experimental.register_error_hint(MethodError) do io, exc, argtypes, kwargs
        if (exc.f === Base.firstindex || exc.f === Base.lastindex) &&
           length(argtypes) == 1 &&
           (argtypes[1] <: FlexiChain || argtypes[1] <: FlexiChains.FlexiSummary)
            printstyled(
                io,
                "\n\n    Indexing into FlexiChains objects with `begin` or `end` does not work; please use `Begin` and `End` instead, which are equivalent.";
                color=:cyan,
            )
        end
    end
    return nothing
end

end # module FlexiChains
