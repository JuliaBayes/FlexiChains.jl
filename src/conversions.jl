using VarNames: Draw

"""
    to_vnt_and_stats(transition)::Tuple{VarNamedTuple,NamedTuple}

Convert the _first output_ (i.e. the 'transition') of an AbstractMCMC sampler into a
`VarNamedTuple` mapping parameter names to their values, plus a `NamedTuple` of any
additional statistics.

The `VarNamedTuple` will be converted into `Parameter` keys, and the `NamedTuple` into
`Extra` keys.

If you are writing a custom AbstractMCMC sampler and want to allow users to collect the
samples as a `FlexiChain{VarName}`, i.e., 

    sample(...; chain_type=FlexiChain{VarName})

then you should ensure that your method of `AbstractMCMC.step` returns a transition that can
be passed to this method. (The other return value, the state, is not relevant.)

Note that this method is already implemented for `VarNames.VarNamedTuple` (in which case the
stats are empty) as well as `VarNames.Draw`. Thus the easiest solution is to just return one
of those types.
"""
to_vnt_and_stats(vnt::VarNamedTuple) = (vnt, (;))
to_vnt_and_stats(d::Draw) = parameters(d), extras(d)
@public to_vnt_and_stats

"""
    to_nt_and_stats(transition)::Tuple{NamedTuple,NamedTuple}

Convert the _first output_ (i.e. the 'transition') of an AbstractMCMC sampler into a
`NamedTuple` mapping parameter names to their values, plus a `NamedTuple` of any additional
statistics.

The first `NamedTuple` will be converted into `Parameter` keys, and the second `NamedTuple`
into `Extra` keys.

If you are writing a custom AbstractMCMC sampler and want to allow users to collect the
samples as a `FlexiChain{Symbol}`, i.e., 

    sample(...; chain_type=FlexiChain{Symbol})

then you should ensure that your method of `AbstractMCMC.step` returns a transition that can
be passed to this method. (The other return value, the state, is not relevant.)
"""
to_nt_and_stats(nt::NamedTuple) = (nt, (;))
# These methods might fail with complex VarNames, but we can define it
to_nt_and_stats(vnt::VarNamedTuple) = (NamedTuple(vnt), (;))
to_nt_and_stats(d::Draw) = (NamedTuple(parameters(d)), extras(d))
@public to_nt_and_stats

function AbstractMCMC.bundle_samples(
    transitions::AbstractVector,
    @nospecialize(m::AbstractMCMC.AbstractModel),
    @nospecialize(s::AbstractMCMC.AbstractSampler),
    last_sampler_state::Any,
    chain_type::Type{FlexiChain{Symbol}};
    save_state=false,
    stats=missing,
    discard_initial::Int=0,
    thinning::Int=1,
    _kwargs...,
)::FlexiChain{Symbol}
    niters = length(transitions)
    nts_and_stats = map(FlexiChains.to_nt_and_stats, transitions)
    dicts = map(nts_and_stats) do (nt, stat)
        d = OrderedDict{ParameterOrExtra{Symbol},Any}(
            Parameter(sym) => val for (sym, val) in pairs(nt)
        )
        for (stat_name, stat_val) in pairs(stat)
            d[Extra(stat_name)] = stat_val
        end
        d
    end
    # timings
    tm = stats === missing ? missing : stats.stop - stats.start
    # last sampler state
    st = save_state ? last_sampler_state : missing
    # calculate iteration indices
    start = discard_initial + 1
    iter_indices = if thinning != 1
        range(start; step=thinning, length=niters)
    else
        # This returns UnitRange not StepRange -- a bit cleaner
        start:(start+niters-1)
    end
    return FlexiChain{Symbol}(
        niters,
        1,
        dicts;
        iter_indices=iter_indices,
        # 1:1 gives nicer DimMatrix output than just [1]
        chain_indices=1:1,
        sampling_time=[tm],
        last_sampler_state=[st],
    )
end

function AbstractMCMC.bundle_samples(
    transitions::AbstractVector,
    @nospecialize(m::AbstractMCMC.AbstractModel),
    @nospecialize(s::AbstractMCMC.AbstractSampler),
    last_sampler_state::Any,
    chain_type::Type{<:FlexiChain{<:VarName}};
    save_state=false,
    stats=missing,
    discard_initial::Int=0,
    thinning::Int=1,
    _kwargs...,
)::FlexiChain{VarName}
    niters = length(transitions)
    vnts_and_stats = map(FlexiChains.to_vnt_and_stats, transitions)
    dicts = map(vnts_and_stats) do (vnt, stat)
        d = OrderedDict{ParameterOrExtra{<:VarName},Any}(
            Parameter(vn) => val for (vn, val) in pairs(vnt)
        )
        for (stat_vn, stat_val) in pairs(stat)
            d[Extra(stat_vn)] = stat_val
        end
        d
    end
    # note that FlexiChains constructor expects structures to have size (niters x nchains),
    # so a vector won't do
    skeletons = hcat(map(VarNames.skeleton ∘ first, vnts_and_stats))
    # timings
    tm = stats === missing ? missing : stats.stop - stats.start
    # last sampler state
    st = save_state ? last_sampler_state : missing
    # calculate iteration indices
    start = discard_initial + 1
    iter_indices = if thinning != 1
        range(start; step=thinning, length=niters)
    else
        # This returns UnitRange not StepRange -- a bit cleaner
        start:(start+niters-1)
    end
    return FlexiChain{VarName}(
        niters,
        1,
        dicts;
        structures=skeletons,
        iter_indices=iter_indices,
        # 1:1 gives nicer DimMatrix output than just [1]
        chain_indices=1:1,
        sampling_time=[tm],
        last_sampler_state=[st],
    )
end

"""
    AbstractMCMC.from_samples(
        ::Type{<:VNChain},
        params_and_stats::AbstractMatrix{<:VarNames.Draw}
    )::OldVNChain

Convert a matrix of [`VarNames.Draw`](@extref) to a `VNChain`.
"""
function AbstractMCMC.from_samples(
    ::Type{<:FlexiChain{<:VarName}},
    params_and_stats::AbstractMatrix{<:VarNames.Draw},
)
    # Just need to convert the `ParamsWithStats` to Dicts of ParameterOrExtra.
    dicts = map(params_and_stats) do ps
        # Parameters
        d = OrderedDict{ParameterOrExtra{<:VarName},Any}(
            Parameter(vn) => val for (vn, val) in pairs(ps.params)
        )
        # Stats
        for (stat_vn, stat_val) in pairs(ps.stats)
            d[Extra(stat_vn)] = stat_val
        end
        d
    end
    # And get the structures.
    structures = map(ps -> VarNames.skeleton(ps.params), params_and_stats)
    return FlexiChain{VarName}(
        size(params_and_stats, 1),
        size(params_and_stats, 2),
        dicts;
        structures=structures,
    )
end

"""
    AbstractMCMC.from_samples(
        ::Type{<:VNChain},
        params_and_stats::AbstractMatrix{<:VarNamedTuple}
    )::VNChain

Convert a matrix of [`VarNames.VarNamedTuple`](@extref) to a `VNChain`.
"""
function AbstractMCMC.from_samples(
    ::Type{<:FlexiChain{<:VarName}},
    vnts::AbstractMatrix{<:VarNamedTuple},
)
    draws = map(vnts) do vnt
        VarNames.Draw(vnt, (;))
    end
    return AbstractMCMC.from_samples(FlexiChain{VarName}, draws)
end

"""
    AbstractMCMC.to_samples(
        ::Type{VarNames.Draw},
        chain::FlexiChain{T},
    )::DD.DimMatrix{<:VarNames.Draw} where {T<:VarName}

Convert a `VNChain` to a matrix of [`VarNames.Draw`](@extref) objects.
"""
function AbstractMCMC.to_samples(
    ::Type{VarNames.Draw},
    chain::FlexiChain{T},
)::DD.DimMatrix{<:VarNames.Draw} where {T<:VarName}
    # If there is no skeletal VNT structure stored, then values_at will return a Dict.
    # Otherwise it will return a Draw.
    dicts_or_draws = FlexiChains.values_at(chain; iter=:, chain=:)
    pwss = map(dicts_or_draws) do dict_or_draw
        if dict_or_draw isa VarNames.Draw
            dict_or_draw
        else
            # No skeleton. Just cry and use setindex!!.
            vnt = VarNamedTuple()
            for (vn_param, val) in pairs(dict_or_draw)
                if vn_param isa Parameter
                    vnt = VarNames.setindex!!(vnt, val, vn_param.name)
                end
            end
            # Stats
            stats_nt = NamedTuple(
                Symbol(extra_param.name) => val for
                (extra_param, val) in dict_or_draw if extra_param isa Extra
            )
            VarNames.Draw(vnt, stats_nt)
        end
    end
    return FlexiChains._raw_to_user_data(chain, pwss)
end

"""
    AbstractMCMC.to_samples(
        ::Type{VarNamedTuple},
        chain::FlexiChain{T},
    )::DD.DimMatrix{<:VarNamedTuple} where {T<:VarName}

Convert a `VNChain` to a matrix of [`VarNames.VarNamedTuple`](@extref) objects.
"""
function AbstractMCMC.to_samples(
    ::Type{VarNamedTuple},
    chain::FlexiChain{T},
)::DD.DimMatrix{<:VarNamedTuple} where {T<:VarName}
    pwss = AbstractMCMC.to_samples(VarNames.Draw, chain)
    return map(pws -> pws.params, pwss)
end
