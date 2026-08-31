###########################################################
# Utility functions for plotting (shared across backends) #
###########################################################
#
# We stick these in a module to avoid cluttering the main FlexiChains namespace.

module PlotUtils

function _PARAM_DOCSTRING(funcname)
    return """
    If no parameters are specified, this will plot all parameters in the chain. Note that
    non-parameter, i.e. `Extra`, keys are excluded by default. If you want to plot _all_ keys,
    you can explicitly pass all keys with `$(funcname)(chn, :)`.
    """
end

const _POOL_CHAINS_DOCSTRING = """
The `pool_chains` keyword argument specifies whether to pool samples across multiple chains
when plotting. If `true` (the default), samples from all chains are pooled together; if
`false`, samples from each chain are plotted separately.
"""

const DEFAULT_WIDTH = 400
const DEFAULT_HEIGHT = 250

function get_hdi_intervals end  # Overloaded in PosteriorStatsExt
const DEFAULT_INTERVALS = (0.66, 0.95) # for forestplot

# for the pushforward plots
const DEFAULT_LEVELS = [0.2, 0.4, 0.6, 0.8]

using ..FlexiChains:
    FlexiChain,
    ParameterOrExtra,
    Parameter,
    Extra,
    VarName,
    _split_varnames,
    _get_raw_data,
    niters,
    get_name,
    _get_multi_keys,
    _get_multi_key
import DimensionalData as DD
import StatsBase
import Statistics

"""
Return a chain that has been:

1. Subsetted to just the parameters we want to plot; and

2. Split up such that each key corresponds to a single real-valued parameter.

This ensures that each plotting function can simply loop over the keys of the returned chain
and plot each one, without needing to worry about the structure of the data.
"""
function subset_and_split_chain(
    chn::FlexiChain{TKey},
    param_or_params,
)::Tuple{FlexiChain,Dict} where {TKey}
    parameters_to_plot = if param_or_params isa Union{AbstractVector,Colon}
        _get_multi_keys(TKey, keys(chn), param_or_params)
    else
        # Assume it's a single key. No, don't ask what happens if the key type is an
        # AbstractVector...
        [_get_multi_key(TKey, keys(chn), param_or_params)]
    end
    # Subset the chain to just those parameters. Ordinarily we wouldn't need to do this; we
    # would just directly return `keys_to_plot`. However, there are some subtle
    # considerations when using VarName chains. See below for a full explanation.
    chn = chn[parameters_to_plot]
    # Split into real-valued parameters if possible.
    return _split_varnames(chn; collect_plot_names=true)
end

"""
Get the name to use when plotting a parameter. Usually this defaults to
`string(get_name(key))`, but under some circumstances (specifically DimVectors) this can be
overridden to provide more informative names. This is implemented in
`FlexiChains._split_varnames`.
"""
function get_plot_param_name(key::Parameter{<:T}, plot_names::Dict{T,String}) where {T}
    nm = get_name(key)
    return get(plot_names, nm, string(nm))
end
get_plot_param_name(key::Extra, ::Dict) = string(get_name(key))

"""
Check that the element type of the array is a subtype of `Real`.
"""
function check_eltype_is_real(::AbstractArray{T}) where {T}
    return if !(T <: Real)
        throw(
            ArgumentError(
                "plotting functions only support real-valued data; got data of type $T",
            ),
        )
    end
end

"""
Convert an interval mass `level` (e.g. `0.95`) to the pair of quantile probabilities
`(lower, upper)` bounding the central interval of that mass, e.g. `0.95` becomes
`(0.025, 0.975)`.
"""
function level_to_quantile_bounds(level::Real)
    if !(0 < level < 1)
        throw(ArgumentError("level must be in (0, 1), got $level"))
    end
    lower = (1 - level) / 2
    upper = 1 - lower
    return lower, upper
end

"""
Sort `levels` (interval masses) so that index 1 is the widest, and return the sorted levels
together with the vector of quantile probabilities needed to compute every band boundary
plus the median. That vector is sorted ascending and always contains `0.5`.
"""
function levels_to_quantile_probs(levels::AbstractVector{<:Real})
    sorted_levels = sort(levels; rev=true)
    bounds = level_to_quantile_bounds.(sorted_levels)
    probs = sort(vcat(0.5, first.(bounds), last.(bounds)))
    return sorted_levels, probs
end

"""
Compute nested-quantile band values.

`quantile_levels` are in 0–1. For a matrix (`iter × chain`), each quantile is the *ensemble
estimate*: the empirical quantile is computed per chain (per column) and then averaged
across chains. Returns a vector of the same length as `quantile_levels`.
"""
function compute_quantile_bands(
    data::AbstractMatrix{<:Real},
    quantile_levels::AbstractVector{<:Real},
)
    nchains = size(data, 2)
    acc = zeros(length(quantile_levels))
    for c in 1:nchains
        acc = acc .+ Statistics.quantile(view(data, :, c), quantile_levels)
    end
    return acc ./ nchains
end

"""
Compute nested-quantile band values for every key in `chn`.
"""
function chain_quantile_bands(
    chn::FlexiChain,
    probs::AbstractVector{<:Real};
    warn::Bool=true,
)
    fs = Statistics.quantile(chn, probs; dims=:iter, warn=warn, split_varnames=false)
    da = DD.DimArray(fs)
    return Statistics.mean(da, dims=:chain)
end

"""
Per-band alpha for `n_bands` nested uncertainty bands drawn outermost-first.

Band `k` is drawn on top of bands `1:k-1`, so the visible (composite) opacity at depth `k`
is `A(k) = 1 - prod(1 - alpha_j for j in 1:k)`. This targets a composite ramp that is
linear in `k`, running from `alpha_limits[1]` at the outermost band to `alpha_limits[2]` at
the innermost.
"""
function band_alpha(n_bands; alpha_limits::NTuple{2,AbstractFloat}=(0.15, 0.85))
    issorted(alpha_limits) || throw(ArgumentError("`alpha_limits` must be sorted"))
    a_min, a_max = alpha_limits
    0 <= a_min && a_max <= 1 || throw(
        ArgumentError("values in `alpha_limits` must be in [0, 1], got $alpha_limits"),
    )
    composite(i) = a_min + (a_max - a_min) * (i - 1) / max(n_bands - 1, 1)
    return map(1:n_bands) do i
        i == 1 && return a_min
        return 1 - (1 - composite(i)) / (1 - composite(i - 1))
    end
end

"""
Equal-width bin edges spanning the range of `values`; returns `nbins+1` edges.
`values` must be non-empty.
"""
function get_bin_edges(values::AbstractArray, nbins::Integer)
    isempty(values) && throw(ArgumentError("get_bin_edges: `values` must be non-empty"))
    lo, hi = extrema(values)
    if lo == hi
        hi = lo + eps(lo) # Don't make the bin have 0 width.
    end
    return collect(range(lo, hi; length=nbins + 1))
end

"""
Returns a vector `v` where `v[b]` is the number of entries of `values` falling within the
bin `[edges[b], edges[b+1])`. The length of `v` is `length(edges) - 1`.

edges  [0]     [1]     [2] ...
        |  v[0] |  v[1] |  ...
        | elems | elems |  ...
        -----------------  ...

Values equal to the final edge land in the last bin, and out-of-range values are ignored.
"""
function histogram_counts(values::AbstractVector{<:Real}, edges::AbstractVector{<:Real})
    issorted(edges) || throw(ArgumentError("edges must be sorted"))
    length(edges) >= 2 || throw(ArgumentError("edges must have at least 2 elements"))
    nbins = length(edges) - 1
    counts = zeros(Int, nbins)
    last_edge = last(edges)
    for v in values
        b = if v == last_edge
            nbins # clamp to last bin
        else
            searchsortedlast(edges, v)
        end
        if 1 <= b <= nbins
            counts[b] += 1
        end
    end
    return counts
end

"""
Histogram a vector-valued parameter across posterior draws.

`components` must be a length-K vector of `iter × chain` matrices, one per component of the
parameter (e.g. `y_pred[1], ..., y_pred[K]`).

For each combination of `(iter, chain)`, the `K` component values are binned into a
histogram defined by `edges`.

Returns an `iter × chain × nbins` array where `counts[i, c, b]` is the number of components
that fell in bin `b` for draw `(i, c)`.
"""
function bin_count_matrices(
    values::AbstractArray{<:Real,3}, # iter × chain × component
    edges::AbstractVector{<:Real},
)
    n_iter, n_chain, _ = size(values)
    n_bins = length(edges) - 1
    counts = zeros(Int, n_iter, n_chain, n_bins)
    for c in 1:n_chain, i in 1:n_iter
        counts[i, c, :] = histogram_counts(values[i, c, :], edges)
    end
    return counts
end

struct FlexiChainTrace{TKey,Tp<:ParameterOrExtra{<:TKey}}
    chn::FlexiChain{TKey}
    param::Tp
end

struct FlexiChainRank{TKey,Tp<:ParameterOrExtra{<:TKey}}
    chn::FlexiChain{TKey}
    param::Tp
    # indicates which one to plot
    chn_idx
    # indexed by iter/chain -- note this matrix contains ranks for all chains because we
    # need to calculate ranks across all chains, even if we only plot one.
    ranks::DD.DimMatrix{<:Real}
end
function get_ranks(
    chn::FlexiChain{TKey},
    param::Tp,
) where {TKey,Tp<:ParameterOrExtra{<:TKey}}
    return StatsBase.tiedrank(chn[param])
end

struct FlexiChainRankOverlay{TKey,Tp<:ParameterOrExtra{<:TKey}}
    chn::FlexiChain{TKey}
    param::Tp
    ranks::DD.DimMatrix{<:Real} # same as above
end

struct FlexiChainHistogram{TKey,Tp<:ParameterOrExtra{<:TKey}}
    chn::FlexiChain{TKey}
    param::Tp
    pool_chains::Bool
end

function runningmean(v::AbstractVector{<:Union{Real,Missing}})
    y = similar(v, Float64)
    n = 0
    sum = zero(eltype(v))
    for i in eachindex(v)
        if !ismissing(v[i])
            n += 1
            sum += v[i]
        end
        y[i] = sum / n
    end
    return y
end
struct FlexiChainMean{TKey,Tp<:ParameterOrExtra{<:TKey}}
    chn::FlexiChain{TKey}
    param::Tp
end

"""
Calculate default lags for autocorrelation plots. This is directly taken from StatsBase.jl.
"""
function default_lags(chn::FlexiChain)
    return 1:min(niters(chn)-1, round(Int, 10*log10(niters(chn))))
end
struct FlexiChainAutoCor{TKey,Tp<:ParameterOrExtra{<:TKey},Tl<:AbstractVector{Int}}
    chn::FlexiChain{TKey}
    param::Tp
    lags::Tl
    demean::Bool
end

struct FlexiChainMixedDensity{TKey,Tp<:ParameterOrExtra{<:TKey}}
    chn::FlexiChain{TKey}
    param::Tp
    pool_chains::Bool
end

struct FlexiChainDensity{TKey,Tp<:ParameterOrExtra{<:TKey}}
    chn::FlexiChain{TKey}
    param::Tp
    pool_chains::Bool
end

struct FlexiChainViolin{TKey,Tp<:ParameterOrExtra{<:TKey}}
    chn::FlexiChain{TKey}
    param::Tp
    pool_chains::Bool
    with_box::Bool
end

struct FlexiChainForest{TKey}
    chn::FlexiChain{TKey}
    params::Vector
    param_names::Vector{String}
    pool_chains::Bool
    point::Symbol
    interval::Symbol
    hdi_method::Symbol
    levels::Vector{Float64}
    function FlexiChainForest(
        chn::FlexiChain{TKey},
        params::Vector,
        param_names::Vector{String},
        pool_chains::Bool,
        point=:median,
        interval=:quantile,
        hdi_method=:unimodal,
        levels=DEFAULT_INTERVALS,
    ) where {TKey}
        point in (:mean, :median) ||
            throw(ArgumentError("point must be :mean or :median, got :$point"))
        interval in (:quantile, :hdi) ||
            throw(ArgumentError("interval must be :quantile or :hdi, got :$interval"))
        all(l -> 0 < l < 1, levels) ||
            throw(ArgumentError("interval levels must be in (0, 1)"))
        sorted_levels = sort(collect(Float64, levels))
        return new{TKey}(
            chn,
            params,
            param_names,
            pool_chains,
            point,
            interval,
            hdi_method,
            sorted_levels,
        )
    end
end

struct FlexiChainRidgeline{TKey}
    chn::FlexiChain{TKey}
    params::Vector
    param_names::Vector{String}
    pool_chains::Bool
end

end # module PlotUtils
