# Accessing samples

FlexiChains stores data in a dict-of-array format (a column-oriented form, similar to dataframes).
This means that it is very easy to access all the data for a given variable, but accessing all the data for a given sample (i.e., iteration / chain number) is a bit more involved.

Consider the following example:

```@example samples
using FlexiChains, Distributions
using DynamicPPL: @model, @varname

@model function f()
    x ~ Normal()
    y ~ Uniform(1, 2)
end

chn = FlexiChains._make_prior_chain(f(), 10, 1)
```

Here, we have two variables `x` and `y`.
FlexiChains makes it very easy to access _all_ the samples for `x`, or _all_ the samples for `y`, and so on:

```@example samples
chn[@varname(x)]
```

However, suppose you want to access the samples for a given iteration and chain number.
For example, you might want to know what happened at the fifth iteration.

One way is to subset a chain.
The issue is that that gives you just another chain back:

```@example samples
subsetted = chn[iter=5, chain=1]
```

and to access the data you will still need to index into it, which is rather awkward:

```@example samples
(x=only(subsetted[@varname(x)]), y=only(subsetted[@varname(y)]))
```

More generally speaking, the operation above can be viewed as a transformation from column-oriented data to row-oriented data, or from a dict-of-arrays to an array-of-dicts.
FlexiChains provides a few convenient ways for you to do this transformation.

# `values_at`

The function `values_at` is at the core of this transformation.
Given iteration and chain indices (as keyword arguments), it returns some container that holds all the values for a given iteration.

```@example samples
vs = FlexiChains.values_at(chn; iter=5, chain=1)
```

In the case of a chain sampled from Turing, the returned container is `DynamicPPL.ParamsWithStats`, which separately stores the parameters and the stats as a `VarNamedTuple` and `NamedTuple` respectively.
This is a high-fidelity representation of the data, and is exactly what you get when sampling with Turing.jl (for example, if you call `sample(...; chain_type=Any)`, you will get an array of `ParamsWithStats` objects).

!!! info

    This is accomplished by storing a skeletal `VarNamedTuple` for each sample in the chain; if you are interested, see [the DynamicPPL docs](https://turinglang.org/DynamicPPL.jl/stable/vnt/manipulation/#Skeleton-VNTs) for more info.

The main benefit of this is that you can feed this right back into Turing's API.
For example, to initialise MCMC sampling from the fifth sample, you can write:

```julia
pws = FlexiChains.values_at(chn; iter=5, chain=1)
sample(f(), NUTS(), 10; initial_params=InitFromParams(pws), progress=false);
```

Sometimes, though, one might want different output formats.
There is some support for converting to `NamedTuple` or `AbstractDict`, by passing an optional type argument.

!!! warning

    Note that conversion to `NamedTuple` is lossy if you have `VarName`s that contain indexing or field access syntax (e.g., `x[1]` or `x.a`).

```@example samples
FlexiChains.values_at(chn, NamedTuple; iter=5, chain=1)
```

```@example samples
FlexiChains.values_at(chn, Dict; iter=5, chain=1)
```

# Parameters only

Often the stats are not of very much interest, and you just want the parameters.
In that case, you can use `parameters_at`:

For Turing-sampled chains, this returns a `VarNamedTuple`, which is just the same as the `params` field of the `ParamsWithStats` object.

```@example samples
FlexiChains.parameters_at(chn; iter=5, chain=1)
```

# Arrays of samples

To get more than one sample, you can pass arrays of indices.

```@example samples
FlexiChains.parameters_at(chn; iter=[5, 6], chain=1)
```

All of DimensionalData's selectors also work:

```@example samples
FlexiChains.parameters_at(chn; iter=Not(1..8), chain=1)
```

This also means that you can convert a FlexiChain back into an `Array` of `ParamsWithStats` objects by passing `:` for both the iteration and chain indices, which is essentially the inverse of what `sample` does (it bundles the array into a FlexiChain).
In fact, `:` is the default for both of these keyword arguments, so you can just write:

```@example samples
FlexiChains.values_at(chn)
```

# Drawing random samples

To get a random sample from the chain, you can use `rand`:

```@example samples
rand(chn)
```

This method follows Julia's conventions closely, so you can have an optional `rng` first argument, and you can also specify the number of samples to draw:

```@example samples
using Random: Xoshiro
rand(Xoshiro(468), chn, 2, 2)
```

If you only want parameters, pass the `parameters_only=true` keyword argument:

```@example samples
rand(chn, parameters_only=true)
```

# Using `VarNamedTuple`s

All of the above functions, when run with Turing-sampled chains, return `VarNamedTuple`s or containers thereof.
To access the values, you need to index with a `VarName`:

```@example samples
vnt = rand(chn, parameters_only=true)
vnt[@varname(x)]
```

Please see [the Turing docs](https://turinglang.org/docs/usage/varnamedtuple/) for more details on working with `VarNamedTuple`s.

# Docstrings

```@docs
FlexiChains.values_at
FlexiChains.parameters_at
Base.rand
```
