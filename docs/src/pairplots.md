# [PairPlots.jl](@id integrations-pairplots)

[Documentation for PairPlots.jl ↗](https://sefffal.github.io/PairPlots.jl/dev/)

FlexiChains provides two ways to interact with PairPlots.jl.

## `pairplot()`

Firstly, you can directly call `pairplot(chn[, param_or_params])` on a `FlexiChain`.
This is a convenience method which includes extra functionality for e.g. highlighting divergent transitions.
To demonstrate this we'll create a fake `FlexiChain` with some random data.
(Our usual `EXAMPLE_CHAIN` only contains 10 iterations, so leads to some very poor plots.)

```@example pairplots
using FlexiChains
using FlexiChains: FlexiChain, Parameter, Extra, OrderedDict

chn = FlexiChain{VarName}(
    500,
    2,
    OrderedDict(
        Parameter(@vn(mu)) => randn(500, 2),
        Parameter(@vn(tau)) => randn(500, 2) .* 3 .+ 2,
        Parameter(@vn(theta)) => [[randn(), randn() - 1.0] for _ in 1:500, _ in 1:2],
        Extra(:is_divergent) => rand(500, 2) .< 0.1,
    ),
)
```

When sampling with NUTS, the resulting chain will (hopefully!) contain an `Extra` Boolean indicating whether or not the transition was divergent.
In the example chain above, this has been stored in the `Extra(:is_divergent)` key.
If you are sampling with e.g. Turing.jl, this key should be named `Extra(:numerical_error)`.
Either way, this can be passed to `pairplot()` to highlight the divergent transitions in the plot.

Carrying on with our plotting:

```@example pairplots
# Limit the parameters being plotted for readability
vns = [@vn(tau), @vn(theta[1]), @vn(theta[2])]

using PairPlots, CairoMakie
pairplot(chn, vns; divergences=:is_divergent)
Makie.save("pairplot.png", ans); # hide
```

![Pair plot of the sampled chain](pairplot.png)

## Conversion to Series

For more low-level control, you can also convert a `FlexiChain` into a `PairPlots.Series`, so that you can combine it with other data or fixed values in custom plots.

```@example pairplots
# Just some random values.
expected_means = (tau=2.0, var"theta[1]"=0.0, var"theta[2]"=-1.0)

pairplot(PairPlots.Series(chn[vns]), PairPlots.Truth(expected_means, label="True"))
```

Notice that `Series(chn)` will pool the samples in all chains together.
If you want to plot each chain separately, split them up into separate `Series` objects:

```@example pairplots
pairplot(
    (
        PairPlots.Series(chn[vns, chain=i], label="Chain $i") for
        i in FlexiChains.chain_indices(chn)
    )...,
    PairPlots.Truth(expected_means, label="True"),
)
```

## Docstrings

```@docs
PairPlots.pairplot
PairPlots.Series
```
