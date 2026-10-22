# [MCMCChains.jl](@id integrations-mcmcchains)

You can convert FlexiChain objects to and from `MCMCChains.Chains`.

## FlexiChain to MCMCChains

The conversion from FlexiChain to MCMCChains is much more straightforward.
Since an `MCMCChains.Chains` object contains much less information than a `FlexiChain`, this is just a one-liner, with no real customisation available:

```@example mcmcchains
using FlexiChains, MCMCChains

chain = FlexiChains.EXAMPLE_CHAIN
```

```@example mcmcchains
mc = MCMCChains.Chains(chain)
```

## MCMCChains to FlexiChain

Let's now explore how we can convert this object back into a `FlexiChain`, putting all the type and shape information back in.

The relevant function is [`FlexiChains.from_mcmcchains`](@ref).
If we naively call this we will get a `FlexiChain{Symbol}`, since that is the key type of MCMCChains:

```@example mcmcchains
FlexiChains.from_mcmcchains(mc)
```

Notice that we don't have the vector structure of the parameter `theta`, and instead have different scalar parameters `theta[1]` through `theta[8]`.
Furthermore, the `is_divergent` extra key has been converted into a `Float64`.

This is a direct result of the fact that `MCMCChains.Chains` objects don't store any type information, and only store scalar parameters.

Let's tackle both of these separately.
We can regain the structure of `theta` by specifying a set of keys as the second argument:

```@example mcmcchains
using FlexiChains: Parameter, Extra, @vn

fc = FlexiChains.from_mcmcchains(
    mc,
    (
        Parameter(@vn(mu)),
        Parameter(@vn(tau)),
        Parameter(@vn(theta)) => (8,),
        Extra(:logjoint),
        Extra(:is_divergent),
    ),
)
```

By passing `VarName` parameters instead of `Symbol`s, we can 'upconvert' this into a `VNChain` rather than a `SymChain`.
Furthermore, by specifying the shape of `theta` as `(8,)`, we can recover the vector structure of that parameter.
In general array-valued parameters can be 'recovered' in this way, but more complicated structs cannot be.

!!! warning "Order of parameters"

    The parameters provided as the second argument must add up to exactly the same number of columns in the original MCMCChains object, and must also be in the same order as they appear in the original object.
    The order of the parameters in an MCMCChains object is not always obvious, so be careful with this.

After that, we can also convert `is_divergent` back into a Boolean:

```@example mcmcchains
fc = FlexiChains.transform_values(fc, Extra(:is_divergent) => Bool)
```

## Docstrings

```@docs
FlexiChains.from_mcmcchains
MCMCChains.Chains(::FlexiChains.FlexiChain)
```
