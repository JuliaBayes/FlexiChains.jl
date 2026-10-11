# [MCMCChains.jl](@id integrations-mcmcchains)

You can convert FlexiChain objects to and from `MCMCChains.Chains`.

## MCMCChains to FlexiChain

For example, let's make an MCMCChains object from a Turing model:

```@example mcmcchains
using DynamicPPL, MCMCChains, AbstractMCMC, Distributions, LinearAlgebra

@model function f()
    x ~ Normal()
    y ~ Bernoulli()
    z ~ MvNormal(zeros(2), I)
end

# Sample from the prior, and tack on a random log-probability.
samples = [DynamicPPL.ParamsWithStats(rand(f()), (; logp=rand())) for _ in 1:100, _ in 1:3]
# Bundle them into a Chain
mc = AbstractMCMC.from_samples(MCMCChains.Chains, samples)
```

The most naive conversion will create a `FlexiChain{Symbol}`, since that is the key type of MCMCChains:

```@example mcmcchains
using FlexiChains

FlexiChains.from_mcmcchains(mc)
```

However, notice that we don't have the vector structure of the parameter `z`, and instead have two different scalar parameters `z[1]` and `z[2]`.
We can add the structure back by specifying a set of keys as the second argument:

```@example mcmcchains
using FlexiChains: Parameter, Extra, @vn

fc = FlexiChains.from_mcmcchains(
    mc,
    (Parameter(@vn(x)), Parameter(@vn(y)), Parameter(@vn(z)) => (2,), Extra(:logp)),
)
```

By passing `VarName` parameters instead of `Symbol`s, we can 'upconvert' this into a `VNChain` rather than a `SymChain` (which is harder to index into, for example, if you want to get `z[1]`).
Furthermore, by specifying the shape of `z` as `(2,)`, we can recover the vector structure of that parameter.
In general array-valued parameters can be 'recovered' in this way, but more complicated structs cannot be.

!!! warning "Order of parameters"

    The parameters provided as the second argument must add up to exactly the same number of columns in the original MCMCChains object, and must also be in the same order as they appear in the original object.
    The order of the parameters in an MCMCChains object is not always obvious, so be careful with this.

After that, you might also want to convert `y` back into a Boolean:

```@example mcmcchains
fc = FlexiChains.transform_values(fc, @vn(y) => Bool)
```

## FlexiChain to MCMCChains

The conversion from FlexiChain to MCMCChains is much more straightforward.
Since MCMCChains just throws away all the information, there is no behaviour to customise:

```@example mcmcchains
MCMCChains.Chains(fc)
```

## Docstrings

```@docs
FlexiChains.from_mcmcchains
MCMCChains.Chains(::FlexiChains.FlexiChain)
```
