# Utilities for 'flattening' chains.
import Tables
using LinearAlgebra: Cholesky

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

# Traverse the chain and collect all the scalar leaves of parameters.
abstract type ReducedKeyValuePair end
# An irreducible part of a parameter. Usually a scalar parameter, but can also be
# a struct or other type that we don't know how to reduce further.
struct Leaf{V<:VarName,A<:AbstractArray} <: ReducedKeyValuePair
    vn::V
    data::A
end
Base.show(io::IO, l::Leaf) = print(io, "Leaf(@varname(", l.vn, ") => ", typeof(l.data), ")")
# Arrays that have a constant size across all iterations can have a fast path where
# we don't eagerly split them up.
struct FixedSizeArrayOfLeaves{
    V<:VarName,
    VV<:AbstractArray{<:VarName},
    A<:AbstractArray{<:AbstractArray},
} <: ReducedKeyValuePair
    vn::V
    # precompute since it's convenient to.
    vn_leaves::VV
    # Invariants that we don't check:
    #  - all elements of data must have the same axes.
    #  - all elements of data must not have any further reducible structure, i.e.
    #    data[i][j] must be a leaf for all (i, j)
    data::A
end
Base.show(io::IO, l::FixedSizeArrayOfLeaves) = print(
    io,
    "FixedSizeArrayOfLeaves(@varname(",
    l.vn,
    ") => ",
    typeof(l.data),
    " (",
    size(first(l.data)),
    "))",
)
struct MaybeStillReducible{V<:VarName,A<:AbstractArray} <: ReducedKeyValuePair
    vn::V
    # Some elements of data still have reducible structure.
    data::A
end
is_reducible(::Type{<:AbstractArray}) = true
is_reducible(::Type{<:NamedTuple}) = true
is_reducible(::Type{T}) where {T} = AbstractArray <: T || NamedTuple <: T
# TODO(penelopeysm): ^^ Handle Tuples and _possibly_ AbstractDicts.
function _reduced_parameters(cs::ChainOrSummary)
    reduced = ReducedKeyValuePair[]
    for (k, data) in cs._data
        if k isa Parameter
            vn = _as_varname(FlexiChains.get_name(k))
            # Is everything in `data` a leaf? NOTE: we are assuming that `data` has been
            # concretised as far as possible. This will often be the case but is not really
            # guaranteed afaik.
            sample_type = eltype(data)
            if is_reducible(sample_type)
                push!(reduced, MaybeStillReducible(vn, data))
            else
                push!(reduced, Leaf(vn, data))
            end
        end
    end
    return _reduce_further(reduced)
end
function _reduce_further(reduced::Vector{<:ReducedKeyValuePair})
    new_reduced = ReducedKeyValuePair[]
    for r in reduced
        if r isa Leaf || r isa FixedSizeArrayOfLeaves
            # nothing left to do
            push!(new_reduced, r)
        else
            # r isa MaybeStillReducible
            vn, data = r.vn, r.data
            et = eltype(data)
            if !is_reducible(et)
                # OK, turns out that everything is a leaf already
                push!(new_reduced, Leaf(vn, data))
            elseif et <: AbstractArray
                # check if anything inside is potentially still reducible
                inner_eltype = eltype(eltype(data))
                if !is_reducible(inner_eltype) && _elems_have_fixed_vn_leaves(data)
                    # fast path: e.g. each element in `data` is an array of leaves of the
                    # same size.
                    vn_leaves = collect(VarNames.varname_leaves(vn, first(data)))
                    push!(new_reduced, FixedSizeArrayOfLeaves(vn, vn_leaves, data))
                    # TODO(penelopeysm): We could do better with e.g. arrays of collections.
                    # That would be the case where _elems_have_fixed_vn_leaves(data) is
                    # true, but the inner_eltype is still reducible. This is left as an
                    # extension.
                else
                    # slow path: just collect `varname_leaves` for the entire thing.
                    vn_leaves = OrderedSet{VarName}()
                    for d_i in data
                        # This is recursive, so we don't need to worry about processing this
                        # again -- we know that anything that comes out of it is a `Leaf`
                        for vn_leaf in VarNames.varname_leaves(vn, d_i)
                            push!(vn_leaves, vn_leaf)
                        end
                    end
                    for vn_leaf in vn_leaves
                        push!(new_reduced, Leaf(vn_leaf, _get_leaf_data(vn, data, vn_leaf)))
                    end
                end
            elseif et <: NamedTuple
                # collect the set of all keys.
                nt_keys = if isconcretetype(et)
                    fieldnames(et)
                else
                    ks = OrderedSet{Symbol}()
                    for d_i in data
                        for k in keys(d_i)
                            push!(ks, k)
                        end
                    end
                    ks
                end
                # then recurse
                for k in nt_keys
                    optic = VarNames.Property{k}() ∘ VarNames.getoptic(vn)
                    vn_leaf = VarName{VarNames.getsym(vn)}(optic)
                    p = MaybeStillReducible(vn_leaf, _get_leaf_data(vn, data, vn_leaf))
                    push!(new_reduced, p)
                end
            else
                # Some horrible abstract type that could contain a mixture of NamedTuples,
                # Arrays, and other stuff. In practice, this is most likely `Any`.
                #
                # TODO(penelopeysm): This code is duplicated from the `AbstractArray` case
                # above. We should refactor.
                vn_leaves = OrderedSet{VarName}()
                for d_i in data
                    for vn_leaf in VarNames.varname_leaves(vn, d_i)
                        push!(vn_leaves, vn_leaf)
                    end
                end
                for vn_leaf in vn_leaves
                    push!(new_reduced, Leaf(vn_leaf, _get_leaf_data(vn, data, vn_leaf)))
                end
            end
        end
    end
    return if any(r -> r isa MaybeStillReducible, new_reduced)
        _reduce_further(new_reduced)
    else
        new_reduced
    end
end


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
    plot_names = Dict{VarName,String}()
    N = cs isa FlexiChain ? 2 : 3
    new_data = OrderedDict{ParameterOrExtra{<:VarName},Array{<:Any,N}}()
    for vn in FlexiChains.parameters(cs)
        d = _get_raw_data(cs, Parameter(vn))
        for (vn_leaf, leaf_data) in _split_parameter_leaves(vn, d)
            new_data[Parameter(vn_leaf)] = leaf_data
        end
        if collect_plot_names && _elems_have_fixed_vn_leaves(d) && eltype(d) <: DD.DimVector
            d1 = first(d)
            dim = DD.dims(d1, 1)
            label_type = eltype(dim)
            if (label_type === Symbol || label_type <: AbstractString)
                vn_leaves = VarNames.varname_leaves(vn, d1)
                for (vn_leaf, label) in zip(vn_leaves, dim)
                    prettylabel = label isa Symbol ? repr(label) : label
                    plot_names[vn_leaf] = string(vn, "[", prettylabel, "]")
                end
            end
        end
    end
    for k in FlexiChains.extras(cs)
        new_data[k] = _get_raw_data(cs, k)
    end
    return _replace_data(cs, VarName, new_data), plot_names
end


# TODO(penelopeysm): Upstream these things.
# convert symbol/string to VarName
_as_varname(name::VarName) = name
_as_varname(name::Symbol) = VarName{name}()
_as_varname(name::AbstractString) = _as_varname(Symbol(name))

# convert VarName to symbol or string
_varname_as(::Type{<:VarName}, vn::VarName) = vn
_varname_as(::Type{Symbol}, vn::VarName) = Symbol(vn)
_varname_as(::Type{<:AbstractString}, vn::VarName) = String(Symbol(vn))

# Get leaf data by applying the optic - slower fallback that always works
function _get_leaf_data(vn::VarName, d::AbstractArray, vn_leaf::VarName)
    # TODO(penelopeysm): the following line is `VarNames._unprefix_optic`. Change this
    # once we can.
    optic, _ = _getindex_optic_and_vn([vn], vn_leaf, VarNames.Iden(), vn_leaf)
    return _map_optic(optic, d, vn_leaf)
end

# Split a parameter into its leaves, if it has any
function _split_parameter_leaves(vn::VarName, d::AbstractArray)
    if _elems_have_fixed_vn_leaves(d)
        # Don't need to iterate over all array elements - just check the first one.
        d1 = first(d)
        vn_leaves = collect(VarNames.varname_leaves(vn, d1))
        if length(vn_leaves) == 1 && only(vn_leaves) == vn
            # Scalar-valued parameter: nothing to split.
            return [vn => d]
        elseif d1 isa AbstractArray{<:Union{Real,Missing}}
            # all leaves have the same dimensions, so invert the nested array structure
            # with a simple broadcast
            return [
                vn_leaf => getindex.(d, i) for (i, vn_leaf) in zip(eachindex(d1), vn_leaves)
            ]
        else
            return [vn_leaf => _get_leaf_data(vn, d, vn_leaf) for vn_leaf in vn_leaves]
        end
    else # leaves may have different sizes
        vns = OrderedSet{VarName}()
        for i in eachindex(d)
            for vn_leaf in VarNames.varname_leaves(vn, d[i])
                push!(vns, vn_leaf)
            end
        end
        return [vn_leaf => _get_leaf_data(vn, d, vn_leaf) for vn_leaf in vns]
    end
end


"""
    FlexiChains._split_varnames(
        cs::ChainOrSummary{Symbol};
        collect_plot_names::Bool=false
    )

For `Symbol`-keyed chains, convert keys to `VarName`, split array-valued parameters into
scalar leaves, then convert the keys back to `Symbol`.

Likewise for `AbstractString`-keyed chains; the keys are converted back to standard
`String`.
"""
function _split_varnames(
    cs::ChainOrSummary{T};
    collect_plot_names::Bool=false,
) where {T<:Union{Symbol,AbstractString}}
    N = cs isa FlexiChain ? 2 : 3
    new_data = OrderedDict{ParameterOrExtra{<:VarName},Array{<:Any,N}}()
    for (k, v) in cs._data
        new_key = k isa Parameter ? Parameter(_as_varname(k.name)) : k
        new_data[new_key] = v
    end
    vn_cs = FlexiChains._replace_data(cs, VarName, new_data)
    split_cs, plot_names = _split_varnames(vn_cs; collect_plot_names)
    plot_names = Dict(_varname_as(T, k) => v for (k, v) in plot_names)
    return FlexiChains.map_parameters(k -> _varname_as(T, k), split_cs), plot_names
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

# This function is a performance optimisation. It copies the data of a
# `FixedSizeArrayOfLeaves` into `output`, starting at column `col` of the last (`param`)
# dimension, while avoiding intermediate arrays as far as possible, and reading `data` in
# memory order.
#
# `data` has dimensions (niters x nchains), or for summaries (niters x nchains x nstats),
# and each element is an array with `ncols` elements.
#
# The `k`-th element of `x` (in column-major order) goes into column `col + k - 1`, which
# matches the order of `vec(vn_leaves)`.
#
# This is a separate function so that the loop is compiled for the concrete types of
# `output` and `data`.
function _copy_fixed_size_leaves!(output::Array, data::AbstractArray, col::Int)
    out_matrix = reshape(output, :, size(output, ndims(output)))
    for (j, x) in enumerate(data)
        for (k, v) in enumerate(x)
            out_matrix[j, col+k-1] = v
        end
    end
    return output
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
    cs::ChainOrSummary{TKey};
    warn::Bool=true,
    eltype_filter::Type{T}=Any,
    parameters_only::Bool=true,
    split_varnames::Bool=true,
) where {TKey,T}
    reduced_parameters = ReducedKeyValuePair[]
    skipped_keys = ParameterOrExtra{<:TKey}[]
    kept_leaf_eltypes = Type[]

    if split_varnames
        # Split up the parameters first as much as possible.
        unfiltered_reduced_parameters = _reduced_parameters(cs)
        # Filter the parameters according to eltype.
        for r in unfiltered_reduced_parameters
            leaf_eltype = if r isa Leaf
                eltype(r.data)
            elseif r isa FixedSizeArrayOfLeaves
                eltype(first(r.data))
            end
            if leaf_eltype <: eltype_filter
                push!(reduced_parameters, r)
                push!(kept_leaf_eltypes, leaf_eltype)
            else
                push!(skipped_keys, Parameter(_varname_as(TKey, r.vn)))
            end
        end
    else
        for (k, v) in cs._data
            leaf_eltype = eltype(v)
            if k isa Parameter
                if leaf_eltype <: eltype_filter
                    push!(reduced_parameters, Leaf(_as_varname(FlexiChains.get_name(k)), v))
                    push!(kept_leaf_eltypes, leaf_eltype)
                else
                    push!(skipped_keys, k)
                end
            end
        end
    end

    # Tack on extras if necessary. (Note that extras are never split)
    extras_to_add = Extra[]
    if !parameters_only
        for (k, v) in cs._data
            leaf_eltype = eltype(v)
            if k isa Extra && leaf_eltype <: eltype_filter
                push!(extras_to_add, k)
                push!(kept_leaf_eltypes, leaf_eltype)
            end
        end
    end

    if warn && !isempty(skipped_keys)
        skipped_str = join(("`$k`" for k in skipped_keys), ", ")
        @warn "skipping keys $skipped_str as their values do not subtype $eltype_filter"
    end

    # Construct output array. First we need to decide how many columns we're going to have
    # (i.e. how many 'parameters' there are after splitting).
    n_cols = 0
    for r in reduced_parameters
        if r isa Leaf
            n_cols += 1
        elseif r isa FixedSizeArrayOfLeaves
            n_cols += length(first(r.data))
        end
    end
    n_cols += length(extras_to_add)

    s = map(length, DD.dims(cs))
    if n_cols == 0
        @warn "no keys with values subtyping $eltype_filter found"
        empty_keys = parameters_only ? TKey[] : ParameterOrExtra{<:TKey}[]
        empty_dims = (DD.dims(cs)..., DD.Dim{PARAM_DIM_NAME}(empty_keys))
        return DD.DimArray(Array{T}(undef, (s..., 0)), empty_dims)
    end

    # Allocate output and copy data into it.
    Tout = reduce(typejoin, kept_leaf_eltypes)
    output = Array{Tout}(undef, (s..., n_cols))
    N = ndims(output)
    parameter_names = VarName[]
    col = 1
    for r in reduced_parameters
        if r isa Leaf
            copyto!(selectdim(output, N, col), r.data)
            push!(parameter_names, r.vn)
            col += 1
        elseif r isa FixedSizeArrayOfLeaves
            ncols = length(first(r.data))
            _copy_fixed_size_leaves!(output, r.data, col)
            append!(parameter_names, vec(r.vn_leaves))
            col += ncols
        end
    end
    for e in extras_to_add
        copyto!(selectdim(output, N, col), _get_raw_data(cs, e))
        col += 1
    end

    kept_keys = if parameters_only
        map(vn -> _varname_as(TKey, vn), parameter_names)
    else
        params = map(vn -> Parameter(_varname_as(TKey, vn)), parameter_names)
        vcat(params, extras_to_add)
    end
    dims = (DD.dims(cs)..., DD.Dim{PARAM_DIM_NAME}(kept_keys))
    return DD.DimArray(output, dims)
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
    chain::ChainOrSummary{TKey};
    warn::Bool=true,
    eltype_filter::Type{T}=Any,
    parameters_only::Bool=true,
    split_varnames::Bool=true,
) where {TKey,T}
    return parent(DD.DimArray(chain; warn, eltype_filter, parameters_only, split_varnames))
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

| Summary produced via                          | Dimensions of resulting `DimArray` |
| :-------------------------------------------- | :--------------------------------- |
| `mean(chn)`                                   | `(:param)`                         |
| `mean(chn; dims=:iter)`                       | `(:chain, :param)`                 |
| `mean(chn; dims=:chain)`                      | `(:iter, :param)`                  |
| `summarystats(chn)`                           | `(:stat, :param)`                  |
| `collapse(chn, [cfunc1, cfunc2]; dims=:iter)` | `(:chain, :stat, :param)`          |

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
DD.DimArray

"""
    Base.Array(
        summary::FlexiSummary;
        kwargs...
    )

Convert a `FlexiSummary` into a standard `Array`. This is the same as the conversion to
[`DimensionalData.DimArray`](@ref), except that the dimension metadata is discarded.

See [`DimensionalData.DimArray(::FlexiChains.FlexiSummary)`](@ref) for details.
"""
Base.Array

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
                "duplicate column names (note that keys are converted to Symbols, and " *
                "`$(ITER_DIM_NAME)`, `$(CHAIN_DIM_NAME)`, and `$(PARAM_DIM_NAME)` are " *
                "reserved column names): " *
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

Suppose we have a `chn::FlexiChain` with 2 parameters, `x::Float64` and `b::Bool`, 10
iterations and 2 chains. Then `DataFrame(Wide(chn))` will return a DataFrame that looks like
the following. Each parameter is a different column, and the `iter` and `chain` dimensions
are represented as separate columns as well; `iter` varies faster than `chain`.

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
 Row │ param     mean
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
        w = new{typeof(cs),typeof(symbol_to_keys)}(cs, symbol_to_keys, parameters_only)
        # Parameter or stat names can still clash with the `iter`/`chain`/`param` columns.
        _check_duplicate_keys(Tables.columnnames(w))
        return w
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

Suppose we have a `chn::FlexiChain` with 2 parameters, `x::Float64` and `b::Bool`, 10
iterations and 2 chains. Then `DataFrame(Long(chn))` will return a DataFrame that looks like
the following. The `iter` and `chain` dimensions are represented as separate columns as
before, but now the parameter names are stacked into a single `param` column, and the values
are stacked into a single `value` column.

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
    # Use the stored stat indices even if the stat dimension was dropped, so that e.g.
    # `DataFrame(mean(chn))` has a `mean` column rather than a generic `stat` column.
    append!(cols, parent(w.cs._stat_indices))
    return cols
end
function Tables.getcolumn(w::Wide{<:FlexiSummary}, col::Symbol)
    ii = iter_indices(w.cs)
    ci = chain_indices(w.cs)
    si = w.cs._stat_indices
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
    elseif col in parent(si)
        # Named stat column. Perf optimisation: this is equivalent to
        #     get_stat_val(k) = w.cs[k, stat=At(col)]
        # but avoids the overhead of the getindex call when we know for certain that `k`
        # is already a valid key in `w.cs._data`.
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
        throw(ArgumentError("summary does not have a stat named $col; should not happen"))
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
