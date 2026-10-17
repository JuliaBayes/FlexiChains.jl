# [PosteriorStats.jl](@id integrations-posteriorstats)

[Documentation for PosteriorStats.jl ↗](@extref PosteriorStats :doc:`index`)

## Interval estimation

PosteriorStats.jl provides the `hdi` and `eti` functions for computing highest density
intervals and equal-tailed intervals, respectively.
These are overloaded for `FlexiChain` objects in much the same way as `Statistics.mean`, `Statistics.std`, etc. (see [the Summarising page](@ref "Individual statistics") for more information on those).
Here is an example:

```@example posteriorstats
using FlexiChains, DynamicPPL, Distributions, PosteriorStats

@model function g(z)
    x ~ Normal()
    y ~ Normal(x)
    z ~ Normal(y)
end
model = g(1.0)

chn = FlexiChains._make_prior_chain(model, 100, 2)
PosteriorStats.hdi(chn; prob=0.95)
```

By default, each interval is split into its lower and upper bounds, which are stored as separate statistics (`hdi_lower` and `hdi_upper`, or `eti_lower` and `eti_upper`).
If you would rather have a single statistic containing `IntervalSets.ClosedInterval`s, pass `split_interval=false`:

```@example posteriorstats
PosteriorStats.hdi(chn; prob=0.95, split_interval=false)
```

## LOO-CV

`PosteriorStats.loo`, which computes Pareto-smoothed importance sampling leave-one-out cross-validation (PSIS-LOO), is also overloaded for `FlexiChain` objects.

This is most easily used in conjunction with Turing.jl, since you can use Turing's functionality to directly compute log-likelihood values.

As an example, let's use our favourite eight-schools model.

```@example loocv
using FlexiChains, DynamicPPL, Distributions, PosteriorStats, LinearAlgebra

y = [28, 8, -3, 7, -1, 1, 18, 12]
sigma = [15, 10, 16, 11, 9, 11, 10, 18]
@model function eight_schools(y, sigma)
    mu ~ Normal(0, 5)
    tau ~ truncated(Cauchy(0, 5); lower=0)
    theta ~ MvNormal(fill(mu, length(y)), tau^2 * I)
    y ~ MvNormal(theta, Diagonal(sigma .^ 2))
    return nothing
end
model = eight_schools(y, sigma)

chn = FlexiChains._make_posterior_chain(model, 500, 4)
```

(Instead of sampling with Turing, we use an internal function to draw samples from the posterior, in order to avoid incurring a docs dependency on Turing.)

Now, `chn` is a chain which contains posterior samples.
You can directly get a LOO-CV result by calling:

```@example loocv
PosteriorStats.loo(model, chn; factorize=true)
```

However, it's worth taking the scenic route to understand what's going on.
To go from posterior samples to a LOO-CV result, we need to compute the pointwise log-likelihood for each observation.

To obtain a chain of log-likelihood values, we can use `DynamicPPL.pointwise_loglikelihoods`.
Note that, because we wrote `y ~ MvNormal(...)`, if we simply called `pointwise_likelihoods` we would obtain a *single* log-likelihood for the entire vector `y`.
Notice the `Float64` type here:

```@example loocv
DynamicPPL.pointwise_loglikelihoods(model, chn)
```

To get the log-likelihood for each individual `y[i]`, we can pass the `factorize=true` keyword argument, which uses [`PartitionedDistributions.jl`](https://sethaxen.github.io/PartitionedDistributions.jl/stable/) to calculate the conditional log-likelihood for each observation.
This gives us a `Vector{Float64}` instead:

```@example loocv
loglik_chn = DynamicPPL.pointwise_loglikelihoods(model, chn; factorize=true)
```

This chain has the same structure as `chn`, but instead of containing posterior samples, it contains log-likelihood values for each observation in `y`.

```@example loocv
loglik_chn[@varname(y), iter=1:5, chain=1]
```

Then you can pass this to `PosteriorStats.loo` directly, without the model:

```@example loocv
PosteriorStats.loo(loglik_chn)
```

This returns a struct `n::NamesAndLOOResult`, where `n.param_names` contains the `VarName`s corresponding to each observation, and `n.loo` contains the actual [`PosteriorStats.PSISLOOResult`](@extref PosteriorStats).

## Docstrings

```@docs
PosteriorStats.hdi(::FlexiChains.FlexiChain; kwargs...)
PosteriorStats.eti(::FlexiChains.FlexiChain; kwargs...)
PosteriorStats.loo(::FlexiChains.FlexiChain; kwargs...)
PosteriorStats.loo(model::DynamicPPL.Model, posterior_chn::FlexiChains.FlexiChain; kwargs...)
```
