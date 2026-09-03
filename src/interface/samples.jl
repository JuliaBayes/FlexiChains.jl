@public values_at, parameters_at, reconstruct_values, reconstruct_parameters

_VALUES_PARAMETER_AT_DOCSTRING = """
The `iter` and `chain` keyword arguments can be anything used to index into the respective
dimensions of a `FlexiChain`, such as an integer, a vector of integers, a range, or a
DimensionalData.jl selector. Both default to `:` (i.e. all iterations / all chains).

In particular, you can convert the entire chain into a `DimMatrix` of the desired output
type by calling this function with no keyword arguments.
"""

_VALUES_PARAMETER_AT_WARNING = """
!!! warning "Using `NamedTuple` or `ComponentArray`"

    This will throw an error if any key cannot be converted to a `Symbol`, or if there are
    duplicate key names after conversion. If you have parameter names that convert to the
    same `Symbol`, you can either use `OrderedDict`, subset the chain before calling this
    function, or rename your parameters. Furthermore, please be aware that this is a lossy
    conversion as it does not retain information about whether a key is a parameter or an
    extra.
"""

"""
    FlexiChains.values_at(chn::FlexiChain; iter=:, chain=:)
    FlexiChains.values_at(chn::FlexiChain, ::Type{Tout}; iter=:, chain=:)

Extract all values from the chain corresponding to a particular set of MCMC iterations(s).

$(_VALUES_PARAMETER_AT_DOCSTRING)

To get only the parameter keys, use [`FlexiChains.parameters_at`](@ref).

The output type can be specified with an (optional) positional argument. Possible options
are:

- unspecified: uses the `structure` stored in the chain to determine the output type.
  Specifically, for chains sampled with Turing.jl, the stored `structure` will be
  `VarNamedTuple`, and consequently the output of `parameters_at` will be a
  `DynamicPPL.ParamsWithStats` per iteration (which stores the parameters as a
  `VarNamedTuple`, and the stats/extras as a `NamedTuple`).

  For chains that do not have a stored `structure`, the default output will be an
  `OrderedDict`.

- `Tout <: AbstractDict`: returns a dictionary mapping `ParameterOrExtra{TKey}` to their
  values. This is the most faithful representation of the data in the chain.

- `Tout = NamedTuple`, or `Tout = ComponentArray`: attempts to convert every key name to a
  Symbol, which is used as the field name in the output `NamedTuple` or `ComponentArray`.

$(_VALUES_PARAMETER_AT_WARNING)

For order-sensitive output types, such as `OrderedDict`, the keys are returned in the same
order as they are stored in the `FlexiChain`. This also corresponds to the order returned by
`keys(chn)`.
"""
function values_at end

"""
    FlexiChains.parameters_at(chn::FlexiChain; iter=:, chain=:)
    FlexiChains.parameters_at(chn::FlexiChain, ::Type{Tout}; iter=:, chain=:)

Extract all *parameter* values from the chain corresponding to a particular set of MCMC
iteration(s), discarding non-parameter (i.e. `Extra`) keys.

$(_VALUES_PARAMETER_AT_DOCSTRING)

To get all keys (not just parameters), use [`FlexiChains.values_at`](@ref).

The output type for each iteration can be specified with the first (optional) positional
argument. Possible options are:

- unspecified: uses the `structure` stored in the chain to determine the output type.
  Specifically, for chains sampled with Turing.jl, the stored `structure` will be
  `VarNamedTuple`, and consequently the output of `parameters_at` will be a `VarNamedTuple`
  per iteration.

  For chains that do not have a stored `structure`, the default output will be an
  `OrderedDict`.

- `Tout <: AbstractDict`: returns a dictionary mapping `TKey` to their values.

- `Tout = NamedTuple` or `Tout <: ComponentArray`: attempts to convert every parameter name
   to a Symbol, which is used as the field name in the output `NamedTuple` or
   `ComponentArray`.

$(_VALUES_PARAMETER_AT_WARNING)

For order-sensitive output types, such as `OrderedDict`, the parameters are returned in the
same order as they are stored in the `FlexiChain`. This also corresponds to the order
returned by `FlexiChains.parameters(chn)`.
"""
function parameters_at end

for f in (:values_at, :parameters_at)
    _f = Symbol("_", f)
    @eval begin
        function $f(chn::FlexiChain, ::Type{Tout}=Nothing; iter=:, chain=:) where {Tout}
            return $_f(chn, iter, chain, Tout)
        end
        function $f(chn::FlexiChain, iter, chain, ::Type{Tout}=Nothing) where {Tout}
            Base.depwarn(
                "Positional `iter` and `chain` arguments to `" *
                $(string(f)) *
                "` are deprecated and will be removed in a future version. " *
                "Please use keyword arguments instead: `" *
                $(string(f)) *
                "(chn[, Tout]; iter=..., chain=...)`.",
                $(QuoteNode(f)),
            )
            return $_f(chn, iter, chain, Tout)
        end
    end
end

"""
    reconstruct_values(chn::FlexiChain{T}, iter, chain, structure) where {T}

Given a `FlexiChain`, an iteration index, a chain index, and the `structure` stored in the
chain, reconstruct the values (both parameters and extras) for that iteration and chain.

The default behaviour is to simply return an `OrderedDict` of `ParameterOrExtra` to their
values, but this can be overloaded for specific `structure` types to return more informative
output types.
"""
function reconstruct_values(chn::FlexiChain{TKey}, iter, chain, structure) where {TKey}
    return OrderedDict{ParameterOrExtra{<:TKey},Any}(
        k => chn[k, iter=iter, chain=chain] for k in keys(chn)
    )
end
function FlexiChains.reconstruct_values(
    chn::FlexiChain{<:VarName},
    i,
    j,
    structure::VarNamedTuple,
)
    vnt = VarNamedTuple()
    nt = NamedTuple()
    for param_or_extra in keys(chn)
        val = chn[param_or_extra][i, j]
        if param_or_extra isa Parameter
            ismissing(val) && continue
            vn = param_or_extra.name
            top_sym = VarNames.getsym(vn)
            template = get(structure.data, top_sym, VarNames.NoTemplate())
            vnt = VarNames.templated_setindex!!(vnt, val, vn, template)
        elseif param_or_extra isa Extra
            nt = merge(nt, (; Symbol(param_or_extra.name) => val))
        end
    end
    return VarNames.Draw(vnt, nt)
end

"""
    reconstruct_parameters(chn::FlexiChain{T}, iter, chain, structure) where {T}

Given a `FlexiChain`, an iteration index, a chain index, and the `structure` stored in the
chain, reconstruct the parameter values for that iteration and chain.

The default behaviour is to simply return an `OrderedDict` of parameter keys to their
values, but this can be overloaded for specific `structure` types to return more informative
output types.
"""
function reconstruct_parameters(chn::FlexiChain{TKey}, iter, chain, structure) where {TKey}
    return OrderedDict{TKey,Any}(
        k => chn[Parameter(k), iter=iter, chain=chain] for k in FlexiChains.parameters(chn)
    )
end
function FlexiChains.reconstruct_parameters(
    chn::FlexiChain{<:VarName},
    i,
    j,
    structure::VarNamedTuple,
)
    vnt = VarNamedTuple()
    for vn in FlexiChains.parameters(chn)
        val = chn[Parameter(vn)][i, j]
        ismissing(val) && continue
        top_sym = VarNames.getsym(vn)
        template = get(structure.data, top_sym, VarNames.NoTemplate())
        vnt = VarNames.templated_setindex!!(vnt, val, vn, template)
    end
    return vnt
end

# This eval block is quite nasty, but the alternative of duplicating all this code was even
# nastier.
#
#   f          – general entry point (_values_at or _parameters_at)
#   f_single   – scalar implementation (_values_at_single or _parameters_at_single)
#   reconstruct_f – the reconstruct function to call for structure-based output
#   get_keys   – expression to obtain the relevant keys from the chain
#   KeyType    – key type for AbstractDict return types
#   idx_key    – expression to convert a key `k` into the form used for indexing
#   to_sym     – expression to convert a key `k` into a Symbol (for NamedTuple output)
#   desc       – noun used in error messages ("key" or "parameter")
for (f, f_single, reconstruct_f, get_keys, KeyType, idx_key, to_sym, desc) in (
    (
        :_values_at,
        :_values_at_single,
        :reconstruct_values,
        :(Base.keys(chn)),
        :(ParameterOrExtra{<:TKey}),
        :k,
        :(Symbol(k.name)),
        "key",
    ),
    (
        :_parameters_at,
        :_parameters_at_single,
        :reconstruct_parameters,
        :(FlexiChains.parameters(chn)),
        :TKey,
        :(Parameter(k)),
        :(Symbol(k)),
        "parameter",
    ),
)
    @eval begin
        # We start by defining `_*_at_single` methods, which act on a single sample at a
        # time and use the `Tout` argument to determine the output type. We need to define
        # quite a few of these, one per output type.
        function $f_single(
            chn::FlexiChain{TKey},
            iter::Union{Int,DD.At},
            chain::Union{Int,DD.At},
            ::Type{Nothing}=Nothing,
        ) where {TKey}
            i_1based = DD.selectindices(iter_indices(chn), iter)
            c_1based = DD.selectindices(chain_indices(chn), chain)
            return $reconstruct_f(chn, iter, chain, chn._structures[i_1based, c_1based])
        end
        function $f_single(
            chn::FlexiChain{TKey},
            iter::Union{Int,DD.At},
            chain::Union{Int,DD.At},
            ::Type{T},
        )::T{$KeyType,Any} where {TKey,T<:AbstractDict}
            return T{$KeyType,Any}(
                k => chn[$idx_key, iter=iter, chain=chain] for k in $get_keys
            )
        end
        function $f_single(
            chn::FlexiChain{TKey},
            iter::Union{Int,DD.At},
            chain::Union{Int,DD.At},
            ::Type{NamedTuple},
        ) where {TKey}
            ks = collect($get_keys)
            N_expected = length(ks)
            N_unique = length(Set($to_sym for k in ks))
            if N_expected != N_unique
                throw(
                    ArgumentError(
                        $desc * " names could not be converted to unique symbols",
                    ),
                )
            end
            return NamedTuple($to_sym => chn[$idx_key, iter=iter, chain=chain] for k in ks)
        end

        # Once that's been defined, we can make use of them in the main `_values_at` and
        # `_parameters_at` methods, which handle multi-index inputs and additionally convert
        # to `DimArray` output when necessary.
        function $f(chn::FlexiChain, iter, chain, ::Type{Tout}=Nothing) where {Tout}
            new_iter_indices, new_iter_lookup, collapse_iter =
                _get_indices_and_lookup(chn, iter_indices, iter)
            new_chain_indices, new_chain_lookup, collapse_chain =
                _get_indices_and_lookup(chn, chain_indices, chain)
            new_iter_indices = if new_iter_indices isa Colon
                1:length(new_iter_lookup)
            else
                new_iter_indices
            end
            new_chain_indices = if new_chain_indices isa Colon
                1:length(new_chain_lookup)
            else
                new_chain_indices
            end

            return if collapse_iter && collapse_chain
                # Avoid materialising a full array if we're just going to drop it anyway.
                $f_single(chn, only(new_iter_indices), only(new_chain_indices), Tout)
            else
                mat = [
                    $f_single(chn, i, c, Tout) for
                    i in new_iter_indices, c in new_chain_indices
                ]
                dimmat = DD.DimMatrix(
                    map(identity, mat),
                    (
                        DD.Dim{ITER_DIM_NAME}(new_iter_lookup),
                        DD.Dim{CHAIN_DIM_NAME}(new_chain_lookup),
                    ),
                )
                return if collapse_iter
                    dropdims(dimmat; dims=ITER_DIM_NAME)
                elseif collapse_chain
                    dropdims(dimmat; dims=CHAIN_DIM_NAME)
                else
                    dimmat
                end
            end
        end
    end
end
