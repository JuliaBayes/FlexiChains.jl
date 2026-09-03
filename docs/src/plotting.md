# [Plotting overview](@id plotting)

FlexiChains contains a number of functions for visualising chains with [Makie.jl](@ref plotting-makie) and [Plots.jl](@ref plotting-plots).

The Makie backend is more developed, and we recommend using that in the first instance.

FlexiChains can also be used with [AlgebraOfGraphics.jl](@ref plotting-aog) via the [Tables.jl interface](@ref integrations-tables).

## Available functions

Here is an overview of what is currently available:

| Type of plot                       | Makie.jl                                                                                                                                                 | Plots.jl                                   |
|:---------------------------------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------ |
| Trace + mixed density (default)    | ✅ [`Makie.plot`](@ref)                                                                                                                                   | ✅ [`Plots.plot`](@ref)                     |
| Trace plots                        | ✅ [`FlexiChains.Makie.traceplot`](@ref)                                                                                                                  | ✅ [`FlexiChains.Plots.traceplot`](@ref)    |
| Density plots                      | ✅ [`Makie.density`](@ref)                                                                                                                                | ✅ [`Plots.density`](@ref)                  |
| Histograms                         | ✅ [`Makie.hist`](@ref) and [`Makie.stephist`](@ref)                                                                                                      | ✅ [`Plots.histogram`](@ref)                |
| Mixed density plots                | ✅ [`FlexiChains.Makie.mixeddensity`](@ref)                                                                                                               | ✅ [`FlexiChains.Plots.mixeddensity`](@ref) |
| Running mean plots                 | ✅ [`FlexiChains.Makie.meanplot`](@ref)                                                                                                                   | ✅ [`FlexiChains.Plots.meanplot`](@ref)     |
| Autocorrelation plots              | ✅ [`FlexiChains.Makie.autocorplot`](@ref)                                                                                                                | ✅ [`FlexiChains.Plots.autocorplot`](@ref)  |
| Rank plots                         | ✅ [`FlexiChains.Makie.rankplot`](@ref)                                                                                                                   | ✅ [`FlexiChains.Plots.rankplot`](@ref)     |
| Corner plots                       | ✅ [`PairPlots.pairplot`](@ref)                                                                                                                           | ✅ [`StatsPlots.cornerplot`](@ref)          |
| Violin plots                       | ✅ [`Makie.violin`](@ref)                                                                                                                                 | ✅ [`StatsPlots.violin`](@ref)              |
| Energy plots                       | 🐌                                                                                                                                                        | 🐌                                          |
| Forest plots                       | ✅ [`FlexiChains.Makie.forestplot`](@ref)                                                                                                                 | 🐌                                          |
| Ridgeline plots                    | ✅ [`FlexiChains.Makie.ridgeline`](@ref)                                                                                                                  | 🐌                                          |
| Dot plots                          | ✅ [`FlexiChains.Makie.dotplot`](@ref) (needs SwarmMakie.jl)                                                                                              | 🐌                                          |
| [Pushforward plots](@ref pf-plots) | ✅ [`FlexiChains.Makie.pushforward_continuous`](@ref), [`FlexiChains.Makie.pushforward_discrete`](@ref), and [`FlexiChains.Makie.pushforward_hist`](@ref) | 🐌                                          |

All of the above functions have 'mutating' versions with a `!` suffix.

Notice that FlexiChains provides separate functions for Plots.jl and Makie.jl backends, which are namespaced within the `FlexiChains.Plots` and `FlexiChains.Makie` modules, respectively.
This is necessary for disambiguation, much like how `Plots.plot()` and `Makie.plot()` are different functions.

## Compositionality

In general, the plotting interfaces in FlexiChains try to stay as close as possible to the way the original plotting libraries work.
That means that you should be able to construct your own plots, insert a FlexiChains plot into a larger figure, and so on, using the interface provided by the original plotting library.

For example, with Makie you can do something like:

```julia
# Set up a Makie figure
f = Makie.Figure()
# These functions provided / extended by FlexiChains
FlexiChains.Makie.traceplot!(f[1, 1], chn, param1)
Makie.density!(f[1, 2], chn, param2)
# This is some completely external Makie.jl plot
Makie.plot!(f[1, 3], randn(10, 10))
# Show the figure
f
```

And with Plots.jl you can do:

```julia
# These functions provided / extended by FlexiChains
p1 = FlexiChains.Plots.traceplot(chn, param1)
p2 = Plots.density(chn, param2)
# This is some completely external Plots.jl plot
p3 = Plots.plot(randn(10, 10))
# Compose them with Plots.jl
plot([p1, p2, p3], layout=(3, 1))
```
