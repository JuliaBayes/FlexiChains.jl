# Overview

FlexiChains.jl provides a rich data structure for storing and analysing Markov chain Monte Carlo (MCMC) output.

```julia
using Turing, FlexiChains
@model function f()
    x ~ Normal()
    y ~ Poisson(3.0)
    z ~ MvNormal([x + y, x - y], I)
end
chain = sample(f(), Prior(), MCMCSerial(), 1000, 4)
```

```@example splash
# Avoid actually sampling with Turing! # hide
using DynamicPPL, Distributions, LinearAlgebra # hide
using FlexiChains # hide
@model function f() # hide
    x ~ Normal() # hide
    y ~ Poisson(3.0) # hide
    z ~ MvNormal([x + y, x - y], I) # hide
end # hide
chain = FlexiChains._make_prior_chain(f(), 1000, 4) # hide
```

## Primary features

### Type and structure fidelity

FlexiChains preserves the original shapes of your samples: all Julia types are faithfully stored without modification.
The example Turing.jl model above yields a `FlexiChain` where each `x` is a Float64, each `y` is an Int, and each `z` is a `Vector{Float64}`.

This is in contrast to many other representations which flatten all samples into a single `Array{Float64}`.

### Diverse input sources

FlexiChains is the default chain type for [Turing.jl](@ref integrations-turing).
Note that if you are using Turing with FlexiChains, you probably want to look at [the FlexiChains v0.6 docs](https://juliabayes.github.io/FlexiChains.jl/v0.6/) instead, since Turing is using that version.

You can also construct a FlexiChain from a variety of other sources, including
[ParallelMCMC.jl](@ref integrations-parallelmcmc),
[Pigeons.jl](@ref integrations-pigeons),
[Stan CSV files](@ref integrations-stan),
[MCMCChains.jl](@ref integrations-mcmcchains),
or [PosteriorDB.jl](@ref integrations-posteriordb).

### Expressive indexing

You can [access data stored in chains](@ref indexing) in a variety of ways, using the full power of DimensionalData.jl selectors.

```@example splash
chain[@varname(x), iter=101:End, chain=2]
```

### Downstream analysis

FlexiChains provides a number of tools for statistical analysis, including:

  - [simple statistics](@ref summarising) (mean, variance, quantiles, etc.)
  - [MCMC diagnostics and statistics](@ref mcmc-diagnostics) via MCMCDiagnosticTools.jl and PosteriorStats.jl
  - [LOO-CV](@ref integrations-posteriorstats) via PosteriorStats.jl and PSIS.jl

```@example splash
ss = summarystats(chain)
```

```@example splash
ss[@varname(x), stat=:mean]
```

For added versatility you can also [convert a FlexiChain into a `DimArray` or a `DataFrame`](@ref api-flatten).

### Plotting

Many visualisation functions with both [Makie.jl](@ref plotting-makie) and [Plots.jl](@ref plotting-plots) backends are provided, along with [a PairPlots.jl extension](@ref integrations-pairplots).

```@example splash
using PairPlots, CairoMakie
pairplot(chain)
Makie.save("index-pairplot.png", ans); # hide
```

![Pair plot of the sampled chain](index-pairplot.png)
