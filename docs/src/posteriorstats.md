# [PosteriorStats.jl](@id integrations-posteriorstats)

[Documentation for PosteriorStats.jl ↗](@extref PosteriorStats :doc:`index`)

## Interval estimation

PosteriorStats.jl provides the `hdi` and `eti` functions for computing highest density
intervals and equal-tailed intervals, respectively.
These are overloaded for `FlexiChain` objects in much the same way as `Statistics.mean`, `Statistics.std`, etc. (see [the Summarising page](@ref "Individual statistics") for more information on those).
Here is an example:

```@example posteriorstats
using FlexiChains, PosteriorStats

chn = FlexiChains.EXAMPLE_CHAIN
PosteriorStats.hdi(chn; prob=0.95)
```

By default, each interval is split into its lower and upper bounds, which are stored as separate statistics (`hdi_lower` and `hdi_upper`, or `eti_lower` and `eti_upper`).
If you would rather have a single statistic containing `IntervalSets.ClosedInterval`s, pass `split_interval=false`:

```@example posteriorstats
PosteriorStats.hdi(chn; prob=0.95, split_interval=false)
```

## LOO-CV

`PosteriorStats.loo`, which computes Pareto-smoothed importance sampling leave-one-out cross-validation (PSIS-LOO), is also overloaded for `FlexiChain` objects.

To make use of this, you will need to have a chain that contains log-likelihood values.
Specifically, instead of mapping `VarName`s to posterior samples, you will need to map them to log-likelihood values for each observation in your dataset.
For example, if you have `x ~ Normal()` and `chn[@vn(x)]` contains the posterior samples for `x`, you will need to make a new chain `llike_chn` for which `llike_chn[@vn(x)] = logpdf.(Normal(), chn[@vn(x)])`.

If you have a Turing model, this functionality is made much easier by the `DynamicPPL.pointwise_loglikelihoods` function.
However, you almost certainly want to look at [the corresponding documentation page for FlexiChains v0.6](https://juliabayes.org/FlexiChains.jl/v0.6/posteriorstats), since Turing currently depends only on v0.6.

## Docstrings

```@docs
PosteriorStats.hdi(::FlexiChains.FlexiChain; kwargs...)
PosteriorStats.eti(::FlexiChains.FlexiChain; kwargs...)
PosteriorStats.loo(::FlexiChains.FlexiChain; kwargs...)
PosteriorStats.loo(model::DynamicPPL.Model, posterior_chn::FlexiChains.FlexiChain; kwargs...)
```
