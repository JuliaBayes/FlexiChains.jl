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

# for connquantile etc.
const DEFAULT_QUANTILE_LEVELS = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]

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
import SpecialFunctions

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

"""
Return the predictive draws of `param` as a matrix with one row per pooled draw, ordered
chain by chain, and one column per component of `param`.
"""
function pooled_predictive_draws(chn::FlexiChain, param)
    sub, _ = subset_and_split_chain(chn, param)
    component_keys = collect(keys(sub))
    isempty(component_keys) && throw(ArgumentError("no parameters to plot"))
    draws_per_component = map(component_keys) do k
        iter_by_chain = _get_raw_data(sub, k)
        check_eltype_is_real(iter_by_chain)
        vec(iter_by_chain)
    end
    return stack(draws_per_component)
end

function check_observed_length(observed, ncomponents::Integer)
    return if length(observed) != ncomponents
        throw(
            ArgumentError(
                "length of `observed` ($(length(observed))) must match the number of components of `param` ($ncomponents)",
            ),
        )
    end
end

"""
Row indices of `ndraws` pooled draws at evenly spaced positions from the first to the last
of `npooled`. `ndraws=nothing` selects every draw.
"""
function evenly_spaced_draw_indices(npooled::Integer, ndraws::Integer)
    ndraws >= 1 || throw(ArgumentError("`ndraws` must be at least 1; got $ndraws"))
    ndraws <= npooled || throw(
        ArgumentError("`ndraws` ($ndraws) exceeds the number of pooled draws ($npooled)"),
    )
    ndraws == 1 && return [1]
    return round.(Int, LinRange(1, npooled, ndraws))
end
evenly_spaced_draw_indices(npooled::Integer, ::Nothing) = Base.OneTo(npooled)

"""
Uniformity test for PIT values from continuous outcomes, based on the distribution of order
statistics.
"""
struct POT end

"""
Uniformity test for PIT values from integer-valued outcomes, based on the distribution of
ranks.
"""
struct PRIT end

"""
Choose the uniformity test from the element types of the predictive draws and the
observations: `PRIT` when both are integer-valued, `POT` when neither is.
"""
uniformity_test_for(::Type{<:Integer}, ::Type{<:Integer}) = PRIT()
uniformity_test_for(::Type{<:Real}, ::Type{<:Real}) = POT()
function uniformity_test_for(TDraws::Type{<:Integer}, TObserved::Type{<:Real})
    return throw_mixed_eltypes(TDraws, TObserved)
end
function uniformity_test_for(TDraws::Type{<:Real}, TObserved::Type{<:Integer})
    return throw_mixed_eltypes(TDraws, TObserved)
end
function throw_mixed_eltypes(TDraws, TObserved)
    throw(
        ArgumentError(
            "predictive draws and `observed` must both be integer-valued or both be non-integer; got element types $TDraws and $TObserved",
        ),
    )
end

"""
PIT value of each observation: `mean(y_rep .< y) + U * mean(y_rep .== y)`, where `y_rep` is
the column of `draws` belonging to observation `y` and `U` is uniform on `[0, 1)`.
"""
function pit_values(rng, draws::AbstractMatrix, observed)
    return [
        Statistics.mean(<(observation), component_draws) +
        rand(rng) * Statistics.mean(==(observation), component_draws) for
        (component_draws, observation) in zip(eachcol(draws), observed)
    ]
end

two_sided_pvalue(lower_tail, upper_tail) = 2 * min(lower_tail, upper_tail)

function pointwise_pvalues(::POT, sorted_pit)
    n = length(sorted_pit)
    return [
        two_sided_pvalue(SpecialFunctions.beta_inc(rank, n + 1 - rank, u)...) for
        (rank, u) in enumerate(sorted_pit)
    ]
end

function binomial_cdf(n, p, k)
    k >= n && return one(p)
    return first(SpecialFunctions.beta_inc(n - k, k + 1, 1 - p))
end

function binomial_pmf(n, p, k)
    return exp(
        first(SpecialFunctions.logabsbinomial(n, k)) + k * log(p) + (n - k) * log1p(-p),
    )
end

function pointwise_pvalues(::PRIT, sorted_pit)
    n = length(sorted_pit)
    return map(sorted_pit) do u
        n_at_most_u = searchsortedlast(sorted_pit, u)
        mid_cdf = binomial_cdf(n, u, n_at_most_u) - binomial_pmf(n, u, n_at_most_u) / 2
        two_sided_pvalue(mid_cdf, 1 - mid_cdf)
    end
end

cauchy_transform(pvalue) = tan((0.5 - pvalue) * π)

function truncated_cauchy_combination(pvalues)
    mean_truncated = Statistics.mean(p -> p < 0.5 ? cauchy_transform(p) : zero(p), pvalues)
    return 0.5 - atan(mean_truncated) / π
end

function shapley_contributions(pvalues)
    n = length(pvalues)
    transformed = map(cauchy_transform, pvalues)
    n == 1 && return zero(transformed)
    harmonic_number = sum(inv, 1:n)
    total = sum(transformed)
    return map(transformed) do x
        mean_of_others = (total - x) / (n - 1)
        x / n + (harmonic_number - 1) / n * (x - mean_of_others)
    end
end

"""
Test whether PIT values are uniform, in a way that remains valid when they depend on each
other (Tesso and Vehtari, 2026, arXiv:2603.02928). `sorted_pit` must be sorted and lie
strictly inside `(0, 1)`.

Returns the global p-value and the contribution of each PIT value to the test statistic,
in the order of `sorted_pit`.
"""
function uniformity_test(test::Union{POT,PRIT}, sorted_pit::AbstractVector{<:Real})
    Base.require_one_based_indexing(sorted_pit)
    isempty(sorted_pit) && throw(ArgumentError("PIT values must be non-empty"))
    issorted(sorted_pit) || throw(ArgumentError("PIT values must be sorted"))
    all(u -> 0 < u < 1, sorted_pit) ||
        throw(ArgumentError("PIT values must lie strictly between 0 and 1"))
    pvalues = pointwise_pvalues(test, sorted_pit)
    return (;
        pvalue=truncated_cauchy_combination(pvalues),
        contributions=shapley_contributions(pvalues),
    )
end

function check_pit_values(pit)
    isempty(pit) && throw(ArgumentError("PIT values must be non-empty"))
    indices_outside = findall(u -> !(0 <= u <= 1), pit)
    isempty(indices_outside) || throw(
        ArgumentError(
            "PIT values must lie in [0, 1]; got values outside it at indices $indices_outside",
        ),
    )
    indices_on_boundary = findall(u -> u == 0 || u == 1, pit)
    isempty(indices_on_boundary) || throw(
        ArgumentError(
            "$(length(indices_on_boundary)) observation(s) lie outside the range of all predictive draws (indices $indices_on_boundary); the uniformity test is undefined for PIT values of exactly 0 or 1",
        ),
    )
end

"""
Everything `ppc_pit_ecdf` draws, computed from PIT values: the sorted PIT values, the ECDF
difference at each of them, the global p-value of the uniformity test `test`, the threshold
`alpha = 1 - prob`, the positions in `sorted_pit` of the flagged points, and the half-width
of the y-axis.
"""
function pit_ecdf_check(test::Union{POT,PRIT}, pit::AbstractVector{<:Real}, prob)
    Base.require_one_based_indexing(pit)
    0 < prob < 1 ||
        throw(ArgumentError("`prob` must lie strictly between 0 and 1; got $prob"))
    check_pit_values(pit)
    sorted_pit = sort(pit)
    n = length(sorted_pit)
    ecdf_difference = [rank / n - u for (rank, u) in enumerate(sorted_pit)]
    pvalue, contributions = uniformity_test(test, sorted_pit)
    alpha = 1 - prob
    flagged = pvalue < alpha ? findall(>(0), contributions) : Int[]
    chance_level_bound = 1.3 * sqrt(log(2 / alpha) / (2 * n))
    ylimit = max(chance_level_bound, maximum(abs, ecdf_difference))
    return (; sorted_pit, ecdf_difference, pvalue, alpha, flagged, ylimit)
end
pit_ecdf_check(pit::AbstractVector{<:Real}, prob) = pit_ecdf_check(POT(), pit, prob)
function pit_ecdf_check(rng, chn::FlexiChain, param, observed, prob)
    draws = pooled_predictive_draws(chn, param)
    check_observed_length(observed, size(draws, 2))
    test = uniformity_test_for(eltype(draws), eltype(observed))
    return pit_ecdf_check(test, pit_values(rng, draws, observed), prob)
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
