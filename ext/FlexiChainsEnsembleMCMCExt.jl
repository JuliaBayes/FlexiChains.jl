module FlexiChainsEnsembleMCMCExt

using EnsembleMCMC: EnsembleMCMC
using FlexiChains: FlexiChains, FlexiChain, Parameter, Extra
using DimensionalData: DimArray, Dim
using OrderedCollections: OrderedDict

const EnsembleDraws = NamedTuple{(:positions, :logdensities, :accepted, :move_indices, :walker_ids)}

"""
    FlexiChains.FlexiChain(draws, others...; param_names=nothing, kwargs...)

Convert one or more results of `EnsembleMCMC.sample!` to a `FlexiChain{Symbol}`.
Each result represents one independent ensemble run, not one walker. All runs
must have the same coordinate count, positive sweep count, and ordered walker IDs.

Each iteration is one sweep. The matrix-valued parameter `:positions` has
dimensions `coordinate × walker`, with walker IDs as dimension labels. Supply
`param_names` to store each coordinate as a named, walker-valued parameter instead.
Names must be unique and match the coordinate count.
Extras `:log_density` and `:accepted` are walker-labelled vectors;
`:move_index` is the move index for the sweep. Positions, log densities, and
acceptance flags are views: mutations are shared with the input arrays.
Labels and scalar move indices are copied. Containers still allocate;
indexing with `stack=true` materializes an array rather than returning a view.
Chain metadata keywords, such as `iter_indices` and `chain_indices`, pass to
the `FlexiChain` constructor. Iteration indices default to `1:nsweeps`, since
`sample!` does not record the number of preceding warmup sweeps.

This conversion does not pool walkers or add ensemble-aware diagnostics.
Walkers within one ensemble are not independent chains. Standard diagnostics
apply to individual coordinate/walker components, not the pooled estimator.
Multiple arguments must come from independent runs, not chunks of one run.
"""
function FlexiChains.FlexiChain(
    first::EnsembleDraws, others::EnsembleDraws...; param_names=nothing, kwargs...
)
    runs = (first, others...)
    ndims(first.positions) == 3 || throw(DimensionMismatch("positions must have three dimensions"))
    ncoords, nwalkers, nsweeps = size(first.positions)
    nsweeps > 0 || throw(ArgumentError("at least one sweep is needed to retain walker dimensions"))
    walker_ids = copy(first.walker_ids)
    length(walker_ids) == nwalkers || throw(DimensionMismatch("walker IDs must match positions"))
    for run in runs
        size(run.positions) == (ncoords, nwalkers, nsweeps) ||
            throw(DimensionMismatch("ensemble runs must have matching position shapes"))
        run.walker_ids == walker_ids ||
            throw(DimensionMismatch("ensemble runs must have matching ordered walker IDs"))
        size(run.logdensities) == size(run.accepted) == (nwalkers, nsweeps) ||
            throw(DimensionMismatch("log densities and acceptance flags must match positions"))
        length(run.move_indices) == nsweeps ||
            throw(DimensionMismatch("move indices must match the sweep count"))
    end

    walker = Dim{:walker}(walker_ids)
    coordinates = Dim{:coordinate}(1:ncoords)
    data = OrderedDict{Any,Matrix}()
    if param_names === nothing
        data[Parameter(:positions)] = [
            DimArray(view(run.positions, :, :, i), (coordinates, walker))
            for i in 1:nsweeps, run in runs
        ]
    else
        names = Symbol.(param_names)
        length(names) == ncoords || throw(DimensionMismatch("one name is required per coordinate"))
        allunique(names) || throw(ArgumentError("parameter names must be unique"))
        for (j, name) in enumerate(names)
            data[Parameter(name)] = [
                DimArray(view(run.positions, j, :, i), walker)
                for i in 1:nsweeps, run in runs
            ]
        end
    end
    data[Extra(:log_density)] = [
        DimArray(view(run.logdensities, :, i), walker) for i in 1:nsweeps, run in runs
    ]
    data[Extra(:accepted)] = [
        DimArray(view(run.accepted, :, i), walker) for i in 1:nsweeps, run in runs
    ]
    data[Extra(:move_index)] = [run.move_indices[i] for i in 1:nsweeps, run in runs]
    return FlexiChain{Symbol}(nsweeps, length(runs), data; kwargs...)
end

end
