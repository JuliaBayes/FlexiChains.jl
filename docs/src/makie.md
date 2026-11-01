# [Makie.jl](@id plotting-makie)

[Documentation for Makie.jl ↗](https://docs.makie.org/stable/)

FlexiChains provides a number of functions to visualise chains using the Makie plotting library.

Parts of the Makie integration in FlexiChains are heavily lifted from [the (unreleased) ChainsMakie.jl package](https://simonsteiger.github.io/ChainsMakie.jl/dev/) (there have also been many further additions since then!).
This includes some custom code to generate (e.g.) shared legends, which leads to slightly nicer plots than for Plots.jl (on top of Makie generally yielding nicer plots out of the box).

!!! note

    You can also use Makie as a backend to make pair / corner plots!
    This requires loading a Makie backend as well as PairPlots.jl.
    Please see the [PairPlots.jl integration section](@ref integrations-pairplots) for more details.

## [General interface](@id makie-interface)

For all functions `plotfunc` shown in the table of [the plotting page](./plotting.md), you can use the following invocation:

 1. Generate an entire `Makie.Figure`. This automatically generates a complete plot for you, including a legend.

    ```julia
    plotfunc(
        chn,
        param_or_params;
        figure=(;),
        axis=(;),
        legend=(;),
        legend_position=:bottom,
        kwargs...,
    )
    ```

    `param_or_params` can be anything used to index into a chain (single parameters are also accepted).
    It can also be omitted, in which case all parameters in the chain will be plotted.

    Most keyword arguments are passed to the underlying Makie plotting functions, but there are some special ones which are handled by FlexiChains.
    For more information about these, see the [customisation section below](@ref makie-customisation).

For functions which create only a single plot per parameter (e.g. `density`, or `traceplot`), the following options are also available.
The intention is to allow you to build more complex figures using these as building blocks:

 2. Plot a single parameter onto an existing `Makie.Axis` object: this uses the 'mutating' version with an exclamation mark.

    If `ax` is not specified, uses the current axis. Colours are handled the same way as above. `param` must be a single parameter.

    ```julia
    plotfunc!([ax]chn, param; kwargs...)
    ```

 3. Plot a single parameter onto a Makie grid position. This constructs a `Makie.Axis` for you, and as before you can pass options via the `axis` keyword argument. Colours are handled the same way as above. `param` must be a single parameter.

    ```julia
    f = Figure()
    gp = f[1, 1]
    plotfunc!(gp, chn, param; axis=(;), kwargs...)
    ```

## Setup

Here, we set up a chain with different types of parameters (continuous, discrete, and vector-valued).
We could use the familiar example chain from the other docs pages, but that one is too small to demonstrate some of these plots well.

```@example 1
using FlexiChains, CairoMakie
import FlexiChains.Makie as FM  # For the plotting functions.

using FlexiChains: FlexiChain, Parameter, Extra, OrderedDict
chn = FlexiChain{VarName}(
    500,
    2,
    OrderedDict(
        Parameter(@vn(float)) => randn(500, 2),
        Parameter(@vn(int)) => rand(1:5, 500, 2) .* 3 .+ 2,
        Parameter(@vn(vect)) => [[randn(), randn() - 1.0] for _ in 1:500, _ in 1:2],
        Extra(:an_extra) => randn(500, 2),
    ),
)
```

## Default plot

Calling `Makie.plot(chn)` produces a trace plot and mixed density side-by-side for each parameter.

```@docs
Makie.plot
```

```@example 1
Makie.plot(chn)
Makie.save("plot_makie.png", ans.figure); # hide
```

![Default trace and density plots of the sampled chain](plot_makie.png)

## Trace plots

```@docs
FlexiChains.Makie.traceplot
FlexiChains.Makie.traceplot!
```

```@example 1
FM.traceplot(chn)
Makie.save("traceplot_makie.png", ans.figure); # hide
```

![Trace plots of the sampled chain](traceplot_makie.png)

## Density plots

```@docs
Makie.density
```

```@example 1
Makie.density(chn)
Makie.save("density_makie.png", ans.figure); # hide
```

![Density plots of the sampled chain](density_makie.png)

## Histograms

```@docs
Makie.hist
Makie.stephist
```

```@example 1
Makie.hist(chn)
Makie.save("hist_makie.png", ans.figure); # hide
```

![Histograms of the sampled chain](hist_makie.png)

## Mixed density plots

```@docs
FlexiChains.Makie.mixeddensity
FlexiChains.Makie.mixeddensity!
```

```@example 1
FM.mixeddensity(chn)
Makie.save("mixeddensity_makie.png", ans.figure); # hide
```

![Mixed density plots of the sampled chain](mixeddensity_makie.png)

## Running mean plots

```@docs
FlexiChains.Makie.meanplot
FlexiChains.Makie.meanplot!
```

```@example 1
FM.meanplot(chn)
Makie.save("meanplot_makie.png", ans.figure); # hide
```

![Running mean plots of the sampled chain](meanplot_makie.png)

## Autocorrelation plots

```@docs
FlexiChains.Makie.autocorplot
FlexiChains.Makie.autocorplot!
```

```@example 1
FM.autocorplot(chn)
Makie.save("autocorplot_makie.png", ans.figure); # hide
```

![Autocorrelation plots of the sampled chain](autocorplot_makie.png)

## Rank plots

```@docs
FlexiChains.Makie.rankplot
FlexiChains.Makie.rankplot!
```

```@example 1
FM.rankplot(chn)
Makie.save("rankplot_makie.png", ans.figure); # hide
```

![Rank plots of the sampled chain](rankplot_makie.png)

## Violin plots

```@docs
Makie.violin
```

```@example 1
Makie.violin(chn; with_box=true)
Makie.save("violin_makie.png", ans.figure); # hide
```

![Violin plots of the sampled chain](violin_makie.png)

## Forest plots

!!! info "Half-eye plots"

    To get a 'half-eye' look similar to R's `ggdist` package, you can compose `forestplot!` and `ridgeline!`.
    See e.g. the example [here](https://github.com/JuliaBayes/FlexiChains.jl/pull/230).

```@docs
FlexiChains.Makie.forestplot
FlexiChains.Makie.forestplot!
```

```@example 1
FM.forestplot(chn)
Makie.save("forestplot_makie.png", ans.figure); # hide
```

![Forest plots of the sampled chain](forestplot_makie.png)

## Ridgeline plots

!!! info "Half-eye plots"

    To get a 'half-eye' look similar to R's `ggdist` package, you can compose `forestplot!` and `ridgeline!`.
    See e.g. the example [here](https://github.com/JuliaBayes/FlexiChains.jl/pull/230).

```@docs
FlexiChains.Makie.ridgeline
FlexiChains.Makie.ridgeline!
```

```@example 1
FM.ridgeline(chn)
Makie.save("ridgeline_makie.png", ans.figure); # hide
```

![Ridgeline plots of the sampled chain](ridgeline_makie.png)

## [Pushforward plots](@id pf-plots)

These plots are based on Michael Betancourt's [`mcmc_visualization_tools`](https://github.com/betanalpha/mcmc_visualization_tools).
We include a worked example to motivate and demonstrate the use of these plots.

### Example

A *pushforward* distribution is obtained by mapping a function over a distribution: specifically, if some random variable `θ` has distribution `p(θ)`, then the pushforward of `θ` through a function `f` is the distribution of `Y = f(θ)`.

In Bayesian inference, we're often interested in taking posterior draws `θ ~ p(θ | D)` (as represented in a chain) and pushing this through some function `f` to obtain a new distribution.
For example, `f` may be the function which generates posterior predictive draws, in which case the pushforward distribution is the posterior predictive distribution.

Each parameter draw `θ` yields a different draw of `f`, so the spread of `f` inherits posterior uncertainty.
The pushforward plots in this section visualise that uncertainty as nested quantile bands, displayed as either a fitted curve (`pushforward_continuous`), per-group summaries (`pushforward_discrete`), or predictive histograms (`pushforward_hist`).

```@docs
FlexiChains.Makie.pushforward_continuous
FlexiChains.Makie.pushforward_continuous!
FlexiChains.Makie.pushforward_discrete
FlexiChains.Makie.pushforward_discrete!
FlexiChains.Makie.pushforward_hist
FlexiChains.Makie.pushforward_hist!
```

## [Predictive checks](@id ppc-plots)

The plots in this section follow the same idea as the `pushforward` plots above, namely that if our model fits the data well, we should be able to use it to predict new data that look reasonably similarly to those we first observed.

For this example, we simulate predictive draws and observed values from a standard normal distribution.
Each predictive draw contains 30 values.

[`ppc_plot`](@ref FlexiChains.Makie.ppc_plot) plots a density per predictive draw and overlays the density of the observed values.

```@example ppc
using FlexiChains, CairoMakie
using FlexiChains: FlexiChain
using Random: Xoshiro
import FlexiChains.Makie as FM

rng = Xoshiro(1)
ppd = FlexiChain{VarName}(randn(rng, 100, 2, 30), @vn(y))
observed = randn(rng, 30)
FM.ppc_plot(ppd, @vn(y); observed=observed)
```

```@docs
FlexiChains.Makie.ppc_plot
FlexiChains.Makie.ppc_plot!
```

## [Customisation](@id makie-customisation)

As described in the [general interface section above](@ref makie-interface), all of the above functions accept keyword arguments to control the appearance of the plot.

The `figure`, `axis`, and `legend` arguments (which can be, e.g., `NamedTuple`s) allow you to pass extra keyword arguments to the `Figure`, `Axis`, and `Legend` constructors.
Then, most other keyword arguments are forwarded to the underlying Makie plotting functions; please refer to the Makie documentation for more details on these.

Finally, there are also some special keyword arguments which are handled by FlexiChains.
Here are some examples of these in action.

### Custom layout

By default, plots are arranged with one parameter per row.
You can pass a tuple of `(nrows, ncols)` as the `layout` keyword argument to change this:

```@example 1
Makie.density(chn; layout=(2, 2))
Makie.save("custom_layout_makie.png", ans.figure); # hide
```

![Density plots with a 2x2 layout](custom_layout_makie.png)

### Custom colours

Pass a vector of colours (one per chain) via the `color` keyword, or a categorical colormap via `colormap`:

```@example 1
FM.traceplot(
    chn,
    [@vn(float), @vn(int)];
    color=[(:red, 0.6), (:blue, 0.6)],
    # or e.g. colormap=:tab10
)
Makie.save("custom_colors_makie.png", ans.figure); # hide
```

![Trace plots with custom colours](custom_colors_makie.png)

!!! note

    To get the best effects with `colormap`, you should pass a categorical colormap such as `:tab10`.
    Continuous colormaps like `:viridis` will give poor results since it will use the first `n` colours of the colormap, which are all very similar!

### Legend position

Use `legend_position` to move the legend (`:bottom`, `:right`, or `:none`):

```@example 1
FM.traceplot(chn; legend_position=:right)
Makie.save("custom_legend_makie.png", ans.figure); # hide
```

![Trace plots with the legend on the right](custom_legend_makie.png)
