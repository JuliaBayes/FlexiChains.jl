# Accessing samples

FlexiChains stores data in a dict-of-array format (a column-oriented form, similar to dataframes).
This means that it is very easy to access all the data for a given variable, but accessing all the data for a given sample (i.e., iteration / chain number) is a bit more involved.

Consider our now-familiar example chain:

```@example samples
using FlexiChains

chn = FlexiChains.EXAMPLE_CHAIN
```

Here, we have three parameters `mu`, `tau`, and `theta`.
FlexiChains makes it very easy to access the value of _a single parameter_ across all iterations and chains:

```@example samples
chn[@vn(mu)]
```

However, suppose you want to obtain the values of _all parameters_ at a given iteration and chain number.
For example, you might want to know what happened at the fifth iteration.

One way is to subset a chain.
The issue is that that gives you just another chain back:

```@example samples
subsetted = chn[iter=5, chain=1]
```

and to access the data you will still need to index into it, which is rather awkward:

```@example samples
(mu=only(subsetted[@vn(mu)]), tau=only(subsetted[@vn(tau)]))
```

We should definitely like to have a better way of accessing this collection of values at a given iteration/chain.

Generally speaking, the operation above can be viewed as a transformation from column-oriented data to row-oriented data, or from a dict-of-arrays to an array-of-dicts.
FlexiChains provides a few convenient ways for you to do this transformation.

# `values_at`

The function [`FlexiChains.values_at`](@ref) is at the core of this transformation.
Given iteration and chain indices (as keyword arguments), it returns some container that holds all the values for a given iteration.

```@example samples
draw = FlexiChains.values_at(chn; iter=5, chain=1)
```

There is a subtlety here in that the exact type of the container returned depends on what is stored in the chain.

!!! note "Structures"

    For the interested reader, or if you are developing FlexiChains, this is determined by the _structures_ stored in the chain, which are meant to be a 'template' for the container.
    If you are just a user who has obtained a `FlexiChain` from some library, should not need to worry about this, as the structures should be set up correctly for you by that library.

For chains that have parameter type `VarName`, i.e. a `VNChain`, the returned container should usually be a [`VarNames.Draw`](@extref).
This is a struct that separately stores the parameters and the stats as a [`VarNames.VarNamedTuple`](@extref) and a `NamedTuple` respectively.

!!! note "Not getting a `Draw`?"

    If you instead get an `OrderedDict`, you _should_ probably report this as a bug to the library that produced the chain.

For more information about these types, the reader is referred to the [VarNames.jl docs](https://juliabayes.org/VarNames.jl/stable/).
The key point here is that this is a high-fidelity representation of the data.
You can access the parameters and extras separately:

```@example samples
ps = FlexiChains.parameters(draw)
```

```@example samples
FlexiChains.extras(draw)
```

The parameter `VarNamedTuple` can be further indexed into with `VarName`s to obtain the values of individual parameters.
Much like a `FlexiChain` itself, you have the ability to index into a `VarNamedTuple` with sub-variables, such as `theta[1:3]`:

```@example samples
ps[@vn(mu)], ps[@vn(theta[1:3])]
```

## Choosing a different container type

Sometimes, though, one might want different output formats.
There is some support for converting to `NamedTuple` or `AbstractDict`, by passing an optional type argument.

!!! warning "Conversion to NamedTuple is not faithful"

    Note that conversion to `NamedTuple` is lossy if you have `VarName`s that contain indexing or field access syntax (e.g., `x[1]` or `x.a`).

```@example samples
FlexiChains.values_at(chn, NamedTuple; iter=5, chain=1)
```

```@example samples
FlexiChains.values_at(chn, Dict; iter=5, chain=1)
```

# Obtaining only parameters

Often the stats are not of very much interest, and you just want the parameters.
In that case, you can use `parameters_at`:

```@example samples
FlexiChains.parameters_at(chn; iter=5, chain=1)
```

This is exactly the same as `values_at`, except that it only returns the parameters.

!!! note "Not getting a VarNamedTuple"

    Just as above, if you instead get an `OrderedDict`, you should *probably* report this as a bug to the library that produced the chain.

# Arrays of samples

The functions above also accept multiple iteration or chain indices, and will return the corresponding array of containers.

```@example samples
FlexiChains.parameters_at(chn; iter=[5, 6], chain=1)
```

All of DimensionalData's selectors also work:

```@example samples
FlexiChains.parameters_at(chn; iter=Not(1..8), chain=1)
```

This also means that you can convert a `VNChain` back into an `Array` of `Draw` objects by passing `:` for both the iteration and chain indices.

```@example samples
FlexiChains.values_at(chn; iter=:, chain=:)
```

# Drawing random samples

To get a random sample from the chain, you can use [`Base.rand`](@ref).
The container type returned is the same as for `values_at`:

```@example samples
rand(chn)
```

This method follows Julia's conventions closely, so you can have an optional `rng` first argument, and you can also specify the number of samples to draw:

```@example samples
using Random: Xoshiro
rand(Xoshiro(468), chn, 2, 2)
```

Weighted sampling is also supported (see the docstring below for more info).

If you only want parameters, pass the `parameters_only=true` keyword argument:

```@example samples
rand(chn, parameters_only=true)
```

# Docstrings

```@docs
FlexiChains.values_at
FlexiChains.parameters_at
Base.rand
```
