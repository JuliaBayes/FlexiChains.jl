# [Turing.jl](@id integrations-turing)

[Documentation for Turing.jl ↗](https://turinglang.org/docs)

This page provides a fairly high-level overview of how to use FlexiChains with Turing.jl.

If you have a previous workflow that uses MCMCChains.jl and want to find out how to update it, you might also be interested in [the MCMCChains migration guide](@ref migration).

## Sampling

Since Turing.jl v0.45, FlexiChains is the default chain type returned by MCMC sampling.

!!! note "Not on Turing v0.45 yet?"

    To obtain a `FlexiChain` with older versions of Turing.jl, you can specify the `chain_type` keyword argument when calling `sample`:

    ```julia
    using FlexiChains
    sample(model, sampler, N; chain_type=VNChain)
    ```

Let's use a non-trivial model so that we can illustrate some features of FlexiChains.

```julia
using Turing, FlexiChains

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
chain = sample(model, Prior(), 5)
```

```@example 1
using FlexiChains, Distributions, LinearAlgebra # hide
using DynamicPPL: @model, @varname # hide
y = [28, 8, -3, 7, -1, 1, 18, 12] # hide
sigma = [15, 10, 16, 11, 9, 11, 10, 18] # hide
@model function eight_schools(y, sigma) # hide
    mu ~ Normal(0, 5) # hide
    tau ~ truncated(Cauchy(0, 5); lower=0) # hide
    theta ~ MvNormal(fill(mu, length(y)), tau^2 * I) # hide
    for i in eachindex(y) # hide
        y[i] ~ Normal(theta[i], sigma[i]) # hide
    end # hide
    return (mu=mu, tau=tau) # hide
end # hide
model = eight_schools(y, sigma) # hide
chain = FlexiChains._make_prior_chain(model, 5, 1) # hide
```

!!! note

    We only run 5 MCMC iterations here to keep the output in the following sections small.

## Key types

First, notice in the printout above that a `FlexiChain` stores 'parameters' and 'extra keys' separately.
Parameters correspond to random variables of the model you sampled from, whereas other keys are extra data associated with the samples drawn (for example, the log-joint probability of each sample).

In FlexiChains, these are wrapped in the [`FlexiChains.Parameter`](@ref) and [`FlexiChains.Extra`](@ref) types respectively.
Thus, the parameter `mu` is really stored as `Parameter(@varname(mu))`, and the log-joint probability is `Extra(:logjoint)`.

For a `FlexiChain{T}`, all `Parameter` keys must wrap objects that subtype `T`.
`Extra`s on the other hand can wrap anything.

`VNChain` is an alias for `FlexiChain{VarName}`, i.e., the parameters are stored as `VarName`s, which is the natural output for Turing.jl.

!!! note "SymChain"

    For other modelling packages it may sometimes be more natural to store parameters as `Symbol`s instead of `VarName`s.
    In that case, you can use `SymChain` (an alias for `FlexiChain{Symbol}`) instead of `VNChain`.

## Accessing data

FlexiChains provides multiple different ways to access the data for a given key.

### Parameters

To access parameters, the recommended way is to use `VarName`s to index into the chain.
`VarName` is a data structure [defined in AbstractPPL.jl](https://turinglang.org/AbstractPPL.jl/stable/api/#AbstractPPL.VarName), and is what Turing.jl uses to represent the name of a random variable (appearing on the left-hand side of a tilde-statement).

`VarName`s are most easily constructed by applying the `@varname` macro to the name of the variable that you want to access.
For example, this directly gives us the value of `mu` in each iteration as a plain old vector of floats.

```@example 1
chain[@varname(mu)]
```

!!! note "Wrapping in Parameter and Extra"

    When looking up a parameter, you do not need to wrap the `VarName` in `FlexiChains.Parameter(...)`: this will be automatically done for you. `Extra` keys always need to be wrapped (*but* see also [the shortcut for Symbol-based indexing below](@ref symbol-indexing)).

!!! note "DimMatrix"

    Indexing into a `FlexiChain` returns a [`DimensionalData.DimMatrix`](@extref DimensionalData DimArrays). This behaves exactly like a regular `Matrix`, but additionally carries extra information about its dimensions.

    This allows you to keep track of what each dimension means, and also allows for more advanced indexing operations, which are described in [the 'indexing' page](@ref indexing).

For vector-valued parameters like `theta`, this works in exactly the same way, except that you get a `DimMatrix` of vectors.

```@example 1
chain[@varname(theta)]
```

**This is probably the biggest difference between FlexiChains and MCMCChains.**
MCMCChains by default will break vector-valued parameters into multiple scalar-valued parameters called `theta[1]`, `theta[2]`, etc., whereas FlexiChains keeps them together as they were defined in the model.

!!! tip "If you want a 3D array..."

    If you want to access `theta` as a 3D array of shape `(num_iterations, num_chains, length(theta))`, you can also pass the keyword argument `stack=true` to `getindex`:

    ```@example 1
    chain[@varname(theta), stack=true]
    ```

If you want to obtain only the first element of `theta`, you don't need to manipulate the `DimMatrix`.
You can just index into the chain with the corresponding `VarName`:

```@example 1
chain[@varname(theta[1])]
```

In this way, you can 'break down', or access nested fields of, larger parameters.
That is, if your model has `x ~ dist`, FlexiChains will let you access some field or index of `x`.

!!! note "Heterogeneous data"

    If some samples of `x` have one element and others have two elements, attempting to access `x[2]` will return an array with `missing` values for the samples where `x` only has one element.

You can also use keyword arguments when indexing to specify which chains or iterations you are interested in.
Note that when using square brackets to index, keyword arguments must be separated from positional arguments by a comma, not a semicolon!

```@example 1
chain[@varname(mu), iter=2:4, chain=1]
```

You can also use selectors from DimensionalData.jl to specify which iterations or chains you want.

```@example 1
chain[@varname(mu), iter=Not(At(7)), chain=At(1)]
```

The indexing behaviour of FlexiChains is described fully on [the Indexing page](@ref indexing).

### Other keys

In general Turing.jl tries to package up some extra metadata into the chain that may be helpful.
For example, the log-joint probability of each sample is stored with the key `:logjoint`.
To access non-parameter information like this in an unambiguous fashion, you should use the `Extra` wrapper.

```@example 1
using FlexiChains: Extra

chain[Extra(:logjoint)]
```

!!! warning

    In older versions of Turing.jl, MCMCChains would store the log-joint probability as `:lp`. FlexiChains uses `:logjoint` instead, which is clearer. Since Turing v0.42, both MCMCChains and FlexiChains use `:logjoint`.

If there is no ambiguity in the symbol `:logjoint`, then you can use a shortcut which is described in the next section.

### [Indexing by `Symbol`: a shortcut](@id symbol-indexing)

If you are used to MCMCChains.jl, you may find this more cumbersome than before.
So, FlexiChains provides some shortcuts for accessing data.
You can index into a `FlexiChain` with a single `Symbol`, and _as long as it is unambiguous_, it will return the corresponding data.

```@example 1
chain[:mu] # parameter
```

!!! note "What does unambiguous mean?"

    In this case, because the only key `k` for which `Symbol(k.name) == :mu` is `Parameter(@varname(mu))`, we can safely identify `Parameter(@varname(mu))` as the key that we want. If this chain also had an extra key called `Extra(:mu)`, then this would be ambiguous, and FlexiChains would throw an error.

!!! note "No sub-varnames"

    You cannot use `chain[Symbol("theta[1]")]` as a replacement for `chain[@varname(theta[1])]`.

Likewise, we can omit wrapping `:logjoint` in `Extra(...)`:

```@example 1
chain[:logjoint] # other key
```

### Prefix-agnostic indexing

If you want to access a variable that has been prefixed (e.g. because it is part of a submodel) but you don't want to specify the full prefix, you can use [`FlexiChains.Prefixed`](@ref):

```julia
using Turing
using FlexiChains: Prefixed, VNChain

@model inner() = x ~ MvNormal(zeros(2), I)

@model function outer()
    a ~ to_submodel(inner())
    return nothing
end

pfx_chain = sample(outer(), Prior(), 5)
```

```@example pfx
using FlexiChains: FlexiChains, Prefixed, VNChain # hide
using DynamicPPL: @model, @varname, to_submodel # hide
using Distributions, LinearAlgebra # hide
@model inner() = x ~ MvNormal(zeros(2), I) # hide
@model function outer() # hide
    a ~ to_submodel(inner()) # hide
    return nothing # hide
end # hide
pfx_chain = FlexiChains._make_prior_chain(outer(), 5, 1) # hide

# Inside the chain, the actual key is `@varname(a.x)`;
# this will pick out that key.
pfx_chain[Prefixed(@varname(x))]
```

Sub-VarNames are also supported:

```@example pfx
pfx_chain[Prefixed(@varname(x[1]))]
```

## Summary statistics

### Overall summaries

For a very quick summary of the chain, you can use `StatsBase.summarystats` (which FlexiChains reexports):

```@example 1
using FlexiChains: summarystats

summarystats(chain)
```

!!! note

    The large number of NaN's and Inf's here are just because of the very short chain length. On a real chain you would get proper statistics.

To index into this, you can use a similar syntax as for `FlexiChain`s:

```@example 1
ss = summarystats(chain)
ss[@varname(mu)]
```

or to access an individual statistic

```@example 1
ss[@varname(mu), stat=:mean]
```

Alternatively, you can directly convert the `FlexiSummary` into an array and manipulate it as you would any other array.
(Note that `Array(ss)` also works, but you lose the dimension information in that case.)

```@example 1
DimArray(ss)
```

By default, `summarystats` will split `VarName`s up.
This is done because summary statistics often only make sense for scalar-valued parameters.
If you want to avoid this, you can set `split_varnames=false`:

```@example 1
summarystats(chain; split_varnames=false)
```

Notice how many of the statistics for `theta` are now `missing`.
This is because statistics like the quantiles cannot be meaningfully calculated for vector-valued parameters.

### Individual summaries

You can obtain, for example, the mean of each key in the chain using `Statistics.mean`.
This returns a `FlexiSummary` object:

```@example 1
using Statistics: mean

mn = mean(chain)
```

You can index into a `FlexiSummary` in exactly the same ways as a `FlexiChain`.

```@example 1
mn[@varname(mu)]
```

Out of the box, FlexiChains provides many commonly used summary functions, such as `Statistics.mean` and `Statistics.std` (a full list is given in [the Summarising page](./summarising.md)).
These functions can all be applied to a `FlexiChain` with their usual signatures (for example, `Statistics.quantile` will require a second argument).
Keyword arguments of the original functions are also supported, for example `MCMCDiagnosticTools.ess(chain; kind=:tail)` returns the tail ESS.

!!! note "Other summary functions"

    If you want to apply a summary function that isn't listed above, you can manually use [`FlexiChains.collapse`](@ref). If it is something that is worth appearing in FlexiChains proper, please do open an issue!

### Collapsed dimensions

By default, applying summary functions will collapse the data in both the iteration and chain dimensions (the latter is only relevant if multiple chains are present).

To only collapse over one dimension you can use

```@example 1
mean(chain; dims=:iter)[@varname(mu)]
```

or `dims=:chain` (although that is probably less useful).

## Saving and resuming MCMC sampling progress

If you want to sample a fewer number of iterations first and then resume it later, you can use the following:

```julia
chn1 = sample(model, NUTS(), 10; save_state=true)
chn2 = sample(model, NUTS(), 10; initial_state=only(FlexiChains.last_sampler_state(chn1)))
```

The chains can be combined using `vcat`:

```julia
combined_chn = vcat(chn1, chn2)
```

!!! note "The `initial_state` argument"

    When performing **single-chain sampling** with `sample(model, spl, N; initial_state=state)`, `initial_state` should be either `nothing` (to start a new chain) or the state to resume from.
    For **multiple-chain sampling** with `sample(model, spl, MCMCThreads(), N, C)`, `initial_state` should be a vector of length `C`, where `initial_state[i]` is the state to resume the `i`-th chain from (or `nothing` to start a new chain).

    To obtain the saved final state of a chain, you can use [`FlexiChains.last_sampler_state`](@ref).
    This always returns a vector of states with length equal to the number of chains.
    Note that this applies also if you only sampled a single chain, in which case the returned value is a vector of length 1: you will therefore have to use `only()` to extract the state itself.

    The above applies equally to `MCMCSerial()` and `MCMCDistributed()`.

## Initialising MCMC sampling from a FlexiChain

You can also use the parameters stored in a `FlexiChain` to initialise MCMC sampling.
Note that this is different from _resuming sampling_ from a saved sampler state, because all other sampler information (e.g. momentum, ...) will be re-initialised.

For example, to start a new chain from the fifth iteration and first chain contained inside `chain`, you can do

```julia
chn3 = sample(model, MH(), 5; initial_params=InitFromParams(chain, 5, 1))
```

Since this only uses the parameters which are already part of the chain, this does not require you to use `save_state=true` for the original chain.

## Posterior predictions and friends

The functions `predict`, `returned`, `logjoint`, `loglikelihood`, and `logprior` all work 'as expected' using FlexiChains with exactly the same signatures that you are used to.

```@example 1
returned(model, chain)
```

`pointwise_logdensities`, `pointwise_loglikelihoods`, and `pointwise_prior_logdensities` are also supported, and will return a new FlexiChain containing the log-probabilities for each variable.

LOO-CV is also supported if you load PosteriorStats.jl: see the [PosteriorStats.jl integration](@ref integrations-posteriorstats) for more details.

## Plotting

FlexiChains contains a few recipes for plotting with Plots.jl and Makie.jl; please see the [plotting pages](./plotting.md) for more details.
Here we demonstrate usage with Plots.jl.

When plotting a `VNChain`, array-valued parameters will automatically be split up into their individual components.
In this example we plot only `tau` and `theta[1]` to save space, but if you were to plot `theta`, you would get eight separate plots for each element of `theta`.

```@example 1
using StatsPlots

# Or omit the second argument to plot all parameters.
plot(chain, [@varname(tau), @varname(theta[1])])
savefig("plot_ex.svg");
nothing # hide
```

![Trace and density plots for mu, tau, and theta1](plot_ex.svg)
