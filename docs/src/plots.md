# [Plots.jl](@id plotting-plots)

[Documentation for Plots.jl ↗](@extref Plots :doc:`index`)

FlexiChains defines a collection of plot recipes which allows you to use the Plots.jl ecosystem to visualise chains.
In particular, to access these you will want to load StatsPlots.jl:

```julia
using StatsPlots
```

## Plot types

What kind of plot you get in when using Plots.jl is controlled *mainly* by the `seriestype` keyword argument.
For example, `plot(..., seriestype=:histogram)` will produce a histogram.
In fact, calling `histogram(...)` simply redirects to `plot(..., seriestype=:histogram)`.

The following series types are supported for `FlexiChain` objects.

| `seriestype=`            | Equivalent function                                       | Description                                                                             |
|:------------------------ |:--------------------------------------------------------- |:--------------------------------------------------------------------------------------- |
| `:traceplot`             | [`FlexiChains.Plots.traceplot`](@ref)                     | Trace plot of samples                                                                   |
| `:histogram`             | [`Plots.histogram`](@ref plots-histogram)                 | Histogram of samples                                                                    |
| `:density`               | [`Plots.density`](@ref plots-density)                     | Kernel density estimate of samples                                                      |
| `:mixeddensity`          | [`FlexiChains.Plots.mixeddensity`](@ref)                  | Density plot or histogram, depending on whether the parameter is continuous or discrete |
| `:meanplot`              | [`FlexiChains.Plots.meanplot`](@ref)                      | Running mean of samples                                                                 |
| `:autocorplot`           | [`FlexiChains.Plots.autocorplot`](@ref)                   | Autocorrelation of samples                                                              |
| `:traceplot_and_density` | [`Plots.plot`](@ref) (with no `seriestype` argument)      | Trace plot and mixed density side-by-side                                               |
| `:rankplot`              | [`FlexiChains.Plots.rankplot`](@ref) with `overlay=false` | Rank plot with separate histograms per chain                                            |
| `:rankplot_overlay`      | [`FlexiChains.Plots.rankplot`](@ref) with `overlay=true`  | Rank plot with all chains' data overlaid                                                |

There is currently one exception to this: `StatsPlots.cornerplot` is manually overloaded because it does not use the usual `seriestype` mechanism.

!!! warning "Identifier conflicts"

    Please note that the identifiers `traceplot`, `meanplot`, `mixeddensity`, and `autocorplot` are also exported by MCMCChains.jl (which uses Plots.jl as its backend), as well as the `FlexiChains.Makie` submodule. If you have imported more than one of these modules, you will need to disambiguate which function you want to use by prefixing it with the module name, e.g. `FlexiChains.Plots.traceplot`.

## General interface

The above plotting functions should be called with the following signature:

```julia
plotfunc(chn, param_or_params; pool_chains::Bool=false, kwargs...)
```

**Positional arguments**

  - `chn` is a `FlexiChain` object.
  - `param_or_params` is optional, and can be [anything that is used to index into a chain](@ref indexing). If not provided, all parameters in the chain will be plotted.

**Keyword arguments**

  - If `pool_chains=true`, then samples from all chains are concatenated before plotting densities or histograms.
    Otherwise, each chain is plotted separately.

  - Some plotting functions like `autocorplot` and `rankplot` have additional keyword arguments which control the details of the plot; please see the docstrings for those functions for more details.

  - Other keyword arguments are passed through to the underlying Plots.jl functions which allow you to, for example, control the appearance of the plot.

## Setup

Here, we demonstrate the plotting features with a typical chain sampled from a Turing model.
However, the general principles are applicable to any `FlexiChain` object.

We'll make a model with different types of parameters (continuous, discrete, and vector-valued).

```@example plotsjl
using FlexiChains, StatsPlots, Distributions, LinearAlgebra
using DynamicPPL: @model

import FlexiChains.Plots as FP # For the plotting functions.

@model function f()
    x ~ Normal()
    y ~ Poisson(3)
    z ~ MvNormal(zeros(2), I)
end

chn = FlexiChains._make_prior_chain(f(), 1000, 3)
```

## Default plot

Calling `plot(chn)` produces a trace plot and mixed density side-by-side for each parameter.

Notice that the chain has not split `z` up into `z[1]` and `z[2]`.
However, when plotting, it will be automatically split up for you.
Also notice that `Extra` keys, like the log probabilities, are not plotted by default.

```@docs
Plots.plot
```

```@example plotsjl
plot(chn)
savefig("plot1.svg");
nothing # hide
```

![Trace and density plots of the sampled chain](plot1.svg)

If you want to plot specific parameter(s), you can specify them as the second positional argument.
In general, the second argument can be _anything_ that you can index into a chain with.
This means a symbol, a parameter, a `FlexiChains.Extra`, a sub-VarName, or a vector thereof:

```@example plotsjl
plot(chn, [@varname(x), :logjoint])
savefig("plot2.svg");
nothing # hide
```

![Trace and density plots of x and the logjoint](plot2.svg)

## Trace plots

```@docs
FlexiChains.Plots.traceplot
FlexiChains.Plots.traceplot!
```

```@example plotsjl
FP.traceplot(chn)
savefig("traceplot.svg");
nothing # hide
```

![Trace plots of the sampled chain](traceplot.svg)

## [Density plots](@id plots-density)

Density plots are produced using the standard `Plots.density` function, which works with `FlexiChain` objects.

```@docs
Plots.density
```

```@example plotsjl
density(chn)
savefig("density.svg");
nothing # hide
```

![Density plots of the sampled chain](density.svg)

## [Histograms](@id plots-histogram)

Similarly, `Plots.histogram` works with `FlexiChain` objects:

```@docs
Plots.histogram
```

```@example plotsjl
histogram(chn)
savefig("histogram.svg");
nothing # hide
```

![Histograms of the sampled chain](histogram.svg)

## Running mean plots

```@docs
FlexiChains.Plots.meanplot
FlexiChains.Plots.meanplot!
```

```@example plotsjl
FP.meanplot(chn)
savefig("meanplot.svg");
nothing # hide
```

![Running mean plots of the sampled chain](meanplot.svg)

## Rank plots

```@docs
FlexiChains.Plots.rankplot
FlexiChains.Plots.rankplot!
```

```@example plotsjl
FP.rankplot(chn)
savefig("rankplot.svg");
nothing # hide
```

![Rank plots of the sampled chain](rankplot.svg)

## Autocorrelation plots

```@docs
FlexiChains.Plots.autocorplot
FlexiChains.Plots.autocorplot!
```

```@example plotsjl
FP.autocorplot(chn)
savefig("autocorplot.svg");
nothing # hide
```

![Autocorrelation plots of the sampled chain](autocorplot.svg)

## Mixed density plots

```@docs
FlexiChains.Plots.mixeddensity
FlexiChains.Plots.mixeddensity!
```

```@example plotsjl
FP.mixeddensity(chn)
savefig("mixeddensity.svg");
nothing # hide
```

![Mixed density plots of the sampled chain](mixeddensity.svg)

## Corner plots

```@docs
StatsPlots.cornerplot
```

```@example plotsjl
StatsPlots.cornerplot(chn)
savefig("cornerplot.svg");
nothing # hide
```

![Corner plot of the sampled chain](cornerplot.svg)

## Violin plots

```@docs
Plots.violin
```

```@example plotsjl
Plots.violin(chn)
savefig("violin.svg");
nothing # hide
```

![Violin plots of the sampled chain](violin.svg)
