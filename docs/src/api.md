# API

The types and functions documented on this page form part of FlexiChains's public API.

On Julia 1.11 and later, these are marked with the `public` keyword (or are extensions of other packages' APIs).

FlexiChains also guarantees that any changes to these APIs will be reflected with a breaking version bump.

## The `FlexiChain` and `FlexiSummary` types

The `FlexiChain` and `FlexiSummary` types are technically marked as public, but you should not handle them or their fields directly.
For dispatch purposes, it is guaranteed that the first type parameter is always the key type; this should typically be all you need.
Both types have extra type parameters, but they are considered internal and may change at any time.

```@docs
FlexiChains.FlexiChain
FlexiChains.FlexiSummary
```

There are aliases for common `FlexiChain` key types:

```@docs
VNChain
SymChain
```

You can also use `Base.keytype`:

```@docs
Base.keytype(::FlexiChains.ChainOrSummary)
```

If you ever need to construct a `FlexiChain` from scratch, there are exactly three ways to do so:

  - with an *array of dictionaries*, i.e., one dictionary per iteration;
  - with a *dictionary of arrays*, i.e., the values for each key are already grouped together;
  - from a 3D array of `iters x chains x params` (see the [converting from 3D arrays page](@ref api-fromarray) for discussion of this).

```@docs
FlexiChains.FlexiChain{TKey}(niters::Int, nchains::Int, array_of_dicts::AbstractArray{<:AbstractDict}) where TKey
FlexiChains.FlexiChain{TKey}(niters::Int, nchains::Int, dict_of_arrays::AbstractDict{<:Any,<:AbstractArray{<:Any,N}}) where {TKey,N}
```

Note that, although the dictionaries themselves may have loose types, the key type of the `FlexiChain` must be specified (and the keys of the dictionaries will be checked against this).

`FlexiSummary` objects should always be constructed by summarising a `FlexiChain`.
If for some reason you need to construct one from scratch, please refer to the source code (and do let me know, so that I can make this part of the public API).

To demonstrate some of FlexiChains's functionality, the docs use this:

```@docs
FlexiChains.EXAMPLE_CHAIN
```

## Parameters and Extras

```@docs
FlexiChains.Parameter
FlexiChains.Extra
FlexiChains.ParameterOrExtra
FlexiChains.get_name
```

## Equality

```@docs
Base.:(==)(::FlexiChains.FlexiChain, ::FlexiChains.FlexiChain)
Base.isequal(::FlexiChains.FlexiChain, ::FlexiChains.FlexiChain)
FlexiChains.has_same_data(::FlexiChains.FlexiChain, ::FlexiChains.FlexiChain)
```

## Sizes

```@docs
Base.size(::FlexiChains.FlexiChain)
Base.size(::FlexiChains.FlexiSummary)
FlexiChains.niters
FlexiChains.nchains
FlexiChains.nstats
```

## Indices

```@docs
FlexiChains.iter_indices
FlexiChains.chain_indices
FlexiChains.stat_indices
FlexiChains.renumber_iters
FlexiChains.renumber_chains
```

## Key types

```@docs
FlexiChains.Prefixed
```

## Accessing key-value pairs

```@docs
Base.keys(::FlexiChains.ChainOrSummary)
Base.haskey(::FlexiChains.ChainOrSummary{TKey}, key::TKey) where {TKey}
Base.haskey(::FlexiChains.ChainOrSummary{TKey}, key::FlexiChains.ParameterOrExtra{<:TKey}) where TKey
FlexiChains.parameters(::FlexiChains.ChainOrSummary)
FlexiChains.extras(::FlexiChains.ChainOrSummary)
Base.values(::FlexiChains.ChainOrSummary)
Base.pairs(::FlexiChains.ChainOrSummary)
```

## Indexing by key

For the public interface of `getindex`, please see [the Indexing page](@ref indexing).

## Accessing metadata

Chains additionally store some metadata:

```@docs
FlexiChains.sampling_time
FlexiChains.last_sampler_state
```

## Combining chains

```@docs
Base.vcat(::FlexiChains.FlexiChain{T}, ::FlexiChains.FlexiChain{T}) where {T}
Base.hcat(::FlexiChains.FlexiChain{T}, ::FlexiChains.FlexiChain{T}) where {T}
Base.merge(::FlexiChains.FlexiChain{T}, ::FlexiChains.FlexiChain{T}) where {T}
```

## Subsetting chains

You can do these with `getindex` too, but these functions are sometimes more convenient.

```@docs
FlexiChains.subset_parameters
FlexiChains.subset_extras
```

## Converting to flattened arrays

Please see the [converting to/from arrays page](@ref arrays).

## Extracting per-iteration samples

Please see the [samples page](./samples.md).

## Integration with Turing.jl

!!! warning

    Note that if you are using Turing.jl with FlexiChains you almost certainly want to read [the docs for v0.6](https://juliabayes.org/FlexiChains.jl/v0.6).

```@docs
DynamicPPL.logprior
DynamicPPL.loglikelihood
DynamicPPL.logjoint
DynamicPPL.returned
DynamicPPL.predict
DynamicPPL.pointwise_logdensities
DynamicPPL.pointwise_loglikelihoods
DynamicPPL.pointwise_prior_logdensities
DynamicPPL.InitFromParams
AbstractMCMC.from_samples
AbstractMCMC.to_samples
```

## Summaries

The summaries interface is documented on the [summarising page](./summarising.md).

## Plotting

The plotting interface is documented on the [plotting pages](./plotting.md).
