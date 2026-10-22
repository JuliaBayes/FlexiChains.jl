module FlexiChainsPosteriorDBExt

using PosteriorDB
using OrderedCollections: OrderedDict
using FlexiChains: FlexiChains, FlexiChain, Parameter, VarName

"""
    FlexiChains.from_posteriordb(ref::PosteriorDB.ReferencePosterior)
    FlexiChains.from_posteriordb(db::PosteriorDB.PosteriorDatabase, model_name::String)

Load a reference posterior from PosteriorDB.jl into a `FlexiChain{VarName}`.

PosteriorDB stores vector-valued parameters as separate scalar entries, using Stan's naming
convention (e.g. `theta[1]`, ..., `theta[8]`). When loaded into FlexiChains, these are
recombined into a single vector-valued parameter (e.g. `@vn(theta)`, where each draw is a
`Vector{Float64}`).
"""
function FlexiChains.from_posteriordb(ref::PosteriorDB.ReferencePosterior)
    raw, niters, nchains, iter_indices = _load_posteriordb_ref(ref)

    # Group the Stan names by their base symbol, keeping track of the indices.
    groups = OrderedDict{Symbol,Vector{Pair{Union{Nothing,Int},Matrix{Float64}}}}()
    for (name, vals) in raw
        sym, idx = _parse_stan_name(name)
        push!(get!(groups, sym, Pair{Union{Nothing,Int},Matrix{Float64}}[]), idx => vals)
    end

    d = OrderedDict{Parameter{<:VarName},Matrix}()
    for (sym, entries) in groups
        len = _vector_length(sym, entries)
        if len === nothing
            # Scalar parameter: there is exactly one entry, with no index.
            d[Parameter(VarName{sym}())] = only(entries).second
        else
            vecs = [Vector{Float64}(undef, len) for _ in 1:niters, _ in 1:nchains]
            for (idx, vals) in entries, c in 1:nchains, i in 1:niters
                vecs[i, c][idx] = vals[i, c]
            end
            d[Parameter(VarName{sym}())] = vecs
        end
    end
    return FlexiChain{VarName}(niters, nchains, d; iter_indices=iter_indices)
end
function FlexiChains.from_posteriordb(db::PosteriorDB.PosteriorDatabase, model_name::String)
    post = PosteriorDB.posterior(db, model_name)
    ref = PosteriorDB.reference_posterior(post)
    ref === nothing &&
        throw(ArgumentError("Posterior `$model_name` has no reference posterior."))
    return FlexiChains.from_posteriordb(ref)
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
Parse a Stan parameter name like `theta[3]` into its base symbol and index (`(:theta, 3)`).
Names without an index return `nothing` for the index. Names that do not follow Stan's
naming convention are returned as a `Symbol` as-is. Multi-dimensional names like
`Sigma[1,2]` throw an error.
"""
function _parse_stan_name(name::AbstractString)
    m = match(STAN_NAME_REGEX, name)
    m === nothing && return (Symbol(name), nothing)
    sym = Symbol(m.captures[1])
    idx = m.captures[2]
    idx === nothing && return (sym, nothing)
    if occursin(',', idx)
        error(
            "PosteriorDB parameter `$name` looks like a matrix-valued parameter, which " *
            "`from_posteriordb` does not support. Please open an issue on FlexiChains.jl.",
        )
    end
    return (sym, parse(Int, idx))
end

"""
Given a list of `index => values` for a single base symbol, determine the length of the
vector that they form. Returns `nothing` if the (single) entry is not indexed, i.e. the
parameter is a scalar. Throws an error if the indices do not form a complete, 1-based vector
with each element appearing exactly once.
"""
function _vector_length(sym::Symbol, entries)
    idxs = map(first, entries)
    all(isnothing, idxs) && return nothing
    if any(isnothing, idxs) || sort(Vector{Int}(idxs)) != 1:length(idxs)
        error(
            "PosteriorDB entries for parameter `$sym` do not form a complete, 1-based " *
            "vector (got indices $(idxs)). Please open an issue on FlexiChains.jl.",
        )
    end
    return length(idxs)
end

end # module
