module FlexiChainsPosteriorDBExt

using PosteriorDB
using OrderedCollections: OrderedDict
using FlexiChains: FlexiChains, FlexiChain, Parameter, VarName, VarNames

"""
    FlexiChains.from_posteriordb(
        ref::PosteriorDB.ReferencePosterior
    )::FlexiChain{VarName}

Load a `PosteriorDB.ReferencePosterior` into a `FlexiChain{VarName}`.

PosteriorDB stores array-valued parameters as separate scalar entries, using Stan's naming
convention (e.g. `theta[1]`, ..., `theta[8]`, or `Sigma[1,1]`, `Sigma[2,1]`, ...). These are
recombined into a single array-valued parameter (e.g. `@vn(theta)`, where each draw is a
`Vector{Float64}`). If the entries for a given parameter do not form a complete array, they
are instead kept as separate scalar parameters with indexed `VarName`s (e.g.
`@vn(theta[1])`).
"""
function FlexiChains.from_posteriordb(ref::PosteriorDB.ReferencePosterior)
    raw, niters, nchains, iter_indices = _load_posteriordb_ref(ref)

    # Group the Stan names by their base symbol, keeping track of the indices.
    groups = OrderedDict{Symbol,Vector{Pair{Any,Matrix{Float64}}}}()
    for (name, vals) in raw
        sym, idx = _parse_stan_name(name)
        push!(get!(groups, sym, Pair{Any,Matrix{Float64}}[]), idx => vals)
    end

    d = OrderedDict{Parameter{<:VarName},Matrix}()
    for (sym, entries) in groups
        shape = _array_shape(entries)
        if shape === nothing
            # Scalar, or something that cannot be reassembled into an array: keep each
            # entry as a separate parameter.
            for (idx, vals) in entries
                d[Parameter(_make_varname(sym, idx))] = vals
            end
        else
            arrs = [Array{Float64}(undef, shape) for _ in 1:niters, _ in 1:nchains]
            for (idx, vals) in entries, c in 1:nchains, i in 1:niters
                arrs[i, c][idx...] = vals[i, c]
            end
            d[Parameter(VarName{sym}())] = arrs
        end
    end
    return FlexiChain{VarName}(niters, nchains, d; iter_indices=iter_indices)
end

"""
    FlexiChains.from_posteriordb_ref(
        ref::PosteriorDB.ReferencePosterior
    )::FlexiChain{String}

Load a `PosteriorDB.ReferencePosterior` into a `FlexiChain`. The keys are stored as strings,
which matches the storage format in PosteriorDB.jl.

!!! warning
    This function is deprecated. Please use [`FlexiChains.from_posteriordb`](@ref) instead,
    which returns a `FlexiChain{VarName}` with array-valued parameters recombined.
"""
function FlexiChains.from_posteriordb_ref(ref::PosteriorDB.ReferencePosterior)
    Base.depwarn(
        "`FlexiChains.from_posteriordb_ref(ref)` is deprecated, use `FlexiChains.from_posteriordb(ref)` instead. Note that `from_posteriordb` returns a `FlexiChain{VarName}` rather than a `FlexiChain{String}`.",
        :from_posteriordb_ref,
    )
    raw, niters, nchains, iter_indices = _load_posteriordb_ref(ref)
    d = OrderedDict{Parameter{String},Matrix{Float64}}(Parameter(k) => v for (k, v) in raw)
    return FlexiChain{String}(niters, nchains, d; iter_indices=iter_indices)
end

"""
Load the raw data from a reference posterior. Returns an `OrderedDict` mapping the
PosteriorDB names to `niters x nchains` matrices, as well as `niters`, `nchains`, and the
iteration indices.
"""
function _load_posteriordb_ref(ref::PosteriorDB.ReferencePosterior)
    ref_post = PosteriorDB.load(ref)
    ref_info = PosteriorDB.info(ref)
    # All of this Dict indexing is obviously quite fragile, but surprisingly it just works
    # on all the reference posteriors in PosteriorDB (this is tested in CI), so I guess we
    # can just roll with it.
    nchains = ref_info["inference"]["method_arguments"]["chains"]
    # nsteps = total number of steps including warmup and thinned
    nsteps = ref_info["inference"]["method_arguments"]["iter"]
    nwarmup = ref_info["inference"]["method_arguments"]["warmup"]
    thin = ref_info["inference"]["method_arguments"]["thin"]
    niters, r = divrem(nsteps - nwarmup, thin)
    @assert r == 0

    # `ref_post` is a Vector of OrderedDicts, one per chain. We _could_ convert each
    # OrderedDict to a chain and then hcat them, but let's be good citizens and avoid
    # unnecessary work by hcatting the raw data directly.
    raw = OrderedDict{String,Matrix{Float64}}()
    for k in keys(ref_post[1])
        raw[String(k)] = hcat(map(d -> d[k], ref_post)...)
    end
    iter_indices = if thin != 1
        range(nwarmup + thin; step=thin, length=niters)
    else
        # This returns UnitRange not StepRange -- a bit cleaner
        (nwarmup+1):nsteps
    end
    return raw, niters, nchains, iter_indices
end

const STAN_NAME_REGEX = r"^([A-Za-z_][A-Za-z0-9_]*)(?:\[\s*(\d+(?:\s*,\s*\d+)*)\s*\])?$"

"""
Parse a Stan parameter name like `theta[1,2]` into its base symbol and a tuple of indices
(`(:theta, (1, 2))`). Names without indices return `nothing` for the indices. Names that do
not follow Stan's naming convention are returned as a `Symbol` as-is.
"""
function _parse_stan_name(name::AbstractString)
    m = match(STAN_NAME_REGEX, name)
    m === nothing && return (Symbol(name), nothing)
    sym = Symbol(m.captures[1])
    idx = m.captures[2]
    idx === nothing && return (sym, nothing)
    return (sym, Tuple(parse.(Int, split(idx, ','))))
end

function _make_varname(sym::Symbol, idx)
    return if idx === nothing
        VarName{sym}()
    else
        VarName{sym}(VarNames.Index(idx, (;)))
    end
end

"""
Given a list of `indices => values` for a single base symbol, determine the shape of the
array that they form. Returns `nothing` if the entries are not indexed, or if they do not
form a complete, 1-based array with each element appearing exactly once.
"""
function _array_shape(entries)
    idxs = map(first, entries)
    any(isnothing, idxs) && return nothing
    N = length(first(idxs))
    all(idx -> length(idx) == N, idxs) || return nothing
    any(idx -> any(<(1), idx), idxs) && return nothing
    shape = ntuple(n -> maximum(idx -> idx[n], idxs), N)
    (length(idxs) == prod(shape) && allunique(idxs)) || return nothing
    return shape
end

end # module
