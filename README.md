<div align="center">
  <img src="docs/src/assets/logo.svg" alt="FlexiChains.jl logo" width="230">
  <h1>FlexiChains.jl</h1>
  <p>Type- and structure-preserving Markov chains.</p>
  <p><a href="https://juliabayes.org/FlexiChains.jl/stable"><b>Documentation</b></a></p>
</div>

> [!NOTE]
>
> **Issues and requests for new functionality are more than welcome!**
> Please don't hesitate to [open an issue](https://github.com/JuliaBayes/FlexiChains.jl/issues) if you have any questions or suggestions.
>
> In particular, I'm very interested in integrating FlexiChains with other packages, which can either be input sources (i.e., packages that generate MCMC samples) or output sinks (i.e., visualisation or analysis packages).
> This allows improvements to be shared across the entire ecosystem.
> If you know of a package that would benefit from FlexiChains integration, do get in touch!

# Quickstart

## Installation

```julia
import Pkg
Pkg.add("FlexiChains")
```

## Obtaining a chain

MCMC sampling with [Wren.jl](https://juliabayes.org/Wren.jl) or [ParallelMCMC.jl](https://github.com/rsenne/ParallelMCMC.jl) returns a FlexiChain by default:

```julia
using Wren, Distributions
@wren function f()
    x ~ Normal()
    y ~ Poisson(3.0)
    z ~ MvNormal(zeros(2), I)
end
model = f()
chain = prior(model, 1000, 3)
```

```
╭─FlexiChain (1000 iterations, 3 chains) ────────────────────────────────────╮
│ ↓ iter  = 1:1000                                                           │
│ → chain = 1:3                                                              │
│                                                                            │
│ Parameters (3) ── VarName                                                  │
│  Float64          x                                                        │
│  Int64            y                                                        │
│  Vector{Float64}  z (2,)                                                   │
│                                                                            │
│ Extras (4)                                                                 │
│  Vector{Float64}  return_value (2,)                                        │
│  Float64          logprior, loglikelihood, logjoint                        │
╰────────────────────────────────────────────────────────────────────────────╯
```

You can also construct a FlexiChain from a variety of other sources, including
[Pigeons.jl](https://juliabayes.org/FlexiChains.jl/stable/integrations/#integrations-pigeons),
[Stan CSV files](https://juliabayes.org/FlexiChains.jl/stable/integrations/#integrations-stan),
[PosteriorDB.jl](https://juliabayes.org/FlexiChains.jl/stable/integrations/#integrations-posteriordb), or
an [`MCMCChains.Chains` object](https://juliabayes.org/FlexiChains.jl/stable/integrations/#integrations-mcmcchains).

[Turing.jl](https://turinglang.org) also uses FlexiChains as its default chain type, but is currently using an older version of FlexiChains (v0.6).
Please see [the documentation for that version](https://juliabayes.org/FlexiChains.jl/v0.6/) if you are using Turing.jl!

## A quick primer on the data structure

A `FlexiChain{T}` stores data for *parameters* of type `T`, along with *extras* of any type which represent per-iteration metadata such as log densities.

Broadly speaking, a `FlexiChain` can be thought of as a dictionary mapping `Union{Parameter{<:T},Extra}` to `niters x nchains` matrices of samples.
Each matrix can have a different element type, which allows FlexiChains to store samples as their original types (e.g. Int or Vector) rather than flattening and converting everything to Float64.

We strongly recommend using [`VarNames.VarName`](https://juliabayes.org/VarNames.jl/stable/) as the key type for parameters, because it allows for powerful indexing and subsetting of parameters.
`FlexiChain{VarName}` is aliased to `VNChain`; you will see this type used throughout the documentation.
When implementing new features we will prioritise making them work for `VarName` keys.
Although `Symbol` keys also work and can be more familiar, `VarName` is almost strictly better than `Symbol` and should be preferred in most cases.

## Indexing

Indexing into a `FlexiChain` returns a `DimMatrix` from the [`DimensionalData.jl` package](https://rafaqz.github.io/DimensionalData.jl/), which behaves exactly like an ordinary `Matrix` but additionally carries more information about its dimensions.

```julia
chain[@vn(x)]              # -> (niters x nchains)     DimMatrix{Float64}
chain[@vn(y)]              # -> (niters x nchains)     DimMatrix{Int}
chain[@vn(z)]              # -> (niters x nchains)     DimMatrix{Vector{Float64}}
chain[@vn(z), stack=true]  # -> (niters x nchains x 2) DimArray{Float64} 
```

If you have a `VNChain`, you can access sub-components of parameters by specifying the appropriate `VarName`.
Here `z` is a 2-dimensional vector, so accessing either `z[1]` or `z[2]` gives us scalars:

```julia
chain[@vn(z[1])]  # -> (niters x nchains) DimMatrix{Float64}
```

You can index with `Symbol`s, as long as it can be unambiguously resolved to a parameter or extra:

```julia
chain[:y]         # -> (niters x nchains) DimMatrix{Int}
chain[:logjoint]  # -> (niters x nchains) DimMatrix{Float64}
```

You can additionally subset iterations / chains using `iter` or `chain` keyword arguments:

```julia
chain[@vn(x), iter=101:End, chain=2]
```

(note that with keyword arguments you have to use `End` instead of `end`).

See the [full guide to indexing](https://juliabayes.org/FlexiChains.jl/stable/indexing) for more.

## Statistics

Quick and dirty summary stats can be obtained with:

```julia
ss = summarystats(chain)
```

This produces a `FlexiSummary` object with mean, standard deviation, Monte Carlo standard error, effective sample size, R-hat, and quantiles for each key:

```
╭─FlexiSummary (9 statistics) ────────────────────────────────────────────────────╮
│   iter    collapsed                                                             │
│   chain   collapsed                                                             │
│ ↓ stat  = [mean, std, mcse, ess_bulk, ess_tail, rhat, q5, q50, q95]             │
│                                                                                 │
│ Parameters (4) ── VarName                                                       │
│  Float64  x, y, z[1], z[2]                                                      │
│                                                                                 │
│ Extras (4)                                                                      │
│  Union{Missing, Vector{Float64}}  return_value                                  │
│  Float64                          logprior, loglikelihood, logjoint             │
│                                                                                 │
│ Summary                                                                         │
│  param  mean    std     mcse    …  rhat    q5       q50     q95                 │
│  x      0.0156  1.0015  0.0181     1.0005  -1.6250  0.0155  1.6776              │
│  y      2.9550  1.7002  0.0315     0.9997  0.0000   3.0000  6.0000              │
│  z[1]   0.0058  0.9913  0.0171     1.0004  -1.6178  0.0259  1.5754              │
│  z[2]   0.0292  1.0125  0.0183     1.0003  -1.6193  0.0162  1.7494              │
╰─────────────────────────────────────────────────────────────────────────────────╯
```

You can index into this much like a `FlexiChain`:

```julia
ss[@vn(x), stat=:mean]  # mean of `x`
```

Or you can compute statistics directly with individual functions:

```julia
mean(chain)              # just the mean for all variables
mean(chain)[@vn(x)]      # -> Float64
mean(chain; dims=:iter)  # take the mean over iterations only
```

See the [full guide to summarising](https://juliabayes.org/FlexiChains.jl/stable/summarising) for more.

## Plotting

FlexiChains contains extensive functionality for visualising chains with [Makie.jl](https://docs.makie.org/stable/) and [Plots.jl](https://docs.juliaplots.org/stable/).
Most of the effort has been focused on the Makie backend, and we recommend using this first.

```julia
using CairoMakie
plot(chain)                    # trace + densities for all parameters
plot(chain; pool_chains=true)  # combine samples from all chains
plot(chain, [@vn(z)])          # z[1] and z[2] only
```

<div align="center">
<img src="https://raw.githubusercontent.com/JuliaBayes/FlexiChains.jl/refs/heads/readme-images/readme-default-plot.png" width="500" alt="Trace/density plot of z in the FlexiChain sampled above"></img>
</div>

Specialised MCMC plots are namespaced under the `FlexiChains.Makie` module:

```julia
import FlexiChains.Makie as FM
FM.meanplot(chain; layout=(2, 2)) # Running mean plot, with custom grid layout
```

<div align="center">
<img src="https://raw.githubusercontent.com/JuliaBayes/FlexiChains.jl/refs/heads/readme-images/readme-meanplot.png" width="500" alt="Running mean plot of the FlexiChain sampled above"></img>
</div>

Pair plots can be generated with the [PairPlots.jl extension](https://juliabayes.org/FlexiChains.jl/stable/integrations/#integrations-pairplots):

```julia
using PairPlots
pairplot(chain)
```

<div align="center">
<img src="https://raw.githubusercontent.com/JuliaBayes/FlexiChains.jl/refs/heads/readme-images/readme-pairplot.png" width="500" alt="Pair plot of the FlexiChain sampled above"></img>
</div>

The interface to Plots.jl is similar:

```julia
using StatsPlots
plot(chain)

import FlexiChains.Plots as FP
FP.meanplot(chain; layout=(2, 2))

StatsPlots.corner(chain)
```

See the [full guide to plotting](https://juliabayes.org/FlexiChains.jl/stable/plotting) for more.
