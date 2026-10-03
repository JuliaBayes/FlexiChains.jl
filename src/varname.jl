using VarNames: VarNames, VarName, @vn, @varname

@public Prefixed


"""
    Prefixed(vn::VarName)

A struct that represents a VarName that might have an arbitrary prefix. This is useful for
indexing into a chain with VarNames when the exact prefix is not known (or too verbose to
construct). For example, this allows for data-processing code that is agnostic towards
whether a submodel was used or not.

When indexing into a chain with a `Prefixed{VarName}` key, the chain will be searched for
any VarName that ends with the target VarName. For example, if the key is
`Prefixed(@vn(x))`, and the chain contains `@vn(a.x)`, the data corresponding to `@vn(a.x)`
will be returned. (If there are multiple matches, an error is thrown.)

Note that `Prefixed` is only supported for `VarName`s, and not for general keys.
"""
struct Prefixed{T}
    # TODO(penelopeysm): Should be <:VarNames.VarName or <:VarNames.VarName
    target_vn::T
end
Base.show(io::IO, prefixed::Prefixed) = print(io, "Prefixed($(prefixed.target_vn))")
"""
    Prefixed(sym::Symbol)

Convenience function for `Prefixed(@varname(sym))`.
"""
Prefixed(sym::Symbol) = Prefixed(VarName{sym}())

"""
Helper function to apply an optic function to an array. Errors if none of the array elements
actually can be transformed by the optic. If only some of the array elements can be
transformed, then the transformed elements are returned and the rest are `missing`.

`orig_vn` is the VarName that the user attempted to access. It is used only for error
reporting.
"""
function _map_optic(::VarNames.Iden, arr::AbstractArray, ::Union{VarName,Prefixed})
    return arr
end
function _map_optic(
    optic::VarNames.AbstractOptic,
    arr::AbstractArray,
    orig_vn::Union{VarName,Prefixed},
)
    found = false
    results = map(arr) do elem
        if VarNames.canview(optic, elem)
            found = true
            optic(elem)
        else
            missing
        end
    end
    found || throw(KeyError(orig_vn))
    return results
end

"""
Helper function for `getindex` with `VarName`. Accesses the VarName `vn` in the chain (if it
is a parameter) and applies the `optic` function to the data before returning it.

`orig_vn` is the VarName that the user attempted to access. It is used only for error
reporting.
"""
function _getindex_optic_and_vn(
    vn_keys::AbstractVector{<:VarName},
    vn::VarName{sym},
    optic::VarNames.AbstractOptic,
    orig_vn::VarName{sym},
)::Tuple{VarNames.AbstractOptic,VarName} where {sym}
    if vn in vn_keys
        return (optic, vn)
    else
        # Not found -- attempt to reduce.
        o = VarNames.getoptic(vn)
        i, l = VarNames.oinit(o), VarNames.olast(o)
        if l isa VarNames.Iden
            # Cannot reduce further
            throw(KeyError(orig_vn))
        else
            new_vn = VarName{sym}(i)
            new_optic = optic ∘ l
            return _getindex_optic_and_vn(vn_keys, new_vn, new_optic, orig_vn)
        end
    end
end

"""
Overloaded method which provides extra functionality when indexing by VarNames.
"""
function _get_raw_data(cs::ChainOrSummary{<:VarName}, vn_param::Parameter{<:VarName})
    # Shortcircuit if the VarName is already present as-is (this can save quite a bit of
    # time in tight loops)
    haskey(cs._data, vn_param) && return cs._data[vn_param]
    # Otherwise we might need to split up the VarName into a prefix + an optic.
    orig_vn = vn_param.name
    optic, vn = _getindex_optic_and_vn(
        FlexiChains.parameters(cs),
        orig_vn,
        VarNames.Iden(),
        orig_vn,
    )
    # Can't use get_raw_data in this line or else it will recurse.
    raw = cs._data[Parameter(vn)]
    return _map_optic(optic, raw, orig_vn)
end

"""
    Base.getindex(
        fchain::FlexiChain{<:VarName}, vn::VarName;
        iter=Colon(), chain=Colon()
    )

An additional specialisation for `VarName`, meant for convenience when working with
Turing.jl models.

`chn[vn]` first checks if the VarName `vn` itself is stored in the chain. If not, it will
attempt to check if the 'parent' of `vn` is in the chain, and so on, until all possibilities
have been exhausted.

For example, the parent of `@varname(x[1])` is `@varname(x)`. If `@varname(x[1])` itself is
in the chain, then that will be returned. If not, then `@varname(x)` will be checked next,
and if that is a vector-valued parameter then all of its first entries will be returned.
"""
function Base.getindex(
    fchain::FlexiChain{<:VarName},
    vn::VarName;
    iter=Colon(),
    chain=Colon(),
    stack=nothing,
)
    raw = _get_raw_data(fchain, Parameter(vn))
    return _raw_to_user_data(fchain, raw; name=string(Parameter(vn)), stack=stack)[
        iter=iter,
        chain=chain,
    ]
end
"""
    Base.getindex(
        fs::FlexiSummary{<:VarName},
        vn::VarName;
        [iter=Colon(),]
        [chain=Colon(),]
        [stat=Colon()]
    )

An additional specialisation for `VarName`, meant for convenience when working with
Turing.jl models.

$(SUMMARY_GETINDEX_KWARGS)
"""
function Base.getindex(
    fs::FlexiSummary{<:VarName},
    vn::VarName;
    iter=_UNSPECIFIED_KWARG,
    chain=_UNSPECIFIED_KWARG,
    stat=_UNSPECIFIED_KWARG,
    stack=nothing,
)
    relevant_kwargs = _check_summary_kwargs(fs, iter, chain, stat)
    user_data = _raw_to_user_data(
        fs,
        _get_raw_data(fs, Parameter(vn));
        name=string(Parameter(vn)),
        stack=stack,
    )
    return _maybe_getindex_with_summary_kwargs(user_data, relevant_kwargs)
end

function shares_tail(vn::VarName, target_vn::VarName)
    opt = VarNames.varname_to_optic(vn)
    target_opt = VarNames.varname_to_optic(target_vn)
    # TODO: Could be micro-optimised by stopping the loop as soon as opt is 'shorter' than
    # target_opt, but we don't yet have a function that gets the 'length' of a VarName, even
    # though the notion is quite well-defined.
    while !(opt isa VarNames.Iden)
        if opt == target_opt
            return true
        else
            opt = VarNames.otail(opt)
        end
    end
    return false
end
function _prefixed_get_key_and_optic(
    vns::Set{<:VarName},
    target_vn::VarName,
    optic::VarNames.AbstractOptic,
    original_prefixed::Prefixed,
)
    matching_vns = collect(filter(vn -> shares_tail(vn, target_vn), vns))
    if isempty(matching_vns)
        # No matches found; but maybe we need to strip off some optics from the tail of
        # Prefixed. For example, if the user tries to access `Prefixed(@varname(x.b[1]))`,
        # and we have `@varname(a.x)` in the chain, then we should still return the data
        # corresponding to `@varname(a.x.b[1])` (if it exists).
        target_vn_optic = VarNames.getoptic(target_vn)
        if target_vn_optic == VarNames.Iden()
            # Nothing left to strip
            throw(KeyError(original_prefixed))
        else
            init_optic = VarNames.oinit(target_vn_optic)
            new_optic = Base.cat(VarNames.olast(target_vn_optic), optic)
            new_target_vn = VarName{VarNames.getsym(target_vn)}(init_optic)
            return _prefixed_get_key_and_optic(
                vns,
                new_target_vn,
                new_optic,
                original_prefixed,
            )
        end
    elseif length(matching_vns) > 1
        throw(
            ArgumentError(
                "Multiple matches found for $(original_prefixed): ($(join(matching_vns, ", ")))",
            ),
        )
    else
        return only(matching_vns), optic
    end
end
function prefixed_get_key_and_optic(vns::Set{<:VarName}, prefixed::Prefixed)
    return _prefixed_get_key_and_optic(vns, prefixed.target_vn, VarNames.Iden(), prefixed)
end

"""
    Base.getindex(
        fchain::FlexiChain{<:VarName}, prefixed::Prefixed{<:VarName};
        iter=Colon(), chain=Colon()
    )

Get a parameter from the chain that matches the target VarName but with an arbitrary prefix.
See [`Prefixed`](@ref) for details.
"""
function Base.getindex(
    fchain::FlexiChain{<:VarName},
    prefixed::Prefixed;
    iter=Colon(),
    chain=Colon(),
    stack=nothing,
)
    vn, optic = prefixed_get_key_and_optic(Set(FlexiChains.parameters(fchain)), prefixed)
    # We could use get_raw_data here, but we don't need to since we already calculated the
    # split between vn and optic (get_raw_data would just recalculate it).
    combined_vn = VarNames.append_optic(vn, optic)
    raw = fchain._data[Parameter(vn)]
    raw_with_optic = _map_optic(optic, raw, prefixed)
    return _raw_to_user_data(
        fchain,
        raw_with_optic;
        name=string(Parameter(combined_vn)),
        stack=stack,
    )[
        iter=iter,
        chain=chain,
    ]
end
"""
    Base.getindex(
        fs::FlexiSummary{<:VarName},
        prefixed::Prefixed;
        [iter=Colon(),]
        [chain=Colon(),]
        [stat=Colon()]
    )

Get a parameter from the summary that matches the target VarName but with an arbitrary
prefix. See [`Prefixed`](@ref) for details.
"""
function Base.getindex(
    fs::FlexiSummary{<:VarName},
    prefixed::Prefixed;
    iter=_UNSPECIFIED_KWARG,
    chain=_UNSPECIFIED_KWARG,
    stat=_UNSPECIFIED_KWARG,
    stack=nothing,
)
    relevant_kwargs = _check_summary_kwargs(fs, iter, chain, stat)
    vn, optic = prefixed_get_key_and_optic(Set(FlexiChains.parameters(fs)), prefixed)
    raw = fs._data[Parameter(vn)]
    combined_vn = VarNames.append_optic(vn, optic)
    user_data = _raw_to_user_data(
        fs,
        _map_optic(optic, raw, prefixed);
        name=string(Parameter(combined_vn)),
        stack=stack,
    )
    return _maybe_getindex_with_summary_kwargs(user_data, relevant_kwargs)
end
