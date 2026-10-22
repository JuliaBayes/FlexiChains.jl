# What's in a FlexiChain?

A `FlexiChain{T}`, at its core, is a wrapper around a dictionary which maps *keys* to *matrices* of size (`niters x nchains`).

Let's start by loading an example `FlexiChain`.

```@example datastructure
using FlexiChains

chain = FlexiChains.EXAMPLE_CHAIN
```

## Keys: parameters and extras

Each key in a `FlexiChain{T}` can be either:

  - a [`Parameter{<:T}`](@ref FlexiChains.Parameter), or
  - an [`Extra`](@ref FlexiChains.Extra).

Each `Parameter` or `Extra` itself carries a *name*, which can be retrieved with [`FlexiChains.get_name`](@ref).

```@example datastructure
using FlexiChains: get_name, Parameter

name = FlexiChains.get_name(FlexiChains.Parameter(@vn(mu)))

name, typeof(name)
```

For a `Parameter{T}`, the name must be a `T`.
For an `Extra`, the name must always be a `Symbol`, regardless of the parameter key type.

You can list all keys, all parameters, or all extras:

```@example datastructure
keys(chain)
```

```@example datastructure
FlexiChains.parameters(chain)
```

```@example datastructure
FlexiChains.extras(chain)
```

## Values: matrices

Because each key maps to a different matrix, FlexiChains can store values of different types and sizes.

For example, `mu` is stored as `Float64`, and `theta` as a `Vector{Float64}`.
Indexing into a chain returns an `niters x nchains` matrix of these samples:

```@example datastructure
chain[@vn(mu)]
```

```@example datastructure
chain[:is_divergent]
```

In this introductory page we don't go into the details of indexing; there's [one full page on that](@ref indexing).

To obtain the number of iterations or chains, you can use [`FlexiChains.niters`](@ref) and [`FlexiChains.nchains`](@ref):

```@example datastructure
FlexiChains.niters(chain), FlexiChains.nchains(chain)
```

Alternatively, `size(chain)` returns `(niters, nchains)`:

```@example datastructure
size(chain)
```

Notice that there is no measure of the *number of parameters*.
Unlike other chains packages, such as MCMCChains.jl, FlexiChains does not have a third 'parameter axis'.
If you want to get such a number, you can use `length(keys(chain))` or `length(FlexiChains.parameters(chain))`.
