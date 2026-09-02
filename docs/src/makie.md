# [Makie.jl](@id plotting-makie)

[Documentation for Makie.jl ↗](https://docs.makie.org/stable/)

FlexiChains provides a number of functions to visualise chains using the Makie plotting library.

Parts of the Makie integration in FlexiChains are heavily lifted from [the (unreleased) ChainsMakie.jl package](https://simonsteiger.github.io/ChainsMakie.jl/dev/), although there have also been further modifications made since then.
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

Here, we create a model with different types of parameters (continuous, discrete, and vector-valued).
This is the same model as used on the Plots.jl documentation page.

```@example 1
using FlexiChains, CairoMakie, Turing

import FlexiChains.Makie as FM # For the plotting functions.

@model function f()
    x ~ Normal()
    y ~ Poisson(3)
    z ~ MvNormal(zeros(2), I)
end

chn = sample(
    f(),
    MH(),
    MCMCThreads(),
    1000,
    3;
    discard_initial=100,
    chain_type=VNChain,
    progress=false,
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

## Dot plots

Quantile dot plots may make it easier for non-technical audiences to interpret uncertainty (further reading [here](https://idl.uw.edu/papers/when-ish-is-my-bus)).

```@docs
FlexiChains.Makie.dotplot
FlexiChains.Makie.dotplot!
```

```@example 1
FM.dotplot(chn)
Makie.save("dotplot_makie.png", ans.figure); # hide
```

![Dot plots of the sampled chain](dotplot_makie.png)

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

We'll concoct an example with the [Palmer penguins dataset](https://github.com/devmotion/PalmerPenguins.jl) to show how these plots can be used.

```@example pushforward
using Turing, DataFrames, PalmerPenguins, CairoMakie
import FlexiChains.Makie as FM
using StatsBase: denserank, fit, ZScoreTransform, reconstruct

# Load data
penguins = DataFrame(PalmerPenguins.load())

# Drop missing values first (this ensures that standardisation doesn't trip over)
dropmissing!(penguins)

# Fit standardisation transforms so we can unstandardise predictions later
bill_zs = fit(ZScoreTransform, Float64.(penguins.bill_length_mm))
mass_zs = fit(ZScoreTransform, Float64.(penguins.body_mass_g))

# Tidy up the data
standardize(x) = (x .- mean(x)) ./ std(x)
transform!(penguins, names(penguins, Real) .=> standardize => identity)
transform!(penguins, :species => denserank => :species_idx)

# Save the mapping from species index (integer) to species name (string)
species_names = sort(unique(penguins[!, [:species, :species_idx]]), :species_idx).species

# Define a model for penguin bill length as a function of species and body mass
@model function bill_model(species, body_mass)
    n_species = length(unique(species))
    beta1 ~ filldist(Normal(0, 1), n_species)
    beta2 ~ Normal(0, 1)
    beta3 ~ filldist(Normal(0, 1), n_species)
    sigma ~ Exponential(1)
    mu = @. beta1[species] + beta2 * body_mass + beta3[species] * body_mass
    bill_length_mm ~ MvNormal(mu, sigma)
end
nothing # hide
```

We model a penguin's bill length as a function of its species (`beta1`), its body mass (`beta2`), and the interaction between them (`beta3`), i.e., we ask "does the effect of body mass vary by species?".

Next, we condition the model on the observed data and run MCMC.

```@example pushforward
prior_model = bill_model(penguins.species_idx, penguins.body_mass_g)
cond_model = prior_model | (; bill_length_mm=penguins.bill_length_mm)
chain = sample(cond_model, NUTS(0.8), MCMCThreads(), 1000, 4; progress=false)
nothing # hide
```

A common starting point is to plot the posterior predictive distribution (see also [the Turing.jl docs](https://turinglang.org/docs/usage/predictive-distributions/) on this); it can help us (at least superficially) test if the model captured basic patterns in the input data.
We can plot a summary histogram with uncertainty bands using [`pushforward_hist`](@ref FlexiChains.Makie.pushforward_hist).
By specifying the `observed` keyword argument we can also overlay the observed data so that we can visually compare the two distributions.

Before plotting, we can use [`transform_values`](@ref FlexiChains.transform_values) to unstandardise the predictions back to physical units (see [Modifying data](@ref modifying) for more details).

```@example pushforward
# Note that we pass the `prior_model` here, not the conditioned model, so that
# we can sample new draws for the conditioned variables (i.e., bill length).
# This is explained in the Turing docs linked above.
ppd = predict(prior_model, chain)

# Unstandardise the predicted and observed bill lengths
using FlexiChains: transform_values
ppd = transform_values(ppd, :bill_length_mm => (v -> reconstruct(bill_zs, v)))
observed = reconstruct(bill_zs, penguins.bill_length_mm)

FM.pushforward_hist(
    ppd,
    @varname(bill_length_mm);
    observed=observed,
    axis=(; xlabel="bill length (mm)"),
)
```

We may also be interested in how predicted bill length changes with increasing body mass, and how this varies by species.
For this, we can make use of [`pushforward_continuous`](@ref FlexiChains.Makie.pushforward_continuous) by feeding it a grid of body mass values.

In the example below, we have set `sigma = 0` to drop the predictive uncertainty; we're interested only in the uncertainty of the means here.

```@example pushforward
# Set up the grid of body mass values and species indices
pred_body_mass = repeat(range(-3, 3, length=50), outer=3)
pred_species = repeat(1:3, inner=50)

# For each draw of the parameters in the chain, compute the predicted
# bill length for each combination of species and body mass.
pred_model = fix(bill_model(pred_species, pred_body_mass), (; sigma=0))
pred = predict(pred_model, chain)

# Unstandardise the predicted means
using FlexiChains: transform_values
pred = transform_values(pred, :bill_length_mm => (v -> reconstruct(bill_zs, v)))

# Plot the predicted means with uncertainty bands, coloured by species.
fig = Figure()
ax = Axis(fig[1, 1]; xlabel="body mass (g)", ylabel="bill length (mm)")
colors = Makie.wong_colors()[1:3]
for (s, color) in enumerate(colors)
    ix = findall(==(s), pred_species)
    x_grid = reconstruct(mass_zs, pred_body_mass[ix])
    FM.pushforward_continuous!(
        ax,
        pred,
        @varname(bill_length_mm[ix]);
        x_grid=x_grid,
        color=color,
    )
end
axislegend(ax, [PolyElement(; color=c) for c in colors], species_names; position=:lt)

fig
```

Finally, if we want to examine the distributions of discrete parameters, such as the main or interaction effect of species, we can use [`pushforward_discrete`](@ref FlexiChains.Makie.pushforward_discrete).
Here, we'll look at the interaction effect to see if there's any evidence for the effect of body mass varying by species.

```@example pushforward
FM.pushforward_discrete(chain, @varname(beta3))
```

```@docs
FlexiChains.Makie.pushforward_continuous
FlexiChains.Makie.pushforward_continuous!
FlexiChains.Makie.pushforward_discrete
FlexiChains.Makie.pushforward_discrete!
FlexiChains.Makie.pushforward_hist
FlexiChains.Makie.pushforward_hist!
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
    [@varname(x), @varname(y)];
    color=[(:red, 0.6), (:blue, 0.6), (:green, 0.6)],
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
