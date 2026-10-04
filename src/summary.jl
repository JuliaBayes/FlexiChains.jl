using Printf: @sprintf
using Statistics: Statistics
using StatsBase: StatsBase
using MCMCDiagnosticTools: MCMCDiagnosticTools

@public FlexiSummary, collapse
@public CollapseFunction, CollapseFunctionVec, CollapseFunctionDiagnostic

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
    FlexiChains.CollapseFunction(name::Symbol, over_chain_iter, over_chain, over_iter)
    FlexiChains.CollapseFunction(over_chain_iter, over_chain, over_iter)

A summary statistic that can be passed to [`FlexiChains.collapse`](@ref). It bundles together
three functions, one for each way that the `(iter, chain)` dimensions of a `FlexiChain` can
be collapsed. Each function receives the full `(iter, chain)` matrix of samples for a single
key, and must return:

 - `over_chain_iter`: a single summary value (used for `dims=:both`);
 - `over_chain`: one value per iteration, i.e. a vector of length `niters` or an `(niters, 1)`
   matrix (used for `dims=:chain`);
 - `over_iter`: one value per chain, i.e. a vector of length `nchains` or a `(1, nchains)`
   matrix (used for `dims=:iter`).

Any of these may be `nothing`, which indicates that the statistic cannot be computed when
collapsing over those dimensions. In that case, `collapse` throws an `ArgumentError` if the
corresponding `dims` is requested.

`name` is the name of the statistic in the resulting `FlexiSummary`. If it is not provided,
it is obtained from the first function which is not `nothing`.

For example, the mean can be expressed as

```julia
using Statistics: mean
CollapseFunction(mean, m -> mean(m; dims=2), m -> mean(m; dims=1))
```

Most of the time, you will not need to construct this directly, and can instead use one of
the following shortcuts:

 - [`FlexiChains.CollapseFunctionVec`](@ref), for functions which map a vector to a single
   value (e.g. `mean`, `quantile`);
 - [`FlexiChains.CollapseFunctionDiagnostic`](@ref), for MCMC diagnostics which need to know
   which chain each sample came from (e.g. `rhat`, `ess`).
"""
struct CollapseFunction{F1,F2,F3}
    name::Symbol
    over_chain_iter::F1
    over_chain::F2
    over_iter::F3
end
function CollapseFunction(over_chain_iter, over_chain, over_iter)
    fs = (over_chain_iter, over_chain, over_iter)
    i = findfirst(!isnothing, fs)
    i === nothing &&
        throw(ArgumentError("a CollapseFunction must have at least one non-`nothing` field"))
    return CollapseFunction(Symbol(fs[i]), over_chain_iter, over_chain, over_iter)
end

"""
    FlexiChains.CollapseFunctionVec(f, args...; kwargs...)

Construct a [`FlexiChains.CollapseFunction`](@ref) from a function `f` which maps a vector to
a single value, like `Statistics.mean` or `Statistics.quantile`. When collapsing over both
dimensions, `f` is applied to all samples stacked together into a single vector; otherwise it
is applied to each row (`dims=:chain`) or column (`dims=:iter`) of the `(iter, chain)` matrix.
This is equivalent to

```julia
CollapseFunction(
    Symbol(f),
    m -> f(vec(m), args...; kwargs...),
    m -> map(r -> f(r, args...; kwargs...), eachrow(m)),
    m -> map(c -> f(c, args...; kwargs...), eachcol(m)),
)
```

Note that this discards the information about which chain each sample came from when
collapsing over both dimensions. For MCMC diagnostics, which depend on this information, use
[`FlexiChains.CollapseFunctionDiagnostic`](@ref) instead.
"""
function CollapseFunctionVec(f, args...; kwargs...)
    return CollapseFunction(
        Symbol(f),
        m -> f(vec(m), args...; kwargs...),
        m -> map(r -> f(r, args...; kwargs...), eachrow(m)),
        m -> map(c -> f(c, args...; kwargs...), eachcol(m)),
    )
end

"""
    FlexiChains.CollapseFunctionDiagnostic(f, args...; kwargs...)

Construct a [`FlexiChains.CollapseFunction`](@ref) from an MCMC diagnostic function `f`, such
as `MCMCDiagnosticTools.rhat` or `MCMCDiagnosticTools.ess`, which takes an `(iter, chain)`
matrix of samples and returns a single value.

 - When collapsing over both dimensions, `f` is applied to the full `(iter, chain)` matrix, so
   that it can make use of the chain structure.
 - When collapsing over iterations only (`dims=:iter`), `f` is applied to each chain
   separately.
 - Collapsing over chains only (`dims=:chain`) is not supported, since a diagnostic computed
   across chains at a single iteration is not meaningful.

This is equivalent to

```julia
CollapseFunction(
    Symbol(f),
    m -> f(m, args...; kwargs...),
    nothing,
    m -> map(c -> f(c, args...; kwargs...), eachcol(m)),
)
```
"""
function CollapseFunctionDiagnostic(f, args...; kwargs...)
    return CollapseFunction(
        Symbol(f),
        m -> f(m, args...; kwargs...),
        nothing,
        m -> map(c -> f(c, args...; kwargs...), eachcol(m)),
    )
end

function _get_collapse_func(cf::CollapseFunction, dims::Symbol)
    return if dims == :both
        cf.over_chain_iter
    elseif dims == :chain
        cf.over_chain
    elseif dims == :iter
        cf.over_iter
    else
        throw(ArgumentError("`dims` must be `:iter`, `:chain`, or `:both`"))
    end
end

function _get_names_and_funcs(names_or_funcs::AbstractVector)
    names = Symbol[]
    funcs = CollapseFunction[]
    for nf in names_or_funcs
        if nf isa CollapseFunction
            push!(names, nf.name)
            push!(funcs, nf)
        elseif nf isa Tuple{Symbol,CollapseFunction}
            push!(names, nf[1])
            push!(funcs, nf[2])
        else
            throw(
                ArgumentError(
                    "each element of `funcs` must be a `FlexiChains.CollapseFunction` or a " *
                    "`(Symbol, CollapseFunction)` tuple; to convert an ordinary function `f` " *
                    "that maps a vector to a single value, use " *
                    "`FlexiChains.CollapseFunctionVec(f)`",
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
    _reshape_collapsed(result, expected_size::NTuple{2,Int}, dims::Symbol)

Reshape the output of a `CollapseFunction` field into a matrix of size `expected_size`.
"""
function _reshape_collapsed(result, expected_size::NTuple{2,Int}, dims::Symbol)
    # note: [result;;] doesn't work if the result is a vector
    dims == :both && return reshape([result], 1, 1)
    if !(result isa AbstractArray) || length(result) != prod(expected_size)
        throw(
            DimensionMismatch(
                "collapsing with `dims=$(repr(dims))` should return an array with $(prod(expected_size)) elements",
            ),
        )
    end
    return reshape(result, expected_size)
end

"""
    FlexiChains.collapse(
        chain::FlexiChain,
        funcs::AbstractVector;
        dims::Symbol=:both,
        warn::Bool=true,
        split_varnames::Bool=true,
        drop_stat_dim::Bool=false,
    )

Low-level function to collapse one or both dimensions of a `FlexiChain` by applying a list
of summary statistics.

The `funcs` argument must be a vector which contains either:
 - tuples of the form `(statistic_name::Symbol, func::FlexiChains.CollapseFunction)`; or
 - just [`FlexiChains.CollapseFunction`](@ref)s, in which case the statistic name is obtained
   from the name of the underlying function.

The `dims` keyword argument specifies which dimensions to collapse. By default, `dims` is
`:both`, which collapses both the iteration and chain dimensions. Other valid values are
`:iter` or `:chain`, which respectively collapse only the iteration or chain dimension.

A `CollapseFunction` specifies how to compute a statistic for each of the three possible
values of `dims`. Ordinary functions can be converted to `CollapseFunction`s using one of
the following shortcuts:

 - [`FlexiChains.CollapseFunctionVec`](@ref) for functions that map a vector to a single
   value, such as `Statistics.mean`;
 - [`FlexiChains.CollapseFunctionDiagnostic`](@ref) for MCMC diagnostics, such as
   `MCMCDiagnosticTools.rhat`.

```julia
using FlexiChains: collapse, CollapseFunctionVec
using Statistics: mean, std

collapse(chn, [CollapseFunctionVec(mean), CollapseFunctionVec(std)]; dims=:both)
collapse(chn, [CollapseFunctionVec(mean), CollapseFunctionVec(std)]; dims=:iter)
```

Positional and keyword arguments passed to the shortcut constructors are forwarded to the
underlying function. Sometimes the inferred statistic name is not what you want (for example,
if you calculate several quantiles). In this case, you can pass a tuple of the form
`(statistic_name::Symbol, func::CollapseFunction)`:

```julia
using FlexiChains: CollapseFunctionVec
using Statistics: quantile

collapse(chn, [
    CollapseFunctionVec(mean),
    CollapseFunctionVec(std),
    (:q5, CollapseFunctionVec(quantile, 0.05)),
    (:q95, CollapseFunctionVec(quantile, 0.95)),
])
```

If a statistic function errors when applied to a key, the value for that statistic is
`missing`. If all statistic functions error for a key, that key is skipped and a warning
is issued. The warning can be suppressed by setting `warn=false`.

If any `CollapseFunction` does not support the requested `dims` (i.e., the corresponding field
is `nothing`), an `ArgumentError` is thrown. If a `CollapseFunction` returns an output of the
wrong size, a `DimensionMismatch` is thrown.

The `split_varnames` keyword argument, if `true`, will first split up variables in the
chain such that each key corresponds to a single scalar value.

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
    names, funcs = _get_names_and_funcs(funcs)
    if drop_stat_dim && length(funcs) != 1
        throw(
            ArgumentError(
                "`drop_stat_dim=true` only allowed when one function is provided",
            ),
        )
    end
    expected_size = _get_expected_size(niters(chain), nchains(chain), dims)
    fs = map(cf -> _get_collapse_func(cf, dims), funcs)
    for (name, f) in zip(names, fs)
        if f === nothing
            throw(
                ArgumentError(
                    "the statistic `$name` does not support collapsing with `dims=$(repr(dims))`",
                ),
            )
        end
    end
    if split_varnames
        chain, _ = FlexiChains._split_varnames(chain)
    end
    data = OrderedDict{ParameterOrExtra{<:TKey},AbstractArray{<:Any,3}}()
    for (k, v) in chain._data
        try
            at_least_one_summary_func_succeeded = false
            output = Array{Any,3}(undef, (expected_size..., length(fs)))
            for (i, f) in enumerate(fs)
                result = try
                    f(v)
                catch
                    output[:, :, i] = fill(missing, expected_size)
                    continue
                end
                # this is outside the try block so that a wrongly-shaped output is reported
                # rather than being silently replaced with `missing`
                output[:, :, i] = _reshape_collapsed(result, expected_size, dims)
                at_least_one_summary_func_succeeded = true
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
    @_forward_stat(make_collapse_func, func)

Helper macro to define the functions `func(chain; dims, warn, kwargs...)`, where
`make_collapse_func` is one of the shortcut constructors for [`CollapseFunction`](@ref) (e.g.
`CollapseFunctionVec`), which determines how `func` is applied to the samples.
"""
macro _forward_stat(make_collapse_func, func)
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
                [$(esc(make_collapse_func))($(esc(func)); kwargs...)];
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
@_forward_stat CollapseFunctionVec Statistics.mean
"""
$(_stat_docstring("Statistics.median", "median"))
"""
@_forward_stat CollapseFunctionVec Statistics.median
"""
$(_stat_docstring("Statistics.std", "standard deviation"))
"""
@_forward_stat CollapseFunctionVec Statistics.std
"""
$(_stat_docstring("Statistics.var", "variance"))
"""
@_forward_stat CollapseFunctionVec Statistics.var
"""
$(_stat_docstring("Base.minimum", "minimum"))
"""
@_forward_stat CollapseFunctionVec Base.minimum
"""
$(_stat_docstring("Base.maximum", "maximum"))
"""
@_forward_stat CollapseFunctionVec Base.maximum
"""
$(_stat_docstring("Base.sum", "sum"))
"""
@_forward_stat CollapseFunctionVec Base.sum
"""
$(_stat_docstring("Base.prod", "product"))
"""
@_forward_stat CollapseFunctionVec Base.prod
"""
$(_stat_docstring("MCMCDiagnosticTools.ess", "effective sample size"))

!!! note
    `dims=:chain` is not supported, since the effective sample size cannot be meaningfully
    computed across chains at a single iteration.
"""
@_forward_stat CollapseFunctionDiagnostic MCMCDiagnosticTools.ess
"""
$(_stat_docstring("MCMCDiagnosticTools.rhat", "R-hat diagnostic"))

!!! note
    `dims=:chain` is not supported, since R-hat cannot be meaningfully computed across chains
    at a single iteration.
"""
@_forward_stat CollapseFunctionDiagnostic MCMCDiagnosticTools.rhat
"""
$(_stat_docstring("MCMCDiagnosticTools.mcse", "Monte Carlo standard error"))

!!! note
    `dims=:chain` is not supported, since the Monte Carlo standard error cannot be
    meaningfully computed across chains at a single iteration.
"""
@_forward_stat CollapseFunctionDiagnostic MCMCDiagnosticTools.mcse
"""
$(_stat_docstring("StatsBase.mad", "median absolute deviation"))
"""
@_forward_stat CollapseFunctionVec StatsBase.mad
"""
$(_stat_docstring("StatsBase.geomean", "geometric mean"))
"""
@_forward_stat CollapseFunctionVec StatsBase.geomean
"""
$(_stat_docstring("StatsBase.harmmean", "harmonic mean"))
"""
@_forward_stat CollapseFunctionVec StatsBase.harmmean
"""
$(_stat_docstring("StatsBase.iqr", "interquartile range"))
"""
@_forward_stat CollapseFunctionVec StatsBase.iqr

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
    return collapse(
        chn,
        [(:quantile, CollapseFunctionVec(Statistics.quantile, p; kwargs...))];
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
        (:mean, CollapseFunctionVec(Statistics.mean)),
        (:std, CollapseFunctionVec(Statistics.std)),
        (:mcse, CollapseFunctionDiagnostic(MCMCDiagnosticTools.mcse)),
        (:ess_bulk, CollapseFunctionDiagnostic(MCMCDiagnosticTools.ess; kind=:bulk)),
        (:ess_tail, CollapseFunctionDiagnostic(MCMCDiagnosticTools.ess; kind=:tail)),
        (:rhat, CollapseFunctionDiagnostic(MCMCDiagnosticTools.rhat)),
        (:q5, CollapseFunctionVec(Statistics.quantile, 0.05)),
        (:q50, CollapseFunctionVec(Statistics.quantile, 0.5)),
        (:q95, CollapseFunctionVec(Statistics.quantile, 0.95)),
    ]
    return collapse(
        chain,
        _DEFAULT_SUMMARYSTAT_FUNCTIONS;
        dims=:both,
        split_varnames=split_varnames,
        warn=warn,
    )
end
