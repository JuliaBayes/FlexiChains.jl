using VarNames: VarNames, parameters, extras

@public has_parameter
@public map_keys, map_parameters

"""
    Base.keys(cs::ChainOrSummary)

Returns the keys of the `FlexiChain` (or summary thereof).

To obtain only the parameters, use [`FlexiChains.parameters`](@ref).
"""
function Base.keys(cs::ChainOrSummary)
    return keys(cs._data)
end

"""
    Base.keytype(cs::ChainOrSummary{TKey})

Returns `TKey`.
"""
Base.keytype(::ChainOrSummary{TKey}) where {TKey} = TKey

"""
    Base.haskey(cs::ChainOrSummary{TKey}, key::ParameterOrExtra{<:TKey}) where {TKey}

Returns `true` if the `FlexiChain` or summary contains the given key.
"""
function Base.haskey(cs::ChainOrSummary{TKey}, key::ParameterOrExtra{<:TKey}) where {TKey}
    return haskey(cs._data, key)
end
"""
    Base.haskey(cs::ChainOrSummary{TKey}, key::TKey) where {TKey}

Returns `true` if the `FlexiChain` or summary contains the given name as a parameter key.
"""
function Base.haskey(cs::ChainOrSummary{TKey}, key::TKey) where {TKey}
    return haskey(cs._data, Parameter(key))
end

"""
    Base.values(cs::ChainOrSummary; parameters_only::Bool=false)

Returns the values of the `FlexiChain` or `FlexiSummary`, i.e., the matrices obtained by
indexing into the chain with each key.

If `parameters_only` is `true`, only the values corresponding to parameter keys are returned.
"""
function Base.values(cs::ChainOrSummary; parameters_only::Bool=false)
    if parameters_only
        return (cs[Parameter(k)] for k in parameters(cs))
    else
        return (cs[k] for k in keys(cs))
    end
end

"""
    Base.pairs(cs::ChainOrSummary)

Returns an iterator over the key-value pairs of the `FlexiChain` or `FlexiSummary`.

If `parameters_only` is `true`, only the values corresponding to parameter keys are returned.

!!! tip
    Note that this function allows you to decompose a `FlexiChain` into a dict-of-arrays,
    e.g. with `OrderedDict(pairs(chain; parameters_only=...))`.
"""
function Base.pairs(cs::ChainOrSummary; parameters_only::Bool=false)
    if parameters_only
        return (k => cs[Parameter(k)] for k in parameters(cs))
    else
        return (k => cs[k] for k in keys(cs))
    end
end

"""
    VarNames.parameters(cs::ChainOrSummary{TKey}) where {TKey}

Returns a vector of parameter names in the `FlexiChain` or summary thereof.
"""
function VarNames.parameters(cs::ChainOrSummary{TKey})::Vector{TKey} where {TKey}
    parameter_names = TKey[]
    for k in keys(cs)
        if k isa Parameter{<:TKey}
            push!(parameter_names, k.name)
        end
    end
    return parameter_names
end
"""
    FlexiChains.has_parameter(cs::ChainOrSummary{TKey}, param::TKey) where {TKey}

Returns `true` if the `FlexiChain` or summary contains the given parameter.
"""
function has_parameter(cs::ChainOrSummary{TKey}, key::TKey) where {TKey}
    return haskey(cs, Parameter(key))
end

"""
    VarNames.extras(cs::ChainOrSummary)

Returns a vector of non-parameter names in the `FlexiChain` or summary thereof.
"""
function VarNames.extras(cs::ChainOrSummary)::Vector{Extra}
    other_key_names = Extra[]
    for k in keys(cs)
        if k isa Extra
            push!(other_key_names, k)
        end
    end
    return other_key_names
end

"""
Figure out the new key type for a FlexiChain or FlexiSummary after mapping keys with `f`.
"""
function _get_new_keytype(f, ks::Base.KeySet)
    seen = Set()
    TKey = Union{}
    for k in ks
        new_key = f(k)
        if !(new_key isa ParameterOrExtra)
        end
        if new_key in seen
            throw(
                ArgumentError(
                    "function `f` must return unique keys; got duplicates of `$new_key`",
                ),
            )
        else
            push!(seen, new_key)
        end
        if new_key isa Parameter
            # Heuristic to avoid constructing chains like `FlexiChain{VarName{sym,Iden} where
            # {sym}}` which can cause issues.
            Tnew = typeof(new_key).parameters[1]
            Tnew = Tnew <: VarName ? VarName : Tnew
            TKey = typejoin(TKey, Tnew)
        end
    end
    return TKey
end

"""
    FlexiChains.map_keys(f, cs::ChainOrSummary{T})::ChainOrSummary{S} where {T,S}

Change the keys of a `FlexiChain` or `FlexiSummary` by applying the function `f` to each key.

`f` must have the signature `f(::ParameterOrExtra{<:T}) -> ParameterOrExtra{<:S}`. It must return a unique key for each input key.

"""
function map_keys(f, cs::ChainOrSummary)
    new_keytype = _get_new_keytype(f, keys(cs))
    N = cs isa FlexiChain ? 2 : 3
    new_data = OrderedDict{ParameterOrExtra{<:new_keytype},Array{<:Any,N}}(
        f(k) => v for (k, v) in pairs(cs._data)
    )
    return _replace_data(cs, new_keytype, new_data)
end

"""
    FlexiChains.map_parameters(f, cs::ChainOrSummary{T})::ChainOrSummary{S} where {T,S}

Change the parameters of a `FlexiChain` or `FlexiSummary` by applying the function `f` to each parameter name.

`f` must have the signature `f(::T) -> S`. It must return a unique parameter for each input parameter.
"""
function map_parameters(f, cs::ChainOrSummary)
    seen = Set()
    TKey = Union{}
    for p in parameters(cs)
        newp = f(p)
        if newp in seen
            throw(
                ArgumentError(
                    "function `f` must return unique parameter names; got duplicates of `$newp`",
                ),
            )
        else
            push!(seen, newp)
        end
        # Heuristic to avoid constructing chains like `FlexiChain{VarName{sym,Iden} where
        # {sym}}` which can cause issues.
        Tnew = typeof(newp)
        Tnew = Tnew <: VarName ? VarName : Tnew
        TKey = typejoin(TKey, Tnew)
    end
    wrapper_f = k -> k isa Parameter ? Parameter(f(k.name)) : k
    N = cs isa FlexiChain ? 2 : 3
    new_data = OrderedDict{ParameterOrExtra{<:TKey},Array{<:Any,N}}(
        wrapper_f(k) => v for (k, v) in pairs(cs._data)
    )
    return _replace_data(cs, TKey, new_data)
end
