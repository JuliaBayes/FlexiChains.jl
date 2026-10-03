# [Migrating from MCMCChains](@id migration)

This page contains a few examples of how to adapt code written for MCMCChains to work with FlexiChains instead.
These are collated from my experience updating Turing's docs and tests.

If you have any other questions or usage patterns, *please do open an issue*!
I will be more than happy to add more examples here.

## Setup

For the purposes of these docs, we will have to write a function, `prior_chains`, that creates a chain without using Turing explicitly.
This is because Turing depends on FlexiChains, and if we make a breaking release of FlexiChains, then the docs will break as there will not yet be a version of Turing that is compatible.

The code is shown here for demonstration purposes, but don't worry about the implementation of this too much!
It is really the same as calling `sample(model, Prior(), MCMCSerial(), n_iters, n_chains; chain_type=Tchn)`.

!!! details "Prior chain sampling"

    ```@example migration
    using DynamicPPL, AbstractMCMC, MCMCChains, FlexiChains, Random, Distributions
    
    function prior_chains(
        rng::Random.AbstractRNG,
        model::DynamicPPL.Model,
        niters::Int,
        nchains::Int,
    ) where {Tchn}
        vi = DynamicPPL.OnlyAccsVarInfo()
        vi = DynamicPPL.setacc!!(vi, DynamicPPL.RawValueAccumulator(true))
        ps = [
            DynamicPPL.ParamsWithStats(
                last(DynamicPPL.init!!(rng, model, vi, InitFromPrior(), UnlinkAll())),
            ) for _ in 1:niters, _ in 1:nchains
        ]
    
        mcmcchain = AbstractMCMC.from_samples(MCMCChains.Chains, ps)
        flexichain = AbstractMCMC.from_samples(FlexiChains.FlexiChain{DynamicPPL.VarName}, ps)
        return mcmcchain, flexichain
    end
    ```

## A1. Extracting scalar-valued samples

```@example migration
@model f() = x ~ Normal()
model = f()
mchain, fchain = prior_chains(Xoshiro(468), model, 5, 2)
nothing # hide
```

### MCMCChains

```@example migration
mchain[:x]
```

gives you an `niters × nchains` `AxisArray` of samples for the variable `x`.

### FlexiChains

It is recommended to index into the chain using `VarName`s because this is clearer:

```@example migration
fchain[@varname(x)]
```

This will also give you an `niters × nchains` matrix of samples but it is a `DimArray` instead.

You can also use `fchain[:x]` as long as the Symbol can be [unambiguously resolved to a key in the chain](@ref symbol-indexing).

## A2. Extracting an element of an array-valued sample

```@example migration
@model g() = x ~ filldist(Normal(), 2, 3)
model = g()
mchain, fchain = prior_chains(Xoshiro(468), model, 5, 2)
nothing # hide
```

### MCMCChains

With MCMCChains, the array `x` will have been split up into its scalar elements.
You can access, for example:

```@example migration
mchain[Symbol("x[1, 2]")]
```

which again gives you an `niters × nchains` `AxisArray` of samples for the variable `x[1, 2]`.

### FlexiChains

With FlexiChains, the array `x` will be kept together as a single variable.
There is no *single* variable in the chain that corresponds to `x[1, 2]`.
However, you can still access the element `x[1, 2]` using `VarName`s.

```@example migration
fchain[@varname(x[1, 2])]
```

(In fact you can also [use other indexing patterns](@ref why), such as `fchain[@varname(x[end])]` to get the last element of `x`.)

## A3. Extracting array-valued samples

Consider the same model as above, but suppose we want the entire array of `x` values.

```julia
@model g() = x ~ filldist(Normal(), 2, 3)
```

### MCMCChains

With MCMCChains, you have to use the `group` function to subset the chain to variables that begin with `x`:

```@example migration
mchain_xonly = group(mchain, :x)
```

This gives you a `Chains` object, whose internal data has dimensions `niters × nparams × nchains`.
Here, `nparams` is the number of scalar parameters that begin with `x` (in this case, 6).
The internal data can be accessed by converting the `Chains` object to an array.

To get, for example, the first sample of `x`, you can then do:

```@example migration
x_vec = Array(mchain_xonly[1, :, 1])
x = reshape(x_vec, 2, 3)
```

If you want to get (for example) the mean of `x`, or an array of all `x` values, you will similarly need some combination of `group` + `reshape` or `permutedims`.

### FlexiChains

With FlexiChains, you can directly access the entire array of `x` values using `VarName`s.

For example,

```@example migration
fchain[@varname(x)]
```

returns a `DimArray` of dimensions `niters × nchains` where each element is a `2 × 3` array of samples for `x`.

To get the first sample of `x` you can either index into the `DimMatrix` above (i.e., `fchain[@varname(x)][1, 1]`), _or_ you can directly index with

```@example migration
fchain[@varname(x), iter=1, chain=1]
```

If you need to process all `x` samples at once, you can also use

```@example migration
fchain[@varname(x), stack=true]
```

to get a `DimArray` of dimensions `niters × nchains × 2 × 3`, where the last two dimensions correspond to the dimensions of `x`.

## A4. Subsetting a chain to specific parameters, iterations, or chains

```@example migration
@model function h()
    x ~ Normal()
    y ~ Normal()
    z ~ Normal()
end
model = h()
mchain, fchain = prior_chains(Xoshiro(468), model, 5, 2)
nothing # hide
```

### MCMCChains

MCMCChains allows you to subset a chain simply by indexing into it as if it were a 3D array of dimensions `niters × nparams × nchains`.

This means that if you want to drop the first 2 iterations, and only retain the parameters `x` and `y`, you can for example do:

```@example migration
mchain_subset = mchain[3:end, [:x, :y], :]
```

### FlexiChains

With FlexiChains, _parameter subsetting_ is done with a positional argument, but _iteration and chain subsetting_ are done with keyword arguments.

Unfortunately, Julia does not (yet?) support `begin` and `end` in keyword arguments, so you will have to explicitly calculate what `end` should be.

```@example migration
n_iters = FlexiChains.niters(fchain)  # or equivalently size(fchain, 1)
fchain_subset = fchain[[@varname(x), @varname(y)], iter=3:n_iters]
```

## A5. Subsetting the chain to parameters only

With MCMCChains you need to know that the parameters are stored in a section called `:parameters`, and extract that section specifically.
(In general, a chain can have any section with any name, but Turing makes sure to create `:parameters` and `:internals` sections.)

```@example migration
MCMCChains.get_sections(mchain, :parameters)
```

FlexiChains has a strict notion of parameters and other keys, so there is a dedicated function for this:

```@example migration
FlexiChains.subset_parameters(fchain)
```

## B1. Extracting summary statistics

MCMCChains has a few functions which notionally can do the same thing:

```@example migration
summarystats(mchain)     # calculate summary stats

# Also:
# summarize(mchain)      # same as summarystats for the most part
# describe(mchain)       # prints them but returns nothing
```

FlexiChains only uses `StatsBase.summarystats`:

```@example migration
summarystats(fchain)
```

Both MCMCChains and FlexiChains accept keyword arguments which give you more control over which statistics are calculated.
For FlexiChains please see [the summarising docs](@ref summarising) for more info.

## B2. Extracting the mean of a scalar-valued variable

This applies to any statistic, not just the mean.

```@example migration
using LinearAlgebra
@model function k()
    x ~ Normal()
    y ~ MvNormal(zeros(2), I)
end
model = k()
mchain, fchain = prior_chains(Xoshiro(468), model, 5, 2)
nothing # hide
```

### MCMCChains

```@example migration
mmean = mean(mchain)
```

This returns a `ChainDataFrame` object, which is slightly confusing to work with (and isn't really documented at all).
To actually access the mean value, you have to do

```@example migration
mmean[:x, :mean]
```

There is a more direct way of getting the mean of a specific variable, which is to pass that as a second argument to `mean`:

```@example migration
mean(mchain, :x)
```

### FlexiChains

There are two ways to get the mean of `x` with FlexiChains, which are essentially equivalent.

The first way is to the mean of the entire chain and index into it.

```@example migration
fmean = mean(fchain)
```

This returns a `FlexiSummary` object, which can be indexed into with a `VarName`:

```@example migration
fmean[@varname(x)]
```

Or, perhaps more efficiently since this avoids calculating the mean of all other variables, you can index into the chain first to extract the variable `x` and then take the mean of that:

```@example migration
fmean_x = mean(fchain[@varname(x)])
```

## B3. Mean of an array-valued variable

### MCMCChains

In the example above we had `y ~ MvNormal(zeros(2), I)`, so `y` is a 2-dimensional array-valued variable.
With MCMCChains, you have to first subset the chain to variables that begin with `y` using `group`, and then calculate the mean:

```@example migration
mchain_yonly = group(mchain, :y)
mmean_yonly = mean(mchain_yonly)
```

With this `ChainDataFrame` object in hand, you can index into it:

```@example migration
mmean_yonly[:, :mean]
```

### FlexiChains

The same description applies to `y` as to `x` in the previous section, except that now `y` is an array-valued variable.

```@example migration
# Make sure to avoid splitting `y` up.
fmean = mean(fchain; split_varnames=false)
fmean[@varname(y)]
```

Alternatively, recall that `fchain[@varname(y)]` returns a `DimArray` of vectors, so you can take the mean of that directly:

```@example migration
fmean_y = mean(fchain[@varname(y)])
```

## B4. Accessing the mean of all parameters

Suppose you just wanted `mean(x), mean(y[1]), mean(y[2])` all at once as a single vector.

### MCMCChains

With MCMCChains you can do this in several ways.
One way is to first subset the chain to parameters only (see the next section), convert that to an array, and then take the mean across the iteration and chain dimensions.
(Recall that with MCMCChains, the array layout is `niters × nparams × nchains`.)

```@example migration
mchain_params = MCMCChains.get_sections(mchain, :parameters)
mchain_params_array = Array(mchain_params)
mmean_params = mean(mchain_params_array, dims=(1, 3))
```

### FlexiChains

With FlexiChains, the easiest way is to take the mean of the chain, and then convert _that_ `FlexiSummary` object to an array.
The array conversion retains only parameters by default, but this can be changed with the `parameters_only` keyword argument (see [the docstring](@ref api-flatten) for more info).

```@example migration
fmean = mean(fchain)
DimArray(fmean)  # or `Array(fmean)` if you don't need dimensions
```

## B5. Taking the per-chain means

### MCMCChains

```@example migration
mean(mchain, append_chains=false)
```

This returns a vector of `ChainDataFrame`s, one per chain, which can be worked with as described above.

### FlexiChains

The syntax in FlexiChains is closer to that in base Julia, where you specify the dimensions you _do_ want to reduce over:

```@example migration
mean(fchain; dims=:iter)
```

If you want a flattened array you can likewise convert this to a `DimArray`, which will have dimensions `chains × parameters`:

```@example migration
DimArray(mean(fchain; dims=:iter))
```

## C1. Listing all parameters

```@example migration
MCMCChains.names(mchain, :parameters)
```

Similar to the above, FlexiChains has a dedicated function for this:

```@example migration
FlexiChains.parameters(fchain)
```

## C2. Listing all _keys_ (not just parameters)

```@example migration
MCMCChains.names(mchain)
```

A FlexiChain is really a dictionary mapping keys to matrices, so you can just use `Base.keys`:

```@example migration
collect(keys(fchain))
```

## C3. Getting the number of samples

```@example migration
size(mchain)  # niters × nparams × nchains
```

```@example migration
size(fchain)  # niters × nchains
```

For FlexiChains, since the parameters do not form an array dimension, it is not exposed as part of the 'size': however, if you want to get the number of parameters, you can do `length(FlexiChains.parameters(fchain))`, or `length(keys(fchain))` if you want to count all keys, not just parameters.

## D1. `get` and `get_params`

`MCMCChains.get` and `MCMCChains.get_params` allow you to extract a NamedTuple mapping parameter names to their samples.
This is needed because MCMCChains stores samples as a 3D array.

For example:

```@example migration
p = MCMCChains.get_params(mchain)
p.x     # all samples for x
```

With FlexiChains these functions are no longer needed since indexing into the chain with `VarName`s already gives you the samples in the correct format.

```@example migration
fchain[@varname(x)]
```

## E1. `DynamicPPL.predict`

By default FlexiChains returns a new chain that includes both the new predicted variables, as well as the original variables from the input chain.
To disable this use `predict(...; include_all=false)`.

MCMCChains's default is `include_all=false`, so if you _do_ want FlexiChains's behaviour, you can likewise just pass `include_all=true` to it.

## E2. Final sampler states

!!! note

    The code examples here are not run since they require Turing.

When sampling a **single** chain with Turing + MCMCChains, if you specify `save_state=true`, the final sampler state will be bundled inside the chain.
Importantly, this is stored as a single sampler state object.
This means that if you want to resume sampling from this state, you can do something like

```julia
last_state = Turing.loadstate(mchain)
resume_chain = sample(model, sampler, N; initial_state=last_state)
```

With FlexiChains, note that the final sampler state is always stored as a *vector* of sampler states, one per chain.

That means you need to extract the first (or whichever) sampler state from this vector before passing it to `sample`:

```julia
last_states = Turing.loadstate(fchain)
resume_chain = sample(model, sampler, N; initial_state=last_states[1])
```

If you instead sample **multiple** chains and save its state, the saved state will always be a vector of sampler states, even with MCMCChains.

## F1. Plotting

Please see the [plotting docs](@ref plotting) for information on what plotting functionality is available in FlexiChains.

```@example migration
@model function q()
    x ~ Normal()
    y ~ MvNormal(zeros(2), I)
    z ~ Normal()
end
model = q()
mchain, fchain = prior_chains(Xoshiro(468), model, 5, 2)
nothing # hide
```

Plotting functions in FlexiChains all allow you to pass a collection of parameters as a second, optional argument.
Thus, for example, if you wanted to plot only `y`, then you could do:

```@example migration
using StatsPlots
plot(fchain, [@varname(y)])
savefig("fchainplot.svg");
nothing # hide
```

![FlexiChains plots](fchainplot.svg)

With MCMCChains you would probably be best off subsetting the chain to variables that begin with `y` first, and then plotting that:

```@example migration
mchain_yonly = group(mchain, :y)
plot(mchain_yonly)
savefig("mchainplot.svg");
nothing # hide
```

![MCMCChains plots](mchainplot.svg)
