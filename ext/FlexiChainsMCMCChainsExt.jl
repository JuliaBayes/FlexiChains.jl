module FlexiChainsMCMCChainsExt

using FlexiChains: FlexiChains, FlexiChain, VarName, VarNames, Parameter, Extra
using MCMCChains: MCMCChains
using OrderedCollections: OrderedDict, OrderedSet

# Magic constants. Such is life when MCMCChains allows you to bundle arbitrary info into a
# NamedTuple. Refer to DynamicPPLMCMCChainsExt for where these get set
const MCStartTimeKey = :start_time
const MCStopTimeKey = :stop_time
const MCSamplerStateKey = :samplerstate

##############################
# Conversion from MCMCChains #
##############################

"""
    FlexiChains.from_mcmcchains(chains::MCMCChains.Chains, key_spec=nothing)

Convert an `MCMCChains.Chains` object to a `FlexiChain`.

If `key_spec` is not provided, parameters in the `:parameters` section are stored as
`Parameter{Symbol}` keys and all other sections (e.g. `:internals`) as `Extra{Symbol}` keys,
giving a `FlexiChain{Symbol}`.

If `key_spec` is provided, it is passed directly to the `FlexiChain` from-array constructor.
The key type of the resulting `FlexiChain` is inferred from `key_spec`. You can pass this
argument if you want to override the parameter names stored in the `MCMCChains.Chains`
object, or to group array-valued parameters together, for example.

Please see [the `FlexiChain` constructor documentation](@ref
FlexiChains.FlexiChain(::AbstractArray{T,3}, key_spec) where {T}) for details on what
`key_spec` is allowed.

Iteration indices, chain indices, and per-chain sampling times are inherited from the
`MCMCChains.Chains` object. If the `MCMCChains.Chains` object contains a `samplerstate`
field in its `info` NamedTuple, this is also preserved in the resulting FlexiChain.
"""
function FlexiChains.from_mcmcchains(
    chains::MCMCChains.Chains,
    key_spec::Union{Nothing,Tuple}=nothing,
)
    ni, _, nc = size(chains)
    # MCMCChains stores data as (niters, nparams, nchains); the FlexiChain from-array
    # constructor expects (niters, nchains, nparams).
    arr = permutedims(chains.value.data, (1, 3, 2))

    # If no key_spec is provided, build one from the MCMCChains name_map. The :parameters
    # section becomes Parameter keys, everything else becomes Extra keys.
    if key_spec === nothing
        param_names = get(chains.name_map, :parameters, Symbol[])
        other_names = Iterators.flatmap(keys(chains.name_map)) do section
            section === :parameters ? Symbol[] : chains.name_map[section]
        end
        key_spec = tuple(
            (Parameter(n) for n in param_names)...,
            (Extra(n) for n in other_names)...,
        )
    end

    iter_indices = collect(Int, Base.range(chains))
    chain_indices = collect(Int, MCMCChains.chains(chains))  # bizarre function name, yeah

    # Attempt to determine whether the chain was constructed with `sample(model, spl, N)` or
    # `sample(model, spl, MCMCThreads(), N, M)`. This affects whether the metadata is
    # recorded as scalars or vectors.
    has_vector_metadata = (
        # trivially true if there are multiple chains
        nc > 1 ||
        # attempt to infer from start/stop time
        (
            hasproperty(chains.info, MCStartTimeKey) &&
            chains.info.start_time isa AbstractVector
        ) ||
        (
            hasproperty(chains.info, MCStopTimeKey) &&
            chains.info.stop_time isa AbstractVector
        )
    )

    sampling_time =
        if hasproperty(chains.info, MCStartTimeKey) &&
           hasproperty(chains.info, MCStopTimeKey)
            start_time = getfield(chains.info, MCStartTimeKey)
            stop_time = getfield(chains.info, MCStopTimeKey)
            starts = has_vector_metadata ? start_time : [start_time]
            stops = has_vector_metadata ? stop_time : [stop_time]
            Float64.(stops .- starts)
        else
            fill(missing, nc)
        end

    last_sampler_state = if hasproperty(chains.info, MCSamplerStateKey)
        st = getfield(chains.info, MCSamplerStateKey)
        has_vector_metadata ? st : [st]
    else
        fill(missing, nc)
    end

    TKey = _infer_key_type(key_spec)
    return FlexiChain{TKey}(
        arr,
        key_spec;
        iter_indices=iter_indices,
        chain_indices=chain_indices,
        sampling_time=sampling_time,
        last_sampler_state=last_sampler_state,
    )
end

function _infer_key_type(key_spec::Tuple)
    T = Union{}
    for k in key_spec
        key = k isa Pair ? first(k) : k
        if key isa Parameter
            Tnew = typeof(key).parameters[1]
            # Special-case promote VarName parameters to avoid overly narrow key types like
            # `VarName{sym,Iden} where {sym}`, which can happen if you have [@varname(x),
            # @varname(y)]. This causes issues when parameters like e.g. @varname(x[1]) are
            # used later on, e.g. in _split_varnames.
            Tnew = FlexiChains._maybe_promote_key(Tnew)
            T = typejoin(T, Tnew)
        end
    end
    return T
end

# I can't seem to get Base.@deprecate to work
function FlexiChains.FlexiChain{Symbol}(chains::MCMCChains.Chains)
    Base.depwarn(
        "`FlexiChain{Symbol}(chains::MCMCChains.Chains)` is deprecated, use `FlexiChains.from_mcmcchains(chains)` instead.",
        :FlexiChain,
    )
    return FlexiChains.from_mcmcchains(chains)
end

############################
# Conversion to MCMCChains #
############################

"""
    MCMCChains.Chains(chain::FlexiChain)

Convert a `FlexiChain` to an `MCMCChains.Chains` object.

Array-valued parameters are split up into their individual real-valued elements, much like
the output that you get directly from sampling with Turing + MCMCChains.
"""
function MCMCChains.Chains(fchain::FlexiChain{T}) where {T}
    ni, nc = size(fchain)
    array_of_dicts =
        [FlexiChains.parameters_at(fchain; iter=i, chain=j) for i in 1:ni, j in 1:nc]
    # Construct array of parameter names and array of values. NOTE: Regardless of the type
    # of `T`, we will always promote to `VarName` here because that allows us to keep track
    # of sub-parameters correctly.
    names_set = OrderedSet{VarName}()
    # Extract the parameter names and values from each transition.
    split_dicts = map(array_of_dicts) do d
        nms_and_vs = if isempty(d)
            Tuple{VarName,Any}[]
        else
            # Force conversion of keys to VarNames, so that we can split them up with
            # varname_and_value_leaves.
            keys_as_vns = map(FlexiChains._internal_to_varname, collect(Base.keys(d)))
            iters = map(VarNames.varname_and_value_leaves, keys_as_vns, Base.values(d))
            mapreduce(collect, vcat, iters)
        end
        nms = map(first, nms_and_vs)
        vs = map(last, nms_and_vs)
        for nm in nms
            push!(names_set, nm)
        end
        # Convert the names and values to a single dictionary.
        return OrderedDict(zip(nms, vs))
    end
    varnames = collect(names_set)
    values =
        [get(split_dicts[i, j], key, missing) for i in 1:ni, key in varnames, j in 1:nc]
    # Once we're done processing the VarNames, we convert them back to Symbols because
    # that's what will fit into MCMCChains.
    varname_symbols = map(Symbol, varnames)

    # Handle non-parameter keys
    internal_keys = Symbol[]
    internal_values = Array{Real,3}(undef, ni, 0, nc)
    for k in FlexiChains.extras(fchain)
        v = map(identity, fchain[k])
        if eltype(v) <: Real
            push!(internal_keys, Symbol(k.name))
            internal_values = hcat(internal_values, reshape(v, ni, 1, nc))
        else
            @warn "key $k skipped in MCMCChains conversion as it is not Real-valued"
        end
    end

    all_symbols = vcat(varname_symbols, internal_keys)
    all_values = hcat(values, internal_values)
    # The following 'concretisation' (in reality, casting everything to Float64) is overly
    # aggressive. It's only included to match what Turing.jl does. See
    # https://github.com/TuringLang/Turing.jl/issues/2666 for details.
    all_values = MCMCChains.concretize(all_values)

    # Bundle Symbol -> VarName Dict if necessary (this is a Turing compatibility shim)
    info = if T <: VarName
        (varname_to_symbol=OrderedDict(zip(varnames, varname_symbols)),)
    else
        (;)
    end

    # Preserve sampling time as start_time/stop_time if available.
    # MCMCChains stores these as absolute timestamps. FlexiChains only stores durations, so
    # we use 0-based start times...
    st = FlexiChains.sampling_time(fchain)
    if !all(ismissing, st)
        starts = zeros(Float64, nc)
        stops = Float64.(coalesce.(st, 0.0))
        info = merge(info, (; MCStartTimeKey => starts, MCStopTimeKey => stops))
    end

    # Preserve last sampler state if available.
    lss = FlexiChains.last_sampler_state(fchain)
    if !all(ismissing, lss)
        info = merge(info, (; MCSamplerStateKey => collect(lss)))
    end

    # See comment above for the use of 'internals' as the only section.
    return MCMCChains.Chains(
        all_values,
        all_symbols,
        # Note that Turing.jl stores all other keys in the 'internals' section.
        (; internals=internal_keys);
        info=info,
        iterations=parent(FlexiChains.iter_indices(fchain)),
    )
end

end # module
