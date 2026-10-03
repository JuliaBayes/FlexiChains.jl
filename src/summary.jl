using Printf: @sprintf
using Statistics: Statistics
using StatsBase: StatsBase
using MCMCDiagnosticTools: MCMCDiagnosticTools

@public FlexiSummary, collapse

const STAT_DIM_NAME = :stat
function _make_categorical(v::AbstractVector{Symbol})
    return DD.Categorical(v; order=DD.Unordered())
end

"""
    FlexiChains.FlexiSummary{
        TKey,
        TIIdx<:Union{DimensionalData.Lookup,Nothing},
        TCIdx<:Union{DimensionalData.Lookup,Nothing},
        TSIdx<:DimensionalData.Categorical,
    }

A data structure containing summary statistics of a [`FlexiChain`](@ref).

## Construction

Calling summary functions such as `mean` or `std` on a `FlexiChain` will return a `FlexiSummary`.
For more flexibility, you can use [`FlexiChains.collapse`](@ref) to apply one or more summary functions to a `FlexiChain`.

Users should not need to construct `FlexiSummary` objects directly.

## Indexing

A `FlexiSummary{TKey}` can be indexed into using exactly the same techniques as a
`FlexiChain{TKey}`. That is to say:

- with `Parameter{TKey}` or `Extra` to unambiguously get the summary statistics for that
  key
- with `TKey` for automatic conversion to `Parameter{TKey}`
- with `Symbol` to find unambiguous matches
- if `TKey<:VarName`, using `VarName` or sub-`VarName`s to additionally extract part of the
  data.

The returned value will be either a `DimensionalData.DimArray` (if there are one or more
non-collapsed dimensions), or a single value (if all dimensions are collapsed).

If a `DimArray` is returned, the dimensions that you will see are: `:$(ITER_DIM_NAME)` (if the
summary function was only applied over chains), `:$(CHAIN_DIM_NAME)` (same but for
iterations), and `:$(STAT_DIM_NAME)` (typically seen when multiple summary functions were
applied).

# Extended help

## Internal data layout

A `FlexiSummary`, much like a `FlexiChain`, contains a mapping of keys to arrays of data.
However, the dimensions of a `FlexiSummary` are substantially different. In particular:

- The `:$(ITER_DIM_NAME)` and/or `:$(CHAIN_DIM_NAME)` dimensions may have been collapsed via
  the act of calculating a summary over iterations or chains.
- There is an additional, third, dimension: the _statistic_ dimension, represented by
  `:$(STAT_DIM_NAME). This dimension records which statistic(s) have been calculated.
- The `:$(STAT_DIM_NAME)` dimension may *also* have been collapsed. This can happen if
  only one statistic was computed and `drop_stat_dim=true` was used when calling
  [`FlexiChains.collapse`](@ref). The purpose of this is to avoid making the user deal with
  a redundant singleton dimension when calling a function such as `mean(chain)`.

Regardless of which dimensions have been collapsed, the internal data of a `FlexiSummary`
**always** contains all three dimensions (some of which may have size 1).

Information about which dimensions are collapsed is therefore not stored in the arrays.
Instead, it is stored in the `_iter_indices` and `_chain_indices` fields of the
`FlexiSummary`, as well as their types. If either of these is `nothing`, then that
dimension has been collapsed. For the stat dimension, `_stat_indices` always contains a
`DimensionalData.Categorical` with the stat name(s), but the `_drop_stat_dim` field
controls whether the stat dimension is presented to the user.

This information is later used in the `_get_raw_data` and `_raw_to_user_data` functions.
"""
struct FlexiSummary{
    TKey,
    TIIdx<:Union{DD.Lookup,Nothing},
    TCIdx<:Union{DD.Lookup,Nothing},
    TSIdx<:DD.Categorical,
}
    _data::OrderedDict{ParameterOrExtra{<:TKey},<:AbstractArray{<:Any,3}}
    _iter_indices::TIIdx
    _chain_indices::TCIdx
    _stat_indices::TSIdx
    _drop_stat_dim::Bool

    function FlexiSummary{TKey}(
        data::OrderedDict{<:Any,<:AbstractArray{<:Any,3}},
        iter_indices::TIIdx,
        chain_indices::TCIdx,
        stat_indices::TSIdx,
        drop_stat_dim::Bool,
    )::FlexiSummary{
        TKey,
        TIIdx,
        TCIdx,
        TSIdx,
    } where {
        TKey,
        TIIdx<:Union{DD.Lookup,Nothing},
        TCIdx<:Union{DD.Lookup,Nothing},
        TSIdx<:DD.Categorical,
    }
        # Get expected size.
        expected_size = (
            TIIdx === Nothing ? 1 : length(iter_indices),
            TCIdx === Nothing ? 1 : length(chain_indices),
            length(stat_indices),
        )
        # Size verification (while marshalling into a Dict with the right type).
        d = OrderedDict{ParameterOrExtra{<:TKey},Array{<:Any,3}}()
        for (k, v) in pairs(data)
            if size(v) != expected_size
                msg = "got size $(size(v)) for key $k, expected $expected_size"
                throw(DimensionMismatch(msg))
            end
            d[k] = collect(v)
        end
        return new{TKey,TIIdx,TCIdx,TSIdx}(
            d,
            iter_indices,
            chain_indices,
            stat_indices,
            drop_stat_dim,
        )
    end
end
"""
    iter_indices(summary::FlexiSummary)::DimensionalData.Lookup

The iteration indices, which are either the same as in the original chain, or `nothing` if
the `$ITER_DIM_NAME` dimension has been collapsed.
"""
function iter_indices(fs::FlexiSummary{TKey,TIIdx})::TIIdx where {TKey,TIIdx}
    return fs._iter_indices
end
"""
    chain_indices(summary::FlexiSummary)::DimensionalData.Lookup

The chain indices, which are either the same as in the original chain, or `nothing` if the
`$CHAIN_DIM_NAME` dimension has been collapsed.
"""
function chain_indices(fs::FlexiSummary{TKey,TIIdx,TCIdx})::TCIdx where {TKey,TIIdx,TCIdx}
    return fs._chain_indices
end
"""
    stat_indices(summary::FlexiSummary)

The indices for each statistic in the summary. Returns `nothing` if the `$STAT_DIM_NAME`
dimension has been collapsed (i.e. `drop_stat_dim=true` was used).
"""
function stat_indices(fs::FlexiSummary)
    return fs._drop_stat_dim ? nothing : fs._stat_indices
end

_pretty_value(x::Integer, ::Bool=false) = repr(x)
_pretty_value(x::AbstractString, ::Bool=false) = x
_pretty_value(x::Symbol, ::Bool=false) = String(x)
function _pretty_value(x::AbstractFloat, short::Bool=false)
    return short ? @sprintf("%.1f", x) : @sprintf("%.4f", x)
end
function _pretty_value(x::AbstractVector, ::Bool=false)
    return "[" * join(map(x -> _pretty_value(x, true), x), ",") * "]"
end
# Fallback: just use repr
_pretty_value(x, ::Bool=false) = repr(x)
_truncate(x::String, n::Int) = length(x) > n ? first(x, n - 1) * "…" : x

"""
    _get_raw_data(summary::FlexiSummary{<:TKey}, key::ParameterOrExtra{<:TKey})

Extract the raw data (i.e. an Array of samples) corresponding to a given key in the summary.
The returned data is always a 3D array with dimensions (NIter, NChain, NStat).

!!! important
    This function does not check if the key exists.
"""
function _get_raw_data(
    summary::FlexiSummary{<:TKey},
    key::ParameterOrExtra{<:TKey},
) where {TKey}
    return summary._data[key]
end

"""
    _get_summary_dims(summary::FlexiSummary)

Determine which dimensions of the summary have been collapsed.

Returns a tuple of two elements:

- a vector of `DimensionalData.Dim` objects corresponding to the dimensions that have not
  been collapsed; and
- a tuple of integers corresponding to the dimensions that have been collapsed, which can be
  passed to `dropdims`.
"""
function _get_summary_dims(fs::FlexiSummary)
    new_dims = DD.Dim[]
    dims_to_keep = Int[]
    ii = iter_indices(fs)
    ci = chain_indices(fs)
    si = stat_indices(fs)
    if ii !== nothing
        push!(dims_to_keep, 1)
        push!(new_dims, DD.Dim{ITER_DIM_NAME}(ii))
    end
    if ci !== nothing
        push!(dims_to_keep, 2)
        push!(new_dims, DD.Dim{CHAIN_DIM_NAME}(ci))
    end
    if si !== nothing
        push!(dims_to_keep, 3)
        push!(new_dims, DD.Dim{STAT_DIM_NAME}(si))
    end
    dim_indices_to_drop = tuple(setdiff(1:3, dims_to_keep)...)
    return new_dims, dim_indices_to_drop
end
"""
    _raw_to_user_data(summary::FlexiSummary, data::AbstractArray; stack=nothing)

Convert `data`, which is a raw 3D array of samples, to either:

- a `DimensionalData.DimArray` using the indices stored in in the `FlexiSummary`, if there
  are one or more non-collapsed dimensions; or
- a single value, if all dimensions are collapsed.

The `stack` keyword argument controls stacking of array-valued elements; see
[`_raw_to_user_data(::FlexiChain, ...)`](@ref) for details.

!!! important
    This function performs no checks to make sure that the lengths of the indices stored in
the chain line up with the size of the matrix.
"""
function _raw_to_user_data(
    fs::FlexiSummary{TKey,TIIdx,TCIdx,TSIdx},
    arr::Array{<:Any,3};
    name=DD.NoName(),
    stack=nothing,
) where {TKey,TIIdx,TCIdx,TSIdx}
    new_dims, dim_indices_to_drop = _get_summary_dims(fs)
    dropped_arr = dropdims(arr; dims=dim_indices_to_drop)
    # If dropped_arr is a 0-dimensional array, return the scalar itself
    isempty(new_dims) && return dropped_arr[]
    # Otherwise we need to check if we need to stack it
    dimarr = DD.DimArray(dropped_arr, tuple(new_dims...); name=name)
    if eltype(dropped_arr) <: DD.DimArray && stack === nothing
        @warn _STACK_DEPWARN_MSG
        stack = true
    end
    return if stack === true && eltype(dropped_arr) <: AbstractArray
        _stack_arrays(dimarr; name=name)
    else
        dimarr
    end
end

"""
    _replace_data(summary::FlexiSummary, new_keytype, new_data)

Construct a new `FlexiSummary` with the same indices as `summary`, but with `new_data`. Note
that the key type of the resulting FlexiSummary must be specified, and must be consistent
with `new_data`.

!!! danger
    Do not use this function unless you are very sure of what you are doing!
"""
function _replace_data(summary::FlexiSummary, ::Type{newkey}, new_data) where {newkey}
    return FlexiSummary{newkey}(
        new_data,
        summary._iter_indices,
        summary._chain_indices,
        summary._stat_indices,
        summary._drop_stat_dim,
    )
end

"""
    FlexiChains.ChainDimAware(f)

Wrapper marking a summary function `f` which must be given the full `(iter, chain)` matrix of
samples, rather than a flat vector of all the samples stacked together.

Most summary functions (`mean`, `std`, `quantile`, ...) do not care which chain a sample came
from, so when [`FlexiChains.collapse`](@ref) collapses them its irrelevant; the function works
regardless of chain structure. MCMC convergence diagnostics are different: R-hat and the effective 
sample size are defined in terms of the variation between chains, and silently return wrong answers 
if the chain labels are discarded. Wrapping such a function in `ChainDimAware` tells `collapse` to
pass the uncollapsed matrix instead.
"""
struct ChainDimAware{F} <: Function
    f::F
end
(c::ChainDimAware)(x) = c.f(x)
Base.Symbol(c::ChainDimAware) = Symbol(c.f)

_apply_to_all(f, v) = f(v[:])
_apply_to_all(c::ChainDimAware, v) = c.f(v)

function _get_names_and_funcs(names_or_funcs::AbstractVector)
    names = Symbol[]
    funcs = Function[]
    for nf in names_or_funcs
        if nf isa Function
            push!(names, Symbol(nf))
            push!(funcs, nf)
        elseif nf isa Tuple{Symbol,Function}
            push!(names, nf[1])
            push!(funcs, nf[2])
        else
            throw(
                ArgumentError(
                    "each element of `funcs` must be a Function or a (Symbol, Function) tuple",
                ),
            )
        end
    end
    # check that there are no repeats
    if length(names) != length(unique(names))
        throw(ArgumentError("function names must be unique"))
    end
    return names, funcs
end
function _get_expected_size(niters::Int, nchains::Int, collapsed_dims::Symbol)
    return if collapsed_dims == :iter
        (1, nchains)
    elseif collapsed_dims == :chain
        (niters, 1)
    elseif collapsed_dims == :both
        (1, 1)
    else
        throw(ArgumentError("`dims` must be `:iter`, `:chain`, or `:both`"))
    end
end

struct CollapseFailedError{T} <: Exception
    key::T
end

"""
    FlexiChains.collapse(
        chain::FlexiChain,
        funcs::AbstractVector;
        dims::Symbol=:both,
        warn::Bool=true,
        drop_stat_dim::Bool=false,
    )

Low-level function to collapse one or both dimensions of a `FlexiChain` by applying a list
of summary functions.

The `funcs` argument must be a vector which contains either:
 - tuples of the form `(statistic_name::Symbol, func::Function)`; or
 - just functions, in which case the statistic name is obtained from the function name.

The `dims` keyword argument specifies which dimensions to collapse. By default, `dims` is
`:both`, which collapses both the iteration and chain dimensions. Other valid values are
`:iter` or `:chain`, which respectively collapse only the iteration or chain dimension.

**The functions in `funcs` must map a vector to a single value.** For example, both
`Statistics.mean` and `Statistics.std` satisfy this:

```julia
using FlexiChains: collapse
using Statistics: mean, std

collapse(chn, [mean, std]; dims=:both)
```

If `dims=:iter` or `dims=:chain` are selected, then the functions are automatically applied
to each column or row as appropriate. No adjustment to the functions is necessary:

```julia
collapse(chn, [mean, std]; dims=:iter)
collapse(chn, [mean, std]; dims=:chain)
```

For `dims=:both`, the function is applied to all the samples stacked together as a single
vector. Functions which need to know which chain each sample came from -- such as MCMC
convergence diagnostics -- must be wrapped in `FlexiChains.ChainDimAware`.

Sometimes, for more complicated functions like `quantile`, you have to pass an anonymous
function (such as `x -> quantile(x, 0.05)` or a closure (such as `Base.Fix2(quantile,
0.05)`). In this case, to get a sensible statistic name, instead of just passing the function
you can pass a tuple of the form `(statistic_name::Symbol, func::Function)`.

```julia
collapse(chn, [
    mean,
    std,
    (:q5, x -> quantile(x, 0.05)),
    (:q95, x -> quantile(x, 0.95)),
])
```

If a statistic function errors when applied to a key, that key is skipped and a warning
is issued. The warning can be suppressed by setting `warn=false`.

If the `drop_stat_dim` keyword argument is `true` and only one function is provided in
`funcs`, then the resulting `FlexiSummary` will have the `stat` dimension dropped. This allows
for easier indexing into the result when only one statistic is computed. It is an error to set
`drop_stat_dim=true` when more than one function is provided.
"""
function collapse(
    chain::FlexiChain{TKey},
    funcs::AbstractVector;
    dims::Symbol=:both,
    warn::Bool=true,
    split_varnames::Bool=true,
    drop_stat_dim::Bool=false,
) where {TKey}
    if split_varnames
        chain, _ = FlexiChains._split_varnames(chain)
    end
    data = OrderedDict{ParameterOrExtra{<:TKey},AbstractArray{<:Any,3}}()
    names, funcs = _get_names_and_funcs(funcs)
    expected_size = _get_expected_size(niters(chain), nchains(chain), dims)
    # Not proud of this function, but it does what it needs to do... sigh.
    for (k, v) in chain._data
        try
            at_least_one_summary_func_succeeded = false
            output = Array{Any,3}(undef, (expected_size..., length(funcs)))
            for (i, f) in enumerate(funcs)
                try
                    collapsed = if dims == :both
                        # note: [_apply_to_all(f, v);;] doesn't work if the result is a vector
                        reshape([_apply_to_all(f, v)], 1, 1)
                    elseif dims == :iter
                        # mapslices(f, v; dims=1)
                        # again the above doesn't work if v contains vectors!
                        reshape(f.(eachcol(v)), 1, size(v, 2))
                    elseif dims == :chain
                        # mapslices(f, v; dims=2)
                        reshape(f.(eachrow(v)), size(v, 1), 1)
                    else
                        throw(ArgumentError("`dims` must be `:iter`, `:chain`, or `:both`"))
                    end
                    output[:, :, i] = collapsed
                    at_least_one_summary_func_succeeded = true
                catch
                    output[:, :, i] = fill(missing, expected_size)
                end
            end
            at_least_one_summary_func_succeeded || throw(CollapseFailedError(k))
            data[k] = map(identity, output)
        catch e
            if e isa CollapseFailedError
                warn &&
                    @warn "skipping key `$(e.key)` as no summary function could be applied to it"
            else
                rethrow()
            end
        end
    end
    if drop_stat_dim && length(funcs) != 1
        throw(
            ArgumentError(
                "`drop_stat_dim=true` only allowed when one function is provided",
            ),
        )
    end
    iter_idxs = dims == :chain ? FlexiChains.iter_indices(chain) : nothing
    chain_idxs = dims == :iter ? FlexiChains.chain_indices(chain) : nothing
    stat_lookup = _make_categorical(names)
    return FlexiSummary{TKey}(data, iter_idxs, chain_idxs, stat_lookup, drop_stat_dim)
end

function _stat_docstring(func_name, short_name)
    return """
        $(func_name)(
            chain::FlexiChain{TKey};
            dims::Symbol=:both,
            warn::Bool=true,
            split_varnames::Bool=true,
            kwargs...
        ) where {TKey}

    Calculate the $(short_name) across all iterations and chains for each key in
    the `chain`. If the statistic cannot be computed for a key, that key is
    skipped and a warning is issued (which can be suppressed by setting
    `warn=false`).

    The `dims` keyword argument specifies which dimensions to collapse. The default value
    of `:both` collapses both the iteration and chain dimensions. Other valid values are
    `:iter` or `:chain`, which respectively collapse only the iteration or chain dimension.

    The `split_varnames` keyword argument, if `true`, will first split up variables in the
    chain such that each key corresponds to a single scalar value. This is only supported
    for chains with `TKey<:VarName` or `TKey==Symbol`; for other key types this will be a
    no-op as long as the data already contain scalar values for every key, but will error if
    the data contain non-scalar values.

    Other keyword arguments are forwarded to [`$(func_name)`](@extref); please see its
    documentation for details of supported keyword arguments.
    """
end

"""
    @_forward_stat(func)

Helper macro to define the functions `func(chain; dims, warn, kwargs...)`.
"""
macro _forward_stat(func)
    return quote
        function $(esc(func))(
            chn::FlexiChain{TKey};
            dims::Symbol=:both,
            warn::Bool=true,
            split_varnames::Bool=true,
            kwargs...,
        ) where {TKey}
            return collapse(
                chn,
                [(Symbol($(esc(func))), x -> $(esc(func))(x; kwargs...))];
                dims=dims,
                split_varnames=split_varnames,
                warn=warn,
                drop_stat_dim=true,
            )
        end
    end
end

"""
    @_forward_diagnostic(func)

As [`@_forward_stat`](@ref), but for MCMC diagnostics.
"""
macro _forward_diagnostic(func)
    return quote
        function $(esc(func))(
            chn::FlexiChain{TKey};
            dims::Symbol=:both,
            warn::Bool=true,
            split_varnames::Bool=true,
            kwargs...,
        ) where {TKey}
            return collapse(
                chn,
                [(Symbol($(esc(func))), ChainDimAware(x -> $(esc(func))(x; kwargs...)))];
                dims=dims,
                split_varnames=split_varnames,
                warn=warn,
                drop_stat_dim=true,
            )
        end
    end
end

"""
$(_stat_docstring("Statistics.mean", "mean"))
"""
@_forward_stat Statistics.mean
"""
$(_stat_docstring("Statistics.median", "median"))
"""
@_forward_stat Statistics.median
"""
$(_stat_docstring("Statistics.std", "standard deviation"))
"""
@_forward_stat Statistics.std
"""
$(_stat_docstring("Statistics.var", "variance"))
"""
@_forward_stat Statistics.var
"""
$(_stat_docstring("Base.minimum", "minimum"))
"""
@_forward_stat Base.minimum
"""
$(_stat_docstring("Base.maximum", "maximum"))
"""
@_forward_stat Base.maximum
"""
$(_stat_docstring("Base.sum", "sum"))
"""
@_forward_stat Base.sum
"""
$(_stat_docstring("Base.prod", "product"))
"""
@_forward_stat Base.prod
"""
$(_stat_docstring("MCMCDiagnosticTools.ess", "effective sample size"))
"""
@_forward_diagnostic MCMCDiagnosticTools.ess
"""
$(_stat_docstring("MCMCDiagnosticTools.rhat", "R-hat diagnostic"))
"""
@_forward_diagnostic MCMCDiagnosticTools.rhat
"""
$(_stat_docstring("MCMCDiagnosticTools.mcse", "Monte Carlo standard error"))
"""
@_forward_diagnostic MCMCDiagnosticTools.mcse
"""
$(_stat_docstring("StatsBase.mad", "median absolute deviation"))
"""
@_forward_stat StatsBase.mad
"""
$(_stat_docstring("StatsBase.geomean", "geometric mean"))
"""
@_forward_stat StatsBase.geomean
"""
$(_stat_docstring("StatsBase.harmmean", "harmonic mean"))
"""
@_forward_stat StatsBase.harmmean
"""
$(_stat_docstring("StatsBase.iqr", "interquartile range"))
"""
@_forward_stat StatsBase.iqr

# Quantile is just different! Grr.
"""
    Statistics.quantile(
        chain::FlexiChain{TKey},
        p;
        dims::Symbol=:both,
        warn::Bool=true,
        split_varnames::Bool=true,
        kwargs...
    ) where {TKey}

Calculate the quantile across all iterations and chains for each key in the `chain`. If it
cannot be computed for a key, that key is skipped and a warning is issued (which can be
suppressed by setting `warn=false`).

The `dims` keyword argument specifies which dimensions to collapse.
- `:iter`: collapse the iteration dimension only
- `:chain`: collapse the chain dimension only
- `:both`: collapse both the iteration and chain dimensions (default)

The argument `p` specifies the quantile to compute, and is forwarded to
`Statistics.quantile`, along with any other keyword arguments.
"""
function Statistics.quantile(
    chn::FlexiChain{TKey},
    p;
    dims::Symbol=:both,
    warn::Bool=true,
    split_varnames::Bool=true,
    kwargs...,
) where {TKey}
    funcs = if dims == :both
        # quantile only acts on a vector so we have to linearise the matrix x
        [(:quantile, x -> Statistics.quantile(x[:], p; kwargs...))]
    elseif dims == :iter
        [(:quantile, x -> mapslices(c -> Statistics.quantile(c, p; kwargs...), x; dims=1))]
    elseif dims == :chain
        [(:quantile, x -> mapslices(r -> Statistics.quantile(r, p; kwargs...), x; dims=2))]
    else
        throw(ArgumentError("`dims` must be `:iter`, `:chain`, or `:both`"))
    end
    return collapse(
        chn,
        funcs;
        dims=dims,
        split_varnames=split_varnames,
        warn=warn,
        drop_stat_dim=true,
    )
end

"""
    StatsBase.summarystats(
        chain::FlexiChain{TKey};
        split_varnames::Bool=true,
        warn::Bool=true,
    ) where {TKey}

Compute a standard set of summary statistics for each key in the `chain`. The statistics include:

- mean (using [`Statistics.mean`](@extref))
- standard deviation ([`Statistics.std`](@extref))
- Monte Carlo standard error ([`MCMCDiagnosticTools.mcse`](@extref))
- bulk effective sample size ([`MCMCDiagnosticTools.ess`](@extref))
- tail effective sample size
- R-hat diagnostic ([`MCMCDiagnosticTools.rhat`](@extref))
- 5th, 50th (median), and 95th percentiles ([`Statistics.quantile`](@extref))

The `split_varnames` keyword argument, if `true`, will first split up variables in the chain
such that each key corresponds to a single scalar value. The splitting is only supported for
chains with `TKey<:VarName` or `TKey==Symbol`; for other key types, this will be a no-op as
long as the data already contain scalar values for every key, but will error if the data
contain non-scalar values.

If any of the statistics cannot be computed for a key, a `missing` value is returned. If
_none_ of the statistics can be computed for a key, that key will be dropped from the
resulting `FlexiSummary`, and a warning issued. The warning can be suppressed by setting
`warn=false`.
"""
function StatsBase.summarystats(
    chain::FlexiChain{TKey};
    split_varnames::Bool=true,
    warn::Bool=true,
) where {TKey}
    _DEFAULT_SUMMARYSTAT_FUNCTIONS = [
        (:mean, Statistics.mean),
        (:std, Statistics.std),
        (:mcse, ChainDimAware(MCMCDiagnosticTools.mcse)),
        (:ess_bulk, ChainDimAware(x -> MCMCDiagnosticTools.ess(x; kind=:bulk))),
        (:ess_tail, ChainDimAware(x -> MCMCDiagnosticTools.ess(x; kind=:tail))),
        (:rhat, ChainDimAware(MCMCDiagnosticTools.rhat)),
        (:q5, x -> Statistics.quantile(x, 0.05)),
        (:q50, x -> Statistics.quantile(x, 0.5)),
        (:q95, x -> Statistics.quantile(x, 0.95)),
    ]
    return collapse(
        chain,
        _DEFAULT_SUMMARYSTAT_FUNCTIONS;
        dims=:both,
        split_varnames=split_varnames,
        warn=warn,
    )
end
