module FlexiChainsAbstractPPLExt

# Don't blanket import FlexiChains or VarNames as that will lead to conflicts with AbstractPPL
# identifiers
using FlexiChains: FlexiChains, FlexiChain, FlexiSummary
using AbstractPPL: AbstractPPL, VarName, @varname
using VarNames: VarNames
using OrderedCollections: OrderedSet, OrderedDict
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
    stack::Bool=false,
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
    stack::Bool=false,
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
    stack::Bool=false,
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
    stack::Bool=false,
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
    plot_names = Dict{VarName,String}()
    N = cs isa FlexiChain ? 2 : 3
    new_data = OrderedDict{FC.ParameterOrExtra{<:VarName},Array{<:Any,N}}()
    for vn in FC.parameters(cs)
        d = FC._get_raw_data(cs, FC.Parameter(vn))
        for (vn_leaf, leaf_data) in FC._split_parameter_leaves(vn, d)
            new_data[FC.Parameter(vn_leaf)] = leaf_data
        end
        if collect_plot_names &&
           FC._elems_have_fixed_vn_leaves(d) &&
           eltype(d) <: DD.DimVector
            d1 = first(d)
            dim = DD.dims(d1, 1)
            label_type = eltype(dim)
            if (label_type === Symbol || label_type <: AbstractString)
                vn_leaves = AbstractPPL.varname_leaves(vn, d1)
                for (vn_leaf, label) in zip(vn_leaves, dim)
                    prettylabel = label isa Symbol ? repr(label) : label
                    plot_names[vn_leaf] = string(vn, "[", prettylabel, "]")
                end
            end
        end
    end
    for k in FC.extras(cs)
        new_data[k] = FC._get_raw_data(cs, k)
    end
    return FC._replace_data(cs, VarName, new_data), plot_names
end

function FC._split_parameter_leaves(vn::VarName, d::AbstractArray)
    if FC._elems_have_fixed_vn_leaves(d)
        # Don't need to iterate over all array elements - just check the first one.
        d1 = first(d)
        vn_leaves = collect(AbstractPPL.varname_leaves(vn, d1))
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
            return [vn_leaf => FC._get_leaf_data(vn, d, vn_leaf) for vn_leaf in vn_leaves]
        end
    else # leaves may have different sizes
        vns = OrderedSet{VarName}()
        for i in eachindex(d)
            for vn_leaf in AbstractPPL.varname_leaves(vn, d[i])
                push!(vns, vn_leaf)
            end
        end
        return [vn_leaf => FC._get_leaf_data(vn, d, vn_leaf) for vn_leaf in vns]
    end
end
# Get leaf data by applying the optic - slower fallback that always works
function FC._get_leaf_data(vn::VarName, d::AbstractArray, vn_leaf::VarName)
    optic, _ = FC._getindex_optic_and_vn([vn], vn_leaf, AbstractPPL.Iden(), vn_leaf)
    return FC._map_optic(optic, d, vn_leaf)
end

function FC._parameter_array_components(
    cs::FC.ChainOrSummary{TKey};
    warn::Bool=true,
    eltype_filter::Type{T}=Any,
    parameters_only::Bool=true,
    split_varnames::Bool=true,
) where {TKey<:VarName,T}
    kept_keys = parameters_only ? TKey[] : FC.ParameterOrExtra{<:TKey}[]
    kept_eltypes = Type[]
    skipped_keys = FC.ParameterOrExtra{<:TKey}[]

    # Loop through data without copying to figure out eltype and size
    for (k, v) in cs._data
        if split_varnames &&
           k isa FC.Parameter &&
           eltype(v) <: AbstractArray{<:eltype_filter}
            vn = FC.get_name(k)
            d1 = first(v)
            if FC._elems_have_fixed_vn_leaves(v) &&
               d1 isa AbstractArray{<:Union{Real,Missing}}
                # No need to look more at data if all have fixed leaves
                for vn_leaf in AbstractPPL.varname_leaves(vn, d1)
                    push!(kept_keys, parameters_only ? vn_leaf : FC.Parameter(vn_leaf))
                    push!(kept_eltypes, eltype(d1))
                end
            else
                # Fall back to materializing leaves
                for (vn_leaf, leaf_data) in FC._split_parameter_leaves(vn, v)
                    if eltype(leaf_data) <: eltype_filter
                        push!(kept_keys, parameters_only ? vn_leaf : FC.Parameter(vn_leaf))
                        push!(kept_eltypes, eltype(leaf_data))
                    else
                        push!(skipped_keys, FC.Parameter(vn_leaf))
                    end
                end
            end
        elseif eltype(v) <: eltype_filter && (!parameters_only || k isa FC.Parameter)
            push!(kept_keys, parameters_only ? FC.get_name(k) : k)
            push!(kept_eltypes, eltype(v))
        elseif !(parameters_only && k isa FC.Extra)
            push!(skipped_keys, k)
        end
    end
    if warn && !isempty(skipped_keys)
        skipped_str = join(("`$k`" for k in skipped_keys), ", ")
        @warn "skipping keys $skipped_str as their values do not subtype $eltype_filter"
    end

    s = map(length, DD.dims(cs))
    if isempty(kept_keys)
        @warn "no keys with values subtyping $eltype_filter found"
        return Array{T}(undef, (s..., 0)), kept_keys
    end

    # Allocate output and loop again to copy data
    Tout = reduce(typejoin, kept_eltypes)
    output = Array{Tout}(undef, (s..., length(kept_keys)))
    _write_parameters_to_array!(output, cs; split_varnames, parameters_only)
    return output, kept_keys
end
# function barrier for a small performance improvement
function _write_parameters_to_array!(
    output::Array{T,N},
    cs;
    split_varnames,
    parameters_only,
) where {T,N}
    col = 0
    for (k, v) in cs._data
        if split_varnames && k isa FC.Parameter && eltype(v) <: AbstractArray{<:T}
            vn = FC.get_name(k)
            d1 = first(v)
            if FC._elems_have_fixed_vn_leaves(v) &&
               d1 isa AbstractArray{<:Union{Real,Missing}}
                for i in eachindex(d1)
                    col += 1
                    selectdim(output, N, col) .= getindex.(v, i)
                end
            else
                for (vn_leaf, leaf_data) in FC._split_parameter_leaves(vn, v)
                    if eltype(leaf_data) <: T
                        col += 1
                        copyto!(selectdim(output, N, col), leaf_data)
                    end
                end
            end
        elseif eltype(v) <: T && (!parameters_only || k isa FC.Parameter)
            col += 1
            copyto!(selectdim(output, N, col), v)
        end
    end
end

# convert AbstractPPL optics to VarNames optics
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
# convert AbstractPPL VarNames to FlexiChains VarNames
function FC._as_varname(vn::AbstractPPL.VarName{sym}) where {sym}
    return FC.VarName{sym}(_internal_to_optic(AbstractPPL.getoptic(vn)))
end

FC._maybe_promote_key(::Type{<:AbstractPPL.VarName}) = AbstractPPL.VarName

end # module FlexiChainsAbstractPPLExt
