module FlexiChainsPosteriorStatsExt

using PosteriorStats
using FlexiChains: FlexiChains, FlexiChain, OrderedDict, ParameterOrExtra
import DimensionalData as DD
using IntervalSets: leftendpoint, rightendpoint, ClosedInterval

function _split_interval_fail_sanity_check()
    error(
        "split_interval=true was requested, but the FlexiSummary has the incorrect shape. This should not happen! Please report this as a bug.",
    )
end
function _split_interval(
    fs::FlexiChains.FlexiSummary{TKey},
    lower_name::Symbol,
    upper_name::Symbol,
) where {TKey}
    FlexiChains.stat_indices(fs) === nothing || _split_interval_fail_sanity_check()
    if any(v -> !(eltype(v) <: ClosedInterval), values(fs._data))
        @warn "split_interval=true was requested, but not all values in the statistic column are ClosedIntervals. Returning the original FlexiSummary without splitting."
        return fs
    end
    new_data = OrderedDict{ParameterOrExtra{<:TKey},Array{<:Any,3}}()
    for (k, v) in fs._data
        # v is a 3D array of iter x chain x stat
        size(v, 3) == 1 || _split_interval_fail_sanity_check()
        lower = map(leftendpoint, v)
        upper = map(rightendpoint, v)
        combined = cat(lower, upper; dims=3) # new 3D array with stat dimension of size 2
        new_data[k] = combined
    end
    si = FlexiChains._make_categorical([lower_name, upper_name])
    return FlexiChains.FlexiSummary{TKey}(
        new_data,
        fs._iter_indices,
        fs._chain_indices,
        si,
        false,
    )
end

"""
$(FlexiChains._stat_docstring("PosteriorStats.hdi", "highest density interval"))

## Splitting intervals

By default (`split_interval=true`), the output `FlexiSummary` has one statistic column per
interval bound, i.e., `hdi_lower` and `hdi_upper`. Set `split_interval=false` to instead get
a single statistic column named `hdi` containing `IntervalSets.ClosedInterval`s.

Splitting is only possible when a _single_ interval is computed per parameter (i.e.,
`method=:unimodal`, which is the default in PosteriorStats.jl). If you use a multimodal
method (e.g. `method=:multimodal`), each parameter can have several intervals, so the
returned `FlexiSummary` will always have a single statistic column named `hdi` containing a
vector of intervals. In this case, a warning is emitted unless you pass
`split_interval=false`.
"""
function PosteriorStats.hdi(
    chn::FlexiChain{TKey};
    dims::Symbol=:both,
    warn::Bool=true,
    split_varnames::Bool=true,
    split_interval::Bool=true,
    kwargs...,
) where {TKey}
    # Emit a message if `prob` is not passed since PosteriorStats intentionally chooses an
    # 'unconventional' default value for `prob` to force users to be explicit about the
    # interval width.
    if !haskey(kwargs, :prob)
        @info "PosteriorStats.hdi: `prob` keyword argument not provided. Consider explicitly specifying `prob` to control the interval width: the default value is 0.89."
    end
    fs = FlexiChains.collapse(
        chn,
        [FlexiChains.CollapseFunctionVec(:hdi, PosteriorStats.hdi; kwargs...)];
        dims=dims,
        split_varnames=split_varnames,
        warn=warn,
        drop_stat_dim=true,
    )

    return split_interval ? _split_interval(fs, :hdi_lower, :hdi_upper) : fs
end


"""
$(FlexiChains._stat_docstring("PosteriorStats.eti", "equal-tailed interval"))

## Splitting intervals

By default (`split_interval=true`), the output `FlexiSummary` has one statistic column per
interval bound, i.e., `eti_lower` and `eti_upper`. Set `split_interval=false` to instead get
a single statistic column named `eti` containing `IntervalSets.ClosedInterval`s.
"""
function PosteriorStats.eti(
    chn::FlexiChain{TKey};
    dims::Symbol=:both,
    warn::Bool=true,
    split_varnames::Bool=true,
    split_interval::Bool=true,
    kwargs...,
) where {TKey}
    # Emit a message if `prob` is not passed since PosteriorStats intentionally chooses an
    # 'unconventional' default value for `prob` to force users to be explicit about the
    # interval width.
    if !haskey(kwargs, :prob)
        @info "PosteriorStats.eti: `prob` keyword argument not provided. Consider explicitly specifying `prob` to control the interval width: the default value is 0.89."
    end
    fs = FlexiChains.collapse(
        chn,
        [FlexiChains.CollapseFunctionVec(:eti, PosteriorStats.eti; kwargs...)];
        dims=dims,
        split_varnames=split_varnames,
        warn=warn,
        drop_stat_dim=true,
    )
    return split_interval ? _split_interval(fs, :eti_lower, :eti_upper) : fs
end

struct NamesAndLOOResult{V<:AbstractVector,P<:PosteriorStats.PSISLOOResult}
    param_names::V
    loo::P
end
function Base.show(io::IO, m::MIME"text/plain", x::NamesAndLOOResult)
    printstyled(io, "NamesAndLOOResult"; bold=true)
    println(io)
    print(io, "├─ param_names: $(x.param_names)")
    println(io)
    print(io, "└─ loo: ")
    return show(io, m, x.loo)
end

"""
    PosteriorStats.loo(chn::FlexiChains; kwargs...)

Calculates the leave-one-out cross-validation (LOO) statistic for a `FlexiChain` object. The
chain must contain only log-likelihood values, and they must all be stored as parameters
(not extras). Parameters that map to arrays of log-likelihood values are supported: they
will be flattened before being passed to `PosteriorStats.loo`.

Returns a struct with the following fields:

- `param_names::Vector`: A vector of parameter names whose log-likelihood values were used.

- `loo::PosteriorStats.PSISLOOResult`: The return value of `PosteriorStats.loo` applied to
  the log-likelihood values extracted from the `FlexiChain`. This contains the statistics
  of interest.

Additional keyword arguments are forwarded to [`PosteriorStats.loo`](@extref).
"""
function PosteriorStats.loo(chn::FlexiChain; kwargs...)
    da = DD.DimArray(chn; eltype_filter=Real, parameters_only=true)
    param_names = DD.val(DD.dims(da, FlexiChains.PARAM_DIM_NAME))
    return NamesAndLOOResult(param_names, PosteriorStats.loo(da; kwargs...))
end

function FlexiChains.PlotUtils.get_hdi_intervals(
    data::Union{<:AbstractVector,<:AbstractMatrix},
    prob::Float64,
    method::Symbol,
)
    interval_or_intervals = PosteriorStats.hdi(data; prob=prob, method=method)
    # method=:unimodal returns a single interval, so wrap in a vector
    intervals = if method === :unimodal
        [interval_or_intervals]
    else
        interval_or_intervals
    end
    # then convert each interval to a tuple so that downstream code doesn't have to faff
    # with IntervalSets
    return map(intervals) do interval
        (leftendpoint(interval), rightendpoint(interval))
    end
end

end # module
