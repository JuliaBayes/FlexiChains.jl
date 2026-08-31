# Utilities for 'flattening' chains.
import Tables
using LinearAlgebra: Cholesky

"""
    FlexiChains._split_varnames(
        cs::ChainOrSummary{<:VarName};
        collect_plot_names::Bool=false
    )

Split up a chain, which in general may contain array- or other-valued parameters, into a
chain containing only scalar-valued parameters. This is done by replacing the original
`VarName` keys with appropriate _leaves_. For example, if `x` is a vector-valued parameter,
then it is replaced by `x[1]`, `x[2]`, etc.

This function is only used for summarising and plotting: note that calling this on an
original chain, and subsequently using that chain for functions such as `returned` or
`predict`, **will** lead to errors!

Returns a tuple of the new chain and a dictionary which maps the new `VarName` keys to
'pretty names' (i.e., Strings) used for plot labels. Ordinarily, plot labels are obtained by
just converting the `VarName` to a String, but for DimVector parameters, we use the labels
stored inside the DimVector itself. For all other parameters the plot label is just the
default.

If `collect_plot_names` is `false`, then the dictionary will always be empty.
"""
function _split_varnames(cs::ChainOrSummary{<:VarName}; collect_plot_names::Bool=false)
    vns = OrderedSet{VarName}()
    plot_names = Dict{VarName,String}()
    for vn in FlexiChains.parameters(cs)
        d = _get_raw_data(cs, Parameter(vn))
        if _elems_have_fixed_vn_leaves(d)
            # Don't need to iterate over all array elements - just check the first one.
            # (Note that `d` could be Array{T,2} or Array{T,3} depending on whether `cs` is
            # a chain or summary.)
            d1 = first(d)
            vn_leaves = AbstractPPL.varname_leaves(vn, d1)
            for vn_leaf in vn_leaves
                push!(vns, vn_leaf)
            end
            if collect_plot_names && eltype(d) <: DD.DimVector
                dim = DD.dims(d1, 1)
                label_type = eltype(dim)
                if (label_type === Symbol || label_type <: AbstractString)
                    for (vn_leaf, label) in zip(vn_leaves, dim)
                        prettylabel = label isa Symbol ? repr(label) : label
                        plot_names[vn_leaf] = string(vn, "[", prettylabel, "]")
                    end
                end
            end
        else
            for i in eachindex(d)
                for vn_leaf in AbstractPPL.varname_leaves(vn, d[i])
                    push!(vns, vn_leaf)
                end
            end
        end
    end
    return cs[[collect(vns)..., FlexiChains.extras(cs)...]], plot_names
end

# This helper function identifies cases where we don't need to check every single Niters x
# Nchains elements, because they all have the same structure.
_elems_have_fixed_vn_leaves(data::Array{T}) where {T<:Real} = !isempty(data)
_elems_have_fixed_vn_leaves(data::Array{T}) where {T<:AbstractString} = !isempty(data)
_elems_have_fixed_vn_leaves(data::Array{Symbol}) = !isempty(data)
function _elems_have_fixed_vn_leaves(data::Array{T}) where {T<:AbstractArray}
    # If `T` is not even a concrete type, e.g. it's a Union of two different
    # AbstractArray types, then we have no hope.
    (isconcretetype(T) && !isempty(data)) || return false
    # Checking axes is no less expensive than checking size, and axes works better because
    # it catches things like OffsetArrays which have the same size but different offsets.
    a = axes(first(data))
    return all(x -> axes(x) == a, data)
end
function _elems_have_fixed_vn_leaves(data::Array{T}) where {T<:Cholesky}
    (isconcretetype(T) && !isempty(data)) || return false
    f = first(data)
    a = axes(f)
    ul = f.uplo
    return all(x -> axes(x) == a && x.uplo == ul, data)
end
_elems_have_fixed_vn_leaves(::Array) = false  # Fallback.

"""
    FlexiChains._split_varnames(
        cs::ChainOrSummary{Union{Symbol,<:AbstractString}};
        collect_plot_names::Bool=false
    )

For `Symbol`-keyed chains, convert keys to `VarName`, split array-valued parameters into
scalar leaves, then convert the keys back to `Symbol`.

Likewise for `AbstractString`-keyed chains; the keys are converted back to standard
`String`.
"""
function _split_varnames(cs::ChainOrSummary{Symbol}; collect_plot_names::Bool=false)
    N = cs isa FlexiChain ? 2 : 3
    new_data = OrderedDict{ParameterOrExtra{<:VarName},Array{<:Any,N}}()
    for (k, v) in cs._data
        new_key = k isa Parameter ? Parameter(VarName{k.name}()) : k
        new_data[new_key] = v
    end
    vn_cs = FlexiChains._replace_data(cs, VarName, new_data)
    split_cs, plot_names = _split_varnames(vn_cs; collect_plot_names=collect_plot_names)
    plot_names = Dict{Symbol,String}(Symbol(k) => v for (k, v) in plot_names)
    return FlexiChains.map_parameters(k -> Symbol(k), split_cs), plot_names
end
function _split_varnames(
    cs::ChainOrSummary{<:AbstractString};
    collect_plot_names::Bool=false,
)
    N = cs isa FlexiChain ? 2 : 3
    new_data = OrderedDict{ParameterOrExtra{<:VarName},Array{<:Any,N}}()
    for (k, v) in cs._data
        new_key = k isa Parameter ? Parameter(VarName{Symbol(k.name)}()) : k
        new_data[new_key] = v
    end
    vn_cs = FlexiChains._replace_data(cs, VarName, new_data)
    split_cs, plot_names = _split_varnames(vn_cs; collect_plot_names=collect_plot_names)
    plot_names = Dict{String,String}(String(Symbol(k)) => v for (k, v) in plot_names)
    return FlexiChains.map_parameters(k -> String(Symbol(k)), split_cs), plot_names
end

"""
    FlexiChains._split_varnames(cs::ChainOrSummary; collect_plot_names::Bool=false)

For all other chains that are not keyed by `VarName` or `Symbol`, we check if all keys are
real-valued anyway. If they are, then we can just return the original chain. If not, this
throws an error.
"""
function _split_varnames(cs::ChainOrSummary{T}; collect_plot_names::Bool=false) where {T}
    for (k, v) in cs._data
        if eltype(v) <: Real
            continue
        else
            throw(
                ArgumentError(
                    "key $(k) in the chain has data of type $(eltype(v)), which is not scalar-valued; variable names cannot be split for this chain. Please use a chain with key type VarName or Symbol if you want to use variable name splitting.",
                ),
            )
        end
    end
    return cs, Dict{T,String}() # No plot names to return
end

"""
    DimensionalData.DimArray(
        chain::FlexiChain{TKey};
        warn::Bool=true,
        eltype_filter=Any,
        parameters_only::Bool=true,
        split_varnames::Bool=true,
    ) where {TKey}

Convert a FlexiChain into a 3-dimensional `DimArray` with dimensions `(:iter, :chain,
:param)`.

This proceeds by first splitting array-valued parameters into scalar leaves (if
`split_varnames` is `true`), then extracting all parameters whose element type subtypes
`eltype_filter` and stacking them into a 3D array.

Keys whose values do not subtype `eltype_filter` are skipped (with a warning if
`warn=true`).

If `parameters_only=true` (the default), then two things happen:

- Only parameters (not extras) are included in the `DimArray`. Otherwise, both
  parameters and extras are included.

- The keys in the `:param` dimension of the resulting `DimArray` are just
  `TKey`, i.e., the `Parameter` wrapper is removed. Otherwise, the keys will
  be `Union{Parameter{<:TKey},Extra}`.
"""
function DD.DimArray(
    chain::FlexiChain{TKey};
    warn::Bool=true,
    eltype_filter::Type{T}=Any,
    parameters_only::Bool=true,
    split_varnames::Bool=true,
) where {TKey,T}
    chain::FlexiChain = split_varnames ? first(FlexiChains._split_varnames(chain)) : nothing
    kept_keys = parameters_only ? TKey[] : ParameterOrExtra{<:TKey}[]
    ni, nc = size(chain)
    kept_matrices = Matrix[]
    skipped_keys = ParameterOrExtra{<:TKey}[]
    for (k, v) in chain._data
        if eltype(v) <: T && (!parameters_only || k isa Parameter)
            k = if parameters_only && k isa Parameter
                FlexiChains.get_name(k)
            else
                k
            end
            push!(kept_keys, k)
            push!(kept_matrices, v)
        else
            if !(parameters_only && k isa Extra)
                push!(skipped_keys, k)
            end
        end
    end
    if warn && !isempty(skipped_keys)
        skipped_str = join(("`$k`" for k in skipped_keys), ", ")
        @warn "skipping keys $skipped_str as their values do not subtype $T"
    end
    np = length(kept_matrices)
    np == 0 && @warn "no keys with values subtyping $T found"
    # Here we could call `stack(kept_matrices)` to do mostly the same thing. Unfortunately
    # `stack` aggressively promotes element types, so if there are e.g. continuous
    # and discrete parameters it will promote everything to `Float64`. We work
    # around that by manually filling in an array.
    kept_data = Array{eltype_filter}(undef, ni, nc, np)
    for (i, m) in enumerate(kept_matrices)
        kept_data[:, :, i] = m
    end
    # Concretise as far as possible.
    kept_data = [x for x in kept_data]
    dims = (
        DD.Dim{ITER_DIM_NAME}(iter_indices(chain)),
        DD.Dim{CHAIN_DIM_NAME}(chain_indices(chain)),
        DD.Dim{PARAM_DIM_NAME}(kept_keys),
    )
    return DD.DimArray(kept_data, dims)
end

"""
    Base.Array(
        chain::FlexiChain;
        kwargs...
    )

Convert a `FlexiChain` into a standard `Array` with dimensions `(iter, chain, param)`. This
is the same as the conversion to [`DimensionalData.DimArray`](@ref), except that the
dimension metadata is discarded.

See [`DimensionalData.DimArray(::FlexiChains.FlexiChain)`](@ref) for more details on the
conversion process and available keyword arguments.
"""
function Base.Array(
    chain::FlexiChain{TKey};
    warn::Bool=true,
    eltype_filter::Type{T}=Any,
    parameters_only::Bool=true,
    split_varnames::Bool=true,
) where {TKey,T}
    da = DD.DimArray(chain; warn, eltype_filter, parameters_only, split_varnames)
    return parent(da)
end

"""
    DimensionalData.DimArray(
        summary::FlexiSummary{TKey};
        warn::Bool=true,
        eltype_filter=Any,
        parameters_only::Bool=true,
        split_varnames::Bool=true,
    ) where {TKey}

Convert a `FlexiSummary` into a `DimArray` with a `:param` dimension appended after the
non-collapsed dimensions of the summary. For example:

| Summary produced via                     | Dimensions of resulting `DimArray` |
| :--------------------------------------- | :--------------------------------- |
| `mean(chn)`                              | `(:param)`                         |
| `mean(chn; dims=:iter)`                  | `(:chain, :param)`                 |
| `mean(chn; dims=:chain)`                 | `(:iter, :param)`                  |
| `summarystats(chn)`                      | `(:stat, :param)`                  |
| `collapse(chn, [mean, std]; dims=:iter)` | `(:chain, :stat, :param)`          |

## Keyword arguments

- `split_varnames::Bool=true`: whether to split array-valued statistics into scalar leaves.
  If `true`, then array-valued parameters are split into scalar leaves, e.g. a vector-valued
  statistic for `x` would be split into `x[1]`, `x[2]`, etc.

  **Note:** FlexiChains has no way of knowing whether the vector elements correspond to
  different parts of the _parameter_ (e.g., the mean of `x[i]` for a vector-valued parameter
  `x`) or whether they correspond to different parts of the same _statistic_ (e.g., when
  calculating `quantile` with multiple probabilities, for a scalar parameter `x` the
  result will be a vector). When `split_varnames=true` FlexiChains will always assume the
  former. If you need the latter behaviour you should set `split_varnames=false` and then
  manually perform any data processing you need to do.

- `eltype_filter::Any`: retain only parameters whose values subtype `eltype_filter`.
  For example, if `eltype_filter=Float64`, then integer-valued parameters are dropped.

- `parameters_only::Bool=true`: whether to include only parameters (not extras) in the
  resulting `DimArray`.

- `warn::Bool=true`: whether to issue a warning if any keys are skipped due to their values
  not subtyping `eltype_filter`.
"""
function DD.DimArray(
    summary::FlexiSummary{TKey};
    warn::Bool=true,
    eltype_filter::Type{T}=Any,
    parameters_only::Bool=true,
    split_varnames::Bool=true,
) where {TKey,T}
    summary::FlexiSummary =
        split_varnames ? first(FlexiChains._split_varnames(summary)) : summary
    kept_keys = parameters_only ? TKey[] : ParameterOrExtra{<:TKey}[]
    new_dims, dim_indices_to_drop = _get_summary_dims(summary)
    kept_arrays = AbstractArray[]
    skipped_keys = ParameterOrExtra{<:TKey}[]
    for (k, v) in summary._data
        if eltype(v) <: T && (!parameters_only || k isa Parameter)
            k = if parameters_only && k isa Parameter
                FlexiChains.get_name(k)
            else
                k
            end
            push!(kept_keys, k)
            dropped = if isempty(dim_indices_to_drop)
                v
            else
                dropdims(v; dims=dim_indices_to_drop)
            end
            push!(kept_arrays, dropped)
        else
            if !(parameters_only && k isa Extra)
                push!(skipped_keys, k)
            end
        end
    end
    if warn && !isempty(skipped_keys)
        skipped_str = join(("`$k`" for k in skipped_keys), ", ")
        @warn "skipping keys $skipped_str as their values do not subtype $T"
    end
    np = length(kept_arrays)
    np == 0 && @warn "no keys with values subtyping $T found"
    base_shape = tuple(length.(new_dims)...)
    kept_data = Array{eltype_filter}(undef, base_shape..., np)
    for (i, arr) in enumerate(kept_arrays)
        # This is equivalent to kept_data[:, :, ..., i] = arr but works
        # for any number of dimensions
        selectdim(kept_data, ndims(kept_data), i) .= arr
    end
    kept_data = [x for x in kept_data] # Concretise
    all_dims = (new_dims..., DD.Dim{PARAM_DIM_NAME}(kept_keys))
    return DD.DimArray(kept_data, all_dims)
end

"""
    Base.Array(
        summary::FlexiSummary;
        kwargs...
    )

Convert a `FlexiSummary` into a standard `Array`. This is the same as the conversion to
[`DimensionalData.DimArray`](@ref), except that the dimension metadata is discarded.

See [`DimensionalData.DimArray(::FlexiChains.FlexiSummary)`](@ref) for details.
"""
function Base.Array(
    summary::FlexiSummary{TKey};
    warn::Bool=true,
    eltype_filter::Type{T}=Any,
    parameters_only::Bool=true,
    split_varnames::Bool=true,
) where {TKey,T}
    da = DD.DimArray(summary; warn, eltype_filter, parameters_only, split_varnames)
    return parent(da)
end

function _prepare_chain_or_summary(
    cs::ChainOrSummary;
    split_varnames::Bool=true,
    parameters_only::Bool=true,
)
    if parameters_only
        cs = FlexiChains.subset_parameters(cs)
    end
    if split_varnames
        cs, _ = FlexiChains._split_varnames(cs)
    end
    return cs
end

function _check_duplicate_keys(ks)
    seen = Set{eltype(ks)}()
    duplicates = eltype(ks)[]
    for k in ks
        if k in seen
            push!(duplicates, k)
        else
            push!(seen, k)
        end
    end
    return if !isempty(duplicates)
        throw(
            ArgumentError(
                "duplicate column names after converting keys to Symbols: " *
                join(unique(duplicates), ", "),
            ),
        )
    end
end

const WIDE_LONG_KWARGS_DOC = """
## Keyword arguments

- `split_varnames`: whether to split array-valued parameters into scalar leaves. If `true`
  (the default), then array-valued parameters are split into scalar leaves, e.g. a
  vector-valued parameter `x` would be split into `x[1]`, `x[2]`, etc.

- `parameters_only`: whether to include only parameters (and skip extras) in the resulting
  table. Defaults to `true`.
"""

"""
    FlexiChains.Wide(
        chn::Union{<:FlexiChain,<:FlexiSummary};
        split_varnames::Bool=true,
        parameters_only::Bool=true
    )

A wrapper struct indicating a 'wide' table format. The exact meaning depends on whether the
input is a `FlexiChain` or a `FlexiSummary`. A `FlexiChain` will have each parameter in a
separate column; conversely, a `FlexiSummary` will have each summary statistic in a separate
column.

## Example (`FlexiChain`)

```julia
using Turing, FlexiChains, DataFrames

@model function f()
    x ~ Normal()
    b ~ Bernoulli()
end
chn = sample(f(), Prior(), MCMCThreads(), 10, 2; chain_type=VNChain)

df = DataFrame(Wide(chn))
```

returns a DataFrame that looks like the following. Each parameter is a different column, and
the `iter` and `chain` dimensions are represented as separate columns as well; `iter` varies
faster than `chain`.

!!! note
    Because all parameter names must be converted to `Symbol` for column names, this
    may lead to clashes between e.g. parameters and extras which convert to the same
    `Symbol`. FlexiChains will error in such a situation.

```
20×4 DataFrame
 Row │ iter   chain  x          b
     │ Int64  Int64  Float64    Bool
─────┼────────────────────────────────
   1 │     1      1  -1.38809   false
   2 │     2      1  -0.511805   true
   3 │     3      1  -1.37277   false
  ⋮  │   ⋮      ⋮        ⋮        ⋮
  18 │     8      2   2.31312   false
  19 │     9      2   1.58254    true
  20 │    10      2  -1.14516   false
```

$(WIDE_LONG_KWARGS_DOC)

## Example (`FlexiSummary`)

```julia
julia> df = DataFrame(Wide(summarystats(chn)))
2×10 DataFrame
 Row │ param     mean       std       mcse      ess_bulk  ess_tail  rh ⋯
     │ VarName…  Float64    Float64   Float64   Float64   Float64   Fl ⋯
─────┼──────────────────────────────────────────────────────────────────
   1 │ x         -0.253812  0.987327  0.193554   26.0206    25.641     ⋯
   2 │ b          0.5       0.512989  0.113426   20.4545   NaN      Na
                                                       4 columns omitted

julia> df = DataFrame(Wide(mean(chn)))
2×2 DataFrame
 Row │ param     stat
     │ VarName…  Float64
─────┼─────────────────────
   1 │ x         -0.253812
   2 │ b          0.5
```
"""
struct Wide{F<:ChainOrSummary,N<:NamedTuple}
    cs::F
    # A precomputed mapping from Symbol(get_name(k)) => k for all keys in `cs`.
    symbol_to_keys::N
    # For summaries, a flag to indicate whether or not the keys should be unwrapped
    # for the param column. This isn't an issue for chains because Wide(chn) doesn't
    # have a param column
    parameters_only::Bool

    function Wide(cs::ChainOrSummary; split_varnames::Bool=true, parameters_only::Bool=true)
        cs = _prepare_chain_or_summary(cs; split_varnames, parameters_only)
        # Strip parameter/extra wrappers and convert to Symbol for column names.
        ks = Tuple(keys(cs))
        sym_ks = Symbol.(get_name.(ks))
        _check_duplicate_keys(sym_ks)
        symbol_to_keys = NamedTuple{sym_ks}(ks)
        return new{typeof(cs),typeof(symbol_to_keys)}(cs, symbol_to_keys, parameters_only)
    end
end

"""
    FlexiChains.Long(
        chn::FlexiChain;
        split_varnames::Bool=true,
        parameters_only::Bool=true
    )

A wrapper struct indicating that a `FlexiChain` should be converted to a 'long' table
format, where all values are stacked into a single column, and there is an additional column
indicating the parameter name.

!!! note
    Because all parameter values are stacked into a single column, note that the resulting
    element type of the `value` column will be the common supertype of all parameter values.
    This can cause data to be promoted to a type that is not the same as its original type.
    For example, the `b` parameter below is converted to `Float64`.

## Example

```julia
using Turing, FlexiChains, DataFrames

@model function f()
    x ~ Normal()
    b ~ Bernoulli()
end
chn = sample(f(), Prior(), MCMCThreads(), 10, 2; chain_type=VNChain)

df = DataFrame(Long(chn))
```

returns a DataFrame that looks like the following. The `iter` and `chain` dimensions are
represented as separate columns as before, but now the parameter names are stacked into a
single `param` column, and the values are stacked into a single `value` column.

The `iter` column varies faster than the `chain` column, which in turn varies faster than
the `param` column.

```
40×4 DataFrame
 Row │ iter   chain  param     value
     │ Int64  Int64  VarName…  Float64
─────┼─────────────────────────────────
   1 │     1      1  x         -1.38809
   2 │     2      1  x         -0.511805
   3 │     3      1  x         -1.37277
  ⋮  │   ⋮      ⋮      ⋮         ⋮
  38 │     8      2  b          0.0
  39 │     9      2  b          1.0
  40 │    10      2  b          0.0
```

$(WIDE_LONG_KWARGS_DOC)

Additionally, when `parameters_only=true` (the default), the `Parameter` wrapper is stripped
from keys. Otherwise, the `Parameter`/`Extra` wrappers are retained. If you want to unwrap
them, you can use [`FlexiChains.get_name`](@ref) on the `param` column of the resulting
table.
"""
struct Long{F<:FlexiChain,K<:Tuple}
    chn::F
    # The keys for the param column: unwrapped if parameters_only, wrapped otherwise.
    maybe_unwrapped_keys::K

    function Long(chn::FlexiChain; split_varnames::Bool=true, parameters_only::Bool=true)
        chn = _prepare_chain_or_summary(chn; split_varnames, parameters_only)
        maybe_unwrapped_keys = if parameters_only
            Tuple(FlexiChains.get_name.(keys(chn)))
        else
            Tuple(keys(chn))
        end
        _check_duplicate_keys(maybe_unwrapped_keys)
        return new{typeof(chn),typeof(maybe_unwrapped_keys)}(chn, maybe_unwrapped_keys)
    end
end

Tables.istable(::Type{<:Wide}) = true
Tables.istable(::Type{<:Long}) = true
Tables.columnaccess(::Type{<:Wide}) = true
Tables.columnaccess(::Type{<:Long}) = true

# Default Tables.jl implementation for FlexiChain and FlexiSummary itself
Tables.columns(chn::FlexiChain) = Wide(chn; split_varnames=true, parameters_only=true)
Tables.columns(fs::FlexiSummary) = Wide(fs; split_varnames=true, parameters_only=true)

# Wide chain
Tables.columnnames(s::Wide{<:FlexiChain}) =
    [FlexiChains.ITER_DIM_NAME, FlexiChains.CHAIN_DIM_NAME, keys(s.symbol_to_keys)...]
function Tables.getcolumn(s::Wide{<:FlexiChain}, col::Symbol)
    return if col === FlexiChains.ITER_DIM_NAME
        repeat(iter_indices(s.cs); outer=FlexiChains.nchains(s.cs))
    elseif col === FlexiChains.CHAIN_DIM_NAME
        repeat(chain_indices(s.cs); inner=FlexiChains.niters(s.cs))
    else
        # Because the chain has been constructed via `_prepare_chain_or_summary`, we know
        # that `s.symbol_to_keys[col]` is actually a legitimate key in the raw data
        # dictionary, so we can index directly into the data dict instead of the chain.
        vec(s.cs._data[s.symbol_to_keys[col]])
    end
end
Tables.getcolumn(s::Wide, col::Int) = Tables.getcolumn(s, Tables.columnnames(s)[col])
Tables.columns(s::Wide) = s

# Wide summary
function Tables.columnnames(w::Wide{<:FlexiSummary})
    cols = [FlexiChains.PARAM_DIM_NAME]
    if iter_indices(w.cs) !== nothing
        push!(cols, FlexiChains.ITER_DIM_NAME)
    end
    if chain_indices(w.cs) !== nothing
        push!(cols, FlexiChains.CHAIN_DIM_NAME)
    end
    si = stat_indices(w.cs)
    if si !== nothing
        append!(cols, parent(si))
    else
        push!(cols, FlexiChains.STAT_DIM_NAME)
    end
    return cols
end
function Tables.getcolumn(w::Wide{<:FlexiSummary}, col::Symbol)
    ii = iter_indices(w.cs)
    ci = chain_indices(w.cs)
    si = stat_indices(w.cs)
    nic = if ii === nothing && ci === nothing
        1
    elseif ii === nothing
        length(ci)
    elseif ci === nothing
        length(ii)
    else
        throw(ArgumentError("summary has both iter and chain dimensions; should not happen"))
    end
    nparams = length(w.symbol_to_keys)
    return if col === FlexiChains.PARAM_DIM_NAME
        ks = collect(values(w.symbol_to_keys))
        if w.parameters_only
            ks = FlexiChains.get_name.(ks)
        end
        repeat(ks; inner=nic)
    elseif col === FlexiChains.ITER_DIM_NAME
        ii === nothing && throw(
            ArgumentError("summary does not have an iter dimension; should not happen"),
        )
        repeat(ii; outer=nparams)
    elseif col === FlexiChains.CHAIN_DIM_NAME
        ci === nothing && throw(
            ArgumentError("summary does not have a chain dimension; should not happen"),
        )
        repeat(ci; outer=nparams)
    elseif col === FlexiChains.STAT_DIM_NAME
        if si === nothing
            if ii === nothing && ci === nothing
                [w.cs._data[k][] for k in values(w.symbol_to_keys)]
            else
                vcat([vec(w.cs._data[k]) for k in values(w.symbol_to_keys)]...)
            end
        else
            throw(
                ArgumentError(
                    "summary has a non-collapse stat dimension but :stat column was requested; should not happen",
                ),
            )
        end
    else
        # named stat dimension.
        if si === nothing
            throw(
                ArgumentError("summary does not have a stat dimension; should not happen"),
            )
        else
            if col in parent(si)
                # Perf optimisation. This is equivalent to
                #     get_stat_val(k) = w.cs[k, stat=At(col)]
                # but avoids the overhead of the getindex call when we know for certain
                # that `k` is already a valid key in `w.cs._data`.
                idx = findfirst(==(col), parent(si))
                get_stat_val(k) = w.cs._data[k][:, :, idx]
                if ii === nothing && ci === nothing
                    # get_stat_val returns 1x1x1 array
                    [get_stat_val(k)[] for k in values(w.symbol_to_keys)]
                else
                    # get_stat_val returns iters x 1 x 1 array or 1 x nchains x 1 array
                    stat_vals = [vec(get_stat_val(k)) for k in values(w.symbol_to_keys)]
                    vcat(stat_vals...)
                end
            else
                throw(
                    ArgumentError(
                        "summary does not have a stat named $col; should not happen",
                    ),
                )
            end
        end
    end
end

# Long
const VALUE_COL_NAME = :value
Tables.columnnames(::Long) = [
    FlexiChains.ITER_DIM_NAME,
    FlexiChains.CHAIN_DIM_NAME,
    FlexiChains.PARAM_DIM_NAME,
    VALUE_COL_NAME,
]
function Tables.getcolumn(s::Long, col::Symbol)
    nkeys = length(s.maybe_unwrapped_keys)
    return if col === FlexiChains.ITER_DIM_NAME
        repeat(iter_indices(s.chn); outer=FlexiChains.nchains(s.chn) * nkeys)
    elseif col === FlexiChains.CHAIN_DIM_NAME
        repeat(chain_indices(s.chn); inner=FlexiChains.niters(s.chn), outer=nkeys)
    elseif col === FlexiChains.PARAM_DIM_NAME
        repeat(
            collect(s.maybe_unwrapped_keys);
            inner=FlexiChains.niters(s.chn) * FlexiChains.nchains(s.chn),
        )
    elseif col === VALUE_COL_NAME
        # mapreduce(vcat, ...) is very slow (presumably quadratic behaviour?)
        vs = map(s.maybe_unwrapped_keys) do k
            wrapped_key = k isa ParameterOrExtra ? k : Parameter(k)
            vec(s.chn._data[wrapped_key])
        end
        vcat(vs...)
    else
        throw(ArgumentError("unknown column name: $col"))
    end
end
function Tables.getcolumn(s::Long, col::Int)
    return Tables.getcolumn(s, Tables.columnnames(s)[col])
end
Tables.columns(s::Long) = s
