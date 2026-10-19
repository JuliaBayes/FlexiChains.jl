# Overview

FlexiChains.jl provides a rich data structure for storing and analysing Markov chain Monte Carlo (MCMC) output.

For example, this is a chain obtained by sampling from the classic eight-schools model (with centred parameterisation) using the NUTS algorithm.

```@example splash
using FlexiChains

chain = FlexiChains.EXAMPLE_CHAIN
```

This model might be expressed in pseudocode as follows:

```julia
y = [28, 8, -3, 7, -1, 1, 18, 12]
sigma = [15, 10, 16, 11, 9, 11, 10, 18]

mu ~ Normal(0, 5)
tau ~ HalfCauchy(0, 5)
theta ~ MvNormal(fill(mu, 8), tau^2 * I)
y ~ MvNormal(theta, sigma^2 * I)
```

## Primary features

### Type and structure fidelity

FlexiChains preserves the original shapes of your samples: all Julia types are faithfully stored without modification.
The example chain above has `mu` and `tau` as ordinary `Float64`s.
More interestingly, though, `theta` is stored as a `Vector{Float64}` of length 8; and the extra statistic `is_divergent` is stored as a `Bool`.

This approach avoids flatten all samples into a single `Array{Float64}`, which not only causes `is_divergent` to be promoted unnecessarily, but also causes `theta` to be split up into separate variables.

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
chain[@vn(tau), iter=101:End, chain=2]
```

You can also access sub-components of variables using [`VarName`s](https://juliabayes.org/VarNames.jl):

```@example splash
chain[@vn(theta[2])] # Only get the second element of theta.
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
ss[@vn(mu), stat=:mean]
```

For added versatility you can also [convert a FlexiChain into a `DimArray` or a `DataFrame`](@ref arrays).

### Plotting

Many visualisation functions with both [Makie.jl](@ref plotting-makie) and [Plots.jl](@ref plotting-plots) backends are provided, along with [a PairPlots.jl extension](@ref integrations-pairplots).

```@example splash
using CairoMakie
using FlexiChains.Makie: traceplot

# Restrict variables plotted for this example.
vns = [@vn(mu), @vn(tau), @vn(theta[1]), @vn(theta[2])]

traceplot(chain, vns)
Makie.save("index-plot.png", ans); # hide
```

![Trace plot of the sampled chain](index-plot.png)
