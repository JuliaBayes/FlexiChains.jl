# [Modifying data](@id modifying)

While `FlexiChain` and `FlexiSummary` are intended to be immutable, there are scenarios where you may want to modify the data that they contain.

FlexiChains provides generic, high-level functions that allow you to modify either the keys or the values stored inside a `FlexiChain` or `FlexiSummary`.

All of these functions return a new chain (or summary) and avoid mutating the original chain (or summary).

!!! note "Specialised applications"

    These functions are meant to be general, in that you can use them to perform any transformation you like.
    This means that for 'simple' applications such as renaming a single key they can be quite verbose.
    If you have a specific use case that would benefit from a more specialised function, please do feel free to open an issue or submit a pull request!

## Modifying keys

Let's set up a chain first:

```@example modifications
using FlexiChains: FlexiChain, Parameter, Extra

data = Dict(
    Parameter(:x) => randn(10, 3),
    Parameter(:y) => randn(10, 3),
    Extra(:a) => randn(10, 3),
)
chain = FlexiChain{Symbol}(10, 3, data)
```

If you want to change the keys stored inside a `FlexiChain` or `FlexiSummary`, you can use the `map_keys` function:

```@example modifications
using FlexiChains: get_name, map_keys

# Define a function that takes the old key and returns a new key.
f(p::Parameter) = Parameter(Symbol("new_", get_name(p)))
f(p::Extra) = p

map_keys(f, chain)
```

Often for the most part you will only want to modify `Parameter`s, in which case you can use `map_parameters`, and can skip the wrapping/unwrapping in `Parameter`:

```@example modifications
using FlexiChains: map_parameters

g(s::Symbol) = Symbol("new_", s)

map_parameters(g, chain)
```

Note that both `map_keys` and `map_parameters` work with `FlexiSummary` as well.

## [Modifying values](@id modifying-values)

It is also possible to modify the *values* stored inside a `FlexiChain` (but not a `FlexiSummary`).
This is done with the `transform_values` function:

```@example modifications
using FlexiChains: FlexiChain, VarName, Parameter, Extra, transform_values
using DynamicPPL: @varname
data = Dict(
    Parameter(@varname(x)) => randn(10, 3),
    Parameter(@varname(y)) => randn(10, 3),
    Extra(:a) => randn(10, 3),
)
chain = FlexiChain{VarName}(10, 3, data)

chain2 = transform_values(
    chain,
    @varname(x) => (i -> i + 1),
    @varname(y) => (i -> i * 2) => @varname(new_y),
)
```

The above example:

  - adds 1 to each element of `chain[@varname(x)]`; and
  - multiplies each element of `chain[@varname(y)]` by 2, and stores the result in a new key `@varname(new_y)`.

```@example modifications
chain2[@varname(x)] .- chain[@varname(x)]   # Should be all 1.
```

You can pass as many transformations as you like.
The syntax is designed to be similar to that of `DataFrames.transform`, but has some slight differences: notably, the function being applied acts on *individual draws* from `chain[@varname(x)]` rather than the matrix as a whole.

You can also pass binary (or *n*-ary) functions to `transform_values` to combine multiple keys.
Again, this is similar to `DataFrames.transform`, but the function combines individual draws from `chain[@varname(x)]` and `chain[@varname(y)]` rather than the matrices themselves.

```@example modifications
chain3 = transform_values(chain, [@varname(x), @varname(y)] => (+) => @varname(sum_xy))
```

```@example modifications
chain3[@varname(sum_xy)] == chain[@varname(x)] .+ chain[@varname(y)]
```

### Attaching labels to data

A common use case for `transform_values` is to attach labels to data, for example, converting a `Vector` of parameters into a `DimVector`.
For example, consider our (now familiar) eight-schools model.

```@example modifications
using DynamicPPL: @model, filldist
using Distributions, LinearAlgebra

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
chain = FlexiChains._make_prior_chain(model, 3, 1)
```

In this chain, `theta` has one entry per school, but is stored as a plain `Vector`.
While this is fine for many applications, attaching labels can help make it easier to analyse the data.

```@example modifications
using DimensionalData: DimArray, Dim

school_names = [
    "Choate",
    "Deerfield",
    "Phillips Andover",
    "Phillips Exeter",
    "Hotchkiss",
    "Lawrenceville",
    "St. Paul's",
    "Mt. Hermon",
]
add_labels(v::Vector{<:Real}) = DimArray(v, Dim{:school}(school_names))

chain = transform_values(chain, :theta => add_labels)
```

For example, `DimVector` parameters get special labels when plotting:

```@example modifications
using CairoMakie

FlexiChains.Makie.traceplot(chain, @varname(theta); layout=(4, 2))
```

Having the labels also benefits downstream analysis of any data extracted from the chain.
For example, you can obtain the same functionality as [tidybayes' `spread_draws`](https://mjskay.github.io/tidybayes/reference/spread_draws.html):

```@example modifications
using DataFrames

# Create a 3D DimArray (iter x chain x school)
dimarr = chain[:theta, stack=true]

# Convert it to a DataFrame (long-format by default)
df = DataFrame(dimarr)
```

If you want a wide-format table, you can tap into the functionality in DimensionalData.jl (please see [their docs](@extref DimensionalData tables) for full info):

```@example modifications
using DimensionalData: DimTable

df = DataFrame(DimTable(dimarr; layersfrom=:school))
```

### Standardisation

Another use case for transforming values is to (un)standardise parameter values.

For example, consider this simple linear regression (in principle `X` should also be standardised, but we'll skip it here).

```@example modifications
X = randn(100, 3)
y = randn(100) .* 4.0 .+ 2.0

using StatsBase: fit, ZScoreTransform, transform
zs = fit(ZScoreTransform, y)
y_scaled = transform(zs, y)

mean(y_scaled), std(y_scaled)  # ≈ 0 and 1
```

```@example modifications
@model function linear_regression(X)
    beta ~ filldist(Normal(), size(X, 2))
    mu := X * beta
    y ~ MvNormal(mu, I)
end
model = linear_regression(X) | (; y=y_scaled)

chain = FlexiChains._make_prior_chain(model, 1000, 1)
```

In the resulting chain, we have values of `mu` but these are standardised according to the same ZScoreTransform we fitted to `y`.

```@example modifications
mean(chain[:mu, stack=true])  # (probably) close to 0.
```

We can unstandardise them by applying the inverse transformation.

```@example modifications
using StatsBase: reconstruct

chain = transform_values(chain, :mu => (i -> reconstruct(zs, i)))

mean(chain[:mu, stack=true])
```

## Docstrings

```@docs
FlexiChains.map_keys
FlexiChains.map_parameters
FlexiChains.transform_values
```
