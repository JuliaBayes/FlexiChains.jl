module FlexiChainsAbstractPPLExt

# Don't blanket import FlexiChains or VarNames as that will lead to conflicts with AbstractPPL
# identifiers
using FlexiChains: FlexiChains, FlexiChain, FlexiSummary
using AbstractPPL: AbstractPPL, VarName, @varname
using VarNames: VarNames
using OrderedCollections: OrderedSet
using DimensionalData: DimensionalData

const FC = FlexiChains
const DD = DimensionalData

function FC._map_optic(
    ::AbstractPPL.Iden,
    arr::AbstractArray,
    ::Union{VarName,FC.Prefixed{<:VarName}},
)
    return arr
end
function FC._map_optic(
    optic::AbstractPPL.AbstractOptic,
    arr::AbstractArray,
    orig_vn::Union{VarName,FC.Prefixed{<:VarName}},
)
    found = false
    results = map(arr) do elem
        if AbstractPPL.canview(optic, elem)
            found = true
            optic(elem)
        else
            missing
        end
    end
    found || throw(KeyError(orig_vn))
    return results
end

function FC._getindex_optic_and_vn(
    vn_keys::AbstractVector{<:VarName},
    vn::VarName{sym},
    optic::AbstractPPL.AbstractOptic,
    orig_vn::VarName{sym},
)::Tuple{AbstractPPL.AbstractOptic,VarName} where {sym}
    if vn in vn_keys
        return (optic, vn)
    else
        # Not found -- attempt to reduce.
        o = AbstractPPL.getoptic(vn)
        i, l = AbstractPPL.oinit(o), AbstractPPL.olast(o)
        if l isa AbstractPPL.Iden
            # Cannot reduce further
            throw(KeyError(orig_vn))
        else
            new_vn = VarName{sym}(i)
            new_optic = optic ∘ l
            return FC._getindex_optic_and_vn(vn_keys, new_vn, new_optic, orig_vn)
        end
    end
end

function FC._get_raw_data(
    cs::FC.ChainOrSummary{<:VarName},
    vn_param::FC.Parameter{<:VarName},
)
    # Shortcircuit if the VarName is already present as-is (this can save quite a bit of
    # time in tight loops)
    haskey(cs._data, vn_param) && return cs._data[vn_param]
    # Otherwise we might need to split up the VarName into a prefix + an optic.
    orig_vn = vn_param.name
    optic, vn =
        FC._getindex_optic_and_vn(FC.parameters(cs), orig_vn, AbstractPPL.Iden(), orig_vn)
    # Can't use get_raw_data in this line or else it will recurse.
    raw = cs._data[FC.Parameter(vn)]
    return FC._map_optic(optic, raw, orig_vn)
end

function Base.getindex(
    fchain::FlexiChain{<:VarName},
    vn::VarName;
    iter=Colon(),
    chain=Colon(),
    stack=nothing,
)
    raw = FC._get_raw_data(fchain, FC.Parameter(vn))
    return FC._raw_to_user_data(fchain, raw; name=string(FC.Parameter(vn)), stack=stack)[
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

$(FC.SUMMARY_GETINDEX_KWARGS)
"""
function Base.getindex(
    fs::FlexiSummary{<:VarName},
    vn::VarName;
    iter=FC._UNSPECIFIED_KWARG,
    chain=FC._UNSPECIFIED_KWARG,
    stat=FC._UNSPECIFIED_KWARG,
    stack=nothing,
)
    relevant_kwargs = FC._check_summary_kwargs(fs, iter, chain, stat)
    user_data = FC._raw_to_user_data(
        fs,
        FC._get_raw_data(fs, FC.Parameter(vn));
        name=string(FC.Parameter(vn)),
        stack=stack,
    )
    return FC._maybe_getindex_with_summary_kwargs(user_data, relevant_kwargs)
end

function FC.shares_tail(vn::VarName, target_vn::VarName)
    opt = AbstractPPL.varname_to_optic(vn)
    target_opt = AbstractPPL.varname_to_optic(target_vn)
    # TODO: Could be micro-optimised by stopping the loop as soon as opt is 'shorter' than
    # target_opt, but we don't yet have a function that gets the 'length' of a VarName, even
    # though the notion is quite well-defined.
    while !(opt isa AbstractPPL.Iden)
        if opt == target_opt
            return true
        else
            opt = AbstractPPL.otail(opt)
        end
    end
    return false
end
function FC._prefixed_get_key_and_optic(
    vns::Set{<:VarName},
    target_vn::VarName,
    optic::AbstractPPL.AbstractOptic,
    original_prefixed::FC.Prefixed{<:VarName},
)
    matching_vns = collect(filter(vn -> FC.shares_tail(vn, target_vn), vns))
    if isempty(matching_vns)
        # No matches found; but maybe we need to strip off some optics from the tail of
        # Prefixed. For example, if the user tries to access `Prefixed(@varname(x.b[1]))`,
        # and we have `@varname(a.x)` in the chain, then we should still return the data
        # corresponding to `@varname(a.x.b[1])` (if it exists).
        target_vn_optic = AbstractPPL.getoptic(target_vn)
        if target_vn_optic == AbstractPPL.Iden()
            # Nothing left to strip
            throw(KeyError(original_prefixed))
        else
            init_optic = AbstractPPL.oinit(target_vn_optic)
            new_optic = Base.cat(AbstractPPL.olast(target_vn_optic), optic)
            new_target_vn = VarName{AbstractPPL.getsym(target_vn)}(init_optic)
            return FC._prefixed_get_key_and_optic(
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
function FC.prefixed_get_key_and_optic(
    vns::Set{<:VarName},
    prefixed::FC.Prefixed{<:VarName},
)
    return FC._prefixed_get_key_and_optic(
        vns,
        prefixed.target_vn,
        AbstractPPL.Iden(),
        prefixed,
    )
end

function Base.getindex(
    fchain::FlexiChain{<:VarName},
    prefixed::FC.Prefixed{<:VarName};
    iter=Colon(),
    chain=Colon(),
    stack=nothing,
)
    vn, optic = FC.prefixed_get_key_and_optic(Set(FC.parameters(fchain)), prefixed)
    # We could use get_raw_data here, but we don't need to since we already calculated the
    # split between vn and optic (get_raw_data would just recalculate it).
    combined_vn = AbstractPPL.append_optic(vn, optic)
    raw = fchain._data[FC.Parameter(vn)]
    raw_with_optic = FC._map_optic(optic, raw, prefixed)
    return FC._raw_to_user_data(
        fchain,
        raw_with_optic;
        name=string(FC.Parameter(combined_vn)),
        stack=stack,
    )[
        iter=iter,
        chain=chain,
    ]
end

function Base.getindex(
    fs::FlexiSummary{<:VarName},
    prefixed::FC.Prefixed{<:VarName};
    iter=FC._UNSPECIFIED_KWARG,
    chain=FC._UNSPECIFIED_KWARG,
    stat=FC._UNSPECIFIED_KWARG,
    stack=nothing,
)
    relevant_kwargs = FC._check_summary_kwargs(fs, iter, chain, stat)
    vn, optic = FC.prefixed_get_key_and_optic(Set(FC.parameters(fs)), prefixed)
    raw = fs._data[FC.Parameter(vn)]
    combined_vn = AbstractPPL.append_optic(vn, optic)
    user_data = FC._raw_to_user_data(
        fs,
        FC._map_optic(optic, raw, prefixed);
        name=string(FC.Parameter(combined_vn)),
        stack=stack,
    )
    return FC._maybe_getindex_with_summary_kwargs(user_data, relevant_kwargs)
end

function FC._split_varnames(
    cs::FC.ChainOrSummary{<:VarName};
    collect_plot_names::Bool=false,
)
    vns = OrderedSet{VarName}()
    plot_names = Dict{VarName,String}()
    for vn in FC.parameters(cs)
        d = FC._get_raw_data(cs, FC.Parameter(vn))
        if FC._elems_have_fixed_vn_leaves(d)
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
    return cs[[collect(vns)..., FC.extras(cs)...]], plot_names
end

_internal_to_optic(@nospecialize x) = x
_internal_to_optic(di::AbstractPPL.DynamicIndex) = VarNames.DynamicIndex(di.expr, di.f)
_internal_to_optic(::AbstractPPL.Iden) = VarNames.Iden()
_internal_to_optic(p::AbstractPPL.Property{sym}) where {sym} =
    VarNames.Property{sym}(_internal_to_optic(p.child))
function _internal_to_optic(i::AbstractPPL.Index)
    ix = map(_internal_to_optic, i.ix)
    kw = map(_internal_to_optic, i.kw)
    return VarNames.Index(ix, kw, _internal_to_optic(i.child))
end
function FC._internal_to_varname(vn::AbstractPPL.VarName{sym}) where {sym}
    return FC.VarName{sym}(_internal_to_optic(AbstractPPL.getoptic(vn)))
end

end # module FlexiChainsAbstractPPLExt
