# [Summarising](@id summarising)

In general a `FlexiChain` contains data in matrices of size `(niters, nchains)`.
Often it is useful to summarise this data along one or both dimensions.

FlexiChains therefore allows you to calculate one or more statistics for each variable stored in a `FlexiChain`.
The result is a `FlexiSummary` object, which can be indexed into in a very similar way to `FlexiChain`s: see [the Indexing page](@ref indexing) for full details, or the examples on this page.

## Unsupported data types

Before we launch into the available summary statistics, it is worth mentioning one point about data types.
Since FlexiChains allows for storage of completely arbitrary data types, it can contain data for which the mean (or other statistic) is not defined.
For example, the mean of `String` values is not defined.
Thus, when calculating `mean(chain)`, any `String`-valued parameters will be dropped from the result.

If multiple summary statistics are requested (e.g. with [`summarystats`](@ref StatsBase.summarystats)), the key is only dropped if _all_ of them fail.
If at least one statistic is successfully computed for a key, that key will be included in the result, with `missing` values for the statistics that failed.

This behaviour should be more or less intuitive, so we will not delve into it further here, except to note that FlexiChains will warn you when a key is dropped, so that you are aware of it.

## Overall summary statistics

If you want a quick overview of what your chain contains, [`summarystats`](@ref StatsBase.summarystats) provides a handy selection of commonly used statistics:

```@docs
StatsBase.summarystats(::FlexiChains.FlexiChain)
```

```@example stats
using FlexiChains

chain = FlexiChains.EXAMPLE_CHAIN
summary = summarystats(chain)
```

Recall that you can index into a chain using a parameter name, e.g. `chain[@vn(mu)]` to get a matrix of values for the first element of `theta`.

With a `FlexiSummary`, you can use parameter names in the same way:

```@example stats
summary[@vn(mu)]  # All of mu's stats.
```

You can add the `stat` dimension to extract a specific statistic:

```@example stats
summary[@vn(mu), stat=:mean]  # Mean of mu.
```

!!! note "Named statistic shorthand"

    Passing a `Symbol` to `stat` is shorthand for a named lookup: `stat=:mean` is equivalent to `stat=At(:mean)`.
    Other selectors follow DimensionalData.jl's usual behaviour; for example, `stat=1` selects the first statistic by position.

For more details on indexing, please see the [Indexing page](@ref indexing).

### Splitting of variables

Notice that in the `FlexiSummary`, the vector-valued parameter `theta` has been broken up into its individual elements `theta[1]` through `theta[8]`.
We can also see this by looking at the keys of the summary:

```@example stats
keys(summary)
```

This is done mainly for convenience.
Many statistic functions are not well-defined for array-valued parameters, or other more complicated structures.
You can disable this behaviour by passing `split_varnames=false`:

```@example stats
summarystats(chain; split_varnames=false)
```

Now, the summary statistics are calculated with each vector `v` being a single entity.
The key `v` is still present in the result (since `mean` and `std` could be computed for it).
However, notice that other statistics such as `ess` are no longer defined, and so return `missing` values.

Don't forget that if you want to do a more involved analysis, e.g. calculating correlations between different elements of a vector-valued parameter, you can always index into the original `FlexiChain`.

## Individual statistics

Sometimes you may only want to calculate a single statistic.

The following functions are all overloaded to accept `FlexiChain` objects.
In most cases, they can be called with `dims=:both`, `dims=:iter`, or `dims=:chain` to specify the dimension over which to compute the statistic; the default is `dims=:both`.
There are some exceptions to this, such as the MCMC diagnostics `ess`, `rhat`, and `mcse`, which do not support `dims=:chain` (since computing them across chains at a single iteration is not meaningful).

All of these functions return a `FlexiSummary` where the `:stat` dimension has already been collapsed.
That means that if you want to access the mean of a variable `@vn(a)` you don't need to further use the `stat` dimension:

```@example stats
mn = mean(chain)

# Not needed: mean_mu = m[@vn(mu), stat=:mean]
# Just do:
mean_mu = mn[@vn(mu)]
```

In fact, behind the scenes, the actual name of the statistic is retained.
This means that, for example, if you convert the result to a `DataFrame`, the column will still be named `mean`:

```@example stats
using DataFrames;
DataFrame(mn)
```

```@docs
Statistics.mean(::FlexiChains.FlexiChain; kwargs...)
Statistics.median(::FlexiChains.FlexiChain; kwargs...)
Statistics.std(::FlexiChains.FlexiChain; kwargs...)
Statistics.var(::FlexiChains.FlexiChain; kwargs...)
Statistics.quantile(::FlexiChains.FlexiChain, p; kwargs...)
Base.minimum(::FlexiChains.FlexiChain; kwargs...)
Base.maximum(::FlexiChains.FlexiChain; kwargs...)
Base.sum(::FlexiChains.FlexiChain; kwargs...)
Base.prod(::FlexiChains.FlexiChain; kwargs...)
MCMCDiagnosticTools.ess(::FlexiChains.FlexiChain; kwargs...)
MCMCDiagnosticTools.rhat(::FlexiChains.FlexiChain; kwargs...)
MCMCDiagnosticTools.mcse(::FlexiChains.FlexiChain; kwargs...)
StatsBase.mad(::FlexiChains.FlexiChain; kwargs...)
StatsBase.geomean(::FlexiChains.FlexiChain; kwargs...)
StatsBase.harmmean(::FlexiChains.FlexiChain; kwargs...)
StatsBase.iqr(::FlexiChains.FlexiChain; kwargs...)
StatsBase.autocor(::FlexiChains.FlexiChain; kwargs...)
Statistics.cor(::FlexiChains.FlexiChain; kwargs...)
FlexiChains.changerate(::FlexiChains.FlexiChain; kwargs...)
```

### Density intervals

It is worth just noting briefly here that FlexiChains has a PosteriorStats extension which allows you to calculate highest density intervals and equal-tailed intervals.
Please see the [PosteriorStats integration section](@ref integrations-posteriorstats) for details.

## Custom statistics

There are two scenarios where the above are not enough:

 1. you want to calculate a specific set of statistics that is not the same as what `summarystats` does; or
 2. you want to calculate a completely custom statistic, which is not implemented above.

In both cases, you can directly use [`FlexiChains.collapse`] to achieve this.
(But in the latter case, please do also consider opening an issue so that we can implement it!)

```@docs
FlexiChains.collapse
```

Instead of just passing the functions you want to use, such as `mean`, `std`, and so on, `FlexiChains.collapse` must be passed a series of `FlexiChains.CollapseFunction`s.
This is a wrapper type which allows you to precisely specify how the values should be collapsed over iterations, chains, or both.

```@docs
FlexiChains.CollapseFunction
```

For many cases, you can construct a `CollapseFunction` using the following shortcuts:

```@docs
FlexiChains.CollapseFunctionVec
FlexiChains.CollapseFunctionDiagnostic
```

As an example, suppose you have a statistic that calculates the sum of the mean and standard deviation.
(This is of course quite contrived: if you have a _real_ example, again, please do open an issue!)

We start by defining our own function:

```@example stats
using Statistics

function mean_std_sum(x::AbstractVector{<:Real})
    return mean(x) + std(x)
end
```

This function maps a vector to a single value, so we can use [`FlexiChains.CollapseFunctionVec`](@ref) to turn it into a `CollapseFunction`.
When collapsing over both dimensions, it will be applied to all the samples for a variable stacked together into a single vector; when collapsing over only one dimension, it will be applied to each chain (`dims=:iter`) or each iteration (`dims=:chain`) separately.

Now we can use `collapse` to apply this function to all variables in the chain.
The second argument is a vector, which in this case will only contain our one statistic:

```@example stats
custom_stat =
    FlexiChains.collapse(chain, [FlexiChains.CollapseFunctionVec(mean_std_sum)]; dims=:both)
```

There are two things worth mentioning, which we will note in passing here without demonstrating (since they are also covered in the docstring):

 1. If there is only one function provided, you can additionally pass `drop_stat_dim=true` to remove the `:stat` dimension from the result, much like what `mean(chain)` does for you.

 2. The name of the statistic is inferred from the underlying function.
    Sometimes this doesn't work out nicely, for example if you pass an anonymous function.
    In this case you can pass the name as the first argument, e.g. `FlexiChains.CollapseFunctionVec(:name, f)`.

## Merging summaries

As an alternative to using `collapse`, you can also calculate separate summaries and then merge them.

```@example stats
mn = mean(chain)
sd = std(chain)

merge(mn, sd)
```

```@docs
Base.merge(::FlexiChains.FlexiSummary, ::FlexiChains.FlexiSummary)
```

## [MCMC diagnostics](@id mcmc-diagnostics)

There are a number of functions in MCMCDiagnosticTools.jl which do not nicely fit the notion of 'collapse over one or more dimensions'.
For example, quantities like the Gelman diagnostic are calculated over the entire dataset.

For these functions, you can simply pass a FlexiChain to them.
For example:

```@example stats
gelmandiag(chain)
```

The available functions are as follows (and FlexiChains reexports all of these too, for convenience).

```@docs
MCMCDiagnosticTools.gelmandiag
MCMCDiagnosticTools.gelmandiag_multivariate
MCMCDiagnosticTools.discretediag
MCMCDiagnosticTools.bfmi
MCMCDiagnosticTools.rstar
```

## Flattening summaries

Finally, `FlexiSummary` objects can be converted to `DimArray`s or `DataFrame`s, just like `FlexiChain`s.
This is useful for various analyses and visualisations.

```@example stats
st = summarystats(chain)
DimArray(st)
```

```@example stats
using DataFrames

DataFrame(st)
```
