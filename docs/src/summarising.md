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

To give a flavour of how this works, here is an example of a model that generates parameters of different types:

```@example stats
using FlexiChains, DynamicPPL, Distributions, LinearAlgebra

@model function f()
    f ~ Normal()               # float
    v ~ MvNormal(zeros(2), I)  # vector
    s := "a string"            # string
end

chain = FlexiChains._make_prior_chain(f(), 20, 3)
```

Over the course of this page we will see what happens to each of these parameters when we try to compute summary statistics.

## Overall summary statistics

If you want a quick overview of what's in your chain, [`summarystats`](@ref StatsBase.summarystats) provides a handy selection of commonly used statistics:

```@docs
StatsBase.summarystats(::FlexiChains.FlexiChain)
```

```@example stats
st = summarystats(chain)
```

Notice that the string-valued parameter `s` has been dropped from the result, since no statistics could be computed for it.
(If you run this in the terminal, you will see a warning about this, so it is not completely silent; it's just not shown in the docs.)

You can index with a variable name (or names!) and the `stat` dimension:

```@example stats
st[@varname(v[1]), stat=:mean]  # Mean of first element of vector v
```

!!! note "Named statistic shorthand"

    Passing a `Symbol` to `stat` is shorthand for a named lookup: `stat=:mean` is
    equivalent to `stat=At(:mean)`. Other selectors follow DimensionalData.jl's usual
    behaviour; for example, `stat=1` selects the first statistic by position.

For more details on indexing, please see the [Indexing page](@ref indexing).

In the result above, the vector-valued `v` has been broken up into its individual elements `v[1]` and `v[2]`.
This happens automatically for chains with `VarName` keys; you can disable this behaviour by passing `split_varnames=false`:

```@example stats
st2 = summarystats(chain; split_varnames=false)
```

Now, the summary statistics are calculated with each vector `v` being a single entity.
The key `v` is still present in the result (since `mean` and `std` could be computed for it).
However, notice that other statistics such as `ess` are no longer defined, and so return `missing` values.
Just like before, the string `s` is dropped since no statistics could be computed for it.

## Individual statistics

Sometimes you may only want to calculate a single statistic.

The following functions are all overloaded to accept `FlexiChain` objects.
In all cases, they can be called with `dims=:both`, `dims=:iter`, or `dims=:chain` to specify the dimension over which to compute the statistic; the default is `dims=:both`.

All of these functions return a `FlexiSummary` where the `:stat` dimension has already been collapsed.
That means that if you want to access the mean of a variable `@varname(a)` you don't need to further use the `stat` dimension:

```@example stats
mn = mean(chain)
# Not needed: mean_f = m[@varname(f), stat=:mean]
# Just do:
mean_f = mn[@varname(f)]
```

In fact, behind the scenes, the actual name of the statistic is retained.
This means that, for example, if you convert the result to a `DataFrame`, the column will be named `mean` rather than `stat`:

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
```

There are also similar overloads for `PosteriorStats.hdi` and `PosteriorStats.eti`, which calculate highest density intervals and equal-tailed intervals, respectively.
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

As an example, suppose you have a statistic that calculates the sum of the mean and standard deviation.
(This is of course quite contrived: if you have a _real_ example, again, please do open an issue!)

We start by defining our own function:

```@example stats
using Statistics

function mean_std_sum(x::AbstractVector{<:Real})
    return mean(x) + std(x)
end
```

As noted in the docstring of [`FlexiChains.collapse`](@ref), the function you provide must accept a vector argument and return a single value.
Of course, it can also have other methods, but this is the one which `collapse` uses.

Now we can use `collapse` to apply this function to all variables in the chain.
The second argument is a vector, which in this case will only contain our one function:

```@example stats
custom_stat = FlexiChains.collapse(chain, [mean_std_sum]; dims=:both)
```

There are two things worth mentioning, which we will note in passing here without demonstrating (since they are also covered in the docstring):

 1. If there is only one function provided, you can additionally pass `drop_stat_dim=true` to remove the `:stat` dimension from the result, much like what `mean(chain)` et al. do.

 2. The name of the statistic is inferred from the function. Sometimes this doesn't work out nicely, for example if you pass an anonymous function. In this case you can provide a tuple of `(:name, function)` instead of just the function.

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

## Density intervals

It is worth just noting briefly here that FlexiChains has a PosteriorStats extension which allows you to calculate highest density intervals and equal-tailed intervals.
Please see the [PosteriorStats integration section](@ref integrations-posteriorstats) for details.

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
