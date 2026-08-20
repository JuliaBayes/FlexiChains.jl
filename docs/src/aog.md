# [AlgebraOfGraphics.jl](@id plotting-aog)

[Documentation for AlgebraOfGraphics.jl ↗](https://aog.makie.org/stable/)

AlgebraOfGraphics.jl (AoG) is a plotting package built on top of Makie, which provides a declarative interface for plotting, much like R's `ggplot2`.

FlexiChains does not provide any direct functionality to work with AoG.
However, since FlexiChains [provides a Tables.jl interface](@ref integrations-tables), it can be fed into AoG for plotting.
This page provides a handful of examples.

We begin by sampling our familiar eight-schools model.

```@example aog
using FlexiChains, DynamicPPL, Distributions, LinearAlgebra

y = [28, 8, -3, 7, -1, 1, 18, 12]
sigma = [15, 10, 16, 11, 9, 11, 10, 18]
@model function eight_schools(y, sigma)
    mu ~ Normal(0, 5)
    tau ~ truncated(Cauchy(0, 5); lower=0)
    theta ~ MvNormal(fill(mu, length(y)), tau^2 * I)
    for i in eachindex(y)
        y[i] ~ Normal(theta[i], sigma[i])
    end
    return (mu=mu, tau=tau)
end
model = eight_schools(y, sigma)
chain = FlexiChains._make_prior_chain(model, 100, 3)
```

Because AoG mainly works with long-form data, we need to specify this when creating a Tables.jl-compatible object, as the default for FlexiChains is a wide-form table.
We also subset the chain to only include the `theta` parameters.

```@example aog
using FlexiChains: Long

lng = Long(chain[[@varname(theta)]])
nothing # hide
```

We can directly feed `lng` into AoG, without having to materialise it as a DataFrame.
For the purposes of these docs we will take a look at (ten random rows of) the data:

```@example aog
using DataFrames, Random

df = DataFrame(lng)
row_idxs = shuffle(1:nrow(df))[1:10]
df[row_idxs, :]
```

Often when plotting you will want to facet by parameter.
For a `VNChain`, it is necessary to [apply the `presorted` transform](https://aog.makie.org/stable/tutorials/intro-iv#presorted), because `VarName`s do not have a natural ordering.
The `presorted` function makes sure that the facets retain the order in the chain.

```@example aog
using AlgebraOfGraphics, CairoMakie

d = data(lng)
m = mapping(:value, layout=:param => presorted)
v = AlgebraOfGraphics.density()

draw(d * m * v)
```

To avoid pooling all chains into a single plot, we can also split the chains into separate colours:

```@example aog
d = data(lng)
m = mapping(:value, layout=:param => presorted, color=:chain => nonnumeric)
v = visual(Density; alpha=0.4)
draw(d * m * v)
```

And here is a violin plot:

```@example aog
d = data(lng)
m = mapping(:param => presorted, :value)
v = visual(Violin; orientation=:horizontal)
draw(d * m * v)
```
