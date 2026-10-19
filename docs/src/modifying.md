# [Modifying data](@id modifying)

While `FlexiChain` and `FlexiSummary` are intended to be immutable, there are scenarios where you may want to modify the data that they contain.

FlexiChains provides generic, high-level functions that allow you to modify either the keys or the values stored inside a `FlexiChain` or `FlexiSummary`.

All of these functions return a new chain (or summary) and avoid mutating the original chain (or summary).

!!! note "Specialised applications"

    These functions are meant to be general, in that you can use them to perform any transformation you like.
    This means that for 'simple' applications such as renaming a single key they can be quite verbose.
    If you have a specific use case that would benefit from a more specialised function, please do feel free to open an issue or submit a pull request!

## Modifying keys

Let's load our example chain first:

```@example modifications
using FlexiChains

chain = FlexiChains.EXAMPLE_CHAIN
```

If you want to change the keys stored inside a `FlexiChain` or `FlexiSummary`, you can use the [`FlexiChains.map_keys`](@ref) function.

```@example modifications
using FlexiChains: get_name, map_keys, Parameter, Extra, VarName
using VarNames: getsym, getoptic

# Define a function that takes the old key and returns a new key.
function f(p::Parameter{<:VarName})
    # Get the name of the parameter (e.g. @vn(x))
    name = get_name(p)
    # Get the components of that VarName.
    sym, optic = getsym(name), getoptic(name)
    # Add a prefix to the symbol.
    new_sym = Symbol("new_", sym)
    # Return a new Parameter with the new name
    return Parameter{VarName}(VarName{new_sym}(optic))
end

# Don't change extras!
f(p::Extra) = p

map_keys(f, chain)
```

This example is admittedly quite contrived.
However, it is intended to be general enough to cover any use case you might have.
For example, if you want to rename a single key, `f` can simply be a function that looks it up in a dictionary:

```julia
mapping = Dict(old_key => new_key)

f(p) = get(mapping, p, p)  # Return the new key if it exists, otherwise return the old key.
```

Often for the most part you will only want to modify `Parameter`s, in which case you can use [`FlexiChains.map_parameters`](@ref).
This has the same behaviour as `map_keys`, except that you can skip the wrapping/unwrapping in `Parameter`.

Note that both `map_keys` and `map_parameters` work with `FlexiSummary` as well.

## [Modifying values](@id modifying-values)

It is also possible to modify the *values* stored inside a `FlexiChain` (but not a `FlexiSummary`).
This is done with the `transform_values` function:

```@example modifications
using FlexiChains: transform_values

chain2 = transform_values(
    chain,
    @vn(mu) => (i -> i + 1),
    @vn(tau) => (i -> i * 2) => @vn(new_tau)
)
```

The above example:

  - adds 1 to each element of `chain[@vn(mu)]`; and
  - multiplies each element of `chain[@vn(tau)]` by 2, and stores the result in a new key `@vn(new_tau)`.

```@example modifications
chain2[@vn(mu)] .- chain[@vn(mu)]   # Should be all 1.
```

You can pass as many transformations as you like.
The syntax is designed to be similar to that of `DataFrames.transform`, but has some slight differences: notably, the function being applied acts on *individual draws* from `chain[@vn(x)]` rather than the matrix of all draws.
(In DataFrames, the functions act on entire columns of data.)

You can also pass binary (or *n*-ary) functions to `transform_values` to combine multiple keys.
Again, this is similar to `DataFrames.transform`, but the function combines individual draws from `chain[@vn(mu)]` and `chain[@vn(tau)]` rather than the matrices themselves.

```@example modifications
chain3 = transform_values(chain, [@vn(mu), @vn(tau)] => (+) => @vn(mu_plus_tau))
```

```@example modifications
chain3[@vn(mu_plus_tau)] == chain[@vn(mu)] .+ chain[@vn(tau)]
```

### Attaching labels to data

A common use case for `transform_values` is to attach labels to data, for example, converting a `Vector` of parameters into a `DimVector`.

In our example chain above, `theta` has one entry per school, but is stored as a plain `Vector`.
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

labelled_chain = transform_values(chain, @vn(theta) => add_labels)
```

For example, `DimVector` parameters get special labels when plotting:

```@example modifications
using CairoMakie

FlexiChains.Makie.traceplot(labelled_chain, @vn(theta); layout=(4, 2))
```

Having the labels also benefits downstream analysis of any data extracted from the chain.
For example, you can obtain the same functionality as [tidybayes' `spread_draws`](https://mjskay.github.io/tidybayes/reference/spread_draws.html):

```@example modifications
using DataFrames

# Create a 3D DimArray (iter x chain x school)
dimarr = labelled_chain[@vn(theta), stack=true]

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

For example, consider a case where we have some model data `y` which is standardised before being passed to a model:

```@example modifications
y = randn(100) .* 4.0 .+ 2.0

using StatsBase: fit, ZScoreTransform, transform
zs = fit(ZScoreTransform, y)
y_scaled = transform(zs, y)

mean(y_scaled), std(y_scaled)  # ≈ 0 and 1
```

Then, suppose that we pass `y_scaled` to a model and sample a parameter `m_scaled` which is the mean of the standardised `y`.
We'll construct one such chain for demonstration purposes:

```@example modifications
using FlexiChains: FlexiChain, VarName, Parameter

niters, nchains = 1000, 2
fake_m_data = [randn(100) .+ 1 for _ in 1:niters, _ in 1:nchains]

fake_chain =
    FlexiChain{VarName}(niters, nchains, Dict(Parameter(@vn(m_scaled)) => fake_m_data))
```

The mean of this `m_scaled` should be approximately 1:

```@example modifications
mean(fake_chain[@vn(m_scaled), stack=true])
```

We can unstandardise the `m_scaled` values by applying the inverse transformation:

```@example modifications
using StatsBase: reconstruct

fake_chain =
    transform_values(fake_chain, @vn(m_scaled) => (i -> reconstruct(zs, i)) => @vn(m))
```

The mean of the reconstructed `m` should be approximately `(4 * 1) + 2 = 6`:

```@example modifications
mean(fake_chain[@vn(m), stack=true])
```

## Docstrings

```@docs
FlexiChains.map_keys
FlexiChains.map_parameters
FlexiChains.transform_values
```
